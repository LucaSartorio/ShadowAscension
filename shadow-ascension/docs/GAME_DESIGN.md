# ShadowAscension — Game Design Document

Documents the design decisions taken so far. Only decisions explicitly agreed are recorded here; unresolved mechanics are marked as future / to-be-decided.

> **Note on numeric values.** All numeric values referenced in this document — movement speed, acceleration, camera FOV, sensitivity, distance, height, attack timings, damage, cooldowns — are **placeholders / initial targets only**. Final values are determined through playtesting and are **not** considered definitive design decisions. Numbers in this document may change without affecting the design intent around them.

---

## Camera

The game uses a free 3D third-person camera.

Characteristics:
- Orbital camera controlled by the mouse.
- Mouse X controls horizontal rotation (yaw).
- Mouse Y controls vertical rotation (pitch).
- WASD movement is relative to the camera direction.
- Camera is positioned slightly elevated and behind the character.
- Slight shoulder offset is allowed if it improves readability.
- The following parameters are configurable (Resource-driven, not hardcoded):
  - camera distance
  - camera height
  - field of view (FOV)
  - mouse sensitivity
- Initial FOV target: ~70–75 degrees (placeholder, subject to playtesting).
- Camera collision handling must prevent clipping through walls and geometry (spring-arm-style or equivalent).

---

## Movement

- WASD movement.
- Full 360-degree movement (analog direction from WASD combinations).
- Movement direction is relative to the camera.
- Diagonal movement is normalized (no diagonal speed boost).
- Character rotation is interpolated (no snap turns).
- During exploration the character tends to face the movement direction.
- No click-to-move.

---

## Aim

The mouse controls both camera and aim.

- Mouse cursor is captured during gameplay.
- The camera's central direction represents the aim direction.
- The architecture must be prepared to use camera raycasting for aim resolution.
- During attacks the character can orient toward the aim direction.
- A central crosshair may or may not be added — the decision is deferred to combat development.
- No lock-on in the first implementation.
- The system must be designed so that a future lock-on can be added without a rewrite.

---

## Combat Feel

Combat targets a midpoint between a fast action RPG and a Souls-like.

Principles:
- Responsive.
- Attacks must convey weight.
- Attacks require a minimum of commitment.
- Wind-up and recovery are perceivable but short.
- No consequence-free button mashing.
- No excessively slow animations.
- Controlled attack cancel windows will be used in the future.
- Enemy attacks must be readable and telegraphed.
- Movement and control must remain fluid during combat.

Design target statement:

**Responsive combat + deliberate attacks + readable enemy behavior.**

---

## Future Combat Features

The following features are **future direction, not yet defined or implemented**. They are listed here so architecture and data schemas can leave room for them, but no numeric values, timing windows, or interactions are committed.

- Light attack
- Heavy attack
- Combo
- Dodge
- Sprint
- Lock-on
- Abilities
- Ranged abilities
- Stamina / resource system — under evaluation
- Parry / block — under evaluation

Nothing in the list above should be treated as a locked design decision. Each feature is defined at the milestone that implements it.
