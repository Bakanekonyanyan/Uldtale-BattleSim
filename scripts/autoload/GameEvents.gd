# res://scripts/autoload/GameEvents.gd
# Global event bus. Gameplay code emits; town systems (Guild bounties now,
# Adventurer quests later) listen. Emitters never need to know who listens.
extends Node

## An expedition began at a location/floor.
signal expedition_started(location_id: String, floor_num: int)
## The expedition ended: cleared = returned alive (breather/town), false = died.
signal expedition_ended(location_id: String, cleared: bool)
## An enemy was defeated in battle.
signal enemy_killed(enemy: CharacterData, location_id: String, floor_num: int, is_boss: bool)
## The player won a battle (one wave).
signal battle_won(location_id: String, floor_num: int, wave: int, is_boss: bool)
## The player beat a floor's boss.
signal floor_cleared(location_id: String, floor_num: int)
## Town crafting / upgrading (emitted by AlchemyManager / BlacksmithManager).
signal item_crafted(item_id: String, quantity: int)
signal item_upgraded(item: Equipment, new_level: int, success: bool)
signal item_enchanted(item: Equipment, rarity: String, success: bool)
signal challenge_completed(challenge_id: String)
## World clock (WorldClock.gd): one per day passed, then one per advance.
signal day_passed(player: CharacterData, day: int)
signal days_advanced(player: CharacterData, from_day: int, to_day: int)
