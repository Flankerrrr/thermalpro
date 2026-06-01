# 版本变更记录 (Changelog)

## v8.82 (Latest)
- **FEATURE**: 新增 `onAutoSequence` — 一键全帧自动边界检测。替代手动逐帧锚点选择，扫描全部帧并通过梯度分析检测熔池边界，线性插值填补无熔池帧，滑动中值去噪，定间隔存储锚点。含取消支持、进度条和捕获后审核图表。
- **FEATURE**: 新增 `showAnchorReview` 审核图表，展示原始边界温度散点、平滑曲线、refTemp 参考线和锚点位置。
- **ENHANCEMENT**: `detectMeltPoolBoundaryTemp` 新增可选 `minRadials` 参数（默认 3，全序列用 15）。
- **FIX**: `onAutoSequence` 在边界检测前自动应用 De-Haze 和去噪预处理，确保跨帧边界温度一致性。

## v8.81
- **PHYSICS FIX**: 将 `onAutoCatch` 的全局最大值锚定替换为梯度熔池边界检测（`detectMeltPoolBoundaryTemp`）。固-液界面是热力学强制等温面，提供独立于束流功率和发射率的物理标定锚点。
- **PHYSICS FIX**: 将 `maskWeights` 归一化参数从 `dispLow`/`localMax`（显示参数/帧统计量）替换为 `physFloor`/`physCeil`（背景温度/材料熔点），使 maskWeights 跨帧一致且与显示设置解耦。
- **PHYSICS FIX**: 将默认 `T_htw` 从 600°C 改为 980°C，对齐 TC4 β 转变温度。

## v8.80
- **BUG FIX**: 修复 `onAutoCatch` 从屏幕渲染图像 (`hImg.CData`) 读取坐标导致稳像后位置偏移的问题。改为使用 `getProcessedFrame` 获取真实校准坐标。
- **BUG FIX**: 为 5 个长计算进度条添加「取消」按钮 (`onCalcArea`, `onCalcMotion`, `calcBackgroundCurve`, `extractTimeProfile`, `onSetLocalAnchor`)，解决关闭进度条后界面假死问题。

## v8.79
- 修复参考温度同步、稳像回退、动态锚点排序及 NDT 剖面边界问题
- 扩展项目保存/加载以持久化 NDT、热循环、锚点、ROI 及绘图状态
- 添加数值校验、FPS 同步、更安全的加热曲线解析、分块 MAT 导出
- 为主题/布局偏好添加配置令牌（为后续 UI 现代化做准备）

## v8.78
- 升级形态学引擎，提取 BoundingBox 尺寸 (Size H / Size L)
- 将单轴面积图替换为 3 标签页 UI 组（Area, Size H, Size L）
- 在所有面积子图中扩展进度线逻辑
- 严格隔离二次缩放 (Area: mm²) 与线性缩放 (Length: mm)
- 在轮廓追踪视图中渲染熔池与 HAZ 的动态边界几何
