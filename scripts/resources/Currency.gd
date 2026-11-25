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
	return format_copper(copper)

## Short form for tight buttons: 1250 -> "1g 2s 50c".
static func format_short(amount: int) -> String:
	var parts: Array = []
	for u in [[10000, "p"], [1000, "g"], [100, "s"]]:
		if amount >= int(u[0]):
			parts.append("%d%s" % [amount / int(u[0]), u[1]])
			amount = amount % int(u[0])
	if amount > 0 or parts.is_empty():
		parts.append("%dc" % amount)
	return " ".join(parts)

## Format any copper amount, e.g. 1250 -> "1 gold 2 silver 50 copper".
static func format_copper(amount: int) -> String:
	var platinum = amount / 10000
	var gold = (amount % 10000) / 1000
	var silver = (amount % 1000) / 100
	var remaining_copper = amount % 100
	
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
