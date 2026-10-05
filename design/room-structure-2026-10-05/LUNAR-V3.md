# 月轨配套装饰 v3

本文件记录 v3 历史样稿，素材清单为 [lunar-assets-v3/manifest.json](lunar-assets-v3/manifest.json)。当前 [lunar.html](lunar.html) 使用 [v5](LUNAR-V5.md)；v3 墙面与地板保留，窗户与画框已换为细化实体模型，窗外增加独立昼夜月色。

本轮重做画框、窗户、墙面和地板。造型与材质对照已确认的书柜母版和 `design/art/reference-model/lunar-style-v2.png`：奶油漆面的柔和纹理、圆润角帽、细金属包边、浮雕月牙与星饰。采用内置 imagegen 制作四个独立的正面/平面母版，然后在原房屋内组合；没有生成整屋图。

## 具体内容

- **画框**：宽奶油框条、软倒角、四个星饰角帽、顶边浮雕月牙、底边星轨与窄深蓝内圈。框体侧面也采用分层圆润倒角，保持真实厚度。
- **窗户**：奶油浅拱窗楣、浮雕月牙与星饰、圆润角帽、一根竖梃和两个大开口。窗台采用圆角与分层收边。矩形窗洞、窗台位置与外包络不变，窗外仍留空。右窗直接镜像左窗的原生像素，未另行生成。
- **墙面**：奶油抹灰纹理，上半部稀疏的浅浮雕星月，下半部留白；踢脚线有柔和截面和细金色收边。图案属于墙面材质，按墙面平面投影，窗洞单独裁切。
- **地板**：浅色木纹板面与细接缝，外围为金色月轨镶嵌边和曲线角饰。中央以木纹为主，原 6×6 地毯覆盖其上。板面材质从严格俯视母版映射到固定地板平面。

## 三种模板与固定标准

| 模板 | 外框宽×高（格） | 宽×高（L） |
|---|---|---|
| 横版 | 1.6×1.2 | 0.20×0.15 |
| 竖版 | 1.2×1.6 | 0.15×0.20 |
| 正方形 | 1.4×1.4 | 0.175×0.175 |

三种画框使用同一张正方形母版，通过九区切片派生，角帽来自同一源图，中央区不绘制。框条宽仍为 0.014L，框深仍为 0.026L。画芯独立放入，保留原作比例并居中 contain，不裁切。

挂位中心仍是每墙 1.44、6.56 格，高度 4.05 格；窗宽 2.56 格、高 1.7 格、下沿 3.2 格、中心 4.05 格。窗台底 3.136 格，距 3 格高书柜顶 0.136 格。窗框倒角包含在原先 0.026L 的深度和外框包络内；窗台圆角包含在原先 0.046L 深、0.008L 厚的包络内。

房屋标准仍是 `room-standard-v1`：8×8 正方形地板、固定墙高、相机、投影、五个基准点与 1080×1073 画布均未改。所有家具的素材、尺寸、占格、接地锚点、位置和两种镜像朝向保持上一版。家具规格详见 [v2 的尺寸表](LUNAR-V2.md#家具尺寸占格与接地锚点)。三种画框规格和上一轮已放大的画位范围也保持不变。

## 独立母版与复用

四张原始绘制稿与处理后的母版保存在项目内：

| 用途 | 原始稿 | 使用稿 |
|---|---|---|
| 画框 | `frame-master-source.png` | `frame-master.png` |
| 窗框 | `window-master-source.png` | `window-master.png` |
| 墙材 | `wall-master-source.png` | `wall-master.png` |
| 地材 | `floor-master-source.png` | `floor-master.png` |

图像生成使用内置 `image_gen.imagegen`，四个完整提示词及参考图角色保存在 [decor-prompts.json](lunar-assets-v3/decor-prompts.json)。参考只决定画风，正面画框、窗框和严格俯视地材不携带房屋角度。

透明稿先清理低透明度光晕和断开的残留像素，再校准到正面材质平面。画框切片边界由透明开口测得，保存在 `manifest.decorSkins.frame.insets`；窗框只保留一个母版。左右窗的像素锚点随整件水平镜像转换。

`configureDecorSkins` 载入母版；`frameLayout` 和 `wallArtwork` 沿用固定挂心套画；`materialSvg` 把材质面映射到标准墙面/地板。三维框体与窗台轮廓由固定坐标下的圆角和倒角截面绘制。独立 PNG 和 SVG 仍可直接复用，正式素材以清单为准，共 31 组。

世界接地锚点和像素裁切锚点仍按原公式组合：

```text
spriteTopLeft = project(worldGroundAnchor) - pixelGroundOrigin
```

## 重建与验证

```powershell
node design/room-structure-2026-10-05/build-lunar-v2.cjs lunar-assets-v3
# 复用 4181 服务，或启动 python design/room-structure-2026-10-05/serve.py
node design/room-structure-2026-10-05/lunar-v3-browser.test.cjs
python design/room-structure-2026-10-05/audit-lunar-alpha.py lunar-assets-v3
```

重建脚本读取已保存的四张母版，没有图像生成调用。检查覆盖固定标准、32 种家具朝向组合、三种模板在四个画位上套入两幅作品或留空、左右窗和五组家具的像素镜像、透明边缘、画框透明中心和家具投影包络，以及 360/390px 显示。

- [固定房屋组合](lunar-assets-v3/scene-clean.png)
- [三种空画框](lunar-assets-v3/frame-templates-sheet.png)
- [网格与占格](lunar-assets-v3/scene-grid.png)
- [全部家具镜像朝向](lunar-assets-v3/scene-alternate.png)
- [验证结果](lunar-assets-v3/verification.json)、[透明素材检查](lunar-assets-v3/alpha-verification.json)

本轮未修改 `geometry.mjs`、房屋标准文件、商店或生产主页。此前工作区内容和旧版素材均保留。
