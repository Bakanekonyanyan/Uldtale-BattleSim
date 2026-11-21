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
