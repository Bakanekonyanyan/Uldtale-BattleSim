# SkillManager.gd
extends Node

var skills = {}

func _ready():
	load_skills()

func load_skills():
	var json = DataRegistry.get_data("skills")
	for skill_name in json.skills:
		skills[skill_name] = Skill.create_from_dict(json.skills[skill_name])

func get_skill(skill_name: String) -> Skill:
	return skills.get(skill_name)
