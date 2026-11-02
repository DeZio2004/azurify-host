# AZURIFY Host

One-command game/app hosting panel for AZURIFY, with a glass UI.
The panel, database, Redis, nginx, SSL and the game node (wings + Docker) all install on the same VPS.

## Fresh install

On a fresh Ubuntu 22.04/24.04 or Debian 12 VPS, as root (point the domain's A record at the VPS first):

    bash <(curl -Ls https://raw.githubusercontent.com/DeZio2004/azurify-host/main/install.sh)

It asks: domain, admin username, email, password, then the ports:

| Question | Default | Used for |
|---|---|---|
| Panel port | 443 | the website you log in to |
| Node port | 8080 | live console and server control (wings) |
| SFTP port | 2022 | uploading files to servers |
| Server ports | 3000-3050 | ports your servers/apps can use (`none` to skip) |

If a port is busy, it shows what holds it and offers to stop that service. Server ports are added to the node
automatically, and the firewall (ufw) is turned on with SSH, 80 and all of the ports above allowed.
If your VPS provider has its own cloud firewall, open the same ports there.

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

## Uninstall

    bash <(curl -Ls https://raw.githubusercontent.com/DeZio2004/azurify-host/main/uninstall.sh)

Removes the panel, its database, the node and every server with its files (type DELETE to confirm).
System packages stay so a reinstall is fast; add `--purge` at the end to remove nginx, MariaDB, PHP, Redis and Docker too.

## Firewall

The installer opens the VPS firewall for you. A provider cloud firewall needs the same ports opened by hand.

Built on the MIT-licensed Pterodactyl panel; its LICENSE file stays in the panel folder.
