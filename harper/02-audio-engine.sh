#!/usr/bin/env bash
# ==============================================================================
# HARPER MODULE 02: AUDIO ENGINE (`harper/02-audio-engine.sh`)
# ==============================================================================
# PLAIN-ENGLISH OVERVIEW (100-LEVEL INTRO):
#   This module defines a single reusable Bash function—`press_audio_formats`—that
#   `04-track-processor.sh` launches in parallel in the background (`&`) across
#   CPU cores! Given one mastered WAV file (whose EBU R128 / streaming loudness
#   profile and BWF header are already locked in), `press_audio_formats` uses
#   **FFmpeg** to press 4 distinct audio quality tiers while embedding cover art,
#   ISRC codes, CC BY-SA 4.0 licensing, and AI transparency tags into every file:
#     - Tier 1 (`web-mp3/*.mp3`)   : 128 kbps CBR MP3 -> Public CDN (`assets.raggiesoft.com`)
#                                    for instant low-bandwidth streaming on `music.raggiesoft.com`.
#     - Tier 2 (`vault/mp3/*.mp3`) : LAME V0 (~245 kbps VBR) MP3 -> Private Local Vault.
#     - Tier 3 (`vault/ogg/*.ogg`) : Vorbis Q9 (~320 kbps VBR) OGG -> Private Local Vault
#                                    (gapless frame boundaries for rock operas!).
#     - Tier 4 (`vault/flac/*.flac`): Lossless Level-8 FLAC -> Private Local Vault
#                                    (100% bit-identical audio samples to the WAV master,
#                                    compressed ~50% smaller like a ZIP file for audio!).
#
# CRITICAL FFMPEG-IN-LOOPS RULE (`-nostdin`):
#   By default, `ffmpeg` listens to standard input (`stdin`) for interactive keys
#   like `q` to quit. When `ffmpeg` runs inside a `while read` loop, it will
#   accidentally swallow lines of JSON from `stdin` and skip tracks unless you
#   pass `-nostdin`! `-hide_banner -loglevel error` keeps multi-core output clean.
# ==============================================================================

# --- THE FFMPEG WORKER FUNCTION ---
press_audio_formats() {
    # Map numbered positional parameters (`$1`..`$10`) into descriptive `local` variables.
    # BASH POSITIONAL PARAMETER GOTCHA (`${10:-}`):
    #   Single-digit arguments can be written `$1`..`$9`, but 2-digit arguments MUST
    #   use curly braces `${10}`—otherwise Bash reads `$10` as `$1` followed by `"0"`!
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
    # If `04-track-processor.sh` just minted or linked a brand-new ISRC for this song,
    # force `-y` (overwrite) so the new ISRC is guaranteed to be baked into every audio file!
    if [ "$MINTED_NEW_ISRC" = true ]; then
        local_ff_flag="-y"
    fi
    
    # Universal AI & CC BY-SA 4.0 disclosure embedded into every file's `comment` tag
    local ai_disclaimer="Audio Generation: Suno. AI Elements: Vocals, Instrumentation, Composition. Human Elements: Lyrics, Narrative Lore. CC BY-SA 4.0. Commercial Rights Cleared."
    local transcode_err=0

    # --------------------------------------------------------------------------
    # Tier 1: Radio Edit (128kbps CBR MP3 -> Public `web-mp3/` CDN folder)
    # --------------------------------------------------------------------------
    # FFmpeg Flags Explained:
    #   - `$ART_FILE_PARAM`     : Unquoted intentionally so `-i album-art.jpg -map 0:a -map 1:v ...`
    #                             attaches the JPEG cover art as an embedded `APIC` picture stream!
    #   - `-codec:a libmp3lame` : Uses the industry-standard LAME MP3 audio encoder.
    #   - `-b:a 128k`           : Constant Bitrate of 128 kilobits/sec (~1 MB per minute of song).
    #   - `-id3v2_version 3 -write_id3v1 1`: Writes BOTH modern ID3v2.3 tags (most compatible with
    #                             Windows Explorer, car stereos, & iTunes) AND legacy ID3v1 tags.
    #   - `-metadata TSRC=...`  : `TSRC` is the official ID3v2.3 frame ID for ISRC codes.
    #   - `|| transcode_err=1`  : Records any non-zero FFmpeg failure so the parent pool detects it.
    if [ ! -f "web-mp3/$f_base.mp3" ] || [ "$OVERWRITE" = true ] || [ "$MINTED_NEW_ISRC" = true ]; then
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
    # Tier 2: Premium MP3 (LAME V0 Variable Bitrate -> Private Local Vault)
    # --------------------------------------------------------------------------
    # `-q:a 0` ("V0") allocates higher bitrates (up to 320 kbps) to dense synth/guitar
    # crescendos and lower bitrates to quiet passages—achieving transparent perceptual quality.
    if [ ! -f "$vault_dir/mp3/$f_base.mp3" ] || [ "$OVERWRITE" = true ] || [ "$MINTED_NEW_ISRC" = true ]; then
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
    # Tier 3: Premium OGG Vorbis (Q9 Variable Bitrate -> Private Local Vault)
    # --------------------------------------------------------------------------
    # `-codec:a libvorbis -q:a 9` encodes ~320 kbps VBR with sample-accurate gapless
    # transitions (MP3 adds tiny encoder-delay padding frames, whereas Ogg Vorbis is
    # natively gapless!). Vorbis Comments use `tracknumber` and `discnumber` field names,
    # and omit `-disposition:v attached_pic` due to Ogg video-stream container quirks.
    if [ ! -f "$vault_dir/ogg/$f_base.ogg" ] || [ "$OVERWRITE" = true ] || [ "$MINTED_NEW_ISRC" = true ]; then
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
    # Tier 4: Premium FLAC (Bit-Perfect Lossless -> Private Local Vault)
    # --------------------------------------------------------------------------
    # `-codec:a flac -compression_level 8` applies maximum lossless linear-prediction math:
    # unlike MP3/OGG (which discard inaudible frequencies), FLAC is 100% lossless—decoding
    # a Level 8 FLAC reproduces the exact same PCM waveform bit-for-bit as the source WAV!
    if [ ! -f "$vault_dir/flac/$f_base.flac" ] || [ "$OVERWRITE" = true ] || [ "$MINTED_NEW_ISRC" = true ]; then
        ffmpeg -nostdin -hide_banner -loglevel error $local_ff_flag -i "$in_wav" $ART_FILE_PARAM \
        -codec:a flac -compression_level 8 \
        -metadata title="$t_title" -metadata artist="$t_artist" -metadata album="$t_album" \
        -metadata date="$t_year" -metadata track="$t_track" -metadata disc="$t_disc" -metadata genre="$t_genre" \
        -metadata ISRC="$t_isrc" \
        -metadata publisher="Engine Room Records" -metadata copyright="CC BY-SA 4.0 - $t_year Michael P. Ragsdale / RaggieSoft" \
        -metadata comment="Premium Audiophile Archive | $ai_disclaimer" \
        "$vault_dir/flac/$f_base.flac" || transcode_err=1
    fi

    # Return `0` if all 4 tiers succeeded, or `1` if any `ffmpeg` invocation failed
    return "$transcode_err"
}
