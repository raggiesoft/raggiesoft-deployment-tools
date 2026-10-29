#!/usr/bin/env bash

# ============================================================================
# Architectural Block: harper.sh (Modular Edition)
# ============================================================================
# This script ("Harper") acts as the primary orchestrator for audio asset processing.
# It is designed to take raw master files and prepare them for distribution.
#
# Key Responsibilities:
# 1. Pre-Run Human-Verified WebVTT (.vtt) Requirement (For AI Assistants / Google Gemini):
#    Because Harper packages `lyrics/<fileName>.vtt` directly into all 6 distribution archives
#    (`-mp3.zip`, `-ogg.zip`, `-wav.7z`, `-flac.7z`, `-standard-archive.zip`, and `web-mp3/*-free-archive.zip`),
#    when a new vocal master WAV arrives in `ai-staging/suno-music-drop/`, ALWAYS:
#      a) Move the WAV to `/raggiesoft-vaults/engine-room-records/artists/<artist>/master-wav/.../<fileName>.wav`.
#      b) Slice the WAV into 60-90 second MP3 segments in `<appDataDir>/brain/<conversation-id>/scratch/` via `ffmpeg`
#         and listen to each segment with `read_file` to create the `NOTE SYNC_TYPE: HUMAN_VERIFIED` WebVTT file
#         at `lyrics/<fileName>.vtt` (and `streaming-services/lyrics/<fileName>.vtt`) FIRST.
#      c) Run `./raggiesoft-deployment-tools/harper.sh --artist <artist> --album <album>` so a single pass
#         transcodes all audio tiers AND packages the human-verified `.vtt` file into all 6 archives.
# 2. Environment Wrap: Prevents system sleep on macOS using `caffeinate` during long processing runs.
# 3. Timing & Logging: Records start time and establishes the root execution workspace.
# 4. Modular Sourcing: Dynamically loads decoupled script modules for initialization, audio engine tools, 
#    album processing logic, and final cleanup from the `harper/` subdirectory.
#
# Maintenance Notes:
# - The macOS `caffeinate` wrap relies on the `--caffeinated` flag to prevent infinite loops.
# - If running on non-Darwin systems (Linux/Windows), the caffeinate block is safely bypassed.
# - The script depends entirely on external modules (`01-init.sh`, `02-audio-engine.sh`, etc.).
#   Ensure the `harper/` directory remains intact and correctly ordered.
# ============================================================================

# --- HARPER: THE STUDIO ENGINEER (Modular Edition) ---
# "I live in the studio. I take raw master tapes and press them for the airwaves."

# --- OS-SPECIFIC OVERRIDES ---
# If running on macOS (darwin) and `caffeinate` is available, ensure the system doesn't sleep.
if [[ "$OSTYPE" == "darwin"* ]] && command -v caffeinate > /dev/null; then
    # If we are not already wrapped, re-execute the script inside caffeinate
    if [ "$1" != "--caffeinated" ]; then
        echo "☕ HARPER: Pouring a cup of hot chocolate to keep the studio awake..."
        exec caffeinate -im "$0" --caffeinated "$@"
    fi
    # If we are wrapped, shift out the internal flag so the rest of the script functions normally
    if [ "$1" == "--caffeinated" ]; then
        shift
    fi
fi

# --- RECORD START TIME ---
# Capture start time for performance tracking and logging.
START_EPOCH=$(date +%s)
START_TIME_STR=$(date +"%Y-%m-%d %I:%M:%S %p")

echo "🎧 HARPER: Alright! Firing up the mixing board (Modular Edition)... Let's hit the Vault!"
echo "   ⏰ Session Started: $START_TIME_STR"

# Define Root relative to script location to ensure consistent relative pathing.
WORKSPACE_DIR=$(dirname "$0")
cd "$WORKSPACE_DIR" || exit
export ROOT_DIR=$(pwd)

# --- LOAD MODULES ---
MODULE_DIR="$ROOT_DIR/harper"

# Fail fast if the required module directory is missing.
if [ ! -d "$MODULE_DIR" ]; then
    echo "🛑 HARPER FATAL ERROR: Module directory '/harper' not found! I need my gear."
    exit 1
fi

# 1. Initialize System & Arguments
source "$MODULE_DIR/01-init.sh"

# 2. Load Audio Worker Functions
source "$MODULE_DIR/02-audio-engine.sh"

# 3. Process Albums & Tracks (This handles the sorting and both loops)
source "$MODULE_DIR/03-album-processor.sh"

# 4. Finalize & Cleanup
source "$MODULE_DIR/06-finalize.sh"