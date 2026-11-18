# Battle System

`Battle.tscn` is the battle scene. Its root script, `BattleOrchestrator.gd`, builds
the components below and runs **one explicit turn loop**. To follow a fight, read
`_run_battle_loop()` and `_run_turn()` top to bottom.

## Folder map

| Folder | What lives here | Touches the scene tree? |
|---|---|---|
| `core/` | Data and rules: what an action *is* and what it *does* | No |
| `flow/` | Turn order and the steps of a turn | Calls UI/visuals, owns no nodes |
| `ai/` | How enemies choose actions | No |
| `ui/` | What the player sees and clicks | Yes (Control nodes) |
| `visuals/` | Sprites, attack/death animations, camera shake | Yes (Node2D) |

## Components

| Script | Responsibility |
|---|---|
| `BattleOrchestrator.gd` | Scene root. Public setup API (`set_player`, `set_enemies`, `set_dungeon_info`, `setup_pvp_battle`), builds components, runs the turn loop, and routes player input. Emits `battle_completed(won, xp)` for SceneManager. |
| `core/BattleContext.gd` | Shared state for one battle: combatants, dungeon info, per-turn flags, `battle_over`. |
| `core/BattleAction.gd` | A request: attack / skill / item / defend, plus actor and targets. |
| `core/ActionResult.gd` | What happened: damage, healing, crit/miss/dodge, buffs, and the message. |
| `core/CombatEngine.gd` | Combat rules: damage formulas, skill/item resolution, status ticks. Pure logic. |
| `core/ReflectionInfo.gd` | Predicts reflected damage for the combat log. Reflection itself is applied only in `CharacterData.take_damage()`. |
| `flow/TurnQueue.gd` | Decides whose turn is next: rolls initiative by agility, rotates actors, and re-rolls each round. |
| `flow/TurnStartProcessor.gd` | Runs the start of a turn: clears Defend, ticks status effects, then returns `CAN_ACT`, `STUNNED` or `DIED`. |
| `flow/ActionExecutor.gd` | Executes one action: animation, then `CombatEngine`, then hit feedback, then the log. Returns `Outcome {result, dead}`. |
| `flow/BattleOutcomeHandler.gd` | Removes the dead and handles victory or defeat **once**, including the Press On / Breather dialog. |
| `ai/EnemyTurnPlanner.gd` | Keeps one AI per enemy and returns a valid `BattleAction` for the enemy's turn. |
| `ai/EnemyAI.gd`, `ai/BossAI.gd` | Decision logic. Bosses add phases, enrage and an opener. |
| `ui/BattleUIController.gd` | HUD, combat log, action buttons, skill menu, inspect dialogs. Emits `action_selected(BattleAction)`. |
| `ui/TargetSelector.*`, `ui/InventoryMenu.gd` | Target picker and in-battle item picker. |
| `visuals/BattleVisualManager.gd` | Enemy sprites, animations, screen shake. |

PvP: `scripts/network/BattleNetworkSync.gd` is created by the orchestrator in PvP
mode. It calls `finish_remote_turn()` when the opponent's action arrives and
`end_battle_from_network()` when the other client decides the match.

## One turn

```
TurnQueue.current_actor()
  -> TurnStartProcessor.run(actor)        DIED -> handle_deaths, STUNNED -> skip
  -> player : wait for UI action_selected -> ActionExecutor.execute()
     enemy  : EnemyTurnPlanner.plan_action -> ActionExecutor.execute(announce)
     remote : wait for BattleNetworkSync.finish_remote_turn()
  -> BattleOutcomeHandler.handle_deaths(outcome.dead)
  -> BattleOutcomeHandler.check_battle_end()  (victory/defeat runs once)
  -> TurnQueue.advance()
```

Items are a free action: one per turn, and they don't end the turn. Attack, Skill
and Defend end the turn.
