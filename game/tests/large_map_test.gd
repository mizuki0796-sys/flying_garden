extends SceneTree

const Tiles = preload("res://scripts/island_tiles.gd")
const COUNTS := [1000, 10000, 100000]
const IMAGE_SIZE := Vector2i(1152, 648)
const MAP_RECT := Rect2i(76, 82, 1000, 500)
const COLORS := {
	"grass": Color("#77ad59"), "farm": Color("#9c784b"), "sand": Color("#d8bc78"),
	"tree": Color("#467b4a"), "rock": Color("#7e8987"), "lava": Color("#ad4c3d"), "gold": Color("#d6ad3f")
}

var failures: Array[String] = []
var results: Array = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene: PackedScene = load("res://main.tscn")
	var game := scene.instantiate()
	root.add_child(game)
	await process_frame
	game.set_physics_process(false)
	game.set_process(false)
	game.hide()

	for count in COUNTS:
		var before_memory := OS.get_static_memory_usage()
		var start := Time.get_ticks_usec()
		var tiles := _make_tiles(count)
		# Exercise the best propulsion configuration currently allowed: three Lv.4 engines
		# under engine/efficiency research Lv.3. This exposes whether a huge island is movable,
		# rather than only whether its array can be stored.
		for engine_index in range(3):
			tiles[engine_index].facility = "power"
			tiles[engine_index].level = 4
		var build_ms := _elapsed_ms(start)
		var dimensions := _dimensions(count)
		_expect(tiles.size() == count, "%d tiles are generated exactly" % count)
		_expect(_is_connected_rectangle(tiles, dimensions), "%d tiles form one edge-connected island" % count)

		start = Time.get_ticks_usec()
		var bounds := Tiles.bounds(tiles)
		var bounds_ms := _elapsed_ms(start)
		start = Time.get_ticks_usec()
		var mass := Tiles.mass(tiles)
		var mass_ms := _elapsed_ms(start)
		_expect(bounds.size.x > 0.0 and bounds.size.y > 0.0, "%d-tile bounds remain valid" % count)
		_expect(is_finite(mass) and mass > 0.0, "%d-tile mass remains finite" % count)

		game.island_tiles = tiles
		game.development.tech.engine = 3
		game.development.tech.efficiency = 3
		start = Time.get_ticks_usec()
		game._refresh_island_shape()
		var refresh_ms := _elapsed_ms(start)
		_expect(game.island_tiles.size() == count and is_equal_approx(game.island_mass, mass), "%d tiles can be assigned as the player island" % count)
		var zoom: float = game._god_zoom_limit()
		_expect(zoom > 0.0 and is_finite(zoom), "%d-tile overview zoom remains calculable" % count)
		var maximum_speed: float = game._max_speed()
		var maximum_acceleration: float = game._engine_thrust() / game._effective_mass()
		var moving_thrust_energy_per_second: float = (game.movement_settings.moving_energy_per_second + game.movement_settings.thrust_energy_per_second) * game._mass_energy_ratio()

		var target_cell: Vector2i = tiles[-1].cell
		start = Time.get_ticks_usec()
		var found: Dictionary = game.development.tile_at(target_cell)
		var last_lookup_ms := _elapsed_ms(start)
		_expect(not found.is_empty() and found.cell == target_cell, "%d-tile last-cell lookup succeeds" % count)

		start = Time.get_ticks_usec()
		var index: Dictionary = {}
		for tile in tiles:
			index[tile.cell] = tile
		var index_ms := _elapsed_ms(start)
		_expect(index.size() == count, "%d-tile dictionary index preserves every tile" % count)

		var memory_delta := maxi(0, OS.get_static_memory_usage() - before_memory)
		var preview_path := "res://../artifacts/game/large-map-%d-tiles.png" % count
		var preview_error := _save_preview(tiles, dimensions, count, preview_path)
		_expect(preview_error == OK, "%d-tile overview image is saved" % count)
		results.append({
			"tiles": count, "columns": dimensions.x, "rows": dimensions.y,
			"world_width_px": int(bounds.size.x), "world_height_px": int(bounds.size.y),
			"mass": mass, "overview_zoom": zoom, "memory_delta_bytes": memory_delta,
			"maximum_speed_px_per_second": maximum_speed,
			"maximum_acceleration_px_per_second_squared": maximum_acceleration,
			"moving_thrust_energy_per_second": moving_thrust_energy_per_second,
			"build_ms": build_ms, "bounds_ms": bounds_ms, "mass_ms": mass_ms,
			"refresh_ms": refresh_ms, "last_linear_lookup_ms": last_lookup_ms,
			"dictionary_index_ms": index_ms, "preview": ProjectSettings.globalize_path(preview_path)
		})
		print("LARGE MAP %d: %dx%d cells, world %dx%d px, build %.2f ms, refresh %.2f ms, last lookup %.2f ms, index %.2f ms, max speed %.3f px/s, thrust energy %.1f E/s, zoom %.5f, memory delta %.2f MiB" % [
			count, dimensions.x, dimensions.y, bounds.size.x, bounds.size.y, build_ms, refresh_ms,
			last_lookup_ms, index_ms, maximum_speed, moving_thrust_energy_per_second, zoom, float(memory_delta) / 1048576.0])

	game.queue_free()
	await process_frame
	var report := {"engine": Engine.get_version_info().string, "results": results, "failures": failures}
	var file := FileAccess.open("res://../artifacts/game/large-map-test-report.json", FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(report, "  "))
		file.close()
	else:
		failures.append("report file could not be opened")

	if failures.is_empty():
		print("LARGE MAP TEST PASSED: exact counts, connectivity, player-island assignment, bounds, mass, lookup, indexing, and previews")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("LARGE MAP TEST FAILED: %d failures" % failures.size())
		quit(1)


func _dimensions(count: int) -> Vector2i:
	# The cell art is wider than tall, so a slightly taller cell grid fills a 16:9 overview.
	var columns := ceili(sqrt(float(count) * 1.12))
	return Vector2i(columns, ceili(float(count) / columns))


func _make_tiles(count: int) -> Array:
	var dimensions := _dimensions(count)
	var tiles: Array = []
	tiles.resize(count)
	for index in range(count):
		var raw := Vector2i(index % dimensions.x, index / dimensions.x)
		var cell := raw - Vector2i(dimensions.x / 2, dimensions.y / 2)
		var border := raw.x == 0 or raw.y == 0 or raw.x == dimensions.x - 1 or raw.y == dimensions.y - 1
		var value := posmod(raw.x * 17 + raw.y * 31, 97)
		var kind := "grass"
		if border and value % 3 == 0: kind = "sand"
		elif value < 6: kind = "tree"
		elif value < 10: kind = "rock"
		elif value == 10: kind = "gold"
		elif value == 11: kind = "lava"
		tiles[index] = {"cell": cell, "kind": kind, "facility": "", "level": 1, "hp": 100.0, "depleted": false}
	return tiles


func _is_connected_rectangle(tiles: Array, dimensions: Vector2i) -> bool:
	# Row-major generation means every tile except the first has its left neighbor,
	# or begins a row directly below an occupied tile. This proves one connected component.
	if tiles.is_empty(): return false
	for index in range(1, tiles.size()):
		var cell: Vector2i = tiles[index].cell
		var previous: Vector2i = tiles[index - 1].cell
		if cell.y == previous.y and cell.x == previous.x + 1:
			continue
		if cell.x == -dimensions.x / 2 and cell.y == previous.y + 1:
			continue
		return false
	return true


func _save_preview(tiles: Array, dimensions: Vector2i, count: int, path: String) -> Error:
	var image := Image.create(IMAGE_SIZE.x, IMAGE_SIZE.y, false, Image.FORMAT_RGBA8)
	image.fill(Color("#96cfdf"))
	# A restrained sky backdrop keeps the three scale previews comparable.
	image.fill_rect(Rect2i(0, 0, IMAGE_SIZE.x, 55), Color("#294c43"))
	image.fill_rect(Rect2i(0, 55, IMAGE_SIZE.x, 9), Color("#bfd49e"))
	for cloud in [Rect2i(55, 116, 180, 26), Rect2i(884, 155, 195, 30), Rect2i(740, 535, 230, 24)]:
		image.fill_rect(cloud, Color(1.0, 1.0, 1.0, 0.28))
	var cell_px := maxi(1, mini(MAP_RECT.size.x / dimensions.x, MAP_RECT.size.y / dimensions.y))
	var drawn_size := Vector2i(dimensions.x * cell_px, dimensions.y * cell_px)
	var origin := MAP_RECT.position + (MAP_RECT.size - drawn_size) / 2
	# A common drop shadow makes the footprint read as one very large floating island.
	image.fill_rect(Rect2i(origin + Vector2i(maxi(2, cell_px), maxi(5, cell_px * 2)), drawn_size), Color(0.13, 0.22, 0.22, 0.24))
	for index in range(tiles.size()):
		var raw := Vector2i(index % dimensions.x, index / dimensions.x)
		var rect := Rect2i(origin + raw * cell_px, Vector2i(cell_px, cell_px))
		image.fill_rect(rect, COLORS[str(tiles[index].kind)])
	# Scale ruler: 10 logical tiles, clamped so it remains visible at every scale.
	var ruler := maxi(20, cell_px * 10)
	image.fill_rect(Rect2i(70, 607, ruler, 5), Color("#294c43"))
	# Encode the requested scale as a small set of blocks in the top strip (1/10/100 blocks).
	var blocks := 1 if count == 1000 else (10 if count == 10000 else 100)
	for block in range(blocks):
		var x := 650 + (block % 50) * 7
		var y := 20 + (block / 50) * 13
		image.fill_rect(Rect2i(x, y, 5, 8), Color("#d6efbd"))
	return image.save_png(ProjectSettings.globalize_path(path))


func _elapsed_ms(start_usec: int) -> float:
	return float(Time.get_ticks_usec() - start_usec) / 1000.0


func _expect(condition: bool, description: String) -> void:
	if condition:
		print("PASS: " + description)
	else:
		failures.append(description)
