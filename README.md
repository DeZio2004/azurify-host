# AZURIFY Host

One-command game/app hosting panel for AZURIFY, with a glass UI.
The panel, database, Redis, nginx, SSL and the game node (wings + Docker) all install on the same VPS.

## Fresh install

On a fresh Ubuntu 22.04/24.04 or Debian 12 VPS, as root (point the domain's A record at the VPS first):

    bash <(curl -Ls https://raw.githubusercontent.com/DeZio2004/azurify-host/main/install.sh)

It asks 5 things: domain, admin username, admin email, admin password, panel port (default 443).
If the port is busy, it shows what holds it and offers to stop that service.

## Update branding / theme on an existing install

    bash <(curl -Ls https://raw.githubusercontent.com/DeZio2004/azurify-host/main/brand.sh)

Also run this after any panel version update. Then hard-refresh the browser (Ctrl+F5).

## Firewall

Open 80, your panel port, 8080 and 2022 (plus game ports) in any cloud firewall.

Built on the MIT-licensed Pterodactyl panel; its LICENSE file stays in the panel folder.
