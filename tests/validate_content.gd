# res://tests/validate_content.gd
# Loads every piece of game content through the real game code and reports
# anything that fails. Run by the content manager's "Validate in Godot" button:
#   godot --headless res://tests/validate_content.tscn     (exit code 0 = OK)
# Output lines the tool parses:
#   VALIDATE ERROR|<tab>|<entry>|<message>
#   VALIDATE RESULT: <errors> errors, <checks> checks
extends Node

var errors := 0
var checks := 0

func fail(tab: String, entry: String, msg: String) -> void:
	errors += 1
	print("VALIDATE ERROR|%s|%s|%s" % [tab, entry, msg])

func ok(cond: bool, tab: String, entry: String, msg: String) -> bool:
	checks += 1
	if not cond:
		fail(tab, entry, msg)
	return cond

func _ready():
	await get_tree().process_frame
	_items()
	_skills()
	_classes_and_races()
	_enemies()
	_recipes()
	_locations()
	_bounties()
	_damage_types()
	print("VALIDATE RESULT: %d errors, %d checks" % [errors, checks])
	get_tree().quit(1 if errors > 0 else 0)

func _read(path: String) -> Variant:
	var f = FileAccess.open(path, FileAccess.READ)
	if f == null:
		fail("", path, "file missing")
		return {}
	var data = JSON.parse_string(f.get_as_text())
	ok(data != null, "", path, "invalid JSON")
	return data if data != null else {}

func _items() -> void:
	for id in _read("res://data/items/consumables.json"):
		var it = ItemManager.get_item(id)
		ok(it != null, "Consumables", id, "ItemManager can't create this item")
	for id in _read("res://data/items/materials.json"):
		ok(ItemManager.get_item(id) != null, "Materials", id, "ItemManager can't create this item")
	for id in ItemManager.weapons:
		_equipment("Weapons", id)
	for id in ItemManager.armors:
		_equipment("Armors", id)

func _equipment(tab: String, id: String) -> void:
	var e = ItemManager.create_equipment_for_floor(id, 1)
	if not ok(e is Equipment, tab, id, "can't be created as equipment"):
		return
	ok(e.key == id, tab, id, "proficiency key is '%s', expected '%s'" % [e.key, id])
	ok(e.slot in ["main_hand", "off_hand", "head", "chest", "hands", "legs", "feet"], tab, id, "unknown slot '%s'" % e.slot)
	ok(e.get_full_description() != "", tab, id, "description failed")
	var probe = CharacterFactory.create_character("Probe", "Hume", "Paladin", true)
	probe.equipment[e.slot] = e
	probe.calculate_secondary_attributes()
	ok(probe.max_hp > 0, tab, id, "breaks stat calculation when equipped")

func _skills() -> void:
	var data = _read("res://data/skills.json").get("skills", {})
	for skill_name in data:
		var s = Skill.create_from_dict(data[skill_name])
		if not ok(s != null and s.name == skill_name, "Skills", skill_name, "Skill.create_from_dict failed (check enum values)"):
			continue
		ok(s.type in Skill.SkillType.values(), "Skills", skill_name, "bad type")

func _classes_and_races() -> void:
	var classes = _read("res://data/classes.json")
	var races = _read("res://data/races.json")
	for cls in classes.get("playable", {}):
		var c = CharacterFactory.create_character("T", "Hume", cls, true)
		if not ok(c != null and c.max_hp > 0, "Classes", cls, "can't create a level-1 hero"):
			continue
		for sk in classes.playable[cls].get("skills", []):
			ok(c.get_skill_instance(sk) != null, "Classes", cls, "skill '%s' didn't load" % sk)
		ok(c.attack_power > 0, "Classes", cls, "attack power is 0 (attack_power_type?)")
		ok(c.spell_power > 0, "Classes", cls, "spell power is 0 (spell_power_type?)")
	for race in races.get("playable", {}):
		var r = CharacterFactory.create_character("T", race, "Paladin", true)
		ok(r != null and r.max_hp > 0, "Races", race, "can't create a hero of this race")

func _enemies() -> void:
	var locs = _read("res://data/locations.json").get("locations", {})
	for loc in locs:
		EnemyFactory.set_location(loc)
		for boss in [false, true]:
			var g = EnemyGroup.new()
			g.initialize(1, 6 if boss else 1, boss)
			if not ok(g.enemies.size() > 0, "Locations", loc, "%s wave generated no enemies" % ("boss" if boss else "first")):
				continue
			for e in g.enemies:
				ok(e.max_hp > 0 and e.attack_power >= 0, "Locations", loc, "enemy %s has broken stats" % e.name)

func _recipes() -> void:
	for rid in AlchemyManager.get_recipe_ids():
		var r = AlchemyManager.get_recipe(rid)
		ok(ItemManager.get_item(String(r.get("output", ""))) != null, "Recipes", rid, "output '%s' isn't an item" % r.get("output", ""))
		for ing in r.get("ingredients", {}):
			ok(ItemManager.get_item(ing) != null, "Recipes", rid, "ingredient '%s' isn't an item" % ing)
		ok(AlchemyManager.get_unlock_text(rid) != null, "Recipes", rid, "unlock text failed")

func _locations() -> void:
	for id in LocationManager.get_ids():
		ok(LocationManager.get_display_name(id) != "", "Locations", id, "no display name")

func _bounties() -> void:
	var p = CharacterFactory.create_character("T", "Hume", "Paladin", true)
	p.max_floor_cleared = 10
	for i in 40:
		GuildManager.refresh_board(p)
		for b in GuildManager.get_board(p):
			var text = "%s %s %s" % [b.get("title", ""), GuildManager.describe_objective(p, b), GuildManager.describe_rewards(b)]
			if not ok(not ("{" in text), "Bounties", String(b.get("template", "")), "unfilled placeholder in: %s" % text):
				return
			for mat in b.get("rewards", {}).get("materials", {}):
				ok(ItemManager.get_item(mat) != null, "Bounties", String(b.get("template", "")), "reward material '%s' isn't an item" % mat)

func _damage_types() -> void:
	var cfg = DamageTypes.cfg()
	ok(not cfg.is_empty(), "Damage Types", "", "data/damage_types.json didn't load")
	for wid in cfg.get("weapons", {}):
		ok(DamageTypes.parse(String(cfg.weapons[wid])) >= 0, "Damage Types", wid, "unknown damage type '%s'" % cfg.weapons[wid])
