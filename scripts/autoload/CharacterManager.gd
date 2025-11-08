extends Node

var current_character: CharacterData = null
const SAVE_DIR = "user://characters/"
const SAVE_FILE_EXTENSION = ".tres"
const CURRENT_CHARACTER_SAVE = "user://current_character.tres"

var current_character_resource: Resource

func _ready():
	load_current_character()

func load_current_character():
	if ResourceLoader.exists(CURRENT_CHARACTER_SAVE):
		current_character_resource = ResourceLoader.load(CURRENT_CHARACTER_SAVE)
	else:
		current_character_resource = Resource.new()
	print("CharacterManager: Loaded current_character_resource with meta: ", current_character_resource.get_meta_list())

func save_current_character():
	var error = ResourceSaver.save(current_character_resource, CURRENT_CHARACTER_SAVE)
	if error != OK:
		print("CharacterManager: Error saving current character: ", error)
	else:
		print("CharacterManager: Saved current character successfully")

func set_current_character(character: CharacterData):
	current_character_resource.set_meta("current_character", character)
	print("CharacterManager: Current character set to ", character.name if character else "null")
	save_current_character()

func get_current_character() -> CharacterData:
	print("CharacterManager: get_current_character called")
	var character = current_character_resource.get_meta("current_character", null)
	if character == null:
		print("CharacterManager: Warning - current_character is null")
	else:
		print("CharacterManager: Returning current character: ", character.name)
	return character

func load_character(character_name: String) -> CharacterData:
	var file_name = SAVE_DIR + character_name + SAVE_FILE_EXTENSION
	if FileAccess.file_exists(file_name):
		var loaded_character = ResourceLoader.load(file_name)
		if loaded_character is CharacterData:
			print("Character loaded successfully.")
			return loaded_character
	print("Failed to load character.")
	return null

func save_character(character: CharacterData):
	var file_name = SAVE_DIR + character.name + SAVE_FILE_EXTENSION
	var error = ResourceSaver.save(character, file_name)
	if error != OK:
		print("An error occurred while saving the character.")
	else:
		print("Character saved successfully.")

func delete_character(character_name: String):
	var file_name = SAVE_DIR + character_name + SAVE_FILE_EXTENSION
	if FileAccess.file_exists(file_name):
		var dir = DirAccess.open(SAVE_DIR)
		if dir:
			dir.remove(file_name)
			print("Character deleted: ", character_name)
	else:
		print("Character file not found: ", character_name)

func get_all_characters() -> Array:
	var characters = []
	var dir = DirAccess.open(SAVE_DIR)
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if not dir.current_is_dir() and file_name.ends_with(SAVE_FILE_EXTENSION):
				var character = load_character(file_name.get_basename())
				if character:
					characters.append(character)
			file_name = dir.get_next()
	return characters
