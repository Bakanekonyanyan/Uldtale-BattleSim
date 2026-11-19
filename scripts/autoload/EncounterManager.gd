# res://scripts/autoload/EncounterManager.gd
# Expedition encounters (data/encounters.json).
#
# SceneManager asks roll() before each wave; a hit is handed to the battle
# (BattleOrchestrator.set_encounter), which calls begin() before the first
# turn. Encounter people are real Guild adventurers (AdventurerManager):
#   helper       - a friend fights beside you (from the start or mid-battle)
#   wounded      - give a potion (rapport up) or refuse (down)
#   rival_theft  - they take part of your banked loot; confront (fight them
#                  right after the wave) or let it go
#   saboteur     - an enemy of yours joins the wave mid-battle, or attacks
#                  when you think the wave is won
# finish() applies the consequences when the battle ends.
extends Node

var cfg: Dictionary = {}
var _count: int = 0          # encounters this expedition

func _ready():
	var f = FileAccess.open("res://data/encounters.json", FileAccess.READ)
	var d = JSON.parse_string(f.get_as_text()) if f else null
	cfg = d if d is Dictionary else {}
	GameEvents.expedition_started.connect(func(_l, _f): _count = 0)

func _t(type: String) -> Dictionary:
	return cfg.get("types", {}).get(type, {})

func _fmt(text: String, npc: Dictionary, location := "") -> String:
	return text.format({"name": npc.get("name", "Someone"), "location": LocationManager.get_display_name(location) if location != "" else "the wilds"})

func _rangei(v) -> int:
	return RandomManager.randi_range(int(v[0]), int(v[1])) if v is Array and v.size() == 2 else int(v)

func _pick_mode(modes: Dictionary) -> String:
	var total := 0.0
	for k in modes:
		total += float(modes[k])
	var r = RandomManager.randf() * total
	for k in modes:
		r -= float(modes[k])
		if r <= 0.0:
			return k
	return modes.keys()[0] if not modes.is_empty() else "start"

# ------------------------------------------------------------------ rolling

## Who could appear for an encounter type (active, not in your party).
func candidates(player: CharacterData, type: String) -> Array:
	var c = _t(type)
	var out: Array = []
	for n in AdventurerManager.active(player):
		if String(n.status) == "party" or PartyManager.is_member(player, int(n.id)):
			continue
		var r = int(n.rapport)
		var rival = "Rival" in AdventurerManager.tags(n)
		match type:
			"helper":
				if r >= int(c.get("min_rapport", 20)):
					out.append(n)
			"wounded":
				out.append(n)
			"rival_theft":
				if rival or r <= int(c.get("max_rapport", 10)) and (AdventurerManager.trait_mult(n, "compete") > 1.0):
					out.append(n)
			"saboteur":
				var schemer = n.traits.any(func(t): return t in c.get("traits_any", []))
				if schemer and (r <= int(c.get("max_rapport", -10)) or (c.get("rival_counts", true) and rival)):
					out.append(n)
	return out

## Roll an encounter for the wave about to start. {} = nothing happens.
## force_type is for tests and debugging.
func roll(battle_data: Dictionary, force_type := "") -> Dictionary:
	var player: CharacterData = battle_data.get("player_character")
	if player == null:
		return {}
	var st: Dictionary = cfg.get("settings", {})
	var wave = int(battle_data.get("current_wave", 1))
	if force_type == "":
		if _count >= int(st.get("max_per_expedition", 2)):
			return {}
		if wave in st.get("skip_waves", [1]) or (battle_data.get("is_boss_fight", false) and not st.get("allow_boss_waves", false)):
			return {}
		if RandomManager.randf() >= float(st.get("chance_per_wave", 0.22)):
			return {}
	var weights := {}
	for type in cfg.get("types", {}):
		if force_type != "" and type != force_type:
			continue
		if type == "rival_theft" and _t(type).get("needs_banked_loot", true) and int(MomentumSystem.momentum_loot_accumulated.get("currency", 0)) <= 0:
			continue
		if type == "wounded" and battle_data.get("is_boss_fight", false):
			continue
		if not candidates(player, type).is_empty():
			weights[type] = float(_t(type).get("weight", 1))
	if weights.is_empty():
		return {}
	var type = _pick_mode(weights)
	var pool = candidates(player, type)
	var npc: Dictionary = pool[RandomManager.randi() % pool.size()]
	_count += 1
	var enc := {"type": type, "npc_id": int(npc.id), "location": DungeonStateManager.current_location}
	match type:
		"helper", "saboteur":
			enc.mode = _pick_mode(_t(type).get("modes", {"start": 1.0}))
			enc.round = _rangei(_t(type).get("mid_round", [2, 3]))
	return enc

# ------------------------------------------------------------------ in battle

## Build the NPC as a combatant. Saboteurs are enemies (scaled down a little).
func build_combatant(player: CharacterData, npc: Dictionary, as_enemy: bool) -> CharacterData:
	var spec = npc.duplicate()
	spec.level = max(int(npc.level), player.level - 1) if not as_enemy else max(1, max(int(npc.level), player.level))
	var c = AutoBattler.build_hero(spec)
	c.set_meta("npc_id", int(npc.id))
	if as_enemy:
		var s = _t("saboteur")
		c.is_player = false
		c.hp_multiplier = float(s.get("hp_mult", 1.0))
		c.damage_multiplier = float(s.get("damage_mult", 0.75))
		c.set_meta("ai_role", {"Cleric": "healer", "Druid": "healer", "Kannagi": "healer", "Elementalist": "caster", "Necromancer": "controller", "Beastmaster": "controller", "Paladin": "tank"}.get(String(npc.cls), "skirmisher"))
		c.calculate_secondary_attributes()
		c.current_hp = c.max_hp
		c.current_mp = c.max_mp
		c.current_sp = c.max_sp
	else:
		c.set_meta("auto", true)   # helpers fight on their own
	return c

## Run the encounter's opening. Returns what the battle should do:
## {log: [lines], allies_now: [], pending: [{side, chars, trigger, round, text}]}
## `parent` hosts the choice dialog.
func begin(enc: Dictionary, player: CharacterData, parent: Node) -> Dictionary:
	var out := {"log": [], "allies_now": [], "pending": []}
	var npc = AdventurerManager.get_npc(player, int(enc.get("npc_id", -1)))
	if npc.is_empty():
		return out
	var c = _t(String(enc.type))
	var loc = String(enc.get("location", ""))
	match String(enc.type):
		"helper":
			var ally = build_combatant(player, npc, false)
			if String(enc.get("mode", "start")) == "start":
				await choice(parent, "A friendly face", _fmt(String(c.get("text_start", "")), npc), [["ok", "Welcome aboard"]])
				out.allies_now.append(ally)
			else:
				out.pending.append({"side": "ally", "chars": [ally], "trigger": "round", "round": int(enc.get("round", 2)), "text": _fmt(String(c.get("text_mid", "")), npc)})
		"wounded":
			var item_id = String(c.get("item", "health_potion"))
			var has = player.inventory.get_quantity(item_id) > 0
			var opts = [["give", "Give a %s" % ItemManager.get_item(item_id).display_name]] if has else []
			opts.append(["refuse", "Sorry, I can't" if has else "I have nothing to give"])
			var pick = await choice(parent, "A wounded adventurer", _fmt(String(c.get("text", "")), npc), opts)
			var day = WorldClock.day(player)
			if pick == "give":
				player.inventory.remove_item(item_id, 1)
				AdventurerManager._set_rapport(npc, int(c.get("give_rapport", 10)))
				AdventurerManager._history(npc, day, "%s shared a potion when they were bleeding out." % player.name)
				out.log.append("%s thanks you warmly (+%d rapport)." % [npc.name, int(c.get("give_rapport", 10))])
			else:
				var d = int(c.get("refuse_rapport", -4)) if has else 0
				AdventurerManager._set_rapport(npc, d)
				out.log.append("You leave %s behind.%s" % [npc.name, " (%d rapport)" % d if d != 0 else ""])
		"rival_theft":
			var banked: Dictionary = MomentumSystem.momentum_loot_accumulated
			var frac = RandomManager.randf_range(float(c.get("steal_fraction", [0.3, 0.5])[0]), float(c.get("steal_fraction", [0.3, 0.5])[1]))
			var stolen = int(int(banked.get("currency", 0)) * frac)
			banked.currency = int(banked.get("currency", 0)) - stolen
			var pick = await choice(parent, "Thief!", _fmt(String(c.get("text", "")), npc) + "\n\n(%s of your banked loot is gone.)" % Currency.format_copper(stolen),
				[["confront", "Confront them (fight after this wave)"], ["let_go", "Let it go"]])
			npc.rivalry = int(npc.get("rivalry", 0)) + 1
			if pick == "confront":
				var rival = build_combatant(player, npc, true)
				rival.set_meta("encounter", "rival_theft")
				rival.set_meta("stolen", stolen)
				out.pending.append({"side": "enemy", "chars": [rival], "trigger": "victory", "text": "%s stands their ground, purse in hand. Fight!" % npc.name})
			else:
				AdventurerManager._set_rapport(npc, int(c.get("let_go_rapport", -3)))
				WorldClock.add_news(player, _fmt(String(c.get("news", "")), npc, loc), "rival")
				out.log.append("%s saunters off with %s." % [npc.name, Currency.format_copper(stolen)])
		"saboteur":
			var foe = build_combatant(player, npc, true)
			foe.set_meta("encounter", "saboteur")
			if RandomManager.randf() < float(c.get("warning_chance", 0.4)):
				out.log.append(_fmt(String(c.get("warning", "")), npc))
			if String(enc.get("mode", "mid")) == "after":
				out.pending.append({"side": "enemy", "chars": [foe], "trigger": "victory", "text": _fmt(String(c.get("text_after", "")), npc)})
			else:
				out.pending.append({"side": "enemy", "chars": [foe], "trigger": "round", "round": int(enc.get("round", 2)), "text": _fmt(String(c.get("text_mid", "")), npc)})
	return out

## Consequences when the battle ends. `joined` = encounter combatants that
## actually took part.
func finish(enc: Dictionary, player: CharacterData, won: bool, joined: Array) -> Array:
	var lines: Array = []
	var npc = AdventurerManager.get_npc(player, int(enc.get("npc_id", -1)))
	if npc.is_empty():
		return lines
	var c = _t(String(enc.type))
	var loc = String(enc.get("location", ""))
	var day = WorldClock.day(player)
	match String(enc.type):
		"helper":
			if joined.is_empty():
				return lines
			AdventurerManager._set_rapport(npc, int(c.get("rapport_after", 3)))
			AdventurerManager._history(npc, day, "Fought beside %s in %s." % [player.name, LocationManager.get_display_name(loc)])
			WorldClock.add_news(player, _fmt(String(c.get("news", "")), npc, loc), "adventurer")
			lines.append("%s salutes and heads off (+%d rapport)." % [npc.name, int(c.get("rapport_after", 3))])
		"rival_theft", "saboteur":
			if joined.is_empty():
				return lines
			if won:
				var sab = _t("saboteur")
				npc.status = "injured"
				npc.job = {}
				npc.injured_until = day + _rangei(sab.get("injury_days", [3, 6]))
				npc.rivalry = int(npc.get("rivalry", 0)) + 1
				if String(enc.type) == "saboteur":
					AdventurerManager._set_rapport(npc, int(sab.get("beaten_rapport", -8)))
					AdventurerManager._history(npc, day, "Ambushed %s and was beaten." % player.name)
					WorldClock.add_news(player, _fmt(String(sab.get("news_beaten", "")), npc, loc), "rival")
					lines.append("%s limps away, beaten." % npc.name)
				else:
					var stolen = int(joined[0].get_meta("stolen", 0))
					MomentumSystem.momentum_loot_accumulated.currency = int(MomentumSystem.momentum_loot_accumulated.get("currency", 0)) + stolen
					AdventurerManager._set_rapport(npc, int(c.get("confront_win_rapport", -6)))
					AdventurerManager._history(npc, day, "Was made to give back what they stole from %s." % player.name)
					lines.append("You take back your %s." % Currency.format_copper(stolen))
			else:
				AdventurerManager._history(npc, day, "Got the better of %s in %s." % [player.name, LocationManager.get_display_name(loc)])
				WorldClock.add_news(player, _fmt(String(_t("saboteur").get("news_lost", "")), npc, loc), "rival")
	return lines

# ------------------------------------------------------------------ dialog

## A small choice dialog. options = [[id, label], ...]. Returns the chosen id.
## In headless runs (no rendering) or with auto_choice set it answers at once.
var auto_choice: String = ""
signal _chosen(id: String)

func choice(parent: Node, title: String, text: String, options: Array) -> String:
	if auto_choice != "":
		for o in options:
			if o[0] == auto_choice:
				return auto_choice
		return String(options[0][0])
	var layer = CanvasLayer.new()
	layer.layer = 55
	parent.add_child(layer)
	var dim = ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.size = Vector2(1200, 720)
	layer.add_child(dim)
	var panel = Panel.new()
	panel.position = Vector2(300, 200)
	panel.size = Vector2(600, 300)
	layer.add_child(panel)
	var head = Label.new()
	head.text = title
	head.position = Vector2(24, 16)
	head.add_theme_font_size_override("font_size", 22)
	panel.add_child(head)
	var body = RichTextLabel.new()
	body.bbcode_enabled = true
	body.text = text
	body.position = Vector2(24, 60)
	body.size = Vector2(552, 160)
	panel.add_child(body)
	var row = HBoxContainer.new()
	row.position = Vector2(24, 236)
	row.add_theme_constant_override("separation", 12)
	panel.add_child(row)
	for o in options:
		var b = Button.new()
		b.text = String(o[1])
		b.custom_minimum_size = Vector2(170, 40)
		var id = String(o[0])
		b.pressed.connect(func(): _chosen.emit(id))
		row.add_child(b)
	var picked: String = await _chosen
	layer.queue_free()
	return picked
