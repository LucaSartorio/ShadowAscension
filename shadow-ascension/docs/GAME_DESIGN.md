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

## Progression

Confirmed in M6.1. Only what is listed here is decided; everything else about progression is open.

**Base stats** — four, no more:

| Stat | |
|---|---|
| STR | strength |
| AGI | agility |
| VIT | vitality |
| INT | intelligence |

Each starts at **10**. In M6.1 they are data only: nothing reads them yet. What each one actually
does to combat is decided in M6.2, and no derived stat is committed here.

**Levelling** — a level grants **5 stat points**. Spending them is M6.2; M6.1 only accumulates them.

**XP curve** — computed, never a per-level table:

```
xp_required(level) = round(100 * 1.25 ^ (level - 1))
```

so 100 XP for the first level, 125 for the second, 156 for the third. Both constants are tuning
values on a Resource, not design commitments.

**Derived stats** — confirmed in M6.2. A stat contributes only above the neutral value of 10; below
it nothing is granted and nothing is penalised. All five constants are tuning fields on the
progression Resource.

| Stat | Drives | Formula | At 15 |
|---|---|---|---|
| STR | melee damage | `1.0 + max(0, STR - 10) * 0.03` | ×1.15 |
| AGI | movement speed | `1.0 + max(0, AGI - 10) * 0.01` | ×1.05 |
| AGI | dodge speed | `1.0 + max(0, AGI - 10) * 0.005` | ×1.025 |
| VIT | max health | `base + max(0, VIT - 10) * 8` | base + 40 |
| INT | ability power | `1.0 + max(0, INT - 10) * 0.03` | ×1.15 |

STR scales a swing when it is prepared; the combo steps keep their base damage, so the multiplier
never compounds and never writes back into the data. AGI touches speed only — never i-frames, dodge
duration, cooldown, attack timings, active windows or cancel windows. VIT raises the ceiling without
healing: investing while wounded leaves the wound. Ability power is computed and displayed but no
system consumes it yet; the abilities it is meant for do not exist.

**Not decided**: the real maximum level (the current 100 is a technical bound on the level-up loop,
nothing more), respec, stat decrement, stat caps, XP modifiers, prestige, equipment modifiers, and
what ability power will eventually scale.

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
