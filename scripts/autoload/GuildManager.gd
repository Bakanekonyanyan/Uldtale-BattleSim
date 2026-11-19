# res://scripts/autoload/GuildManager.gd
# Guild bounty rules (no UI). Design: docs/design/TOWN_SERVICES.md section 6.
#
# - The board offers `board_size` bounties rolled from data/bounties.json and
#   refreshes whenever days pass (WorldClock), or for a fee.
# - Up to `max_active` accepted bounties. Each has a deadline in days.
# - Progress comes from GameEvents (kills, floor clears, wins); DELIVER bounties
#   are checked at turn-in. Completed bounties are turned in for rewards.
# - Missing a deadline: lose part of the bounty's Guild Points + 1 demerit.
#   Abandoning: same demerit, or pay a fee instead.
# - Adventurer rank (RankManager, data/ranks.json) sets board size, active slots,
#   bounty gold and which templates appear (template "min_rank"). Promotion
#   trials are active bounties with trial = true: no deadline, no slot, no penalty.
# - Each completed bounty works off demerits_cleared_per_bounty demerits.
# Per-character state lives in CharacterData.town_state["guild"].
extends Node

## A line for the battle log, e.g. "Bounty: Cull the Brutes 4/7"
signal progress_message(text: String)

var templates: Dictionary = {}
var settings: Dictionary = {}
var _streak: int = 0  # consecutive won waves this expedition without a Breather

func _ready():
	_load()
	GameEvents.enemy_killed.connect(_on_enemy_killed)
	GameEvents.floor_cleared.connect(_on_floor_cleared)
	GameEvents.battle_won.connect(_on_battle_won)
	GameEvents.expedition_started.connect(func(_loc, _floor): _streak = 0)
	GameEvents.day_passed.connect(_on_day_passed)
	GameEvents.days_advanced.connect(_on_days_advanced)
	MomentumSystem.momentum_changed.connect(_on_momentum_changed)

## A Breather resets momentum to 0, which ends the win streak.
func _on_momentum_changed(level: int) -> void:
	if level == 0:
		_streak = 0

func _load() -> void:
	var data = DataRegistry.get_data("bounties")
	if data is Dictionary:
		templates = data.get("templates", {})
		settings = data.get("settings", {})

# === STATE ===

func state(player: CharacterData) -> Dictionary:
	if not player.town_state.has("guild"):
		player.town_state["guild"] = {}
	var s: Dictionary = player.town_state["guild"]
	for key in ["active", "board", "completed_ids"]:
		if not s.has(key):
			s[key] = []
	for key in ["points", "demerits", "completed_count", "next_uid"]:
		if not s.has(key):
			s[key] = 0
	if not s.has("rank"):
		s["rank"] = "F"
	return s

## Days to finish an accepted bounty.
func deadline_days() -> int:
	return int(settings.get("deadline_days", 6))

## Board size and active-bounty slots come from the Adventurer rank.
func board_size(player: CharacterData) -> int:
	return int(RankManager.perk(player, "board_size", settings.get("board_size", 3)))

func max_active(player: CharacterData) -> int:
	return int(RankManager.perk(player, "max_active", settings.get("max_active", 3)))

## Active bounties that use a slot (promotion trials don't).
func active_count(player: CharacterData) -> int:
	return state(player).active.filter(func(b): return not b.get("trial", false)).size()

func get_points(player: CharacterData) -> int:
	return int(state(player).points)

func get_demerits(player: CharacterData) -> int:
	return int(state(player).demerits)

func get_board(player: CharacterData) -> Array:
	if state(player).board.is_empty():
		refresh_board(player)
	return state(player).board

func get_active(player: CharacterData) -> Array:
	return state(player).active

func is_complete(player: CharacterData, bounty: Dictionary) -> bool:
	if bounty.type == "DELIVER":
		return player.count_owned(bounty.item) >= int(bounty.count)
	return int(bounty.progress) >= int(bounty.count)

# === BOARD ===

func refresh_board(player: CharacterData) -> void:
	var board: Array = []
	var used := {}
	var tries := 0
	while board.size() < board_size(player) and tries < 50:
		tries += 1
		var tid = _pick_template(player, used)
		if tid == "":
			break
		var b = _instantiate(tid, player)
		if not b.is_empty():
			board.append(b)
			used[tid] = true
	state(player).board = board
	state(player)["board_day"] = WorldClock.day(player)

func get_reroll_fee(player: CharacterData) -> int:
	return int(settings.get("reroll_fee_per_floor", 50)) * max(1, player.max_floor_cleared)

func reroll_board(player: CharacterData) -> Dictionary:
	var fee = get_reroll_fee(player)
	if not player.currency.subtract(fee):
		return {"ok": false, "reason": "Rerolling the board costs %s." % Currency.format_copper(fee)}
	refresh_board(player)
	return {"ok": true, "reason": "New bounties posted (%s)." % Currency.format_copper(fee)}

func accept(player: CharacterData, uid: int) -> Dictionary:
	var s = state(player)
	if active_count(player) >= max_active(player):
		return {"ok": false, "reason": "You already have %d active bounties (your rank allows %d)." % [active_count(player), max_active(player)]}
	var b = _find(s.board, uid)
	if b.is_empty():
		return {"ok": false, "reason": "That bounty is no longer on the board."}
	s.board.erase(b)
	b.deadline = deadline_days()
	s.active.append(b)
	return {"ok": true, "reason": "Accepted: %s" % b.title}

# === TURN IN / ABANDON ===

func turn_in(player: CharacterData, uid: int) -> Dictionary:
	var s = state(player)
	var b = _find(s.active, uid)
	if b.is_empty():
		return {"ok": false, "reason": "No such active bounty."}
	if not is_complete(player, b):
		return {"ok": false, "reason": "\"%s\" isn't finished yet." % b.title}
	if b.type == "DELIVER":
		player.take_owned(b.item, int(b.count))

	var r: Dictionary = b.rewards
	var got: PackedStringArray = []
	if int(r.get("gold", 0)) > 0:
		player.currency.add(int(r.gold))
		got.append(Currency.format_copper(int(r.gold)))
	for id in r.get("materials", {}):
		player.add_to_pack(ItemManager.get_item(id), int(r.materials[id]))
		got.append("%d x %s" % [int(r.materials[id]), _item_name(id)])
	for id in r.get("chance", {}):
		if RandomManager.randf() < float(r.chance[id]):
			player.add_to_pack(ItemManager.get_item(id), 1)
			got.append("1 x %s (bonus!)" % _item_name(id))
	if String(r.get("recipe", "")) != "":
		AlchemyManager.learn_recipe(player, r.recipe)
		got.append("Recipe: %s" % AlchemyManager.get_output_name(r.recipe))
	s.active.erase(b)
	if b.get("trial", false):
		var promo = RankManager.promote(player, String(b.get("rank", "")))
		return {"ok": true, "reason": "Trial complete! Received " + ", ".join(got) + ". " + promo}
	s.points = int(s.points) + int(r.get("points", 0))
	got.append("%d Guild Points" % int(r.get("points", 0)))
	var worked_off = min(int(s.demerits), int(RankManager.cfg.get("settings", {}).get("demerits_cleared_per_bounty", 1)))
	if worked_off > 0:
		s.demerits = int(s.demerits) - worked_off
		got.append("%d demerit%s worked off" % [worked_off, "" if worked_off == 1 else "s"])

	s.completed_ids.append(b.template)
	s.completed_count = int(s.completed_count) + 1
	return {"ok": true, "reason": "Bounty complete! Received " + ", ".join(got) + "."}

func get_abandon_fee(bounty: Dictionary) -> int:
	return int(ceil(int(bounty.rewards.get("gold", 0)) * float(settings.get("abandon_fee_fraction", 0.25))))

func get_point_penalty(bounty: Dictionary) -> int:
	return int(ceil(int(bounty.rewards.get("points", 0)) * float(settings.get("fail_point_penalty", 0.5))))

## Abandon an active bounty: pay a fee (no demerit) or take the demerit.
func abandon(player: CharacterData, uid: int, pay_fee: bool) -> Dictionary:
	var s = state(player)
	var b = _find(s.active, uid)
	if b.is_empty():
		return {"ok": false, "reason": "No such active bounty."}
	if b.get("trial", false):
		s.active.erase(b)
		return {"ok": true, "reason": "You set the trial aside. You can take it again at any time."}
	if pay_fee:
		var fee = get_abandon_fee(b)
		if not player.currency.subtract(fee):
			return {"ok": false, "reason": "The penalty fee is %s." % Currency.format_copper(fee)}
		s.active.erase(b)
		return {"ok": true, "reason": "Abandoned \"%s\" and paid %s." % [b.title, Currency.format_copper(fee)]}
	s.active.erase(b)
	return {"ok": true, "reason": "Abandoned \"%s\": %s" % [b.title, _apply_demerit(s, b)]}

# === PROGRESS (GameEvents) ===

func _player() -> CharacterData:
	return DungeonStateManager.active_player

func _on_enemy_killed(enemy: CharacterData, location_id: String, floor_num: int, is_boss: bool) -> void:
	var player = _player()
	if player == null:
		return
	for b in state(player).active:
		if is_complete(player, b):
			continue
		var counts := false
		match b.type:
			"KILL":
				counts = _matches(b.target, enemy, location_id)
			"KILL_BOSS":
				counts = is_boss and _location_ok(b.target, location_id) and floor_num >= int(b.target.get("min_floor", 1))
		if counts:
			_advance(player, b, int(b.progress) + 1)

func _on_floor_cleared(location_id: String, floor_num: int) -> void:
	var player = _player()
	if player == null:
		return
	for b in state(player).active:
		if b.type == "CLEAR_FLOOR" and not is_complete(player, b) and _location_ok(b.target, location_id) and floor_num >= int(b.floor):
			_advance(player, b, int(b.count))

func _on_battle_won(_location_id: String, _floor_num: int, _wave: int, _is_boss: bool) -> void:
	_streak += 1
	var player = _player()
	if player == null:
		return
	for b in state(player).active:
		if b.type == "WIN_STREAK" and not is_complete(player, b) and _streak > int(b.progress):
			_advance(player, b, _streak)

## The board refreshes every board_refresh_days (or when empty). In between,
## NPC adventurers may take bounties off it (AdventurerManager).
func _on_days_advanced(player: CharacterData, _from: int, to_day: int) -> void:
	var s = state(player)
	if s.board.is_empty() or to_day - int(s.get("board_day", 0)) >= int(settings.get("board_refresh_days", 3)):
		refresh_board(player)

## Deadlines tick down per day (WorldClock).
func _on_day_passed(player: CharacterData, _day: int) -> void:
	if player == null:
		return
	var s = state(player)
	for b in s.active.duplicate():
		if is_complete(player, b) or b.get("trial", false):
			continue  # finished bounties wait for turn-in; trials have no deadline
		b.deadline = int(b.deadline) - 1
		if int(b.deadline) <= 0:
			s.active.erase(b)
			var msg = "Bounty failed: %s - %s" % [b.title, _apply_demerit(s, b)]
			progress_message.emit(msg)
			WorldClock.add_news(player, msg, "guild")

func _advance(player: CharacterData, b: Dictionary, value: int) -> void:
	b.progress = min(int(b.count), value)
	if is_complete(player, b):
		progress_message.emit("Bounty complete: %s - return to the Guild!" % b.title)
	else:
		progress_message.emit("Bounty: %s %d/%d" % [b.title, int(b.progress), int(b.count)])

func _apply_demerit(s: Dictionary, b: Dictionary) -> String:
	var lost = get_point_penalty(b)
	s.points = max(0, int(s.points) - lost)
	s.demerits = int(s.demerits) + 1
	return "-%d Guild Points and a demerit." % lost

## Kill filter: location, race and class fields (never display names).
## Bosses have class "King (Brute)" and count for their minion class.
func _matches(target: Dictionary, enemy: CharacterData, location_id: String) -> bool:
	if not _location_ok(target, location_id):
		return false
	if target.has("race") and enemy.race != target.race:
		return false
	if target.has("class"):
		var cls: String = enemy.character_class
		if cls != target["class"] and cls != "King (%s)" % target["class"]:
			return false
	return true

func _location_ok(target: Dictionary, location_id: String) -> bool:
	return not target.has("location") or target.location == "" or target.location == location_id

# === ROLLING BOUNTIES ===

func _pick_template(player: CharacterData, used: Dictionary) -> String:
	var pool: Array = []
	var total := 0
	for tid in templates:
		if used.has(tid) or max(1, player.max_floor_cleared) < int(templates[tid].get("min_floor", 1)):
			continue
		if RankManager.get_rank_index(player) < RankManager.rank_index(String(templates[tid].get("min_rank", "F"))):
			continue
		pool.append(tid)
		total += int(templates[tid].get("weight", 1))
	if pool.is_empty():
		return ""
	var roll = RandomManager.randi() % max(1, total)
	for tid in pool:
		roll -= int(templates[tid].get("weight", 1))
		if roll < 0:
			return tid
	return pool[0]

func _instantiate(tid: String, player: CharacterData) -> Dictionary:
	var t: Dictionary = templates[tid]
	var obj: Dictionary = t.objective
	var ref = max(1, player.max_floor_cleared)
	var ctx := {}

	# Target: resolve placeholders
	var target: Dictionary = obj.get("target", {}).duplicate(true)
	for key in target.keys():
		target[key] = _resolve(str(target[key]), ctx, player)

	var count = _roll_range(obj.get("count", 1))
	var floor_num := 0
	if obj.has("floor"):
		floor_num = player.get_max_floor(ctx.get("location", LocationManager.DEFAULT_LOCATION))
	var item := ""
	if obj.has("item"):
		item = _resolve(str(obj.item), ctx, player)

	# Rewards (concrete now; "chance" items roll at turn-in)
	var r: Dictionary = t.get("rewards", {})
	var rewards := {
		"gold": int(round((int(r.get("gold_flat", 0)) + int(r.get("gold_per_count", 0)) * count) * ref * RankManager.reward_mult(player))),
		"points": int(r.get("points", 0)),
		"materials": {},
		"chance": r.get("chance", {}).duplicate(),
		"recipe": ""
	}
	for key in r.get("materials", {}):
		var id = _resolve(str(key), ctx, player)
		if id != "":
			rewards.materials[id] = rewards.materials.get(id, 0) + _roll_range(r.materials[key])
	if r.has("recipe"):
		rewards.recipe = _resolve(str(r.recipe), ctx, player)
		if rewards.recipe == "":
			rewards.gold += 100 * ref  # every flask recipe already known

	var s = state(player)
	s.next_uid = int(s.next_uid) + 1
	var title: String = t.get("title", tid)
	title = title.format({
		"location_name": LocationManager.get_display_name(ctx.get("location", "")) if ctx.has("location") else "",
		"class": ctx.get("class", ""), "race": ctx.get("race", ""),
		"class_plural": plural(ctx.get("class", "")), "race_plural": plural(ctx.get("race", "")),
		"count": count, "floor": floor_num, "item_name": _item_name(item) if item != "" else ""
	})
	return {
		"uid": int(s.next_uid), "template": tid, "title": title, "type": obj.type,
		"target": target, "count": count, "progress": 0, "floor": floor_num, "item": item,
		"deadline": deadline_days(), "rewards": rewards
	}

func _resolve(value: String, ctx: Dictionary, player: CharacterData) -> String:
	match value:
		"{any_location}":
			var ids = LocationManager.get_ids()
			ctx.location = ids[RandomManager.randi() % ids.size()]
			return ctx.location
		"{themed_location}":
			var themed = LocationManager.get_ids().filter(func(id): return not LocationManager.is_mixed(id))
			ctx.location = themed[RandomManager.randi() % themed.size()]
			ctx.race = LocationManager.get_races(ctx.location, [])[0]
			return ctx.location
		"{race}":
			return ctx.get("race", "")
		"{any_class}":
			var classes: Array = settings.get("classes", ["Minion"])
			ctx["class"] = classes[RandomManager.randi() % classes.size()]
			return ctx["class"]
		"{any_material}":
			var mats = ItemManager.materials.keys().filter(func(id): return id not in ["mithril_ore", "adamant_ore", "monster_core"])
			return mats[RandomManager.randi() % mats.size()]
		"{location_material}":
			var tables: Dictionary = RewardsManager._get_material_tables().get("races", {})
			var races = LocationManager.get_races(ctx.get("location", LocationManager.DEFAULT_LOCATION), tables.keys())
			var common: Array = tables.get(races[RandomManager.randi() % races.size()], {}).get("common", [])
			return common[RandomManager.randi() % common.size()] if not common.is_empty() else "iron_ore"
		"{unknown_flask_recipe}":
			var unknown = AlchemyManager.get_recipe_ids().filter(func(id):
				return AlchemyManager.get_purchase_price(id) > 0 and not AlchemyManager.is_known(player, id))
			return unknown[RandomManager.randi() % unknown.size()] if not unknown.is_empty() else ""
	return value

func _roll_range(v) -> int:
	if v is Array and v.size() == 2:
		return RandomManager.randi_range(int(v[0]), int(v[1]))
	return int(v)

func _find(list: Array, uid: int) -> Dictionary:
	for b in list:
		if int(b.uid) == uid:
			return b
	return {}

func _item_name(id: String) -> String:
	var item = ItemManager.get_item(id)
	return item.display_name if item else id

## "Fairy" -> "Fairies", "Mage" -> "Mages"
static func plural(word: String) -> String:
	if word == "":
		return word
	if word.ends_with("y") and not word.ends_with("ey"):
		return word.left(-1) + "ies"
	return word + "s"

## Human-readable objective + progress (for the Guild screen).
func describe_objective(player: CharacterData, b: Dictionary) -> String:
	var where = LocationManager.get_display_name(b.target.get("location", "")) if b.target.get("location", "") != "" else "any location"
	match b.type:
		"KILL":
			var who = "enemies"
			if b.target.has("class"):
				who = plural(b.target["class"])
			elif b.target.has("race"):
				who = plural(b.target.race)
			return "Defeat %d %s in %s (%d/%d)" % [int(b.count), who, where, int(b.progress), int(b.count)]
		"KILL_BOSS":
			var depth = "floor %d or deeper" % int(b.target.min_floor) if int(b.target.get("min_floor", 1)) > 1 else "any floor"
			return "Defeat the boss of %s in %s (%d/%d)" % [depth, where, int(b.progress), int(b.count)]
		"DELIVER":
			return "Deliver %d %s (have %d)" % [int(b.count), _item_name(b.item), player.count_owned(b.item)]
		"CLEAR_FLOOR":
			return "Clear floor %d of %s (%s)" % [int(b.floor), LocationManager.get_display_name(b.target.get("location", "")), "done" if is_complete(player, b) else "not yet"]
		"WIN_STREAK":
			return "Best streak this bounty: %d/%d waves" % [int(b.progress), int(b.count)]
	return "Progress: %d/%d" % [int(b.progress), int(b.count)]

func describe_rewards(b: Dictionary) -> String:
	var r: Dictionary = b.rewards
	var parts: PackedStringArray = []
	if int(r.get("gold", 0)) > 0:
		parts.append(Currency.format_copper(int(r.gold)))
	for id in r.get("materials", {}):
		parts.append("%d x %s" % [int(r.materials[id]), _item_name(id)])
	if String(r.get("recipe", "")) != "":
		parts.append("Recipe: " + AlchemyManager.get_output_name(r.recipe))
	for id in r.get("chance", {}):
		parts.append("%d%% chance: %s" % [int(round(float(r.chance[id]) * 100)), _item_name(id)])
	if b.get("trial", false):
		parts.append("promotion to " + RankManager.display(String(b.get("rank", ""))))
	else:
		parts.append("%d GP" % int(r.get("points", 0)))
	return ", ".join(parts)
