extends SceneTree

const Tiles = preload("res://scripts/island_tiles.gd")
const OUT := "res://../artifacts/game/island-y-sort/"

class Probe extends "res://scripts/main.gd":
	var drawn: Array[int] = []
	func _draw_islands() -> void:
		drawn.clear()
		super._draw_islands()
	func _draw_island() -> void:
		drawn.append(-1)
		super._draw_island()
	func _draw_hazard(hazard: Dictionary) -> void:
		drawn.append(int(hazard.world_index))
		super._draw_hazard(hazard)

var game
var failures := 0

func _init() -> void: call_deferred("run")

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)

func island(offset: Vector2, biome: int, index: int) -> Dictionary:
	return {"pos": game.island_pos + offset, "active": true, "biome": biome,
		"tiles": Tiles.wild_tiles(biome, 1), "world_key": "preview", "world_index": index}

func capture(name: String) -> void:
	game.queue_redraw()
	await process_frame
	await process_frame
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	check(game.drawn == game._island_draw_order(), "Actual rendering follows island Y order")
	check(root.get_texture().get_image().save_png(ProjectSettings.globalize_path(OUT + name + ".png")) == OK, "Screenshot saved")

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	root.size = Vector2i(1152, 648)
	game = Probe.new()
	root.add_child(game)
	await process_frame
	game._start_demo()
	game.set_process(false)
	game.set_physics_process(false)
	game.targets = []
	game.zones = []
	game.current_weather = -1
	game.weather_tint = 0.0
	game.day_minutes = 600
	game.animation_time = 2.35
	game.wind_strength = 0.14
	game.development.tech.radar = 3
	game.camera_zoom = 1.0
	game.camera_zoom_target = 1.0
	game.camera_world = game.island_pos + Vector2(70, 0)
	game.notice_label.text = ""
	game.selected_plot = -1
	game.hovered_plot = -1
	game._update_hud()
	game.hazards = [island(Vector2(90, 220), 0, 0)]
	check(game._island_draw_order() == [-1, 0], "Lower wild island draws over player")
	await capture("01-foreground-forest")
	game.hazards[0].pos = game.island_pos + Vector2(90, -220)
	game.camera_world = game.island_pos + Vector2(70, -80)
	game.camera_zoom = 0.85
	check(game._island_draw_order() == [0, -1], "Upper wild island draws behind player")
	await capture("02-background-forest")
	game.hazards = [island(Vector2(300, 110), 0, 0), island(Vector2(300, -20), 1, 1), island(Vector2(-90, -220), 0, 2)]
	game.camera_world = game.island_pos + Vector2(70, -40)
	game.camera_zoom = 0.8
	check(game._island_draw_order() == [2, 1, -1, 0], "Wild islands and player share one order")
	for optimized in [false, true]:
		game.optimized_rendering = optimized
		await capture("03-multiple-islands-" + ("cached" if optimized else "original"))
	var original_ids: Array = game.hazards.map(func(h): return h.world_index)
	game._island_draw_order()
	check(game.hazards.map(func(h): return h.world_index) == original_ids, "Sorting never mutates gameplay hazard indices")
	game.hazards[0].active = false
	game.hazards[1].pos = game.island_pos + Vector2(100000, 0)
	check(game._island_draw_order() == [2, -1], "Inactive and invisible islands stay excluded")
	game.view_mode = game.VIEW_FOCUS
	check(game._island_draw_order() == [-1], "Focus mode keeps only player")
	game.view_mode = game.VIEW_GOD
	game.hazards = [island(Vector2(0, 0), 0, 0), island(Vector2(100, 0), 1, 1)]
	check(game._island_draw_order() == [-1, 0, 1], "Equal Y uses deterministic index tie break")
	game.island_bounds.position.y += 100
	check(game._island_draw_order() == [0, 1, -1], "Asymmetric player footprint uses its center")
	game.island_bounds.position.y -= 100
	game.hazards = [island(Vector2(-100, 225), 0, 0)]
	game.camera_world = game.island_pos + Vector2(-30, 45)
	game.camera_zoom = 0.9
	await capture("04-front-left-forest")
	game.hazards = [island(Vector2(-290, -130), 0, 0), island(Vector2(290, -130), 5, 1), island(Vector2(-290, 130), 1, 2), island(Vector2(290, 130), 0, 3)]
	game.camera_world = game.island_pos
	game.camera_zoom = 0.85
	await capture("05-surrounding-islands")
	game.hazards = [island(Vector2(300, 70), 0, 0), island(Vector2(300, -60), 1, 1)]
	game.camera_world = game.island_pos + Vector2(285, 0)
	game.camera_zoom = 1.65
	await capture("06-wild-island-overlap-closeup")
	print("ISLAND Y SORT: %d failures" % failures)
	quit(1 if failures else 0)
