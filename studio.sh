#!/bin/bash

# ============================================================================
# Architectural Block: studio.sh
# ============================================================================
# Purpose:
# - Single-command local launcher for the Engine Room Records Studio IDE &
#   DistroKid-Style Hold-Spacebar VTT Lyric Synchronizer (`/studio`).
# - Rebuilds `musicCatalog.json` from `raggiesoft-servers/raggiesoft-assets/engine-room-records/artists/`
#   and starts the local Vite dev server (`raggiesoft-music`) with the
#   `/__studio_api` local filesystem middleware enabled, opening
#   `http://localhost:5173/studio` directly in the default browser.
# - Saving a synced VTT in `/studio` automatically stamps:
#     WEBVTT
#     NOTE SYNC_TYPE: HUMAN_VERIFIED
#   into both `lyrics/{fileName}.vtt` and `streaming-services/lyrics/{fileName}.vtt`
#   so `harper.sh` (`04-track-processor.sh`) skips AI WhisperX lyric syncing.
# ============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PARENT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
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

cd "$MUSIC_ROOT"
npm run dev -- --open /studio

