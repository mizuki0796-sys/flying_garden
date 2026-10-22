extends RefCounted

# All construction/research prices and extraction yields live here for balancing.
const RESOURCE_NAMES := {"coins": "金币", "wood": "木材", "stone": "石材", "ore": "矿物", "magma": "岩浆晶", "food": "粮食", "seeds": "种子"}
const TERRAIN_NAMES := {"grass": "草地", "farm": "农田", "tree": "林木", "sand": "沙地", "rock": "矿石", "lava": "岩浆", "gold": "金矿"}
const FACILITY_NAMES := {"power": "引擎室", "water": "储能室", "grapple": "抓钩小屋"}
const BUILD_COSTS := {"power": {"coins": 40, "wood": 6, "ore": 3}, "water": {"coins": 30, "wood": 4, "stone": 2}, "farm": {"coins": 10, "food": 1}}
const YIELDS := {
	"grass": {"seeds": 2, "food": 1}, "sand": {"stone": 3, "coins": 6},
	"tree": {"wood": 6, "seeds": 2}, "rock": {"stone": 4, "ore": 4},
	"gold": {"coins": 40, "ore": 2}, "lava": {"magma": 3, "ore": 2}
}
const TECH_ORDER := ["engine", "storage", "efficiency", "automatic", "hook", "development", "terraform", "geothermal"]
const TECH := {
	"engine": {"name": "动力工程", "max": 3, "cost": {"coins": 25, "wood": 3, "ore": 2}, "needs": {}, "effect": "解锁引擎建造；每级总推力 +30%，开放更高建筑等级"},
	"storage": {"name": "储能工程", "max": 3, "cost": {"coins": 25, "stone": 3}, "needs": {}, "effect": "解锁储能室建造；每级储量 +20%，开放更高建筑等级"},
	"efficiency": {"name": "高效利用", "max": 3, "cost": {"coins": 35, "ore": 3}, "needs": {"engine": 1}, "effect": "每级机械能耗 -15%（最多 -45%）"},
	"automatic": {"name": "自动填充", "max": 1, "cost": {"coins": 45, "wood": 4, "ore": 4}, "needs": {"efficiency": 1}, "effect": "能源低于 30% 时自动消耗燃料，可在开发面板开关"},
	"hook": {"name": "远程抓钩", "max": 3, "cost": {"coins": 30, "wood": 3, "ore": 2}, "needs": {}, "effect": "每级射程 +96 px；开放抓钩小屋升级"},
	"development": {"name": "岛屿开拓", "max": 3, "cost": {"coins": 25, "wood": 3}, "needs": {}, "effect": "I 采矿与金矿；II 岩浆采集；III 产量翻倍、勘探费减半"},
	"terraform": {"name": "岛屿剪裁", "max": 1, "cost": {"coins": 40, "stone": 5, "ore": 3}, "needs": {"development": 1}, "effect": "解锁抛弃地块，保留主岛连通；设施须先搬走"},
	"geothermal": {"name": "地热转化", "max": 1, "cost": {"coins": 50, "ore": 5, "magma": 1}, "needs": {"development": 2, "efficiency": 1}, "effect": "每份岩浆晶可转化 60 E；自动填充也可使用"}
}

static func scaled_cost(cost: Dictionary, multiplier: int) -> Dictionary:
	var result: Dictionary = {}
	for key in cost:
		result[key] = int(cost[key]) * multiplier
	return result

static func cost_text(cost: Dictionary) -> String:
	var parts: PackedStringArray = []
	for key in cost:
		parts.append("%d %s" % [cost[key], RESOURCE_NAMES[key]])
	return " / ".join(parts)
