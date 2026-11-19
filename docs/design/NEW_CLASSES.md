# New classes: Berserker, Shinobi, Kannagi, Beastmaster

Built from `docs/lore/CLASS_PHILOSOPHIES.md` using only systems the game already has. Each class has three skills, like the original eight.

Larger ideas from the philosophies that need new systems are listed under **Later**:
- talents
- stances and forms
- summons
- stealth
- ultimates

## Berserker (Warden): Howl of the War Wolf, Arathorn and Fenrisulfr
Massive weapons, area damage, lifesteal, a frenzy that grows in battle, high health.

- **Stats:** high VIT, STR, END and FOR; little magic. Attack from Strength.
- **Gear:** greatsword, great hammer, spear, mace, short sword; mail and plate.
- **Skills:**

| Skill | What it does | Idea |
|---|---|---|
| Cleave | Physical hit on all enemies, may Bleed | AoE with massive weapons |
| Blood Feast | Physical HP drain (60% healed back) | lifesteal |
| Wolf's Frenzy | Self buff: Strength up + Enraged | the frenzy |

- **Combos:** Cleave with a greatsword pays off Open Wound on bleeding enemies (including its own Bleeds).
- **Later (talents):** rage that builds each turn; Momentum bonuses.

## Shinobi (Martialist): Kagekiri Clan, Tsukuyomi
Stealth, speed, elemental ninjutsu (fire, water, lightning, shadow), kunai and smoke bombs.

- **Stats:** highest DEX and AGI; some INT for ninjutsu. Attack from Dexterity, spells from Intelligence.
- **Gear:** dagger and short sword (both dual-wield), cloth and leather.
- **Skills:**

| Skill | What it does | Idea |
|---|---|---|
| Lightning Kunai | Pierce + Lightning hit, may Shock | thrown kunai with raiton |
| Water Dragon Jutsu | Water debuff hit: always Soaks, lowers Agility | suiton |
| Smoke Bomb | Blinds all enemies | vanish in smoke |

- **Combos:** Water Dragon Jutsu, then Lightning Kunai = **Conduction** (x1.5).
- **Later (talents):** stealth (untargetable for a turn), fire and shadow techniques, shuriken.

## Kannagi (Mender): Path of the Ancients, the Ancient (Eternal) Ones
Bridge to the Ancient Ones: barriers, healing, mana and stamina, devastating spells.

- **Stats:** high MND, ARC and FAI. Attacks and spells from Arcane.
- **Gear:** dagger and talisman (ofuda-like symbols); cloth and leather.
- **Skills:**

| Skill | What it does | Idea |
|---|---|---|
| Ancestral Mending | Heal + Regeneration | healing |
| Spirit Barrier | Ally buff: Fortitude up + Reflect barrier | barriers |
| Wrath of the Ancients | Element-less magic hit on all enemies | primal power older than the elements |

- **Later (talents):** transfer MP and SP between allies; seals; party barriers once parties exist.

## Beastmaster (Sorcerer): Circle of the Verdant Heart, Fenrisulfr
Pacts with legendary beasts; channels them through the body (claws, fangs, wings).

- **Stats:** balanced; Arcane drives attack and spells, like the Druid.
- **Gear:** spear, short sword, mace, dagger (dual-wield); leather and mail.
- **Skills:**

| Skill | What it does | Pact |
|---|---|---|
| Fenris Rend | Slash claw hit, may Bleed | Fenrisulfr (strength) |
| Manticore Sting | Pierce debuff hit: always Poisons, lowers Fortitude | Manticore (ferocity) |
| Behemoth Hide | Self buff: Endurance + Fortitude up | Behemoth (defense) |

- **Combos:** Manticore Sting and Fenris Rend both pay off **Open Wound** on bleeding targets. Its Poison sets up **Blight** for a Necromancer ally.
- **Later (talents):** the Roc pact (speed); summoned beasts once there is a party or summon system.

## Element changes made with these classes
- **Water** is a new element. The **Soaked** status (−2 Agility) sets up two combos: **Conduction** (Soaked + Lightning, x1.5) and **Flash Freeze** (Soaked + Ice, x1.35). Djinn are weak to Water.
- **Damage-over-time statuses have elements:** Burn = Fire, Freeze = Ice, Shock = Lightning, Poison = Earth. Resistances and weaknesses now apply to their ticks.
- **Bushido** (Samurai) has no element; it's a physical self-buff.

## Existing classes aligned with their philosophies
- **Cleric:** can wear mail (not plate).
- **Monk:** animal-style kit: Tiger Claw (Slash, Bleed), Mantis Strike (debuff that always Confuses), Crane Stance (Agility + Evasive).
  - Fists are Blunt.
  - Combos: Tiger Claw pays off its own Bleeds (Open Wound); any hit after Mantis Strike is a Sucker Punch.
  - The old Fists of Thunder, Ice Splitter and Meditation remain in skills.json, unused, for enemies or talents.
- **Paladin:** sword and board first, two-handers allowed.
  - Drops lean toward short sword, mace, buckler and great shield.
  - Holy Strike does x1.2 with a shield.
  - Great katana removed (it's the Samurai's).
- **Berserker:** drops lean toward great axe, greatsword and great hammer; Cleave and Blood Feast do x1.25 with any two-hander.
- **Samurai:** Iaido does x1.2 with a katana or great katana.

## Weapon variety
Every class can use at least three main-hand weapon types.
- **New weapons:**
  - Axe (one-handed, Slash)
  - Katana (one-handed, Slash)
  - Great Axe (two-handed, Slash)
  - Staff (two-handed, Blunt, +6 spell power)
- **`preferred_weapons`** (per class, in classes.json) only biases drops (75% of usable drops come from the list). Players can still equip anything their class allows.
- **`weapon_bonus`** (per skill) is a damage multiplier while wielding a weapon id or type.
- **Fix:** off-hand sources' `spell_power` (Tome, Talisman, Fetish, Relic: +10) was never applied; it is now.

## Balance (sim, floor-1 full runs, 300 per class, best play style)
| Class | Clear rate |
|---|---|
| Berserker | 31% |
| Shinobi | 31% |
| Kannagi | 19% |
| Beastmaster | 20% |
| Monk (new kit) | 15% |

The original eight classes range from 13% (Druid) to 31% (Samurai). Tuning passes:
- **Berserker:** 65% → 31%. Core stats lowered from 13 to 10, Blood Feast heals 40% of damage (was 60%), Cleave power 20.
- **Kannagi:** 6% → 19%. Attacks scale off Arcane; Wrath of the Ancients power 45 with a 2-turn cooldown.

Note: the game charges only one resource per skill (MP for magical, SP for physical), so the SP listed on Wrath of the Ancients is not actually paid.
- **Shinobi:** Lightning Kunai power 30.
