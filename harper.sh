#!/usr/bin/env bash

# ============================================================================
# Architectural Block: harper.sh (Modular Edition)
# ============================================================================
# This script ("Harper") acts as the primary orchestrator for audio asset processing.
# It is designed to take raw master files and prepare them for distribution.
#
# Key Responsibilities:
# 1. Environment Wrap: Prevents system sleep on macOS using `caffeinate` during long processing runs.
# 2. Timing & Logging: Records start time and establishes the root execution workspace.
# 3. Modular Sourcing: Dynamically loads decoupled script modules for initialization, audio engine tools, 
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