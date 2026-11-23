# 🌿 Pixel Terrarium

> macOS 메뉴 막대 속에 조용히 살아 숨 쉬는 힐링 픽셀 테라리움 데스크톱 펫.

[English](../../README.md#english) | [简体中文](../../README.md#简体中文) | [繁體中文](README.zh-Hant.md) | [日本語](README.ja.md) | **한국어** | [Español](README.es.md) | [Deutsch](README.de.md) | [Français](README.fr.md)

<p align="center">
  <img src="../assets/itch_cover_630x500.png" alt="Pixel Terrarium Cover" width="520" />
</p>

### 📸 스크린샷

| 🌿 촉촉한 이끼원 (Lush Meadow) | 🏜️ 따스한 사막 (Sunlit Desert) |
| :---: | :---: |
| <img src="../assets/screenshot_meadow.png" alt="Lush Meadow" width="380" /> | <img src="../assets/screenshot_sand.png" alt="Sunlit Desert" width="380" /> |
| **🌴 열대 우림 (Tropical Rainforest)** | **🐟 맑은 어항 (Crystal Aquatic)** |
| <img src="../assets/screenshot_rainforest.png" alt="Tropical Rainforest" width="380" /> | <img src="../assets/screenshot_aquatic.png" alt="Crystal Aquatic" width="380" /> |

---

### ✨ 주요 특징

- **4가지 바이옴 (최대 9개 수조 동시 관리)**: 무료 **이끼원 수조**로 시작해 **사막**, **열대 우림**, **어항**을 해금하고 다중 수조 간 **생태 공명**을 경험해 보세요.
- **52종 도감 수집**:
  - **식물 21종**: 이끼, 고사리, 야광 버섯, 다육식물, 난초, 마리모, 수련 등.
  - **입양 가능한 생물 25종**: 청개구리, 달팽이, 무당벌레, 레오파드 게코, 카멜레온, 네온 테트라, 크리스탈 새우 등 (먹이사슬 안전 보관 및 커스텀 닉네임 지원).
  - **공중 방문객 6종**: 반딧불이, 달나방, 잠자리 등 서식지 조건이 맞으면 자연스럽게 찾아오는 희귀 종.
- **세심한 돌봄과 교감**: 분무/산소 공급, 먹이 주기, 온도 조절 장비(히트 램프, 쿨링 팬, 수조 히터), 20종의 자유 배치 소품 및 5종의 프레임 스킨, 쓰다듬기로 **Lv.5 절친 호감도** 달성.
- **메뉴 막대 네이티브 경험**: 상태에 따라 변하는 6가지 동적 아이콘, 일출/일몰 조명 효과, 최대 8시간 오프라인 시뮬레이션, 수면 모드(유리 뚜껑 닫기), **4x 무손실 픽셀 스냅샷** PNG 내보내기.
- **8개 언어 기본 지원**: 한국어, English, 简体中文, 繁體中文, 日本語, Español, Deutsch, Français.

### 💻 설치 방법 (macOS 13.0+)

1. [GitHub Releases](https://github.com/jampsn/TerrariumMenuBar/releases) 또는 [itch.io](https://jamplus.itch.io/pixel-terrarium)에서 최신 `.dmg` 파일을 다운로드합니다.
2. `TerrariumMenuBar.app`을 `응용 프로그램` 폴더로 드래그합니다.
3. **최초 실행 안내 (미서명 앱)**: 아직 Apple 개발자 공증을 받지 않은 오픈소스 앱이므로 macOS Gatekeeper 경고가 표시될 수 있습니다.
   - **방법 A**: `TerrariumMenuBar.app` 우클릭 → **열기** → 대화상자에서 **열기** 클릭.
   - **방법 B**: 터미널에서 실행:
     ```bash
     xattr -cr /Applications/TerrariumMenuBar.app
     ```

### 🛠️ 소스 빌드

**macOS 13.0+** 및 **Swift 5.9+** 환경이 필요합니다:

```bash
./build_app.sh
```

### 🛠️ 개발 및 AI 활용 고지 (Transparency)

본 프로젝트는 **jam**이 직접 설계, 아키텍처 구성 및 밸런싱을 주도하여 개발했습니다. 개발 과정에서 코드 작성 및 일부 비주얼/커버 이미지 탐색에 AI 도구를 보조 수단으로 활용했으며, 모든 게임 시스템과 픽셀 애니메이션은 수작업으로 검수·조정·테스트되었습니다.

### ❤️ 프로젝트 후원하기

Pixel Terrarium은 **100% 무료 오픈소스**입니다. 이 작은 유리 세계가 여러분의 일상에 소소한 휴식이 되었다면 후원으로 응원해 주세요 (후원금은 macOS 보안 경고를 없애기 위한 Apple 개발자 인증서 비용에 우선 사용됩니다):

- 🎮 **itch.io (Pay What You Want)**: [https://jamplus.itch.io/pixel-terrarium](https://jamplus.itch.io/pixel-terrarium)

### 📄 라이선스

- **소스 코드 (`Sources/**/*.swift`, scripts)**: [MIT License](../../LICENSE)
- **아트 및 그래픽 에셋 (`Sources/TerrariumMenuBar/Resources/Pixel/`, `AppIcon.icns`, 커버 이미지)**: **CC BY-NC-SA 4.0** (비상업적 용도). 자세한 내용은 [LICENSE](../../LICENSE)를 참고하세요.
