# RaggieSoft Deployment Tools (`/raggiesoft-deployment-tools`)

Centralized DevOps, CI/CD, audio mastering, and content compilation orchestration suite for the RaggieSoft multi-domain ecosystem.

## Core Orchestrators

- **[`jenna-sync.sh`](./jenna-sync.sh) (Jenna — The Development Liaison):**
  Multi-repository build, QA audit, Git synchronization (`raggiesoft-hub`, `stardust-engine-cms`, `raggiesoft-narratives`, `raggiesoft-nebulae`, `raggiesoft-book-library`, `raggiesoft-lore`, `raggiesoft-music`, `raggiesoft-portfolio`, `raggiesoft-deployment-tools`, `nginx-config`, `raggiesoft-assets`), and DigitalOcean Spaces CDN distribution (`rclone`).
- **[`sarah-deploy.sh`](./sarah-deploy.sh) (Sarah — Autonomous Server Deployment):**
  Zero-root continuous deployment agent running on the NYC1 DigitalOcean Droplet via `systemd` timer (`sarah.timer`), pulling pre-compiled static and PHP payloads from GitHub into `/var/www/*`.
- **[`harper.sh`](./harper.sh) & [`harper/`](./harper/) (Harper — The Studio Engineer):**
  Modular multi-threaded FFmpeg audio mastering, Broadcast Wave Format (BWF) RIFF/BEXT metadata stamping, Real-ESRGAN cover art upscaling, DistroKid metadata sheet generation, CC BY-SA 4.0 `/suno-prompts/` archive packaging, and Google Gemini Multimodal Audio-to-WebVTT (`SYNC_TYPE: HUMAN_VERIFIED`) lyric alignment.
- **[`claire.sh`](./claire.sh) (Claire — Technical Debt Sweeper):**
  Deterministic build artifact cleaner for the Engine Room Records studio archives.

## License

- **Code & Automation Scripts:** [MIT License](./LICENSE)

