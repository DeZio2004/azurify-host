#!/usr/bin/env bash
# AZURIFY Host - remove the panel, node (wings), game/app servers and their data from this VPS.
#   bash <(curl -Ls https://raw.githubusercontent.com/DeZio2004/azurify-host/main/uninstall.sh)
# Shared system packages (nginx, MariaDB, PHP, Redis, Docker) stay installed unless you choose --purge.
set -uo pipefail

PANEL_DIR="${PANEL_DIR:-/var/www/azurify}"
PURGE=0; [ "${1:-}" = "--purge" ] && PURGE=1
[ "$(id -u)" -eq 0 ] || { echo "Run as root."; exit 1; }

echo -e "\033[1;31mThis permanently deletes the AZURIFY panel, its database, every server and all server files on this VPS.\033[0m"
[ "$PURGE" = 1 ] && echo "--purge: nginx, MariaDB, PHP, Redis, Docker and certbot packages are removed too."
if [ "${AZ_YES:-}" != "yes" ]; then
  read -rp "Type DELETE to continue: " ANSWER
  [ "$ANSWER" = "DELETE" ] || { echo "Cancelled."; exit 1; }
fi

step() { echo -e "\033[1;36m==>\033[0m $*"; }

DB_NAME=azurify; DB_USER=azurify
if [ -f "$PANEL_DIR/.env" ]; then
  DB_NAME=$(grep '^DB_DATABASE=' "$PANEL_DIR/.env" | cut -d= -f2- | tr -d '"' || echo azurify)
  DB_USER=$(grep '^DB_USERNAME=' "$PANEL_DIR/.env" | cut -d= -f2- | tr -d '"' || echo azurify)
fi

step "Stopping services"
systemctl disable --now wings azurify-queue 2>/dev/null || true
rm -f /etc/systemd/system/wings.service /etc/systemd/system/azurify-queue.service
systemctl daemon-reload

step "Removing server containers and their data"
if command -v docker >/dev/null; then
  docker ps -aq --filter "label=Service=Pterodactyl" | xargs -r docker rm -f >/dev/null 2>&1 || true
  docker network rm pterodactyl_nw >/dev/null 2>&1 || true
fi
rm -rf /var/lib/pterodactyl /etc/pterodactyl /var/log/pterodactyl /tmp/pterodactyl /usr/local/bin/wings
userdel pterodactyl 2>/dev/null || true

step "Removing the panel"
rm -rf "$PANEL_DIR" /opt/azurify-host /usr/local/bin/azurify-brand /root/azurify-credentials.txt
rm -f /etc/nginx/sites-enabled/azurify.conf /etc/nginx/sites-available/azurify.conf
systemctl reload nginx 2>/dev/null || true
(crontab -l 2>/dev/null | grep -v 'artisan schedule:run' | grep -v 'certbot renew' || true) | crontab -

step "Removing the database"
if command -v mysql >/dev/null; then
  mysql -u root -e "DROP DATABASE IF EXISTS \`$DB_NAME\`; DROP USER IF EXISTS '$DB_USER'@'127.0.0.1'; FLUSH PRIVILEGES;" 2>/dev/null || true
fi

if [ "$PURGE" = 1 ]; then
  step "Removing system packages"
  export DEBIAN_FRONTEND=noninteractive
  apt-get purge -y nginx nginx-common mariadb-server mariadb-client mariadb-common mysql-common galera-4 \
    redis-server redis-tools certbot 'php8.3*' docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin >/dev/null 2>&1 || true
  apt-get autoremove --purge -y >/dev/null 2>&1 || true
  # purge anything left in "removed, config kept" state so a reinstall starts clean
  dpkg -l | awk '/^rc/ {print $2}' | grep -E 'mariadb|mysql|galera|nginx|redis|php|docker|containerd|certbot' | xargs -r dpkg --purge >/dev/null 2>&1 || true
  rm -rf /var/lib/mysql /etc/mysql /var/lib/docker /etc/letsencrypt /etc/nginx /usr/local/bin/composer
fi

echo
echo -e "\033[1;32mAZURIFY Host removed.\033[0m"
[ "$PURGE" = 0 ] && echo "System packages were kept, so a fresh install is faster. SSL certificates in /etc/letsencrypt were kept."
echo "Fresh install: bash <(curl -Ls https://raw.githubusercontent.com/DeZio2004/azurify-host/main/install.sh)"
