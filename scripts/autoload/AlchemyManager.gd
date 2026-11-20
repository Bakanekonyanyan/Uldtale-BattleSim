# res://scripts/autoload/AlchemyManager.gd
# Alchemist rules (no UI): which recipes a character knows, buying recipe books,
# and crafting. Ingredients come from the pack first, then the stash; output
# over the consumable carry limit goes to the stash (CharacterData.add_to_pack).
# Recipes live in data/recipes.json. Per-character state is saved in
# CharacterData.town_state["alchemy"] = {"known_recipes": [...], "crafts": n}.
extends Node

const CATEGORY_ORDER := ["Potions", "Cures", "Flasks", "Elixirs"]

var recipes: Dictionary = {}

func _ready():
	_load()

func _load() -> void:
	var data = DataRegistry.get_data("recipes")
	recipes = data.get("recipes", {}) if data is Dictionary else {}

# === QUERIES ===

func get_recipe(recipe_id: String) -> Dictionary:
	return recipes.get(recipe_id, {})

## Recipe ids grouped by category, then by output name.
func get_recipe_ids() -> Array:
	var ids = recipes.keys()
	ids.sort_custom(func(a, b):
		var ca = CATEGORY_ORDER.find(recipes[a].get("category", ""))
		var cb = CATEGORY_ORDER.find(recipes[b].get("category", ""))
		if ca != cb:
			return ca < cb
		return get_output_name(a) < get_output_name(b))
	return ids

func get_output_name(recipe_id: String) -> String:
	var item = ItemManager.get_item(get_recipe(recipe_id).get("output", ""))
	return item.display_name if item else recipe_id

func is_known(player: CharacterData, recipe_id: String) -> bool:
	var unlock: Dictionary = get_recipe(recipe_id).get("unlock", {"type": "default"})
	match unlock.get("type", "default"):
		"default":
			return true
		"floor_reached":
			return player.max_floor_cleared >= int(unlock.get("floor", 1)) or recipe_id in _state(player).known_recipes
		"adventurer_rank":
			return RankManager.get_rank_index(player) >= RankManager.rank_index(String(unlock.get("rank", "S"))) \
				or recipe_id in _state(player).known_recipes
		"standing":   # commissions (CommissionManager)
			return CommissionManager.tier(player, String(unlock.get("shop", "alchemist"))) >= int(unlock.get("tier", 0)) \
				or recipe_id in _state(player).known_recipes
		_:  # purchase, bounty_reward: learned explicitly
			return recipe_id in _state(player).known_recipes

## Learned by purchase/reward/rank (not just unlocked by a rule).
func is_known_explicitly(player: CharacterData, recipe_id: String) -> bool:
	return recipe_id in _state(player).known_recipes

## How to unlock a recipe the player doesn't know yet (for the UI).
func get_unlock_text(recipe_id: String) -> String:
	var unlock: Dictionary = get_recipe(recipe_id).get("unlock", {})
	match unlock.get("type", "default"):
		"purchase": return "Buy the recipe for %s" % Currency.format_copper(int(unlock.get("price", 0)))
		"floor_reached": return "Reach floor %d in any location" % int(unlock.get("floor", 1))
		"bounty_reward": return "Reward from a Guild bounty"
		"adventurer_rank": return "Requires Adventurer rank %s" % unlock.get("rank", "?")
		"standing":
			var t: Array = CommissionManager.cfg().get("standing_tiers", [])
			var i = int(unlock.get("tier", 0))
			return "Reach %s standing with the %s (commissions)" % [String(t[i].get("name", "?")) if i < t.size() else "?", String(unlock.get("shop", "alchemist")).capitalize()]
	return ""

func get_purchase_price(recipe_id: String) -> int:
	var unlock: Dictionary = get_recipe(recipe_id).get("unlock", {})
	return int(unlock.get("price", 0)) if unlock.get("type", "") == "purchase" else 0

## Pack + stash quantity of a material.
func count_available(player: CharacterData, item_id: String) -> int:
	return player.count_owned(item_id)

## How many times this recipe can be crafted right now (0 if unknown).
func max_craftable(player: CharacterData, recipe_id: String) -> int:
	var recipe = get_recipe(recipe_id)
	if recipe.is_empty() or not is_known(player, recipe_id):
		return 0
	var most := 1 << 30
	for mat in recipe.ingredients:
		most = min(most, count_available(player, mat) / int(recipe.ingredients[mat]))
	var fee = int(recipe.get("fee", 0))
	if fee > 0:
		most = min(most, player.currency.copper / fee)
	return max(0, most)

# === ACTIONS ===

func buy_recipe(player: CharacterData, recipe_id: String) -> Dictionary:
	var price = get_purchase_price(recipe_id)
	if price <= 0:
		return {"ok": false, "reason": "That recipe isn't for sale."}
	if is_known(player, recipe_id):
		return {"ok": false, "reason": "You already know that recipe."}
	if not player.currency.subtract(price):
		return {"ok": false, "reason": "Not enough money (%s)." % Currency.format_copper(price)}
	learn_recipe(player, recipe_id)
	return {"ok": true, "reason": "Learned %s." % get_output_name(recipe_id)}

## Grant a recipe (purchase, bounty reward, rank unlock...).
func learn_recipe(player: CharacterData, recipe_id: String) -> void:
	var state = _state(player)
	if recipe_id not in state.known_recipes:
		state.known_recipes.append(recipe_id)

## Craft `times` batches. Returns {"ok", "reason", "made", "to_pack", "to_stash"}.
func craft(player: CharacterData, recipe_id: String, times: int = 1) -> Dictionary:
	var recipe = get_recipe(recipe_id)
	if recipe.is_empty():
		return {"ok": false, "reason": "Unknown recipe."}
	if not is_known(player, recipe_id):
		return {"ok": false, "reason": "You haven't learned this recipe. " + get_unlock_text(recipe_id)}
	if times < 1:
		return {"ok": false, "reason": "Nothing to craft."}
	if max_craftable(player, recipe_id) < times:
		return {"ok": false, "reason": "Not enough materials or money."}

	for mat in recipe.ingredients:
		player.take_owned(mat, int(recipe.ingredients[mat]) * times)
	player.currency.subtract(int(recipe.get("fee", 0)) * times)

	var output: Item = ItemManager.get_item(recipe.output)
	var made = int(recipe.get("quantity", 1)) * times
	var placed = player.add_to_pack(output, made)
	_state(player).crafts += times
	GameEvents.item_crafted.emit(recipe.output, made)

	var reason = "Crafted %d x %s." % [made, output.display_name]
	if placed.stash > 0:
		reason += " %d sent to stash (carry limit %d)." % [placed.stash, player.carry_limit]
	return {"ok": true, "reason": reason, "made": made, "to_pack": placed.pack, "to_stash": placed.stash}

# === INTERNAL ===

func _state(player: CharacterData) -> Dictionary:
	if not player.town_state.has("alchemy"):
		player.town_state["alchemy"] = {"known_recipes": [], "crafts": 0}
	var state: Dictionary = player.town_state["alchemy"]
	if not state.has("known_recipes"):
		state["known_recipes"] = []
	if not state.has("crafts"):
		state["crafts"] = 0
	return state
