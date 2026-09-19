# Whispree Local

Apple Silicon Mac에서 **완전 로컬 추론과 보안 우선**을 목표로 강화한 Whispree fork입니다.

## 보안 설계

음성 전사와 LLM 텍스트 교정은 로컬 모델만 사용합니다.

이 fork에서 제거한 기능:

- Groq 등 Cloud STT
- OpenAI / OpenAI-compatible / Groq LLM
- Codex CLI 인증 파일 접근 및 OpenAI OAuth
- 화면 캡처, Screen Context, 이미지 붙여넣기, Vision 모델
- MediaRemoteAdapter 및 미디어 제어
- Chrome / iTerm AppleEvents 자동화
- iCloud / 공유 사전 동기화
- Sparkle 자동 업데이트와 upstream release/signing 파이프라인
- 외부 녹음 URL scheme
- upstream Team ID와 Bundle ID

Analytics/Telemetry client, Cloud inference provider, network entitlement, Cloud sync 기능을 포함하지 않습니다. 다만 App Sandbox를 사용하지 않으므로 **모델과 Python 패키지를 최초 설치할 때는 네트워크를 사용**할 수 있습니다. 고정된 모델과 Python 환경 설치가 끝난 뒤의 일반적인 음성 전사/텍스트 교정 경로에서는 오디오나 텍스트를 원격 inference 서비스로 전송하지 않습니다.

## 로컬 모델

- STT: revision이 고정된 WhisperKit Large V3 Turbo(기본) 또는 MLX Audio / Qwen3-ASR
- LLM: Hugging Face commit SHA로 고정된 로컬 MLX 텍스트 모델만 지원
- 기본 LLM: mlx-community/Qwen3-4B-Instruct-2507-4bit
- Vision 모델은 지원하지 않습니다.

WhisperKit CoreML 모델과 tokenizer는 각각 고정된 commit SHA를 사용하며 revision별 별도 cache root에 저장합니다. MLX 모델 역시 다운로드 시 검토된 Hugging Face commit SHA를 명시합니다.

## 필요한 권한

- 마이크 — 음성 녹음
- 손쉬운 사용(Accessibility) — 전역 단축키와 텍스트 자동 삽입
- 화면 기록 및 AppleEvents 권한은 사용하지 않습니다.

## 직접 빌드

요구 사항: macOS 14+, Apple Silicon, Xcode 16+, XcodeGen, Python 모델 사용 시 uv.

    brew install xcodegen uv
    git clone https://github.com/scarkoo/whispree.git
    cd whispree
    git checkout security/local-only-hardening
    xcodegen generate
    open Whispree.xcodeproj

Xcode의 Signing & Capabilities에서 본인의 Personal Team을 선택합니다. 저장소에는 DEVELOPMENT_TEAM을 고정하지 않습니다. Bundle ID는 com.scarkoo.whispree 입니다.

본인 Mac에서 직접 빌드해 사용할 목적이라면 유료 Apple Developer Program 가입은 필요하지 않습니다.

## 의존성 및 공급망 고정

- Swift package는 exact version/revision과 Package.resolved로 고정합니다.
- Python direct dependency는 exact version, 전체 dependency graph는 mlx-worker/uv.lock으로 고정합니다.
- Python worker 실행 시 uv sync --frozen / uv run --frozen을 사용합니다.
- Hugging Face 모델도 mutable main 대신 commit SHA를 사용합니다.
- Python worker는 signed app bundle의 파일로 매번 갱신하고 복사 후 byte 비교를 통과해야 실행합니다.
- GitHub Actions는 contents: read만 사용하며 lockfile을 수정하거나 branch에 자동 push하지 않습니다.

## 원본 프로젝트

https://github.com/Arsture/whispree

이 fork는 Cloud provider 유연성, Cloud 동기화, 화면 컨텍스트 기능보다 개인정보 보호와 공급망 표면 축소를 우선합니다.
