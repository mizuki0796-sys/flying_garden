# 方形采集船厚度优化

- 用户要求：现有方形船像纸片，需要增加立体感。
- 母版：`game/assets/pixel_v2/vehicles/collector_box.png`，SHA-256 `20ED4372A1FA97A9322D6BF6AEE6D26E973D6C2B577604FE053437EA55AF136A`。
- 允许：船体表面明暗、船舷厚度、货舱内壁、矿石块面及接触阴影；船体底边在原占地内表现浅侧壁。保持原结构和组件布局，不新增组件。
- 保持：方正四边、80×64 占地、内嵌推进器、四块矿石、木色深绿配色、正交近俯视。港口、其他场景、航行停泊采矿玩法不变。
- 风格：左上光源，单材质三档主要明度，硬边粗像素；无等距透视、柔光、外部投影、烟火、灯光或动画。
- 实现：内置 ImageGen 编辑母版；新图另存，按新稿外沿校准固定源框 `(154,128,1094,896)`，保持最近邻 80×64 采样，避免裁掉船舷。
- 交付：母版、提示词、实际游戏近景及四向停泊/出航/返航验证；逐像素验证船体以外区域不变。
- 新素材：`game/assets/pixel_v2/vehicles/collector_box_depth.png`，SHA-256 `D7DDEB870D671060BC08172DC625F7364E0E613AC7748E0EE92A7A59D487E1E4`。提示词：`artifacts/game/collector-depth/prompt.txt`。
- 验证：实际游戏预览六张截图、80×64 尺寸、四向停泊、出航返航断言通过；与前版近景比较，45972 个变化像素全部位于船体区域，范围外差异为 0。
- 复现：Godot `--path game --script res://tests/harbor_ship_preview.gd --rendering-method gl_compatibility`。输出：`artifacts/game/collector-depth/`。
- 环境：编辑器缓存/设置写入及系统证书库读取报错，素材导入和离线游戏渲染完成；无脚本断言失败。未录新视频，未验证导出包。
