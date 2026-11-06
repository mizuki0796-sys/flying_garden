# 港口与探索飞船截图

- 请求：截取当前游戏港口和探索飞船图片，不修改造型或玩法。
- 复用：`main.gd::_draw_harbor`、`exploration_ship.gd::draw_ship`，均为当前代码绘制的占位造型，没有独立 PNG 母版。
- 范围：仅在独立预览场景中通过实际建造函数创建港口与飞船，并调用实际出航更新；不改游戏代码、存档、素材或特效。
- 参数：1152×648、10:00、动画时间 2.35、风力 0.14；全景 1 倍，近景 3 倍。港口位于地块 (2, 0)，出航后采样 0.8 秒。
- 输出：`artifacts/game/harbor-ship/`，三张实际 viewport 截图，包含停泊全景、停泊近景、离港近景。
- 复现：Godot `--path game --script res://tests/harbor_ship_preview.gd`（需图形渲染）。脚本检查实际建造、出航和截图保存成功。
