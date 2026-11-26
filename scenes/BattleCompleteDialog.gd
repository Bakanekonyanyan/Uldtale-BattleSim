# res://scenes/BattleCompleteDialog.gd
# After a won wave: Press On or Take a Breather. Shows what the choice is
# about - the party's condition, the momentum at stake and what comes next -
# but not the loot itself: what's in the bag stays a surprise until the
# Breather (that's the gamble).
extends Control

signal press_on_selected
signal take_breather_selected

const PANEL := Rect2(96, 40, 1008, 640)

var xp_gained: int = 0
var player_character: CharacterData
var heroes: Array = []

var title_label: Label
var sub_label: RichTextLabel
var party_text: RichTextLabel
var stakes_text: RichTextLabel
var press_on_button: Button
var breather_button: Button

func _ready():
	hide()
	mouse_filter = Control.MOUSE_FILTER_STOP
	size = Vector2(1200, 720)
	for c in get_children():
		if c is CanvasItem and not (c is Sprite2D):
			c.visible = false
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.size = size
	add_child(dim)
	var panel := Panel.new()
	ScreenChrome.place(panel, PANEL)
	add_child(panel)
	title_label = Label.new()
	title_label.theme_type_variation = "ScreenTitle"
	title_label.text = "Victory!"
	ScreenChrome.place(title_label, Rect2(28, 16, 600, 48))
	panel.add_child(title_label)
	sub_label = RichTextLabel.new()
	sub_label.bbcode_enabled = true
	ScreenChrome.place(sub_label, Rect2(28, 64, 952, 56))
	panel.add_child(sub_label)
	ScreenChrome.caption(panel, "YOUR PARTY", Vector2(28, 124))
	party_text = RichTextLabel.new()
	party_text.bbcode_enabled = true
	ScreenChrome.place(party_text, Rect2(28, 150, 470, 236))
	panel.add_child(party_text)
	ScreenChrome.caption(panel, "WHAT'S AT STAKE", Vector2(520, 124))
	stakes_text = RichTextLabel.new()
	stakes_text.bbcode_enabled = true
	ScreenChrome.place(stakes_text, Rect2(520, 150, 460, 236))
	panel.add_child(stakes_text)
	press_on_button = _choice(Rect2(28, 404, 466, 208), _on_press_on)
	breather_button = _choice(Rect2(514, 404, 466, 208), _on_breather)
	panel.add_child(press_on_button)
	panel.add_child(breather_button)

func _choice(r: Rect2, cb: Callable) -> Button:
	var b := Button.new()
	ScreenChrome.place(b, r)
	b.autowrap_mode = TextServer.AUTOWRAP_WORD
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.pressed.connect(cb)
	return b

## `allies`: the rest of the party (CharacterData), shown with the player.
func show_dialog(character: CharacterData, xp: int, allies: Array = []):
	player_character = character
	xp_gained = xp
	heroes = [character] + allies
	var dsm = DungeonStateManager
	var where = LocationManager.get_display_name(dsm.current_location)
	var wave_text = "boss defeated" if dsm.is_boss_fight else "wave %d of %d" % [dsm.current_wave, dsm.waves_per_floor]
	var next_text = "[color=#e07a5f]Next: the floor's boss.[/color]" if not dsm.is_boss_fight and dsm.current_wave >= dsm.waves_per_floor else ("Next: floor %d." % (dsm.current_floor + 1) if dsm.is_boss_fight else "Next: wave %d." % (dsm.current_wave + 1))
	var need = LevelSystem.calculate_xp_for_level(character.level)
	var lvl = "  [color=#e5c34a]Level up![/color]" if character.xp + xp >= need else "  [color=#a99f90](%d / %d to level %d)[/color]" % [character.xp + xp, need, character.level + 1]
	sub_label.text = "%s, floor %d - %s.   %s\n[color=#8fd46a]+%d XP[/color]%s" % [where, dsm.current_floor, wave_text, next_text, xp, lvl]
	party_text.text = _party_text()
	stakes_text.text = _stakes_text()
	var m = MomentumSystem.get_momentum()
	var next_level = mini(m + 1, MomentumSystem.MAX_MOMENTUM)
	press_on_button.text = "PRESS ON\n\nMomentum x%d: +%d%% damage, and the Breather will pay +%d%%.\nNo rest. If you fall, every unopened wave is lost." % [
		next_level, int(round(next_level * MomentumSystem.DAMAGE_BONUS_PER_LEVEL * 100)), int(round(MomentumSystem.get_reward_bonus(next_level) * 100))]
	breather_button.text = "TAKE A BREATHER\n\nOpen the spoils of %d wave%s%s.\nRest and recover. Momentum resets." % [
		m + 1, "" if m == 0 else "s", " (+%d%% bonus)" % int(round(MomentumSystem.get_reward_bonus() * 100)) if MomentumSystem.has_momentum_bonus() else ""]
	if MomentumSystem.should_show_bonus_notification():
		var bonus_popup = AcceptDialog.new()
		bonus_popup.dialog_text = "Maximum Momentum Bonus!\n\nMomentum x%d: your next Breather opens everything you've banked with +%d%% rewards.\nPressing on still raises your damage - and the danger." % [
			MomentumSystem.get_momentum(), int(MomentumSystem.MAX_REWARD_BONUS * 100)]
		bonus_popup.title = "Momentum Bonus!"
		add_child(bonus_popup)
		bonus_popup.popup_centered()
	show()

func _party_text() -> String:
	var t := ""
	for h in heroes:
		if h == null:
			continue
		var down = h.current_hp <= 0
		t += "[b]%s[/b]%s\n" % [h.name, "  [color=#e07a5f]down[/color]" if down else ""]
		t += "  %s   %s   %s\n" % [_stat("HP", h.current_hp, h.max_hp, 0.5), _stat("MP", h.current_mp, h.max_mp, 0.3), _stat("SP", h.current_sp, h.max_sp, 0.3)]
		if not h.status_effects.is_empty():
			t += "  [color=#c9b8ff]%s[/color]\n" % h.get_status_effects_string()
	return t

func _stat(label: String, cur: int, mx: int, low: float) -> String:
	var col = "#e07a5f" if mx > 0 and cur < mx * low else "#e6dccb"
	return "%s [color=%s]%d/%d[/color]" % [label, col, cur, mx]

func _stakes_text() -> String:
	var m = MomentumSystem.get_momentum()
	var t = "Momentum [b]x%d[/b] of %d" % [m, MomentumSystem.MAX_MOMENTUM]
	t += "  ([color=#ffb066]+%d%% damage[/color])\n" % int(round(m * MomentumSystem.DAMAGE_BONUS_PER_LEVEL * 100)) if m > 0 else "\n"
	t += "Unopened spoils: [b]%d wave%s[/b]\n" % [m + 1, "" if m == 0 else "s"]
	if MomentumSystem.has_momentum_bonus():
		t += "Breather bonus now: [color=#8fd46a]+%d%%[/color]\n" % int(round(MomentumSystem.get_reward_bonus() * 100))
	var omen: Array = RunState.omens.map(func(id): return String(RunState.all_omens().get(id, {}).get("name", id)))
	if not omen.is_empty():
		t += "Omens: [color=#c9b8ff]%s[/color]\n" % ", ".join(omen)
	t += "\n[color=#a99f90]What's in the bag stays a mystery until you stop to look.[/color]"
	return t

func _on_press_on():
	press_on_selected.emit()
	queue_free()

func _on_breather():
	take_breather_selected.emit()
	queue_free()
