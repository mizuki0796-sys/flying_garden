# 素材统一使用指南

素材数量多不等于全部混用。`flying_garden` 建议确定一套主视觉，再把其它包作为“零件库”。

## 目标视觉

- 2D 顶视角或轻俯视角；角色和动物偏 Q 版。
- 单格地块以游戏现有 80×64 逻辑尺寸为基准，内部细节可按 16×16 子网格组织；显示时只使用整数倍最近邻过滤。
- 主色以嫩绿、奶油黄、天空蓝、桃粉为主；阴影偏蓝紫，避免纯黑大轮廓。
- UI 参考 Micro Macro Farm：信息密度高但卡片分区清楚，圆角、浅底色、图标优先。

## 已确认的地块视觉基准

2026-10-22 起，地形与地块以 [`floating_grass_tile_pixel_master_v1.png`](../../asset-library/01_islands_sky/flying_garden_tile_style_reference/floating_grass_tile_pixel_master_v1.png) 为最高优先级视觉基准，详细规范见同目录 [`README.md`](../../asset-library/01_islands_sky/flying_garden_tile_style_reference/README.md)。

- 采用接近正俯视的纯 2D 正交投影，不采用等距 3D 透视。
- 使用粗颗粒、大色块的马赛克像素语言；正式地块按约 80×64 逻辑尺寸重绘。
- 顶面面积优先，朝向玩家的一侧只露出浅土层与块状岩层。
- 单材质最多 3 个明度层级，禁止柔光、渐变、模糊、抗锯齿和写实纹理。
- 草皮边缘使用“左上亮、右下暗”的硬边像素提示厚度，不用立体建模表达体积。

本节覆盖本文及其它旧文档中与之冲突的主画风建议。第三方素材包继续作为动作、内容和构图参考，但正式地形必须先匹配此基准。

第一批按该基准生成的衍生方向稿已经入库：[`地形概念组 v1`](../../asset-library/01_islands_sky/flying_garden_pixel_terrains_v1/)、[`作物概念组 v1`](../../asset-library/02_farming_crops/flying_garden_pixel_crops_v1/) 与 [`设施概念组 v1`](../../asset-library/04_buildings_props/flying_garden_pixel_facilities_v1/)。它们用于统一材质、比例、功能轮廓和色彩分区；最高优先级基准仍是上方草地地块原图。概念稿中的半透明预览晕色不属于画风，正式切片必须清除。

## 世界对象比例

接入补充：树木必须使用 `flying_garden_pixel_terrains_v1/tree_tile_concept_v2_large.png` 的原稿像素，不以比例对照图中的重绘树替代。地块顶面连续铺满逻辑格；同材质连片、异材质做硬边像素过渡，草皮包边与土石侧面只用于浮岛外沿，内部接边不留缝。

以约 40 逻辑像素高的 Q 版小人为基准：成熟水稻约 30 像素、成熟番茄约 32 像素、成熟大树约 110 像素。大树约为角色的 2.75 倍高，成熟作物约为角色的 0.75–0.8 倍高。比例图见 [`tree_farmer_crops_scale_reference_v1.png`](../../asset-library/02_farming_crops/flying_garden_pixel_crops_v1/tree_farmer_crops_scale_reference_v1.png)。

## 采用顺序

1. 先按已确认基准绘制空岛轮廓和草地/岩壁边缘。
2. 再定农田格尺寸，所有作物按同一格宽重排。
3. 角色、动物、建筑统一缩放比例和阴影方向。
4. 从食物图标库中只保留一种描边粗细与一种光源方向。
5. 最后补云、粒子、按钮和输入提示。

## 不宜直接混用的组合

- `kenney_ui_pack_cc0` 的高清矢量感与 16×16 像素场景：可以借结构，不建议原样混用。
- `oga_surt_cc0_scraps` 的概念草图与完成度较高的精灵：适合重绘参考，不适合整包导入。
- 不同包的 16×16、18×18、20×20、32×32：先在 Aseprite/LibreSprite 中归一网格，禁止在 Godot 中用任意比例拉伸。

## 导入 Godot 4.7

- PNG 纹理关闭 Filter，避免像素边缘发糊；缩放只使用整数倍最近邻。
- TileSet 先复制经过筛选的图片到 `game/assets/`，不要让 Godot 扫描整个素材库。
- 动画精灵表先确认帧宽/高和方向顺序，再建立 `SpriteFrames`。
- CC-BY 素材同步登记到游戏内 Credits；CC0 也保留来源，方便后续换图和审计。
