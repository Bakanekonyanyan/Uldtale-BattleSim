# res://scenes/LevelUpScene.gd
# Spend attribute points: shown after a battle that levels you up, and from
# Character > Status ("Spend points"). Each row shows what +1 does right now,
# the class's key attributes are marked, and the next attribute passive
# (data/thresholds.json) is shown with how far off it is. Points can be kept
# for later.
#   var s = load("res://scenes/LevelUpScene.tscn").instantiate()
#   parent.add_child(s); s.setup(character, true); await s.level_up_complete
extends Control

signal level_up_complete

const ATTRS := ["vitality", "strength", "dexterity", "intelligence", "faith", "mind", "endurance", "arcane", "agility", "fortitude"]
const PANEL := Rect2(96, 40, 1008, 640)

var character: CharacterData
var initial_attributes := {}
var leveled := true

var title_label: Label
var gains_label: RichTextLabel
var points_label: Label
var rows := {}          # attr -> {value, effect, next, minus, plus}
var done_button: Button
var later_button: Button
var reset_button: Button

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	size = Vector2(1200, 720)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.72)
	dim.size = size
	add_child(dim)
	var panel := Panel.new()
	ScreenChrome.place(panel, PANEL)
	add_child(panel)
	var box := VBoxContainer.new()
	ScreenChrome.place(box, Rect2(24, 16, PANEL.size.x - 48, PANEL.size.y - 32))
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)
	title_label = Label.new()
	title_label.theme_type_variation = "ScreenTitle"
	box.add_child(title_label)
	gains_label = RichTextLabel.new()
	gains_label.bbcode_enabled = true
	gains_label.fit_content = true
	gains_label.custom_minimum_size = Vector2(0, 48)
	box.add_child(gains_label)
	points_label = Label.new()
	points_label.add_theme_color_override("font_color", ScreenChrome.ACCENT)
	box.add_child(points_label)
	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 4)
	box.add_child(grid)
	for a in ATTRS:
		var name_l := Label.new()
		name_l.custom_minimum_size = Vector2(150, 0)
		name_l.name = "Name_" + a
		var value_l := Label.new()
		value_l.custom_minimum_size = Vector2(44, 0)
		value_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		var minus := Button.new()
		minus.text = "-"
		minus.custom_minimum_size = Vector2(44, 36)
		minus.pressed.connect(_change.bind(a, -1))
		var plus := Button.new()
		plus.text = "+"
		plus.custom_minimum_size = Vector2(44, 36)
		plus.pressed.connect(_change.bind(a, 1))
		var effect := Label.new()
		effect.custom_minimum_size = Vector2(330, 0)
		effect.add_theme_font_size_override("font_size", 15)
		var nxt := Label.new()
		nxt.custom_minimum_size = Vector2(250, 0)
		nxt.add_theme_font_size_override("font_size", 15)
		nxt.add_theme_color_override("font_color", ScreenChrome.MUTED)
		for n in [name_l, value_l, minus, plus, effect, nxt]:
			grid.add_child(n)
		rows[a] = {"name": name_l, "value": value_l, "minus": minus, "plus": plus, "effect": effect, "next": nxt}
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(spacer)
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 12)
	foot.alignment = BoxContainer.ALIGNMENT_END
	box.add_child(foot)
	reset_button = _button("Reset", _reset)
	later_button = _button("Spend later", _finish)
	later_button.tooltip_text = "Keep your points: spend them any time from Character > Status."
	done_button = _button("Done", _finish)
	for b in [reset_button, later_button, done_button]:
		foot.add_child(b)

func _button(t: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = t
	b.custom_minimum_size = Vector2(160, 48)
	b.pressed.connect(cb)
	return b

## `leveled`: opened by a level-up (shows what the level gave you).
func setup(char1: CharacterData, just_leveled := true) -> void:
	character = char1
	leveled = just_leveled
	for a in ATTRS:
		initial_attributes[a] = int(character.get(a))
	update_ui()

func _key_attributes() -> Array:
	var keys: Array = [String(character.attack_power_type), String(character.spell_power_type)]
	var cd: Dictionary = DataRegistry.get_data("classes").get("playable", {}).get(character.character_class, {})
	var bases: Array = []
	for a in ATTRS:
		bases.append([int(cd.get("base_" + a.substr(0, 3), 0)), a])
	bases.sort()
	bases.reverse()
	for i in range(min(3, bases.size())):
		if not keys.has(bases[i][1]):
			keys.append(bases[i][1])
	return keys

func update_ui() -> void:
	if character == null:
		return
	title_label.text = ("Level %d!" % character.level) if leveled else "Attribute Points"
	var g := ""
	if leveled:
		g = "Every attribute rose by 1, and you have points to spend. "
		var tp = character.talents.available_points() if character.talents else 0
		if tp > 0:
			g += "[color=#e5c34a]%d talent point%s waiting[/color] (Character > Talents). " % [tp, "" if tp == 1 else "s"]
	g += "[color=#a99f90]★ marks what your class leans on.[/color]"
	gains_label.text = g
	points_label.text = "Points to spend: %d" % character.attribute_points
	var keys = _key_attributes()
	var base = _snapshot()
	for a in ATTRS:
		var r = rows[a]
		r.name.text = ("★ " if a in keys else "   ") + a.capitalize()
		if a in keys:
			r.name.add_theme_color_override("font_color", ScreenChrome.ACCENT)
		var added = int(character.get(a)) - int(initial_attributes[a])
		r.value.text = str(character.get(a)) + ("" if added == 0 else "")
		r.value.add_theme_color_override("font_color", Color("88dd88") if added > 0 else Color("e6dccb"))
		r.minus.disabled = added <= 0
		r.plus.disabled = character.attribute_points <= 0
		r.effect.text = "+1: " + _effect_text(a, base)
		r.next.text = _next_threshold(a)
	done_button.disabled = character.attribute_points > 0
	later_button.visible = character.attribute_points > 0
	reset_button.disabled = ATTRS.all(func(x): return int(character.get(x)) == int(initial_attributes[x]))

func _snapshot() -> Dictionary:
	var c = character
	return {
		"HP": float(c.max_hp), "MP": float(c.max_mp), "SP": float(c.max_sp),
		"Attack": BattleFormulas.physical_offense(c), "Spell": BattleFormulas.magical_offense(c),
		"Def": BattleFormulas.physical_defense(c), "M.Def": BattleFormulas.magical_defense(c),
		"Acc": c.accuracy * 100.0, "Dodge": c.dodge * 100.0, "Crit": c.critical_hit_rate * 100.0,
	}

## What +1 in `attr` changes, measured on the character itself.
func _effect_text(attr: String, base: Dictionary) -> String:
	character.set(attr, int(character.get(attr)) + 1)
	character.calculate_secondary_attributes()
	var after = _snapshot()
	character.set(attr, int(character.get(attr)) - 1)
	character.calculate_secondary_attributes()
	var bits: Array = []
	for k in base:
		var d = float(after[k]) - float(base[k])
		if k in ["Acc", "Dodge", "Crit"]:
			if absf(d) >= 0.05:
				bits.append("%s %+.1f%%" % [k, d])
		elif absf(d) >= 0.5:
			bits.append("%s %+d" % [k, int(round(d))])
	return ", ".join(bits) if not bits.is_empty() else "small gains"

## The next attribute passive for `attr`, if any.
func _next_threshold(attr: String) -> String:
	var have = character.talents.raw_attribute(attr) if character.talents else int(character.get(attr))
	for p in TalentManager.threshold_passives():
		if String(p.attribute) == attr and int(p.at) > have:
			return "%s at %d (%d to go)" % [p.get("name", p.id), int(p.at), int(p.at) - have]
	return ""

func _change(attr: String, delta: int) -> void:
	if delta > 0 and character.attribute_points > 0:
		character.spend_attribute_point(attr)
	elif delta < 0 and int(character.get(attr)) > int(initial_attributes[attr]):
		character.set(attr, int(character.get(attr)) - 1)
		character.attribute_points += 1
		character.calculate_secondary_attributes()
	update_ui()

func _reset() -> void:
	for a in ATTRS:
		var extra = int(character.get(a)) - int(initial_attributes[a])
		if extra > 0:
			character.set(a, int(initial_attributes[a]))
			character.attribute_points += extra
	character.calculate_secondary_attributes()
	update_ui()

func _finish() -> void:
	level_up_complete.emit()
	queue_free()

## Back to the old behaviour for callers that free the scene themselves.
func _on_done_pressed() -> void:
	_finish()
