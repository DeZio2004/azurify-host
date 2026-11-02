#!/usr/bin/env bash
# AZURIFY Host - update an existing install to the latest AZURIFY files
# (branding/theme, AzuRaya eggs, stock-egg removal, API keys, staff permissions).
#   bash <(curl -Ls https://raw.githubusercontent.com/DeZio2004/azurify-host/main/update.sh)
set -euo pipefail
trap 'echo -e "\033[1;31mFAILED at line $LINENO:\033[0m $BASH_COMMAND" >&2' ERR

REPO_REF="${AZURIFY_REF:-main}"
REPO_TGZ="https://codeload.github.com/DeZio2004/azurify-host/tar.gz/$REPO_REF"
SRC=/opt/azurify-host
PANEL_DIR="${PANEL_DIR:-/var/www/azurify}"
CRED_FILE=/root/azurify-credentials.txt

[ "$(id -u)" -eq 0 ] || { echo "Run as root."; exit 1; }
[ -f "$PANEL_DIR/artisan" ] || { echo "Panel not found in $PANEL_DIR"; exit 1; }

DB_NAME=$(grep '^DB_DATABASE=' "$PANEL_DIR/.env" | cut -d= -f2- | tr -d '"')
ADMIN_USER="${1:-$(mysql -N -u root "$DB_NAME" -e 'SELECT username FROM users WHERE root_admin = 1 ORDER BY id LIMIT 1')}"
[ -n "$ADMIN_USER" ] || { echo "No admin user found. Pass the username: update.sh <username>"; exit 1; }

echo "==> Downloading AZURIFY Host files ($REPO_REF)"
rm -rf "$SRC" && mkdir -p "$SRC"
if [ -n "${AZURIFY_SRC:-}" ] && [ -d "$AZURIFY_SRC" ]; then
  cp -r "$AZURIFY_SRC"/. "$SRC"/
else
  curl -fsSL "$REPO_TGZ" | tar -xz -C "$SRC" --strip-components=1
fi
install -m 755 "$SRC/brand.sh" /usr/local/bin/azurify-brand

echo "==> Branding and theme"
AZURIFY_SRC="$SRC" PANEL_DIR="$PANEL_DIR" /usr/local/bin/azurify-brand

echo "==> Eggs, API keys and staff permissions (admin: $ADMIN_USER)"
SETUP_OK=1
php "$SRC/setup/azurify-setup.php" "$PANEL_DIR" "$SRC" "$ADMIN_USER" "$CRED_FILE" || SETUP_OK=0

cd "$PANEL_DIR"
php artisan view:clear >/dev/null
php artisan route:clear >/dev/null || true
php artisan config:clear >/dev/null
chown -R www-data:www-data "$PANEL_DIR"
systemctl restart azurify-queue 2>/dev/null || true

echo
if [ -s "$CRED_FILE" ]; then
  echo "API keys (saved in $CRED_FILE):"
  sed -n 's/^\(dezio[a-z]*\)=\(.*\)$/  \1 : \2/p' "$CRED_FILE"
fi
if [ "$SETUP_OK" = 1 ]; then
  echo -e "\033[1;32mUpdate complete.\033[0m Hard-refresh the panel (Ctrl+F5). Staff page: Admin > Staff."
else
  echo -e "\033[1;31mSome steps failed - see the PROBLEM lines above.\033[0m"
  exit 1
fi
