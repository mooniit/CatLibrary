# 月轨侧框、窗台与窗外昼夜 v5

本版已由用户确认定稿。当前手板保持本版呈现，后续正式开发另行处理墙体和窗外图像：两堵墙分别设计，景色按各墙的真实朝向与可见范围独立投影，不能用简单水平镜像造成月相方向、文字或其他景物逻辑错误。家具两方向的镜像方案仍按此前确认保留。本次不修改手板视觉，也不接入生产主页。

当前入口：[lunar.html](lunar.html)。[夜间组合](lunar-assets-v5/scene-night.png) · [日间组合](lunar-assets-v5/scene-day.png) · [侧框与窗台放大图](lunar-assets-v5/joinery-details.png) · [素材及锚点](lunar-assets-v5/manifest.json)。

撤掉 v4 新增的圆角墙角收边，恢复原墙面交接。本轮细化画框与窗框的厚度侧面、加深并装饰窗台，加入符合月轨主题的简洁窗外景色。墙面、地板、地毯、家具素材及摆放保持已认可版本。房屋仍为 `room-standard-v1`；相机、墙高、地板、五个基准点和画布比例不变。

## 构件细节

窗户和画框的主框条采用带起伏肩线的弧面截面，侧面有两道窄金色线脚。左右侧框各有一块圆弧端头的奶油侧饰板，内嵌细金色 S 形卷纹及两端小环。侧饰是实体体积与圆截面细管，不是贴在正面的图案。两面由同一构造派生，部件、月牙和饰件完全一致。

正面保留浅拱框楣、月牙浮雕、圆润星饰角帽、底部星轨和窄深蓝内圈。横版、竖版、正方形共用同一套截面与饰件，外尺寸仍为 `1.6×1.2、1.2×1.6、1.4×1.4 格`，框体总深仍为 `0.026L`。画芯独立装入凹槽，保持原作画幅比例，居中 contain，不裁切。四个挂位中心不变。

窗台有分层圆润截面、细金色环边、台面上的轻弧星轨、前缘月牙与两颗小星，以及两端的弧形卷纹。窗口仍宽 `2.56 格`、高 `1.7 格`，下沿 `3.2 格`，中心 `4.05 格`。

| 窗台参数 | v4 | v5 |
|---|---|---|
| 总宽 | 0.34L / 2.72 格 | 0.352L / 2.816 格 |
| 深度包络 | 0.046L / 0.368 格 | 0.064L / 0.512 格 |
| 主体厚度 | 0.008L / 0.064 格 | 0.008L / 0.064 格 |
| 底部高度 | 3.136 格 | 3.136 格 |

主体台面深 `0.062L`，凸起前缘饰件包含在 `0.064L` 包络内；台面细金属线脚最高凸起约 `0.0006L`。两端各比 v4 延长 `0.006L`。加深平台没有移动窗口或窗台底部，距 3 格高书柜顶仍为 `0.136 格`，家具占格与位置无变化。

实体规则由 [lunar-joinery.mjs](lunar-joinery.mjs) 定义；用固定相机投影后导出透明 SVG/PNG。不添加投射阴影，主要通过真实截面、曲面法线及柔和材质明暗表现体积。

## 简洁月色与昼夜切换

窗外不是完整风景，只是一小片天空：夜间一轮暖白月牙、五个稀疏星点；日间同一轮淡月与浅蓝天空，星点隐藏。没有山林、湖泊、建筑或复杂星云。月牙位于画幅左侧，避开中央窗梃，使小窗中可见的内容有明确焦点。

使用 imagegen 制作独立夜景绘画，再以该图为编辑目标转换为日景，保留月亮的位置、大小、轮廓和画幅。两个源文件为 `view-night-source.png` 与 `view-day-source.png`，均为 1536×1024，原比例 3:2。没有生成房间图。

景色像画芯一样独立于框体，由 [lunar-window-views.mjs](lunar-window-views.mjs) 等比投影至标准窗洞，窗洞裁切负责边界，框体与窗梃置于景色前方。左右墙各有 `view-{left|right}-{day|night}.svg/png`，构图一致，使用同一原画按各墙投影；天空不随框图镜像翻转。窗框自身仍使用同一母版的精确镜像，PNG 镜像像素差为零。

样稿右侧的“窗外昼夜”会同步切换两个窗景。隐藏一扇窗时对应景色一起隐藏。切换不改变画框、画芯、家具、位置或房屋几何。

样稿调用接口为 `window.lunarStudy.setWindowMode('day'|'night')`，URL 可用 `?mode=day` 或 `?mode=night` 指定首屏。正式房间接入时沿用 Flutter 的模式映射：`Brightness.dark → night`，`Brightness.light → day`；项目已存储的 `appearance_theme` 值 `night` 对应夜景、`light` 对应日景。本轮范围是设计样稿，未修改生产主页或主题设置逻辑。独立景色文件与此映射可直接复用。

## 交付与重建

`lunar-assets-v5/` 包含 35 组透明 SVG/PNG：10 个家具方向、6 个墙/地面材质、2 个窗框、3 个正面空框、6 个墙面空框、4 个套画素材、4 个窗景。另有两张独立天空绘画源图、放大细节及组合预览。当前清单与组合中没有墙角收边。历史 v4 文件保留作记录。

家具尺寸、占格和接地锚点沿用 [v2 尺寸表](LUNAR-V2.md#家具尺寸占格与接地锚点)；当前每个素材的 viewBox、像素锚点、世界锚点、墙面挂位和部件列表见 [manifest.json](lunar-assets-v5/manifest.json)。窗台扩大是本轮唯一尺寸调整，已在 `sillChange` 中记录。

```powershell
node design/room-structure-2026-10-05/build-lunar-v2.cjs lunar-assets-v5
node --test design/room-structure-2026-10-05/geometry.test.mjs design/room-structure-2026-10-05/lunar.test.mjs design/room-structure-2026-10-05/lunar-joinery.test.mjs
node design/room-structure-2026-10-05/lunar-v5-browser.test.cjs
node design/room-structure-2026-10-05/export-lunar-v5-details.cjs
python design/room-structure-2026-10-05/audit-lunar-alpha.py lunar-assets-v5
```

验证覆盖 18 项几何检查、32 种家具朝向组合、36 组模板/画芯切换、昼夜控制与调用接口、隐藏窗户联动、手机宽度、透明边缘及精确镜像。已认可的墙面、地板、地毯和家具 SVG/PNG 与 v3 逐字节一致。五个房屋标准文件与固定提交 `cc33751` 的差异为空。

[浏览器验证](lunar-assets-v5/verification.json) · [透明素材验证](lunar-assets-v5/alpha-verification.json) · [网格预览](lunar-assets-v5/scene-grid.png) · [三种实体画框](lunar-assets-v5/frame-templates-sheet.png)。
