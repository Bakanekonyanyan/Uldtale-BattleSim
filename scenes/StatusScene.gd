# StatusScene.gd
extends Control

var current_character: CharacterData

@onready var name_label = $NameLabel if has_node("NameLabel") else null
@onready var class_label = $ClassLabel if has_node("ClassLabel") else null
@onready var level_label = $LevelLabel if has_node("LevelLabel") else null
@onready var primary_attributes = $PrimaryAttributes if has_node("PrimaryAttributes") else null
@onready var secondary_attributes = $SecondaryAttributes if has_node("SecondaryAttributes") else null
@onready var equipment_info = $EquipmentInfo if has_node("EquipmentInfo") else null
@onready var skills_info = $SkillsInfo if has_node("SkillsInfo") else null
@onready var prof_info = $ProficiencyInfo if has_node("ProficiencyInfo") else null
@onready var exit_button = $ExitButton if has_node("ExitButton") else null
@onready var xp_label = $XPLabel


func _ready():
	print("StatusScene: _ready called")
	current_character = CharacterManager.get_current_character()
	if not current_character:
		print("Error: No character loaded")
		return
	update_status()
	
	if exit_button:
		exit_button.connect("pressed", Callable(self, "_on_exit_pressed"))

func set_player(character: CharacterData):
	current_character = character
	update_status()

func update_status():
	print("StatusScene: update_status called")
	if not current_character:
		print("Error: No character data available")
		return
	
	set_label_text(name_label, "Name: " + str(current_character.name))
	set_label_text(class_label, "Class: " + str(current_character.character_class))
	set_label_text(level_label, "Level: " + str(current_character.level))
	
	if primary_attributes:
		set_label_text(primary_attributes, """
		Vitality: %d
		Strength: %d
		Dexterity: %d
		Intelligence: %d
		Faith: %d
		Mind: %d
		Endurance: %d
		Arcane: %d
		Agility: %d
		Fortitude: %d
		""" % [
			current_character.vitality,
			current_character.strength,
			current_character.dexterity,
			current_character.intelligence,
			current_character.faith,
			current_character.mind,
			current_character.endurance,
			current_character.arcane,
			current_character.agility,
			current_character.fortitude
		])
	else:
		print("Error: PrimaryAttributes node not found")
	
	if secondary_attributes:
		set_label_text(secondary_attributes, """
		HP: %d / %d
		MP: %d / %d
		Attack Power: %d
		Spell Power: %d
		Defense: %d
		Toughness: %.2f
		Dodge: %.2f%%
		Spell Ward: %.2f
		Accuracy: %.2f%%
		Crit Rate: %.2f%%
		""" % [
			current_character.current_hp,
			current_character.max_hp,
			current_character.current_mp,
			current_character.max_mp,
			current_character.get_attack_power(),
			current_character.spell_power,
			current_character.get_defense(),
			current_character.toughness,
			current_character.dodge * 100,
			current_character.spell_ward,
			current_character.accuracy * 100,
			current_character.critical_hit_rate * 100
		])
	
	if equipment_info:
		var equipment_text = "Equipment:\n"
		for slot in current_character.equipment:
			var item = current_character.equipment[slot]
			var slot_name = slot.capitalize().replace("_", " ")
			if item:
				# Use BBCode for colored text
				var color = item.get_rarity_color()
				equipment_text += "%s: [color=%s]%s[/color] [%s]\n" % [slot_name, color, item.name, item.rarity.capitalize()]
			else:
				equipment_text += "%s: Empty\n" % slot_name
		
		# Enable BBCode for RichTextLabel or create a RichTextLabel if it's a Label
		if equipment_info is RichTextLabel:
			equipment_info.bbcode_enabled = true
			equipment_info.text = equipment_text
		else:
			# If it's a Label, we need to convert the scene to use RichTextLabel
			# For now, just set the text without colors
			equipment_info.text = equipment_text
	
	if xp_label:
		xp_label.text = "XP: %d / %d" % [current_character.xp, LevelSystem.calculate_xp_for_level(current_character.level)]
	
	# Display skills with levels and progress
	if skills_info:
		var skills_text = "[b]Skills:[/b]\n"
		for skill_name in current_character.skills:
			var skill = current_character.get_skill_instance(skill_name)
			if skill:
				var level_str = skill.get_level_string()
				var progress_text = ""
				if skill.level < 6:
					var next_threshold = skill.LEVEL_THRESHOLDS[skill.level - 1]
					progress_text = " (%d/%d uses)" % [skill.uses, next_threshold]
				
				skills_text += "\n[b]%s[/b] - Level %s%s\n" % [skill.name, level_str, progress_text]
				skills_text += "  %s\n" % skill.description
				
				# Show skill stats
				if skill.type in [Skill.SkillType.DAMAGE, Skill.SkillType.HEAL, Skill.SkillType.RESTORE]:
					skills_text += "  Power: %d | " % skill.power
				if skill.type in [Skill.SkillType.BUFF, Skill.SkillType.DEBUFF, Skill.SkillType.INFLICT_STATUS]:
					if skill.duration > 0:
						skills_text += "  Duration: %d turns | " % skill.duration
				
				# Show costs
				if skill.mp_cost > 0:
					skills_text += "MP Cost: %d | " % skill.mp_cost
				if skill.sp_cost > 0:
					skills_text += "SP Cost: %d | " % skill.sp_cost
				if skill.cooldown > 0:
					skills_text += "Cooldown: %d turns" % skill.cooldown
				skills_text += "\n"
		
		# Enable BBCode for RichTextLabel
		if skills_info is RichTextLabel:
			skills_info.bbcode_enabled = true
			skills_info.text = skills_text
		else:
			skills_info.text = skills_text
	
	# NEW: Display proficiencies
	if current_character.proficiency_manager:
		var prof_text = "\n\n[b][color=cyan]Proficiencies:[/color][/b]\n\n"
		
		# Weapon proficiencies
		var weapon_profs = current_character.proficiency_manager.get_all_weapon_proficiencies()
		if not weapon_profs.is_empty():
			prof_text += "[b]Weapons:[/b]\n"
			for prof_str in weapon_profs:
				prof_text += "  " + prof_str + "\n"
		
		# Armor proficiencies
		var armor_profs = current_character.proficiency_manager.get_all_armor_proficiencies()
		if not armor_profs.is_empty():
			prof_text += "\n[b]Armor:[/b]\n"
			for prof_str in armor_profs:
				prof_text += "  " + prof_str + "\n"
		prof_info.text += prof_text
		
	print("StatusScene: update_status completed")

func set_label_text(label: Label, text: String):
	if label:
		label.text = text
	else:
		print("Warning: Attempted to set text on a null label")

func _on_exit_pressed():
	# Return to the previous scene (likely the town scene)
	SceneManager.change_to_town(current_character)
