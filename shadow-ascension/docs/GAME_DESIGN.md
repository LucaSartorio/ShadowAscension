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

## Items and rarity

Confirmed in M7.1. Only what is listed here is decided.

**Rarity**, five tiers, ordered: Common, Uncommon, Rare, Epic, Legendary. Rarity is **data**. It
colours an item in the world and in the inventory and orders the inventory list, and it does
nothing else — no tier grants stats by itself. An item only has an effect if its own definition
says so.

**Item types**: Material, Consumable, Weapon, Armor. Weapon and Armor exist as types but are not
equippable yet; equipping arrives in M7.2.

**Stacking**: an item declares whether it stacks and its maximum stack. In M7.1 the inventory holds
one stack per item and has no capacity limit of its own.

**Equipment slots**, confirmed in M7.2: **Main Hand** and **Chest**. A weapon goes in the main hand,
a piece of armour in the chest; materials and consumables are not worn. No other slot exists.

An equippable item declares flat bonuses to STR, AGI, VIT and INT, and a weapon also declares
**melee attack power**. Those bonuses are added on top of the player's allocated stats when an
effective value is asked for — they are never written into the allocated stats, so removing a piece
can never leave a stat inflated.

```
effective_<stat> = allocated_<stat> + sum(equipment bonuses)
final_melee_damage = round((base_attack_damage + melee_attack_power) * melee_damage_multiplier)
```

The existing M6.2 formulas are unchanged; they simply read the effective stat instead of the
allocated one. An empty main hand contributes 0 attack power and combat works unarmed.

**Not decided**: what each rarity tier is worth mechanically, drop rates beyond placeholders,
durability, affixes, sockets, set bonuses, item level, dual wield, shields, further slots,
inventory capacity, and whether consumables are used from the inventory.

---

## Shadows

Confirmed in M8.1 and M8.2. Only what is listed here is decided.

A fallen enemy may leave a **remnant**: one chance, and only one, to tear its shadow loose. The
attempt either works or it does not, and either way the remnant is spent and gone. There is no
retry, no second remnant, and no way to bank one for later.

**Extraction chance is data**: each `ShadowData` declares its own, and the basic melee shadow sits
at **0.70**. Nothing in the extraction logic knows that number.

Every successful extraction produces an **individual shadow**, not a tally. Two extractions of the
same type are two separate things with their own ids, which is what lets them diverge later.

A shadow collection **persists for the session** — across gates, exits, further runs and the
player's own death — and is lost when the game closes. That is the same rule as progression and the
inventory, and for the same reason: there is no save system yet.

A remnant is not an enemy. A room clears the moment its last enemy dies, whether or not anything is
still standing on the floor waiting to be extracted.

### Summoning

**One shadow at a time.** Summoning a second takes the first back. The limit is deliberate: the
shadow is a companion the player commits to, not a stable they field.

**Summoning is free.** There is no cost, no cooldown and no resource — the decision is which shadow,
not whether the player can afford one.

**It comes back on its own.** A shadow that was out when the player changed scene is standing there
again in the next one. The player asked for it once; a gate is not a reason to ask again.

**A death is a recall.** When the player dies the next run starts with nothing summoned. When the
*shadow* dies, the shadow itself is unharmed — it keeps its level and XP and can be summoned again.
Dying costs the run, never the collection.

### Shadow behaviour

The shadow follows the player at about **2 m**, and breaks off a fight rather than being dragged
past its **8 m** leash. It picks the nearest enemy within **10 m** on its own — the player never
points it at anything. It commits to its swing exactly as the player and the enemies do: startup,
active, recovery, and an enemy that steps aside is genuinely missed.

**No friendly fire, in either direction.** The shadow cannot hit the player and the player cannot
hit the shadow. Enemies can hit both.

### Shadow progression

A shadow has its own **level and XP**, separate from the player's. The curve is **50 XP at Lv.1,
x1.2 per level** — 50, 60, 72, 86, 104. Each level adds **+8 max health** and **+2 damage** to its
base of 80 and 12.

**Who lands the killing blow decides the reward.** The player keeps the whole of its own kills. A
kill the shadow finishes pays the shadow **70%** and the player the rest: a 25 XP enemy splits
**18 to the shadow, 7 to the player**. The reward is never inflated — the two halves always add back
up to what the enemy was worth.

**Not decided**: ranks or evolution, summoning more than one, any cost to summon, whether bosses
yield shadows, and what happens to a collection between sessions.

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
