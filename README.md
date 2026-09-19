# Whispree Local

Apple Silicon Mac에서 **완전 로컬 추론과 보안 우선**을 목표로 강화한 Whispree fork입니다.

## 핵심 구성

런타임은 Swift 네이티브 경로만 사용합니다.

- STT: **WhisperKit Large V3 Turbo** 고정
- LLM: **mlx-community/Qwen3-8B-4bit** 고정
- Python 런타임 없음
- uv / pip / virtualenv 없음
- 별도 worker process / stdin·stdout IPC 없음
- Cloud inference provider 없음

WhisperKit CoreML 모델과 tokenizer, Qwen3 8B 모델은 모두 검토된 **immutable commit SHA**로 revision을 고정합니다.

## 보안 설계

이 fork에서 제거한 기능:

- Groq 등 Cloud STT
- OpenAI / OpenAI-compatible / Groq LLM
- Codex CLI 인증 파일 접근 및 OpenAI OAuth
- MLX Audio / Python `mlx-audio`
- Python `mlx-lm` worker
- 화면 캡처, Screen Context, 이미지 붙여넣기, Vision 모델
- MediaRemoteAdapter 및 미디어 제어
- Chrome / iTerm AppleEvents 자동화
- iCloud / 공유 사전 동기화
- Sparkle 자동 업데이트와 upstream release/signing 파이프라인
- 외부 녹음 URL scheme
- upstream Team ID와 Bundle ID

Analytics/Telemetry client, Cloud inference provider, network entitlement, Cloud sync 기능을 포함하지 않습니다.

다만 App Sandbox를 사용하지 않으므로 **고정된 모델을 최초 다운로드할 때는 네트워크를 사용**할 수 있습니다. 모델 설치 후 일반적인 음성 전사와 텍스트 교정 경로에서는 오디오나 텍스트를 원격 inference 서비스로 전송하지 않습니다.

## 로컬 모델

### STT

WhisperKit Large V3 Turbo만 지원합니다.

- CoreML + Apple Neural Engine 사용
- 모델 repository와 tokenizer revision을 각각 commit SHA로 고정
- 다른 STT provider 선택 기능 없음

### LLM

Qwen3 8B 4-bit만 지원합니다.

- `mlx-community/Qwen3-8B-4bit`
- Swift `mlx-swift-lm`에서 직접 실행
- Hugging Face commit SHA 고정
- Python fallback 없음
- 다른 LLM 모델 선택 기능 없음
- 필요하면 텍스트 교정 자체는 끌 수 있음

## 필요한 권한

- 마이크 — 음성 녹음
- 손쉬운 사용(Accessibility) — 전역 단축키와 텍스트 자동 삽입
- 화면 기록 및 AppleEvents 권한은 사용하지 않습니다.

## 직접 빌드

요구 사항:

- macOS 14+
- Apple Silicon
- Xcode 16+
- XcodeGen

```bash
brew install xcodegen
git clone https://github.com/scarkoo/whispree.git
cd whispree
git checkout security/local-only-hardening
xcodegen generate
open Whispree.xcodeproj
```

Xcode의 **Signing & Capabilities**에서 본인의 Personal Team을 선택합니다.

저장소에는 `DEVELOPMENT_TEAM`을 고정하지 않습니다.

Bundle ID:

```text
com.scarkoo.whispree
```

본인 Mac에서 직접 빌드해 사용할 목적이라면 유료 Apple Developer Program 가입은 필요하지 않습니다.

## 의존성 및 공급망 고정

- Swift package는 exact version/revision으로 고정
- 전체 SwiftPM graph는 `Package.resolved`로 고정
- Hugging Face 모델은 mutable `main` 대신 commit SHA 사용
- GitHub Actions는 `contents: read`만 사용
- CI는 lockfile을 수정하거나 branch에 자동 push하지 않음
- `actions/checkout`도 commit SHA로 고정
- CI에서 SwiftPM pin drift, plist/entitlement, unsigned Release build를 검증

## 네트워크 경계

이 프로젝트의 "로컬 전용"은 **음성/텍스트 inference를 외부 API로 보내지 않는다**는 의미입니다.

모델 최초 다운로드에는 Hugging Face 등의 네트워크 접근이 필요합니다. 또한 App Sandbox를 사용하지 않기 때문에 entitlement 제거만으로 운영체제 수준의 outbound network 차단이 적용되는 것은 아닙니다.

모델 설치 후 더 강한 네트워크 격리가 필요하다면 macOS outbound firewall을 별도로 적용할 수 있습니다.

## 원본 프로젝트

https://github.com/Arsture/whispree

이 fork는 provider 다양성과 확장성보다 **개인정보 보호, 재현 가능한 공급망, 작은 공격 표면**을 우선합니다.
