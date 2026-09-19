# Whispree Local

Apple Silicon Mac에서 완전 로컬 추론을 우선하도록 보안 강화한 Whispree fork입니다.

## 보안 설계

음성 전사와 LLM 텍스트 교정은 로컬 모델만 사용합니다.

이 fork에서 제거한 기능:

- Groq 등 Cloud STT
- OpenAI / OpenAI-compatible / Groq LLM
- Codex CLI 인증 파일 접근 및 OpenAI OAuth
- 화면 캡처, Screen Context, Vision 모델
- MediaRemoteAdapter 및 미디어 제어
- Chrome / iTerm AppleEvents 자동화
- Sparkle 자동 업데이트와 upstream release/signing 파이프라인
- upstream Team ID와 Bundle ID

Analytics/Telemetry client는 포함하지 않습니다. 모델과 빌드 의존성 다운로드를 위해 network.client entitlement는 유지합니다. 모델과 Python 환경 설치가 끝난 뒤 일반적인 음성 전사와 텍스트 교정 과정에서는 오디오나 텍스트를 원격 inference 서비스로 전송하지 않습니다.

## 로컬 모델

- STT: WhisperKit Large V3 Turbo(기본 권장) 또는 MLX Audio / Qwen3-ASR
- LLM: 로컬 MLX 텍스트 모델만 지원, 기본 모델은 mlx-community/Qwen3-4B-Instruct-2507-4bit
- Vision 모델은 의도적으로 지원하지 않습니다.

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

## 의존성 고정

Swift package는 project.yml에서 버전을 고정합니다. Python worker는 direct dependency를 exact version으로 지정하고 mlx-worker/uv.lock을 커밋하며 실행 시 uv sync --frozen을 사용합니다.

## 원본 프로젝트

https://github.com/Arsture/whispree

이 fork는 Cloud provider 유연성과 화면 컨텍스트 기능 대신 개인정보 보호와 공급망 표면 축소를 우선합니다.
