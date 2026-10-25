extends SceneTree

const Tiles = preload("res://scripts/island_tiles.gd")
const Art = preload("res://scripts/pixel_terrain.gd")
var failures: Array[String] = []

class GroundProbe extends Node2D:
	var tiles: Array = []
	var textures: Dictionary = {}
	func _draw() -> void:
		Tiles.draw_ground(self, Vector2.ZERO, tiles, Tiles.CELL_SIZE, textures)


func _init() -> void:
	call_deferred("_run")


func expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _run() -> void:
	var hashes: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/pixel_sources.sha256.json"))
	for asset in hashes:
		expect(FileAccess.get_sha256("res://assets/pixel_v2/" + asset) == hashes[asset], "Approved source PNG must stay byte-for-byte unchanged: " + asset)
	var game := (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.set_physics_process(false)
	var tree: Image = game.tree_texture.get_image()
	var original := (load(Art.SOURCE_ROOT + "tree_tile_concept_v2_large.png") as Texture2D).get_image()
	expect(tree.get_size() == Art.TREE_REGION.size, "Tree must use the approved v2 source rectangle, not the comparison sheet")
	var retained := 0
	for y in range(0, tree.get_height(), 4):
		for x in range(0, tree.get_width(), 4):
			var color := tree.get_pixel(x, y)
			if color.a == 0.0:
				continue
			retained += 1
			var source := original.get_pixelv(Art.TREE_REGION.position + Vector2i(x, y))
			expect(color.r == source.r and color.g == source.g and color.b == source.b, "Tree colors must be copied unchanged from the selected artwork")
	expect(retained > 18000, "Canopy and trunk remain present after removing the concept's ground")
	expect(tree.get_pixel(54, 657).a == 0.0, "Grass below the tree must not be baked into the sprite")
	var tiles: Array = []
	var kinds := ["grass", "farm", "sand", "rock", "tree", "grass", "lava", "gold", "sand", "rock", "grass", "farm"]
	var occupied: Dictionary = {}
	for i in range(kinds.size()):
		var cell := Vector2i(i % 4, i / 4)
		var tile := {"cell": cell, "kind": kinds[i], "facility": "", "depleted": false}
		tiles.append(tile)
		occupied[cell] = tile
	for kind in Art.FOOTPRINTS:
		var source: Texture2D = load(Art.SOURCE_ROOT + kind + "_tile_concept_v1.png")
		expect(game.terrain_textures[kind] == source, "Terrain must render the original texture directly, not a sampled replacement")
		expect(game.terrain_textures[kind].get_size() == source.get_size(), "Terrain retains full source resolution")
	expect(Art.ground_kind("farm") == "grass", "Farmland keeps the approved grass verges between beds")
	for crop in [[game.rice_atlas, game.RICE_FRAMES], [game.tomato_atlas, game.TOMATO_FRAMES]]:
		var source: Image = crop[0].get_image()
		var missed := 0
		for frame in crop[1]:
			expect(frame.size.y == source.get_height(), "Crop frame includes the full source height without vertical distortion")
		for y in range(0, source.get_height(), 2):
			for x in range(0, source.get_width(), 2):
				if source.get_pixel(x, y).a <= 0.5:
					continue
				var owners := 0
				for frame in crop[1]:
					if frame.has_point(Vector2(x, y)):
						owners += 1
				if owners != 1:
					missed += 1
		expect(missed == 0, "Every visible crop pixel belongs to exactly one complete growth stage")
	if DisplayServer.get_name() != "headless":
		await _check_rendered_seams(game, tiles)
		await _capture_game(game)
	else:
		print("Headless: GPU seam checks skipped; use a rendering display to run them.")
	game.queue_free()
	await process_frame
	for failure in failures.slice(0, 15):
		push_error(failure)
	print("TERRAIN VISUAL TEST: %d failures" % failures.size())
	quit(0 if failures.is_empty() else 1)


func _check_rendered_seams(game: Node2D, tiles: Array) -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(800, 600)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	root.add_child(viewport)
	var backing := ColorRect.new()
	backing.color = Color.MAGENTA
	backing.size = Vector2(800, 600)
	viewport.add_child(backing)
	var probe := GroundProbe.new()
	probe.tiles = tiles
	probe.textures = game.terrain_textures
	viewport.add_child(probe)
	for zoom in [0.55, 1.0, 1.4, 2.0]:
		probe.position = Vector2(95.37, 90.63)
		probe.scale = Vector2.ONE * zoom
		probe.queue_redraw()
		await process_frame
		await RenderingServer.frame_post_draw
		var screenshot := viewport.get_texture().get_image()
		var uncovered := 0
		var occupied: Dictionary = {}
		for tile in tiles:
			occupied[tile.cell] = true
		for tile in tiles:
			var rect := Tiles.cell_rect(Vector2.ZERO, tile.cell)
			# Authored exterior silhouettes are intentionally not rectangular. Check
			# every interior pixel and full shared edges, excluding only open-sky rims.
			for direction in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				if occupied.has(tile.cell + direction):
					continue
				if direction == Vector2i.LEFT:
					rect.position.x += 4.0
					rect.size.x -= 4.0
				elif direction == Vector2i.RIGHT:
					rect.size.x -= 4.0
				elif direction == Vector2i.UP:
					rect.position.y += 4.0
					rect.size.y -= 4.0
				else:
					rect.size.y -= 4.0
			var screen := Rect2(probe.position + rect.position * zoom, rect.size * zoom)
			for y in range(ceili(screen.position.y), floori(screen.end.y)):
				for x in range(ceili(screen.position.x), floori(screen.end.x)):
					var color := screenshot.get_pixel(x, y)
					if color.r > 0.9 and color.g < 0.1 and color.b > 0.9:
						uncovered += 1
		print("Rendered ground at zoom %.2f: %d uncovered pixels" % [zoom, uncovered])
		expect(uncovered == 0, "Connected terrain must never reveal background between cells")
		if zoom == 1.4:
			screenshot.save_png(ProjectSettings.globalize_path("res://../artifacts/game/terrain-seam-check.png"))
	# A trimmed cell must stay empty; only its upper cliff may extend into the hole.
	probe.tiles = tiles.duplicate(true)
	probe.tiles.remove_at(5)
	probe.scale = Vector2.ONE
	probe.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	var hole_image := viewport.get_texture().get_image()
	var hole_center := Vector2i(probe.position + Vector2(80, 64))
	expect(hole_image.get_pixelv(hole_center).is_equal_approx(Color.MAGENTA), "Concave island/trimmed hole must not be filled by boundary stitching")
	probe.tiles = tiles
	probe.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	expect(not viewport.get_texture().get_image().get_pixelv(hole_center).is_equal_approx(Color.MAGENTA), "Merged terrain must fill the old hole")
	viewport.queue_free()


func _capture_game(game: Node2D) -> void:
	game.get_node("HUD").hide()
	game.demo_started = true
	game.selected_plot = -1
	game.hovered_plot = -1
	game.selected_tool = game.TOOL_HOOK
	game.camera_zoom = 1.4
	game.camera_world = game.island_pos + Vector2(0, -24)
	game.hazards = []
	game.targets = []
	game.zones = []
	game.current_weather = -1
	game.weather_tint = 0.0
	for i in range(game.plots.size()):
		game.plots[i].state = 2 if i % 3 != 0 else 1
		game.plots[i].progress = 1.0 if i % 3 != 0 else 0.4
	game.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../artifacts/game/original-art-island-preview.png"))
