#!/usr/bin/env bash
# Builds the AZURIFY Host interface: Pterodactyl panel source (pinned version) + ui/overrides.
# Output: ui/dist/assets (the compiled public/assets folder the installer ships).
#   bash ui/build-ui.sh [--deploy /var/www/azurify]
set -euo pipefail

PANEL_VERSION="1.15.2"
HERE="$(cd "$(dirname "$0")" && pwd)"
BASE=/opt/az-ui
SRC="$BASE/panel-src"          # pristine upstream source + node_modules
WORK="$BASE/work"              # source with our overrides applied

if [ ! -d "$SRC" ]; then
  mkdir -p "$BASE"
  curl -fsSL "https://github.com/pterodactyl/panel/archive/refs/tags/v$PANEL_VERSION.tar.gz" | tar -xz -C "$BASE"
  mv "$BASE/panel-$PANEL_VERSION" "$SRC"
fi
if [ ! -d "$SRC/node_modules" ]; then
  (cd "$SRC" && yarn install --frozen-lockfile --non-interactive)
fi

rm -rf "$WORK" && mkdir -p "$WORK"
tar -C "$SRC" --exclude=./node_modules -cf - . | tar -C "$WORK" -xf -
ln -s "$SRC/node_modules" "$WORK/node_modules"
cp -r "$HERE/overrides/." "$WORK/"
find "$WORK/resources/scripts" "$WORK/tailwind.config.js" -type f -exec sed -i 's/\r$//' {} +

cd "$WORK"
echo "==> Type check"
yarn -s tsc
echo "==> Production build"
yarn -s build:production

rm -rf "$HERE/dist/assets" && mkdir -p "$HERE/dist"
cp -r "$WORK/public/assets" "$HERE/dist/assets"
echo "$PANEL_VERSION" > "$HERE/dist/PANEL_VERSION"
echo "==> Built into $HERE/dist/assets"

if [ "${1:-}" = "--deploy" ] && [ -n "${2:-}" ]; then
  cp -r "$HERE/dist/assets/." "$2/public/assets/"
  chown -R www-data:www-data "$2/public/assets"
  echo "==> Deployed to $2"
fi
