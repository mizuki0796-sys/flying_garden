extends RefCounted

# Player capacity is enforced by every island attachment stage.
const PLAYER_TILE_LIMIT := 100
const PLAYER_TYPICAL_TILES := 81
const DEBUG_TILE_LIMIT := 144
const PLAYER_GROWTH_MILESTONES := [25, 36, 49, 64, 81, 100]

static func player_limit(debug_override: int, debug_build: bool) -> int:
	return clampi(debug_override, PLAYER_TILE_LIMIT, DEBUG_TILE_LIMIT) if debug_build else PLAYER_TILE_LIMIT
