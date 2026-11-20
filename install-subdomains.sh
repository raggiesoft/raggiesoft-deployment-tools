#!/bin/bash
# ==============================================================================
# Architectural Block: install-subdomains.sh (Idempotent "Skip Existing" Edition)
# ==============================================================================
# PLAIN-ENGLISH OVERVIEW (100-LEVEL INTRO):
#   What does **"idempotent"** mean in computer science & DevOps?
#   An operation is *idempotent* if running it once, twice, or ten times produces
#   the exact same valid server state without breaking or redoing things that
#   are already working!
#
#   When we launch a brand-new RaggieSoft subdomain (like `backstage.raggiesoft.com`)
#   or bootstrap a fresh Ubuntu Droplet (`142.93.244.239`), `install-subdomains.sh`
#   runs on the server as user `michael` and walks a 5-step checklist—skipping
#   every folder, repo, and Nginx config that already exists while provisioning
#   ONLY what is missing:
#     1. Pulls `raggiesoft-deployment-tools` and `nginx-config`.
#     2. Creates any missing `/var/www/<site>` directories (`michael:www-data`, `755`)
#        while leaving already-populated live web roots 100% untouched.
#     3. Clones any missing `/home/michael/raggiesoft-*` GitHub repos.
#     4. Installs & symlinks any missing `/etc/nginx/sites-available/*.conf` virtual
#        hosts (or updates modified ones with `--sync-nginx`), testing `nginx -t`
#        before gracefully reloading Nginx.
#     5. Calls `sarah-deploy.sh` to hydrate any newly created empty web roots!
#
# CLI Flags (100% Non-Interactive — Never Prompts Aside From OS `sudo` Auth):
#   ./install-subdomains.sh                 # Default: provision ONLY missing sites/vhosts
#   ./install-subdomains.sh --sync-nginx    # Also update changed Nginx .conf files
#   ./install-subdomains.sh --force-reset   # Force full re-sync of all repos & web roots
# ==============================================================================

# Exit immediately if any command returns a non-zero error code
set -e

# Enforce zero-interactive environment variables so `git` and `ssh` never block on prompts
export CI=true
export GIT_TERMINAL_PROMPT=0
export GIT_MERGE_AUTOEDIT=no
export GIT_EDITOR=true
export GIT_PAGER=cat
export PAGER=cat
export GIT_SSH_COMMAND="ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10"

# Guard against running the entire script as `root` (`EUID == 0`); we run as `michael`
# so cloned Git repos in `/home/michael/` belong to `michael`, using `sudo` only for `/var/www` & `/etc/nginx`!
if [ "$EUID" -eq 0 ]; then
    echo "🚨 ERROR: Please run this script as 'michael' from ~ (not as root). It will invoke sudo only where needed."
    exit 1
fi

# Parse optional CLI flags via `while [[ "$#" -gt 0 ]]` + `shift`
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

# ==============================================================================
# STEP 1/5: SYNC INFRASTRUCTURE REPOSITORIES
# ==============================================================================
# HOW `git -C <path>` WORKS:
#   `git -C "/some/folder" fetch` tells Git to run inside `/some/folder` WITHOUT
#   changing our current shell's working directory (`cd`), keeping loops super clean!
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

# ==============================================================================
# STEP 2/5: PROVISION `/var/www/*` DOCUMENT ROOTS
# ==============================================================================
# Assigns `michael:www-data` ownership (user `michael` writes files via Sarah;
# group `www-data` lets Nginx read them) ONLY on missing or empty folders!
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

# ==============================================================================
# STEP 3/5: CLONE MISSING GITHUB APPLICATION REPOSITORIES
# ==============================================================================
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

# ==============================================================================
# STEP 4/5: INSTALL & SYMLINK NGINX VIRTUAL HOSTS
# ==============================================================================
# HOW UBUNTU NGINX `sites-available` vs `sites-enabled` WORKS:
#   - `/etc/nginx/sites-available/*.conf` stores all virtual-host config files.
#   - `/etc/nginx/sites-enabled/*.conf` holds symbolic links (`ln -sf`) pointing
#     to the active ones! Nginx only serves sites linked inside `sites-enabled/`.
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
            # `cmp -s` compares two files byte-for-byte silently; returns `0` (true) if 100% identical!
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

# Validate syntax (`sudo nginx -t`) BEFORE `systemctl reload nginx` (because `set -e` is active,
# a failed `nginx -t` aborts immediately before `reload` is ever called!).
if [ "$NGINX_CHANGED" = true ]; then
    sudo nginx -t
    sudo systemctl reload nginx
    echo "   ✓ Nginx configuration validated and gracefully reloaded."
else
    echo "   ✓ No Nginx vhost changes required (reload skipped)."
fi

# ==============================================================================
# STEP 5/5: HAND OFF TO SARAH FOR INCREMENTAL WEB ROOT HYDRATION
# ==============================================================================
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
