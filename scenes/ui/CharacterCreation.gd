# res://scenes/ui/CharacterCreation.gd
# Character creation, one choice per page: Race, Class, Birthplace,
# Background, World, Name & Mode. Left: the options. Middle: the chosen
# option's details and lore (data/creation.json). Right: a summary of every
# choice so far, with stats read from a real character built from them.
extends Control

const STARTING_GOLD = 100
const STEPS := ["Race", "Class", "Birthplace", "Background", "World", "Name & Mode"]
const TAB_NAMES := STEPS   # the UI sweep walks the steps like tabs
const ATTRS := ["vitality", "strength", "dexterity", "intelligence", "faith", "mind", "endurance", "arcane", "agility", "fortitude"]
const LIST_RECT := Rect2(32, 72, 280, 552)
const DETAIL_RECT := Rect2(328, 72, 488, 552)
const SUMMARY_RECT := Rect2(832, 72, 336, 552)

var races: Dictionary = {}
var classes: Dictionary = {}
var lore: Dictionary = {}

var step := 0
var choice := {"race": "", "class": "", "birthplace": "", "background": "", "world": "", "name": "", "permadeath": false}

var chrome: ScreenChrome
var list: ItemList
var detail: RichTextLabel
var summary: RichTextLabel
var name_box: VBoxContainer
var name_input: LineEdit
var permadeath_box: CheckBox
var prev_button: Button
var next_button: Button
var cancel_button: Button
var drop_line := ""
var _worlds: Array = []

func _ready():
	races = DataRegistry.get_data("races").get("playable", {})
	classes = DataRegistry.get_data("classes").get("playable", {})
	var l = DataRegistry.get_data("creation")
	lore = l if l is Dictionary else {}
	choice.race = String(races.keys()[0])
	choice["class"] = String(classes.keys()[0])
	choice.background = String(Backgrounds.cfg().keys()[0]) if not Backgrounds.cfg().is_empty() else ""
	_default_birthplace()
	_worlds = WorldShare.joinable()
	_build_ui()
	_set_step(0)

# === UI ===

func _build_ui() -> void:
	chrome = ScreenChrome.attach(self, "New Character", Callable())
	var ui := CanvasLayer.new()
	ui.layer = 1
	add_child(ui)
	list = ItemList.new()
	ScreenChrome.place(list, LIST_RECT)
	list.item_selected.connect(_on_pick)
	ui.add_child(list)
	var dpanel := Panel.new()
	ScreenChrome.place(dpanel, DETAIL_RECT)
	ui.add_child(dpanel)
	detail = RichTextLabel.new()
	detail.bbcode_enabled = true
	ScreenChrome.place(detail, Rect2(16, 12, DETAIL_RECT.size.x - 32, DETAIL_RECT.size.y - 24))
	dpanel.add_child(detail)
	var spanel := Panel.new()
	ScreenChrome.place(spanel, SUMMARY_RECT)
	ui.add_child(spanel)
	summary = RichTextLabel.new()
	summary.bbcode_enabled = true
	ScreenChrome.place(summary, Rect2(14, 12, SUMMARY_RECT.size.x - 28, SUMMARY_RECT.size.y - 24))
	spanel.add_child(summary)
	# the last step: name and mode, in place of the list
	name_box = VBoxContainer.new()
	ScreenChrome.place(name_box, LIST_RECT)
	name_box.add_theme_constant_override("separation", 10)
	ui.add_child(name_box)
	var cap := Label.new()
	cap.text = "Name"
	cap.add_theme_color_override("font_color", ScreenChrome.MUTED)
	name_box.add_child(cap)
	name_input = LineEdit.new()
	name_input.placeholder_text = "Your name..."
	name_input.max_length = 24
	name_input.custom_minimum_size = Vector2(0, 44)
	name_input.text_changed.connect(func(t): choice.name = t.strip_edges(); _refresh())
	name_box.add_child(name_input)
	var rnd := Button.new()
	rnd.text = "Random name"
	rnd.custom_minimum_size = Vector2(0, 40)
	rnd.pressed.connect(_random_name)
	name_box.add_child(rnd)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 16)
	name_box.add_child(gap)
	permadeath_box = CheckBox.new()
	permadeath_box.text = "Permadeath"
	permadeath_box.toggled.connect(func(on): choice.permadeath = on; _refresh())
	name_box.add_child(permadeath_box)
	cancel_button = _footer("Cancel", Vector2(ScreenChrome.LEFT_X, ScreenChrome.FOOTER_Y), func(): SceneManager.change_to_character_selection())
	prev_button = _footer("< Back", Vector2(848, ScreenChrome.FOOTER_Y), func(): _set_step(step - 1))
	next_button = _footer("Next >", Vector2(1008, ScreenChrome.FOOTER_Y), _on_next)
	ui.add_child(cancel_button)
	ui.add_child(prev_button)
	ui.add_child(next_button)

func _footer(text: String, pos: Vector2, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.position = pos
	b.size = Vector2(160, 48)
	b.pressed.connect(cb)
	return b

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		if step > 0:
			_set_step(step - 1)
		else:
			SceneManager.change_to_character_selection()

## For the UI sweep.
func _set_tab(i: int) -> void:
	_set_step(i)

func _set_step(i: int) -> void:
	step = clampi(i, 0, STEPS.size() - 1)
	chrome.set_info("Step %d of %d:  %s" % [step + 1, STEPS.size(), STEPS[step]])
	var drops: Array = lore.get("lore_drops", {}).get(["race", "class", "origin", "origin", "world", "name"][step], [])
	drop_line = String(drops[RandomManager.randi() % drops.size()]) if not drops.is_empty() else ""
	var naming = step == STEPS.size() - 1
	list.visible = not naming
	name_box.visible = naming
	prev_button.visible = step > 0
	next_button.text = "Create" if naming else "Next >"
	if not naming:
		_fill_list()
	else:
		name_input.text = choice.name
		permadeath_box.set_pressed_no_signal(choice.permadeath)
		if name_input.is_inside_tree():
			name_input.grab_focus.call_deferred()
	_refresh()

func _on_next() -> void:
	if step < STEPS.size() - 1:
		_set_step(step + 1)
	else:
		_create()

# === LISTS ===

## The options for this step: [label, value] (value null = a heading).
func _options() -> Array:
	var out: Array = []
	match step:
		0:
			for r in races:
				out.append([String(r), String(r)])
		1:
			var cats := {}
			for c in classes:
				var cat = String(lore.get("classes", {}).get(c, {}).get("category", "Other"))
				if not cats.has(cat):
					cats[cat] = []
				cats[cat].append(String(c))
			for cat in cats:
				out.append([cat + "s", null])
				for c in cats[cat]:
					out.append(["   " + c, c])
		2:
			var last := ""
			for t in Regions.towns():
				if t.region != last:
					out.append([String(t.region_name), null])
					last = t.region
				out.append(["   " + String(t.town), String(t.town)])
		3:
			for id in Backgrounds.cfg():
				out.append([String(Backgrounds.get_bg(id).get("name", id)), String(id)])
		4:
			out.append(["A new world", ""])
			if not _worlds.is_empty():
				out.append(["Join a world", null])
			for w in _worlds:
				out.append(["   %s's world" % w.name, String(w.name)])
	return out

func _key() -> String:
	return ["race", "class", "birthplace", "background", "world", "name"][step]

func _fill_list() -> void:
	list.clear()
	var current = choice[_key()]
	for o in _options():
		var idx = list.add_item(o[0])
		if o[1] == null:
			list.set_item_disabled(idx, true)
			list.set_item_selectable(idx, false)
			list.set_item_custom_fg_color(idx, ScreenChrome.ACCENT)
		else:
			list.set_item_metadata(idx, o[1])
			if String(o[1]) == String(current):
				list.select(idx)
				list.ensure_current_is_visible()

func _on_pick(idx: int) -> void:
	var v = list.get_item_metadata(idx)
	if v == null:
		return
	choice[_key()] = String(v)
	if step == 0:
		_default_birthplace()
	_refresh()

## Start on a town of the race's homeland.
func _default_birthplace() -> void:
	var home: Array = Regions.cfg().get("race_homelands", {}).get(choice.race, [])
	for t in Regions.towns():
		if home.is_empty() or t.region in home:
			choice.birthplace = String(t.town)
			return

func _random_name() -> void:
	var probe := CharacterData.new("", choice.race, choice["class"])
	name_input.text = AdventurerManager._unique_name(probe, choice.race)
	choice.name = name_input.text
	_refresh()

# === TEXT ===

func _refresh() -> void:
	detail.text = _detail_text()
	summary.text = _summary_text()
	next_button.disabled = step == STEPS.size() - 1 and (choice.name == "" or SaveManager.save_exists(choice.name))

func _drop() -> String:
	return "[i][color=#a99f90]%s[/color][/i]\n\n" % drop_line if drop_line != "" else ""

func _title(t: String) -> String:
	return "[font_size=26][b][color=#e5c34a]%s[/color][/b][/font_size]\n" % t

func _detail_text() -> String:
	match step:
		0: return _race_text()
		1: return _class_text()
		2: return _birthplace_text()
		3: return _background_text()
		4: return _world_text()
	return _mode_text()

func _race_text() -> String:
	var r = choice.race
	var rl: Dictionary = lore.get("races", {}).get(r, {})
	var t = _title(r)
	t += "[color=#a99f90]%s[/color]\n\n" % rl.get("summary", "")
	t += _drop() + "%s\n\n" % rl.get("lore", "")
	var homes: Array = Regions.cfg().get("race_homelands", {}).get(r, []).map(func(x): return Regions.region_name(String(x)))
	if not homes.is_empty():
		t += "[b]Homeland:[/b] %s\n" % ", ".join(homes)
	var mods: Array = []
	var rd: Dictionary = races.get(r, {})
	for a in ATTRS:
		var m = int(rd.get(a.substr(0, 3) + "_mod", 0))
		if m != 0:
			mods.append("%s %+d" % [a.capitalize(), m])
	t += "[b]Attributes:[/b] %s\n" % (", ".join(mods) if not mods.is_empty() else "none")
	t += _elements_text(r)
	return t

func _elements_text(race: String) -> String:
	var ed = RaceElementalData.get_race_elemental_data(race, true)
	var bits: Array = []
	for element in ElementalDamage.Element.values():
		if element == ElementalDamage.Element.NONE:
			continue
		var key = ElementalDamage.Element.keys()[element]
		var col = ElementalDamage.get_element_color(element)
		var nm = ElementalDamage.get_element_name(element)
		var bonus = float(ed.get("damage_bonuses", {}).get(key, 0.0))
		var res = float(ed.get("resistances", {}).get(key, 0.0))
		var weak = float(ed.get("weaknesses", {}).get(key, 0.0))
		if bonus > 0:
			bits.append("[color=%s]%s[/color] +%d%% damage" % [col, nm, int(bonus * 100)])
		if res > 0:
			bits.append("[color=%s]%s[/color] resist %d%%" % [col, nm, int(res * 100)])
		if weak > 0:
			bits.append("[color=%s]%s[/color] [color=orange]weak +%d%%[/color]" % [col, nm, int(weak * 100)])
	return "[b]Elements:[/b] %s\n" % (", ".join(bits) if not bits.is_empty() else "no strengths or weaknesses")

func _class_text() -> String:
	var c = String(choice["class"])
	var cl: Dictionary = lore.get("classes", {}).get(c, {})
	var cd: Dictionary = classes.get(c, {})
	var t = _title(c)
	t += "[color=#a99f90]%s  ·  %s  ·  %s[/color]\n" % [cl.get("category", ""), cl.get("order", ""), cl.get("patrons", "")]
	var diff = int(cl.get("difficulty", 1))
	t += "[b]Role:[/b] %s     [b]Difficulty:[/b] %s[color=#555555]%s[/color]\n\n" % [cl.get("role", ""), "★".repeat(diff), "★".repeat(3 - diff)]
	t += _drop() + "%s\n" % cl.get("blurb", "")
	if cl.has("quote"):
		t += "[i][color=#c9b8ff]\"%s\"[/color][/i]\n" % cl.quote
	t += "\n[b]Starting skills:[/b] %s\n" % ", ".join(cd.get("skills", []))
	var weps: Array = []
	for w in cd.get("preferred_weapons", []):
		var it = ItemManager.get_item(String(w))
		weps.append(it.display_name if it else String(w).replace("_", " "))
	t += "[b]Weapons:[/b] %s\n" % ", ".join(weps)
	var sig: Dictionary = WeaponArts.cfg().get("signatures", {}).get(c, {})
	if not sig.is_empty():
		var arts: Array = []
		for fam in sig:
			arts.append("%s (%s)" % [sig[fam], fam])
		t += "[b]Signature art%s:[/b] %s\n" % ["s" if sig.size() > 1 else "", ", ".join(arts)]
	var arm: Dictionary = ArmorTraining.cfg().get("classes", {}).get(c, ArmorTraining.cfg().get("default_start", {}))
	t += "[b]Armour training:[/b] up to %s%s\n" % [arm.get("weight", "leather"), " and shields" if arm.get("shield", false) else ""]
	t += "[b]Power:[/b] attacks scale with %s, spells with %s\n" % [String(cd.get("attack_power_type", "")).capitalize(), String(cd.get("spell_power_type", "")).capitalize()]
	return t

func _birthplace_text() -> String:
	var b = choice.birthplace
	var r = Regions.region_of(b)
	var reg: Dictionary = Regions.cfg().get("regions", {}).get(r, {})
	var t = _title(b)
	t += "[color=#a99f90]%s  ·  held by %s[/color]\n\n" % [reg.get("name", ""), reg.get("god", "?")]
	t += _drop() + "%s\n\n" % reg.get("description", "")
	var home: Array = Regions.cfg().get("race_homelands", {}).get(choice.race, [])
	if r in home:
		t += "[color=#88dd88]A homeland of the %s people.[/color]\n" % choice.race
	t += "Adventurers from the same region start out a little warmer toward you.\n"
	t += "From here it's [b]%d day(s)[/b] on the road to the Guild at %s." % [Regions.travel_days(b), Regions.town_name()]
	return t

func _background_text() -> String:
	var bgd = Backgrounds.get_bg(choice.background)
	var t = _title(String(bgd.get("name", ""))) + "\n"
	t += _drop() + "%s\n\n" % String(bgd.get("description", "")).replace("{birthplace}", choice.birthplace)
	t += "[b]What it gives you[/b]\n"
	for bit in _background_bits(bgd):
		t += "  •  %s\n" % bit
	return t

func _background_bits(bgd: Dictionary) -> Array:
	var bits: Array = []
	for at in bgd.get("attributes", {}):
		bits.append("%+d %s" % [int(bgd.attributes[at]), String(at).capitalize()])
	var cop = int(bgd.get("start_copper", 0))
	if cop != 0:
		bits.append("%s%s starting money" % ["+" if cop > 0 else "-", Currency.format_copper(absi(cop))])
	for it in bgd.get("start_items", []):
		var item = ItemManager.get_item(String(it.id))
		bits.append("%d× %s" % [int(it.get("qty", 1)), item.display_name if item else String(it.id)])
	if float(bgd.get("sell_bonus", 0)) > 0:
		bits.append("+%d%% when selling" % int(round(float(bgd.sell_bonus) * 100)))
	for sh in bgd.get("craft_discount", {}):
		bits.append("-%d%% %s costs" % [int(round(float(bgd.craft_discount[sh]) * 100)), sh])
	if int(bgd.get("training_points", 0)) > 0:
		bits.append("+%d armour training" % int(bgd.training_points))
	for tr in bgd.get("rapport_traits", {}):
		bits.append("%s adventurers like you more" % String(tr).capitalize())
	for a in bgd.get("reputation", {}):
		bits.append("the Guild sees you as a little %s" % String(a).replace("_", " "))
	return bits

func _world_text() -> String:
	var t := ""
	if choice.world == "":
		t = _title("A new world") + "\n" + _drop()
		t += "The Guild of %s lives through %d days of its own history before you arrive: adventurers join and rise, form companies, fall in love, feud and die, and a champion is crowned.\n\n" % [Regions.town_name(), WorldGen.days()]
		t += "You sign the Guild's ledger on the day the history ends. Two rivals sign it with you."
		return t
	var w := {}
	for x in _worlds:
		if x.name == choice.world:
			w = x
	t = _title("%s's world" % choice.world)
	var state = "  ·  fallen" if w.get("fallen", false) else ("  ·  retired" if w.get("retired", false) else "")
	t += "[color=#a99f90]Lv %d %s %s%s  ·  day %d  ·  %d adventurers[/color]\n\n" % [int(w.get("level", 1)), w.get("race", ""), w.get("cls", ""), state, int(w.get("day", 1)), int(w.get("adventurers", 0))]
	t += _drop()
	t += "Arrive in the world %s knows, as it stands in their save: the same Guild, the same people with their bonds and feuds, the same Ledger and Chronicle.\n\n" % choice.world
	t += "No one knows [i]you[/i] yet. What they remember of %s stays with %s, whose deeds remain in the Chronicle under their name.\n\n" % [choice.world, choice.world]
	t += "[color=#a99f90]A copy: from here, your world and theirs go on separately.[/color]"
	return t

func _mode_text() -> String:
	var t = _title("Who are you?") + "\n" + _drop()
	if choice.name != "" and SaveManager.save_exists(choice.name):
		t += "[color=orange]There's already a character named %s.[/color]\n\n" % choice.name
	t += "[b]Permadeath[/b]\n"
	if choice.permadeath:
		t += "One life. If you fall and no one who owes you drags you out, you die: your Legend is written and the save is gone.\n\n"
	else:
		t += "[color=#a99f90]Off: a defeat costs you gear, money and time to heal, but you live to try again.[/color]\n\n"
	t += "[color=#a99f90]Check the summary, then Create.[/color]"
	return t

## Every choice so far, and stats from a character built from them.
func _summary_text() -> String:
	var c = _preview()
	var t = "[b][color=#e5c34a]%s[/color][/b]\n" % (choice.name if choice.name != "" else "Unnamed")
	t += "%s %s\n" % [choice.race, choice["class"]]
	t += "[color=#a99f90]Born in %s\n%s\n%s%s[/color]\n\n" % [Regions.describe(choice.birthplace), Backgrounds.get_bg(choice.background).get("name", ""),
		"A new world" if choice.world == "" else "Joining %s's world" % choice.world, "  ·  Permadeath" if choice.permadeath else ""]
	t += "HP [b]%d[/b]   MP [b]%d[/b]   SP [b]%d[/b]\n" % [c.max_hp, c.max_mp, c.max_sp]
	t += "Attack [b]%d[/b]   Spell [b]%d[/b]\n" % [int(BattleFormulas.physical_offense(c)), int(BattleFormulas.magical_offense(c))]
	t += "Defense [b]%d[/b]   Magic def. [b]%d[/b]\n" % [int(round(BattleFormulas.physical_defense(c))), int(round(BattleFormulas.magical_defense(c)))]
	t += "Accuracy %d%%   Crit %d%%\n\n" % [int(round(c.accuracy * 100)), int(round(c.critical_hit_rate * 100))]
	t += "[table=2]"
	for a in ATTRS:
		t += "[cell]%s   [/cell][cell][b]%d[/b][/cell]" % [a.capitalize(), int(c.get(a))]
	return t + "[/table]"

func _preview() -> CharacterData:
	var c = CharacterFactory.create_character(choice.name if choice.name != "" else "Preview", choice.race, choice["class"], true)
	var bgd = Backgrounds.get_bg(choice.background)
	for a in bgd.get("attributes", {}):
		c.set(String(a), int(c.get(String(a))) + int(bgd.attributes[a]))
	c.calculate_secondary_attributes()
	return c

# === CREATE ===

func _create() -> void:
	if choice.name == "" or SaveManager.save_exists(choice.name):
		return
	var c = CharacterFactory.create_character(choice.name, choice.race, choice["class"], true)
	c.max_floor_unlocked = 1
	c.town_state["birthplace"] = choice.birthplace
	if choice.permadeath:
		c.town_state["permadeath"] = true
	c.currency.copper = STARTING_GOLD
	if choice.background != "":
		Backgrounds.apply_creation(c, choice.background)
	if choice.world == "" or not WorldShare.join(c, choice.world):
		c.town_state["world_pending"] = true   # TownScene writes the history on arrival
	SaveManager.save_game(c)
	Log.debug("character_creation", "Character created: %s (Level %d %s %s)" % [c.name, c.level, c.race, c.character_class])
	SceneManager.change_to_character_selection()
