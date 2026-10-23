extends RefCounted

# All material deposits belong to islands. No independent floating loot.
const SECTOR_SIZE := 640.0
const ACTIVE_RADIUS := 5
const WORLD_SEED := 271828
const ISLAND_CHANCE := 0.42
const BIOMES := ["林地岛", "矿石岛", "沙地岛", "草甸岛", "火山岛", "金矿岛"]


static func sector_at(position: Vector2, origin: Vector2) -> Vector2i:
	return Vector2i(floori((position.x - origin.x) / SECTOR_SIZE), floori((position.y - origin.y) / SECTOR_SIZE))


static func make_sector(key: Vector2i, origin: Vector2) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = WORLD_SEED + key.x * 73856093 + key.y * 19349663
	var sector_origin := origin + Vector2(key) * SECTOR_SIZE
	var islands: Array = []
	var position := sector_origin + Vector2(rng.randf_range(200.0, 440.0), rng.randf_range(180.0, 460.0))
	var starter_position := origin + Vector2(450, -100)
	if position.distance_to(origin) > 450.0 and position.distance_to(starter_position) > 260.0 and rng.randf() <= ISLAND_CHANCE:
		var biome := rng.randi_range(0, BIOMES.size() - 1)
		var distance_band := Vector2(key).length()
		var rarity_roll := rng.randf()
		var size_class := 2 if distance_band >= 4.0 and rarity_roll < 0.035 else (1 if distance_band >= 2.0 and rarity_roll < 0.16 else 0)
		var shop := distance_band >= 2.0 and rng.randf() < 0.045
		if shop:
			size_class = maxi(1, size_class)
			biome = 3
		var rarity := "超级" if size_class == 2 else ("大型" if size_class == 1 else "普通")
		islands.append({"pos": position, "radius": 74.0, "biome": biome,
			"name": "漂流商店岛" if shop else rarity + BIOMES[biome], "variant": rng.randi_range(0, 3),
			"size_class": size_class, "rarity": rarity, "shop": shop})
	if key == Vector2i(0, -1):
		islands.append({"pos": starter_position, "radius": 104.0, "biome": 0, "name": "普通林地岛", "variant": 0,
			"size_class": 0, "rarity": "普通", "shop": false})
	return {"hazards": islands, "targets": [], "zones": []}
