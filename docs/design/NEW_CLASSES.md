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

- **Stats:** highest VIT, STR, END and FOR of any class; little magic. Attack from Strength.
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

- **Stats:** high MND, ARC and FAI. Spells from Arcane.
- **Gear:** dagger and talisman (ofuda-like symbols); cloth and leather.
- **Skills:**

| Skill | What it does | Idea |
|---|---|---|
| Ancestral Mending | Heal + Regeneration | healing |
| Spirit Barrier | Ally buff: Fortitude up + Reflect barrier | barriers |
| Wrath of the Ancients | Element-less magic hit on all enemies, costs MP **and** SP | primal power older than the elements; uses both pools |

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

## Noticed while doing this (not changed)
- The Cleric philosophy says "clad in mail armor", but Clerics can't wear mail (only cloth and leather).
- The Monk philosophy is about nature and animal forms, but its skills are lightning and ice.
- The Paladin is described as sword-and-shield, but it is tuned around two-handers.
