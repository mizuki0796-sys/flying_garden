# 飞船 Y 排序与十倍货舱

- 用户要求：飞船不要盖住前方树木；现有全部阶段货舱容量乘十。
- 唯一视觉变化：飞船与主岛、外岛共用世界中心 Y 排序，同 Y 时先画船，再画岛与树；船旁血量、电量提示仍在前景。
- 复用母版：`game/assets/pixel_v2/vehicles/` 下的 `collector_cargo_empty.png`、`collector_cargo_partial.png`、`collector_box_depth.png`。SHA-256 依次为 `96A5AC89BB08FD15B66ADD65E97A992D1E7984674AD9CE0FFD0A47CE23EB6C23`、`F6D1FAD6ED7BEF0F2B09686FF8BAB75FDB3ED751D352FD0AB9F1808ADB4EDD34`、`D7DDEB870D671060BC08172DC625F7364E0E613AC7748E0EE92A7A59D487E1E4`。
- 保持：80×64 船体、中心锚点、素材、朝向、尾气参数、港口与树木外观、碰撞逻辑；没有生成素材或新增动画。
- 容量：0–10 级为 240、400、640、1000、1500、2200、3200、4500、6000、8000、10000。电池仍为 500；现有按容量计算的负载和采矿能耗公式沿用，单次采矿耗电随扩容降低。
- 实现：`main.gd` 的绘制排序；`exploration_ship.gd` 分离前景状态提示；`development_rules.gd` 的容量表及说明。存档和界面读取同一容量表。
- 预览：`godot --path game --script res://tests/island_y_sort_test.gd --rendering-method gl_compatibility`，固定时间 2.35 秒、风力 0.14、2 倍近景，实际调用游戏绘制。
- 输出：`artifacts/game/island-y-sort/07-ship-behind-forest-cached.png`、`07-ship-behind-forest-original.png`、`08-ship-on-top-baseline.png`、`ship-scope-validation.txt`。
- 不变区验证：与原先船在顶层的同帧基准比较，变化边界为 `(496,170,622,258)`，全部位于船体屏幕矩形 `(496,130,656,258)` 内；船体范围外无变化。
- 验证通过：Y 排序（含两种渲染路径、同 Y、前后位置、聚焦视图、未建造）、对接与容量 92 项、货舱状态 83 项、生产科技 224 项、港口控制 27 项。覆盖满载返航卸货、超载确认、旧档兼容和满级存档。
- 未录制新视频，未重新导出安装包。
