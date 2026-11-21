#!/bin/bash
# ==============================================================================
# SARAH: AUTONOMOUS DEPLOYMENT (v5.0 - Multi-Site Edition)
# ==============================================================================
# PLAIN-ENGLISH OVERVIEW (100-LEVEL INTRO):
#   In our two-person deployment relay, **Jenna** (`jenna-sync.sh`) runs on your
#   local Mac/PC to compile websites and push commits to GitHub, while **Sarah**
#   (`sarah-deploy.sh`) lives on our Ubuntu production server (`jessica.raggiesoft.com`,
#   DigitalOcean NYC1 `142.93.244.239`)!
#
# WHEN IT RUNS:
#   1. Automatically every 5 minutes via Linux `systemd` (`sarah.timer` -> `sarah.service`),
#      acting like a modern self-logging `cron` job.
#   2. Instantly within ~2 seconds whenever `jenna-sync.sh --push` wakes Sarah up
#      over SSH (`ssh michael@jessica.raggiesoft.com '/home/michael/sarah-deploy.sh'`).
#   3. Manually on the server (`./sarah-deploy.sh --force-reset`) for a clean reset.
#
# WHAT SHE READS & DEPLOYS:
#   - Step 0 (Self-Upgrading Infra): Pulls `raggiesoft-deployment-tools` (re-launching
#     herself immediately via `exec` if her own code changed!) and `nginx-config`
#     (atomically validating `nginx -t` with automatic rollback before reloading Nginx!).
#   - Steps 1–11 (All 11 Live Showrooms): Compares `LOCAL` vs `REMOTE` Git commit
#     hashes across all 11 site repos in `/home/michael/raggiesoft-*`. If unchanged,
#     skips in milliseconds! If updated, resets to `origin/main`, `rsync`s the static/PHP
#     payload into `/var/www/<domain>`, runs `minify_showroom` on `/var/www/<domain>`
#     (so GitHub keeps 100% of our beginner-friendly Read-Along Teaching Comments while
#     live production serves stripped, minified PHP/JS/CSS/HTML/JSON!), normalizes
#     `755`/`644` permissions, and pings **IndexNow** (`api.indexnow.org`)!
# ==============================================================================
# "I check for updates every 5 minutes. If Jenna pushed code, I deploy it instantly."
# NO SUDO REQUIRED FOR WEB FILES.

# ZERO-INTERACTIVE / AUTOMATIC "YES" ENVIRONMENT ENFORCEMENT:
# Because Sarah runs unattended in the background (`systemd` / `cron` / non-TTY SSH) with
# nobody at a keyboard, ANY interactive prompt (`[Y/n]`, `vim` editor, SSH host-key question,
# or `less` pager) would hang the server job forever! Exporting these variables disables all prompts:
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

# SECURITY CHECK: SARAH REFUSES TO RUN AS ROOT (`$EUID -eq 0`)
# HOW `$EUID` WORKS IN UNIX/LINUX:
#   Every Linux user has a numeric ID (`UID`). Normal users get numbers like `1000` (`michael`),
#   whereas the all-powerful superuser `root` (or anyone running `sudo ./sarah-deploy.sh`)
#    ALWAYS has Effective User ID `EUID = 0`!
#   If Sarah ran as `root`, `git` and `rsync` would create `root:root` files inside
#   `/home/michael/` and `/var/www/`, locking out future non-root runs and increasing attack surface!
if [ "$EUID" -eq 0 ]; then
    echo "🚨 SARAH FATAL ERROR: I am not allowed to run as root or via sudo!"
    echo "I was designed to run autonomously as the standard user. Please drop your privileges and try again."
    exit 1
fi

# NON-BLOCKING SINGLE-INSTANCE MUTEX (`flock -n`):
# Prevents `sarah.timer` (every 5 min) and `jenna-sync.sh`'s SSH wakeup from ever running
# two overlapping deployments at the same time! Note: preserved across self-upgrade `exec`
# via `SARAH_LOCK_HELD=1` so re-execing Sarah inherits file descriptor 9 cleanly.
if command -v flock >/dev/null 2>&1 && [ "${SARAH_LOCK_HELD:-0}" != "1" ]; then
    exec 9>/tmp/sarah-deploy.lock
    if ! flock -n 9; then
        echo "ℹ️  SARAH: Another deployment is already running; skipping overlapping run."
        exit 0
    fi
    export SARAH_LOCK_HELD=1
fi

# Save original CLI flags (`"$@"`) into a Bash array so if Sarah pulls an updated version
# of `sarah-deploy.sh` during Step 0, `exec` can pass the exact same flags (`--force-reset`) along!
SARAH_ORIG_ARGS=("$@")

# Self-healing symlink (`-L` tests if a path is a symbolic link):
# Ensures `/home/michael/sarah-deploy.sh` (targeted by `sarah.service`) always points to
# the Git-tracked script in `/home/michael/raggiesoft-deployment-tools/sarah-deploy.sh`.
if [ -f "/home/michael/raggiesoft-deployment-tools/sarah-deploy.sh" ] && [ ! -L "/home/michael/sarah-deploy.sh" ]; then
    ln -sf "/home/michael/raggiesoft-deployment-tools/sarah-deploy.sh" "/home/michael/sarah-deploy.sh" 2>/dev/null || true
fi

FORCE_RESET=false

# Optional `--force-reset` flag bypasses Git SHA comparisons and forces `git clean -fdx` + full `rsync`
if [ "$1" == "--force-reset" ]; then
    FORCE_RESET=true
    echo "🚨 SARAH: NUCLEAR OVERRIDE INITIATED. Forcing a clean deployment..."
fi

# Official RaggieSoft IndexNow API Key (hosted at `/<INDEXNOW_KEY>.txt` on every domain)
readonly INDEXNOW_KEY="726167676965736f6674696e6465786e"

# ==============================================================================
# Helper: notify_indexnow_for_webroot <web_root>
# ==============================================================================
# WHAT INDEXNOW IS:
#   Instead of waiting days for search engines to randomly re-crawl our sites,
#   **IndexNow** (`api.indexnow.org`) is an open instant-indexing protocol shared
#   by Bing, DuckDuckGo, Yandex, Naver, Seznam, and Yep.
#   Right after `rsync` updates `/var/www/<site>`, an inline Python XML parser
#   extracts up to 10,000 `<loc>` URLs from `sitemaps/*.xml` or `sitemap.xml`,
#   formats the JSON payload, and `curl` POSTs it with a strict `--max-time 8`
#   8-second timeout (`-w "%{http_code}"` prints HTTP `200`/`202` while `-o /dev/null`
#   discards body noise, and `|| echo "000"` ensures network hiccups NEVER fail cron!).
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

# ==============================================================================
# Helper: minify_showroom <web_root>
# ==============================================================================
# WHY WE MINIFY IN SARAH (`/var/www/*`) INSTEAD OF IN GIT REPOSITORIES:
#   Every source file across RaggieSoft's GitHub repositories is written with
#   exhaustive, beginner-friendly "Read-Along Teaching Comments" from top to bottom
#   so any developer, student, or hiring manager browsing GitHub can understand
#   every line. However, shipping megabytes of comments and indentation on live
#   production wastes bandwidth, disk I/O, and parse time!
#
#   Because `deploy_site` copies files one-way from `/home/michael/raggiesoft-*`
#   into `/var/www/<domain>` via `rsync`, running `minify_showroom` exclusively on
#   `/var/www/<domain>` gives us the best of both worlds:
#     - GitHub & `/home/michael/raggiesoft-*` keep 100% of human-readable comments.
#     - `/var/www/<domain>` serves stripped, compact PHP, CSS, JS, HTML, and JSON!
#
# HOW EACH FILE TYPE IS MINIFIED SAFELY (ZERO BROKEN SYNTAX):
#   1. `.php`       : Uses PHP's built-in C Zend Engine lexer (`php -w`) + `token_get_all()`
#                     to strip both PHP comments and non-raw HTML comments, then gates
#                     every file through `php -l` before replacing!
#   2. `.css`       : Single-pass lexical state machine tracking `'...'`, `"..."`, and `url(...)`
#                     so `/* ... */` comments and redundant whitespace are stripped without
#                     ever breaking `calc(100% - 2rem)` or `.parent :hover`, gated by `{}` balance.
#   3. `.js`/`.mjs` : Single-pass ASI-safe ECMAScript lexical scanner tracking strings,
#                     nested `` `...${...}...` `` template literals, and `/.../flags` regex
#                     literals—gated by `node --check` whenever Node.js is installed!
#   4. `.html`      : Strips `<!-- ... -->` comments outside `<script>`/`<style>`/`<pre>`/
#                     `<code>`/`<textarea>` while minifying inline `<style>`, `<script>`, and JSON-LD.
#   5. `.json`      : Parses via `json.loads()` and re-serializes with `separators=(",", ":")`.
function minify_showroom() {
    local WEB_ROOT="$1"
    if [ ! -d "$WEB_ROOT" ] || ! command -v python3 >/dev/null 2>&1; then
        return 0
    fi

    # Feed the inline Python minifier via stdin (`python3 - "$WEB_ROOT" <<'PYMIN'`)
    python3 - "$WEB_ROOT" <<'PYMIN' 2>/dev/null || true
import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

# Directories skipped completely because they are third-party, XML sitemaps, or already bundler-minified
SKIP_DIRS = {".git", "node_modules", "vendor", "3rdparty", "sitemaps", "logs"}

# Single-pass HTML5 lexical matcher: scans left-to-right from byte 0 so an HTML comment
# (`<!-- ... -->`) containing literal teaching text like `` `<script>` `` is consumed as a
# comment FIRST and can NEVER be mistaken for an opening `<script>` tag!
HTML_TOKEN_RE = re.compile(
    r"<!--[\s\S]*?-->|<(script|style|pre|code|textarea)\b([^>]*)>([\s\S]*?)</\1>",
    re.IGNORECASE,
)

# ECMAScript grammar tokens after which `/` begins a `/regex/` literal instead of division
JS_REGEX_PRECEDERS = {
    "(", ",", "=", ":", "[", "!", "&", "|", "?", "{", "}", ";",
    "+", "-", "*", "/", "%", "^", "~", "<", ">",
}
JS_REGEX_KEYWORDS = {
    "return", "throw", "case", "delete", "void", "typeof",
    "yield", "await", "in", "of", "instanceof", "new", "else", "do",
}


def minify_css(css: str) -> str:
    """Strips /*...*/ CSS comments outside strings/url() and collapses safe whitespace."""
    out = []
    n = len(css)
    i = 0
    in_quote = None
    in_url = False
    paren_depth = 0

    while i < n:
        ch = css[i]
        if in_quote:
            out.append(ch)
            if ch == "\\" and i + 1 < n:
                out.append(css[i + 1])
                i += 2
                continue
            if ch == in_quote:
                in_quote = None
            i += 1
            continue
        if in_url:
            out.append(ch)
            if ch == "\\" and i + 1 < n:
                out.append(css[i + 1])
                i += 2
                continue
            if ch in ("'", '"'):
                in_quote = ch
            elif ch == "(":
                paren_depth += 1
            elif ch == ")":
                paren_depth -= 1
                if paren_depth <= 0:
                    in_url = False
            i += 1
            continue
        if ch == "/" and i + 1 < n and css[i + 1] == "*":
            end = css.find("*/", i + 2)
            if end == -1:
                break
            out.append(" ")
            i = end + 2
            continue
        if ch in ("'", '"'):
            in_quote = ch
            out.append(ch)
            i += 1
            continue
        if ch in ("u", "U") and css[i : i + 4].lower() == "url(":
            in_url = True
            paren_depth = 1
            out.append(css[i : i + 4])
            i += 4
            continue
        out.append(ch)
        i += 1

    stripped = "".join(out)
    res = []
    i = 0
    m = len(stripped)
    in_quote = None
    in_url = False
    paren_depth = 0

    while i < m:
        ch = stripped[i]
        if in_quote:
            res.append(ch)
            if ch == "\\" and i + 1 < m:
                res.append(stripped[i + 1])
                i += 2
                continue
            if ch == in_quote:
                in_quote = None
            i += 1
            continue
        if in_url:
            res.append(ch)
            if ch == "\\" and i + 1 < m:
                res.append(stripped[i + 1])
                i += 2
                continue
            if ch in ("'", '"'):
                in_quote = ch
            elif ch == "(":
                paren_depth += 1
            elif ch == ")":
                paren_depth -= 1
                if paren_depth <= 0:
                    in_url = False
            i += 1
            continue
        if ch in ("'", '"'):
            in_quote = ch
            res.append(ch)
            i += 1
            continue
        if ch in ("u", "U") and stripped[i : i + 4].lower() == "url(":
            in_url = True
            paren_depth = 1
            res.append(stripped[i : i + 4])
            i += 4
            continue
        if ch.isspace():
            while i < m and stripped[i].isspace():
                i += 1
            prev_ch = res[-1] if res else ""
            next_ch = stripped[i] if i < m else ""
            if prev_ch in ("", "{", "}", ";", ",") or next_ch in ("", "{", "}", ";", ","):
                continue
            res.append(" ")
            continue
        if ch == "}" and res and res[-1] == ";":
            res[-1] = "}"
            i += 1
            continue
        res.append(ch)
        i += 1

    return "".join(res).strip()


def strip_js_comments(js: str) -> str:
    """Single-pass ASI-safe ECMAScript comment & horizontal whitespace compactor."""
    out = []
    n = len(js)
    i = 0
    template_brace_stack = []
    last_sig_char = ""
    last_word = ""
    pending_nl = False
    pending_space = False

    if js.startswith("#!"):
        nl = js.find("\n")
        if nl == -1:
            return js
        out.append(js[: nl + 1])
        i = nl + 1

    def flush_ws(next_first_char: str) -> None:
        nonlocal pending_nl, pending_space
        if pending_nl:
            if out and out[-1] != "\n":
                out.append("\n")
            pending_nl = False
            pending_space = False
        elif pending_space:
            prev_c = out[-1][-1] if out and out[-1] else ""
            if prev_c and next_first_char and (
                ((prev_c.isalnum() or prev_c in "_$") and (next_first_char.isalnum() or next_first_char in "_$"))
                or (prev_c == "+" and next_first_char == "+")
                or (prev_c == "-" and next_first_char == "-")
                or (prev_c == "/" and next_first_char in ("/", "*"))
            ):
                out.append(" ")
            pending_space = False

    def can_start_regex() -> bool:
        if not last_sig_char:
            return True
        if last_sig_char in JS_REGEX_PRECEDERS:
            return True
        if last_word in JS_REGEX_KEYWORDS:
            return True
        return False

    def consume_template_body(idx: int) -> int:
        while idx < n:
            c = js[idx]
            out.append(c)
            if c == "\\" and idx + 1 < n:
                out.append(js[idx + 1])
                idx += 2
                continue
            if c == "`":
                return idx + 1
            if c == "$" and idx + 1 < n and js[idx + 1] == "{":
                out.append("{")
                template_brace_stack.append(1)
                return idx + 2
            idx += 1
        return idx

    while i < n:
        ch = js[i]
        if ch in (" ", "\t", "\r", "\n"):
            if ch == "\n":
                pending_nl = True
            else:
                pending_space = True
            i += 1
            continue
        if ch == "/" and i + 1 < n and js[i + 1] == "/":
            nl = js.find("\n", i + 2)
            if nl == -1:
                break
            pending_nl = True
            i = nl + 1
            continue
        if ch == "/" and i + 1 < n and js[i + 1] == "*":
            end = js.find("*/", i + 2)
            if end == -1:
                break
            if "\n" in js[i + 2 : end]:
                pending_nl = True
            else:
                pending_space = True
            i = end + 2
            continue

        flush_ws(ch)

        if ch in ("'", '"'):
            quote = ch
            start = i
            i += 1
            while i < n:
                c = js[i]
                if c == "\\" and i + 1 < n:
                    i += 2
                    continue
                i += 1
                if c == quote:
                    break
            out.append(js[start:i])
            last_sig_char = quote
            last_word = ""
            continue
        if ch == "`":
            out.append(ch)
            last_sig_char = "`"
            last_word = ""
            i = consume_template_body(i + 1)
            continue
        if ch == "{" and template_brace_stack:
            template_brace_stack[-1] += 1
            out.append(ch)
            last_sig_char = "{"
            last_word = ""
            i += 1
            continue
        if ch == "}" and template_brace_stack:
            template_brace_stack[-1] -= 1
            out.append(ch)
            if template_brace_stack[-1] == 0:
                template_brace_stack.pop()
                last_sig_char = "`"
                last_word = ""
                i = consume_template_body(i + 1)
                continue
            last_sig_char = "}"
            last_word = ""
            i += 1
            continue
        if ch == "/" and can_start_regex():
            start = i
            i += 1
            in_char_class = False
            while i < n:
                c = js[i]
                if c == "\\" and i + 1 < n:
                    i += 2
                    continue
                if c == "[":
                    in_char_class = True
                elif c == "]":
                    in_char_class = False
                elif c == "/" and not in_char_class:
                    i += 1
                    while i < n and (js[i].isalpha() or js[i] == "$"):
                        i += 1
                    break
                elif c == "\n":
                    break
                i += 1
            out.append(js[start:i])
            last_sig_char = "/"
            last_word = ""
            continue
        if ch.isalpha() or ch in ("_", "$"):
            start = i
            while i < n and (js[i].isalnum() or js[i] in ("_", "$")):
                i += 1
            word = js[start:i]
            out.append(word)
            last_word = word
            last_sig_char = word[-1]
            continue

        out.append(ch)
        last_sig_char = ch
        last_word = ""
        i += 1

    return "".join(out).strip() + "\n"


def is_hydration_or_special_comment(comment: str) -> bool:
    """
    Preserves framework SSR hydration & boundary comment nodes required at runtime by:
      - Svelte 5 (`<!--[-->`, `<!--[-1-->`, `<!--[0-->`, `<!--]-->`, `<!---->`, `<!--1uha8ag-->`)
      - React 19 / Next.js (`<!--$-->`, `<!--$!-->`, `<!--/$-->`, `<!-- -->`)
      - Vue 3 / Nuxt / Angular / Lit (`<!--[-->`, `<!--]-->`, `<!--ngh=...-->`, `<!--lit-...-->`)
      - Conditional comments (`<!--[if ...]-->`)
    Only multi-word human prose comments that start with whitespace are stripped!
    """
    inner = comment[4:-3]
    if not inner:
        return True
    stripped = inner.strip()
    if not stripped:
        return True
    if not inner[0].isspace():
        return True
    if " " not in stripped and "\n" not in stripped:
        return True
    return False


def compact_inter_tag_whitespace(chunk: str) -> str:
    chunk = re.sub(r"\n[ \t]+", "\n", chunk)
    chunk = re.sub(r"\n{2,}", "\n", chunk)
    return chunk


def minify_html_fragment(html: str) -> str:
    """Single-pass HTML5-tokenizer-safe minifier preserving SSR hydration markers & inline scripts (zero subprocesses)."""
    out = []
    pos = 0
    for m in HTML_TOKEN_RE.finditer(html):
        if m.start() > pos:
            out.append(compact_inter_tag_whitespace(html[pos : m.start()]))
        pos = m.end()
        full = m.group(0)

        # Case 1: Top-level HTML comment (`<!-- ... -->`)
        if full.startswith("<!--"):
            if is_hydration_or_special_comment(full):
                out.append(full)
            continue

        # Case 2: Matched raw/rcdata element (`<script>`, `<style>`, `<pre>`, `<code>`, `<textarea>`)
        tag = m.group(1).lower()
        attrs = m.group(2)
        body = m.group(3)

        if tag == "style":
            minified_css = minify_css(body)
            if minified_css.count("{") == minified_css.count("}"):
                out.append(f"<style{attrs}>{minified_css}</style>")
                continue
        elif tag == "script":
            low_attrs = attrs.lower()
            if 'application/ld+json' in low_attrs or 'application/json' in low_attrs:
                try:
                    parsed = json.loads(body)
                    compact_json = json.dumps(parsed, ensure_ascii=False, separators=(",", ":")).replace("</", "<\\/")
                    out.append(f"<script{attrs}>{compact_json}</script>")
                    continue
                except Exception:
                    pass

        # Executable inline `<script>`, `<pre>`, `<code>`, and `<textarea>` stay 100% verbatim
        # (fast in-memory pass—zero `node --check` subprocesses across thousands of SSG pages!)
        out.append(full)

    if pos < len(html):
        out.append(compact_inter_tag_whitespace(html[pos:]))
    return "".join(out)


# Inline PHP helper passed to `php -r`: runs Zend's `php_strip_whitespace` first, then uses
# single-pass `preg_replace_callback` across `T_INLINE_HTML` so `<script>` inside an HTML comment
# never confuses raw-tag tracking and SSR/hydration markers stay 100% intact!
PHP_TOKEN_MINIFIER = r"""
$src = php_strip_whitespace($argv[1]);
$tokens = token_get_all($src);
$out = '';
$inRaw = false;
foreach ($tokens as $tok) {
    if (is_array($tok)) {
        if ($tok[0] === T_INLINE_HTML) {
            $chunk = $tok[1];
            $chunk = preg_replace_callback(
                '/<!--[\s\S]*?-->|<(?:script|style|pre|code|textarea)\b[^>]*>|<\/(?:script|style|pre|code|textarea)>/i',
                function ($m) use (&$inRaw) {
                    $s = $m[0];
                    if (str_starts_with($s, '<!--')) {
                        if ($inRaw) return $s;
                        $inner = substr($s, 4, -3);
                        if ($inner === '' || trim($inner) === '') return $s;
                        if (!ctype_space($inner[0])) return $s;
                        $trimmed = trim($inner);
                        if (!str_contains($trimmed, ' ') && !str_contains($trimmed, "\n")) return $s;
                        return '';
                    }
                    if ($s[1] === '/') {
                        $inRaw = false;
                    } else {
                        $inRaw = true;
                    }
                    return $s;
                },
                $chunk
            );
            if (!$inRaw) {
                $chunk = preg_replace('/\n[ \t]+/', "\n", $chunk);
                $chunk = preg_replace('/\n{2,}/', "\n", $chunk);
            }
            $out .= $chunk;
        } else {
            $out .= $tok[1];
        }
    } else {
        $out .= $tok;
    }
}
echo $out;
"""


def minify_php_file(path: Path, php_bin: str) -> tuple[int, int]:
    orig_bytes = path.stat().st_size
    res = subprocess.run([php_bin, "-r", PHP_TOKEN_MINIFIER, str(path)], capture_output=True)
    if res.returncode != 0 or not res.stdout:
        return orig_bytes, orig_bytes
    tmp = path.with_name(".sarah_tmp_" + path.name)
    tmp.write_bytes(res.stdout)
    chk = subprocess.run([php_bin, "-l", str(tmp)], capture_output=True)
    if chk.returncode == 0:
        new_bytes = tmp.stat().st_size
        if new_bytes < orig_bytes:
            os.replace(tmp, path)
            return orig_bytes, new_bytes
    tmp.unlink(missing_ok=True)
    return orig_bytes, orig_bytes


def main() -> None:
    web_root = Path(sys.argv[1])
    php_bin = shutil.which("php")
    node_bin = shutil.which("node")
    total_before = 0
    total_after = 0
    files_minified = 0

    for root, dirs, files in os.walk(web_root):
        dirs[:] = [
            d for d in dirs
            if d not in SKIP_DIRS
            and not (d == "immutable" and os.path.basename(root) == "_app")
            and not (d == "static" and os.path.basename(root) == "_next")
        ]
        for fname in files:
            if fname.startswith(".sarah_tmp_"):
                continue
            fpath = Path(root) / fname
            if fpath.is_symlink():
                continue
            low = fname.lower()
            if low.endswith((".min.js", ".min.css")):
                continue
            if re.match(r"^(?:main|polyfills|chunk|scripts|styles)-[A-Za-z0-9_-]{6,}\.(?:js|css)$", fname):
                continue
            try:
                if low.endswith(".php") and php_bin:
                    b0, b1 = minify_php_file(fpath, php_bin)
                    total_before += b0
                    total_after += b1
                    if b1 < b0:
                        files_minified += 1
                elif low.endswith(".css"):
                    raw = fpath.read_text(encoding="utf-8")
                    b0 = len(raw.encode("utf-8"))
                    minified = minify_css(raw)
                    b1 = len(minified.encode("utf-8"))
                    if b1 < b0 and minified.count("{") == minified.count("}"):
                        fpath.write_text(minified, encoding="utf-8")
                        total_before += b0
                        total_after += b1
                        files_minified += 1
                    else:
                        total_before += b0
                        total_after += b0
                elif low.endswith((".js", ".mjs")):
                    raw = fpath.read_text(encoding="utf-8")
                    b0 = len(raw.encode("utf-8"))
                    minified = strip_js_comments(raw)
                    tmp = fpath.with_name(".sarah_tmp_" + fname)
                    tmp.write_text(minified, encoding="utf-8")
                    valid = True
                    if node_bin:
                        chk = subprocess.run([node_bin, "--check", str(tmp)], capture_output=True)
                        if chk.returncode != 0:
                            valid = False
                    if valid:
                        b1 = tmp.stat().st_size
                        if b1 < b0:
                            os.replace(tmp, fpath)
                            total_before += b0
                            total_after += b1
                            files_minified += 1
                        else:
                            tmp.unlink(missing_ok=True)
                            total_before += b0
                            total_after += b0
                    else:
                        tmp.unlink(missing_ok=True)
                        total_before += b0
                        total_after += b0
                elif low.endswith(".html"):
                    raw = fpath.read_text(encoding="utf-8")
                    b0 = len(raw.encode("utf-8"))
                    minified = minify_html_fragment(raw)
                    b1 = len(minified.encode("utf-8"))
                    if b1 < b0:
                        fpath.write_text(minified, encoding="utf-8")
                        total_before += b0
                        total_after += b1
                        files_minified += 1
                    else:
                        total_before += b0
                        total_after += b0
                elif low.endswith(".json") and low not in ("package.json", "package-lock.json", "composer.json"):
                    raw = fpath.read_text(encoding="utf-8")
                    b0 = len(raw.encode("utf-8"))
                    obj = json.loads(raw)
                    minified = json.dumps(obj, ensure_ascii=False, separators=(",", ":"))
                    b1 = len(minified.encode("utf-8"))
                    if b1 < b0:
                        fpath.write_text(minified, encoding="utf-8")
                        total_before += b0
                        total_after += b1
                        files_minified += 1
                    else:
                        total_before += b0
                        total_after += b0
            except Exception:
                pass

    if files_minified > 0 and total_before > 0:
        saved_pct = (total_before - total_after) / total_before * 100.0
        print(f"   -> ⚡ Minified {files_minified} showroom files ({total_before/1024:.1f} KB -> {total_after/1024:.1f} KB, saved {saved_pct:.1f}%).")


if __name__ == "__main__":
    main()
PYMIN
}

# ==============================================================================
# Helper: deploy_site <site_name> <repo_dir> <web_root> [sync_dir]
# ==============================================================================
# Sarah's core per-website deployment state machine:
#   - `$1` (`SITE_NAME`): Human-readable label for logs (e.g., `"Music"`).
#   - `$2` (`REPO_DIR`) : Local Git clone path (`/home/michael/raggiesoft-music`).
#   - `$3` (`WEB_ROOT`) : Live Nginx document root (`/var/www/music.raggiesoft.com`).
#   - `$4` (`SYNC_DIR`) : Optional compiled output subfolder (`/home/michael/raggiesoft-music/build`);
#                         `${4:-$REPO_DIR}` defaults to `$REPO_DIR` for PHP sites that deploy from root!
function deploy_site() {
    local SITE_NAME=$1
    local REPO_DIR=$2
    local WEB_ROOT=$3
    local SYNC_DIR=${4:-$REPO_DIR}

    local JUST_CLONED=false
    # Self-healing clone: if a brand-new site repository hasn't been cloned on the server yet, clone it automatically!
    if [ ! -d "$REPO_DIR" ]; then
        echo "⚠️ SARAH: Repository missing at $REPO_DIR. Cloning from GitHub..."
        local REPO_BASENAME=$(basename "$REPO_DIR")
        cd "$(dirname "$REPO_DIR")" || return
        git clone "https://github.com/raggiesoft/$REPO_BASENAME.git"
        if [ ! -d "$REPO_DIR" ]; then
            echo "🚨 SARAH: Clone failed for $SITE_NAME."
            return
        fi
        JUST_CLONED=true
    fi

    # Empty Showroom Check (`ls -A` lists all entries except `.` and `..`):
    # Right after `install-subdomains.sh` or `sync_nginx_vhosts` creates a brand-new empty
    # `/var/www/<site>` folder, `LOCAL == REMOTE` might already be true in Git—checking
    # `WEB_ROOT_EMPTY` ensures Sarah populates the empty `/var/www/<site>` folder anyway!
    local WEB_ROOT_EMPTY=false
    if [ ! -d "$WEB_ROOT" ] || [ -z "$(ls -A "$WEB_ROOT" 2>/dev/null)" ]; then
        WEB_ROOT_EMPTY=true
    fi

    cd "$REPO_DIR" || return

    # `git fetch origin main` downloads commit metadata from GitHub into `.git/` WITHOUT touching working files yet.
    git fetch origin main

    # `git rev-parse` resolves a branch/pointer into its exact 40-character SHA-1 commit hash!
    LOCAL=$(git rev-parse HEAD)
    REMOTE=$(git rev-parse origin/main)

    # Fast-path skip: if local commit == GitHub commit AND `/var/www/` isn't empty AND not `--force-reset`, return in <5ms!
    if [ "$FORCE_RESET" = false ] && [ "$JUST_CLONED" = false ] && [ "$WEB_ROOT_EMPTY" = false ]; then
        if [ "$LOCAL" == "$REMOTE" ]; then
            return
        fi
        echo "👩‍💼 SARAH: Change detected in $SITE_NAME! Jenna pushed updates."
    elif [ "$WEB_ROOT_EMPTY" = true ] && [ "$FORCE_RESET" = false ]; then
        echo "👩‍💼 SARAH: Empty showroom detected at $WEB_ROOT for $SITE_NAME! Hydrating initial build."
    else
        echo "👩‍💼 SARAH: Bypassing version check for $SITE_NAME. Purging local repository cache."
    fi

    # Align local working tree 100% with `origin/main` (`git clean -fdx` also wipes untracked files during `--force-reset`)
    git reset --hard origin/main
    if [ "$FORCE_RESET" = true ]; then
        git clean -fdx
    fi

    if [ ! -d "$WEB_ROOT" ]; then
        mkdir -p "$WEB_ROOT" 2>/dev/null
    fi

    # Safety fallback: if Jenna didn't commit the pre-built `dist/`/`build/` directory, build on server
    if [ ! -d "$SYNC_DIR" ] && [ -f "package.json" ]; then
        echo "   -> Pre-compiled payload missing. Building $SITE_NAME static bundle..."
        yes 2>/dev/null | npm --yes run build 2>/dev/null || true
    fi

    if [ ! -d "$SYNC_DIR" ]; then
        echo "🚨 SARAH: Sync directory $SYNC_DIR not found for $SITE_NAME. Skipping deployment."
        return
    fi

    # DEPLOY VIA `rsync`:
    #   - `-av`           : Archive mode + verbose output.
    #   - `--delete`      : Removes stale old pages/assets from `$WEB_ROOT/` that no longer exist in `$SYNC_DIR/`.
    #   - `--no-o --no-g` : Keeps `michael`'s current user/group ownership instead of trying `chown` (which requires root!).
    #   - Trailing `/` on BOTH `"$SYNC_DIR/"` and `"$WEB_ROOT/"` syncs contents directly inside `$WEB_ROOT/`.
    echo "   -> Syncing $SITE_NAME to Showroom..."
    rsync -av --delete --no-o --no-g \
        --exclude '.git' \
        --exclude '.gitignore' \
        --exclude 'README.md' \
        "$SYNC_DIR/" "$WEB_ROOT/"

    # Strip Read-Along Teaching Comments & dead whitespace inside `/var/www/<domain>` ONLY,
    # keeping `/home/michael/raggiesoft-*` and GitHub 100% documented while serving pure speed!
    minify_showroom "$WEB_ROOT"

    # UNIX WEB PERMISSIONS (`chmod 755` vs `chmod 644` + `find ... -exec ... +`):
    #   - `755` (`rwxr-xr-x`) on directories (`-type d`): Nginx (`www-data`) needs the `x` ("execute/traverse") bit to enter folders!
    #   - `644` (`rw-r--r--`) on files (`-type f`): Owner can read/write; Nginx can read (`r--`), nobody can execute uploaded static files.
    #   - Ending `-exec ... +` (with a `+` instead of `\;`) batches thousands of paths into ONE `chmod` call so it finishes ~50x faster!
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
#
# HOW SELF-UPGRADING `exec` RE-ENTRY WORKS:
#   Suppose Jenna pushes an update to `sarah-deploy.sh` AND a brand-new 12th subdomain
#   in the same commit. When the currently running (older) `sarah-deploy.sh` pulls
#   `raggiesoft-deployment-tools`, she detects `UPDATED=true` and runs:
#     `export SARAH_REEXECED=1`
#     `exec "/home/michael/raggiesoft-deployment-tools/sarah-deploy.sh" "${SARAH_ORIG_ARGS[@]}"`
#   `exec` replaces the running Bash process image in-place with the NEW `sarah-deploy.sh`
#   (while `SARAH_REEXECED=1` prevents an infinite loop!), so the brand-new 12th subdomain
#   deploys on THIS exact run without waiting 5 minutes for the next timer tick!
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

    # `-path "$REPO_DIR/.git" -prune -o` skips internal `.git/` objects while setting `755` on dirs/`.sh` and `644` on files
    find "$REPO_DIR" -path "$REPO_DIR/.git" -prune -o -type d -exec chmod 755 {} +
    find "$REPO_DIR" -path "$REPO_DIR/.git" -prune -o -type f -exec chmod 644 {} +
    find "$REPO_DIR" -path "$REPO_DIR/.git" -prune -o -type f -name "*.sh" -exec chmod 755 {} +
    echo "✅ SARAH: $REPO_LABEL Sync Complete."

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
# Zero-touch Nginx virtual host & web-root reconciler with **atomic rollback**:
#   1. `sudo -n true`: `-n` ("non-interactive") checks if passwordless sudo is active;
#      if a password would be required, returns immediately rather than hanging `cron`/`systemd`!
#   2. `shopt -s nullglob`: Tells Bash that if `*.conf` matches 0 files, expand to an empty
#      array `()` instead of the literal string `"*.conf"`.
#   3. Scans `root /var/www/...;` lines via `awk` (`<<< "$DECLARED_ROOTS"` is a Bash "here-string"
#      feeding a variable into `while read`) and creates any missing `/var/www/<site>` folders.
#   4. `cmp -s` compares each `.conf` byte-for-byte against `/etc/nginx/sites-available/`;
#      if nothing changed, returns in <2ms without touching Nginx!
#   5. Snapshots live configs into `mktemp -d`, applies updates, runs `sudo -n nginx -t` to syntax-test
#      Nginx BEFORE reloading (`systemctl reload nginx`), and **rolls back** to the snapshot if `nginx -t`
#      catches a syntax typo—guaranteeing live production websites NEVER go down!
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

    # 1. Ensure any declared `/var/www/*` root exists (skipping already-existing dirs)
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

    # 2. Fast byte-for-byte diff check (`cmp -s`) across all managed `.conf` files
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

# ==============================================================================
# EXECUTION PIPELINE: INFRASTRUCTURE REPOS -> ALL 11 LIVE SHOWROOMS
# ==============================================================================

# 0. PROCESS INFRASTRUCTURE & DEPLOYMENT REPOSITORIES FIRST
sync_infra_repo "Deployment Tools" "/home/michael/raggiesoft-deployment-tools"
sync_infra_repo "Nginx Config" "/home/michael/nginx-config"
sync_nginx_vhosts "/home/michael/nginx-config"

# 1. PROCESS RAGGIESOFT HUB (PHP 8.5 + DaisyUI 5 — deploys directly from repo root)
deploy_site "Hub" "/home/michael/raggiesoft-hub" "/var/www/raggiesoft.com"

# 2. PROCESS NEBULAE INCUBATOR (Cosmic Visualizer — deploys from repo root)
deploy_site "Nebulae" "/home/michael/raggiesoft-nebulae" "/var/www/nebulae.raggiesoft.com"

# 3. PROCESS STARDUST ENGINE LIBRARY (RaggieSoft Book Reader PHP 8.5 SPA — deploys from repo root)
deploy_site "Books" "/home/michael/raggiesoft-book-library" "/var/www/raggiesoft-book-library"

# 4. PROCESS LORE GRAPH (Next.js 16 + React 19 Static Export — deploys from `/out` subfolder)
deploy_site "Lore" "/home/michael/raggiesoft-lore" "/var/www/lore.raggiesoft.com" "/home/michael/raggiesoft-lore/out"

# 5. PROCESS ENGINE ROOM RECORDS / THE LISTENING ROOM (SvelteKit 2 + Svelte 5 Runes — deploys from `/build`)
deploy_site "Music" "/home/michael/raggiesoft-music" "/var/www/music.raggiesoft.com" "/home/michael/raggiesoft-music/build"

# 6. PROCESS EXECUTIVE SYSTEMS ARCHITECT DOSSIER (`michaelpragsdale.com` — Angular 19 Zoneless `/dist/.../browser`)
deploy_site "Portfolio" "/home/michael/raggiesoft-portfolio" "/var/www/michaelpragsdale.com" "/home/michael/raggiesoft-portfolio/dist/raggiesoft-portfolio/browser"

# 7. PROCESS ENGINE ROOM RECORDS IMPRINT (`engineroom.raggiesoft.com` — Astro 6 Static SSG `/dist`)
deploy_site "Engine Room Records" "/home/michael/raggiesoft-engine-room-records" "/var/www/engineroom.raggiesoft.com" "/home/michael/raggiesoft-engine-room-records/dist"

# 8. PROCESS THE STARDUST ENGINE (`stardust.raggiesoft.com` — Nuxt 4 + Vue 3 Static SSG `/.output/public`)
deploy_site "The Stardust Engine" "/home/michael/raggiesoft-stardust-engine" "/var/www/stardust.raggiesoft.com" "/home/michael/raggiesoft-stardust-engine/.output/public"

# 9. PROCESS RAGGIESOFT MEDIA CORPORATE HUB (`corporate.raggiesoft.com` — Bootstrap 5.3.8 Static SSG `/dist`)
deploy_site "RaggieSoft Media" "/home/michael/raggiesoft-corporate" "/var/www/corporate.raggiesoft.com" "/home/michael/raggiesoft-corporate/dist"

# 10. PROCESS RAGGIESOFT STORETRAINER (`storetrainer.raggiesoft.com` — Vanilla TS + Win32/Netscape 4.78 `/dist`)
deploy_site "StoreTrainer" "/home/michael/raggiesoft-storetrainer" "/var/www/storetrainer.raggiesoft.com" "/home/michael/raggiesoft-storetrainer/dist"

# 11. PROCESS RAGGIESOFT BACKSTAGE (`backstage.raggiesoft.com` — Web Awesome Pro + Font Awesome Pro+ PWA `/dist`)
deploy_site "Backstage" "/home/michael/raggiesoft-backstage" "/var/www/backstage.raggiesoft.com" "/home/michael/raggiesoft-backstage/dist"

# 12. PROCESS CEDAR RUN LAUNCHPAD (`cedarrun.raggiesoft.com` — SolidJS + TypeScript + Vite Static SSG `/dist`)
deploy_site "Cedar Run" "/home/michael/raggiesoft-cedar-run" "/var/www/cedarrun.raggiesoft.com" "/home/michael/raggiesoft-cedar-run/dist"

# 13. PROCESS RAGGIESOFT STORY CROSSROADS (`crossroads.raggiesoft.com` — Eleventy v3 + Lit 3 + TypeScript SSG `/dist`)
deploy_site "Story Crossroads" "/home/michael/raggiesoft-crossroads" "/var/www/crossroads.raggiesoft.com" "/home/michael/raggiesoft-crossroads/dist"

# 14. PROCESS THE UNCHARTED WAYSTATION (`waystation.raggiesoft.com` + Default 404 Catch-All — Mithril.js + TS SSG `/dist`)
deploy_site "Waystation" "/home/michael/raggiesoft-waystation" "/var/www/waystation.raggiesoft.com" "/home/michael/raggiesoft-waystation/dist"





