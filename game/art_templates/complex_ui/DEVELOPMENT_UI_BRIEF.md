# 岛屿开发与林业种植

- 用户要求：减少岛屿开发常驻文字，用图标、短名称和悬停介绍；加入明确的林业种植入口。
- 后续修正：开发面板的采集按钮直接复用左侧工具栏采集按钮的镐头图标；保留短名称、悬停介绍与原采集操作。
- 母版：现有 island_development.gd 开发菜单、pixel_hud_icons.svg 与现有 HUD 图标；不生成新位图。
- 修改前 SHA-256：island_development.gd `83F70B6A554CDB602856FDFE08CEE455D921CDA1DE4D4F33E7822C0378C2BB22`；pixel_hud_icons.svg `A938DB57DF3675BED4EFA63835897709086B8B78ACEAC069386A9657D21C2DFD`。
- 允许范围：B 开发面板的排版、按钮、资源显示、提示；林业入口复用现有 tree 建造、生长、采集与保存逻辑。
- 保持：其余面板、地形和建筑素材、所有动画与特效、科技条件、资源费用、存档格式。
- 尺寸：开发面板 426×510，三列动作按钮，1152×648 实际游戏窗口预览。
- 部件、补绘、运动、视频：无；本次为静态 UI，不新增动画。
- 验证：实际 main.tscn 中打开菜单并截屏；检查全部动作可达、锁定原因与成本提示、林木种植及成熟采集；通过 diff 确认绘制函数与素材未变。
- 可复现预览：tests/development_ui_test.gd，输出 artifacts/game/development-ui/。
- 验证结果：development_ui_test 48、development_test 674、mechanics_update_test 142、left_ui_test 13 项检查均通过；UI 测试同时在无头与 OpenGL 实际渲染模式运行。实际悬停截图为 `03-forestry-hover.png`，默认和解锁界面为 `01-locked.png`、`02-planting.png`。
- 复现命令：Godot 4.7.2 `--path game --script res://tests/development_ui_test.gd --rendering-method gl_compatibility`（先创建 `artifacts/game/development-ui` 目录）。
- 不变区：本次未修改任何图片、地形/设施绘制函数、生长/采集逻辑或存档格式；原左侧抽屉位置保持 x=8，仅宽度从 380 调整为 426。
