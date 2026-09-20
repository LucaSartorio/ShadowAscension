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

**Pause menus** — the character sheet and the inventory both join the `pause_menu` group, and
opening one closes the others. Only one is ever up, so C and I always do what they say.
