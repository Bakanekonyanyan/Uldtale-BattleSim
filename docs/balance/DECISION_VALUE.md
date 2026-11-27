# Does skilled play win more? (decision value)

Measured with `tests/balance_sim.tscn`, **paired seeds**: every policy fights the
identical battles (same hero, gear, enemies and dice), so the difference is the
decisions alone.

```
godot --headless res://tests/balance_sim.tscn -- duel --floor=10 --wave=3 --runs=25 --party=2
godot --headless res://tests/balance_sim.tscn -- compare --policies=simple,naive,smart --floor=1 --runs=40
```

`duel` = one fight from full health with a hero levelled (2 x floor) and geared
for the floor. `compare` = whole floors (attrition, Breathers) from level 1.

## The three players

| Policy | Plays like |
|---|---|
| **simple** | Strongest affordable damage skill on the first enemy in the list. Heals itself when low. No focus fire, combos, buffs, Defend or Link play. |
| **naive** | Focus fire on the weakest enemy, combos, buffs and debuffs every fight. |
| **smart** | naive + reads the fight: set-ups only when the fight is long enough to pay them back, Perfect Guard against big or charged hits, heals allies, finishes and builds Breaks on weaknesses, Unison Strike. |

## What we found first (before tuning)

- Floor runs, floor 1: simple 26%, naive 28%, smart 29% - no real difference.
- Single fights, floor 5 regular wave: **simple 82% > smart 73%**. Fights were
  ~8 turns (3-4 hero actions), so every non-damage turn was a loss: buffs and
  debuffs cost 13 points, Perfect Guard and Break-building were neutral.
- Conclusion: tempo beat tactics. Two causes: the "smart" player spent turns
  on set-ups in fights too short to pay them back, and the mechanics barely
  punished ignoring the panels.

## Changes

1. **Smart policy**: set-ups only when the fight needs 4+ more hero actions
   (`AutoBattler.hero_actions_left`); Perfect Guard only against a charge, a
   hit worth 45%+ of current HP, or one that would Break you; heals allies.
2. **Weakness bonus** (`combat.json weakness_bonus` 0.3): hits on a weakness
   (damage type or element) deal +30%, on top of the affinity.
3. **Regular charge-ups** (`intents.regular_charge_chance` 0.3, min power 30):
   regular enemies sometimes wind up a heavy skill you can see coming.
4. **Charged strikes** hit x2.0 (was 1.5): ignoring a telegraph hurts;
   Perfect Guard takes it to 0.5x.

## Results now (win %, paired, 25 runs x 12 classes)

| Fight | simple | naive | smart | smart - simple |
|---|---|---|---|---|
| Solo, floor 5 regular wave | 84 | 75 | 89 | +5 |
| Solo, floor 5 boss | 65 | 70 | 78 | **+13** |
| Solo, floor 10 boss | 51 | 61 | 63 | **+12** |
| Party of 3, floor 10 regular wave | 46 | 66 | 81 | **+35** |
| Party of 3, floor 10 boss | 83 | 97 | 97 | **+14** |

Party of 3, floor 10 wave before the mechanic changes: simple 43, smart 70 (+27).

## Reading it

- Skill clearly wins in **boss fights** and **party play**, and smart parties
  also finish with more HP (37% vs 19% on floor 10 waves).
- **Solo regular waves** stay mostly tempo (+5): 3-4 actions leave little room
  for decisions. That's acceptable for fodder waves; if you want more there,
  the levers are longer regular fights (enemy HP) or more dangerous
  telegraphs (`regular_charge_chance`, `charge_power_mult`).
- **naive** (buffs every fight) is often worse than simple: knowing *when*
  to set up is the skill.
- Floor 10 solo regular waves are hard for every policy (~30%) with a hero at
  level 20: worth a look in the difficulty pass.
