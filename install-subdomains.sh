#!/bin/bash
# ==============================================================================
# Architectural Block: install-subdomains.sh
# ==============================================================================
# Purpose:
#   One-shot server bootstrap & provisioning script designed to be executed from
#   `~` (`/home/michael`) on the RaggieSoft DigitalOcean Droplet (NYC1 - 142.93.244.239).
#
# Key Responsibilities:
#   1. Pulls the latest `raggiesoft-deployment-tools` and `nginx-config` repos.
#   2. Creates `/var/www/` directories for all new `*.raggiesoft.com` subdomains
#      (`engineroom`, `stardust`, `corporate`, `storetrainer`, `nebulae`) and
#      assigns `michael:www-data` ownership so `sarah-deploy.sh` can rsync
#      without requiring root privileges.
#   3. Clones (or updates) the public GitHub repositories in `/home/michael/`:
#      - `raggiesoft/raggiesoft-engine-room-records`
#      - `raggiesoft/raggiesoft-stardust-engine`
#      - `raggiesoft/raggiesoft-corporate`
#      - `raggiesoft/raggiesoft-storetrainer`
#      - `raggiesoft/raggiesoft-nebulae`
#   4. Installs all Nginx vhost `.conf` files into `/etc/nginx/sites-available/`,
#      links them into `/etc/nginx/sites-enabled/`, validates with `sudo nginx -t`,
#      and reloads Nginx gracefully.
#   5. Runs `/home/michael/raggiesoft-deployment-tools/sarah-deploy.sh --force-reset`
#      as standard user `michael` to populate all `/var/www/` document roots.
# ==============================================================================

set -e

if [ "$EUID" -eq 0 ]; then
    echo "🚨 ERROR: Please run this script as 'michael' from ~ (not as root). It will prompt for sudo only where needed."
    exit 1
fi

HOME_DIR="/home/michael"
cd "$HOME_DIR"

echo "🚀 [1/5] Synchronizing raggiesoft-deployment-tools and nginx-config..."
if [ -d "$HOME_DIR/raggiesoft-deployment-tools/.git" ]; then
    git -C "$HOME_DIR/raggiesoft-deployment-tools" fetch origin main
    git -C "$HOME_DIR/raggiesoft-deployment-tools" reset --hard origin/main
else
    git clone https://github.com/raggiesoft/raggiesoft-deployment-tools.git "$HOME_DIR/raggiesoft-deployment-tools"
fi

if [ -d "$HOME_DIR/nginx-config/.git" ]; then
    git -C "$HOME_DIR/nginx-config" fetch origin main
    git -C "$HOME_DIR/nginx-config" reset --hard origin/main
else
    git clone https://github.com/raggiesoft/nginx-config.git "$HOME_DIR/nginx-config"
fi

echo "📂 [2/5] Provisioning /var/www subdomain directories and permissions..."
WEB_ROOTS=(
    "/var/www/raggiesoft.com"
    "/var/www/engineroom.raggiesoft.com"
    "/var/www/stardust.raggiesoft.com"
    "/var/www/corporate.raggiesoft.com"
    "/var/www/storetrainer.raggiesoft.com"
    "/var/www/backstage.raggiesoft.com"
    "/var/www/nebulae.raggiesoft.com"
    "/var/www/music.raggiesoft.com"
    "/var/www/lore.raggiesoft.com"
    "/var/www/raggiesoft-book-library"
    "/var/www/michaelpragsdale.com"
)

for dir in "${WEB_ROOTS[@]}"; do
    sudo mkdir -p "$dir"
    sudo chown -R michael:www-data "$dir"
    sudo chmod -R 755 "$dir"
    echo "   ✓ Ready: $dir"
done

echo "📦 [3/5] Cloning / updating subdomain GitHub repositories in $HOME_DIR..."
REPOS=(
    "raggiesoft-hub"
    "raggiesoft-nebulae"
    "raggiesoft-book-library"
    "raggiesoft-lore"
    "raggiesoft-music"
    "raggiesoft-portfolio"
    "raggiesoft-engine-room-records"
    "raggiesoft-stardust-engine"
    "raggiesoft-corporate"
    "raggiesoft-storetrainer"
    "raggiesoft-backstage"
)

for repo in "${REPOS[@]}"; do
    if [ -d "$HOME_DIR/$repo/.git" ]; then
        echo "   -> Updating $repo..."
        git -C "$HOME_DIR/$repo" fetch origin main
        git -C "$HOME_DIR/$repo" reset --hard origin/main
    else
        echo "   -> Cloning $repo..."
        git clone "https://github.com/raggiesoft/$repo.git" "$HOME_DIR/$repo"
    fi
done

echo "🌐 [4/5] Installing Nginx virtual host configurations & validating..."
VHOSTS=(
    "raggiesoft.com.conf"
    "engineroom.raggiesoft.com.conf"
    "stardust.raggiesoft.com.conf"
    "corporate.raggiesoft.com.conf"
    "storetrainer.raggiesoft.com.conf"
    "backstage.raggiesoft.com.conf"
    "nebulae.raggiesoft.com.conf"
    "music.raggiesoft.com.conf"
    "books.raggiesoft.com.conf"
    "lore.raggiesoft.com.conf"
    "michaelpragsdale.com.conf"
)

for conf in "${VHOSTS[@]}"; do
    if [ -f "$HOME_DIR/nginx-config/$conf" ]; then
        sudo cp "$HOME_DIR/nginx-config/$conf" "/etc/nginx/sites-available/$conf"
        sudo ln -sf "/etc/nginx/sites-available/$conf" "/etc/nginx/sites-enabled/$conf"
        echo "   ✓ Enabled vhost: $conf"
    fi
done

sudo nginx -t
sudo systemctl reload nginx
echo "   ✓ Nginx configuration validated and reloaded."

echo "👩‍💼 [5/5] Triggering Sarah Autonomous Deployment (--force-reset)..."
chmod +x "$HOME_DIR/raggiesoft-deployment-tools/sarah-deploy.sh"
"$HOME_DIR/raggiesoft-deployment-tools/sarah-deploy.sh" --force-reset

echo "=============================================================================="
echo "✅ ALL RAGGIESOFT SUBDOMAIN CONSTELLATIONS INSTALLED & LIVE!"
echo "   • https://raggiesoft.com           (Stardust Engine CMS / Elara)"
echo "   • https://engineroom.raggiesoft.com (Engine Room Records - Astro 6)"
echo "   • https://stardust.raggiesoft.com   (The Stardust Engine - Nuxt 4 + Vue 3)"
echo "   • https://corporate.raggiesoft.com  (RaggieSoft Media - Bootstrap 5.3.8)"
echo "   • https://storetrainer.raggiesoft.com (StoreTrainer - Vanilla TS + Win98)"
echo "   • https://backstage.raggiesoft.com  (RaggieSoft Backstage - Web Awesome Pro PWA)"
echo "   • https://nebulae.raggiesoft.com    (Cosmic Observatory Master Sitemap)"
echo "   • https://music.raggiesoft.com      (The Listening Room - SvelteKit 2)"
echo "   • https://books.raggiesoft.com      (Ocean View Archives Book Reader)"
echo "   • https://lore.raggiesoft.com       (Lore Encyclopedia - Next.js 16)"
echo "   • https://michaelpragsdale.com      (Executive Dossier - Angular 19)"
echo "=============================================================================="

