# 代码架构说明

## 总体架构

`ThermalAPP_v8_80.m` 采用**单体 GUI 脚本**架构，所有功能通过嵌套子函数实现，共享全局状态结构体 `S`。

## 函数调用关系

```
ThermalPro_v8_80 (主入口, 构建 GUI)
│
├── onLoadFile ───────────────── 数据加载
│   └── syncFPS ─────────────── FPS 同步
│   └── updateFrame ─────────── 帧渲染（核心渲染管线）
│       └── getProcessedFrame ── 图像预处理（去噪 + CLAHE）
│
├── 图像分析模块
│   ├── onCalcMotion ────────── 稳像计算
│   ├── onSetLocalAnchor ────── 动态 ROI 锚点
│   ├── onAutoCatch ─────────── 自动蒸汽峰值捕捉
│   │   └── getProcessedFrame
│   └── onCalcArea ──────────── 面积分析
│       └── performSingleFrameCalc ── 单帧熔池/HAZ 计算
│           └── getMorphDims ── BoundingBox 尺寸提取
│       └── plotAreaCurves ──── 面积曲线绘图
│
├── NDT 模块
│   ├── onSetBaseline ───────── 基准位置设定
│   ├── onGenerateNDTReport ──── NDT 报告生成
│   │   └── getMeltPoolZ ────── 熔池 Z 深度提取
│   └── onPlotParity ────────── 一致性图
│
├── 校准模块
│   ├── onHeatCurveMenu ─────── 加热曲线菜单
│   ├── onLayerManager ──────── 多层管理器
│   └── onCalibrateScale ────── 空间尺度校准
│
├── 数据持久化
│   ├── onExportProject ─────── 项目保存
│   ├── onExportBaked ───────── 烘焙数据导出
│   ├── onExportMP4 ─────────── 视频导出
│   ├── onExportAreaCSV ─────── 面积数据 CSV 导出
│   └── exportToCSV ─────────── ROI 数据 CSV 导出
│
└── UI/交互
    ├── onMouseDown / onMouseUp / onMouseMoveGlobal ── 鼠标交互
    ├── addROI ──────────────── ROI 管理
    └── onPlayToggle ────────── 播放控制
```

## 数据流

```
MAT 文件 (.mat)
    │
    ▼
S.matObj (MatFile 对象)
    │
    ▼
updateFrame(idx)
    │
    ├──► getProcessedFrame(idx) ──► 预处理后图像
    │
    ├──► S.stab.shifts ──► 稳像偏移补偿
    │
    └──► 渲染至 GUI 轴对象
```

## 设计注意事项

1. **全局状态 S**：所有模块共享同一个 `S` 结构体，修改任何字段都会影响全局行为
2. **无模块隔离**：子函数间无显式接口，通过 `S` 隐式通信
3. **GUI 句柄**：`S.hUI` 存储所有 UI 控件句柄，`S.hImg` 存储主图像对象
4. **性能瓶颈**：`getProcessedFrame` 和 `onCalcArea` 是计算最密集的路径
