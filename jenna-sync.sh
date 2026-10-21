#!/bin/bash

# ============================================================================
# Architectural Block: jenna-sync.sh
# ============================================================================
# This script ("Jenna") is the central Deployment & Synchronization Liaison for the 
# entire Raggiesoft platform. It handles pulling, auditing, building, and pushing 
# code across multiple Git repositories and syncing heavy assets to DigitalOcean Spaces.
#
# Key Responsibilities:
# 1. Multi-Repo Orchestration: Clones, pulls, and pushes updates to 'raggiesoft-hub', 
#    'stardust-engine-cms', 'raggiesoft-narratives', 'raggiesoft-nebulae', etc.
# 2. Asset Synchronization: Uses `rclone` to push/pull binaries to a remote CDN (do-spaces).
# 3. Build & Minification: Executes local PHP scripts to minify CSS/JS and compile static assets.
# 4. QA & Auditing: Runs PHP-based tests (Integrity Check, Orphan Audit) before allowing a push.
# 5. Evasion Tactics: Includes a `--public-wifi` stealth mode to bypass restrictive firewalls (port 443).
#
# Maintenance Notes:
# - Do NOT execute this script locally unless you are preparing a full production sync.
# - Rclone dependencies: Requires a valid `rclone.conf` inside `build-tools/rclone/`.
# - PHP dependencies: Heavily relies on local CLI PHP to run the embedded QA scripts and build tools.
# - DO NOT force push (`--force`) unless recovering from a catastrophic git desync.
# ============================================================================

# --- JENNA: THE DEVELOPMENT LIAISON (v7.3 - Force Push Edition) ---
# Usage: ./jenna-sync.sh --push -m "Message" [-t "v1.0.0"] [--force] [--public-wifi]
#        ./jenna-sync.sh --pull [--public-wifi]

# --- OS-SPECIFIC OVERRIDES ---
# If running on macOS (darwin) and `caffeinate` is available, ensure the system doesn't sleep during long syncs.
if [[ "$OSTYPE" == "darwin"* ]] && command -v caffeinate > /dev/null; then
    # If we are not already wrapped, re-execute the script inside caffeinate
    if [ "$1" != "--caffeinated" ]; then
        echo "☕ JENNA: Pouring a cup of joe to keep the Mac awake during sync..."
        exec caffeinate -im "$0" --caffeinated "$@"
    fi
    # If we are wrapped, shift out the internal flag so the rest of the script functions normally
    if [ "$1" == "--caffeinated" ]; then
        shift
    fi
fi


# 1. ESTABLISH PATHS (Dynamically resolved across OS)
# Note: jenna-sync.sh now resides in /raggiesoft-deployment-tools (1 level below SERVER_ROOT).
WORKSPACE_DIR=$(cd "$(dirname "$0")" && pwd)
SERVER_ROOT=$(cd "$WORKSPACE_DIR/.." && pwd)
ASSETS_ROOT="$SERVER_ROOT/raggiesoft-assets"

HUB_ROOT="$SERVER_ROOT/raggiesoft.com/www"
CMS_ROOT="$SERVER_ROOT/stardust-engine-cms"
NARRATIVES_ROOT="$SERVER_ROOT/raggiesoft-narratives"
NEBULAE_ROOT="$SERVER_ROOT/raggiesoft.com/subdomains/nebulae"
BOOKS_ROOT="$SERVER_ROOT/raggiesoft.com/subdomains/books"
LORE_ROOT="$SERVER_ROOT/raggiesoft.com/subdomains/lore"
MUSIC_ROOT="$SERVER_ROOT/raggiesoft.com/subdomains/music"
ENGINEROOM_ROOT="$SERVER_ROOT/raggiesoft.com/subdomains/engineroom"
STARDUST_ROOT="$SERVER_ROOT/raggiesoft.com/subdomains/stardust"
CORPORATE_ROOT="$SERVER_ROOT/raggiesoft.com/subdomains/corporate"
STORETRAINER_ROOT="$SERVER_ROOT/raggiesoft.com/subdomains/storetrainer"
PORTFOLIO_ROOT="$SERVER_ROOT/michaelpragsdale.com/www"
DEPLOYMENT_TOOLS_ROOT="$SERVER_ROOT/raggiesoft-deployment-tools"
NGINX_CONFIG_ROOT="$SERVER_ROOT/nginx-config"
LOGS_DIR="$WORKSPACE_DIR/logs"

# 2. DETECT RCLONE
RCLONE_BIN=""
RCLONE_CONF="$WORKSPACE_DIR/build-tools/rclone/rclone.conf"

if [[ "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" ]]; then
    if [ -f "$WORKSPACE_DIR/build-tools/rclone/rclone.exe" ]; then
        RCLONE_BIN="$WORKSPACE_DIR/build-tools/rclone/rclone.exe"
    else
        echo "👱‍♀️ JENNA: I can't find rclone.exe! Check build-tools?"
        exit 1
    fi
else
    if command -v rclone &> /dev/null; then
        RCLONE_BIN="rclone"
    elif [ -f "$WORKSPACE_DIR/build-tools/rclone/rclone" ]; then
        RCLONE_BIN="$WORKSPACE_DIR/build-tools/rclone/rclone"
    else
        echo "👱‍♀️ JENNA: I can't find the rclone binary anywhere!"
        exit 1
    fi
fi

if [ ! -f "$RCLONE_CONF" ]; then
    echo "👱‍♀️ JENNA: Uh oh, I'm missing my credentials (rclone.conf)!"
    exit 1
fi

# 3. JENNA'S BRAIN (Functions)

# Global Connectivity State Flags (Populated by 5-second pre-flight probes)
CAN_PUSH_GITHUB=true
CAN_SYNC_CDN=true

# ============================================================================
# Helper: run_with_timeout <seconds> <command...>
# ============================================================================
# Executes a command in its own process group with a strict OS-level SIGKILL (-9)
# timer enforced by /usr/bin/perl. Unlike user-space flags (--timeout), this
# guarantees that blackholed DNS or TLS handshakes on restrictive public WiFi
# networks terminate at the exact <seconds> mark even for Go binaries (rclone).
function run_with_timeout() {
    local secs="$1"
    shift
    /usr/bin/perl -e '
        my $t = shift @ARGV;
        my $pid = fork();
        if ($pid == 0) { setpgrp(0, 0); exec @ARGV; exit 127; }
        local $SIG{ALRM} = sub { kill -9, $pid; exit 124; };
        alarm $t;
        waitpid($pid, 0);
        alarm 0;
        exit($? >> 8);
    ' "$secs" "$@"
}

# ============================================================================
# Helper: run_github_preflight (5-Second Automatic GitHub Probe)
# ============================================================================
# Probes GitHub reachability within 5 seconds without needing --public-wifi:
# 1. Tests standard SSH on Port 22 (unless --public-wifi already forced Port 443).
# 2. If Port 22 is blocked/timed out, automatically falls back to SSH over Port 443
#    (ssh.github.com:443) and tests within 5 seconds.
# 3. Also tests HTTPS git reachability within 5 seconds.
# 4. If unreachable, sets CAN_PUSH_GITHUB=false so Jenna still builds and commits
#    locally while cleanly skipping network git push/pull/fetch commands.
function run_github_preflight() {
    echo "👱‍♀️ JENNA: Running 5-second GitHub pre-flight check..."
    export GIT_HTTP_LOW_SPEED_LIMIT=1000
    export GIT_HTTP_LOW_SPEED_TIME=5

    local ssh_ok=false
    if [ "$USE_PUBLIC_WIFI" != true ]; then
        local out22
        out22=$(run_with_timeout 5 ssh -T -o BatchMode=yes -o ConnectTimeout=4 -o StrictHostKeyChecking=accept-new git@github.com 2>&1)
        if echo "$out22" | grep -qi "successfully authenticated"; then
            ssh_ok=true
            echo "      ✓ GitHub SSH (Port 22) reachable."
        fi
    fi

    if [ "$ssh_ok" = false ]; then
        local out443
        out443=$(run_with_timeout 5 ssh -T -p 443 -o HostName=ssh.github.com -o BatchMode=yes -o ConnectTimeout=4 -o StrictHostKeyChecking=accept-new git@github.com 2>&1)
        if echo "$out443" | grep -qi "successfully authenticated"; then
            export GIT_SSH_COMMAND="ssh -o Port=443 -o HostName=ssh.github.com -o StrictHostKeyChecking=accept-new -o ConnectTimeout=5"
            ssh_ok=true
            echo "      ✓ GitHub SSH auto-routed over Port 443 (ssh.github.com:443)."
        fi
    fi

    local https_ok=false
    if run_with_timeout 5 command git ls-remote --heads https://github.com/raggiesoft/raggiesoft-narratives.git main >/dev/null 2>&1; then
        https_ok=true
        echo "      ✓ GitHub HTTPS (Port 443) reachable."
    fi

    if [ "$ssh_ok" = true ] || [ "$https_ok" = true ]; then
        CAN_PUSH_GITHUB=true
    else
        CAN_PUSH_GITHUB=false
        echo "⚠️  JENNA PRE-FLIGHT: GitHub did not respond within 5 seconds on this network."
        echo "      -> Local builds and Git commits will still run; remote pushes will be skipped."
    fi
}

# ============================================================================
# Helper: run_cdn_preflight (5-Second Automatic DigitalOcean Spaces Probe)
# ============================================================================
# Tests whether DigitalOcean Spaces (nyc3.digitaloceanspaces.com) can complete
# a single top-level bucket listing within 5 seconds. If the current WiFi
# firewall blackholes S3/Spaces traffic, kills the probe at 5.0s and sets
# CAN_SYNC_CDN=false so rclone never hangs indefinitely.
function run_cdn_preflight() {
    echo "👱‍♀️ JENNA: Running 5-second DigitalOcean Spaces CDN pre-flight check..."
    if run_with_timeout 5 "$RCLONE_BIN" lsf do-spaces:assets.raggiesoft.com \
        --max-depth 1 \
        --config "$RCLONE_CONF" \
        --contimeout=4s \
        --timeout=4s \
        --retries=1 \
        --low-level-retries=1 \
        --bind 0.0.0.0 \
        --disable-http2 \
        --user-agent "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36" >/dev/null 2>&1; then
        CAN_SYNC_CDN=true
        echo "      ✓ DigitalOcean Spaces CDN reachable (<5s)."
    else
        CAN_SYNC_CDN=false
        echo "⚠️  JENNA PRE-FLIGHT: DigitalOcean Spaces blocked or timed out (>5s) on this WiFi."
        echo "      -> Skipping rclone CDN sync (will sync automatically next time Spaces is reachable)."
    fi
}

# ============================================================================
# Wrapper: git (Guards network git subcommands with pre-flight & timeout)
# ============================================================================
# Local git operations (add, commit, status, diff-index, tag, log, rev-parse)
# execute directly via `command git`. Remote network operations (push, pull,
# fetch, clone, ls-remote) check CAN_PUSH_GITHUB first so offline/restricted
# WiFi runs never hang.
function git() {
    case "$1" in
        push|pull|fetch|clone|ls-remote)
            if [ "$CAN_PUSH_GITHUB" != true ]; then
                echo "      ⚠️  [GitHub Unreachable] Skipping 'git $*' (saved locally)."
                return 0
            fi
            command git "$@"
            ;;
        *)
            command git "$@"
            ;;
    esac
}

function show_help() {
    echo "Usage: "
    echo "  ./jenna-sync.sh --push -m \"Commit Message\" [-t \"v1.0.0\"] [--force]"
    echo "  ./jenna-sync.sh --pull"
    echo "  ./jenna-sync.sh --audit"
    echo "Options: --public-wifi (Stealth mode)"
}

function run_integrity_check() {
    echo "👱‍♀️ JENNA: QA Protocol Initiated..."
    (
        cd "$WORKSPACE_DIR" && php -r "
            \$hubRoot = realpath('../raggiesoft.com/www') ?: realpath('../raggiesoft-hub');
            if (!\$hubRoot || !is_dir(\$hubRoot)) { exit(1); }
            \$hasErrors = false;
            \$pattern = \$hubRoot . '/data/routes/*.json';
            \$files = glob(\$pattern);
            if (empty(\$files)) { exit(1); }

            foreach(\$files as \$f) {
                \$filename = basename(\$f);
                \$data = json_decode(file_get_contents(\$f), true);
                if (json_last_error() !== JSON_ERROR_NONE) { \$hasErrors = true; continue; }

                foreach(\$data as \$route => \$config) {
                    if (isset(\$config['navbarBrandLogo']) && !empty(\$config['navbarBrandLogo'])) {
                        if (!isset(\$config['navbarBrandAlt']) || empty(trim(\$config['navbarBrandAlt']))) {
                            echo \"❌ WCAG FAIL: [\$filename] Route '\$route' missing Alt Text!\n\";
                            \$hasErrors = true;
                        }
                    }
                    if (isset(\$config['view'])) {
                        \$viewPath = \$hubRoot . '/' . \$config['view'] . '.php';
                        if (!file_exists(str_replace('/', DIRECTORY_SEPARATOR, \$viewPath))) {
                            echo \"❌ 404 FAIL:  [\$filename] Route '\$route' missing PHP file.\n\";
                            \$hasErrors = true;
                        }
                    }
                }
            }
            if (\$hasErrors) { exit(1); }
            exit(0); 
        "
    )
    if [ $? -ne 0 ]; then
        echo "🛑 JENNA: INTEGRITY CHECK FAILED."
        exit 1
    else
        echo "✅ JENNA: Integrity check passed. Proceeding..."
    fi
}

function run_orphan_audit() {
    echo "👱‍♀️ JENNA: Starting Orphaned Page Audit..."
    if [ ! -d "$LOGS_DIR" ]; then mkdir -p "$LOGS_DIR"; fi
    
    TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
    PRETTY_DATE=$(date +"%Y-%m-%d %H:%M:%S")

    (
        cd "$WORKSPACE_DIR" && php -r "
            \$timestamp = \$argv[1];
            \$prettyDate = \$argv[2];
            \$hubRoot = realpath('../raggiesoft.com/www') ?: realpath('../raggiesoft-hub');
            \$logsDir = __DIR__ . '/logs'; 
            
            \$definedViews = [];
            \$routesDir = \$hubRoot . '/data/routes';
            
            if (is_dir(\$routesDir)) {
                \$iterator = new RecursiveIteratorIterator(new RecursiveDirectoryIterator(\$routesDir));
                foreach (\$iterator as \$file) {
                    if (\$file->isFile() && strtolower(\$file->getExtension()) === 'json') {
                        \$json = json_decode(file_get_contents(\$file->getPathname()), true);
                        if (is_array(\$json)) {
                            if (isset(\$json['common'])) {
                                \$common = \$json['common'];
                                unset(\$json['common']);
                                foreach (\$json as \$k => \$v) { \$json[\$k] = array_merge(\$common, \$v); }
                            }
                            foreach (\$json as \$route => \$config) {
                                if (isset(\$config['view'])) {
                                    \$definedViews[] = str_replace(['\\\\', '/'], '/', \$config['view']);
                                } else {
                                    \$potentialPath = 'pages' . \$route; 
                                    \$potentialPath = str_replace('//', '/', \$potentialPath);
                                    \$absCheck = \$hubRoot . '/' . \$potentialPath;
                                    if (file_exists(\$absCheck . '.php')) {
                                        \$definedViews[] = \$potentialPath;
                                    } elseif (is_dir(\$absCheck)) {
                                        if (file_exists(\$absCheck . '/overview.php')) {
                                            \$definedViews[] = \$potentialPath . '/overview';
                                        } elseif (file_exists(\$absCheck . '/home.php')) {
                                            \$definedViews[] = \$potentialPath . '/home';
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            \$definedViews = array_unique(\$definedViews);

            \$pagesDir = \$hubRoot . '/pages';
            \$orphans = []; \$drafts = []; \$exposed = [];

            if (is_dir(\$pagesDir)) {
                \$iterator = new RecursiveIteratorIterator(new RecursiveDirectoryIterator(\$pagesDir));
                foreach (\$iterator as \$file) {
                    if (\$file->isFile() && strtolower(\$file->getExtension()) === 'php') {
                        \$fullPath = str_replace('\\\\', '/', \$file->getPathname());
                        \$rootPath = str_replace('\\\\', '/', \$hubRoot);
                        \$relativePath = ltrim(str_replace(\$rootPath, '', \$fullPath), '/');
                        \$viewId = preg_replace('/\.php$/', '', \$relativePath);
                        
                        if (strpos(\$viewId, 'template') !== false) continue;
                        if (strpos(\$viewId, 'errors/') !== false) continue;

                        \$content = file_get_contents(\$file->getPathname());
                        \$title = '(No H1 Found)';
                        if (preg_match('/<h1[^>]*>(.*?)<\/h1>/si', \$content, \$matches)) {
                            \$title = trim(strip_tags(\$matches[1]));
                            \$title = preg_replace('/\s+/', ' ', \$title);
                        }

                        \$entry = ['dir' => dirname(\$relativePath), 'file' => basename(\$relativePath), 'title' => \$title];
                        
                        \$isLinked = in_array(\$viewId, \$definedViews);
                        \$isDraft = (stripos(\$content, 'JENNA: DRAFT') !== false);

                        if (\$isLinked && \$isDraft) { \$exposed[] = \$entry; }
                        elseif (!\$isLinked && \$isDraft) { \$drafts[] = \$entry; }
                        elseif (!\$isLinked && !\$isDraft) { \$orphans[] = \$entry; }
                    }
                }
            }

            if (count(\$orphans) + count(\$drafts) + count(\$exposed) > 0) {
                \$filename = \$timestamp . '_Jenna_Audit_Report.txt';
                \$logPath = \$logsDir . '/' . \$filename;
                
                \$output = \"JENNA'S PAGE AUDIT REPORT\nGenerated: \" . \$prettyDate . \"\nSummary:   \" . count(\$orphans) . \" Orphans | \" . count(\$drafts) . \" EXPOSED\n\n\";
                
                if (!empty(\$exposed)) {
                    \$output .= \"🚨 EXPOSED DRAFTS (Linked!)\n=================\n\";
                    foreach (\$exposed as \$e) { \$output .= \$e['file'] . \" (\" . \$e['title'] . \")\n\"; }
                    echo \"🚨 JENNA ALERT: Found \" . count(\$exposed) . \" EXPOSED Drafts!\n\";
                }
                if (!empty(\$drafts)) {
                    \$output .= \"\n🚧 DETECTED DRAFTS\n=================\n\";
                    foreach (\$drafts as \$d) { \$output .= \$d['file'] . \" (\" . \$d['title'] . \")\n\"; }
                }
                if (!empty(\$orphans)) {
                    \$output .= \"\n⚠️ ORPHANED PAGES\n=================\n\";
                    foreach (\$orphans as \$o) { \$output .= \$o['file'] . \" (\" . \$o['title'] . \")\n\"; }
                }
                file_put_contents(\$logPath, \$output);
                echo \"⚠️  Audit found items. Report saved to: /logs/\" . \$filename . \"\n\";
            } else {
                echo \"✅ JENNA: Clean ship! No orphans, drafts, or exposed files.\n\";
            }
        " -- "$TIMESTAMP" "$PRETTY_DATE"
    )
}

function generate_sitemap() {
    echo "👱‍♀️ JENNA: Generating XML Sitemap and robots.txt..."
    (
        cd "$WORKSPACE_DIR" && php -r "
            \$hubRoot = realpath('../raggiesoft.com/www') ?: realpath('../raggiesoft-hub');
            if (!\$hubRoot || !is_dir(\$hubRoot)) {
                echo '      ❌ ERROR: Could not resolve Hub directory path.' . PHP_EOL;
                exit(1);
            }
            
            \$routesDir = \$hubRoot . '/data/routes';
            \$sitemapPath = \$hubRoot . '/sitemap.xml';
            \$robotsPath = \$hubRoot . '/robots.txt';
            
            \$urls = [];
            
            if (is_dir(\$routesDir)) {
                \$iterator = new RecursiveIteratorIterator(new RecursiveDirectoryIterator(\$routesDir));
                foreach (\$iterator as \$file) {
                    if (\$file->isFile() && strtolower(\$file->getExtension()) === 'json') {
                        \$jsonContent = file_get_contents(\$file->getPathname());
                        \$json = json_decode(\$jsonContent, true);
                        if (json_last_error() === JSON_ERROR_NONE && is_array(\$json)) {
                            foreach (\$json as \$route => \$config) {
                                if (\$route !== 'common' && strpos(\$route, '/') === 0 && empty(\$config['redirect'])) {
                                    \$urls[] = 'https://raggiesoft.com' . \$route;
                                }
                            }
                        }
                    }
                }
            }
            
            \$urls = array_unique(\$urls);
            
            \$xml = '<?xml version=\"1.0\" encoding=\"UTF-8\"?>' . PHP_EOL;
            \$xml .= '<urlset xmlns=\"http://www.sitemaps.org/schemas/sitemap/0.9\">' . PHP_EOL;
            
            foreach (\$urls as \$url) {
                \$xml .= '  <url>' . PHP_EOL . '    <loc>' . htmlspecialchars(\$url) . '</loc>' . PHP_EOL . '  </url>' . PHP_EOL;
            }
            \$xml .= '</urlset>';
            
            file_put_contents(\$sitemapPath, \$xml);
            
            \$robotsContent = 'User-agent: *' . PHP_EOL . 'Sitemap: https://raggiesoft.com/sitemap.xml' . PHP_EOL;
            file_put_contents(\$robotsPath, \$robotsContent);
            
            echo '      ✓ Generated sitemap.xml with ' . count(\$urls) . ' dynamic routes.' . PHP_EOL;
            echo '      ✓ Generated robots.txt pointer.' . PHP_EOL;
        "
    )
}

function do_pull() {
    echo "👱‍♀️ JENNA: On it! Bringing everything down to your machine..."
    echo "          $CONNECTION_MSG"
    run_github_preflight
    
    echo "   1. Checking the Hub (raggiesoft.com/www)..."
    if [ -d "$HUB_ROOT" ]; then cd "$HUB_ROOT" && git pull origin main; fi
    
    echo "   2. Checking the Assets (Workspace)..."
    cd "$ASSETS_ROOT" && git pull origin main
    
    echo "   3. Checking the Stardust Engine CMS..."
    if [ -d "$CMS_ROOT" ]; then cd "$CMS_ROOT" && git pull origin main; fi

    echo "   4. Checking the Narratives..."
    if [ ! -d "$NARRATIVES_ROOT" ]; then
        echo "      > Repository missing. Cloning CC BY-SA 4.0 Narratives from GitHub..."
        cd "$SERVER_ROOT" && git clone https://github.com/raggiesoft/raggiesoft-narratives.git "$NARRATIVES_ROOT"
    else
        cd "$NARRATIVES_ROOT" && git pull origin main
    fi

    echo "   5. Checking the Nebulae Incubator (nebulae.raggiesoft.com)..."
    if [ ! -d "$NEBULAE_ROOT" ]; then
        echo "      > Repository missing. Cloning Nebulae from GitHub..."
        mkdir -p "$(dirname "$NEBULAE_ROOT")"
        git clone https://github.com/raggiesoft/raggiesoft-nebulae.git "$NEBULAE_ROOT"
    else
        cd "$NEBULAE_ROOT" && git pull origin main
    fi

    echo "   5.4 Checking the Book Library (books.raggiesoft.com)..."
    if [ ! -d "$BOOKS_ROOT" ]; then
        echo "      > Repository missing. Cloning Books from GitHub..."
        mkdir -p "$(dirname "$BOOKS_ROOT")"
        git clone https://github.com/raggiesoft/raggiesoft-book-library.git "$BOOKS_ROOT"
    else
        cd "$BOOKS_ROOT" && git pull origin main
    fi
    
    echo "   5.5 Checking the Lore Graph (lore.raggiesoft.com)..."
    if [ ! -d "$LORE_ROOT" ]; then
        echo "      > Repository missing. Cloning Lore from GitHub..."
        mkdir -p "$(dirname "$LORE_ROOT")"
        git clone https://github.com/raggiesoft/raggiesoft-lore.git "$LORE_ROOT"
    else
        cd "$LORE_ROOT" && git pull origin main
    fi

    echo "   5.6 Checking The Listening Room (music.raggiesoft.com)..."
    if [ ! -d "$MUSIC_ROOT" ]; then
        echo "      > Repository missing. Cloning Music Site from GitHub..."
        mkdir -p "$(dirname "$MUSIC_ROOT")"
        git clone https://github.com/raggiesoft/raggiesoft-music.git "$MUSIC_ROOT"
    else
        cd "$MUSIC_ROOT" && git pull origin main
    fi

    echo "   5.65 Checking Engine Room Records, Stardust Engine, Corporate & StoreTrainer Subdomains..."
    if [ -d "$ENGINEROOM_ROOT/.git" ] && (cd "$ENGINEROOM_ROOT" && git remote get-url origin &>/dev/null); then
        cd "$ENGINEROOM_ROOT" && git pull origin main
    fi
    if [ -d "$STARDUST_ROOT/.git" ] && (cd "$STARDUST_ROOT" && git remote get-url origin &>/dev/null); then
        cd "$STARDUST_ROOT" && git pull origin main
    fi
    if [ -d "$CORPORATE_ROOT/.git" ] && (cd "$CORPORATE_ROOT" && git remote get-url origin &>/dev/null); then
        cd "$CORPORATE_ROOT" && git pull origin main
    fi
    if [ -d "$STORETRAINER_ROOT/.git" ] && (cd "$STORETRAINER_ROOT" && git remote get-url origin &>/dev/null); then
        cd "$STORETRAINER_ROOT" && git pull origin main
    fi

    echo "   5.7 Checking Executive Systems Architect Dossier (michaelpragsdale.com/www)..."
    if [ ! -d "$PORTFOLIO_ROOT" ]; then
        echo "      > Repository missing. Cloning raggiesoft-portfolio from GitHub..."
        mkdir -p "$(dirname "$PORTFOLIO_ROOT")"
        git clone https://github.com/raggiesoft/raggiesoft-portfolio.git "$PORTFOLIO_ROOT" 2>/dev/null || true
    elif [ -d "$PORTFOLIO_ROOT/.git" ] && (cd "$PORTFOLIO_ROOT" && git remote get-url origin &>/dev/null); then
        cd "$PORTFOLIO_ROOT" && git pull origin main
    fi

    echo "   5.8 Checking Deployment Tools & Nginx Config..."
    if [ -d "$DEPLOYMENT_TOOLS_ROOT/.git" ] && (cd "$DEPLOYMENT_TOOLS_ROOT" && git remote get-url origin &>/dev/null); then
        cd "$DEPLOYMENT_TOOLS_ROOT" && git pull origin main
    fi
    if [ -d "$NGINX_CONFIG_ROOT/.git" ] && (cd "$NGINX_CONFIG_ROOT" && git remote get-url origin &>/dev/null); then
        cd "$NGINX_CONFIG_ROOT" && git pull origin main
    fi
    
    echo "   6. Hauling the heavy boxes (DigitalOcean Spaces)..."
    run_cdn_preflight
    if [ "$CAN_SYNC_CDN" = true ]; then
        "$RCLONE_BIN" sync do-spaces:assets.raggiesoft.com "$ASSETS_ROOT" \
            --config "$RCLONE_CONF" \
            --exclude "/_workspace/**" \
            --exclude "/.git/**" \
            --exclude "**/vault/**" \
            --exclude "**/master-wav/**" \
            --exclude ".DS_Store" \
            --exclude "desktop.ini" \
            --exclude "Thumbs.db" \
            --exclude "._*" \
            "${RCLONE_PERF_FLAGS[@]}"
        echo "👱‍♀️ JENNA: All done! Your local files are perfectly synced."
    else
        echo "👱‍♀️ JENNA: Git pull complete! (DigitalOcean Spaces CDN sync skipped on this WiFi.)"
    fi
}

function do_push() {
    if [[ -z "$COMMIT_MSG" && -z "$TAG_NAME" ]]; then
        echo "🛑 JENNA: MISSING COMMIT MESSAGE"
        show_help
        exit 1
    fi
    
    if [[ -z "$COMMIT_MSG" ]]; then
        COMMIT_MSG="Jenna: Automated sync for release $TAG_NAME"
    fi

    run_github_preflight

    # --- PRE-FLIGHT TAG CHECK ---
    if [ -n "$TAG_NAME" ]; then
        echo "👱‍♀️ JENNA: Validating tag '$TAG_NAME'..."
        if [ -d "$HUB_ROOT" ]; then
            cd "$HUB_ROOT"
            if git show-ref --tags "$TAG_NAME" --quiet || git ls-remote --tags origin | grep -q "refs/tags/$TAG_NAME"; then
                echo "🛑 JENNA: ABORTING! The tag '$TAG_NAME' is already used in the Hub repository."
                exit 1
            fi
        fi
        if [ -d "$CMS_ROOT" ]; then
            cd "$CMS_ROOT"
            if git show-ref --tags "$TAG_NAME" --quiet || git ls-remote --tags origin | grep -q "refs/tags/$TAG_NAME"; then
                echo "🛑 JENNA: ABORTING! The tag '$TAG_NAME' is already used in the CMS repository."
                exit 1
            fi
        fi
        if [ -d "$NARRATIVES_ROOT" ]; then
            cd "$NARRATIVES_ROOT"
            if git show-ref --tags "$TAG_NAME" --quiet || git ls-remote --tags origin | grep -q "refs/tags/$TAG_NAME"; then
                echo "🛑 JENNA: ABORTING! The tag '$TAG_NAME' is already used in the Narratives repository."
                exit 1
            fi
        fi
        if [ -d "$NEBULAE_ROOT" ]; then
            cd "$NEBULAE_ROOT"
            if git show-ref --tags "$TAG_NAME" --quiet || git ls-remote --tags origin | grep -q "refs/tags/$TAG_NAME"; then
                echo "🛑 JENNA: ABORTING! The tag '$TAG_NAME' is already used in the Nebulae repository."
                exit 1
            fi
        fi
        if [ -d "$PORTFOLIO_ROOT/.git" ]; then
            cd "$PORTFOLIO_ROOT"
            if git show-ref --tags "$TAG_NAME" --quiet || (git remote get-url origin &>/dev/null && git ls-remote --tags origin | grep -q "refs/tags/$TAG_NAME"); then
                echo "🛑 JENNA: ABORTING! The tag '$TAG_NAME' is already used in the Portfolio repository."
                exit 1
            fi
        fi
    fi

    # 1. QA Check
    run_integrity_check

    # 0. SYNC COMPONENTS LIBRARY
    echo "   -> Syncing /components-library to applications..."
    if [ -d "$SERVER_ROOT/components-library" ]; then
        if [ -d "$HUB_ROOT" ]; then
            cp -r "$SERVER_ROOT/components-library/"* "$HUB_ROOT/includes/"
            echo "      ✓ Synced components to raggiesoft-hub"
        fi
        if [ -d "$BOOKS_ROOT" ]; then
            cp -r "$SERVER_ROOT/components-library/"* "$BOOKS_ROOT/includes/"
            echo "      ✓ Synced components to raggiesoft-book-library"
        fi
    fi

    # 2. Orphan Audit
    run_orphan_audit

    # 3. Generate Sitemap
    generate_sitemap

    echo "👱‍♀️ JENNA: Shipping it! Message: \"$COMMIT_MSG\""
    if [ -n "$TAG_NAME" ]; then
        echo "          Applying Tag: $TAG_NAME"
    fi
    if [ -n "$FORCE_FLAG" ]; then
        echo "          ⚠️ EXECUTING FORCE PUSH PROTOCOL ⚠️"
    fi
    echo "          $CONNECTION_MSG"

    # --- PRE-PUSH NARRATIVE BUILD ---
    echo "👱‍♀️ JENNA: Generating AI Context Lumps..."
    if [ -f "$NARRATIVES_ROOT/scripts/lump_narratives.php" ]; then
        php "$NARRATIVES_ROOT/scripts/lump_narratives.php"
        if [ $? -ne 0 ]; then
            echo "⚠️  JENNA: Warning - Failed to generate AI lumps, continuing anyway..."
        fi
    fi

    echo "      > Building Stardust Engine Assets..."
    # Local minification (so the .min files are pushed to GitHub and the CDN)
    php -r '
        $dir = "'"$ASSETS_ROOT"'/stardust-engine-library";
        if (is_dir($dir)) {
            $css = "";
            foreach(glob("$dir/css/src/*.css") as $file) { $css .= file_get_contents($file); }
            $css = preg_replace("!/\*[^*]*\*+([^/][^*]*\*+)*/!", "", $css);
            $css = str_replace(array("\r\n", "\r", "\n", "\t", "  ", "    ", "    "), "", $css);
            file_put_contents("$dir/css/stardust-engine.min.css", $css);
            foreach(glob("$dir/css/src/theme-*.css") as $file) {
                $name = basename($file, ".css");
                $tcss = file_get_contents($file);
                $tcss = preg_replace("!/\*[^*]*\*+([^/][^*]*\*+)*/!", "", $tcss);
                $tcss = str_replace(array("
", "
", "
", "	", "  ", "    ", "    "), "", $tcss);
                file_put_contents("$dir/css/" . $name . ".min.css", $tcss);
            }
            
            foreach(glob("$dir/js/src/*.js") as $file) {
                $name = basename($file, ".js");
                $js = file_get_contents($file);
                $js = preg_replace("!/\*[^*]*\*+([^/][^*]*\*+)*/!", "", $js);
                $js = preg_replace("/^[ 	]+/m", "", $js);
                $js = preg_replace("/
+/", "
", $js);
                file_put_contents("$dir/js/" . $name . ".min.js", $js);
            }
        }
    '

    echo "👱‍♀️ JENNA: Calling Paige (paige.php) to compile Narratives & Books..."
    if [ -f "$DEPLOYMENT_TOOLS_ROOT/paige.php" ]; then
        php "$DEPLOYMENT_TOOLS_ROOT/paige.php"
        if [ $? -ne 0 ]; then
            echo "🛑 JENNA: ABORTING! Paige reported an error compiling narratives."
            exit 1
        fi
    else
        echo "⚠️  JENNA: Could not find paige.php in raggiesoft-deployment-tools. Skipping compilation."
    fi

    echo "👱‍♀️ JENNA: Generating EPUB and PDF eBooks..."
    if [ -f "$NARRATIVES_ROOT/scripts/compile_ebooks.php" ]; then
        php "$NARRATIVES_ROOT/scripts/compile_ebooks.php"
        if [ $? -ne 0 ]; then
            echo "🛑 JENNA: ABORTING! Failed to compile eBooks."
            exit 1
        fi
    else
        echo "⚠️  JENNA: Could not find compile_ebooks.php. Skipping eBook generation."
    fi

    # 4. HUB PUSH
    echo "   1. Packaging the Hub..."
    if [ -d "$HUB_ROOT" ]; then
        cd "$HUB_ROOT"
        git add .
        
        if ! git diff-index --quiet HEAD --; then
             git commit -m "$COMMIT_MSG"
             git push $FORCE_FLAG origin main
             echo "      ✓ Code committed and sent to GitHub."
        elif [ "$(git log origin/main..HEAD 2>/dev/null)" ]; then
             echo "      ⚠️  Found pending commits from a previous run. Pushing now..."
             git push $FORCE_FLAG origin main
             echo "      ✓ Pending code sent to GitHub."
        else
             echo "      (Hub is clean and up to date.)"
             if [ -n "$FORCE_FLAG" ]; then
                 echo "      ⚠️  Force pushing anyway..."
                 git push $FORCE_FLAG origin main
             fi
        fi

        if [ -n "$TAG_NAME" ]; then
            echo "      > Stamping Hub with tag: $TAG_NAME..."
            git tag -a "$TAG_NAME" -m "Release $TAG_NAME"
            git push origin "$TAG_NAME"
            echo "      ✓ Hub Tag sent to GitHub."
        fi
    fi

    # 4.5 CMS PUSH
    echo "   -> Packaging the Stardust Engine CMS..."
    if [ -d "$CMS_ROOT" ]; then
        cd "$CMS_ROOT"
        git add .
        
        if ! git diff-index --quiet HEAD --; then
             git commit -m "$COMMIT_MSG"
             git push $FORCE_FLAG origin main
             echo "      ✓ CMS code committed and sent to GitHub."
        elif [ "$(git log origin/main..HEAD 2>/dev/null)" ]; then
             echo "      ⚠️  Found pending CMS commits. Pushing now..."
             git push $FORCE_FLAG origin main
             echo "      ✓ Pending CMS code sent to GitHub."
        else
             echo "      (CMS is clean and up to date.)"
             if [ -n "$FORCE_FLAG" ]; then
                 echo "      ⚠️  Force pushing anyway..."
                 git push $FORCE_FLAG origin main
             fi
        fi

        if [ -n "$TAG_NAME" ]; then
            echo "      > Stamping CMS with tag: $TAG_NAME..."
            git tag -a "$TAG_NAME" -m "Release $TAG_NAME"
            git push origin "$TAG_NAME"
            echo "      ✓ CMS Tag sent to GitHub."
        fi
    fi
    
    # 4.6 NARRATIVES PUSH
    echo "   -> Packaging the Narratives..."
    if [ -d "$NARRATIVES_ROOT" ]; then
        cd "$NARRATIVES_ROOT"
        git add .
        
        if ! git diff-index --quiet HEAD --; then
             git commit -m "$COMMIT_MSG"
             git push $FORCE_FLAG origin main
             echo "      ✓ Narratives committed and sent to GitHub."
        elif [ "$(git log origin/main..HEAD 2>/dev/null)" ]; then
             echo "      ⚠️  Found pending Narratives commits. Pushing now..."
             git push $FORCE_FLAG origin main
             echo "      ✓ Pending Narratives code sent to GitHub."
        else
             echo "      (Narratives are clean and up to date.)"
             if [ -n "$FORCE_FLAG" ]; then
                 echo "      ⚠️  Force pushing anyway..."
                 git push $FORCE_FLAG origin main
             fi
        fi

        if [ -n "$TAG_NAME" ]; then
            echo "      > Stamping Narratives with tag: $TAG_NAME..."
            git tag -a "$TAG_NAME" -m "Release $TAG_NAME"
            git push origin "$TAG_NAME"
            echo "      ✓ Narratives Tag sent to GitHub."
        fi
    fi

    # 4.7 NEBULAE PUSH
    echo "   -> Packaging the Nebulae Cosmic Observatory (nebulae.raggiesoft.com)..."
    if [ -d "$NEBULAE_ROOT" ]; then
        cd "$NEBULAE_ROOT"
        if [ -f "$NEBULAE_ROOT/package.json" ]; then
            export PATH="/opt/homebrew/bin:$PATH"
            npm run build
            if [ $? -ne 0 ]; then
                echo "🛑 JENNA: ABORTING! Nebulae Observatory build failed."
                exit 1
            fi
        fi
        git add -A
        
        if ! git diff-index --quiet HEAD --; then
             git commit -m "$COMMIT_MSG"
             git push $FORCE_FLAG origin main
             echo "      ✓ Nebulae committed and sent to GitHub."
        elif [ "$(git log origin/main..HEAD 2>/dev/null)" ]; then
             echo "      ⚠️  Found pending Nebulae commits. Pushing now..."
             git push $FORCE_FLAG origin main
             echo "      ✓ Pending Nebulae code sent to GitHub."
        else
             echo "      (Nebulae is clean and up to date.)"
             if [ -n "$FORCE_FLAG" ]; then
                 echo "      ⚠️  Force pushing anyway..."
                 git push $FORCE_FLAG origin main
             fi
        fi

        if [ -n "$TAG_NAME" ]; then
            echo "      > Stamping Nebulae with tag: $TAG_NAME..."
            git tag -a "$TAG_NAME" -m "Release $TAG_NAME"
            git push origin "$TAG_NAME"
            echo "      ✓ Nebulae Tag sent to GitHub."
        fi
    fi

    echo "   -> Checking Books Repo..."
    if [ -d "$BOOKS_ROOT" ]; then
        cd "$BOOKS_ROOT"
        git add .
        
        if ! git diff-index --quiet HEAD --; then
             git commit -m "$COMMIT_MSG"
             git push $FORCE_FLAG origin main
             echo "      ✓ Books committed and sent to GitHub."
        elif [ "$(git log origin/main..HEAD 2>/dev/null)" ]; then
             echo "      ⚠️  Found pending Books commits. Pushing now..."
             git push $FORCE_FLAG origin main
             echo "      ✓ Pending Books code sent to GitHub."
        else
             echo "      (Books is clean and up to date.)"
             if [ -n "$FORCE_FLAG" ]; then
                 echo "      ⚠️  Force pushing anyway..."
                 git push $FORCE_FLAG origin main
             fi
        fi

        if [ -n "$TAG_NAME" ]; then
            echo "      > Stamping Books with tag: $TAG_NAME..."
            git tag "$TAG_NAME"
            git push origin "$TAG_NAME"
        fi
    fi

    # 4.8 LORE PUSH
    echo "   -> Packaging the Lore Graph..."
    if [ -d "$LORE_ROOT" ]; then
        cd "$LORE_ROOT"
        
        echo "      > Compiling Static HTML Graph..."
        export PATH="/opt/homebrew/bin:$PATH"
        npm run build
        
        git add .
        
        if ! git diff-index --quiet HEAD --; then
             git commit -m "$COMMIT_MSG"
             git push $FORCE_FLAG origin main
             echo "      ✓ Lore committed and sent to GitHub."
        elif [ "$(git log origin/main..HEAD 2>/dev/null)" ]; then
             echo "      ⚠️  Found pending Lore commits. Pushing now..."
             git push $FORCE_FLAG origin main
             echo "      ✓ Pending Lore code sent to GitHub."
        else
             echo "      (Lore is clean and up to date.)"
             if [ -n "$FORCE_FLAG" ]; then
                 echo "      ⚠️  Force pushing anyway..."
                 git push $FORCE_FLAG origin main
             fi
        fi

        if [ -n "$TAG_NAME" ]; then
            echo "      > Stamping Lore with tag: $TAG_NAME..."
            git tag "$TAG_NAME"
            git push origin "$TAG_NAME"
        fi
    fi

    # 4.9 MUSIC PUSH
    echo "   -> Packaging Engine Room Records (music.raggiesoft.com)..."
    if [ -d "$MUSIC_ROOT" ]; then
        cd "$MUSIC_ROOT"
        
        echo "      > Compiling dynamic Engine Room Records catalog & static PWA build..."
        export PATH="/opt/homebrew/bin:$PATH"
        npm run build
        npm run check
        if [ $? -ne 0 ]; then
            echo "🛑 JENNA: ABORTING! SvelteKit check failed in raggiesoft-music."
            exit 1
        fi
        
        git add .
        
        if ! git diff-index --quiet HEAD --; then
             git commit -m "$COMMIT_MSG"
             git push $FORCE_FLAG origin main
             echo "      ✓ Music platform committed and sent to GitHub."
        elif [ "$(git log origin/main..HEAD 2>/dev/null)" ]; then
             echo "      ⚠️  Found pending Music commits. Pushing now..."
             git push $FORCE_FLAG origin main
             echo "      ✓ Pending Music code sent to GitHub."
        else
             echo "      (Music is clean and up to date.)"
             if [ -n "$FORCE_FLAG" ]; then
                 echo "      ⚠️  Force pushing anyway..."
                 git push $FORCE_FLAG origin main
             fi
        fi

        if [ -n "$TAG_NAME" ]; then
            echo "      > Stamping Music with tag: $TAG_NAME..."
            git tag "$TAG_NAME"
            git push origin "$TAG_NAME"
        fi
    fi

    # 4.95 ENGINE ROOM RECORDS IMPRINT PUSH (engineroom.raggiesoft.com)
    if [ -d "$ENGINEROOM_ROOT" ] && [ -f "$ENGINEROOM_ROOT/package.json" ]; then
        echo "   -> Packaging Engine Room Records Imprint (engineroom.raggiesoft.com)..."
        cd "$ENGINEROOM_ROOT"
        export PATH="/opt/homebrew/bin:$PATH"
        npm run build
        if [ $? -ne 0 ]; then
            echo "🛑 JENNA: ABORTING! Astro 6 build failed in engineroom.raggiesoft.com."
            exit 1
        fi
        if [ -d "$ENGINEROOM_ROOT/.git" ]; then
            git add -A
            if ! git diff-index --quiet HEAD -- 2>/dev/null || ! git rev-parse --verify HEAD &>/dev/null; then
                git commit -m "$COMMIT_MSG"
                if git remote get-url origin &>/dev/null; then
                    git push -u $FORCE_FLAG origin main
                    echo "      ✓ Engine Room Records Imprint committed and sent to GitHub."
                else
                    echo "      ✓ Engine Room Records Imprint committed locally (awaiting GitHub 'origin' remote)."
                fi
            elif git remote get-url origin &>/dev/null && ( ! git rev-parse --verify origin/main &>/dev/null || [ "$(git log origin/main..HEAD 2>/dev/null)" ] ); then
                git push -u $FORCE_FLAG origin main
                echo "      ✓ Pending Engine Room Records Imprint code sent to GitHub."
            else
                echo "      (Engine Room Records Imprint is clean and up to date.)"
            fi
        fi
    fi

    # 4.96 THE STARDUST ENGINE PUSH (stardust.raggiesoft.com)
    if [ -d "$STARDUST_ROOT" ] && [ -f "$STARDUST_ROOT/package.json" ]; then
        echo "   -> Packaging The Stardust Engine (stardust.raggiesoft.com)..."
        cd "$STARDUST_ROOT"
        export PATH="/opt/homebrew/bin:$PATH"
        npm run build
        if [ $? -ne 0 ]; then
            echo "🛑 JENNA: ABORTING! Nuxt 4 build failed in stardust.raggiesoft.com."
            exit 1
        fi
        if [ -d "$STARDUST_ROOT/.git" ]; then
            git add -A
            if ! git diff-index --quiet HEAD -- 2>/dev/null || ! git rev-parse --verify HEAD &>/dev/null; then
                git commit -m "$COMMIT_MSG"
                if git remote get-url origin &>/dev/null; then
                    git push -u $FORCE_FLAG origin main
                    echo "      ✓ The Stardust Engine committed and sent to GitHub."
                else
                    echo "      ✓ The Stardust Engine committed locally (awaiting GitHub 'origin' remote)."
                fi
            elif git remote get-url origin &>/dev/null && ( ! git rev-parse --verify origin/main &>/dev/null || [ "$(git log origin/main..HEAD 2>/dev/null)" ] ); then
                git push -u $FORCE_FLAG origin main
                echo "      ✓ Pending The Stardust Engine code sent to GitHub."
            else
                echo "      (The Stardust Engine is clean and up to date.)"
            fi
        fi
    fi

    # 4.97 RAGGIESOFT MEDIA CORPORATE HUB PUSH (corporate.raggiesoft.com)
    if [ -d "$CORPORATE_ROOT" ] && [ -f "$CORPORATE_ROOT/package.json" ]; then
        echo "   -> Packaging RaggieSoft Media Corporate Hub (corporate.raggiesoft.com)..."
        cd "$CORPORATE_ROOT"
        export PATH="/opt/homebrew/bin:$PATH"
        npm run build
        if [ $? -ne 0 ]; then
            echo "🛑 JENNA: ABORTING! Bootstrap 5.3.8 build failed in corporate.raggiesoft.com."
            exit 1
        fi
        if [ -d "$CORPORATE_ROOT/.git" ]; then
            git add -A
            if ! git diff-index --quiet HEAD -- 2>/dev/null || ! git rev-parse --verify HEAD &>/dev/null; then
                git commit -m "$COMMIT_MSG"
                if git remote get-url origin &>/dev/null; then
                    git push -u $FORCE_FLAG origin main
                    echo "      ✓ RaggieSoft Media Corporate Hub committed and sent to GitHub."
                else
                    echo "      ✓ RaggieSoft Media Corporate Hub committed locally (awaiting GitHub 'origin' remote)."
                fi
            elif git remote get-url origin &>/dev/null && ( ! git rev-parse --verify origin/main &>/dev/null || [ "$(git log origin/main..HEAD 2>/dev/null)" ] ); then
                git push -u $FORCE_FLAG origin main
                echo "      ✓ Pending RaggieSoft Media Corporate Hub code sent to GitHub."
            else
                echo "      (RaggieSoft Media Corporate Hub is clean and up to date.)"
            fi
        fi
    fi

    # 4.98 RAGGIESOFT STORETRAINER PUSH (storetrainer.raggiesoft.com)
    if [ -d "$STORETRAINER_ROOT" ] && [ -f "$STORETRAINER_ROOT/package.json" ]; then
        echo "   -> Packaging RaggieSoft StoreTrainer (storetrainer.raggiesoft.com)..."
        cd "$STORETRAINER_ROOT"
        export PATH="/opt/homebrew/bin:$PATH"
        npm run build
        if [ $? -ne 0 ]; then
            echo "🛑 JENNA: ABORTING! Vanilla TypeScript build failed in storetrainer.raggiesoft.com."
            exit 1
        fi
        if [ -d "$STORETRAINER_ROOT/.git" ]; then
            git add -A
            if ! git diff-index --quiet HEAD -- 2>/dev/null || ! git rev-parse --verify HEAD &>/dev/null; then
                git commit -m "$COMMIT_MSG"
                if git remote get-url origin &>/dev/null; then
                    git push -u $FORCE_FLAG origin main
                    echo "      ✓ RaggieSoft StoreTrainer committed and sent to GitHub."
                else
                    echo "      ✓ RaggieSoft StoreTrainer committed locally (awaiting GitHub 'origin' remote)."
                fi
            elif git remote get-url origin &>/dev/null && ( ! git rev-parse --verify origin/main &>/dev/null || [ "$(git log origin/main..HEAD 2>/dev/null)" ] ); then
                git push -u $FORCE_FLAG origin main
                echo "      ✓ Pending RaggieSoft StoreTrainer code sent to GitHub."
            else
                echo "      (RaggieSoft StoreTrainer is clean and up to date.)"
            fi
        fi
    fi


    # 4.10 PORTFOLIO PUSH (Executive Systems Architect Dossier - michaelpragsdale.com)
    echo "   -> Packaging Executive Systems Architect Dossier (michaelpragsdale.com)..."
    if [ -d "$PORTFOLIO_ROOT" ]; then
        cd "$PORTFOLIO_ROOT"

        echo "      > Compiling Angular 19 Zoneless static build..."
        export PATH="/opt/homebrew/bin:$PATH"
        npm run build
        if [ $? -ne 0 ]; then
            echo "🛑 JENNA: ABORTING! Angular production build failed in raggiesoft-portfolio."
            exit 1
        fi

        if [ -d "$PORTFOLIO_ROOT/.git" ]; then
            if git remote get-url origin &>/dev/null; then
                git fetch origin main 2>/dev/null || true
                if git rev-parse --verify origin/main &>/dev/null && ! git merge-base origin/main HEAD &>/dev/null; then
                    echo "      > Grafting Angular 19 Portfolio Dossier onto historical origin/main..."
                    git reset --soft origin/main
                fi
            fi
            git add -A

            if ! git diff-index --quiet HEAD -- 2>/dev/null || ! git rev-parse --verify HEAD &>/dev/null; then
                git commit -m "$COMMIT_MSG"
                if git remote get-url origin &>/dev/null; then
                    git push -u $FORCE_FLAG origin main
                    echo "      ✓ Portfolio Dossier committed and sent to GitHub."
                else
                    echo "      ✓ Portfolio Dossier committed locally (awaiting GitHub 'origin' remote)."
                fi
            elif git remote get-url origin &>/dev/null && ( ! git rev-parse --verify origin/main &>/dev/null || [ "$(git log origin/main..HEAD 2>/dev/null)" ] ); then
                echo "      ⚠️  Found pending Portfolio commits. Pushing now..."
                git push -u $FORCE_FLAG origin main
                echo "      ✓ Pending Portfolio code sent to GitHub."
            else
                echo "      (Portfolio Dossier is clean and up to date.)"
                if [ -n "$FORCE_FLAG" ] && git remote get-url origin &>/dev/null; then
                    echo "      ⚠️  Force pushing anyway..."
                    git push -u $FORCE_FLAG origin main
                fi
            fi

            if [ -n "$TAG_NAME" ]; then
                echo "      > Stamping Portfolio with tag: $TAG_NAME..."
                git tag "$TAG_NAME"
                if git remote get-url origin &>/dev/null; then
                    git push origin "$TAG_NAME"
                fi
            fi
        fi
    fi

    # 4.11 DEPLOYMENT TOOLS PUSH (/raggiesoft-deployment-tools)
    echo "   -> Packaging Deployment Tools (/raggiesoft-deployment-tools)..."
    if [ -d "$DEPLOYMENT_TOOLS_ROOT/.git" ]; then
        cd "$DEPLOYMENT_TOOLS_ROOT"
        git add .

        if ! git diff-index --quiet HEAD -- 2>/dev/null || ! git rev-parse --verify HEAD &>/dev/null; then
            git commit -m "$COMMIT_MSG"
            if git remote get-url origin &>/dev/null; then
                git push -u $FORCE_FLAG origin main
                echo "      ✓ Deployment Tools committed and sent to GitHub."
            else
                echo "      ✓ Deployment Tools committed locally (awaiting GitHub 'origin' remote)."
            fi
        elif git remote get-url origin &>/dev/null && ( ! git rev-parse --verify origin/main &>/dev/null || [ "$(git log origin/main..HEAD 2>/dev/null)" ] ); then
            echo "      ⚠️  Found pending Deployment Tools commits. Pushing now..."
            git push -u $FORCE_FLAG origin main
            echo "      ✓ Pending Deployment Tools sent to GitHub."
        else
            echo "      (Deployment Tools are clean and up to date.)"
        fi
    fi

    # 4.12 NGINX CONFIG PUSH (/nginx-config)
    echo "   -> Packaging Nginx Configurations (/nginx-config)..."
    if [ -d "$NGINX_CONFIG_ROOT/.git" ]; then
        cd "$NGINX_CONFIG_ROOT"
        git add .

        if ! git diff-index --quiet HEAD -- 2>/dev/null || ! git rev-parse --verify HEAD &>/dev/null; then
            git commit -m "$COMMIT_MSG"
            if git remote get-url origin &>/dev/null; then
                git push -u $FORCE_FLAG origin main
                echo "      ✓ Nginx Configs committed and sent to GitHub."
            else
                echo "      ✓ Nginx Configs committed locally (awaiting GitHub 'origin' remote)."
            fi
        elif git remote get-url origin &>/dev/null && ( ! git rev-parse --verify origin/main &>/dev/null || [ "$(git log origin/main..HEAD 2>/dev/null)" ] ); then
            echo "      ⚠️  Found pending Nginx Config commits. Pushing now..."
            git push -u $FORCE_FLAG origin main
            echo "      ✓ Pending Nginx Configs sent to GitHub."
        else
            echo "      (Nginx Configs are clean and up to date.)"
        fi
    fi

    # 5. ASSETS PUSH
    echo "   2. Packaging the Assets Repository..."
    cd "$ASSETS_ROOT"
    
    echo "      > Building Stardust Engine Assets..."
    # Local minification (so the .min files are pushed to GitHub and the CDN)
    php -r '
        $dir = "'"$ASSETS_ROOT"'/stardust-engine-library";
        if (is_dir($dir)) {
            $css = "";
            foreach(glob("$dir/css/src/*.css") as $file) { $css .= file_get_contents($file); }
            $css = preg_replace("!/\*[^*]*\*+([^/][^*]*\*+)*/!", "", $css);
            $css = str_replace(array("\r\n", "\r", "\n", "\t", "  ", "    ", "    "), "", $css);
            file_put_contents("$dir/css/stardust-engine.min.css", $css);
            foreach(glob("$dir/css/src/theme-*.css") as $file) {
                $name = basename($file, ".css");
                $tcss = file_get_contents($file);
                $tcss = preg_replace("!/\*[^*]*\*+([^/][^*]*\*+)*/!", "", $tcss);
                $tcss = str_replace(array("
", "
", "
", "	", "  ", "    ", "    "), "", $tcss);
                file_put_contents("$dir/css/" . $name . ".min.css", $tcss);
            }
            
            foreach(glob("$dir/js/src/*.js") as $file) {
                $name = basename($file, ".js");
                $js = file_get_contents($file);
                $js = preg_replace("!/\*[^*]*\*+([^/][^*]*\*+)*/!", "", $js);
                $js = preg_replace("/^[ \t]+/m", "", $js);
                $js = preg_replace("/\n+/", "\n", $js);
                file_put_contents("$dir/js/" . $name . ".min.js", $js);
            }
        }
    '
    
    echo "      > Indexing files (Verbose mode active)..."
    git add -v .
    
    if ! git diff-index --quiet HEAD --; then
        echo "      > Committing changes..."
        git commit -m "$COMMIT_MSG"
        echo "      > Pushing to remote..."
        git push $FORCE_FLAG --progress origin main
        echo "      ✓ Workspace synced to GitHub."
    elif [ "$(git log origin/main..HEAD 2>/dev/null)" ]; then
        echo "      ⚠️  Found pending commits. Pushing now..."
        git push $FORCE_FLAG --progress origin main
        echo "      ✓ Pending workspace changes sent to GitHub."
    else
        echo "      (Assets repo looks unchanged.)"
        if [ -n "$FORCE_FLAG" ]; then
            echo "      ⚠️  Force pushing anyway..."
            git push $FORCE_FLAG --progress origin main
        fi
    fi
    
    # 6. CDN SYNC (Public Assets Only - Vaults & Master-WAVs live locally in /raggiesoft-vaults)
    echo "   3. Beaming public web assets to the CDN (Vaults & Master-WAVs excluded)..."
    run_cdn_preflight
    if [ "$CAN_SYNC_CDN" = true ]; then
        "$RCLONE_BIN" copy "$ASSETS_ROOT" do-spaces:assets.raggiesoft.com \
            --config "$RCLONE_CONF" \
            --exclude "/_workspace/**" \
            --exclude "/.git/**" \
            --exclude "**/vault/**" \
            --exclude "**/vault-*/**" \
            --exclude "**/master-wav/**" \
            --exclude ".gitignore" \
            --exclude ".DS_Store" \
            --exclude "desktop.ini" \
            --exclude "Thumbs.db" \
            --exclude "._*" \
            --s3-acl public-read \
            "${RCLONE_PERF_FLAGS[@]}"
        echo "👱‍♀️ JENNA: Success! All public assets are live on the CDN, and your local vaults remain safely off DigitalOcean Spaces. Sarah will pick this up shortly."
    else
        echo "👱‍♀️ JENNA: Finished! Code/narratives are committed (and pushed if GitHub was reachable); CDN sync was skipped because DigitalOcean Spaces is blocked on this WiFi."
    fi
}

# --- UNIFIED ARGUMENT PARSER ---
ACTION=""
COMMIT_MSG=""
TAG_NAME=""
USE_PUBLIC_WIFI=false
FORCE_FLAG=""

while [[ "$#" -gt 0 ]]; do
    case $1 in
        --push) ACTION="push" ;;
        --pull) ACTION="pull" ;;
        --audit) ACTION="audit" ;;
        --force) FORCE_FLAG="--force" ;;
        --msg|-m) COMMIT_MSG="$2"; shift ;;
        --tag|-t) TAG_NAME="$2"; shift ;;
        --public-wifi) USE_PUBLIC_WIFI=true ;;
        *) echo "👱‍♀️ JENNA: I don't recognize the command '$1'."; show_help; exit 1 ;;
    esac
    shift
done

# Apply connection modifications based on parsing
if [ "$USE_PUBLIC_WIFI" = true ]; then
    # Use a proper Bash array so spaces inside the full Chrome User-Agent string do not word-split into invalid rclone positional args.
    # --bind 0.0.0.0 prevents broken public-WiFi IPv6 blackholes, and --disable-http2 prevents DPI middleboxes from dropping Go HTTP/2 streams.
    RCLONE_PERF_FLAGS=(
        -P
        --transfers=2
        --checkers=4
        --tpslimit=4
        --timeout=15s
        --contimeout=5s
        --retries=1
        --low-level-retries=1
        --bind 0.0.0.0
        --disable-http2
        --user-agent "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"
    )
    # Bypass port 22 blocks on public WiFi by routing Git SSH over port 443 (with accept-new so [ssh.github.com]:443 never hangs on host key prompt)
    export GIT_SSH_COMMAND="ssh -o Port=443 -o HostName=ssh.github.com -o StrictHostKeyChecking=accept-new -o ConnectTimeout=5"
    CONNECTION_MSG="🕵️‍♀️ CAMOUFLAGE MODE: Spoofing macOS Chrome User-Agent, HTTP/1.1 IPv4, and routing Git via Port 443."
else
    RCLONE_PERF_FLAGS=(-P --transfers=8 --contimeout=5s --timeout=15s --retries=1 --low-level-retries=1)
    CONNECTION_MSG="🚀 STANDARD MODE: Automatic 5-second pre-flight checks active."
fi

# Dispatch
case "$ACTION" in
    pull) do_pull ;;
    push) do_push ;;
    audit) run_orphan_audit ;;
    *) show_help ;;
esac