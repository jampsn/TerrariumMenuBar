# 002 - 经济重平衡、管理员时间加速、UI 对齐与造景摆件扩充

> **关联版本**：`v0.2.2`  
> **状态**：已确认立项（方案 A），开发中

---

## 一、核心改造清单与验收标准

1. **食盘/湿度/温度传感器三栏等高对齐**
   - 统一三栏第二行字号为 `9.5pt` 与 `.frame(minHeight: 16)`；外层 `HStack` 使用 `.fixedSize(horizontal: false, vertical: true)`，三张卡片统一 `.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)`。
2. **经济数值重平衡与离线分段衰减**
   - `ecoPointBaseIntervalSeconds`: `360.0 -> 1200.0`（20 分钟/点 = 3 点/小时）；
   - `ecoPointOptimalIntervalSeconds`: `240.0 -> 720.0`（12 分钟/点 = 5 点/小时）；
   - 离线结算分段衰减：单次离线前 4 小时 100% 速率，4~8 小时 50% 速率，超过 8 小时截断；
   - 离线代偿进食补齐 `mealRewardCooldownSeconds`（`10800s`）冷却校验；`flushSave()` 保存前先执行一次增量结算。
3. **管理员模式时间加速**
   - 会话级 `adminTimeScale`（`1x / 10x / 60x / 300x`）与一键快进（`+10m / +1h / +8h`），通过内存虚拟时钟 `adminVirtualNowOffset` 推进而不污染真实 `lastSavedAt`；退出管理员模式自动归零。
4. **修剪二次确认防误操作**
   - 动态区分按钮文案：`移除幼苗 (0点)` vs `修剪 (+1点)`；点击后展开二次确认条明确提示返点数额，确认后才移除植株。
5. **温控硬件购买与开关解耦（方案 A）**
   - 未购买加热灯/棒或散热风扇时，点击 `☀️8` / `❄️8` 弹出二次确认购买并安装到缸壁上（待机态），不自动开机；已购买后点击免费切换开关状态；
   - 压暗 `equip_cooling_fan` 帧 0 待机态扇毂亮度、柔化 `equip_heat_lamp` 帧 1 光晕。
6. **摆件放大精细化重绘 + 每缸新增 2 件摆件（共 8 件）**
   - 12 件既有摆件按 4 阶明暗色板扩大重绘（消除留白，同步更新 `PixelStageView` 的 `frameSize`、`anchor` 与 `Pass 3` 接触阴影）；
   - 新增 8 件精巧占地（`1×1` / `2×1`）造景摆件：
     - 苔原：`meadow_mushroom_log`（菌丝小木墩，`1×1`，8 点）、`meadow_stepping_stones`（溪涧汀步石，`2×1`，7 点，可踩踏）
     - 沙地：`sand_cairn`（沙漠叠石堆，`1×1`，8 点）、`sand_rib_arch`（枯木风蚀拱，`2×1`，11 点，可穿过）
     - 雨林：`rainforest_bromeliad_stump`（积水凤梨朽桩，`1×1`，9 点）、`rainforest_slate_ledge`（苔藓阶梯岩，`2×1`，11 点）
     - 鱼缸：`aquatic_seiryu_stone`（青龙造景石组，`2×1`，10 点）、`aquatic_bamboo_tube`（莫斯竹筒屋，`1×1`，8 点）
