资源：energy_conversion_drip_atlas.png
透明 PNG 图集，1920×1920，6列×6行，每帧320×320。
按从左至右、从上至下读取36帧；20 FPS；1.8秒循环。
Godot独立场景：res://art_templates/complex_ui/energy_conversion_ui.tscn
场景直接绘制母版与液滴，不依赖GIF。playing属性控制动画。
验证：36帧液滴范围之外以及铜环像素完全不变，周期首尾相同。
