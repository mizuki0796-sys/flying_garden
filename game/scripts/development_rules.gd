extends RefCounted

# Central balance table. UI, tests and gameplay read the same values.
const RESOURCE_NAMES := {"coins": "金币", "wood": "木材", "stone": "石材", "ore": "矿物", "magma": "岩浆晶", "food": "粮食", "rice_seeds": "水稻种子", "tomato_seeds": "番茄种子"}
const TERRAIN_NAMES := {"grass": "草地", "farm": "农田", "tree": "林木", "sand": "沙地", "rock": "矿石", "lava": "岩浆", "gold": "金矿"}
const FACILITY_NAMES := {"power": "引擎室", "water": "储能室", "grapple": "抓钩小屋", "energy": "能源工厂", "farm_hut": "自动化管理小屋", "harbor": "探索港口"}
const BUILD_COSTS := {
	"harbor": {"coins": 12000, "wood": 800, "stone": 600, "ore": 300, "magma": 50},
	"power": {"coins": 40, "wood": 6, "ore": 1},
	"water": {"coins": 30, "wood": 4, "stone": 1},
	"grapple": {"coins": 38, "wood": 7, "ore": 1},
	"energy": {"coins": 45, "wood": 6, "stone": 2, "ore": 2},
	"farm_hut": {"coins": 60, "wood": 10, "stone": 4, "ore": 2},
	"farm": {"coins": 10, "food": 1},
	"tree": {"wood": 3, "food": 1},
}
const YIELDS := {
	"grass": {"rice_seeds": 1, "tomato_seeds": 1, "food": 1}, "sand": {"stone": 3, "coins": 6},
	"tree": {"wood": 6, "rice_seeds": 1, "tomato_seeds": 1}, "rock": {"stone": 4, "ore": 4},
	"gold": {"coins": 40, "ore": 2}, "lava": {"magma": 3, "ore": 2}
}
const CROP_GROW_SECONDS := 45.0
const HARVEST_COINS := 2
const TOMATO_HARVEST_COINS := HARVEST_COINS * 2
const CROP_SELL_COINS := [1, 2]
const RESTORE_FARM_COST := {"coins": 2}
const LAND_REPAIR_COST := {"coins": 120, "wood": 18, "stone": 24, "ore": 6}
const FARM_RADII := [0, 2, 3, 4]
const FARM_CYCLE_SECONDS := 6.0
const FUEL_CYCLE_SECONDS := 12.0
const FUEL_NAMES := {"": "不选择（停止补能）", "rice": "水稻", "tomato": "番茄", "ore": "矿物", "magma": "岩浆晶"}
const FOREST_RADIUS := 2.0
const FOREST_PROTECTION := [0.15, 0.30, 0.45, 0.60]
const RICE_ENERGY_BY_LEVEL := [0, 8, 15, 25]
const ENERGY_CROP_ENERGY_BY_LEVEL := [0, 20, 35, 55]
const ORE_ENERGY_BY_LEVEL := [0, 36, 60, 90]
const MAGMA_ENERGY := 120
const TRIM_COST := {"coins": 2, "wood": 1}
const LAYOUT_BASE_COST := {"coins": 500, "wood": 60, "stone": 80, "ore": 20}
const LAYOUT_TILE_COST := {"coins": 40, "wood": 4, "stone": 6, "ore": 2}
const REINFORCE_COST := {"coins": 2, "stone": 1}
const RECYCLE_RATIOS := [0.0, 0.25, 0.45, 0.65]
const TREE_GROW_SECONDS := CROP_GROW_SECONDS * 4.0
const SHIP_BUILD_COST := {"coins": 25000, "wood": 1200, "stone": 800, "ore": 600, "magma": 100}
const TECH_COST_GROWTH := 3
# Emergency imports cost considerably more than locally gathered materials.
const MINERAL_BUY_PRICES := {"stone": 10, "ore": 35, "magma": 90}

# column/row drive the visual tree. Every node also carries a short player-facing summary.
const TECH_ORDER := [
	"engine", "efficiency", "storage",
	"bioenergy", "automatic", "mineral_energy", "geothermal",
	"hook", "docking", "development", "radar", "terraform",
	"agri_automation", "forestry", "shelter", "forecast",
	"reinforcement", "recycling", "harbor", "exploration", "layout"
]
const TECH := {
	"layout": {"name": "整岛规划", "max": 1, "cost": {"coins": 300, "wood": 30, "stone": 40, "ore": 12}, "needs": {"terraform": 1, "development": 2}, "effect": "解锁整岛剪裁布局与三个阵型预设；应用布局需支付高额资源，按移动地块数计费", "column": 2, "row": 5, "icon": 5},
	"reinforcement": {"name": "地块加固", "max": 5, "cost": {"coins": 10, "stone": 2}, "needs": {"development": 1}, "effect": "每级解锁 3 次地块加固，共 15 次；每次耐久上限 +20，地块费用逐级翻倍", "column": 0, "row": 7, "icon": 5},
	"recycling": {"name": "地块回收", "max": 3, "cost": {"coins": 60, "stone": 8, "ore": 3}, "needs": {"terraform": 1}, "effect": "回收返还加固投入的 25% / 45% / 65%；未加固地块仅返还 1 石头", "column": 1, "row": 7, "icon": 5},
	"harbor": {"name": "空岛港口", "max": 1, "cost": {"coins": 10000, "wood": 500, "stone": 400, "ore": 200}, "needs": {"docking": 2, "storage": 3}, "effect": "允许在浮岛外围建造唯一探索港口，供飞船停泊和充能", "column": 1, "row": 8, "icon": 4},
	"exploration": {"name": "探索飞船", "max": 1, "cost": {"coins": 20000, "wood": 800, "ore": 500, "magma": 80}, "needs": {"harbor": 1, "engine": 3, "radar": 2}, "effect": "在港口建造唯一采矿飞船；以浮岛能源充能，负载降低飞行速度", "column": 2, "row": 8, "icon": 2},
	"engine": {"name": "动力工程", "max": 3, "cost": {"coins": 25, "wood": 3, "ore": 1}, "needs": {}, "effect": "解锁引擎；每级增加 1 座上限并提高总推力 30%", "column": 0, "row": 0, "icon": 1},
	"efficiency": {"name": "能耗优化", "max": 3, "cost": {"coins": 35, "ore": 1}, "needs": {"engine": 1}, "effect": "每级机械能耗 -15%，最多 -45%", "column": 1, "row": 0, "icon": 1},
	"storage": {"name": "储能工程", "max": 3, "cost": {"coins": 25, "stone": 1}, "needs": {}, "effect": "解锁储能室；每级总储量 +20%", "column": 0, "row": 1, "icon": 4},
	"bioenergy": {"name": "作物能源", "max": 3, "cost": {"coins": 32, "wood": 3, "ore": 1}, "needs": {}, "effect": "逐级提高粮食与能源作物的转化效率", "column": 0, "row": 2, "icon": 3},
	"automatic": {"name": "能源自动化", "max": 1, "cost": {"coins": 48, "wood": 5, "ore": 2}, "needs": {"bioenergy": 1}, "effect": "解锁能源工厂；仅持续消耗手动选择的来源，满能或缺料时暂停", "column": 1, "row": 2, "icon": 4},
	"mineral_energy": {"name": "矿物能源", "max": 3, "cost": {"coins": 45, "stone": 2, "ore": 2}, "needs": {"automatic": 1}, "effect": "能源工厂可消耗矿物；等级越高转化越多", "column": 2, "row": 2, "icon": 5},
	"geothermal": {"name": "地热转化", "max": 1, "cost": {"coins": 55, "ore": 2, "magma": 1}, "needs": {"development": 2, "automatic": 1}, "effect": "能源工厂可将 1 岩浆晶转化为 120 E", "column": 2, "row": 3, "icon": 5},
	"hook": {"name": "抓钩工程", "max": 3, "cost": {"coins": 30, "wood": 4, "ore": 1}, "needs": {"engine": 1}, "effect": "I 解锁唯一抓钩小屋；升级扩大射程并降低绞盘能耗", "column": 0, "row": 3, "icon": 2},
	"docking": {"name": "岛屿对接", "max": 2, "cost": {"coins": 55, "wood": 6, "ore": 2}, "needs": {"hook": 2}, "effect": "I 对接大型岛与商店；II 对接超级浮岛", "column": 1, "row": 3, "icon": 2},
	"development": {"name": "岛屿开拓", "max": 3, "cost": {"coins": 25, "wood": 3}, "needs": {}, "effect": "I 采矿；II 岩浆；III 双倍采集、勘探费减半", "column": 0, "row": 4, "icon": 5},
	"radar": {"name": "天空雷达", "max": 3, "cost": {"coins": 45, "stone": 2, "ore": 1}, "needs": {"development": 1}, "effect": "逐级扩大地图可见距离并识别岛屿稀有度", "column": 1, "row": 4, "icon": 6},
	"terraform": {"name": "岛屿剪裁", "max": 1, "cost": {"coins": 40, "stone": 2, "ore": 1}, "needs": {"development": 1}, "effect": "解锁抛弃地块，须保持主岛连通", "column": 1, "row": 5, "icon": 5},
	"agri_automation": {"name": "小屋升级", "max": 3, "cost": {"coins": 80, "wood": 8, "ore": 3}, "needs": {}, "effect": "I 解锁管理小屋；II/III 允许小屋升至 2/3 级，管理半径为 2/3/4 格，仅自动播种和收获农田", "column": 0, "row": 5, "icon": 3},
	"forestry": {"name": "空岛林业", "max": 1, "cost": {"coins": 45, "wood": 5, "food": 2}, "needs": {}, "effect": "可在空草地种树；林木为半径 2 格内农田提供基础 15% 减灾，多棵不叠加", "column": 0, "row": 6, "icon": 7},
	"shelter": {"name": "防护林工程", "max": 3, "cost": {"coins": 60, "wood": 8, "stone": 2}, "needs": {"forestry": 1}, "effect": "林木减灾提高至 30%/45%/60%；与预报合用仍保留至少 20% 灾害损伤，不能免灾", "column": 1, "row": 6, "icon": 7},
	"forecast": {"name": "天气预报", "max": 3, "cost": {"coins": 80, "stone": 2, "ore": 2}, "needs": {"forestry": 1}, "effect": "强化好天气收益，逐级缓解但不免除灾害", "column": 2, "row": 6, "icon": 6},
}

static func tile_max_hp(tile: Dictionary) -> float:
	return 100.0 + 20.0 * int(tile.get("reinforcement", 0))

static func tile_health(tile: Dictionary) -> float:
	return clampf(float(tile.get("hp", 100.0)) / tile_max_hp(tile), 0.0, 1.0)

static func reinforcement_cost(level: int) -> Dictionary:
	return scaled_cost(REINFORCE_COST, int(pow(2, level)))

static func tree_max_hp(tile: Dictionary) -> float:
	var stage := mini(3, int(float(tile.get("tree_progress", 1.0)) * 4.0))
	return [25.0, 45.0, 70.0, 100.0][stage]

static func scaled_cost(cost: Dictionary, multiplier: int) -> Dictionary:
	var result: Dictionary = {}
	for key in cost:
		result[key] = int(cost[key]) * multiplier
	return result

static func research_cost(key: String, current_level: int) -> Dictionary:
	# Each upgrade consumes 1x, 3x, 9x ... of every resource in the base quote.
	return scaled_cost(TECH[key].cost, int(pow(TECH_COST_GROWTH, current_level)))

static func cost_text(cost: Dictionary) -> String:
	var parts: PackedStringArray = []
	for key in cost:
		parts.append("%d %s" % [cost[key], RESOURCE_NAMES[key]])
	return " / ".join(parts)
