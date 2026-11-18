# Legacy scripts

These scripts were superseded or were never wired into the game. They are kept for
reference only.

The `.gdignore` file in this folder makes Godot skip everything here. The scripts
are not compiled, their `class_name`s are not registered, and they can't conflict
with live code. To revive one, move it back out of `legacy/` and fix its references.

| File | Why it's here |
|---|---|
| `scripts/autoload/BattleOrchestrator.gd` | The original single-enemy orchestrator, superseded by `scenes/battle/BattleOrchestrator.gd`. It was not registered as an autoload and had a parse error. |
| `scripts/BattleManager.gd` | The old battle manager, used only by `WaveBattle`. |
| `scenes/WaveBattle.gd` / `.tscn` | The old wave battle scene. Nothing loads it, and it had a parse error (`BattleManager` has no `class_name`). |
| `scripts/combat/CombatManager.gd`, `TurnManager.gd`, `BattleUIManager.gd`, `CombatActions.gd` | The pre-refactor combat layer, replaced by `scenes/battle/core` and `flow`. `CharacterData.attack()`, which used `CombatActions`, was removed with it. |
| `scenes/battle/BossPhaseIndicator.gd` | An empty stub. |
| `scripts/network/ArenaNetworkAdapter.gd`, `RemotePlayerController.gd` | An unused PvP prototype. The live PvP code is `ArenaNetworkManager` and `BattleNetworkSync`. |
| `scripts/systems/ProgressionManager.gd`, `ResourceManager.gd` | Static utilities extracted from CharacterData but never called. |
| `scripts/autoload/EquipmentDebugLogger.gd` | A debug helper that was never registered as an autoload. |
