#!/usr/bin/env bash
# AZURIFY Host - rebrand + glass theme. Safe to run again after any panel update.
#   bash <(curl -Ls https://raw.githubusercontent.com/DeZio2004/azurify-host/main/brand.sh)
set -euo pipefail
trap 'echo -e "\033[1;31mFAILED at line $LINENO:\033[0m $BASH_COMMAND" >&2' ERR

REPO_RAW="${AZURIFY_RAW:-https://raw.githubusercontent.com/DeZio2004/azurify-host/main}"
PANEL_DIR="${PANEL_DIR:-/var/www/azurify}"
BRAND_NAME="${BRAND_NAME:-AZURIFY}"
BRAND_URL="${BRAND_URL:-https://azurify.win}"

[ "$(id -u)" -eq 0 ] || { echo "Run as root."; exit 1; }
[ -f "$PANEL_DIR/artisan" ] || { echo "Panel not found in $PANEL_DIR"; exit 1; }
cd "$PANEL_DIR"
echo "==> Applying $BRAND_NAME branding to $PANEL_DIR"

# ---- assets
BR="$PANEL_DIR/public/azurify"; mkdir -p "$BR"
for f in logo.png favicon.svg azurify-glass.css azurify-glass.js azurify-admin.css; do
  if [ -n "${AZURIFY_SRC:-}" ] && [ -f "$AZURIFY_SRC/branding/$f" ]; then
    cp -f "$AZURIFY_SRC/branding/$f" "$BR/$f"
  else
    curl -fsSL "$REPO_RAW/branding/$f?t=$(date +%s)" -o "$BR/$f"
  fi
done
V=$(date +%s)   # cache-buster so browsers pick up the new theme

# ---- app name (config fallback, .env and the settings table used by the admin "Settings" page)
if grep -q '^APP_NAME=' .env; then sed -i "s/^APP_NAME=.*/APP_NAME=\"$BRAND_NAME\"/" .env; else echo "APP_NAME=\"$BRAND_NAME\"" >> .env; fi
sed -i "s/env('APP_NAME', 'Pterodactyl')/env('APP_NAME', '$BRAND_NAME')/" config/app.php
DB_NAME=$(grep '^DB_DATABASE=' .env | cut -d= -f2- | tr -d '"')
mysql -u root "$DB_NAME" -e "INSERT INTO settings (\`key\`, \`value\`) VALUES ('settings::app:name', '$BRAND_NAME') ON DUPLICATE KEY UPDATE \`value\`='$BRAND_NAME';" 2>/dev/null \
  || mysql -u root "$DB_NAME" -e "DELETE FROM settings WHERE \`key\`='settings::app:name'; INSERT INTO settings (\`key\`, \`value\`) VALUES ('settings::app:name', '$BRAND_NAME');" || true

# ---- favicons from the logo (php-gd is already installed)
php -r '
$src = imagecreatefrompng($argv[1]); $w = imagesx($src); $h = imagesy($src); $s = max($w, $h);
foreach (["favicon-16x16"=>16,"favicon-32x32"=>32,"favicon-96x96"=>96,"apple-touch-icon"=>180,"apple-icon"=>180,
          "apple-icon-precomposed"=>180,"android-chrome-192x192"=>192,"android-chrome-512x512"=>512,"mstile-150x150"=>150,
          "ms-icon-144x144"=>144,"favicon"=>48] as $n=>$z) {
  $d = imagecreatetruecolor($z, $z); imagesavealpha($d, true); imagealphablending($d, false);
  imagefill($d, 0, 0, imagecolorallocatealpha($d, 0, 0, 0, 127)); imagealphablending($d, true);
  $tw = (int)round($w * $z / $s); $th = (int)round($h * $z / $s);
  imagecopyresampled($d, $src, (int)(($z-$tw)/2), (int)(($z-$th)/2), 0, 0, $tw, $th, $w, $h);
  imagepng($d, $argv[2]."/".($n === "favicon" ? "favicon.ico" : "$n.png"));
}' "$BR/logo.png" "$PANEL_DIR/public/favicons"
cp -f "$BR/favicon.svg" public/favicons/safari-pinned-tab.svg
sed -i 's/"name": *"[^"]*"/"name": "'"$BRAND_NAME"'"/; s/"short_name": *"[^"]*"/"short_name": "'"$BRAND_NAME"'"/' public/favicons/manifest.json 2>/dev/null || true

# ---- Blade templates: visible text only (never PHP namespaces or JS globals)
V_DIR=resources/views
sed -i "s/'Pterodactyl')/'$BRAND_NAME')/g" $V_DIR/layouts/admin.blade.php $V_DIR/templates/wrapper.blade.php
sed -i "s#Copyright &copy; 2015 - {{ date('Y') }} <a href=\"https://pterodactyl.io/\">Pterodactyl Software</a>.#\&copy; {{ date('Y') }} <a href=\"$BRAND_URL\">$BRAND_NAME</a>. All rights reserved.#" $V_DIR/layouts/admin.blade.php
sed -i "s/color=\"#bc6e3c\"/color=\"#22d3ee\"/; s/content=\"#0e4688\"/content=\"#070b17\"/" $V_DIR/layouts/admin.blade.php $V_DIR/templates/wrapper.blade.php
sed -i 's#https://www.gravatar.com/avatar/{{ md5(strtolower(Auth::user()->email)) }}?s=160#/azurify/logo.png#' $V_DIR/layouts/admin.blade.php
sed -i -E "s/Pterodactyl Panel version/$BRAND_NAME Host version/; s/Pterodactyl Panel/$BRAND_NAME Host/g" $V_DIR/admin/index.blade.php $V_DIR/admin/nests/index.blade.php
sed -i "s/Configure advanced settings for Pterodactyl\./Configure advanced settings for $BRAND_NAME./" $V_DIR/admin/settings/advanced.blade.php
sed -i "s/Configure Pterodactyl to your liking\./Configure $BRAND_NAME to your liking./" $V_DIR/admin/settings/index.blade.php
sed -i "s/Configure how Pterodactyl should handle/Configure how $BRAND_NAME should handle/" $V_DIR/admin/settings/mail.blade.php
sed -i "s/'Pterodactyl Console'/'$BRAND_NAME Console'/" $V_DIR/admin/servers/index.blade.php
sed -i -E "s#<a href=\"https://github.com/Pterodactyl/Panel/releases/v\{\{ \\\$version->getPanel\(\) \}\}\" target=\"_blank\">#<a>#; s#You can find instructions on how to update your panel <a href=\"https://pterodactyl.io/panel/1.0/updating.html\">here</a>.##" $V_DIR/admin/index.blade.php
# admin overview: drop the Discord / Docs / GitHub / Donate buttons
php -r '$f=$argv[1]; $s=file_get_contents($f);
$a=strpos($s, "getDiscord()"); $e=strrpos($s, "@endsection");
if ($a !== false && $e !== false) { $r=strrpos(substr($s, 0, $a), "<div class=\"row\">"); if ($r !== false) $s=substr($s, 0, $r).substr($s, $e); }
file_put_contents($f,$s);' $V_DIR/admin/index.blade.php
# nests page: drop the "Eggs are a powerful feature ... support@pterodactyl.io" warning box
php -r '$f=$argv[1]; $s=file_get_contents($f);
$a=strpos($s, "Eggs are a powerful feature");
if ($a !== false) { $r=strrpos(substr($s, 0, $a), "<div class=\"row\">"); $n=strpos($s, "<div class=\"row\">", $a);
  if ($r !== false && $n !== false) $s=substr($s, 0, $r).substr($s, $n); }
file_put_contents($f,$s);' $V_DIR/admin/nests/index.blade.php
# language files
grep -rlE "Pterodactyl" resources/lang 2>/dev/null | xargs -r sed -i -E "s/Pterodactyl Panel/$BRAND_NAME Host/g; s/Pterodactyl/$BRAND_NAME/g" || true

# ---- inject theme (replaces any older injection)
for L in $V_DIR/templates/wrapper.blade.php $V_DIR/layouts/admin.blade.php $V_DIR/templates/auth/core.blade.php; do
  [ -f "$L" ] || continue
  sed -i -E 's#<link rel="stylesheet" href="/azurify/[^"]*">##g; s#<script defer src="/azurify/[^"]*"></script>##g' "$L"
done
sed -i "s#</head>#<link rel=\"stylesheet\" href=\"/azurify/azurify-glass.css?v=$V\"><script defer src=\"/azurify/azurify-glass.js?v=$V\"></script>\n</head>#" $V_DIR/templates/wrapper.blade.php
sed -i "s#</head>#<link rel=\"stylesheet\" href=\"/azurify/azurify-admin.css?v=$V\">\n</head>#" $V_DIR/layouts/admin.blade.php
sed -i 's/class="hold-transition skin-blue fixed sidebar-mini"/class="hold-transition skin-blue fixed sidebar-mini azurify"/' $V_DIR/layouts/admin.blade.php

# ---- compiled client app (React bundle): display strings, links, mascot, terminal prompt
for J in public/assets/*.js; do
  sed -i -E \
    -e "s#\"/assets/svgs/pterodactyl.svg\"#\"/azurify/logo.png\"#g" \
    -e "s#\"https://pterodactyl.io\"#\"$BRAND_URL\"#g" \
    -e "s#\"Pterodactyl Software\"#\"$BRAND_NAME\"#g" \
    -e "s#\"Pterodactyl®\"#\"$BRAND_NAME\"#g" \
    -e "s#Pterodactyl Panel#$BRAND_NAME Host#g" \
    -e "s#container@pterodactyl~#container@azurify~#g" \
    -e "s#© 2015 - \"#© \"#g" \
    "$J"
done

# keep subresource-integrity hashes valid for the edited bundle files
php -r '$m=json_decode(file_get_contents($argv[1]),true); foreach($m as $k=>&$e){ $f=$argv[2].$e["src"]; if(is_file($f)) $e["integrity"]="sha384-".base64_encode(hash_file("sha384",$f,true)); } file_put_contents($argv[1], json_encode($m, JSON_PRETTY_PRINT|JSON_UNESCAPED_SLASHES));' public/assets/manifest.json public

# ---- caches
php artisan view:clear >/dev/null
php artisan config:clear >/dev/null
php artisan cache:clear >/dev/null || true
chown -R www-data:www-data "$PANEL_DIR"
systemctl reload "php*-fpm" 2>/dev/null || systemctl restart php8.3-fpm 2>/dev/null || true

echo -e "\033[1;32mDone.\033[0m Hard-refresh the panel in your browser (Ctrl+F5)."
