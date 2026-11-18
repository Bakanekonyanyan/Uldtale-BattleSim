# Town Services: Alchemist, Blacksmith and Guild Bounties

**Status:** Draft v1. Decisions are needed on the open questions in §7.
**Scope:** three new town buildings that turn dungeon loot into character progress.
**Out of scope (parked):** the Adventurer system (§8).

---

## 1. Goals

Today a dungeon run produces gold, XP and gear. Materials drop but do nothing except
sell. The town only offers a shop, equipment, stash and the arena. These three
services close the loop:

```
        ┌──────────── Dungeon (waves + boss) ────────────┐
        │  gold · XP · gear · MATERIALS · kills          │
        ▼                                                │
  Town ─┬─ Alchemist  : materials → potions, flasks, cures ──► survive deeper
        ├─ Blacksmith : materials + gold → upgraded gear  ───► hit harder, take less
        └─ Guild      : kills/clears → gold, rare mats, recipes ─┘ (feeds the other two)
```

Design principles:

1. **Every source needs a sink.** Materials and gold get meaningful uses, and every
   new reward has somewhere to go.
2. **Data-driven.** Recipes, upgrade costs and bounties live in `data/*.json` and get
   tabs in `DevTools/content_manager.py`, like the existing content.
3. **Reuse existing mechanics.** Crafted items are existing `Item` consumables.
   Upgrades reuse `EquipmentScaler`. Bounties reuse enemy `race` and `character_class`.
   No new battle mechanics are needed.
4. **Tune with the simulator.** Anything that adds player power (potions, upgrades)
   gets checked with `tests/balance_sim.tscn` before playtesting.
5. **One save migration.** All new persistent data ships under a single save version bump.

## 2. What exists today

| System | Current state | Relevance |
|---|---|---|
| Materials (`data/items/materials.json`) | 10 materials. Eight say "Used to craft X" in their description (Bogblossom → Antidote Herb, Frostroot → Coolroot Gel, …). Iron Ore and Wood are generic. | Alchemist inputs are already designed; Iron Ore and Wood suit the Blacksmith |
| Consumables (`consumables.json`) | 20 items. The shop sells 12. **The 8 cure items are not sold anywhere.** | Cures are effectively craft-only already |
| Material drops (`RewardsManager`) | 30% × (1 + 0.1·floor) per regular wave, 100% for the boss. About 1.3 materials per floor-1 run, picked uniformly at random. | Far too few to craft with; must change (§3.1) |
| Gold | `(50 + 10·wave) × floor` per wave, boss ×2. About 620 copper for a floor-1 clear; 500 to start. Shop potions cost 25–30. | Sets the scale for crafting and upgrade prices |
| Equipment scaling (`EquipmentScaler`) | damage/armor = base × rarity mult (1–5) × (1 + 0.05·(ilvl−1)) | An upgrade can be "more item level"-style scaling |
| Dungeon race (`EnemyFactory.set_dungeon_race`) | Random per floor, not shown to the player | Problem for race-specific bounties (§6.4) |
| Kill tracking | None. Since the battle refactor, every death goes through `BattleOutcomeHandler.handle_deaths()`. | One clean hook for bounty progress |
| Town (`TownScene`, `SceneManager.ScenePath`) | Button per service plus a `ScenePath` entry | New buildings follow the same pattern |

## 3. Shared foundations (build first)

### 3.1 Material economy
- **More drops.** Each regular wave drops 1–2 materials and the boss 3, plus floor scaling.
  Target: about **8–10 materials per floor-1 run**.
- **Themed drop tables per dungeon race**, so where you farm matters:

  | Dungeon race | Common drops | Uncommon drops |
  |---|---|---|
  | Goblin | bogblossom_petal, rousepepper_seeds | iron_ore |
  | Orc | iron_ore, bloodvine_fiber | wood |
  | Troll | frostroot_chunk, wood | voltslate_pebble |
  | Fairy | glowcap_mushroom, mindglass_shard | embershard_fragment |

  Stored in `data/loot/material_tables.json`, keyed by race with floor-bracket overrides.
- **New tiered materials** (for upgrades and higher-tier potions):
  - `mithril_ore` (floors 6+) and `adamant_ore` (floors 12+), as a progression gate.
  - `monster_core`: boss-only, used for high-end upgrades and bounty rewards.
- **Crafting reads inventory and stash together**, since both are in town. Ingredients
  come out of the inventory first.

### 3.2 `GameEvents` autoload (event bus)
A small signal hub that gameplay emits to and town systems listen to:

```gdscript
signal enemy_killed(enemy: CharacterData, floor_num: int, wave: int, is_boss: bool)
signal battle_won(floor_num: int, wave: int, is_boss: bool)
signal floor_cleared(floor_num: int)
signal item_crafted(item_id: String, quantity: int)
signal item_upgraded(item: Equipment, new_level: int)
```

These are emitted from `BattleOutcomeHandler` (kills and victory) and
`DungeonStateManager` (floor clear). The Guild listens now, and the Adventurer
system's quests can listen later (§8) without touching battle code again.

### 3.3 Save format v2
- Add `"save_version": 2` and a migration from v1, which has no version key.
- New top-level `"town"` block:
  ```json
  "town": {
    "alchemy":    { "known_recipes": ["antidote_herb", "..."], "crafts": 0 },
    "blacksmith": { },
    "guild":      { "points": 0, "active": [ ... ], "completed_ids": [ ... ], "board": [ ... ], "board_refresh_runs": 0 }
  }
  ```
- Equipment gains `base_damage`, `base_armor` and `upgrade_level` (§5.2). A v1 item
  migrates as base = current value, upgrade 0.

### 3.4 Town building pattern
Each building gets the same three pieces:

- a scene: `scenes/town/AlchemistScene`, `BlacksmithScene`, `GuildScene`
- a manager autoload holding the logic, with no UI
- a data file

Each also gets a `ScenePath` entry and a TownScene button. The managers contain all
the rules, so they can be unit-tested headlessly like the battle code.

## 4. Alchemist

**Role:** turns materials into consumables. It's the only source of cure items and of
higher-tier potions, and it makes basic potions cheaper than the shop.

### 4.1 Rules
- **Craft:** select a recipe and a quantity (1, 5 or max). It consumes ingredients plus
  a small copper fee and adds the output to the inventory.
- **Value proposition, so crafting isn't just a worse shop:**
  1. Cures are craft-only (they already aren't sold).
  2. Shop-sold items cost about **50–70%** of the shop price to craft.
  3. Higher tiers (Greater Health Potion, Ether) can only be crafted.
- **Recipe unlocks.** All 8 cures and the basic potions are known from the start. The
  status flasks are bought at the Alchemist as recipe books. Higher tiers come from
  bounty rewards or reaching a floor.

### 4.2 Data: `data/recipes.json`
```json
"antidote_herb": {
  "output": "antidote_herb",
  "quantity": 2,
  "ingredients": { "bogblossom_petal": 2 },
  "fee": 10,
  "unlock": { "type": "default" }
},
"flame_flask": {
  "output": "flame_flask",
  "quantity": 1,
  "ingredients": { "embershard_fragment": 2, "wood": 1 },
  "fee": 15,
  "unlock": { "type": "purchase", "price": 300 }
},
"greater_health_potion": {
  "output": "greater_health_potion",
  "quantity": 1,
  "ingredients": { "glowcap_mushroom": 2, "bloodvine_fiber": 2, "monster_core": 1 },
  "fee": 60,
  "unlock": { "type": "floor_reached", "floor": 5 }
}
```
Unlock types: `default`, `purchase`, `floor_reached`, `bounty_reward`.

### 4.3 Starter recipe table (first pass, to be tuned)

| Output | Ingredients | Fee | Shop price | Unlock |
|---|---|---|---|---|
| 2× each cure (8 recipes) | 2× its matching material | 10 | not sold | default |
| Health Potion | glowcap ×1, bloodvine ×1 | 5 | 25 | default |
| Mana Potion | mindglass ×1, glowcap ×1 | 8 | 30 | default |
| Stamina Potion | rousepepper ×1, bloodvine ×1 | 8 | 30 | default |
| Flame Flask | embershard ×2, wood ×1 | 15 | 50 | purchase 300 |
| Frost Crystal | frostroot ×2, mindglass ×1 | 15 | 50 | purchase 300 |
| Thunder Orb | voltslate ×2, iron_ore ×1 | 15 | 50 | purchase 300 |
| Venom Vial | bogblossom ×2, wood ×1 | 15 | 50 | purchase 300 |
| Greater Health Potion *(new)* | glowcap ×2, bloodvine ×2, monster_core ×1 | 60 | – | floor 5 |
| Ether *(new: restores MP and SP)* | mindglass ×2, rousepepper ×2, monster_core ×1 | 60 | – | floor 5 |

### 4.4 Battle impact
- Potions are the intended fix for the weak classes (Elementalist, Druid), which run
  out of HP and MP over a Press-On streak.
- Risk: unlimited cheap potions can make floors trivial. **Mitigation:** a carry limit
  on consumables taken into the dungeon (see open question Q3).
- **The simulator needs an item-using policy** (drink a potion below X% HP) before
  potion numbers are final. It currently never uses items.

### 4.5 UI
`AlchemistScene` has three areas:

- a recipe list, filtered to Craftable, Known, or All with locked recipes greyed out
- a detail panel showing each ingredient's have/need count (inventory + stash), the
  fee, and the output description
- a quantity selector and a Craft button, with a "Buy recipe" button for purchasable
  recipes

## 5. Blacksmith

**Role:** makes gear you like stronger, and turns gear you don't want into materials.
This matters now that armor and weapon damage count in combat.

### 5.1 Services
| Service | What it does | v1? |
|---|---|---|
| **Upgrade** | +1 upgrade level: more damage/armor, renamed "+N Item" | ✅ |
| **Salvage** | Destroy an item for ores (and a chance of `monster_core` for rare+) | ✅ |
| Reforge | Reroll `stat_modifiers` for gold + a core | later |

### 5.2 Upgrade math
Equipment currently overwrites `damage` and `armor_value` when it scales them, so the
original values are lost. Fix that by **storing the post-generation values as
`base_damage` and `base_armor`**, then deriving:

```
damage = round(base_damage × (1 + UPGRADE_STEP × upgrade_level))
armor  = round(base_armor  × (1 + UPGRADE_STEP × upgrade_level))
UPGRADE_STEP = 0.08            # +8% per level, not compounding
```

Max upgrade level depends on rarity, so rare gear stays worth chasing:

| Rarity | common | uncommon | magic | rare | epic | legendary |
|---|---|---|---|---|---|---|
| Max level | +3 | +4 | +5 | +6 | +8 | +10 |
| Max bonus | +24% | +32% | +40% | +48% | +64% | +80% |

A fully upgraded common item stays below an un-upgraded uncommon (rarity mult 2.0).
**Upgrades smooth out bad luck with drops; they don't replace finding better gear.**

### 5.3 Upgrade cost (to level L)
```
gold      = item.value × 0.25 × L
materials = ore × L          (iron_ore for L ≤ 3, mithril_ore for L 4–6, adamant_ore for L 7+)
          + wood × 1         (weapons only)
          + monster_core × 1 (L ≥ 6)
```
Example: a Short Sword (value 100) from +0 to +3 costs 25 + 50 + 75 = **150 copper and
6 Iron Ore**. That's about a quarter of a floor-1 run's gold, and a run's worth of ore.

- **No failure chance** (recommended; see Q2). Deterministic upgrades are friendlier
  and easier to balance.
- Enemies never get upgraded gear, so upgrades are a real edge for the player.

### 5.4 Salvage yields
| Rarity | Yield |
|---|---|
| common | 1–2 ore |
| uncommon | 2–3 ore |
| magic / rare | 3–4 ore + 25% monster_core |
| epic / legendary | 4–6 higher-tier ore + 1 monster_core |

The ore tier follows the item's level (iron below ilvl 6, mithril 6–11, adamant 12+).
Salvaging requires a confirmation, and equipped items can't be salvaged.

### 5.5 UI
`BlacksmithScene` has two tabs, Upgrade and Salvage. Both list equipped, inventory and
stash gear. Upgrade shows a before/after preview of damage or armor, the cost, and
an Upgrade button.

## 6. Guild Bounties

**Role:** gives dungeon runs short-term goals and pays out rewards the other two
buildings need, such as rare materials and recipes.

### 6.1 Rules
- The **board** shows 3 bounties, and the player can have up to **3 active** at once.
- The board **refreshes after each completed dungeon run** (cleared or died), or for a
  small copper fee.
- Progress counts as it happens and is saved with the character. If you die before
  the next save, you lose that unsaved progress, the same as XP today.
- Completed bounties are **turned in at the Guild** to claim the reward, so the moment
  is visible.
- Every bounty also grants **Guild Points (GP)**. In v1 these are just a number on the
  character. They're the hook for the Adventurer rank later (§8).

### 6.2 Objective types (generic on purpose, for reuse by future quests)
| Type | Example | Progress source |
|---|---|---|
| `KILL` | Defeat 10 Orc Brutes | `enemy_killed` + target filter |
| `KILL_BOSS` | Defeat a floor-3+ boss | `enemy_killed` with `is_boss` |
| `CLEAR_FLOOR` | Clear floor 4 | `floor_cleared` |
| `WIN_STREAK` | Win 5 waves in a row with Press On | `battle_won` + momentum |
| `DELIVER` | Bring 6 Frostroot Chunks | turned in at the Guild, consumes items |

Target filter fields: `race`, `class` (boss classes are `"King (Brute)"`, so match on
the minion class), `is_boss`, `min_floor`. **Filters match the `race` and
`character_class` fields, never display names** (display names look like "Orc Brute 2").

### 6.3 Data: `data/bounties.json` (templates the board rolls from)
```json
"cull_brutes": {
  "title": "Cull the Brutes",
  "objective": { "type": "KILL", "target": { "class": "Brute" }, "count": [6, 12] },
  "min_floor": 1,
  "weight": 10,
  "rewards": {
    "gold_per_count": 20,
    "materials": { "iron_ore": [2, 4] },
    "points": 10,
    "chance": { "monster_core": 0.25 }
  }
},
"recipe_frost": {
  "title": "The Frozen Depths",
  "objective": { "type": "CLEAR_FLOOR", "floor": "player_max+1" },
  "min_floor": 3,
  "weight": 3,
  "rewards": { "recipe": "frost_crystal", "points": 25 }
}
```
Counts and rewards scale with the player's highest cleared floor when the bounty is
rolled. Rewards should add up to about 30–50% of a run's gold, plus the items.

### 6.4 The random-race problem
Each floor's enemy race is rolled at random and hidden, so "kill 10 Trolls" can be
impossible to plan for. Options:

| Option | Pros | Cons |
|---|---|---|
| **A. Fix each floor's race per character and show it on the floor-select screen** *(recommended)* | Bounties become plannable; you choose where to farm; matches the themed drop tables | Changes dungeon generation; less surprise |
| B. While a race bounty is active, weight that race higher (e.g. 50%) | Small change | Still luck-based; players can't see it |
| C. Only offer class-based bounties (every class appears on every floor) | No dungeon change | Bounties have less flavor; race tables matter less |

### 6.5 UI
`GuildScene` has three tabs:

- **Board:** available bounties, each with an Accept button
- **Active:** progress bars and an Abandon button
- **Turn In:** completed bounties and their rewards

In battle, the combat log shows progress lines such as "Bounty: Orc Brutes 4/10" when
a kill counts.

## 7. Open questions (need your call)

| # | Question | Recommendation |
|---|---|---|
| Q1 | Fix and show each floor's enemy race (§6.4)? | **Yes (option A)** |
| Q2 | Can a Blacksmith upgrade fail? | **No**, deterministic |
| Q3 | Limit consumables carried into a dungeon? | **Yes**, e.g. 5 per item type, or a 10-slot "belt" |
| Q4 | Can crafting and upgrading use stash materials directly? | **Yes** |
| Q5 | Are the status flask recipes bought or known from the start? | **Bought** (gold sink, early goal) |
| Q6 | How often does the bounty board refresh? | **After each run**, plus a paid reroll |
| Q7 | Are Guild Points visible in v1, or hidden until the Adventurer system? | **Visible** as a number, with no ranks yet |

## 8. Future: Adventurer system (parked)

Your idea, recorded so it isn't lost:

- **Exploration dungeons** that are explored rather than played as wave gauntlets.
- **An Adventurer rank** that unlocks new quest types.
- **A robust NPC system** with quest givers and named characters.
- **Alignment and relationship systems** that affect quests and NPC reactions.

This is a much larger project. It needs NPC data and dialogue, an alignment model,
per-NPC relationship values, and a quest engine with branching and prerequisites.

**What this design does now so it plugs in later, without building any of it yet:**
- The `GameEvents` bus (§3.2) means quests listen to gameplay without touching battle code.
- The bounty **objective schema** (§6.2) is generic, so it can become the quest engine's
  objective format. NPC quests add givers, prerequisites and branches on top.
- **Guild Points** (§6.1) can seed the Adventurer rank. The Guild can become the
  Adventurer's Guild.
- **Save v2's `town` block** (§3.3) leaves room for `npcs`, `relationships` and `alignment`.

## 9. Build plan

| Phase | Contents | Main files |
|---|---|---|
| **0. Foundations** | `GameEvents` autoload; save v2 + migration; material drop rework + new materials; simulator item-use policy | `scripts/autoload/GameEvents.gd`, `SaveManager.gd`, `RewardsManager.gd`, `data/loot/material_tables.json`, `materials.json`, `tests/balance_sim.gd` |
| **1. Alchemist** | recipes data, `AlchemyManager`, AlchemistScene, town button, content-tool tab, tests | `data/recipes.json`, `scripts/autoload/AlchemyManager.gd`, `scenes/town/AlchemistScene.*`, `consumables.json` (2 new) |
| **2. Blacksmith** | `base_damage`/`base_armor`/`upgrade_level` on Equipment; `BlacksmithManager` (upgrade, salvage); naming; save fields; simulator gear profiles | `Equipment.gd`, `EquipmentNamer.gd`, `scripts/autoload/BlacksmithManager.gd`, `scenes/town/BlacksmithScene.*` |
| **3. Guild** | Q1 decision implemented; `bounties.json`; `GuildManager` (board, progress, turn-in); GuildScene; combat log lines | `data/bounties.json`, `scripts/autoload/GuildManager.gd`, `scenes/town/GuildScene.*`, `EnemyFactory.gd` (if Q1 = A) |

Each phase ships on its own: playable, saved, covered by a headless test, and checked
with the balance simulator where it adds player power.
