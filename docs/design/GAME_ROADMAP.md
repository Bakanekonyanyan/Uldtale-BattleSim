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
| ~~B2~~ | ~~**Party of up to 3 heroes in battle**~~ | **Done** (§4, "Party and recruiting") | M-L |
| ~~B3~~ | ~~**Defeat consequences**~~ | **Done:** gold fee, injury, gear to the Guild's Lost & Found (buy-back), Infirmary. Rescue by a rival can come with NPC adventurers | S |
| B4 | **Battle HUD with your art** | Status icons, combo/weak-spot callouts, ultimates presented as big moments | M (art-driven) |
| B5 | Forms / stealth / summons | Druid shapeshift, Shinobi stealth, Necromancer undead are in the philosophies. Can wait: talents already give a taste | M |
| B6 | Advanced combos (Link → Transcendent → Hidden chains) | Agreed for "after more skills and talents". The LINK and ULTIMATE skill categories now exist to chain | M |

## 1b. Combat depth (built)

Five systems on one shared rules layer (`scenes/battle/core/BattleRules.gd`). The battle scene and every headless battle (NPC fights, companions on Auto, the balance sim) play by the same rules. Tuning: `data/combat.json` and `data/elites.json` (Content Manager tabs **Combat** and **Elites**).

**1. Enemy intents:**
- Each enemy's next action is planned ahead and shown on its panel ("Fireball → Mira", "Howl → everyone").
- On its turn, the enemy does what it showed (re-targeted if the target fell).
- **Boss charge-ups:** at the 60% and 35% HP triggers, a boss spends a turn charging its signature or ultimate ("⚠ CHARGING Avalanche Slam"). The charged strike hits ×1.5 next turn. Defend halves it, and a Break cancels it.

**2. Break:**
- Weakness hits fill an enemy's Break pips: the damage type or element it's weak to (shown on the panel). A hit that also triggers a combo counts one extra. Neutral hits don't count.
- Hits needed: 2 for regular enemies, 2 for elites, 3 for bosses, +1 after each Break.
- A Broken enemy loses its next turn, takes +30% damage until then, and loses any charge (and an elite's shield).
- **Heroes and companions have the same meter.** Enemies hitting a hero's weakness (race and armor, shown as "Weak:" on the player panel) fill the hero's pips. 3 hits (`hero_hits`) Break a hero, with the same loss of a turn and +30% damage taken. Pips show on the player panel and the party rows. Breaking a hero gives the enemies no Link. Hero poise resets every battle.

**3. Turn order:**
- A timeline directly under the dungeon banner shows the next turns ("|" marks next round, which is re-rolled).
- Skills with `turn_delay` push enemies back:
  - Ox Kick, Glacial Prison, Behemoth Charge: 2 places.
  - Shield Bash, Kiai, Pinning Thrust, Sacred Seal, Crane Wing Sweep: 1 place.
- Bless, Spirit Barrier and Divine Blessing pull an ally forward to act next.

**4. Link gauge (party):**
- Fills from hits (split across the party), combos (+15) and Breaks (+25). It starts at 10 per Momentum level. Shown directly under the player panel.
- **Ultimates cost 50 Link.**
- LINK skills add 15 and pull the next ally forward.
- At 100, **Unison Strike**: every standing hero hits one target together (×1.4).

**5. Elites:**
- From floor 2, one enemy in a regular wave may be an Elite (6% + 1% per floor, max 30%): ×1.5 HP, +2 levels, ×1.5 gold, and an affix:

| Affix | Effect |
|---|---|
| Shielded | A barrier of 30% max HP soaks damage first; a Break shatters it |
| Vampiric | Heals for 30% of the damage it deals |
| Raging | Below 50% HP it enrages and hits ×1.35 |
| Splitting | Splits into two 35% copies on death |
| Swift | ×1.6 agility |
| Thorned | Reflects 20% of the damage it takes |

**Balance:**
- Floor-1 clear rate stays around 27% solo (was 29%).
- Party scaling was raised to keep a party an advantage but not an auto-win: about 38% with one companion and 48% with two. Per companion, enemies get +70% HP and +1 enemy, and bosses get +200% HP and +30% damage.

**Hero AI** (companions on Auto, NPC fights):
- Uses Unison when the gauge is full.
- Breaks a charging boss if it can this turn, otherwise Defends against the charged hit.
- Finishes Breaks that are one hit away and builds Breaks on bosses and elites.
- Aims at the target worth the most: share of HP removed × threat, weakness, kills.

**What the sim can't measure:** a scripted "smart" policy scores about the same as "strongest skill" (within noise). The value of these systems is information and timing for a human player: when to brace, whom to break, when to spend the gauge. Playtesting is the real check.

## 1c. Replayability, skill and NPC systems (built)

Each system is data-driven; the Content Manager tab is in brackets.

**Skill expression**
- **Perfect Guard** (Combat): Defend while an enemy's shown intent targets you (or a boss is charging). You take a quarter of the damage, gain no Break pips, the attacker gains one, and a charged strike is countered. The Defend button reads "⛨ Perfect Guard" when it applies.
- **Hidden weaknesses + Bestiary** (Combat → Bestiary): enemy weaknesses show "???" until found. A weakness hit reveals it for that race, a Break studies the race (everything), and Inspect studies an enemy if the party has a scholar (Elementalist, Necromancer, Druid, Kannagi, or a Scholarly companion). Town button **Bestiary**.
- **Wave challenges** (Challenges): 60% of waves (every boss wave) offer a goal such as Break 2, Win without items, Perfect Guard, Win in 3 rounds. Progress shows under the turn order. Meet it and win to bank gold, materials and a chance at gear.

**Replayability**
- **Omens** (Omens): after choosing a floor, take up to 3: Bloodmoon, Ironhide, Quickened, Thin Veil, Brittle, Discord, Dim Sight. Each adds 10–20% to wave gold and materials. The dungeon banner lists them.
- **Run boons** (Boons): after each boss, pick 1 of 3 that last the expedition: Vigor, Kindred Spirits, Keen Eye, Ruthless, Steadfast, Second Wind, Opening Gambit, Plunder, Bulwark.
- Both live in `RunState` and clear when the expedition ends.

**NPC interaction**
- **Bonds + duo techs** (Bonds): at rapport 25 / 50 / 75 a companion's next Tavern visit plays a scene written from their traits (Acquainted, Trusted, Bonded). Bonded companions unlock a duo tech for their class: a 50-Link skill you use while they fight beside you, after which they act next.
- **Companion opinions** (Bonds): party members react by trait to Press On, Breather, Omens, boss wins, helping or leaving the wounded, confronting a thief, completed challenges.
- **Commissions** (Commissions): the Blacksmith, Alchemist and Enchanter each post a material request. Deliveries build standing (Known 2, Valued 5, Partner 10): Blacksmith/Enchanter discounts and success bonuses; the Alchemist teaches Elixir of Dawn (Known) and Grand Panacea (Valued). Town button **Commissions**.
- **Rumours** (Rumours): the Tavern's **Rumours** button lists up to 2 tips: a named Elite on a floor, or a cache past a floor's boss. Acting on one banks a bonus.
- **Nemesis rivals** (Encounters): a rival at rivalry 5, or anyone who beat you in an ambush, returns as a Nemesis encounter (2 levels up, sturdier, a grudge line). Beat them for their named signature item.

**Recipes** (Recipes): 14 new, 34 in all. Party heals (Field Dressing, Healing Mist), attribute tonics (Ironbark Tonic, Sage's Draught, Prayer Incense, Hide Ward, Hunter's Focus), area flasks (Firestorm Bomb, Shock Net), combo set-up items (Tidal Flask → Soaked, Marking Dye → Marked, Stagger Stone → Staggered) and the two standing recipes.

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

### What was built (NPC adventurers)

**Choices made:**
- The roster is **fully generated** per new game.
- Personality is **traits + two hidden axes** (Honor, Heart).
- Interaction is **social plus competition**.
- **Real battles for the big moments.**

Data: `data/adventurers.json` (Content Manager tab **Adventurers**). Code:
- `scripts/autoload/AdventurerManager.gd`
- `scripts/resources/AutoBattler.gd` (headless battles with the real engine)
- `scenes/town/TavernScene.gd`

State: `town_state["adventurers"]`.

**Roster:**
- 15–17 adventurers at the start: any playable race (names built from per-race syllables and family names or epithets), any of the 12 classes, levels 1–8, and a rank to match.
- **Two rivals** start near your level with Ambitious or Boastful.
- Newcomers join to keep 14–20 active. The fallen and retired stay in the Tavern's "Fallen & retired" tab.

**Personality:**
- 2–3 of 15 traits: Reckless, Cautious, Ambitious, Greedy, Loyal, Honorable, Cowardly, Kind, Cruel, Lazy, Cheerful, Aloof, Devout, Scholarly, Boastful. Some exclude each other.
- Traits shift the hidden **Honor** and **Heart** axes. Once known, these show as e.g. "Honorable and kind" or "Unscrupulous and ruthless".
- You discover traits by chatting; their nature shows after 3 chats or once they're a friend.

**Daily simulation** (on `GameEvents.day_passed`):
- Idle adventurers take jobs about 45% of days, adjusted by traits.
- **Everyday jobs:** an abstract roll on level, gear and job floor vs traits (about 85% success).
- **Boss hunts** (12%) and **promotion trials** are **real battles**: `AutoBattler.build_hero` builds the NPC (class, level, attributes, talents, class gear), then fights the floor boss through CombatEngine and EnemyAI.
- Trials are only attempted at level ≥ 1.6 × the trial floor. They succeed about 40–60% of the time.
- **Fates on failure** (trait-weighted):
  - Death: 3%, or 6% after a real battle; Reckless ×2, Cautious ×0.4.
  - Retirement: 3%, or 5% after a real battle; Cowardly ×2.5.
  - Otherwise injured for 3–8 days.
- Over 90 simulated days: about 2–3 deaths, 0–6 retirements, and the guild climbs mostly to E and D.

**Competition:**
- Ambitious, Greedy and Boastful adventurers may take a bounty off your board when they leave on a job, but never the last one.
- The board now refreshes every 3 days, so what they take is really gone.

**Rivals:**
- Rivalry grows when they take your bounties or you get promoted.
- News when a rival is promoted, especially when they move ahead of you.

**Tavern:** roster sorted in town first, then by rank, then name, with ⚔ for rivals and ♥ for friends. Each adventurer shows rank, status, a rapport bar and tags, known traits, nature, record and recent history. Actions, each once per day per adventurer and only while they're in town:
- **Chat:** free; raises rapport and reveals a trait.
- **Buy a Drink:** 8 copper × your level; raises rapport more, with a 30% chance to reveal a trait.
- **Give a Gift:** a pack item; value × their tastes (Greedy likes gear, Kind likes potions, Scholarly likes materials).
- Rapport runs from −100 to +100. Tags: Friend at 40, Close friend at 70, Enemy at −40, Rival.

**News:** joins, deaths (it notes when you lost a friend), retirements, promotions, rival moves, bounties taken off the board, and notable boss kills.

**Next (later steps):** recruiting from rapport and rank (B2, party of 3); expedition encounters with these same adventurers (§6); "owes you" and "betrayed you" tags.

### What was built (party and recruiting, B2)

**Choices made:**
- **You control** every hero, with a per-companion **Auto** toggle.
- **Friend rapport and a share of the loot** to recruit and keep companions.
- **Fully automatic** recruit gear and talents.
- **Knock-out with an injury afterwards.** A full party wipe carries a small death chance.

Code:
- `scripts/autoload/PartyManager.gd`
- Party-aware `BattleContext`, `TurnQueue`, `CombatEngine` and `BattleOutcomeHandler`
- `BattleOrchestrator`: manual or Auto turns for companions
- `BattleUIController`: party rows, Auto toggles, ally targeting

Data: `data/adventurers.json` `party` (Content Manager tab **Adventurers**, section Party).

**Recruiting** (Tavern → Invite to Party):
- Needs Friend rapport (40) and a free slot: rank party size − 1 (D and C: 1 companion; B and up: 2).
- Recruits stop taking Guild jobs, level with you (never below your level), and build their own gear and talents.
- They share your pack.

**Battle:**
- Companions take turns in the initiative order. On your turn for them, the info panel, skills and items switch to that hero.
- ALLY skills and items let you choose which hero; ALL_ALLIES reaches the whole party.
- **Auto** hands a companion to the hero AI (the same policy NPC real battles use). It is remembered per companion.
- A knocked-out hero is out for the fight and gets back up at 10% HP after a win. Only a full wipe is a defeat.

**After an expedition:**
- A good one gives +3 rapport, a defeat −2, and each knock-out −3 and a 2–4 day injury.
- You get an injury if you were knocked out but the party won.
- A full defeat has a 4% death chance per companion (× trait).
- Below 20 rapport a companion may leave (35% × trait; Loyal ×0.2).

**Gold:** each companion takes 10–20% of Breather gold by rank (Greedy ×1.5, Honorable ×0.8, Kind and Loyal ×0.9). The Reward screen shows the party's share.

**Scaling** (tuned with `balance_sim.tscn -- tool --party=N`): each companion adds one enemy to regular waves, +35% enemy HP, and bosses get +120% HP and +20% damage.
- Floor-1 clear: about 20% solo, 42% with one companion, 50% with two.
- Class gaps also narrow in a party.

### What was built (expedition encounters)

Data: `data/encounters.json` (Content Manager tab **Encounters**). Code: `scripts/autoload/EncounterManager.gd`, plus join hooks in `BattleOrchestrator`.

**When:**
- SceneManager rolls before each wave: 22% chance, never wave 1 or a boss wave, at most 2 per expedition.
- The cast is real Guild adventurers (never your party), chosen by rapport, rivalry and traits.

**Encounter types:**
- **Helper** (rapport 20+): fights beside you on Auto, either from the start ("Mind if I lend a blade?") or **arriving mid-battle** from round 2–3. +3 rapport and a news item afterwards.
- **Wounded adventurer:** give a Health Potion (+10 rapport, remembered in their history) or refuse (−4).
- **Rival theft** (only with banked Press-On loot; rivals or low-rapport competitors): they take 30–50% of the banked gold.
  - **Confront** them: they fight you right after this wave's enemies fall. Win it back, and they go home injured.
  - **Let it go:** −3 rapport and a news item.
- **Saboteur ambush** (rapport −10 or worse, or a rival, plus Greedy, Ambitious, Cruel or Boastful):
  - The NPC is built with their real class, level, talents and gear, and fights on the enemy side with their role's AI.
  - They either **join mid-battle** (round 2–3) or **attack right when the wave's enemies fall**. Sometimes you get a warning first.
  - Beaten: they limp off injured (rivalry +1, rapport −8, news). If they beat you, it's a normal defeat (news).
- No sprites yet for encounter adventurers; the battle runs without them.

**Also in this step:**
- **Revival:** a new REVIVE skill type, one skill per mender, each in their starting kit (older saves get it on load):
  - Cleric: Dawn's Return, 45% HP.
  - Druid: Rebirth, 30% HP + Regeneration.
  - Kannagi: Spirit Recall, 35% HP, costs MP and SP.
  - It targets a knocked-out ally, who rejoins the turn order. The hero AI revives fallen allies first.
- **Combo guide** (battle action menu, free action, and the Town "Combos" button):
  - Every combo with its set-up, payoff and bonus.
  - ⚡ = an enemy is primed right now; ★ = your party can set up and pay off.
  - Which hero's skills do each.
- **Item tips** in the battle item menu: effect, amount, status, duration and target (`ItemTips.gd`), also shown as hover tooltips.
- **Fix:** the Breather reward screen now shows the level-up screen when the payout levels you up. Before, only Press On did.

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
4. ~~**NPC adventurers:** generator, roster, rapport, simulated quests on the clock.~~ Done.
5. ~~**Party of 3 in battle** (B2), then **recruitment** from the roster.~~ Done.
6. ~~**Expedition encounters:** helpers, rivals, saboteurs between waves.~~ Done.
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
| Exploration | **Etrian Odyssey style:** first-person dungeon crawling with floor mapping. Design in section 8 (build starts Wednesday) |

## 8. Exploration mode (design agreed, not built yet)

Concept sketch: a first-person illustrated view of the path ahead, with a minimap in the top-right corner that fills in as you explore (start, chests, skulls).

**Decisions**

| Topic | Decision |
|---|---|
| Movement | **Full grid with turning:** step forward/back, turn left/right on any tile |
| Layouts | **Generated per location** from rules (size, branching, chests, fights); **boss floors can be handmade** in the Content Manager |
| Fights | **Random encounters** (step counter); fixed skull tiles for Elites, rumoured foes and the boss stairs |
| Wave mode | **Per location:** themed locations (forest, caves, glades) use exploration; the Dungeon stays a wave gauntlet |

**View: layered set pieces (stays 2D illustration)**
- The view is stacked from pieces for what is 1, 2 and 3 tiles ahead, so turning only changes which tiles are looked up. No view is painted per direction, which keeps full-grid turning affordable.
- Per location: a backdrop (sky + horizon band), ground/path pieces at 3 depths (straight, opening left, opening right, dead end), side scenery at 3 depths (tree lines, rocks; mirrored for the other side) and props scaled by depth (chest, skull, campfire, stairs, NPC). About 15–20 pieces per location.
- Line-art placeholders like the sketch until the real art is ready.

**Minimap**
- Top-right corner; full map on a key. Visited tiles revealed, neighbouring tiles dimmed.
- Icons: S start, chest, skull, campfire, stairs, NPC, ★ rumoured Elite.

**Ties to existing systems**
- Random encounters and skull tiles use the current wave builder (enemies, Elites, boss).
- Campfires replace Press On / Breather: Momentum builds until you rest.
- Encounters (helpers, wounded, thieves, nemeses), rumours (marked tiles) and commission materials (gathering spots) happen on the map. Omens, boons, challenges and the Bestiary carry over unchanged.

