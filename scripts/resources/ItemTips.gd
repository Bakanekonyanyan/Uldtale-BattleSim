# res://scripts/resources/ItemTips.gd
# Short, readable descriptions of what a consumable does, for item menus
# (battle InventoryMenu, and anywhere else that lists items).
class_name ItemTips
extends RefCounted

const TARGETS := {
	Item.TargetType.SELF: "yourself",
	Item.TargetType.ALLY: "one ally",
	Item.TargetType.ENEMY: "one enemy",
	Item.TargetType.ALL_ALLIES: "your whole party",
	Item.TargetType.ALL_ENEMIES: "every enemy",
}

## One line: "Heals 20% HP - yourself"
static func effect_line(item: Item) -> String:
	if item == null or item.item_type != Item.ItemType.CONSUMABLE:
		return ""
	var amt = ("%d%%" % int(round(item.effect_percent * 100))) if item.is_percentage_based else str(item.effect_power)
	var what := ""
	match item.consumable_type:
		Item.ConsumableType.HEAL:
			what = "Heals %s HP" % amt
		Item.ConsumableType.RESTORE:
			var pool = {"MP": "MP", "SP": "SP"}.get(item.restore_resource, "MP and SP")
			what = "Restores %s %s" % [amt, pool]
		Item.ConsumableType.DAMAGE:
			what = "Deals %s%s damage" % [amt, " of max HP as" if item.is_percentage_based else ""]
		Item.ConsumableType.BUFF:
			what = "+%s %s" % [amt, item.buff_type.capitalize() if item.buff_type != "" else "stats"]
		Item.ConsumableType.DEBUFF:
			what = ("-%s %s" % [amt, item.buff_type.capitalize()]) if item.buff_type != "" else ""
		Item.ConsumableType.CURE:
			what = "Cures status effects" + ((" and heals %s HP" % amt) if item.effect_percent > 0 or item.effect_power > 0 else "")
	if item.status_effect != Skill.StatusEffect.NONE:
		var st = Skill.StatusEffect.keys()[item.status_effect].capitalize()
		var chance = "" if item.poison_chance >= 1.0 else " (%d%% chance)" % int(round(item.poison_chance * 100))
		what += ("Inflicts %s%s" if what == "" else ", inflicts %s%s") % [st, chance]
	if item.effect_duration > 0 and item.consumable_type in [Item.ConsumableType.BUFF, Item.ConsumableType.DEBUFF, Item.ConsumableType.DAMAGE]:
		what += " for %d turns" % item.effect_duration
	return "%s - %s" % [what, TARGETS.get(item.target_type, "")]

## BBCode block for a details panel.
static func describe(item: Item, quantity: int = -1) -> String:
	if item == null:
		return ""
	var t = "[b]%s[/b]%s\n" % [item.display_name, ("  x%d" % quantity) if quantity > 0 else ""]
	var line = effect_line(item)
	if line != "":
		t += "[color=#9fd8ff]%s[/color]\n" % line
	if item.description != "":
		t += "[color=#a99f90]%s[/color]" % item.description
	return t
