class_name Currency
extends Resource

@export var copper: int = 0

func add(amount: int):
	copper += amount

func subtract(amount: int) -> bool:
	if copper >= amount:
		copper -= amount
		return true
	return false

func get_formatted() -> String:
	var platinum = copper / 10000
	var gold = (copper % 10000) / 1000
	var silver = (copper % 1000) / 100
	var remaining_copper = copper % 100
	
	var result = []
	if platinum > 0:
		result.append("%d platinum" % platinum)
	if gold > 0:
		result.append("%d gold" % gold)
	if silver > 0:
		result.append("%d silver" % silver)
	if remaining_copper > 0 or result.is_empty():
		result.append("%d copper" % remaining_copper)
	
	return " ".join(result)
