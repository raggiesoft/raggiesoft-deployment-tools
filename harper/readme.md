# Harper: The Studio Engineer 🎧

> _"I live in the studio. I take raw master tapes and press them for the airwaves."_

## Overview

Harper (v21.8.0) is the high-energy, modular Bash workhorse that automates the entire audio processing, archiving, and metadata pipeline for Engine Room Records. She transforms raw central vault `.wav` files into fully tagged, DistroKid-ready commercial releases while compiling chronological master discographies and tracking internal catalog IDs.

## Key Features

- **Multi-Tier Audio Pressing:** Parallelized `ffmpeg` generation of 128kbps Radio Edits, V0 Premium MP3s, Q9 OGGs, and Lossless FLACs.
    
- **Master Discography Compiler:** Chronologically sorts albums by narrative year to bind artist lore, lyrics, and structural cues into a single master markdown file.
    
- **Dynamic Threading & iGPU Safety:** Automatically calculates logical CPU cores to maximize concurrent audio rendering without locking up shared integrated graphics.
    
- **DDEX-Compliant Metadata & AI Transparency:** Deep-parses Schema.org JSON and `tracks.json` (`title` + optional `version` key) to generate DistroKid and DistributeMusic.ai ready DSP sheets—including per-album `dsp-upload-sheet.md` (with pre-separated `Name` and `Version` fields for strict distributor title validation) and per-artist `*-dsp-upload-guide.md` rollups. When `.version` is defined on a track in `tracks.json` (e.g., `"title": "Electric Color", "version": "Live in Norfolk"`), Harper automatically constructs the composite tag title `$songName ($versionInformation)` (`"Electric Color (Live in Norfolk)"`) and stamps it into BWF WAV headers, ID3v2/v1 tags (MP3 128k & V0), and Vorbis Comments (OGG Q9 & FLAC). Injects granular AI disclaimers—explicitly dividing human-authored lyrics/lore from synthetic audio—directly into archive `README.txt` files and audio containers.
    
- **Vault Archiving:** Decouples heavy standard and audiophile tiers into ultra-compressed 7-Zip archives (`.zip` and `.7z`).
    
- **Art Upscaling:** Integrates Real-ESRGAN for automated 4K album art enhancement.
    

## Modular Architecture

Harper is split into focused modules for safe execution and easy maintenance. They are loaded dynamically by the main `harper.sh` script:

```text
/harper
├── 01-init.sh             # Setup, hardware detection, dependencies
├── 02-audio-engine.sh     # The parallelized ffmpeg worker function
├── 03-album-processor.sh  # Chronological sorting and album routing
├── 04-track-processor.sh  # JSON parsing, metadata, and lyrics
├── 05-archiver.sh         # 7-Zip compression and Vault routing
└── 06-finalize.sh         # Catalog indexing and cleanup
```

## Usage & Flags

Execute Harper from the root workspace directory containing the `/harper` module folder. Ensure `ffmpeg`, `ffprobe`, `jq`, and `7z` (or `7zz`) are available in your environment.

```
./harper.sh [FLAGS]
```

- `--rebuild` (or `-y`): Wipes the slate clean. Overwrites existing audio, archives, and master discography files from scratch across the entire library (or scopes the rebuild when paired with `--artist` / `--album`).

- `--artist <artist-slug>`: When used with `--rebuild`, rebuilds **only** that artist's entire library (e.g., `./harper.sh --rebuild --artist the-stardust-engine`) while fast-indexing all other artists so global catalogs (`metadata.json` and `master-catalog.json`) remain complete.

- `--album <album-slug>`: Requires `--artist <artist-slug>`. When used with `--rebuild --artist <artist-slug>`, rebuilds **only** that single album (e.g., `./harper.sh --rebuild --artist the-stardust-engine --album 2016-live-at-the-crucible`).
    
- `--metadata`: Bypasses audio rendering and archiving to rapidly repack JSON updates, DSP sheets, and lyrics.
    
- `--force-igpu`: Overrides the safety lock to allow full parallel audio processing on integrated graphics.