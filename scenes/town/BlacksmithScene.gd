# res://scenes/town/BlacksmithScene.gd
# Blacksmith screen: upgrade gear (with optional reinforcement) or salvage it.
# All rules live in BlacksmithManager; this script only builds and updates the UI.
# Uses the shop background until dedicated art exists.
extends Control

enum Mode { UPGRADE, SALVAGE }

var player_character: CharacterData
var mode: Mode = Mode.UPGRADE
var gear: Array = []            # entries from BlacksmithManager.list_gear (filtered)
var selected: Equipment = null

# UI (built in code)
var money_label: Label
var upgrade_tab: Button
var salvage_tab: Button
var gear_list: ItemList
var details: RichTextLabel
var reinforce_label: Label
var reinforce_spin: SpinBox
var action_button: Button
var status_label: Label
var confirm_dialog: ConfirmationDialog

func _ready():
	_build_ui()
	if player_character == null:
		player_character = CharacterManager.get_current_character()
	_refresh()

## Called by SceneManager when navigating here.
func set_player(character: CharacterData) -> void:
	player_character = character
	if is_node_ready():
		_refresh()

# === UI CONSTRUCTION ===

func _build_ui() -> void:
	var ui: CanvasLayer = $UI
	_label(ui, "Blacksmith", Vector2(40, 16), 28)
	money_label = _label(ui, "", Vector2(760, 24), 18)

	upgrade_tab = _button(ui, "Upgrade", Vector2(40, 68), func(): _set_mode(Mode.UPGRADE), Vector2(140, 36))
	salvage_tab = _button(ui, "Salvage", Vector2(190, 68), func(): _set_mode(Mode.SALVAGE), Vector2(140, 36))
	upgrade_tab.toggle_mode = true
	salvage_tab.toggle_mode = true

	gear_list = ItemList.new()
	gear_list.position = Vector2(40, 112)
	gear_list.size = Vector2(420, 500)
	gear_list.item_selected.connect(_on_gear_selected)
	ui.add_child(gear_list)

	var panel = Panel.new()
	panel.position = Vector2(490, 72)
	panel.size = Vector2(670, 440)
	ui.add_child(panel)
	details = RichTextLabel.new()
	details.bbcode_enabled = true
	details.position = Vector2(16, 12)
	details.size = Vector2(640, 416)
	panel.add_child(details)

	reinforce_label = _label(ui, "Reinforce:", Vector2(490, 532), 16)
	reinforce_spin = SpinBox.new()
	reinforce_spin.position = Vector2(580, 526)
	reinforce_spin.custom_minimum_size = Vector2(100, 36)
	reinforce_spin.min_value = 0
	reinforce_spin.value_changed.connect(func(_v): _update_details())
	ui.add_child(reinforce_spin)

	action_button = _button(ui, "Upgrade", Vector2(700, 526), _on_action_pressed)
	_button(ui, "Back to Town", Vector2(980, 640), _on_back_pressed)

	status_label = _label(ui, "", Vector2(490, 580), 16)
	status_label.size = Vector2(670, 50)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD

	confirm_dialog = ConfirmationDialog.new()
	confirm_dialog.title = "Salvage"
	confirm_dialog.confirmed.connect(_do_salvage)
	ui.add_child(confirm_dialog)

func _label(parent: Node, text: String, pos: Vector2, font_size: int) -> Label:
	var l = Label.new()
	l.text = text
	l.position = pos
	l.add_theme_font_size_override("font_size", font_size)
	parent.add_child(l)
	return l

func _button(parent: Node, text: String, pos: Vector2, handler: Callable, min_size := Vector2(150, 40)) -> Button:
	var b = Button.new()
	b.text = text
	b.position = pos
	b.custom_minimum_size = min_size
	b.pressed.connect(handler)
	parent.add_child(b)
	return b

# === REFRESH ===

func _set_mode(new_mode: Mode) -> void:
	mode = new_mode
	status_label.text = ""
	_refresh()

func _refresh() -> void:
	if player_character == null or gear_list == null:
		return
	upgrade_tab.button_pressed = mode == Mode.UPGRADE
	salvage_tab.button_pressed = mode == Mode.SALVAGE
	money_label.text = "Money: %s" % player_character.currency.get_formatted()

	gear.clear()
	gear_list.clear()
	for entry in BlacksmithManager.list_gear(player_character):
		if mode == Mode.SALVAGE and entry.where == "equipped":
			continue  # can't salvage what you're wearing
		var item: Equipment = entry.item
		var tag = "Equipped" if entry.where == "equipped" else entry.where.capitalize()
		var text = "[%s] %s" % [tag, item.display_name]
		if mode == Mode.UPGRADE:
			text += "  (+%d/+%d)" % [item.upgrade_level, BlacksmithManager.get_max_level(item)]
		var idx = gear_list.add_item(text)
		# Lighten rarity colors so dark ones (uncommon blue) stay readable
		gear_list.set_item_custom_fg_color(idx, _readable(item.get_rarity_color()))
		gear.append(entry)

	var keep = -1
	for i in range(gear.size()):
		if gear[i].item == selected:
			keep = i
	if keep < 0 and not gear.is_empty():
		keep = 0
	if keep >= 0:
		gear_list.select(keep)
		selected = gear[keep].item
	else:
		selected = null
	_update_details()

func _update_details() -> void:
	var upgrading = mode == Mode.UPGRADE
	reinforce_label.visible = upgrading
	reinforce_spin.visible = upgrading
	action_button.text = "Upgrade" if upgrading else "Salvage"

	if selected == null:
		details.text = "[i]You have no gear to %s.[/i]" % ("upgrade" if upgrading else "salvage")
		action_button.disabled = true
		return

	var item = selected
	var t = "[b][font_size=22]%s[/font_size][/b]\n" % item.display_name
	t += "[color=#%s]%s[/color]   Item level %d\n\n" % [_readable(item.get_rarity_color()).to_html(false), item.rarity.capitalize(), item.item_level]

	if upgrading:
		t += _upgrade_text(item)
	else:
		var p = BlacksmithManager.get_salvage_preview(item)
		var ore = ItemManager.get_item(p.ore_id)
		t += "[b]Salvage yields:[/b]\n  %d-%d x %s\n" % [p.ore_min, p.ore_max, ore.display_name if ore else p.ore_id]
		if p.core_chance > 0.0:
			t += "  %d%% chance of a Monster Core\n" % int(round(p.core_chance * 100))
		if item.upgrade_level > 0:
			t += "\n[color=orange]This item is +%d - its upgrades are lost when salvaged.[/color]\n" % item.upgrade_level
		action_button.disabled = false
	details.text = t

func _upgrade_text(item: Equipment) -> String:
	var t = "[b]Upgrade level:[/b] +%d / +%d\n" % [item.upgrade_level, BlacksmithManager.get_max_level(item)]
	if not BlacksmithManager.can_upgrade(item):
		action_button.disabled = true
		reinforce_spin.max_value = 0
		return t + "\n[color=gold]Fully upgraded.[/color]"

	var max_steps = BlacksmithManager.steps_to_guarantee(item)
	reinforce_spin.max_value = max_steps
	reinforce_spin.editable = max_steps > 0
	var steps = int(reinforce_spin.value)

	# Before / after preview (same math as Equipment.set_upgrade_level)
	item.ensure_upgrade_base()
	var next = item.upgrade_level + 1
	if item.base_damage > 0:
		t += "[b]Damage:[/b] %d -> [color=lime]%d[/color]\n" % [item.damage, int(round(item.base_damage * (1.0 + Equipment.UPGRADE_STEP * next)))]
	if item.base_armor > 0:
		t += "[b]Armor:[/b] %d -> [color=lime]%d[/color]\n" % [item.armor_value, int(round(item.base_armor * (1.0 + Equipment.UPGRADE_STEP * next)))]
	# Caster off-hands etc.: attribute bonuses scale with upgrades too
	var now_b = item.get_flat_bonuses()
	var saved_level = item.upgrade_level
	item.upgrade_level = next
	var next_b = item.get_flat_bonuses()
	item.upgrade_level = saved_level
	for stat in now_b:
		if _fmt(now_b[stat]) != _fmt(next_b.get(stat, 0.0)):  # hide lines that don't visibly change
			t += "[b]%s:[/b] +%s -> [color=lime]+%s[/color]\n" % [stat.capitalize(), _fmt(now_b[stat]), _fmt(next_b[stat])]

	var cost = BlacksmithManager.get_upgrade_cost(item, steps)
	t += "\n[b]Cost for +%d%s:[/b]\n" % [next, "" if steps == 0 else " (reinforced x%d)" % steps]
	var gold_ok = player_character.currency.copper >= cost.gold
	t += "  [color=%s]%s[/color]\n" % ["lime" if gold_ok else "salmon", Currency.format_copper(cost.gold)]
	for id in cost.materials:
		var have = player_character.count_owned(id)
		var mat = ItemManager.get_item(id)
		t += "  [color=%s]%s  %d / %d[/color]\n" % ["lime" if have >= cost.materials[id] else "salmon", mat.display_name if mat else id, have, cost.materials[id]]

	var chance = BlacksmithManager.get_success_chance(item, steps)
	var color = "lime" if chance >= 1.0 else ("yellow" if chance >= 0.6 else "orange")
	t += "\n[b]Success chance:[/b] [color=%s]%d%%[/color]" % [color, int(round(chance * 100))]
	if item.tempered > 0:
		t += "   [color=cyan](Tempered x%d included)[/color]" % item.tempered
	if max_steps > 0:
		t += "\n[color=gray]Each reinforcement step pays +25%% of the cost for +10%% success (%d step%s = guaranteed).[/color]" % [max_steps, "" if max_steps == 1 else "s"]
	if item.upgrade_level >= int(BlacksmithManager.cfg.get("downgrade_from_level", 7)) and chance < 1.0:
		t += "\n[color=orange]Warning: failing at +%d drops this item to +%d.[/color]" % [item.upgrade_level, item.upgrade_level - 1]

	action_button.disabled = not BlacksmithManager.can_afford(player_character, cost)
	return t

## Rarity colors lightened so dark ones (uncommon blue) stay readable on the backdrop.
func _readable(rarity_color: String) -> Color:
	return Color(rarity_color).lerp(Color.WHITE, 0.45) if rarity_color != "" else Color.WHITE

func _fmt(v: float) -> String:
	return str(int(round(v))) if v >= 1.0 else "%.0f%%" % (v * 100.0)

# === ACTIONS ===

func _on_gear_selected(index: int) -> void:
	if index >= 0 and index < gear.size():
		selected = gear[index].item
		reinforce_spin.value = 0
		_update_details()

func _on_action_pressed() -> void:
	if selected == null:
		return
	if mode == Mode.UPGRADE:
		var result = BlacksmithManager.upgrade(player_character, selected, int(reinforce_spin.value))
		status_label.text = result.reason
		reinforce_spin.value = 0
		_refresh()
	else:
		confirm_dialog.dialog_text = "Salvage %s? This destroys the item." % selected.display_name
		confirm_dialog.popup_centered()

func _do_salvage() -> void:
	var result = BlacksmithManager.salvage(player_character, selected)
	status_label.text = result.reason
	selected = null
	_refresh()

func _on_back_pressed() -> void:
	SaveManager.save_game(player_character)
	SceneManager.change_to_town(player_character)
