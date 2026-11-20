#!/bin/bash
# ============================================================================
# Architectural Block: studio.sh
# ============================================================================
# PLAIN-ENGLISH OVERVIEW (100-LEVEL INTRO):
#   `studio.sh` is a one-command launcher for the **Engine Room Studio IDE**—an
#   interactive local web tool inside The Listening Room (`subdomains/music`)
#   where a human producer can play a song and hold down the Spacebar in real
#   time to stamp karaoke-accurate WebVTT (`.vtt`) lyric timestamps.
#
# WHEN IT RUNS:
#   Run manually on your local Mac/PC (`./raggiesoft-deployment-tools/studio.sh`)
#   whenever you want to visually inspect or manually fine-tune `.vtt` timed
#   lyrics and track lore in a browser (`http://localhost:5173/studio`).
#
# INPUTS & OUTPUTS:
#   - Reads: `raggiesoft-servers/raggiesoft-assets/engine-room-records/artists/`
#     and launches the SvelteKit + Vite dev server in `raggiesoft.com/subdomains/music`.
#   - Writes (when you click Save inside `/studio` in the browser):
#     Stamps `WEBVTT` + `NOTE SYNC_TYPE: HUMAN_VERIFIED` into both
#     `lyrics/<fileName>.vtt` and `streaming-services/lyrics/<fileName>.vtt` so
#     `harper.sh` (`04-track-processor.sh`) preserves your verified timing 100%.
# ============================================================================

# `-e` (errexit) exits immediately if `cd` or `npm` fails with a non-zero exit code.
set -e

# Resolve absolute directory paths relative to `studio.sh` (`$0`) so the script works
# regardless of which folder your terminal is currently sitting in.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PARENT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Locate the `raggiesoft-servers` monorepo whether `raggiesoft-deployment-tools`
# is a sibling folder (`~/Developer/raggiesoft-deployment-tools`) or nested inside.
if [ -d "$PARENT_ROOT/raggiesoft-servers" ]; then
    SERVER_ROOT="$PARENT_ROOT/raggiesoft-servers"
elif [ -d "$SCRIPT_DIR/raggiesoft-servers" ]; then
    SERVER_ROOT="$SCRIPT_DIR/raggiesoft-servers"
else
    SERVER_ROOT="$SCRIPT_DIR"
fi
MUSIC_ROOT="$SERVER_ROOT/raggiesoft.com/subdomains/music"

echo "🎛️  ENGINE ROOM STUDIO IDE: Synchronizing catalog and starting local Studio server..."
echo "👉 Open http://localhost:5173/studio to use the Hold-Spacebar VTT Synchronizer & Lore IDE."

# Move into the SvelteKit music app directory and start its local `dev` script.
# HOW `--` WORKS IN `npm run dev -- --open /studio`:
#   Normally `npm` tries to parse flags starting with `--` as flags for `npm` itself.
#   The standalone double-dash `--` acts as a separator telling `npm`: "Stop reading
#   flags for `npm`, and forward everything after `--` (`--open /studio`) directly to
#   Vite so Vite opens `http://localhost:5173/studio` in your default web browser!"
cd "$MUSIC_ROOT"
npm run dev -- --open /studio

