# World simulation: the Guild over years

`tests/world_sim.tscn` lets the Guild live for years while you stay in town.
It runs the real daily loop (`WorldClock.advance` → every manager's daily
tick: adventurer jobs, relations, drama, memory, Ledger, rumours,
commissions) and reports per year.

```
godot --headless res://tests/world_sim.tscn -- --years=10 --seed=1 --social=0.3
```

- `--years` (default 5), `--seed` (RNG seed), `--social`: the weekly chance
  that you befriend a random adventurer (rapport 50) - a stand-in for a player
  who visits the Tavern, so invitations, ripples and jealousy have a target.
- `WORLD|...` rows: active roster, average/max level, ranks, relations by
  status, companies, couples, grieving, avengers, memories per adventurer,
  milliseconds per simulated day, size of the saved world state.
- `WORLD YEAR EVENTS`: drama counted from the news that year. `WORLD CROWNS`:
  each year's Champion.

## What the first runs showed (Phase 4)

Before tuning (10 years, seed 1):

| Problem | Seen |
|---|---|
| The world froze | deaths fell to ~0 a year after year 5; by year 10, 13 of 19 adventurers were S-rank |
| Veterans never failed | job success capped at 97% and veterans' power grows ~0.35 per level |
| Nobody quarrelled | 2 feuds and no vengeance in 10 years; drift wore away small clashes |
| Grief almost never fired | most of the dead had no friend at 40+ |

Changes:

| Change | Where |
|---|---|
| Job success cap 0.97 → **0.93** | `adventurers.json` jobs.success_max |
| **Careers end**: past 4 years with the Guild, 1% x (years past prime) a week to retire; a retiring partner may take theirs along | `adventurers.json` settings.career, `AdventurerManager._career_week`, `DramaManager.on_retire` |
| Clashing traits x**2** at town meetings (compatible x2 already) | `social.json` relations.clash_mult |
| Ledger neighbours (within 2 places) **-1** affinity a week | relations.events.ledger_neighbour_week |
| Shared job success +6 → **+4** | relations.events.job_success |
| Grief for anyone at affinity **30+** (was friends, 40+) | drama.grief.min_affinity |
| Feud confrontation 5% → **8%** a week, invitations 6% → **4%** a day | drama.feuds / drama.invitations |

## After tuning (10 years, `--social=0.3`, seeds 1-3)

| | seed 1 | seed 2 | seed 3 |
|---|---|---|---|
| Deaths / retirements | 13 / 17 | 17 / 27 | 29 / 27 |
| Newcomers | 47 | 58 | 68 |
| Ranks at year 10 | F1 E4 D6 C3 B4 A1 S1 | F1 E1 D3 C4 B6 A4 S1 | F2 E3 D6 C6 B1 S1 |
| Feuds begun / brawls / killings | 16 / 1 / 1 | 13 / 0 / 0 | 6 / 4 / 1 |
| Companies / romances | 3 / 3 | 14 / 7 | 6 / 6 |
| Vengeance oaths / grief retirements / hardened | 0 / 0 / 0 | 0 / 0 / 0 | 2 / 0 / 3 |
| Champions | 2 | 5 | 3 |
| ms per day / state | ~29 ms / ~80 KB | ~28 ms / ~85 KB | ~30 ms / ~83 KB |

Reading it:
- The Guild now **turns over**: a mix of ranks every year, 2-4 deaths and
  2-3 retirements a year, newcomers to replace them. Champions change (a
  legend can still hold the crown for years - that's someone for you to beat).
- Seeds differ in **temperament** - one Guild is clannish (14 companies, 7
  romances), another quarrelsome (16 feuds). That's the point: each world has
  its own character.
- Grief, vengeance and killings stay **rare** - most deaths are of people with
  no close friends. They should feel like events when they happen. If they
  feel too rare in play, lower `drama.grief.min_affinity` or raise
  `fates.death_chance` for veterans.
- Cost is flat: ~30 ms per simulated day (the expensive part is real
  AutoBattler fights for boss jobs, trials and brawls) and the saved world
  levels off around 80 KB thanks to the caps (8 relations each, 20 memories
  each, 30 departed kept, 40 news).

## Known gaps

- Champions who hold the crown for 6-8 years: fine for now (Defend), but if
  it feels static, make veterans' retirement chance scale with rank too.
- Memories per adventurer stay low (1-3): most fade. Strong ones (rescues,
  killings) persist, which is what matters for behaviour.
- The sim's player is passive apart from `--social`; your own actions (gifts,
  rescues, bounties) add more memories and ripples in real play.
