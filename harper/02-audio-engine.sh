#!/usr/bin/env bash
# ==============================================================================
# HARPER MODULE 02: AUDIO ENGINE
# ==============================================================================
# Architecture & Purpose:
# This module defines the `press_audio_formats` worker function used by the 
# Harper build system to transcode master WAV files into multiple distribution 
# formats (MP3 128k, MP3 V0, OGG Q9, FLAC). 
#
# Key Operations:
# 1. Accepts standard track metadata as positional arguments.
# 2. Injects a universal AI disclosure stamp into the audio file metadata.
# 3. Uses `ffmpeg` to encode the four distinct quality tiers.
# 4. Respects the global `$OVERWRITE` flag to skip or force re-encoding.
#
# Maintenance Notes:
# - FFmpeg runs in `-nostdin` and `-hide_banner` to prevent swallowing terminal
#   input during parallel execution loops.
# - The `$ART_FILE_PARAM` variable must be prepared by the caller module before 
#   invoking this function to inject cover art.
# ==============================================================================

# --- THE FFMPEG WORKER FUNCTION ---
press_audio_formats() {
    # Positional argument mapping for clarity
    local in_wav="$1"
    local f_base="$2"
    local t_title="$3"
    local t_artist="$4"
    local t_album="$5"
    local t_year="$6"
    local t_track="$7"
    local t_disc="$8"
    local t_genre="$9"
    local t_isrc="${10:-}"
    local local_ff_flag="$ffmpeg_flag"
    if [ "$MINTED_NEW_ISRC" = true ]; then
        local_ff_flag="-y"
    fi
    
    # Define the universal AI disclosure stamp required for copyright transparency
    local ai_disclaimer="Audio Generation: Suno. AI Elements: Vocals, Instrumentation, Composition. Human Elements: Lyrics, Narrative Lore. CC BY-SA 4.0. Commercial Rights Cleared."
    local transcode_err=0

    # --------------------------------------------------------------------------
    # Tier 1: Radio Edit (128kbps MP3)
    # Target: Fast web streaming, low bandwidth
    # --------------------------------------------------------------------------
    if [ ! -f "web-mp3/$f_base.mp3" ] || [ "$OVERWRITE" = true ] || [ "$MINTED_NEW_ISRC" = true ]; then
        # -write_id3v1 ensures legacy player compatibility alongside id3v2
        ffmpeg -nostdin -hide_banner -loglevel error $local_ff_flag -i "$in_wav" $ART_FILE_PARAM \
        -codec:a libmp3lame -b:a 128k -id3v2_version 3 -write_id3v1 1 \
        -metadata title="$t_title" -metadata artist="$t_artist" -metadata album="$t_album" \
        -metadata date="$t_year" -metadata track="$t_track" -metadata disc="$t_disc" -metadata genre="$t_genre" \
        -metadata TSRC="$t_isrc" -metadata ISRC="$t_isrc" \
        -metadata publisher="Engine Room Records" -metadata copyright="CC BY-SA 4.0 - $t_year Michael P. Ragsdale / RaggieSoft" \
        -metadata comment="Free Stream Edition | $ai_disclaimer" \
        "web-mp3/$f_base.mp3" || transcode_err=1
    fi

    local vault_dir="${ALBUM_VAULT_DIR:-vault}"

    # --------------------------------------------------------------------------
    # Tier 2: Premium MP3 (V0 Variable Bitrate)
    # Target: High-quality archival / standard premium download (Stored in Local Vault)
    # --------------------------------------------------------------------------
    if [ ! -f "$vault_dir/mp3/$f_base.mp3" ] || [ "$OVERWRITE" = true ] || [ "$MINTED_NEW_ISRC" = true ]; then
        # -q:a 0 sets the highest variable bitrate quality for LAME
        ffmpeg -nostdin -hide_banner -loglevel error $local_ff_flag -i "$in_wav" $ART_FILE_PARAM \
        -codec:a libmp3lame -q:a 0 -id3v2_version 3 -write_id3v1 1 \
        -metadata title="$t_title" -metadata artist="$t_artist" -metadata album="$t_album" \
        -metadata date="$t_year" -metadata track="$t_track" -metadata disc="$t_disc" -metadata genre="$t_genre" \
        -metadata TSRC="$t_isrc" -metadata ISRC="$t_isrc" \
        -metadata publisher="Engine Room Records" -metadata copyright="CC BY-SA 4.0 - $t_year Michael P. Ragsdale / RaggieSoft" \
        -metadata comment="Premium Archive | $ai_disclaimer" \
        "$vault_dir/mp3/$f_base.mp3" || transcode_err=1
    fi

    # --------------------------------------------------------------------------
    # Tier 3: Premium OGG (Q9 Variable Bitrate)
    # Target: Web audio API gapless playback and audiophile alternatives (Stored in Local Vault)
    # --------------------------------------------------------------------------
    if [ ! -f "$vault_dir/ogg/$f_base.ogg" ] || [ "$OVERWRITE" = true ] || [ "$MINTED_NEW_ISRC" = true ]; then
        # Note: Cover art injection is skipped here due to Ogg Vorbis container quirks
        # -q:a 9 is roughly equivalent to ~320kbps VBR
        ffmpeg -nostdin -hide_banner -loglevel error $local_ff_flag -i "$in_wav" \
        -codec:a libvorbis -q:a 9 \
        -metadata title="$t_title" -metadata artist="$t_artist" -metadata album="$t_album" \
        -metadata date="$t_year" -metadata tracknumber="$t_track" -metadata discnumber="$t_disc" \
        -metadata ISRC="$t_isrc" \
        -metadata publisher="Engine Room Records" -metadata copyright="CC BY-SA 4.0 - $t_year Michael P. Ragsdale / RaggieSoft" \
        -metadata comment="Premium Archive | $ai_disclaimer" \
        "$vault_dir/ogg/$f_base.ogg" || transcode_err=1
    fi

    # --------------------------------------------------------------------------
    # Tier 4: Premium FLAC (Lossless)
    # Target: Master archive and strict audiophile distribution (Stored in Local Vault)
    # --------------------------------------------------------------------------
    if [ ! -f "$vault_dir/flac/$f_base.flac" ] || [ "$OVERWRITE" = true ] || [ "$MINTED_NEW_ISRC" = true ]; then
        # -compression_level 8 provides maximum algorithmic file size reduction 
        # without affecting the lossless audio quality (it just takes longer to encode)
        ffmpeg -nostdin -hide_banner -loglevel error $local_ff_flag -i "$in_wav" $ART_FILE_PARAM \
        -codec:a flac -compression_level 8 \
        -metadata title="$t_title" -metadata artist="$t_artist" -metadata album="$t_album" \
        -metadata date="$t_year" -metadata track="$t_track" -metadata disc="$t_disc" -metadata genre="$t_genre" \
        -metadata ISRC="$t_isrc" \
        -metadata publisher="Engine Room Records" -metadata copyright="CC BY-SA 4.0 - $t_year Michael P. Ragsdale / RaggieSoft" \
        -metadata comment="Premium Audiophile Archive | $ai_disclaimer" \
        "$vault_dir/flac/$f_base.flac" || transcode_err=1
    fi

    return "$transcode_err"
}
