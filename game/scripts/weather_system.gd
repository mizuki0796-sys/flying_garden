extends RefCounted

# Rain/storm area >= 100 * (400 * 320) starting-island area.
# Clouds fully contain their precipitation child, with a shared slow drift.
const CELL := 8000.0
const RAIN_RADIUS := 2200.0
const CLOUD_RADIUS := 4100.0
const NAMES := {"sun": "晴天", "cloud": "阴天", "rain": "雨天", "storm": "雷暴", "snow": "雪天", "cyclone": "飓风"}
const GROWTH := {"sun": 1.55, "cloud": 0.75, "rain": 2.30, "storm": 0.35, "snow": 0.50, "cyclone": 0.15}
const PRIORITY := {"sun": 0, "cloud": 1, "rain": 2, "snow": 3, "storm": 4, "cyclone": 5}
const EDGE := {"sun": Color("#f7c74a"), "cloud": Color("#8798af"), "rain": Color("#56a8dc"), "storm": Color("#8060a8"), "snow": Color("#d9eff7"), "cyclone": Color("#bd5968")}

static func regions(position: Vector2, origin: Vector2, elapsed: float) -> Array:
	var result: Array = []
	var cell := Vector2i(floori((position.x - origin.x) / CELL), floori((position.y - origin.y) / CELL))
	for y in range(cell.y - 1, cell.y + 2):
		for x in range(cell.x - 1, cell.x + 2):
			var rng := RandomNumberGenerator.new()
			rng.seed = 314159 + x * 73856093 + y * 19349663
			var cycle_length := rng.randf_range(240.0, 320.0)
			var cycle := floori(elapsed / cycle_length)
			var age := fmod(elapsed, cycle_length)
			rng.seed += cycle * 83492791
			var duration := rng.randf_range(170.0, 220.0)
			if age >= duration:
				continue
			var velocity := Vector2(rng.randf_range(-0.6, 0.6), rng.randf_range(-0.35, 0.35))
			var center := origin + Vector2(x, y) * CELL + Vector2(rng.randf_range(-600, 600), rng.randf_range(-600, 600)) + velocity * age
			var id := "%d:%d:%d" % [x, y, cycle]
			var cloudy := rng.randf() < 0.7
			result.append(region(id, "cloud" if cloudy else "sun", center, CLOUD_RADIUS if cloudy else 2400.0, velocity, duration - age))
			var onset := rng.randf_range(15.0, 40.0)
			var ending := duration - rng.randf_range(20.0, 40.0)
			if cloudy and age >= onset and age < ending:
				var event_roll := rng.randf()
				var child_kind := "cyclone" if event_roll < 0.14 else ("storm" if event_roll < 0.34 else ("snow" if event_roll < 0.52 else "rain"))
				var child := region(id + ":" + child_kind, child_kind, center + Vector2(650, -300), RAIN_RADIUS, velocity, ending - age)
				child.parent_id = id
				result.append(child)
	return result

static func region(id: String, kind: String, center: Vector2, radius: float, velocity: Vector2, remaining: float) -> Dictionary:
	return {"id": id, "kind": kind, "name": NAMES[kind], "pos": center, "radius": radius,
		"velocity": velocity, "remaining": remaining, "priority": PRIORITY[kind], "growth": GROWTH[kind],
		"edge": EDGE[kind], "color": Color(EDGE[kind], 0.035), "icon": 5 if kind == "sun" else (6 if kind in ["rain", "snow"] else 7)}
