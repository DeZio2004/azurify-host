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
echo -e "
${c_b}AZURIFY Host installer${c_0}
"
ask DOMAIN AZ_DOMAIN "Panel domain (e.g. panel.example.com, DNS must point to this VPS): "
[ -n "$DOMAIN" ] || die "Domain is required."
ask ADMIN_USER AZ_USER "Admin username: "
[[ "$ADMIN_USER" =~ ^[A-Za-z0-9_.-]{3,}$ ]] || die "Username: 3+ chars, letters/numbers/._-"
while :; do
  ask EMAIL AZ_EMAIL "Admin email (used for login, password reset and SSL notices): "
  [[ "$EMAIL" =~ ^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$ ]] && break
  [ -n "${AZ_EMAIL:-}" ] && die "AZ_EMAIL is not a valid email."
  echo "Enter a valid email, e.g. you@gmail.com"
done
if [ -n "${AZ_PASS:-}" ]; then
  ADMIN_PASS="$AZ_PASS"; [ "${#ADMIN_PASS}" -ge 8 ] || die "AZ_PASS must be 8+ chars."
else
  while :; do
    read -rsp "Admin password (min 8 chars): " ADMIN_PASS; echo
    [ "${#ADMIN_PASS}" -ge 8 ] || { echo "Too short."; continue; }
    read -rsp "Repeat password: " P2; echo
    [ "$ADMIN_PASS" = "$P2" ] && break || echo "Passwords differ."
  done
fi
valid_port() { [[ "$1" =~ ^[0-9]+$ ]] && [ "$1" -ge 1 ] && [ "$1" -le 65535 ]; }
SSH_PORT=$(sshd -T 2>/dev/null | awk '/^port /{print $2; exit}' || true); SSH_PORT="${SSH_PORT:-22}"

ask PANEL_PORT AZ_PORT "Panel HTTPS port [443]: "
PANEL_PORT="${PANEL_PORT:-443}"
valid_port "$PANEL_PORT" || die "Invalid panel port."
ask NODE_PORT AZ_NODE_PORT "Node (wings) port [8080]: "
NODE_PORT="${NODE_PORT:-8080}"
valid_port "$NODE_PORT" || die "Invalid node port."
ask SFTP_PORT AZ_SFTP_PORT "SFTP (file upload) port [2022]: "
SFTP_PORT="${SFTP_PORT:-2022}"
valid_port "$SFTP_PORT" || die "Invalid SFTP port."
ask APP_PORTS AZ_APP_PORTS "Ports for your servers/apps, e.g. 3000-3050 [3000-3050, or 'none']: "
APP_PORTS="${APP_PORTS:-3000-3050}"
[ "$APP_PORTS" = none ] && APP_PORTS=""

# every port must be different (80 is needed for the SSL certificate, SSH must stay reachable)
USED="80 $SSH_PORT"; [ "${AZ_SSL:-1}" = 0 ] && USED="$SSH_PORT"
for pair in "panel:$PANEL_PORT" "node:$NODE_PORT" "SFTP:$SFTP_PORT"; do
  name=${pair%%:*}; port=${pair#*:}
  for u in $USED; do [ "$port" = "$u" ] && die "The $name port $port is already used (by SSH, SSL or another answer). Pick another."; done
  USED="$USED $port"
done
APP_FROM=""; APP_TO=""
if [ -n "$APP_PORTS" ]; then
  [[ "$APP_PORTS" =~ ^([0-9]{4,5})(-([0-9]{4,5}))?$ ]] || die "Server ports must look like 3000-3050 (or a single port like 25565, from 1025 up)."
  APP_FROM=${BASH_REMATCH[1]}; APP_TO=${BASH_REMATCH[3]:-$APP_FROM}
  [ "$APP_FROM" -gt 1024 ] && [ "$APP_TO" -le 65535 ] && [ "$APP_FROM" -le "$APP_TO" ] || die "Server ports must be between 1025 and 65535, low-high."
  [ $((APP_TO - APP_FROM)) -lt 1000 ] || die "Use at most 1000 server ports at once."
  for u in $USED; do [ "$u" -ge "$APP_FROM" ] && [ "$u" -le "$APP_TO" ] && die "Server ports $APP_PORTS include port $u, which is already used. Pick another range."; done
fi

# free a chosen port if something else holds it
holder() { ss -ltnpH "sport = :$1" 2>/dev/null | head -1; }
free_port() {
  local port=$1
  [ -n "$(holder "$port")" ] || return 0
  echo -e "\nPort $port is in use by:\n  $(holder "$port")"
  ask FREE AZ_FREE_PORT "Stop/disable that service to free port $port? [y/N]: "
  if [[ "$FREE" =~ ^[Yy]$ ]]; then
    PID=$(holder "$port" | grep -oP 'pid=\K[0-9]+' | head -1 || true)
    UNIT=$( [ -n "$PID" ] && systemctl status "$PID" 2>/dev/null | grep -oE '[A-Za-z0-9@_.-]+\.service' | head -1 || true)
    if [ -n "$UNIT" ]; then systemctl disable --now "$UNIT" || true; else [ -n "$PID" ] && kill "$PID" || true; fi
    sleep 2
    [ -z "$(holder "$port")" ] || die "Port $port is still busy. Free it manually or choose another port."
    ok "Port $port freed."
  else
    die "Choose another port and run again."
  fi
}
for p in "$PANEL_PORT" "$NODE_PORT" "$SFTP_PORT"; do free_port "$p"; done

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
if [ -n "$APP_FROM" ] && [ -n "$PUBLIC_IP" ]; then
  if php "$SRC/setup/azurify-ports.php" "$PANEL_DIR" 1 "$PUBLIC_IP" "$DOMAIN" "$APP_FROM-$APP_TO"; then
    ok "Server ports $APP_FROM-$APP_TO added to node-1 ($PUBLIC_IP, shown as $DOMAIN)"
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
[ -n "$APP_FROM" ] && FW_PORTS="$FW_PORTS $APP_FROM:$APP_TO/tcp $APP_FROM:$APP_TO/udp"
[ "$APP_FROM" = "$APP_TO" ] && [ -n "$APP_FROM" ] && FW_PORTS="$SSH_PORT/tcp 80/tcp $PANEL_PORT/tcp $NODE_PORT/tcp $SFTP_PORT/tcp $APP_FROM/tcp $APP_FROM/udp"
FW_PORTS=$(echo $FW_PORTS | tr ' ' '\n' | awk '!seen[$0]++' | tr '\n' ' ')
for rule in $FW_PORTS; do ufw allow "$rule" >/dev/null; done
if [ "${AZ_UFW_ENABLE:-1}" = 1 ]; then
  ufw --force enable >/dev/null
fi
ufw reload >/dev/null 2>&1 || true
ok "Firewall (ufw) allows: $(echo $FW_PORTS | sed 's# #, #g')"

PORT_LIST=$(printf '%s\n' "$PANEL_PORT" 80 "$NODE_PORT" "$SFTP_PORT" | awk '!seen[$0]++' | paste -sd, - | sed 's/,/, /g')
[ -n "$APP_FROM" ] && PORT_LIST="$PORT_LIST, $APP_FROM-$APP_TO (tcp+udp)"
echo
echo -e "${c_g}AZURIFY Host is ready${c_0}"
echo "  Panel : $PANEL_URL"
echo "  Login : $ADMIN_USER  (the password you entered)"
echo "  Node  : node-1 (this VPS, node port $NODE_PORT, SFTP $SFTP_PORT)"
[ -n "$APP_FROM" ] && echo "  Server ports: $APP_FROM-$APP_TO, ready to pick when you create a server"
echo "  This VPS firewall is open for: $PORT_LIST"
echo "  If your VPS provider has its own cloud firewall, open the same ports there too."
if [ -s "$CRED_FILE" ]; then
  echo
  echo "  API keys (also saved to $CRED_FILE):"
  sed -n 's/^\(dezio[a-z]*\)=\(.*\)$/    \1 : \2/p' "$CRED_FILE"
fi
[ "$SETUP_OK" = 1 ] || echo -e "  ${c_r}Some setup steps failed - see the PROBLEM lines above.${c_0}"
