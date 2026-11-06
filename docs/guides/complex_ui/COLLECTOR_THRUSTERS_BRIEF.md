# 采集飞船推进器替换

- 用户要求：飞船不用螺旋桨，只用推进器。
- 唯一母版：`game/assets/pixel_v2/vehicles/collector_single_tile.png`，1402×1122，SHA-256 `79E65CEE943BBD58147DE7CCB90410E19272DB13433353119EA82EED9A94066F`。
- 范围：仅两侧螺旋桨与转子轴帽更换为深绿/铜色推进器，喷口朝船尾。与船身相接的内侧支架保留。
- 必须保持：船身、铲斗、矿石、货舱、驾驶室、底部装置、港口、其他画面及全部航行/充能/采矿规则。
- 制作：ImageGen 以母版局部编辑，再由原母版合成授权侧区；不使用整张生成图替代船体。旧母版与旧双桨实现保留备查。
- 显示：保留原源框 `(120,140,1162,890)`、中心 `(701,585)` 及 80×64 逻辑画布；最近邻。推进器为静态喷口，不新增火焰、烟雾、灯光、抖动或状态机制。
- 验证：源图授权范围外字节一致、实际游戏停泊/出航/返航截图及视频。保留生成提示词、编辑候选与确定性合成脚本。
- 生成：内置 ImageGen 编辑，候选 `artifacts/game/collector-thrusters/generated-edit.png`，提示词同目录 `prompt.txt`。
- 合成区域：左 `(145,470,180,380)`、右 `(1077,470,180,380)`；包含喷口底部余量，区域外逐字节保留母版。复现：Godot `--headless --path game --script res://art_templates/complex_ui/prepare_collector_thrusters.gd`。
- 最终素材：`game/assets/pixel_v2/vehicles/collector_thrusters.png`，SHA-256 `782113F6E5CD87A0BF61A2EE83EAF7AE3B915478011E24E86F6B7916897D29B0`。共享绘制组件 `collector_thrusters.gd` 替换游戏中的双桨组件，保留原视口采样及缩放，无转子 shader。
- 实测：素材合成断言通过；`harbor_ship_preview.gd` 六张实际截图及返航断言通过。对比旧版近景，3723 个变化像素均在两侧动力区域内，范围外差异为 0。
- 视频：`artifacts/game/collector-thrusters/thrusters-test.mp4`，1152×648，30 FPS，240 帧/8 秒，2 秒出航、3 秒召回、最终回港；H.264/yuv420p 完整解码通过。母帧在同目录 `video-frames/`。
- 未制作喷焰动画、无音轨；未验证导出安装包。
