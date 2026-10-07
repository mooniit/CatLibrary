# 纪念品精细重制 · 已接入选稿

2026-10-07 用户确认古典披衣维纳斯，并随后指示“接入”。六款当前选稿已接入原生房间：故宫宫殿、卢浮宫维纳斯雕像、富士山、埃及金字塔、埃菲尔铁塔、自由女神像。此指示只适用于当前六张选稿；不修改 room-standard-v1 或通用素材准入门槛。

原图的严格几何测量仍失败，见各款 registration.json / verification.json；实际比例误差约0.25%～6.98%，部分真实结构边超1°，最大5.28°，部分内边可信样本不足。没有把包络检查、像素镜像或原生运行通过写成真实边线通过。

## 文件与固定注册

- *-coordinate-guide.svg/.png/.json：先生成的数值样板、完整尺寸、固定投影及注册原点。
- *-coordinate-guide-axes.png：X/Y 底座上下结构边。
- *-x-source.png：built-in imagegen 当前选稿；*-actual-prompt.txt 为实际提示词。维纳斯采用已确认的披衣断臂造型。
- *-registration.json / verification.json：真实素材边线原始失败报告，未修改。
- [应用注册清单](../../../assets/images/room/souvenirs-v2/manifest.json)：源文件 SHA256、等比注册、完整绘制矩形、3倍像素密度、授权选稿状态与透明边检查。

共用宽深0.10L，1×1占格，锚点[0,0]；数值几何水平外缘在X/Y=[0.0125,0.1125]L。高度分别0.115、0.21、0.09、0.115、0.22、0.21L。维纳斯代替玻璃金字塔，高度由0.10L改为0.21L，宽深/占格不变；新增009迁移更新目录，不改已有实例、来源、布局或钱包。

打包沿用测量报告的单一 scale 与样板中心平移，保留整张源图及透明边，未做斜切、纵向拉伸、旋转修角、裁切匹配包络或自动找接地点。3倍像素图统一绘制到权威注册矩形。第二朝向逐RGBA像素镜像第一朝向，未独立生成。墙体、画作及窗景不受此流程影响。

## 命令与实际验证

数值样板：node scripts/build-souvenir-v2-guides.mjs；提示词基线：node scripts/souvenir-v2-prompts.mjs。
严格测量：node scripts/register-souvenir-v2.mjs；当前返回失败，合格输出只进 design 下 validated，不覆盖应用资源。
当前指定选稿打包：node scripts/package-souvenir-v2.mjs；重复执行核对源哈希，拒绝更换原图或改写已应用迁移。

[Flutter实际绘制检查](../../../docs/evidence/m6-v2-sprite-tests.txt)覆盖六款资源、四周透明边、1×1占格、世界坐标移动、旧离线目录使用当前注册和绘制后逐像素镜像。PNG两朝向镜像和原生绘制后1080×1073画布镜像均一致。
[Android原生组合](../../../docs/evidence/m6-v2-native-six-x.png)、[第二朝向](../../../docs/evidence/m6-v2-native-six-y.png)、[维纳斯预览](../../../docs/evidence/m6-v2-native-venus-preview.png)，均使用现有RoomScene/Flame房间，未新建房屋或调整房屋相机。
[双人业务复测](../../../docs/evidence/m6-v2-native-integration.txt)通过来源选择、旋转、确认、手动保存、更新提示、对方刷新及收起保留库存。

后续严格美术验收仍须修正真实结构边、比例与接地差异；这次按用户指示接入不构成通用放宽。手机与远程验证另见M6实施记录。
