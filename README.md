# AZURIFY Host

One-command Pterodactyl-based game/app hosting panel, rebranded for AZURIFY with a glass UI.
Panel, database, Redis, nginx, SSL and the node (wings + Docker) are installed on the same VPS.

1. Push this folder to GitHub (repo `azurify-host`), then edit `REPO_RAW` at the top of `install.sh`
   (replace `DeZio2004`).
2. On a fresh Ubuntu 22.04/24.04 or Debian 12 VPS, as root:

       bash <(curl -Ls https://raw.githubusercontent.com/DeZio2004/azurify-host/main/install.sh)

3. Answer 4 questions: domain, admin username, admin password, panel port (default 443).
   If the port is busy the installer shows what holds it and offers to stop that service.

Notes: the domain's A record must point to the VPS before installing (SSL uses port 80 briefly).
Open 80, your panel port, 8080 and 2022 in any cloud firewall.
Pterodactyl is MIT-licensed; its LICENSE file stays in the panel folder.
