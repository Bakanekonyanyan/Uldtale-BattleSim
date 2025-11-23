# res://scripts/factories/CharacterFactory.gd
class_name CharacterFactory
extends RefCounted

const RACES_PATH = "res://data/races.json"
const CLASSES_PATH = "res://data/classes.json"

static var _races_data: Dictionary = {}
static var _classes_data: Dictionary = {}

static func _load_data():
	if _races_data.is_empty():
		var file = FileAccess.open(RACES_PATH, FileAccess.READ)
		if file:
			_races_data = JSON.parse_string(file.get_as_text())
			file.close()
	
	if _classes_data.is_empty():
		var file = FileAccess.open(CLASSES_PATH, FileAccess.READ)
		if file:
			_classes_data = JSON.parse_string(file.get_as_text())
			file.close()

static func create_character(char_name: String, race: String, char_class: String, is_player: bool = false) -> CharacterData:
	_load_data()
	
	var char = CharacterData.new(char_name, race, char_class)
	char.is_player = is_player
	
	var race_type = "playable" if is_player else "non_playable"
	var class_type = "playable" if is_player else ("boss" if char_class == "King" else "non_playable")
	
	var race_data = _races_data[race_type][race]
	var class_data = _classes_data[class_type][char_class]
	
	# Apply base stats
	char.vitality = class_data.base_vit + race_data.vit_mod
	char.strength = class_data.base_str + race_data.str_mod
	char.dexterity = class_data.base_dex + race_data.dex_mod
	char.intelligence = class_data.base_int + race_data.int_mod
	char.faith = class_data.base_fai + race_data.fai_mod
	char.mind = class_data.base_mnd + race_data.mnd_mod
	char.endurance = class_data.base_end + race_data.end_mod
	char.arcane = class_data.base_arc + race_data.arc_mod
	char.agility = class_data.base_agi + race_data.agi_mod
	char.fortitude = class_data.base_for + race_data.for_mod
	
	char.attack_power_type = class_data.attack_power_type
	char.spell_power_type = class_data.spell_power_type
	
	# Initialize skills
	if "skills" in class_data:
		char.skill_manager.add_skills(class_data.skills)
	
	# Initialize racial elementals
	char.initialize_racial_elementals(true)
	
	# Calculate secondary attributes
	char.calculate_secondary_attributes()
	
	return char

static func create_boss(floor: int) -> CharacterData:
	var boss = create_character("Floor %d King" % floor, "Orc", "King", false)
	boss.level = floor
	
	# Scale stats with floor
	var scale = 1.0 + (floor - 1) * 0.15
	boss.vitality = int(boss.vitality * scale)
	boss.strength = int(boss.strength * scale)
	boss.calculate_secondary_attributes()
	
	return boss

static func create_enemy(floor: int, enemy_class: String, race: String) -> CharacterData:
	var enemy = create_character("Enemy", race, enemy_class, false)
	enemy.level = floor
	
	# Scale with floor
	var scale = 1.0 + (floor - 1) * 0.1
	enemy.vitality = int(enemy.vitality * scale)
	enemy.strength = int(enemy.strength * scale)
	enemy.calculate_secondary_attributes()
	
	return enemy
