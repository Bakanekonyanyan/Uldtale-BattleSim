# res://scenes/EquipmentScene.gd
# Equipment screen, built in code on the ScreenChrome grid:
#   left    Equipped slots + a live summary of your combat stats
#   middle  Pack gear (click a slot to show only gear for that slot)
#   right   Item details, a comparison with what you're wearing, and actions
# Double-click equips (pack) or unequips (slot). The old .tscn nodes are hidden.
extends Control

const SLOTS := ["main_hand", "off_hand", "head", "chest", "hands", "legs", "feet"]
const GOOD := "#8fd46a"
const BAD := "#e07a5f"
const MUTED := "#a99f90"
const ACCENT := "#e5c34a"

var current_character: CharacterData
var chrome: ScreenChrome

var slot_filter := ""          # "" = show all pack gear
var pack_items: Array = []     # Equipment shown in pack_list, same order
var selected_item: Equipment = null
var selected_from_pack := false

var slot_list: ItemList
var stats_text: RichTextLabel
var pack_caption: Label
var show_all_button: Button
var pack_list: ItemList
var details: RichTextLabel
var equip_button: Button
var unequip_button: Button
var swap_hands_button: Button
var status_label: Label

func _ready():
	current_character = CharacterManager.get_current_character()
	if not current_character:
		push_error("EquipmentScene: no character loaded")
		return
	_build_ui()
	_refresh()

func set_player(character: CharacterData):
	current_character = character
	if is_node_ready() and chrome:
		_refresh()

# === UI CONSTRUCTION ===

func _build_ui() -> void:
	chrome = ScreenChrome.attach(self, "Equipment", _on_exit_pressed, "Back")
	for child in get_children():
		if child is ItemList or child is Button or child is RichTextLabel or child is Label:
			child.visible = false

	var ui := CanvasLayer.new()
	ui.name = "EquipmentUI"
	add_child(ui)

	# Left: equipped slots + stats
	ScreenChrome.caption(ui, "Equipped", Vector2(32, 72))
	slot_list = ItemList.new()
	ScreenChrome.place(slot_list, Rect2(32, 98, 340, 268))
	slot_list.item_selected.connect(_on_slot_selected)
	slot_list.item_activated.connect(_on_slot_activated)
	ui.add_child(slot_list)

	var stats_panel := Panel.new()
	ScreenChrome.place(stats_panel, Rect2(32, 380, 340, 244))
	ui.add_child(stats_panel)
	stats_text = RichTextLabel.new()
	stats_text.bbcode_enabled = true
	stats_text.scroll_active = false
	stats_text.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	stats_text.add_theme_constant_override("table_h_separation", 16)
	ScreenChrome.place(stats_text, Rect2(12, 10, 316, 226))
	stats_panel.add_child(stats_text)

	# Middle: pack gear
	pack_caption = ScreenChrome.caption(ui, "Pack", Vector2(388, 72))
	show_all_button = Button.new()
	show_all_button.text = "Show all"
	show_all_button.add_theme_font_size_override("font_size", 13)
	ScreenChrome.place(show_all_button, Rect2(616, 68, 92, 26))
	show_all_button.pressed.connect(func(): _set_filter(""))
	ui.add_child(show_all_button)
	pack_list = ItemList.new()
	ScreenChrome.place(pack_list, Rect2(388, 98, 320, 526))
	pack_list.item_selected.connect(_on_pack_selected)
	pack_list.item_activated.connect(_on_pack_activated)
	ui.add_child(pack_list)

	# Right: details + actions
	details = RichTextLabel.new()
	details.bbcode_enabled = true
	ScreenChrome.place(details, Rect2(724, 72, 444, 492))
	ui.add_child(details)
	equip_button = _button(ui, "Equip", Rect2(724, 576, 140, 44), _on_equip_pressed)
	unequip_button = _button(ui, "Unequip", Rect2(876, 576, 140, 44), _on_unequip_pressed)
	swap_hands_button = _button(ui, "Swap Hands", Rect2(1028, 576, 140, 44), _on_swap_hands_pressed)

	status_label = Label.new()
	ScreenChrome.place(status_label, Rect2(32, 648, 940, 32))
	status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	ui.add_child(status_label)

func _button(parent: Node, text: String, rect: Rect2, handler: Callable) -> Button:
	var b := Button.new()
	b.text = text
	ScreenChrome.place(b, rect)
	b.pressed.connect(handler)
	parent.add_child(b)
	return b

# === REFRESH ===

func _refresh() -> void:
	var c = current_character
	chrome.set_info(ScreenChrome.money_text(c))

	slot_list.clear()
	for slot in SLOTS:
		var item = c.equipment.get(slot)
		var idx: int
		if item:
			idx = slot_list.add_item("%s:  %s" % [ScreenChrome.slot_name(slot), item.display_name])
			slot_list.set_item_custom_fg_color(idx, ScreenChrome.rarity_color(item))
		else:
			idx = slot_list.add_item("%s:  -" % ScreenChrome.slot_name(slot))
			slot_list.set_item_custom_fg_color(idx, Color(MUTED))
		slot_list.set_item_tooltip(idx, "Click: show pack gear for this slot. Double-click: unequip.")

	pack_items.clear()
	pack_list.clear()
	for key in c.inventory.items:
		var item = c.inventory.items[key].item
		if not (item is Equipment) or not _fits_filter(item):
			continue
		var text = "%s  -  %s" % [ScreenChrome.slot_name(item.slot), ScreenChrome.item_row(item)]
		var idx = pack_list.add_item(text)
		pack_list.set_item_tooltip(idx, text + "\nDouble-click to equip.")
		if item.can_equip(c):
			pack_list.set_item_custom_fg_color(idx, ScreenChrome.rarity_color(item))
		else:
			pack_list.set_item_custom_fg_color(idx, Color(MUTED).darkened(0.25))
			pack_list.set_item_tooltip(idx, text + "\nYour class can't use this.")
		pack_items.append(item)
	if pack_items.is_empty():
		var idx = pack_list.add_item("No %sgear in your pack" % ("" if slot_filter == "" else ScreenChrome.slot_name(slot_filter).to_lower() + " "))
		pack_list.set_item_disabled(idx, true)
		pack_list.set_item_selectable(idx, false)
		pack_list.set_item_custom_fg_color(idx, Color(MUTED))
	pack_caption.text = "Pack" if slot_filter == "" else "Pack - %s" % ScreenChrome.slot_name(slot_filter)
	show_all_button.visible = slot_filter != ""

	# Keep the current selection highlighted after a refresh
	if selected_item:
		if selected_from_pack and selected_item in pack_items:
			pack_list.select(pack_items.find(selected_item))
		elif not selected_from_pack:
			var slot_index = _slot_of(selected_item)
			if slot_index >= 0:
				slot_list.select(slot_index)
			else:
				selected_item = null
		else:
			selected_item = null

	stats_text.text = _stats_text()
	_update_details()

func _fits_filter(item: Equipment) -> bool:
	if slot_filter == "":
		return true
	if item.slot == slot_filter:
		return true
	# Dual-wield weapons can go in either hand
	return slot_filter in ["main_hand", "off_hand"] and item.dual_wieldable and item.can_dual_wield(current_character)

func _slot_of(item: Equipment) -> int:
	for i in range(SLOTS.size()):
		if current_character.equipment.get(SLOTS[i]) == item:
			return i
	return -1

func _set_filter(slot: String) -> void:
	slot_filter = slot
	if selected_from_pack:
		selected_item = null
	_refresh()

# === DETAILS / COMPARISON ===

func _update_details() -> void:
	var c = current_character
	var item = selected_item
	equip_button.disabled = not (item and selected_from_pack and item.can_equip(c))
	unequip_button.disabled = not (item and not selected_from_pack)
	var main = c.equipment.get("main_hand")
	var off = c.equipment.get("off_hand")
	swap_hands_button.disabled = not (main and off and (main.dual_wieldable or off.dual_wieldable))

	if item == null:
		details.text = "[color=%s][i]Select gear in your pack to see how it compares with what you're wearing.\n\nClick a slot on the left to show only gear for that slot. Double-click to equip or unequip.[/i][/color]" % MUTED
		return

	var t = item.get_full_description()
	# The description uses raw rarity colors; swap in the readable ones
	if item.get_rarity_color() != "":
		t = t.replace("[color=%s]" % item.get_rarity_color(), "[color=#%s]" % ScreenChrome.rarity_color(item).to_html(false))
	if selected_from_pack:
		if not item.can_equip(c):
			t += "\n[color=%s][b]Your class can't use this.[/b][/color]\n" % BAD
		else:
			t += "\n" + _comparison_text(item, c.equipment.get(item.slot))
	details.text = t

## Item-vs-item differences: damage, armor, attribute and secondary bonuses.
func _comparison_text(new_item: Equipment, old_item) -> String:
	var t = "[b][color=%s]If you equip this[/color][/b]" % ACCENT
	if old_item == null:
		return t + "  [color=%s](%s slot is empty)[/color]\n%s" % [MUTED, ScreenChrome.slot_name(new_item.slot), _delta_lines(_item_stats(new_item), {})]
	t += "  [color=%s]replaces %s[/color]\n" % [MUTED, old_item.display_name]
	var lines = _delta_lines(_item_stats(new_item), _item_stats(old_item))
	return t + (lines if lines != "" else "[color=%s]No stat difference.[/color]\n" % MUTED)

func _item_stats(item: Equipment) -> Dictionary:
	var s := {}
	if item.damage > 0: s["Damage"] = float(item.damage)
	if item.armor_value > 0: s["Armor"] = float(item.armor_value)
	for stat in item.stat_modifiers:
		var name = Skill.AttributeTarget.keys()[stat].capitalize()
		s[name] = s.get(name, 0.0) + float(item.stat_modifiers[stat])
	var flat = item.get_flat_bonuses()
	for stat in flat:
		var name = String(stat).replace("_", " ").capitalize()
		s[name] = s.get(name, 0.0) + float(flat[stat])
	if item.status_effect_type != Skill.StatusEffect.NONE:
		s["%s chance" % Skill.StatusEffect.keys()[item.status_effect_type].capitalize()] = item.status_effect_chance
	return s

func _delta_lines(new_stats: Dictionary, old_stats: Dictionary) -> String:
	var keys = new_stats.keys()
	for k in old_stats:
		if not k in keys:
			keys.append(k)
	var t := ""
	for k in keys:
		var d = new_stats.get(k, 0.0) - old_stats.get(k, 0.0)
		if abs(d) < 0.0001:
			continue
		var is_pct = abs(new_stats.get(k, 0.0)) < 1.0 and abs(old_stats.get(k, 0.0)) < 1.0
		var amount = ("%+d%%" % int(round(d * 100))) if is_pct else ("%+d" % int(round(d)))
		t += "  [color=%s]%s %s[/color]\n" % [GOOD if d > 0 else BAD, amount, k]
	return t

func _stats_text() -> String:
	var c = current_character
	var phys = BattleFormulas.physical_defense(c)
	var mag = BattleFormulas.magical_defense(c)
	var rows = [
		["Physical attack", "%d" % int(BattleFormulas.physical_offense(c))],
		["Spell power", "%d" % int(c.spell_power)],
		["Physical defense", "%d  [color=%s](take %d%%)[/color]" % [int(round(phys)), MUTED, int(round(BattleFormulas.mitigation(phys) * 100))]],
		["Magic defense", "%d  [color=%s](take %d%%)[/color]" % [int(round(mag)), MUTED, int(round(BattleFormulas.mitigation(mag) * 100))]],
		["Accuracy", "%d%%" % int(round(c.accuracy * 100))],
		["Dodge", "%d%%" % int(round(c.dodge * 100))],
		["Critical hit", "%d%%" % int(round(c.critical_hit_rate * 100))],
	]
	if BattleFormulas.get_armor_penetration(c) > 0.0:
		rows.append(["Armor penetration", "%d%%" % int(round(BattleFormulas.get_armor_penetration(c) * 100))])
	var t := "[color=%s][font_size=14]YOUR STATS[/font_size][/color]\n[table=2]" % ACCENT
	for r in rows:
		t += "[cell]%s[/cell][cell][b]%s[/b][/cell]" % r
	return t + "[/table]"

# === ACTIONS ===

func _on_slot_activated(index: int) -> void:
	_on_slot_selected(index)
	_on_unequip_pressed()

func _on_pack_activated(index: int) -> void:
	_on_pack_selected(index)
	_on_equip_pressed()

func _on_slot_selected(index: int) -> void:
	if index < 0 or index >= SLOTS.size():
		return
	pack_list.deselect_all()
	selected_item = current_character.equipment.get(SLOTS[index])
	selected_from_pack = false
	status_label.text = ""
	if slot_filter != SLOTS[index]:
		_set_filter(SLOTS[index])
		slot_list.select(index)
	else:
		_update_details()

func _on_pack_selected(index: int) -> void:
	if index < 0 or index >= pack_items.size():
		return
	slot_list.deselect_all()
	selected_item = pack_items[index]
	selected_from_pack = true
	status_label.text = ""
	_update_details()

func _on_equip_pressed() -> void:
	var item = selected_item
	if item == null or not selected_from_pack:
		return
	if not item.can_equip(current_character):
		status_label.text = "Your class can't use %s." % item.display_name
		return
	current_character.equip_item(item)
	if _slot_of(item) >= 0:
		status_label.text = "Equipped %s." % item.display_name
		selected_from_pack = false   # keep it selected, now as the worn item
	else:
		status_label.text = "Couldn't equip %s - your main-hand weapon blocks the off hand." % item.display_name
		selected_item = null
	_refresh()

func _on_unequip_pressed() -> void:
	var item = selected_item
	if item == null or selected_from_pack:
		return
	var index = _slot_of(item)
	if index < 0:
		return
	current_character.unequip_item(SLOTS[index])
	status_label.text = "Moved %s to your pack." % item.display_name
	selected_from_pack = true
	_refresh()

func _on_swap_hands_pressed() -> void:
	if current_character.swap_hands():
		status_label.text = "Swapped main hand and off hand."
	else:
		status_label.text = "Those two can't swap hands."
	selected_item = null
	_refresh()

func _on_exit_pressed():
	CharacterManager.save_character(current_character)
	SceneManager.return_to_previous_scene()

func get_equipment_from_inventory() -> Array:
	var items = []
	for key in current_character.inventory.items:
		if current_character.inventory.items[key].item is Equipment:
			items.append(current_character.inventory.items[key].item)
	return items
