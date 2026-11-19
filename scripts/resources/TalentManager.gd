# res://scripts/resources/TalentManager.gd
# Per-character talent trees. Data: data/talents.json (design: docs/design/TALENTS.md).
#
# Rules
#   - 1 point per level from settings.first_point_level (level 2): points = level - 1
#   - Each class has 3 branches of 5 tiers. A node in tier T needs
#     settings.tier_points[T-1] points already spent in that branch.
#   - Nodes have max_rank ranks. A node with "skill" unlocks that active skill.
#   - Respec refunds everything for settings.respec_gold_per_level x level copper.
#
# Effects (each node's "effects" list; numbers are per rank):
#   {"type": "stats", "stats": {"vitality": 2, "dodge": 0.02, ...}}
#   {"type": "damage", "mult": 0.05, <conditions>}        +5% damage dealt
#   {"type": "defense", "reduce": 0.04, <conditions>}     -4% damage taken
#   {"type": "heal_bonus", "mult": 0.06}                  +6% healing done
#   {"type": "lifesteal", "fraction": 0.03, <conditions>} heal 3% of damage dealt
#   {"type": "skill", "skill": "Iaido", "power": 10, "cooldown": -1, "duration": 1, "mp_cost": -5, "sp_cost": -5}
#   {"type": "combo", "combo": "open_wound", "bonus": 0.1} combo multiplier +0.1
#   {"type": "status_chance", "chance": 0.05}             damage-skill status riders +5%
#   {"type": "regen", "hp": 0.01, "mp": 0.02, "sp": 0.02} per turn, fraction of max
# Conditions (all optional, all must hold):
#   with (weapon id/type in main or off hand), element / elements (any), damage_type,
#   ability (PHYSICAL/MAGICAL), skill, category (BASIC/ADVANCED/ULTIMATE...),
#   target_status, user_hp_below, target_hp_below, weak_spot (true)
#
# Heroes and enemies share this code; enemies simply have no ranks yet.
class_name TalentManager
extends RefCounted

static var _data: Dictionary = {}

var character: CharacterData
var ranks: Dictionary = {}          # "Branch/node" -> rank
var _fx: Dictionary = {}            # aggregated effects, rebuilt on change

func _init(owner_character: CharacterData):
	character = owner_character
	_rebuild()

# ------------------------------------------------------------------ data

static func data() -> Dictionary:
	if _data.is_empty():
		var f = FileAccess.open("res://data/talents.json", FileAccess.READ)
		var d = JSON.parse_string(f.get_as_text()) if f else null
		_data = d if d is Dictionary else {}
		if _data.is_empty():
			push_error("TalentManager: data/talents.json missing or invalid")
			_data = {"settings": {}, "branches": {}, "nodes": {}}
	return _data

static func settings() -> Dictionary:
	return data().get("settings", {})

## {branch_id: {name, description, order}} for a class, sorted by order.
static func branches_for(cls: String) -> Array:
	var b: Dictionary = data().get("branches", {}).get(cls, {})
	var ids = b.keys()
	ids.sort_custom(func(x, y): return int(b[x].get("order", 0)) < int(b[y].get("order", 0)))
	var out: Array = []
	for id in ids:
		var e = b[id].duplicate()
		e["id"] = id
		out.append(e)
	return out

## Nodes of one branch sorted by tier: [{id, key, name, tier, max_rank, ...}]
static func nodes_for(cls: String, branch: String) -> Array:
	var n: Dictionary = data().get("nodes", {}).get(cls, {}).get(branch, {})
	var out: Array = []
	for id in n:
		if String(id).begins_with("_"):
			continue
		var e = n[id].duplicate()
		e["id"] = id
		e["key"] = "%s/%s" % [branch, id]
		e["branch"] = branch
		out.append(e)
	out.sort_custom(func(a, b): return int(a.get("tier", 1)) < int(b.get("tier", 1)))
	return out

func node(key: String) -> Dictionary:
	var parts = key.split("/")
	if parts.size() != 2:
		return {}
	var n = data().get("nodes", {}).get(character.character_class, {}).get(parts[0], {}).get(parts[1], {})
	if n.is_empty():
		return {}
	var e = n.duplicate()
	e["id"] = parts[1]
	e["key"] = key
	e["branch"] = parts[0]
	return e

# ------------------------------------------------------------------ points

func total_points() -> int:
	var first = int(settings().get("first_point_level", 2))
	return max(0, (character.level - first + 1) * int(settings().get("points_per_level", 1)))

func spent_points() -> int:
	var s := 0
	for k in ranks:
		s += int(ranks[k])
	return s

func available_points() -> int:
	return total_points() - spent_points()

func spent_in_branch(branch: String) -> int:
	var s := 0
	for k in ranks:
		if String(k).begins_with(branch + "/"):
			s += int(ranks[k])
	return s

func rank(key: String) -> int:
	return int(ranks.get(key, 0))

func tier_requirement(tier: int) -> int:
	var t: Array = settings().get("tier_points", [0, 2, 4, 6, 8])
	return int(t[clamp(tier - 1, 0, t.size() - 1)])

## "" if the node can take another rank now, else the reason.
func why_not(key: String) -> String:
	var n = node(key)
	if n.is_empty():
		return "Unknown talent."
	if rank(key) >= int(n.get("max_rank", 1)):
		return "Already at max rank."
	if available_points() <= 0:
		return "No talent points left (1 per level)."
	var need = tier_requirement(int(n.get("tier", 1)))
	var have = spent_in_branch(n.branch)
	# points spent in this node itself don't count toward its own tier
	if have - rank(key) < need:
		return "Needs %d points in this branch (has %d)." % [need, have - rank(key)]
	return ""

func can_learn(key: String) -> bool:
	return why_not(key) == ""

func learn(key: String) -> bool:
	if not can_learn(key):
		return false
	ranks[key] = rank(key) + 1
	var n = node(key)
	if n.has("skill") and rank(key) == 1:
		# keep the current loadout (implicitly "first N known" if never chosen)
		if character.equipped_skills.is_empty():
			character.equipped_skills = character.get_battle_skills().duplicate()
		character.add_skills([String(n.skill)])
		if character.equipped_skills.size() < loadout_size() and not String(n.skill) in character.equipped_skills:
			character.equipped_skills.append(String(n.skill))
	_rebuild()
	_apply()
	return true

func respec_cost() -> int:
	return int(settings().get("respec_gold_per_level", 100)) * character.level

## Refund every point. Pays respec_cost() unless free = true. Returns false if unaffordable.
func respec(free := false) -> bool:
	if not free:
		if character.currency.copper < respec_cost():
			return false
		character.currency.subtract(respec_cost())
	for skill_name in talent_skills():
		character.remove_skill(skill_name)
		character.equipped_skills.erase(skill_name)
	ranks.clear()
	_rebuild()
	_apply()
	return true

## Active skills unlocked by learned nodes.
func talent_skills() -> Array:
	var out: Array = []
	for key in ranks:
		if int(ranks[key]) > 0:
			var n = node(key)
			if n.has("skill"):
				out.append(String(n.skill))
	return out

static func loadout_size() -> int:
	return int(settings().get("loadout_size", 6))

# ------------------------------------------------------------------ save

func get_save_data() -> Dictionary:
	return ranks.duplicate()

func load_save_data(saved: Dictionary) -> void:
	ranks.clear()
	for k in saved:
		if not node(k).is_empty():
			ranks[k] = int(saved[k])
	# skills granted by talents (older saves may not have them yet)
	var missing = talent_skills().filter(func(s): return not character.skills.has(s))
	if not missing.is_empty():
		character.add_skills(missing)
	_rebuild()
	_apply()

# ------------------------------------------------------------------ effects

func _rebuild() -> void:
	_fx = {"stats": {}, "damage": [], "defense": [], "heal_bonus": 0.0, "lifesteal": [],
		"skill": {}, "combo": {}, "status_chance": 0.0, "regen": {"hp": 0.0, "mp": 0.0, "sp": 0.0}}
	if character == null or character.character_class == "":
		return
	for key in ranks:
		var r = int(ranks[key])
		if r <= 0:
			continue
		for e in node(key).get("effects", []):
			_add_effect(e, r)

func _add_effect(e: Dictionary, r: int) -> void:
	match String(e.get("type", "")):
		"stats":
			for s in e.get("stats", {}):
				_fx.stats[s] = _fx.stats.get(s, 0.0) + float(e.stats[s]) * r
		"damage":
			var d = e.duplicate(); d["mult"] = float(e.get("mult", 0.0)) * r
			_fx.damage.append(d)
		"defense":
			var d = e.duplicate(); d["reduce"] = float(e.get("reduce", 0.0)) * r
			_fx.defense.append(d)
		"heal_bonus":
			_fx.heal_bonus += float(e.get("mult", 0.0)) * r
		"lifesteal":
			var d = e.duplicate(); d["fraction"] = float(e.get("fraction", 0.0)) * r
			_fx.lifesteal.append(d)
		"skill":
			var name = String(e.get("skill", ""))
			var m: Dictionary = _fx.skill.get(name, {})
			for f in ["power", "cooldown", "duration", "mp_cost", "sp_cost"]:
				if e.has(f):
					m[f] = m.get(f, 0) + int(e[f]) * r
			_fx.skill[name] = m
		"combo":
			var c = String(e.get("combo", ""))
			_fx.combo[c] = _fx.combo.get(c, 0.0) + float(e.get("bonus", 0.0)) * r
		"status_chance":
			_fx.status_chance += float(e.get("chance", 0.0)) * r
		"regen":
			for p in ["hp", "mp", "sp"]:
				_fx.regen[p] += float(e.get(p, 0.0)) * r

## Push changes to stats and skill instances.
func _apply() -> void:
	character.refresh_talent_skill_mods()
	character.calculate_secondary_attributes()

func stat_bonuses() -> Dictionary:
	return _fx.get("stats", {})

func skill_mods(skill_name: String) -> Dictionary:
	return _fx.get("skill", {}).get(skill_name, {})

func combo_bonus(combo_id: String) -> float:
	return float(_fx.get("combo", {}).get(combo_id, 0.0))

func status_chance_bonus() -> float:
	return float(_fx.get("status_chance", 0.0))

func heal_bonus() -> float:
	return float(_fx.get("heal_bonus", 0.0))

## Hit context: {physical, damage_type, elements, skill, category, target, attacker}
func damage_mult(ctx: Dictionary) -> float:
	var m := 1.0
	for e in _fx.get("damage", []):
		if _matches(e, ctx, character, ctx.get("target")):
			m += float(e.mult)
	return m

func defense_mult(ctx: Dictionary) -> float:
	var reduce := 0.0
	for e in _fx.get("defense", []):
		if _matches(e, ctx, ctx.get("attacker"), character):
			reduce += float(e.reduce)
	return max(0.3, 1.0 - reduce)     # talents never reduce damage taken below 30%

func lifesteal(ctx: Dictionary) -> float:
	var f := 0.0
	for e in _fx.get("lifesteal", []):
		if _matches(e, ctx, character, ctx.get("target")):
			f += float(e.fraction)
	return f

## Turn-start regeneration. Returns a combat-log line ("" if none).
func on_turn_start() -> String:
	var r: Dictionary = _fx.get("regen", {})
	var parts: Array = []
	var hp = int(round(character.max_hp * float(r.get("hp", 0.0))))
	var mp = int(round(character.max_mp * float(r.get("mp", 0.0))))
	var sp = int(round(character.max_sp * float(r.get("sp", 0.0))))
	if hp > 0 and character.current_hp < character.max_hp:
		parts.append("%d HP" % character.heal(hp))
	if mp > 0 and character.current_mp < character.max_mp:
		parts.append("%d MP" % character.restore_mp(mp))
	if sp > 0 and character.current_sp < character.max_sp:
		parts.append("%d SP" % character.restore_sp(sp))
	return ("%s's talents restore %s\n" % [character.name, ", ".join(parts)]) if not parts.is_empty() else ""

static func _matches(e: Dictionary, ctx: Dictionary, user: CharacterData, target) -> bool:
	if e.has("with"):
		var found := false
		if user:
			for slot in ["main_hand", "off_hand"]:
				var it = user.equipment.get(slot)
				if it is Equipment and (it.key == e.with or it.type == e.with):
					found = true
		if not found:
			return false
	if e.has("ability"):
		if (e.ability == "PHYSICAL") != bool(ctx.get("physical", false)):
			return false
	if e.has("damage_type"):
		var dt = int(ctx.get("damage_type", -1))
		if dt < 0 or DamageTypes.Type.keys()[dt] != e.damage_type:
			return false
	var els: Array = []
	if e.has("element"):
		els.append(e.element)
	els.append_array(e.get("elements", []))
	if not els.is_empty():
		var any := false
		for x in ctx.get("elements", []):
			if x in els:
				any = true
		if not any:
			return false
	if e.has("skill") and String(ctx.get("skill", "")) != e.skill:
		return false
	if e.has("category") and String(ctx.get("category", "")) != e.category:
		return false
	if e.has("user_hp_below") and (user == null or float(user.current_hp) / max(1, user.max_hp) >= float(e.user_hp_below)):
		return false
	if e.has("target_hp_below") and (target == null or float(target.current_hp) / max(1, target.max_hp) >= float(e.target_hp_below)):
		return false
	if e.has("target_status"):
		if target == null or target.status_manager == null or not Skill.StatusEffect.has(e.target_status) \
				or not target.status_manager.has_effect(Skill.StatusEffect[e.target_status]):
			return false
	if bool(e.get("weak_spot", false)):
		var dt2 = int(ctx.get("damage_type", -1))
		if target == null or dt2 < 0 or DamageTypes.multiplier(target, dt2) <= 1.01:
			return false
	return true

## Context for a hit by `user` (skill may be null for a basic attack).
static func hit_context(user: CharacterData, target: CharacterData, physical: bool, skill = null, damage_type: int = -1) -> Dictionary:
	var els: Array = []
	var cat := ""
	var name := ""
	if skill:
		for e in skill.elements:
			var n = Skill.ElementType.keys()[e]
			if n != "NONE" and n != "PHYSICAL":
				els.append(n)
		cat = String(skill.category)
		name = skill.name
	return {"physical": physical, "elements": els, "skill": name, "category": cat, "target": target, "attacker": user,
		"damage_type": DamageTypes.attack_type(user, damage_type) if physical else -1}

## Human-readable lines for a node's effects at `r` ranks (UI).
static func describe_effects(n: Dictionary, r: int) -> Array:
	var out: Array = []
	r = max(1, r)
	for e in n.get("effects", []):
		var cond = _describe_conditions(e)
		match String(e.get("type", "")):
			"stats":
				var bits: Array = []
				for s in e.stats:
					var v = float(e.stats[s]) * r
					bits.append(("+%d%% " % int(round(v * 100)) if abs(v) < 1.0 else "+%d " % int(v)) + String(s).replace("_", " "))
				out.append(", ".join(bits))
			"damage": out.append("+%d%% damage%s" % [int(round(float(e.mult) * r * 100)), cond])
			"defense": out.append("-%d%% damage taken%s" % [int(round(float(e.reduce) * r * 100)), cond])
			"heal_bonus": out.append("+%d%% healing done" % int(round(float(e.mult) * r * 100)))
			"lifesteal": out.append("heal %d%% of damage dealt%s" % [int(round(float(e.fraction) * r * 100)), cond])
			"skill":
				var bits: Array = []
				for f in ["power", "cooldown", "duration", "mp_cost", "sp_cost"]:
					if e.has(f):
						bits.append("%+d %s" % [int(e[f]) * r, f.replace("_", " ")])
				out.append("%s: %s" % [e.skill, ", ".join(bits)])
			"combo": out.append("%s combo +%.2fx" % [String(e.combo).replace("_", " ").capitalize(), float(e.bonus) * r])
			"status_chance": out.append("+%d%% chance for damage skills to apply their status" % int(round(float(e.chance) * r * 100)))
			"regen":
				var bits: Array = []
				for p in ["hp", "mp", "sp"]:
					if float(e.get(p, 0)) > 0:
						bits.append("%d%% %s" % [int(round(float(e[p]) * r * 100)), p.to_upper()])
				out.append("regenerate %s each turn" % ", ".join(bits))
	return out

static func _describe_conditions(e: Dictionary) -> String:
	var c: Array = []
	if e.has("with"): c.append("with a %s" % String(e.with).replace("_", " "))
	if e.has("element"): c.append("with %s" % String(e.element).capitalize())
	if e.has("elements"): c.append("with %s" % "/".join(e.elements.map(func(x): return String(x).capitalize())))
	if e.has("damage_type"): c.append("with %s hits" % String(e.damage_type).capitalize())
	if e.has("ability"): c.append("with %s attacks" % String(e.ability).to_lower())
	if e.has("skill"): c.append("with %s" % e.skill)
	if e.has("category"): c.append("with %s skills" % String(e.category).to_lower())
	if e.has("target_status"): c.append("vs %s targets" % String(e.target_status).to_lower())
	if e.has("user_hp_below"): c.append("below %d%% HP" % int(float(e.user_hp_below) * 100))
	if e.has("target_hp_below"): c.append("vs targets below %d%% HP" % int(float(e.target_hp_below) * 100))
	if bool(e.get("weak_spot", false)): c.append("on weak spots")
	return (" " + " ".join(c)) if not c.is_empty() else ""
