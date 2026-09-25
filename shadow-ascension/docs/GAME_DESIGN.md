# ShadowAscension — Game Design Document

Documents the design decisions taken so far. Only decisions explicitly agreed are recorded here;
unresolved mechanics are marked as future / to-be-decided, and anything already scheduled names the
milestone that will decide it.

This file owns **gameplay design**: the loop, progression, shadows, gates, the RPG layer and art
direction. Milestone order lives in `ROADMAP.md`, system structure in `ARCHITECTURE.md`.

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

Confirmed in M8.1, M8.2 and M8.3. Only what is listed here is decided.

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

### Commanding it

**One shadow, and the player commands it directly.** There are no formations, no tactical pause and
no unit selection. Every order is one key and applies to the one shadow that is out.

**Two modes, toggled with [T].** In **FOLLOW** the shadow never starts a fight: it stays with the
player and walks past enemies. In **AGGRESSIVE** it picks the nearest enemy in range and engages on
its own. A shadow is summoned in AGGRESSIVE — the player switches it *down*, not up.

**An order outranks the mode.** Aiming at an enemy and pressing **[MMB]** sends the shadow at that
enemy, in either mode: FOLLOW means "do not pick fights", not "do not fight". A marker sits over the
ordered target until it dies or the order is dropped. Aiming at nothing, or at a wall, changes
nothing.

**[Q] is "come back to me"**, and is not the same as the collection menu's *Richiama*, which
dismisses the shadow. The quick recall breaks off the fight and brings the shadow home; it stays
summoned and keeps its level and XP. For a few seconds afterwards it will not pick a new fight of
its own — otherwise recalling it next to an enemy would be undone the moment it arrived.

**The leash.** A fight may not travel more than **18 m from the player**. The shadow breaks off and
comes back rather than being led across the level, and an order aimed at something already past that
distance is refused rather than started and abandoned.

**Friendly fire, restated:** an order can never be given against the player, and the shadow and the
player cannot hit each other by any route.

### Shadow visual system

**A shadow does not need its own model.** The intended pipeline reuses the mesh of the enemy it was
taken from and changes what covers it:

```
enemy mesh + shadow material + shadow shader + emission + VFX + particles + aura
            ( + eye / material variations where they read )
```

This is what makes the mechanic scale: any enemy that can be modelled can become a shadow without a
second art budget, and a new enemy arrives shadow-ready.

The system has to carry, visually: **extraction**, **spawn / summon**, **recall**, **death /
despawn**, the standing **aura**, **dissolve**, **particles**, **emission**, and eventually
**variation by shadow rank**. Whether a given shadow also gets bespoke silhouette work is a
case-by-case decision, not the default.

Built in **M13.7**. Until then the summoned shadow is a translucent, emissive capsule, which is a
placeholder and reads as one.

**Not decided**: any cost to summon, whether bosses yield shadows, what happens to a collection
between sessions, and whether the command mode should persist across a full restart.

**Scheduled rather than undecided**: shadow **ranks, evolution, shadow skills and fielding more
than one** are M17; the **save** that would carry a collection between sessions is M19.

---

## The run loop

Confirmed in M9.1. Only what is listed here is decided.

**The game opens on a menu**, not in a world: title, GIOCA, ESCI. There is no settings screen, no
load, and no character creation in the slice. GIOCA is a New Game: it always starts a fresh
character. The character then lasts for the session — every gate, dungeon, death and return to the
hub keeps it — and ends when the game is closed, since there is no save until M19.

**The hub is where a run starts and ends.** It is a walled courtyard with a lit path to the gate and
a training corner with dummies. It states one objective — *Entra nel Gate* — and it is not a combat
arena: nothing hostile lives there.

**One gate, one dungeon.** The gate is the brightest thing in the hub, and it is the only way on.

**A run ends with a summary, not a scene change.** When the boss falls the dungeon pauses and says
what the run was worth: enemies, boss, the XP the player earned, items taken, shadows extracted.
Dismissing it hands the dungeon back — walking to the exit portal is still the player's move, in
their own time.

**The XP a summary reports is the player's own.** A kill the shadow finished pays the player 30%,
and 30% is what the summary shows. The number on the panel is what the character gained, never what
the enemy was worth.

**Dying costs the run, never the character.** The dungeon restarts fresh — enemies alive, doors
locked, the tally back to zero — and level, XP, stats, inventory, equipment and shadows all carry
over. Health is restored for the new attempt.

**A second run is a clean run.** Nothing survives from the last one but the character.

---

## Combat features: what exists, what is coming

**Already implemented and playable** (M2, M9): a three-hit **light attack combo**, a **dodge** with
an i-frame window that can cancel late attack recovery, hitboxes with startup/active/recovery, and
a damage pipeline from attacker through hitbox and hurtbox to a health component. These are
described above under *Combat Feel*; they are not future work.

**M11.1 rebuilt that combat as a foundation**, and **M11.2 made the light combo a real chain**:
Attack 1 → Attack 2 → Attack 3. Each of the first two accepts the next only while it recovers — its
combo window — and a press up to **0.15 s** before that window opens still counts (the input buffer).
The accepted attack follows the moment the current one is over. An attack that did not accept a
follow-up ends the chain, so pressing again after an attack has fully finished always starts Attack 1;
Attack 3 always ends it. Damage is 20 / 25 / 35 (×1.0 / ×1.25 / ×1.75 of the base 20), as since M2.

**M11.3 added the heavy attack**: a single, slower, harder blow on its own button — 40 damage (×2.0),
0.35 s of windup and 0.45 s of recovery against Light 1's 0.12 s and 0.22 s, and half walking speed
while it runs. It is a separate move, not part of the light chain: pressed during a light combo it is
ignored, and a light pressed during a heavy is ignored too; once free, each button starts its own
attack (Light 1, or the heavy). No charge, no stamina cost and no stagger yet.

**M11.4 made the dodge's timing explicit** (`Space`, as since M2). A dodge lasts **0.35 s** and covers
about **4 m** (11.5 m/s, scaled by AGI) in the direction the movement keys point relative to the
camera — straight back if none is held — and walls and enemies still stop it. It is invulnerable
from **0.06 s to 0.24 s**: a short vulnerable start, the i-frames, a vulnerable tail. A hit landing in
the i-frames does nothing at all; one landing before or after them hurts as usual. After a dodge,
another one waits **0.15 s**; attacks do not. A dodge cancels an attack only late in its recovery —
from the start of Light 1's, 35% into Light 2's, 60% into Light 3's and the heavy's — never out of a
windup or a swing, and a dodge pressed too early is dropped, not saved for later. Attack buttons do
nothing during a dodge.

**M11.5 added stamina**, the player's first limited resource: **100**, shown as a thin gold bar right
under the health bar. A dodge costs **25**, paid in full when it starts, so a full bar is four dodges
in a row; with less than 25 left the dodge simply does not happen — no shorter dodge, no weaker
i-frames. Stamina starts coming back **0.8 s** after the last dodge ends, at **40 per second** (empty
to full in 2.5 s), and every new dodge restarts that wait. Attacks cost nothing — neither the light
combo nor the heavy, which already pays with its commitment — and do not delay regeneration; at zero
stamina the player still walks and attacks normally, only the dodge waits. Every new scene's player
starts full. There is no sprint in the game yet; when there is, it will drain stamina by the second.

**M11.6 made enemies react to being hit.** Every hit an enemy survives makes it flinch. A strong enough
hit **staggers** it: whatever attack it was winding up or swinging is cut off before it can land, and
for **0.5 s** it does nothing at all; then it goes back to fighting, and for **1 s** after that it
cannot be staggered again (it still takes damage and gets pushed), so no string of hits keeps it
helpless. Hits also **push** it straight away from whoever struck, and walls and other bodies stop the
push. The light combo builds up to its finisher: Light 1 and Light 2 only flinch a basic enemy and
barely nudge it, keeping it in reach; Light 3 staggers it and knocks it back a step; the heavy
staggers it and throws it back about a metre. A killing blow simply kills — no stagger, no push. The
boss takes damage and flashes, but it is never staggered and never pushed. The shadow's hits make
their target flinch, nothing more. The player is not staggered or pushed by enemies yet.

**M11.7 added critical hits.** Any hit of the player's has a **10%** chance to be critical and deal
**150%** of its damage: Light 1 / 2 / 3 and the heavy hit for 20 / 25 / 35 / 40, or 30 / 38 / 53 / 60
when critical. Each hit rolls on its own — within a combo, and for each enemy a swing reaches — so a
combo can go normal, critical, normal, and one swing can crit one enemy and not the one beside it. A
critical only does more damage: it does not stagger harder, push further or get through a dodge. The
shadow, enemies and the boss do not land critical hits.

**M11.8 added a target lock.** `Tab` locks onto the enemy best placed in front of the camera — within
**15 m** and not behind a wall — shows a red ring on it and a reminder of the keys, and turns the
player to face it; walking sideways or back then circles it while still facing it. `Z` and `X` move
the lock to the next enemy to the left or right as the screen shows them. Every attack aims at the
locked enemy when it starts, but still has to reach it: the lock turns the player, it never pulls the
swing onto the target. A dodge still goes where the movement keys point; with no key, it jumps back
away from the target. The lock lets go when the target dies, gets further than **18 m**, when `Tab` is
pressed again, or when the player dies. The boss can be locked like any enemy; the shadow never can.

**M11.9 made the player's hits felt, and closed M11.** When a hit of the player's lands and counts,
the whole game holds for a split second — the **hit stop** — and the camera jolts and settles — the
**camera shake**. Both grow through the light combo and are biggest on the heavy: Light 1 / 2 / 3
and the heavy hold for **0.025 / 0.03 / 0.04 / 0.065 s** and shake the camera **3 / 4.5 / 7 / 12 cm**.
A critical holds **0.015 s** longer, shakes **35%** harder, and pops a **CRITICO!** above the enemy
(a placeholder until there are damage numbers). One swing is one hit stop however many enemies it
reaches. A miss, or a hit on something already dead, is felt as nothing. None of it changes damage,
criticals, stagger, knockback, stamina, the lock or any timing: the game simply stands still for a
moment and carries on exactly where it was, and a button pressed during the stop still counts. The
shadow's hits are not felt this way — only its target's own reaction — so a crowd of shadows never
shakes the screen. Nothing of it plays over a menu or a death, and the boss's last blow goes straight
to the run summary with no slow motion. The shake and the stop can each be turned down or off (there
is no settings screen for it yet).

**Not built in M11**, and not committed to: sprint (stamina pays only for the dodge), soft targeting
and a camera that frames the locked target, floating damage numbers, and a damage model with magic,
elemental and status damage, defense or armour penetration. Each is defined at the milestone that
implements it.

**Scheduled for M17 — Skills & Shadow Army 2.0**: active, passive, ultimate, movement and shadow
skills, with cooldown, mana cost, cast, range and area.

**Still under evaluation, not scheduled**: parry and block.

Nothing in the scheduled lists is a locked design decision. Each feature is defined at the
milestone that implements it.

---

## Art direction

**Not yet decided.** The definitive visual identity is chosen in **M13**, and this section is the
place it will be written down. What follows is direction, not specification: it is enough to judge
a reference against, and deliberately not enough to model from.

**The direction is original.** ShadowAscension is not a reproduction of Solo Leveling, and
"looks like Solo Leveling" is not an acceptable answer to an art question.

Conceptual references:

- **dark fantasy** as the base register;
- **urban fantasy** — a contemporary world, not a medieval one;
- a modern atmosphere, with dungeons that **contrast** with the real world rather than continuing it;
- a **strong visual identity for the shadows**, distinct at a glance from both the player and the
  enemies they came from;
- combat that is **legible first and spectacular second** — an effect that hides a telegraph is a
  bug, not a flourish;
- cinematic environments that never cost gameplay readability.

When M13 settles it, this section will describe: player visual style, enemy style, boss style,
shadow style, gate style, dungeon style, hub style, UI style, lighting, colour palette, and the
VFX language. **Those are deliberately undecided today and are not to be invented in advance.**

### Placeholders are the plan until M12

Everything visible in the game today — capsules, boxes, flat materials — is a placeholder, and that
is intentional. Definitive assets are produced from **M13**, once combat, hitboxes, skeleton and
animation requirements, AI, movement, interaction and architecture have stopped moving. See
`ROADMAP.md`, *Why art waits for M13*.

---

## Controls

The bindings as the InputMap actually defines them. Shadow commands only do anything while a
shadow is summoned, and their on-screen hints appear with it.

| Action | Binding |
| --- | --- |
| Move | `W` `A` `S` `D` |
| Camera | mouse |
| Light attack (3-hit combo) | left mouse button |
| Heavy attack | right mouse button (temporary binding) |
| Dodge (i-frames) | `Space` |
| Lock onto a target / let go | `Tab` (temporary binding) |
| Switch target left / right (while locked) | `Z` / `X` (temporary binding) |
| Interact — gate, exit, loot, remnant | `E` |
| Character sheet | `C` |
| Inventory and equipment | `I` |
| Shadow collection | `O` |
| Shadow: come back to me | `Q` |
| Shadow: FOLLOW / AGGRESSIVE | `T` |
| Shadow: attack what I am aiming at | middle mouse button |
| Close a menu / release the cursor | `Esc` |

Key rebinding is a settings feature scheduled for **M19**.
