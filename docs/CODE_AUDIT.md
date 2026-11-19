# Code audit: memory, deprecated code, optimization

Date: 2026-11-19. Scope: the Godot project (115 GDScript files, about 26,000 lines incl. tests), the data files, and the Python Content Manager. Everything below was **measured** in headless Godot 4.4.1 (leak counts, weakref checks, timings) or found by searching the code. The fixes marked **tested** were prototyped in a scratch copy and pass the full smoke suite (312/312). They are **not applied** to the repository yet.

## Summary

| # | Severity | Finding | Fix | Effort |
|---|---|---|---|---|
| L1 | **Critical** | Every `CharacterData` leaks: a reference cycle with its six managers | Weak back-reference in the managers (**tested**) | S |
| L2 | **High** | `CharacterData.last_attacker`: two fighters keep each other alive | Weak reference (**tested**) | XS |
| L3 | Low | `SceneManager.scene_stack` grows with every pushed screen you leave via Town | Clear the stack on REPLACE to Town; use POP for back | XS |
| L4 | Low | Fallen and retired adventurers stay in the save forever | Keep the last ~30 | XS |
| D1 | Medium | Dead code: `legacy/` (1,017 lines), two unused autoloads, unused functions, stray data files | Delete | S |
| D2 | Medium | Self-deprecated `SceneManager.change_scene/push_scene/pop_scene`: still called 13 times in 7 files | Switch to `navigate()`, delete the wrappers | S |
| D3 | Low | Godot 3-style string signals: 52 `connect("x", Callable(self, "y"))`, 39 `emit_signal("x")` | Typed `x.connect(y)` / `x.emit()` | S |
| D4 | Low | `EquipmentKeyHelper` probes four item paths, incl. `res://Data/...` (wrong case: breaks in exported builds on Linux) | One path from a data registry | XS |
| O1 | Medium | 495 `print()` calls, many in hot paths; one full balance sim wrote a **1.3 GB** log | `Log` autoload with levels, silent in release | S |
| O2 | Medium | The same JSON parsed in many places (`classes.json` ×7, `races.json` ×5, items ×3) | One `DataRegistry` autoload | M |
| O3 | Low | Enemy AI personality rolls use the global RNG, not `RandomManager` | Use `RandomManager` | XS |
| O4 | Low | Two copies of the hero battle policy (`AutoBattler` vs `tests/balance_sim.gd`) | Sim uses `AutoBattler` | S |
| O5 | Low | Shop prices and enemy multipliers hard-coded in scripts | Move to data | S |

**Status (2026-11-19): all findings below are fixed** except the maintainability notes in section 4. See "Resolution" at the end.

Performance is **not** a problem today (see "Measurements"). The real costs are the leaks, log spam and maintainability.

---

## 1. Memory leaks

### L1 (critical): every character leaks

`CharacterData` (a `Resource`, so reference-counted) creates six managers in `_init`:

```gdscript
status_manager = StatusEffectManager.new(self)
buff_manager = BuffDebuffManager.new(self)
skill_manager = SkillProgressionManager.new(self)
proficiency_manager = ProficiencyManager.new(self)
elemental_resistances = ElementalResistanceManager.new(self)
talents = TalentManager.new(self)
```

Each manager stores `var character: CharacterData`, a **strong** reference back to its owner. Godot 4 frees a `RefCounted` only when its count reaches zero; a cycle never does. So **no character is ever freed**, together with everything it holds (skills, inventory, gear, status data).

**Measured** (weakref check after releasing every reference):

| Created | Still alive | Objects left behind |
|---|---|---|
| 200 enemies (`EnemyFactory.create_enemy`) | **200 / 200** | +4,733 (about 24 each) |
| 50 NPC heroes (`AutoBattler.build_hero`) | **50 / 50** | +1,718 (about 34 each) |
| 1 NPC real battle (hero + boss) | - | +75 |
| Full smoke suite, at exit | - | **5,120 leaked instances** |

**Where it bites in play:**
- Every enemy of every wave.
- Every boss.
- Every NPC "big moment" battle (boss hunts and trials, daily).
- Every companion rebuilt per expedition.
- Every encounter combatant.
- The Town "Combos" button, which builds the party's heroes on each click.

A long session grows memory without bound.

**Fix (tested):** keep the same `character` name but make it weak, in all six managers:

```gdscript
## Weak back-reference: the character owns this manager, so a strong
## reference here would be a cycle and neither would ever be freed.
var _character_ref: WeakRef
var character: CharacterData:
	get: return _character_ref.get_ref() if _character_ref else null
	set(value): _character_ref = weakref(value) if value else null
```

Files:
- `scripts/resources/TalentManager.gd`
- `scripts/resources/StatusEffectManager.gd`
- `scripts/resources/BuffDebuffManager.gd`
- `scripts/resources/SkillProgressionManager.gd`
- `scripts/ElementalResistanceManager.gd`
- `scripts/autoload/ProficiencyManager.gd`

Result: **0 / 200** enemies and **0 / 50** heroes alive after release. The leak test's memory dropped from 54.6 MB to 37.2 MB. All smoke checks pass.

### L2 (high): `last_attacker` cycle

`CharacterData.last_attacker` (used for reflect damage) is a strong reference. When the hero hits an enemy and the enemy hits back, each holds the other, so both survive the battle.

**Fix (tested):** the same weak-property pattern on `last_attacker`.

With **L1 + L2** applied, the full smoke suite reports **0 leaked instances at exit** (was 5,120) and still passes 312/312.

### L3 (low): the scene stack only grows

`navigate(..., PUSH)` (Shop, Guild, Tavern, Alchemist, Blacksmith, Talents) appends `{path, character, data}` to `scene_stack`. Those screens go back through `change_to_town()`, a **REPLACE** that never pops. Each visit leaves one stale entry.

Scenes themselves are freed correctly (`queue_free` in `_deferred_load`, measured 0 orphan nodes), so this is a small dictionary per visit. It also means `return_to_previous_scene()` can pop an unrelated, stale entry.

**Fix:** clear `scene_stack` when replacing to Town. Or have town screens "go back" with POP and keep PUSH/POP paired.

### L4 (low): unbounded save growth

`town_state["adventurers"].list` keeps fallen and retired adventurers forever (about 5–10 per 90 days). News (40) and per-NPC history (10) are already capped. **Fix:** keep the last ~30 departed.

### Checked and clean

| Area | Result |
|---|---|
| Signals from scenes to autoloads (`BattleUIController` → `GuildManager.progress_message` lambda) | Godot drops the connection when the scene is freed: 0 connections after 5 battles |
| Battle scene nodes | 0 orphan nodes after 5 battle scenes freed |
| Equipment generation | 0 objects left after 200 rolls |
| Party, encounter and target dialogs | Freed (`queue_free`) after use |
| Static caches (`TalentManager._data`, `EnemyArchetypes._data`, `Combos._cfg`, factory caches) | Intentional, loaded once. They are the "N resources still in use at exit" message, which is harmless |

---

## 2. Deprecated and dead code

### D1: dead code to delete

| Item | Size | Status |
|---|---|---|
| `legacy/` | 1,017 lines | `.gdignore`d, nothing references it. Git history keeps it |
| `BossFactory` autoload | 59 lines | **0 uses**, but it still loads `races.json` and `classes.json` at startup |
| `LootManager` autoload | 107 lines | **0 uses** |
| `CharacterFactory.create_boss` / `create_enemy` | - | 0 uses (EnemyFactory does this) |
| `EnemyGroup.get_strongest_enemy / get_weakest_enemy / get_random_living_enemy / get_total_xp` | - | 0 uses |
| `DungeonStateManager.get_state_summary` | - | 0 uses |
| `ElementalDamage.try_apply_status` | - | 0 uses (also uses the global RNG) |
| `data/oldskills.json`, `data/skills.json1333019251.tmp` | 11 KB | Not read by anything |

### D2: the code's own deprecated API is still used

`SceneManager` marks `change_scene()`, `push_scene()` and `pop_scene()` as deprecated (they `push_warning`). They are still called **13 times** in:
- `MainMenu`, `CharacterSelection`, `CharacterCreation`
- `TownScene`, `ShopScene`, `RewardScene`
- `Main/Main.gd`

Replace them with `navigate()` / `change_to_*()` and delete the wrappers.

`CharacterData` keeps "LEGACY ACCESSORS" (`skills`, `status_effects`, `buffs`, `debuffs`, `skill_cooldowns`, `skill_levels`) that forward to the managers. `skills` is used everywhere and is fine to keep as API. The others have about 10 uses and could call the managers directly. Note that `status_effects` returns a **copy**, which has already caused one bug ("clearing it did nothing").

### D3: Godot 3-style signals (valid in 4.4, but untyped)

- 52 × `connect("pressed", Callable(self, "_on_x"))` in 10 files: MainMenu, CharacterSelection, CharacterCreation, TownScene, Shop, Inventory, Stash, LevelUp, BattleCompleteDialog, PointLight2D.
- 39 × `emit_signal("x")`.

The typed forms (`button.pressed.connect(_on_x)`, `x.emit()`) are checked when the script is parsed, so a renamed signal or method fails immediately instead of silently at runtime.

### D4: path probing with the wrong case

`EquipmentKeyHelper._load_caches()` tries four paths per item file, including `res://Data/...` with a capital D. That works in the editor, but exported packs are case-sensitive. It's harmless today because the first path hits, but it should use one path from a central registry (O2).

### Comment debt

60 "CRITICAL FIX", "ADD THIS", "FIX:" and "NEW:" markers left from past fixes (plus emoji in comments and prints). They describe old history, not the current code. Clean them up in passing.

---

## 3. Optimization

### O1: logging

There are **495** `print()` calls. The busiest files:

| File | prints |
|---|---|
| `StatusEffectManager` | 32 |
| `CombatEngine` | 23 |
| `EnemyAI` | 18 |
| `BossAI` | 17 |
| `CharacterData` | 17 |
| `ItemManager` | 15 |

Many run per action, per status tick or per enemy created (e.g. `[ALLIES] Found N allies`, `[ELEMENTAL] Initialized...`, `[STATUS MGR] Got data...`). Costs:
- Formatting and stdout I/O on every turn. One full balance-sim run produced a **1.3 GB** log.
- They bury real errors in the output.
- They ship in release builds.

**Fix:** a small `Log` autoload (`Log.debug/info/warn/error`, a per-category level, `OS.is_debug_build()` gate), then convert the hot paths first.

### O2: one data registry

| File | Parsed in |
|---|---|
| `classes.json` | 7 places |
| `races.json` | 5 places |
| `items/weapons.json`, `items/armors.json` | 3 each |
| `status_effects.json`, `skills.json` | 2 each |

`SaveManager` re-reads `classes.json` on every load. Some systems cache in a static var, some in an autoload, some not at all.

**Fix:** a `DataRegistry` autoload that parses each file once and exposes typed getters. It also gives one place to **hot-reload** after editing in the Content Manager, which today needs a restart because of the static caches.

### O3: determinism

`EnemyAI`/`BossAI` roll their personality (aggression, intelligence, desperation) with the global `randf_range`, while everything else uses `RandomManager`. That makes balance runs and future replays non-reproducible from a seed. Use `RandomManager`.

### O4: one hero policy

`AutoBattler.hero_policy` (companions on Auto, NPC real battles) and `tests/balance_sim.gd` `player_policy` are two copies of the same logic, and they have already drifted: the sim's copy has no revive. Make the sim call `AutoBattler`, so balance numbers match the in-game Auto.

### O5: data in code

These belong in data files (and the Content Manager):
- `ShopManager.consumable_inventory` prices.
- `EnemyFactory` `ENEMY_HP_MULT`, `ENEMY_DAMAGE_MULT`, `BOSS_*`.
- The AI personality ranges.

### Measurements (current code)

| Operation | Time |
|---|---|
| `SaveManager.save_game` (60 days in, full roster) | ~2 ms, 27 KB file |
| `EnemyFactory.create_enemy` | ~1.3 ms |
| `AutoBattler.build_hero` | ~3 ms |
| Build hero + one real boss fight | ~29 ms |
| One world day (NPC simulation) | ~18 ms (3-night Inn rest ≈ 55 ms) |

No hot spot needs work now. Watch the world day as the roster and real battles grow; it's the first thing to profile if resting ever feels slow.

---

## 4. Maintainability notes

- **Large files:**
  - `tests/battle_smoke_test.gd` (1,556 lines): split by system into `tests/smoke/*.gd`.
  - `CharacterData` (852), `BattleUIController` (783), `Skill` (733).
- **PvP (`BattleNetworkSync`, 569 lines):** not covered by any test since the party and encounter changes. It still loads, but it's the most likely place for silent breakage. Add a loopback test or flag it as experimental.
- **Duck typing:** 38 `has_method("...")` checks, mostly in scene setup. They're fine, but typed scene scripts would let the parser catch mistakes.

## 5. Suggested order

1. **L1 + L2 leak fixes** (tested; about 20 lines) plus a smoke check that asserts characters are freed. This is the biggest win.
2. **D1 dead code** and **D2** deprecated SceneManager calls, plus **L3** stack clearing.
3. **O1 `Log` autoload**, converting battle and status hot paths first.
4. **O2 `DataRegistry`** (removes D4 and gives hot-reload).
5. **D3** typed signals, **O3** RNG, **O4** single policy, **O5** data-driven tuning, **L4** cap.
6. Split the smoke test; add a PvP loopback test.

## Resolution

| # | Fixed in | Result |
|---|---|---|
| L1, L2 | `cc7a38c` | Weak back-references. Smoke-test leaks at exit: 5,120 → **0**. A new check asserts released characters are freed |
| L3, L4, D1, D2 | `334b439` | 1,833 lines removed; deprecated SceneManager calls replaced; REPLACE clears the back-stack; last 30 departed NPCs kept |
| O1 | `4204196` | `Log` autoload; all 495 prints converted. Smoke log 1.69 MB → 17 KB; balance sim 96 MB → 244 bytes and 11% faster |
| O2, D4 | `a2a7ee1` | `DataRegistry`: 36 loaders → one; each file parsed once (23 loads per smoke run); `reload()`; the orphaned `StatusEffectData.gd` duplicate deleted |
| D3, O3, O4, O5 | step 5 | 57 connections and 39 emits now typed; AI personality via `RandomManager` with ranges in data; the balance sim uses `AutoBattler.hero_policy` (one policy, same balance band); shop prices in `data/shop.json`, enemy scaling in `enemy_archetypes.json` "scaling" (Content Manager tabs Shop and Enemy Archetypes) |

**Still open:** section 4 (split the big files and the smoke test; a PvP loopback test; the ~60 old "FIX:" comment markers).
