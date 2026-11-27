# Economy model

`tests/economy_sim.tscn` plays out a career with the game's own reward and cost
functions and prints, per floor band: income per expedition by source, the cost
of keeping gear current, and materials in vs needed.

```
godot --headless res://tests/economy_sim.tscn -- --runs=40
```

## Assumptions (constants at the top of economy_sim.gd)

- An expedition = 2 floors x 6 waves; Press On twice, then a Breather.
- A band = 6 expeditions (about 12 in-game days).
- Keeping gear current = 6 items (weapon + 5 armor of mixed types) upgraded to
  the band's target (+3 early, +5/+6 mid, +7/+8 late; expected attempts
  included, no reinforcement) + one enchant tier on 3 items.
- Running costs: 4 health + 2 mana potions per expedition, a 15% defeat rate.
- Half of the offered wave challenges are met; a rumour is acted on every 4
  days; 2 commissions a week. Gear and leftover consumables are sold.
- Not modelled (extra sinks on top): buying gear from the shop, recipe books,
  Lost & Found buybacks, drinks, Inn rest, party loot shares.

**Target:** band income / band cost of about **1.2-2.2**: you can keep your gear
current with some money left over, but not everything at once. The unmodelled
sinks take part of the surplus.

## Before

| Floors | Income/expedition | Ratio | Main problem |
|---|---|---|---|
| 1-7 | 3,837 | 4.4 | |
| 8-14 | 18,730 | 7.1 | wave gold = (50 + 10 x wave) x floor grows linearly; costs follow item value |
| 16-22 | 43,647 | 11.3 | selling looted gear (half value) made 15k per expedition |

Commissions and rumours paid ~60-90 per expedition (didn't scale). Materials,
not gold, were the real limit: mithril 30/57, monster cores 10/21, Embershard
21/80 for enchanting.

## Changes

| What | Before | After |
|---|---|---|
| Wave gold | (50 + 10 x wave) x floor | (40 + 6 x wave) x **floor_scale** (`data/loot/gold.json`) |
| floor_scale | - | 1 + 0.3 x (floor - 1), shared by every gold source |
| Challenges / rumours / commissions | fixed or x floor | base x floor_scale (rumour base 300, challenge base 60) |
| Selling equipment | 50% of value | **20%** (`shop.json sell_fraction`); other items 50% |
| Blacksmith gold | value x 0.25 x level | value x **0.5** x level |
| Enchanter gold | value x 0.5 x tier | value x **1.0** x tier |
| Enchant to Rare / Epic | 8 mats + 1 core / 12 mats + 2 cores | 6 + 1 / **8 + 1** |
| Mithril / thick hide per wave (floor 6+) | 25% / 20% | **45% / 35%** |
| Boss Monster Core | 60% | **100%** |
| Embershard | Fairy uncommon only | Fairy common + Goblin uncommon |

## After

| Floors | Income/expedition | Band cost | Ratio | Materials (in / needed per band) |
|---|---|---|---|---|
| 1-7 | 2,594 | 7,024 | 2.2 | iron 16/18, embershard 24/20 |
| 4-10 | 4,480 | 16,948 | 1.6 | embershard 24/30, cores 14/5 |
| 8-14 | 7,359 | 33,455 | 1.3 | mithril 57/32, thick hide 45/21, embershard 40/53, cores 14/6 |
| 12-18 | 11,367 | 51,040 | 1.3 | mithril 59/57, cores 14/15, thick hide 45/38 |
| 16-22 | 17,161 | 47,351 | 2.2 | mithril 55/57, cores 14/15 |
| 20-26 | 12,133 | 42,343 | 1.7 | mithril 57/57, cores 14/15 |
| 25-31 | 14,727 | 74,312 | 1.2 | mithril 62/57, cores 14/15 |

## Still to watch

- **Gear resale is lumpy** (a legendary drop is worth a lot). At 20% it no
  longer dominates, but bands with lucky drops swing.
- **Linen and rawhide pile up** (5-10x need): cheap, so they mostly become
  sale value and commission deliveries. Fine, or trim their drop weight.
- **Monster cores** sit right at need from floor 12: every boss must drop one.
- The model assumes solo play; a party takes a loot share (PartyManager), which
  lowers the ratio by roughly the share.
