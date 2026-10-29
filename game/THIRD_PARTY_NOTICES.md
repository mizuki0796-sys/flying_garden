# 资源说明

## `assets/ui/lucide/`（2026-10-28）

- 来自 [lucide-icons/lucide](https://github.com/lucide-icons/lucide)：`icons/layout-grid.svg`、`icons/pickaxe.svg`、`icons/save.svg`。分别用于岛屿布局、采集与存档。
- 许可：ISC，Copyright (c) 2026 Lucide Icons and Contributors；上游完整 LICENSE 随素材保存（含其 Feather 衍生图标说明）。
- 修改：仅将 `currentColor` 描边替换为项目棕色 `#624635`。
- 上游文件 Git blob SHA：layout-grid `f8eca3a721201b652dbbc3b76c15e92fd271c9f9`；pickaxe `86678fbd5b0766c4ba34af948b8ef3e8ebd8b888`；save `07af0708302018606f9619adb2d4d6ec2175db57`；LICENSE `718bb3f0e44153809972abed31839375804bf652`。

## `assets/ui/farm_ui_icons.png`

- 用途：原型中的金币、能源、抓钩、种子、作物与天气图标。
- 来源：由 OpenAI 内置图像生成工具为本项目生成的原创占位素材。
- 生成日期：2026-10-21。
- 生成提示摘要：八枚原创舒适农场主题的 16-bit 像素图标，透明背景，4×2 排列，不含文字、商标和水印。

本项目没有复制《Micro Macro Farm》的游戏截图、UI 图块或其他受版权保护素材。该游戏只用于研究界面层级与交互节奏。

## `assets/pixel_v2/`

- 用途：运行时地形、树木、小人、水稻、番茄、引擎室、储能室与抓钩工坊。
- 来源：由 OpenAI 内置图像生成工具根据本项目已确认的 2D 马赛克视觉规范生成，并由项目代码裁切、缩放和组合。
- 接入日期：2026-10-23。
- 许可记录：项目内部原创生成素材；详细生成规范和素材索引见仓库根目录 `asset-library/`。

### 农务小屋图片（2026-10-26）

- 文件：`facilities/farm_management_hut_rice_v1.png`、`facilities/farm_management_hut_tomato_v1.png`。
- 来源：OpenAI 内置 ImageGen 生成，经用户确认后接入。水稻小屋采用金色屋顶、深绿墙体、谷物标识；番茄小屋沿用同一轮廓与比例，改为红屋顶、番茄标识与收获筐。
- 提示规范：纯 2D 正交、粗颗粒马赛克像素、有限色板、单体透明背景；以用户已确认的设施风格为参考。
- 原图以独立文件保存，不覆盖此前已确认的建筑素材。

### 动力室飞轮动画（2026-10-27）

- 文件：`facilities/engine_room_layers_v1/body.png`、`flywheel.png`。
- 来源：OpenAI 内置 ImageGen 基于原动力室 PNG 拆分、补绘；提示词随素材保存在 `prompts.json`。
- 使用方式：仅独立飞轮参与旋转；补绘 `body.png` 已停用。固定连接件和可见墙面保留原图，旧轮轮廓通过原图暗部取样修复；烟雾仍使用原有绘制代码。
- 制作与导出规范：项目根目录 `COMPLEX_UI_ANIMATION_GUIDE.md`。

