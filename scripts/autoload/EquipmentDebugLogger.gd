# EquipmentDebugLogger.gd - Autoload singleton to track equipment flow
# Add this to your autoloads to track equipment instances

extends Node

var tracked_equipment = {}  # Maps equipment instance ID to its stats

func track_equipment(equipment: Equipment, location: String):
	"""Track an equipment instance's stats at a specific point"""
	var instance_id = equipment.get_instance_id()
	
	if not tracked_equipment.has(instance_id):
		tracked_equipment[instance_id] = {
			"name": equipment.name,
			"ilvl": equipment.item_level,
			"rarity": equipment.rarity,
			"damage": equipment.damage,
			"armor": equipment.armor_value,
			"stat_modifiers": equipment.stat_modifiers.duplicate(),
			"flow": []
		}
	
	tracked_equipment[instance_id]["flow"].append({
		"location": location,
		"timestamp": Time.get_ticks_msec()
	})
	
	print("EquipmentDebug: [%s] %s (ilvl %d, instance %d) at %s" % [
		location,
		equipment.name,
		equipment.item_level,
		instance_id,
		Time.get_ticks_msec()
	])

func verify_no_changes(equipment: Equipment, location: String) -> bool:
	"""Verify equipment stats haven't changed since tracking started"""
	var instance_id = equipment.get_instance_id()
	
	if not tracked_equipment.has(instance_id):
		print("EquipmentDebug: WARNING - Equipment not tracked: ", equipment.name)
		return false
	
	var original = tracked_equipment[instance_id]
	var changed = false
	
	if original["damage"] != equipment.damage:
		print("EquipmentDebug: ERROR - Damage changed! %d -> %d at %s" % [
			original["damage"], equipment.damage, location
		])
		changed = true
	
	if original["armor"] != equipment.armor_value:
		print("EquipmentDebug: ERROR - Armor changed! %d -> %d at %s" % [
			original["armor"], equipment.armor_value, location
		])
		changed = true
	
	if original["stat_modifiers"] != equipment.stat_modifiers:
		print("EquipmentDebug: ERROR - Stat modifiers changed at %s" % location)
		print("  Original: ", original["stat_modifiers"])
		print("  Current: ", equipment.stat_modifiers)
		changed = true
	
	if not changed:
		print("EquipmentDebug: VERIFIED - %s unchanged at %s ✓" % [
			equipment.name, location
		])
	
	return not changed

func print_flow(equipment: Equipment):
	"""Print the complete flow of an equipment instance"""
	var instance_id = equipment.get_instance_id()
	
	if not tracked_equipment.has(instance_id):
		print("EquipmentDebug: No flow data for: ", equipment.name)
		return
	
	var data = tracked_equipment[instance_id]
	print("EquipmentDebug: Flow for %s (instance %d):" % [data["name"], instance_id])
	for step in data["flow"]:
		print("  -> %s (t=%d)" % [step["location"], step["timestamp"]])

# Usage Example:
# In EnemyFactory.give_enemy_equipment():
#   EquipmentDebugLogger.track_equipment(item, "EnemyFactory.give_enemy_equipment")
#
# In RewardsManager.calculate_battle_rewards():
#   EquipmentDebugLogger.verify_no_changes(item, "RewardsManager.calculate_battle_rewards")
#
# In RewardScene.display_rewards():
#   EquipmentDebugLogger.verify_no_changes(equipment, "RewardScene.display_rewards")
#
# In RewardScene._on_accept_reward_pressed():
#   EquipmentDebugLogger.verify_no_changes(equipment, "RewardScene._on_accept_reward_pressed")
