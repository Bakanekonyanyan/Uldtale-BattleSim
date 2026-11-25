# res://scripts/autoload/RankManager.gd
# Adventurer ranks F -> S (data/ranks.json, GAME_ROADMAP.md section 3).
#
# Promotion to the next rank needs:
#   1. that rank's Guild Points (earned from bounties),
#   2. fewer than demerit_block demerits (each completed bounty works one off),
#   3. its promotion trial: a special Guild bounty with no deadline that sits in
#      the Active list (it doesn't use an active-bounty slot).
# Turning the trial in (Guild > Turn In, or the Rank tab) promotes you.
#
# Perks are read from the current rank: floor_cap, carry_limit, board_size,
# max_active, reward_mult (bounty gold), party_size (recruit slots, for B2) and
# recipes with unlock {type: adventurer_rank}.
# State: player.town_state["guild"]["rank"] (saved with the Guild block).
extends Node

## Emitted on promotion (for town messages; NPC rivals will listen later).
signal rank_changed(player: CharacterData, rank: String)

var cfg: Dictionary = {}
var _order: Array = []        # rank ids, lowest first

func _ready():
	var d = DataRegistry.get_data("ranks")
	cfg = d if d is Dictionary else {}
	if cfg.is_empty():
		push_error("RankManager: data/ranks.json missing or invalid")
		cfg = {"settings": {}, "ranks": {"F": {"order": 0, "title": "Fledgling", "points": 0}}}
	var ranks: Dictionary = cfg.get("ranks", {})
	_order = ranks.keys()
	_order.sort_custom(func(a, b): return int(ranks[a].get("order", 0)) < int(ranks[b].get("order", 0)))

# ------------------------------------------------------------------ queries

func rank_ids() -> Array:
	return _order

func info(rank_id: String) -> Dictionary:
	return cfg.get("ranks", {}).get(rank_id, {})

func get_rank(player: CharacterData) -> String:
	var r = String(GuildManager.state(player).get("rank", ""))
	return r if r in _order else String(_order[0])

func rank_index(rank_id: String) -> int:
	return max(0, _order.find(rank_id))

func get_rank_index(player: CharacterData) -> int:
	return rank_index(get_rank(player))

## "C-Rank Vanguard"
func display(rank_id: String) -> String:
	return "%s-Rank %s" % [rank_id, info(rank_id).get("title", "")]

## The rank above the player's, or "" at the top.
func next_rank(player: CharacterData) -> String:
	var i = get_rank_index(player) + 1
	return String(_order[i]) if i < _order.size() else ""

## A perk value from the player's current rank.
func perk(player: CharacterData, key: String, default_value = 0):
	return info(get_rank(player)).get(key, default_value)

## Highest floor the player can unlock at any location (0 = no cap).
func floor_cap(player: CharacterData) -> int:
	return int(perk(player, "floor_cap", 0))

## True if the rank cap stops the player from unlocking `floor_num`.
func is_floor_capped(player: CharacterData, floor_num: int) -> bool:
	var cap = floor_cap(player)
	return cap > 0 and floor_num > cap

## Highest floor the player may start from at a location: unlocked progress,
## limited by the rank cap (progress past the cap is kept for after promotion).
func start_floor_limit(player: CharacterData, location_id: String) -> int:
	var cap = floor_cap(player)
	var unlocked = player.get_max_floor(location_id)
	return min(unlocked, cap) if cap > 0 else unlocked

func reward_mult(player: CharacterData) -> float:
	return float(perk(player, "reward_mult", 1.0))

func demerit_block() -> int:
	return int(cfg.get("settings", {}).get("demerit_block", 3))

## Promotion progress for the UI:
## {rank, next, points, points_needed, demerits, blocked_by_demerits,
##  trial (data), trial_state: "top" | "need_points" | "demerits" | "available" | "active" | "ready"}
func promotion_status(player: CharacterData) -> Dictionary:
	var nxt = next_rank(player)
	var s := {"rank": get_rank(player), "next": nxt, "points": GuildManager.get_points(player),
		"points_needed": int(info(nxt).get("points", 0)) if nxt != "" else 0,
		"demerits": GuildManager.get_demerits(player), "trial": info(nxt).get("trial", {}) if nxt != "" else {}}
	s.blocked_by_demerits = int(s.demerits) >= demerit_block()
	var t = get_trial(player)
	if nxt == "":
		s.trial_state = "top"
	elif not t.is_empty():
		s.trial_state = "ready" if GuildManager.is_complete(player, t) else "active"
	elif s.blocked_by_demerits:
		s.trial_state = "demerits"
	elif int(s.points) < int(s.points_needed):
		s.trial_state = "need_points"
	else:
		s.trial_state = "available"
	return s

## The player's active promotion trial (a Guild bounty with trial = true), or {}.
func get_trial(player: CharacterData) -> Dictionary:
	for b in GuildManager.get_active(player):
		if b.get("trial", false):
			return b
	return {}

# ------------------------------------------------------------------ actions

## Take the next rank's promotion trial. Returns {ok, reason}.
func start_trial(player: CharacterData) -> Dictionary:
	var st = promotion_status(player)
	match st.trial_state:
		"top":
			return {"ok": false, "reason": "You are already %s." % display(st.rank)}
		"active", "ready":
			return {"ok": false, "reason": "You are already taking your promotion trial."}
		"demerits":
			return {"ok": false, "reason": "The Guild won't promote you with %d demerits. Complete bounties to work them off." % int(st.demerits)}
		"need_points":
			return {"ok": false, "reason": "You need %d Guild Points for %s (you have %d)." % [int(st.points_needed), display(st.next), int(st.points)]}
	var t: Dictionary = st.trial
	var target := {}
	if String(t.get("location", "")) != "":
		target["location"] = String(t.location)
	if t.has("min_floor"):
		target["min_floor"] = int(t.min_floor)
	var gs = GuildManager.state(player)
	gs.next_uid = int(gs.next_uid) + 1
	var b := {
		"uid": int(gs.next_uid), "template": "trial_" + String(st.next), "trial": true, "rank": String(st.next),
		"title": "%s (promotion to %s)" % [t.get("title", "Promotion trial"), st.next],
		"type": String(t.get("type", "KILL_BOSS")), "target": target, "count": int(t.get("count", 1)),
		"progress": 0, "floor": int(t.get("floor", 0)), "item": "", "deadline": 0,
		"description": String(t.get("description", "")),
		"rewards": {"gold": int(t.get("gold", 0)), "points": 0, "materials": {}, "chance": {}, "recipe": ""}
	}
	gs.active.append(b)
	return {"ok": true, "reason": "Trial accepted: %s" % t.get("description", b.title)}

## Called by GuildManager.turn_in for a finished trial. Returns the perk summary.
func promote(player: CharacterData, rank_id: String) -> String:
	if rank_index(rank_id) <= get_rank_index(player):
		return ""
	GuildManager.state(player)["rank"] = rank_id
	var lines = apply_perks(player)
	WorldClock.add_news(player, "%s was promoted to %s." % [player.name, display(rank_id)], "rank")
	ArmorTraining.grant_point(player)   # a promotion brings armour training
	rank_changed.emit(player, rank_id)
	return "Promoted to %s! %s" % [display(rank_id), " ".join(lines)]

## Apply the current rank's perks that live on the character (carry limit,
## recipes). Safe to call on load. Returns short lines describing what changed.
func apply_perks(player: CharacterData) -> Array:
	var lines: Array = []
	var carry = int(perk(player, "carry_limit", player.carry_limit))
	if carry > player.carry_limit:
		player.carry_limit = min(carry, CharacterData.CARRY_LIMIT_MAX)
		lines.append("Carry limit %d." % player.carry_limit)
	for id in AlchemyManager.get_recipe_ids():
		var unlock: Dictionary = AlchemyManager.get_recipe(id).get("unlock", {})
		if unlock.get("type", "") == "adventurer_rank" and rank_index(String(unlock.get("rank", "S"))) <= get_rank_index(player) \
				and not AlchemyManager.is_known_explicitly(player, id):
			AlchemyManager.learn_recipe(player, id)
			lines.append("New recipe: %s." % AlchemyManager.get_output_name(id))
	return lines

## Short perk list for a rank (UI).
func describe_perks(rank_id: String) -> Array:
	var r = info(rank_id)
	var out: Array = []
	out.append("Floors: %s" % ("no limit" if int(r.get("floor_cap", 0)) <= 0 else "up to %d" % int(r.floor_cap)))
	out.append("Carry limit: %d of each consumable" % int(r.get("carry_limit", 5)))
	out.append("Bounty board: %d posted, %d active" % [int(r.get("board_size", 3)), int(r.get("max_active", 3))])
	out.append("Bounty gold: x%.2f" % float(r.get("reward_mult", 1.0)))
	out.append("Party: %d adventurer%s (recruiting comes later)" % [int(r.get("party_size", 1)), "" if int(r.get("party_size", 1)) == 1 else "s"])
	var recipes: Array = []
	for id in AlchemyManager.get_recipe_ids():
		var unlock: Dictionary = AlchemyManager.get_recipe(id).get("unlock", {})
		if unlock.get("type", "") == "adventurer_rank" and String(unlock.get("rank", "")) == rank_id:
			recipes.append(AlchemyManager.get_output_name(id))
	if not recipes.is_empty():
		out.append("Recipes: " + ", ".join(recipes))
	return out
