extends RefCounted

# Dedicated hut presentation, separate from the generic tile action list.
static func render(menu, tile: Dictionary) -> void:
	var game = menu.game
	var dev = game.development
	var title := Label.new()
	title.text = "%s小屋 / FARM COTTAGE" % game._crop_name(int(tile.get("farm_crop", game.CROP_RICE)))
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color("#315e47"))
	menu.content.add_child(title)
	var hero := HBoxContainer.new()
	hero.add_theme_constant_override("separation", 16)
	menu.content.add_child(hero)
	var portrait := TextureRect.new()
	portrait.name = "FarmHutPortrait"
	portrait.texture = game.farm_hut_texture(tile)
	portrait.custom_minimum_size = Vector2(82, 82)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	hero.add_child(portrait)
	var info := VBoxContainer.new()
	hero.add_child(info)
	var status := Label.new()
	status.text = "Lv.%d　覆盖半径 %d 格\n%s · 每 6 秒作业\n只播种与收获" % [tile.get("level", 1), dev.farm_radius(tile), "运行中" if bool(tile.get("farm_enabled", true)) else "已暂停"]
	status.add_theme_font_size_override("font_size", 14)
	status.add_theme_color_override("font_color", Color("#465b49"))
	info.add_child(status)
	var managed := 0
	var mature := 0
	for plot in game.plots:
		if dev.farm_manager(plot.cell) == tile:
			managed += 1
			if int(plot.state) == 2: mature += 1
	var summary := Label.new()
	summary.text = "管辖 %d 块农田　·　待收获 %d 块\n%s种子 %d 份　·　地块耐久 %d / %d" % [managed, mature, game._crop_name(int(tile.get("farm_crop", 0))), game.seed_stock(int(tile.get("farm_crop", 0))), tile.hp, dev.Rules.tile_max_hp(tile)]
	summary.add_theme_color_override("font_color", Color("#627559"))
	summary.add_theme_font_size_override("font_size", 13)
	menu.content.add_child(summary)
	var overlap_hint := Label.new()
	overlap_hint.text = "多座运行中的小屋覆盖时，重叠区默认种水稻。\n缺少稻种时等待；已有作物收获后再补种。"
	overlap_hint.add_theme_font_size_override("font_size", 11)
	overlap_hint.add_theme_color_override("font_color", Color("#627559"))
	menu.content.add_child(overlap_hint)
	menu.content.add_child(HSeparator.new())
