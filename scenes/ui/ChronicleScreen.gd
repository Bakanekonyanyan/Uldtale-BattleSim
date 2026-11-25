# res://scenes/ui/ChronicleScreen.gd
# The Chronicle (ChronicleManager): the world's history in four views -
#   Timeline (by year, most important first within a season's span), People
#   (a biography per adventurer, and you), the Fallen (epitaphs), and Legends
#   (stories of past worlds, LegendManager).
class_name ChronicleScreen
extends CanvasLayer

const TABS := ["Timeline", "People", "The Fallen", "Legends"]

var player: CharacterData
var tab := 0
var body: RichTextLabel
var people: ItemList
var people_keys: Array = []
var tab_buttons: Array = []

static func open(parent: Node, p: CharacterData) -> ChronicleScreen:
	var c = ChronicleScreen.new()
	c.player = p
	parent.add_child(c)
	return c

func _ready() -> void:
	layer = 60
	var dim = ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.size = Vector2(1200, 720)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	var panel = Panel.new()
	panel.position = Vector2(80, 30)
	panel.size = Vector2(1040, 660)
	add_child(panel)
	var title = Label.new()
	title.text = "The Chronicle"
	title.position = Vector2(24, 12)
	title.add_theme_font_size_override("font_size", 24)
	panel.add_child(title)
	for i in range(TABS.size()):
		var b = Button.new()
		b.text = TABS[i]
		b.toggle_mode = true
		b.position = Vector2(260 + i * 150, 14)
		b.custom_minimum_size = Vector2(140, 34)
		b.pressed.connect(func(): _set_tab(i))
		panel.add_child(b)
		tab_buttons.append(b)
	people = ItemList.new()
	people.position = Vector2(24, 60)
	people.size = Vector2(280, 520)
	people.item_selected.connect(func(i): _show_person(i))
	panel.add_child(people)
	body = RichTextLabel.new()
	body.bbcode_enabled = true
	body.scroll_active = true
	panel.add_child(body)
	var close = Button.new()
	close.text = "Close"
	close.custom_minimum_size = Vector2(150, 40)
	close.position = Vector2(866, 604)
	close.pressed.connect(queue_free)
	panel.add_child(close)
	_set_tab(0)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		queue_free()
		get_viewport().set_input_as_handled()

func _set_tab(i: int) -> void:
	tab = i
	for j in range(tab_buttons.size()):
		tab_buttons[j].set_pressed_no_signal(j == i)
	people.visible = i == 1
	body.position = Vector2(320, 60) if i == 1 else Vector2(24, 60)
	body.size = Vector2(696, 530) if i == 1 else Vector2(992, 530)
	match i:
		0: body.text = timeline_text(player)
		1: _fill_people()
		2: body.text = fallen_text(player)
		3: body.text = LegendManager.legends_text()

## Timeline, year by year (newest first), the most important entries of each year.
static func timeline_text(p: CharacterData, per_year := 25) -> String:
	var by_year := {}
	for e in ChronicleManager.entries(p):
		var y = ChronicleManager.year_of(int(e.day))
		if not by_year.has(y):
			by_year[y] = []
		by_year[y].append(e)
	if by_year.is_empty():
		return "[i]Nothing worth remembering has happened yet. Give it time.[/i]"
	var years = by_year.keys()
	years.sort()
	years.reverse()
	var t := ""
	for y in years:
		var list: Array = by_year[y]
		var top = list.duplicate()
		top.sort_custom(func(a, b): return int(a.imp) > int(b.imp))
		top = top.slice(0, per_year)
		top.sort_custom(func(a, b): return int(a.day) < int(b.day))
		t += "[b][font_size=20][color=#ffd166]Year %d[/color][/font_size][/b]\n" % y
		for e in top:
			var col = "#ffd166" if int(e.imp) >= 9 else ("#e6dccb" if int(e.imp) >= 5 else "#a99f90")
			t += "[color=gray]%s[/color]  [color=%s]%s[/color]\n" % [ChronicleManager.date_for(int(e.day)).get_slice(",", 0), col, e.text]
		t += "\n"
	return t

func _fill_people() -> void:
	people.clear()
	people_keys = ["you"]
	var ep = ChronicleManager.player_epithet(player)
	people.add_item("You - %s%s" % [player.name, (" " + ep) if ep != "" else ""])
	var all = AdventurerManager.all_adventurers(player).duplicate()
	all.sort_custom(func(a, b): return ChronicleManager.about(player, MemoryManager.key_npc(a)).size() > ChronicleManager.about(player, MemoryManager.key_npc(b)).size())
	for n in all:
		people_keys.append(int(n.id))
		people.add_item(ChronicleManager.full_name(n) + ("" if AdventurerManager.is_active(n) else " †" if String(n.status) == "dead" else " (retired)"))
	people.select(0)
	_show_person(0)

func _show_person(i: int) -> void:
	if i < 0 or i >= people_keys.size():
		return
	if str(people_keys[i]) == "you":
		body.text = player_text(player)
	else:
		body.text = ChronicleManager.bio(player, AdventurerManager.get_npc(player, int(people_keys[i])))

static func player_text(p: CharacterData) -> String:
	var ep = ChronicleManager.player_epithet(p)
	var t := "[b][font_size=18]%s%s[/font_size][/b]\n" % [p.name, (" " + ep) if ep != "" else ""]
	t += "[color=gray]%s %s, %s. %s[/color]\n\n" % [p.race, p.character_class, RankManager.display(RankManager.get_rank(p)), PersonalityManager.player_reputation(p)]
	var mine = ChronicleManager.about(p, "you")
	if mine.is_empty():
		t += "[i]Your story hasn't started yet.[/i]\n"
	for e in mine.slice(max(0, mine.size() - 20)):
		t += "[color=gray]%s[/color]  %s\n" % [ChronicleManager.date_for(int(e.day)), e.text]
	return t

static func fallen_text(p: CharacterData) -> String:
	var dead = AdventurerManager.all_adventurers(p).filter(func(n): return String(n.status) == "dead")
	if dead.is_empty():
		return "[i]No one has fallen. Yet.[/i]"
	dead.sort_custom(func(a, b): return int(a.get("died_day", 0)) > int(b.get("died_day", 0)))
	var t := "[b][font_size=20][color=#ff9f6b]The Fallen[/color][/font_size][/b]\n\n"
	for n in dead:
		t += "[b]%s[/b]  [color=gray]%s %s, %s-Rank - %s[/color]\n   [i]%s[/i]\n" % [ChronicleManager.full_name(n), n.race, n.cls, n.rank,
			ChronicleManager.date_for(int(n.get("died_day", 1))), ChronicleManager.epitaph(n)]
	return t
