extends RefCounted
const Tiles = preload("res://scripts/island_tiles.gd")
const SAFE_SPEED := 35.0

static func movable(terrain: Dictionary) -> bool:
	return terrain.get("active", false) and not terrain.get("tethered", false) and not terrain.get("shop", false) and not terrain.get("tiles", []).is_empty()

static func impulse(a_velocity: Vector2, b_velocity: Vector2, a_mass: float, b_mass: float, normal: Vector2) -> Vector2:
	var closing := maxf(0.0, -(a_velocity - b_velocity).dot(normal))
	var bounce := 0.15 if closing >= SAFE_SPEED else 0.0
	return normal * (1.0 + bounce) * closing / (1.0 / a_mass + 1.0 / b_mass)

static func damage(terrain: Dictionary, point: Vector2, speed: float, other_mass: float) -> void:
	if speed < SAFE_SPEED or terrain.get("tiles", []).is_empty(): return
	var origin: Vector2 = terrain.pos - Tiles.bounds(terrain.tiles).get_center()
	var nearest: Dictionary = terrain.tiles[0]
	for tile in terrain.tiles:
		if (origin + Vector2(tile.cell) * Tiles.CELL_SIZE).distance_squared_to(point) < (origin + Vector2(nearest.cell) * Tiles.CELL_SIZE).distance_squared_to(point): nearest = tile
	nearest.hp = maxf(0.0, float(nearest.get("hp", 100.0)) - clampf(speed * 0.55 + other_mass * 0.4, 12.0, 80.0))
	if nearest.kind == "tree": nearest.tree_hp = maxf(0.0, float(nearest.get("tree_hp", 100.0)) - speed * 0.55)

static func move_wild(terrains: Array, delta: float, drag: float) -> void:
	var moving := false
	for terrain in terrains:
		if not movable(terrain): continue
		var velocity: Vector2 = terrain.get("velocity", Vector2.ZERO)
		if velocity.is_zero_approx(): continue
		moving = true
		terrain.pos += velocity * delta
		terrain.velocity = velocity * exp(-drag * delta)
		if terrain.velocity.length() < 0.05: terrain.velocity = Vector2.ZERO
	if not moving: return
	for i in range(terrains.size()):
		var a: Dictionary = terrains[i]
		if not movable(a): continue
		for j in range(i + 1, terrains.size()):
			var b: Dictionary = terrains[j]
			if not movable(b): continue
			var av: Vector2 = a.get("velocity", Vector2.ZERO)
			var bv: Vector2 = b.get("velocity", Vector2.ZERO)
			if av.is_zero_approx() and bv.is_zero_approx(): continue
			var ab := Tiles.bounds(a.tiles)
			var bb := Tiles.bounds(b.tiles)
			var ao: Vector2 = a.pos - ab.get_center()
			var bo: Vector2 = b.pos - bb.get_center()
			if not Rect2(ao + ab.position, ab.size).intersects(Rect2(bo + bb.position, bb.size)): continue
			var hit := Tiles.contact(a.tiles, ao, b.tiles, bo)
			if hit.is_empty(): continue
			var am := Tiles.mass(a.tiles)
			var bm := Tiles.mass(b.tiles)
			var closing := maxf(0.0, -(av - bv).dot(hit.normal))
			var force := impulse(av, bv, am, bm, hit.normal)
			a.velocity = av + force / am
			b.velocity = bv - force / bm
			a.pos += hit.normal * (hit.depth + 0.1) * bm / (am + bm)
			b.pos -= hit.normal * (hit.depth + 0.1) * am / (am + bm)
			damage(a, hit.point, closing, bm)
			damage(b, hit.point, closing, am)
