# ShadowAscension — Technical Architecture

Architecture reference for the project. Describes structure, principles, and forward direction.
Does **not** commit to unimplemented features or undocumented game-design choices.

This file owns **how the systems are built**: data-driven architecture, state separation, the
content pipeline, and the gameplay/visual split. Milestone order lives in `ROADMAP.md`, design
decisions in `GAME_DESIGN.md`.

Sections 1–10 are the standing principles. The sections after them describe **what exists today**,
milestone by milestone. *Direction for M10+* at the end describes what is planned and is explicitly
not yet built.

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
    tests/                   # test scenes + SceneTree flow scripts, grouped by system
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
- Groups (`add_to_group`) are used for tagging, never as a replacement for typed references.
- **A group name is a typed constant on the class that owns the group**, never a bare literal at the call site: `Player.GROUP`, `DungeonBoss.GROUP`, `SceneTransition.GROUP`, `InteractionPrompt.GROUP`, `RunSummary.GROUP`. A mistyped constant is a parse error; a mistyped string is a lookup that silently finds nothing. (M10.1 closed the last exception, `"player"`, which had been repeated across 23 call sites.)
- **Finding a node outside your own subtree goes through a static helper on the owner**: `SceneTransition.find_in(tree)`, `InteractionPrompt.raise()` / `.clear()`, `RunSummary.dismiss_open(tree)`. The group name and the cast then live in one place instead of in a private helper copied into every caller.
- **A node placed in a scene reaches that scene's root as its `owner`**, not by walking up: `RunSummary` and `DungeonObjectiveUI` find their `DungeonController` as `owner as DungeonController`, which is null in the hub. (M10.4 first tried a static `DungeonController.find_for(node)`; with it in the script, Godot 4.5 reported GDScript instances and RIDs leaked at exit on every flow run through the dungeon, and removing it — nothing else — made them go. The cause inside the engine was not pinned down, so the observation is recorded rather than a rule about statics.)

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

**Components that exist** (`scripts/combat/`), shared by the player, enemies, bosses and shadows:

- **`HealthComponent`** (`Node`) — tracks `current_health` / `max_health`; emits `health_changed(current, maximum)` and `died`, and records `last_damage_source` for the owner to read. `reset_to(maximum)` sets a new maximum *and* refills, which is what an actor calls when its real maximum arrives after the component's own `_ready()`.
- **`Hitbox`** (`Area3D`) — active only during attack frames via `activate()` / `deactivate()`; emits `hit_landed(target, damage)`, and will not hit the same target twice within one activation.
- **`Hurtbox`** (`Area3D`) — receives hits, honours `is_invulnerable` (dodge i-frames), and forwards damage to the `HealthComponent` it is wired to.
- **`AttackStep`** (`Resource`) — one step of a combo as data: timings, damage and the window in which the next step can be buffered.

Progression stats live in `scripts/player/` (`PlayerProgression`, `ProgressionStats`) rather than in a generic stats component, because so far only the player has allocatable stats.

**Still direction, not built:**

- **A stats component shared by every actor** — enemies read their numbers from their own Resource today. Generalising this is part of the data-driven pass in **M10**.
- **A movement component** — movement math currently lives in the actor scripts. Extracting it is **M10** work, and **M11** is what will need it (sprint, stamina, dodge variants).

These two are directions, not commitments; the API is settled when the owning milestone starts. They are documented here so future implementations converge rather than diverge.

Communication rules for components:
- Components never reach across the tree to poke other components on other actors. Interaction happens through hitboxes/hurtboxes, signals, or an event bus.
- Components on the same actor may call each other directly (e.g. `Hurtbox` → `HealthComponent`) via a reference wired at `_ready()`.

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

### Configuration versus runtime state (M10.3)

The two are kept apart because they have different lifetimes and different owners, and confusing
them is how shared state leaks between entities.

- **Configuration** is what a *kind* of thing is: an enemy archetype's health and speed, the XP
  curve, a shadow type's growth per level. It is authored in the editor, saved as `.tres`, shared by
  every entity of that kind, and **never written during play**.
- **Runtime state** is how *one* thing is doing: this enemy's current health, this shadow's level,
  this boss's phase-2 speed. It belongs to the entity (or, for the character, to the session) and
  starts from the configuration.

An entity that needs per-instance values **copies them out of its asset once, in `_ready()`**, and
works on the copies: `BasicMeleeEnemy`, `DungeonBoss` and `PlayerProgression` each seed their own
fields in one apply function. Those fields carry **no literal values of their own** — until M10.3
they carried a second copy of every number, and the boss's had already drifted (600 HP in the script
and in its scene, 900 in its asset). With no asset assigned, the apply function warns and falls back
to a fresh instance of the resource class, so even the fallback's numbers exist in one place: the
resource script's defaults, which are also what a new asset starts from in the editor. An
archetype's real numbers are the ones saved in its `.tres`.

Current health is never configuration. A `HealthComponent` is given its maximum by its owner through
`reset_to()`, explicitly, after the owner has read its asset — the scenes carry no health value of
their own for the enemy, the boss or the shadow.

Sharing a configuration asset is safe exactly because nothing writes to it. No `.tres` here is
`resource_local_to_scene`, and none needs to be; what *is* mutable and per-instance — materials, a
navigation mesh, a collision shape — is duplicated by its owner before it is changed.
`tests/core/game_data_run.gd` checks the rule on the real dungeon: two enemies sharing one
`EnemyData`, one damaged and retuned, the other and the asset unchanged.

| Resource | Responsible for | Main fields | Read by | Must NOT contain |
| --- | --- | --- | --- | --- |
| `EnemyData` (`scripts/enemies/enemy_data.gd`) | one enemy archetype | `xp_reward`, `max_health`, movement, perception, spacing, attack damage and timings, telegraph | `BasicMeleeEnemy._apply_stats()` | current health or any fight state; placement (approach angle, attack desync — set per instance in the room); loot and shadow drops, which `LootDropper` and `ShadowSource` declare |
| `BossStats` (`scripts/enemies/bosses/`) | the boss's body | `xp_reward`, `max_health`, movement, spacing, decision, phase 2, encounter beats | `DungeonBoss._apply_stats()` | its attacks (each a `BossAttack`); its display name, still on the node; phase or health state |
| `BossAttack` (`scripts/enemies/bosses/`) | one boss attack | damage, timings, range, multi-hit, phase-2 variants, weights, telegraph | `DungeonBoss` | cooldown remaining or any per-fight state |
| `ProgressionStats` (`scripts/player/`) | the player's progression rules | starting level and stat block, XP curve, points per level, cap, derived-stat rates | `PlayerProgression._apply_tuning()`; `PlayerProgressionData.from_stats()`, once per session | level, XP or allocated points — those are `PlayerProgressionData`, runtime state |
| `AttackStep` (`scripts/combat/`) | one step of the player's combo | damage, startup / active / recovery, dodge-cancel window, tilt | `Player` | combo position or timers |
| `ShadowData` (`scripts/shadows/`) | one kind of shadow | `id`, name, extraction chance, summon scene, base health and damage and their growth, XP curve | `ShadowInstance`, `ShadowSource`, `ShadowRemnant`, the menus | a shadow's level or XP — every shadow of a type shares this, so progress on it would be shared too; that is `ShadowInstance`'s |
| `ItemData`, `LootTable`, `LootTableEntry` (`scripts/items/`) | items and what drops them | see *Items and loot* | inventory, equipment, `LootDropper` | stack counts or what is carried |

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
- Storing *scene-scoped* gameplay state (the current room, the enemy being fought, what a hitbox has hit this swing). This belongs in scene-owned components.
- Shortcut access to nodes that could be reached via injection.
- "Managers" that mix unrelated concerns.

**The project has exactly one autoload today: `PlayerRuntimeState`**, documented in full below. It is the deliberate edge of the rule above: a scene change destroys the player, so the values that belong to the *session* rather than to any one scene — level, XP, allocated stats, current health, inventory, equipment, the shadow collection — have to live somewhere that outlives it. It is a store, not a manager: it holds and returns data and owns no formula. M10 formalises this as the **Persistent Player State** category (see *Direction for M10+*).

Every autoload is documented (what it owns, its public API, its lifetime) at introduction.

---

## 8. Save System Direction

Not implemented. **Scheduled for M19**; until then this is direction only, so the work converges:

- Save format: JSON or Godot Resource (`.tres`) — decision deferred until the first save/load milestone.
- Save is a snapshot of *definitions in use* + *runtime state*, not of scene instances. Scenes are rebuilt from saved state on load.
- Responsibility: a dedicated `SaveService` autoload will orchestrate save/load; each domain (progression, inventory, shadow collection) exposes a `to_save_dict()` / `from_save_dict()` pair. Systems own their own serialization — the save service coordinates, it does not know internals.
- Versioned save format from day one (a `version` field), with a migration hook for future format changes.
- No save/load calls per frame. Explicit save points (hub return, boss cleared, manual save) only.

Concrete decisions are made at M19; nothing above binds gameplay-design choices.

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

The project has no third-party test framework and does not need one: the harnesses are written in
GDScript and Godot runs them headless. They grew with the systems they cover, and by the close of
M9 there were **31 suites and 1265 assertions**.

Two shapes, because two different things need testing:

- **Scene suites** — `tests/<area>/<suite>.tscn`, one scene that builds a system in isolation and
  asserts against it. This is most of the suite count: combat, enemies, bosses, items, player,
  dungeon, shadows.
- **Flow scripts** — `tests/<area>/<name>_run.gd`, `extends SceneTree`, for anything that must
  actually change scene: the whole-game runs in `tests/core/` (vertical slice, QA, repeated full
  runs, balance baseline) live here, because a scene suite cannot survive the scene being swapped.

Both print `[PASS]` / `[FAIL]` lines and a closing `[SUMMARY]`; the invocations are in the
repository README.

**`tests/run_all.gd` runs all of them** (M10.5), each in its own Godot process, and reports every
suite's passes, failures, **runtime errors and exit-time leaks**, exiting non-zero if any are present:

```
godot --headless --path . --script res://tests/run_all.gd
```

The last two columns are there because a PASS/FAIL count cannot see them: M10.4's first version
leaked GDScript instances on every run through the dungeon while every assertion passed. At the
close of M10 the run is **35 suites and 1430 assertions**, all clean.

**Parser warnings** are what the editor shows in the script panel; headless, nothing prints them.
To see them all at once, put an `override.cfg` in the project root that raises each warning to an
error (`[debug]` then `gdscript/warnings/unused_variable=2`, and so on for the others), run
`godot --headless --path . --check-only --script res://<file>.gd` over the scripts, and **delete the
file afterwards** — it overrides the project settings for the editor too. At the close of M10 the
game scripts have none; some older test scripts still carry harmless ones (redundant `await`s,
unused locals), left alone because they are tests and not wrong. Two that were not harmless — a
check computed and never asserted, and a call to a method that did not exist — were fixed.

Rules that hold regardless:
- **Manual validation** is still mandatory after any significant change: run `godot --path .` (or
  `--headless --quit` for a smoke check), confirm zero runtime errors, zero parser warnings.
- A change that touches a system runs **that system's suite and the end-to-end runs** before it is
  called done. Several of the bugs closed in M9.2 were only visible end to end.
- **Never guard a test's action behind `has_method()`.** A renamed method then turns the action
  into a silent no-op and the assertion after it into a tautology: `qa_run` asked for a `drop()` and
  a `_check_cleared()` that never existed, so two of its checks tested nothing for a whole milestone.
  Call the method; if it goes away, the test should fail to compile.
- **Write the test against the rule, not against the observation.** More than one apparent bug in
  M8–M9 turned out to be the harness: measuring speed in m/s where headless physics outruns wall
  clock, or placing an actor outside the level geometry. A failing assertion is a claim about the
  game that has to be checked in both directions.
- **Definition of Done** (from `CLAUDE.md`) is the acceptance bar for every task: project launches,
  zero runtime errors, zero parser errors, coherent structure, feature verifiable, docs updated.

---

## Boot flow and scenes

`Main.tscn` is the project's `run/main_scene` and stays a bootstrap router, never a gameplay scene:
it holds the main menu and a `SceneTransition`, nothing else. The route is

```
Main.tscn (MainMenu)  --GIOCA-->  scenes/core/hub.tscn  --DungeonGate-->  scenes/dungeons/dungeon_test.tscn
                                        ^                                          |
                                        +---------------- DungeonExit -------------+
```

**`MainMenu`** (`scripts/ui/main_menu.gd`) is a router with no state. GIOCA is a New Game, and
since M10.2 it is the one place the session is reset (`PlayerRuntimeState.reset_runtime_state()`),
rather than that being left to whichever scene happens to come up first. It emits `quit_requested`
before asking the application to close, and `quit_on_request` turns the closing off — a headless run
can then watch the choice without the process going away underneath it.

**The hub** (`scenes/core/hub.tscn`) is the former test world, renamed rather than duplicated. It is
where a run starts and ends, and it owns the same UI stack the dungeon does, minus the
dungeon-specific pieces.

## Scene communication (M10.4)

Who knows about whom. The rule is one direction per relationship: an owner holds references to what
it owns and calls it; what is owned reports back with signals; the UI observes and never drives.

| Mechanism | Used for | Examples |
| --- | --- | --- |
| **Owner wiring** | an entity handing its own parts the siblings they need | `Player._wire_components()` → `setup()` on progression, equipment, summoner, commander |
| **Injection at creation** | a node made at runtime for someone | the summoner binds each shadow to its player; a `ShadowSource` configures its remnant; a `LootDropper` configures its items |
| **The body that arrived** | an interactable acting for the player in front of it | `WorldItem` and `ShadowRemnant` keep the `Player` from `body_entered` |
| **`owner`** | a node reaching the root of the scene it was placed in | `RunSummary`, `DungeonObjectiveUI` → their `DungeonController` |
| **Own subtree** | a controller finding what belongs to its scene | `DungeonController` resolves its player once, inside itself; `DungeonRunStats` asks it |
| **Signals** | everything that flows back up, and everything the UI shows | `enemy_died`, `room_cleared`, `dungeon_completed`, `xp_changed`, `shadow_summoned`, `extraction_finished` |
| **Typed groups** | genuinely "whoever that is" lookups, done once | enemies acquire `Player.GROUP`; HUDs find the player once on ready; `BossHealthBar` finds `DungeonBoss.GROUP` |

**Dependency rules.**

- **Gameplay never calls the UI.** The last exception, `ShadowRemnant` driving the extraction banner,
  went in M10.4. The UI subscribes; an extraction lands with no banner in the scene at all.
- **A component never looks up its siblings by name.** The player is the one place that knows its
  layout (`$VisualRoot/AttackHitbox` lives in exactly one `@onready` line), so moving a node is a
  one-line change. Generic combat components that find their own `HealthComponent` sibling
  (`Hurtbox`, `EnemyHealthBar3D`) keep doing so: that is local to one entity and the same everywhere.
- **Something acting for a player acts for a specific player**: the shadow its summoner bound, the
  loot and remnant the one standing on them, the dungeon the one inside it.
- **Generic scenes do not know the level they are in.** A player, an enemy, a shadow, a gate, an item
  and a remnant each come up on their own and either work or stand still — nothing assumes a
  `Player`, a `HUD` or a `DungeonController` at a known path.
- **No lookups per frame.** Enemies and the boss cache the player they acquire; the character sheet
  caches its player instead of searching on every refresh.
- **A connection to something that outlives the connector is dropped explicitly** in `_exit_tree()`
  — the two `SceneTree.node_added` listeners (`DungeonRunStats`, `ExtractionFeedback`) do.

**Main flows.**

```
Enemy death    Hurtbox.receive_hit(amount, source) -> HealthComponent (records the source)
               -> RoomCombatant.report_death(killer) -> enemy_died
                  -> RoomController (counts it)       -> room_cleared -> DungeonController
                  -> PlayerProgression._collect()     (claim_xp() pays once)
                  -> LootDropper, ShadowSource        (drop, leave a remnant)
                  -> DungeonRunStats                  (tallies it once)

XP             PlayerProgression.add_xp() -> PlayerProgressionData (the session's)
               -> xp_changed / level_changed / level_up -> ProgressionHUD, character sheet

Shadow kill    the killer is the node the HealthComponent recorded, as a reference: a
               BasicMeleeShadow whose instance is in this player's collection
               -> 70% ShadowInstance via PlayerShadowCollection.award_xp(), 30% add_xp()
               -> shadow_xp_gained / shadow_leveled_up -> the summoned entity, the banner, HUDs

Extraction     ShadowRemnant.attempt_extraction() -> extraction_started -> banner
               -> the extracting player's collection.add_shadow() -> extraction_finished -> banner

Gate           DungeonGate (player in range, [E]) -> gate_activated
               -> SceneTransition.transition_to_scene() -> the dungeon scene is built

Completion     the boss dies like any combatant -> its room clears -> dungeon_completed
               -> exit portal enabled, RunSummary opens; the boss never knows the dungeon
```

**Deliberately unchanged**, with the reason. Enemies acquire the player through the typed group:
the room could hand them the player that walked in, but choosing a target is M12's to redesign (the
shadow is not a target yet). And the rule for which interactable answers [E] when two overlap lives in
`InteractionPrompt.should_act()` — a UI node arbitrating gameplay. It works, it is the contract
CLAUDE.md §9 prescribes, and moving it means moving the whole interaction system to the player, which
is its own change.

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

`scripts/core/player_runtime_state.gd`, registered as the autoload `PlayerRuntimeState`. It is the
**Persistent Player State** of the M10 category table below, and the only one of the six that has an
owner in code today.

**Reached by node name, from one place.** `Player.session(node)` is the single accessor; the seven
player scripts that need the session call it through their own one-line `_runtime_state()`, and the
autoload's node name lives once, in `Player.RUNTIME_STATE_NODE`.

**It is deliberately *not* reached through the `PlayerRuntimeState` autoload global**, and that is a
constraint rather than a preference. A flow test entered through `--script` compiles the game's
scripts *before* the autoloads are registered, so the global identifier does not resolve and every
script naming it fails to compile — `player.gd` first, taking the boss, the rooms, the dungeon and
the gate down with it. Scene-based suites and a normal boot do not show this, because there the
autoloads come up first. M10.1 tried the global, the flow harnesses rejected it, and the lookup by
name went back. Anything that reaches the session must go through `Player.session()`.

One consequence is worth stating: the accessor returns an untyped `Node`, so nothing about the
session contract is checked at parse time. Fixing that means giving the script a `class_name`, which
cannot be `PlayerRuntimeState` — Godot refuses a class that hides an autoload singleton — so it
means a second name for one concept. That is a decision for the later steps of M10, where the state
categories are formalised, not a change to smuggle into an audit.

**Global runtime session data — not a save system.** Nothing here touches the disk. Closing the
game starts a fresh session at level 1. Permanent saving is a separate milestone and will not live
in this node.

It exists because a scene change destroys the player and builds a new one. It is the one autoload
CLAUDE.md §4 allows: genuinely global state that has to outlive a scene, not gameplay logic parked
in a singleton. It holds data and owns no behaviour — every formula, from the XP curve to each
derived stat, stays in `PlayerProgression`. It is not a `GameManager`, a `SceneManager`, or a
general blackboard, and nothing unrelated to player session data belongs in it.

### What it holds (M10.2)

| Field | What it is |
| --- | --- |
| `progression: PlayerProgressionData` | level, XP into the level, unspent points, the allocated stat block |
| `shadows: Array[ShadowInstance]` | every extracted shadow, each carrying its own level and XP |
| `next_shadow_index` | the id counter, so two scenes never mint the same shadow id |
| `active_shadow_instance_id`, `active_shadow_mode` | which shadow was out, and how it was fighting, so it re-summons after a scene change |
| `current_health` | the hand-off value between one player and the next; negative means "full" |
| `inventory`, `equipment` | what is carried and worn, still as copies the components sync (see below) |

**The progression and the shadows are held by reference, not copied.** Until M10.2 each of them
existed twice: `PlayerProgression` kept its own `current_level`, `current_xp` and stats and wrote
them back through a sync call, and `PlayerShadowCollection` rebuilt new `ShadowInstance` objects
from flat rows on every scene and flattened them back on every change. Both copies were kept in step
by hand, and a missed sync was exactly the M6.3 class of bug. Now there is one
`PlayerProgressionData` and one shadow array per session; every player scene attaches to those same
objects on `_ready()` and reads and writes them in place. There is nothing to restore on the way in
and nothing to write back on the way out, so neither step can be forgotten.

### Who owns what

| Data | Stored in | Only writer | Consumers are told by |
| --- | --- | --- | --- |
| Player level, XP, points | `PlayerProgressionData` | `PlayerProgression.add_xp()`, `allocate_stat()` | `xp_changed`, `level_changed`, `level_up`, `stat_points_changed` |
| Player allocated stats | `PlayerProgressionData` | `PlayerProgression.allocate_stat()` | `stats_changed` |
| Effective / derived stats | nowhere — computed | `PlayerProgression` getters, from the data plus equipment | `stats_changed` |
| Shadow level and XP | its `ShadowInstance` | `PlayerShadowCollection.award_xp()` | `shadow_xp_gained`, `shadow_leveled_up`, `collection_changed` |
| Which shadows exist | the session's shadow array | `PlayerShadowCollection.add_shadow()`, `remove_shadow()` | `shadow_added`, `shadow_removed`, `collection_changed` |
| Max health | nowhere — derived | `Player._apply_stat_effects()`: base + VIT + equipment | `HealthComponent.health_changed` |
| Current health | the player's `HealthComponent` | combat, through the hurtbox | `HealthComponent.health_changed` |
| Current health, between scenes | `PlayerRuntimeState.current_health` | `Player`, on every `health_changed` | read once, when the next player spawns |
| Run tally | `DungeonRunStats` | its own signal handlers | `stats_changed` |
| Dungeon progress | `DungeonController`, `RoomController` | their own signal handlers | `objective_changed`, `room_cleared`, `dungeon_completed` |

**The UI owns none of it.** Every HUD and menu reads the owner's getters and redraws on the owner's
signals; the only writes any UI makes go through the owner's API — `allocate_stat()` from the
character sheet, `toggle()` from the shadow menu, `equip()` from the inventory. Nothing polls.

**Kill attribution and the 70/30 split** are `PlayerProgression._collect()`: the combatant hands
its reward over exactly once (`claim_xp()` latches), the killer is whoever `HealthComponent`
recorded as the last source, and a kill the summoned shadow finished pays it
`round(reward × SHADOW_KILL_SHARE)` through `award_xp()` while the player keeps the remainder
through `add_xp()`. The summoned `BasicMeleeShadow` is a runtime view onto its `ShadowInstance` — it
reads its health and damage from the instance's level and stores no progress of its own.

### Lifecycle

| Moment | What happens to the persistent state |
| --- | --- |
| **New Game** (GIOCA) | `MainMenu` calls `reset_runtime_state()` — the one reset point. The progression and the shadow array are *replaced*, so anything still holding the old ones cannot write into the new game. |
| **First player of the session** | `get_or_create_progression(stats)` builds the character from `ProgressionStats`. The only place starting values are applied. |
| **Scene change** (gate, exit) | The scene and its player are freed and rebuilt. The session is untouched; the new player attaches to the same objects. |
| **In the dungeon** | Kills write XP into the session as they happen. The run and dungeon state live in the dungeon scene and die with it. |
| **Death** | `reset_health_to_max()`; the dungeon reloads. Progression and shadows are untouched. |
| **Return to the hub** | A scene change like any other. |
| **Return to the menu** | Nothing in the game leads there yet. When something does, GIOCA already resets, so no session can leak into the next. |

**Initialization is split three ways**, which is what closes the M6.3 bug class: *first
initialization* is `get_or_create_progression()`, once per session; *a scene coming up* only
attaches, and `PlayerProgression._ready()` applies tuning (the XP curve, the derived-stat rates) but
never a starting value; *an explicit reset* is `reset_runtime_state()`, called by New Game and by
tests.

**Max health is deliberately not stored.** It is recomputed from the player's own base plus VIT on
every load, so the two can never desync. A negative `current_health` means "start at whatever this
player computes as its maximum" — both the fresh-session state and what a death leaves behind.

**Inventory and equipment are still copies.** `PlayerInventory` and `PlayerEquipment` restore a copy
on `_ready()` and sync one back on each change, the pattern the progression and shadows used to
follow. They were left alone because M10.2 was scoped to progression, shadows and health; they are
the next candidates for the same by-reference treatment.

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
result shows briefly, and the remnant goes whether it worked or not. It is gameplay only: it
announces the attempt and its outcome through `extraction_started` / `extraction_finished`, and the
banner (`ExtractionFeedback`) watches remnants appear and listens — before M10.4 the remnant found the
banner and drove it. The shadow goes to the player that made the attempt, taken from the body that
walked in, not to whichever player a group search finds first. A remnant is **not** an enemy:
a room clears and its doors open the moment the last enemy dies, regardless of what is still
standing on the floor.

**`PlayerShadowCollection`** (`scripts/player/player_shadow_collection.gd`) — a component on the
player holding `ShadowInstance` objects rather than a count per type. It mints the ids; the session
remembers where the counter got to, so two scenes can never hand out the same number. The array it
holds *is* the session's (`PlayerRuntimeState.shadows`), taken by reference on `_ready()`, so every
extraction and every XP award is already in the session when it happens. `award_xp()` pays one named
shadow — only the one that struck the killing blow earns anything — and is the only thing that
changes a shadow's level or XP.

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
parented to the scene, not to the player, so it moves under its own power, and it is **bound to this
player** (`bind(instance, player)`) before it enters the tree: that is the owner it follows, defends
and returns to. A shadow nobody bound has no owner and stands still. The active instance id
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

`HealthComponent` records `last_damage_source` and emits the unchanged `died` (a separate
`died_from(source)` signal, never connected, was removed in M10.5); `Hurtbox` passes the source
through instead of discarding it; `RoomCombatant.report_death()`
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

---

# Direction for M10+

Everything above this line describes what exists. Everything below is **planned and not yet
built** — direction for the Core Production Foundation phase and what follows it. Nothing here
should be read as a description of the current code.

## Data-driven architecture (M10)

The vertical slice is already partly data-driven: `EnemyData`, `BossStats`, `BossAttack`,
`ProgressionStats`, `ItemData`, `LootTable`, `AttackStep` and `ShadowData` are all `Resource` assets
today, described in §5. M10 finishes the job and gives every domain one named definition resource —
each introduced when a system actually reads it, never as an empty file ahead of one:

| Resource | Owns | State |
| --- | --- | --- |
| `PlayerData` / `PlayerStats` | the player's definition and its stat rules | progression rules exist as `ProgressionStats`; movement, dodge and combo are still `@export`s on the player scene (see below) |
| `EnemyData` | an enemy archetype's definition | **exists since M10.3** — renamed from `EnemyStats`, no longer copied into literals |
| `SkillData` | one skill: cost, cooldown, range, area, effects | not built — no skill exists (M17) |
| `ItemData` | one item | exists; extended for the M16 slot set |
| `ShadowData` | one kind of shadow | exists; extended for rank and skills (M17) |
| `DungeonData` | a dungeon's composition rules | not built — one dungeon, one scene (M18) |
| `GateData` | a gate: rank, contents, rewards | not built — one gate, configured on its node (M18) |

**What M10.3 deliberately left in code**, and why:

- **The player's movement, dodge and combo values** are `@export`s on `player.gd`, set on the one
  player scene, and the combo's three `AttackStep`s are sub-resources of that scene. They are
  already editable in the inspector and exist once. A `PlayerData` would have one consumer and no
  variant, and M11 reshapes exactly this block (heavy attack, stamina, sprint), so it is built there.
- **The summoned shadow's AI tuning** — follow distance, leash, attack timings, stuck recovery — is
  `@export`s on `basic_melee_shadow.gd`, which is already per-type because `ShadowData.summon_scene`
  names the scene. It moves with the shadow AI rebuild at M17.
- **The boss's display name** is still an `@export` on its node; M12's boss framework decides
  where boss identity lives.
- **`PlayerProgression.SHADOW_KILL_SHARE` (0.70)** is a rule of the shadow system, defined once. If
  the split ever varies — by shadow rank, say — it will vary per shadow, so the data it belongs to
  is decided at M17 rather than guessed now.
- **The gate, the exit, the doors and the dungeon's objective texts** are `@export`s on their nodes:
  there is one of each, and `GateData` / `DungeonData` arrive with the gate ranks at M18.
- Timing constants inside behaviour (`AVOIDANCE_FALLBACK_FRAMES`, prompt priorities, the id format)
  are implementation, not design, and stay constants.

The rule that already governs resources still holds: definitions are pure data with minimal derived
getters, and `.tres` is preferred over `.res` for diff-ability. Instance state lives in components —
except the character's, which since M10.2 lives in the session's data objects
(`PlayerProgressionData`, `ShadowInstance`) and is only *viewed* by components. Today the player's
definition is `ProgressionStats`; `PlayerData` is where it goes once there is more to define.

## State separation (M10)

M10 separates state into six categories, with no system reading or writing outside its own. M10.1
named them and gave each existing one a single owner in code; M10.2 made the persistent one a single
source of truth (see *PlayerRuntimeState* above for the ownership and lifecycle tables). The three
with no owner are not built, and inventing a home for them before a system needs one is exactly the
premature abstraction M10 avoids. A cross-scene Run State in particular was considered and not
built: one gate leads to one dungeon, the run begins and ends inside that dungeon scene, and nothing
yet carries a run's information back to the hub.

| Category | What it holds | Lifetime | Owner today |
| --- | --- | --- | --- |
| **Persistent Player State** | level, XP, allocated stats, health, inventory, equipment, shadows, skills | the character | `PlayerRuntimeState` (autoload), holding `PlayerProgressionData` and the `ShadowInstance`s |
| **Run State** | the current dungeon run: tally, temporary buffs, what the run has consumed | one run | `DungeonRunStats` |
| **Dungeon State** | the current dungeon instance: rooms cleared, doors, spawned contents | one dungeon | `DungeonController` + `RoomController` |
| **World State** | hub state, gate availability, world-level flags | the world | *nothing needs it yet* |
| **Settings** | resolution, audio, controls, graphics | the installation | *not built — M19* |
| **Save Data** | the serialised form of the above that is written to disk | across sessions | *not built — M19* |

The categories are stated in each owner's own header, so the rule is read where the code is written.
The test for what belongs where is lifetime: if a new dungeon should start a value over, it is not
Persistent Player State, however convenient the autoload would be.

**The hard requirement:** persistent data must never be reinitialised by a scene change. That class
of bug has been hit and fixed twice already — once in M6.3 (level and XP resetting through a gate)
and once in M9.2 (run stats taking their XP baseline from the player being freed during a
transition). M10.2 closed it structurally for progression and shadows: a scene has no copy to
reinitialise, only a reference to attach. `tests/core/persistent_state_run.gd` proves it by object
identity across the menu, the gate, the exit, a death and a second New Game.

## Gameplay logic and visual representation stay separate

The principle that makes M13 possible without a rewrite. A placeholder is replaced by a finished
model as a **scene-level change** that touches no behaviour.

```
Player
├── gameplay controller      <- input, movement, state
├── combat controller        <- combo, dodge, commitment windows
├── stats / progression      <- numbers
├── skills
├── hitboxes / hurtbox       <- collision shapes, owned by gameplay
└── visual model             <- the only thing M13 replaces
```

The same split applies to **Enemy**, **Boss**, **Shadow**, **Weapon** and **NPC**. The project
already works this way in the small — every combatant keeps its mesh under a `VisualRoot` that the
controller rotates, while collision shapes and hitboxes hang off the body — and M10 makes it
explicit and uniform.

Two consequences worth stating, because they are easy to lose:

- **Hitboxes belong to gameplay, not to the model.** A hitbox that is a bone attachment on an
  artist-authored rig makes combat reach an art decision.
- **Animation drives presentation, not truth.** Damage windows come from the combat controller's
  timings, not from an animation's frame events, so retiming an animation cannot silently retune
  combat.

## Before M11

M11 (Combat System 2.0) can start without another refactor: persistence, UI ownership, `EnemyData`
and the scene paths it would otherwise trip over are settled. What it should know about the combat
code as it stands:

- **The player's combat lives in `player.gd`**, beside movement and dodge — one script for the combo
  state machine, the dodge and the movement. It is the obvious thing M11 splits into a component, and
  `Player._wire_components()` is where that component is handed its siblings.
- **Damage is a single float.** `Hitbox.damage` → `Hurtbox.receive_hit(amount, source)` →
  `HealthComponent.receive_damage(amount, source)`. M11's damage model (physical, magic, critical,
  armour penetration, status) needs a payload in place of the float; `source` is already a reference
  to the attacker, which is what knockback direction and kill attribution need.
- **Invulnerability exists**: `Hurtbox.set_invulnerable()` is what the dodge's i-frames drive today.
- **The combo is data**: three `AttackStep`s, currently sub-resources of `player.tscn`. A heavy
  attack or new steps extend `AttackStep`; the player's configuration resource (`PlayerData`) was
  deferred to M11 precisely because this block changes there.
- **The player's attack hitbox hangs under `VisualRoot`**, so it inherits the cosmetic attack and
  dodge tilts. M11 decides the real hit volumes; M13 needs the hitbox off the visual node. The enemy
  already has the right shape (`VisualRoot/AttackOrigin`, apart from the mesh).
- **Finding enemies is physics, not a registry.** The shadow uses a detection `Area3D` on the enemy
  body layer and the commander a ray; target lock can do the same. No enemy group is needed.
- **Enemies acquire the player through `Player.GROUP`.** Choosing between the player and the shadow
  is M12's; an M11 target lock is the player's side only.
- **New runtime state goes where M10 says.** Stamina, stagger and combo position are the player's
  runtime state, on the component; their maxima and rates are configuration, in a resource; nothing of
  it belongs in `PlayerRuntimeState` unless the design says it must survive a scene change.
- **The session is reached through `Player.session()`**, never the `PlayerRuntimeState` autoload
  identifier — flow tests compile the game's scripts before autoloads exist.

## Content pipeline (M13+)

Godot is the engine and the runtime. Blender is a content-pipeline tool — it is not where the game
is assembled.

```
concept / reference
      -> 3D asset
      -> Blender:  modelling, mesh edits, UVs, base materials, rigging, skeleton,
                   animation prep, retargeting, optimisation
      -> GLB
      -> Godot:    gameplay wiring, shaders, VFX, lighting, level composition
```

**Environments are modular kits, not monolithic levels.** A dungeon kit — wall, floor, arch,
column, door, stairs, statue, props — is authored in Blender and *assembled in Godot*. This is what
gives reuse, better performance, simpler edits, more than one dungeon, and eventually
semi-procedural composition (M18).

**Toolchain.** The pipeline may come to include Godot, Blender, asset libraries, animation
libraries, Mixamo or equivalents where appropriate, AI-assisted tools where legally and technically
appropriate, Python scripting for Blender, and import/export automation. Deliberately **no hard
dependency on any specific service that has not been chosen yet** — the pipeline is described by
its stages, and a stage can be filled by a different tool without the rest moving.
