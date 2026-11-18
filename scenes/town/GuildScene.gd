# res://scenes/town/GuildScene.gd
# Guild screen: bounty board, active bounties, turn-in.
# All rules live in GuildManager; this script only builds and updates the UI.
# Uses the shop background until dedicated art exists.
extends Control

enum Tab { BOARD, ACTIVE, TURN_IN }
const TAB_NAMES := ["Board", "Active", "Turn In"]

var player_character: CharacterData
var tab: Tab = Tab.BOARD
var shown: Array = []          # bounties listed for the current tab
var selected_uid: int = -1

# UI (built in code)
var header_label: Label
var tab_buttons: Array[Button] = []
var bounty_list: ItemList
var details: RichTextLabel
var primary_button: Button      # Accept / Abandon / Turn In
var reroll_button: Button
var status_label: Label
var abandon_dialog: ConfirmationDialog

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
	_label(ui, "Adventurers' Guild", Vector2(40, 16), 28)
	header_label = _label(ui, "", Vector2(560, 24), 18)

	for i in range(TAB_NAMES.size()):
		var b = _button(ui, TAB_NAMES[i], Vector2(40 + i * 145, 68), func(): _set_tab(i), Vector2(135, 36))
		b.toggle_mode = true
		tab_buttons.append(b)

	bounty_list = ItemList.new()
	bounty_list.position = Vector2(40, 112)
	bounty_list.size = Vector2(420, 500)
	bounty_list.item_selected.connect(_on_bounty_selected)
	ui.add_child(bounty_list)

	var panel = Panel.new()
	panel.position = Vector2(490, 72)
	panel.size = Vector2(670, 440)
	ui.add_child(panel)
	details = RichTextLabel.new()
	details.bbcode_enabled = true
	details.position = Vector2(16, 12)
	details.size = Vector2(640, 416)
	panel.add_child(details)

	primary_button = _button(ui, "Accept", Vector2(490, 526), _on_primary_pressed)
	reroll_button = _button(ui, "Reroll Board", Vector2(660, 526), _on_reroll_pressed, Vector2(220, 40))
	_button(ui, "Back to Town", Vector2(980, 640), _on_back_pressed)

	status_label = _label(ui, "", Vector2(490, 580), 16)
	status_label.size = Vector2(670, 50)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD

	abandon_dialog = ConfirmationDialog.new()
	abandon_dialog.title = "Abandon Bounty"
	abandon_dialog.confirmed.connect(func(): _do_abandon(true))
	abandon_dialog.add_button("Take the demerit", true, "demerit")
	abandon_dialog.custom_action.connect(func(action):
		if action == "demerit":
			abandon_dialog.hide()
			_do_abandon(false))
	ui.add_child(abandon_dialog)

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

func _set_tab(new_tab: int) -> void:
	tab = new_tab as Tab
	selected_uid = -1
	status_label.text = ""
	_refresh()

func _refresh() -> void:
	if player_character == null or bounty_list == null:
		return
	var p = player_character
	header_label.text = "Guild Points: %d   Demerits: %d   Money: %s" % [
		GuildManager.get_points(p), GuildManager.get_demerits(p), p.currency.get_formatted()]
	for i in range(tab_buttons.size()):
		tab_buttons[i].button_pressed = i == tab

	match tab:
		Tab.BOARD:
			shown = GuildManager.get_board(p)
		Tab.ACTIVE:
			shown = GuildManager.get_active(p)
		Tab.TURN_IN:
			shown = GuildManager.get_active(p).filter(func(b): return GuildManager.is_complete(p, b))

	bounty_list.clear()
	for b in shown:
		var text = b.title
		if tab == Tab.ACTIVE:
			text += "  [%s]" % ("ready!" if GuildManager.is_complete(p, b) else "%d exp. left" % int(b.deadline))
		var idx = bounty_list.add_item(text)
		if tab != Tab.BOARD and GuildManager.is_complete(p, b):
			bounty_list.set_item_custom_fg_color(idx, Color(0.6, 1.0, 0.6))

	var keep = -1
	for i in range(shown.size()):
		if int(shown[i].uid) == selected_uid:
			keep = i
	if keep < 0 and not shown.is_empty():
		keep = 0
	if keep >= 0:
		bounty_list.select(keep)
		selected_uid = int(shown[keep].uid)
	else:
		selected_uid = -1
	_update_details()

func _selected() -> Dictionary:
	for b in shown:
		if int(b.uid) == selected_uid:
			return b
	return {}

func _update_details() -> void:
	var p = player_character
	var b = _selected()
	reroll_button.visible = tab == Tab.BOARD
	reroll_button.text = "Reroll Board (%s)" % Currency.format_copper(GuildManager.get_reroll_fee(p))
	primary_button.text = ["Accept", "Abandon", "Turn In"][tab]

	if b.is_empty():
		details.text = ["[i]The board is empty. Check back after your next expedition.[/i]",
			"[i]No active bounties. Accept some from the Board (up to %d).[/i]" % int(GuildManager.settings.get("max_active", 3)),
			"[i]Nothing ready to turn in yet.[/i]"][tab]
		primary_button.disabled = true
		return

	var done = GuildManager.is_complete(p, b)
	var t = "[b][font_size=22]%s[/font_size][/b]\n\n" % b.title
	t += "[b]Objective:[/b] %s\n" % GuildManager.describe_objective(p, b)
	if tab == Tab.BOARD:
		t += "[b]Deadline:[/b] %d expeditions after accepting\n" % int(GuildManager.settings.get("deadline_expeditions", 3))
	elif not done:
		t += "[b]Deadline:[/b] %d expedition%s left\n" % [int(b.deadline), "" if int(b.deadline) == 1 else "s"]
	else:
		t += "[color=lime][b]Complete - turn it in for your reward![/b][/color]\n"
	t += "\n[b]Reward:[/b] %s\n" % GuildManager.describe_rewards(b)
	if tab != Tab.TURN_IN:
		t += "\n[color=gray]Missing the deadline or abandoning costs %d Guild Points and a demerit (or pay %s to abandon without one).[/color]" % [
			GuildManager.get_point_penalty(b), Currency.format_copper(GuildManager.get_abandon_fee(b))]
	details.text = t

	match tab:
		Tab.BOARD:
			primary_button.disabled = GuildManager.get_active(p).size() >= int(GuildManager.settings.get("max_active", 3))
		Tab.ACTIVE:
			primary_button.disabled = false
		Tab.TURN_IN:
			primary_button.disabled = not done

# === ACTIONS ===

func _on_bounty_selected(index: int) -> void:
	if index >= 0 and index < shown.size():
		selected_uid = int(shown[index].uid)
		_update_details()

func _on_primary_pressed() -> void:
	var b = _selected()
	if b.is_empty():
		return
	match tab:
		Tab.BOARD:
			status_label.text = GuildManager.accept(player_character, selected_uid).reason
		Tab.ACTIVE:
			abandon_dialog.dialog_text = "Abandon \"%s\"?\n\nPay %s to leave cleanly, or take a demerit (-%d Guild Points)." % [
				b.title, Currency.format_copper(GuildManager.get_abandon_fee(b)), GuildManager.get_point_penalty(b)]
			abandon_dialog.ok_button_text = "Pay %s" % Currency.format_copper(GuildManager.get_abandon_fee(b))
			abandon_dialog.popup_centered()
			return
		Tab.TURN_IN:
			status_label.text = GuildManager.turn_in(player_character, selected_uid).reason
	selected_uid = -1
	_refresh()

func _do_abandon(pay_fee: bool) -> void:
	status_label.text = GuildManager.abandon(player_character, selected_uid, pay_fee).reason
	selected_uid = -1
	_refresh()

func _on_reroll_pressed() -> void:
	status_label.text = GuildManager.reroll_board(player_character).reason
	selected_uid = -1
	_refresh()

func _on_back_pressed() -> void:
	SaveManager.save_game(player_character)
	SceneManager.change_to_town(player_character)
