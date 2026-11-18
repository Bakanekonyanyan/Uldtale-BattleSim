# Battle Math

Combat math lives in two places:

- **`core/BattleFormulas.gd`**: how damage, defense, crits, heals, buffs and status procs work.
- **`scripts/autoload/EnemyFactory.gd`** (constants at the top): how strong enemies and bosses are.

Status effect strengths (DoT %, stun chance) live in `data/status_effects.json`.

Check any change with the simulator before playtesting:

```
godot --headless res://tests/balance_sim.tscn -- mylabel
```

## Formulas

| | Formula |
|---|---|
| Physical offense | `attack_power + weapon damage` |
| Magical offense | `spell_power` |
| Hit damage | `offense × 0.75 × (1 + skill_power × 1%) × mitigation(defense)` |
| Mitigation | `100 / (100 + defense)` → 0 def = 100%, 100 def = 50%, 300 def = 25% |
| Physical defense | `toughness + armor × 0.5` |
| Magical defense | `spell_ward + armor × 0.25` |
| Crit | `crit_rate` chance for ×1.5–2.0 |
| Heal | `skill_power + spell_power × 0.5` |
| Buff / debuff | `skill_power` × 1.5% of the target's **base** attribute (Roar 40 = −60% Agility), lasting the full listed number of the target's turns |
| Debuff hit | Debuff skills also hit each target for 75% of a basic attack |
| Status on damage skills | 35% chance per effect per target hit (dedicated status/debuff skills always apply) |

Basic attacks are hit damage with skill power 0. A skill is a basic attack boosted
by its power (power 25 → ×1.25, power 55 → ×1.55). Its value comes from AoE, status
effects and buffs, and it's paid for with MP/SP and cooldowns.

### Character stats (`CharacterData.calculate_secondary_attributes`)

Attack power and spell power share one shape: **primary stat ×2 + two secondaries ×0.5**.

| Type | Attack power | Spell power |
|---|---|---|
| strength | STR×2 + DEX×0.5 + VIT×0.5 | |
| dexterity | DEX×2 + STR×0.5 + AGI×0.5 | |
| arcane | ARC×2 + STR×0.5 + DEX×0.5 | ARC×2 + INT×0.5 + FAI×0.5 |
| intelligence | | INT×2 + FAI×0.5 + ARC×0.5 |
| faith | | FAI×2 + INT×0.5 + ARC×0.5 |
| balanced | | INT + FAI + ARC |

- Toughness = VIT×0.45 + STR×0.25 + END×0.15 + FOR×0.15
- Spell ward = MND×0.45 + FAI×0.25 + ARC×0.15 + FOR×0.15
- Accuracy = 85% + small stat bonus. Dodge = 5% + small stat bonus.

### Enemies (`EnemyFactory` constants)

| Constant | Value | Meaning |
|---|---|---|
| `WAVE_SCALING` | 0.05 | +5% stats per wave in a floor (wave 1 ×1.00, wave 5 ×1.20) |
| `ENEMY_HP_MULT` | 0.5 | Regular enemies have half a hero's HP for the same stats |
| `ENEMY_DAMAGE_MULT` | 0.85 | ...and deal 85% damage. The hero fights alone against groups. |
| `BOSS_HP_MULT` | 1.0 | Boss HP vs a hero with the same stats (King stats already make it ~2× a hero) |
| `BOSS_DAMAGE_MULT` | 0.7 | Boss damage scale (bosses also gain phase/enrage buffs) |
| `BOSS_MINION_STAT_SHARE` | 0.25 | Share of the minion class's stats a boss inherits |

Floor scaling (`get_base_multiplier`) and momentum (+10% enemy stats per level) are unchanged.

### Status effects (`data/status_effects.json`)

| Effect | Old | New |
|---|---|---|
| Poison | 15% max HP / turn | 6% |
| Burn | 10% | 4% |
| Shock | 12.5%, 30% stun | 5%, 15% stun |
| Freeze | 25% stun | 15% stun |
| Bleed burst (3 stacks) | 30% max HP | 20% |

## What was wrong before

1. **Skills did 2–8× a basic attack.** A skill dealt `power + 100% of offense − defense`, while a basic attack dealt `50% of offense`. Enemy Fireball hit a 140 HP Paladin for ~86.
2. **Spell power was 0 for "faith" casters** (Paladin, Cleric, Druid, Shaman), and **attack power was 0 for Druid** ("arcane"). Those types weren't handled.
3. **Armor and weapon damage did nothing in combat.** They were only displayed.
4. **Defense was cosmetic.** Toughness was divided by 10 (~1 at level 1). Spell ward multiplied two stats together, so it grew quadratically.
5. **Buff/debuff skills added their raw power as stat points.** Roar (40) removed 40 Agility from a level-1 hero who had ~6. The boss's Royal Decree added +60 Strength.
6. **The floor-1 boss was multiplied three times** (×2 VIT and ×1.5 other stats, then ×1.5 boss, then ×1.9 wave): ~1,400 HP and ~8× the hero's attack power.
7. **Enemies scaled +15% per wave**, so floor-1 wave 5 enemies had 1.75× a level-1 hero's stats.

## Simulated results

150 simulated runs per cell, using the real engine, AI and enemy generation with an
auto-pilot player. The player heals when low, uses its best ready damage skill, and
otherwise attacks the weakest enemy. It never uses items, so real players should do
somewhat better.

**Single fights, floor 1, fresh level-1 hero with no gear (win %):**

| Class | Wave 1 before → after | Wave 3 before → after | Wave 5 before → after |
|---|---|---|---|
| Paladin | 54 → 96 | 12 → 92 | 0 → 86 |
| Necromancer | 59 → 90 | 25 → 79 | 2 → 62 |
| Myrmidon | 45 → 93 | 10 → 87 | 0 → 77 |
| Cleric | 30 → 87 | 5 → 80 | 0 → 65 |
| Samurai | 58 → 92 | 17 → 86 | 2 → 81 |
| Elementalist | 72 → 84 | 37 → 82 | 13 → 66 |
| Druid | 24 → 69 | 4 → 58 | 0 → 40 |
| Monk | 53 → 98 | 22 → 88 | 3 → 68 |

**Full floor-1 run** (5 waves and a boss in one go, starting at level 1). The player
levels up from XP, takes a Breather below 50% HP (below 80% before the boss), and
otherwise presses on:

| Class | Before | After |
|---|---|---|
| Paladin | 0% | 37% |
| Myrmidon | 0% | 39% |
| Samurai | 0% | 22% |
| Cleric | 0% | 18% |
| Monk | 0% | 16% |
| Necromancer | 0% | 14% |
| Elementalist | 0% | 2% |
| Druid | 0% | 0% |

Results vary by roughly ±10 points between simulator runs, because each floor's
enemy race is random. A repeat run of the same settings gave floor-1 clears of
Paladin 49%, Myrmidon 50%, Samurai 40%, Monk 35%, Necromancer 23%, Cleric 21%,
Druid 12% and Elementalist 6%.

Before, no class ever cleared floor 1. After, a character that clears floor 1 usually
keeps going: most floor-1 clearers also clear floors 2–4 (campaign mode in the
simulator). The floor-1 boss is the main gate. A death keeps the levels already
earned, so a failed run still moves the character forward.

## Class tuning (pass 1)

Floor-1 full-run clear rate, judged by each class's better play style, from
`godot --headless res://tests/balance_sim.tscn -- classes_<label>` (N=200, ±~5 points):

| Class | Before (no potions / 5+5 potions) | After |
|---|---|---|
| Paladin | 43% / 83% | 27% / 68% |
| Elementalist | 3% / 19% | 23% / 70% |
| Druid | 4% / 10% | 18% / 52% |
| Others (unchanged) | 14–30% / 41–60% | 16–31% / 45–58% |

Changes (`data/skills.json`, `data/classes.json`):
- **Paladin:** Holy Strike power 25→20, MP 10→20, cooldown 3→4, riders Confused+Blind+Burn → Blind+Burn. Base VIT 12→11.
- **Elementalist:** Blazing Ice Spear is now the repeatable bread-and-butter spell: power 20→30, MP 25→20, cooldown 4→1. Volcanic Thunder Storm power 30→40, cooldown 6→4. Base VIT 7→8.
- **Druid:** Plague Strike power 40→55, SP 25→15, cooldown 4→2. Wild Protection duration 3→4. Base ARC 10→12.

The root problem for both casters was that their main damage skill was on a long
cooldown, so most turns were weak basic attacks.

**Finding:** for almost every class, damage-only play beats spending turns on buffs
or debuffs, which pay back less than a turn of damage in a 5–8 turn fight. Support
skills (Arcane Clarity, Divine Shield, Bless, Curse of Weakness…) need a general pass,
e.g. longer durations or an immediate effect.

## Buff/debuff rework and class pass 2

**Why buffs were weak:** durations tick at the start of the target's turn, so an
N-turn buff boosted only N−1 of the caster's actions, after the caster spent a turn
casting it. A +40% stat buff came out about even with just attacking.

**Changes** (`BattleFormulas`):
- `BUFF_DURATION_BONUS = 1`: the listed duration is now the number of turns affected.
- `BUFF_PERCENT_PER_POWER` 1% → 1.5%.
- `DEBUFF_HIT_SCALE = 0.75`: debuffs also hit, so they're never a wasted turn.

**Compensation:** enemies use buffs and debuffs too, so regular enemy damage went
0.85 → 0.8. Two classes also changed:
- **Necromancer:** VIT 6→8, Life Tap cooldown 4→3.
- **Cleric:** Smite cooldown 3→2 and MP 30→20; STR 6→8.

**Result:** set-up play (buff/debuff first) now beats or ties damage-only for every
class; before, damage-only won for 7 of 8. Floor-1 full-run clear rates (best style):

| Class | No potions | 5+5 potions |
|---|---|---|
| Cleric | 28% | 63% |
| Paladin | 23% | 60% |
| Monk | 21% | 59% |
| Elementalist | 28% | 56% |
| Druid | 19% | 53% |
| Necromancer | 23% | 51% |
| Samurai | 15% | 46% |
| Myrmidon | 18% | 44% |

All classes are within about 20 points of each other. Average difficulty with
potions (54%) matches pass 1 (56%). Samurai and Myrmidon are the next candidates
for a pass. Myrmidon's Evasion buffs Agility, which barely moves dodge (dodge uses
AGI/200).

## Known gaps and next steps

- **Class balance.** Two passes are done (see above). Samurai and Myrmidon are now the lowest, and Myrmidon's Agility-based Evasion is weak because of the dodge formula.
- **Skill effect sizes in `skills.json` were authored against the old formulas.** Buff/debuff "power" now means percent. Values of 20–70 are reasonable, but worth a pass.
- **Item effects (`Item.gd`) use their own fixed numbers** and weren't changed.
