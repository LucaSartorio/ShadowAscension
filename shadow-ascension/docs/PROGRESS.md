# ShadowAscension — Progress

> **Maintenance note:** This file MUST be kept in sync with the actual state of the project. Update it whenever a milestone changes status, a task moves between sections, or a blocker appears/clears. Stale progress data is worse than none.

---

## Current Milestone

**M4 — Dungeon Foundation** (In Progress)

M4.1 delivered: a static, deterministic dungeon that runs end to end — Gate in the test world,
start room, two combat rooms gated by locking doors, a boss-room placeholder, and dungeon
completion. No procedural generation, no real boss, no loot/XP/shadow systems.

M4.1 deliverable status (verified by `dungeon_test_suite.tscn`, 31/31):

- dungeon gate — implemented
- dungeon scene — implemented
- start room — implemented
- room controller — implemented
- combat rooms — implemented
- door locking — implemented
- room clearing — implemented
- sequential progression — implemented
- boss room placeholder — implemented
- dungeon completion foundation — implemented

M4 stays **In Progress**: M4.2 still owes the return trip to the test world, and the layout is a
grey-box.

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
- **M3 — Enemy Foundation** (Completed). Exit criteria verified:
    - *One concrete enemy variant instantiated from a Resource works end-to-end* — `BasicMeleeEnemy`
      reads its tuning from `resources/enemies/basic_melee_enemy_stats.tres` (`EnemyStats`, defined in
      `scripts/enemies/enemy_stats.gd`). Enemy test #21 asserts the asset is wired, that the runtime
      fields are seeded from it, and that writing an instance field does not mutate the shared
      definition.
    - *Transitions Idle → Detect → Chase → Attack → (Damaged) → Dead run cleanly* — enemy suite 22/22
      plus an 18s scripted encounter that covered CHASE, REPOSITION, ATTACK and DEAD across instances.
    - *Multiple enemy instances coexist without cross-talk or shared-state bugs* — per-instance body
      materials and `HealthComponent`s confirmed distinct objects; damaging one enemy left the other
      two at full health (65 / 100 / 100).
    - *Zero runtime errors during a combat encounter with 3+ enemies* — 18s encounter with three
      engaged enemies, zero engine errors; `Main.tscn` 600 frames clean.
    - Deliverables: enemy base architecture data-driven via `EnemyStats`; idle; player detection;
      chase; basic attack; damage reception through the M2 pipeline; death with a drop hook stub
      (`enemy_died` signal carrying the enemy — nothing subscribes yet, loot lands in M7).
    - Architecture: the Resource is a definition, never runtime state. The enemy copies its values
      into its own fields on `_ready()`, so debug tweaks and future buffs mutate the instance and the
      shared `.tres` stays untouched. Only genuinely per-instance values stay `@export` on the node:
      `combat_angle_offset_degrees`, `initial_attack_delay`, `attack_cooldown_variation`.
    - Final validation: combo 10/10, dodge 18/18, enemy 22/22, enemy polish 17/17 — **67/67**;
      `--check-only` clean across `scripts/` and `tests/`; `Main.tscn` 600 frames zero ERROR /
      WARNING / Failed / Parse Error / SCRIPT ERROR.
    - Known non-blocking observations, left unfixed for want of profiling evidence:
      `_has_line_of_sight()` allocates per call on the paths that reach it (only when an enemy is in
      range, facing, off cooldown *and* blocked); `_hit_flash()` tweens overlap during a fast combo,
      visual only. `Orphan StringName: servers` at shutdown is vanilla engine noise.
First iteration delivered: `BasicMeleeEnemy` scene + local enum state machine (IDLE / CHASE / ATTACK / DEAD), player detection via distance + `player` group, chase via `NavigationAgent3D` with periodic target updates, telegraphed melee attack that flows through the existing `Hitbox` / `Hurtbox` / `HealthComponent` pipeline, hit-flash feedback, death state that disables body/hurtbox/hitbox and topples the visual. Test world updated with `NavigationRegion3D` + 3 concrete enemies + navigation-obstacle wall.

    M3.1 deliverable status:

- enemy base scene — implemented
- basic state logic (IDLE / CHASE / ATTACK / DEAD enum) — implemented
- detection (with `detection_range` / `lose_target_range` hysteresis) — implemented
- navigation (`NavigationAgent3D` + baked `NavigationMesh`, obstacle detour confirmed) — implemented
- chase — implemented
- melee attack (STARTUP / ACTIVE / RECOVERY + cooldown) — implemented
- player damage (via Hitbox -> Hurtbox -> HealthComponent) — implemented
- hit reaction (visual squash only, no stagger) — implemented
- death — implemented

    M3.2 deliverable status (verified by `enemy_polish_test.tscn`, 17/17):

- local avoidance — implemented (NavigationAgent3D RVO, no second navigation system)
- enemy spacing — implemented (`preferred`/`minimum_combat_distance` + `enemy_spacing_radius`)
- reposition — implemented (`REPOSITION` state with timeout + re-entry block)
- facing refinement — implemented (per-state turn rates, `max_attack_facing_angle` gate)
- attack telegraph refinement — implemented (per-phase scale + albedo, per-instance material)
- aggro refinement — implemented (`lose_target_delay`)
- multi-enemy combat polish — implemented (per-instance approach angle + attack desync)
- **M3 progress — Enemy Foundation, M3.1 Basic Melee Enemy**:
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
    - Automated headless validation `res://tests/enemies/enemy_test.tscn` — **20/20 PASS**:
        1. Enemy IDLE when player > `detection_range`
        2. Enemy CHASE when player < `detection_range`, and actually closes distance (5.95 -> 3.97 in 0.6s)
        3. Enemy ATTACK when player < `attack_range`
        4. Attack phase gating: hitbox off during STARTUP + telegraph visible; hitbox on during ACTIVE; hitbox off during RECOVERY
        5. Enemy deals exactly 15 damage to Player (`100 -> 85`)
        6. Player dodge i-frame during ACTIVE avoids enemy damage
        7. Attack cooldown: enemy returns to CHASE with cooldown active; re-attacks after cooldown expires
        8. Real CHASE -> IDLE transition when the *player* moves past `lose_target_range`
        9. Player Attack 1 damages enemy 20
        10. Player full combo damages enemy 80
        11. Enemy dies (`state = DEAD`, hitbox off, body collision disabled, hurtbox not monitorable, `velocity == 0`)
        12. Dead enemy in attack range deals no damage and stays DEAD
        13. 3 concurrently spawned enemies all reach CHASE independently
        14. Navigation around big wall (`2.27u` sideways, crosses wall Z from 13.65 to 4.28 over 3s)
        15. Mistimed dodge (too early / too late) still takes the full 15 damage — i-frame window measured with `dodge_speed = 0` so displacement cannot mask it
        16. Player stepping out of the swing during STARTUP takes no damage (attack does not home)
        17. Enemy stays committed for the full RECOVERY (phase + state hold, hitbox off throughout)
        18. Enemy returns to CHASE when the player leaves `attack_range` mid-attack
        19. Enemy takes exactly one hit per player swing (1 `health_changed` emission, 20 damage)
        20. Hit feedback squash plays (`scale.y` 0.875) and settles back to rest
    - Engine-level checks on `test_world.tscn`: baked `NavigationMesh` has 53 vertices / 50 polygons, navigation map active with 1 region; `NavigationServer3D.map_get_path()` from Enemy1 `(0, 16)` to Player `(0, 4)` returns a 7-point path routing around `BigWall` at `x = -4.5` (wall spans `x` -4..4) — confirmed detour, not a straight line through geometry.
    - Regression: combo suite 10/10 PASS, dodge suite 18/18 PASS, `Main.tscn` 300 frames verbose scan zero ERROR / WARNING / Failed / Parse Error / SCRIPT ERROR, `--check-only` parse of every `.gd` under `scripts/` and `tests/` clean.
    - Validation engine note: this pass was executed on **Godot 4.5.stable** headless (no 4.7 binary available in the CI container). The project declares `config/features = ("4.7", "Forward Plus")`; it imported and ran without complaint, but 4.7-specific behavior is unverified.
- **M3.2 — Enemy Combat Polish**. Refinement of M3.1, not a rewrite: the enum state
  machine, the Hitbox/Hurtbox/HealthComponent pipeline and NavigationAgent3D pathfinding
  are unchanged in kind.
    - New state `REPOSITION` — enum is now `IDLE / CHASE / REPOSITION / ATTACK / DEAD`.
      Entered from CHASE when the enemy is inside `minimum_combat_distance` or in range but
      mis-facing. It paths to its combat slot, turns to face the player, and leaves for
      ATTACK once distance + facing + line of sight + cooldown all pass. `reposition_timeout`
      (1.5s) hands control back to CHASE and `reposition_cooldown` (0.6s) blocks immediate
      re-entry, so the two states cannot ping-pong.
    - Local avoidance via `NavigationAgent3D` RVO: `avoidance_enabled = true`, `radius` driven
      by `enemy_spacing_radius` (0.8), `neighbor_distance` 4.0, `max_neighbors` 6,
      `time_horizon_agents` 1.0, `time_horizon_obstacles` 0.5, `max_speed` = `movement_speed`,
      `use_3d_avoidance` false. Desired velocity goes through `set_velocity()`; the move happens
      in the `velocity_computed` callback. A 10-frame watchdog falls back to direct motion if the
      agent never joins a navigation map, so an enemy can never freeze waiting for a callback.
    - **Navigation fix:** the baked navmesh surface sits 0.5 above the walkable floor, so raw path
      points came back 0.5 above the agent and waypoint advancement compared against that vertical
      gap. `path_height_offset = 0.5` puts path points on the agent plane; `path_desired_distance`
      0.4, `target_desired_distance` 0.25. Before this, a reposition target 0.7 away was reported
      unreachable and the enemy stood still.
    - Spacing: CHASE stops advancing once inside `preferred_combat_distance` (1.6) instead of
      grinding into the player. `minimum_combat_distance` 1.15.
    - Per-instance combat slots: `combat_angle_offset_degrees` biases each instance's approach
      bearing, so instances converge on different points on the ring rather than one point.
    - Facing per state — CHASE: toward movement direction at `rotation_speed`. REPOSITION: toward
      the player at `rotation_speed`. ATTACK STARTUP: toward the player at
      `rotation_speed * attack_startup_turn_fraction` (0.3). ATTACK ACTIVE and RECOVERY: no
      rotation at all. `max_attack_facing_angle` (25 deg) gates attack entry. The M3.1 snap-to-player
      on attack entry is gone.
    - Telegraph per phase: STARTUP rears up (`scale` 0.88/1.22/0.88) and the body tints to
      `telegraph_color`; ACTIVE squashes forward and tints to `active_color` with the hitbox debug
      mesh visible; RECOVERY returns both to rest. The body material is duplicated per instance in
      `_ready` — shared sub-resources would otherwise make every enemy telegraph in unison.
    - Line of sight: a ray on `line_of_sight_mask` (world layer only) gates attack entry, so an
      enemy cannot swing through a wall. Evaluated only after the cheap distance and cooldown
      checks fail-fast, never unconditionally per frame.
    - Aggro: `lose_target_delay` (1.0s) must elapse beyond `lose_target_range` before the target is
      dropped, so a momentary distance spike no longer ends the fight.
    - Attack desync: `initial_attack_delay` and `attack_cooldown_variation`, both per-instance and
      deterministic (no RNG). Test world uses 0.0 / 0.3 / 0.6 and 0.0 / 0.15 / 0.3.
    - Range coherence (asserted, not assumed): hitbox covers 0.4–2.0 in front of the enemy;
      `attack_range` 1.8 <= 2.0 and `minimum_combat_distance` 1.15 >= 0.4, with
      `preferred_combat_distance` inside the band.
    - Collision layers split so physics intent is explicit — see the table below. Correction to an
      earlier claim in this file and in commit 29ee6db: the camera SpringArm never collided with the
      player's own body, because `camera_rig.gd` already excludes it via `add_excluded_object()`.
      What the split actually changed is that the SpringArm (mask 1) no longer collides with *enemy*
      bodies, which moved from layer 1 to layer 4. Enemies are not geometry, so the camera pushing
      in for them was not required by GAME_DESIGN's camera-collision rule.
    - Death: `_physics_process` returns early, and `nav_agent.avoidance_enabled` is set false so a
      corpse leaves the RVO simulation and stops steering the living. Telegraph is reset instantly.
      The topple tween is death feedback, not AI facing.
    - Collision layers after M3.2:
        - Layer 1: world geometry (Floor, Wall1, Wall2, BigWall) — mask 1
        - Layer 2: Player body — mask 5 (world + enemy bodies)
        - Layer 4: Enemy + Dummy bodies — enemy mask 7 (world + player + enemies), dummy mask 1
        - Layer 8: player-dealt hitbox (Player AttackHitbox, mask 16)
        - Layer 16: enemy-receiving hurtboxes (Enemy + Dummy Hurtbox, mask 0)
        - Layer 32: enemy-dealt hitbox + DebugDamageZone (mask 64)
        - Layer 64: player-receiving hurtbox (Player Hurtbox, mask 0)
    - Test world rebuilt for the five required scenarios, still one scene with no new node types:
      `EnemySolo` (14, 4) single engagement; `EnemyTrio1/2/3` (-13, -2/1/4) two-then-three from a
      similar direction with staggered delays; `EnemyBehindWall` (0, 16) behind `BigWall`;
      `EnemyLateral` (9, 13) with a 70 deg approach bias. Dummies and DebugDamageZone preserved.
    - Automated validation `res://tests/enemies/enemy_polish_test.tscn` — **17/17 PASS**: avoidance
      configured; two enemies keep separate targets (gap 2.45) and bodies (2.26); three enemies
      spread 165 deg with 1.96 min gap; too-close enemy repositions and backs off to 1.20; reposition
      exits via timeout at 1.53s; attack gated at 140 deg then fires once aligned; startup correction
      gradual (24 deg turned, 66 deg residual); zero yaw change during ACTIVE; player sidesteps the
      swing unharmed; range/hitbox coherence incl. an edge-of-range connect; no attack through wall
      (1.70 < 1.80, phase stayed NONE); enemy never enters the wall volume; three converging enemies
      move the player 0.000; dead enemy leaves avoidance and drifts 0.000; enemies die independently;
      first-ACTIVE times 0.42 / 0.72 / 1.00 with 0.28s min gap; aggro survives a sub-delay spike.
    - Engine-level check of `test_world.tscn`: navmesh 53 verts / 50 polys, map active with 1 region;
      after dropping the player next to the trio they settle at 1.84 / 1.57 / 1.76 from the player
      with a 1.61 min pairwise gap and states `[CHASE, CHASE, ATTACK]` — spread out, not stacked, not
      swinging in unison.
    - M3.1 regression `enemy_test.tscn` **20/20 PASS** against the refactored enemy. Two assertions
      were updated for deliberate behavior changes: the telegraph check is now shape-agnostic (the
      startup pose rears up instead of scaling uniformly), and the aggro-drop check now waits out
      `lose_target_delay` and additionally asserts the target is *held* during the grace period.
    - Regression: combo 10/10, dodge 18/18, `Main.tscn` 360 frames zero ERROR / WARNING / Failed /
      Parse Error / SCRIPT ERROR, `--check-only` clean across `scripts/` and `tests/`.
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

- **M4.1 — Dungeon Foundation**:
    - `scripts/dungeon/dungeon_controller.gd` (`DungeonController`) — dungeon state
      `NOT_STARTED / IN_PROGRESS / COMPLETED`, room order taken from tree order under its `Rooms`
      container, completion when the last room reports cleared. No combat, AI, health or door
      details. No global manager of any kind.
    - `scripts/dungeon/room_controller.gd` (`RoomController`) — one room's lifecycle:
      `IDLE / ACTIVE / CLEARED`, arms on player entry, locks its exit, wakes its own enemies,
      counts their deaths, unlocks and emits. A cleared room never re-arms, so backtracking is
      safe. It only ever touches its own subtree — no global enemy search, no per-frame scan.
    - `scripts/dungeon/dungeon_door.gd` (`DungeonDoor`) — `lock()` / `unlock()` / `is_locked()`.
      Locked: collider on, slab down, red. Unlocked: collider off, slab raised by tween, green.
      It knows nothing above itself.
    - `scripts/dungeon/dungeon_gate.gd` (`DungeonGate`) — Area3D that tracks the player, shows a
      `Label3D` prompt, and answers `interact` only while the player is inside. `activate()` is
      public so a future scene router (M4.2) can drive it; `change_scene_on_activate` lets it
      announce without switching scenes.
    - Enemy interface added, AI untouched: `BasicMeleeEnemy.set_combat_enabled(bool)` plus a
      `combat_enabled` export. While false `_physics_process` applies gravity and returns —
      no perception, no chase, no attack, no navigation, and the agent leaves the avoidance
      simulation. Rooms park their enemies in `_ready()` so a room can never ship with live ones.
    - Rooms subscribe to the enemy `enemy_died` drop hook added in M3, which is its first consumer.
      `BasicMeleeEnemy` still knows nothing about rooms.
    - **Bug found and fixed during the build:** the `NavigationMesh` is a sub-resource of
      `combat_room.tscn`, so both instances of that scene shared one object and the second bake
      overwrote the first — room 2's obstacles were never carved. `RoomController` now duplicates
      the navmesh before baking. Same class of shared-sub-resource bug as the enemy body material
      in M3.2. Verified: room 1 bakes 4 polygons, room 2 bakes 33, and a path straight through
      room 2's obstacle deviates 1.75 laterally while an open lane stays at 0.00.
    - Navigation: one `NavigationRegion3D` per room, baked by that room. Rooms are walled off, so
      each navmesh is an island and no enemy can path out of its own room. No runtime rebaking
      beyond the one bake per room at load.
    - Input map: `interact` = E added to `project.godot`.
    - Layout (static, grey-box): Start (0) → corridor → Combat 1 (z −18, 2 enemies) → corridor →
      Combat 2 (z −38, 3 enemies + 2 obstacles) → corridor → Boss placeholder (z −59, 1 clearly
      labelled `BasicMeleeEnemy`). The boss room's door seals behind the player on entry and opens
      on clear.
    - Collision layers reuse the M3 scheme: doors, floors, walls and corridors on world layer 1;
      room entry triggers are layer 0 / mask 2 (player body only); the Gate likewise. No new layers.
    - Test world: `DungeonGate` at (0, −16), 19.1 units from the nearest testing enemy — outside
      both `detection_range` (10) and `lose_target_range` (14), so the player is not harassed while
      using it.
    - Automated validation `res://tests/dungeon/dungeon_test_suite.tscn` — **31/31 PASS**, covering
      gate in/out of range, spawn, dormant enemies, one-shot room arming, door lock/unlock with a
      real `test_move()` collision probe, partial kills holding the door, backtracking, room 2 on
      the same controller, obstacle navigation, boss placeholder, `COMPLETED` firing once, the
      visible DUNGEON COMPLETE label and the cleared-room ordering.
    - Regression: combo 10/10, dodge 18/18, enemy 22/22, enemy polish 17/17 — with the dungeon suite,
      **98/98**. `--check-only` clean; `Main.tscn` and `dungeon_test.tscn` each 480 frames verbose
      with zero ERROR / WARNING / Failed / Parse Error / SCRIPT ERROR.
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
- Playtest-tune M3 enemy parameters — now edited in `resources/enemies/basic_melee_enemy_stats.tres`, not in code
- M4.2 — return from the dungeon to the test world on completion (deferred from M4.1 by design)
- M4.2 — dungeon layout pass: the grey-box is functional, not shaped for play
- Optional M3 polish, non-blocking: additional enemy archetypes as new `EnemyStats` assets,
  more expressive telegraph

---

## Blocked

None
