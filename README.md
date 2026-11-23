# 🌿 Pixel Terrarium

> A cozy pixel-art terrarium living quietly in your macOS menu bar.  
> 一款安静栖息在 macOS 菜单栏里的治愈系像素生态缸桌面伙伴。

[English](#english) | [简体中文](#简体中文)

---

## English

**Pixel Terrarium** is a cozy, open-source desktop companion and idle terrarium simulator built natively with Swift & SwiftUI for macOS. Click the dynamic pixel icon in your menu bar anytime to mist moss, feed tiny critters, or watch a miniature ecosystem thrive quietly beside your work or study.

### ✨ Key Features

- **4 Distinct Biomes (Up to 9 Tanks)**: Start with a free **Lush Meadow** tank and unlock **Sunlit Desert**, **Tropical Rainforest**, and **Crystal Aquatic** tanks, with cross-tank **Eco-Resonance**.
- **52 Collectible Species**:
  - **21 Plants**: Moss, ferns, glowing mushrooms, succulents, orchids, marimo moss balls, lotus, and more.
  - **25 Adoptable Critters**: Tree frogs, dew snails, ladybugs, leopard geckos, chameleons, neon tetras, crystal shrimp, and more — with food-chain-safe storage and custom nicknames.
  - **6 Aerial Visitors**: Fireflies, moon moths, dragonflies, orchid bees, and other rare visitors that appear naturally when habitat conditions align.
- **Tactile Daily Care & Bonding**: Mist or oxygenate the water, feed critters, toggle thermal equipment (heat lamp, cooling fan, aquarium heater), decorate with 20 movable props & 5 frame skins, and pet critters up to **Lv.5 Best-Friend Affinity**.
- **Menu Bar Native Experience**: 6-state dynamic menu bar icon (Normal, Night, Rain/Event, Dry, Hungry, Sleep), sunrise/sunset lighting, up to 8 hours of offline simulation, one-click Sleep Mode, and **4x lossless pixel snapshot** PNG exports.
- **8 Languages Built-In**: English, 简体中文, 繁體中文, 日本語, 한국어, Español, Deutsch, and Français.

### 💻 Installation (macOS 13.0+)

1. Download the latest `.dmg` from [Releases](https://github.com/jampsn/TerrariumMenuBar/releases) or [itch.io](https://jamplus.itch.io/pixel-terrarium).
2. Drag `TerrariumMenuBar.app` into `/Applications`.
3. **First Launch Note (Unsigned App)**: Since this is an indie open-source app without a paid Apple Developer ID yet, macOS Gatekeeper may warn that the developer cannot be verified.
   - **Option A**: Right-click `TerrariumMenuBar.app` → **Open** → confirm **Open**.
   - **Option B**: Run in Terminal:
     ```bash
     xattr -cr /Applications/TerrariumMenuBar.app
     ```

### 🛠️ Build from Source

Requires **macOS 13.0+** and **Swift 5.9+** (Xcode or Command Line Tools).

```bash
# Build & package TerrariumMenuBar.app into /tmp/terrarium-build
./build_app.sh

# Or build directly with Swift Package Manager
swift build -c release
```

### 🛠️ Development & AI Disclosure

Independently designed, engineered, and balanced by **jam**.  
During development, AI tools were used as a productivity assistant for code scaffolding and visual/cover art exploration. All gameplay systems, pixel animations, and Mac interactions were manually curated, refined, and tested.

### ❤️ Support the Project

Pixel Terrarium is **100% free and open source**. If this tiny world brings calm to your desk, you can support future updates (and help cover the Apple Developer Certificate cost to remove the macOS security warning):

- 🎮 **itch.io (Pay What You Want)**: [https://jamplus.itch.io/pixel-terrarium](https://jamplus.itch.io/pixel-terrarium)

---

## 简体中文

**Pixel Terrarium（像素生态箱）** 是一款使用原生 Swift / SwiftUI 打造的 macOS 菜单栏治愈系像素生态缸。工作或学习间隙，轻点菜单栏的动态像素小图标，即可展开微缩世界：喷水加湿、调节温控、投喂小生物、布置造景，静看草木与小生灵随时间悄然生长。

### ✨ 核心特色

- **四大生态缸体（最多同时养护 9 口缸）**：从免费初始的 **温润苔原缸** 起步，逐步解锁 **暖阳沙地缸**、**热带雨林缸** 与 **碧波鱼缸**，多缸并存时可触发「跨缸生态共鸣」。
- **52 种像素物种图鉴**：
  - **21 种植物**：绒球苔藓、微光菇、仙人球、龟背竹、莫斯藻球、迷你睡莲等，满足条件即触发首株必出萌发。
  - **25 种可领养动物**：绿豆树蛙、露珠蜗牛、七星瓢虫、豹纹守宫、七彩变色龙、红绿灯鱼、水晶红虾等，支持食物链安全存仓与自定义昵称。
  - **6 种空中奇遇访客**：微光萤火虫、月光小飞蛾、碧蓝蜻蜓等稀有访客，在温湿度与造景契合时自然现身。
- **细腻照料与羁绊互动**：支持喷水/打氧、投喂、夹缸温控设备（加热灯/降温扇/水底加热棒）、20 件自由摆件与 5 款缸框皮肤；轻抚动物提升好感度至 Lv.5 挚友，解锁专属暖心微叙事。
- **菜单栏专属体验**：6 态动态菜单栏图标、晨昏光影渐变、最高 8 小时离线模拟结算、一键盖上玻璃盖进入休眠，以及 **4x 无损像素快照** 导出。
- **原生 8 语种支持**：简体中文、繁體中文、English、日本語、한국어、Español、Deutsch、Français。

### 💻 安装与首次打开说明（macOS 13.0+）

1. 前往 [GitHub Releases](https://github.com/jampsn/TerrariumMenuBar/releases) 或 [itch.io](https://jamplus.itch.io/pixel-terrarium) 下载最新 `.dmg` 安装包。
2. 将 `TerrariumMenuBar.app` 拖入「应用程序」文件夹。
3. **首次打开提示“无法验证开发者”**：目前为个人独立免费开源分发，尚未购买 Apple 开发者公证证书：
   - **方法一**：右键点击 `TerrariumMenuBar.app` → 选择「打开」→ 弹窗中再次点击「打开」。
   - **方法二**：在终端执行：
     ```bash
     xattr -cr /Applications/TerrariumMenuBar.app
     ```

### 🛠️ 源码构建

需要 **macOS 13.0+** 及 **Swift 5.9+**：

```bash
./build_app.sh
```

### 🛠️ 开发说明（Transparency）

本项目由 **jam** 主导设计、架构与测试调校；开发过程中借助 AI 工具辅助进行了代码编写与部分视觉/封面素材探索，并经人工逐项修整与验证。

### ❤️ 支持作者

如果这方小小的像素玻璃缸陪伴了你的工作与摸鱼时光，欢迎请缸里的小生物吃顿大餐（赞助目标将优先用于申请 Apple 开发者证书以消除系统弹窗）：

- 🎮 **itch.io**：[https://jamplus.itch.io/pixel-terrarium](https://jamplus.itch.io/pixel-terrarium)

<details>
<summary>📱 微信赞赏码（点击展开 / WeChat Appreciation）</summary>

> 可在此处放入你的微信赞赏码图片（建议放在 `docs/assets/` 后通过相对路径引用）。

</details>

---

## 📄 License

- **Source Code (`Sources/**/*.swift`, scripts)**: Licensed under the [MIT License](LICENSE).
- **Art Assets (`Sources/TerrariumMenuBar/Resources/Pixel/`, `AppIcon.icns`, cover images)**: Licensed under **CC BY-NC-SA 4.0** (Non-Commercial). See [LICENSE](LICENSE) for full details.
