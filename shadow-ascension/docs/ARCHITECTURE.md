# ShadowAscension — Technical Architecture

Initial architecture reference for the project. Describes structure, principles, and forward direction. Does **not** commit to unimplemented features or undocumented game-design choices.

**Stack**
- Engine: Godot 4.7.x
- Language: GDScript (static typing preferred)
- Dimension: 3D
- Renderer: Forward+ (D3D12 pinned on Windows)
- Physics: Jolt Physics (3D)
- Session model: single-player (initial scope)

---

## 1. Architecture Goals

The architecture aims to keep the project scalable as more systems land in later milestones. Non-negotiable principles:

- **Composition over deep inheritance.** Behavior built from small, replaceable components attached to scenes; inheritance chains kept shallow (≤ 2 levels beyond engine base types) except where extending engine types requires it.
- **Modular scenes.** No monolithic scenes. Sub-scenes instanced by responsibility.
- **Single-responsibility scripts.** One script, one concern. If a script mixes input + combat + audio, it gets split.
- **Custom Resources for configurable data.** Every gameplay value that becomes tunable graduates to a `Resource` asset under `resources/`.
- **Separation of data and behavior.** Data lives in `Resource` assets; behavior lives in scripts; nodes glue them together in scenes.
- **Signals for decoupled communication.** Cross-system messaging uses signals — direct tree walking (`get_node("../../..")`) is avoided.
- **No circular dependencies.** Dependency direction flows one way per system. Shared low-level modules do not import high-level game modules.
- **Autoload only for genuine global services.** No autoloads used as convenience singletons.
- **No singleton-as-shortcut.** If something is "just easier as a singleton," it does not qualify as a global service.
- **Static typing where reasonable.** Typed vars, typed function signatures, typed collections when element type is stable — especially in hot paths.
- **Extensible without full rewrite.** Systems designed so new content (enemies, skills, items, shadows) is added as data (Resources) or plug-in components, not by editing core loops.

---

## 2. Project Structure

Godot project root: `shadow-ascension/`.

```
shadow-ascension/
    Main.tscn                # entry point / bootstrap router
    project.godot
    addons/
        godot_mcp/           # editor integration

    assets/                  # raw import sources
        audio/
        characters/
        environments/
        fx/
        materials/
        models/
        textures/

    scenes/                  # .tscn, grouped by domain
        core/                # bootstrap, root controllers, scene wiring
        player/
        enemies/
        world/
        dungeons/
        ui/

    scripts/                 # .gd, grouped by system
        core/                # framework, autoloads, base classes
        player/
        combat/
        enemies/
        dungeon/
        shadow/
        ui/

    resources/               # .tres data assets
        characters/
        enemies/
        items/
        skills/
        shadows/

    docs/                    # architecture, design, roadmap, progress
    tests/                   # test scenes/scripts (framework TBD)
```

Rules:
- Every new file lands in the correct domain directory. No ad-hoc folders.
- Resource *script* (class definition) lives in `scripts/<domain>/`; Resource *instance* (`.tres`) lives in `resources/<domain>/`.
- Filenames `snake_case`. `class_name` `PascalCase`.

---

## 3. Scene Architecture

- `Main.tscn` is a bootstrap/router. It does not host gameplay logic directly. Its role is to load the appropriate scene (menu, hub, dungeon) via a scene-router (future).
- Gameplay scenes are grouped by domain under `scenes/`:
  - `scenes/player/` — player character and rigs
  - `scenes/enemies/` — enemy variants
  - `scenes/world/` — hub, environment set pieces
  - `scenes/dungeons/` — dungeon container, rooms, gates
  - `scenes/ui/` — HUD, menus, panels
  - `scenes/core/` — infrastructure scenes (root controllers, camera rigs, spawners)
- Composed scenes reference sub-scenes by instancing. Sub-scenes are authored to be reusable — no hard assumptions about their parent.
- Root node of each scene is named in `PascalCase` and matches the file's intent.
- Groups (`add_to_group`) are used for tagging (e.g. `"enemy"`, `"player"`), never as a replacement for typed references.

Scene lifecycle expectations:
- `_ready()` performs setup and signal wiring.
- `_exit_tree()` performs teardown (disconnect long-lived signals, free owned resources).
- No scene assumes the presence of a specific sibling — it discovers dependencies through injection (exported node paths, exported Resources) or events.

---

## 4. Component Architecture

Systems are built from small, composable components attached to a scene root (e.g. `CharacterBody3D` for actors). Each component:

- Owns one concern.
- Exposes a small, typed API.
- Communicates outward through signals and inward through direct method calls from its owner.
- Reads tuning data from an injected `Resource`, not from hardcoded constants.

**Planned component directions** (architectural intent, **not implemented yet**):

- **HealthComponent** — tracks current/max HP; emits `health_changed`, `died`. Reads max HP from a stats or health Resource.
- **StatsComponent** — holds derived and base stats for an actor; recomputes derived stats when base stats or equipment change.
- **HitboxComponent** — active during attack frames; emits `hit_landed` with damage payload when it overlaps a `HurtboxComponent`.
- **HurtboxComponent** — receives hits; forwards damage payload to owner (typically to `HealthComponent`).
- **MovementComponent** — encapsulates movement math (input → velocity → `move_and_slide`), reads speed / accel from a Resource.

These are directions, not commitments. Exact API and boundaries are finalized when the owning milestone starts (M1 for movement, M2 for hit/hurt/health, M6 for stats, etc.). The direction is documented here so future implementations converge rather than diverge.

Communication rules for components:
- Components never reach across the tree to poke other components on other actors. Interaction happens through hitboxes/hurtboxes, signals, or an event bus.
- Components on the same actor may call each other directly (e.g. `HurtboxComponent` → `HealthComponent`) via a reference wired at `_ready()`.

---

## 5. Data Architecture

Gameplay data is stored as custom `Resource` subclasses. Resource scripts under `scripts/<domain>/`, Resource instances (`.tres`) under `resources/<domain>/`.

Planned domains for data-driven content:

- `resources/characters/` — player-facing character configuration
- `resources/enemies/` — enemy definitions (stats, behavior parameters, drop hooks)
- `resources/items/` — weapons, consumables, equippables
- `resources/skills/` — active/passive skill definitions
- `resources/shadows/` — extractable shadow definitions

Rules:
- Resources hold **pure data** and minimal derived getters. No per-frame logic. No scene-tree access.
- `.tres` (text) is preferred over `.res` (binary) for diff-ability.
- Runtime state (current HP, active buffs) lives in components, not in Resources. Resources are definitions; components hold instance state.
- Data schemas are extended additively when possible. When a field's meaning changes, existing `.tres` files are migrated in the same commit.

---

## 6. Events and Signals

Signals are the primary decoupling mechanism.

Conventions:
- Signal names describe *what happened*, not what to do: `health_changed`, `died`, `room_cleared` — not `update_health_bar`, `kill_me`, `spawn_next_room`.
- Signals are declared on the node that owns the event, at the top of the script.
- Subscribers connect in `_ready()` (or the editor) and disconnect in `_exit_tree()` when the connection outlives the emitter's parent.
- Payloads are typed. Prefer explicit args over untyped dictionaries.

Event bus:
- Truly global events (run started, player died, boss defeated, save requested) will be delivered through a dedicated event-bus autoload (introduced when needed, not preemptively).
- The event bus is **not** a place to dump arbitrary signals — it is reserved for cross-system events with no natural single owner.

---

## 7. Autoload Policy

Autoloads (singletons) are reserved for genuine global services with lifetime spanning the entire session.

Acceptable candidates (added when a milestone actually requires them):
- Scene router / bootstrap controller
- Event bus (see §6)
- Save/load service
- Audio bus wrapper (if the built-in bus system is insufficient)
- Input remapper (if runtime rebinding is added)

Forbidden uses of autoload:
- Storing gameplay state (player HP, inventory contents, current room). This belongs in scene-owned components.
- Shortcut access to nodes that could be reached via injection.
- "Managers" that mix unrelated concerns.

Every autoload is documented (what it owns, its public API, its lifetime) at introduction.

---

## 8. Save System Direction

Not implemented. Direction only, so future work converges:

- Save format: JSON or Godot Resource (`.tres`) — decision deferred until the first save/load milestone.
- Save is a snapshot of *definitions in use* + *runtime state*, not of scene instances. Scenes are rebuilt from saved state on load.
- Responsibility: a dedicated `SaveService` autoload will orchestrate save/load; each domain (progression, inventory, shadow collection) exposes a `to_save_dict()` / `from_save_dict()` pair. Systems own their own serialization — the save service coordinates, it does not know internals.
- Versioned save format from day one (a `version` field), with a migration hook for future format changes.
- No save/load calls per frame. Explicit save points (hub return, boss cleared, manual save) only.

Concrete decisions are made when the save milestone is scheduled; nothing above binds gameplay-design choices.

---

## 9. Performance Guidelines

- No per-frame allocations in `_process` / `_physics_process` (no `Array`/`Dictionary` literals in hot paths — reuse buffers).
- Cache `get_node` results in `_ready()`. Never `get_node` per frame.
- Use `_physics_process` for physics/movement, `_process` for visuals/UI. Do not mix concerns.
- Prefer signals over polling for state changes.
- Static typing in hot paths — the compiler generates faster bytecode for typed code.
- Physics: rely on Jolt's broad-phase; do not manually check-all-pairs.
- Profile before optimizing. Godot's built-in profiler and frame graph are the first tool. No speculative micro-optimizations.
- Object pooling considered when frequent spawn/despawn appears (projectiles, VFX). Not preemptive.

---

## 10. Testing Strategy

Testing is minimal today and grows with the project.

Current state:
- No test framework wired.
- `tests/` directory reserved for test scenes/scripts.

Direction:
- **Manual validation** is mandatory after any significant change: run `godot --path .` (or `--headless --quit` for a smoke check), confirm zero runtime errors, zero parser warnings.
- **Test scenes** land in `tests/` — small, focused scenes that exercise one system in isolation (e.g. `tests/combat/hitbox_smoke.tscn`).
- **Automated tests** (GUT or equivalent) will be introduced when a system's complexity justifies it. When introduced, the runner command is documented in `CLAUDE.md`.
- **Definition of Done** (from `CLAUDE.md`) is the acceptance bar for every task: project launches, zero runtime errors, zero parser errors, coherent structure, feature verifiable, docs updated.

Regressions caught during play are the priority signal until automation exists.

---

## Boot flow and scenes

`Main.tscn` is the project's `run/main_scene` and stays a bootstrap router, never a gameplay scene:
it holds the main menu and a `SceneTransition`, nothing else. The route is

```
Main.tscn (MainMenu)  --GIOCA-->  scenes/core/hub.tscn  --DungeonGate-->  scenes/dungeons/dungeon_test.tscn
                                        ^                                          |
                                        +---------------- DungeonExit -------------+
```

**`MainMenu`** (`scripts/ui/main_menu.gd`) is a router with no state. It emits `quit_requested`
before asking the application to close, and `quit_on_request` turns the closing off — a headless run
can then watch the choice without the process going away underneath it.

**The hub** (`scenes/core/hub.tscn`) is the former test world, renamed rather than duplicated. It is
where a run starts and ends, and it owns the same UI stack the dungeon does, minus the
dungeon-specific pieces.

## HUD layout

One rule: no two panels share pixels, and `vertical_slice_run.gd` asserts it by comparing the actual
control rectangles rather than by eye.

| Corner | What |
| --- | --- |
| top-left | `PlayerHealthHUD`, then `ProgressionHUD` (level and XP) |
| top-centre | `BossHealthBar`, band y 24–88, only during the encounter |
| top-right | `DungeonObjectiveUI`, deliberately below the boss bar's band |
| bottom-centre | `InteractionPrompt` |
| bottom-right | `ActiveShadowHUD`, then the three menu hints |

The objective sits below the boss bar's band rather than beside it because "beside" depends on the
window width: centred and right-anchored rectangles that clear each other at one size overlap at
another.

**`PlayerHealthHUD`** (`scripts/ui/player_health_hud.gd`) is its own node rather than another block
inside `ProgressionHUD`, because health is not progression and the two are driven by different
components. It is driven by `health_changed` alone — which also fires when the ceiling moves, so a
point spent on VIT or a swapped chestpiece reaches the bar without this node knowing either system
exists.

**`DungeonObjectiveUI`** shows `default_text` when there is no `DungeonController` above it, which
is how the hub says "Entra nel Gate" without a second UI doing the same job in a different place.

## Run stats and the summary

**`DungeonRunStats`** (`scripts/dungeon/dungeon_run_stats.gd`) is a component on the
`DungeonController` counting five things about one run: enemies defeated, bosses defeated, items
picked up, shadows extracted, and the player's XP. It is deliberately not an analytics service —
nothing global reads it, it keeps no history, and a new dungeon scene builds a new one, which is
what "reset on entry" means here. Everything comes from signals the systems already emit; no system
was changed to report to it.

Two of its rules are worth stating:

- **XP is the player's own share.** It differences `PlayerProgression.get_total_xp()` across the run
  rather than adding up enemy rewards, so a kill the shadow finished contributes the player's 30%.
- **Items are counted as they leave the floor**, through `WorldItem.picked_up`. Counting
  `PlayerInventory.item_added` instead would also count a piece of equipment being taken off.

**`RunSummary`** (`scripts/ui/run_summary.gd`) opens on `dungeon_completed`, pauses the tree, frees
the cursor, and waits for `[Continua]`. It changes no scene: the walk to the exit portal stays the
player's move. It refreshes on `stats_changed` as well as on open, because the kill that ends the
run and the tally of it are two handlers on the same signal and nothing orders them.

Its static `dismiss_open(tree)` is what anything driving the game without a player uses — the
dungeon is paused while the summary is up, so a headless flow that does not dismiss it waits forever
on the next physics frame.

## PlayerRuntimeState (autoload)

`scripts/core/player_runtime_state.gd`, registered as the autoload `PlayerRuntimeState`.

**Global runtime session data — not a save system.** Nothing here touches the disk. Closing the
game starts a fresh session at level 1. Permanent saving is a separate milestone and will not live
in this node.

It exists because a scene change destroys the player and builds a new one, so everything the player
knew about itself died with it. This node holds the few values that belong to the *session* rather
than to any one scene, and hands them to the next player:

- `current_level`, `current_xp`, `available_stat_points`
- `strength`, `agility`, `vitality`, `intelligence`
- `current_health`

It is the one autoload CLAUDE.md §4 allows: genuinely global state that has to outlive a scene, not
gameplay logic parked in a singleton. It stores and returns data and owns no behaviour — every
formula, from the XP curve to each derived stat, stays in `PlayerProgression`. It is not a
`GameManager`, a `SceneManager`, or a general blackboard, and nothing unrelated to player session
data belongs in it.

**Max health is deliberately not stored.** It is recomputed from the player's own base plus VIT on
every load, so the two can never desync. A negative `current_health` means "start at whatever this
player computes as its maximum" — both the fresh-session state and what a death leaves behind.

**Flow.** The first player of a session calls `capture_initial()` with the values its own resources
gave it. Every later player restores from the node instead, then recomputes its derived stats from
scratch. `PlayerProgression` writes back through a single `_sync_to_runtime_state()`, so a new
persisted field does not have to be remembered in each callback that can change it. The player
itself reports health, through `HealthComponent.health_changed`.

**Not persisted**, on purpose: position, camera rotation, combat and combo state, dodge state,
cooldowns, the current room, dungeon progress, enemy and boss state, and transient UI.

---

## Items and loot

**`ItemData`** (`scripts/items/item_data.gd`, instances in `resources/items/`) — one item
definition: id, display name, description, rarity, type, and whether it stacks. Pure data. Rarity
and type are enums with presentation helpers (`rarity_color`, `rarity_label`, `type_label`) so the
world drop, the inventory row and the detail pane cannot disagree about what "Rare" looks like.
Rarity carries no mechanical effect: it is displayed, not applied. `WEAPON` and `ARMOR` exist as
types but nothing equips them yet.

**`LootTable`** / **`LootTableEntry`** (`scripts/items/`) — what a combatant can drop, as data. Each
entry rolls independently, so overall odds come from the entries rather than a hidden rule. No enemy
script ever branches on its own type to decide loot. `guarantee_at_least_one` grants the rarest
entry when everything misses, which is how the boss is never worth nothing.

**`LootDropper`** (`scripts/items/loot_dropper.gd`) — a component on a combatant that rolls its
table once on death and scatters the results around the corpse. It hangs off
`RoomCombatant.enemy_died`, which fires exactly once however the death was reached, and latches as
well, so a duplicated signal, a boss phase transition, a room clearing or a dungeon completing
cannot roll again. Its seed is mixed with its own scene path: one shared seed would make an entire
room drop identically.

**`WorldItem`** (`scripts/items/world_item.gd`, `scenes/items/world_item.tscn`) — a dropped stack on
the floor. It reuses the existing `InteractionPrompt` rather than adding a second interaction
system, and takes only what the inventory accepts, leaving any remainder on the ground.

**`PlayerInventory`** (`scripts/player/player_inventory.gd`) — a component on the player, like
`PlayerProgression`. One stack per item, `id -> quantity`, no capacity limit on the inventory
itself; a stackable item caps at its own `max_stack`, and anything else accumulates a count, since
M7.1 has no per-instance stats to keep apart. `add_item()` returns what it actually took. Contents
survive a scene change through `PlayerRuntimeState`, which stores them and interprets nothing —
every rule stays in the inventory. Items already collected persist; items left lying on a floor do
not, which is intended for this milestone.

**`PlayerEquipment`** (`scripts/player/player_equipment.gd`) — what the player is wearing, in two
slots: `MAIN_HAND` and `CHEST`. A component on the player, beside the inventory and the progression.
Items *move* rather than being copied: equipping takes one out of the inventory, unequipping puts it
back, and a swap does both, so the same item is never in a slot and in the bag at once. The order is
deliberate — the item is only placed after the inventory has actually given it up, and a displaced
piece goes straight back — so no path loses one.

**Effective stats.** Two sources of truth, never merged:

- `PlayerProgression` owns the **allocated** stats. They are never written to by equipment.
- `PlayerEquipment` owns the **equipment bonuses**.

`PlayerProgression` remains the stats layer and holds every formula: it asks equipment for its
bonuses and exposes `get_effective_strength()` and friends, which is what all the derived values
use. Taking a piece off therefore cannot leave a stat inflated — there is nothing to subtract,
because nothing was ever added. Max health follows the same route, so equipping vitality raises the
ceiling without healing and unequipping it lowers the ceiling and clamps current health down.

**Melee damage** is `round((base + main-hand attack power) * STR multiplier)`, computed when a swing
is prepared. The `AttackStep` keeps its base damage and the weapon is never written into it, so
neither the weapon nor the multiplier can stack across attacks. An empty main hand contributes 0 and
combat works unarmed.

**Pause menus** — the character sheet and the inventory both join the `pause_menu` group, and
opening one closes the others. Only one is ever up, so C and I always do what they say. The
inventory panel also hosts the equipment slots, so equipping is one screen rather than two.

---

## Shadows

**`ShadowData`** (`scripts/shadows/shadow_data.gd`, instances in `resources/shadows/`) — the
definition of one kind of shadow: id, name, description, accent colour, the probability that one
extraction attempt succeeds, the scene it is summoned as, and every number its level scales. Pure
data, and the only place any of it exists — no script hardcodes a chance, a curve or a stat.
`health_at_level()`, `damage_at_level()` and `xp_required_for_level()` are derived getters on the
asset, so the curve is defined once and read everywhere.

**`ShadowInstance`** (`scripts/shadows/shadow_instance.gd`, a `RefCounted`) — one extracted shadow
as opposed to the type it belongs to: a unique instance id, the `ShadowData` it came from, and the
level and XP it has earned. It asks the data for its health, damage and next requirement rather
than storing them, so tuning an asset retunes every shadow already held. `add_xp()` applies as many
levels as the award pays for and returns how many, so one award is one level-up.

**`ShadowSource`** (`scripts/shadows/shadow_source.gd`) — a component that declares a combatant
leaves a shadow and spawns its remnant on death, the same shape as `LootDropper`. Nothing anywhere
branches on an enemy's class to decide which shadow it yields. It hangs off
`RoomCombatant.enemy_died`, which fires once however the death was reached, and latches as well.
The boss deliberately has no `ShadowSource` yet.

**`ShadowRemnant`** (`scripts/shadows/shadow_remnant.gd`, `scenes/shadows/shadow_remnant.tscn`) —
what a corpse leaves behind, and one chance to tear the shadow loose. The roll happens once, the
result shows briefly, and the remnant goes whether it worked or not. A remnant is **not** an enemy:
a room clears and its doors open the moment the last enemy dies, regardless of what is still
standing on the floor.

**`PlayerShadowCollection`** (`scripts/player/player_shadow_collection.gd`) — a component on the
player holding `ShadowInstance` objects rather than a count per type. It mints the ids; the session
remembers only where the counter got to, so two scenes can never hand out the same number.
Contents survive a scene change through `PlayerRuntimeState`, which stores them and interprets
nothing. `award_xp()` pays one named shadow — only the one that struck the killing blow earns
anything.

**`BasicMeleeShadow`** (`scripts/shadows/basic_melee_shadow.gd`,
`scenes/shadows/basic_melee_shadow.tscn`) — the summoned entity. It shares the combat components
with the enemies (`HealthComponent`, `Hurtbox`, `Hitbox`, `NavigationAgent3D`) and none of their AI:
`FOLLOW → ACQUIRE_TARGET → CHASE_TARGET → ATTACK → RETURN_TO_PLAYER → DEAD`, with a leash that
breaks off a chase rather than being dragged away from the player. Targets come from its own
`DetectionArea` rather than a scene scan. Health and damage are read from its `ShadowInstance`'s
level, recomputed rather than adjusted so a level-up can never compound. Its death frees the entity
and leaves the instance untouched.

**`PlayerShadowSummoner`** (`scripts/player/player_shadow_summoner.gd`) — a component on the player,
beside the collection: the collection owns what is *held*, this owns what is *out*. One at a time,
enforced here rather than by every caller — summoning a second recalls the first. The entity is
parented to the scene, not to the player, so it moves under its own power. The active instance id
lives in `PlayerRuntimeState`, which is what makes a shadow re-summon itself after a scene change;
a recall, a shadow's death and the player's own death all clear it, so none of those come back by
themselves.

### Command and target ownership

Three components, three questions, no overlap:

| Component | Owns |
| --- | --- |
| `PlayerShadowCollection` | what is **held** |
| `PlayerShadowSummoner` | what is **out** |
| `PlayerShadowCommander` | what it is **told** |

**`PlayerShadowCommander`** (`scripts/player/player_shadow_commander.gd`) is the only thing in the
shadow system that reads input. It owns the three bindings (`shadow_recall` = Q,
`shadow_mode_toggle` = T, `shadow_attack_command` = middle mouse), the aim raycast, and the target
marker. Orders reach the shadow as method calls, never as events it has to interpret — so the same
order can come from a key, from the HUD, or from a test, and the shadow is drivable without faking
input.

It is a pausable node using `_unhandled_input`. Every menu pauses the tree, so shadow commands
cannot fire behind an open UI; that is the whole mechanism, and there is no second guard for it.

**Command mode** (`BasicMeleeShadow.CommandMode`) belongs to the summoned entity, not to
`ShadowData` — it is how one shadow is being used right now, not what that kind of shadow is.
`FOLLOW` never picks a fight; `AGGRESSIVE` does. Both obey an order. It is mirrored into
`PlayerRuntimeState.active_shadow_mode` as a plain int so a shadow that re-summons itself after a
scene change comes back in the mode it was fighting in; anything that leaves no shadow out clears
it back to the default.

**Target priority** is resolved in one place, `BasicMeleeShadow.get_target()`: the manual order
first, then the automatic target in `AGGRESSIVE`, then nothing. `is_valid_target()` is the single
answer to "may it act on this" — valid, in the tree, alive, and inside the leash — and every state
asks it rather than repeating the checks. `_validate_targets()` runs once per frame before any
state looks at a target, so no state ever sees a corpse.

**The leash** (`max_combat_distance_from_player`, 18m) is measured from the **player**, not from
the shadow: the point is to keep the fight near whoever is being guarded. A target already outside
it refuses the order rather than starting a chase that gets abandoned.

**Quick recall** is tactical and is not the collection menu's *Richiama*, which despawns. It clears
both targets, lets an active attack window finish before it walks (a hitbox cut off inside its own
frame is a live hitbox on a walking shadow), and holds the shadow off from picking its own fights
for `recall_hold_duration`. Without that hold an `AGGRESSIVE` shadow re-acquires the moment it gets
home and the order is undone within a second of being given.

**The aim ray** uses the camera's direction and the **player's** position. Starting it at the
camera meant a wall close behind the player ate the order — a third-person camera artefact, not
something the player did. Its mask is world plus enemy bodies: the world is in there on purpose, so
a wall between the player and an enemy is a miss rather than a hit on what is behind it.

**`ShadowTargetMarker`** (`scripts/shadows/shadow_target_marker.gd`) is feedback for one command,
not a lock-on: it points at a target already chosen and nothing reads it back. One marker exists and
is moved between targets, because a marker parented to its subject would be freed with it.

### Stuck recovery

Progress, not position, decides that a shadow is stuck: one standing still because it has arrived
is fine, one that should be walking and is not is not. No progress for `stuck_check_duration`
triggers a **repath** — a stale path is far more common than a trapped shadow. Only a shadow still
stuck after that AND further than `hard_recovery_distance` from the player is repositioned, behind
`recovery_cooldown`, to the follow offset beside the player — a spot that is walkable by definition,
because the player is standing there. Standing still inside `attack_range` of a target is fighting,
not being stuck, and is excluded. Falling out of the level is the one case handled immediately,
since every extra second of it is another ten metres down.

The shadow asks the NavigationAgent for the nearest **navigable** point rather than a raw one: a
moving target's exact centre is off the navmesh more often than not, and an agent given an
unreachable point returns no path at all — which reads as a shadow that simply stops.

### Kill attribution

`HealthComponent` records `last_damage_source` and emits `died_from(source)` alongside the unchanged
`died`; `Hurtbox` passes the source through instead of discarding it; `RoomCombatant.report_death()`
records the killer and exposes `get_killer()`. The `enemy_died(combatant)` signature did not change
— whoever cares about the killer asks the combatant. `PlayerProgression` reads it to split the
reward: the player keeps the whole of its own kills, and the shadow takes
`PlayerProgression.SHADOW_KILL_SHARE` (70%) of a kill it finished, with the player taking the
remainder rather than a second rounded share, so the two halves always sum to the full reward.

### Collision layers

Named in `project.godot`. 1 world, 2 player body, 4 enemy body, 8 player hitbox, 16 enemy hurtbox,
32 enemy hitbox, 64 player hurtbox, 128 shadow body, 256 shadow hurtbox, 512 shadow hitbox.

The shadow's **body** masks the world only. Enemies never had its layer in their mask, so making it
solid to them in one direction only meant an enemy walking at the player could pin the shadow
against nothing. Who stands where in a fight is decided by attack ranges, not by bodies shoving
each other.

There is no friendly-fire check anywhere, because the masks make it unrepresentable: the shadow's
hitbox sees layer 16 only (enemy hurtboxes) and the player's hitbox likewise, so neither can reach
the other's hurtbox. Enemy and boss hitboxes mask 320 (player hurtbox + shadow hurtbox), so their
swings reach both.

### Interaction ownership

`InteractionPrompt` is now a small stack rather than a single owner. Everything in reach registers,
and the prompt shows the highest priority, most recently raised — a shadow remnant outranks ordinary
loot. Each interactable checks `InteractionPrompt.should_act()` before acting, so the prompt is a
single shared answer to "what does E do right now", and whoever acts consumes the input event. Both
halves are needed: acting also releases the prompt, which the next interactable in range would
inherit within the same frame, so without consuming the event one press would reach two of them.
When the winner goes away the runner-up takes the prompt over instead of leaving the player with
nothing to press.
