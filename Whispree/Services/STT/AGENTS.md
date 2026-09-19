# STT Service

이 fork의 STT는 **WhisperKit Large V3 Turbo 하나로 고정**합니다.

## 구조

- `WhisperKitProvider.swift` — Swift/WhisperKit 기반 로컬 STT
- CoreML 모델 repository와 tokenizer는 immutable Hugging Face commit SHA로 고정
- 다른 STT provider, Cloud STT, Python worker fallback은 지원하지 않음

## 보안 규칙

- 음성 데이터를 원격 inference API로 전송하지 않음
- 모델 최초 다운로드만 네트워크 사용 가능
- 화면 캡처나 외부 컨텍스트를 STT 입력에 포함하지 않음
- 새 STT provider를 추가할 경우 local-only 보안 모델을 먼저 재검토할 것
