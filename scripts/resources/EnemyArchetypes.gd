# res://scripts/resources/EnemyArchetypes.gd
# Enemy and boss archetypes (data/enemy_archetypes.json, GAME_ROADMAP.md section 2).
# An archetype is a role template: skills drawn from hero-class pools plus
# monster-only skills, talents spent in one hero branch, and an AI role. Players
# = enemies: an enemy's Whirlwind or ultimate is the exact same skill a hero uses.
class_name EnemyArchetypes
extends RefCounted

static var _data: Dictionary = {}

static func data() -> Dictionary:
	if _data.is_empty():
		var f = FileAccess.open("res://data/enemy_archetypes.json", FileAccess.READ)
		var d = JSON.parse_string(f.get_as_text()) if f else null
		_data = d if d is Dictionary else {}
		if _data.is_empty():
			push_error("EnemyArchetypes: data/enemy_archetypes.json missing or invalid")
			_data = {"archetypes": {}, "races": {}, "ai_roles": {}, "boss": {}, "settings": {}}
	return _data

static func archetypes() -> Dictionary:
	return data().get("archetypes", {})

static func get_archetype(id: String) -> Dictionary:
	return archetypes().get(id, {})

static func boss_cfg() -> Dictionary:
	return data().get("boss", {})

## Default AI tuning, overridden per role in ai_roles.
const DEFAULT_ROLE := {"skill_chance": 0.75, "consider_buffs": 0.6, "debuff_chance": 0.6,
	"combo_bias": 0.0, "defend_below": 0.35, "heal_ally_below": 0.0}

static func role(role_id: String) -> Dictionary:
	var r = DEFAULT_ROLE.duplicate()
	r.merge(data().get("ai_roles", {}).get(role_id, {}), true)
	return r

# ------------------------------------------------------------------ picking

static func _weighted(weights: Dictionary) -> String:
	var total := 0.0
	for k in weights:
		total += max(0.0, float(weights[k]))
	if total <= 0.0:
		return ""
	var roll = RandomManager.randf() * total
	for k in weights:
		roll -= max(0.0, float(weights[k]))
		if roll <= 0.0:
			return k
	return weights.keys()[-1]

## Archetype for one enemy of `race`, weighted by the race's archetype_weights
## (uniform if the race lists none).
static func pick_archetype(race: String) -> String:
	var w: Dictionary = {}
	var rw: Dictionary = data().get("races", {}).get(race, {}).get("archetype_weights", {})
	for id in archetypes():
		w[id] = float(rw.get(id, 1.0)) if not rw.is_empty() else 1.0
	var pick = _weighted(w)
	return pick if pick != "" else String(archetypes().keys()[0])

## Skill names for one enemy. `known` is the skill table (name -> data) used to
## skip unknown names and check require_types.
static func roll_skills(archetype_id: String, race: String, known: Dictionary, extra: int = 0, floor: int = 1) -> Array:
	var a = get_archetype(archetype_id)
	var st: Dictionary = data().get("settings", {})
	var cap = float(st.get("damage_power_cap_base", 999)) + float(st.get("damage_power_cap_per_floor", 0)) * floor
	var min_floor: Dictionary = st.get("skill_min_floor", {})
	var fits = func(s) -> bool:
		return known.has(s) and floor >= int(min_floor.get(s, 1)) \
			and (String(known[s].get("type", "")) != "DAMAGE" or float(known[s].get("power", 0)) <= cap)
	var pools: Dictionary = a.get("skill_pools", {})
	var weights: Dictionary = a.get("pool_weights", {})
	var count = int(a.get("skills_per_enemy", 3)) + extra
	var out: Array = []
	# remaining candidates per pool
	var left := {}
	for p in pools:
		left[p] = (pools[p] as Array).filter(fits)
	var take = func(p: String) -> bool:
		var l: Array = left.get(p, [])
		if l.is_empty():
			return false
		var s = l.pop_at(RandomManager.randi() % l.size())
		if s in out:
			return false
		out.append(s)
		return true
	# guaranteed picks per pool
	var mins: Dictionary = a.get("min_from", {})
	for p in mins:
		for i in range(int(mins[p])):
			take.call(p)
	# required skill types (e.g. a Shaman always has a heal)
	for t in a.get("require_types", []):
		if out.any(func(s): return String(known[s].get("type", "")) == t):
			continue
		var cands: Array = []
		for p in left:
			for s in left[p]:
				if String(known[s].get("type", "")) == t and not s in out:
					cands.append(s)
		if not cands.is_empty():
			out.append(cands[RandomManager.randi() % cands.size()])
	# race flavour: one pick from the race's own pool
	var race_pools: Dictionary = data().get("races", {}).get(race, {}).get("skills", {})
	if not race_pools.is_empty() and out.size() < count \
			and RandomManager.randf() < float(data().get("settings", {}).get("race_skill_chance", 0.5)):
		var cands: Array = []
		for p in race_pools:
			for s in race_pools[p]:
				if fits.call(s) and not s in out:
					cands.append(s)
		if not cands.is_empty():
			out.append(cands[RandomManager.randi() % cands.size()])
	# fill by pool weight
	var guard := 0
	while out.size() < count and guard < 50:
		guard += 1
		var w := {}
		for p in left:
			if not (left[p] as Array).is_empty():
				w[p] = float(weights.get(p, 1.0))
		if w.is_empty():
			break
		take.call(_weighted(w))
	return out

# ------------------------------------------------------------------ talents

## Talent points for a regular enemy on `floor`.
static func enemy_points(floor: int) -> int:
	return int(floor * float(data().get("settings", {}).get("talent_points_per_floor", 0.5)))

static func boss_points(floor: int) -> int:
	var b = boss_cfg()
	return int(b.get("talent_points_min", 3)) + int(floor * float(b.get("talent_points_per_floor", 1)))

## Spend `points` in the archetype's branch, tier by tier. With ultimate_first,
## the tier-5 node is taken as soon as it is reachable (bosses).
## Returns the names of skills the talents granted.
static func apply_talents(c: CharacterData, archetype_id: String, points: int, ultimate_first := false, branch_override := "") -> Array:
	var t: Dictionary = get_archetype(archetype_id).get("talents", {})
	var cls = String(t.get("class", ""))
	var branch = branch_override if branch_override != "" else String(t.get("branch", ""))
	if cls == "" or branch == "" or points <= 0:
		return []
	c.talents.tree_class = cls
	c.talents.points_override = points
	var nodes = TalentManager.nodes_for(cls, branch)
	var ult: Dictionary = {}
	for n in nodes:
		if int(n.get("tier", 1)) == 5:
			ult = n
	var progressed := true
	while c.talents.available_points() > 0 and progressed:
		progressed = false
		if ultimate_first and not ult.is_empty() and c.talents.can_learn(ult.key):
			c.talents.learn(ult.key)
			progressed = true
			continue
		for n in nodes:
			if c.talents.can_learn(n.key):
				c.talents.learn(n.key)
				progressed = true
				break
	return c.talents.talent_skills()

## The tier-5 (ultimate) skill of the archetype's branch: learned, or (with
## granted = true) given outright to a boss whose points don't reach it yet.
static func ultimate_skill(c: CharacterData, archetype_id: String, branch_override := "", granted := false) -> String:
	var t: Dictionary = get_archetype(archetype_id).get("talents", {})
	var branch = branch_override if branch_override != "" else String(t.get("branch", ""))
	for n in TalentManager.nodes_for(String(t.get("class", "")), branch):
		if int(n.get("tier", 1)) == 5 and n.has("skill"):
			if c.talents.rank(n.key) > 0:
				return String(n.skill)
			if granted:
				c.add_skills([String(n.skill)])
				return String(n.skill)
	return ""

## Named boss for this location and floor, or {}.
static func named_boss(location: String, floor: int) -> Dictionary:
	var nb: Dictionary = data().get("named_bosses", {})
	for id in nb:
		if String(id).begins_with("_"):
			continue
		var e: Dictionary = nb[id]
		if String(e.get("location", "")) == location and (e.get("floors", []) as Array).has(floor):
			return e
	return {}
