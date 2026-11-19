# Talent trees

Generated from `data/talents.json` by `tools/talent_doc.py`. Edit the data (content manager **Talents** tab) and re-run.
Engine: `scripts/resources/TalentManager.gd`. Lore: `docs/lore/CLASS_PHILOSOPHIES.md`, `docs/lore/ABILITY_TYPES.md`.

## Rules
- **Points:** 1 talent point per level from level 2.
- **Branches:** each class has 3 branches of 5 tiers.
  - Points needed in a branch before each tier opens: [0, 2, 4, 6, 8].
  - Every branch follows the same pattern: tier 1 passive, tier 2 **skill**, tier 3 and 4 passives (one usually upgrades a skill or combo), tier 5 **ultimate**.
- **Passives** have up to 3 ranks; the numbers below are per rank.
- **Skill nodes** add the skill and put it in the loadout if there's room.
- **Loadout:** 6 equipped skills are usable in battle. Choose them on the Talents screen (Town → Talents).
- **Respec:** costs 100 copper × level and refunds everything.
- **Players = enemies:** the same engine runs for enemies, which have no talents yet.

## New set-up statuses and signature combos
- **Staggered** (−3 Agility, −10% dodge): shield bashes, kicks, charges, war cries.
- **Marked** (no penalty by itself): marks, pins, studying the foe.
- **Sealed** (−3 Intelligence and Mind): Kannagi seals.

| Class | Signature combo | Set-up | Payoff | x |
|---|---|---|---|---|
| Paladin | Sanctified Strike | Staggered | elements: HOLY | 1.35 |
| Samurai | Decisive Cut | Marked | damage types: SLASH | 1.4 |
| Berserker | Bloodbath | Bleed | skills: Rampage, Fenrisulfr's Maw | 1.5 |
| Monk | Pressure Break | Staggered | damage types: BLUNT | 1.35 |
| Shinobi | Assassinate | Marked | damage types: PIERCE | 1.45 |
| Myrmidon | Exploit Opening | Staggered | damage types: SLASH, PIERCE | 1.3 |
| Druid | Bramble Burst | Bleed | elements: EARTH | 1.3 |
| Cleric | Purge | Burn | elements: HOLY | 1.3 |
| Kannagi | Exorcism | Sealed | ability types: MAGICAL | 1.35 |
| Elementalist | Steam Burst | Soaked | elements: FIRE | 1.35 |
| Beastmaster | Manticore's Venom | Poison | damage types: SLASH | 1.35 |
| Necromancer | Dread | Blind | elements: DARK | 1.3 |

## Wardens

### Paladin

**Bulwark**: Sword and board: the shield of the party.

| Tier | Node | Ranks | Effect |
|---|---|---|---|
| 1 | Shield Discipline | 3 | +3 toughness; -2% damage taken (with a shield). *Drilled behind the shield in the Grand Cathedral.* |
| 2 | Shield Bash | 1 | **Skill: Shield Bash** (Basic; debuff; enemy; power 25; 15 SP; cd 2; applies staggered; Blunt; x1.3 with shield). Slam your shield into the foe, knocking it off balance. |
| 3 | Bastion | 3 | -4% damage taken (with a shield); +1 fortitude. *Your guard becomes a wall.* |
| 4 | Unbreakable | 2 | -10% damage taken (below 40% HP). *When the line is about to break, you hold.* |
| 5 | Aegis of Dawn | 1 | **Skill: Aegis of Dawn** (Ultimate; buff; self; power 60; 40 MP; cd 8; applies reflect, regeneration). Solara's light hardens into a radiant aegis that heals and turns blows back. |

**Crusader**: Holy offense; two-handers welcome.

| Tier | Node | Ranks | Effect |
|---|---|---|---|
| 1 | Righteous Fury | 3 | +4% damage (Holy). *Your strikes carry the Radiant Dawn.* |
| 2 | Radiant Cleave | 1 | **Skill: Radiant Cleave** (Advanced; damage; all enemies; power 30; 25 SP; cd 3; applies blind; Holy; x1.2 with two handed). A sweeping blow trailing holy light that dazzles every foe. |
| 3 | Zeal | 3 | +5% damage (with a two handed, physical attacks). *Fervor behind a great blade.* |
| 4 | Sanctified Blows | 2 | Sanctified Strike +0.15x; Judgement +0.1x. *Strike the reeling and the blinded with judgement.* |
| 5 | Solara's Verdict | 1 | **Skill: Solara's Verdict** (Ultimate; damage; enemy; power 110; 45 MP; cd 8; applies blind; Holy). Call down the full judgement of the Radiant Dawn on one foe. |

**Devotion**: Faith that mends and protects.

| Tier | Node | Ranks | Effect |
|---|---|---|---|
| 1 | Faithful | 3 | +2 faith. *Unwavering faith.* |
| 2 | Lay on Hands | 1 | **Skill: Lay on Hands** (Basic; heal; ally; power 45; 25 MP; cd 3). Mend an ally's wounds with a touch of Solara's grace. |
| 3 | Dawn's Mercy | 3 | +6% healing. *Your healing burns brighter.* |
| 4 | Radiant Aura | 2 | regen 2% HP per turn. *Light lingers around you.* |
| 5 | Dawn's Embrace | 1 | **Skill: Dawn's Embrace** (Ultimate; heal; ally; power 120; 50 MP; cd 8; applies regeneration). Wrap an ally in the dawn itself: a great heal that keeps on mending. |

### Samurai

**Iai**: The art of the draw: one perfect cut.

| Tier | Node | Ranks | Effect |
|---|---|---|---|
| 1 | Swift Draw | 3 | +3% critical hit rate. *The blade is out before the eye can follow.* |
| 2 | Flash Draw | 1 | **Skill: Flash Draw** (Link; damage; enemy; power 25; 15 SP; cd 1; applies bleed; Slash; x1.2 with katana, x1.2 with great katana). A lightning-quick draw cut that opens a bleeding wound. |
| 3 | Iai Mastery | 3 | Iaido: +10 power. *Years of drawing the same cut.* |
| 4 | Killing Intent | 2 | +8% damage (Slash hits, vs bleed). *A wounded foe is a finished foe.* |
| 5 | Thousand Cuts | 1 | **Skill: Thousand Cuts** (Ultimate; damage; all enemies; power 90; 50 SP; cd 8; applies bleed; Slash; x1.2 with katana, x1.2 with great katana). A storm of draws too fast to see, cutting every foe. |

**Bushido**: Discipline and inner spirit.

| Tier | Node | Ranks | Effect |
|---|---|---|---|
| 1 | Discipline | 3 | +2 endurance, +2 mind. *Body and mind tempered alike.* |
| 2 | Kiai | 1 | **Skill: Kiai** (Basic; debuff; all enemies; power 20; 20 SP; cd 4; applies staggered). A spirit shout that shakes the enemy's footing. |
| 3 | Unshaken | 3 | +2 toughness, +2 spell ward. *Composure in any storm.* |
| 4 | Code of Honor | 2 | Bushido: +10 power, +1 duration. *The creed burns longer.* |
| 5 | Spirit of Amakiri | 1 | **Skill: Spirit of Amakiri** (Ultimate; buff; self; power 60; 50 SP; cd 8; applies enraged, evasive). Channel the founder's spirit: speed, strength and a blade no one can touch. |

**Kenjutsu**: Reading the opponent; the great katana.

| Tier | Node | Ranks | Effect |
|---|---|---|---|
| 1 | Blade Form | 3 | +4% damage (Slash hits). *Clean, precise forms.* |
| 2 | Read the Opponent | 1 | **Skill: Read the Opponent** (Basic; debuff; enemy; power 20; 15 SP; cd 3; applies marked). Study the foe and find the opening for a decisive cut. |
| 3 | Parry | 3 | +3% dodge. *Turn the blade aside.* |
| 4 | Decisive Strike | 2 | Decisive Cut +0.15x. *When the opening comes, end it.* |
| 5 | Heaven Splitter | 1 | **Skill: Heaven Splitter** (Ultimate; damage; enemy; power 130; 55 SP; cd 8; Slash; x1.25 with great katana). One overhead cut said to split the sky. |

### Berserker

**Carnage**: Massive weapons, wide arcs.

| Tier | Node | Ranks | Effect |
|---|---|---|---|
| 1 | Heavy Hands | 3 | +5% damage (with a two handed). *The heavier the weapon, the better.* |
| 2 | Whirlwind | 1 | **Skill: Whirlwind** (Advanced; damage; all enemies; power 30; 25 SP; cd 3; applies staggered; x1.25 with two handed). Spin with your weapon, battering everything around you. |
| 3 | Sundering | 3 | +5% armor penetration. *Armor means little to you.* |
| 4 | Cleave Mastery | 2 | Cleave: +10 power. *Wider, deeper cleaves.* |
| 5 | Berserker Rage | 1 | **Skill: Berserker Rage** (Ultimate; buff; self; power 70; 60 SP; cd 8; applies enraged). Enter a wild rage that massively boosts strength and endurance while becoming enraged. |

**Bloodlust**: Fenrisulfr's hunger: lifesteal and frenzy.

| Tier | Node | Ranks | Effect |
|---|---|---|---|
| 1 | Thirst | 3 | heal 3% of damage dealt. *Every wound you deal feeds you.* |
| 2 | Rampage | 1 | **Skill: Rampage** (Advanced; damage; enemy; power 45; 25 SP; cd 2; applies bleed; x1.2 with two handed). A savage flurry against one foe; devastating on a bleeding target. |
| 3 | Frenzy | 3 | +4% damage (below 50% HP). *Pain makes you stronger.* |
| 4 | Feast of Wolves | 2 | Blood Feast: +10 power. *Blood Feast tears deeper.* |
| 5 | Fenrisulfr's Maw | 1 | **Skill: Fenrisulfr's Maw** (Ultimate; drain; all enemies; power 70; 50 SP; cd 8; x1.2 with two handed). The Wild Father's jaws close on every foe and drink deep. |

**War Wolf**: The tank that will not fall.

| Tier | Node | Ranks | Effect |
|---|---|---|---|
| 1 | Thick Hide | 3 | +4% max HP, +2 toughness. *Scarred and hardened.* |
| 2 | War Howl | 1 | **Skill: War Howl** (Basic; debuff; all enemies; power 25; 20 SP; cd 4; applies staggered). Howl like the war wolf; foes lose their nerve and footing. |
| 3 | Iron Will | 3 | -4% damage taken. *Shrug off blows.* |
| 4 | Last Stand | 2 | -12% damage taken (below 30% HP). *Hardest to kill when nearly dead.* |
| 5 | Second Wind | 1 | **Skill: Second Wind** (Ultimate; heal; self; power 100; 40 SP; cd 8; applies regeneration). Rise again from the brink with a roar. |

## Martialists

### Monk

**Tiger**: Power: the tiger's ferocity.

| Tier | Node | Ranks | Effect |
|---|---|---|---|
| 1 | Tiger's Strength | 3 | +2 strength; +3% damage (physical attacks). *Muscle like coiled springs.* |
| 2 | Ox Kick | 1 | **Skill: Ox Kick** (Basic; debuff; enemy; power 25; 15 SP; cd 2; applies staggered; Blunt). A low, heavy kick that takes the legs out from under the foe. |
| 3 | Ferocity | 3 | +3% critical hit rate. *Strike where it hurts.* |
| 4 | Rending Claws | 2 | Tiger Claw: +10 power. *Tiger Claw tears deeper.* |
| 5 | Five Animal Fury | 1 | **Skill: Five Animal Fury** (Ultimate; damage; enemy; power 120; 50 SP; cd 8; applies bleed; Blunt). Tiger, crane, mantis, ox and serpent in one devastating sequence. |

**Crane**: Grace: balance, evasion and counters.

| Tier | Node | Ranks | Effect |
|---|---|---|---|
| 1 | Crane's Grace | 3 | +2 agility, +2% dodge. *Light as a feather.* |
| 2 | Crane Wing Sweep | 1 | **Skill: Crane Wing Sweep** (Advanced; damage; all enemies; power 25; 20 SP; cd 3; applies confused; Wind; Blunt). Sweeping wing strikes that spin every foe around. |
| 3 | Flowing Water | 3 | +2% dodge, +2% accuracy. *Move like water around the blow.* |
| 4 | Counterflow | 2 | +10% damage (vs confused). *Punish the off-balance.* |
| 5 | Heavenly Crane | 1 | **Skill: Heavenly Crane** (Ultimate; buff; self; power 60; 40 SP; cd 8; applies evasive, regeneration). Become untouchable: soaring agility and a body that mends itself. |

**Verdant Heart**: Harmony with Elandria, Nimue and Fenrisulfr.

| Tier | Node | Ranks | Effect |
|---|---|---|---|
| 1 | Inner Harmony | 3 | regen 1% HP, 2% SP per turn. *Breath and body in balance.* |
| 2 | Earth Mother's Palm | 1 | **Skill: Earth Mother's Palm** (Basic; damage; enemy; power 35; 20 SP; cd 2; applies poison; Earth; Blunt). A palm strike carrying Elandria's weight; it can shatter what is frozen. |
| 3 | Spirit Weave | 3 | +2 mind, +2 spell ward. *Nimue's flow guards the mind.* |
| 4 | Balance | 2 | Mantis Strike: +10 power. *Mantis Strike lands truer.* |
| 5 | Nimue's Tide | 1 | **Skill: Nimue's Tide** (Ultimate; heal; self; power 100; 30 MP; cd 8; applies regeneration; Water). Let the Spirit Weaver's tide wash through you, healing deep wounds. |

### Shinobi

**Kage**: Shadow arts and assassination.

| Tier | Node | Ranks | Effect |
|---|---|---|---|
| 1 | Silent Steps | 3 | +2% dodge, +2% critical hit rate. *Unheard, unseen.* |
| 2 | Shadow Mark | 1 | **Skill: Shadow Mark** (Basic; debuff; enemy; power 20; 15 SP; cd 3; applies marked; Dark). Brand the target with Tsukuyomi's shadow; it cannot hide from you. |
| 3 | Lethality | 3 | +5% damage (Pierce hits). *Every thrust finds a vital point.* |
| 4 | Assassin | 2 | Assassinate +0.15x. *The marked die quickly.* |
| 5 | Moonless Night | 1 | **Skill: Moonless Night** (Ultimate; damage; enemy; power 130; 50 SP; cd 8; Dark; Pierce). Vanish into darkness and strike once, perfectly. |

**Ninjutsu**: Fire, water and lightning techniques.

| Tier | Node | Ranks | Effect |
|---|---|---|---|
| 1 | Chakra Flow | 3 | +2 intelligence, +2 spell power. *Energy guided through the seals.* |
| 2 | Phoenix Flower | 1 | **Skill: Phoenix Flower** (Advanced; damage; all enemies; power 30; 25 MP; cd 3; applies burn; Fire). Fire release: a spray of burning flowers. |
| 3 | Elemental Affinity | 3 | +5% damage (Fire/Water/Lightning). *Your elements answer faster.* |
| 4 | Conductor | 2 | Conduction +0.15x. *Water and lightning, perfected.* |
| 5 | Raijin's Descent | 1 | **Skill: Raijin's Descent** (Ultimate; damage; all enemies; power 85; 50 MP; cd 8; applies shock; Lightning). Lightning release: the storm god's strike falls on every foe. |

**Shinobi Tools**: Kunai, shuriken and smoke.

| Tier | Node | Ranks | Effect |
|---|---|---|---|
| 1 | Quick Hands | 3 | Lightning Kunai: +5 power, -2 sp cost. *Throw faster, tire less.* |
| 2 | Shuriken Storm | 1 | **Skill: Shuriken Storm** (Basic; damage; all enemies; power 20; 15 SP; cd 2; applies bleed; Pierce). A fan of shuriken across every foe. |
| 3 | Vanishing | 3 | +3% dodge. *Gone before the blow lands.* |
| 4 | Poisoned Tools | 2 | +10% status chance. *Everything you throw carries something nasty.* |
| 5 | Shadow Clone | 1 | **Skill: Shadow Clone** (Ultimate; buff; self; power 60; 40 SP; cd 8; applies evasive, reflect). Split into shadow clones; foes strike the wrong you. |

### Myrmidon

**Arms Master**: Every weapon, used well.

| Tier | Node | Ranks | Effect |
|---|---|---|---|
| 1 | Weapon Training | 3 | +4% damage (physical attacks). *Iron Gauntlet drills.* |
| 2 | Disarming Strike | 1 | **Skill: Disarming Strike** (Basic; debuff; enemy; power 25; 15 SP; cd 2; applies staggered). Knock the foe's weapon aside and leave it reeling. |
| 3 | Exploit Weakness | 3 | +6% damage (on weak spots). *Switch to whatever hurts most.* |
| 4 | Opportunist | 2 | Exploit Opening +0.15x. *Never waste an opening.* |
| 5 | Blade Storm | 1 | **Skill: Blade Storm** (Ultimate; damage; all enemies; power 80; 50 SP; cd 8; applies bleed). A whirlwind of steel that cuts through every foe. |

**Skirmisher**: Two blades and quick feet.

| Tier | Node | Ranks | Effect |
|---|---|---|---|
| 1 | Light Feet | 3 | +1 agility, +2% dodge. *Never where they swing.* |
| 2 | Twin Fangs | 1 | **Skill: Twin Fangs** (Link; damage; enemy; power 30; 20 SP; cd 1; applies bleed; Pierce). Two quick thrusts that link into your next move. |
| 3 | Ambidextrous | 3 | +4% damage (with a one handed). *Light weapons, fast hands.* |
| 4 | Backstab Mastery | 2 | Backstab: +12 power. *From the shadows, deeper.* |
| 5 | Hundred Blades | 1 | **Skill: Hundred Blades** (Ultimate; damage; enemy; power 120; 55 SP; cd 8; applies bleed; Pierce). An unbroken torrent of strikes on one foe. |

**Mercenary**: Professional grit and dirty tricks.

| Tier | Node | Ranks | Effect |
|---|---|---|---|
| 1 | Battle Hardened | 3 | +2 vitality, +2 endurance, +2% max HP. *Countless contracts survived.* |
| 2 | Pinning Thrust | 1 | **Skill: Pinning Thrust** (Basic; debuff; enemy; power 20; 15 SP; cd 3; applies marked; Pierce). Pin the target in place and mark it for the kill. |
| 3 | Toxic Expertise | 3 | +5% damage (vs poison). *Your poisons, your rules.* |
| 4 | Contract Killer | 2 | +10% damage (vs marked). *The mark never escapes.* |
| 5 | Iron Gauntlet | 1 | **Skill: Iron Gauntlet** (Ultimate; buff; self; power 60; 40 SP; cd 8; applies enraged). The guild's creed made flesh: strength, precision and resolve. |

## Menders

### Druid

**Bear Form**: Elandria's bear: raw strength and resilience.

| Tier | Node | Ranks | Effect |
|---|---|---|---|
| 1 | Ursine Hide | 3 | +3% max HP, +3 toughness. *Thick fur and thicker skin.* |
| 2 | Bear Form | 1 | **Skill: Bear Form** (Advanced; buff; self; power 40; 20 SP; cd 6). Take the shape of a great bear: stronger, tougher, harder to kill. |
| 3 | Maul | 3 | +5% damage (physical attacks). *Claws and crushing paws.* |
| 4 | Thick Fur | 2 | -6% damage taken. *Blows sink into fur.* |
| 5 | Elder Bear | 1 | **Skill: Elder Bear** (Ultimate; damage; all enemies; power 80; 45 SP; cd 8; applies staggered; Earth; Blunt). Become the elder bear and crash into every foe. |

**Alraune**: The flower spirit: healing and control.

| Tier | Node | Ranks | Effect |
|---|---|---|---|
| 1 | Verdant Bloom | 3 | +6% healing. *Growth answers your call.* |
| 2 | Alraune's Kiss | 1 | **Skill: Alraune's Kiss** (Basic; heal; ally; power 40; 25 MP; cd 3; applies regeneration). A blossom's kiss that heals and keeps healing. |
| 3 | Thorned Vines | 3 | +5% damage (Earth). *The earth bites back.* |
| 4 | Strangling Roots | 2 | +10% damage (vs poison). *Poisoned prey wither faster.* |
| 5 | Garden of Elandria | 1 | **Skill: Garden of Elandria** (Ultimate; heal; ally; power 110; 50 MP; cd 8; applies regeneration, reflect). Raise a living garden that heals and shields. |

**Wildcaller**: Storms, frost and thorns of the wild.

| Tier | Node | Ranks | Effect |
|---|---|---|---|
| 1 | Storm Kin | 3 | +4% damage (Ice/Wind). *Wind and frost obey you.* |
| 2 | Bramble Lash | 1 | **Skill: Bramble Lash** (Basic; damage; enemy; power 35; 20 MP; cd 2; applies bleed; Earth). Whip the foe with thorned brambles that leave it bleeding. |
| 3 | Nature's Grasp | 3 | +5% status chance. *Your effects take hold more often.* |
| 4 | Arctic Mastery | 2 | Arctic Blast: +10 power. *Arctic Blast bites harder.* |
| 5 | Wrath of the Wild | 1 | **Skill: Wrath of the Wild** (Ultimate; damage; all enemies; power 85; 50 MP; cd 8; applies freeze; Wind/Ice). A howling blizzard sweeps the battlefield. |

### Cleric

**Battle Priest**: Mace, mail and divine wrath.

| Tier | Node | Ranks | Effect |
|---|---|---|---|
| 1 | Holy Might | 3 | +2 strength; +3% damage (physical attacks). *Faith in your arm.* |
| 2 | Hammer of Dawn | 1 | **Skill: Hammer of Dawn** (Basic; damage; enemy; power 35; 20 SP; cd 2; applies staggered; Holy; Blunt; x1.2 with mace). A blessed blow that rocks the foe on its feet. |
| 3 | Crushing Faith | 3 | +5% damage (Blunt hits). *The mace is a prayer.* |
| 4 | Smite Mastery | 2 | Smite: +10 power. *Smite strikes harder.* |
| 5 | Solara's Hammer | 1 | **Skill: Solara's Hammer** (Ultimate; damage; enemy; power 120; 40 SP; cd 8; applies staggered; Holy; Blunt). Bring down the Radiant Dawn's hammer on one foe. |

**Restoration**: Healing that can mend the gravest wound.

| Tier | Node | Ranks | Effect |
|---|---|---|---|
| 1 | Healing Hands | 3 | +6% healing. *Your prayers mend more.* |
| 2 | Divine Blessing | 1 | **Skill: Divine Blessing** (Skill; buff; ally; power 60; 45 MP; cd 6; applies regeneration; Holy). Grant divine protection, greatly boosting fortitude and endurance while regenerating health. |
| 3 | Devout | 3 | +2 faith, +2 mind. *Deep, constant prayer.* |
| 4 | Blessed Light | 2 | Healing Light: +10 power. *Healing Light shines brighter.* |
| 5 | Miracle | 1 | **Skill: Miracle** (Ultimate; heal; ally; power 150; 50 MP; cd 8). A true miracle of the Dawn: an enormous heal. |

**Inquisitor**: Purging fire and judgement.

| Tier | Node | Ranks | Effect |
|---|---|---|---|
| 1 | Zeal of the Dawn | 3 | +4% damage (Holy). *Holy wrath burns hotter.* |
| 2 | Purifying Flame | 1 | **Skill: Purifying Flame** (Advanced; damage; enemy; power 35; 25 MP; cd 3; applies burn; Holy/Fire). Holy fire that sears the unclean. |
| 3 | Judgement Mastery | 3 | Judgement +0.1x; Purge +0.1x. *The blinded and burning are judged harder.* |
| 4 | Heretic Bane | 2 | +10% damage (vs burn). *The burning heretic falls.* |
| 5 | Dawnfire | 1 | **Skill: Dawnfire** (Ultimate; damage; all enemies; power 85; 50 MP; cd 8; applies blind; Holy/Fire). The sky ignites with the first light: holy fire on every foe. |

### Kannagi

**Barrier Arts**: Seals and wards of the Ancient Ones.

| Tier | Node | Ranks | Effect |
|---|---|---|---|
| 1 | Warding | 3 | +3 spell ward, +2 toughness. *Symbols of protection.* |
| 2 | Sacred Seal | 1 | **Skill: Sacred Seal** (Basic; debuff; enemy; power 20; 20 MP; cd 3; applies sealed). Press an ofuda seal onto the foe, binding its spirit. |
| 3 | Barrier Mastery | 3 | Spirit Barrier: +10 power. *Spirit Barrier grows stronger.* |
| 4 | Sanctuary | 2 | -5% damage taken. *Sacred ground beneath you.* |
| 5 | Torii of the Ancients | 1 | **Skill: Torii of the Ancients** (Ultimate; buff; ally; power 70; 45 MP; cd 8; applies reflect, regeneration). Raise a gate of the Ancient Ones over an ally: warded, healing, reflecting. |

**Ancestral Spirits**: Healing, mana and stamina.

| Tier | Node | Ranks | Effect |
|---|---|---|---|
| 1 | Spirit Well | 3 | regen 3% MP, 2% SP per turn. *The spirits refill you.* |
| 2 | Stamina Conversion | 1 | **Skill: Stamina Conversion** (Link; drain; enemy; power 35; 15 SP; cd 4). Draw stamina from your foe and convert it to magical energy. |
| 3 | Ancestral Blessing | 3 | +6% healing. *The ancestors mend through you.* |
| 4 | Mending Mastery | 2 | Ancestral Mending: +10 power. *Ancestral Mending heals more.* |
| 5 | Communion | 1 | **Skill: Communion** (Ultimate; heal; ally; power 120; 50 MP; cd 8; applies regeneration). Commune with the Ancient Ones; their power floods an ally with life. |

**Kotodama**: Words of power older than the gods.

| Tier | Node | Ranks | Effect |
|---|---|---|---|
| 1 | Primal Voice | 3 | +2 arcane; +3% damage (magical attacks). *Your words carry weight.* |
| 2 | Spirit Lance | 1 | **Skill: Spirit Lance** (Basic; damage; enemy; power 40; 20 MP; cd 2). A spear of pure spirit, unbound by element. |
| 3 | Exorcist | 3 | Exorcism +0.1x. *Sealed spirits break apart.* |
| 4 | Wrath Mastery | 2 | Wrath of the Ancients: +10 power. *Wrath of the Ancients grows.* |
| 5 | Voice of Nyxara | 1 | **Skill: Voice of Nyxara** (Ultimate; damage; all enemies; power 95; 50 MP; cd 8; applies confused). Speak a word from before creation; every foe reels. |

## Sorcerers

### Elementalist

**Conflux**: Fire and ice, the classic contradiction.

| Tier | Node | Ranks | Effect |
|---|---|---|---|
| 1 | Searing Mind | 3 | +4% damage (Fire/Ice). *Heat and cold both answer.* |
| 2 | Glacial Prison | 1 | **Skill: Glacial Prison** (Basic; debuff; enemy; power 20; 20 MP; cd 3; applies freeze; Ice). Encase the foe in ice. |
| 3 | Thermodynamics | 3 | Thermal Shock +0.1x; Steam Burst +0.1x. *Exploit every temperature shock.* |
| 4 | Spear Mastery | 2 | Blazing Ice Spear: +10 power. *Blazing Ice Spear grows.* |
| 5 | Meteor | 1 | **Skill: Meteor** (Ultimate; damage; all enemies; power 95; 55 MP; cd 8; applies burn; Fire/Earth). Pull a burning star down on every foe. |

**Stormcalling**: Water, wind and lightning.

| Tier | Node | Ranks | Effect |
|---|---|---|---|
| 1 | Static Mind | 3 | +4% damage (Lightning/Water/Wind). *The storm hums in you.* |
| 2 | Tidal Wave | 1 | **Skill: Tidal Wave** (Advanced; debuff; all enemies; power 20; 25 MP; cd 4; applies soaked; Water). A wave crashes over every foe and leaves them drenched. |
| 3 | Conduction Mastery | 3 | Conduction +0.1x; Overload +0.1x. *Lightning through water.* |
| 4 | Storm Mastery | 2 | Volcanic Thunder Storm: +10 power. *Volcanic Thunder Storm grows.* |
| 5 | Tempest | 1 | **Skill: Tempest** (Ultimate; damage; all enemies; power 95; 55 MP; cd 8; applies shock; Lightning/Wind). A living storm of wind and lightning. |

**The Fifth Element**: Conversion of the four, toward Aether.

| Tier | Node | Ranks | Effect |
|---|---|---|---|
| 1 | Arcane Study | 3 | +2 intelligence, +2 arcane. *Endless study in the tower.* |
| 2 | Elemental Convergence | 1 | **Skill: Elemental Convergence** (Advanced; damage; enemy; power 35; 30 MP; cd 3; Fire/Ice/Lightning/Earth). Fire, ice, lightning and earth fused in one bolt; it answers any combo. |
| 3 | Overflowing Mana | 3 | regen 3% MP per turn. *Mana wells up unbidden.* |
| 4 | Eccentric Genius | 2 | +5% critical hit rate. *Brilliant, chaotic, effective.* |
| 5 | Aether Nova | 1 | **Skill: Aether Nova** (Ultimate; damage; all enemies; power 110; 60 MP; cd 8). A glimpse of the fifth element: pure Aether, beyond any resistance. |

### Beastmaster

**Predator**: Pacts with Fenrisulfr and the Manticore.

| Tier | Node | Ranks | Effect |
|---|---|---|---|
| 1 | Feral Strength | 3 | +4% damage (physical attacks); +1 arcane. *Borrowed claws, borrowed fury.* |
| 2 | Hunter's Mark | 1 | **Skill: Hunter's Mark** (Basic; debuff; enemy; power 20; 15 SP; cd 3; applies marked). Mark your prey; the pack will not lose it. |
| 3 | Venom Glands | 3 | +5% damage (vs poison). *Poisoned prey weakens fast.* |
| 4 | Manticore Fury | 2 | Manticore Sting: +10 power; Manticore's Venom +0.1x. *Manticore Sting, deeper.* |
| 5 | Call of Fenrisulfr | 1 | **Skill: Call of Fenrisulfr** (Ultimate; damage; all enemies; power 90; 50 SP; cd 8; applies bleed; Slash). The Wild Father answers: spectral wolves tear through every foe. |

**Behemoth**: The Behemoth's endurance.

| Tier | Node | Ranks | Effect |
|---|---|---|---|
| 1 | Behemoth Blood | 3 | +2 vitality, +2 fortitude, +2% max HP. *Its blood in your veins.* |
| 2 | Behemoth Charge | 1 | **Skill: Behemoth Charge** (Basic; debuff; enemy; power 25; 20 SP; cd 3; applies staggered; Blunt). Charge with the Behemoth's weight and bowl the foe over. |
| 3 | Stone Skin | 3 | -4% damage taken. *Hide like rock.* |
| 4 | Hide Mastery | 2 | Behemoth Hide: +10 power. *Behemoth Hide grows thicker.* |
| 5 | Earthshaker | 1 | **Skill: Earthshaker** (Ultimate; damage; all enemies; power 85; 50 SP; cd 8; applies staggered; Earth; Blunt). The Behemoth stamps; the ground breaks under every foe. |

**Roc**: The Roc's speed and the open sky.

| Tier | Node | Ranks | Effect |
|---|---|---|---|
| 1 | Roc's Wings | 3 | +2 agility, +2% dodge. *Lighter than air.* |
| 2 | Roc Dive | 1 | **Skill: Roc Dive** (Basic; damage; enemy; power 35; 20 SP; cd 2; Wind; Pierce). Plunge from above with talons first. |
| 3 | Tailwind | 3 | +3% critical hit rate. *Strike first, strike true.* |
| 4 | Sky Hunter | 2 | +10% damage (vs marked). *Marked prey can't escape the sky.* |
| 5 | Storm of Feathers | 1 | **Skill: Storm of Feathers** (Ultimate; damage; all enemies; power 85; 50 SP; cd 8; applies confused; Wind; Pierce). The Roc's wings whip up a storm of razor feathers. |

### Necromancer

**Curses**: Hel's maledictions.

| Tier | Node | Ranks | Effect |
|---|---|---|---|
| 1 | Malediction | 3 | +4% damage (Dark). *Darkness answers you.* |
| 2 | Crippling Hex | 1 | **Skill: Crippling Hex** (Advanced; debuff; enemy; power 40; 50 MP; cd 6; applies blind; Dark). A devastating curse that weakens strength, agility, and fortitude while blinding the target. |
| 3 | Lingering Curse | 3 | Curse of Weakness: +8 power. *Curse of Weakness bites deeper.* |
| 4 | Blight Mastery | 2 | Blight +0.15x; Dread +0.1x. *Poison and shadow, perfected.* |
| 5 | Hel's Decree | 1 | **Skill: Hel's Decree** (Ultimate; debuff; all enemies; power 60; 50 MP; cd 8; applies poison; Dark). The Shadow Keeper's decree: every foe weakens and rots. |

**Life Drinker**: Your own life, and others', as fuel.

| Tier | Node | Ranks | Effect |
|---|---|---|---|
| 1 | Dark Pact | 3 | heal 3% of damage dealt. *Stolen life sustains you.* |
| 2 | Blood Rite | 1 | **Skill: Blood Rite** (Advanced; damage; enemy; power 55; 5 MP; 8% max HP; cd 2; Dark). Pay with your own blood for a devastating bolt of shadow. |
| 3 | Sanguine | 3 | Life Tap: +8 power. *Life Tap drinks deeper.* |
| 4 | Undying | 2 | -10% damage taken (below 30% HP). *Death keeps letting you go.* |
| 5 | Perfect Drain | 1 | **Skill: Perfect Drain** (Ultimate; drain; enemy; power 100; 50 MP; cd 8; Dark). A master-level technique that perfectly converts life to life. |

**Gravecaller**: Bone and the cold of the grave.

| Tier | Node | Ranks | Effect |
|---|---|---|---|
| 1 | Death's Embrace | 3 | +2 intelligence, +2 mind. *The grave's patience.* |
| 2 | Bone Spear | 1 | **Skill: Bone Spear** (Basic; damage; enemy; power 40; 20 MP; cd 2; applies bleed; Dark). A lance of bone that tears and bleeds. |
| 3 | Grave Chill | 3 | +4% damage (Ice/Dark). *The cold of the grave.* |
| 4 | Reaper | 2 | +12% damage (vs targets below 30% HP). *Finish the dying.* |
| 5 | Danse Macabre | 1 | **Skill: Danse Macabre** (Ultimate; damage; all enemies; power 95; 55 MP; cd 8; applies confused; Dark). The dead rise and dance through the enemy ranks. |

## Balance snapshot (sim, floor-1 full runs, talents spent first branch first)
Heroes reach about level 4 on floor 1, so 3 talent points; clear rates rose a few points.

| Class | Clear rate | | Class | Clear rate |
|---|---|---|---|---|
| Paladin | 34% | | Monk | 19% |
| Necromancer | 25% | | Berserker | 27% |
| Myrmidon | 28% | | Shinobi | 33% |
| Cleric | 32% | | Kannagi | 30% |
| Samurai | 38% | | Beastmaster | 31% |
| Elementalist | 31% | | Druid | 21% |

The Druid was 12%. It now has Plague Strike power 65, Arctic Blast cooldown 4 and base VIT 10.

Run-to-run noise at 250 runs is about ±9 points. The sim can't yet judge late tiers (ultimates appear around level 9 with a focused branch).
