# res://scenes/ui/LedgerBoard.gd
# The Guild Ledger standings (LedgerManager): rank, renown and deeds for the
# top adventurers and you, with weekly movement. Click a row for details.
class_name LedgerBoard
extends CanvasLayer

var player: CharacterData
var rows: Array = []
var list: Tree
var details: RichTextLabel

static func open(parent: Node, p: CharacterData) -> LedgerBoard:
	var b = LedgerBoard.new()
	b.player = p
	parent.add_child(b)
	return b

func _ready() -> void:
	layer = 60
	var dim = ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.size = Vector2(1200, 720)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	var panel = Panel.new()
	panel.position = Vector2(60, 40)
	panel.size = Vector2(1080, 640)
	add_child(panel)
	var title = Label.new()
	title.text = "Guild Ledger"
	title.position = Vector2(24, 12)
	title.add_theme_font_size_override("font_size", 24)
	panel.add_child(title)
	var sub = Label.new()
	sub.text = LedgerManager.summary(player)
	sub.position = Vector2(220, 8)
	sub.add_theme_font_size_override("font_size", 15)
	sub.add_theme_color_override("font_color", Color("ffd166"))
	panel.add_child(sub)
	var crown = Label.new()
	var ch = LedgerManager.champion(player)
	crown.text = ("Reigning Champion: %s (Year %d)" % [("you" if ch.is_player else String(ch.name)), int(ch.year)] if not ch.is_empty() else "No Champion crowned yet") \
		+ "   -   The Crowning in %d day%s" % [LedgerManager.days_to_crowning(player), "" if LedgerManager.days_to_crowning(player) == 1 else "s"]
	crown.position = Vector2(220, 30)
	crown.add_theme_font_size_override("font_size", 13)
	crown.add_theme_color_override("font_color", Color("c9b8ff"))
	panel.add_child(crown)
	list = Tree.new()
	list.position = Vector2(20, 60)
	list.size = Vector2(620, 506)
	list.columns = 7
	list.column_titles_visible = true
	list.hide_root = true
	list.select_mode = Tree.SELECT_ROW
	var titles = ["#", "Adventurer", "Rank", "Renown", "Deepest", "Bosses", "Week"]
	var widths = [40, 230, 50, 80, 70, 64, 56]
	for c in range(7):
		list.set_column_title(c, titles[c])
		list.set_column_custom_minimum_width(c, widths[c])
		list.set_column_expand(c, c == 1)
	list.item_selected.connect(func(): _show(int(list.get_selected().get_metadata(0))))
	panel.add_child(list)
	details = RichTextLabel.new()
	details.bbcode_enabled = true
	details.position = Vector2(660, 76)
	details.size = Vector2(400, 490)
	panel.add_child(details)
	var hint = Label.new()
	hint.text = "Renown: rank, Guild points, deepest floor, bosses, level and World Firsts. Reach S-rank and #1 to face the Ascension Trial."
	hint.position = Vector2(20, 578)
	hint.size = Vector2(840, 40)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	hint.add_theme_font_size_override("font_size", 13)
	hint.modulate = Color(0.75, 0.72, 0.65)
	panel.add_child(hint)
	var close = Button.new()
	close.text = "Close"
	close.custom_minimum_size = Vector2(150, 40)
	close.position = Vector2(910, 584)
	close.pressed.connect(queue_free)
	panel.add_child(close)
	_fill()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		queue_free()
		get_viewport().set_input_as_handled()

func _fill() -> void:
	list.clear()
	var root = list.create_item()
	var st = LedgerManager.standings(player)
	var top = int(LedgerManager.cfg().get("show_top", 15))
	rows = st.slice(0, top)
	var me = st.filter(func(p): return p.is_player)
	if not me.is_empty() and int(me[0].pos) > top:
		rows.append(me[0])
	var mine: TreeItem = null
	for i in range(rows.size()):
		var p: Dictionary = rows[i]
		var it = list.create_item(root)
		var mv = "▲%d" % p.move if p.move > 0 else ("▼%d" % -p.move if p.move < 0 else "-")
		var crowned = "♛ " if String(LedgerManager.champion(player).get("key", "")) == String(p.key) else ""
		var cells = [str(p.pos), crowned + p.name + (" (you)" if p.is_player else (" (your character)" if p.get("is_pc", false) else "")), String(p.rank), str(p.renown), str(p.deepest), str(p.bosses), mv]
		var col = Color("e6dccb")
		if p.is_player:
			col = Color("ffd166")
			mine = it
		elif not p.npc.is_empty() and (p.npc.get("rival", false) or p.npc.get("nemesis", false)):
			col = Color("ff8c69")
		elif p.get("is_pc", false):
			col = Color("c9b8ff")
		elif p.move > 0:
			col = Color("9fe0a0")
		for c in range(7):
			it.set_text(c, cells[c])
			it.set_custom_color(c, col)
			if c != 1:
				it.set_text_alignment(c, HORIZONTAL_ALIGNMENT_CENTER)
		it.set_metadata(0, i)
	if mine:
		mine.select(0)
		list.scroll_to_item.call_deferred(mine)
		_show(int(mine.get_metadata(0)))

func _show(i: int) -> void:
	if i < 0 or i >= rows.size():
		return
	var p: Dictionary = rows[i]
	var t = "[b][font_size=20]#%d  %s[/font_size][/b]\n" % [p.pos, p.name]
	t += "%s   Level %d\n\n" % [RankManager.display(String(p.rank)), int(p.level)]
	t += "[b]Renown:[/b] [color=#ffd166]%d[/color]\n" % int(p.renown)
	t += "Guild points: %d\nDeepest floor cleared: %d\nBosses slain: %d\nWorld Firsts: %d\nCrowns: %d\n" % [int(p.points), int(p.deepest), int(p.bosses), int(p.firsts), int(p.get("crowns", 0))]
	if p.get("is_pc", false):
		var e: Dictionary = WorldShare.others(player).get(p.name, {})
		t += "\n[color=#c9b8ff]Another adventurer of this world - one of your other characters.[/color]\n%s %s, last seen on day %d.\n" % [e.get("race", ""), e.get("cls", ""), int(e.get("day", 1))]
	elif not p.is_player:
		var n: Dictionary = p.npc
		t += "\n%s\n" % AdventurerManager.title_line(n)
		t += "[color=gray]%s[/color]\n" % AdventurerManager.status_text(player, n)
		var tg = AdventurerManager.tags(n)
		if not tg.is_empty():
			t += "[color=#ff8c69]%s[/color]\n" % ", ".join(tg)
		var me = LedgerManager.profile_player(player)
		var gap = int(p.renown) - int(me.renown)
		t += "\n" + ("[color=salmon]%d renown ahead of you.[/color]" % gap if gap > 0 else "[color=lime]%d renown behind you.[/color]" % -gap)
	details.text = t
