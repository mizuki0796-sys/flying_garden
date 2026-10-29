extends RefCounted

# Player capacity is enforced by every island attachment stage.
const PLAYER_TILE_LIMIT := 100
const PLAYER_TYPICAL_TILES := 81
const DEBUG_TILE_LIMIT := 144
const PLAYER_GROWTH_MILESTONES := [25, 36, 49, 64, 81, 100]

# Design budgets for the future combat system, not measured unit capacities.
# Include player terrain in the scene budget. Do not hide collidable islands
# to satisfy it: future encounter loading must admit whole combat zones.
const COMBAT_SCENE_TILE_BUDGET := 160
const COMBAT_ZONE_MIN_TILES := 49
const COMBAT_ZONE_MAX_TILES := 81
const COMBAT_NORMAL_UNIT_BUDGET := 50
const COMBAT_PEAK_UNIT_BUDGET := 80
const COMBAT_BOSS_BUDGET := 3
const ARMY_ROSTER_LIMIT := 500

static func player_limit(debug_override: int, debug_build: bool) -> int:
	return clampi(debug_override, PLAYER_TILE_LIMIT, DEBUG_TILE_LIMIT) if debug_build else PLAYER_TILE_LIMIT

static func available_combat_tiles(player_tiles: int) -> int:
	return maxi(0, COMBAT_SCENE_TILE_BUDGET - player_tiles)
