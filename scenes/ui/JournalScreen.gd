# res://scenes/ui/JournalScreen.gd
# The Journal: everything you're working on, in one place. Nothing new is
# tracked here - it reads the systems that own each objective:
#   standing (LedgerManager, RankManager), Guild bounties (GuildManager),
#   commissions (CommissionManager), rumours (RumorManager), companions
#   waiting to talk (BondManager), injuries and Lost & Found (DefeatManager).
# Anything due within DUE_SOON days is flagged.
class_name JournalScreen
extends CanvasLayer

const DUE_SOON := 2

var player: CharacterData
var body: RichTextLabel

static func open(parent: Node, p: CharacterData) -> JournalScreen:
	var j = JournalScreen.new()
	j.player = p
	parent.add_child(j)
	return j

func _ready() -> void:
	layer = 60
	var dim = ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.size = Vector2(1200, 720)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	var panel = Panel.new()
	panel.position = Vector2(140, 40)
	panel.size = Vector2(920, 640)
	add_child(panel)
	var title = Label.new()
	title.text = "Journal"
	title.position = Vector2(24, 12)
	title.add_theme_font_size_override("font_size", 24)
	panel.add_child(title)
	var date = Label.new()
	date.text = WorldClock.date_text(player)
	date.position = Vector2(160, 20)
	date.add_theme_font_size_override("font_size", 14)
	date.modulate = Color(0.75, 0.72, 0.65)
	panel.add_child(date)
	body = RichTextLabel.new()
	body.bbcode_enabled = true
	body.position = Vector2(24, 60)
	body.size = Vector2(872, 512)
	body.scroll_active = true
	panel.add_child(body)
	var close = Button.new()
	close.text = "Close"
	close.custom_minimum_size = Vector2(150, 40)
	close.position = Vector2(746, 584)
	close.pressed.connect(queue_free)
	panel.add_child(close)
	body.text = build_text(player)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		queue_free()
		get_viewport().set_input_as_handled()

static func _days(n: int) -> String:
	var t = "%d day%s left" % [n, "" if n == 1 else "s"]
	return "[color=#ff9f6b]%s - due soon[/color]" % t if n <= DUE_SOON else "[color=gray]%s[/color]" % t

static func _section(title: String, lines: Array, empty: String) -> String:
	var t = "[b][font_size=18][color=#ffd166]%s[/color][/font_size][/b]\n" % title
	if lines.is_empty():
		return t + "[color=gray][i]%s[/i][/color]\n\n" % empty
	for l in lines:
		t += "  • %s\n" % l
	return t + "\n"

## The whole journal as BBCode (also used by tests).
static func build_text(p: CharacterData) -> String:
	var t := ""
	var day = WorldClock.day(p)
	# --- standing
	var st: Array = [LedgerManager.summary(p)]
	var ch = LedgerManager.champion(p)
	st.append("The Crowning in %d days%s" % [LedgerManager.days_to_crowning(p),
		(" - reigning Champion: %s" % ("you" if ch.get("is_player", false) else String(ch.name))) if not ch.is_empty() else ""])
	st.append(PersonalityManager.player_reputation(p))
	var pr = RankManager.promotion_status(p)
	match String(pr.get("trial_state", "")):
		"top":
			st.append("%s - the highest rank" % RankManager.display(String(pr.rank)))
		"need_points":
			st.append("%s: %d / %d Guild points for %s" % [RankManager.display(String(pr.rank)), int(pr.points), int(pr.points_needed), RankManager.display(String(pr.next))])
		"available":
			st.append("[color=#7bd389]A promotion trial for %s is available at the Guild[/color]" % RankManager.display(String(pr.next)))
		"active":
			st.append("Promotion trial for %s under way" % RankManager.display(String(pr.next)))
		"ready":
			st.append("[color=#7bd389]Promotion trial complete - turn it in at the Guild[/color]")
		"demerits":
			st.append("[color=#ff9f6b]Promotion blocked by demerits[/color]")
	t += _section("Standing", st, "")
	# --- bounties
	var bl: Array = []
	for b in GuildManager.get_active(p):
		var state = "[color=#7bd389]ready to turn in[/color]" if GuildManager.is_complete(p, b) \
			else ("[color=gray]trial - no deadline[/color]" if b.get("trial", false) else _days(int(b.get("deadline", 0))))
		bl.append("[b]%s[/b] - %s   %s" % [b.title, GuildManager.describe_objective(p, b), state])
	t += _section("Guild bounties", bl, "None accepted. The Guild board has work.")
	# --- commissions
	var cl: Array = []
	for shop in CommissionManager.shops():
		var a = CommissionManager.active(p, shop)
		if a.is_empty():
			continue
		var have = p.count_owned(String(a.item))
		var item = ItemManager.get_item(String(a.item))
		cl.append("[b]%s[/b]: %d %s ([color=%s]have %d[/color]) for %s   %s" % [CommissionManager.shops()[shop].get("name", shop), int(a.qty),
			item.display_name if item else String(a.item), "lime" if have >= int(a.qty) else "salmon", have, Currency.format_copper(int(a.reward)), _days(max(0, int(a.due) - day))])
	t += _section("Commissions", cl, "No shop requests right now.")
	# --- rumours
	var rl: Array = []
	for r in RumorManager.list(p):
		rl.append("%s   %s" % [RumorManager.text(r), _days(max(0, int(r.expires) - day))])
	t += _section("Rumours", rl, "Nothing heard. Ask around at the Tavern.")
	# --- companions
	var bonds: Array = []
	for n in BondManager.pending(p):
		bonds.append("[color=#ff9fbf]%s wants to talk[/color] - visit the Tavern" % n.name)
	var inv = DramaManager.invitation(p)
	if not inv.is_empty():
		bonds.append("[color=#7bd389]%s invited you along[/color] - answer at the Tavern   %s" % [DramaManager.company(p, int(inv.company)).name, _days(max(0, int(inv.expires) - day))])
	for n in PartyManager.members(p):
		var tier = BondManager.tier_name(n)
		bonds.append("%s is in your party%s" % [n.name, (" (%s)" % tier) if tier != "" else ""])
	t += _section("Companions", bonds, "Nobody's travelling with you.")
	# --- people (your memories, who owes you)
	var ppl: Array = []
	for n in AdventurerManager.active(p):
		if MemoryManager.owes_you(n):
			ppl.append("[color=#7bd389]%s owes you a favour[/color] - they'll help you when it counts" % n.name)
	var mine = MemoryManager.list(p).duplicate()
	mine.sort_custom(func(a, b): return abs(float(a.w)) > abs(float(b.w)))
	for m in mine.slice(0, 8):
		ppl.append("[color=%s]%s[/color]" % ["#9fd8ff" if float(m.w) > 0 else "#ff9f6b", MemoryManager.text(m, p, true)])
	t += _section("People", ppl, "No one has left a mark on you yet.")
	# --- recovery
	var rec: Array = []
	for inj in DefeatManager.get_injuries(p):
		var info = DefeatManager.injury_info(String(inj.id))
		rec.append("Injury: %s - heals in %d day%s (or treat it at the Guild Infirmary)" % [info.get("name", inj.id), int(inj.remaining), "" if int(inj.remaining) == 1 else "s"])
	for e in DefeatManager.get_lost_found(p):
		rec.append("Lost & Found: %s, %s to buy back   %s" % [String(e.item.get("name", "gear")), Currency.format_copper(int(e.price)), _days(int(e.get("expires_in", 0)))])
	t += _section("Recovery", rec, "No injuries, nothing in Lost & Found.")
	return t
