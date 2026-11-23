# TerrariumMenuBar 游戏工程基线 (BASELINE)

> 本文档为 `TerrariumMenuBar`（原生 macOS 菜单栏生态箱游戏）的唯一技术与业务基线（SSOT）。
> 每次修复非显而易见的 Bug、调整核心数值或修改渲染管线后，必须将新发现的暗坑与防呆规约同步沉淀至本文档。

---

## 1. 工程与架构分层

- **工程路径**：`src/TerrariumMenuBar/`（`Package.swift`，Swift 5.9+，最低系统要求 `macOS 13.0+`）
- **模块划分**：
  1. `Sources/TerrariumCore/`：纯逻辑层（**严禁引入 SwiftUI / AppKit 依赖**，保证全量无头单测）
     - `TerrariumConfig.swift`：全局数值配置（生态参数、温湿度区间、五阶好感表、经济与折旧参数、图鉴判定规则）
     - `TerrariumModels.swift`：`Codable` 持久化模型、生态缸容器类型、物种/摆件/设备枚举
     - `TerrariumSimulation.swift`：分段步进仿真引擎（`<=60s` 步进）、离线结算、物种演化与防刷判定
     - `GridPathfinder.swift`：等距网格寻路与障碍/生态位避让
     - `TerrariumPersistence.swift`：原子存档读写（`~/Library/Application Support/TerrariumMenuBar/save.json`）
     - `TerrariumL10n.swift` & `Resources/Locales/`：纯 `Foundation` 8 语种本地化引擎与 JSON 词典包（`zh-Hans` / `zh-Hant` / `en` / `ja` / `ko` / `es` / `de` / `fr`）
  2. `Sources/TerrariumMenuBar/`：表现与交互层
     - `TerrariumApp.swift`：应用入口、菜单栏图标与 `--self-test` 全量无头自检
     - `TerrariumState.swift`：主线程状态管理、30 秒后台 Tick 调度、`applicationWillTerminate` 强存
     - `MenuBarPopoverView.swift`：菜单栏 Popover UI、多缸按键切换、图鉴/商店/Admin 面板
     - `PixelStageView.swift`：Canvas 多 Pass 像素舞台渲染引擎
     - `StageAnimator.swift`：精灵动画状态机、VFX 粒子预算与轻抚/气泡/露水帧驱动
     - `LocalWeatherService.swift`：本地实时气温联动服务
     - `PixelAssetLoader.swift` & `Resources/Pixel/`：像素精灵表与静态图资产加载
  3. `Sources/TerrariumCoreTestRunner/`：无头单元测试运行器（`main.swift`，当前 24 项核心测试）
  4. `build_app.sh`：原生 `.app` 编译、资源拷贝（含 `AppIcon.icns`）与签名打包脚本（默认输出 `/tmp/terrarium-build/TerrariumMenuBar.app`）

---

## 2. 像素舞台渲染管线规范（PixelStageView）

- **逻辑画布**：`224 × 176` 逻辑像素 `45°` 等距箱庭，2x 整数放大至 `448 × 352 pt`（禁用模糊插值）。
- **渲染 Pass 顺序（严禁破坏先后遮挡关系）**：
  1. **Pass 0**：缸外环境氛围（日/夜/雨/暖光房间背景）
  2. **Pass 1 & Pass 1b**：后壁玻璃框体（Pass 1）+ **后壁内贴挂温控硬件层**（Pass 1b：加热灯、水下加热棒、散热风扇本体均在此绘制，绝不遮挡前景生物）
  3. **Pass 2**：2:1 等距地面与三层土/水底剖面
  4. **Pass 2.5**：贴地水洼与卵石滩图层（避免地面生物视觉沉入底层）
  5. **Pass 3**：统一 2:1 等距接触阴影
  6. **Pass 4**：严格 **Y-Sort** 前后遮挡层（造景摆件、陆生固定食盆、动态植物/睡莲水下细茎、地面/水中生物）
  7. **Pass 5**：空中专属生物（萤火虫、月光飞蛾）与气泡/露水 VFX 粒子
  8. **Pass 6 & Pass 6b**：透明水体叠加层（`tank_water_overlay`）+ **水面浮点层**（`gz = 38.0`：后壁浮游喂食圈、浮水睡莲叶、气泡触面破灭微环）+ 前玻璃框
  9. **Pass 7b**：前玻璃外层柔和光锥/风锥氛围叠加（仅氛围光效，不含实体硬件）

---

## 3. 存档兼容与升级规范

- **当前存档版本**：`schemaVersion = 5`（支持多生态缸实例自由购置、跨缸共享生态点、50 项图鉴与收集称号、五阶好感数据、全缸通用缸体边框皮肤）。
- **向后兼容硬约束**：
  - `TerrariumModels.swift` 必须保持对 `v1 ~ v4` 旧版存档的无损解码与自动迁移至 `v5`；
  - 新增 `Codable` 字段必须使用 `decodeIfPresent` 并提供安全默认值，严禁因缺失字段导致老玩家存档崩溃或重置。

---

## 4. 经济平衡与核心防刷基线

1. **五阶轻抚羁绊（0 点击直发点数）**：
   - 好感范围 `0~100`，划分 `Lv.1 初识(0~9) -> Lv.2 熟稔(10~29) -> Lv.3 亲近(30~59) -> Lv.4 信赖(60~99) -> Lv.5 挚友(100)`；
   - 点击轻抚 **0 直发点数**；单只 `20 分钟` 冷却、每日上限 `6 次`、连点受惊 `60 秒` 缓神期；通过 Lv.2~Lv.5 被动性格特技（降低饥饿或全缸产点共振提速，共振上限 `+25%`）反哺收益。
2. **产点与消耗防呆**：
   - 在线与离线均统一采用 `<=60s` 分段步进，离线结算上限 `8 小时`；
   - **禁止 `.stored` 生物仓生物偷吃食物**；在线进食需饥饿 `>=55%` 且进食冷却 `>=3 小时` 才触发奖励点数；
   - 枯萎植物不自动复生且不计入产点；鱼缸溶氧 `<60%` 或沙地湿度 `<26%` 停止自然产点；
   - 拆缸按购置价格 **`75%` 折旧退点**（`tankRefundRatio = 0.75`）；所有生物售价严格高于对应图鉴解锁奖励，杜绝倒卖刷点。

---

## 5. 历史暗坑沉淀（Post-Mortem 清单）

| 编号 | 领域 | 暗坑现象与根因 | 防呆规约（必须遵守） |
| :--- | :--- | :--- | :--- |
| **PM-01** | 后台调度 | 固定按 `+30s` 推进仿真会导致 Mac 合盖休眠/App Nap 唤醒后丢失大量离线挂机时长。 | 必须基于真实时间戳差值 `now - lastSavedAt` 计算 `elapsed` 推进仿真。 |
| **PM-02** | 演化一致性 | `PixelStageView` 与 `TerrariumSimulation` 若各自写物种条件阈值，会出现“画面已长出但图鉴未解锁”或反之的脱节。 | 所有物种/图鉴判定条件统一收敛至 `TerrariumConfig` 静态方法，UI 与 Core 共用同一判据。 |
| **PM-03** | 遮挡与净空 | 陆生食盆或加热器材若在前景/Pass 7 绘制实体，会与前景游动的鱼或爬虫产生严重穿插遮挡。 | 温控硬件本体统一绘于 **Pass 1b 后壁内层**；水缸喂食圈置于 **Pass 6b 后壁水面**；陆生食盆保留前方净空区。 |
| **PM-04** | 内存与定时器 | `StageAnimator` 粒子分裂若无预算上限或缺少 `deinit` 清理 `Timer`，长期挂机将引发内存/CPU 爬升。 | 粒子严格受预算上限裁剪；`StageAnimator` / `TerrariumState` 必须在 `deinit` 销毁 `Timer` 与 Combine 订阅。 |
| **PM-05** | 休眠交互 | 休眠冻结模式下若允许切氛围或点击触发演化，会被用于白嫖解锁。 | 休眠状态严格冻结状态流转与演化产出。 |
| **PM-06** | 资源校验 | 新增或重命名 PNG 资产时若未同步校验，打包运行会静默缺图。 | 任何 PNG 变更后必须通过 `--self-test` 全量资产存在性校验（确保 exit code 0）。 |
| **PM-07** | 温控交互 | `toggleThermalMode` 在开关切入时若附带瞬时 `±2°C` 硬改，会导致玩家连点 2 次（关→开）无冷却刷温，绕过 180s/1°C 热传导节奏。 | 温控开关仅更新 `thermalMode` 与重置 `ambientRelaxSeconds = 0`，严禁在点击回调中直接增减 `temperature`。 |
| **PM-08** | 45° 渲染 | 在 45° 等距箱庭中使用直角 `CGRect` 遮罩（如鱼缸绿藻）或平视双层背景会严重割裂立体透视；睡莲成熟期长茎根爪亦会破坏水体通透感。 | 水体染色必须沿 `isoToScreen` 六边形轮廓绘制并辅以贴壁像素藻斑；睡莲仅在 `.sprout` 幼苗期绘制半透明细芽茎。 |
| **PM-09** | 粒子隔离 | 切换生态缸时 `StageAnimator.particles` 若未清空，鱼缸上浮气泡会残留在陆地缸舞台中。 | `syncCrittersFromState` 检测到 `containerChanged` 时必须立即清空 `particles`，且 `.bubble` 仅在 `.aquatic` 保留。 |
| **PM-10** | 幼苗贴地 | 植物幼苗帧（`sprout`）若在精灵表中留白偏上（`bottom_y < anchor_y`），小株会与接触阴影分离产生飘浮感。 | 幼苗帧底部像素必须精确对齐物种的 `anchor_y`（与 Pass 3 接触阴影严丝合缝贴合）。 |
| **PM-11** | 经济与离线 | 基础产点过快且离线代偿进食缺少 `3h` 冷却校验时，挂机一晚极易溢出单缸毕业点数；`flushSave` 未先结算也会丢失尾段进度。 | 离线结算执行前 4h 全速 / 4~8h 半衰，离线进食对齐 `mealRewardCooldownSeconds`；`flushSave` 须先推进一次后台 Tick。 |
| **PM-12** | 边缘防穿壁 | 摆件底边若画成平底或宽弧且超过锚点下沿，置于缸前边缘时会垂出底砂斜边露在侧剖面上；Pass 3 阴影亦会穿透缸壁。 | 所有摆件底边必须收为 2:1 等距 V 形斜边；Pass 3 地面接触阴影必须裁剪于 11×11 缸底菱形内部。 |
| **PM-13** | 存档与能耗 | 主档单文件解码失败会静默覆写丢档；`MenuBarExtra(.window)` 收起后不触发 `onDisappear`，导致 15fps `Timer` 后台空转。 | 写盘前轮转 `.bak` 备份、坏档隔离恢复；监听 `NSWindow.didResignKey/didBecomeKey` 暂停/恢复 15fps 渲染。 |
| **PM-14** | 菜单栏窗体 | macOS `MenuBarExtra(.window)` 切换矮高度 Tab 或展开管理员面板时，容器未顶边锚定会导致窗口整体下移、上方出现透明留白。 | 根视图须设 `alignment: .top` + `.fixedSize(horizontal: false, vertical: true)`，并配合 `MenuBarWindowTopPinHelper` 锁定 `NSWindow.frame.maxY` 贴紧菜单栏下沿，只向下伸展。 |
| **PM-15** | 精灵锚点 | 同一张植物精灵表内成熟/幼苗/枯萎帧底部实像素 `max_y` 常不一致（如卷叶蕨成熟帧 `22`、幼苗帧 `26`；兰花成熟 `21`、幼苗 `18`），若共用单一 `anchor.y` 会导致成熟株飘浮或下沉错位。 | 新增或修改精灵表后须逐帧检查 Alpha 实像素底沿 `max_y`，在 `PixelStageView` 中按帧态精确绑定 `anchor.y`；开源发布版统一保留 `Bundle.module` 明文 PNG 与符号，不启用符号剥离与 `Assets.car` 封包。 |
| **PM-16** | 多语言与存档 | 枚举 `TerrariumBiome`/`ThermalMode`/`SceneAtmosphere` 与 `CritterPersistentState.personality` 以中文作为 `save.json` 持久化与数值匹配键，直接改 `rawValue` 会导致老存档坏档；SwiftPM 核心库资源在独立 `.app` 中位于 `Contents/Resources/TerrariumMenuBar_TerrariumCore.bundle`。 | 持久化键与性格逻辑匹配键恒定保留中文原值，展示层统一通过 `TerrariumL10n` + JSON 命名占位符映射；`TerrariumL10n` 须优先探测 `Bundle.main` 内资源包再回落 `Bundle.module`，`build_app.sh` 同步拷贝该 bundle 并声明 `CFBundleLocalizations`。 |

---

## 6. 标准化自动化验证命令

每次代码或资产修改完成后，必须依次执行以下三段式验证：

```bash
# 1. 核心逻辑单元测试（要求 0 failed）
swift run --package-path src/TerrariumMenuBar --scratch-path /tmp/terrarium-build TerrariumCoreTestRunner

# 2. 原生应用编译打包（要求 0 Swift 编译警告）
bash src/TerrariumMenuBar/build_app.sh

# 3. 无头全量资产与端到端自检（要求 SELF_TEST_PASS）
/tmp/terrarium-build/TerrariumMenuBar.app/Contents/MacOS/TerrariumMenuBar --self-test
```
