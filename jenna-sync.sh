#!/bin/bash

# ============================================================================
# JENNA: THE DEVELOPMENT & SYNCHRONIZATION LIAISON (`jenna-sync.sh`)
# ============================================================================
# PLAIN-ENGLISH OVERVIEW (100-Level Course Guide):
#   Think of `jenna-sync.sh` ("Jenna") as the single "Publish Everything Safely"
#   button on your local workstation (`$HOME/Developer`). You NEVER run raw
#   `git push` directly inside `raggiesoft-servers/` or `raggiesoft-deployment-tools/`—
#   instead, you run Jenna (`./jenna-sync.sh --push -m "Commit Message"`), and she
#   orchestrates the entire RaggieSoft multi-repo & CDN release pipeline in order:
#
#   WHEN IT RUNS:
#     - `--pull`: Pulls the latest Git commits across all 15+ local repositories and
#       downloads any updated binary assets from DigitalOcean Spaces CDN (`rclone sync`).
#     - `--audit`: Runs read-only QA checks (broken asset references, orphan files,
#       network SEO/OpenGraph validation) without committing or pushing anything.
#     - `--push -m "Message" [-t "v1.0.0"] [--force]`: Runs the full pre-flight,
#       QA, build/compile (`paige.php`, `audrey.php`, CSS/JS minifiers, Next.js 16,
#       SvelteKit 2, Astro 6, Nuxt 4, Bootstrap 5, TypeScript, Web Awesome, Angular 19),
#       multi-repo Git commit + push, DigitalOcean Spaces CDN upload, and IndexNow ping!
#
#   WHAT INPUTS / REPOS IT READS & UPDATES:
#     - `raggiesoft-narratives` (Markdown novels & lore)
#     - `stardust-engine-cms` (Shared PHP 8.5 CMS core)
#     - `raggiesoft.com/www` + all 9 `raggiesoft.com/subdomains/*` apps
#     - `michaelpragsdale.com/www` (Angular 19 Zoneless engineering portfolio)
#     - `raggiesoft-deployment-tools` & `nginx-config`
#     - `raggiesoft-assets` -> mirrored via `rclone` to DigitalOcean Spaces (`assets.raggiesoft.com`)
#
#   KEY BASH / DEVOPS CONCEPTS EXPLAINED IN THIS FILE:
#     1. Self-Wrapping Process Replacement (`exec caffeinate -im "$0" --caffeinated "$@"`)
#     2. Zero-Interactive Environment Variables (`export CI=true`, `GIT_TERMINAL_PROMPT=0`)
#     3. OS-Level Hard Timeouts (`fork` + `setpgrp` + `SIGALRM` via `/usr/bin/perl`)
#     4. Automatic Network Fallback (SSH Port 22 -> SSH over HTTPS Port 443 -> Local-Only)
#     5. Binary Shadowing (`function git()` intercepting `git` via `command git "$@"`)
#     6. Structured POSIX Exit Codes (`ERRORLEVEL` 0, 1, 2, 3, 4)
# ============================================================================

# --- JENNA: THE DEVELOPMENT LIAISON (v7.3 - Force Push Edition) ---
# Usage: ./jenna-sync.sh --push -m "Message" [-t "v1.0.0"] [--force]
#        ./jenna-sync.sh --pull
#        ./jenna-sync.sh --audit

# --- OS-SPECIFIC OVERRIDES (`caffeinate` Sleep Prevention on macOS) ---
# HOW `exec` + `shift` SELF-WRAPPING WORKS IN BASH:
#   - `$OSTYPE` is built into Bash (`darwin*` = macOS, `linux-gnu*` = Linux, `msys` = Windows Git Bash).
#   - `command -v caffeinate > /dev/null` checks if Apple's `caffeinate` utility exists.
#   - When you run `./jenna-sync.sh --push -m "Msg"`, `$1` (the first argument) is `--push`,
#     NOT `--caffeinated`. So `exec caffeinate -im "$0" --caffeinated "$@"` REPLACES the current
#     Bash process (`exec` = no extra subshell PID!) with `caffeinate -im` (prevent idle & disk sleep),
#     which immediately re-launches this exact script (`"$0"`) with `--caffeinated` prepended in front
#     of all your original quoted arguments (`"$@"`).
#   - On that second entry, `$1` IS `--caffeinated`, so `shift` pops `$1` off the argument list
#     (sliding `$2` into `$1`, `$3` into `$2`, etc.) and the rest of the script runs normally while
#     macOS stays wide awake until Jenna exits!
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

# ============================================================================
# 0. ZERO-INTERACTIVE / AUTOMATIC "YES" ENVIRONMENT ENFORCEMENT
# ============================================================================
# HOW `export VAR=value` WORKS IN BASH:
#   A plain variable (`FOO=bar`) only exists inside this Bash script. Prefixing it
#   with `export` places it into the OS process environment block so EVERY child
#   program Jenna launches (`git`, `ssh`, `npm`, `npx`, `php`, `node`) inherits it!
#
# Guarantees that Jenna NEVER blocks or hangs waiting for keyboard input:
# 1. Node / npm / npx / Next.js / Angular / Astro / Nuxt / Vite:
#    - `npm_config_yes=true`: Automatically answers "Yes" to any npm/npx install or upgrade prompt.
#    - `CI=true`: Disables interactive CLI spinners, pagers, and first-run wizard prompts.
#    - `__NEXT_AGENT_UPGRADE=security`: Combined with `CI=true`, instructs Next.js 16.4+ (`nudge.js`)
#      not to pause on the interactive `cli-select` upgrade prompt or throw `SecurityFatalError`
#      during automated/agent builds while Jenna handles auto-upgrading Next.js directly.
#    - `NEXT_TELEMETRY_DISABLED=1`, `NG_CLI_ANALYTICS=false`, `NG_FORCE_TTY=false`,
#      `ASTRO_TELEMETRY_DISABLED=1`, `NUXT_TELEMETRY_DISABLED=1`, `NO_UPDATE_NOTIFIER=1`:
#      Suppresses framework telemetry & update-notifier prompts across all subdomains.
# 2. Git & SSH:
#    - `GIT_TERMINAL_PROMPT=0`: Never blocks on an interactive HTTPS username/password prompt.
#    - `GIT_MERGE_AUTOEDIT=no` & `GIT_EDITOR=true`: Never opens vim/nano during `git pull` merges
#      (`/usr/bin/true` is a tiny Unix program that immediately exits 0 without opening an editor!).
#    - `GIT_PAGER=cat` & `PAGER=cat`: Streams output straight to stdout instead of pausing in `less`.
#    - `GIT_SSH_COMMAND`: Enforces `BatchMode=yes` and `StrictHostKeyChecking=accept-new`
#      so SSH never pauses to ask `(yes/no/[fingerprint])` on rotated GitHub host keys.
# 3. Homebrew / GitHub CLI:
#    - `HOMEBREW_NO_AUTO_UPDATE=1`, `GH_PROMPT_DISABLED=1`: Disables CLI auto-update/interactive prompts.
# ============================================================================
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
export HOMEBREW_NO_AUTO_UPDATE=1
export HOMEBREW_NO_INSTALL_CLEANUP=1
export GH_PROMPT_DISABLED=1


# ============================================================================
# 1. ESTABLISH PATHS (Dynamically resolved across macOS, Linux, and Windows Git Bash)
# ============================================================================
# HOW `$(cd "$(dirname "$0")" && pwd)` FINDS THIS SCRIPT'S TRUE DIRECTORY:
#   - `$0` is the path used to invoke the script (e.g., `./raggiesoft-deployment-tools/jenna-sync.sh`).
#   - `dirname "$0"` strips the filename (`./raggiesoft-deployment-tools`).
#   - Running `cd ... && pwd` inside `$(...)` (a subshell command substitution) resolves
#     relative `.` or `..` segments into an absolute path (`/Users/michael/Developer/raggiesoft-deployment-tools`)
#     without changing the parent script's current working directory!
WORKSPACE_DIR=$(cd "$(dirname "$0")" && pwd)
PARENT_ROOT=$(cd "$WORKSPACE_DIR/.." && pwd)
# `[ -d ... ]` tests whether a directory exists on disk (supporting both monorepo and flat layouts):
if [ -d "$PARENT_ROOT/raggiesoft-servers" ]; then
    SERVER_ROOT="$PARENT_ROOT/raggiesoft-servers"
else
    SERVER_ROOT="$PARENT_ROOT"
fi
ASSETS_ROOT="$SERVER_ROOT/raggiesoft-assets"

# Map every web property, subdomain, CMS, narratives repo, and config directory:
HUB_ROOT="$SERVER_ROOT/raggiesoft.com/www"
CMS_ROOT="$SERVER_ROOT/stardust-engine-cms"
if [ -d "$SERVER_ROOT/raggiesoft-novels" ]; then
    NARRATIVES_ROOT="$SERVER_ROOT/raggiesoft-novels"
else
    NARRATIVES_ROOT="$SERVER_ROOT/raggiesoft-narratives"
fi
NEBULAE_ROOT="$SERVER_ROOT/raggiesoft.com/subdomains/nebulae"
BOOKS_ROOT="$SERVER_ROOT/raggiesoft.com/subdomains/books"
LORE_ROOT="$SERVER_ROOT/raggiesoft.com/subdomains/lore"
MUSIC_ROOT="$SERVER_ROOT/raggiesoft.com/subdomains/music"
ENGINEROOM_ROOT="$SERVER_ROOT/raggiesoft.com/subdomains/engineroom"
STARDUST_ROOT="$SERVER_ROOT/raggiesoft.com/subdomains/stardust"
CORPORATE_ROOT="$SERVER_ROOT/raggiesoft.com/subdomains/corporate"
STORETRAINER_ROOT="$SERVER_ROOT/raggiesoft.com/subdomains/storetrainer"
BACKSTAGE_ROOT="$SERVER_ROOT/raggiesoft.com/subdomains/backstage"
CEDARRUN_ROOT="$SERVER_ROOT/raggiesoft.com/subdomains/cedarrun"
CROSSROADS_ROOT="$SERVER_ROOT/raggiesoft.com/subdomains/crossroads"
WAYSTATION_ROOT="$SERVER_ROOT/raggiesoft.com/subdomains/waystation"
JESSICA_ROOT="$SERVER_ROOT/raggiesoft.com/subdomains/jessica"
PORTFOLIO_ROOT="$SERVER_ROOT/michaelpragsdale.com/www"
DEPLOYMENT_TOOLS_ROOT="$WORKSPACE_DIR"
NGINX_CONFIG_ROOT="$SERVER_ROOT/nginx-config"
DESKTOP_APPS_ROOT="$PARENT_ROOT/desktop-apps"
DESKTOP_STORETRAINER_ROOT="$DESKTOP_APPS_ROOT/storetrainer"
LOGS_DIR="$WORKSPACE_DIR/logs"

# ============================================================================
# 2. DETECT RCLONE (Cloud Storage Sync Engine for DigitalOcean Spaces S3 CDN)
# ============================================================================
# `rclone` is the command-line "rsync for cloud storage" that syncs `raggiesoft-assets/`
# to our DigitalOcean Spaces bucket (`do-spaces:assets.raggiesoft.com`).
# - On Windows Git Bash (`$OSTYPE` is `msys` or `cygwin`), look for bundled `rclone.exe`.
# - On macOS / Linux, check `PATH` first (`command -v rclone &> /dev/null` silences both
#   stdout and stderr), then fall back to `build-tools/rclone/rclone`.
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

# `[ ! -f "$RCLONE_CONF" ]` (`!` = NOT, `-f` = regular file exists) aborts early if credentials are missing:
if [ ! -f "$RCLONE_CONF" ]; then
    echo "👱‍♀️ JENNA: Uh oh, I'm missing my credentials (rclone.conf)!"
    exit 1
fi

# 3. JENNA'S BRAIN (Functions & ERRORLEVEL Exit Code Contract)
# ============================================================================
# HOW POSIX EXIT CODES (`0`–`255`) WORK:
#   Every CLI program returns an integer exit status (`$?` in Bash, `%ERRORLEVEL%` on Windows)
#   when it finishes: `0` universally means "100% success", while non-zero integers encode
#   specific failure modes so calling scripts (`studio.sh`, CI runners) know what happened.
#   `readonly` locks these constants so nothing later in the script can accidentally overwrite them!
#
# MS-DOS / POSIX Exit Code Table (ERRORLEVEL):
#   0 = ERR_SUCCESS                    (100% complete: Builds + GitHub + CDN all succeeded)
#   1 = ERR_FATAL_BUILD_OR_QA          (Missing args/binaries, QA fail, duplicate tag, or build error)
#   2 = ERR_GITHUB_SYNC_FAILED         (Local build & CDN succeeded, but GitHub push/pull failed or was unreachable)
#   3 = ERR_CDN_SYNC_FAILED            (Local build & GitHub succeeded, but DO Spaces rclone failed or was unreachable)
#   4 = ERR_NETWORK_OFFLINE_LOCAL_ONLY (Both GitHub and DO Spaces were unreachable/failed; committed locally only)
# ============================================================================
readonly ERR_SUCCESS=0
readonly ERR_FATAL_BUILD_OR_QA=1
readonly ERR_GITHUB_SYNC_FAILED=2
readonly ERR_CDN_SYNC_FAILED=3
readonly ERR_NETWORK_OFFLINE_LOCAL_ONLY=4

# Global Connectivity & Error State Flags (Populated by 5-second pre-flight probes & sync steps)
CAN_PUSH_GITHUB=true
CAN_SYNC_CDN=true
GITHUB_SYNC_HAD_ERROR=false
CDN_SYNC_HAD_ERROR=false

# Evaluates the cumulative network flags at the very end of `--pull` or `--push` and exits with the exact code:
function finalize_jenna_exit() {
    if [ "$GITHUB_SYNC_HAD_ERROR" = true ] && [ "$CDN_SYNC_HAD_ERROR" = true ]; then
        echo "⚠️  JENNA EXIT STATUS: ERRORLEVEL=$ERR_NETWORK_OFFLINE_LOCAL_ONLY (ERR_NETWORK_OFFLINE_LOCAL_ONLY — Built & committed locally; both GitHub & CDN unreachable/failed)."
        exit "$ERR_NETWORK_OFFLINE_LOCAL_ONLY"
    elif [ "$GITHUB_SYNC_HAD_ERROR" = true ]; then
        echo "⚠️  JENNA EXIT STATUS: ERRORLEVEL=$ERR_GITHUB_SYNC_FAILED (ERR_GITHUB_SYNC_FAILED — CDN synced, but GitHub push/pull failed or was unreachable)."
        exit "$ERR_GITHUB_SYNC_FAILED"
    elif [ "$CDN_SYNC_HAD_ERROR" = true ]; then
        echo "⚠️  JENNA EXIT STATUS: ERRORLEVEL=$ERR_CDN_SYNC_FAILED (ERR_CDN_SYNC_FAILED — GitHub synced, but DigitalOcean Spaces rclone failed or was unreachable)."
        exit "$ERR_CDN_SYNC_FAILED"
    else
        echo "✅ JENNA EXIT STATUS: ERRORLEVEL=$ERR_SUCCESS (ERR_SUCCESS — 100% of builds, GitHub repos, and CDN assets synced)."
        exit "$ERR_SUCCESS"
    fi
}

# ============================================================================
# Helper: run_with_timeout <seconds> <command...>
# ============================================================================
# WHY MACOS NEEDS THIS PERL WATCHDOG (`timeout` isn't installed by default on macOS!):
#   Linux ships GNU `timeout`, and macOS does not. Furthermore, user-space `--timeout` flags
#   can still hang inside OS kernel DNS resolution or blackholed hotel/cafe WiFi firewalls.
#   Here, `/usr/bin/perl` (installed on every Mac & Linux system) acts as a tiny OS watchdog:
#     - `fork()` spawns a child process (`$pid == 0`), puts it in a dedicated process group
#       (`setpgrp(0, 0)`), and `exec @ARGV` runs the target command.
#     - In the parent process, `alarm $t` sets a kernel hardware timer for `$secs` seconds.
#     - If the timer fires (`$SIG{ALRM}`) before `waitpid` finishes, `kill -9, $pid` sends
#       an unblockable `SIGKILL` and exits with code `124` (the POSIX convention for timeout).
#     - Otherwise `alarm 0` cancels the timer and `$? >> 8` extracts the child's real exit code!
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
# Automatically probes GitHub reachability within 5 seconds:
# 1. Tests standard SSH on Port 22 (`ssh -T git@github.com`, where `2>&1` merges stderr into
#    stdout because GitHub prints `"Hi <user>! You've successfully authenticated"` on stderr!).
# 2. If Port 22 is blocked by a campus/cafe firewall, automatically falls back to GitHub's
#    official SSH-over-HTTPS endpoint (`ssh.github.com` on Port `443`) and updates `GIT_SSH_COMMAND`!
# 3. Also tests HTTPS git reachability (`command git ls-remote`) within 5 seconds.
# 4. If completely offline, sets `CAN_PUSH_GITHUB=false` so Jenna still builds and commits
#    locally while cleanly skipping network `git push/pull/fetch` commands.
function run_github_preflight() {
    echo "👱‍♀️ JENNA: Running 5-second GitHub pre-flight check..."
    # Abort stalled HTTP transfers if throughput drops below 1,000 bytes/sec for 5 seconds:
    export GIT_HTTP_LOW_SPEED_LIMIT=1000
    export GIT_HTTP_LOW_SPEED_TIME=5

    local ssh_ok=false
    local out22
    out22=$(run_with_timeout 5 ssh -T -o BatchMode=yes -o ConnectTimeout=4 -o StrictHostKeyChecking=accept-new git@github.com 2>&1)
    if echo "$out22" | grep -qi "successfully authenticated"; then
        ssh_ok=true
        echo "      ✓ GitHub SSH (Port 22) reachable."
    fi

    # Automatic Port 443 SSH fallback when Port 22 is firewalled:
    if [ "$ssh_ok" = false ]; then
        local out443
        out443=$(run_with_timeout 5 ssh -T -p 443 -o HostName=ssh.github.com -o BatchMode=yes -o ConnectTimeout=4 -o StrictHostKeyChecking=accept-new git@github.com 2>&1)
        if echo "$out443" | grep -qi "successfully authenticated"; then
            export GIT_SSH_COMMAND="ssh -o BatchMode=yes -o Port=443 -o HostName=ssh.github.com -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10"
            ssh_ok=true
            echo "      ✓ GitHub SSH auto-routed over Port 443 (ssh.github.com:443)."
        fi
    fi

    # Also verify HTTPS Port 443 reachability for any HTTPS-cloned remotes:
    local https_ok=false
    if run_with_timeout 5 command git ls-remote --heads https://github.com/raggiesoft/raggiesoft-narratives.git main >/dev/null 2>&1; then
        https_ok=true
        echo "      ✓ GitHub HTTPS (Port 443) reachable."
    fi

    if [ "$ssh_ok" = true ] || [ "$https_ok" = true ]; then
        CAN_PUSH_GITHUB=true
    else
        CAN_PUSH_GITHUB=false
        GITHUB_SYNC_HAD_ERROR=true
        echo "⚠️  JENNA PRE-FLIGHT: GitHub did not respond within 5 seconds on this network."
        echo "      -> Local builds and Git commits will still run; remote pushes will be skipped."
    fi
}

# ============================================================================
# Helper: run_cdn_preflight (5-Second Automatic DigitalOcean Spaces Probe)
# ============================================================================
# Tests whether DigitalOcean Spaces (`nyc3.digitaloceanspaces.com`) can complete
# a single top-level bucket listing (`lsf --max-depth 1`) within 5 seconds.
# Note `--bind 0.0.0.0` (forces IPv4 when broken WiFi IPv6 routes blackhole S3)
# and `--disable-http2` (avoids middlebox HTTP/2 framing stalls). If unreachable,
# kills the probe at 5.0s and sets `CAN_SYNC_CDN=false` so `rclone` never hangs!
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
        CDN_SYNC_HAD_ERROR=true
        echo "⚠️  JENNA PRE-FLIGHT: DigitalOcean Spaces blocked or timed out (>5s) on this WiFi."
        echo "      -> Skipping rclone CDN sync (will sync automatically next time Spaces is reachable)."
    fi
}

# ============================================================================
# Wrapper: git (Intercepts `git` Calls Using Bash's `command` Builtin!)
# ============================================================================
# HOW SHADOWING A BINARY WITH `function git()` + `command git` WORKS:
#   In Bash, if you define `function git()`, every `git ...` line below calls THIS
#   function first! Inside the function, writing `command git "$@"` tells Bash:
#   "Bypass shell functions and execute the real `/usr/bin/git` binary on `PATH`"
#   (preventing infinite recursion!).
#   - Local subcommands (`add`, `commit`, `diff-index`, `tag`, `rev-parse`) run directly.
#   - Network subcommands (`push`, `pull`, `clone`, `fetch`, `ls-remote`) check
#     `$CAN_PUSH_GITHUB` first so offline runs skip network calls instantly!
function git() {
    case "$1" in
        push|pull|clone)
            if [ "$CAN_PUSH_GITHUB" != true ]; then
                GITHUB_SYNC_HAD_ERROR=true
                echo "      ⚠️  [GitHub Unreachable] Skipping 'git $*' (saved locally)."
                return 1
            fi
            command git "$@"
            local rc=$?
            if [ $rc -ne 0 ]; then
                GITHUB_SYNC_HAD_ERROR=true
            fi
            return $rc
            ;;
        fetch|ls-remote)
            if [ "$CAN_PUSH_GITHUB" != true ]; then
                echo "      ⚠️  [GitHub Unreachable] Skipping 'git $*'."
                return 1
            fi
            command git "$@"
            ;;
        *)
            command git "$@"
            ;;
    esac
}

# ============================================================================
# Helper: run_non_interactive_npm <subcommand...>
# ============================================================================
# HOW `yes | npm --yes "$@"` + `${PIPESTATUS[1]}` WORKS:
#   - Unix `yes` prints an endless stream of `"y\n"` lines into `npm`'s stdin so any
#     unexpected `[Y/n]` prompt is answered immediately.
#   - Normally `$?` after `yes | npm` returns the exit status of the right-hand command,
#     while Bash's special `PIPESTATUS` array stores the exit code of EVERY stage in the
#     pipe (`PIPESTATUS[0]` = `yes`, `PIPESTATUS[1]` = `npm`)—returning `"${PIPESTATUS[1]}"`
#     guarantees that if `npm run build` fails, Jenna catches the exact build failure!
function run_non_interactive_npm() {
    export PATH="/opt/homebrew/bin:$PATH"
    yes 2>/dev/null | npm --yes "$@"
    return "${PIPESTATUS[1]}"
}

# ============================================================================
# Helper: auto_upgrade_nextjs_if_requested
# ============================================================================
# Proactively inspects Next.js 16.4+'s `prepareUpgrade` helper before `next build`;
# if a security patch release is flagged, installs it automatically with `--save-exact`.
function auto_upgrade_nextjs_if_requested() {
    export PATH="/opt/homebrew/bin:$PATH"
    if [ "$CAN_PUSH_GITHUB" = true ] && [ -f "./node_modules/next/dist/lib/upgrade/prepare-upgrade.js" ]; then
        local NEXT_TARGET_VER
        NEXT_TARGET_VER=$(run_with_timeout 6 node -e '
            const { prepareUpgrade } = require("./node_modules/next/dist/lib/upgrade/prepare-upgrade.js");
            prepareUpgrade(process.cwd(), "security")
                .then(r => {
                    if (r && r.status === "ready" && r.targetVersion && r.targetVersion !== r.installedVersion) {
                        process.stdout.write(r.targetVersion);
                    }
                })
                .catch(() => {});
        ' 2>/dev/null)
        if [ -n "$NEXT_TARGET_VER" ]; then
            echo "      ⚡ Next.js requested an upgrade to v${NEXT_TARGET_VER}: Auto-approving ('Yes') and installing..."
            run_non_interactive_npm install "next@${NEXT_TARGET_VER}" "eslint-config-next@${NEXT_TARGET_VER}" --save-exact
        fi
    fi
}

function show_help() {
    echo "Usage: "
    echo "  ./jenna-sync.sh --push -m \"Commit Message\" [-t \"v1.0.0\"] [--force]"
    echo "  ./jenna-sync.sh --pull"
    echo "  ./jenna-sync.sh --audit"
    echo "  ./jenna-sync.sh --indexnow"
    echo "Note: Jenna automatically tests GitHub & CDN connectivity (5s pre-flight probe) and reports back."
}

# ============================================================================
# QA Gate 1: run_integrity_check (Pre-Push WCAG & 404 Route Validator)
# ============================================================================
# Runs an inline PHP CLI script (`php -r "..."`) inside a subshell `( ... )`
# (parentheses isolate `cd "$WORKSPACE_DIR"` so the outer shell's directory never moves!).
# Scans every JSON route manifest in `raggiesoft.com/www/data/routes/*.json`:
#   1. Fails with `WCAG FAIL` if a route sets `navbarBrandLogo` without `navbarBrandAlt`!
#   2. Fails with `404 FAIL` if a route's `"view"` points to a missing `.php` file!
# If `$? -ne 0` (exit code `1`), Jenna aborts the push immediately before shipping broken code.
function run_integrity_check() {
    echo "👱‍♀️ JENNA: QA Protocol Initiated..."
    (
        cd "$WORKSPACE_DIR" && php -r "
            \$hubRoot = realpath('../raggiesoft-servers/raggiesoft.com/www') ?: realpath('../raggiesoft.com/www') ?: realpath('../raggiesoft-hub');
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

# ============================================================================
# QA Gate 2: run_orphan_audit (Detects Unrouted Pages & Exposed Drafts)
# ============================================================================
# Cross-references every `.php` view file in `raggiesoft.com/www/pages/` against
# `data/routes/*.json` and writes a timestamped report to `logs/` if it finds:
#   - `EXPOSED`: Marked `JENNA: DRAFT` inside the file, yet accidentally linked in routes!
#   - `DRAFTS` : Marked `JENNA: DRAFT` and safely unlinked.
#   - `ORPHANS`: Finished `.php` page sitting on disk with no route pointing to it.
function run_orphan_audit() {
    echo "👱‍♀️ JENNA: Starting Orphaned Page Audit..."
    if [ ! -d "$LOGS_DIR" ]; then mkdir -p "$LOGS_DIR"; fi
    
    TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
    PRETTY_DATE=$(date +"%Y-%m-%d %H:%M:%S")

    (
        cd "$WORKSPACE_DIR" && php -r "
            \$timestamp = \$argv[1];
            \$prettyDate = \$argv[2];
            \$hubRoot = realpath('../raggiesoft-servers/raggiesoft.com/www') ?: realpath('../raggiesoft.com/www') ?: realpath('../raggiesoft-hub');
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

# Official RaggieSoft IndexNow API Key (hosted at `/<INDEXNOW_KEY>.txt` on every domain)
readonly INDEXNOW_KEY="726167676965736f6674696e6465786e"

# ============================================================================
# Sitemap & Crawler Manifest Compiler: generate_sitemap
# ============================================================================
# Uses PHP CLI (`php -r`) to walk `raggiesoft.com/www/data/routes/*.json`, skip
# redirects/APIs/`noindex` routes, compute truthful `<lastmod>` dates from `.php`
# view file modification times (`filemtime`), and emit 4 crawler files:
#   1. `sitemap.xml`         (single-host routes for `https://raggiesoft.com`)
#   2. `sitemap-network.xml` (`<sitemapindex>` linking all 10 `raggiesoft.com` + subdomain sitemaps)
#   3. `robots.txt`          (crawler rules + `Sitemap:` directives)
#   4. `<INDEXNOW_KEY>.txt`  (IndexNow domain ownership verification file)
function generate_sitemap() {
    echo "👱‍♀️ JENNA: Generating XML Sitemap, robots.txt, and IndexNow verification key..."
    (
        cd "$WORKSPACE_DIR" && php -r "
            \$hubRoot = realpath('../raggiesoft-servers/raggiesoft.com/www') ?: realpath('../raggiesoft.com/www') ?: realpath('../raggiesoft-hub');
            if (!\$hubRoot || !is_dir(\$hubRoot)) {
                echo '      ❌ ERROR: Could not resolve Hub directory path.' . PHP_EOL;
                exit(1);
            }
            
            \$routesDir = \$hubRoot . '/data/routes';
            \$sitemapPath = \$hubRoot . '/sitemap.xml';
            \$robotsPath = \$hubRoot . '/robots.txt';
            \$indexNowKey = '${INDEXNOW_KEY}';
            \$indexNowPath = \$hubRoot . '/' . \$indexNowKey . '.txt';
            
            \$entries = [];
            \$todayIso = gmdate('Y-m-d');
            
            if (is_dir(\$routesDir)) {
                \$iterator = new RecursiveIteratorIterator(new RecursiveDirectoryIterator(\$routesDir));
                foreach (\$iterator as \$file) {
                    if (\$file->isFile() && strtolower(\$file->getExtension()) === 'json') {
                        \$jsonContent = file_get_contents(\$file->getPathname());
                        \$json = json_decode(\$jsonContent, true);
                        if (json_last_error() === JSON_ERROR_NONE && is_array(\$json)) {
                            \$routeFileMtime = @filemtime(\$file->getPathname()) ?: time();
                            foreach (\$json as \$route => \$config) {
                                if (\$route === 'common' || strpos(\$route, '/') !== 0) {
                                    continue;
                                }
                                // Skip redirect routes and internal JSON/API endpoints (e.g., /api/lore)
                                if (!empty(\$config['redirect']) || !empty(\$config['isApi']) || !empty(\$config['noindex'])) {
                                    continue;
                                }
                                \$canonicalRoute = (\$route !== '/') ? rtrim(\$route, '/') : '/';
                                \$fullUrl = 'https://raggiesoft.com' . \$canonicalRoute;
                                \$bestMtime = \$routeFileMtime;
                                if (!empty(\$config['view'])) {
                                    \$viewPath = \$hubRoot . '/' . \$config['view'] . '.php';
                                    if (is_file(\$viewPath)) {
                                        \$vMtime = @filemtime(\$viewPath) ?: 0;
                                        if (\$vMtime > \$bestMtime) {
                                            \$bestMtime = \$vMtime;
                                        }
                                    }
                                }
                                \$lastmod = gmdate('Y-m-d', \$bestMtime) ?: \$todayIso;
                                if (!isset(\$entries[\$fullUrl]) || \$lastmod > \$entries[\$fullUrl]) {
                                    \$entries[\$fullUrl] = \$lastmod;
                                }
                            }
                        }
                    }
                }
            }
            
            ksort(\$entries);
            
            \$xml = '<?xml version=\"1.0\" encoding=\"UTF-8\"?>' . PHP_EOL;
            \$xml .= '<urlset xmlns=\"http://www.sitemaps.org/schemas/sitemap/0.9\">' . PHP_EOL;
            
            foreach (\$entries as \$url => \$lastmod) {
                \$xml .= '  <url>' . PHP_EOL
                      . '    <loc>' . htmlspecialchars(\$url, ENT_XML1) . '</loc>' . PHP_EOL
                      . '    <lastmod>' . htmlspecialchars(\$lastmod, ENT_XML1) . '</lastmod>' . PHP_EOL
                      . '  </url>' . PHP_EOL;
            }
            \$xml .= '</urlset>' . PHP_EOL;
            
            file_put_contents(\$sitemapPath, \$xml);

            // Also generate a Domain-Property Master Sitemap Index (sitemap-network.xml)
            // referencing raggiesoft.com + all 12 *.raggiesoft.com subdomain sitemaps
            // while keeping sitemap.xml pure single-host for strict crawler parsers.
            \$networkSitemapPath = \$hubRoot . '/sitemap-network.xml';
            \$networkHosts = [
                'https://raggiesoft.com/sitemap.xml',
                'https://books.raggiesoft.com/sitemap.xml',
                'https://crossroads.raggiesoft.com/sitemap.xml',
                'https://cedarrun.raggiesoft.com/sitemap.xml',
                'https://waystation.raggiesoft.com/sitemap.xml',
                'https://jessica.raggiesoft.com/sitemap.xml',
                'https://music.raggiesoft.com/sitemap.xml',
                'https://lore.raggiesoft.com/sitemap.xml',
                'https://engineroom.raggiesoft.com/sitemap.xml',
                'https://stardust.raggiesoft.com/sitemap.xml',
                'https://backstage.raggiesoft.com/sitemap.xml',
                'https://corporate.raggiesoft.com/sitemap.xml',
                'https://storetrainer.raggiesoft.com/sitemap.xml',
                'https://nebulae.raggiesoft.com/sitemap.xml',
            ];
            \$netXml = '<?xml version=\"1.0\" encoding=\"UTF-8\"?>' . PHP_EOL;
            \$netXml .= '<sitemapindex xmlns=\"http://www.sitemaps.org/schemas/sitemap/0.9\">' . PHP_EOL;
            foreach (\$networkHosts as \$smUrl) {
                \$netXml .= '  <sitemap>' . PHP_EOL
                         . '    <loc>' . htmlspecialchars(\$smUrl, ENT_XML1) . '</loc>' . PHP_EOL
                         . '    <lastmod>' . htmlspecialchars(\$todayIso, ENT_XML1) . '</lastmod>' . PHP_EOL
                         . '  </sitemap>' . PHP_EOL;
            }
            \$netXml .= '</sitemapindex>' . PHP_EOL;
            file_put_contents(\$networkSitemapPath, \$netXml);
            
            \$robotsContent = implode(PHP_EOL, [
                '# RaggieSoft Hub (https://raggiesoft.com)',
                'User-agent: *',
                'Allow: /',
                'Disallow: /api/',
                '',
                'Sitemap: https://raggiesoft.com/sitemap.xml',
                'Sitemap: https://raggiesoft.com/sitemap-network.xml',
                ''
            ]);
            file_put_contents(\$robotsPath, \$robotsContent);
            file_put_contents(\$indexNowPath, \$indexNowKey);
            
            echo '      ✓ Generated sitemap.xml (' . count(\$entries) . ' routes) + sitemap-network.xml (13 RaggieSoft hosts).' . PHP_EOL;
            echo '      ✓ Generated robots.txt + IndexNow key (' . \$indexNowKey . '.txt).' . PHP_EOL;
        "
    )
}

# ============================================================================
# Helper: trigger_remote_sarah_deploy
# ============================================================================
# Performs a 5-second non-interactive SSH pre-flight check directly to the NYC1
# Droplet IPv4 (`michael@142.93.244.239`, since `jessica.raggiesoft.com` is now an
# Orange-Cloud proxied web property on Cloudflare!). When reachable, triggers
# `/home/michael/sarah-deploy.sh` immediately so newly pushed GitHub commits,
# self-upgrading Sarah script updates, and validated Nginx `.conf` updates deploy
# live in seconds rather than waiting up to 5 minutes for `sarah.timer`.
function trigger_remote_sarah_deploy() {
    echo "👱‍♀️ JENNA: Checking SSH link to NYC1 host (142.93.244.239) for instant Sarah wakeup..."
    if run_with_timeout 5 ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=4 michael@142.93.244.239 true >/dev/null 2>&1; then
        echo "      ✓ Connected to NYC1 host! Waking Sarah for immediate live deployment..."
        if run_with_timeout 120 ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=8 michael@142.93.244.239 '/home/michael/sarah-deploy.sh'; then
            echo "      ✓ Sarah completed live server sync (web roots, scripts, and Nginx verified)."
        else
            echo "      ⚠️  Remote Sarah wakeup exited non-zero or timed out; sarah.timer will reconcile automatically."
        fi
    else
        echo "      ℹ️  SSH port 22 unreachable on current network; sarah.timer on NYC1 will pull within 5 minutes."
    fi
}

# ============================================================================
# Helper: submit_indexnow_pings
# ============================================================================
# Submits canonical URLs from every compiled RaggieSoft property's XML sitemaps
# to `https://api.indexnow.org/indexnow` (Bing, Yandex, DuckDuckGo, Naver, Seznam,
# Yep) using non-blocking 6-second bounded requests. Never fails the build even
# if a subdomain is offline or not yet provisioned on the remote server.
function submit_indexnow_pings() {
    echo "👱‍♀️ JENNA: Broadcasting updated canonical URLs via IndexNow (Bing, DuckDuckGo, Yandex, Yep)..."
    local SITEMAP_ROOTS=(
        "$HUB_ROOT"
        "$MUSIC_ROOT/build"
        "$BOOKS_ROOT"
        "$ENGINEROOM_ROOT/dist"
        "$STARDUST_ROOT/.output/public"
        "$CORPORATE_ROOT/dist"
        "$STORETRAINER_ROOT/dist"
        "$BACKSTAGE_ROOT/dist"
        "$CEDARRUN_ROOT/dist"
        "$CROSSROADS_ROOT/dist"
        "$WAYSTATION_ROOT/dist"
        "$JESSICA_ROOT/dist"
        "$NEBULAE_ROOT"
        "$LORE_ROOT/out"
        "$PORTFOLIO_ROOT/dist/raggiesoft-portfolio/browser"
    )

    for web_dir in "${SITEMAP_ROOTS[@]}"; do
        if [ ! -d "$web_dir" ]; then
            continue
        fi
        local PAYLOAD_INFO
        PAYLOAD_INFO=$(python3 - "$web_dir" "$INDEXNOW_KEY" <<'PYEOF' 2>/dev/null || true
import sys, os, glob, json, urllib.parse, xml.etree.ElementTree as ET

web_dir, key = sys.argv[1], sys.argv[2]
xml_files = sorted(glob.glob(os.path.join(web_dir, "sitemaps", "*.xml")))
if not xml_files:
    sm = os.path.join(web_dir, "sitemap.xml")
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

print(host + "\t" + str(len(urls[:10000])) + "\t" + json.dumps({
    "host": host,
    "key": key,
    "keyLocation": f"https://{host}/{key}.txt",
    "urlList": urls[:10000]
}))
PYEOF
)
        if [ -z "$PAYLOAD_INFO" ]; then
            continue
        fi
        local HOST_NAME URL_COUNT JSON_BODY
        HOST_NAME=$(printf '%s' "$PAYLOAD_INFO" | cut -f1)
        URL_COUNT=$(printf '%s' "$PAYLOAD_INFO" | cut -f2)
        JSON_BODY=$(printf '%s' "$PAYLOAD_INFO" | cut -f3-)

        local HTTP_CODE
        HTTP_CODE=$(run_with_timeout 6 curl -sS -o /dev/null -w "%{http_code}" --max-time 5 \
            -H "Content-Type: application/json; charset=utf-8" \
            -d "$JSON_BODY" \
            "https://api.indexnow.org/indexnow" 2>/dev/null || echo "000")
        echo "      ✓ ${HOST_NAME}: submitted ${URL_COUNT} URLs (HTTP ${HTTP_CODE})"
    done
}

# ============================================================================
# Mode 1: do_pull (`./jenna-sync.sh --pull`)
# ============================================================================
# Pulls latest `origin/main` commits across all 15 GitHub repositories (cloning
# any missing repo automatically) and pulls public CDN files down from DigitalOcean
# Spaces (`do-spaces:assets.raggiesoft.com` -> `$ASSETS_ROOT`).
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

    echo "   5.65 Checking Engine Room Records, Stardust Engine, Corporate, StoreTrainer & Backstage Subdomains..."
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
    if [ -d "$BACKSTAGE_ROOT/.git" ] && (cd "$BACKSTAGE_ROOT" && git remote get-url origin &>/dev/null); then
        cd "$BACKSTAGE_ROOT" && git pull origin main
    fi
    if [ ! -d "$CEDARRUN_ROOT" ]; then
        echo "      > Repository missing. Cloning raggiesoft-cedar-run from GitHub..."
        mkdir -p "$(dirname "$CEDARRUN_ROOT")"
        git clone https://github.com/raggiesoft/raggiesoft-cedar-run.git "$CEDARRUN_ROOT" 2>/dev/null || true
    elif [ -d "$CEDARRUN_ROOT/.git" ] && (cd "$CEDARRUN_ROOT" && git remote get-url origin &>/dev/null); then
        cd "$CEDARRUN_ROOT" && git pull origin main
    fi
    if [ ! -d "$CROSSROADS_ROOT" ]; then
        echo "      > Repository missing. Cloning raggiesoft-crossroads from GitHub..."
        mkdir -p "$(dirname "$CROSSROADS_ROOT")"
        git clone https://github.com/raggiesoft/raggiesoft-crossroads.git "$CROSSROADS_ROOT" 2>/dev/null || true
    elif [ -d "$CROSSROADS_ROOT/.git" ] && (cd "$CROSSROADS_ROOT" && git remote get-url origin &>/dev/null); then
        cd "$CROSSROADS_ROOT" && git pull origin main
    fi
    if [ ! -d "$WAYSTATION_ROOT" ]; then
        echo "      > Repository missing. Cloning raggiesoft-waystation from GitHub..."
        mkdir -p "$(dirname "$WAYSTATION_ROOT")"
        git clone https://github.com/raggiesoft/raggiesoft-waystation.git "$WAYSTATION_ROOT" 2>/dev/null || true
    elif [ -d "$WAYSTATION_ROOT/.git" ] && (cd "$WAYSTATION_ROOT" && git remote get-url origin &>/dev/null); then
        cd "$WAYSTATION_ROOT" && git pull origin main
    fi
    if [ ! -d "$JESSICA_ROOT" ]; then
        echo "      > Repository missing. Cloning raggiesoft-jessica from GitHub..."
        mkdir -p "$(dirname "$JESSICA_ROOT")"
        git clone https://github.com/raggiesoft/raggiesoft-jessica.git "$JESSICA_ROOT" 2>/dev/null || true
    elif [ -d "$JESSICA_ROOT/.git" ] && (cd "$JESSICA_ROOT" && git remote get-url origin &>/dev/null); then
        cd "$JESSICA_ROOT" && git pull origin main
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

    echo "   5.9 Checking Desktop App Repositories (desktop-apps/storetrainer)..."
    if [ ! -d "$DESKTOP_STORETRAINER_ROOT" ]; then
        echo "      > Repository missing. Cloning storetrainer from GitHub..."
        mkdir -p "$DESKTOP_APPS_ROOT"
        git clone https://github.com/raggiesoft/storetrainer.git "$DESKTOP_STORETRAINER_ROOT" 2>/dev/null || true
    elif [ -d "$DESKTOP_STORETRAINER_ROOT/.git" ] && (cd "$DESKTOP_STORETRAINER_ROOT" && git remote get-url origin &>/dev/null); then
        cd "$DESKTOP_STORETRAINER_ROOT" && git pull origin main
    fi
    
    # Pull public CDN assets down from DigitalOcean Spaces (`rclone sync <remote> <local>`),
    # excluding `.git/` and private `vault/`/`master-wav/` paths so local Git metadata isn't wiped!
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
        if [ $? -ne 0 ]; then
            CDN_SYNC_HAD_ERROR=true
            echo "⚠️  JENNA: DigitalOcean Spaces rclone sync reported an error."
        else
            echo "👱‍♀️ JENNA: All done! Your local files are perfectly synced."
        fi
    else
        echo "👱‍♀️ JENNA: Git pull complete! (DigitalOcean Spaces CDN sync skipped on this WiFi.)"
    fi
    finalize_jenna_exit
}

# ============================================================================
# Mode 2: do_push (`./jenna-sync.sh --push -m "Message" [-t "v1.0.0"]`)
# ============================================================================
function do_push() {
    # Require a commit message (`-m`) or release tag (`-t`) so history stays documented
    if [[ -z "$COMMIT_MSG" && -z "$TAG_NAME" ]]; then
        echo "🛑 JENNA: MISSING COMMIT MESSAGE"
        show_help
        exit 1
    fi
    
    if [[ -z "$COMMIT_MSG" ]]; then
        COMMIT_MSG="Jenna: Automated sync for release $TAG_NAME"
    fi

    run_github_preflight

    # --- PRE-FLIGHT RELEASE TAG COLLISION CHECK ---
    # If `-t "v1.x.y"` was passed, verify neither local `git show-ref --tags` nor remote
    # `git ls-remote --tags` already has that tag before modifying any repository!
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

    # 1. QA Check (WCAG Alt Text + Missing PHP View 404 Guard)
    run_integrity_check

    # 0. SYNC SHARED COMPONENTS LIBRARY (`command cp -rf` bypasses any `alias cp='cp -i'` prompt!)
    echo "   -> Syncing /components-library to applications..."
    if [ -d "$SERVER_ROOT/components-library" ]; then
        if [ -d "$HUB_ROOT" ]; then
            command cp -rf "$SERVER_ROOT/components-library/"* "$HUB_ROOT/includes/"
            echo "      ✓ Synced components to raggiesoft-hub"
        fi
        if [ -d "$BOOKS_ROOT" ]; then
            command cp -rf "$SERVER_ROOT/components-library/"* "$BOOKS_ROOT/includes/"
            echo "      ✓ Synced components to raggiesoft-book-library"
        fi
    fi

    # 2. Orphan & Exposed-Draft Audit
    run_orphan_audit

    # 3. Generate Hub XML Sitemaps, `robots.txt`, & IndexNow Key
    generate_sitemap

    echo "👱‍♀️ JENNA: Shipping it! Message: \"$COMMIT_MSG\""
    if [ -n "$TAG_NAME" ]; then
        echo "          Applying Tag: $TAG_NAME"
    fi
    if [ -n "$FORCE_FLAG" ]; then
        echo "          ⚠️ EXECUTING FORCE PUSH PROTOCOL ⚠️"
    fi
    echo "          $CONNECTION_MSG"

    # --- PRE-PUSH NARRATIVE, ASSET MINIFICATION, PAIGE, & PANDOC EBOOK PIPELINE ---
    echo "👱‍♀️ JENNA: Generating AI Context Lumps..."
    if [ -f "$NARRATIVES_ROOT/scripts/lump_narratives.php" ]; then
        php "$NARRATIVES_ROOT/scripts/lump_narratives.php"
        if [ $? -ne 0 ]; then
            echo "⚠️  JENNA: Warning - Failed to generate AI lumps, continuing anyway..."
        fi
    fi

    echo "      > Building Stardust Engine Assets..."
    # Inline PHP CSS/JS Minifier: concatenates `css/src/*.css`, strips `/* ... */` block comments
    # and extra whitespace via `preg_replace` / `str_replace`, and emits `.min.css` & `.min.js`!
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

    # Invoke Paige (`paige.php`) to compile all book TOCs, Story Crossroads graphs, Story Arcs,
    # hovercards, `<slug>-package.7z` archives, `search-index.json`, and Book Reader XML sitemaps!
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

    # Invoke `compile_ebooks.php` (uses Pandoc + WeasyPrint + `.ebook_build_hash` incremental caching
    # to render Illustrated & Text-Only `.epub` and `.pdf` deliverables into `raggiesoft-assets/raggiesoft-books/books/<slug>/`).
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

    # ============================================================================
    # HOW JENNA'S 3-BRANCH GIT COMMIT & PUSH IDIOM WORKS (REPEATED PER REPOSITORY):
    #   1. `git add .` (or `git add -A`) stages modified, added, and deleted files.
    #   2. `if ! git diff-index --quiet HEAD --; then`:
    #      `git diff-index --quiet HEAD --` returns exit code `1` (false) when staged
    #      changes exist! `!` flips that to true -> commits with `$COMMIT_MSG` & pushes.
    #   3. `elif [ "$(git log origin/main..HEAD 2>/dev/null)" ]; then`:
    #      What if we committed locally earlier on airplane/blocked WiFi (`CAN_PUSH_GITHUB=false`)
    #      and now have WiFi again with zero new file edits? `origin/main..HEAD` lists any
    #      local commits ahead of GitHub and pushes them automatically!
    #   4. `else`: Repository is 100% clean & synced—skip in milliseconds!
    # ============================================================================

    # 4. HUB PUSH (`raggiesoft.com/www`)
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

    # 4.7 NEBULAE PUSH (`nebulae.raggiesoft.com`)
    echo "   -> Packaging the Nebulae Cosmic Observatory (nebulae.raggiesoft.com)..."
    if [ -d "$NEBULAE_ROOT" ]; then
        cd "$NEBULAE_ROOT"
        if [ -f "$NEBULAE_ROOT/package.json" ]; then
            run_non_interactive_npm run build
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

    # 4.75 BOOKS REPO PUSH (`books.raggiesoft.com` — includes fresh route maps & sitemaps generated by `paige.php`!)
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

    # 4.8 LORE PUSH (`lore.raggiesoft.com` — Next.js 16 + React 19 + Tailwind CSS v4 Static Graph)
    # Note the self-healing Next.js 16 security auto-upgrade pattern:
    #   1. `auto_upgrade_nextjs_if_requested` checks if Next.js has published a required security patch.
    #   2. Runs `npm run build` via `run_non_interactive_npm` (`< /dev/null`).
    #   3. If `$? -ne 0` (`$?` = exit code of the immediately preceding command; `-ne 0` = non-zero / failed),
    #      re-runs `auto_upgrade_nextjs_if_requested` + `npm run build` once before aborting (`exit 1`)!
    echo "   -> Packaging the Lore Graph..."
    if [ -d "$LORE_ROOT" ]; then
        cd "$LORE_ROOT"
        
        auto_upgrade_nextjs_if_requested
        echo "      > Compiling Static HTML Graph..."
        run_non_interactive_npm run build
        if [ $? -ne 0 ]; then
            echo "      ⚠️  Next.js build requested a retry; re-running automatically..."
            auto_upgrade_nextjs_if_requested
            run_non_interactive_npm run build
            if [ $? -ne 0 ]; then
                echo "🛑 JENNA: ABORTING! Next.js static build failed in raggiesoft-lore."
                exit 1
            fi
        fi
        
        git add .
        
        # `! git diff-index --quiet HEAD --` is true when staged/working files differ from `HEAD`:
        if ! git diff-index --quiet HEAD --; then
             git commit -m "$COMMIT_MSG"
             git push $FORCE_FLAG origin main
             echo "      ✓ Lore committed and sent to GitHub."
        # Otherwise check if local `HEAD` has unpushed commits ahead of `origin/main` (`origin/main..HEAD`):
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

    # 4.9 MUSIC PUSH (`music.raggiesoft.com` — The Listening Room, SvelteKit 2 + Svelte 5 Runes)
    # Runs BOTH `npm run build` (compiles the production SvelteKit bundle & service worker) AND
    # `npm run check` (`svelte-check` static TypeScript/Runes type-checker). If type-checking fails
    # (`$? -ne 0`), Jenna halts immediately (`exit 1`) so broken UI types never ship!
    echo "   -> Packaging Engine Room Records (music.raggiesoft.com)..."
    if [ -d "$MUSIC_ROOT" ]; then
        cd "$MUSIC_ROOT"
        
        echo "      > Compiling dynamic Engine Room Records catalog & static PWA build..."
        run_non_interactive_npm run build
        run_non_interactive_npm run check
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

    # ============================================================================
    # 4.95–4.99 SPECIALIZED STATIC SUBDOMAIN BUILDS & GIT PUSHES
    # ============================================================================
    # HOW THE GIT GUARD CONDITIONS WORK IN SECTIONS 4.95–4.99:
    #   - `git add -A`: Stages all new, modified, AND deleted files across the repo.
    #   - `! git rev-parse --verify HEAD &>/dev/null`: Handles a brand-new `git init` repo
    #     that has ZERO commits yet (where `HEAD` does not exist yet, so `diff-index HEAD` fails!).
    #   - `if git remote get-url origin &>/dev/null`: Checks whether a GitHub `origin` URL is
    #     configured yet—if yes, pushes with `git push -u` (`-u` = `--set-upstream`, linking local
    #     `main` to `origin/main` for future pulls/pushes); if no, commits cleanly locally!

    # 4.95 ENGINE ROOM RECORDS IMPRINT PUSH (`engineroom.raggiesoft.com` — Astro 6 Static SSG)
    if [ -d "$ENGINEROOM_ROOT" ] && [ -f "$ENGINEROOM_ROOT/package.json" ]; then
        echo "   -> Packaging Engine Room Records Imprint (engineroom.raggiesoft.com)..."
        cd "$ENGINEROOM_ROOT"
        run_non_interactive_npm run build
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

    # 4.96 THE STARDUST ENGINE PUSH (`stardust.raggiesoft.com` — Nuxt 4 + Vue 3 Static SSG)
    if [ -d "$STARDUST_ROOT" ] && [ -f "$STARDUST_ROOT/package.json" ]; then
        echo "   -> Packaging The Stardust Engine (stardust.raggiesoft.com)..."
        cd "$STARDUST_ROOT"
        run_non_interactive_npm run build
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

    # 4.97 RAGGIESOFT MEDIA CORPORATE HUB PUSH (`corporate.raggiesoft.com` — Bootstrap 5.3.8 Static SSG)
    if [ -d "$CORPORATE_ROOT" ] && [ -f "$CORPORATE_ROOT/package.json" ]; then
        echo "   -> Packaging RaggieSoft Media Corporate Hub (corporate.raggiesoft.com)..."
        cd "$CORPORATE_ROOT"
        run_non_interactive_npm run build
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

    # 4.98 RAGGIESOFT STORETRAINER PUSH (`storetrainer.raggiesoft.com` — Vanilla TypeScript + Classic Win32 CSS)
    if [ -d "$STORETRAINER_ROOT" ] && [ -f "$STORETRAINER_ROOT/package.json" ]; then
        echo "   -> Packaging RaggieSoft StoreTrainer (storetrainer.raggiesoft.com)..."
        cd "$STORETRAINER_ROOT"
        run_non_interactive_npm run build
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

    # 4.99 RAGGIESOFT BACKSTAGE PUSH (`backstage.raggiesoft.com` — Web Awesome Pro + Font Awesome Pro+ SSG & PWA)
    if [ -d "$BACKSTAGE_ROOT" ] && [ -f "$BACKSTAGE_ROOT/package.json" ]; then
        echo "   -> Packaging RaggieSoft Backstage (backstage.raggiesoft.com)..."
        cd "$BACKSTAGE_ROOT"
        run_non_interactive_npm run build
        if [ $? -ne 0 ]; then
            echo "🛑 JENNA: ABORTING! Web Awesome Pro SSG build failed in backstage.raggiesoft.com."
            exit 1
        fi
        if [ -d "$BACKSTAGE_ROOT/.git" ]; then
            git add -A
            if ! git diff-index --quiet HEAD -- 2>/dev/null || ! git rev-parse --verify HEAD &>/dev/null; then
                git commit -m "$COMMIT_MSG"
                if git remote get-url origin &>/dev/null; then
                    git push -u $FORCE_FLAG origin main
                    echo "      ✓ RaggieSoft Backstage committed and sent to GitHub."
                else
                    echo "      ✓ RaggieSoft Backstage committed locally (awaiting GitHub 'origin' remote)."
                fi
            elif git remote get-url origin &>/dev/null && ( ! git rev-parse --verify origin/main &>/dev/null || [ "$(git log origin/main..HEAD 2>/dev/null)" ] ); then
                git push -u $FORCE_FLAG origin main
                echo "      ✓ Pending RaggieSoft Backstage code sent to GitHub."
            else
                echo "      (RaggieSoft Backstage is clean and up to date.)"
            fi
        fi
    fi

    # 4.995 CEDAR RUN LAUNCHPAD PUSH (`cedarrun.raggiesoft.com` — SolidJS + TypeScript + Vite Static SSG)
    if [ -d "$CEDARRUN_ROOT" ] && [ -f "$CEDARRUN_ROOT/package.json" ]; then
        echo "   -> Packaging Cedar Run Wilderness Launchpad (cedarrun.raggiesoft.com)..."
        cd "$CEDARRUN_ROOT"
        run_non_interactive_npm run build
        if [ $? -ne 0 ]; then
            echo "🛑 JENNA: ABORTING! SolidJS SSG build failed in cedarrun.raggiesoft.com."
            exit 1
        fi
        if [ -d "$CEDARRUN_ROOT/.git" ]; then
            git add -A
            if ! git diff-index --quiet HEAD -- 2>/dev/null || ! git rev-parse --verify HEAD &>/dev/null; then
                git commit -m "$COMMIT_MSG"
                if git remote get-url origin &>/dev/null; then
                    git push -u $FORCE_FLAG origin main
                    echo "      ✓ Cedar Run Launchpad committed and sent to GitHub."
                else
                    echo "      ✓ Cedar Run Launchpad committed locally (awaiting GitHub 'origin' remote)."
                fi
            elif git remote get-url origin &>/dev/null && ( ! git rev-parse --verify origin/main &>/dev/null || [ "$(git log origin/main..HEAD 2>/dev/null)" ] ); then
                git push -u $FORCE_FLAG origin main
                echo "      ✓ Pending Cedar Run Launchpad code sent to GitHub."
            else
                echo "      (Cedar Run Launchpad is clean and up to date.)"
            fi
        fi
    fi

    # 4.996 RAGGIESOFT STORY CROSSROADS PUSH (`crossroads.raggiesoft.com` — Eleventy v3 + Lit 3 + TypeScript SSG)
    if [ -d "$CROSSROADS_ROOT" ] && [ -f "$CROSSROADS_ROOT/package.json" ]; then
        echo "   -> Packaging RaggieSoft Story Crossroads (crossroads.raggiesoft.com)..."
        cd "$CROSSROADS_ROOT"
        if [ ! -d "$CROSSROADS_ROOT/node_modules" ]; then
            echo "      > Installing Eleventy v3 + Lit 3 dependencies non-interactively..."
            run_non_interactive_npm install
        fi
        run_non_interactive_npm run build
        if [ $? -ne 0 ]; then
            echo "🛑 JENNA: ABORTING! Eleventy v3 + Lit 3 SSG build failed in crossroads.raggiesoft.com."
            exit 1
        fi
        if [ -d "$CROSSROADS_ROOT/.git" ]; then
            git add -A
            if ! git diff-index --quiet HEAD -- 2>/dev/null || ! git rev-parse --verify HEAD &>/dev/null; then
                git commit -m "$COMMIT_MSG"
                if git remote get-url origin &>/dev/null; then
                    git push -u $FORCE_FLAG origin main
                    echo "      ✓ Story Crossroads committed and sent to GitHub."
                else
                    echo "      ✓ Story Crossroads committed locally (awaiting GitHub 'origin' remote)."
                fi
            elif git remote get-url origin &>/dev/null && ( ! git rev-parse --verify origin/main &>/dev/null || [ "$(git log origin/main..HEAD 2>/dev/null)" ] ); then
                git push -u $FORCE_FLAG origin main
                echo "      ✓ Pending Story Crossroads code sent to GitHub."
            else
                echo "      (Story Crossroads is clean and up to date.)"
            fi
        fi
    fi

    # 4.997 UNCHARTED WAYSTATION PUSH (`waystation.raggiesoft.com` — Mithril.js + TypeScript Hyperscript SSG)
    if [ -d "$WAYSTATION_ROOT" ] && [ -f "$WAYSTATION_ROOT/package.json" ]; then
        echo "   -> Packaging The Uncharted Waystation (waystation.raggiesoft.com)..."
        cd "$WAYSTATION_ROOT"
        if [ ! -d "$WAYSTATION_ROOT/node_modules" ]; then
            echo "      > Installing Mithril.js + TypeScript dependencies non-interactively..."
            run_non_interactive_npm install
        fi
        run_non_interactive_npm run build
        if [ $? -ne 0 ]; then
            echo "🛑 JENNA: ABORTING! Mithril.js SSG build failed in waystation.raggiesoft.com."
            exit 1
        fi
        if [ -d "$WAYSTATION_ROOT/.git" ]; then
            git add -A
            if ! git diff-index --quiet HEAD -- 2>/dev/null || ! git rev-parse --verify HEAD &>/dev/null; then
                git commit -m "$COMMIT_MSG"
                if git remote get-url origin &>/dev/null; then
                    git push -u $FORCE_FLAG origin main
                    echo "      ✓ Uncharted Waystation committed and sent to GitHub."
                else
                    echo "      ✓ Uncharted Waystation committed locally (awaiting GitHub 'origin' remote)."
                fi
            elif git remote get-url origin &>/dev/null && ( ! git rev-parse --verify origin/main &>/dev/null || [ "$(git log origin/main..HEAD 2>/dev/null)" ] ); then
                git push -u $FORCE_FLAG origin main
                echo "      ✓ Pending Uncharted Waystation code sent to GitHub."
            else
                echo "      (Uncharted Waystation is clean and up to date.)"
            fi
        fi
    fi

    # 4.998 JESSICA SANCTUARY GUIDE PUSH (`jessica.raggiesoft.com` — Preact 10 + Signals + TypeScript + Vite Static SSG)
    if [ -d "$JESSICA_ROOT" ] && [ -f "$JESSICA_ROOT/package.json" ]; then
        echo "   -> Packaging Jessica — Keeper of the House (jessica.raggiesoft.com)..."
        cd "$JESSICA_ROOT"
        if [ ! -d "$JESSICA_ROOT/node_modules" ]; then
            echo "      > Installing Preact 10 + Signals + TypeScript dependencies non-interactively..."
            run_non_interactive_npm install
        fi
        run_non_interactive_npm run build
        if [ $? -ne 0 ]; then
            echo "🛑 JENNA: ABORTING! Preact + Signals SSG build failed in jessica.raggiesoft.com."
            exit 1
        fi
        if [ -d "$JESSICA_ROOT/.git" ]; then
            git add -A
            if ! git diff-index --quiet HEAD -- 2>/dev/null || ! git rev-parse --verify HEAD &>/dev/null; then
                git commit -m "$COMMIT_MSG"
                if git remote get-url origin &>/dev/null; then
                    git push -u $FORCE_FLAG origin main
                    echo "      ✓ Jessica Sanctuary Guide committed and sent to GitHub."
                else
                    echo "      ✓ Jessica Sanctuary Guide committed locally (awaiting GitHub 'origin' remote)."
                fi
            elif git remote get-url origin &>/dev/null && ( ! git rev-parse --verify origin/main &>/dev/null || [ "$(git log origin/main..HEAD 2>/dev/null)" ] ); then
                git push -u $FORCE_FLAG origin main
                echo "      ✓ Pending Jessica Sanctuary Guide code sent to GitHub."
            else
                echo "      (Jessica Sanctuary Guide is clean and up to date.)"
            fi
        fi
    fi


    # 4.10 PORTFOLIO PUSH (`michaelpragsdale.com` — Angular 19 Zoneless Build)
    echo "   -> Packaging Executive Systems Architect Dossier (michaelpragsdale.com)..."
    if [ -d "$PORTFOLIO_ROOT" ]; then
        cd "$PORTFOLIO_ROOT"

        echo "      > Compiling Angular 19 Zoneless static build..."
        run_non_interactive_npm run build
        if [ $? -ne 0 ]; then
            echo "🛑 JENNA: ABORTING! Angular production build failed in raggiesoft-portfolio."
            exit 1
        fi

        if [ -d "$PORTFOLIO_ROOT/.git" ]; then
            # If the local repo was re-initialized without common ancestor (`! git merge-base`),
            # `git reset --soft origin/main` keeps our newly built working files while attaching cleanly onto `origin/main`!
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

    # 4.11 DEPLOYMENT TOOLS PUSH (`/raggiesoft-deployment-tools` — syncs Jenna, Sarah, Paige, & Harper to GitHub!)
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

    # 4.12 NGINX CONFIG PUSH (`/nginx-config` — picked up atomically by Sarah's `sync_nginx_vhosts`!)
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

    # 4.13 DESKTOP STORETRAINER REPOSITORY PUSH (`/desktop-apps/storetrainer` -> github.com/raggiesoft/storetrainer)
    echo "   -> Packaging Desktop StoreTrainer Repository (/desktop-apps/storetrainer)..."
    if [ -d "$DESKTOP_STORETRAINER_ROOT/.git" ]; then
        cd "$DESKTOP_STORETRAINER_ROOT"
        # Non-interactive .NET 10 pre-push compile check if dotnet SDK is installed locally
        if [ -f "$DESKTOP_STORETRAINER_ROOT/dotnet-v2.0/StoreTrainer/StoreTrainer.csproj" ]; then
            if command -v dotnet &>/dev/null; then
                DOTNET_CLI_TELEMETRY_OPTOUT=1 DOTNET_NOLOGO=1 dotnet build "$DESKTOP_STORETRAINER_ROOT/dotnet-v2.0/StoreTrainer/StoreTrainer.csproj" --verbosity quiet
                if [ $? -ne 0 ]; then
                    echo "🛑 JENNA: ABORTING! StoreTrainer 2.0 .NET 10 build failed."
                    exit 1
                fi
            elif [ -x "/opt/homebrew/bin/dotnet" ]; then
                DOTNET_CLI_TELEMETRY_OPTOUT=1 DOTNET_NOLOGO=1 /opt/homebrew/bin/dotnet build "$DESKTOP_STORETRAINER_ROOT/dotnet-v2.0/StoreTrainer/StoreTrainer.csproj" --verbosity quiet
                if [ $? -ne 0 ]; then
                    echo "🛑 JENNA: ABORTING! StoreTrainer 2.0 .NET 10 build failed."
                    exit 1
                fi
            fi
        fi

        git add -A

        if ! git diff-index --quiet HEAD -- 2>/dev/null || ! git rev-parse --verify HEAD &>/dev/null; then
            git commit -m "$COMMIT_MSG"
            if git remote get-url origin &>/dev/null; then
                git push -u $FORCE_FLAG origin main
                echo "      ✓ StoreTrainer Desktop repo committed and sent to GitHub."
            else
                echo "      ✓ StoreTrainer Desktop repo committed locally."
            fi
        elif git remote get-url origin &>/dev/null && ( ! git rev-parse --verify origin/main &>/dev/null || [ "$(git log origin/main..HEAD 2>/dev/null)" ] ); then
            echo "      ⚠️  Found pending StoreTrainer Desktop commits. Pushing now..."
            git push -u $FORCE_FLAG origin main
            echo "      ✓ Pending StoreTrainer Desktop commits sent to GitHub."
        else
            echo "      (StoreTrainer Desktop repo is clean and up to date.)"
        fi
    fi

    # 5. ASSETS REPOSITORY PUSH (`raggiesoft-assets` -> GitHub)
    echo "   2. Packaging the Assets Repository..."
    cd "$ASSETS_ROOT"
    
    echo "      > Building Stardust Engine Assets..."
    # Re-verify `.min.css` and `.min.js` right before staging `raggiesoft-assets`
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
    
    # 6. DIGITALOCEAN SPACES CDN SYNC (`rclone sync "$ASSETS_ROOT" do-spaces:assets.raggiesoft.com`)
    # HOW `rclone sync` & SECURITY EXCLUSIONS WORK:
    #   - `rclone sync <source> <dest>` makes the S3/Spaces bucket `assets.raggiesoft.com`
    #     an exact 1:1 mirror of `$ASSETS_ROOT`—uploading new/modified files AND pruning deleted ones!
    #   - `--s3-acl public-read` marks uploaded images, 128k MP3s, and eBooks world-readable over HTTPS.
    #   - `--exclude "/.git/**"`, `--exclude "**/vault/**"`, and `--exclude "**/master-wav/**"`
    #     guarantee internal Git history and lossless studio master audio NEVER reach public CDN storage!
    echo "   3. Beaming public web assets to the CDN (Vaults & Master-WAVs excluded)..."
    run_cdn_preflight
    if [ "$CAN_SYNC_CDN" = true ]; then
        "$RCLONE_BIN" sync "$ASSETS_ROOT" do-spaces:assets.raggiesoft.com \
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
        if [ $? -ne 0 ]; then
            CDN_SYNC_HAD_ERROR=true
            echo "⚠️  JENNA: DigitalOcean Spaces rclone sync reported an error."
        else
            echo "👱‍♀️ JENNA: Success! All public assets are synced 1:1 on the CDN (stale files pruned), and your local vaults remain safely off DigitalOcean Spaces. Sarah will pick this up shortly."
        fi
    else
        echo "👱‍♀️ JENNA: Finished! Code/narratives are committed (and pushed if GitHub was reachable); CDN sync was skipped because DigitalOcean Spaces is blocked on this WiFi."
    fi
    # Wake Sarah over SSH for immediate live server deployment & ping IndexNow search engines
    if [ "$CAN_PUSH_GITHUB" = true ]; then
        trigger_remote_sarah_deploy
        submit_indexnow_pings
    fi
    finalize_jenna_exit
}

# ============================================================================
# 4. UNIFIED CLI ARGUMENT PARSER & ACTION DISPATCHER
# ============================================================================
ACTION=""
COMMIT_MSG=""
TAG_NAME=""
FORCE_FLAG=""

# Parse flags one-by-one (`shift` advances `$2 -> $1`; flags with a value like `-m "msg"` call `shift` twice!)
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --push) ACTION="push" ;;
        --pull) ACTION="pull" ;;
        --audit) ACTION="audit" ;;
        --indexnow) ACTION="indexnow" ;;
        --force) FORCE_FLAG="--force" ;;
        --msg|-m) COMMIT_MSG="$2"; shift ;;
        --tag|-t) TAG_NAME="$2"; shift ;;
        *) echo "👱‍♀️ JENNA: I don't recognize the command '$1'."; show_help; exit 1 ;;
    esac
    shift
done

# `-P` = live progress readout, `--transfers=8` = 8 parallel S3 file streams at once
RCLONE_PERF_FLAGS=(-P --transfers=8 --contimeout=5s --timeout=15s --retries=1 --low-level-retries=1)
CONNECTION_MSG="🚀 AUTOMATIC PRE-FLIGHT MODE: 5-second GitHub & CDN connection tests active."

# Route execution to the selected mode function
case "$ACTION" in
    pull) do_pull ;;
    push) do_push ;;
    audit) run_orphan_audit ;;
    indexnow) submit_indexnow_pings ;;
    *) show_help ;;
esac