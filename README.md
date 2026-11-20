# RaggieSoft Deployment Tools (`/raggiesoft-deployment-tools`)

[![License: MIT](https://img.shields.io/badge/Code_License-MIT-0369a1.svg)](./LICENSE)
[![Stack: Bash + PHP 8.5 CLI + FFmpeg](https://img.shields.io/badge/Stack-Bash_%2B_PHP_8.5_CLI_%2B_FFmpeg-334155.svg)](https://michaelpragsdale.com/build-team)

Centralized CI/CD build-gate, static content compilation, audio mastering, and non-root server deployment suite powering the 11-property RaggieSoft web and native ecosystem. Full architectural documentation is published at **`https://michaelpragsdale.com/build-team`**.

## Core CLI Orchestrators

- **[`jenna-sync.sh`](./jenna-sync.sh) (Multi-Repo Build Gate & S3 CDN Orchestrator):**
  Single-command release pipeline executing polyglot static builds, SEO/link validation gates, multi-repository Git commits across `raggiesoft-portfolio`, `stardust-engine-cms`, `raggiesoft-hub`, `raggiesoft-corporate`, `raggiesoft-engine-room-records`, `raggiesoft-music`, `raggiesoft-stardust-engine`, `raggiesoft-book-library`, `raggiesoft-backstage`, `raggiesoft-lore`, `raggiesoft-nebulae`, `raggiesoft-storetrainer`, `raggiesoft-narratives`, `nginx-config`, `raggiesoft-deployment-tools`, and `raggiesoft-assets`, followed by differential DigitalOcean Spaces S3 CDN synchronization via `rclone`.
- **[`sarah-deploy.sh`](./sarah-deploy.sh) (Non-Root Continuous Deployment Agent):**
  Server-side deployment daemon running on the hardened Ubuntu NYC1 host (`EUID != 0` enforced), verifying remote Git commit SHAs on a 5-minute cron schedule and atomically promoting pre-built static and PHP 8.5 bundles into `/var/www/*` via `rsync`.
- **[`paige.php`](./paige.php) (Markdown Manuscript, Search Index & Digital Edition Compiler):**
  PHP 8.5 CLI compiler that validates YAML frontmatter and cross-chapter link integrity, builds hierarchical JSON route trees (`catalog.json`, `toc.json`, Story Crossroads branching manifests) and full-text `search-index.json` payloads for `books.raggiesoft.com`, and packages downloadable EPUB, PDF, and `.7z` editions.
- **[`harper.sh`](./harper.sh) & [`harper/`](./harper/) (Multi-Core FFmpeg Audio Mastering & WebVTT Verifier):**
  Idempotent studio media pipeline performing multi-core FFmpeg audio normalization, Broadcast Wave Format (BWF) RIFF/BEXT metadata stamping, human-verified WebVTT (`NOTE SYNC_TYPE: HUMAN_VERIFIED`) caption validation, DistroKid metadata verification, and multi-tier archive packaging while keeping 24-bit WAV masters isolated off public cloud storage.
- **[`claire.sh`](./claire.sh) (Deterministic Build Artifact Cleaner):**
  Idempotent workspace and studio build-cache sweeper.

## License

- **Code & Automation Scripts:** [MIT License](./LICENSE)
