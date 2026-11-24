# Living world and class depth (design draft - for workshopping)

Goal: the Guild simulation is the heart of the game. Stories should come out of
it the way they do in Dwarf Fortress: the world **remembers**, people are
**connected to each other** (not just to you), and what happened is
**surfaced** so you can retell it. Classes should be deep enough that two
Paladins - yours or an NPC's - play differently.

Everything below is a proposal. Numbers are starting points for the sims.
**Open questions** at the end of each section are for us to decide.

---

## A. NPC-to-NPC relationships

Today rapport and rivalry only point at the player. NPCs should also relate
to each other.

### Data
- A **relation** exists between two adventurers once they've interacted:
  `{a, b, affinity: -100..100, tags: [...], since: day}`.
- Stored in `town_state.adventurers.relations`, keyed `"<low id>:<high id>"`.
- Each NPC keeps at most **8** relations (the weakest |affinity| is forgotten),
  so the world stays bounded.

### What changes affinity (daily sim)

| Event | Change |
|---|---|
| Ran a job together, succeeded | +6 |
| Ran a job together, failed (shared hardship) | +2; but -4 if either is Boastful or Cruel (blame) |
| One rescued the other (a success in the same place/day as the other's failure) | +20 to the rescued, +5 to the rescuer |
| Both in town and idle (Tavern time), per day | traits: each compatible pair +1, each clashing pair -1 |
| Both Ambitious and within 3 places on the Ledger, per week | -3 |
| One promoted past the other (if the other is Ambitious/Boastful) | -5 |
| One robbed or sabotaged the other | -25 |
| One gave the other a share of loot / bought drinks (Kind, Cheerful, Loyal) | +3 |

Compatible traits (examples): Kind–Kind, Devout–Devout, Scholarly–Scholarly,
Loyal–Honorable, Cheerful–anything except Aloof. Clashing: Honorable–Cruel,
Cautious–Reckless, Greedy–Kind, Lazy–Ambitious. (Data table, editable.)

### Thresholds

| Affinity | Becomes | Effect |
|---|---|---|
| ≥ 40 | **Friends** | prefer jobs together (+50% chance to pair up) |
| ≥ 70 | **Sworn companions** | form a named NPC party ("The Ashpelt Wardens"): always job together, combined power, climb the Ledger together, share renown |
| ≤ -40 | **Rivals** | compete: race for the same World Firsts, sour news |
| ≤ -70 | **Feud** | may sabotage each other off-screen (news), duel at the Guild, or drag you in (see storylets) |

### NPC parties
- Sworn companions (2-3 people) take jobs as a party: success uses their
  combined level and gear (the same job-success formula, summed power).
- A party has a generated name, a leader (highest renown) and a shared history.
- A party breaks up on a death, a feud inside it, or retirement.

### Grief and its paths
When an NPC's friend or companion dies, the survivor gets **grief** for
14-28 days, then one outcome weighted by traits:

| Outcome | Weighted by |
|---|---|
| **Vengeance**: gets the goal "slay the boss of <place, floor>"; takes riskier jobs there | Reckless, Loyal, Honorable |
| **Withdraws**: retires or leaves the Guild | Cautious, Cowardly, Kind |
| **Hardens**: gains a trait (Aloof or Cruel) | Ambitious, Cruel |
| **Carries on**: a memorial line in the Chronicle, nothing more | Cheerful, Devout |

A vengeance goal fulfilled (by them, or by **you**, if you kill that boss) is a
story moment: big affinity/rapport, a Chronicle entry, maybe a storylet.

### You in the web
- **Ripple:** when your rapport with someone changes, their friends' rapport
  with you changes by 25% of it (rivals: -25%). Help Kara, and Kara's friends
  warm to you; Kara's rival cools.
- Recruiting someone into your party counts as "ran a job together" for you.

### Decided (A): all four - NPC parties, romance, lethal feuds, invitations

**Romance**
- Two adventurers who are sworn companions (affinity ≥ 70) and neither in a
  romance may become **partners**: a weekly 10% chance, x2 with a compatible
  trait pair, x0 if either is Aloof (unless both are). No restrictions by race
  or gender.
- Partners: +50% chance to job together, shared grief is doubled (the grief
  outcome is picked twice and both apply), and a partner's death is always a
  core memory and a Chronicle entry.
- A partner who ends up in a feud with the other (affinity ≤ -40) **separates**
  (news, Chronicle).
- With you (later): the same rules on your rapport, at the Tavern, opt-in.

**Lethal feuds**
- A feud (affinity ≤ -70) has a weekly chance of a **confrontation**: 5%, x2 if
  either is Cruel, x0.5 if either is Honorable or Kind.
- A confrontation is an off-screen duel (the AutoBattler, real builds). The
  loser is injured; if either is Cruel or the gap in level is 5+, there's a
  25% chance it's **lethal**. Witnesses' friends gain memories of the killer
  (`killed_my_friend`, core) - a killer can become a pariah, or someone's
  vengeance target.
- The Guild reacts: a killer gets 3 demerits and drops 1 rank (if
  "honourable conduct" world setting is on - default on).

**Parties invite you**
- An NPC party with a friend of yours (rapport ≥ 40) may **invite you** to its
  next job (news + a Journal entry, valid 3 days).
- Accept: you join their expedition (they fight beside you; you share loot by
  their split), and every member gains `shared_victory` or `shared_hardship`
  memories of you. Decline: no penalty, unless you decline the same party
  three times (a small cool-down).

---

## B. Consequential memory

NPCs already keep a history list. Make it **drive behaviour**.

### Data
A memory: `{day, kind, about: "you" | npc id, weight, core: bool}`.
- Each NPC keeps its **20 strongest** memories.
- Weight **fades** 2% per day (half-life ~35 days), except **core** memories
  (weight ≥ 50, or anything involving a death), which never fade.
- An NPC's opinion of someone = the sum of its memory weights about them.
  Rapport (you) and affinity (NPCs) move with it.

### Memory kinds (examples)

| Kind | Weight | Made when |
|---|---|---|
| saved_me | +30 | you gave a potion when they were dying, rescued them |
| abandoned_me | -30 | you refused the wounded with a potion in your pack |
| robbed_me / robbed_by_me | -25 / ±0 (guilt if Honorable: -5 on self-opinion) | thefts |
| beat_me / beaten_by | -15 / +5 (respect if Honorable) | duels, ambushes, nemesis fights |
| shared_victory | +8 | a job or wave won together |
| saw_them_die | core | a companion died beside them |
| heard_of | ×0.3 of the original | gossip (below) |

### Behaviour rules
1. **Grudges:** a remembered `abandoned_me` or `robbed_me` about you (weight ≥ 20)
   → won't join your party, can be a saboteur even if rapport isn't low,
   and tells their friends (gossip).
2. **Debts:** `saved_me` ≥ 20 → appears as a helper twice as often, and once
   can be **called in**: join you for a whole expedition without a loot share,
   or carry you home on a defeat (no Guild fee or lost gear).
3. **Learning:** a nemesis who has lost to you twice **studies you**: they
   switch to armor that resists your main damage type and favour skills that
   hit your weaknesses. The third fight is genuinely harder.
4. **Gossip:** each day one NPC in town shares one strong memory with a
   friend, who gets a `heard_of` copy at 30% weight (with the source). Your
   reputation spreads through the social graph - for good and ill.
5. **Admiration:** an NPC whose vengeance goal *you* fulfilled gets a core
   `saved_me`-sized memory of you.

### Visible to the player
The Tavern details panel shows what someone remembers about you ("Kara
remembers you left her in the Troll Caves - day 34"), and what they've heard
("Dao heard from Kara that you…").

### Decided (B): hints first, full once you're friends
- Below rapport 40: the Tavern shows only a **mood** from their opinion of you
  ("warm", "wary", "cold", "hostile") and one hint line ("Kara won't meet your
  eye").
- From rapport 40 (Friend): the full list - what they remember about you and
  what they've heard (with who told them).

### Decided (B): the player has memories too - see section G.

---

## C. The Chronicle (Legends mode)

The world's history, browsable, so emergent stories become retellable.

### Recorded (append-only, with an importance score)
Named adventurer deaths and retirements; Crownings; World Firsts; NPC parties
formed and broken; friendships, feuds and how they ended; vengeance sworn and
fulfilled; nemesis duels; your promotions, bosses and rescues; world events.
Capped at ~500 entries (low-importance ones pruned first).

### Views
- **Timeline** by year and season.
- **People**: a generated biography per adventurer from their memories and
  Chronicle entries ("Kara Ashpelt, Elvarian Cleric. Joined in Year 1.
  Sworn companion of Dao Vale. Swore vengeance on the Troll King after Dao fell
  on floor 9 (Year 2, Frostmere). Retired as a B-rank in Year 3.").
- **Places**: who died where, first clears, the deepest anyone has gone.
- **Bonds and feuds**: the social web over time.
- **Hall of the fallen**: epitaphs written from traits.

### Decided (C): it carries over as a Legend - see section H.

---

## D. Class depth and customization

Today: 12 classes; each has 3 talent branches (5 tiers, an ultimate at tier 5),
a 6-skill loadout, skills that level with use, weapon proficiency and gear.

Proposed layers (each optional - pick what we build):

1. **Choice nodes.** Some talent tiers become "pick one of two"
   (mutually exclusive), so builds diverge inside a branch. E.g. Paladin
   Bulwark tier 3: *Bastion* (shield wall) or *Retribution* (counter when hit).
2. **Skill augments.** Skills gain augment slots as they level (level 3, 6, 9).
   Augments change how a skill plays, not just its numbers: Fireball →
   *Twin Flame* (two targets at 60%), *Steam Burst* (also Soaks), *Quickcast*
   (-1 cooldown). Augments drop, come from bounties, or are taught by trainers.
3. **Secondary discipline (subclass).** At C rank, pick a second class and
   spend points in tiers 1-3 of one of its branches (up to 12 points).
   Hybrid builds: a Paladin with Elementalist fire, a Shinobi with Druid roots.
4. **Weapon arts.** Weapon proficiency milestones unlock weapon-specific
   skills, so a Samurai with a bow and a Samurai with a katana play
   differently.
5. **Attribute thresholds.** Passives unlocked by raw attributes
   (e.g. 60 Agility: *Fleetfoot*, act first in the opening round).
6. **Mastery (S rank).** A prestige specialization per class with a signature
   mechanic (Paladin → Templar or Sentinel).
7. **Build loadouts.** Save several talent + skill + gear sets; respec has a
   gold cost.

**NPCs use the same system.** Their builds follow their traits (Reckless →
offense branches, Cautious → defense), so every Guild Paladin is different and
the Ledger's top adventurers have recognisable builds - and a nemesis can
re-spec against you (rule B3).

### Decided (D): first layers 1, 2, 4 and 5; respec cheap, rising with level

**1. Choice nodes**
- Tiers 2 and 4 of every branch get a **pair** of mutually exclusive nodes
  (`"choice": "<group id>"` in talents.json); learning one locks the other
  until a respec. 12 classes x 3 branches x 2 tiers = 72 pairs to write.
- Rule of thumb for each pair: one option deepens the branch's identity, the
  other bends it toward another play style (offense <-> defense, single <->
  area, self <-> party).

**2. Skill augments**
- Skills already level with use. Augment slots open at skill level 3, 6 and 9.
- An augment is data: `{id, name, applies_to: [skill names or tags],
  effects: [...]}` using the same effect kinds as talents plus skill-shape
  changes: `extra_targets`, `add_status`, `cooldown_delta`, `cost_delta`,
  `power_mult`, `element`, `turn_delay`.
- Sources: boss and elite drops, Guild bounties, and **trainers** (a class
  trainer NPC per school in town, later).
- Swapping augments is free in town.

**4. Weapon arts**
- Weapon proficiency (already tracked) unlocks a weapon art at proficiency
  levels 3 and 6 for each weapon family (sword, katana, bow, staff, tome...):
  `{family, level, skill}`. They join the skill pool and the 6-slot loadout.
- So a Samurai with a bow and one with a katana really play differently.

**5. Attribute thresholds**
- Passives at raw (base + gear) attribute thresholds: 40 / 80 / 120. Two per
  attribute to start (e.g. Agility 40: *Fleetfoot* - act first in the opening
  round; Faith 80: *Grace* - heals +15%; Fortitude 80: *Unshaken* - one free
  Break pip each fight).
- Data-driven; shown on the Status screen with progress.

**Respec**
- Talents and choice nodes: gold = level x 20 (cheap early, a commitment
  late). Attribute points: not refundable (thresholds stay meaningful).
- Augments: free to swap in town.

**Later layers:** secondary discipline, mastery, saved loadouts.

**NPC builds:** generated NPCs pick branches, choice nodes and augments by
traits, so the Ledger's top adventurers have recognisable builds.

---

## F. Personality depth: archetypes, drives and arcs (built - first pass)

Built: `PersonalityManager` + `data/personalities.json` (tab Personalities). 18 archetypes with voices (10 contexts) and arcs, 12 drives, 8 flaws, 20 quirks; mods feed the existing trait helpers; Tavern shows personality, mood, arc, quirks, drive/flaw reveals and a greeting; voice lines in chat, gifts, joining/refusing and companion battle barks; arcs advance with rapport (news); drives fulfilled by the sim (avenge, S-rank, Champion); phobias steer job choice; your reputation (archetype from your choices) in the Journal. Not yet: event-triggered arc stages and storylets, Yandere jealousy (needs relationships), drive-specific job logic beyond avenge.

Traits alone (Reckless, Kind, Greedy...) make NPCs act differently; they don't
make them feel like *characters*. Each adventurer gets five layers, so two
Kind Clerics can still be completely different people:

| Layer | What it is | Example |
|---|---|---|
| **Archetype** | a recognisable anime/manga trope: how they present and how they grow | Tsundere, Hot-blooded Rival, Kuudere |
| **Traits** (2-3, existing) | how they behave | Reckless, Loyal |
| **Drive** | what they want - a long-term goal the sim pursues | become Champion, avenge a sibling, pay a family debt, find a lost mentor |
| **Flaw / fear** | what can break them | pride, fear of abandonment, fear of deep water (a location they avoid) |
| **Quirks** (1-2) | small, memorable, sometimes mechanical | always orders milk at the Tavern; names every attack; collects goblin teeth |

### Archetypes (first set - data, editable)

Each archetype defines: trait weights (what traits it tends to roll with),
a **voice** (lines for contexts), behaviour hooks, and an **arc** (stages
unlocked by memories and rapport).

| Archetype | Presents as | Behaviour hooks | Arc |
|---|---|---|---|
| **Tsundere** | prickly, denies caring | their *mood* reads colder than their real opinion until rapport 60; gifts "rejected" but still count | Denial → Slip (a storylet where they let it show) → Honest |
| **Kuudere** | cool, quiet, logical | slow rapport gains from chat; big ones from shared victories | Distant → Trusting → Fiercely loyal (never leaves your party) |
| **Dandere** | shy, says little | needs 2x chats; once a friend, the most loyal | Silent → Opens up → Speaks up for you (defends you in gossip) |
| **Genki** | bursting with energy | cheers the party (small Link gain at battle start) | Reckless joy → learns from a loss → steady light |
| **Hot-blooded Rival** | loud, competitive, honest | rivalry grows when you're ahead on the Ledger; challenges you to duels | Rival → Respect (2 duels each way) → **Rival-friend** (a special duo tech) |
| **Stoic Swordmaster** | few words, all discipline | prefers solo jobs; respects strength | Lone wolf → Accepts a party → Mentor to a younger NPC |
| **Noble Heir** (ojou-sama / young lord) | proud, refined, generous with money | spends gold freely; looks down on low ranks | Arrogant → Humbled (a defeat) → Noblesse oblige |
| **Chuunibyou** | dramatic, grand titles, secret "dark powers" | names attacks in the combat log; gives themself epithets | Delusion → a real moment of greatness → embraces it, half-joking |
| **Battle Maniac** | lives for a strong opponent | seeks the deepest floors and the Ledger's top; may challenge the Champion | Thrill-seeker → finds a worthy foe (you or a boss) → dies fighting, or settles |
| **Lazy Genius** | naps, shirks, brilliant when it counts | takes few jobs; very high success on the ones it takes | Coasting → something they care about is threatened → full power |
| **Big Sibling** (aniki / aneki) | protective, teasing | helps low-rank adventurers; shows up when you're at low HP | Protector → loses someone → over-protective, or lets go |
| **Mysterious Stranger** | secretive past | hidden drive revealed in stages | Secret → Clue → Revelation (a storylet) |
| **Comic Coward** | scared of everything | flees jobs often; somehow survives | Coward → one brave moment (a big story beat) → still scared, but stays |
| **Airhead** (tennen) | cheerful, oblivious | random harmless mishaps in the news | — (a constant; their arc is everyone else's) |
| **Veteran Mentor** | older, tired, wise | teaches: friends gain XP faster | Retired spirit → one last job → passes the torch (or falls) |
| **Gap Character** | scary-looking, soft inside | "intimidating" first impression lowers starting rapport; gifts of sweets x2 | Feared → Understood |
| **Devoted Admirer** | idolises the top adventurer | follows the Ledger #1 (could be you) | Fan → Disciple → Rival to their idol |
| **Yandere** *(optional, off by default)* | sweet, possessive | jealous of your other bonds; may sabotage them | — (a dark trope; a world setting) |

### Voice
Lines per archetype per **context**: greeting, chat, join party, battle start,
low HP, ally down, victory, gift (liked / disliked), refuse, grief, taunt
(rivals / nemeses), farewell. 3 lines per context to start (~40 lines per
archetype). Used in the Tavern, as companion barks in the combat log, in the
news and in storylets. `{name}`, `{you}`, `{place}` placeholders.

### Drives and flaws drive the simulation
- A **drive** biases job choice and decisions (an avenger takes jobs at the
  place their sibling died; a debtor takes the best-paying work and may steal
  when desperate).
- Reaching a drive is a Chronicle moment and changes them (a new drive, or
  retirement).
- A **flaw** can trigger under pressure: Pride → refuses help / won't retreat;
  Fear of abandonment → a huge grudge if a friend leaves them; a phobia →
  avoids a location, or panics there (job failure chance up).

### Arcs
- Each arc stage has a **trigger** (memory, rapport, event) and a **change**:
  new voice lines, a behaviour change, sometimes a trait swap or a new skill.
- Some stage changes are staged as **storylets** (the Tsundere's slip, the
  Stranger's revelation, the Coward's brave moment).
- Arcs are why the same archetype is a different story each time: *who* they
  meet and *what* happens to them decides how far they get.

---

## G. Player memory

The player keeps memories too, with the same structure as NPCs:
- `helped_me`, `saved_me`, `robbed_me`, `betrayed_me`, `beat_me`,
  `killed_my_friend`, `stood_by_me`, `my_first_crown`... about NPCs, places
  and bosses.
- Core memories never fade; others fade like an NPC's.

Used by:
- **A "People" page in the Journal**: allies, debts owed (to and by you),
  grudges, the fallen.
- **Storylets and story mode**: "confront the one who killed your companion",
  "repay the debt to Kara".
- **Dialogue choices**: forgive or hold a grudge - which shapes your
  reputation (honour, mercy, boldness) and how NPC archetypes see you.
- **The Legend** (below).

---

## H. Legends: the Chronicle carried into the next world

When your character's story ends (retirement, or death in a hardcore world),
the world's Chronicle is distilled into a **Legend**: your story retold in a
mythic voice, kept across playthroughs.

### Writing the Legend
- Picks the most important beats by score: origin, first rival, bonds, great
  deeds, tragedies, crowns, the end.
- Each beat type has legend-voice templates:
  "In the {year} year of {season}, when {boss} still ruled {place}, there came
  a {race} {class} named {name}..."; "{name} and {friend} swore an oath beneath
  the Guild's lamps..."; "But {rival} would not be outdone...".
- **Epithets** earned from deeds become part of the name: *the Unbroken*,
  *Trollbane*, *Kingslayer*, *the Twice-Crowned*. NPCs earn them too.

### Carrying it over
- Legends are stored outside the save (`user://legends.json`) and kept
  across worlds.
- In a new world:
  - **Bards** at the Tavern tell your past Legends (and your past
    companions' and rivals').
  - A **Hall of Legends** in the Guild: statues and their stories.
  - NPCs reference them ("You fight like Mira the Unbroken").
  - **Heirs**: sometimes a generated adventurer is the descendant or
    apprentice of a past legend's companion or rival - with a drive tied to
    that story (e.g. surpass their grandmother's record).
  - **Relics**: a past legend's signature item can be found as a named relic
    (flavour first, power modest).

---

## Decided (F-H)

**Yandere: always possible** (like any archetype), with limits so it's drama,
not griefing:
- Rolls rarely (weight 0.3 vs 1.0 for most archetypes).
- Their jealousy targets **your bonds**, not you: when your rapport with
  someone else rises above theirs, they gain a `jealous_of` memory; past a
  threshold they spread bad gossip about that person, then may sabotage them
  (an ambush on *that NPC*, off-screen, injury only).
- Lethal only through the normal lethal-feud rules, never directly.
- Their arc: Infatuation → Jealousy → either **Let go** (you keep their
  rapport high and stay honest in a confrontation storylet) or **Break**
  (they become a nemesis).

**Writing: I draft, you edit.** Voices, storylets and legend templates are
data files (Content Manager tabs) with my first drafts for you to revise.

**Your voice: defined by your choices.**
- You start **neutral** (plain lines).
- Choices carry archetype tags: confronting the thief (+Hot-blooded,
  +Battle Maniac), sparing a nemesis (+Big Sibling, +Gap), sharing loot
  (+Genki, +Big Sibling), refusing help (+Kuudere, +Stoic), taking every
  Omen (+Chuunibyou, +Battle Maniac), naming your party something grand
  (+Chuunibyou)...
- Once your top archetype has 10+ points and leads the next by 3, your lines
  and barks use its voice; it can still drift if you change how you play.
- NPC archetypes react to yours (a Hot-blooded Rival seeks out a fellow
  hot-blood; a Kuudere respects a quiet one; a Tsundere clashes with a Genki).
- The Status screen shows how you're seen ("The Guild thinks you're a
  hot-blooded fighter").

**Relics: modest heirlooms.** A past legend's signature item, found as a named
relic: about an Epic of its level plus one small unique property tied to the
story (e.g. *Mira's Prayer Beads: +10% healing received when below half HP*).
At most one relic per past legend per world.

## E. How it fits together

- Relationships and memory make the simulation **produce** stories.
- The Chronicle **surfaces** them.
- Storylets (next design step) **stage** the best moments as small scenes:
  a rescue request when a friend's party doesn't return, an Infirmary visit
  to your injured nemesis, a public duel between two rivals near the top.
- Story mode (later) **casts** its roles from this living population.
- Class depth makes every adventurer - you and the NPCs - a distinct person
  in a fight, not just a name.
