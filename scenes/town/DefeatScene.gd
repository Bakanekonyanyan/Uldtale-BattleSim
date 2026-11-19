# res://scenes/town/DefeatScene.gd
# Shown after losing a battle: what the Guild charged you and what you lost.
# Penalties are applied by DefeatManager before this screen opens.
extends Control

var player_character: CharacterData

func _ready():
	if player_character == null:
		player_character = CharacterManager.get_current_character()
	var chrome = ScreenChrome.attach(self, "Defeated", _on_continue, "Return to Town")
	chrome.set_info(ScreenChrome.money_text(player_character))
	var s: Dictionary = player_character.get_meta("last_defeat", {}) if player_character else {}
	var panel := Panel.new()
	ScreenChrome.place(panel, Rect2(250, 110, 700, 470))
	$UI.add_child(panel)
	var text := RichTextLabel.new()
	text.bbcode_enabled = true
	text.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	ScreenChrome.place(text, Rect2(24, 18, 652, 434))
	panel.add_child(text)
	var t = "[font_size=20][b]You fell in battle.[/b][/font_size]\n"
	t += "[color=#a99f90]Guild scouts dragged you back to town. Recovery isn't free.[/color]\n\n"
	t += "[b]Recovery fee:[/b] [color=#e07a5f]%s[/color]\n" % Currency.format_copper(int(s.get("gold_lost", 0)))
	var inj: Dictionary = s.get("injury", {})
	if not inj.is_empty():
		t += "[b]Injury:[/b] [color=#e07a5f]%s[/color] - %s\n" % [inj.name, inj.description]
		t += "[color=#a99f90]  Lasts %d day(s). The Guild Infirmary can treat it sooner.[/color]\n" % int(inj.days)
	var items: Array = s.get("items", [])
	if items.is_empty():
		t += "[b]Gear:[/b] nothing lost.\n"
	else:
		t += "[b]Gear lost to the Guild's Lost & Found:[/b]\n"
		for it in items:
			t += "  %s  [color=#a99f90](%s - buy back for %s)[/color]\n" % [it.name, String(it.rarity).capitalize(), Currency.format_copper(int(it.price))]
		t += "[color=#a99f90]Buy it back at the Guild before it's sold off.[/color]\n"
	t += "\n[color=#a99f90]Any loot banked by pressing on was lost.[/color]"
	var who = CharacterManager.get_current_character()
	if who:
		t += "\n[color=#a99f90]You wake in the Guild infirmary on %s.[/color]" % WorldClock.date_text(who)
	text.text = t

func set_player(character: CharacterData) -> void:
	player_character = character

func _on_continue() -> void:
	SceneManager.change_to_town(player_character)
