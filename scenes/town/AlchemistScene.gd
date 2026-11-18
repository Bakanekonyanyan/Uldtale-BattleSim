# res://scenes/town/AlchemistScene.gd
# Alchemist screen: browse recipes, buy recipe books, craft.
# All rules live in AlchemyManager; this script only builds and updates the UI.
# Uses the shop background until dedicated art exists.
extends Control

const FILTERS := ["All", "Craftable", "Known"]

var player_character: CharacterData
var recipe_ids: Array = []      # ids currently shown in the list (filtered)
var selected_id: String = ""

# UI (built in code)
var title_label: Label
var money_label: Label
var filter_option: OptionButton
var recipe_list: ItemList
var details: RichTextLabel
var quantity_spin: SpinBox
var craft_button: Button
var buy_button: Button
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

	title_label = _label(ui, "Alchemist", Vector2(40, 16), 28)
	money_label = _label(ui, "", Vector2(760, 24), 18)

	filter_option = OptionButton.new()
	for f in FILTERS:
		filter_option.add_item(f)
	filter_option.position = Vector2(40, 72)
	filter_option.custom_minimum_size = Vector2(200, 32)
	filter_option.item_selected.connect(func(_i): _refresh())
	ui.add_child(filter_option)

	recipe_list = ItemList.new()
	recipe_list.position = Vector2(40, 112)
	recipe_list.size = Vector2(420, 500)
	recipe_list.item_selected.connect(_on_recipe_selected)
	ui.add_child(recipe_list)

	var panel = Panel.new()
	panel.position = Vector2(490, 72)
	panel.size = Vector2(670, 440)
	ui.add_child(panel)

	details = RichTextLabel.new()
	details.bbcode_enabled = true
	details.position = Vector2(16, 12)
	details.size = Vector2(640, 416)
	panel.add_child(details)

	_label(ui, "Batches:", Vector2(490, 532), 16)
	quantity_spin = SpinBox.new()
	quantity_spin.position = Vector2(570, 526)
	quantity_spin.custom_minimum_size = Vector2(110, 36)
	quantity_spin.min_value = 1
	quantity_spin.max_value = 1
	quantity_spin.value_changed.connect(func(_v): _update_details())
	ui.add_child(quantity_spin)

	craft_button = _button(ui, "Craft", Vector2(700, 526), _on_craft_pressed)
	buy_button = _button(ui, "Buy Recipe", Vector2(870, 526), _on_buy_pressed)
	_button(ui, "Back to Town", Vector2(980, 640), _on_back_pressed)

	status_label = _label(ui, "", Vector2(490, 580), 16)
	status_label.size = Vector2(670, 50)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD

func _label(parent: Node, text: String, pos: Vector2, font_size: int) -> Label:
	var l = Label.new()
	l.text = text
	l.position = pos
	l.add_theme_font_size_override("font_size", font_size)
	parent.add_child(l)
	return l

func _button(parent: Node, text: String, pos: Vector2, handler: Callable) -> Button:
	var b = Button.new()
	b.text = text
	b.position = pos
	b.custom_minimum_size = Vector2(150, 40)
	b.pressed.connect(handler)
	parent.add_child(b)
	return b

# === REFRESH ===

func _refresh() -> void:
	if player_character == null or recipe_list == null:
		return
	money_label.text = "Money: %s" % player_character.currency.get_formatted()

	var filter = FILTERS[filter_option.selected]
	recipe_ids.clear()
	recipe_list.clear()
	for id in AlchemyManager.get_recipe_ids():
		var known = AlchemyManager.is_known(player_character, id)
		var can = AlchemyManager.max_craftable(player_character, id)
		if filter == "Craftable" and can == 0:
			continue
		if filter == "Known" and not known:
			continue
		var recipe = AlchemyManager.get_recipe(id)
		var text = "[%s] %s x%d" % [recipe.get("category", ""), AlchemyManager.get_output_name(id), int(recipe.get("quantity", 1))]
		if not known:
			text += "  (locked)"
		elif can > 0:
			text += "  - can craft %d" % can
		var idx = recipe_list.add_item(text)
		if not known:
			recipe_list.set_item_custom_fg_color(idx, Color(0.6, 0.6, 0.6))
		elif can > 0:
			recipe_list.set_item_custom_fg_color(idx, Color(0.6, 1.0, 0.6))
		recipe_ids.append(id)

	var keep = recipe_ids.find(selected_id)
	if keep >= 0:
		recipe_list.select(keep)
	elif not recipe_ids.is_empty():
		recipe_list.select(0)
		selected_id = recipe_ids[0]
	else:
		selected_id = ""
	_update_details()

func _update_details() -> void:
	if selected_id == "":
		details.text = "[i]No recipes match this filter.[/i]"
		craft_button.disabled = true
		buy_button.visible = false
		return

	var recipe = AlchemyManager.get_recipe(selected_id)
	var output: Item = ItemManager.get_item(recipe.output)
	var known = AlchemyManager.is_known(player_character, selected_id)
	var can = AlchemyManager.max_craftable(player_character, selected_id)
	var batches = int(quantity_spin.value)

	var t = "[b][font_size=22]%s[/font_size][/b]  x%d per batch\n" % [output.display_name, int(recipe.get("quantity", 1))]
	t += "[i]%s[/i]\n\n" % output.description
	t += "[b]Ingredients[/b] (pack + stash), for %d batch%s:\n" % [batches, "" if batches == 1 else "es"]
	for mat in recipe.ingredients:
		var need = int(recipe.ingredients[mat]) * batches
		var have = AlchemyManager.count_available(player_character, mat)
		var mat_item = ItemManager.get_item(mat)
		var color = "lime" if have >= need else "salmon"
		t += "  [color=%s]%s  %d / %d[/color]\n" % [color, mat_item.display_name if mat_item else mat, have, need]
	t += "\n[b]Fee:[/b] %s\n" % Currency.format_copper(int(recipe.get("fee", 0)) * batches)
	t += "[b]In pack:[/b] %d   [b]In stash:[/b] %d   (carry limit %d)\n" % [
		player_character.inventory.get_quantity(recipe.output),
		player_character.stash.get_quantity(recipe.output),
		player_character.carry_limit]
	if not known:
		t += "\n[color=orange][b]Locked:[/b] %s[/color]" % AlchemyManager.get_unlock_text(selected_id)
	details.text = t

	quantity_spin.max_value = max(1, can)
	craft_button.disabled = not known or can < batches
	var price = AlchemyManager.get_purchase_price(selected_id)
	buy_button.visible = not known and price > 0
	buy_button.text = "Buy Recipe (%s)" % Currency.format_copper(price)

# === ACTIONS ===

func _on_recipe_selected(index: int) -> void:
	if index >= 0 and index < recipe_ids.size():
		selected_id = recipe_ids[index]
		quantity_spin.value = 1
		_update_details()

func _on_craft_pressed() -> void:
	var result = AlchemyManager.craft(player_character, selected_id, int(quantity_spin.value))
	status_label.text = result.reason
	quantity_spin.value = 1
	_refresh()

func _on_buy_pressed() -> void:
	var result = AlchemyManager.buy_recipe(player_character, selected_id)
	status_label.text = result.reason
	_refresh()

func _on_back_pressed() -> void:
	SaveManager.save_game(player_character)
	SceneManager.change_to_town(player_character)
