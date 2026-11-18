# Town Services: Alchemist, Blacksmith and Guild Bounties

**Status:** v3. All decisions (Q1–Q7, F1–F5) are incorporated; see the decision log in §10.
Phase 0 (foundations) is built on PR #1; Phase 1 (Alchemist) is next.
**Scope:** three new town buildings that turn dungeon loot into character progress, plus
**Expedition Locations**, which the bounty design needs.
**Out of scope (parked):** the Adventurer system (§9).
**Art:** all three buildings use the shop background until dedicated art is ready.

---

## 1. Goals

Today a dungeon run produces gold, XP and gear. Materials drop but do nothing except
sell. These services close the loop:

```
   Town ── choose a LOCATION (Goblin Forest · Troll Caves · Orc Plains · Fairy Circles · The Dungeon)
     │
     ▼
   Expedition (waves + boss) ── gold · XP · gear · MATERIALS (by location) · kills
     │
     ▼
   Town ─┬─ Alchemist  : materials → potions, flasks, cures ──► survive deeper
         ├─ Blacksmith : materials + gold → upgraded gear  ───► hit harder, take less
         └─ Guild      : bounties → gold, rare mats, recipes, Guild Points ─┘ (feeds the other two)
```

Design principles:

1. **Every source needs a sink.** Materials and gold get meaningful uses, and every
   new reward has somewhere to go.
2. **Data-driven.** Locations, recipes, upgrade costs and bounties live in `data/*.json`
   and get tabs in `DevTools/content_manager.py`, like the existing content.
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
| Consumables (`consumables.json`) | 20 items, `max_stack` 99. The shop sells 12. **The 8 cure items are not sold anywhere.** | Cures are effectively craft-only already |
| Material drops (`RewardsManager`) | 30% × (1 + 0.1·floor) per regular wave, 100% for the boss. About 1.3 materials per floor-1 run, picked uniformly at random. | Far too few to craft with; must change (§3.2) |
| Gold | `(50 + 10·wave) × floor` per wave, boss ×2. About 620 copper for a floor-1 clear; 500 to start. Shop potions cost 25–30. | Sets the scale for prices |
| Equipment scaling (`EquipmentScaler`) | damage/armor = base × rarity mult (1–5) × (1 + 0.05·(ilvl−1)), applied in place | Upgrades need the base values stored (§5.2) |
| Dungeon race (`EnemyFactory.set_dungeon_race`) | Random per floor, hidden; set in `DungeonStateManager.start_dungeon` and `advance_floor` | Replaced by Locations (§3.1) |
| Floor select (`TownScene.show_floor_selection_dialog`) | Floors 1–25, gated by `max_floor_cleared` | The Location picker goes in front of it |
| Kill tracking | None. Every death goes through `BattleOutcomeHandler.handle_deaths()` since the battle refactor. | One clean hook for bounty progress |
| Town (`TownScene`, `SceneManager.ScenePath`) | Button per service plus a `ScenePath` entry | New buildings follow the same pattern |

## 3. Shared foundations (build first)

### 3.1 Expedition Locations *(Q1)*
The player picks **where** to go, then **which floor**:

| Location | Enemy races | Character |
|---|---|---|
| **Goblin Forest** | Goblin only | Fast, high-dodge enemies; poison and bleed |
| **Troll Caves** | Troll only | Tanky hitters; cold-themed drops |
| **Orc Plains** | Orc only | Brutes and armor; ore-rich |
| **Fairy Circles** | Fairy only | Casters, high magic; arcane drops |
| **The Dungeon** | **Mixed:** each enemy rolls a random race | The classic wave gauntlet; drops from every table |

Rules:
- **Two modes, eventually** *(F1)*. **The Dungeon stays a wave-based gauntlet.** The
  four themed locations will become **exploration** areas once the Adventurer system
  exists (§9). Until then they use the same wave format with a single race.
- **Floor progress is tracked per location** *(F2)*. Each location has its own highest
  unlocked floor (`location_progress[location_id]`). Existing saves carry their old
  `max_floor_cleared` over to The Dungeon, which is the mode they were played in.
  Themed locations start at floor 1.
- **Bosses match the location**, e.g. "Goblin Brute King" in the Goblin Forest. In
  The Dungeon the boss race is random.
- **Material drops come from the race of each defeated enemy** (§3.2). Single-race
  locations are where you farm specific materials; The Dungeon gives a mix.
- **Race-specific bounties point at a location** ("Cull the Brutes of Orc Plains"),
  so every bounty can be planned.

Data: `data/locations.json`
```json
"goblin_forest": { "name": "Goblin Forest", "races": ["Goblin"], "description": "...", "reward_mult": 1.0 },
"troll_caves":   { "name": "Troll Caves",   "races": ["Troll"],  "description": "...", "reward_mult": 1.0 },
"orc_plains":    { "name": "Orc Plains",    "races": ["Orc"],    "description": "...", "reward_mult": 1.0 },
"fairy_circles": { "name": "Fairy Circles", "races": ["Fairy"],  "description": "...", "reward_mult": 1.0 },
"the_dungeon":   { "name": "The Dungeon",   "races": "all", "mixed": true, "mode": "waves", "description": "...", "reward_mult": 1.0 }
```
Code changes:
- `EnemyFactory.set_dungeon_race(floor)` becomes `set_location(location_id)`. For a
  mixed location, `create_enemy` rolls the race per enemy.
- `DungeonStateManager.start_dungeon(player, floor, location_id)` stores the location.
- The battle background will be chosen per location once art exists *(F5)*; there's a
  `background` field reserved for it.

### 3.2 Material economy
- **More drops.** Each regular wave drops 1–2 materials and the boss 3, plus floor scaling.
  Target: about **8–10 materials per floor-1 run**.
- **Drop table per race** (`data/loot/material_tables.json`):

  | Race (location) | Common drops | Uncommon drops |
  |---|---|---|
  | Goblin (Goblin Forest) | bogblossom_petal, rousepepper_seeds | iron_ore |
  | Orc (Orc Plains) | iron_ore, bloodvine_fiber | wood |
  | Troll (Troll Caves) | frostroot_chunk, wood | voltslate_pebble |
  | Fairy (Fairy Circles) | glowcap_mushroom, mindglass_shard | embershard_fragment |

- **New tiered materials** (for upgrades and higher-tier potions):
  - `mithril_ore` (floors 6+) and `adamant_ore` (floors 12+), as a progression gate.
  - `monster_core`: boss-only, used for high-end upgrades, top-tier potions and as a
    bounty reward.
- **Crafting and upgrading read inventory and stash together** *(Q4)*. Ingredients come
  out of the inventory first.

### 3.3 Consumable carry limit *(Q3)*
- The **pack** holds at most **5 of each consumable**. The **stash** keeps the rest,
  up to the item's existing `max_stack` of 99.
- The limit is a value on the character, `carry_limit` (default 5). It increases in
  steps of **+5 up to 20**, from a future purchase (e.g. "Adventurer's Satchel") and/or
  Adventurer rank (§9).
- **Overflow goes to the stash automatically:** loot drops, shop purchases and crafting
  output above the limit are sent there, with a log line like "3 Health Potions sent to
  stash". This one rule covers every way items arrive, and never blocks loot.
- A one-time migration moves any existing excess from the inventory to the stash.
- Enemy inventories are not affected.

### 3.4 `GameEvents` autoload (event bus)
A small signal hub that gameplay emits to and town systems listen to:

```gdscript
signal expedition_started(location_id: String, floor_num: int)
signal expedition_ended(location_id: String, cleared: bool)      # cleared or died
signal enemy_killed(enemy: CharacterData, location_id: String, floor_num: int, is_boss: bool)
signal battle_won(location_id: String, floor_num: int, wave: int, is_boss: bool)
signal floor_cleared(location_id: String, floor_num: int)
signal item_crafted(item_id: String, quantity: int)
signal item_upgraded(item: Equipment, new_level: int, success: bool)
```

These are emitted from `BattleOutcomeHandler` (kills and victory) and
`DungeonStateManager` (expedition and floor events). The Guild listens now, and the
Adventurer system's quests can listen later (§9) without touching battle code.

### 3.5 Save format v2
- Add `"save_version": 2` and a migration from v1, which has no version key.
- New fields on the character: `carry_limit` (default 5) and `last_location`.
- New top-level `"town"` block:
  ```json
  "town": {
    "alchemy":    { "known_recipes": ["antidote_herb", "..."], "crafts": 0 },
    "blacksmith": { },
    "guild":      { "points": 0, "demerits": 0, "active": [ ... ], "completed_ids": [ ... ], "board": [ ... ] }
  }
  ```
- Equipment gains `base_damage`, `base_armor` and `upgrade_level` (§5.2). A v1 item
  migrates as base = current value, upgrade 0.

### 3.6 Town building pattern
Each building gets the same three pieces:

- a scene: `scenes/town/AlchemistScene`, `BlacksmithScene`, `GuildScene`
- a manager autoload holding the logic, with no UI
- a data file

Each also gets a `ScenePath` entry and a TownScene button. **For now, all three scenes
use the shop background.** The managers contain all the rules, so they can be tested
headlessly like the battle code.

## 4. Alchemist

**Role:** turns materials into consumables. It's the only source of cure items and of
higher-tier potions, and it makes basic potions cheaper than the shop.

### 4.1 Rules
- **Craft:** select a recipe and a quantity (1, 5 or max). It consumes ingredients plus
  a small copper fee. Output goes to the pack up to the carry limit; the rest goes to
  the stash (§3.3).
- **Value proposition, so crafting isn't just a worse shop:**
  1. Cures are craft-only (they already aren't sold).
  2. Shop-sold items cost about **50–70%** of the shop price to craft.
  3. Higher tiers (Greater Health Potion, Ether) can only be crafted.
- **Recipe unlocks:** cures and basic potions are known from the start. **Status
  flasks are bought** at the Alchemist as recipe books *(Q5)*, which gives an early
  gold goal. Higher tiers come from reaching a floor or from bounties. Upgraded flask
  recipes will later be gated by Adventurer rank (§9).

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
Unlock types: `default`, `purchase`, `floor_reached`, `bounty_reward`, and later
`adventurer_rank`.

### 4.3 Starter recipe table (first pass, to be tuned)

| Output | Ingredients | Fee | Shop price | Unlock | Farm at |
|---|---|---|---|---|---|
| 2× each cure (8 recipes) | 2× its matching material | 10 | not sold | default | varies |
| Health Potion | glowcap ×1, bloodvine ×1 | 5 | 25 | default | Fairy / Orc |
| Mana Potion | mindglass ×1, glowcap ×1 | 8 | 30 | default | Fairy |
| Stamina Potion | rousepepper ×1, bloodvine ×1 | 8 | 30 | default | Goblin / Orc |
| Flame Flask | embershard ×2, wood ×1 | 15 | 50 | buy 300 | Fairy / Troll |
| Frost Crystal | frostroot ×2, mindglass ×1 | 15 | 50 | buy 300 | Troll / Fairy |
| Thunder Orb | voltslate ×2, iron_ore ×1 | 15 | 50 | buy 300 | Troll / Orc |
| Venom Vial | bogblossom ×2, wood ×1 | 15 | 50 | buy 300 | Goblin / Troll |
| Greater Health Potion *(new)* | glowcap ×2, bloodvine ×2, monster_core ×1 | 60 | – | floor 5 | bosses |
| Ether *(new: restores MP and SP)* | mindglass ×2, rousepepper ×2, monster_core ×1 | 60 | – | floor 5 | bosses |

Most recipes need materials from two locations, which gives a reason to visit more
than one.

### 4.4 Battle impact
- Potions are the intended fix for the weak classes (Elementalist, Druid), which run
  out of HP and MP over a Press-On streak.
- The **5-per-type carry limit** *(Q3)* keeps potions from trivializing floors.
- **The simulator needs an item-using policy** (drink a potion below X% HP) before
  potion numbers are final. It currently never uses items.

### 4.5 UI (shop background for now)
`AlchemistScene` has three areas:

- a recipe list, filtered to Craftable, Known, or All with locked recipes greyed out
- a detail panel showing each ingredient's have/need count (pack + stash), the fee,
  the output description, and where to farm each material
- a quantity selector and a Craft button, with a "Buy recipe" button for purchasable
  recipes

## 5. Blacksmith

**Role:** makes gear you like stronger, and turns gear you don't want into materials.

### 5.1 Services
| Service | What it does | v1? |
|---|---|---|
| **Upgrade** | +1 upgrade level: more damage/armor, renamed "+N Item". Higher levels can fail; extra payment raises the odds. | ✅ |
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

### 5.3 Upgrade cost (base cost to reach level L)
```
gold      = item.value × 0.25 × L
materials = ore × L          (iron_ore for L ≤ 3, mithril_ore for L 4–6, adamant_ore for L 7+)
          + wood × 1         (weapons only)
          + monster_core × 1 (L ≥ 6)
```
Example: a Short Sword (value 100) from +0 to +3 costs 25 + 50 + 75 = **150 copper and
6 Iron Ore**, with no risk.

### 5.4 Success chance and reinforcement *(Q2)*
Upgrades to +1…+3 always succeed. Above that, each attempt has a **base success chance**:

| Target level | +1–3 | +4 | +5 | +6 | +7 | +8 | +9 | +10 |
|---|---|---|---|---|---|---|---|---|
| Base success | 100% | 90% | 80% | 70% | 60% | 50% | 40% | 30% |

**Reinforcement:** the player can pay more than the base cost to raise the odds. A
slider adds extra payment in **steps of 25% of the base cost** (gold *and* materials
together). Each step adds **+10% success**, up to 100%.

```
success = min(1.0, base_success + 0.10 × reinforcement_steps)
```

| Target | Base | Steps to guarantee | Total cost to guarantee | Expected cost with no reinforcement |
|---|---|---|---|---|
| +4 | 90% | 1 | 1.25× | 1.11× |
| +6 | 70% | 3 | 1.75× | 1.43× |
| +8 | 50% | 5 | 2.25× | 2.0× |
| +10 | 30% | 7 | 2.75× | 3.33× |

So a gambler pays less on average at low levels, while at the top it's cheaper to buy
certainty. That makes the slider a real decision.

**On failure** *(F3)*: **the payment is consumed.** Below +7 the item keeps its level.
**If the item is already +7 or higher, it drops one level** (a failed +7→+8 attempt
leaves it at +6). It never breaks. Every failure also gives the item **"Tempered"**:
+5% to its next attempt, stacking, and reset on success.

```
DOWNGRADE_FROM_LEVEL = 7     # items at this level or above lose 1 level on failure
TEMPERED_BONUS       = 0.05  # per consecutive failure
```

The UI always shows the exact success %, the cost of each reinforcement step, and the
pity bonus.

### 5.5 Salvage yields
| Rarity | Yield |
|---|---|
| common | 1–2 ore |
| uncommon | 2–3 ore |
| magic / rare | 3–4 ore + 25% monster_core |
| epic / legendary | 4–6 higher-tier ore + 1 monster_core |

The ore tier follows the item's level (iron below ilvl 6, mithril 6–11, adamant 12+).
Salvaging requires a confirmation, and equipped items can't be salvaged.

### 5.6 UI (shop background for now)
`BlacksmithScene` has two tabs, Upgrade and Salvage. Both list equipped, pack and
stash gear. Upgrade shows:

- a before/after preview of damage or armor
- the base cost and a reinforcement slider
- the live success %, including any Tempered bonus
- an Upgrade button

## 6. Guild Bounties

**Role:** gives expeditions short-term goals and pays out rewards the other two
buildings need, such as rare materials and recipes.

### 6.1 Rules
- The **board** shows 3 bounties and **refreshes after each expedition** (cleared or
  died) *(Q6)*. The player can have up to **3 active** at once.
- **Deadlines** (my proposal): an accepted bounty must be completed within
  **3 expeditions**. The remaining count shows on the Active tab.
- **Failing a bounty** *(Q6)*:
  - If the deadline passes, the bounty fails automatically: **demerit −50% of the
    bounty's Guild Points**, and +1 to the character's `demerits` count.
  - **Abandoning early** lets the player choose: take the **same demerit**, or pay a
    **penalty fee of 25% of the bounty's gold reward** to leave with no demerit.
  - GP can't go below 0. The `demerits` count is stored for the future rank system,
    e.g. too many demerits could block promotion.
- Progress counts as it happens and is saved with the character. If you die before
  the next save, you lose that unsaved progress, the same as XP today.
- Completed bounties are **turned in at the Guild** to claim the reward.
- **Guild Points are shown in v1** *(Q7)* as a plain number with no ranks yet. They
  become Adventurer rank progress later (F → S, §9).

### 6.2 Objective types (generic on purpose, for reuse by future quests)
| Type | Example | Progress source |
|---|---|---|
| `KILL` | Defeat 10 Brutes in Orc Plains | `enemy_killed` + target filter |
| `KILL_BOSS` | Defeat the Troll Caves boss on floor 3+ | `enemy_killed` with `is_boss` |
| `CLEAR_FLOOR` | Clear floor 4 in any location | `floor_cleared` |
| `WIN_STREAK` | Win 5 waves in a row with Press On | `battle_won` + momentum |
| `DELIVER` | Bring 6 Frostroot Chunks | turned in at the Guild, consumes items (pack + stash) |

Target filter fields: `location`, `race`, `class` (boss classes are `"King (Brute)"`,
so match on the minion class), `is_boss`, `min_floor`. **Filters match the `race` and
`character_class` fields, never display names** (display names look like "Orc Brute 2").
The board only rolls bounties the player can complete, i.e. no floor above
`max_floor_cleared + 1`.

### 6.3 Data: `data/bounties.json` (templates the board rolls from)
```json
"cull_brutes": {
  "title": "Cull the Brutes",
  "objective": { "type": "KILL", "target": { "location": "orc_plains", "class": "Brute" }, "count": [6, 12] },
  "min_floor": 1,
  "deadline_expeditions": 3,
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
  "objective": { "type": "CLEAR_FLOOR", "target": { "location": "troll_caves" }, "floor": "player_max+1" },
  "min_floor": 3,
  "deadline_expeditions": 3,
  "weight": 3,
  "rewards": { "recipe": "frost_crystal", "points": 25 }
}
```
Counts and rewards scale with `max_floor_cleared` when the bounty is rolled. Rewards
should add up to about 30–50% of an expedition's gold, plus the items.

### 6.4 UI (shop background for now)
`GuildScene` has three tabs, plus a header showing **Guild Points and demerits**:

- **Board:** available bounties, each with an Accept button
- **Active:** progress bars, expeditions remaining, and an Abandon button that offers
  the demerit-or-fee choice
- **Turn In:** completed bounties and their rewards

In battle, the combat log shows progress lines such as "Bounty: Brutes 4/10" when a
kill counts.

## 7. Floor selection flow (updated)

```
Town → [Expedition] → pick Location (5 cards with description, races, materials,
                      active-bounty markers) → pick Floor (existing 1–25 grid) → Start
```
The location picker is a new dialog in front of the existing
`show_floor_selection_dialog()`. It remembers `last_location`.

## 8. Follow-up decisions

| # | Question | Decision |
|---|---|---|
| F1 | What makes The Dungeon different? | It stays the **wave-based gauntlet** with mixed races. The themed locations become **exploration** areas later (waves until then). No reward multiplier needed. |
| F2 | Shared or per-location floor progress? | **Per location**. Old saves carry their progress over to The Dungeon. |
| F3 | Upgrade failure | **Payment lost, item kept, Tempered bonus. Items at +7 or higher lose one level on failure.** |
| F4 | Bounty deadlines and penalties | **Default**: 3 expeditions; fail = −50% GP + 1 demerit; abandon = demerit or 25% fee |
| F5 | Per-location battle backgrounds | **Later**; the data field is reserved |

## 9. Future: Adventurer system (parked)

Your idea, recorded so it isn't lost:

- **Exploration dungeons** that are explored rather than played as wave gauntlets. The
  four themed locations (§3.1) become these.
- **Adventurer rank F, E, D, C, B, A, S**, unlocking new quest types.
- **A robust NPC system** with quest givers and named characters.
- **Alignment and relationship systems** that affect quests and NPC reactions.
- **Rank-gated perks** you've already named:
  - **carry limit +5 per step up to 20** (§3.3)
  - **upgraded status-flask recipes** (§4.1)

This is a much larger project. It needs NPC data and dialogue, an alignment model,
per-NPC relationship values, and a quest engine with branching and prerequisites.

**What this design does now so it plugs in later, without building any of it yet:**
- The `GameEvents` bus (§3.4) means quests listen to gameplay without touching battle code.
- The bounty **objective schema** (§6.2) is generic, so it can become the quest engine's
  objective format. NPC quests add givers, prerequisites and branches on top.
- **Guild Points and demerits** (§6.1) become rank progress and promotion blockers.
  The Guild can become the Adventurer's Guild.
- **`carry_limit`** (§3.3) and the recipe **`adventurer_rank` unlock type** (§4.2) are
  already data fields, so rank perks only need to set them.
- **Save v2's `town` block** (§3.5) leaves room for `npcs`, `relationships` and `alignment`.

## 10. Decision log

| # | Question | Decision |
|---|---|---|
| Q1 | Enemy race per floor | Selectable locations: **Goblin Forest, Troll Caves, Orc Plains, Fairy Circles**, plus **The Dungeon** with mixed enemies (§3.1) |
| Q2 | Upgrade failure | **Higher levels can fail**; paying extra materials and gold raises the success chance (§5.4) |
| Q3 | Carry limit | **5 of each consumable**; later +5 steps to **max 20** via purchase or Adventurer rank (§3.3) |
| Q4 | Crafting from stash | **Yes** |
| Q5 | Status flask recipes | **Bought**; upgraded flask recipes later tied to Adventurer rank |
| Q6 | Bounty board refresh | **After each run**; unfinished bounties give **demerits or a penalty fee** (§6.1) |
| Q7 | Guild Points | **Visible now**; Adventurer ranks **F, E, D, C, B, A, S** later |
| F1 | Dungeon vs themed | Dungeon = wave gauntlet (mixed races); themed locations = exploration later |
| F2 | Floor progress | **Per location** |
| F3 | Upgrade failure | Payment lost, Tempered; **−1 level on failure at +7 and above** |
| F4 | Bounty deadlines | Default (3 expeditions, demerit or fee) |
| F5 | Location backgrounds | Later |
| – | Art | Alchemist, Blacksmith and Guild use the **shop background** for now |

## 11. Build plan

| Phase | Contents | Main files |
|---|---|---|
| **0. Foundations** ✅ built | `GameEvents` autoload; save v2 + migration; **Locations** (data, `EnemyFactory.set_location`, mixed races, location picker); material drop tables + new materials; **carry limit** with overflow to stash; simulator item-use policy + per-location runs | `scripts/autoload/GameEvents.gd`, `SaveManager.gd`, `data/locations.json`, `EnemyFactory.gd`, `EnemyGroup.gd`, `DungeonStateManager.gd`, `TownScene.gd`, `RewardsManager.gd`, `data/loot/material_tables.json`, `materials.json`, `Inventory.gd`, `tests/balance_sim.gd` |
| **1. Alchemist** | recipes data, `AlchemyManager`, AlchemistScene (shop background), town button, content-tool tab, tests | `data/recipes.json`, `scripts/autoload/AlchemyManager.gd`, `scenes/town/AlchemistScene.*`, `consumables.json` (2 new) |
| **2. Blacksmith** | `base_damage`/`base_armor`/`upgrade_level`; `BlacksmithManager` (upgrade with success roll + reinforcement + Tempered, salvage); naming; save fields; simulator gear profiles | `Equipment.gd`, `EquipmentNamer.gd`, `scripts/autoload/BlacksmithManager.gd`, `scenes/town/BlacksmithScene.*` |
| **3. Guild** | `bounties.json`; `GuildManager` (board, progress, deadlines, demerits/fees, turn-in); GuildScene; combat log lines | `data/bounties.json`, `scripts/autoload/GuildManager.gd`, `scenes/town/GuildScene.*` |

Each phase ships on its own: playable, saved, covered by a headless test, and checked
with the balance simulator where it adds player power. Phase 0 is now the largest,
because Locations and the carry limit change how expeditions start.
