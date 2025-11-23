# StatusScene.gd - ENHANCED UX/UI
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
	
	# Enhanced header display
	set_label_text(name_label, "[b][color=#FFD700]%s[/color][/b]" % str(current_character.name))
	set_label_text(race_label, "[color=#CCCCCC]%s[/color]" % str(current_character.race))
	set_label_text(class_label, "[color=#88DDFF]%s[/color]" % str(current_character.character_class))
	set_label_text(level_label, "[color=#FFAA44]Level %d[/color]" % current_character.level)
	
	# Enhanced XP display with progress bar
	if xp_label:
		var current_xp = current_character.xp
		var needed_xp = LevelSystem.calculate_xp_for_level(current_character.level)
		var xp_percent = (float(current_xp) / float(needed_xp)) * 100.0
		
		var xp_color = "#88FF88"
		if xp_percent >= 75:
			xp_color = "#FFD700"  # Gold when close to leveling
		
		xp_label.text = "[color=%s]XP: %d / %d  (%.1f%%)[/color]" % [
			xp_color, current_xp, needed_xp, xp_percent
		]
	
	# Combined attributes and elemental info
	if elemental_info and current_character.get("elemental_resistances") != null:
		var info_text = ""
		
		# === PRIMARY ATTRIBUTES ===
		info_text += "[center][b][color=#00DDFF]═══ PRIMARY ATTRIBUTES ═══[/color][/b][/center]\n\n"
		
		# Row 1: Physical stats
		info_text += "[color=#FF8888]⚔ Vitality:[/color] %s  " % current_character.get_attribute_display_compact("vitality")
		info_text += "[color=#FFAA44]💪 Strength:[/color] %s  " % current_character.get_attribute_display_compact("strength")
		info_text += "[color=#88FF88]🎯 Dexterity:[/color] %s\n" % current_character.get_attribute_display_compact("dexterity")
		
		# Row 2: Mental stats
		info_text += "[color=#88AAFF]🧠 Intelligence:[/color] %s  " % current_character.get_attribute_display_compact("intelligence")
		info_text += "[color=#FFDD88]✨ Faith:[/color] %s  " % current_character.get_attribute_display_compact("faith")
		info_text += "[color=#AA88FF]🔮 Mind:[/color] %s\n" % current_character.get_attribute_display_compact("mind")
		
		# Row 3: Defensive stats
		info_text += "[color=#66DDFF]🛡 Endurance:[/color] %s  " % current_character.get_attribute_display_compact("endurance")
		info_text += "[color=#DD88FF]🌟 Arcane:[/color] %s\n" % current_character.get_attribute_display_compact("arcane")
		
		# Row 4: Utility stats
		info_text += "[color=#AAFF88]⚡ Agility:[/color] %s  " % current_character.get_attribute_display_compact("agility")
		info_text += "[color=#FFAA88]🏔 Fortitude:[/color] %s\n\n" % current_character.get_attribute_display_compact("fortitude")
		
		# === SECONDARY ATTRIBUTES ===
		info_text += "[center][b][color=#00DDFF]═══ SECONDARY ATTRIBUTES ═══[/color][/b][/center]\n\n"
		
		# Resource pools with color coding
		var hp_percent = float(current_character.current_hp) / float(current_character.max_hp)
		var hp_color = "#FF4444" if hp_percent < 0.3 else "#FFAA44" if hp_percent < 0.7 else "#66FF66"
		
		var mp_percent = float(current_character.current_mp) / float(current_character.max_mp)
		var mp_color = "#4444FF" if mp_percent < 0.3 else "#6666FF" if mp_percent < 0.7 else "#88AAFF"
		
		var sp_percent = float(current_character.current_sp) / float(current_character.max_sp)
		var sp_color = "#FFAA00" if sp_percent < 0.3 else "#FFCC44" if sp_percent < 0.7 else "#FFDD88"
		
		info_text += "[color=%s]❤ HP:[/color] %d / %d  " % [hp_color, current_character.current_hp, current_character.max_hp]
		info_text += "[color=%s]✦ MP:[/color] %d / %d  " % [mp_color, current_character.current_mp, current_character.max_mp]
		info_text += "[color=%s]⚡ SP:[/color] %d / %d\n\n" % [sp_color, current_character.current_sp, current_character.max_sp]
		
		# Offensive stats
		info_text += "[color=#FF6666]⚔ Attack Power:[/color] %d  " % current_character.get_attack_power()
		info_text += "[color=#8888FF]🔮 Spell Power:[/color] %d\n" % current_character.spell_power
		
		# Defensive stats
		info_text += "[color=#6666FF]🛡 Defense:[/color] %d  " % current_character.get_defense()
		info_text += "[color=#AAAA88]🏔 Toughness:[/color] %.2f\n" % current_character.toughness
		
		# Evasion stats
		info_text += "[color=#88FFAA]💨 Dodge:[/color] %.1f%%  " % (current_character.dodge * 100)
		info_text += "[color=#AA88FF]✨ Spell Ward:[/color] %.2f\n" % current_character.spell_ward
		
		# Accuracy stats
		info_text += "[color=#FFAA66]🎯 Accuracy:[/color] %.1f%%  " % (current_character.accuracy * 100)
		info_text += "[color=#FFDD44]💥 Crit Rate:[/color] %.1f%%\n\n" % (current_character.critical_hit_rate * 100)
		
		# === ELEMENTAL AFFINITIES ===
		info_text += "[center][b][color=#FF8844]═══ ELEMENTAL AFFINITIES ═══[/color][/b][/center]\n\n"
		
		# Show ALL elements with their values
		for element in ElementalDamage.Element.values():
			if element == ElementalDamage.Element.NONE:
				continue
			
			var element_name = ElementalDamage.get_element_name(element)
			var color = ElementalDamage.get_element_color(element)
			var resist = current_character.get_elemental_resistance(element)
			var weak = current_character.get_elemental_weakness(element)
			var bonus = current_character.get_elemental_damage_bonus(element)
			
			# Element icon mapping
			var icon = "○"
			match element:
				ElementalDamage.Element.FIRE: icon = "🔥"
				ElementalDamage.Element.ICE: icon = "❄"
				ElementalDamage.Element.LIGHTNING: icon = "⚡"
				ElementalDamage.Element.EARTH: icon = "🌍"
				ElementalDamage.Element.WIND: icon = "💨"
				ElementalDamage.Element.HOLY: icon = "✨"
				ElementalDamage.Element.DARK: icon = "🌑"
			
			# Build element line with icon
			var line = "[color=%s]%s %s:[/color]" % [color, icon, element_name]
			
			var stats = []
			if resist > 0.0:
				stats.append("[color=#66DDFF]-%d%% dmg taken[/color]" % int(resist * 100))
			if weak > 0.0:
				stats.append("[color=#FF8844]+%d%% dmg taken[/color]" % int(weak * 100))
			if bonus > 0.0:
				stats.append("[color=#88FF66]+%d%% dmg dealt[/color]" % int(bonus * 100))
			
			if stats.is_empty():
				line += " [color=#888888]Normal[/color]"
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
		var info_text = _generate_fallback_attributes()
		
		if elemental_info is RichTextLabel:
			elemental_info.bbcode_enabled = true
			elemental_info.text = info_text
		else:
			elemental_info.text = info_text
	
	# Enhanced Equipment display
	if equipment_info:
		var equipment_text = "[center][b][color=#00DDFF]═══ EQUIPMENT ═══[/color][/b][/center]\n\n"
		
		var slot_icons = {
			"main_hand": "⚔",
			"off_hand": "🛡",
			"head": "⛑",
			"chest": "🎽",
			"hands": "🧤",
			"legs": "👖",
			"feet": "👢"
		}
		
		for slot in current_character.equipment:
			var item = current_character.equipment[slot]
			var slot_name = slot.capitalize().replace("_", " ")
			var icon = slot_icons.get(slot, "○")
			
			if item:
				var color = item.get_rarity_color()
				var item_text = "%s [b]%s:[/b] [color=%s]%s[/color] [%s]" % [
					icon, slot_name, color, item.display_name, item.rarity.capitalize()
				]
				
				# Show key stats inline
				var stats = []
				if item.damage > 0:
					stats.append("[color=#FF6666]%d dmg[/color]" % item.damage)
				if item.armor_value > 0:
					stats.append("[color=#6666FF]%d armor[/color]" % item.armor_value)
				
				if stats.size() > 0:
					item_text += " (%s)" % ", ".join(stats)
				
				equipment_text += item_text + "\n"
			else:
				equipment_text += "%s [b]%s:[/b] [color=#666666]Empty[/color]\n" % [icon, slot_name]
		
		if equipment_info is RichTextLabel:
			equipment_info.bbcode_enabled = true
			equipment_info.text = equipment_text
		else:
			equipment_info.text = equipment_text
	
	# Enhanced Skills display
	if skills_info:
		var skills_text = "[center][b][color=#00DDFF]═══ SKILLS ═══[/color][/b][/center]\n\n"
		
		for skill_name in current_character.skills:
			var skill = current_character.get_skill_instance(skill_name)
			if skill:
				var level_str = skill.get_level_string()
				var progress_text = ""
				
				# Progress bar for skills not at max level
				if skill.level < 6:
					var next_threshold = skill.LEVEL_THRESHOLDS[skill.level - 1]
					var progress_percent = (float(skill.uses) / float(next_threshold)) * 100.0
					progress_text = " [color=#FFAA44](%d/%d uses - %.0f%%)[/color]" % [
						skill.uses, next_threshold, progress_percent
					]
				else:
					progress_text = " [color=#FFD700](MAX)[/color]"
				
				skills_text += "[b][color=#88DDFF]%s[/color][/b] - Level %s%s\n" % [
					skill.name, level_str, progress_text
				]
				skills_text += "  [color=#AAAAAA][i]%s[/i][/color]\n" % skill.description
				
				# Show skill stats in a compact format
				var stat_parts = []
				
				if skill.type in [Skill.SkillType.DAMAGE, Skill.SkillType.HEAL, Skill.SkillType.RESTORE]:
					stat_parts.append("[color=#FF8888]Power: %d[/color]" % skill.power)
				
				if skill.type in [Skill.SkillType.BUFF, Skill.SkillType.DEBUFF, Skill.SkillType.INFLICT_STATUS]:
					if skill.duration > 0:
						stat_parts.append("[color=#FFAA88]Duration: %d turns[/color]" % skill.duration)
				
				if skill.mp_cost > 0:
					stat_parts.append("[color=#8888FF]MP: %d[/color]" % skill.mp_cost)
				if skill.sp_cost > 0:
					stat_parts.append("[color=#FFAA44]SP: %d[/color]" % skill.sp_cost)
				if skill.cooldown > 0:
					stat_parts.append("[color=#AAAA88]CD: %d[/color]" % skill.cooldown)
				
				if stat_parts.size() > 0:
					skills_text += "  " + " | ".join(stat_parts) + "\n"
				
				skills_text += "\n"
		
		if skills_info is RichTextLabel:
			skills_info.bbcode_enabled = true
			skills_info.text = skills_text
		else:
			skills_info.text = skills_text
	
	# Enhanced Proficiencies display
	if prof_info and current_character.proficiency_manager:
		var prof_text = "[center][b][color=#00DDFF]═══ PROFICIENCIES ═══[/color][/b][/center]\n\n"
		
		var prof_mgr = current_character.proficiency_manager
		
		# Get available weapon types
		var available_weapons = prof_mgr.get_available_weapon_types()
		
		prof_text += "[b][color=#FFAA44]⚔ Weapons & Off-Hand:[/color][/b]\n"
		if available_weapons.is_empty():
			prof_text += "  [color=#888888]No weapons available[/color]\n"
		else:
			available_weapons.sort()
			for weapon_key in available_weapons:
				var prof_str = prof_mgr.get_weapon_proficiency_string(weapon_key)
				prof_text += "  " + prof_str + "\n"
		
		# Get available armor types
		var available_armors = prof_mgr.get_available_armor_types()
		
		prof_text += "\n[b][color=#6666FF]🛡 Armor:[/color][/b]\n"
		if available_armors.is_empty():
			prof_text += "  [color=#888888]No armor available[/color]\n"
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

func _generate_fallback_attributes() -> String:
	"""Generate attributes display for characters without elemental system"""
	var info_text = ""
	
	info_text += "[center][b][color=#00DDFF]═══ PRIMARY ATTRIBUTES ═══[/color][/b][/center]\n\n"
	info_text += "Vitality: %s | Strength: %s | Dexterity: %s\n" % [
		current_character.get_attribute_display_compact("vitality"),
		current_character.get_attribute_display_compact("strength"),
		current_character.get_attribute_display_compact("dexterity")
	]
	info_text += "Intelligence: %s | Faith: %s | Mind: %s\n" % [
		current_character.get_attribute_display_compact("intelligence"),
		current_character.get_attribute_display_compact("faith"),
		current_character.get_attribute_display_compact("mind")
	]
	info_text += "Endurance: %s | Arcane: %s\n" % [
		current_character.get_attribute_display_compact("endurance"),
		current_character.get_attribute_display_compact("arcane")
	]
	info_text += "Agility: %s | Fortitude: %s\n\n" % [
		current_character.get_attribute_display_compact("agility"),
		current_character.get_attribute_display_compact("fortitude")
	]
	
	info_text += "[center][b][color=#00DDFF]═══ SECONDARY ATTRIBUTES ═══[/color][/b][/center]\n\n"
	info_text += "HP: %d / %d | MP: %d / %d | SP: %d / %d\n" % [
		current_character.current_hp, current_character.max_hp,
		current_character.current_mp, current_character.max_mp,
		current_character.current_sp, current_character.max_sp
	]
	info_text += "Attack Power: %d | Spell Power: %d\n" % [
		current_character.get_attack_power(), current_character.spell_power
	]
	info_text += "Defense: %d | Toughness: %.2f\n" % [
		current_character.get_defense(), current_character.toughness
	]
	info_text += "Dodge: %.1f%% | Spell Ward: %.2f\n" % [
		current_character.dodge * 100, current_character.spell_ward
	]
	info_text += "Accuracy: %.1f%% | Crit Rate: %.1f%%\n\n" % [
		current_character.accuracy * 100, current_character.critical_hit_rate * 100
	]
	
	info_text += "[color=#888888][i]Elemental system not initialized for this character[/i][/color]"
	
	return info_text

func set_label_text(label, text: String):
	if label:
		if label is RichTextLabel:
			label.bbcode_enabled = true
		label.text = text
	else:
		print("Warning: Attempted to set text on a null label")

func _on_exit_pressed():
	SceneManager.change_to_town(current_character)
