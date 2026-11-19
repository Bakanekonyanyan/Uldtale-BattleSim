# res://scenes/StatusScene.gd
# Character sheet. Built in code on the ScreenChrome grid:
#   left   Vitals (HP/MP/SP/XP bars) + Attributes (with what each one feeds)
#   right  Combat stats + tabs: Skills / Equipment / Elements / Proficiencies
# The old .tscn labels are hidden; only the background art is reused.
extends Control

enum Tab { SKILLS, EQUIPMENT, ELEMENTS, PROFICIENCIES }
const TAB_NAMES := ["Skills", "Equipment", "Elements", "Proficiencies"]

const ATTRIBUTES := ["vitality", "strength", "dexterity", "intelligence", "faith",
	"mind", "endurance", "arcane", "agility", "fortitude"]
## What each attribute feeds (mirrors CharacterData.calculate_secondary_attributes).
const ATTRIBUTE_HINTS := {
	"vitality": "HP, phys. defense",
	"strength": "HP, phys. defense",
	"dexterity": "accuracy, crit, dodge",
	"intelligence": "MP, crit",
	"faith": "magic defense",
	"mind": "MP, magic def., accuracy",
	"endurance": "SP, phys. defense",
	"arcane": "magic defense",
	"agility": "SP, dodge, crit",
	"fortitude": "defenses, dodge, crit",
}
const BAR_COLORS := {"HP": Color("c0443c"), "MP": Color("4a6fd0"), "SP": Color("d0a03a"), "XP": Color("6fae4a")}

const GOOD := "#8fd46a"
const BAD := "#e07a5f"
const MUTED := "#a99f90"
const ACCENT := "#e5c34a"

var current_character: CharacterData
var chrome: ScreenChrome
var tab: Tab = Tab.SKILLS

var bars := {}               # "HP" -> {bar: ProgressBar, value: Label}
var attributes_text: RichTextLabel
var combat_text: RichTextLabel
var tab_buttons: Array[Button] = []
var tab_text: RichTextLabel

func _ready():
	current_character = CharacterManager.get_current_character()
	if not current_character:
		push_error("StatusScene: no character loaded")
		return
	_build_ui()
	update_status()

func set_player(character: CharacterData):
	current_character = character
	if is_node_ready() and chrome:
		update_status()

# === UI CONSTRUCTION ===

func _build_ui() -> void:
	chrome = ScreenChrome.attach(self, "Status", _on_exit_pressed)
	# Hide the old scene-file labels; everything is rebuilt below.
	for child in get_children():
		if (child is Label or child is RichTextLabel or child is Button) and child != chrome:
			child.visible = false

	var ui := CanvasLayer.new()
	ui.name = "StatusUI"
	add_child(ui)

	# Vitals
	var vitals = _card(ui, "Vitals", Rect2(32, 72, 440, 168))
	for i in range(4):
		var key = ["HP", "MP", "SP", "XP"][i]
		bars[key] = _bar(vitals, key, 40 + i * 30)

	# Attributes
	var attrs = _card(ui, "Attributes", Rect2(32, 252, 440, 372))
	attributes_text = _rich(attrs, Rect2(10, 36, 420, 330))

	# Combat
	var combat = _card(ui, "Combat", Rect2(496, 72, 672, 204))
	combat_text = _rich(combat, Rect2(10, 34, 652, 166))
	combat_text.scroll_active = false

	# Tabs
	for i in range(TAB_NAMES.size()):
		var b := Button.new()
		b.text = TAB_NAMES[i]
		b.position = Vector2(496 + i * 142, 288)
		b.size = Vector2(134, 36)
		b.toggle_mode = true
		b.pressed.connect(func(): _set_tab(i))
		ui.add_child(b)
		tab_buttons.append(b)
	var panel = _card(ui, "", Rect2(496, 332, 672, 292))
	tab_text = _rich(panel, Rect2(10, 8, 652, 276))
	tab_text.scroll_active = true

func _card(parent: Node, title: String, rect: Rect2) -> Panel:
	var p := Panel.new()
	p.position = rect.position
	p.size = rect.size
	parent.add_child(p)
	if title != "":
		var l := Label.new()
		l.text = title.to_upper()
		l.position = Vector2(14, 8)
		l.add_theme_color_override("font_color", Color(ACCENT))
		l.add_theme_font_size_override("font_size", 14)
		p.add_child(l)
	return p

func _rich(parent: Node, rect: Rect2) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.position = rect.position
	r.size = rect.size
	r.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	r.add_theme_constant_override("table_h_separation", 18)
	r.add_theme_constant_override("line_separation", 3)
	parent.add_child(r)
	return r

func _bar(parent: Node, key: String, y: int) -> Dictionary:
	var name_label := Label.new()
	name_label.text = key
	name_label.position = Vector2(14, y)
	name_label.size = Vector2(36, 24)
	parent.add_child(name_label)

	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.position = Vector2(54, y + 3)
	bar.size = Vector2(250, 18)
	var fill := StyleBoxFlat.new()
	fill.bg_color = BAR_COLORS[key]
	fill.set_corner_radius_all(2)
	bar.add_theme_stylebox_override("fill", fill)
	parent.add_child(bar)

	var value := Label.new()
	value.position = Vector2(314, y)
	value.size = Vector2(116, 24)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	parent.add_child(value)
	return {"bar": bar, "value": value}

# === REFRESH ===

func _set_tab(new_tab: int) -> void:
	tab = new_tab as Tab
	_refresh_tab()

func update_status():
	if not current_character or not chrome:
		return
	var c = current_character
	chrome.set_title(str(c.name))
	chrome.set_info("Level %d  %s %s" % [c.level, c.race, c.character_class])

	_set_bar("HP", c.current_hp, c.max_hp)
	_set_bar("MP", c.current_mp, c.max_mp)
	_set_bar("SP", c.current_sp, c.max_sp)
	var needed = LevelSystem.calculate_xp_for_level(c.level)
	_set_bar("XP", c.xp, needed)

	attributes_text.text = _attributes_text()
	combat_text.text = _combat_text()
	_refresh_tab()

func _set_bar(key: String, value: float, max_value: float) -> void:
	bars[key].bar.max_value = max(1.0, max_value)
	bars[key].bar.value = value
	bars[key].value.text = "%d / %d" % [value, max_value]

func _refresh_tab() -> void:
	for i in range(tab_buttons.size()):
		tab_buttons[i].set_pressed_no_signal(i == tab)
	match tab:
		Tab.SKILLS: tab_text.text = _skills_text()
		Tab.EQUIPMENT: tab_text.text = _equipment_text()
		Tab.ELEMENTS: tab_text.text = _elements_text()
		Tab.PROFICIENCIES: tab_text.text = _proficiency_text()
	tab_text.scroll_to_line(0)

# === SECTION TEXT ===

func _attributes_text() -> String:
	var c = current_character
	var t := "[table=3]"
	for stat in ATTRIBUTES:
		var b = c.get_attribute_breakdown(stat) if c.has_method("get_attribute_breakdown") else {"total": c.get(stat), "equipment": 0, "buffs": 0}
		var bonus = int(b.get("equipment", 0)) + int(b.get("buffs", 0))
		var value = "[b]%d[/b]" % int(b.get("total", c.get(stat)))
		if bonus != 0:
			value += " [color=%s](%+d)[/color]" % [GOOD if bonus > 0 else BAD, bonus]
		var hint = ATTRIBUTE_HINTS[stat]
		if c.get("attack_power_type") == stat:
			hint = "[color=%s]attack[/color], " % ACCENT + hint
		t += "[cell]%s[/cell][cell]%s[/cell][cell][color=%s]%s[/color][/cell]" % [stat.capitalize(), value, MUTED, hint]
	return t + "[/table]"

func _combat_text() -> String:
	var c = current_character
	var phys_def = BattleFormulas.physical_defense(c)
	var mag_def = BattleFormulas.magical_defense(c)
	var rows = [
		["Physical attack", "%d" % int(BattleFormulas.physical_offense(c)), "attack power + weapon"],
		["Spell power", "%d" % int(BattleFormulas.magical_offense(c)), "magic damage and healing"],
		["Physical defense", "%d" % int(round(phys_def)), "you take %d%% of physical damage" % int(round(BattleFormulas.mitigation(phys_def) * 100))],
		["Magic defense", "%d" % int(round(mag_def)), "you take %d%% of magic damage" % int(round(BattleFormulas.mitigation(mag_def) * 100))],
		["Accuracy / Dodge", "%d%% / %d%%" % [int(round(c.accuracy * 100)), int(round(c.dodge * 100))], "chance to hit / to evade"],
		["Critical hit", "%d%%" % int(round(c.critical_hit_rate * 100)), "x1.5 to x2 damage"],
	]
	var t := "[table=3]"
	for r in rows:
		t += "[cell]%s[/cell][cell][b]%s[/b][/cell][cell][color=%s]%s[/color][/cell]" % [r[0], r[1], MUTED, r[2]]
	return t + "[/table]"

func _skills_text() -> String:
	var c = current_character
	if c.skills.is_empty():
		return "[color=%s][i]No skills learned.[/i][/color]" % MUTED
	var t := ""
	for skill_name in c.skills:
		var s = c.get_skill_instance(skill_name)
		if s == null:
			continue
		var level = "Lv %s" % s.get_level_string()
		if s.level < 6:
			level += "  [color=%s]%d / %d uses to next[/color]" % [MUTED, s.uses, s.get_uses_for_next_level()]
		t += "[b][color=%s]%s[/color][/b]   %s\n" % [ACCENT, s.name, level]
		var parts: Array = []
		if s.mp_cost > 0: parts.append("%d MP" % s.mp_cost)
		if s.sp_cost > 0: parts.append("%d SP" % s.sp_cost)
		if s.cooldown > 0: parts.append("%d turn cooldown" % s.cooldown)
		if s.type in [Skill.SkillType.DAMAGE, Skill.SkillType.HEAL, Skill.SkillType.RESTORE, Skill.SkillType.DRAIN]:
			parts.append("power %d" % s.power)
		if s.duration > 0 and s.type in [Skill.SkillType.BUFF, Skill.SkillType.DEBUFF, Skill.SkillType.INFLICT_STATUS]:
			parts.append("%d turns" % s.duration)
		if not parts.is_empty():
			t += "[color=%s]%s[/color]\n" % [MUTED, "  ·  ".join(parts)]
		if s.description != "":
			t += "%s\n" % s.description
		t += "\n"
	return t

func _equipment_text() -> String:
	var c = current_character
	var t := "[table=3]"
	for slot in c.equipment:
		var item = c.equipment[slot]
		var name_cell = "[color=%s]-[/color]" % MUTED
		var stat_cell = ""
		if item:
			name_cell = "[color=#%s]%s[/color]" % [ScreenChrome.rarity_color(item).to_html(false), item.display_name]
			if item.damage > 0: stat_cell = "%d damage" % item.damage
			elif item.armor_value > 0: stat_cell = "%d armor" % item.armor_value
		t += "[cell][color=%s]%s[/color][/cell][cell]%s[/cell][cell][color=%s]%s[/color][/cell]" % [MUTED, ScreenChrome.slot_name(slot), name_cell, MUTED, stat_cell]
	t += "[/table]\n\n[color=%s][i]Change gear from Town > Equipment.[/i][/color]" % MUTED
	return t

func _elements_text() -> String:
	var c = current_character
	if c.get("elemental_resistances") == null:
		return "[color=%s][i]Elemental data not set up for this character.[/i][/color]" % MUTED
	var t := "[table=3][cell][color=%s]Element[/color][/cell][cell][color=%s]Damage taken[/color][/cell][cell][color=%s]Damage dealt[/color][/cell]" % [MUTED, MUTED, MUTED]
	for element in ElementalDamage.Element.values():
		if element == ElementalDamage.Element.NONE:
			continue
		var taken = 1.0 - c.get_elemental_resistance(element) + c.get_elemental_weakness(element)
		var bonus = c.get_elemental_damage_bonus(element)
		var taken_text = "normal"
		if taken < 0.999:
			taken_text = "[color=%s]%d%% (resist)[/color]" % [GOOD, int(round(taken * 100))]
		elif taken > 1.001:
			taken_text = "[color=%s]%d%% (weak)[/color]" % [BAD, int(round(taken * 100))]
		var dealt_text = "[color=%s]+%d%%[/color]" % [GOOD, int(round(bonus * 100))] if bonus > 0.0 else "normal"
		t += "[cell][color=%s]%s[/color][/cell][cell]%s[/cell][cell]%s[/cell]" % [
			ElementalDamage.get_element_color(element), ElementalDamage.get_element_name(element), taken_text, dealt_text]
	return t + "[/table]"

func _proficiency_text() -> String:
	var pm = current_character.proficiency_manager
	if pm == null:
		return ""
	var t := "[color=%s]Using a weapon or armor type levels it up (max level %d).[/color]\n\n" % [MUTED, pm.MAX_LEVEL]
	t += "[b]Weapons & off-hands[/b]\n" + _prof_table(pm, pm.get_available_weapon_types(), true)
	t += "\n[b]Armor[/b]\n" + _prof_table(pm, pm.get_available_armor_types(), false)
	return t

func _prof_table(pm, keys: Array, weapons: bool) -> String:
	if keys.is_empty():
		return "[color=%s]None[/color]\n" % MUTED
	keys = keys.duplicate()
	keys.sort()
	var t := "[table=4]"
	for key in keys:
		var level = pm.get_weapon_proficiency_level(key) if weapons else pm.get_armor_proficiency_level(key)
		var uses = pm.get_weapon_proficiency_uses(key) if weapons else pm.get_armor_proficiency_uses(key)
		var bonus = (pm.WEAPON_DAMAGE_BONUS if weapons else pm.ARMOR_EFFECTIVENESS_BONUS).get(level, 0.0)
		var label = pm._format_weapon_name(key) if weapons else String(key).capitalize()
		var progress = "[color=%s]max[/color]" % ACCENT
		if level < pm.MAX_LEVEL:
			progress = "[color=%s]%d / %d uses[/color]" % [MUTED, uses, pm.LEVEL_THRESHOLDS[level - 1]]
		t += "[cell]%s[/cell][cell]Lv %d[/cell][cell]+%d%% %s[/cell][cell]%s[/cell]" % [
			label, level, int(round(bonus * 100)), "damage" if weapons else "armor", progress]
	return t + "[/table]\n"

func _on_exit_pressed():
	SceneManager.change_to_town(current_character)
