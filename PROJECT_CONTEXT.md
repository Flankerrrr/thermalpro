# EBWAM 热成像监控分析软件 — 项目上下文

> 最后更新: 2026-05-27 | 当前版本: v8.83

## 项目定位

EBWAM（电子束线材增材制造）过程热成像监控分析工具。用于处理红外热像仪拍摄的逐帧热成像序列，实现熔池/HAZ 面积定量分析、非线性温度标定、动态 Z 深度映射等功能。

**用户**: 材料工程博士，研究方向为 TC4 钛合金 EBWAM 多传感器数据融合下的在线温度监测。**不具备 MATLAB 编程能力**。

## 文件清单

| 文件 | 用途 |
|------|------|
| `CLAUDE.md` | 项目规则文件（角色、规范、推理框架） |
| `src/ThermalAPP_v8_83.m` | **当前主程序**（单体 GUI，~2900 行，70+ 嵌套子函数） |
| `src/ThermalAPP_v8_80.m` | v8.80 存档（初始版本） |
| `docs/changelog.md` | 版本变更记录 |
| `docs/architecture.md` | 代码架构说明 |

## 版本核心改动（v8.80 → v8.83）

### v8.80 → v8.81 — 物理标定修正
- `detectMeltPoolBoundaryTemp`: 全局最大值锚定 → 36 向径向梯度边界检测（固-液界面热力学等温面）
- `maskWeights`: `dispLow`/`localMax` → `physFloor`/`physCeil`（物理常数，移除显示参数耦合）
- `T_htw` 默认值: 600°C → 980°C（对齐 TC4 β 转变温度）

### v8.81 → v8.82 — 全序列自动标定
- `onAutoSequence`: 一键全帧边界检测 + 插值 + 中值去噪 + Review 图表
- `showAnchorReview`: 中/英/俄三语审核图表
- HTW → HAZ 全局重命名

### v8.82 → v8.83 — 自适应面积阈值
- `computeAdaptiveThresholds`: 全帧预扫描生成逐帧边界温度
- **MP T / HAZ T 输入框在自适应模式下完全架空**（灰化）
- `minBoundRatio = 1.00`：`Tm_i = max(boundaryTemp, refTemp × minBoundRatio)`
- `hazRatio = 0.55`：`Th_i = Tm_i × hazRatio`
- 6 重边界检测门控（G0.5, G1, G2, G3, G4, G4b, G5）
- `filterFlashes`: 层间束斑直射过滤（最小连续帧阈值）

## 关键算法：`detectMeltPoolBoundaryTemp`

```
输入: 单帧热图像, refTemp, minRadials
流程:
  G0.5: maxVal >= refTemp × 0.92（预筛）
  G0: maxR >= 10
  36 向径向剖面 → |dT/dr| 峰值 → 边界候选点
  G1: maxVal-minBg >= 50°C（热对比度）
  G2: median(boundaryDist) <= min(W,H)/4（距离中心）
  G3: median(boundaryGrad) >= 15°C/px（梯度陡度）
  G4: median(boundT)/maxVal >= 0.70（边界/峰值比）
  G4b: |medT-refTemp|/refTemp <= 0.20（接近相变温度）
  G5: 有效径向数 >= minRadials
输出: 边界温度 (°C) 或 NaN
```

## 面积分析管线（自适应模式）

```
computeAdaptiveThresholds():
  for i=1:N: boundaryTemps(i)=detectMeltPoolBoundaryTemp(img,refTemp,15)
  filterFlashes: 移除连续帧数 < minMeltDuration 的短事件
  fillmissing(linear) + movmedian(11)
  首/尾无熔池段 → NaN（不回退固定阈值）

updateFrame / onCalcArea / performSingleFrameCalc:
  adaptiveEnabled && boundaryTemps(idx) 有效:
    Tm_i = max(boundaryTemps(idx), refTemp × minBoundRatio)
    Th_i = Tm_i × hazRatio
  adaptiveEnabled && boundaryTemps 为空: 固定阈值预览 (Tm_i=T_melt, Th_i=T_haz)
  adaptiveEnabled && NaN: mp=0, haz=0, 不画叠加
  非自适应: Tm_i = T_melt, Th_i = T_haz（固定值）
```

## 测试数据

| 数据集 | 路径 |
|--------|------|
| 全量原始数据（~2.9GB） | `/Users/flanker/Desktop/ИФПМ文章/data/热成像原始数据/04-12-2025 5hz Ssteel V200 part1+2 fitted/data.mat` |
| 后半段处理数据 | `.../V200 Frmaes 8707-17650 ProcessedData MPt1500 HTWt1330.mat` |
| 变量名 | `D`（全量）/ `ProcessedData`（后半段） |
| 参数 | 5 Hz, 288×382 px, 17650 帧（全量）/ 8944 帧（后半段） |
| 背景 | ~525°C（初始）→ ~928°C（末尾），恒定漂移 |
| refTemp | 1450°C（用户设定） |

## 当前事件

1. ~~`show contour tracking` 功能失效~~ ← **待确认是否已修复**
2. 全量原始数据中 frame 1-8706 未包含在已处理数据中（ProcesedData 仅含 8707-17650）

## 已知设计决策

- **单体架构**: 所有功能在一个 .m 文件中，通过嵌套子函数组织
- **全局状态**: 结构体 `S` 承载所有运行时状态，子函数通过闭包访问
- **无模块隔离**: 不拆分文件，不引入 OOP
- **项目持久化**: `onExportProject` 保存完整 `S.area` 和 `RawData`；`onExportBaked` 保存处理后的 `ProcessedData`
- **matfile 陷阱**: v7.3 HDF5 会挤压尾部单一维度 → 必须直接通过 `matfile` 写 `(h,w,N)` 来创建 3D 数组
