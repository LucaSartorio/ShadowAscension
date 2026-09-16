# ShadowAscension — Progress

> **Maintenance note:** This file MUST be kept in sync with the actual state of the project. Update it whenever a milestone changes status, a task moves between sections, or a blocker appears/clears. Stale progress data is worse than none.

---

## Current Milestone

**M2 — Basic Combat** (In Progress)

Iterations delivered so far:
- **M2.1 — Combat Foundation**: `HealthComponent`, `Hitbox`, `Hurtbox`, damage pipeline, single light attack, training dummy with death behavior.
- **M2.2 — Light Attack Combo**: 3-step light combo, per-step `AttackStep` Resource, single-slot input buffer, `combo_reset_time`, per-step aim orientation and debug feedback.
- **M2.3 — Dodge, i-Frames, Attack Cancel Windows**: directional/backstep dodge, invulnerability window on `Hurtbox`, per-step cancel windows on `AttackStep`, dodge cooldown, Player `HealthComponent` + `Hurtbox`, debug damage zone in `test_world` for manual i-frame verification.

Next iteration: **M2 close** — Player death handling + playtest tuning. Then M3.

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

- Game design definition — foundations defined:
    - third-person camera
    - WASD camera-relative movement
    - mouse-controlled aim
    - combat feel direction
  Still in progress: progression, loot, shadow mechanic, dungeon structure, UI, etc.
- Technical architecture definition — grows as systems land.
- **M2 — Basic Combat** (In Progress). Remaining scope before M2 close:
    - Player death handling (`Player` reacts to its own `HealthComponent.died`)
    - Playtest-tuning of combo timings, damages, dodge params, cancel windows

---

## Todo

- Complete `GAME_DESIGN.md` (systems beyond camera/movement/aim/combat feel)
- Complete `ARCHITECTURE.md` (fill out as systems land)
- Manual editor playtest of M1 + M2 combat feel (mouse aim, hit reg, dummy topple, combo cadence, dodge feel, i-frame reliability, debug damage zone contact)
- Playtest-tune M2 combo + dodge parameters
- Player death state + close M2
- Start M3 — Enemy Foundation

---

## Blocked

None
