extends "res://scripts/thick_wall.gd"

const Rules = preload("res://scripts/development_rules.gd")
const SIZE := Tiles.CELL_SIZE
const INNER := 10000.0
const OUTER := 10015.0
const EDGES := [10005.0,10009.0,10012.0,10014.0,OUTER]
const MATERIALS := ["原木","碎石","混凝土砌块","整体水泥","合金"]
const COLORS := [Color("#875f44"),Color("#948999"),Color("#646e63"),Color("#929497"),Color("#50444b")]
const ART := "res://assets/pixel_v2/walls/"
const SPAWN_CLEARANCE := 6
const HP_SCALE := 10
var near_wall_spawn := true

func ring_center() -> Vector2:
	return game.world_origin + (Vector2.DOWN*(INNER-SPAWN_CLEARANCE)*SIZE.y if near_wall_spawn else Vector2.ZERO)

var hp_left: Dictionary = {}
var viewport: SubViewport
var shader: ShaderMaterial
var mask_rect := Rect2i()
var last_view := Rect2()
var mask_dirty := true

static func layer(cell: Vector2i) -> int:
	var r := (Vector2(cell)+Vector2(0.5,0.5)).length()
	if r < INNER: return -1
	for k in range(5):
		if r < EDGES[k]: return k
	return -1

static func max_hp(k: int, scale: int = HP_SCALE) -> float:
	return Rules.tile_max_hp({}) * (3+2*k) * scale

func grid_area(area: Rect2) -> Rect2:
	return Rect2((area.position-ring_center())/SIZE,area.size/SIZE)

static func cell_range(area: Rect2) -> Rect2i:
	var first := Vector2i(area.position.floor())
	return Rect2i(first,Vector2i(area.end.ceil())-first)

static func touches_ring(area: Rect2, inner: float) -> bool:
	var nearest := Vector2.ZERO.clamp(area.position,area.end)
	var farthest := area.position.abs().max(area.end.abs())
	return nearest.length_squared() < (OUTER+1)*(OUTER+1) and farthest.length_squared() >= (inner-1)*(inner-1)

func beyond_inner(point: Vector2) -> bool:
	return ((point-ring_center())/SIZE).length() >= INNER

func keep_terrain(terrain: Dictionary) -> bool:
	if not enabled: return true
	var center: Vector2 = (terrain.pos-ring_center())/SIZE
	var reach := float(terrain.get("radius",0.0))/SIZE.y+1.0
	if center.length()+reach < INNER: return true
	var half_size := Tiles.bounds(terrain.tiles).size*0.5/SIZE
	return (center.abs()+half_size).length() < INNER

func solids(area: Rect2) -> Array[Rect2]:
	var result: Array[Rect2] = []
	var region := grid_area(area)
	if not enabled or not touches_ring(region,INNER): return result
	var cells := cell_range(region)
	for y in range(cells.position.y,cells.end.y):
		for x in range(cells.position.x,cells.end.x):
			var cell := Vector2i(x,y)
			if layer(cell) >= 0 and hp_left.get(cell,1.0) > 0.0:
				result.append(Rect2(ring_center()+Vector2(cell)*SIZE,SIZE))
	return result

func snapshot() -> Dictionary:
	var state := super.snapshot()
	state.near_wall_spawn = near_wall_spawn
	state.geometry = "ring_v1"
	state.hp_scale = HP_SCALE
	state.cells = hp_left.duplicate()
	return state

static func valid_ring(data: Dictionary) -> bool:
	if data.has("near_wall_spawn") and not data.near_wall_spawn is bool: return false
	if data.get("geometry") != "ring_v1" or not data.get("cells") is Dictionary: return false
	var scale: Variant = data.get("hp_scale",1)
	if not scale is int or scale not in [1, HP_SCALE]: return false
	if not data.get("enabled") is bool or not data.get("crossed") is bool: return false
	if not data.get("rumors") is int or data.rumors < 0 or data.rumors > RUMORS.size(): return false
	if not data.get("depth") is float or not is_finite(data.depth) or data.depth < 0 or data.depth > 15: return false
	var deepest := 0.0
	for cell in data.cells:
		if not cell is Vector2i: return false
		var k := layer(cell)
		var hp: Variant = data.cells[cell]
		if k < 0 or not hp is float or not is_finite(hp) or hp < 0 or hp >= max_hp(k,scale): return false
		if hp == 0.0: deepest = maxf(deepest,cleared_depth(cell))
	return deepest == data.depth and (not data.crossed or deepest == 15)

static func cleared_depth(cell: Vector2i) -> float:
	return floorf((Vector2(cell)+Vector2(0.5,0.5)).length()-INNER)+1.0

func restore(data: Dictionary) -> void:
	super.restore(data)
	near_wall_spawn = data.get("near_wall_spawn",false)
	hp_left = data.cells.duplicate()
	if data.get("hp_scale",1) == 1:
		for cell in hp_left:
			hp_left[cell] *= HP_SCALE
	mask_dirty = true

func journal() -> String:
	if not enabled: return ""
	var message := "\n\n%s\n从内向外：原木5格、碎石4格、砌块3格、水泥2格、合金1格。\n正面撞速达到 35 时，反冲从接触处向岛内逐格减半，最多传 5 格。加固能保护后排，空格能截断反冲。可用 B 修缮。已%s。" % [("出生点在北侧墙内沿往里6格处。" if near_wall_spawn else "出生点在环墙中央，距内沿10000格。"), ("穿过围墙" if crossed else "探索至第%d格" % ceili(depth))]
	for i in range(rumors): message += "\n"+RUMORS[i]
	for i in range(3):
		if depth >= [5,9,12][i]: message += "\n"+RECORDS[i]
	if crossed: message += "\n"+RECORDS[3]
	return message

func collide_island() -> void:
	if not enabled: return
	var bounds := Rect2(game.island_pos+game.island_bounds.position,game.island_bounds.size)
	var obstacles := solids(bounds)
	if obstacles.is_empty():
		if not crossed and depth == 15 and Vector2.ZERO.clamp(grid_area(bounds).position,grid_area(bounds).end).length() > OUTER+1:
			crossed = true
			game._show_notice(RECORDS[3],8.0)
		return
	var pushes := [0.0,0.0,0.0,0.0]
	var contacts := {}
	for tile in game.island_tiles:
		var hull := Tiles.cell_rect(game.island_pos,tile.cell,SIZE)
		for solid in obstacles:
			if not hull.intersects(solid): continue
			var cell := Vector2i(((solid.position-ring_center())/SIZE).round())
			if not contacts.has(cell): contacts[cell] = []
			contacts[cell].append(tile)
			pushes[0] = maxf(pushes[0],solid.end.x-hull.position.x)
			pushes[1] = maxf(pushes[1],hull.end.x-solid.position.x)
			pushes[2] = maxf(pushes[2],solid.end.y-hull.position.y)
			pushes[3] = maxf(pushes[3],hull.end.y-solid.position.y)
	if contacts.is_empty(): return
	var axis := pushes.find(pushes.min())
	var normal: Vector2 = [Vector2.RIGHT,Vector2.LEFT,Vector2.DOWN,Vector2.UP][axis]
	var speed := -Vector2(game.island_velocity).dot(normal)
	game.island_pos += normal*(float(pushes[axis])+0.1)
	if speed <= 0.0: return
	game.island_velocity = Vector2(game.island_velocity).slide(normal)
	if speed < MIN_SPEED or game.collision_cooldown > 0.0: return
	game.collision_cooldown = 2.0
	var impact_mass: float = game.island_mass
	var paid := {}
	for cell in contacts:
		for tile in contacts[cell]:
			if paid.has(tile.cell) or game.development.tile_at(tile.cell).is_empty(): continue
			var cost := (8.0+speed*0.15)/(1.0+0.15*int(tile.get("reinforcement",0)))
			paid[tile.cell] = minf(float(tile.hp),cost)/cost
	apply_recoil(paid.keys(), Vector2i(normal), speed)
	if game.game_over: return
	var destroyed := 0
	var last_cell: Vector2i = contacts.keys()[0]
	for cell in contacts:
		var fraction := 0.0
		for tile in contacts[cell]: fraction += float(paid.get(tile.cell, 0.0))
		if fraction <= 0: continue
		var k := layer(cell)
		var damage: float = impact_mass*speed*fraction/(contacts.size()*contacts[cell].size())
		var hp := maxf(0,float(hp_left.get(cell,max_hp(k)))-damage)
		hp_left[cell] = hp
		last_cell = cell
		if hp == 0:
			destroyed += 1
			depth = maxf(depth,cleared_depth(cell))
	if destroyed > 0: mask_dirty = true
	var kind := layer(last_cell)
	game._show_notice("撞开 %d 格墙体" % destroyed if destroyed else "%s墙剩余耐久 %d / %d，退开修缮后再撞" % [MATERIALS[kind],ceili(hp_left.get(last_cell,max_hp(kind))),max_hp(kind)],4.0)

func _prepare_surface() -> void:
	viewport = SubViewport.new()
	viewport.size = Vector2i(game.VIEW_SIZE)
	viewport.transparent_bg = true
	viewport.disable_3d = true
	game.add_child(viewport)
	var surface := ColorRect.new()
	surface.size = game.VIEW_SIZE
	shader = ShaderMaterial.new()
	shader.shader = preload("res://shaders/ring_wall.gdshader")
	shader.set_shader_parameter("exposed",load(ART+"exposed.png"))
	for key in ["wood","rubble","brick","concrete"]:
		var texture := load(ART+key+".png") as Texture2D
		shader.set_shader_parameter(key,texture)
		shader.set_shader_parameter(key+"_size",texture.get_size())
	for i in range(6): shader.set_shader_parameter("alloy%d"%i,load(ART+"alloy%d.png"%(i+1)))
	surface.material = shader
	viewport.add_child(surface)

func dispose() -> void:
	if is_instance_valid(viewport): viewport.queue_free()

func draw_world() -> void:
	if not enabled: return
	var area := Rect2(game._screen_to_world(Vector2.ZERO),game.VIEW_SIZE/game.camera_zoom)
	var region := grid_area(area)
	if not touches_ring(region,9985): return
	if viewport == null: _prepare_surface()
	var cells := cell_range(region).grow(1) # Include neighbors of partially visible edge cells.
	if mask_dirty or cells != mask_rect:
		var mask := Image.create(cells.size.x,cells.size.y,false,Image.FORMAT_R8)
		mask.fill(Color.WHITE)
		for y in range(cells.position.y,cells.end.y):
			for x in range(cells.position.x,cells.end.x):
				var cell := Vector2i(x,y)
				if hp_left.get(cell,1.0) == 0.0: mask.set_pixelv(cell-cells.position,Color.BLACK)
		shader.set_shader_parameter("remaining_cells",ImageTexture.create_from_image(mask))
		shader.set_shader_parameter("mask_start",Vector2(cells.position))
		shader.set_shader_parameter("mask_size",Vector2(cells.size))
		mask_rect = cells
		last_view = Rect2()
		mask_dirty = false
	if region != last_view:
		shader.set_shader_parameter("world_start",region.position)
		shader.set_shader_parameter("world_size",region.size)
		viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		last_view = region
	game.draw_texture_rect(viewport.get_texture(),area,false)

func draw_map() -> void:
	var area := Rect2(game._map_to_world(game.MAP_RECT.position),game.MAP_RECT.size/game.map_scale)
	for solid in solids(area):
		var visible := solid.intersection(area)
		if visible.has_area():
			var k := layer(Vector2i(((solid.position-ring_center())/SIZE).round()))
			game.map_ink.draw_rect(Rect2(game._world_to_map(visible.position),visible.size*game.map_scale),COLORS[k])
