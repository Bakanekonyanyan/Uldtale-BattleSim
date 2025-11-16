# StatusScene.gd - UPDATED with Elemental System Display
extends Control

var current_character: CharacterData

@onready var name_label = $NameLabel if has_node("NameLabel") else null
@onready var class_label = $ClassLabel if has_node("ClassLabel") else null
@onready var level_label = $LevelLabel if has_node("LevelLabel") else null
@onready var race_label = $RaceLabel if has_node("RaceLabel") else null
@onready var primary_attributes = $PrimaryAttributes if has_node("PrimaryAttributes") else null
@onready var secondary_attributes = $SecondaryAttributes if has_node("SecondaryAttributes") else null
@onready var elemental_info = $ElementalInfo if has_node("ElementalInfo") else null
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
	set_label_text(race_label, "Race: " + str(current_character.race))
	set_label_text(class_label, "Class: " + str(current_character.character_class))
	set_label_text(level_label, "Level: " + str(current_character.level))
	
	# ✅ COMBINED: Primary, Secondary, and Elemental Info
	if elemental_info and current_character.get("elemental_resistances") != null:
		var info_text = ""
		
		# === PRIMARY ATTRIBUTES ===
		info_text += "[b][color=cyan]Primary Attributes:[/color][/b]\n"
		info_text += "Vitality: %d | Strength: %d | Dexterity: %d\n" % [
			current_character.vitality,
			current_character.strength,
			current_character.dexterity
		]
		info_text += "Intelligence: %d | Faith: %d | Mind: %d\n" % [
			current_character.intelligence,
			current_character.faith,
			current_character.mind
		]
		info_text += "Endurance: %d | Arcane: %d\n" % [
			current_character.endurance,
			current_character.arcane
		]
		info_text += "Agility: %d | Fortitude: %d\n\n" % [
			current_character.agility,
			current_character.fortitude
		]
		
		# === SECONDARY ATTRIBUTES ===
		info_text += "[b][color=cyan]Secondary Attributes:[/color][/b]\n"
		info_text += "HP: %d / %d | MP: %d / %d | SP: %d / %d\n" % [
			current_character.current_hp,
			current_character.max_hp,
			current_character.current_mp,
			current_character.max_mp,
			current_character.current_sp,
			current_character.max_sp
		]
		info_text += "Attack Power: %d | Spell Power: %d\n" % [
			current_character.get_attack_power(),
			current_character.spell_power
		]
		info_text += "Defense: %d | Toughness: %.2f\n" % [
			current_character.get_defense(),
			current_character.toughness
		]
		info_text += "Dodge: %.1f%% | Spell Ward: %.2f\n" % [
			current_character.dodge * 100,
			current_character.spell_ward
		]
		info_text += "Accuracy: %.1f%% | Crit Rate: %.1f%%\n\n" % [
			current_character.accuracy * 100,
			current_character.critical_hit_rate * 100
		]
		
		# === ELEMENTAL AFFINITIES ===
		info_text += "[b][color=orange]Elemental Affinities:[/color][/b]\n\n"
		
		# Show ALL elements with their values
		for element in ElementalDamage.Element.values():
			if element == ElementalDamage.Element.NONE:
				continue
			
			var element_name = ElementalDamage.get_element_name(element)
			var color = ElementalDamage.get_element_color(element)
			var resist = current_character.get_elemental_resistance(element)
			var weak = current_character.get_elemental_weakness(element)
			var bonus = current_character.get_elemental_damage_bonus(element)
			
			# Build element line
			var line = "[color=%s]%s:[/color]" % [color, element_name]
			
			var stats = []
			if resist > 0.0:
				stats.append("[color=cyan]-%d%% dmg taken[/color]" % int(resist * 100))
			if weak > 0.0:
				stats.append("[color=orange]+%d%% dmg taken[/color]" % int(weak * 100))
			if bonus > 0.0:
				stats.append("[color=lime]+%d%% dmg dealt[/color]" % int(bonus * 100))
			
			if stats.is_empty():
				line += " [color=gray]Normal[/color]"
			else:
				line += " " + ", ".join(stats)
			
			info_text += line + "\n"
		
		if elemental_info is RichTextLabel:
			elemental_info.bbcode_enabled = true
			elemental_info.text = info_text
		else:
			elemental_info.text = info_text
	elif elemental_info:
		# For old characters without elemental system
		var info_text = ""
		
		# === PRIMARY ATTRIBUTES ===
		info_text += "[b][color=cyan]Primary Attributes:[/color][/b]\n"
		info_text += "Vitality: %d | Strength: %d | Dexterity: %d\n" % [
			current_character.vitality,
			current_character.strength,
			current_character.dexterity
		]
		info_text += "Intelligence: %d | Faith: %d | Mind: %d\n" % [
			current_character.intelligence,
			current_character.faith,
			current_character.mind
		]
		info_text += "Endurance: %d | Arcane: %d\n" % [
			current_character.endurance,
			current_character.arcane
		]
		info_text += "Agility: %d | Fortitude: %d\n\n" % [
			current_character.agility,
			current_character.fortitude
		]
		
		# === SECONDARY ATTRIBUTES ===
		info_text += "[b][color=cyan]Secondary Attributes:[/color][/b]\n"
		info_text += "HP: %d / %d | MP: %d / %d | SP: %d / %d\n" % [
			current_character.current_hp,
			current_character.max_hp,
			current_character.current_mp,
			current_character.max_mp,
			current_character.current_sp,
			current_character.max_sp
		]
		info_text += "Attack Power: %d | Spell Power: %d\n" % [
			current_character.get_attack_power(),
			current_character.spell_power
		]
		info_text += "Defense: %d | Toughness: %.2f\n" % [
			current_character.get_defense(),
			current_character.toughness
		]
		info_text += "Dodge: %.1f%% | Spell Ward: %.2f\n" % [
			current_character.dodge * 100,
			current_character.spell_ward
		]
		info_text += "Accuracy: %.1f%% | Crit Rate: %.1f%%\n\n" % [
			current_character.accuracy * 100,
			current_character.critical_hit_rate * 100
		]
		
		info_text += "[color=gray][i]Elemental system not initialized for this character[/i][/color]"
		
		if elemental_info is RichTextLabel:
			elemental_info.bbcode_enabled = true
			elemental_info.text = info_text
		else:
			elemental_info.text = info_text
	
	# Equipment
	if equipment_info:
		var equipment_text = "[b][color=cyan]Equipment:[/color][/b]\n\n"
		for slot in current_character.equipment:
			var item = current_character.equipment[slot]
			var slot_name = slot.capitalize().replace("_", " ")
			if item:
				var color = item.get_rarity_color()
				var item_text = "%s: [color=%s]%s[/color] [%s]" % [slot_name, color, item.name, item.rarity.capitalize()]
				
				# Show key stats
				if item.damage > 0:
					item_text += " (%d dmg)" % item.damage
				if item.armor_value > 0:
					item_text += " (%d armor)" % item.armor_value
				
				equipment_text += item_text + "\n"
			else:
				equipment_text += "%s: [color=gray]Empty[/color]\n" % slot_name
		
		if equipment_info is RichTextLabel:
			equipment_info.bbcode_enabled = true
			equipment_info.text = equipment_text
		else:
			equipment_info.text = equipment_text
	
	if xp_label:
		xp_label.text = "XP: %d / %d" % [current_character.xp, LevelSystem.calculate_xp_for_level(current_character.level)]
	
	# Skills
	if skills_info:
		var skills_text = "[b][color=cyan]Skills:[/color][/b]\n"
		for skill_name in current_character.skills:
			var skill = current_character.get_skill_instance(skill_name)
			if skill:
				var level_str = skill.get_level_string()
				var progress_text = ""
				if skill.level < 6:
					var next_threshold = skill.LEVEL_THRESHOLDS[skill.level - 1]
					progress_text = " (%d/%d uses)" % [skill.uses, next_threshold]
				
				skills_text += "\n[b]%s[/b] - Level %s%s\n" % [skill.name, level_str, progress_text]
				skills_text += "  [color=gray]%s[/color]\n" % skill.description
				
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
		
		if skills_info is RichTextLabel:
			skills_info.bbcode_enabled = true
			skills_info.text = skills_text
		else:
			skills_info.text = skills_text
	
	# Proficiencies
	if prof_info and current_character.proficiency_manager:
		var prof_text = "[b][color=cyan]Proficiencies:[/color][/b]\n\n"
		
		var prof_mgr = current_character.proficiency_manager
		
		# Get available weapon types
		var available_weapons = prof_mgr.get_available_weapon_types()
		
		prof_text += "[b]Weapons & Off-Hand:[/b]\n"
		if available_weapons.is_empty():
			prof_text += "  [color=gray]No weapons available[/color]\n"
		else:
			available_weapons.sort()
			for weapon_key in available_weapons:
				var prof_str = prof_mgr.get_weapon_proficiency_string(weapon_key)
				prof_text += "  " + prof_str + "\n"
		
		# Get available armor types
		var available_armors = prof_mgr.get_available_armor_types()
		
		prof_text += "\n[b]Armor:[/b]\n"
		if available_armors.is_empty():
			prof_text += "  [color=gray]No armor available[/color]\n"
		else:
			available_armors.sort()
			for armor_type in available_armors:
				var prof_str = prof_mgr.get_armor_proficiency_string(armor_type)
				prof_text += "  " + prof_str + "\n"
		
		if prof_info is RichTextLabel:
			prof_info.bbcode_enabled = true
			prof_info.text = prof_text
		else:
			prof_info.text = prof_text
	
	print("StatusScene: update_status completed")

func set_label_text(label, text: String):
	if label:
		if label is RichTextLabel:
			label.bbcode_enabled = true
		label.text = text
	else:
		print("Warning: Attempted to set text on a null label")

func _on_exit_pressed():
	SceneManager.change_to_town(current_character)
