# res://scenes/ui/CompendiumScreen.gd
# The Compendium: every system explained (data/compendium.json). Text is BBCode with
# placeholders that read live values, so the Compendium stays true when the game
# is retuned:
#   {pct:file:path}  percent      {num:file:path}  number     {x:file:path}  x-multiplier
#   {list:name}      a block generated from the data (see _list)
# Open with CompendiumScreen.open(parent[, topic_id]).
class_name CompendiumScreen
extends CanvasLayer

const SCHOOLS := {
	"Paladin": "Warden", "Samurai": "Warden", "Berserker": "Warden",
	"Monk": "Martialist", "Shinobi": "Martialist", "Myrmidon": "Martialist",
	"Druid": "Mender", "Cleric": "Mender", "Kannagi": "Mender",
	"Elementalist": "Sorcerer", "Beastmaster": "Sorcerer", "Necromancer": "Sorcerer"}

var start_topic := ""
var topics: Array = []
var list: Tree
var page: RichTextLabel

static func open(parent: Node, topic_id := "") -> CompendiumScreen:
	var m = CompendiumScreen.new()
	m.start_topic = topic_id
	parent.add_child(m)
	return m

static func all_topics() -> Array:
	var d = DataRegistry.get_data("compendium")
	return d.get("topics", []) if d is Dictionary else []

func _ready() -> void:
	layer = 65
	var dim = ColorRect.new()
	dim.color = Color(0, 0, 0, 0.65)
	dim.size = Vector2(1200, 720)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	var panel = Panel.new()
	panel.position = Vector2(40, 30)
	panel.size = Vector2(1120, 660)
	add_child(panel)
	var title = Label.new()
	title.text = "Compendium"
	title.position = Vector2(24, 12)
	title.add_theme_font_size_override("font_size", 24)
	panel.add_child(title)
	list = Tree.new()
	list.position = Vector2(20, 56)
	list.size = Vector2(280, 540)
	list.hide_root = true
	list.item_selected.connect(_on_select)
	panel.add_child(list)
	page = RichTextLabel.new()
	page.bbcode_enabled = true
	page.position = Vector2(320, 56)
	page.size = Vector2(780, 540)
	page.scroll_active = true
	panel.add_child(page)
	var close = Button.new()
	close.text = "Close"
	close.custom_minimum_size = Vector2(150, 40)
	close.position = Vector2(950, 606)
	close.pressed.connect(queue_free)
	panel.add_child(close)
	_fill()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		queue_free()
		get_viewport().set_input_as_handled()

func _fill() -> void:
	topics = all_topics()
	var root = list.create_item()
	var sections := {}
	var first: TreeItem = null
	for i in range(topics.size()):
		var t: Dictionary = topics[i]
		var sec = String(t.get("section", "General"))
		if not sections.has(sec):
			var s = list.create_item(root)
			s.set_text(0, sec)
			s.set_selectable(0, false)
			s.set_custom_color(0, Color("ffd166"))
			sections[sec] = s
		var it = list.create_item(sections[sec])
		it.set_text(0, String(t.get("title", t.get("id", "?"))))
		it.set_metadata(0, i)
		if first == null or String(t.get("id", "")) == start_topic:
			first = it
	if first:
		first.select(0)
		_show(int(first.get_metadata(0)))

func _on_select() -> void:
	var it = list.get_selected()
	if it and it.get_metadata(0) != null:
		_show(int(it.get_metadata(0)))

func _show(i: int) -> void:
	var t: Dictionary = topics[i]
	page.text = "[b][font_size=22]%s[/font_size][/b]\n\n%s" % [t.get("title", ""), render(String(t.get("text", "")))]
	page.scroll_to_line(0)

# ------------------------------------------------------------------ rendering

## Replace placeholders with live values / generated blocks.
static func render(text: String) -> String:
	var rx = RegEx.new()
	rx.compile("\\{(pct|num|x|list):([^}]+)\\}")
	var out := ""
	var pos := 0
	for m in rx.search_all(text):
		out += text.substr(pos, m.get_start() - pos)
		out += _value(m.get_string(1), m.get_string(2))
		pos = m.get_end()
	return out + text.substr(pos)

static func _lookup(spec: String):
	var parts = spec.split(":", true, 1)
	if parts.size() < 2:
		return null
	var d = DataRegistry.get_data(parts[0])
	for key in parts[1].split("."):
		if d is Dictionary and d.has(key):
			d = d[key]
		else:
			return null
	return d

static func _fmt(v: float) -> String:
	return str(int(v)) if is_equal_approx(v, round(v)) else ("%.2f" % v).rstrip("0").rstrip(".")

static func _value(kind: String, spec: String) -> String:
	if kind == "list":
		return _list(spec)
	var v = _lookup(spec)
	if v == null:
		return "?"
	match kind:
		"pct": return "%d%%" % int(round(float(v) * 100))
		"x": return "×" + _fmt(float(v))
	return _fmt(float(v))

# ------------------------------------------------------------------ generated blocks

static func _list(name: String) -> String:
	match name:
		"attributes": return _attributes()
		"formulas": return _formulas()
		"classes": return _classes()
		"status_effects": return _status_effects()
		"elite_affixes": return _entries(EliteAffixes.data().get("affixes", {}))
		"omens": return _entries(RunState.all_omens(), "reward", "+%d%% loot")
		"boons": return _entries(RunState.all_boons())
		"challenges": return _entries(WaveChallenges.all())
		"ranks": return _ranks()
		"enchants": return _enchants()
		"enchant_cap": return String(EnchantManager.cfg().get("max_rarity", "epic")).capitalize()
		"damage_types": return _damage_types()
		"gear_stats": return _gear_stats()
		"item_names": return _item_names()
	return "?"

static func _entries(d: Dictionary, extra_key := "", extra_fmt := "") -> String:
	var t := ""
	for id in d:
		if String(id).begins_with("_"):
			continue
		var e: Dictionary = d[id]
		var extra = (" [color=#ffd166](%s)[/color]" % (extra_fmt % int(round(float(e[extra_key]) * 100)))) if extra_key != "" and e.has(extra_key) else ""
		t += "• [b]%s[/b]%s - %s\n" % [e.get("name", id), extra, e.get("description", "")]
	return t.strip_edges()

static func _attributes() -> String:
	var a := [
		["Vitality", "Max HP (x8), toughness. Adds to attack power for Strength fighters."],
		["Strength", "Attack power for Strength classes (x2), max HP (x3), toughness."],
		["Dexterity", "Attack power for Dexterity classes (x2), accuracy, dodge, critical hits."],
		["Intelligence", "Spell power for Intelligence casters (x2), max MP (x3), critical hits."],
		["Faith", "Spell power for Faith casters (x2) and healing, spell ward (magic defense)."],
		["Mind", "Max MP (x5), spell ward, accuracy."],
		["Endurance", "Max SP (x5) for physical skills, toughness."],
		["Arcane", "Attack or spell power for Arcane classes (x2), spell ward."],
		["Agility", "Turn order, dodge, max SP (x3), accuracy, critical hits."],
		["Fortitude", "A little of everything defensive: toughness, spell ward, dodge, accuracy, crits."]]
	var t := ""
	for e in a:
		t += "• [b]%s[/b]: %s\n" % e
	return t.strip_edges()

static func _formulas() -> String:
	var t := "[b]Resources[/b]\n• HP = Vitality x8 + Strength x3\n• MP = Mind x5 + Intelligence x3 (magic skills)\n• SP = Endurance x5 + Agility x3 (physical skills)\n"
	t += "• Basic attacks restore %d%% of max MP and SP.\n\n" % int(round(BattleFormulas.ATTACK_RESOURCE_REGEN * 100))
	t += "[b]Offense[/b]\n• Attack power = your class's physical attribute x2 + two others x0.5, plus weapon damage.\n• Spell power = your class's magical attribute x2 + two others x0.5 (Balanced: Intelligence + Faith + Arcane).\n"
	t += "• A hit deals %d%% of your offense, +%d%% per point of skill power.\n" % [int(round(BattleFormulas.BASE_SCALE * 100)), int(round(BattleFormulas.SKILL_POWER_SCALE * 100))]
	t += "• Critical hits deal x%.1f to x%.1f.\n• Heals restore the skill's power + %d%% of spell power.\n\n" % [BattleFormulas.CRIT_MULT_MIN, BattleFormulas.CRIT_MULT_MAX, int(round(BattleFormulas.HEAL_SPELL_POWER_SCALE * 100))]
	t += "[b]Defense[/b]\n• Toughness (physical) and spell ward (magical) come from attributes; armor adds %s defense per point (half that against magic).\n" % _fmt(BattleFormulas.ARMOR_SCALE)
	t += "• Damage taken = damage x %d / (%d + defense): %d defense halves it.\n" % [int(BattleFormulas.DEFENSE_K), int(BattleFormulas.DEFENSE_K), int(BattleFormulas.DEFENSE_K)]
	t += "• Armor penetration (from gear) ignores part of the target's physical defense (at most %d%%).\n\n" % int(round(BattleFormulas.MAX_ARMOR_PENETRATION * 100))
	t += "[b]Hitting and dodging[/b]\n• Accuracy starts at 85% (+Dexterity, Agility, Mind); dodge starts at 5% (+Agility, Dexterity); critical chance starts at 5% (+Dexterity, Agility, Intelligence).\n"
	t += "• Weapon damage types (Slash, Pierce, Blunt) and elements meet the target's affinities: weak spots deal more, resisted hits less."
	return t

static func _classes() -> String:
	var cl: Dictionary = DataRegistry.get_data("classes").get("playable", {})
	var by_school := {}
	for c in cl:
		var s = SCHOOLS.get(c, "Other")
		if not by_school.has(s):
			by_school[s] = []
		by_school[s].append(c)
	var t := ""
	for s in ["Warden", "Martialist", "Mender", "Sorcerer", "Other"]:
		if not by_school.has(s):
			continue
		t += "[b]%ss[/b]\n" % s
		for c in by_school[s]:
			var d: Dictionary = cl[c]
			t += "• [b]%s[/b] - attack: %s, spells: %s\n" % [c, String(d.get("attack_power_type", "?")).capitalize(), String(d.get("spell_power_type", "?")).capitalize()]
		t += "\n"
	return t.strip_edges()

static func _status_effects() -> String:
	var d = DataRegistry.get_data("status_effects")
	var e: Dictionary = d.get("effects", d) if d is Dictionary else {}
	var t := "Statuses last a few turns. Many are also combo set-ups.\n\n"
	for id in e:
		var s = e[id]
		if not (s is Dictionary) or String(id).begins_with("_"):
			continue
		var parts: Array = []
		match String(s.get("damage_type", "none")):
			"hp_percent": parts.append("loses %d%% of max HP each turn" % int(round(float(s.get("damage_value", 0)) * 100)))
			"heal_percent": parts.append("heals %d%% of max HP each turn" % int(round(float(s.get("damage_value", 0)) * 100)))
			"stackable_burst": parts.append("stacks up to %d; at full stacks it bursts for %d%% of max HP" % [int(s.get("max_stacks", 3)), int(round(float(s.get("burst_damage_percent", 0)) * 100))])
		if float(s.get("stun_chance", 0)) >= 1.0:
			parts.append("can't act" + (" (wakes when hit)" if s.get("break_on_damage", false) else ""))
		elif float(s.get("stun_chance", 0)) > 0:
			parts.append("%d%% chance to lose the turn" % int(round(float(s.stun_chance) * 100)))
		if float(s.get("accuracy_reduction", 0)) > 0:
			parts.append("-%d%% accuracy" % int(round(float(s.accuracy_reduction) * 100)))
		if float(s.get("dodge_reduction", 0)) > 0:
			parts.append("-%d%% dodge" % int(round(float(s.dodge_reduction) * 100)))
		if float(s.get("dodge_bonus", 0)) > 0:
			parts.append("+%d%% dodge" % int(round(float(s.dodge_bonus) * 100)))
		if float(s.get("reflect_damage", 0)) > 0:
			parts.append("reflects %d%% of damage taken" % int(round(float(s.reflect_damage) * 100)))
		if float(s.get("self_harm_chance", 0)) > 0:
			parts.append("%d%% chance to hit itself" % int(round(float(s.self_harm_chance) * 100)))
		var mods: Array = []
		var sm: Dictionary = s.get("stat_modifiers", {})
		for k in sm:
			mods.append("%+d %s" % [int(sm[k]), String(k).capitalize()])
		if not mods.is_empty():
			parts.append(", ".join(mods))
		if parts.is_empty():
			parts.append("no effect on its own - a combo set-up")
		var el = String(s.get("element", ""))
		t += "• [b]%s[/b]%s: %s\n" % [String(id).capitalize(), (" [color=gray](%s)[/color]" % el.capitalize()) if el != "" else "", "; ".join(parts)]
	return t.strip_edges()

static func _ranks() -> String:
	var r: Dictionary = DataRegistry.get_data("ranks").get("ranks", {})
	var ids = r.keys()
	ids.sort_custom(func(a, b): return int(r[a].get("order", 0)) < int(r[b].get("order", 0)))
	var t := ""
	for id in ids:
		var cap = int(r[id].get("floor_cap", 0))
		var party = int(r[id].get("party_size", 1))
		t += "• [b]%s %s[/b] - %d Guild points; %s%s\n" % [id, r[id].get("title", ""), int(r[id].get("points", 0)),
			("floors up to %d" % cap) if cap > 0 else "every floor", (", party of %d" % party) if party > 1 else ""]
	return t.strip_edges()

static func _enchants() -> String:
	var t := "[b]Enchantments[/b] (material → bonus, weapon on-hit):\n"
	for id in EnchantManager.enchants():
		var e: Dictionary = EnchantManager.enchants()[id]
		var mat = ItemManager.get_item(String(e.get("material", "")))
		var st = String(e.get("weapon_status", ""))
		t += "• [b]%s[/b] (%s): %s%s\n" % [e.get("name", id), mat.display_name if mat else e.get("material", "?"), String(e.get("stat", "")).capitalize(), (", " + st.capitalize()) if st != "" else ""]
	return t.strip_edges()

static func _gear_stats() -> String:
	var up = int(round(Equipment.UPGRADE_STEP * 100))
	var t := "Hover or inspect an item to see its numbers. What they mean:\n\n"
	t += "[b]Base stats[/b]\n"
	t += "• [b]Damage[/b] (weapons): added to your attack power for physical hits.\n"
	t += "• [b]Damage type[/b] (weapons): Slash, Pierce or Blunt - meets the target's affinities (see Weaknesses and Break).\n"
	t += "• [b]Armor[/b]: each point adds %s physical defense (half that against magic).\n" % _fmt(BattleFormulas.ARMOR_SCALE)
	t += "• [b]Armor type[/b] (cloth, leather, mail, plate): changes which damage types hurt you - a full set gives the whole effect.\n"
	t += "• [b]Attribute bonus[/b]: a flat bonus to an attribute (e.g. +2 Strength).\n"
	t += "• [b]Item level[/b]: how strong the item is for its floor; higher item levels scale every number up.\n\n"
	t += "[b]Special properties[/b]\n"
	t += "• [b]Dodge[/b]: chance to avoid hits entirely.\n"
	t += "• [b]Critical hit rate[/b]: chance to crit (x%.1f-x%.1f damage).\n" % [BattleFormulas.CRIT_MULT_MIN, BattleFormulas.CRIT_MULT_MAX]
	t += "• [b]Armor penetration[/b]: your physical hits ignore this share of the target's defense (up to %d%%).\n" % int(round(BattleFormulas.MAX_ARMOR_PENETRATION * 100))
	t += "• [b]Spell power[/b] (tomes, talismans, cloth): added to your spell power.\n"
	t += "• [b]Spell ward[/b]: magical defense.\n"
	t += "• [b]On-hit effect[/b] (weapons): a chance to inflict a status (Burn, Freeze, Bleed...) when you hit.\n"
	t += "• [b]Bonus damage[/b] (Legendary weapons): extra damage on every hit.\n\n"
	t += "[b]Rarity[/b]\n"
	t += "• Common, Uncommon, Magic, Rare, Epic, Legendary. Higher rarities roll more attribute bonuses, better base numbers and higher item levels; Rare and better can carry an on-hit effect.\n\n"
	t += "[b]Improvements[/b]\n"
	t += "• [b]+N[/b] (Blacksmith upgrades): +%d%% damage and armor per level (and attribute bonuses on caster gear). The cap depends on rarity.\n" % up
	t += "• [b]Tempered[/b]: a failed upgrade gives the next try a bonus.\n"
	t += "• [b]Enchanted[/b]: the Enchanter raised its rarity and added an attribute bonus (and maybe an on-hit effect).\n\n"
	t += "[b]Who can use it[/b]\n"
	t += "• [b]Class restriction[/b]: only the listed classes can equip it.\n"
	t += "• [b]Dual wield[/b]: some one-handed weapons can go in the off hand for some classes; two-handed weapons block the off hand."
	return t

## How generated item names read (EquipmentNamer's word tables).
static func _item_names() -> String:
	var t := "Magic and better gear gets a generated name: [b][On-hit word] [Main stat word] [Second stat word] Item [of ...][/b]. "
	t += "Example: a [i]Toxic Brilliant Rapid Staff of Growth[/i] poisons on hit, mostly raises Intelligence, also Agility, and was blessed by Elandria.\n\n"
	t += "[b]1. On-hit word[/b] (weapons that can inflict a status)\n"
	for st in EquipmentNamer.STATUS_DESCRIPTORS:
		t += "• %s → [b]%s[/b] on hit\n" % [", ".join(EquipmentNamer.STATUS_DESCRIPTORS[st]), Skill.StatusEffect.keys()[st].capitalize()]
	t += "\n[b]2. Main stat word[/b] - the item's biggest attribute bonus\n"
	for a in EquipmentNamer.STAT_PREFIXES:
		t += "• %s → [b]%s[/b]\n" % [", ".join(EquipmentNamer.STAT_PREFIXES[a]), Skill.AttributeTarget.keys()[a].capitalize()]
	t += "\n[b]3. Second stat word[/b] (Epic and Legendary) - the second-biggest bonus\n"
	for a in EquipmentNamer.SECONDARY_PREFIXES:
		t += "• %s → [b]%s[/b]\n" % [", ".join(EquipmentNamer.SECONDARY_PREFIXES[a]), Skill.AttributeTarget.keys()[a].capitalize()]
	t += "\n[b]4. \"of ...\"[/b] (Rare and up) - the god who blessed it. On an on-hit weapon it matches the status; otherwise it's flavour.\n"
	var by_status := {}
	for st in EquipmentNamer.STATUS_PANTHEON_MAP:
		by_status[EquipmentNamer.STATUS_PANTHEON_MAP[st]] = Skill.StatusEffect.keys()[st].capitalize()
	for g in EquipmentNamer.PANTHEON_NAMES:
		var pd: Dictionary = EquipmentNamer.PANTHEON_NAMES[g]
		t += "• of %s → [b]%s[/b], god of %s%s\n" % [" / ".join(pd.verbs), g, pd.domain, (" (%s weapons)" % by_status[g]) if by_status.has(g) else ""]
	t += "\nCommon gear keeps its plain name. Enchanting doesn't rename an item - check its \"Enchanted:\" line, and note Bleed, Confuse and Blind on-hit effects (from enchanting) have no name word yet."
	return t

static func _damage_types() -> String:
	var armor: Dictionary = DamageTypes.cfg().get("armor", {})
	var t := "[b]Armor affinities[/b] (a full set):\n"
	for a in armor:
		if not String(a).begins_with("_"):
			t += "• %s: %s\n" % [String(a).capitalize(), DamageTypes.describe(armor[a])]
	return t.strip_edges()
