# res://scenes/town/EnchanterScene.gd
# Enchanter screen: pick an item and an enchantment (the material decides the
# effect), see the cost, chance and result, then enchant. All rules live in
# EnchantManager; this script only builds and updates the UI.
# Uses the shop background until dedicated art exists.
extends Control

var player_character: CharacterData
var gear: Array = []            # entries from BlacksmithManager.list_gear
var selected: Equipment = null
var enchant_ids: Array = []

# UI (built in code)
var money_label: Label
var gear_list: ItemList
var details: RichTextLabel
var enchant_pick: OptionButton
var action_button: Button
var status_label: Label

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
	money_label = ScreenChrome.attach(self, "Enchanter", _on_back_pressed).info_label

	var hint = Label.new()
	hint.text = "Raise an item one rarity tier (up to Epic) and add an enchantment. The material decides the effect."
	hint.position = Vector2(32, 78)
	hint.add_theme_font_size_override("font_size", 14)
	hint.modulate = Color(0.8, 0.76, 0.68)
	ui.add_child(hint)

	gear_list = ItemList.new()
	ScreenChrome.place(gear_list, ScreenChrome.LIST_RECT)
	gear_list.item_selected.connect(_on_gear_selected)
	ui.add_child(gear_list)

	var panel = Panel.new()
	panel.position = Vector2(496, 104)
	panel.size = Vector2(672, 408)
	ui.add_child(panel)
	details = RichTextLabel.new()
	details.bbcode_enabled = true
	details.position = Vector2(16, 12)
	details.size = Vector2(640, 384)
	panel.add_child(details)

	var pick_label = Label.new()
	pick_label.text = "Enchantment:"
	pick_label.position = Vector2(496, 532)
	pick_label.add_theme_font_size_override("font_size", 16)
	ui.add_child(pick_label)
	enchant_pick = OptionButton.new()
	enchant_pick.position = Vector2(610, 526)
	enchant_pick.custom_minimum_size = Vector2(300, 36)
	enchant_pick.item_selected.connect(func(_i): _update_details())
	ui.add_child(enchant_pick)

	action_button = Button.new()
	action_button.text = "Enchant"
	action_button.position = Vector2(930, 524)
	action_button.custom_minimum_size = Vector2(150, 40)
	action_button.pressed.connect(_on_enchant_pressed)
	ui.add_child(action_button)

	status_label = Label.new()
	status_label.position = Vector2(496, 580)
	status_label.size = Vector2(670, 50)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	status_label.add_theme_font_size_override("font_size", 16)
	ui.add_child(status_label)

# === REFRESH ===

func _refresh() -> void:
	if player_character == null or gear_list == null:
		return
	money_label.text = "Money: %s" % player_character.currency.get_formatted()
	_fill_enchants()
	gear.clear()
	gear_list.clear()
	for entry in BlacksmithManager.list_gear(player_character):
		var item: Equipment = entry.item
		var tag = "Equipped" if entry.where == "equipped" else entry.where.capitalize()
		var nxt = EnchantManager.next_rarity(item)
		var idx = gear_list.add_item("[%s] %s  (%s)" % [tag, item.display_name, item.rarity.capitalize() + (" → " + nxt.capitalize() if nxt != "" else ", max")])
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

## Enchantments with how many of their material you own; owned ones first.
func _fill_enchants() -> void:
	var prev = _current_enchant()
	enchant_pick.clear()
	enchant_ids = EnchantManager.enchants().keys()
	enchant_ids.sort_custom(func(a, b):
		var ha = player_character.count_owned(_mat(a))
		var hb = player_character.count_owned(_mat(b))
		return ha > hb if (ha > 0) != (hb > 0) else String(a) < String(b))
	for i in range(enchant_ids.size()):
		var id = enchant_ids[i]
		var e: Dictionary = EnchantManager.enchants()[id]
		var mat = ItemManager.get_item(_mat(id))
		enchant_pick.add_item("%s  (%s x%d)" % [e.get("name", id), mat.display_name if mat else _mat(id), player_character.count_owned(_mat(id))])
		if id == prev:
			enchant_pick.select(i)

func _mat(id) -> String:
	return String(EnchantManager.enchants().get(id, {}).get("material", ""))

func _current_enchant() -> String:
	var i = enchant_pick.selected if enchant_pick else -1
	return String(enchant_ids[i]) if i >= 0 and i < enchant_ids.size() else ""

func _update_details() -> void:
	if selected == null:
		details.text = "[i]You have no gear to enchant.[/i]"
		action_button.disabled = true
		return
	var item = selected
	var t = "[b][font_size=22]%s[/font_size][/b]\n" % item.display_name
	t += "[color=#%s]%s[/color]   Item level %d\n" % [_readable(item.get_rarity_color()).to_html(false), item.rarity.capitalize(), item.item_level]
	if not item.enchants.is_empty():
		t += "[color=#c77dff]Enchanted: %s[/color]\n" % ", ".join(item.enchants)
	t += "\n"
	var to = EnchantManager.next_rarity(item)
	if to == "":
		action_button.disabled = true
		details.text = t + "[color=gold]This item can't be raised any further by enchanting%s.[/color]" % ("" if item.rarity == "legendary" else " (Legendary gear only drops)")
		return
	var id = _current_enchant()
	var e: Dictionary = EnchantManager.enchants().get(id, {})
	t += "[b]Enchant to [color=#%s]%s[/color] with %s[/b]\n" % [_readable(item.rarity_generator.get_color(to)).to_html(false), to.capitalize(), e.get("name", id)]
	t += "[i]%s[/i]\n\n" % e.get("description", "")
	var mult = EnchantManager.rarity_mult(item.rarity, to)
	if item.damage > 0:
		t += "[b]Damage:[/b] %d -> [color=lime]~%d[/color]\n" % [item.damage, int(round(item.damage * mult))]
	if item.armor_value > 0:
		t += "[b]Armor:[/b] %d -> [color=lime]~%d[/color]\n" % [item.armor_value, int(round(item.armor_value * mult))]
	var r = EnchantManager.stat_range(item)
	var stat = String(e.get("stat", "")).capitalize()
	if stat != "":
		t += "[b]%s:[/b] [color=lime]+%d to +%d[/color]\n" % [stat, r.x, r.y]
	var st = EnchantManager.weapon_status_for(item, id)
	if st != Skill.StatusEffect.NONE:
		t += "[b]On hit:[/b] [color=lime]chance to inflict %s[/color]\n" % Skill.StatusEffect.keys()[st].capitalize()
	elif item.is_weapon() and String(e.get("weapon_status", "")) != "":
		t += "[color=gray](This weapon already has an on-hit effect.)[/color]\n"
	t += "[color=gray]Blacksmith upgrade cap: +%d -> +%d[/color]\n" % [BlacksmithManager.get_max_level(item), int(BlacksmithManager.cfg.get("max_level", {}).get(to, 3))]

	var cost = EnchantManager.get_cost(item, id)
	t += "\n[b]Cost:[/b]\n"
	t += "  [color=%s]%s[/color]\n" % ["lime" if player_character.currency.copper >= cost.gold else "salmon", Currency.format_copper(cost.gold)]
	for mid in cost.materials:
		var have = player_character.count_owned(mid)
		var mat = ItemManager.get_item(mid)
		t += "  [color=%s]%s  %d / %d[/color]\n" % ["lime" if have >= cost.materials[mid] else "salmon", mat.display_name if mat else mid, have, cost.materials[mid]]
	var chance = EnchantManager.get_success_chance(item)
	t += "\n[b]Success chance:[/b] [color=%s]%d%%[/color]" % ["lime" if chance >= 0.8 else ("yellow" if chance >= 0.55 else "orange"), int(round(chance * 100))]
	if item.enchant_fails > 0:
		t += "   [color=cyan](Attuned x%d included)[/color]" % item.enchant_fails
	t += "\n[color=gray]On failure the gold and materials are lost, but the item is never harmed.[/color]"
	details.text = t
	action_button.disabled = not EnchantManager.can_afford(player_character, cost)

func _readable(rarity_color: String) -> Color:
	return Color(rarity_color).lerp(Color.WHITE, 0.35) if rarity_color != "" else Color("e6dccb")

# === ACTIONS ===

func _on_gear_selected(index: int) -> void:
	if index >= 0 and index < gear.size():
		selected = gear[index].item
		_update_details()

func _on_enchant_pressed() -> void:
	if selected == null:
		return
	var result = EnchantManager.enchant(player_character, selected, _current_enchant())
	status_label.text = result.reason
	status_label.modulate = Color(0.6, 1, 0.6) if result.get("success", false) else Color(1, 0.75, 0.6)
	_refresh()

func _on_back_pressed() -> void:
	SaveManager.save_game(player_character)
	SceneManager.change_to_town(player_character)
