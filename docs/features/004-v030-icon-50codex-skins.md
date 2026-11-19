# 004 - v0.3.0 Phase 1：像素应用图标、50 项图鉴扩展与里程碑/缸框皮肤

> **关联版本**：`v0.3.0`  
> **状态**：已确认立项，开发中

---

## 一、核心任务清单

1. **专属像素 `AppIcon.icns`**
   - 32×32 像素风 45° 等距生态箱图标，放大生成全套 `iconset` 并通过 `iconutil` 编译为 `AppIcon.icns`，集成至 `build_app.sh` `Info.plist`。
2. **图鉴扩展至 50 项（33 → 50，+17 项）**
   - 新增 8 种植物（含 `red_shroom` 转正）：`red_shroom`、`sundew`、`lithops`、`agave`、`pitcher_plant`、`calathea`、`vallisneria`、`red_ludwigia`；
   - 新增 7 种动物（严守 T1~T4 体积分级、伪 3D 立体光影与明显物种特征）：`ladybug`（14×11）、`desertMantis`（22×16）、`hornedToad`（28×18）、`blueMorpho`（22×18）、`redEyedFrog`（20×18，19帧树蛙骨架）、`otoCatfish`（16×12）、`crystalShrimp`（14×11）；
   - 新增 2 种空中奇遇物种：`dragonfly`（18×14）、`luna_cicada`（16×14）。
3. **里程碑称号与缸框皮肤（后期点数出口）**
   - 10 / 20 / 33 / 42 / 50 项图鉴里程碑称号；
   - `TankFrameSkin` 4 款可购买皮肤（经典深绿/温润原木/复古黄铜/极简磨砂白/黑曜石金边），存档 `schemaVersion = 5` 无损兼容 `v1~v4`。
