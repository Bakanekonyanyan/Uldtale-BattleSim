# Storylets (design draft)

Storylets are short, authored story moments - a few paragraphs and a choice -
that the world *casts* from the people who actually live in it. The author
writes the shape ("a grieving adventurer asks you to help avenge their
friend"); the game fills the roles with whoever fits right now (Kara, whose
sworn companion Dao fell on floor 9 of the Troll Caves last week). Chained
together they become branching storylines.

Everything is data (`data/storylets.json`), edited in a Content Manager tab,
with validation and a preview that casts a storylet in a generated world.

---

## 1. Anatomy of a storylet

```json
"tsundere_slip": {
  "title": "Not That I Care",
  "trigger": {"hook": "tavern_visit"},
  "roles": {
    "tsun": {"archetype": "tsundere", "arc_stage": "denial", "rapport_min": 45, "in_town": true}
  },
  "conditions": [{"not_flag": "slip_seen:{tsun.id}"}],
  "weight": 3, "once": "per_cast", "cooldown_days": 20,
  "start": "n1",
  "nodes": {
    "n1": {
      "text": "{tsun.first} shoves a wrapped bundle across the table. \"Found it. Didn't want it. Don't read into it.\" It's a whetstone - exactly the one you lost last week.",
      "choices": [
        {"text": "Thank them warmly.", "tags": ["big_sibling"], "effects": [{"rapport": ["tsun", 8]}], "next": "n2"},
        {"text": "Tease them about it.", "tags": ["genki"], "effects": [{"rapport": ["tsun", 3]}], "next": "n3"},
        {"text": "\"...I'll treasure it.\"", "voice": "kuudere", "effects": [{"rapport": ["tsun", 12]}, {"arc_stage": ["tsun", "honest"]}], "next": "end"}
      ]
    },
    "n2": {"text": "...", "effects": [{"flag": "slip_seen:{tsun.id}"}], "choices": [{"text": "Continue", "next": "end"}]}
  }
}
```

- **trigger** - which hook can fire it (section 2).
- **roles** - who it's about, chosen from the live world by selectors
  (section 3). Text uses `{role.name}`, `{role.first}`, `{role.they}`,
  `{role.class}`, `{place.name}`, `{you}`...
- **conditions** - extra checks (flags, your rank, memories, relations...).
- **weight / once / cooldown_days** - pacing.
- **nodes** - a small graph: text, optional effects on entering, choices.
  Choices have **requirements**, **personality tags** and **effects**, and
  lead to another node or `end`.

## 2. Hooks (where storylets can fire)

The game already raises these moments; each becomes a hook name:

| Hook | When |
|---|---|
| `tavern_visit`, `guild_visit`, `town_day` | entering a town place / a new day in town |
| `expedition_start`, `between_waves`, `after_boss`, `after_defeat` | during an expedition (like encounters) |
| `npc_death`, `npc_retired`, `promotion` (yours or theirs), `crowning` | world events (DramaManager, RankManager, LedgerManager) |
| `relation_changed` (became friends / sworn / feud), `arc_stage`, `grief_resolved`, `vengeance_sworn` | social events |
| `memory_added` (e.g. someone now owes you), `chronicle` (any entry of a kind) | memory and history |

A hook passes **context** (who died, who was promoted, which place), so a
storylet's roles can bind to it: `"mourner": {"friend_of": "$dead"}`.

At most one storylet plays per hook; candidates are weighted; a global
pacing setting (e.g. "at most one every N days") keeps them special.

## 3. Roles: dynamic casting

A role is a selector over adventurers (or places, or legends):

| Selector | Example |
|---|---|
| identity | `archetype`, `trait`, `class`, `race`, `rank_min`, `heir` |
| state | `in_town`, `status`, `grieving`, `has_vengeance`, `in_company`, `partner` |
| you | `rapport_min/max`, `rivalry_min`, `memory_about_you` (kind), `grudge`, `owes_you`, `in_party` |
| others | `friend_of` / `sworn_to` / `rival_of` / `feuding_with` / `partner_of` another role or hook context, `memory_about` another role |
| arcs | `arc_stage`, `drive` (e.g. `avenge`) |
| places | `place: {died_at_of: "dead"}`, `deepest_for_you` |
| legends | `legend: {any}` - for heir and bard storylets |

Roles bind in order, so later roles can refer to earlier ones. If any role
can't be filled, the storylet isn't eligible. Bound casts are remembered in
the storyline state, so a three-part story keeps the same people.

## 4. Choices and your personality

- **Personality tags** on a choice (`hot_blooded`, `kuudere`, `big_sibling`,
  `genki`, `stoic`...) feed your reputation (`PersonalityManager.player_event`)
  - so the choices you make define how the Guild sees you.
- **Voice choices** (`"voice": "hot_blooded"`) appear only when your
  reputation *is* that archetype - a line only someone like you would say.
  These are often the best outcomes: a reward for playing in character.
- **Requirements** can also gate on class, traits of companions, gold, an
  item, rank, a memory ("you saved them once"), or a skill/art you know.
- Choice text can vary by your voice (`text_by_voice`), so a neutral choice
  still sounds like you.

## 5. Effects (what a choice changes)

All existing systems, so a storylet can change the world:

| Effect | Does |
|---|---|
| `rapport`, `affinity`, `rivalry` | change feelings (you <-> NPC, NPC <-> NPC) |
| `memory` | add a memory to anyone, about anyone (they remember what you did) |
| `arc_stage`, `drive`, `trait_tag` / `trait_grow` | push personality arcs and trait growth |
| `flag`, `storyline_stage`, `schedule` | story state; schedule a follow-up storylet in N days |
| `gold`, `item`, `relic`, `injury`, `heal` | rewards and costs |
| `fight` | start a battle: duel a role (nemesis-style), an ambush, or a boss variant |
| `bounty`, `rumour`, `commission` | open new objectives |
| `join_party`, `leave_party`, `company` | party and company changes |
| `chronicle` | write an entry (importance) - big choices become history and Legends |
| `news`, `reputation` | town news; reputation tags without a choice |

## 6. Storylines (branching chains)

A storyline is storylets linked by `storyline_stage` and flags:
`"The Stranger's Secret"`: part 1 (a clue at the Tavern) -> part 2 (a
rumour leads to a floor) -> part 3 (the revelation; three endings by your
earlier choices). Its state is saved per world:
`{id, stage, cast: {role: npc_id}, flags, started}`. If a cast member dies,
an `on_cast_death` branch continues the story (or ends it as a tragedy).

Shown in the Journal ("Stories" section) so you can follow open threads.

## 7. Content Manager tab

- **List** of storylets/storylines with hook, roles and status.
- **Form** for metadata, trigger, roles (structured rows: selector + value),
  conditions.
- **Node editor**: nodes as cards in a list (text box, effects, choices; each
  choice with its tags, requirements, effects and `next` picked from a
  dropdown). A read-only **graph view** (boxes and arrows) to see the shape.
- **Validation**: unreachable nodes, dead ends, missing `next`, placeholders
  for undefined roles, unknown selectors/effects/tags, roles that could
  never be cast.
- **Preview** (Godot test button): generate a world, cast the storylet,
  print the filled text and choices - or "no one fits" with the reason.

## 8. First content (I draft, you edit)

Built from the arcs and systems we already have:
1. The Tsundere's Slip (arc stage)            6. A Feud Spills Over (take a side)
2. The Stranger's Secret (3 parts)             7. The Heir's Challenge (legend)
3. The Coward's Brave Moment                   8. The Yandere Confrontation (Let go / Break)
4. Vengeance for a Friend (npc_death)          9. A Debt Repaid (memory)
5. The Rival's Duel                           10. The Champion's Challenge (crowning)

---

## Decided

- **Pacing:** about one storylet every 3-5 days (a global cooldown, tunable).
- **Where:** town (Tavern, Guild, town days) and expeditions (between waves,
  after a boss or a defeat), like encounters.
- **Voice choices are hidden** unless your reputation matches - a surprise
  reward for playing in character.
- **Editor:** form cards for nodes (text, effects, choices with `next`
  dropdowns) plus a read-only graph view.
