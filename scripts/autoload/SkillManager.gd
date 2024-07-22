# SkillManager.gd
extends Node

var skills = {}

func _ready():
	load_skills()

func load_skills():
	var file = FileAccess.open("res://data/skills.json", FileAccess.READ)
	var json = JSON.parse_string(file.get_as_text())
	for skill_name in json.skills:
		skills[skill_name] = Skill.create_from_dict(json.skills[skill_name])

func get_skill(skill_name: String) -> Skill:
	return skills.get(skill_name)
