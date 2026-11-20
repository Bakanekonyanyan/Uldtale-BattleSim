# res://scenes/ui/CommissionBoard.gd
# The shops' open commissions (CommissionManager): request, progress, reward,
# your standing and its perks, and a Deliver button each. Built in code.
class_name CommissionBoard
extends CanvasLayer

var player: CharacterData
var rows: VBoxContainer
var status: Label

static func open(parent: Node, p: CharacterData) -> CommissionBoard:
	var b = CommissionBoard.new()
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
	panel.position = Vector2(110, 70)
	panel.size = Vector2(980, 580)
	add_child(panel)
	var title = Label.new()
	title.text = "Commissions"
	title.position = Vector2(24, 12)
	title.add_theme_font_size_override("font_size", 24)
	panel.add_child(title)
	var hint = Label.new()
	hint.text = "Bring the shops what they ask for. Standing earns discounts, better odds and new recipes."
	hint.position = Vector2(200, 20)
	hint.add_theme_font_size_override("font_size", 14)
	hint.modulate = Color(0.75, 0.72, 0.65)
	panel.add_child(hint)
	rows = VBoxContainer.new()
	rows.position = Vector2(24, 64)
	rows.size = Vector2(932, 440)
	rows.add_theme_constant_override("separation", 12)
	panel.add_child(rows)
	status = Label.new()
	status.position = Vector2(24, 528)
	status.size = Vector2(760, 40)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD
	panel.add_child(status)
	var close = Button.new()
	close.text = "Close"
	close.custom_minimum_size = Vector2(150, 40)
	close.position = Vector2(806, 524)
	close.pressed.connect(queue_free)
	panel.add_child(close)
	_fill()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		queue_free()
		get_viewport().set_input_as_handled()

func _fill() -> void:
	for c in rows.get_children():
		c.queue_free()
	var day = WorldClock.day(player)
	for shop in CommissionManager.shops():
		var a = CommissionManager.active(player, shop)
		var box = HBoxContainer.new()
		box.add_theme_constant_override("separation", 16)
		var text = RichTextLabel.new()
		text.bbcode_enabled = true
		text.fit_content = true
		text.custom_minimum_size = Vector2(760, 0)
		var name = String(CommissionManager.shops()[shop].get("name", shop))
		var t = "[b]%s[/b]   [color=#ffd166]%s[/color] (%d delivered)\n" % [name, CommissionManager.tier_name(player, shop), CommissionManager.done(player, shop)]
		t += "[i]%s[/i]\n" % CommissionManager.describe(player, shop)
		if not a.is_empty():
			var have = player.count_owned(String(a.item))
			t += "[color=%s]Have %d / %d[/color]   Reward: %s   [color=gray]%d day%s left[/color]\n" % [
				"lime" if have >= int(a.qty) else "salmon", have, int(a.qty), Currency.format_copper(int(a.reward)), max(0, int(a.due) - day), "" if int(a.due) - day == 1 else "s"]
		t += "[color=gray]%s[/color]" % _perks(shop)
		text.text = t
		box.add_child(text)
		var btn = Button.new()
		btn.text = "Deliver"
		btn.custom_minimum_size = Vector2(140, 40)
		btn.disabled = a.is_empty() or player.count_owned(String(a.item)) < int(a.qty)
		btn.pressed.connect(func():
			var r = CommissionManager.deliver(player, shop)
			status.text = r.reason
			_fill())
		box.add_child(btn)
		rows.add_child(box)

func _perks(shop: String) -> String:
	match shop:
		"alchemist":
			return "Standing teaches the Alchemist's special recipes."
	var d = CommissionManager.perk(player, shop, "discount")
	var s = CommissionManager.perk(player, shop, "success")
	return "Perks: -%d%% gold, +%d%% success" % [int(round(d * 100)), int(round(s * 100))] if d > 0 or s > 0 else "Perks start at Known standing: cheaper, more reliable work."
