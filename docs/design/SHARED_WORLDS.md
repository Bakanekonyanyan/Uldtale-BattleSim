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
