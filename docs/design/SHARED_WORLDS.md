# Shared worlds

Any number of characters can live in the same world. The world has its own
file, and each character's save keeps only what is theirs. The code is in
`scripts/resources/WorldShare.gd`, with hooks in `SaveManager`.

## What lives where

| World file `user://worlds/<id>.json` | Character save |
|---|---|
| clock, events, town news (`world`) | bounties (`guild`), party, injuries, Lost & Found |
| adventurers: levels, jobs, traits, relations, companies, deaths, history | your memories, voice and reputation, bestiary, alchemy, commissions, armour training |
| rumours, the Chronicle | birthplace, background, permadeath, retired or fallen |
| the Ledger's shared part: year, crownings, champion | your Ledger deeds and weekly snapshot (`ledger_me`) |
| register of characters (`world_meta.pcs`): level, class, rank, renown, status, last day seen | **what each adventurer feels about you** (`npc_me`) |

`npc_me` holds, per adventurer: rapport, rivalry, rival and nemesis,
traits you've learned, chats, bond tier, the drink/chat/gift days, memories
of you, and their arc stage.

## How it works

- **Save:** the world is split out and written to its file, and the
  character's own part goes into their save.
- **Load:** the world file is read and put back together around the
  character.
  - Adventurers they've never met get a fresh starting rapport (temperament,
    same region, background).
- **Time is shared.** When any character plays, the world moves on for all
  of them.
  - Personal timers (injuries, bounty deadlines) only run while that
    character is playing.
- **Companions** are free while you're away. If one is dead, retired, or in
  another character's party when you come back, they leave your party.
  You see "X moved on while you were away."
- **Other characters stand on the Guild Ledger.** They show as "your
  character", from the register, and can be crowned Champion.
- **Lines about other characters:** Chronicle entries and town news written
  as "you" for one character show to the others as "Name: ...".
- **Deleting a character:** they leave the register. Fallen characters stay
  in it as "fallen". A world nobody lives in any more is removed.
- **Older saves** keep their world inside the save. It becomes a world file
  on the next save.
- **Tests** use `WorldShare.use_dir()`, so they never touch your worlds.

## Joining

Joining happens at character creation (the World step), or from
Character Selection with **New world...**. The newcomer arrives on the
world's current day, and two rivals sign up with them. Everyone meets them
fresh.

## Saves from older versions

A save made before world generation existed has no world file and no
`joined_day`. On load it's marked `returning`, and its world is written
again as if it were the character's first visit.

**What happens on arrival:**
- A **Welcome back** dialog explains what's happening. If the save
  predates birthplaces and backgrounds, it asks for them. "Not now" goes
  back to the character list.
- The world's history is generated: 224 days of it.
- The two rivals who sign up are close to your level, not newcomers.
- The town news says you came back after a long time away.

**Kept:** level, attributes, gear, inventory, gold, talents, skills, rank
and Guild points, floor progress, bounties, bestiary, alchemy, injuries,
Lost & Found, and your Ledger deeds (bosses, firsts, crowns).

**Dropped:** the old world, plus everything that pointed into it: your
party, your memories of adventurers, pending invitations, and the Ledger's
weekly snapshot.

Characters hit by the bug where world generation was skipped fit the same
check, so they get their history on the next load.

**Tests:** real saves made by older versions of the game are in
`tests/fixtures/old_saves/`. The smoke test loads them every run.
- `Oldtimer_971c4e9`: made by commit 971c4e9, from before the living world.
- `Oldtimer_3561778`: made by commit 3561778, from just before world
  generation.
