# res://scenes/town/TavernScene.gd
# Tavern: the Guild's adventurers off duty. See who's in town, chat (learn their
# traits), buy them a drink, give gifts. Rules live in AdventurerManager.
extends Control

enum Tab { ROSTER, DEPARTED }
const TAB_NAMES := ["Adventurers", "Fallen & retired"]

var player_character: CharacterData
var tab: Tab = Tab.ROSTER
var shown: Array = []
var selected_id := -1

var header_label: Label
var tab_buttons: Array[Button] = []
var npc_list: ItemList
var details: RichTextLabel
var chat_button: Button
var drink_button: Button
var gift_button: Button
var gift_menu: PopupMenu
var status_label: Label

func _ready():
	_build_ui()
	if player_character == null:
		player_character = CharacterManager.get_current_character()
	_refresh()

func set_player(character: CharacterData) -> void:
	player_character = character
	if is_node_ready():
		_refresh()

func _build_ui() -> void:
	var ui: CanvasLayer = $UI
	header_label = ScreenChrome.attach(self, "Tavern", _on_back_pressed).info_label
	for i in range(TAB_NAMES.size()):
		var b = _button(ui, TAB_NAMES[i], Vector2(32 + i * 152, 72), func(): _set_tab(i), Vector2(148, 36))
		b.toggle_mode = true
		tab_buttons.append(b)
	npc_list = ItemList.new()
	ScreenChrome.place(npc_list, ScreenChrome.LIST_RECT)
	npc_list.item_selected.connect(func(i):
		if i >= 0 and i < shown.size():
			selected_id = int(shown[i].id)
			_update_details())
	ui.add_child(npc_list)
	var panel = Panel.new()
	panel.position = Vector2(496, 72)
	panel.size = Vector2(672, 440)
	ui.add_child(panel)
	details = RichTextLabel.new()
	details.bbcode_enabled = true
	details.position = Vector2(16, 12)
	details.size = Vector2(640, 416)
	panel.add_child(details)
	chat_button = _button(ui, "Chat", Vector2(496, 526), _on_chat)
	drink_button = _button(ui, "Buy a Drink", Vector2(656, 526), _on_drink, Vector2(190, 40))
	gift_button = _button(ui, "Give a Gift...", Vector2(856, 526), _on_gift_pressed, Vector2(170, 40))
	gift_menu = PopupMenu.new()
	gift_menu.id_pressed.connect(_on_gift_chosen)
	ui.add_child(gift_menu)
	status_label = Label.new()
	status_label.position = Vector2(496, 578)
	status_label.size = Vector2(670, 60)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	status_label.add_theme_font_size_override("font_size", 16)
	ui.add_child(status_label)

func _button(parent: Node, text: String, pos: Vector2, handler: Callable, min_size := Vector2(150, 40)) -> Button:
	var b = Button.new()
	b.text = text
	b.position = pos
	b.custom_minimum_size = min_size
	b.pressed.connect(handler)
	parent.add_child(b)
	return b

func _set_tab(t: int) -> void:
	tab = t as Tab
	selected_id = -1
	status_label.text = ""
	_refresh()

func _refresh() -> void:
	if player_character == null or npc_list == null:
		return
	var p = player_character
	header_label.text = "%s   Money: %s" % [WorldClock.short_date(p), p.currency.get_formatted()]
	for i in range(tab_buttons.size()):
		tab_buttons[i].button_pressed = i == tab
	var all = AdventurerManager.all_adventurers(p)
	if tab == Tab.ROSTER:
		shown = all.filter(func(n): return AdventurerManager.is_active(n))
		# in town first, then by rank (highest first), then name
		shown.sort_custom(func(a, b):
			var ta = AdventurerManager.in_town(a)
			var tb = AdventurerManager.in_town(b)
			if ta != tb:
				return ta
			var ra = RankManager.rank_index(String(a.rank))
			var rb = RankManager.rank_index(String(b.rank))
			if ra != rb:
				return ra > rb
			return String(a.name) < String(b.name))
	else:
		shown = all.filter(func(n): return not AdventurerManager.is_active(n))
	npc_list.clear()
	for n in shown:
		var mark = ""
		var tg = AdventurerManager.tags(n)
		if "Rival" in tg:
			mark = "⚔ "
		elif "Close friend" in tg or "Friend" in tg:
			mark = "♥ "
		var where = "" if AdventurerManager.in_town(n) else ("  (away)" if String(n.status) == "job" else "")
		if tab == Tab.DEPARTED:
			where = "  (fallen)" if String(n.status) == "dead" else "  (retired)"
		var idx = npc_list.add_item("%s%s  %s-%s%s" % [mark, n.name, n.rank, n.cls, where])
		if not AdventurerManager.in_town(n):
			npc_list.set_item_custom_fg_color(idx, Color(0.6, 0.6, 0.6))
		elif "Rival" in tg:
			npc_list.set_item_custom_fg_color(idx, Color(1.0, 0.65, 0.55))
		elif mark == "♥ ":
			npc_list.set_item_custom_fg_color(idx, Color(0.6, 1.0, 0.6))
	var keep = -1
	for i in range(shown.size()):
		if int(shown[i].id) == selected_id:
			keep = i
	if keep < 0 and not shown.is_empty():
		keep = 0
	if keep >= 0:
		npc_list.select(keep)
		selected_id = int(shown[keep].id)
	else:
		selected_id = -1
	_update_details()

func _selected() -> Dictionary:
	return AdventurerManager.get_npc(player_character, selected_id) if selected_id >= 0 else {}

func _rapport_bar(r: int) -> String:
	var filled = int(round((r + 100) / 20.0))
	var col = "#7bd389" if r >= 20 else ("#e07a5f" if r <= -20 else "#d8d0c0")
	return "[color=%s]%s[/color][color=#555555]%s[/color] %d" % [col, "■".repeat(filled), "■".repeat(10 - filled), r]

func _update_details() -> void:
	var p = player_character
	var n = _selected()
	var day = WorldClock.day(p)
	if n.is_empty():
		details.text = "[i]Nobody here.[/i]" if tab == Tab.ROSTER else "[i]No one has fallen or retired yet.[/i]"
		for b in [chat_button, drink_button, gift_button]:
			b.disabled = true
		return
	var t = "[b][font_size=22]%s[/font_size][/b]\n%s\n" % [n.name, AdventurerManager.title_line(n)]
	t += "[color=gray]%s[/color]\n\n" % AdventurerManager.status_text(p, n)
	var tg = AdventurerManager.tags(n)
	t += "[b]Rapport:[/b] %s%s\n" % [_rapport_bar(int(n.rapport)), ("   " + ", ".join(tg)) if not tg.is_empty() else ""]
	var known: Array = []
	for tr in n.traits:
		known.append(String(AdventurerManager.trait_data(tr).get("name", tr)) if tr in n.known_traits else "???")
	t += "[b]Personality:[/b] %s\n" % ", ".join(known)
	for tr in n.known_traits:
		t += "   [color=gray]%s: %s[/color]\n" % [AdventurerManager.trait_data(tr).get("name", tr), AdventurerManager.trait_data(tr).get("description", "")]
	t += "[b]Nature:[/b] %s\n" % (AdventurerManager.alignment_label(n) if AdventurerManager.alignment_known(n) else "[color=gray]Talk with them more to find out.[/color]")
	var rec: Dictionary = n.record
	t += "[b]Record:[/b] %d job%s, %d success%s, %d failure%s\n" % [int(rec.jobs), "" if int(rec.jobs) == 1 else "s", int(rec.wins), "" if int(rec.wins) == 1 else "es", int(rec.fails), "" if int(rec.fails) == 1 else "s"]
	if not n.history.is_empty():
		t += "\n[b]Lately[/b]\n"
		var h: Array = n.history.duplicate()
		h.reverse()
		for e in h.slice(0, 6):
			t += "[color=gray]Day %d[/color]  %s\n" % [int(e.day), e.text]
	details.text = t
	var here = AdventurerManager.in_town(n) and tab == Tab.ROSTER
	chat_button.disabled = not here or int(n.chat_day) == day
	drink_button.disabled = not here or int(n.drank_day) == day or p.currency.copper < AdventurerManager.drink_price(p)
	drink_button.text = "Buy a Drink (%s)" % Currency.format_copper(AdventurerManager.drink_price(p))
	gift_button.disabled = not here or int(n.gift_day) == day

func _after(r: Dictionary) -> void:
	status_label.text = r.reason
	_refresh()

func _on_chat() -> void:
	_after(AdventurerManager.chat(player_character, selected_id))

func _on_drink() -> void:
	_after(AdventurerManager.drink(player_character, selected_id))

var _gift_keys: Array = []

func _on_gift_pressed() -> void:
	gift_menu.clear()
	_gift_keys.clear()
	var p = player_character
	for key in p.inventory.items.keys():
		var e = p.inventory.items[key]
		if e.item == null or p.equipment.values().has(e.item):
			continue
		gift_menu.add_item("%s%s  (%s)" % [e.item.display_name, "" if int(e.quantity) <= 1 else " x%d" % int(e.quantity), Currency.format_copper(int(e.item.value))], _gift_keys.size())
		_gift_keys.append(key)
	if _gift_keys.is_empty():
		status_label.text = "Your pack is empty."
		return
	gift_menu.position = Vector2i(856, 300)
	gift_menu.popup()

func _on_gift_chosen(id: int) -> void:
	if id >= 0 and id < _gift_keys.size():
		_after(AdventurerManager.gift(player_character, selected_id, String(_gift_keys[id])))

func _on_back_pressed() -> void:
	SaveManager.save_game(player_character)
	SceneManager.change_to_town(player_character)
