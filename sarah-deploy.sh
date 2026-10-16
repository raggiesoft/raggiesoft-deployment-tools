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

# SECURITY CHECK: SARAH REFUSES TO RUN AS ROOT
# Prevent deployment script from accidentally modifying system files or creating root-owned web assets
if [ "$EUID" -eq 0 ]; then
    echo "🚨 SARAH FATAL ERROR: I am not allowed to run as root or via sudo!"
    echo "I was designed to run autonomously as the standard user. Please drop your privileges and try again."
    exit 1
fi

FORCE_RESET=false

# Check for the nuclear override flag
# This flag bypasses hash comparisons and forces a hard Git reset and clean sync
if [ "$1" == "--force-reset" ]; then
    FORCE_RESET=true
    echo "🚨 SARAH: NUCLEAR OVERRIDE INITIATED. Forcing a clean deployment..."
fi

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

    cd "$REPO_DIR" || return

    # Fetch the latest info from GitHub without modifying working tree
    git fetch origin main

    # Compare local and remote HEAD SHAs to determine if sync is needed
    LOCAL=$(git rev-parse HEAD)
    REMOTE=$(git rev-parse origin/main)

    # Standard intelligence check
    if [ "$FORCE_RESET" = false ] && [ "$JUST_CLONED" = false ]; then
        if [ "$LOCAL" == "$REMOTE" ]; then
            # No changes detected, quietly exit function to keep cron logs clean
            return
        fi
        echo "👩‍💼 SARAH: Change detected in $SITE_NAME! Jenna pushed updates."
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
        npm run build 2>/dev/null || true
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
    echo "✅ SARAH: $SITE_NAME Deployment Complete."
}

# Helper function to keep non-webroot infrastructure repositories (nginx-config,
# raggiesoft-deployment-tools) synchronized with GitHub on the Droplet.
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

    if [ "$FORCE_RESET" = false ] && [ "$JUST_CLONED" = false ]; then
        if [ "$LOCAL" == "$REMOTE" ]; then
            return
        fi
        echo "👩‍💼 SARAH: Change detected in $REPO_LABEL! Pulling infrastructure updates."
    else
        echo "👩‍💼 SARAH: Synchronizing $REPO_LABEL infrastructure repository."
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
}

# 0. PROCESS INFRASTRUCTURE & DEPLOYMENT REPOSITORIES
sync_infra_repo "Deployment Tools" "/home/michael/raggiesoft-deployment-tools"
sync_infra_repo "Nginx Config" "/home/michael/nginx-config"

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


