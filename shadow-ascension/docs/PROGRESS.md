# ShadowAscension — Progress

> **Maintenance note:** This file MUST be kept in sync with the actual state of the project. Update it whenever a milestone changes status, a task moves between sections, or a blocker appears/clears. Stale progress data is worse than none.

---

## Current Milestone

**M2 — Basic Combat** (Not started)

M0 and M1 complete. M2 introduces the first combat loop: single-swing attack, combo foundation, hitbox/hurtbox, health, damage, death. See `docs/ROADMAP.md` for M2 scope.

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

---

## Todo

- Complete `GAME_DESIGN.md` (systems beyond camera/movement/aim/combat feel)
- Complete `ARCHITECTURE.md` (fill out as systems land)
- Manual editor playtest of M1 (feel-tuning of exported parameters) — deferred, not blocking
- **Start M2 — Basic Combat** (next milestone)

---

## Blocked

None
