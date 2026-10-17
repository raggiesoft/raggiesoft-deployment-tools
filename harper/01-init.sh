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

# --- PATH CONFIGURATION ---
# Define the root path for artist records and metadata (resolved from /raggiesoft-deployment-tools)
SEARCH_PATH="../raggiesoft-assets/engine-room-records/artists"
METADATA_FILE="../raggiesoft-assets/engine-room-records/artists/metadata.json"
export VAULTS_ROOT="$ROOT_DIR/../raggiesoft-vaults/engine-room-records/artists"

# Temporary indices used for fast writes during parallel processing
TEMP_SEARCH_INDEX="temp_search_index.jsonl" 
TEMP_CATALOG_INDEX="temp_catalog_index.jsonl" 

echo "   🎚️  Targeting Studio Archives: $SEARCH_PATH"
echo "   🔐 Targeting Local Master Vaults: $VAULTS_ROOT"

# Initialize Indices by truncating/creating them
> "$TEMP_SEARCH_INDEX" 
> "$TEMP_CATALOG_INDEX"

# --- ARGUMENT PARSING ---
# Default execution flags
REBUILD=false
FORCE_IGPU=false
OVERWRITE=false
METADATA_ONLY=false
NO_VTT=false
ffmpeg_flag="-n"

# Process provided command-line arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --rebuild|-y) 
            REBUILD=true
            OVERWRITE=true
            # Force ffmpeg to overwrite output files
            ffmpeg_flag="-y" 
            ;;
        --force-igpu) FORCE_IGPU=true ;;
        --metadata) METADATA_ONLY=true ;;
        --no-vtt) NO_VTT=true ;;
        *) echo "🛑 HARPER: Unknown parameter passed: $1"; exit 1 ;;
    esac
    shift
done

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

# Prevent accidental complete rebuilds on iGPUs due to performance constraints
if [ "$REBUILD" = true ] && [ "$IGPU_DETECTED" = true ] && [ "$FORCE_IGPU" = false ] && [ "$METADATA_ONLY" = false ]; then
    echo "🛑 HARPER FATAL ERROR: Integrated GPU (iGPU) Detected!"
    echo "===================================================================="
    echo "   Running a complete --rebuild on shared integrated graphics will"
    echo "   result in extremely long, multi-hour processing times."
    echo ""
    echo "   Harper is aborting to prevent an accidental system lockdown."
    echo ""
    echo "   If you genuinely wish to proceed with the iGPU, you must append:"
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
if [ "$OVERWRITE" = true ]; then
    if [ "$METADATA_ONLY" = true ]; then
        echo "   ⚡ HARPER: Rebuild Metadata flag detected! Overwriting JSON & Markdown only."
    else
        echo "   ⚡ HARPER: Rebuild flag detected! Overwriting old tracks and archives."
    fi
fi

# Validate target path existence before progressing to actual processing loops
if [ ! -d "$SEARCH_PATH" ]; then
    echo "   ❌ HARPER: Whoops! Directory not found at $SEARCH_PATH"
    exit 1
fi