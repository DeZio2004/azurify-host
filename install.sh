#!/usr/bin/env bash
# AZURIFY Host - one-VPS installer (panel + database + node/wings + SSL)
# Usage (as root, fresh Ubuntu 22.04/24.04 or Debian 12):
#   bash <(curl -Ls https://raw.githubusercontent.com/DeZio2004/azurify-host/main/install.sh)
set -euo pipefail
trap 'echo -e "[1;31mFAILED at line $LINENO:[0m $BASH_COMMAND" >&2' ERR

REPO_RAW="${AZURIFY_RAW:-https://raw.githubusercontent.com/DeZio2004/azurify-host/main}"
PANEL_DIR=/var/www/azurify
PHP_VER=8.3

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
echo -e "\n${c_b}AZURIFY Host installer${c_0}\n"
read -rp "Panel domain (e.g. panel.example.com, DNS must point to this VPS): " DOMAIN
[ -n "$DOMAIN" ] || die "Domain is required."
read -rp "Admin username: " ADMIN_USER
[[ "$ADMIN_USER" =~ ^[A-Za-z0-9_.-]{3,}$ ]] || die "Username: 3+ chars, letters/numbers/._-"
while :; do
  read -rp "Admin email (used for login, password reset and SSL notices): " EMAIL
  [[ "$EMAIL" =~ ^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$ ]] && break || echo "Enter a valid email, e.g. you@gmail.com"
done
while :; do
  read -rsp "Admin password (min 8 chars): " ADMIN_PASS; echo
  [ "${#ADMIN_PASS}" -ge 8 ] || { echo "Too short."; continue; }
  read -rsp "Repeat password: " P2; echo
  [ "$ADMIN_PASS" = "$P2" ] && break || echo "Passwords differ."
done
read -rp "Panel HTTPS port [443]: " PANEL_PORT
PANEL_PORT="${PANEL_PORT:-443}"
[[ "$PANEL_PORT" =~ ^[0-9]+$ ]] && [ "$PANEL_PORT" -ge 1 ] && [ "$PANEL_PORT" -le 65535 ] || die "Invalid port."
for p in 8080 2022; do [ "$PANEL_PORT" = "$p" ] && die "Port $p is used by the game node (wings). Pick another."; done

# free the chosen port if something else holds it
holder() { ss -ltnpH "sport = :$1" 2>/dev/null | head -1; }
if [ -n "$(holder "$PANEL_PORT")" ]; then
  echo -e "\nPort $PANEL_PORT is in use by:\n  $(holder "$PANEL_PORT")"
  read -rp "Stop/disable that service to free the port? [y/N]: " FREE
  if [[ "$FREE" =~ ^[Yy]$ ]]; then
    PID=$(holder "$PANEL_PORT" | grep -oP 'pid=\K[0-9]+' | head -1 || true)
    UNIT=$( [ -n "$PID" ] && systemctl status "$PID" 2>/dev/null | grep -oE '[A-Za-z0-9@_.-]+\.service' | head -1 || true)
    if [ -n "$UNIT" ]; then systemctl disable --now "$UNIT" || true; else [ -n "$PID" ] && kill "$PID" || true; fi
    sleep 2
    [ -z "$(holder "$PANEL_PORT")" ] || die "Port $PANEL_PORT is still busy. Free it manually or choose another port."
    ok "Port $PANEL_PORT freed."
  else
    die "Choose another port and run again."
  fi
fi

DB_PASS=$(openssl rand -hex 16 2>/dev/null || head -c16 /dev/urandom | od -An -tx1 | tr -d ' \n')
export DEBIAN_FRONTEND=noninteractive

# ---------------------------------------------------------------- packages
say "Installing system packages (this takes a few minutes)"
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
if ! certbot certonly --standalone --non-interactive --agree-tos -m "$EMAIL" -d "$DOMAIN" --preferred-challenges http; then
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
curl -fsSL https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz | tar -xzf -
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
say "Applying AZURIFY branding and glass theme"
curl -fsSL "$REPO_RAW/brand.sh" -o /usr/local/bin/azurify-brand && chmod +x /usr/local/bin/azurify-brand
AZURIFY_RAW="$REPO_RAW" PANEL_DIR="$PANEL_DIR" /usr/local/bin/azurify-brand

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
curl -fsSL https://get.docker.com | sh
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
  --uploadSize=100 --daemonListeningPort=8080 --daemonSFTPPort=2022 --daemonBase=/var/lib/pterodactyl/volumes --no-interaction
php artisan p:node:configuration 1 > /etc/pterodactyl/config.yml
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

# firewall hints (only touches ufw if it is already active)
if ufw status 2>/dev/null | grep -q "Status: active"; then
  ufw allow 80/tcp; ufw allow "$PANEL_PORT"/tcp; ufw allow 8080/tcp; ufw allow 2022/tcp
fi

echo
echo -e "${c_g}AZURIFY Host is ready${c_0}"
echo "  Panel : $PANEL_URL"
echo "  Login : $ADMIN_USER  (the password you entered)"
echo "  Node  : node-1 (this VPS, wings on 8080 / SFTP 2022)"
echo "  Open ports in your cloud firewall: 80, $PANEL_PORT, 8080, 2022 + game server ports."
echo "  Add game ports: Admin > Nodes > node-1 > Allocation."
