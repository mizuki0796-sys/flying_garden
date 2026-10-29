# 动力室飞轮动画素材

2026-10-27 接入。复用此前由内置 ImageGen 基于原动力室合成图拆分、补绘的素材；完整提示词见 `prompts.json`。

- `flywheel.png`：提供可动轮辐的采样；只读取实心铜色与黄色高光。原轮圈及完整连接杆仍直接显示母版，不绘制此图的光晕和外圈。
- `body.png`：保留为此前拆分记录，运行时已停用，避免补绘墙面产生圆形色差。

游戏中的屋身、屋顶、门、烟囱、管道和底座继续取自 `../engine_room_v2.png`。冒烟使用原绘制函数及参数。没有采用独立烟囱或新增连杆、灯等效果。

两张 PNG 的尺寸与透明通道保持生成结果；实际裁切、轴心、遮罩和转速由 `scripts/engine_room_animation.gd` 定义。完整连接杆（含铜色轴套）从旋转区域中扣除；轮辐按原图 18 源像素网格绘制，128 相位缓存，不生成细小旋转纹理碎片。统一流程见项目根目录 `COMPLEX_UI_ANIMATION_GUIDE.md`，最新任务单见 `art_templates/complex_ui/ENGINE_ROOM_CLEAN_BRIEF.md`。
