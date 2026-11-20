#!/usr/bin/env bash
# ============================================================================
# Architectural Block: harper.sh (Modular Edition)
# ============================================================================
# PLAIN-ENGLISH OVERVIEW (100-LEVEL INTRO):
#   Harper ("The Studio Engineer") is our automated audio mastering, ISRC
#   code-minting, lyric-packaging, and catalog-building pipeline for Engine Room
#   Records! Instead of putting 1,800 lines of Bash into one giant file,
#   `harper.sh` is a clean "conductor" script that loads 6 numbered modules in
#   `raggiesoft-deployment-tools/harper/` in exact order:
#     1. `01-init.sh`            — Parses CLI flags, detects CPU/GPU hardware,
#                                  and initializes the US ISRC (`QTAHP`) ledger.
#     2. `02-audio-engine.sh`    — Defines the `press_audio_formats` FFmpeg worker
#                                  that encodes 128k MP3, V0 MP3, Q9 OGG, & FLAC.
#     3. `03-album-processor.sh` — Loops through albums chronologically, upscales/
#                                  caps 3000px cover art, generates DistroKid
#                                  sheets, and calls Modules `04` and `05`.
#     4. `04-track-processor.sh` — Stamps lossless BWF WAV headers, mints ISRCs,
#                                  verifies `HUMAN_VERIFIED` `.vtt` timed lyrics,
#                                  and spawns parallel background FFmpeg jobs.
#     5. `05-archiver.sh`        — Packs all 6 ZIP / `.7z` album download archives.
#     6. `06-finalize.sh`        — Compiles `metadata.json` & `master-catalog.json`
#                                  and returns a strict `ERRORLEVEL` exit code.
#
# WHEN IT RUNS:
#   Locally (`./raggiesoft-deployment-tools/harper.sh --artist <slug> --album <slug>`)
#   whenever a new song or album is added to `/raggiesoft-vaults/engine-room-records/`.
#
# CRITICAL PRE-HARPER WEBVTT (`.vtt`) PROTOCOL (FOR HUMAN & GEMINI PRODUCERS):
#   Because Module `05` packs `lyrics/<fileName>.vtt` into all 6 distribution archives
#   (`-mp3.zip`, `-ogg.zip`, `-wav.7z`, `-flac.7z`, `-standard-archive.zip`, and
#   `web-mp3/*-free-archive.zip`), ALWAYS create the `NOTE SYNC_TYPE: HUMAN_VERIFIED`
#   `.vtt` timed lyric file FIRST before running `harper.sh`:
#     a) Place master WAV at `/raggiesoft-vaults/engine-room-records/artists/<artist>/master-wav/.../<fileName>.wav`.
#     b) Slice the WAV into 60–90s MP3 chunks in `<appDataDir>/brain/<conversation-id>/scratch/`
#        and listen via `read_file` (or use `./studio.sh`) to author `lyrics/<fileName>.vtt`
#        and `streaming-services/lyrics/<fileName>.vtt`.
#     c) Run `./raggiesoft-deployment-tools/harper.sh --artist <artist> --album <album>`
#        so one single pass transcodes audio AND bundles the verified `.vtt` into all 6 archives!
# ============================================================================

# --- HARPER: THE STUDIO ENGINEER (Modular Edition) ---
# "I live in the studio. I take raw master tapes and press them for the airwaves."

# --- OS-SPECIFIC OVERRIDES (`caffeinate` Sleep Prevention on macOS) ---
# Encoding lossless FLAC and `.7z` archives across dozens of albums can take minutes.
# On macOS (`"$OSTYPE" == "darwin"*`), `exec caffeinate -im` replaces this shell process
# with a sleep-inhibited wrapper (`-i` prevents idle sleep, `-m` prevents disk sleep),
# passing `--caffeinated` as `$1` so the re-launched script doesn't loop infinitely!
if [[ "$OSTYPE" == "darwin"* ]] && command -v caffeinate > /dev/null; then
    if [ "$1" != "--caffeinated" ]; then
        echo "☕ HARPER: Pouring a cup of hot chocolate to keep the studio awake..."
        exec caffeinate -im "$0" --caffeinated "$@"
    fi
    # Strip the internal `--caffeinated` sentinel off `$1` so `01-init.sh` sees only real user flags
    if [ "$1" == "--caffeinated" ]; then
        shift
    fi
fi

# --- RECORD START TIME ---
# `date +%s` prints Unix Epoch time (total seconds elapsed since Jan 1, 1970 UTC),
# making it trivial for `06-finalize.sh` to subtract `END_EPOCH - START_EPOCH`!
START_EPOCH=$(date +%s)
START_TIME_STR=$(date +"%Y-%m-%d %I:%M:%S %p")

echo "🎧 HARPER: Alright! Firing up the mixing board (Modular Edition)... Let's hit the Vault!"
echo "   ⏰ Session Started: $START_TIME_STR"

# Lock our working directory to `raggiesoft-deployment-tools/` and `export ROOT_DIR`
# so all sourced modules and child tools (`node`, `python3`) resolve relative paths consistently.
WORKSPACE_DIR=$(dirname "$0")
cd "$WORKSPACE_DIR" || exit
export ROOT_DIR=$(pwd)

# --- LOAD MODULES VIA `source` ---
# HOW BASH `source` WORKS (vs. Running `./script.sh`):
#   If you run `./01-init.sh`, Bash spawns a separate child process; any variables
#   or functions created inside vanish the instant `./01-init.sh` finishes!
#   `source "file.sh"` executes the lines of `file.sh` directly inside THIS current
#   shell's memory (just like `#include` in C/C++), so variables set in `01-init.sh`
#   and functions defined in `02-audio-engine.sh` stay live for `03` and `06`!
MODULE_DIR="$ROOT_DIR/harper"

# Fail fast with exit code `1` if the `harper/` module folder is missing.
if [ ! -d "$MODULE_DIR" ]; then
    echo "🛑 HARPER FATAL ERROR: Module directory '/harper' not found! I need my gear."
    exit 1
fi

# 1. Initialize System, CLI Arguments, Hardware Pool Limits, & US ISRC (`QTAHP`) Ledger
source "$MODULE_DIR/01-init.sh"

# 2. Load the Multi-Tier FFmpeg Audio Mastering Worker Function (`press_audio_formats`)
source "$MODULE_DIR/02-audio-engine.sh"

# 3. Chronologically Sort & Process Every Album (internally sources `04-track-processor.sh` & `05-archiver.sh`)
source "$MODULE_DIR/03-album-processor.sh"

# 4. Compile Global JSON Search/ISRC Catalogs, Clean Up Temp Files, & Enforce Exit Code Contract
source "$MODULE_DIR/06-finalize.sh"