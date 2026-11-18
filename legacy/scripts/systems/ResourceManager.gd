# res://scripts/systems/ResourceManager.gd
class_name ResourceManager
extends RefCounted

# No character reference stored - passed as parameter to methods

func heal(character, amount: int) -> int:
	var hp_before = character.current_hp
	var max_heal = character.max_hp - character.current_hp
	var actual_heal = min(amount, max_heal)
	
	character.current_hp += actual_heal
	character.current_hp = min(character.current_hp, character.max_hp)
	
	print("[HEAL] %s: %d → %d (+%d requested, +%d actual, max: %d)" % [
		character.name, hp_before, character.current_hp, amount, actual_heal, character.max_hp
	])
	
	return actual_heal

func restore_mp(character, amount: int) -> int:
	var mp_before = character.current_mp
	var max_restore = character.max_mp - character.current_mp
	var actual_restore = min(amount, max_restore)
	
	character.current_mp += actual_restore
	character.current_mp = min(character.current_mp, character.max_mp)
	
	print("[RESTORE MP] %s: %d → %d (+%d)" % [character.name, mp_before, character.current_mp, actual_restore])
	return actual_restore

func restore_sp(character, amount: int) -> int:
	var sp_before = character.current_sp
	var max_restore = character.max_sp - character.current_sp
	var actual_restore = min(amount, max_restore)
	
	character.current_sp += actual_restore
	character.current_sp = min(character.current_sp, character.max_sp)
	
	print("[RESTORE SP] %s: %d → %d (+%d)" % [character.name, sp_before, character.current_sp, actual_restore])
	return actual_restore

func spend_mp(character, amount: int) -> bool:
	if character.current_mp >= amount:
		character.current_mp -= amount
		return true
	return false

func spend_sp(character, amount: int) -> bool:
	if character.current_sp >= amount:
		character.current_sp -= amount
		return true
	return false

func reset_resources(character):
	character.current_hp = character.max_hp
	character.current_mp = character.max_mp
	character.current_sp = character.max_sp
