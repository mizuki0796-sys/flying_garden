extends RefCounted

const Layout = preload("res://scripts/world_layout.gd")
const Tiles = preload("res://scripts/island_tiles.gd")
const MAX_FREE := 121
var free_records: Array = []
var journal: Dictionary = {}
var free_tiles: Array = []
var free_terrain: Array = []
var templates: Dictionary = {}
var tile_created := 0
var tile_reused := 0
var created := 0
var reused := 0

func acquire(key: Vector2i, origin: Vector2) -> Dictionary:
	var record: Dictionary
	if free_records.is_empty(): record = {}; created += 1
	else: record = free_records.pop_back(); reused += 1
	var changed := journal.has(key)
	var source: Dictionary = journal[key] if changed else Layout.make_sector(key, origin)
	record.hazards = []
	record.targets = []
	record.zones = []
	for i in range(source.hazards.size()):
		var raw: Dictionary = source.hazards[i]
		var terrain: Dictionary = {} if free_terrain.is_empty() else free_terrain.pop_back()
		for field in raw:
			if field != "tiles": terrain[field] = raw[field]
		terrain.tiles = []
		var shape_key := "%d:%d:%d" % [raw.biome, raw.variant, raw.get("size_class", 0)]
		if not templates.has(shape_key):
			templates[shape_key] = Tiles.wild_tiles(raw.biome, raw.variant, raw.get("size_class", 0))
		var source_tiles: Array = raw.tiles if raw.has("tiles") else templates[shape_key]
		for source_tile in source_tiles:
			var tile: Dictionary
			if free_tiles.is_empty(): tile = {}; tile_created += 1
			else: tile = free_tiles.pop_back(); tile_reused += 1
			for field in source_tile:
				tile[field] = source_tile[field].duplicate(true) if source_tile[field] is Dictionary or source_tile[field] is Array else source_tile[field]
			terrain.tiles.append(tile)
		if not changed:
			terrain.radius = Tiles.bounds(terrain.tiles).size.length() * 0.5
			terrain.active = true
			terrain.tethered = false
			terrain.world_key = key
			terrain.world_index = i
		record.hazards.append(terrain)
	# Already modified sectors stay journaled; untouched regenerated sectors can
	# be discarded entirely when they leave the neighborhood.
	record.baseline = -1 if changed else hash(record.hazards)
	rebuild_targets(record)
	return record

func rebuild_targets(record: Dictionary) -> void:
	record.island_targets = []
	for terrain in record.hazards:
		record.island_targets.append({"pos": terrain.pos, "type": terrain.name, "value": 0, "weight": Tiles.mass(terrain.tiles), "active": terrain.active, "respawn": 0.0, "island": terrain})

func portable(record: Dictionary) -> Dictionary:
	return {"hazards": record.hazards.duplicate(true), "targets": [], "zones": []}

func release(key: Vector2i, record: Dictionary) -> void:
	if hash(record.hazards) != int(record.get("baseline", 0)):
		journal[key] = portable(record)
	else: journal.erase(key)
	for terrain in record.hazards:
		for tile in terrain.tiles:
			tile.clear()
			if free_tiles.size() < 4096: free_tiles.append(tile)
		terrain.clear()
		if free_terrain.size() < 256: free_terrain.append(terrain)
	record.clear()
	if free_records.size() < MAX_FREE: free_records.append(record)

func snapshot(active: Dictionary) -> Dictionary:
	var result := journal.duplicate(true)
	for key in active:
		if hash(active[key].hazards) != int(active[key].get("baseline", 0)): result[key] = portable(active[key])
		else: result.erase(key)
	return result
