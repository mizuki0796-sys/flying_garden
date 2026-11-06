# 已完成实例：动力室仅飞轮旋转

此文保留前版参数。用户随后标出了完整连接杆并要求干净动画，当前实现与验收见 [ENGINE_ROOM_CLEAN_BRIEF.md](ENGINE_ROOM_CLEAN_BRIEF.md)。

用户最终要求：动力室其他任何东西不变，冒烟动画不变，仅设计飞轮旋转。

母版：`game/assets/pixel_v2/facilities/engine_room_v2.png`，SHA-256 `7c9d2499ee2e6796260c1bd5177f71bc952474186e7abd2fc897e9fc5cd99903`。

- 原图画布：1536×1024；原有运行时源矩形：(295, 91, 958, 845)。
- 游戏宽度：92 逻辑像素；原有高度由源图比例计算。
- 原飞轮清理范围：中心 (1024, 660)、半径 (188, 211) 的椭圆内，仅清理铜色旧轮像素，保留已有背景。
- 新飞轮轴心：(1025, 684)，与原轴帽对齐；投影半径：(176, 194)。
- 飞轮源矩形：(795, 406, 460, 500)，使用独立飞轮图。
- 动画：角度 = animation_time × 2.8；局部纹理坐标旋转，固定椭圆裁切。
- 背景衔接：停用补绘的整块墙面，不再使用圆形背景覆盖；仅为旧铜色轮廓取样邻近原图暗部。
- 固定连接件保护区：(817,648,145,110)、(962,666,37,38)、(999,648,55,76)。从旋转多边形中扣除，原图连接件直接保留，不随轮转动。
- 烟雾：原 `_draw_chimney_smoke` 与原有调用参数完整复用。
- 不增加：连杆、活塞、指示灯、像素烟、新的待机/制动逻辑。
- 当前没有新生成整座建筑；仅复用之前 ImageGen 拆分的飞轮，修复通过渲染代码完成。

实现：`game/scripts/engine_room_animation.gd` 与 `main.gd` 的 `_draw_building`。

采样：`game/tests/engine_wheel_preview.gd`，80 帧、20 FPS、4 秒、3 倍显示。原效果与新效果以同时间采样，检查飞轮外像素及烟雾一致。

验证：`verify_wheel_scope.py`，同时检查区域外、烟雾、固定连接件和三个周边墙面取样区。结果写入 `artifacts/game/engine-wheel-only/verification.json`。墙面取样检查不能代替对整幅画面的视觉检查。

编码：`export_preview.py`。生成 GIF 与 MP4；4 秒是预览片段，不承诺飞轮与烟雾共同无缝循环。

先前拆分提示词：`game/assets/pixel_v2/facilities/engine_room_layers_v1/prompts.json`。它们记录素材来源，实际接入范围以本文件及用户最终要求为准。
