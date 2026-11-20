# res://scenes/battle/core/BattleRules.gd
# Combat rules on top of the engine (data/combat.json, data/elites.json),
# shared by the battle scene (BattleOrchestrator) and headless battles
# (AutoBattler: NPC fights, the balance sim):
#   - Break: damage fills an enemy's break meter; at 100 it is Broken
#   - Link: the party gauge (ultimates spend it, Unison Strike empties it)
#   - Turn order: skills with turn_delay push enemies back / pull allies forward
#   - Elite affixes: enrage, splitting
# Usage per action:  var snap = rules.before_action(action)
#                    engine.execute_action(action)
#                    var lines = rules.after_action(action, snap)
# and at each actor's turn start: rules.on_turn_start(actor) (before the stun check).
class_name BattleRules
extends RefCounted

var ctx: BattleContext
var queue: TurnQueue
## Enemies spawned by rules (Splitting elites) waiting to join: the battle
## loop adds them (turn order, AI, UI) and clears this list.
var pending_spawns: Array[CharacterData] = []

func _init(p_ctx: BattleContext, p_queue: TurnQueue) -> void:
	ctx = p_ctx
	queue = p_queue
	ctx.rules = self
	ctx.link_gauge = min(link_max(), MomentumSystem.get_momentum() * int(_link().get("start_per_momentum", 10)))

static func cfg() -> Dictionary:
	var d = DataRegistry.get_data("combat")
	return d if d is Dictionary else {}

func _brk() -> Dictionary:
	return cfg().get("break", {})

func _link() -> Dictionary:
	return cfg().get("link", {})

func link_max() -> int:
	return int(_link().get("max", 100))

# ------------------------------------------------------------------ link

func add_link(amount: float) -> void:
	ctx.link_gauge = clamp(ctx.link_gauge + int(round(amount)), 0, link_max())

## Gauge a hero skill costs (ultimates), 0 for anything else.
func link_cost(skill: Skill) -> int:
	if skill and skill.category == "ULTIMATE":
		return int(_link().get("ultimate_cost", 50))
	return 0

## Heroes can only use what the gauge allows (ultimates).
func link_ok(actor: CharacterData, skill: Skill) -> bool:
	return not ctx.is_hero(actor) or ctx.link_gauge >= link_cost(skill)

func unison_ready() -> bool:
	return ctx.link_gauge >= int(_link().get("unison_cost", 100))

# ------------------------------------------------------------------ action hooks

func before_action(action: BattleAction) -> Dictionary:
	var hp := {}
	for c in ctx.get_heroes() + ctx.enemies:
		hp[c] = c.current_hp
	Combos.recent.clear()
	return {"hp": hp}

## Apply break, link, turn-order and affix rules. Returns combat-log lines.
func after_action(action: BattleAction, snap: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	if action == null or action.actor == null:
		return lines
	var actor = action.actor
	var hero = ctx.is_hero(actor)
	if actor.has_meta("charged_strike"):
		actor.remove_meta("charged_strike")
	var hp: Dictionary = snap.get("hp", {})
	var combo_targets := {}
	for r in Combos.recent:
		combo_targets[r.target] = true
	Combos.recent.clear()
	# --- damage to enemies: break points (weakness hits, combos) and link gauge
	var hit_any := false
	for e in ctx.enemies:
		var before = int(hp.get(e, e.current_hp))
		var dealt = before - max(0, e.current_hp)
		if dealt <= 0 or not hero:
			continue
		hit_any = true
		if e.is_alive() and not e.get_meta("broken", false):
			var pts := 0
			if _weak_hit(action, e):
				pts += 1
				if combo_targets.has(e):
					pts += int(_brk().get("combo_bonus", 1))
			if pts > 0:
				var meter = int(e.get_meta("break_meter", 0)) + pts
				e.set_meta("break_meter", meter)
				if meter >= break_max(e):
					lines.append(break_enemy(e))
	if hero:
		if hit_any:   # split across the party so the gauge fills at a similar pace
			add_link(float(_link().get("gain_per_hit", 4)) / max(1, ctx.get_heroes().size()))
		add_link(float(_link().get("gain_combo", 15)) * combo_targets.size())
	# --- skills: link costs, LINK skills, turn order
	if action.type == BattleAction.ActionType.SKILL and action.skill_data:
		var s = action.skill_data
		if hero and link_cost(s) > 0:
			add_link(-link_cost(s))
		if hero and s.category == "LINK":
			add_link(_link().get("gain_link_skill", 15))
			var nxt = _next_hero_after(actor)
			if nxt:
				queue.haste(nxt)
				lines.append("%s's opening lets %s act next!" % [actor.name, nxt.name])
		if s.turn_delay != 0:
			for t in action.targets:
				if t == null or not t.is_alive():
					continue
				if s.turn_delay > 0 and not ctx.is_hero(t):
					queue.delay(t, s.turn_delay)
					lines.append("%s is knocked back in the turn order." % t.name)
				elif s.turn_delay < 0 and ctx.is_hero(t) and t != actor:
					queue.haste(t)
					lines.append("%s is spurred forward!" % t.name)
	elif action.type == BattleAction.ActionType.UNISON:
		add_link(-int(_link().get("unison_cost", 100)))
	# --- elite affixes
	for e in ctx.enemies.duplicate():
		lines.append_array(_affix_checks(e, int(hp.get(e, e.current_hp))))
	return lines.filter(func(l): return l != "")

## Weakness hits needed to Break `e` (grows each time it is broken).
static func break_max(e: CharacterData) -> int:
	var b: Dictionary = cfg().get("break", {})
	var base = int(b.get("regular_hits", 2))
	if e.character_class.begins_with("King") or e.has_meta("boss_signature"):
		base = int(b.get("boss_hits", 4))
	elif e.has_meta("elite_affix") or e.has_meta("encounter"):
		base = int(b.get("elite_hits", 3))
	return base + int(e.get_meta("times_broken", 0)) * int(b.get("growth_per_break", 1))

func _is_boss(e: CharacterData) -> bool:
	return e.character_class.begins_with("King") or e.has_meta("boss_signature")

## Did this action hit a weakness of `e` (damage type or element)?
func _weak_hit(action: BattleAction, e: CharacterData) -> bool:
	var physical := true
	var dt := -1
	var elements: Array = []
	if action.type == BattleAction.ActionType.SKILL and action.skill_data:
		physical = action.skill_data.ability_type == Skill.AbilityType.PHYSICAL
		dt = action.skill_data.damage_type
		for el in action.skill_data.elements:
			elements.append(Skill.ElementType.keys()[el])
	if physical and DamageTypes.multiplier(e, DamageTypes.attack_type(action.actor, dt)) > 1.05:
		return true
	if e.elemental_resistances:
		for n in elements:
			if ElementalDamage.Element.has(n) and e.elemental_resistances.get_total_weakness(ElementalDamage.Element[n]) > 0.0:
				return true
	return false

func break_enemy(e: CharacterData) -> String:
	e.set_meta("broken", true)
	e.set_meta("break_meter", 0)
	e.set_meta("times_broken", int(e.get_meta("times_broken", 0)) + 1)
	e.is_stunned = true            # loses its next turn
	var extra = ""
	if e.has_meta("charging"):
		e.remove_meta("charging")
		extra = " Its charge is broken!"
	if int(e.get_meta("barrier", 0)) > 0:
		e.set_meta("barrier", 0)
		extra += " The barrier shatters!"
	ctx.intents.erase(e)
	add_link(_brk().get("link_gain", 25))
	return "[b]BREAK![/b] %s is staggered and loses its next turn.%s" % [e.name, extra]

func _next_hero_after(actor: CharacterData) -> CharacterData:
	for c in queue.queue:
		if c != actor and ctx.is_hero(c) and c.is_alive():
			return c
	return null

# ------------------------------------------------------------------ turn start

## Call at the start of `actor`'s turn, before the stun check. Returns a log line.
func on_turn_start(actor: CharacterData) -> String:
	if ctx.is_hero(actor):
		return ""
	if actor.get_meta("broken", false):
		actor.set_meta("broken", false)   # this skipped turn is the recovery
		return "%s recovers from the break." % actor.name
	return ""

# ------------------------------------------------------------------ elites

func _affix_checks(e: CharacterData, hp_before: int) -> Array[String]:
	var out: Array[String] = []
	var aff = String(e.get_meta("elite_affix", ""))
	if aff == "":
		return out
	var a: Dictionary = EliteAffixes.affix(aff)
	match aff:
		"enraged":
			if e.is_alive() and not e.get_meta("enraged_done", false) and float(e.current_hp) / max(1, e.max_hp) < float(a.get("threshold", 0.5)):
				e.set_meta("enraged_done", true)
				e.damage_multiplier *= float(a.get("damage_mult", 1.35))
				e.apply_status_effect(Skill.StatusEffect.ENRAGED, 99)
				out.append("[color=orange]%s flies into a rage![/color]" % e.name)
		"splitting":
			if not e.is_alive() and hp_before > 0 and not e.get_meta("split_done", false):
				e.set_meta("split_done", true)
				for i in range(int(a.get("count", 2))):
					var child = EliteAffixes.make_fragment(e, float(a.get("hp_frac", 0.35)), i + 1, ctx.current_floor)
					if child:
						pending_spawns.append(child)
				out.append("[color=orange]%s splits apart![/color]" % e.name)
	return out

## Hand spawned enemies to the battle: adds them to the context and the turn
## order, and returns them so the caller can wire AI and UI.
func take_spawns() -> Array[CharacterData]:
	var out: Array[CharacterData] = pending_spawns.duplicate()
	pending_spawns.clear()
	for c in out:
		ctx.enemies.append(c)
		queue.join(c, false)
	return out

## Damage types and elements `e` is weak to: ["Blunt", "Fire"].
static func weaknesses(e: CharacterData) -> Array:
	var out: Array = []
	for t in DamageTypes.Type.values():
		if DamageTypes.multiplier(e, t) > 1.05:
			out.append(DamageTypes.Type.keys()[t].capitalize())
	if e.elemental_resistances:
		for n in ElementalDamage.Element.keys():
			if n in ["NONE", "PHYSICAL"]:
				continue
			if e.elemental_resistances.get_total_weakness(ElementalDamage.Element[n]) > 0.0:
				out.append(n.capitalize())
	return out

# ------------------------------------------------------------------ descriptions

## "Fireball → Mira", "⚠ CHARGING Avalanche Slam (everyone)", "" when unknown.
static func describe_intent(e: CharacterData, intents: Dictionary = {}) -> String:
	if not e.is_alive():
		return ""
	if e.get_meta("broken", false):
		return "[color=#ffd166]BROKEN - loses its turn[/color]"
	if e.has_meta("charging"):
		return "[color=#ff6b6b]⚠ CHARGING %s[/color]" % e.get_meta("charging")
	var a = intents.get(e, null)
	if not (a is BattleAction):
		return ""
	var who = ""
	if not a.targets.is_empty() and a.targets[0] != null:
		who = a.targets[0].name.get_slice(" ", 0)
	match a.type:
		BattleAction.ActionType.ATTACK:
			return "Attack → %s" % who
		BattleAction.ActionType.DEFEND:
			return "Defend"
		BattleAction.ActionType.CHARGE:
			return "[color=#ff6b6b]⚠ Gathering power[/color]"
		BattleAction.ActionType.ITEM:
			return "Item: %s" % a.item_data.display_name
		BattleAction.ActionType.SKILL:
			var s: Skill = a.skill_data
			var tgt = who
			if s.target == Skill.TargetType.ALL_ENEMIES:
				tgt = "everyone"
			elif s.target in [Skill.TargetType.SELF, Skill.TargetType.ALL_ALLIES, Skill.TargetType.ALLY]:
				tgt = "allies" if s.target == Skill.TargetType.ALL_ALLIES else (who if who != "" else "self")
			var col = "#ff9f6b" if s.type in [Skill.SkillType.DAMAGE, Skill.SkillType.DRAIN] else "#b8c0ff"
			return "[color=%s]%s → %s[/color]" % [col, s.name, tgt]
	return ""
