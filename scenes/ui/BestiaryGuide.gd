# res://scenes/ui/BestiaryGuide.gd
# What you've learned about each enemy race (Bestiary autoload): known
# weaknesses, kills, Breaks. Open with BestiaryGuide.open(parent). Built in code.
class_name BestiaryGuide
extends CanvasLayer

var races: Array = []
var list: ItemList
var details: RichTextLabel

static func open(parent: Node) -> BestiaryGuide:
	var g = BestiaryGuide.new()
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
	title.text = "Bestiary"
	title.position = Vector2(24, 12)
	title.add_theme_font_size_override("font_size", 24)
	panel.add_child(title)
	var hint = Label.new()
	hint.text = "Weaknesses you've found. Hit a weakness or Break an enemy to learn more."
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

func _fill() -> void:
	list.clear()
	var book = Bestiary.book()
	races = book.keys()
	races.sort()
	for r in races:
		var e: Dictionary = book[r]
		var idx = list.add_item("%s%s  (%d defeated)" % ["★ " if e.get("studied", false) else "", r, int(e.get("kills", 0))])
		if e.get("studied", false):
			list.set_item_custom_fg_color(idx, Color(0.8, 0.6, 1.0))
	if races.is_empty():
		details.text = "[i]No entries yet. Defeat enemies to start your bestiary.[/i]"
	else:
		list.select(0)
		_show(0)

func _show(i: int) -> void:
	if i < 0 or i >= races.size():
		return
	var e: Dictionary = Bestiary.book()[races[i]]
	var t = "[b][font_size=22]%s[/font_size][/b]\n\n" % races[i]
	t += "[b]Defeated:[/b] %d    [b]Broken:[/b] %d\n\n" % [int(e.get("kills", 0)), int(e.get("breaks", 0))]
	var weak: Array = e.get("weak", [])
	t += "[b]Known weaknesses:[/b] %s\n" % ("[color=#7bd389]%s[/color]" % ", ".join(weak) if not weak.is_empty() else "[color=gray]none found yet[/color]")
	if e.get("studied", false):
		t += "[color=#c77dff]Studied: you've Broken one, so what it shows is everything it has.[/color]\n"
	else:
		t += "[color=gray]Not studied yet: Break one (or bring a scholar and Inspect it) to learn all of its weaknesses.[/color]\n"
	t += "\n[color=gray]Armor changes weaknesses too: an individual in plate or cloth can differ from its race.[/color]"
	details.text = t
