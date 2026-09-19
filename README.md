# Whispree Local

Security-hardened local-only fork of Whispree for Apple Silicon Macs.

## Security model

Speech transcription and LLM correction are performed with local models only.

Removed from this fork:

- Groq and other cloud STT
- OpenAI, OpenAI-compatible, and Groq LLM providers
- Codex CLI token access and OpenAI OAuth
- screenshot / screen-context capture and vision models
- MediaRemoteAdapter and media playback automation
- Chrome / iTerm AppleEvents automation
- Sparkle auto-update and the upstream release pipeline
- the upstream signing team and bundle identifier

The app does not include an analytics or telemetry client, cloud inference provider, external recording URL scheme, or network entitlement. Model downloads still require outbound networking at the application/library level because this fork is not App-Sandboxed; after models and Python dependencies are installed, normal transcription and correction do not send audio or text to a remote inference service.

## Local providers

- STT: WhisperKit Large V3 Turbo (default) or MLX Audio / Qwen3-ASR
- LLM: local MLX text models only; default is mlx-community/Qwen3-4B-Instruct-2507-4bit
- Vision models are intentionally unsupported.

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

Swift packages are pinned in project.yml. Python workers use exact direct dependencies plus mlx-worker/uv.lock, and runtime setup uses uv sync --frozen. Review dependency changes before updating lockfiles.

## Upstream

Original project: https://github.com/Arsture/whispree

This fork deliberately trades cloud-provider flexibility and visual context for a smaller privacy and supply-chain surface.
