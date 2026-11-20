# res://scenes/ui/BoonPicker.gd
# After a boss: choose 1 of a few run boons (RunState, data/boons.json).
# var p = BoonPicker.open(parent, ids); var id = await p.chosen
class_name BoonPicker
extends CanvasLayer

signal chosen(boon_id: String)

var ids: Array = []

## Up to `count` boons the run doesn't have yet.
static func offer(count: int = -1) -> Array:
	var n = count if count > 0 else int(RunState.boon_data().get("offer_count", 3))
	var pool = RunState.all_boons().keys().filter(func(i): return not i in RunState.boons)
	pool.shuffle()
	return pool.slice(0, n)

static func open(parent: Node, p_ids: Array) -> BoonPicker:
	var p = BoonPicker.new()
	p.ids = p_ids
	parent.add_child(p)
	return p

func _ready() -> void:
	layer = 70
	var dim = ColorRect.new()
	dim.color = Color(0, 0, 0, 0.7)
	dim.size = Vector2(1200, 720)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	var title = Label.new()
	title.text = "The boss falls. Choose a boon for this expedition."
	title.position = Vector2(0, 150)
	title.size = Vector2(1200, 40)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 26)
	add_child(title)
	var all = RunState.all_boons()
	var w := 320.0
	var gap := 30.0
	var x0 = (1200.0 - (ids.size() * w + (ids.size() - 1) * gap)) / 2.0
	for i in range(ids.size()):
		var b: Dictionary = all.get(ids[i], {})
		var btn = Button.new()
		btn.text = "%s\n\n%s" % [b.get("name", ids[i]), b.get("description", "")]
		btn.autowrap_mode = TextServer.AUTOWRAP_WORD
		btn.position = Vector2(x0 + i * (w + gap), 240)
		btn.custom_minimum_size = Vector2(w, 200)
		btn.size = Vector2(w, 200)
		var id = ids[i]
		btn.pressed.connect(func(): _pick(id))
		add_child(btn)
	var hint = Label.new()
	hint.text = "Boons last until you return to town." + (("  Held: " + ", ".join(RunState.names(RunState.boons, all))) if not RunState.boons.is_empty() else "")
	hint.position = Vector2(0, 470)
	hint.size = Vector2(1200, 30)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.modulate = Color(0.8, 0.76, 0.68)
	add_child(hint)

func _pick(id: String) -> void:
	RunState.add_boon(id)
	chosen.emit(id)
	queue_free()
