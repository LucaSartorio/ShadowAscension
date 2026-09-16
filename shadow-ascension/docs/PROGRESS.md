# ShadowAscension — Progress

> **Maintenance note:** This file MUST be kept in sync with the actual state of the project. Update it whenever a milestone changes status, a task moves between sections, or a blocker appears/clears. Stale progress data is worse than none.

---

## Current Milestone

**M2 — Basic Combat** (In Progress)

First iteration delivers the combat foundation: light attack, `HealthComponent`, `Hitbox`, `Hurtbox`, damage pipeline, and a training dummy that dies. Combo, heavy attack, dodge, sprint, stamina, mana, skills, weapons, inventory, lock-on, enemy AI, loot, and XP are **not** implemented — deferred to later iterations / milestones.

---

## Done

- Godot 4.7.x project created
- Git repository configured
- Claude Code configured
- Godot MCP installed
- Godot MCP connection verified
- `Main.tscn` created
- Project starts successfully
- Repository folder structure created
- `CLAUDE.md` created
- Documentation files created
- **M0 — Project Foundation** (Completed)
- **M1 — Player Controller** (Completed). Delivered:
    - `scenes/player/player.tscn` — `CharacterBody3D` root with `CollisionShape3D`, `VisualRoot` (mesh), and `CameraRig → PitchPivot → SpringArm3D → Camera3D`
    - `scripts/player/player.gd` (`class_name Player`) — WASD camera-relative movement, 360° direction, diagonal normalization, `move_toward`-based acceleration/deceleration, gravity, `move_and_slide` collision, rate-limited `VisualRoot` yaw interpolation toward movement direction
    - `scripts/player/camera_rig.gd` (`class_name CameraRig`) — mouse-driven yaw (rig) and pitch (`PitchPivot`) with pitch clamp, `SpringArm3D` collision with player body excluded, mouse capture on `_ready`, ESC releases the mouse, left-click recaptures when visible
    - Exported tuning — Player: `movement_speed`, `acceleration`, `deceleration`, `rotation_speed`, `gravity`; CameraRig: `mouse_sensitivity`, `minimum_pitch`, `maximum_pitch`, `camera_distance`
    - `scenes/core/test_world.tscn` — floor, four walls, `DirectionalLight3D`, `WorldEnvironment`, `Player` instance
    - `Main.tscn` acts as bootstrap router, instancing `TestWorld` (no gameplay logic in Main)
    - Input map in `project.godot`: `move_forward` W, `move_backward` S, `move_left` A, `move_right` D (physical keycodes)
    - Validation: `godot --headless --path . --quit` clean; `--quit-after 120` clean; verbose scan for ERROR / WARNING / Failed / Parse Error returned no hits

---

## In Progress

- Game design definition — foundations defined:
    - third-person camera
    - WASD camera-relative movement
    - mouse-controlled aim
    - combat feel direction
  Still in progress: other systems (progression, loot, shadow mechanic, dungeon structure, UI, etc.) not yet defined.
- Technical architecture definition — grows as systems land.
- **M2 — Basic Combat** (In Progress). Implemented so far:
    - Reusable combat components under `scripts/combat/`:
        - `health_component.gd` (`class_name HealthComponent`, extends `Node`) — `max_health`, `current_health`, `is_dead`, `receive_damage()`, `heal()`, signals `health_changed(current, maximum)` and `died`. No entity-specific logic.
        - `hitbox.gd` (`class_name Hitbox`, extends `Area3D`) — `damage`, `source`, `activate()` / `deactivate()`, per-activation `_hit_targets` deduplication, emits `hit_landed(target, damage)`, toggles optional child `DebugMesh` for debug feedback.
        - `hurtbox.gd` (`class_name Hurtbox`, extends `Area3D`) — auto-resolves sibling `HealthComponent` and parent `owner_entity`, forwards hits to the `HealthComponent`, no `Player`/`Enemy` coupling.
    - Player light-attack pipeline in `scripts/player/player.gd`:
        - `AttackState` enum (`IDLE`, `STARTUP`, `ACTIVE`, `RECOVERY`) with per-phase timers `attack_startup_time`, `attack_active_time`, `attack_recovery_time` (defaults 0.15 / 0.15 / 0.25 — placeholders per `GAME_DESIGN.md`).
        - New attack starts only while `IDLE` (spam blocked during startup/active/recovery).
        - On attack start, `VisualRoot` snaps to aim/camera XZ direction; per-frame movement-rotation suppressed while attacking.
        - Hitbox activates only during the `ACTIVE` window and deactivates on transition to `RECOVERY`.
    - `CameraRig` (`scripts/player/camera_rig.gd`) refactor:
        - Emits `attack_light_pressed` signal only when the mouse is already captured.
        - Left-click while mouse is visible recaptures the mouse and consumes the event — no attack fires on the recapture click.
        - Signal-based binding so `Player` receives attack input without racing the mouse-mode toggle.
    - `Player` scene (`scenes/player/player.tscn`) — adds `AttackHitbox` (Area3D + child `CollisionShape3D` + debug `MeshInstance3D`) at `VisualRoot`-local `(0, 0.9, -1.2)`, size `1.4 × 1.4 × 1.6`, `Hitbox` script with `damage = 25`.
    - Training dummy:
        - `scripts/enemies/training_dummy.gd` (`class_name TrainingDummy`, extends `CharacterBody3D`) — subscribes to `HealthComponent.health_changed` and `died`, logs on hit, on death: disables body + hurtbox collision (deferred) and topples via a short `Tween` on `VisualRoot.rotation:x`. No AI.
        - `scenes/enemies/training_dummy.tscn` — `CharacterBody3D` with `CollisionShape3D`, `VisualRoot`, `HealthComponent` (`max_health = 100`), and `Hurtbox` with capsule shape.
    - Test world updated: `Player` + 2 `TrainingDummy` instances, extra walking room.
    - Input map: `attack_light` bound to left mouse button.
    - Collision layers/masks:
        - Layer 1: world/physics bodies (floor, walls, Player CharacterBody3D, Dummy CharacterBody3D).
        - Layer 4 (bit value 8): damage-dealing hitboxes. Player `AttackHitbox` on this layer.
        - Layer 5 (bit value 16): damage-receiving hurtboxes. Dummy `Hurtbox` on this layer.
        - Player `AttackHitbox`: `collision_layer=8`, `collision_mask=16`, monitoring toggled by state.
        - Dummy `Hurtbox`: `collision_layer=16`, `collision_mask=0`, `monitorable=true`.
    - Automated headless test — `tests/combat/attack_test.tscn` + `attack_test.gd`:
        - PASS: attack 1 deals 25 damage to dummy (100 → 75).
        - PASS: spam attempt during startup blocked (attack state unchanged).
        - PASS: 4 attacks kill the dummy (100 → 75 → 50 → 25 → 0), `died` signal fires.
    - Validation: `godot --headless --path . --quit-after 180` clean, no ERROR / WARNING / Failed / Parse Error / SCRIPT ERROR.

---

## Todo

- Complete `GAME_DESIGN.md` (systems beyond camera/movement/aim/combat feel)
- Complete `ARCHITECTURE.md` (fill out as systems land)
- Manual editor playtest of M1 + M2 combat feel (mouse aim, hit registration, dummy topple, spam-block feel)
- Playtest-tune M2 exported parameters (attack timings, damage, hitbox size/position)
- M2 remaining scope: combo foundation (input-buffered chain window), Player `HealthComponent` + `Hurtbox`, death of Player
- Close M2 once combo + player-side death land and playtest passes acceptance
- Start M3 — Enemy Foundation

---

## Blocked

None
