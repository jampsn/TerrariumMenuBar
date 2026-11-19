# 003 - 工程性能与存档安全加固

> **关联版本**：`v0.2.3`  
> **状态**：已确认立项，开发中

---

## 一、加固清单与验收标准

1. **存档备份、损坏隔离与自动恢复（`TerrariumPersistence.swift`）**
   - `save(_:)` 写入前若主档 `save.json` 存在且有效，自动轮转备份为 `save.json.bak`；
   - `load()` 若主档损坏，将损坏文件隔离重命名为 `save.corrupted.<timestamp>.json`，并自动从 `save.json.bak` 恢复；
   - `TerrariumState.init` 强制校验 `containers` 非空，防止极端存档下标越界崩溃。
2. **菜单栏 Popover 显隐与休眠低功耗停帧（`StageAnimator.swift` / `PixelStageView.swift`）**
   - 监听 `NSWindow.didBecomeKeyNotification` / `NSWindow.didResignKeyNotification` 感知 Popover 显隐，隐藏时自动暂停 15fps 渲染定时器，打开时恢复；
   - 休眠态且无活跃粒子时跳过 `@Published particles` 重复赋值。
3. **自检帧尺寸对齐、版本号统一与冗余高度清理（`TerrariumApp.swift` / `MenuBarPopoverView.swift`）**
   - 修正 `--self-test` 中 6 处旧帧尺寸，与实际渲染尺寸 100% 一致；
   - 统一版本号至 `0.2.3`，清理列表 Tab 内部多余的 `.frame(height: 446)`。
4. **生态区感知的温湿度提示文案（`TerrariumState.swift`）**
   - `tempHint` 与 `humHint` 基于当前 `currentBiome` 的适宜区间动态判定（沙地干燥正常提示“适宜”，鱼缸显示“溶氧充足”）。
5. **气象服务退避重试与 `os.Logger` 诊断日志（`LocalWeatherService.swift` / `TerrariumState.swift`）**
   - 请求失败时 60 秒后允许重试，不再锁定 30 分钟；关键异常接入 `os.Logger`。
6. **开机自启开关（`MenuBarPopoverView.swift`）**
   - 在 `⚙️ 设置` 面板接入 `ServiceManagement.SMAppService.mainApp` 开机自启开关。
