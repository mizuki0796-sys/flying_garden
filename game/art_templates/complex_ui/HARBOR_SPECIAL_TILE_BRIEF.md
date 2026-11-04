# 专用停泊地块重制

- 最新要求：结合 UI 生成规则重做港口为特殊地块，只有此地块周围允许停船。
- 范围：整个港口顶面重新设计；沿用一格 80×64 占地及原地形外沿，不重复叠加土石底座。港口 facility 仍作为特殊用途标记，兼容现有存档。
- 风格基准：asset-library/STYLE_GUIDE.md 与 floating_grass_tile_pixel_master_v1.png；近正俯视、正交、粗方块像素、左上光源、每材质最多三个明度，无柔光。
- 新视觉：暖木甲板、蓝绿石边、中心锚形标记、四角系泊桩；四边均可表达侧向停泊，船不落在地块顶面。
- 保持：飞船素材、双桨、其他地块、特效、建造费用、科技、唯一飞船与唯一港口限制。无灯、吊机、烟雾或新动画。
- 停泊：仅依据 facility=harbor 的外围地块选择相邻空位，保持现有自动选向。检查无港口时不能造船，停泊和返航始终跟随港口。
- 交付：新透明母版、提示词、共享绘制及实际游戏截图；固定 1152×648、10:00、动画 2.35 秒、风力 0.14，1 倍及 3 倍。
- ImageGen 内置工具生成：`game/assets/pixel_v2/facilities/harbor_special_tile.png`，1402×1122 RGBA，角像素 alpha=0；SHA-256 `5C4ACC2EB91AAEB7FB4515D2036FBDE8682BBE423168489E2A38F62F3E2371B0`。提示词：`artifacts/game/harbor-special-tile/prompt.txt`。
- 参数：固定裁切 `(64,64,1280,992)`，最近邻归一为 80×64；中心锚点 `(40,32)`；四向共用同一纹理，保持左上光源与锚标直立。作为港口顶面绘制，沿用原地块地基。
- 实现：`harbor_visual.gd`，主游戏与布局编辑器复用；`exploration_ship.gd` 去掉缺失港口时以岛心计算泊位的后备行为。
- 验证：`harbor_ship_preview.gd` 生成 6 张实际游戏截图，验证普通地块不能造船、原地块数量/类型不变、四向相邻空位、出航返航、港口搬迁跟随及缺失港口无后备泊位；布局 60 项与玩法 142 项全部通过。
- 复现：Godot 4.7.2 `--path game --script res://tests/harbor_ship_preview.gd --rendering-method gl_compatibility`；输出 `artifacts/game/harbor-special-tile/`。
- 本次静态地块重制，无新动画；未录制新视频、未验证导出包。唯一港口、唯一飞船规则保留，尚不支持多船同时停泊。
- 不变区验证：将新旧 `02-docked-closeup.png` 逐像素比较，40232 个变化像素全部位于 `(351,303)-(590,494)`，恰为 3 倍下单格 240×192 区域；区域外包括飞船、双桨、其他地块与 HUD 的像素完全一致。
- 视频追加：实际游戏脚本追加 `-- --video`，保存 `artifacts/game/harbor-special-tile/harbor-test.mp4` 与 `video-frames/` 母帧。1152×648、30 FPS、240 帧、8 秒；2 秒出航、3 秒召回，最终回泊断言通过。H.264/yuv420p 编码及完整解码检查通过，无音轨；未验证导出包。
