# 方形一体式采集船重设计

- 最新要求：整船重新设计，符合游戏 UI/地块生成风格；像地块一样方正，无突出组件；Ponytail full。
- 本轮允许整船重画，取代上一轮仅换两侧动力的范围限制。旧版 `collector_thrusters.png` 保留，不覆盖。
- 视觉规范：STYLE_GUIDE.md 草地母版优先，近正俯视正交、粗方块像素、单材质最多三个明度、左上光源、木色/深绿/蓝紫阴影。
- 结构：80×64 一体矩形船体，中央开放矿石货舱；收集口、驾驶窗、双推进喷口均内嵌，四边无外伸设备。无螺旋桨。
- 保持：港口与其他画面、航行采矿和停泊玩法、充能消耗、存档结构。无新灯光、烟雾、喷焰、抖动、动画或状态。
- 实现：沿用 collector_thrusters.gd 与实际游戏预览，替换素材和源框；最近邻归一至单格。
- 交付：ImageGen 原始透明稿、提示词、固定裁切参数、实际游戏近景/全景/出航返航预览。验证单格尺寸与不变区。
- 内置 ImageGen 生成母版：`game/assets/pixel_v2/vehicles/collector_box.png`；SHA-256 `20ED4372A1FA97A9322D6BF6AEE6D26E973D6C2B577604FE053437EA55AF136A`。提示词 `artifacts/game/collector-box/prompt.txt`。
- 参数：源框 `(160,134,1082,882)`，最近邻归一为 80×64；中心 `(40,32)`。沿用原 480×384 透明合成视口及 6 倍内部绘制，游戏显示为 80×64。
- 验证：`harbor_ship_preview.gd` 六张实际游戏截图完成；船体单格尺寸断言、四向停泊/搬迁、出航及返航断言通过。新旧近景 45972 个变化像素均在船体 240×192 屏幕范围内，范围外差异为 0。
- 输出：`artifacts/game/collector-box/`；复现 Godot `--path game --script res://tests/harbor_ship_preview.gd --rendering-method gl_compatibility`。
- 环境日志含系统证书库读取失败提示，离线渲染和全部断言完成。未录新视频、未检查导出包；没有新增动画。
