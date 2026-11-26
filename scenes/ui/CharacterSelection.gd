# res://scenes/ui/CharacterSelection.gd
# Your characters as cards (name, level, class, rank, day, birthplace, mode),
# the chosen one's details on the right, and the Hall of Legends (retired and
# fallen heroes of every world).
#   Continue        load the save and go to town
#   New world...    start this character over in a new world, or in another
#                   character's world (deletes their current progress)
#   Delete...       type the name to confirm
extends Control

const TAB_NAMES := ["Characters", "Hall of Legends"]
const LIST_RECT := Rect2(32, 132, 440, 492)
const DETAIL_RECT := Rect2(496, 72, 672, 552)

var character_list: Array = []
var selected_character: CharacterData = null
var tab := 0

var chrome: ScreenChrome
var tabs: Array = []
var cards_box: VBoxContainer
var cards_scroll: ScrollContainer
var detail: RichTextLabel
var continue_button: Button
var new_world_button: Button
var delete_button: Button
var create_button: Button
var quit_button: Button

func _ready():
	character_list = SaveManager.get_all_characters()
	_build_ui()
	_fill_cards()
	if not character_list.is_empty():
		_select(character_list[0])
	_set_tab(0)

# === UI ===

func _build_ui() -> void:
	chrome = ScreenChrome.attach(self, "Characters", Callable())
	var ui := CanvasLayer.new()
	ui.layer = 1
	add_child(ui)
	var row := HBoxContainer.new()
	ScreenChrome.tab_row(row, Rect2(32, 72, 440, 36))
	ui.add_child(row)
	for i in range(TAB_NAMES.size()):
		var b := Button.new()
		b.text = TAB_NAMES[i]
		b.pressed.connect(_set_tab.bind(i))
		row.add_child(b)
		tabs.append(b)
	cards_scroll = ScrollContainer.new()
	ScreenChrome.place(cards_scroll, LIST_RECT)
	cards_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	ui.add_child(cards_scroll)
	cards_box = VBoxContainer.new()
	cards_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cards_box.add_theme_constant_override("separation", 8)
	cards_scroll.add_child(cards_box)
	var panel := Panel.new()
	ScreenChrome.place(panel, DETAIL_RECT)
	ui.add_child(panel)
	detail = RichTextLabel.new()
	detail.bbcode_enabled = true
	ScreenChrome.place(detail, Rect2(18, 14, DETAIL_RECT.size.x - 36, DETAIL_RECT.size.y - 28))
	panel.add_child(detail)
	create_button = _footer("New Character", Vector2(32, 640), func(): SceneManager.change_to_character_creation())
	quit_button = _footer("Quit", Vector2(208, 640), func(): get_tree().quit())
	delete_button = _footer("Delete...", Vector2(528, 640), _ask_delete)
	new_world_button = _footer("New world...", Vector2(688, 640), _ask_new_world)
	continue_button = _footer("Continue", Vector2(1008, 640), _continue)
	continue_button.size.x = 160
	for b in [create_button, quit_button, delete_button, new_world_button, continue_button]:
		ui.add_child(b)

func _footer(text: String, pos: Vector2, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.position = pos
	b.size = Vector2(160, 48)
	b.pressed.connect(cb)
	return b

func _set_tab(i: int) -> void:
	tab = i
	ScreenChrome.set_active_tab(tabs, i)
	cards_scroll.visible = i == 0
	for b in [continue_button, new_world_button, delete_button]:
		b.visible = i == 0
	_refresh()

func _refresh() -> void:
	chrome.set_info("%d character%s" % [character_list.size(), "" if character_list.size() == 1 else "s"])
	if tab == 1:
		var t = "[font_size=24][b][color=#e5c34a]Hall of Legends[/color][/b][/font_size]\n[color=#a99f90]Every hero who retired or fell, in any world. The bards remember them, and their names turn up in later worlds.[/color]\n\n"
		var lt = LegendManager.legends_text()
		detail.text = t + (lt if lt.strip_edges() != "" else "[i][color=#a99f90]No legends yet.[/color][/i]")
		return
	var c = selected_character
	continue_button.disabled = c == null or _status(c) != ""
	new_world_button.disabled = c == null
	delete_button.disabled = c == null
	detail.text = _detail_text(c) if c else "[color=#a99f90]No characters yet. Create one to begin.[/color]"
	for card in cards_box.get_children():
		card.set_pressed_no_signal(card.get_meta("who") == (c.name if c else ""))

# === CARDS ===

func _fill_cards() -> void:
	for ch in cards_box.get_children():
		ch.queue_free()
	for c in character_list:
		var b := Button.new()
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(0, 92)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.set_meta("who", c.name)
		b.pressed.connect(_select.bind(c))
		var box := VBoxContainer.new()
		box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 12)
		box.alignment = BoxContainer.ALIGNMENT_CENTER
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(box)
		var badges = _badges(c)
		_label(box, c.name + ("   " + badges if badges != "" else ""), 20, ScreenChrome.ACCENT)
		_label(box, "Lv %d %s %s  ·  %s" % [c.level, c.race, c.character_class, RankManager.display(RankManager.get_rank(c))], 16, Color("e6dccb"))
		var born = String(c.town_state.get("birthplace", ""))
		_label(box, "Day %d%s" % [WorldClock.day(c), "  ·  from %s" % born if born != "" else ""], 15, ScreenChrome.MUTED)
		cards_box.add_child(b)

func _label(parent: Node, t: String, size: int, col: Color) -> void:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.clip_text = true
	parent.add_child(l)

func _badges(c: CharacterData) -> String:
	var bits: Array = []
	if c.town_state.get("permadeath", false):
		bits.append("[Permadeath]")
	var st = _status(c)
	if st != "":
		bits.append("[%s]" % st)
	return " ".join(bits)

## "Retired" / "Fallen" / "".
func _status(c: CharacterData) -> String:
	if c.town_state.get("dead", false):
		return "Fallen"
	if c.town_state.get("retired", false):
		return "Retired"
	return ""

func _select(c: CharacterData) -> void:
	selected_character = c
	CharacterManager.set_current_character(c)
	_refresh()

# === DETAIL ===

func _detail_text(c: CharacterData) -> String:
	var t = "[font_size=24][b][color=#e5c34a]%s[/color][/b][/font_size]\n" % c.name
	t += "[color=#a99f90]Lv %d %s %s  ·  %s" % [c.level, c.race, c.character_class, RankManager.display(RankManager.get_rank(c))]
	var bg = Backgrounds.of(c)
	if not bg.is_empty():
		t += "  ·  %s" % bg.get("name", "")
	var born = String(c.town_state.get("birthplace", ""))
	if born != "":
		t += "  ·  born in %s" % Regions.describe(born)
	t += "[/color]\n"
	var st = _status(c)
	if st != "":
		t += "[color=#e07a5f]%s - their Legend is written. Start a new world to play them again.[/color]\n" % st
	t += "\n[b]%s[/b]  %s" % [String(c.town_state.get("world_meta", {}).get("name", "World")), WorldClock.date_text(c)]
	var others = WorldShare.others(c)
	if not others.is_empty():
		t += "\n[color=#c9b8ff]Shared with %s[/color]" % ", ".join(others.keys())
	if c.town_state.has("adventurers"):
		t += "\n%s" % LedgerManager.summary(c)
	t += "\n\n[b]Condition[/b]  HP %d/%d   MP %d/%d   SP %d/%d\n" % [c.current_hp, c.max_hp, c.current_mp, c.max_mp, c.current_sp, c.max_sp]
	t += "Attack %d   Spell %d   Money %s\n" % [int(BattleFormulas.physical_offense(c)), int(BattleFormulas.magical_offense(c)), c.currency.get_formatted()]
	var deepest: Array = []
	for loc in LocationManager.get_ids():
		if c.location_progress.has(loc):
			deepest.append("%s %d" % [LocationManager.get_display_name(loc), c.get_max_floor(loc)])
	if not deepest.is_empty():
		t += "Deepest floors: %s\n" % ", ".join(deepest)
	t += "\n[b]Equipment[/b]\n"
	var any := false
	for slot in ["main_hand", "off_hand", "head", "chest", "hands", "legs", "feet"]:
		var item = c.equipment.get(slot)
		if item:
			any = true
			t += "  %s: [color=%s]%s[/color]\n" % [ScreenChrome.slot_name(slot), ScreenChrome.rarity_color(item).to_html(false), item.display_name]
	if not any:
		t += "  [color=#a99f90]Nothing equipped[/color]\n"
	if c.skills and c.skills.size() > 0:
		t += "\n[b]Skills[/b]  %s\n" % ", ".join(c.skills.map(func(s): return String(s)))
	return t

# === ACTIONS ===

func _continue() -> void:
	var c = selected_character
	if c == null:
		return
	var loaded = SaveManager.load_game(c.name)
	if loaded == null or _status(loaded) != "":
		return
	CharacterManager.set_current_character(loaded)
	SceneManager.change_to_town(loaded)

## Start this character over: a new world, or another character's.
func _ask_new_world() -> void:
	var c = selected_character
	if c == null:
		return
	var d := ConfirmationDialog.new()
	d.title = "Start %s in a new world" % c.name
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(520, 0)
	box.add_theme_constant_override("separation", 10)
	var warn := Label.new()
	warn.autowrap_mode = TextServer.AUTOWRAP_WORD
	warn.text = "%s starts again at level 1 - their current progress is deleted. Their Legend (if any) stays in the Hall." % c.name
	box.add_child(warn)
	var pick := OptionButton.new()
	pick.add_item("A new world (history is generated)")
	pick.set_item_metadata(0, "")
	for w in WorldShare.joinable():
		pick.add_item("Join %s (day %d)" % [w.name, int(w.day)])
		pick.set_item_metadata(pick.item_count - 1, String(w.id))
	box.add_child(pick)
	d.add_child(box)
	d.ok_button_text = "Start over"
	d.confirmed.connect(func():
		_start_new_world(c, String(pick.get_item_metadata(pick.selected)))
		d.queue_free())
	d.canceled.connect(d.queue_free)
	add_child(d)
	d.popup_centered()

func _start_new_world(c: CharacterData, join_from: String) -> void:
	c.reset_for_new_game()
	if join_from != "":
		WorldShare.join(c, join_from)
	SaveManager.save_game(c)
	CharacterManager.set_current_character(c)
	SceneManager.change_to_town(c)

## Delete: type the name to confirm.
func _ask_delete() -> void:
	var c = selected_character
	if c == null:
		return
	var d := ConfirmationDialog.new()
	d.title = "Delete %s?" % c.name
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(460, 0)
	var l := Label.new()
	l.autowrap_mode = TextServer.AUTOWRAP_WORD
	l.text = "This deletes %s's save for good. Type their name to confirm." % c.name
	box.add_child(l)
	var input := LineEdit.new()
	input.placeholder_text = c.name
	box.add_child(input)
	d.add_child(box)
	d.ok_button_text = "Delete"
	d.get_ok_button().disabled = true
	input.text_changed.connect(func(t): d.get_ok_button().disabled = t.strip_edges() != c.name)
	d.confirmed.connect(func():
		_delete(c)
		d.queue_free())
	d.canceled.connect(d.queue_free)
	add_child(d)
	d.popup_centered()

func _delete(c: CharacterData) -> void:
	SaveManager.delete_character(c.name)
	character_list = SaveManager.get_all_characters()
	selected_character = null
	_fill_cards()
	if not character_list.is_empty():
		_select(character_list[0])
	else:
		_refresh()
