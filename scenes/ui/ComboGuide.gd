# res://scenes/ui/ComboGuide.gd
# Combo reference (data/combos.json): every set-up -> payoff pair, its bonus,
# and which of YOUR heroes' skills set it up or pay it off. In battle it also
# shows which enemies are primed for a combo right now.
# Open with ComboGuide.open(parent, heroes, enemies). Built in code.
class_name ComboGuide
extends CanvasLayer

var heroes: Array = []
var enemies: Array = []
var ids: Array = []
var list: ItemList
var details: RichTextLabel
var show_all := false

static func open(parent: Node, p_heroes: Array, p_enemies: Array = []) -> ComboGuide:
	var g = ComboGuide.new()
	g.heroes = p_heroes.filter(func(h): return h != null)
	g.enemies = p_enemies.filter(func(e): return e != null)
	parent.add_child(g)
	return g

func _ready() -> void:
	layer = 60
	var dim = ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.size = Vector2(1200, 720)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	var panel = Panel.new()
	panel.position = Vector2(80, 50)
	panel.size = Vector2(1040, 620)
	add_child(panel)
	var title = Label.new()
	title.text = "Combos"
	title.position = Vector2(24, 12)
	title.add_theme_font_size_override("font_size", 24)
	panel.add_child(title)
	var hint = Label.new()
	hint.text = "Combos your party can use now.  ⚡ = an enemy is primed, ★ = you can set it up and pay it off."
	hint.position = Vector2(150, 20)
	hint.add_theme_font_size_override("font_size", 14)
	hint.modulate = Color(0.75, 0.72, 0.65)
	panel.add_child(hint)
	list = ItemList.new()
	list.position = Vector2(20, 60)
	list.size = Vector2(330, 490)
	list.item_selected.connect(_show)
	panel.add_child(list)
	details = RichTextLabel.new()
	details.bbcode_enabled = true
	details.position = Vector2(370, 60)
	details.size = Vector2(650, 490)
	panel.add_child(details)
	var all_box = CheckBox.new()
	all_box.text = "Show all combos"
	all_box.position = Vector2(20, 566)
	all_box.toggled.connect(func(on):
		show_all = on
		_fill())
	panel.add_child(all_box)
	var close = Button.new()
	close.text = "Close"
	close.custom_minimum_size = Vector2(150, 40)
	close.position = Vector2(870, 564)
	close.pressed.connect(queue_free)
	panel.add_child(close)
	_fill()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		queue_free()
		get_viewport().set_input_as_handled()

## Usable = you can pay it off, and your party can set it up or an enemy
## already carries the set-up status.
func is_available(c: Dictionary) -> bool:
	return not _payers(c).is_empty() and (not _setters(c).is_empty() or not _primed(c).is_empty())

func _fill() -> void:
	list.clear()
	var all = Combos.all()
	ids = all.keys().filter(func(k): return not String(k).begins_with("_") and (show_all or is_available(all[k])))
	# primed right now first, then ones your party can do, then the rest
	ids.sort_custom(func(a, b):
		var ka = _sort_key(a)
		var kb = _sort_key(b)
		return ka < kb if ka != kb else String(all[a].name) < String(all[b].name))
	for id in ids:
		var c: Dictionary = all[id]
		var mark = ""
		if not _primed(c).is_empty():
			mark = "⚡ "
		elif not _setters(c).is_empty() and not _payers(c).is_empty():
			mark = "★ "
		var idx = list.add_item("%s%s  (%s → x%.1f)" % [mark, c.get("name", id), _status_name(String(c.setup)), float(c.get("multiplier", 1.0))])
		if mark == "⚡ ":
			list.set_item_custom_fg_color(idx, Color(1.0, 0.85, 0.4))
		elif mark == "★ ":
			list.set_item_custom_fg_color(idx, Color(0.6, 1.0, 0.6))
	if not ids.is_empty():
		list.select(0)
		_show(0)
	else:
		details.text = "[i]Your party has no combo it can use right now.[/i]\n\nCombos need a skill that sets up a status (Freeze, Bleed, Shock...) and one that pays it off. Tick [b]Show all combos[/b] to see what to look for in talents and companions."

func _sort_key(id) -> int:
	var c: Dictionary = Combos.all()[id]
	if not _primed(c).is_empty():
		return 0
	if not _setters(c).is_empty() and not _payers(c).is_empty():
		return 1
	return 2

func _status_name(s: String) -> String:
	return s.capitalize()

## Skills (any hero) that inflict the set-up status: ["Mira: Frost Nova", ...]
func _setters(c: Dictionary) -> Array:
	var out: Array = []
	var want = String(c.setup)
	for h in heroes:
		for sn in h.get_battle_skills():
			var s: Skill = h.get_skill_instance(sn)
			if s == null:
				continue
			for st in s.status_effects:
				if Skill.StatusEffect.keys()[st] == want:
					out.append(_who(h, s.name))
					break
	return out

## Skills (any hero) whose hit pays the combo off, plus basic attacks.
func _payers(c: Dictionary) -> Array:
	var out: Array = []
	for h in heroes:
		if Combos._matches(c.get("payoff", {}), Combos.hit_from_attack(h)):
			out.append(_who(h, "Attack"))
		for sn in h.get_battle_skills():
			var s: Skill = h.get_skill_instance(sn)
			if s and s.type in [Skill.SkillType.DAMAGE, Skill.SkillType.DRAIN, Skill.SkillType.DEBUFF] \
					and Combos._matches(c.get("payoff", {}), Combos.hit_from_skill(h, s)):
				out.append(_who(h, s.name))
	return out

func _who(h: CharacterData, what: String) -> String:
	return what if heroes.size() <= 1 else "%s: %s" % [h.name.get_slice(" ", 0), what]

## Enemies that currently carry this combo's set-up status.
func _primed(c: Dictionary) -> Array:
	var out: Array = []
	var idx = Skill.StatusEffect.keys().find(String(c.setup))
	for e in enemies:
		if e.is_alive() and e.status_manager and idx >= 0 and e.status_manager.has_effect(idx):
			out.append(e.name)
	return out

func _payoff_text(p: Dictionary) -> String:
	var parts: Array = []
	if not p.get("elements", []).is_empty():
		parts.append("%s element" % " / ".join(p.elements.map(func(x): return String(x).capitalize())))
	if not p.get("damage_types", []).is_empty():
		parts.append("%s damage" % " / ".join(p.damage_types.map(func(x): return String(x).capitalize())))
	if not p.get("ability_types", []).is_empty():
		parts.append("any %s hit" % " / ".join(p.ability_types.map(func(x): return String(x).to_lower())))
	if not p.get("skills", []).is_empty():
		parts.append("the skill%s %s" % ["" if p.skills.size() == 1 else "s", ", ".join(p.skills)])
	return " or ".join(parts) if not parts.is_empty() else "?"

func _show(i: int) -> void:
	if i < 0 or i >= ids.size():
		return
	var c: Dictionary = Combos.all()[ids[i]]
	var t = "[b][font_size=22]%s[/font_size][/b]\n[i]%s[/i]\n\n" % [c.get("name", ids[i]), c.get("description", "")]
	t += "[b]1. Set up:[/b] the target has [color=#e9c46a]%s[/color]\n" % _status_name(String(c.setup))
	t += "[b]2. Pay off:[/b] hit it with %s\n" % _payoff_text(c.get("payoff", {}))
	t += "[b]Bonus:[/b] [color=#7bd389]x%.1f damage[/color]%s\n\n" % [float(c.get("multiplier", 1.0)), "  (uses up the status)" if c.get("consume", false) else "  (the status stays)"]
	var primed = _primed(c)
	if not primed.is_empty():
		t += "[color=#ffd166][b]Ready now:[/b] %s[/color]\n\n" % ", ".join(primed)
	var setters = _setters(c)
	var payers = _payers(c)
	t += "[b]Your set-ups:[/b] %s\n" % (", ".join(setters) if not setters.is_empty() else "[color=gray]none in your loadout - items, allies or the enemy may still apply it[/color]")
	t += "[b]Your payoffs:[/b] %s\n" % (", ".join(payers) if not payers.is_empty() else "[color=gray]none in your loadout[/color]")
	details.text = t
