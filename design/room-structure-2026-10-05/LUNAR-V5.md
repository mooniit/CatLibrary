# 月轨 v5 定稿

用户已确认定稿，已接入原生应用。房屋唯一标准为 [room-standard-v1](STANDARD.md)，尺寸、占格和挂位由 [geometry.mjs](geometry.mjs) 定义。[lunar-style-v2.png](../art/reference-model/lunar-style-v2.png) 只用于配色、造型和材质参考，不参与相机或比例计算。

查看 [同一房屋样稿](lunar.html)、[夜间组合](lunar-assets-v5/scene-night.png)、[日间组合](lunar-assets-v5/scene-day.png)、[窗框与窗台细节](lunar-assets-v5/joinery-details.png)。应用的独立墙面投影、窗景取景与手机构建见 [原生接入说明](../../docs/plans/room-redesign-2026-10-05/NATIVE-LUNAR.md)。

## 家具尺寸、占格与锚点

1 格 = L/8，格子从 0 编号。尺寸包含完整外轮廓；格锚点为占格最小 X/Y。世界接地点为声明外轮廓的最小 X/Y，Z=0。家具在矩形占格内居中。

| 家具 | 正面 | X×Y×Z（格） | 占格 | 格锚点 | 世界接地点（格） |
|---|---|---|---|---|---|
| 书柜 | +X | 0.96×2.08×3 | 1×3 | [0,1] | 0.02,1.46,0 |
| 书柜 | +Y | 2.08×0.96×3 | 3×1 | [0,1] | 0.46,1.02,0 |
| 书桌 | +X | 1.36×2.4×1.44 | 2×3 | [4,2] | 4.32,2.30,0 |
| 书桌 | +Y | 2.4×1.36×1.44 | 3×2 | [4,2] | 4.30,2.32,0 |
| 椅子 | +X | 0.92×0.96×1.6 | 1×1 | [5,1] | 5.04,1.02,0 |
| 椅子 | +Y | 0.96×0.92×1.6 | 1×1 | [5,1] | 5.02,1.04,0 |
| 猫爬架 | +X / +Y | 1.36×1.36×2.32 | 2×2 | [0,5] | 0.32,5.32,0 |
| 开放猫窝 | +X / +Y | 1.52×1.52×0.68 | 2×2 | [5,6] | 5.24,6.24,0 |

默认：书柜 +X、书桌 +Y、椅子 +Y、猫爬架 +X、猫窝 +Y。格锚点固定；宽深与矩形占格随朝向交换。地毯固定在中央 6×6 格，四边各留一格，可隐藏，家具可以摆在上方。

家具使用奶油漆面、少量金属包边、深蓝绗缝软垫，保留弧形、月牙和星轨。猫窝低前沿、大开口；猫爬架的开放正面朝室内。结构厚度与柔和材质明暗表现体积，不添加投射阴影。

## 三种画框、窗户和材质

| 画框模板 | 外框尺寸（格） | 外框尺寸（L） |
|---|---|---|
| 横版 | 1.6×1.2 | 0.20×0.15 |
| 竖版 | 1.2×1.6 | 0.15×0.20 |
| 正方形 | 1.4×1.4 | 0.175×0.175 |

框体总深 0.026L。框条有弧面截面、浅拱框楣、月牙浮雕、星饰角帽、窄深蓝内圈；厚度侧面包含圆弧端头饰板、两道细金色线脚和卷纹。三个模板共用截面与饰件。画芯独立放入凹槽，以原画比例 contain 居中，不裁切；猫爪星空为 1424:1104，珍珠猫为 1191:1320。四个挂心保持各墙水平 1.44、6.56 格，高度 4.05 格。

两扇窗口均宽 2.56 格、高 1.7 格，下沿 3.2 格，中心 4.05 格。窗台总宽 2.816 格（0.352L），深度包络 0.512 格（0.064L），主体厚 0.064 格（0.008L），底部 3.136 格，距 3 格高书柜顶 0.136 格。分层圆润台面包含细金边、轻弧星轨、前缘月牙、小星和两端卷纹。窗口与挂位没有移动。

窗框、画框与窗台的实体规则见 [lunar-joinery.mjs](lunar-joinery.mjs)，模板和套画接口见 [lunar-templates.mjs](lunar-templates.mjs)。墙面保持奶油漆面与稀疏月轨纹样，浅色地板的板缝和细嵌线服从标准两轴。墙角没有新增圆角收边。

窗外仅取一小片天空：夜间暖白月牙与稀疏星点，日间浅蓝天空与淡月。天空母版为 `view-night-source.png`、`view-day-source.png`，均 1536×1024。窗框与景色是独立图层；原生应用按两个窗洞分别取景，保留月相方向，不镜像天空。白色简约对应日景，暗色夜晚对应夜景。样稿支持 `?mode=day|night` 与 `window.lunarStudy.setWindowMode('day'|'night')`。

## 当前素材与复用

`lunar-assets-v5/` 是唯一当前设计素材目录，包含 35 组透明 SVG/PNG：10 个家具方向、6 个墙地材质、2 个窗框、3 个正面空框、6 个墙面空框、4 个套画素材、4 个窗景。保留有效原画、提示词、墙地母版和天空母版供后续编辑。废弃版本、另行生成的书柜第二视角与旧生成脚本已删除。

1. 正式家具使用已清理的 `*-x.png` 母版，`*-x-source.png` 仅供美术编辑参考。+Y 是 +X RGBA 像素的精确水平镜像，不重新生成细节；禁止再次缩放或自动裁切定稿。
2. 镜像像素锚点为 `[imageWidth - anchorX, anchorY]`。摆放公式为 `project(worldGroundAnchor) - pixelGroundOrigin`，只对整间房统一等比缩放。
3. 当前 [manifest.json](lunar-assets-v5/manifest.json) 记录尺寸、占格、世界与像素锚点、源图裁切、包络校准和挂位。PNG、SVG 与这些元数据作为一组复用。
4. 画框与画芯分离；调用 `wallArtwork(slot, template, artworkKind, sources)` 套画，挂心保持不变。窗框与窗景同样分离。
5. [export-lunar-runtime.mjs](../../scripts/export-lunar-runtime.mjs) 从当前母版打包应用图层，并将两墙分别按固定几何投影。导出只依赖 v5 和固定标准，不依赖废稿或整屋生成图。

从项目根目录执行：

```powershell
node scripts/export-lunar-runtime.mjs
node --test design/room-structure-2026-10-05/geometry.test.mjs design/room-structure-2026-10-05/lunar.test.mjs design/room-structure-2026-10-05/lunar-joinery.test.mjs
node design/room-structure-2026-10-05/lunar-v5-browser.test.cjs
node design/room-structure-2026-10-05/export-lunar-v5-details.cjs
python design/room-structure-2026-10-05/audit-lunar-alpha.py
```

验证覆盖固定标准、32 种家具朝向组合、36 组模板/画芯切换、昼夜接口、窗户隐藏联动、手机宽度、透明裁切余量、残留像素、镜像和接地锚点。标准文件保持固定提交 `cc33751` 的内容。

[浏览器验证](lunar-assets-v5/verification.json) · [透明素材验证](lunar-assets-v5/alpha-verification.json) · [网格组合](lunar-assets-v5/scene-grid.png) · [三种画框](lunar-assets-v5/frame-templates-sheet.png)。
