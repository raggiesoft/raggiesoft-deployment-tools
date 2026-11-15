#!/bin/bash
# ==============================================================================
# SARAH: AUTONOMOUS DEPLOYMENT (v5.0 - Multi-Site Edition)
# ==============================================================================
# ARCHITECTURAL OVERVIEW:
# Sarah serves as a lightweight, cron-friendly continuous deployment orchestrator.
# She monitors a predefined list of Git repositories, pulls latest changes, and 
# rsyncs them to standard `/var/www/` web roots. She ensures correct file permissions 
# on the destination directories.
#
# FUTURE MAINTENANCE NOTES:
# - Ensure `deploy_site` handles any newly added sites.
# - RSync excludes `.git`, `.gitignore`, and `README.md` by default. If specific
#   sites need additional excludes, the deploy function signature will need to be updated.
# - DO NOT run this script as root, to prevent security escalation risks via RSync.
# ==============================================================================
# "I check for updates every 5 minutes. If Jenna pushed code, I deploy it instantly."
# NO SUDO REQUIRED.

# ZERO-INTERACTIVE / AUTOMATIC "YES" ENVIRONMENT ENFORCEMENT
export CI=true
export npm_config_yes=true
export npm_config_fund=false
export npm_config_audit=false
export npm_config_update_notifier=false
export NO_UPDATE_NOTIFIER=1
export NEXT_TELEMETRY_DISABLED=1
export __NEXT_AGENT_UPGRADE=security
export NG_CLI_ANALYTICS=false
export NG_FORCE_TTY=false
export ASTRO_TELEMETRY_DISABLED=1
export NUXT_TELEMETRY_DISABLED=1
export GIT_TERMINAL_PROMPT=0
export GIT_MERGE_AUTOEDIT=no
export GIT_EDITOR=true
export GIT_PAGER=cat
export PAGER=cat
export GIT_SSH_COMMAND="ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10"

# SECURITY CHECK: SARAH REFUSES TO RUN AS ROOT
# Prevent deployment script from accidentally modifying system files or creating root-owned web assets
if [ "$EUID" -eq 0 ]; then
    echo "🚨 SARAH FATAL ERROR: I am not allowed to run as root or via sudo!"
    echo "I was designed to run autonomously as the standard user. Please drop your privileges and try again."
    exit 1
fi

# Preserve original CLI arguments so Sarah can re-exec cleanly if she pulls an
# updated version of herself from GitHub during Step 0.
SARAH_ORIG_ARGS=("$@")

# Self-healing symlink check: ensure `/home/michael/sarah-deploy.sh` (invoked by
# `sarah.service` / `sarah.timer`) always points to the Git-tracked script in
# `/home/michael/raggiesoft-deployment-tools/sarah-deploy.sh`.
if [ -f "/home/michael/raggiesoft-deployment-tools/sarah-deploy.sh" ] && [ ! -L "/home/michael/sarah-deploy.sh" ]; then
    ln -sf "/home/michael/raggiesoft-deployment-tools/sarah-deploy.sh" "/home/michael/sarah-deploy.sh" 2>/dev/null || true
fi

FORCE_RESET=false

# Check for the nuclear override flag
# This flag bypasses hash comparisons and forces a hard Git reset and clean sync
if [ "$1" == "--force-reset" ]; then
    FORCE_RESET=true
    echo "🚨 SARAH: NUCLEAR OVERRIDE INITIATED. Forcing a clean deployment..."
fi

# Official RaggieSoft IndexNow API Key (hosted at /<INDEXNOW_KEY>.txt on every domain)
readonly INDEXNOW_KEY="726167676965736f6674696e6465786e"

# ==============================================================================
# Helper: notify_indexnow_for_webroot <web_root>
# ==============================================================================
# Reads `<loc>` entries from `$WEB_ROOT/sitemaps/*.xml` (if split sitemaps exist)
# or `$WEB_ROOT/sitemap.xml` right after `rsync` finishes populating `/var/www/*`,
# verifies that `$WEB_ROOT/$INDEXNOW_KEY.txt` is present on disk, and submits up
# to 10,000 canonical URLs to `https://api.indexnow.org/indexnow` (Bing, Yandex,
# DuckDuckGo, Naver, Seznam, Yep) with a hard 8-second timeout so cron never blocks.
function notify_indexnow_for_webroot() {
    local WEB_ROOT="$1"
    if [ ! -f "$WEB_ROOT/${INDEXNOW_KEY}.txt" ]; then
        return 0
    fi
    if ! command -v python3 >/dev/null 2>&1 || ! command -v curl >/dev/null 2>&1; then
        return 0
    fi

    local PAYLOAD
    PAYLOAD=$(python3 - "$WEB_ROOT" "$INDEXNOW_KEY" <<'PYEOF' 2>/dev/null || true
import sys, os, glob, json, urllib.parse, xml.etree.ElementTree as ET

web_root, key = sys.argv[1], sys.argv[2]
xml_files = sorted(glob.glob(os.path.join(web_root, "sitemaps", "*.xml")))
if not xml_files:
    sm = os.path.join(web_root, "sitemap.xml")
    if os.path.isfile(sm):
        xml_files = [sm]

urls = []
seen = set()
for xf in xml_files:
    try:
        root = ET.parse(xf).getroot()
        if root.tag.endswith("sitemapindex"):
            continue
        for elem in root.iter():
            if elem.tag.endswith("loc") and elem.text:
                u = elem.text.strip()
                if u and u not in seen:
                    seen.add(u)
                    urls.append(u)
    except Exception:
        pass

if not urls:
    sys.exit(0)

host = urllib.parse.urlparse(urls[0]).netloc
if not host:
    sys.exit(0)

print(json.dumps({
    "host": host,
    "key": key,
    "keyLocation": f"https://{host}/{key}.txt",
    "urlList": urls[:10000]
}))
PYEOF
)

    if [ -n "$PAYLOAD" ]; then
        local HTTP_CODE
        HTTP_CODE=$(curl -sS -o /dev/null -w "%{http_code}" --max-time 8 \
            -H "Content-Type: application/json; charset=utf-8" \
            -d "$PAYLOAD" \
            "https://api.indexnow.org/indexnow" 2>/dev/null || echo "000")
        echo "   -> IndexNow instant-crawl ping sent (HTTP $HTTP_CODE)."
    fi
}

# Sarah's deployment brain
function deploy_site() {
    # Function arguments mapping
    local SITE_NAME=$1
    local REPO_DIR=$2
    local WEB_ROOT=$3
    # If SYNC_DIR is not provided, default to the repository root
    local SYNC_DIR=${4:-$REPO_DIR}

    local JUST_CLONED=false
    # Ensure repository exists locally before attempting sync
    if [ ! -d "$REPO_DIR" ]; then
        echo "⚠️ SARAH: Repository missing at $REPO_DIR. Cloning from GitHub..."
        # Extract repo name from REPO_DIR (e.g. raggiesoft-lore)
        local REPO_BASENAME=$(basename "$REPO_DIR")
        cd "$(dirname "$REPO_DIR")" || return
        # Attempt to dynamically clone the repository based on expected naming conventions
        git clone "https://github.com/raggiesoft/$REPO_BASENAME.git"
        if [ ! -d "$REPO_DIR" ]; then
            echo "🚨 SARAH: Clone failed for $SITE_NAME."
            return
        fi
        JUST_CLONED=true
    fi

    # Detect whether the target /var/www showroom directory is missing or empty
    # (for example, right after install-subdomains.sh provisions a brand-new site)
    # so Sarah hydrates it even when LOCAL == REMOTE!
    local WEB_ROOT_EMPTY=false
    if [ ! -d "$WEB_ROOT" ] || [ -z "$(ls -A "$WEB_ROOT" 2>/dev/null)" ]; then
        WEB_ROOT_EMPTY=true
    fi

    cd "$REPO_DIR" || return

    # Fetch the latest info from GitHub without modifying working tree
    git fetch origin main

    # Compare local and remote HEAD SHAs to determine if sync is needed
    LOCAL=$(git rev-parse HEAD)
    REMOTE=$(git rev-parse origin/main)

    # Standard intelligence check
    if [ "$FORCE_RESET" = false ] && [ "$JUST_CLONED" = false ] && [ "$WEB_ROOT_EMPTY" = false ]; then
        if [ "$LOCAL" == "$REMOTE" ]; then
            # No changes detected and web root is already populated; quietly exit
            return
        fi
        echo "👩‍💼 SARAH: Change detected in $SITE_NAME! Jenna pushed updates."
    elif [ "$WEB_ROOT_EMPTY" = true ] && [ "$FORCE_RESET" = false ]; then
        echo "👩‍💼 SARAH: Empty showroom detected at $WEB_ROOT for $SITE_NAME! Hydrating initial build."
    else
        echo "👩‍💼 SARAH: Bypassing version check for $SITE_NAME. Purging local repository cache."
    fi

    # PULL UPDATES
    # Hard reset aligns the local cache perfectly with remote, discarding local edits
    git reset --hard origin/main
    if [ "$FORCE_RESET" = true ]; then
        # Clean untracked files/directories if performing a nuclear reset
        git clean -fdx
    fi

    # SELF-HEALING VERIFICATION
    # Ensure destination web root directory exists
    if [ ! -d "$WEB_ROOT" ]; then
        mkdir -p "$WEB_ROOT" 2>/dev/null
    fi

    # Fallback build if pre-compiled sync directory is missing
    if [ ! -d "$SYNC_DIR" ] && [ -f "package.json" ]; then
        echo "   -> Pre-compiled payload missing. Building $SITE_NAME static bundle..."
        yes 2>/dev/null | npm --yes run build 2>/dev/null || true
    fi

    if [ ! -d "$SYNC_DIR" ]; then
        echo "🚨 SARAH: Sync directory $SYNC_DIR not found for $SITE_NAME. Skipping deployment."
        return
    fi

    # DEPLOY
    echo "   -> Syncing $SITE_NAME to Showroom..."
    # RSync synchronizes the web root.
    # --delete removes files in destination that no longer exist in source
    # --no-o --no-g preserves current user ownership instead of attempting to copy source owner
    rsync -av --delete --no-o --no-g \
        --exclude '.git' \
        --exclude '.gitignore' \
        --exclude 'README.md' \
        "$SYNC_DIR/" "$WEB_ROOT/"

    # PERMISSIONS
    # Standardize web server permissions to 755 for directories, 644 for files
    find "$WEB_ROOT" -type d -exec chmod 755 {} +
    find "$WEB_ROOT" -type f -exec chmod 644 {} +
    notify_indexnow_for_webroot "$WEB_ROOT"
    echo "✅ SARAH: $SITE_NAME Deployment Complete."
}

# ==============================================================================
# Helper: sync_infra_repo <repo_label> <repo_dir>
# ==============================================================================
# Keeps non-webroot infrastructure repositories (`raggiesoft-deployment-tools`
# and `nginx-config`) synchronized with GitHub on `jessica.raggiesoft.com`.
# If `raggiesoft-deployment-tools` advances to a new commit on `origin/main`,
# Sarah immediately `exec`s into the newly pulled `sarah-deploy.sh` binary (once
# per invocation, guarded by `SARAH_REEXECED=1`) so new deployment logic takes
# effect on the exact same run without waiting 5 minutes for the next timer tick.
function sync_infra_repo() {
    local REPO_LABEL=$1
    local REPO_DIR=$2

    local JUST_CLONED=false
    if [ ! -d "$REPO_DIR" ]; then
        echo "⚠️ SARAH: Infrastructure repository missing at $REPO_DIR. Cloning from GitHub..."
        local REPO_BASENAME=$(basename "$REPO_DIR")
        cd "$(dirname "$REPO_DIR")" || return
        git clone "https://github.com/raggiesoft/$REPO_BASENAME.git"
        if [ ! -d "$REPO_DIR" ]; then
            echo "🚨 SARAH: Clone failed for $REPO_LABEL."
            return
        fi
        JUST_CLONED=true
    fi

    cd "$REPO_DIR" || return
    git fetch origin main

    LOCAL=$(git rev-parse HEAD)
    REMOTE=$(git rev-parse origin/main)
    local UPDATED=false

    if [ "$FORCE_RESET" = false ] && [ "$JUST_CLONED" = false ]; then
        if [ "$LOCAL" == "$REMOTE" ]; then
            return
        fi
        echo "👩‍💼 SARAH: Change detected in $REPO_LABEL! Pulling infrastructure updates."
        UPDATED=true
    else
        echo "👩‍💼 SARAH: Synchronizing $REPO_LABEL infrastructure repository."
        if [ "$LOCAL" != "$REMOTE" ] || [ "$JUST_CLONED" = true ]; then
            UPDATED=true
        fi
    fi

    git reset --hard origin/main
    if [ "$FORCE_RESET" = true ]; then
        git clean -fdx
    fi

    # Standardize permissions (755 for directories and .sh scripts, 644 for config files)
    find "$REPO_DIR" -path "$REPO_DIR/.git" -prune -o -type d -exec chmod 755 {} +
    find "$REPO_DIR" -path "$REPO_DIR/.git" -prune -o -type f -exec chmod 644 {} +
    find "$REPO_DIR" -path "$REPO_DIR/.git" -prune -o -type f -name "*.sh" -exec chmod 755 {} +
    echo "✅ SARAH: $REPO_LABEL Sync Complete."

    # Self-upgrade re-entry: if Deployment Tools just pulled a new commit and we
    # haven't re-exec'd yet in this run, replace the running bash process cleanly
    # with the newly downloaded `sarah-deploy.sh`.
    if [ "$REPO_DIR" == "/home/michael/raggiesoft-deployment-tools" ] && [ "$UPDATED" = true ] && [ "${SARAH_REEXECED:-0}" != "1" ]; then
        ln -sf "/home/michael/raggiesoft-deployment-tools/sarah-deploy.sh" "/home/michael/sarah-deploy.sh" 2>/dev/null || true
        echo "🔄 SARAH: Self-upgrade complete! Re-launching updated sarah-deploy.sh..."
        export SARAH_REEXECED=1
        exec "/home/michael/raggiesoft-deployment-tools/sarah-deploy.sh" "${SARAH_ORIG_ARGS[@]}"
    fi
}

# ==============================================================================
# Helper: sync_nginx_vhosts <nginx_repo_dir>
# ==============================================================================
# Zero-touch Nginx virtual host & web-root reconciler with atomic rollback:
#   1. Verifies passwordless `sudo -n` availability so cron NEVER blocks.
#   2. Scans `root /var/www/...;` directives across `$NGINX_REPO_DIR/*.conf` and
#      provisions any brand-new `/var/www/<site>` directory (`michael:www-data`,
#      mode `755`) while leaving already-populated web roots untouched.
#   3. Compares each `$NGINX_REPO_DIR/*.conf` byte-for-byte (`cmp -s`) against
#      `/etc/nginx/sites-available/<conf>` and verifies its `sites-enabled`
#      symlink. Returns in <2ms if zero vhost configs changed.
#   4. Snapshots current `/etc/nginx/sites-available/*.conf` and active symlinks,
#      installs changed/new `.conf` files, validates via `sudo -n nginx -t`, and
#      reloads Nginx ONLY if syntax passes 100%—otherwise automatically restores
#      the snapshot so live production traffic is never interrupted.
function sync_nginx_vhosts() {
    local NGINX_REPO_DIR="$1"
    if [ ! -d "$NGINX_REPO_DIR" ] || [ ! -d "/etc/nginx/sites-available" ]; then
        return 0
    fi

    # Never prompt interactively for sudo in autonomous cron/SSH execution
    if ! sudo -n true 2>/dev/null; then
        return 0
    fi

    shopt -s nullglob
    local CONF_FILES=("$NGINX_REPO_DIR"/*.conf)
    shopt -u nullglob
    if [ "${#CONF_FILES[@]}" -eq 0 ]; then
        return 0
    fi

    # 1. Ensure any declared /var/www/* root exists (skipping populated dirs)
    local DECLARED_ROOTS
    DECLARED_ROOTS=$(awk '$1 == "root" { gsub(/;/, "", $2); if ($2 ~ /^\/var\/www\//) print $2 }' "${CONF_FILES[@]}" | sort -u)
    while IFS= read -r web_dir; do
        [ -z "$web_dir" ] && continue
        if [ ! -d "$web_dir" ]; then
            sudo -n mkdir -p "$web_dir"
            sudo -n chown michael:www-data "$web_dir"
            sudo -n chmod 755 "$web_dir"
            echo "📂 SARAH: Provisioned new showroom directory $web_dir."
        fi
    done <<< "$DECLARED_ROOTS"

    # 2. Fast diff check across all managed .conf files
    local NEEDS_SYNC=false
    for src_conf in "${CONF_FILES[@]}"; do
        local conf_name
        conf_name=$(basename "$src_conf")
        local avail_conf="/etc/nginx/sites-available/$conf_name"
        local enabled_conf="/etc/nginx/sites-enabled/$conf_name"
        if [ ! -f "$avail_conf" ] || [ ! -L "$enabled_conf" ] || ! cmp -s "$src_conf" "$avail_conf"; then
            NEEDS_SYNC=true
            break
        fi
    done

    if [ "$NEEDS_SYNC" = false ]; then
        return 0
    fi

    echo "🌐 SARAH: Detected Nginx virtual host updates! Staging atomic sync..."
    local BACKUP_DIR
    BACKUP_DIR=$(mktemp -d /tmp/sarah-nginx-backup.XXXXXX)
    mkdir -p "$BACKUP_DIR/sites-available" "$BACKUP_DIR/sites-enabled"

    # Snapshot only the managed vhost files and symlinks before applying updates
    for src_conf in "${CONF_FILES[@]}"; do
        local conf_name
        conf_name=$(basename "$src_conf")
        if [ -f "/etc/nginx/sites-available/$conf_name" ]; then
            cp -p "/etc/nginx/sites-available/$conf_name" "$BACKUP_DIR/sites-available/$conf_name"
        fi
        if [ -L "/etc/nginx/sites-enabled/$conf_name" ]; then
            touch "$BACKUP_DIR/sites-enabled/$conf_name"
        fi
    done

    # Apply new or modified virtual host configurations
    for src_conf in "${CONF_FILES[@]}"; do
        local conf_name
        conf_name=$(basename "$src_conf")
        local avail_conf="/etc/nginx/sites-available/$conf_name"
        local enabled_conf="/etc/nginx/sites-enabled/$conf_name"
        if [ ! -f "$avail_conf" ] || ! cmp -s "$src_conf" "$avail_conf"; then
            sudo -n cp "$src_conf" "$avail_conf"
            sudo -n chmod 644 "$avail_conf"
            echo "   -> Installed Nginx vhost: $conf_name"
        fi
        if [ ! -L "$enabled_conf" ]; then
            sudo -n ln -sf "$avail_conf" "$enabled_conf"
            echo "   -> Enabled Nginx vhost symlink: $conf_name"
        fi
    done

    # Validate Nginx syntax BEFORE reloading; roll back atomically on any error
    if sudo -n nginx -t >/dev/null 2>&1; then
        sudo -n systemctl reload nginx
        echo "✅ SARAH: Nginx configuration validated (nginx -t OK) and gracefully reloaded."
    else
        echo "🚨 SARAH: nginx -t FAILED! Rolling back virtual host changes to protect live traffic..."
        sudo -n nginx -t || true
        for src_conf in "${CONF_FILES[@]}"; do
            local conf_name
            conf_name=$(basename "$src_conf")
            if [ -f "$BACKUP_DIR/sites-available/$conf_name" ]; then
                sudo -n cp "$BACKUP_DIR/sites-available/$conf_name" "/etc/nginx/sites-available/$conf_name"
            else
                sudo -n rm -f "/etc/nginx/sites-available/$conf_name"
            fi
            if [ -f "$BACKUP_DIR/sites-enabled/$conf_name" ]; then
                sudo -n ln -sf "/etc/nginx/sites-available/$conf_name" "/etc/nginx/sites-enabled/$conf_name"
            else
                sudo -n rm -f "/etc/nginx/sites-enabled/$conf_name"
            fi
        done
        echo "🛡️ SARAH: Rollback complete; existing live Nginx configuration preserved."
    fi

    rm -rf "$BACKUP_DIR"
}

# 0. PROCESS INFRASTRUCTURE & DEPLOYMENT REPOSITORIES
sync_infra_repo "Deployment Tools" "/home/michael/raggiesoft-deployment-tools"
sync_infra_repo "Nginx Config" "/home/michael/nginx-config"
sync_nginx_vhosts "/home/michael/nginx-config"

# 1. PROCESS RAGGIESOFT HUB
deploy_site "Hub" "/home/michael/raggiesoft-hub" "/var/www/raggiesoft.com"

# 2. PROCESS NEBULAE INCUBATOR
deploy_site "Nebulae" "/home/michael/raggiesoft-nebulae" "/var/www/nebulae.raggiesoft.com"

# 3. PROCESS STARDUST ENGINE LIBRARY
deploy_site "Books" "/home/michael/raggiesoft-book-library" "/var/www/raggiesoft-book-library"

# 4. PROCESS LORE GRAPH
# Uses a specific sub-directory (out) as the deployment payload instead of the repo root
deploy_site "Lore" "/home/michael/raggiesoft-lore" "/var/www/lore.raggiesoft.com" "/home/michael/raggiesoft-lore/out"

# 5. PROCESS ENGINE ROOM RECORDS (MUSIC)
# Syncs the pre-compiled SvelteKit static bundle (/build) into /var/www/music.raggiesoft.com
deploy_site "Music" "/home/michael/raggiesoft-music" "/var/www/music.raggiesoft.com" "/home/michael/raggiesoft-music/build"

# 6. PROCESS EXECUTIVE SYSTEMS ARCHITECT DOSSIER (PORTFOLIO - michaelpragsdale.com)
# Syncs the pre-compiled Angular 19 Zoneless browser bundle into /var/www/michaelpragsdale.com
deploy_site "Portfolio" "/home/michael/raggiesoft-portfolio" "/var/www/michaelpragsdale.com" "/home/michael/raggiesoft-portfolio/dist/raggiesoft-portfolio/browser"

# 7. PROCESS ENGINE ROOM RECORDS IMPRINT (engineroom.raggiesoft.com)
# Syncs the pre-compiled Astro 6 static bundle (/dist) into /var/www/engineroom.raggiesoft.com
deploy_site "Engine Room Records" "/home/michael/raggiesoft-engine-room-records" "/var/www/engineroom.raggiesoft.com" "/home/michael/raggiesoft-engine-room-records/dist"

# 8. PROCESS THE STARDUST ENGINE (stardust.raggiesoft.com)
# Syncs the pre-compiled Nuxt 4 + Vue 3 static bundle (/.output/public) into /var/www/stardust.raggiesoft.com
deploy_site "The Stardust Engine" "/home/michael/raggiesoft-stardust-engine" "/var/www/stardust.raggiesoft.com" "/home/michael/raggiesoft-stardust-engine/.output/public"

# 9. PROCESS RAGGIESOFT MEDIA CORPORATE HUB (corporate.raggiesoft.com)
# Syncs the pre-compiled Bootstrap 5.3.8 static bundle (/dist) into /var/www/corporate.raggiesoft.com
deploy_site "RaggieSoft Media" "/home/michael/raggiesoft-corporate" "/var/www/corporate.raggiesoft.com" "/home/michael/raggiesoft-corporate/dist"

# 10. PROCESS RAGGIESOFT STORETRAINER (storetrainer.raggiesoft.com)
# Syncs the pre-compiled Vanilla TypeScript + Classic Win32/Netscape 4.78 static bundle (/dist) into /var/www/storetrainer.raggiesoft.com
deploy_site "StoreTrainer" "/home/michael/raggiesoft-storetrainer" "/var/www/storetrainer.raggiesoft.com" "/home/michael/raggiesoft-storetrainer/dist"

# 11. PROCESS RAGGIESOFT BACKSTAGE (backstage.raggiesoft.com)
# Syncs the pre-compiled Web Awesome Pro + Font Awesome Pro+ PWA static bundle (/dist) into /var/www/backstage.raggiesoft.com
deploy_site "Backstage" "/home/michael/raggiesoft-backstage" "/var/www/backstage.raggiesoft.com" "/home/michael/raggiesoft-backstage/dist"


