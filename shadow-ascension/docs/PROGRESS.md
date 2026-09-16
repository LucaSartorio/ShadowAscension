# ShadowAscension — Progress

> **Maintenance note:** This file MUST be kept in sync with the actual state of the project. Update it whenever a milestone changes status, a task moves between sections, or a blocker appears/clears. Stale progress data is worse than none.

---

## Current Milestone

**M2 — Basic Combat** (In Progress)

Two iterations delivered so far:
- **M2.1 — Combat Foundation**: `HealthComponent`, `Hitbox`, `Hurtbox`, damage pipeline, single light attack, training dummy with death behavior.
- **M2.2 — Light Attack Combo**: 3-step light combo (Attack 1 → 2 → 3), per-step data via `AttackStep` Resource, input buffering (single-deep), combo reset after `combo_reset_time`, per-step aim orientation, per-step debug feedback (color + tilt tween).

Next iteration: **M2.3 — Dodge and Combat Cancel Windows** (not started).

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
- **M1 — Player Controller** (Completed)
- **M2 progress — Combat Foundation** (delivered within M2):
    - `scripts/combat/health_component.gd` — reusable `HealthComponent` (max/current/is_dead, `receive_damage`, `heal`, signals `health_changed`, `died`)
    - `scripts/combat/hitbox.gd` — reusable `Hitbox` (Area3D, `activate`/`deactivate`, per-activation target dedup, `hit_landed` signal, optional debug mesh visualization, `set_debug_color`)
    - `scripts/combat/hurtbox.gd` — reusable `Hurtbox` (Area3D, auto-wires sibling `HealthComponent` + parent `owner_entity`, `receive_hit` forwards to health, no Player/Enemy coupling)
    - Damage pipeline: `Hitbox.area_entered` → `Hurtbox.receive_hit` → `HealthComponent.receive_damage`
    - Training dummy (`scripts/enemies/training_dummy.gd`, `scenes/enemies/training_dummy.tscn`): CharacterBody3D + HealthComponent + Hurtbox; logs hits; on death disables body/hurtbox collisions and topples via short tween. No AI.
- **M2 progress — Single Light Attack Foundation** (delivered within M2, then upgraded in M2.2):
    - Player attack state machine (`AttackState` enum: `IDLE / STARTUP / ACTIVE / RECOVERY`) with per-phase timers
    - Hitbox activation only during the `ACTIVE` window
    - Player faces aim/camera XZ direction at attack start
    - New attack blocked until state returns to `IDLE`
- **M2 progress — 3-Step Light Combo** (M2.2):
    - `scripts/combat/attack_step.gd` — `class_name AttackStep extends Resource` with `damage`, `startup`, `active`, `recovery`, `debug_color`, `visual_tilt_degrees`. Small dedicated Resource; no generic ability framework.
    - Player exports `combo_steps: Array[AttackStep]` and `combo_reset_time` (default 0.8).
    - 3 combo steps defined as inline sub-resources in `scenes/player/player.tscn`:
        - Attack 1 — damage 20, startup 0.12, active 0.12, recovery 0.22
        - Attack 2 — damage 25, startup 0.14, active 0.14, recovery 0.24
        - Attack 3 — damage 35, startup 0.18, active 0.16, recovery 0.32
    - `_combo_index` tracks next step to fire. Cycles 0 → 1 → 2 → 3-then-wraps-to-0.
    - Input buffer: single-deep `_queued_next` flag. Additional presses while `_attack_state != IDLE` set the flag but do not accumulate. Fires the next combo step at the end of `RECOVERY` if buffered.
    - Spam bounded: 10+ rapid clicks in one frame result in at most 2 landed attacks (Attack 1 + queued Attack 2), never a runaway chain.
    - Combo termination: when `_combo_index` reaches `combo_steps.size()` at end of `RECOVERY`, index resets to 0 and the queued flag is cleared. Next click starts a fresh Attack 1.
    - Combo reset: while `_attack_state == IDLE` and `_combo_index > 0`, an idle timer counts up. If it exceeds `combo_reset_time`, the index resets to 0.
    - Per-step aim orientation: `_face_aim_direction()` snaps `VisualRoot.rotation.y` to the camera XZ forward each time a step starts (not the movement direction).
    - Per-step target de-dup: `Hitbox._hit_targets` is cleared on each `activate()`, so every swing can damage each target at most once but consecutive combo steps can hit the same target again.
    - Per-step debug feedback: `Hitbox.set_debug_color()` swaps the debug mesh tint per step, `VisualRoot.rotation:z` tweens by `visual_tilt_degrees` and back (bigger tilt on Attack 3 for a slightly weightier prototype feel).
    - Hitbox damage is written from `_current_step.damage` on activation each swing.

---

## In Progress

- Game design definition — foundations defined:
    - third-person camera
    - WASD camera-relative movement
    - mouse-controlled aim
    - combat feel direction
  Still in progress: other systems (progression, loot, shadow mechanic, dungeon structure, UI, etc.) not yet defined.
- Technical architecture definition — grows as systems land.
- **M2 — Basic Combat** (In Progress). Remaining scope before M2 close:
    - Player-side `HealthComponent` + `Hurtbox` + death state
    - Combat cancel windows (dodge cancels recovery, etc.) — landing with **M2.3 — Dodge and Combat Cancel Windows**
    - Playtest-tuning of combo timings and damages
- Automated headless verification for M2.2 (`res://tests/combat/attack_test.tscn`) — 10/10 tests PASS:
    1. Single click → Attack 1 dmg = 20
    2. Two clicks → Attack 1 + Attack 2 = 45
    3. Three clicks → full combo = 80
    4. After Attack 3 next click starts Attack 1 (dmg 20)
    5. Spam 10 rapid clicks → only 2 attacks land (dmg 45)
    6. Two Attack 1s separated by > `combo_reset_time` → dmg 40 (combo restarted)
    7. Single swing hits each target exactly once
    8. Out-of-range attack deals 0 damage
    9. Two dummies inside hitbox both take 20 dmg
    10. After camera yaw = 90°, player yaw snaps to +π/2 at attack start

---

## Todo

- Complete `GAME_DESIGN.md` (systems beyond camera/movement/aim/combat feel)
- Complete `ARCHITECTURE.md` (fill out as systems land)
- Manual editor playtest of M1 + M2 combat feel (mouse aim, hit registration, dummy topple, combo cadence, spam-block feel, per-step debug feedback)
- Playtest-tune M2 combo values (damages, timings, hitbox size/position, `combo_reset_time`)
- **M2.3 — Dodge and Combat Cancel Windows** (next iteration inside M2)
- Player-side `HealthComponent` + `Hurtbox` + death, then close M2
- Start M3 — Enemy Foundation

---

## Blocked

None
