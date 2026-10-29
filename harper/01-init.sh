#!/usr/bin/env bash
# ==============================================================================
# HARPER MODULE 01: INITIALIZATION
# ==============================================================================
# ARCHITECTURAL OVERVIEW:
# This module is responsible for initializing the core state of the Harper 
# media processing engine. It configures paths, handles command-line arguments,
# performs hardware discovery (GPU and CPU concurrency), and locates external 
# dependencies (7-Zip and Upscaler).
#
# FUTURE MAINTENANCE NOTES:
# - Hardware detection is OS-specific and uses a heuristic regex for iGPUs.
# - The worker pool limits are calculated based on logical CPU cores minus 2.
# - If path structures change in `engine-room-records/artists`, update SEARCH_PATH.
# ==============================================================================

# --- ERRORLEVEL / EXIT CODE CONTRACT ---
#   0 = ERR_SUCCESS                    (100% of audio renders, archives, and JSON catalogs succeeded)
#   1 = ERR_FATAL_INIT                 (Missing modules, invalid CLI parameter, missing path, or iGPU lock)
#   2 = ERR_AUDIO_TRANSCODE_FAILED     (One or more FFmpeg BWF stamps or multi-tier transcodes failed)
#   3 = ERR_ARCHIVE_OR_CATALOG_FAILED  (One or more 7-Zip archives or jq JSON catalog builds failed)
readonly ERR_SUCCESS=0
readonly ERR_FATAL_INIT=1
readonly ERR_AUDIO_TRANSCODE_FAILED=2
readonly ERR_ARCHIVE_OR_CATALOG_FAILED=3
export HARPER_AUDIO_ERRORS=0
export HARPER_ARCHIVE_ERRORS=0

# --- PATH CONFIGURATION ---
# Define the root path for artist records and metadata (resolved from /raggiesoft-deployment-tools)
SEARCH_PATH="../raggiesoft-assets/engine-room-records/artists"
METADATA_FILE="../raggiesoft-assets/engine-room-records/artists/metadata.json"
export VAULTS_ROOT="$ROOT_DIR/../raggiesoft-vaults/engine-room-records/artists"

# Temporary indices used for fast writes during parallel processing
TEMP_SEARCH_INDEX="temp_search_index.jsonl" 
TEMP_CATALOG_INDEX="temp_catalog_index.jsonl" 
export TEMP_GEMINI_VTT_QUEUE="$ROOT_DIR/temp_gemini_vtt_queue.txt"

echo "   🎚️  Targeting Studio Archives: $SEARCH_PATH"
echo "   🔐 Targeting Local Master Vaults: $VAULTS_ROOT"

# Initialize Indices by truncating/creating them
> "$TEMP_SEARCH_INDEX" 
> "$TEMP_CATALOG_INDEX"
> "$TEMP_GEMINI_VTT_QUEUE"

# --- ARGUMENT PARSING ---
# Default execution flags
# - REBUILD: Global or scoped rebuild mode triggered by `--rebuild` (or `-y`).
# - TARGET_ARTIST: Optional artist directory slug (`--artist <artist-slug>`) to scope `--rebuild`
#   to a single artist (or a single album when paired with `--album <album-slug>`).
# - TARGET_ALBUM: Optional album directory slug (`--album <album-slug>`). Strictly requires `--artist`.
REBUILD=false
FORCE_IGPU=false
OVERWRITE=false
METADATA_ONLY=false
NO_VTT=false
TARGET_ARTIST=""
TARGET_ALBUM=""
ffmpeg_flag="-n"

# Process provided command-line arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --rebuild|-y) 
            REBUILD=true
            OVERWRITE=true
            # Force ffmpeg to overwrite output files (scoped per-album in 03-album-processor.sh if --artist/--album are set)
            ffmpeg_flag="-y" 
            ;;
        --artist)
            if [[ -z "${2:-}" || "${2:-}" == --* ]]; then
                echo "🛑 HARPER FATAL ERROR: --artist requires an artist slug argument (e.g., --artist the-stardust-engine)."
                exit "${ERR_FATAL_INIT:-1}"
            fi
            TARGET_ARTIST="$2"
            shift
            ;;
        --album)
            if [[ -z "${2:-}" || "${2:-}" == --* ]]; then
                echo "🛑 HARPER FATAL ERROR: --album requires an album slug argument (e.g., --album 2016-live-at-the-crucible)."
                exit "${ERR_FATAL_INIT:-1}"
            fi
            TARGET_ALBUM="$2"
            shift
            ;;
        --force-igpu) FORCE_IGPU=true ;;
        --metadata) METADATA_ONLY=true ;;
        --no-vtt) NO_VTT=true ;;
        *) echo "🛑 HARPER: Unknown parameter passed: $1"; exit "${ERR_FATAL_INIT:-1}" ;;
    esac
    shift
done

# --- SCOPED REBUILD VALIDATION (--artist & --album) ---
# Rule 1: --album strictly requires --artist so Harper knows which artist vault/assets tree to target.
if [ -n "$TARGET_ALBUM" ] && [ -z "$TARGET_ARTIST" ]; then
    echo "🛑 HARPER FATAL ERROR: --album ('$TARGET_ALBUM') requires --artist <artist-slug> to also be specified!"
    echo "   Usage: ./raggiesoft-deployment-tools/harper.sh --rebuild --artist <artist-slug> --album <album-slug>"
    exit "${ERR_FATAL_INIT:-1}"
fi

# Rule 2: If --artist (or --artist + --album) is passed, auto-enable REBUILD for that target scope
# and verify that the target artist/album directories physically exist on disk before starting.
if [ -n "$TARGET_ARTIST" ]; then
    REBUILD=true
    if [ ! -d "$SEARCH_PATH/$TARGET_ARTIST" ]; then
        echo "🛑 HARPER FATAL ERROR: Artist directory not found at '$SEARCH_PATH/$TARGET_ARTIST'!"
        exit "${ERR_FATAL_INIT:-1}"
    fi
    if [ -n "$TARGET_ALBUM" ] && [ ! -d "$SEARCH_PATH/$TARGET_ARTIST/$TARGET_ALBUM" ]; then
        echo "🛑 HARPER FATAL ERROR: Album directory not found at '$SEARCH_PATH/$TARGET_ARTIST/$TARGET_ALBUM'!"
        exit "${ERR_FATAL_INIT:-1}"
    fi
fi

# --- PRE-FLIGHT HARDWARE CHECK (Cross-Platform) ---
# Detect system GPU capabilities to avoid hanging the system during heavy loads
IGPU_DETECTED=false
GPU_INFO=""
IGPU_SAFE_MODE=""

# Gather GPU info based on the operating system environment
if [[ "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" ]]; then
    # Windows environment check
    GPU_INFO=$(powershell.exe -NoProfile -Command "(Get-CimInstance Win32_VideoController).Name" 2>/dev/null | tr -d '\r')
elif command -v lspci &> /dev/null; then
    # Linux environment check
    GPU_INFO=$(lspci | grep -iE 'vga|3d|display')
elif [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS environment check
    GPU_INFO=$(sysctl -n machdep.cpu.brand_string | tr -d '\n')
fi

# The Heuristic Regex (Works against both Windows and Linux outputs)
# Identifies common integrated graphics cards
if echo "$GPU_INFO" | grep -qiE 'integrated|vega|renoir|cezanne|intel|uhd|iris|radeon.*graphics'; then
    IGPU_DETECTED=true
    # Set safe mode flags for upscaling on weaker integrated graphics
    IGPU_SAFE_MODE="-g 1 -t 32"
fi

# Prevent accidental complete full-library rebuilds on iGPUs due to performance constraints
# (Scoped single-artist or single-album rebuilds via --artist / --album are permitted)
if [ "$REBUILD" = true ] && [ -z "$TARGET_ARTIST" ] && [ "$IGPU_DETECTED" = true ] && [ "$FORCE_IGPU" = false ] && [ "$METADATA_ONLY" = false ]; then
    echo "🛑 HARPER FATAL ERROR: Integrated GPU (iGPU) Detected!"
    echo "===================================================================="
    echo "   Running a complete library --rebuild on shared integrated graphics"
    echo "   will result in extremely long, multi-hour processing times."
    echo ""
    echo "   Harper is aborting to prevent an accidental system lockdown."
    echo ""
    echo "   To rebuild a single artist or album, pass:"
    echo "   --rebuild --artist <artist-slug> [--album <album-slug>]"
    echo "   Or if you genuinely wish to rebuild the entire library on iGPU, append:"
    echo "   --force-igpu"
    echo "===================================================================="
    exit 1
fi

# Acknowledge user override for iGPU constraint
if [ "$REBUILD" = true ] && [ "$IGPU_DETECTED" = true ] && [ "$FORCE_IGPU" = true ] && [ "$METADATA_ONLY" = false ]; then
    echo "⚠️  HARPER WARNING: iGPU detected, but --force-igpu is active."
    echo "   Buckle up. This is going to take a while..."
fi

# --- DYNAMIC HARDWARE DETECTION & WORKER POOL LIMITS ---
echo "   🔍 HARPER: Scanning system hardware for multi-threading..."

# Determine total logical cores available for multiprocessing
if [[ "$OSTYPE" == "darwin"* ]]; then
    TOTAL_CORES=$(sysctl -n hw.ncpu)
else
    TOTAL_CORES=$(nproc)
fi

echo "   🎛️  System reports $TOTAL_CORES logical CPU cores."

# Allocate concurrent jobs dynamically, reserving 2 cores for system stability
if (( TOTAL_CORES > 4 )); then
    MAX_JOBS=$(( TOTAL_CORES - 2 ))
else
    MAX_JOBS=2
fi

echo "   🎚️  HARPER: Concurrency limit dynamically set to $MAX_JOBS simultaneous audio jobs."

# --- LOCATE 7-ZIP BINARY ---
# Attempt to find the local or system 7-Zip executable for archiving operations
SEVEN_ZIP_LOCAL="$ROOT_DIR/build-tools/7zip"
USE_SEVEN_ZIP=false

if [[ "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" ]]; then
     # Windows local executable
     if [ -f "$SEVEN_ZIP_LOCAL/7za.exe" ]; then
         SEVEN_ZIP_CMD="$SEVEN_ZIP_LOCAL/7za.exe"
         USE_SEVEN_ZIP=true
     fi
else
    # Linux/Mac check system PATH first, then fallback to local binaries
    if command -v 7zz &> /dev/null; then
        SEVEN_ZIP_CMD="7zz"
        USE_SEVEN_ZIP=true
    elif [ -f "$SEVEN_ZIP_LOCAL/7zz" ]; then
        SEVEN_ZIP_CMD="$SEVEN_ZIP_LOCAL/7zz"
        chmod +x "$SEVEN_ZIP_CMD"
        USE_SEVEN_ZIP=true
    fi
fi

if [ "$USE_SEVEN_ZIP" = true ]; then
    echo "   ✅ HARPER: 7-Zip loaded: $SEVEN_ZIP_CMD"
else
    echo "   ⚠️  HARPER: I can't find 7-Zip! I'll skip the zip files for now."
fi

# --- LOCATE UPSCALER BINARY ---
# Locate Real-ESRGAN executables depending on the host OS
UPSCALER_BASE="$ROOT_DIR/build-tools/realesrgan"
USE_UPSCALER=false

if [[ "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" ]]; then
    if [ -f "$UPSCALER_BASE/windows/realesrgan-ncnn-vulkan.exe" ]; then
        UPSCALER_CMD="$UPSCALER_BASE/windows/realesrgan-ncnn-vulkan.exe"
        USE_UPSCALER=true
    fi
elif [[ "$OSTYPE" == "darwin"* ]]; then
    if [ -f "$UPSCALER_BASE/macos/realesrgan-ncnn-vulkan" ]; then
        UPSCALER_CMD="$UPSCALER_BASE/macos/realesrgan-ncnn-vulkan"
        chmod +x "$UPSCALER_CMD"
        USE_UPSCALER=true
    fi
elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
    if [ -f "$UPSCALER_BASE/ubuntu/realesrgan-ncnn-vulkan" ]; then
        UPSCALER_CMD="$UPSCALER_BASE/ubuntu/realesrgan-ncnn-vulkan"
        chmod +x "$UPSCALER_CMD"
        USE_UPSCALER=true
    fi
fi

# Apply safe mode scaling restrictions if iGPU is detected
if [ "$USE_UPSCALER" = true ]; then
    if [ "$IGPU_DETECTED" = true ]; then
        echo "   ⚠️  HARPER: Upscaler engaging iGPU Safe Mode (Throttled Tile Size) for $GPU_INFO"
    else
        echo "   ✅ HARPER: Upscaler loaded for GPU: $GPU_INFO"
    fi
else
    echo "   ⚠️  HARPER: Upscaler missing from $UPSCALER_BASE. Skipping art enhancement."
fi

# --- OVERWRITE & METADATA STATUS LOGS ---
# Log configuration parameters that guide downstream operations
if [ "$REBUILD" = true ]; then
    if [ "$METADATA_ONLY" = true ]; then
        echo "   ⚡ HARPER: Rebuild Metadata flag detected! Overwriting JSON & Markdown only."
    elif [ -n "$TARGET_ARTIST" ] && [ -n "$TARGET_ALBUM" ]; then
        echo "   🎯 HARPER: Scoped Album Rebuild active! Overwriting ONLY '$TARGET_ARTIST/$TARGET_ALBUM'."
    elif [ -n "$TARGET_ARTIST" ]; then
        echo "   🎯 HARPER: Scoped Artist Rebuild active! Overwriting all albums for '$TARGET_ARTIST'."
    else
        echo "   ⚡ HARPER: Full Library Rebuild flag detected! Overwriting all tracks and archives."
    fi
fi

# Validate target path existence before progressing to actual processing loops
if [ ! -d "$SEARCH_PATH" ]; then
    echo "   ❌ HARPER: Whoops! Directory not found at $SEARCH_PATH"
    exit 1
fi

# --- OFFICIAL US ISRC AGENCY REGISTRANT INITIALIZATION (PREFIX: QTAHP) ---
# Registrant Name: Michael Ragsdale | Registrant ID: 185611
# Contact: dsp.operations@engineroom-records.com | Prefix Allocated: 2026-10-20
# Ledger Discipline: Scans all tracks.json files to determine both the highest
# allocated sequential designation ($TEMP_ISRC_COUNTER_FILE) and any unassigned
# sequential gaps between 00001 and max_seq ($TEMP_ISRC_GAPS_FILE) so that
# 04-track-processor.sh automatically backfills gaps before incrementing max_seq.
export ISRC_REGISTRANT_PREFIX="QTAHP"
export ISRC_YEAR_SUFFIX=$(date +"%y")
export TEMP_ISRC_COUNTER_FILE="$ROOT_DIR/temp_isrc_counter.txt"
export TEMP_ISRC_GAPS_FILE="$ROOT_DIR/temp_isrc_gaps.txt"
export TEMP_WAV_ISRC_MAP="$ROOT_DIR/temp_wav_isrc_map.tsv"

> "$TEMP_WAV_ISRC_MAP"
> "$TEMP_ISRC_GAPS_FILE"

python3 - "$SEARCH_PATH" "$ISRC_REGISTRANT_PREFIX" "$ISRC_YEAR_SUFFIX" "$TEMP_ISRC_COUNTER_FILE" "$TEMP_WAV_ISRC_MAP" "$TEMP_ISRC_GAPS_FILE" << 'PYEOF'
import glob, json, os, sys

search_path, prefix, yy, counter_file, map_file, gaps_file = sys.argv[1:7]
full_prefix = f"{prefix}{yy}".upper()
max_seq = 0
used_seqs = set()
wav_map = {}

for tf in sorted(glob.glob(f"{search_path}/*/*/tracks.json") + glob.glob(f"{search_path}/*/*/*/tracks.json")):
    rel = os.path.relpath(os.path.dirname(tf), search_path)
    artist = rel.split("/")[0]
    try:
        with open(tf, "r", encoding="utf-8") as f:
            data = json.load(f)
    except Exception:
        continue
    tracks = data if isinstance(data, list) else data.get("tracks", [])
    for t in tracks:
        isrc = str(t.get("isrc") or "").strip().upper()
        mwp = str(t.get("masterWavPath") or "").strip()
        if isrc:
            if mwp and f"{artist}|{mwp}" not in wav_map:
                wav_map[f"{artist}|{mwp}"] = isrc
            if isrc.startswith(full_prefix) and len(isrc) == 12 and isrc[7:].isdigit():
                seq = int(isrc[7:])
                used_seqs.add(seq)
                if seq > max_seq:
                    max_seq = seq

with open(counter_file, "w", encoding="utf-8") as f:
    f.write(str(max_seq))

gaps = [seq for seq in range(1, max_seq + 1) if seq not in used_seqs]
with open(gaps_file, "w", encoding="utf-8") as f:
    for seq in gaps:
        f.write(f"{seq}\n")

with open(map_file, "w", encoding="utf-8") as f:
    for k, v in sorted(wav_map.items()):
        f.write(f"{k}\t{v}\n")
PYEOF

INITIAL_ISRC_MAX=$(cat "$TEMP_ISRC_COUNTER_FILE" 2>/dev/null || echo "0")
INITIAL_GAP_COUNT=$(grep -c '^[0-9]' "$TEMP_ISRC_GAPS_FILE" 2>/dev/null | tr -d '[:space:]')
INITIAL_GAP_COUNT=${INITIAL_GAP_COUNT:-0}
if [ "$INITIAL_GAP_COUNT" -gt 0 ]; then
    FIRST_GAP=$(head -n 1 "$TEMP_ISRC_GAPS_FILE")
    LAST_GAP=$(tail -n 1 "$TEMP_ISRC_GAPS_FILE")
    echo "   🏷️  HARPER: US ISRC Agency Minter Ready (Prefix: ${ISRC_REGISTRANT_PREFIX}${ISRC_YEAR_SUFFIX} • Highest Allocated: $(printf '%05d' "$INITIAL_ISRC_MAX") • Backfill Queue: ${INITIAL_GAP_COUNT} unassigned gap(s) [$(printf '%05d' "$FIRST_GAP")–$(printf '%05d' "$LAST_GAP")])"
else
    echo "   🏷️  HARPER: US ISRC Agency Minter Ready (Prefix: ${ISRC_REGISTRANT_PREFIX}${ISRC_YEAR_SUFFIX} • Highest Allocated: $(printf '%05d' "$INITIAL_ISRC_MAX") • Backfill Queue: 0 gaps)"
fi
