# Game roadmap: from battle prototype to a living guild

**The fantasy:** you are a brand-new adventurer. You rise through the Guild's ranks, build relationships with other adventurers (good and bad), recruit the ones you trust, and run into the ones who want to sabotage you. The guild should feel alive while you're away.

This doc covers:
- what the battle system still needs
- the enemy/boss class question
- the Adventurer Guild, NPC adventurers and a world clock
- a build order

Earlier notes: `docs/design/TOWN_SERVICES.md` §9 (the parked Adventurer system).

---

## 1. Battle: what's done and what's missing

**Done:**
- Turn loop and battle math
- Damage types and elements
- Statuses with elements
- Set-up/payoff combos
- 12 classes with talent trees, ultimates and a 6-skill loadout
- Momentum and Breathers
- Gear drops, crafting, upgrading and bounties
- Skills charge every cost they list
- Enemy and boss archetypes (B1, §2)
- Defeat consequences (B3, §7): fee, injury, Lost & Found buy-back, Infirmary

**Missing before the battle system is "done":**

| # | System | Why it matters now | Size |
|---|---|---|---|
| ~~B1~~ | ~~**Enemy and boss classes** (§2)~~ | **Done** | M |
| B2 | **Party of up to 3 heroes in battle** | Recruiting adventurers is the core fantasy. The engine is prepared (enemies target from a hero list); the battle UI and ally AI are not | M-L |
| ~~B3~~ | ~~**Defeat consequences**~~ | **Done:** gold fee, injury, gear to the Guild's Lost & Found (buy-back), Infirmary. Rescue by a rival can come with NPC adventurers | S |
| B4 | **Battle HUD with your art** | Status icons, combo/weak-spot callouts, ultimates presented as big moments | M (art-driven) |
| B5 | Forms / stealth / summons | Druid shapeshift, Shinobi stealth, Necromancer undead are in the philosophies. Can wait: talents already give a taste | M |
| B6 | Advanced combos (Link → Transcendent → Hidden chains) | Agreed for "after more skills and talents". The LINK and ULTIMATE skill categories now exist to chain | M |

## 2. Enemy and boss classes: recommendation

**Use archetypes that blend hero classes, plus a few monster-only skills.**

- An **enemy class** (Minion, Brute, Shaman, Mage, ...) becomes a *role template*:
  - **Skill pools** drawn from hero classes, by weight. For example, Brute pulls from Berserker and Monk; Shaman from Kannagi and Druid; Mage from Elementalist and Necromancer.
  - **One talent branch** it spends points in as the floor rises.
  - **Monster-only skills** where no hero skill fits (Bite, Scratch, Smash, web, breath).
- **Races add flavor:** a Goblin Brute and a Troll Brute share the template, but race picks some of the skills (Trolls get Blunt and Earth, Fairies get Wind and Confuse).
- **Bosses** are an archetype plus:
  - a full talent branch to its ultimate
  - phase triggers (ultimate at 50% HP, enrage)
  - one **signature** skill
- **Named bosses** (your goblin boss) are hand-authored in the planned hybrid `enemies.json`, so they can override anything.

**Why this approach:**
- It keeps **players = enemies** literal: enemy Assassinates, Shatters and ultimates use the exact same rules.
- It reuses 100+ skills and 180 talents instead of writing a parallel set.
- Balance tools (sim, validation) cover enemies for free.
- Players learn enemy kits by recognising their own class skills ("that Shaman is a Kannagi").

**The cost:** some monster skills still need writing for flavor, and AI needs per-archetype priorities (healers heal, bruisers bruise). Both are small.

**Data sketch:**
```json
"Brute": {
  "skill_pools": {"Berserker": ["Cleave", "War Howl", "Whirlwind"], "Monk": ["Ox Kick"], "monster": ["Smash", "Stomp"]},
  "skills_per_enemy": 3,
  "talents": {"class": "Berserker", "branch": "carnage", "points_per_floor": 1},
  "ai_role": "bruiser"
}
```

### What was built

Data: `data/enemy_archetypes.json` (Content Manager tab **Enemy Archetypes**). Code: `scripts/resources/EnemyArchetypes.gd`, used by `EnemyFactory`, `EnemyAI` and `BossAI`.

| Archetype | Stats | Pools (hero classes + monster) | Talent branch | AI role |
|---|---|---|---|---|
| Minion | Minion | Myrmidon, Shinobi, monster | Myrmidon / Skirmisher | skirmisher |
| Brute | Brute | Berserker, Monk, monster | Berserker / Carnage | bruiser |
| Shaman | Shaman | Kannagi, Druid, monster (always has a heal) | Kannagi / Ancestral Spirits | healer |
| Mage | Mage | Elementalist, Necromancer, monster | Elementalist / Conflux | caster |
| Guard *(new)* | Guard | Paladin, Samurai, monster | Paladin / Bulwark | tank |
| Hexer *(new)* | Hexer | Necromancer, Beastmaster, monster | Necromancer / Curses | controller |

**Races:**
- Each race weights the archetypes. Troll Caves are mostly Brutes and Guards; Fairy Circles are Mages, Hexers and Shamans, with no Brutes or Guards.
- Each race adds a flavour pool (Trolls: Smash/Stomp, Orcs: War Howl/Roar, Fairies: Howl/Tidal Wave).

**Floors:**
- Enemies get `floor × 0.5` talent points in their branch.
- Rolled damage skills are capped at `35 + 5 × floor` power.
- Strong buffs wait for a minimum floor (Wolf's Frenzy at 3).
- So floor-1 enemies don't open with a hero finisher.

**AI roles:**
- Roles tune the AI's chances (skill, buff, debuff, combo, defend).
- Healers mend the most wounded ally below 60% HP.

**Bosses (`<Race> <Archetype> King`):**
- Talent points: 3 + floor, spent in the branch.
- The branch **ultimate** is always granted.
- One royal skill: Royal Decree, Execution or Crown of Flames.
- A race **signature**: Ambush Volley (Goblin), Warlord's Cleave (Orc), Avalanche Slam (Troll), Fae Cyclone (Fairy).
- HP triggers: signature below 60%, ultimate below 35%. Each fires once, waiting for cooldown and resources if needed.
- **Named bosses** go in `named_bosses` (by location and floors) and override race, archetype, branch, signature and skills. The section is empty until the first named boss is designed.

**Balance:**
- Enemy damage multipliers were lowered (regular 0.8 → 0.72, boss 0.7 → 0.65) to keep floor-1 clear rates in the old band.
- Monk got +2 VIT and +1 STR.
- Sim, best style, floor 1, 300–800 runs: 15–39% by class, Monk 22% (was 19–45% before archetypes).

## 3. The Adventurer Guild

The bounty board, Guild Points and demerits exist. Ranks turn them into progression:

- **Ranks F → S:** a Guild Points threshold per rank, a promotion task (a named bounty or boss), and demerits that block promotion.
- **Rank perks** (already data fields):
  - carry limit +5 steps
  - rank-gated recipes
  - better bounty boards
  - recruit slots (party size 1 → 2 → 3)
  - access to deeper floors and new locations
- **The Guild Hall screen:** rank and progress, the adventurer roster (§4), the news ledger (§5), and the recruit/party tab.

### What was built (ranks)

Data: `data/ranks.json` (Content Manager tab **Ranks**). Code: `scripts/autoload/RankManager.gd`, hooked into `GuildManager`, `AlchemyManager`, `DungeonStateManager`, the town floor picker and the Reward screen. UI: Guild **Rank** tab; rank shown in the Guild, Town and Status headers.

| Rank | Title | GP | Trial (boss, no deadline) | Floors | Carry | Board / active | Bounty gold | Party | Recipe |
|---|---|---|---|---|---|---|---|---|---|
| F | Fledgling | 0 | - | to 5 | 5 | 3 / 3 | ×1.0 | 1 | |
| E | Wayfarer | 40 | Goblin Forest, floor 3+ | to 8 | 5 | 3 / 3 | ×1.1 | 1 | Smoke Bomb |
| D | Pathfinder | 120 | Troll Caves, floor 6+ | to 12 | 10 | 4 / 3 | ×1.2 | 2 | Berserker Brew |
| C | Vanguard | 260 | Orc Plains, floor 10+ | to 16 | 10 | 4 / 4 | ×1.35 | 2 | Holy Water |
| B | Veteran | 480 | Fairy Circles, floor 14+ | to 20 | 15 | 5 / 4 | ×1.5 | 3 | |
| A | Champion | 800 | The Dungeon, floor 18+ | no cap | 15 | 5 / 5 | ×1.75 | 3 | |
| S | Legend | 1250 | The Dungeon, floor 23+ | no cap | 20 | 5 / 5 | ×2.0 | 3 | |

**Rules:**
- **Promotion** needs the next rank's Guild Points, fewer than 3 demerits, and its **trial**.
- Trials sit in the Active list but don't use a slot, have no deadline, and can be set aside for free.
- Each completed bounty works off one demerit.
- **Floor cap:**
  - Clearing floors past the cap still records progress, but you can't start or advance beyond the cap. A promotion opens those floors immediately.
  - The Reward screen shows "Rank X: floor N max" instead of Next Floor.
- **Bounty templates** can set `min_rank`. Two new templates:
  - Veteran's Cull, from D
  - Royal Writ: two kings, from C
- **Party size** is stored per rank for B2 (party of 3); nothing reads it yet.
- **Rivals out-ranking you** (§7) hook in through `RankManager.rank_changed` once NPC adventurers exist.

## 4. NPC adventurers

- **Who they are:** generated people with a name, race and class (any of the 12), level, rank, gear tier, 2–3 personality traits (honorable, greedy, reckless, cowardly, loyal, ambitious...) and an alignment.
- **Relationship with you:** a rapport value from −100 to +100 plus tags (*friend*, *rival*, *owes you*, *betrayed you*).
- **Where you meet them:**
  - In the Guild Hall.
  - On shared bounties, competing for the same target.
  - **During expeditions**, as events between waves:
    - an ally helps in a fight
    - a rival steals your banked loot
    - a saboteur sets an ambush (a harder wave)
    - a wounded adventurer asks for a potion
- **What moves rapport:** helping in fights, sharing loot, sharing potions, finishing a bounty they wanted (−), rescuing them (+), turning in a rival (±).
- **Recruiting:** possible once rapport and rank are high enough. Recruits become party members (needs B2), with their own talents and loadout, and the AI plays them.
- **Saboteurs:** low-rapport adventurers with *greedy* or *ambitious* traits get sabotage events. Some can become rivals, then (after a story beat) friends.

## 5. World clock (recommended, light version)

Not real time. A **day counter** advances on actions:
- an expedition costs N days (by location and floors)
- resting at the inn costs 1 day

Each day, the world simulates a little:
- **NPC adventurers take quests:** they pull bounties off the board (so the board feels contested). The outcome is rolled from their level, rank and traits against the difficulty. Success gives Guild Points, levels and rank; failure gives injury, recovery days and sometimes death or retirement.
- The **news ledger** in the Guild Hall shows what happened: "Kira (C) cleared Troll Caves floor 5", "Dorn failed at the Orc Plains and is recovering", "Vex took the bounty you wanted".
- **Shops restock and prices drift;** events fire (festival, monster surge in a location).
- **Bounty deadlines** move from "expeditions" to days (they already tick per expedition, so this is a small change).

### What was built (world clock)

Data: `data/world.json` (Content Manager tab **World**), plus `travel_days` per location. Code: `scripts/autoload/WorldClock.gd`; `GameEvents.day_passed` / `days_advanced`. State: `town_state["world"]` per character.

**Time costs:**
- Expeditions: travel (The Dungeon 0 days, themed locations 1) + 1 + ½ per extra floor, rounded down. Being carried back after a defeat adds 1 day.
- The **Inn** (Town) costs 5 copper × level per night, passes 1 or 3 nights and restores you fully.

**What counts down per day:**
- Bounty deadlines: **6 days**.
- Injuries: **4 days**, 6 after a boss.
- Lost & Found: **10 days**.
- The Guild board refreshes whenever time passes.
- Old saves: timers that were in expeditions are doubled on load.

**Calendar:** 7-day weeks (Solday … Starday) and 4 seasons (Bloomtide, Suncrest, Emberfall, Frostmere) of 4 weeks.

**Weekly:**
- The shop restocks the common gear.
- Consumable prices drift up to ±12% per item.
- A world event may start (60% chance):
  - **Monster Surge** in one themed location: enemies ×1.1, gold ×1.3.
  - **Harvest Festival**: consumables ×0.8, Inn half price.
  - **Smiths' Fair**: upgrade fees ×0.85.
  - **Merchant Caravan**: an instant restock.

**News ledger:** a Town panel shows the date, the current event and recent news: time passing, events, failed bounties and promotions. NPC adventurer news will go here (§4).

**Why build it light and early:**
- It's cheap (a seeded tick function, no real-time scheduling).
- Several systems want a shared clock (deadlines, recovery, restocks, NPC progress).
- Adding time later means rewriting those systems.

## 6. Build order (vertical slice)

1. ~~**Finish the battle core:** enemy/boss archetypes (B1), defeat consequences (B3).~~ Done.
2. ~~**Adventurer ranks** in the Guild.~~ Done.
3. ~~**World clock** (days, inn rest, deadlines in days, news ledger).~~ Done.
4. **NPC adventurers:** generator, roster, rapport, simulated quests on the clock.
5. **Party of 3 in battle** (B2), then **recruitment** from the roster.
6. **Expedition encounters:** helpers, rivals, saboteurs between waves.
7. **Exploration mode** for the themed locations (decided earlier: waves now, exploration later).
8. **Battle HUD with art** (B4) whenever the art is ready; forms, stealth and summons (B5); advanced combos (B6).

Deep alignment, branching dialogue and story quests can wait: for a later milestone, or the next game.

## 7. Decisions (answered)

| Topic | Decision |
|---|---|
| Defeat | **A mix:** injury, a gold fee and lost gear. Lost gear goes to the Guild, which sells it back for a price that scales with item level and rarity |
| NPC death | **Injury, retirement and permadeath.** Which one depends on the NPC's personality and alignment (the reckless die more, the cowardly retire) |
| Roster | Start with **12–20 named adventurers**. Later, adventurers are **generated dynamically**, so every fresh playthrough has a different guild |
| Time pressure | **Rivals out-rank you** if you idle too long, or if they avoid injury and get lucky |
| Recruits | **Level with you** while in your party; when off on their own, their progress comes from the **world simulation** |
| Exploration | **Etrian Odyssey style:** first-person dungeon crawling with floor mapping. Details to be discussed when we build it |
