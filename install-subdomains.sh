#!/bin/bash
# ==============================================================================
# Architectural Block: install-subdomains.sh (Idempotent "Skip Existing" Edition)
# ==============================================================================
# Purpose:
#   Safe, idempotent server bootstrap & incremental subdomain provisioning script
#   designed to be executed as standard user `michael` from `~` (`/home/michael`)
#   on the RaggieSoft DigitalOcean Droplet (NYC1 - 142.93.244.239).
#
# Core Idempotency Guarantee ("Skip What Already Exists"):
#   Every website project added to this script follows a strict non-destructive
#   skip-existing contract by default:
#     1. Infrastructure Sync (`raggiesoft-deployment-tools` & `nginx-config`):
#        Clones if missing or fast-forwards to `origin/main` so the latest
#        manifests and deployment tools are available locally.
#     2. Web Roots (`/var/www/*`):
#        If a web root directory already exists and is populated, it is SKIPPED
#        untouched (never running recursive `chown -R` or `chmod -R 755` over
#        live 644 production assets). Only missing or empty `/var/www/*` folders
#        are created and assigned `michael:www-data` ownership.
#     3. GitHub Repositories (`/home/michael/raggiesoft-*`):
#        If `$HOME_DIR/<repo>/.git` already exists, it is SKIPPED here so live
#        clones are not unnecessarily hard-reset; only newly added/missing
#        repositories (e.g., `raggiesoft-backstage`) are cloned from GitHub.
#     4. Nginx Virtual Hosts (`/etc/nginx/sites-available/*.conf`):
#        If `/etc/nginx/sites-available/<conf>` and `/etc/nginx/sites-enabled/<conf>`
#        already exist, the vhost is SKIPPED by default so live Nginx configs are
#        untouched. Pass `--sync-nginx` when you explicitly want modified `.conf`
#        files from `nginx-config` copied and reloaded (unchanged `.conf` files
#        are still skipped via byte-for-byte `cmp -s`). Nginx is tested and
#        reloaded ONLY if at least one vhost was newly added or updated.
#     5. Incremental Sarah Deployment (`sarah-deploy.sh`):
#        Invokes `sarah-deploy.sh` WITHOUT `--force-reset` by default so Sarah
#        hydrates ONLY newly created/empty web roots and repos with new commits
#        while skipping every unchanged website in milliseconds. Pass
#        `--force-reset` only if you explicitly want a full nuclear re-sync.
#
# CLI Flags (100% Non-Interactive — Never Prompts Aside From OS `sudo` Auth):
#   ./install-subdomains.sh                 # Default: provision ONLY missing sites/vhosts
#   ./install-subdomains.sh --sync-nginx    # Also update changed Nginx .conf files
#   ./install-subdomains.sh --force-reset   # Force full re-sync of all repos & web roots
# ==============================================================================

set -e

# Enforce zero-interactive environment variables for Git/CLI tools
export CI=true
export GIT_TERMINAL_PROMPT=0
export GIT_MERGE_AUTOEDIT=no
export GIT_EDITOR=true
export GIT_PAGER=cat
export PAGER=cat
export GIT_SSH_COMMAND="ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10"

if [ "$EUID" -eq 0 ]; then
    echo "🚨 ERROR: Please run this script as 'michael' from ~ (not as root). It will invoke sudo only where needed."
    exit 1
fi

# Parse optional CLI flags
SYNC_NGINX=false
FORCE_RESET=false

while [[ "$#" -gt 0 ]]; do
    case "$1" in
        --sync-nginx)
            SYNC_NGINX=true
            ;;
        --force-reset)
            FORCE_RESET=true
            ;;
        --help|-h)
            echo "Usage: ./install-subdomains.sh [--sync-nginx] [--force-reset]"
            echo "  (default)      Idempotent mode: skips existing web roots, repos, and Nginx vhosts."
            echo "  --sync-nginx   Also copies modified Nginx .conf files (skips byte-identical ones)."
            echo "  --force-reset  Passes --force-reset to sarah-deploy.sh and updates all repos."
            exit 0
            ;;
        *)
            echo "🚨 Unknown option: $1 (use --help for usage)"
            exit 1
            ;;
    esac
    shift
done

HOME_DIR="/home/michael"
cd "$HOME_DIR"

echo "🚀 [1/5] Checking infrastructure repositories (raggiesoft-deployment-tools & nginx-config)..."
for infra_repo in "raggiesoft-deployment-tools" "nginx-config"; do
    if [ -d "$HOME_DIR/$infra_repo/.git" ]; then
        git -C "$HOME_DIR/$infra_repo" fetch origin main
        LOCAL_SHA=$(git -C "$HOME_DIR/$infra_repo" rev-parse HEAD)
        REMOTE_SHA=$(git -C "$HOME_DIR/$infra_repo" rev-parse origin/main)
        if [ "$LOCAL_SHA" = "$REMOTE_SHA" ] && [ "$FORCE_RESET" = false ]; then
            echo "   ✓ Up to date (skipped): $infra_repo"
        else
            git -C "$HOME_DIR/$infra_repo" reset --hard origin/main
            echo "   ✓ Updated to origin/main: $infra_repo"
        fi
    else
        git clone "https://github.com/raggiesoft/$infra_repo.git" "$HOME_DIR/$infra_repo"
        echo "   ✓ Cloned: $infra_repo"
    fi
done

echo "📂 [2/5] Checking /var/www subdomain directories (skipping already-populated sites)..."
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
    if [ -d "$dir" ] && [ -n "$(ls -A "$dir" 2>/dev/null)" ] && [ "$FORCE_RESET" = false ]; then
        # Directory already exists and holds live showroom files — do NOT touch file modes!
        echo "   ✓ Exists (skipped): $dir"
    elif [ -d "$dir" ] && [ "$FORCE_RESET" = false ]; then
        # Directory exists but is currently empty — ensure top-level ownership/mode without recursion
        sudo chown michael:www-data "$dir"
        sudo chmod 755 "$dir"
        echo "   ✓ Ready (empty root verified): $dir"
    else
        sudo mkdir -p "$dir"
        sudo chown michael:www-data "$dir"
        sudo chmod 755 "$dir"
        echo "   ✓ Created: $dir"
    fi
done

echo "📦 [3/5] Checking GitHub repositories in $HOME_DIR (cloning only missing projects)..."
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
        if [ "$FORCE_RESET" = true ]; then
            echo "   -> Force-updating $repo..."
            git -C "$HOME_DIR/$repo" fetch origin main
            git -C "$HOME_DIR/$repo" reset --hard origin/main
        else
            echo "   ✓ Exists (skipped — Sarah handles incremental sync): $repo"
        fi
    else
        echo "   -> Cloning new repository $repo..."
        git clone "https://github.com/raggiesoft/$repo.git" "$HOME_DIR/$repo"
    fi
done

echo "🌐 [4/5] Checking Nginx virtual host configurations..."
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

NGINX_CHANGED=false

for conf in "${VHOSTS[@]}"; do
    SRC_CONF="$HOME_DIR/nginx-config/$conf"
    AVAIL_CONF="/etc/nginx/sites-available/$conf"
    ENABLED_CONF="/etc/nginx/sites-enabled/$conf"

    if [ ! -f "$SRC_CONF" ]; then
        echo "   ⚠️ Source config missing in nginx-config (skipped): $conf"
        continue
    fi

    if [ -f "$AVAIL_CONF" ] && [ -L "$ENABLED_CONF" ]; then
        if [ "$SYNC_NGINX" = true ] || [ "$FORCE_RESET" = true ]; then
            # Compare byte-for-byte; only copy if the .conf file actually changed
            if cmp -s "$SRC_CONF" "$AVAIL_CONF"; then
                echo "   ✓ Unchanged (skipped): $conf"
            else
                sudo cp "$SRC_CONF" "$AVAIL_CONF"
                sudo ln -sf "$AVAIL_CONF" "$ENABLED_CONF"
                NGINX_CHANGED=true
                echo "   ✓ Updated changed vhost: $conf"
            fi
        else
            echo "   ✓ Exists (skipped): $conf"
        fi
    else
        sudo cp "$SRC_CONF" "$AVAIL_CONF"
        sudo ln -sf "$AVAIL_CONF" "$ENABLED_CONF"
        NGINX_CHANGED=true
        echo "   ✓ Installed & enabled new vhost: $conf"
    fi
done

if [ "$NGINX_CHANGED" = true ]; then
    sudo nginx -t
    sudo systemctl reload nginx
    echo "   ✓ Nginx configuration validated and gracefully reloaded."
else
    echo "   ✓ No Nginx vhost changes required (reload skipped)."
fi

echo "👩‍💼 [5/5] Running Sarah Autonomous Deployment..."
chmod +x "$HOME_DIR/raggiesoft-deployment-tools/sarah-deploy.sh"
if [ "$FORCE_RESET" = true ]; then
    "$HOME_DIR/raggiesoft-deployment-tools/sarah-deploy.sh" --force-reset
else
    "$HOME_DIR/raggiesoft-deployment-tools/sarah-deploy.sh"
fi

echo "=============================================================================="
echo "✅ RAGGIESOFT SUBDOMAIN PROVISIONING COMPLETE!"
echo "   • https://raggiesoft.com              (RaggieSoft Hub — PHP 8.5 + DaisyUI 5)"
echo "   • https://engineroom.raggiesoft.com   (Engine Room Records — Astro 6)"
echo "   • https://stardust.raggiesoft.com     (The Stardust Engine — Nuxt 4 + Vue 3)"
echo "   • https://corporate.raggiesoft.com    (RaggieSoft Media — Bootstrap 5.3.8)"
echo "   • https://storetrainer.raggiesoft.com (StoreTrainer — Vanilla TS + Win32)"
echo "   • https://backstage.raggiesoft.com    (RaggieSoft Backstage — Web Awesome Pro)"
echo "   • https://nebulae.raggiesoft.com      (Cosmic Visualizer)"
echo "   • https://music.raggiesoft.com        (The Listening Room — SvelteKit 2)"
echo "   • https://books.raggiesoft.com        (RaggieSoft Book Reader — PHP 8.5 SPA)"
echo "   • https://lore.raggiesoft.com         (Lore Encyclopedia — Next.js 16)"
echo "   • https://michaelpragsdale.com        (Executive Dossier — Angular 19)"
echo "=============================================================================="
