# ShadowAscension — Progress

> **Maintenance note:** This file MUST be kept in sync with the actual state of the project. Update it whenever a milestone changes status, a task moves between sections, or a blocker appears/clears. Stale progress data is worse than none.

---

## Current Milestone

**M3 — Enemy Foundation** (In Progress)

First iteration delivered: `BasicMeleeEnemy` scene + local enum state machine (IDLE / CHASE / ATTACK / DEAD), player detection via distance + `player` group, chase via `NavigationAgent3D` with periodic target updates, telegraphed melee attack that flows through the existing `Hitbox` / `Hurtbox` / `HealthComponent` pipeline, hit-flash feedback, death state that disables body/hurtbox/hitbox and topples the visual. Test world updated with `NavigationRegion3D` + 3 concrete enemies + navigation-obstacle wall.

---

## Done

- Godot 4.7.x project created
- Git repository configured
- Claude Code configured
- Godot MCP installed / verified
- `Main.tscn` created
- Project starts successfully
- Repository folder structure created
- `CLAUDE.md` created
- Documentation files created
- **M0 — Project Foundation** (Completed)
- **M1 — Player Controller** (Completed)
- **M2 — Basic Combat** (Completed). Exit criteria verified:
    - Attack registers on stationary dummy — combo test #1 (dmg = 20)
    - Combo chains within window, resets outside — combo tests #2, #3, #6 (Attack 1+2 = 45, full combo = 80, two Attack 1s across `combo_reset_time` = 40)
    - Hitboxes activate only during attack frames — dodge test #15 (post-cancel `active=false, monitoring=false`) + combo test #7 (single swing hits exactly once)
    - Damage values match expected — combo tests #1–#4 (20 / 25 / 35 per step)
    - Death transition clean, no orphan nodes / errors — dummy topple + collision disable on `died`; Player `HealthComponent.died` fires cleanly, no crash. Player-side death *reaction* (input lockout) deferred as polish, not blocking.
    - Additional M2.3 deliverables also verified: dodge direction / diagonals normalized / backstep / direction latch / wall collision / cooldown; i-frame timing + damage gating; per-step attack cancel windows (0.0 / 0.35 / 0.6); hitbox cleanup on cancel; combo state reset by dodge; spam-Space state integrity.
    - Automated validation: `attack_test.tscn` 10/10 PASS, `dodge_test.tscn` 18/18 PASS, Main.tscn 300 frames zero ERROR/WARNING/Failed/Parse Error/SCRIPT ERROR.
- **M2 progress — Combat Foundation**:
    - `HealthComponent`, `Hitbox`, `Hurtbox` reusable components under `scripts/combat/`
    - Damage pipeline: `Hitbox.area_entered` → `Hurtbox.receive_hit` → `HealthComponent.receive_damage`
    - Training dummy with sibling `HealthComponent`, `Hurtbox`, on-death disable + topple tween. No AI.
- **M2 progress — 3-Step Light Combo**:
    - `AttackStep` Resource (`scripts/combat/attack_step.gd`) — data-only, per-step tuning
    - Player exports `combo_steps: Array[AttackStep]` and `combo_reset_time`
    - 3 combo steps as inline sub-resources in `player.tscn`
    - Attack 1: dmg 20, 0.12 / 0.12 / 0.22
    - Attack 2: dmg 25, 0.14 / 0.14 / 0.24
    - Attack 3: dmg 35, 0.18 / 0.16 / 0.32
    - Single-slot input buffer, spam bounded to next step, combo termination after Attack 3, `combo_reset_time` = 0.8
    - Per-step aim orientation, per-step debug color, `VisualRoot.rotation:z` tween per step (bigger tilt on Attack 3)
    - `Hitbox.set_debug_color()` swaps material tint per swing; material duplicated on `_ready` for per-instance state
- **M2 progress — Dodge, i-Frames, Attack Cancel Windows** (M2.3):
    - Input action `dodge = Space` in `project.godot`
    - Player exports: `dodge_duration = 0.35`, `dodge_speed = 11.5`, `invulnerability_start = 0.06`, `invulnerability_end = 0.24`, `dodge_cooldown = 0.15`, `dodge_visual_tilt_degrees = -15`
    - Dodge direction: camera-relative on XZ when movement input present, backstep along `-VisualRoot.forward` when no input; diagonals normalized via `Input.get_vector`
    - Dodge uses `move_and_slide` with `dodge_direction * dodge_speed` — respects world collisions, no teleport, no wall clipping
    - Direction latched at dodge start; cannot be changed mid-dodge; cannot restart another dodge until current + cooldown finish
    - Player `Hurtbox` extended with `is_invulnerable` flag + `set_invulnerable(value)`; `receive_hit` ignores damage while invulnerable — no dodge-specific logic in `HealthComponent`
    - i-frame window driven by `Player._tick_dodge`: enables `Hurtbox.set_invulnerable(true)` when `_dodge_elapsed ∈ [invulnerability_start, invulnerability_end)`, disables otherwise, ensures cleanup on `_end_dodge`
    - `AttackStep.dodge_cancel_recovery_fraction` — per-step fraction of recovery after which dodge can cancel the attack
        - Attack 1: 0.0 (immediate on recovery)
        - Attack 2: 0.35
        - Attack 3: 0.6
    - `Player._in_cancel_window()` gates dodge input during attacks. Startup and Active always block dodge. Recovery admits dodge once `_recovery_elapsed >= recovery * fraction`
    - `Player._cancel_current_attack()` deactivates any active Hitbox, resets `_attack_state`, `_attack_timer`, `_recovery_elapsed`, `_combo_index`, `_queued_next`, `_idle_since_step_ended`, `_current_step` — no dangling active hitbox after cancel
    - `_start_dodge()` also resets combo state (`_combo_index = 0`, `_queued_next = false`) so next attack after any dodge starts fresh at Attack 1
    - `VisualRoot.rotation:x` tween lean forward during dodge for prototype visual feedback (kills any conflicting attack tween)
    - Player `HealthComponent` + `Hurtbox` added to `player.tscn`. Collision layers:
        - Layer 8: player-dealt hitboxes (Player AttackHitbox)
        - Layer 16: enemy hurtboxes (Dummy Hurtbox)
        - Layer 32: enemy-dealt hitboxes (test-only debug damage zone)
        - Layer 64: player hurtboxes (Player Hurtbox)
        - Player AttackHitbox: layer 8, mask 16. Dummy Hurtbox: layer 16, mask 0. Player Hurtbox: layer 64, mask 0. Debug damage zone: layer 32, mask 64.
    - Debug damage zone in `test_world.tscn` — Area3D + `tests/combat/debug_damage_zone.gd`, ticks damage every 0.5s on overlapping Hurtboxes, layer 32 mask 64, clearly marked as prototype/test object; only damages Player (not dummies)
    - `_unhandled_input` on Player consumes the `dodge` action and calls `_on_dodge_pressed`
- Automated headless validation:
    - **Combo test** `res://tests/combat/attack_test.tscn` — 10/10 PASS (single click, chained combo, spam bounding, reset time, per-swing dedup, out-of-range, multi-target, orientation)
    - **Dodge test** `res://tests/combat/dodge_test.tscn` — 18/18 PASS:
        1. W+Space → forward dodge direction
        2. W+D diagonal → normalized dodge direction
        3. Space with no input → backstep along `+VisualRoot.z`
        4. Direction latched mid-dodge (changing input mid-dodge has no effect)
        5. Dodge blocked by wall (`move_and_slide` collision honored)
        6. Second dodge during current dodge is blocked (direction unchanged)
        7. Cooldown: mid-cooldown blocked, past-cooldown allowed
        8. i-frame timing: false before 0.06, true in [0.06, 0.24), false after
        9. Damage ignored during i-frames
        10. Damage applied outside i-frames (25 damage → 100 → 75)
        11. Attack 1 not cancelable during Startup / Active
        12. Attack 1 cancelable during Recovery (fraction 0.0)
        13. Attack 2 cancel window (blocked early, allowed after 35% of recovery)
        14. Attack 3 cancel window (blocked early, allowed after 60% of recovery)
        15. `attack_hitbox.is_active()` and `.monitoring` both false after cancel
        16. `_queued_next` cleared and `_combo_index` reset to 0 on dodge cancel
        17. `_combo_index == 0` after dodge + cooldown (next attack starts at Attack 1)
        18. Spam Space (20 rapid calls) leaves player state valid; subsequent single dodge works
    - `godot --headless --verbose --path . --quit-after 180` on `Main.tscn` — no ERROR / WARNING / Failed / Parse Error / SCRIPT ERROR

---

## In Progress

- **M3 — Enemy Foundation** (In Progress). Implemented:
    - `scripts/enemies/basic_melee_enemy.gd` (`class_name BasicMeleeEnemy`) — local enum state machine `State { IDLE, CHASE, ATTACK, DEAD }` and `AttackPhase { NONE, STARTUP, ACTIVE, RECOVERY }`. No generic StateMachine framework; no `EnemyManager` / `AIManager` singleton.
    - `scenes/enemies/basic_melee_enemy.tscn` — `CharacterBody3D` root + `CollisionShape3D` + `VisualRoot` (mesh + `AttackOrigin` + `Hitbox`) + `NavigationAgent3D` + `HealthComponent` + `Hurtbox`. All combat components reused from M2 (no duplication).
    - Player detection: `distance_to(player.global_position) < detection_range`; Player added to group `player`; enemy caches the reference lazily via `get_tree().get_first_node_in_group("player")` — no per-frame tree scan.
    - Hysteresis: separate `detection_range` (10) and `lose_target_range` (14) prevent oscillation at the edge.
    - Navigation: `NavigationAgent3D` with `target_position` updated every 0.2s; `get_next_path_position()` drives velocity via `move_toward` + `move_and_slide`. `NavigationRegion3D` in test world bakes `NavigationMesh` from static colliders on `_ready`. Nav test confirms an enemy behind a wall from the player pathfinds sideways rather than stalling against geometry (2.23u sideways displacement over 3s, final z crossed the wall front).
    - Chase rotation: `VisualRoot` yaws toward movement direction at `rotation_speed` rad/s — no snap.
    - Attack: on entering `attack_range`, enemy snaps `VisualRoot` yaw once to face the player and enters `STARTUP`. Telegraph = short `VisualRoot.scale` tween up during startup. `Hitbox.activate()` only during `ACTIVE`. `Hitbox.deactivate()` on transition to `RECOVERY`. After recovery, `attack_cooldown` (0.4s) blocks re-entry to `ATTACK` and enemy returns to `CHASE`.
    - Damage: enemy → player exclusively via `Hitbox` → `Hurtbox` → `HealthComponent`. No `player.take_damage()` shortcuts. Player's dodge i-frames automatically block damage through the existing `Hurtbox.is_invulnerable` gate.
    - Hit feedback: enemy `mesh_instance.scale` pulses on `health_changed` when HP decreases. No stagger system, no interruption of movement/nav.
    - Death: on `HealthComponent.died` → state `DEAD`, `velocity = 0`, hitbox deactivated, body collision + hurtbox collision + hurtbox monitorable all disabled via `call_deferred`, `VisualRoot` topples via short rotation tween. Dead enemy skips `_physics_process`. Verified no further attacks / no damage post-death.
    - Player integration: Player added to `player` group in `_ready`; existing `HealthComponent` + `Hurtbox` from M2.3 reused unchanged; no HUD.
    - Collision layers (documented):
        - Layer 1: world + physical bodies (floor, walls, Player body, Enemy body, Dummy body)
        - Layer 8: player-dealt hitbox (Player `AttackHitbox`, mask 16)
        - Layer 16: enemy-receiving hurtboxes (Dummy `Hurtbox`, Enemy `Hurtbox`; mask 0)
        - Layer 32: enemy-dealt hitbox + debug damage zone (Enemy `Hitbox`, DebugDamageZone; mask 64)
        - Layer 64: player-receiving hurtbox (Player `Hurtbox`; mask 0)
    - Test world (`scenes/core/test_world.tscn`) updated: `NavigationRegion3D` wraps floor + walls + big wall (`8x3x1` at z=10); 3 `BasicMeleeEnemy` instances at distinct positions; existing 2 `TrainingDummy` + `DebugDamageZone` preserved (dummy on layer 16 still hit by player attacks; debug zone on layer 32 targets layer 64 so it damages Player without affecting dummies). `scripts/core/test_world.gd` synchronously bakes the nav mesh in `_ready`.
    - NavigationMesh tuning: `cell_size = 0.25`, `cell_height = 0.25`, `agent_radius = 0.5`, `agent_height = 2.0`, `agent_max_climb = 0.5`, `geometry_parsed_geometry_type = 1` (STATIC_COLLIDERS). Avoids the RenderingServer parse + agent-value rounding warnings that fired with defaults.
    - Automated headless validation `res://tests/enemies/enemy_test.tscn` — **14/14 PASS**:
        1. Enemy IDLE when player > `detection_range`
        2. Enemy CHASE when player < `detection_range`
        3. Enemy ATTACK when player < `attack_range`
        4. Attack phase gating: hitbox off during STARTUP + telegraph visible; hitbox on during ACTIVE; hitbox off during RECOVERY
        5. Enemy deals exactly 15 damage to Player (`100 → 85`)
        6. Player dodge i-frame during ACTIVE avoids enemy damage
        7. Attack cooldown: enemy returns to CHASE with cooldown active; re-attacks after cooldown expires
        8. Player > `lose_target_range` → enemy back to IDLE
        9. Player Attack 1 damages enemy 20
        10. Player full combo damages enemy 80
        11. Enemy dies (`state = DEAD`, hitbox off, body collision disabled, hurtbox not monitorable, `velocity == 0`)
        12. Dead enemy in attack range deals no damage and stays DEAD
        13. 3 concurrently spawned enemies all reach CHASE independently
        14. Navigation around big wall (`2.23u` sideways, crosses wall Z from 13.6 to 4.28 over 3s)
    - Regression: combo suite 10/10 PASS, dodge suite 18/18 PASS, `Main.tscn` 240 frames verbose scan zero ERROR / WARNING / Failed / Parse Error / SCRIPT ERROR.
- Game design definition — foundations defined:
    - third-person camera
    - WASD camera-relative movement
    - mouse-controlled aim
    - combat feel direction
  Still in progress: progression, loot, shadow mechanic, dungeon structure, UI, etc.
- Technical architecture definition — grows as systems land.

---

## Todo

- Complete `GAME_DESIGN.md` (systems beyond camera/movement/aim/combat feel)
- Complete `ARCHITECTURE.md` (fill out as systems land)
- Manual editor playtest of M1 + M2 + M3 (feel-tuning: numbers only, not blocking)
- Player-side death reaction (input lockout, visual state) — polish, deferred
- Playtest-tune M3 enemy parameters (detection ranges, attack timings, damage, speed)
- Optional M3 polish: enemy variants, more expressive telegraph, per-enemy drop hook stub
- Close M3, then start M4 — Dungeon Foundation

---

## Blocked

None
