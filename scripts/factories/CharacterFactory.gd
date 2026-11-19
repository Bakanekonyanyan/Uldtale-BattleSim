# res://scripts/factories/CharacterFactory.gd
class_name CharacterFactory
extends RefCounted

## Race and class tables come from DataRegistry (parsed once, shared).
static var _races_data: Dictionary:
	get: return DataRegistry.get_data("races")
static var _classes_data: Dictionary:
	get: return DataRegistry.get_data("classes")

static func create_character(char_name: String, race: String, char_class: String, is_player: bool = false) -> CharacterData:
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
