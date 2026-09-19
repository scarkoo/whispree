# Whispree Local

Security-hardened local-only fork of Whispree for Apple Silicon Macs.

## Security model

Speech transcription and LLM correction are performed with local models only.

Removed from this fork:

- Groq and other cloud STT
- OpenAI, OpenAI-compatible, and Groq LLM providers
- Codex CLI token access and OpenAI OAuth
- screenshot / screen-context capture, image paste, and vision models
- MediaRemoteAdapter and media playback automation
- Chrome / iTerm AppleEvents automation
- iCloud/shared dictionary synchronization
- Sparkle auto-update and the upstream release pipeline
- external recording URL schemes
- the upstream signing team and bundle identifier

The app does not include an analytics or telemetry client, cloud inference provider, network entitlement, or cloud-sync feature. The app is not App-Sandboxed, so model/package installation can still use outbound networking. Once the pinned models and Python environment are installed, normal transcription and correction do not send audio or text to a remote inference service.

## Local providers

- STT: pinned WhisperKit Large V3 Turbo (default) or pinned MLX Audio / Qwen3-ASR
- LLM: pinned local MLX text model revisions only; default is mlx-community/Qwen3-4B-Instruct-2507-4bit
- Vision models are intentionally unsupported.

WhisperKit CoreML weights and the Whisper tokenizer are downloaded into revision-specific cache roots. MLX model downloads are also pinned to reviewed Hugging Face commit SHAs.

## Permissions

- Microphone — voice recording
- Accessibility — global shortcuts and text insertion
- Screen Recording and Apple Events permissions are not used.

## Build

Requirements: macOS 14+, Apple Silicon, Xcode 16+, XcodeGen, and uv when using Python-backed models.

    brew install xcodegen uv
    git clone https://github.com/scarkoo/whispree.git
    cd whispree
    git checkout security/local-only-hardening
    xcodegen generate
    open Whispree.xcodeproj

In Xcode select your own Personal Team under Signing & Capabilities. The repository intentionally does not commit a DEVELOPMENT_TEAM. Bundle identifier: com.scarkoo.whispree.

A paid Apple Developer Program membership is not required for building and running the app on your own Mac.

## Dependency reproducibility

- Swift packages are exact-version/revision pinned and committed in Package.resolved.
- Python direct dependencies are exact-pinned and the full graph is committed in mlx-worker/uv.lock.
- Python workers run with uv sync --frozen / uv run --frozen.
- Hugging Face model revisions are immutable commit SHAs.
- Bundled Python worker files are refreshed from the signed app bundle and byte-verified before execution.
- GitHub Actions has read-only repository permissions and only verifies lockfiles/build output; it does not push generated commits.

## Upstream

Original project: https://github.com/Arsture/whispree

This fork deliberately trades cloud-provider flexibility, cloud synchronization, and visual context for a smaller privacy and supply-chain surface.
