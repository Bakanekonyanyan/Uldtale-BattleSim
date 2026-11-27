# Difficulty curve

Measured with the **career** simulation: a hero starts at level 1 on floor 1
and climbs, rebuilt each floor at its current level with gear for that floor
(a player who keeps their gear current, but without Blacksmith upgrades or
enchants), playing the real floor loop (6 waves, Breathers below 50% HP,
2 potions, smart policy). A failed floor is retried, up to 4 times.

```
godot --headless res://tests/balance_sim.tscn -- career --floors=25 --runs=10
```

Tuning lives in `data/progression.json` (Content Manager tab **Progression**).

## Before

| Floor | Hero level | First-try clear | Still climbing |
|---|---|---|---|
| 1-4 | 1-11 | 84-94% | 100% |
| 7 | 16.5 | 35% | 92% |
| 9 | 18.3 | 8% | 35% |
| 10 | 19 | 14% | **7%** |

A wall at floors 6-9; almost nobody passed floor 10 of 25. Two causes:
- **XP stalled heroes near level 20**: XP per level grew 1.5x per level
  (level 20 needed ~867,000 XP).
- **Enemies scaled twice**: a level per floor *and* a floor multiplier that
  accelerated to 13.5x at floor 25.

## Changes

- **XP curve** (`xp`): quadratic, 100 + 40 x (L-1) + 30 x (L-1)^2 per level.
  Levelling slows steadily instead of stopping.
- **Enemy floor multiplier** (`enemy_floor_mult`): auto-calibrated against
  targets with the career sim (two rounds), then smoothed:
  0.9 -> 1.65 by floor 4, a gentle 1.7-1.9 through floor 17, 2.05-2.32 for
  floors 18-25. Enemy level, gear and talents still rise every floor, so
  deeper is always harder.

Targets (smart solo player, gear current, no upgrades): first-try clears
~85% on floors 1-3, ~75% on 4-10, ~65% on 11-20, ~55% on 21-25.

## After (10 careers x 12 classes)

| Floors | First-try clear | Attempts | Still climbing |
|---|---|---|---|
| 1-4 | 78-85% | ~1.2 | 100% |
| 5-11 | 65-77% | 1.3-1.5 | 98-100% |
| 12-21 | 50-74% | 1.3-1.8 | 78-97% |
| 22-25 | 49-54% | 1.9-2.0 | **59% reach floor 25** |

Real players also upgrade and enchant gear, buy potions and bring a party,
so they'll do better than the sim; Omens make it harder by choice.

## Notes

- **Hero levels run high**: about 3.7 levels per floor, ~95 at floor 25.
  Harmless for balance (the curve was calibrated with it), but if you want
  smaller numbers, raise `xp.per_level_sq` and re-run the calibration
  (`tools/calibrate.py` approach: run career, nudge each floor's multiplier
  toward its target, repeat).
- The decision-value duels (DECISION_VALUE.md) assumed level = 2 x floor;
  real levels are now higher, so re-run those before tuning combat again.

## Class depth check (forks, arts, armour training)

Careers from level 1 to floor 12 (`balance_sim -- career --classes=X --floors=12 --runs=N --tries=3`),
before class depth (ed37e40) vs after. N=10 for all classes, N=30 for the ones that moved.

- Healers gained most (heals now apply their statuses; party-wide fork options):
  Kannagi F12 first-try 65% -> 86% (N=30), Druid and Cleric up sharply (N=10).
- Paladin and Berserker are fine at depth; their floor-1 dips were noise.
- Armour training first cost Beastmasters and casters: NPC/sim builds still
  picked gear by the old class lists and wore untrained pieces. Fixed: builds
  pick trained armour; Beastmaster trained in mail, Necromancer in leather.
  Beastmaster F12 reached 86% -> 100%, first-try 69% -> 60%; Necromancer F12
  reached 70% -> 66%, first-try 57% -> 45% (N=30, within noise).
- Shinobi F12 first-try 89% -> 69% (N=30): worth a look in a class tuning pass.
  Note the sim's heroes all share a name, so their fork picks are identical
  per class - a tuning pass should compare both options of each fork.

## Class tuning pass: fork options (A vs B)

`balance_sim -- career --forks=a|b` forces one side of every fork (A = the
alphabetically first option). 20 careers per class and side, level 1 to floor
12. First-try clear % at floor 12, A / B:

| Class | First run | After tuning |
|---|---|---|
| Paladin | 65 / 95 | 75 / 85 |
| Druid | 77 / 31 | 88 / 69 |
| Elementalist | 31 / 61 | 57 / 61 |
| Necromancer | 81 / 28 | 62 / 57 |
| Beastmaster | 90 / 66 | 75 / 55 (within noise) |
| Samurai, Berserker, Monk, Shinobi, Myrmidon, Cleric, Kannagi | within ~12 points | - |

Changes:
- **Spread mutations** (every foe / every ally at reduced power) now pay their
  power cost only when they reach more than one target: alone, or against a
  lone boss, they hit at full power. Party picks no longer punish solo play.
- Druid *Rabid Bear*: +8% physical lifesteal (sustain to match Den Mother).
- Necromancer *Sanguine Pact* 10% HP for x1.45 (was 12% for x1.3); *Blood
  Return* lifesteal 20% (was 25%); *Undying* -14%; *Hexweaver* +12% status
  chance; *Perfect Vessel* also heals 10%.
- Elementalist *Prismatic Split* 75% per target (was 60%); *Searing Focus* and
  *Storm Caller* +8% (was 6%).

## Rookie pass: the combat rhythm (this week)

**Problem.** Combat was easy, and spamming skills was as good as playing
well:
- A normal wave on floor 1 ended in 2–3 hero actions.
- "Always cast the strongest skill" won 98–100% of normal waves, as often as
  careful play did.
- Skills never ran dry, and attacking or defending was just filler.

**Changes:**
- **Combat rhythm** (`combat.json` "rhythm", Content Manager → Combat):
  - Heroes pay 1.6× a skill's listed MP/SP, rising 10% per level, so costs
    keep pace with growing pools. Two or three skills, then you need to
    recover.
  - A basic attack restores 12% of max MP and SP (was 8%). A Defend restores
    15%.
  - A Perfect Guard sets up a riposte: +30% on your next action.
  - A basic attack on a weakness puts 2 points on the Break meter (skills
    put 1).
  - Normal enemies telegraph heavy blows more often (chance 0.4, from
    power 20).
- **Skills by level** (`progression.json` class_skill_levels `[1, 3, 6]`): a
  rookie knows one class skill, learns the second at level 3 and the rest at
  level 6. The level-up screen announces each one.
- **Sturdier normal enemies** (`enemy_archetypes.json` scaling
  `enemy_hp_mult` 0.5 → 0.8): a normal wave now lasts 4–6 hero actions and
  costs real HP.
- **Recalibrated floor multipliers** (`progression.json`
  `enemy_floor_mult`): auto-calibrated with the career sim toward these
  first-try targets for a smart solo hero:
  - floors 1–10: 60%
  - floors 11–20: 55%
  - floors 21–25: 50%
  The deep floors were then laid on a smooth rise (survivors skew the deep
  numbers).

**Career, smart solo, 2 potions** (10 runs × 12 classes):

| Floors | First-try clear | Still climbing |
|---|---|---|
| 1–5 | 59–67% | 99–100% |
| 6–11 | 54–66% | 86–98% |
| 12–17 | 37–55% | 60–84% |
| 18–25 | 50–73% | 40–53% |

Solo is meant to be hard. Rookies hire help at the Tavern (F: 1, E: 2), and
from D-rank they form a permanent team.

**Decision value now** (duels, paired seeds, 20 runs × 12 classes, hero at
career level):

| Fight | Attack only | Skill spam | Smart |
|---|---|---|---|
| Floor 1 normal wave | 87% | 85% | **95%** |
| Floor 1 boss | 15% | 19% | **31%** |
| Floor 3 boss | 34% | 43% | **65%** |
| Floor 5 boss | 58% | 73% | **86%** |
| Floor 10 boss | 88% | 98% | 98% |

Skills matter, but so do timing, guarding and recovering. Skill spam no
longer matches careful play.

**Still to look at:** the floor-10 boss is too easy for a level-33 hero
(98%). Boss scaling (`boss_hp_mult`, `boss_damage_mult`) needs a pass for
the middle floors.
