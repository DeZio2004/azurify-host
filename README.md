# AZURIFY Host

One-command game/app hosting panel for AZURIFY, with a glass UI.
The panel, database, Redis, nginx, SSL and the game node (wings + Docker) all install on the same VPS.

## Fresh install

On a fresh Ubuntu 22.04/24.04 or Debian 12 VPS, as root (point the domain's A record at the VPS first):

    bash <(curl -Ls https://raw.githubusercontent.com/DeZio2004/azurify-host/main/install.sh)

It asks 5 things: domain, admin username, admin email, admin password, panel port (default 443).
If the port is busy, it shows what holds it and offers to stop that service.

What the installer sets up for you:

- **AzuRaya eggs** (Dashboard, Inbox, Managed Bot, Website, WhatsApp Bot) in an "AzuRaya" nest.
  The stock Minecraft / Rust / Source / Voice eggs are removed.
- **API keys** `dezioapplicationapi` (application, `ptla_...`) and `dezioclientapi` (client, `ptlc_...`),
  printed at the end and saved to `/root/azurify-credentials.txt`.
- **Staff permissions**: Admin > Staff lets the owner give any user staff access with ticked permissions
  (view all servers, create, edit, delete servers, manage users, eggs, nodes, ...).

## Update an existing install

    bash <(curl -Ls https://raw.githubusercontent.com/DeZio2004/azurify-host/main/update.sh)

Applies the latest branding, eggs, API keys and staff system. Safe to run again. Hard-refresh the browser after.

## Firewall

Open 80, your panel port, 8080 and 2022 (plus game ports) in any cloud firewall.

Built on the MIT-licensed Pterodactyl panel; its LICENSE file stays in the panel folder.
