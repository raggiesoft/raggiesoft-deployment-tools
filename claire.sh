#!/bin/bash
# ==============================================================================
# CLAIRE: THE STUDIO MANAGER (v1.0.1 - Technical Debt Sweeper)
# ==============================================================================
# PLAIN-ENGLISH OVERVIEW (100-LEVEL INTRO):
#   In software engineering, `claire.sh` is our "make clean" script for the
#   music studio! When Harper (`harper.sh`) runs, she generates derived audio
#   files (`web-mp3/`, `vault/`), DistroKid sheets (`streaming-services/`),
#   `read-me.txt`, and bound Markdown lyric booklets from our raw source files.
#   If you ever want to wipe out 100% of those generated outputs so Harper can
#   rebuild from a spotless slate—WITHOUT ever deleting your irreplaceable raw
#   source masters—you call Claire.
#
# WHEN IT RUNS:
#   Manually before a full clean studio rebuild (`./claire.sh` -> `./harper.sh --rebuild`).
#
# WHAT SHE DELETES vs. WHAT SHE STRICTLY PROTECTS:
#   - DELETES (Generated / Reproducible Artifacts):
#       * `raggiesoft-vaults/.../<album>/vault/` (transcoded V0 MP3, OGG, FLAC, stamped WAVs, ZIP/7z archives)
#       * `raggiesoft-assets/.../<album>/web-mp3/`, `streaming-services/`, `read-me.txt`,
#         root-level bound `<album>.md` booklets, and Harper's `temp_*.jsonl` scratch files.
#   - NEVER TOUCHES (Irreplaceable Source Files):
#       * `raggiesoft-vaults/.../master-wav/` (raw original master WAV recordings!)
#       * `album.json`, `tracks.json`, `album-art.jpg`, `social-preview.jpg`
#       * `lyrics/*.md`, `lyrics/*.vtt`, and `suno-prompts/*.md`
# ==============================================================================
# "A messy studio is a slow studio. Let me clear the floor before Harper comes in."

echo "🧹 CLAIRE: Good evening! I'll get this studio cleaned up and ready for Harper."
echo "   ✨ Grabbing the trash bins..."

# Move into the directory containing `claire.sh` (`dirname "$0"`).
# `|| exit` ensures that if `cd` fails for any reason, the script stops immediately
# instead of accidentally running `rm -rf` in the wrong folder!
WORKSPACE_DIR=$(dirname "$0")
cd "$WORKSPACE_DIR" || exit

# Resolve paths to both the public CDN assets repo (`raggiesoft-assets`) and the
# private local-only audio vault (`raggiesoft-vaults`).
if [ -d "../raggiesoft-servers" ]; then
    SERVER_ROOT="../raggiesoft-servers"
else
    SERVER_ROOT=".."
fi
SEARCH_PATH="$SERVER_ROOT/raggiesoft-assets/engine-room-records/artists"
VAULTS_PATH="$SERVER_ROOT/raggiesoft-vaults/engine-room-records/artists"

# Validate that the archives directory exists (`[ ! -d ... ]` means "is NOT a directory").
if [ ! -d "$SEARCH_PATH" ]; then
    echo "   ❌ CLAIRE: Oh dear, I can't seem to find the archives at $SEARCH_PATH. Are you sure that's the right door?"
    exit 1
fi

echo "   🗄️  Sweeping the archives: $SEARCH_PATH (and Vaults: $VAULTS_PATH)"

# Walk every album folder by searching recursively (`find`) for `tracks.json` files
# and piping (`|`) each found path line-by-line into `while read -r tracks_file`
# (`-r` tells `read` not to mangle backslashes in file paths).
find "$SEARCH_PATH" -name "tracks.json" | while read -r tracks_file; do
    
    # Extract folder names from a path like `.../artists/the-stardust-engine/1997-hard-reset/tracks.json`:
    #   - `album_dir`   -> `.../artists/the-stardust-engine/1997-hard-reset`
    #   - `album_slug`  -> `1997-hard-reset` (`basename` grabs the last path segment)
    #   - `artist_slug` -> `the-stardust-engine` (`dirname` goes up one level, then `basename` grabs the artist name)
    album_dir=$(dirname "$tracks_file")
    album_slug=$(basename "$album_dir")
    artist_slug=$(basename "$(dirname "$album_dir")")
    
    # Confirm `album.json` also exists alongside `tracks.json`; otherwise `continue` skips to the next loop item.
    if [ ! -f "$album_dir/album.json" ]; then
        continue
    fi

    echo "      🗑️  CLAIRE: Dusting off '$album_dir'..."
    
    # Clean ONLY the per-album `vault/` subfolder inside `/raggiesoft-vaults`—NEVER `master-wav/`!
    if [ -d "$VAULTS_PATH/$artist_slug/$album_slug/vault" ]; then
        rm -rf "$VAULTS_PATH/$artist_slug/$album_slug/vault"
    fi

    # `pushd` and `popd` work like a "stack" of directories (Last-In, First-Out):
    # `pushd "$album_dir"` saves our current directory on the stack and jumps into `$album_dir`,
    # and `popd` at the bottom pops us right back out safely (`> /dev/null` hides stack chatter).
    pushd "$album_dir" > /dev/null

    # 1. Delete generated 128kbps web streaming audio and any local `vault/` directory (`rm -rf` = recursive force remove)
    rm -rf web-mp3
    rm -rf vault
    
    # 2. Delete legacy root-level audio folders (from older pre-vault Harper versions)
    rm -rf wav
    rm -rf mp3
    rm -rf ogg
    
    # 3. Delete generated DistroKid / DSP release packages (`streaming-services/`)
    rm -rf streaming-services
    
    # 4. Delete root-level generated `read-me.txt` (`rm -f` deletes a single file without error if already absent)
    rm -f read-me.txt
    
    # 5. Safely remove ONLY the bound Markdown lyric booklet (`<album>.md`) sitting at the album root (`.`).
    # CRITICAL SAFETY GUARD (`-maxdepth 1`):
    # Without `-maxdepth 1`, `find` would recurse into subdirectories and delete our
    # hand-written `lyrics/*.md` and `suno-prompts/*.md` source files! `-maxdepth 1`
    # restricts `find` strictly to files directly inside `$album_dir/`.
    find . -maxdepth 1 -name "*.md" -type f -delete
    
    # Pop back to the directory where `claire.sh` started before the next loop iteration
    popd > /dev/null

done

# 6. Clean up any temporary JSON-Lines (`.jsonl`) scratch files Harper may have left in `raggiesoft-deployment-tools/`
echo "   🧽 CLAIRE: Wiping down the main workspace temp files..."
rm -f temp_search_index.jsonl
rm -f temp_catalog_index.jsonl
rm -f temp_tracks_update.jsonl

echo "🧹 CLAIRE: All done! The floors are swept, the legacy folders are in the dumpster, and the studio is spotless."
echo "   ✨ You're all clear to call in Harper for a --rebuild."