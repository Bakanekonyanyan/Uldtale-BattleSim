# res://scripts/combat/BattleUIManager.gd
class_name BattleUIManager
extends RefCounted

var player_info: Label
var enemy_info: Label
var turn_label: Label
var combat_log: RichTextLabel
var debug_log: RichTextLabel
var xp_label: Label
var action_buttons: VBoxContainer

func initialize(ui_nodes: Dictionary):
	player_info = ui_nodes.get("player_info")
	enemy_info = ui_nodes.get("enemy_info")
	turn_label = ui_nodes.get("turn_label")
	combat_log = ui_nodes.get("combat_log")
	debug_log = ui_nodes.get("debug_log")
	xp_label = ui_nodes.get("xp_label")
	action_buttons = ui_nodes.get("action_buttons")

func update_character_info(player: CharacterData, enemy: CharacterData):
	if player_info and player:
		player_info.text = "Player: %s\nHP: %d/%d\nMP: %d/%d\nSP: %d/%d\nStatus: %s" % [
			player.name, player.current_hp, player.max_hp,
			player.current_mp, player.max_mp,
			player.current_sp, player.max_sp,
			player.get_status_effects_string()
		]
	
	if enemy_info and enemy:
		enemy_info.text = "Enemy: %s\nHP: %d/%d\nMP: %d/%d\nSP: %d/%d\nStatus: %s" % [
			enemy.name, enemy.current_hp, enemy.max_hp,
			enemy.current_mp, enemy.max_mp,
			enemy.current_sp, enemy.max_sp,
			enemy.get_status_effects_string()
		]

func update_turn_display(text: String):
	if turn_label:
		turn_label.text = text

func add_combat_log(message: String):
	if combat_log:
		combat_log.append_text(message + "\n")

func update_xp_display(current_xp: int, level: int):
	if xp_label:
		xp_label.text = "XP: %d / %d" % [current_xp, LevelSystem.calculate_xp_for_level(level)]

func enable_actions(enabled: bool):
	if action_buttons:
		for button in action_buttons.get_children():
			if button is Button:
				button.disabled = !enabled

func clear_action_buttons():
	if action_buttons:
		for child in action_buttons.get_children():
			child.queue_free()

func update_debug_display(player: CharacterData, enemy: CharacterData):
	if not debug_log:
		return
	
	debug_log.clear()
	debug_log.append_text("[b][color=cyan]PLAYER STATS[/color][/b]\n")
	debug_log.append_text("ATK Power: %.1f | Spell Power: %.1f\n" % [player.attack_power, player.spell_power])
	debug_log.append_text("Toughness: %.1f | Spell Ward: %.1f\n" % [player.toughness, player.spell_ward])
	debug_log.append_text("Accuracy: %.2f%% | Dodge: %.2f%% | Crit: %.2f%%\n" % [
		player.accuracy * 100, player.dodge * 100, player.critical_hit_rate * 100
	])
	debug_log.append_text("\n[b][color=red]ENEMY STATS[/color][/b]\n")
	debug_log.append_text("ATK Power: %.1f | Spell Power: %.1f\n" % [enemy.attack_power, enemy.spell_power])
	debug_log.append_text("Toughness: %.1f | Spell Ward: %.1f\n" % [enemy.toughness, enemy.spell_ward])
