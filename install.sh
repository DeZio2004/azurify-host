#!/usr/bin/env bash
# AZURIFY Host - one-VPS installer (panel + database + node/wings + SSL)
# Usage (as root, fresh Ubuntu 22.04/24.04 or Debian 12):
#   bash <(curl -Ls https://raw.githubusercontent.com/DeZio2004/azurify-host/main/install.sh)
set -euo pipefail
trap 'echo -e "\033[1;31mFAILED at line $LINENO:\033[0m $BASH_COMMAND" >&2' ERR

REPO_REF="${AZURIFY_REF:-main}"
REPO_TGZ="https://codeload.github.com/DeZio2004/azurify-host/tar.gz/$REPO_REF"
SRC=/opt/azurify-host          # installer files (eggs, theme, setup scripts)
CRED_FILE=/root/azurify-credentials.txt
PANEL_DIR=/var/www/azurify
PHP_VER=8.3
PANEL_VERSION=1.15.2      # the AZURIFY interface in ui/dist is built for this exact panel version

c_b="\033[1;36m"; c_g="\033[1;32m"; c_r="\033[1;31m"; c_0="\033[0m"
say()  { echo -e "${c_b}==>${c_0} $*"; }
ok()   { echo -e "${c_g}OK${c_0}  $*"; }
die()  { echo -e "${c_r}ERROR:${c_0} $*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || die "Run as root."
[ "$(uname -m)" = "x86_64" ] || [ "$(uname -m)" = "aarch64" ] || die "Unsupported CPU."
. /etc/os-release
case "$ID" in ubuntu|debian) ;; *) die "Only Ubuntu / Debian are supported." ;; esac
ARCH=amd64; [ "$(uname -m)" = "aarch64" ] && ARCH=arm64

# ---------------------------------------------------------------- questions
# Every answer can also come from the environment for unattended installs:
#   AZ_DOMAIN AZ_USER AZ_EMAIL AZ_PASS AZ_PORT AZ_NODE_PORT AZ_SFTP_PORT AZ_APP_PORTS
#   (+ AZ_SSL=0 to skip Let's Encrypt, AZ_FREE_PORT=y, AZ_UFW_ENABLE=0 to leave ufw off)
ask() { local var=$1 env=$2 prompt=$3; if [ -n "${!env:-}" ]; then printf -v "$var" '%s' "${!env}"; else read -rp "$prompt" "$var"; fi; }

# ask_valid VAR ENV "prompt" DEFAULT CHECK
# Asks until CHECK accepts the answer. CHECK prints why an answer is wrong and returns 1.
# With the answer preset in ENV (unattended install) a wrong value stops the installer instead.
ask_valid() {
  local var=$1 env=$2 prompt=$3 def=$4 check=$5 val msg
  while :; do
    if [ -n "${!env:-}" ]; then val=${!env}; else read -rp "$prompt" val; fi
    val="${val#"${val%%[![:space:]]*}"}"; val="${val%"${val##*[![:space:]]}"}"   # trim spaces
    [ -z "$val" ] && val=$def
    if msg=$($check "$val"); then printf -v "$var" '%s' "$val"; return 0; fi
    [ -n "${!env:-}" ] && die "$env: $msg"
    echo -e "  ${c_r}${msg:-That answer is not valid.}${c_0} Please try again."
  done
}

check_domain() {
  [ -n "$1" ] || { echo "A domain is required."; return 1; }
  [[ "$1" =~ ^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?)+$ ]] \
    || { echo "'$1' is not a domain. Use something like panel.example.com (no http://, no spaces)."; return 1; }
  return 0
}
check_user() {
  [[ "$1" =~ ^[A-Za-z0-9_.-]{3,191}$ ]] || { echo "Username needs 3+ characters: letters, numbers, . _ or -"; return 1; }
  return 0
}
check_email() {
  [[ "$1" =~ ^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$ ]] || { echo "'$1' is not an email address, e.g. you@gmail.com"; return 1; }
  return 0
}

echo -e "\n${c_b}AZURIFY Host installer${c_0}\n"
ask_valid DOMAIN AZ_DOMAIN "Panel domain (e.g. panel.example.com, DNS must point to this VPS): " "" check_domain
ask_valid ADMIN_USER AZ_USER "Admin username: " "" check_user
ask_valid EMAIL AZ_EMAIL "Admin email (used for login, password reset and SSL notices): " "" check_email
if [ -n "${AZ_PASS:-}" ]; then
  ADMIN_PASS="$AZ_PASS"; [ "${#ADMIN_PASS}" -ge 8 ] || die "AZ_PASS must be 8+ chars."
else
  while :; do
    read -rsp "Admin password (min 8 chars): " ADMIN_PASS; echo
    [ "${#ADMIN_PASS}" -ge 8 ] || { echo -e "  ${c_r}Too short (min 8 characters).${c_0} Please try again."; continue; }
    read -rsp "Repeat password: " P2; echo
    [ "$ADMIN_PASS" = "$P2" ] && break || echo -e "  ${c_r}Passwords differ.${c_0} Please try again."
  done
fi

# ---- ports: every port must be different (80 is needed for the SSL certificate, SSH must stay reachable)
SSH_PORT=$(sshd -T 2>/dev/null | awk '/^port /{print $2; exit}' || true); SSH_PORT="${SSH_PORT:-22}"
USED="80 $SSH_PORT"; [ "${AZ_SSL:-1}" = 0 ] && USED="$SSH_PORT"

check_port() {
  [[ "$1" =~ ^[0-9]+$ ]] && [ "$1" -ge 1 ] && [ "$1" -le 65535 ] || { echo "'$1' is not a port (1-65535)."; return 1; }
  for u in $USED; do
    [ "$1" = "$u" ] && { echo "Port $1 is already taken (SSH is $SSH_PORT, 80 is for SSL, or you used it above)."; return 1; }
  done
  return 0
}

holder() { ss -ltnpH "sport = :$1" 2>/dev/null | head -1; }
# returns 0 when the port is free (or was freed on request)
port_free() {
  local port=$1 answer PID UNIT
  [ -n "$(holder "$port")" ] || return 0
  echo -e "\n  Port $port is in use by:\n    $(holder "$port")"
  if [ -n "${AZ_FREE_PORT:-}" ]; then answer=$AZ_FREE_PORT; else read -rp "  Stop/disable that service to free port $port? [y/N]: " answer; fi
  [[ "$answer" =~ ^[Yy]$ ]] || return 1
  PID=$(holder "$port" | grep -oP 'pid=\K[0-9]+' | head -1 || true)
  UNIT=$( [ -n "$PID" ] && systemctl status "$PID" 2>/dev/null | grep -oE '[A-Za-z0-9@_.-]+\.service' | head -1 || true)
  if [ -n "$UNIT" ]; then systemctl disable --now "$UNIT" >/dev/null 2>&1 || true; else [ -n "$PID" ] && kill "$PID" 2>/dev/null || true; fi
  sleep 2
  [ -z "$(holder "$port")" ] && { ok "Port $port freed."; return 0; }
  echo -e "  ${c_r}Port $port is still busy.${c_0}"
  return 1
}

# ask_port VAR ENV "prompt" DEFAULT LABEL
ask_port() {
  local var=$1 env=$2 prompt=$3 def=$4 label=$5 picked
  while :; do
    ask_valid picked "$env" "$prompt" "$def" check_port
    if port_free "$picked"; then
      printf -v "$var" '%s' "$picked"; USED="$USED $picked"; return 0
    fi
    [ -n "${!env:-}" ] && die "$env: port $picked is busy."
    echo "  Choose a different $label port."
  done
}

ask_port PANEL_PORT AZ_PORT "Panel HTTPS port [443]: " 443 panel
ask_port NODE_PORT AZ_NODE_PORT "Node (wings) port [8080]: " 8080 node
ask_port SFTP_PORT AZ_SFTP_PORT "SFTP (file upload) port [2022]: " 2022 SFTP

# server/app ports: comma-separated ranges or single ports
check_ranges() {
  local value=${1// /} part from to u
  [ "$value" = none ] && return 0
  IFS=',' read -ra _parts <<< "$value"
  [ "${#_parts[@]}" -gt 0 ] || { echo "Enter ranges like 3000-3010,2000-2010 or 'none'."; return 1; }
  for part in "${_parts[@]}"; do
    [ -n "$part" ] || continue
    [[ "$part" =~ ^([0-9]{1,5})(-([0-9]{1,5}))?$ ]] || { echo "'$part' is not a port or range. Use e.g. 3000-3010,2000-2010,25565"; return 1; }
    from=${BASH_REMATCH[1]}; to=${BASH_REMATCH[3]:-$from}
    [ "$from" -ge 1 ] && [ "$to" -le 65535 ] && [ "$from" -le "$to" ] || { echo "Range $part must be low-high between 1 and 65535."; return 1; }
    [ $((to - from)) -lt 1000 ] || { echo "Range $part is too big (max 1000 ports per range)."; return 1; }
    for u in $USED; do
      [ "$u" -ge "$from" ] && [ "$u" -le "$to" ] && { echo "Range $part includes port $u, which is already taken (SSH, SSL, panel, node or SFTP)."; return 1; }
    done
  done
  return 0
}
ask_valid APP_PORTS AZ_APP_PORTS "Ports for your servers/apps, one or more ranges, e.g. 3000-3010,2000-2010,25565 [3000-3050, or 'none']: " "3000-3050" check_ranges
APP_RANGES=()
if [ "${APP_PORTS// /}" != none ]; then
  IFS=',' read -ra PARTS <<< "${APP_PORTS// /}"
  for part in "${PARTS[@]}"; do
    [ -n "$part" ] || continue
    from=${part%-*}; to=${part#*-}
    APP_RANGES+=("$from-$to")
  done
fi

DB_PASS=$(openssl rand -hex 16 2>/dev/null || head -c16 /dev/urandom | od -An -tx1 | tr -d ' \n')
export DEBIAN_FRONTEND=noninteractive

# ---------------------------------------------------------------- packages
say "Installing system packages (this takes a few minutes)"
# Repair leftovers from an earlier removal (half-removed MariaDB/MySQL packages break a reinstall).
dpkg --configure -a >/dev/null 2>&1 || true
LEFTOVER=$(dpkg -l 2>/dev/null | awk '$1 ~ /^(rc|iF|iU|iH)$/ && $2 ~ /^(mariadb|mysql|galera)/ {print $2}' || true)
if [ -n "$LEFTOVER" ]; then
  echo "Cleaning up a previous MariaDB install: $(echo $LEFTOVER)"
  echo "$LEFTOVER" | xargs -r dpkg --purge --force-all >/dev/null 2>&1 || true
  apt-get -f install -y >/dev/null 2>&1 || true
fi
apt-get update -y
apt-get install -y software-properties-common curl ca-certificates gnupg lsb-release tar unzip git cron openssl \
  nginx redis-server mariadb-server certbot ufw
if [ "$ID" = "ubuntu" ]; then
  add-apt-repository -y ppa:ondrej/php
else
  curl -fsSL https://packages.sury.org/php/apt.gpg -o /usr/share/keyrings/sury.gpg
  echo "deb [signed-by=/usr/share/keyrings/sury.gpg] https://packages.sury.org/php/ $VERSION_CODENAME main" > /etc/apt/sources.list.d/sury.list
fi
apt-get update -y
apt-get install -y "php$PHP_VER" "php$PHP_VER"-{cli,fpm,gd,mysql,mbstring,bcmath,xml,curl,zip,intl,redis}
curl -fsSL https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer
systemctl enable --now mariadb redis-server "php$PHP_VER-fpm"

# ---------------------------------------------------------------- database
say "Creating database"
mysql -u root <<SQL
CREATE DATABASE IF NOT EXISTS azurify;
CREATE USER IF NOT EXISTS 'azurify'@'127.0.0.1' IDENTIFIED BY '${DB_PASS}';
ALTER USER 'azurify'@'127.0.0.1' IDENTIFIED BY '${DB_PASS}';
GRANT ALL PRIVILEGES ON azurify.* TO 'azurify'@'127.0.0.1' WITH GRANT OPTION;
FLUSH PRIVILEGES;
SQL

# ---------------------------------------------------------------- SSL (before nginx so the port logic is simple)
say "Requesting SSL certificate for $DOMAIN"
systemctl stop nginx 2>/dev/null || true
HTTPS=1
if [ "${AZ_SSL:-1}" = 0 ]; then
  echo "Skipping SSL (AZ_SSL=0): the panel will use plain HTTP."
  HTTPS=0
elif ! certbot certonly --standalone --non-interactive --agree-tos -m "$EMAIL" -d "$DOMAIN" --preferred-challenges http; then
  echo -e "${c_r}SSL failed${c_0} (is the DNS A record pointing here and port 80 open?)."
  read -rp "Continue without HTTPS (plain HTTP)? [y/N]: " CONT
  [[ "$CONT" =~ ^[Yy]$ ]] || die "Fix DNS/port 80 and run again."
  HTTPS=0
fi
SCHEME=https; [ "$HTTPS" = 0 ] && SCHEME=http
DEFAULT_PORT=443; [ "$HTTPS" = 0 ] && DEFAULT_PORT=80
PORT_SUFFIX=""; [ "$PANEL_PORT" != "$DEFAULT_PORT" ] && PORT_SUFFIX=":$PANEL_PORT"
PANEL_URL="$SCHEME://$DOMAIN$PORT_SUFFIX"

# ---------------------------------------------------------------- panel files
say "Downloading panel"
mkdir -p "$PANEL_DIR" && cd "$PANEL_DIR"
curl -fsSL https://github.com/pterodactyl/panel/releases/download/v$PANEL_VERSION/panel.tar.gz | tar -xzf -
chmod -R 755 storage/* bootstrap/cache/
cp -n .env.example .env
COMPOSER_ALLOW_SUPERUSER=1 composer install --no-dev --optimize-autoloader --no-interaction
grep -q "^APP_KEY=base64" .env || php artisan key:generate --force --no-interaction

say "Configuring panel"
php artisan p:environment:setup --author="$EMAIL" --url="$PANEL_URL" --timezone="UTC" \
  --cache=redis --session=redis --queue=redis --redis-host=127.0.0.1 --redis-pass= --redis-port=6379 \
  --settings-ui=true --telemetry=false --no-interaction
php artisan p:environment:database --host=127.0.0.1 --port=3306 --database=azurify --username=azurify --password="$DB_PASS" --no-interaction
sed -i 's/^APP_NAME=.*/APP_NAME=AZURIFY/' .env
php artisan migrate --seed --force
php artisan p:user:make --email="$EMAIL" --username="$ADMIN_USER" --name-first=Admin --name-last=AZURIFY \
  --password="$ADMIN_PASS" --admin=1 --no-interaction || echo "(admin user already exists or was just created)"
chown -R www-data:www-data "$PANEL_DIR"

# queue worker + scheduler
(crontab -l 2>/dev/null | grep -v 'artisan schedule:run' || true; echo "* * * * * php $PANEL_DIR/artisan schedule:run >> /dev/null 2>&1") | crontab -
cat >/etc/systemd/system/azurify-queue.service <<EOF
[Unit]
Description=AZURIFY queue worker
After=redis-server.service
[Service]
User=www-data
Restart=always
ExecStart=/usr/bin/php $PANEL_DIR/artisan queue:work --queue=high,standard,low --sleep=3 --tries=3
RestartSec=5s
[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload && systemctl enable --now azurify-queue

# ---------------------------------------------------------------- AZURIFY branding + glass theme
say "Downloading AZURIFY Host files"
rm -rf "$SRC" && mkdir -p "$SRC"
if [ -n "${AZURIFY_SRC:-}" ] && [ -d "$AZURIFY_SRC" ]; then
  cp -r "$AZURIFY_SRC"/. "$SRC"/            # local copy (testing)
else
  curl -fsSL "$REPO_TGZ" | tar -xz -C "$SRC" --strip-components=1
fi
install -m 755 "$SRC/brand.sh" /usr/local/bin/azurify-brand

say "Applying AZURIFY branding and glass theme"
AZURIFY_SRC="$SRC" PANEL_DIR="$PANEL_DIR" /usr/local/bin/azurify-brand

say "Importing AzuRaya eggs, removing stock eggs, creating API keys"
SETUP_OK=1
php "$SRC/setup/azurify-setup.php" "$PANEL_DIR" "$SRC" "$ADMIN_USER" "$CRED_FILE" || SETUP_OK=0
php "$PANEL_DIR/artisan" view:clear >/dev/null; php "$PANEL_DIR/artisan" route:clear >/dev/null || true
chown -R www-data:www-data "$PANEL_DIR"

# ---------------------------------------------------------------- nginx
say "Configuring web server on port $PANEL_PORT"
rm -f /etc/nginx/sites-enabled/default
if [ "$HTTPS" = 1 ]; then
cat >/etc/nginx/sites-available/azurify.conf <<EOF
server {
    listen $PANEL_PORT ssl http2;
    server_name $DOMAIN;
    root $PANEL_DIR/public;
    index index.php;
    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    client_max_body_size 100m;
    location / { try_files \$uri \$uri/ /index.php?\$query_string; }
    location ~ \.php\$ {
        fastcgi_split_path_info ^(.+\.php)(/.+)\$;
        fastcgi_pass unix:/run/php/php$PHP_VER-fpm.sock;
        fastcgi_index index.php;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_param HTTP_PROXY "";
    }
    location ~ /\.ht { deny all; }
}
EOF
else
cat >/etc/nginx/sites-available/azurify.conf <<EOF
server {
    listen $PANEL_PORT;
    server_name $DOMAIN;
    root $PANEL_DIR/public;
    index index.php;
    client_max_body_size 100m;
    location / { try_files \$uri \$uri/ /index.php?\$query_string; }
    location ~ \.php\$ {
        fastcgi_split_path_info ^(.+\.php)(/.+)\$;
        fastcgi_pass unix:/run/php/php$PHP_VER-fpm.sock;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
    }
}
EOF
fi
ln -sf /etc/nginx/sites-available/azurify.conf /etc/nginx/sites-enabled/azurify.conf
nginx -t
systemctl enable --now nginx && systemctl restart nginx
# auto-renew: nginx does not hold port 80, so renew in standalone mode
(crontab -l 2>/dev/null | grep -v 'certbot renew' || true; echo '0 3 * * * certbot renew --quiet --standalone --deploy-hook "systemctl reload nginx; systemctl restart wings 2>/dev/null"') | crontab -

# ---------------------------------------------------------------- node (wings) on the same VPS
say "Installing Docker and the game node (wings)"
command -v docker >/dev/null || curl -fsSL https://get.docker.com | sh
systemctl enable --now docker
mkdir -p /etc/pterodactyl /var/lib/pterodactyl
curl -fsSL -o /usr/local/bin/wings "https://github.com/pterodactyl/wings/releases/latest/download/wings_linux_$ARCH"
chmod +x /usr/local/bin/wings

cd "$PANEL_DIR"
MEM=$(free -m | awk '/Mem:/{print $2}'); DISK=$(df -m /var/lib | awk 'NR==2{print $4}')
php artisan p:location:make --short=main --long="AZURIFY" --no-interaction
php artisan p:node:make --name="node-1" --description="AZURIFY local node" --locationId=1 --fqdn="$DOMAIN" \
  --public=1 --scheme="$SCHEME" --proxy=0 --maintenance=0 \
  --maxMemory="$MEM" --overallocateMemory=0 --maxDisk="$DISK" --overallocateDisk=0 \
  --uploadSize=100 --daemonListeningPort="$NODE_PORT" --daemonSFTPPort="$SFTP_PORT" --daemonBase=/var/lib/pterodactyl/volumes --no-interaction
php artisan p:node:configuration 1 > /etc/pterodactyl/config.yml

# server/app ports: create them on the node so they can be picked when creating a server
PUBLIC_IP=$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<NF;i++) if($i=="src"){print $(i+1); exit}}' || true)
APP_LABEL=""; [ "${#APP_RANGES[@]}" -gt 0 ] && APP_LABEL=$(printf '%s, ' "${APP_RANGES[@]}" | sed 's/, $//')
if [ "${#APP_RANGES[@]}" -gt 0 ] && [ -n "$PUBLIC_IP" ]; then
  if php "$SRC/setup/azurify-ports.php" "$PANEL_DIR" 1 "$PUBLIC_IP" "$DOMAIN" "${APP_RANGES[@]}"; then
    ok "Server ports $APP_LABEL added to node-1 ($PUBLIC_IP, shown as $DOMAIN)"
  else
    echo -e "${c_r}Could not add server ports automatically.${c_0} Add them in Admin > Nodes > node-1 > Allocation."
    SETUP_OK=0
  fi
fi
cat >/etc/systemd/system/wings.service <<EOF
[Unit]
Description=AZURIFY Wings daemon
After=docker.service
Requires=docker.service
[Service]
User=root
WorkingDirectory=/etc/pterodactyl
LimitNOFILE=4096
ExecStart=/usr/local/bin/wings
Restart=on-failure
RestartSec=5s
[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload && systemctl enable --now wings

# firewall: open every port the panel needs (SSH first so the connection is never cut)
say "Opening firewall ports"
FW_PORTS="$SSH_PORT/tcp 80/tcp $PANEL_PORT/tcp $NODE_PORT/tcp $SFTP_PORT/tcp"
for r in "${APP_RANGES[@]}"; do
  from=${r%-*}; to=${r#*-}
  if [ "$from" = "$to" ]; then spec="$from"; else spec="$from:$to"; fi
  FW_PORTS="$FW_PORTS $spec/tcp $spec/udp"
done
FW_PORTS=$(echo $FW_PORTS | tr ' ' '\n' | awk '!seen[$0]++' | tr '\n' ' ')
for rule in $FW_PORTS; do ufw allow "$rule" >/dev/null; done
if [ "${AZ_UFW_ENABLE:-1}" = 1 ]; then
  ufw --force enable >/dev/null
fi
ufw reload >/dev/null 2>&1 || true
ok "Firewall (ufw) allows: $(echo $FW_PORTS | sed 's# #, #g')"

PORT_LIST=$(printf '%s\n' "$PANEL_PORT" 80 "$NODE_PORT" "$SFTP_PORT" | awk '!seen[$0]++' | paste -sd, - | sed 's/,/, /g')
[ -n "$APP_LABEL" ] && PORT_LIST="$PORT_LIST, $APP_LABEL (tcp+udp)"
echo
echo -e "${c_g}AZURIFY Host is ready${c_0}"
echo "  Panel : $PANEL_URL"
echo "  Login : $ADMIN_USER  (the password you entered)"
echo "  Node  : node-1 (this VPS, node port $NODE_PORT, SFTP $SFTP_PORT)"
[ -n "$APP_LABEL" ] && echo "  Server ports: $APP_LABEL, ready to pick when you create a server"
echo "  This VPS firewall is open for: $PORT_LIST"
echo "  If your VPS provider has its own cloud firewall, open the same ports there too."
if [ -s "$CRED_FILE" ]; then
  echo
  echo "  API keys (also saved to $CRED_FILE):"
  sed -n 's/^\(dezio[a-z]*\)=\(.*\)$/    \1 : \2/p' "$CRED_FILE"
fi
[ "$SETUP_OK" = 1 ] || echo -e "  ${c_r}Some setup steps failed - see the PROBLEM lines above.${c_0}"
