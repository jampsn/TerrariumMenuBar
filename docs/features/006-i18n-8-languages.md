# Feature 006: v1.1.0 — 8 语种完整国际化与窄窗排版适配

> 关联基线：[BASELINE.md](../BASELINE.md) | 路线图：[ROADMAP.md](../ROADMAP.md)

## 1. 目标与范围
面向开源桌面发布，为 `TerrariumMenuBar` 构建覆盖 **8 种语言** 的完整国际化（i18n）体系与自适应切换机制，并对 `472pt`（有效内容 `448pt`）窄菜单栏 Popover 窗口进行全量防溢出适配：
1. **支持语种（8 种）**：
   - `zh-Hans`（简体中文）
   - `zh-Hant`（繁體中文）
   - `en`（English）
   - `ja`（日本語）
   - `ko`（한국어）
   - `es`（Español）
   - `de`（Deutsch）
   - `fr`（Français）
2. **语言切换机制**：
   - 默认跟随 macOS 系统语言（`AppLanguagePreference.system`，经 `Locale.preferredLanguages` 解析匹配，未命中 8 语种时安全回落 `.en`）；
   - 设置浮层提供像素风下拉菜单，支持随时切换为「跟随系统」或 8 种语言之一，**无需重启立即全量生效**，偏好通过 `UserDefaults`（`terrarium.languagePreference`）持久化。
3. **资源化语言包架构**：
   - 全部用户可见文案抽离至 `Sources/TerrariumCore/Resources/Locales/<lang>.json` 扁平 JSON 词典，使用 `{param}` 命名占位符，严禁 `%@`/`%d` 位置格式化风险；
   - `TerrariumCore` 保持纯 `Foundation` 零 UI 依赖，通过 `TerrariumL10n` 统一服务核心引擎与菜单栏 UI。

## 2. 持久化键值与架构红线
- **v1~v5 老存档 100% 向后兼容**：
  - 严禁修改 `TerrariumBiome`、`ThermalMode`、`SceneAtmosphere`、`FoodChainGroup` 的 `rawValue`；
  - 严禁修改 `CritterPersistentState.personality` 存储值及 `TerrariumConfig.defaultPersonality(for:)` / `personalityPerk(for:)` 的中文匹配键；
  - 上述模型统一通过 `.localizedName` / `localizedPersonality(for:)` 做展示层映射。
- **成就佩戴判断纯 ID 化**：使用 `equippedTitleID == ach.id`，禁止通过展示文本比对。
- **气象兜底城市名解耦**：`LocalWeatherReading.city` 在未获取到城市名时保留 `nil`，仅在 UI 展示时本地化回落（`sensor.local_fallback`），防止语言词写入跨语言存档。
- **窄窗口防溢出约束**：顶部标题与 4 Tab、三栏 145pt 传感器卡片、4 核心动作按钮、图鉴/成就两行顶栏及生物卡片均需控制西文长度并设置 `.lineLimit(1)` + `.minimumScaleFactor(...)`，杜绝截断与撑宽窗口。

## 3. 验收标准
- **静态校验**：8 个 JSON 语言包 Key 集合完全一致、占位符集合完全一致、非中日文语言零汉字残留、无遗漏的用户可见硬编码中文。
- **单元测试**：`TerrariumCoreTestRunner` 通过全部 **24 项** 核心单元测试（含第 23 项 8 语种 JSON 全量一致性校验与第 24 项实时切换/系统解析/老存档兼容性测试）。
- **打包与自检**：`build_app.sh`（版本 `1.1.0 (110)`）零警告编译，包含 `TerrariumMenuBar_TerrariumCore.bundle` 与 `CFBundleLocalizations`；`--self-test` 全量通过（含 8 语种加载核验）；更新发行安装包 `release/TerrariumMenuBar-1.1.0.dmg`。
