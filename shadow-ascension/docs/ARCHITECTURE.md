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

- **`HealthComponent`** (`Node`) — tracks `current_health` / `max_health`; `take_damage(hit: DamageInfo)` is the only way health goes down. Emits `health_changed(current, maximum)` and `died`, and — for a hit that leaves it alive, never with `died` — `damaged(hit)`, which hit reactions listen to (M11.6), and records the last hit as `last_damage` (with `last_damage_source` read off it) for the owner to read. `reset_to(maximum)` sets a new maximum *and* refills, which is what an actor calls when its real maximum arrives after the component's own `_ready()`.
- **`Hitbox`** (`Area3D`) — active only during an attack's hit window via `activate()` / `deactivate()`; carries the swing's `damage`, `source`, `attack_id`, `stagger_power`, `knockback_force` and critical chance and multiplier, sends each target one `DamageInfo` — its critical rolled for that hit, its direction worked out at impact — emits `hit_landed(target, hit)`, and will not hit the same target twice within one activation.
- **`DamageModel`** (`scripts/combat/damage_model.gd`, static, M11.7) — the damage rules in one place: `attack_damage(base, multiplier)`, `roll_critical(chance, rng)`, `final_damage(raw, critical, multiplier)`. Stateless; see *Damage model and critical hits (M11.7)*.
- **`Hurtbox`** (`Area3D`) — `receive_hit(hit: DamageInfo)`: the one place that decides whether a hit counts. It refuses hits while `is_invulnerable`, which holds while any *reason* set through `set_invulnerable(value, reason)` holds (the dodge's i-frames are one reason, since M11.4), and forwards the rest to the `HealthComponent` it is wired to.
- **`DamageInfo`** (`RefCounted`) — one hit in transit: `amount`, `source`, `attack_id` (M11.1); `stagger_power`, `knockback_force` and the flat `direction` from attacker to target (M11.6); `is_critical` (M11.7), with `amount` already the final damage.
- **`AttackData`** (`Resource`) — one attack as data: windup / active / recovery, damage multiplier, combo and dodge-cancel windows, movement multiplier, and the name of its animation (M11.1, replacing `AttackStep`; one asset per attack since M11.2).

The player's combat controller, **`PlayerCombat`**, is a player component (`scripts/player/`); so is its target lock, **`PlayerTargeting`** (M11.8), the one owner of which enemy the player is locked onto. See *Combat architecture (M11)*.

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
| `EnemyData` (`scripts/enemies/enemy_data.gd`) | one enemy archetype | `xp_reward`, `max_health`, movement, perception, spacing, attack damage and timings, hit reactions (stagger resistance / duration / immunity, knockback multiplier and deceleration), telegraph | `BasicMeleeEnemy._apply_stats()` | current health or any fight state — a stagger or a push in progress included; placement (approach angle, attack desync — set per instance in the room); loot and shadow drops, which `LootDropper` and `ShadowSource` declare |
| `BossStats` (`scripts/enemies/bosses/`) | the boss's body | `xp_reward`, `max_health`, movement, spacing, decision, phase 2, encounter beats | `DungeonBoss._apply_stats()` | its attacks (each a `BossAttack`); its display name, still on the node; phase or health state; hit-reaction tuning — the boss does not stagger or move under hits (M11.6), so it has none |
| `BossAttack` (`scripts/enemies/bosses/`) | one boss attack | damage, timings, range, multi-hit, phase-2 variants, weights, telegraph | `DungeonBoss` | cooldown remaining or any per-fight state |
| `ProgressionStats` (`scripts/player/`) | the player's progression rules | starting level and stat block, XP curve, points per level, cap, derived-stat rates | `PlayerProgression._apply_tuning()`; `PlayerProgressionData.from_stats()`, once per session | level, XP or allocated points — those are `PlayerProgressionData`, runtime state |
| `PlayerTargetingData` (`scripts/player/`, M11.8) | the player's target lock | acquisition and lose ranges, the distance weight of the pick, the facing turn speed, the body and line-of-sight masks, eye height, candidate cap | `PlayerTargeting` | which target is locked — `PlayerTargeting`'s runtime state |
| `PlayerCombatData` (`scripts/player/`) | the player's combat | base damage, critical chance and multiplier, the light combo and the heavy attack (chains of `AttackData`), input-buffer time, dodge duration / i-frames / cooldown / stamina cost, maximum stamina and its regeneration delay and rate | `PlayerCombat` | the combat state, timers, combo position, buffered input or the stamina left — `PlayerCombat`'s runtime state; the dodge's speed, which is movement and scales with AGI on `player.gd` |
| `AttackData` (`scripts/combat/`) | one attack; the light combo's three and the heavy are `resources/characters/player_attacks/*.tres` | `id`, `animation` (a name the presentation resolves), damage multiplier, windup / active / recovery, combo window, dodge-cancel window, movement multiplier, stagger power and knockback force, debug colour | `PlayerCombat`; the presentation reads `animation` | a damage number of its own — it scales the owner's base; any per-swing state (index, queue, timers, hit history); how the attack looks |
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
close of M10 the run is **35 suites and 1430 assertions**, all clean; at M11.1, **37 suites and
1506 assertions**; at M11.2, **39 suites and 1565 assertions**;
at M11.3, **41 suites and 1614 assertions**; at M11.4, **43 suites and 1677 assertions**; at M11.5,
**45 suites and 1749 assertions**; at M11.6, **47 suites and 1804 assertions**; at M11.7,
**49 suites and 1845 assertions**; at M11.8, **51 suites and 1896 assertions**, all clean. Since M11.7 a player hit can be critical at
random; a suite that checks exact damage turns criticals off for its own run (one line at the top of
its script), and the critical suites test them deterministically.

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
Enemy death    Hurtbox.receive_hit(DamageInfo) -> HealthComponent (records the hit and its source)
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
| top-left | `PlayerHealthHUD`, `PlayerStaminaHUD` right under it, then `ProgressionHUD` (level and XP) |
| top-centre | `BossHealthBar`, band y 24–88, only during the encounter |
| top-right | `DungeonObjectiveUI`, deliberately below the boss bar's band |
| bottom-centre | `InteractionPrompt` |
| bottom-right | `ActiveShadowHUD`, then the three menu hints |
| bottom-left | the target lock's hint, only while a target is locked (M11.8) |

The objective sits below the boss bar's band rather than beside it because "beside" depends on the
window width: centred and right-anchored rectangles that clear each other at one size overlap at
another.

**`PlayerHealthHUD`** (`scripts/ui/player_health_hud.gd`) is its own node rather than another block
inside `ProgressionHUD`, because health is not progression and the two are driven by different
components. It is driven by `health_changed` alone — which also fires when the ceiling moves, so a
point spent on VIT or a swapped chestpiece reaches the bar without this node knowing either system
exists.

**`PlayerStaminaHUD`** (M11.5) is the same idea for stamina: a thin, caption-less bar (y 62–72)
between the health bar and the level, driven by `PlayerCombat.stamina_changed` alone. `ProgressionHUD`
moved down 14 px to make room; `vertical_slice_run` includes the bar in its overlap check.

**`TargetLockIndicator`** (M11.8, `scripts/ui/target_lock_indicator.gd`) is the target lock shown: a
ring on the locked target plus the `[Tab] Sblocca bersaglio` / `[Z] [X] Cambia bersaglio` hint,
bottom-left, both only while a lock holds. It hears `PlayerTargeting.target_changed` and nothing else;
see *Target lock (M11.8)*.

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
| Stamina (M11.5) | `PlayerCombat` — per player, not carried between scenes | `PlayerCombat` (`try_spend_stamina()`, `restore_stamina()`, its regeneration) | `stamina_changed` |
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
is prepared, in `PlayerCombat.calculate_damage()`; since M11.1 the base is
`PlayerCombatData.base_damage` times the attack's multiplier. Nothing is ever written back into the
attack or the base, so neither the weapon nor the multiplier can stack across attacks. An empty main hand contributes 0 and
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

`HealthComponent` records the last hit (`last_damage`, a `DamageInfo`, whose `source` is
`last_damage_source`) and emits the unchanged `died` (a separate
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
`ProgressionStats`, `ItemData`, `LootTable`, `AttackStep` (now `AttackData`) and `ShadowData` are all `Resource` assets
today, described in §5. M10 finishes the job and gives every domain one named definition resource —
each introduced when a system actually reads it, never as an empty file ahead of one:

| Resource | Owns | State |
| --- | --- | --- |
| `PlayerData` / `PlayerStats` | the player's definition and its stat rules | progression rules exist as `ProgressionStats`; combat as `PlayerCombatData` since M11.1; movement and dodge speed are still `@export`s on the player scene (see below) |
| `EnemyData` | an enemy archetype's definition | **exists since M10.3** — renamed from `EnemyStats`, no longer copied into literals |
| `SkillData` | one skill: cost, cooldown, range, area, effects | not built — no skill exists (M17) |
| `ItemData` | one item | exists; extended for the M16 slot set |
| `ShadowData` | one kind of shadow | exists; extended for rank and skills (M17) |
| `DungeonData` | a dungeon's composition rules | not built — one dungeon, one scene (M18) |
| `GateData` | a gate: rank, contents, rewards | not built — one gate, configured on its node (M18) |

**What M10.3 deliberately left in code**, and why:

- **The player's movement, dodge and combo values** were `@export`s on `player.gd`, and the combo's
  three `AttackStep`s sub-resources of that scene. A `PlayerData` would have had one consumer and no
  variant, and M11 reshapes exactly this block, so it was left for M11 — where M11.1 moved the combo,
  the base damage, the buffer and the dodge's timing into `PlayerCombatData`. Movement (and the
  dodge's speed) are still `@export`s on the player.
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

## Combat architecture (M11)

M11.1 (Combat Foundation 2.0) rebuilt the player's combat as the foundation the rest of M11 extends.
The gameplay it carries is the one M2–M9 shipped — the three-hit light combo, the dodge with its
i-frames and its cancel windows, the same damage numbers — reorganised so that each step of an attack
has one owner and the animation is never the source of truth. M11.2 (Light Attack Combo Chain) made
the combo a real chain on that foundation, M11.3 (Heavy Attack & Attack Variants) added a second
attack type on the same controller, M11.4 (Dodge & I-Frames) made the dodge's phases and its
invulnerability explicit, M11.5 (Stamina & Combat Resource Management) made the dodge cost
stamina, M11.6 (Hit Reactions, Stagger & Knockback) made enemies answer the hits they take, M11.7
(Critical Hits & Damage Model 2.0) put the damage rules in one place and added critical hits, and
M11.8 (Target Lock & Combat Targeting) let the player lock onto an enemy: see *Light attack combo
(M11.2)*, *Attack types (M11.3)*, *Dodge and i-frames (M11.4)*, *Stamina (M11.5)*, *Hit reactions,
stagger and knockback (M11.6)*, *Damage model and critical hits (M11.7)* and *Target lock (M11.8)*
below.

```
Input          CameraRig (attack_light, attack_heavy — only while the mouse is captured) and
               Player (dodge, target_lock, target_switch_left / _right):
   |             the only code that reads a device. It sends intents and nothing else.
   |           PlayerTargeting.toggle_lock() / switch_target(): the locked target, if any;
   |             target_changed(target) -> TargetLockIndicator
   v
Combat         PlayerCombat.request_light_attack() / request_heavy_attack() / request_dodge()
   |             combat state, attack timeline, input buffer, combo chain, hit window,
   |             dodge timing and i-frames, stamina. Emits attack_started(attack) and
   |             stamina_changed(current, maximum) -> PlayerStaminaHUD.
   v
Attack         AttackData, from PlayerCombatData.light_combo / heavy_combo: windup / active / recovery,
   |             combo and dodge-cancel windows, damage multiplier, movement multiplier
   v
Hit detection  the player's Hitbox (Area3D), open for the active phase only;
   |             one hit per target per swing, any number of targets
   v
Damage         PlayerCombat.calculate_damage() when the window opens -> Hitbox.damage (raw);
   |             per target, DamageModel rolls the critical and gives the final damage,
   |             and the Hitbox sends a DamageInfo(amount, source, attack_id, is_critical,
   |             stagger_power, knockback_force, direction)
   |             -> Hurtbox.receive_hit(hit) -> HealthComponent.take_damage(hit)
   v
Health         health_changed -> health bars;  damaged(hit) -> the target's hit reaction
   |             (flinch, stagger, knockback) — only for a hit it survives;
   |           died -> the combatant's owner
                 -> RoomCombatant.report_death(last_damage_source) -> enemy_died
                 -> PlayerProgression (XP, split by the killer), room, loot, remnant, run tally

Presentation   attack_started(attack) -> Player faces the aim (the locked target, else the
                 camera's forward) and plays the placeholder
```

| Part | Lives in | Does not know about |
| --- | --- | --- |
| Input | `CameraRig`, `Player` (`_unhandled_input`, `_on_attack_light_pressed`, `_on_attack_heavy_pressed`, `_on_dodge_pressed`) | combat state — it asks, combat decides |
| Combat state and timeline | `PlayerCombat` (`scripts/player/player_combat.gd`) | devices, movement, the UI, health bars, enemies, XP, the dungeon |
| Attack definition | `AttackData` in `PlayerCombatData` (`resources/characters/player_combat.tres`) | anything at runtime: never written in play |
| Hit detection | `Hitbox` | who is attacking beyond `source`, what the target does with the hit |
| Damage resolution | `PlayerCombat.calculate_damage()` (outgoing); `HealthComponent.take_damage()` (incoming) | each other: the hit crosses as a `DamageInfo` |
| Presentation | `Player` (`_on_attack_started`, `_play_attack_animation`, `_play_dodge_visual`) | timing: it is told an attack started and shows it |
| Targeting | `PlayerTargeting` (`scripts/player/player_targeting.gd`) | attacks, hits, damage, the UI: it holds a target, others read it |

`PlayerCombat` is wired by the player like every other component —
`Player._wire_components()` hands it the attack hitbox, the hurtbox (for i-frames), the health
component (to hear its own death) and the progression (to scale damage). It reads progression; it
owns none of it.

### Combat state

One enum, `PlayerCombat.State`, instead of an attack state beside an `_is_dodging` flag:

| State | Meaning | Attack press | Dodge press |
| --- | --- | --- | --- |
| `IDLE` | free; no chain | starts Attack 1 now | starts a dodge (off cooldown, with the stamina for it) |
| `WINDUP` | an attack is winding up; the hitbox is shut | held by the buffer, if the attack has a next | refused |
| `ACTIVE` | the hit window: the hitbox is open | held by the buffer, if the attack has a next | refused |
| `RECOVERY` | the hitbox is shut again; the player is still committed | queues the next attack inside the combo window; held before it; ignored after it | cancels the attack, once past the attack's `dodge_cancel_recovery_fraction` |
| `DODGING` | a dodge: STARTUP, INVULNERABLE (the i-frames), RECOVERY | ignored | refused |
| `DEAD` | read from the health component, never stored | refused | refused |

Only what the current combat needs is built. There is no `STUNNED` — the player is not staggered by
anything yet (M11.6 staggers enemies; see below) — and no separate `ATTACKING`: the three phases are the
attack, whichever chain it belongs to. `is_attacking()`, `is_dodging()`, `get_current_attack()`,
`get_combo_index()`, `is_running_chain()`, `get_queued_attack()` and `has_buffered_attack()` are the
queries; `allows_turning()` and `get_movement_multiplier()` are what the player's movement asks. The
attack-press column above is for a press of the *running* chain; a press of another chain is ignored
while an attack runs (*Attack types (M11.3)*).

### Attack lifecycle

```
request_*_attack()    windup            active              recovery
      |-------------------|-------------------|-------------------|--> the queued attack, or IDLE
   attack_started      hitbox opens       hitbox closes      [ combo window ]
   (facing, anim)      (damage stamped)                      a press here queues the next
```

- **Windup** — the attack is committed and aimed; nothing can be hit yet.
- **Active** — `_open_hit_window()` works the damage out, stamps it and the attack's id on the
  hitbox and opens it. `activate()` also forgets whom the last swing hit.
- **Recovery** — the hitbox is shut; the player is still committed. A dodge can cancel it past the
  attack's cancel fraction; a press inside the combo window queues the next attack of the chain,
  which starts the moment recovery ends.

**One timing source**: `PlayerCombat._physics_process`, on `delta`. Each phase restarts its own
clock, so a phase ends on the first physics step at or past its length — at most one step late,
whatever the frame rate (`combat_foundation_test` steps a bare controller at 30 Hz and 144 Hz).
There is no `Timer` node, no `AnimationPlayer` track and no tween deciding anything; the tweens are
presentation. The node pauses with the tree — the buffer does not age during a pause — and is
freed with the player, so no timer, connection or open hit window outlives a scene change.

### Light attack combo (M11.2)

```
IDLE --press--> Attack 1 --window--> Attack 2 --window--> Attack 3 --> IDLE
                   |                    |                    (the chain always ends here)
                   +--no press in the window: the chain ends with this attack --> IDLE
```

**The chain.** `PlayerCombatData.light_combo` holds the three attacks, in order. A press on a free
player starts Attack 1. Each attack that has a next one accepts a follow-up inside its combo window;
the accepted attack is *queued* and starts the moment the current one is over, as a fresh attack
instance — its own timeline, its own hit window, nobody hit yet. An attack that did not accept a
follow-up ends the chain when it ends: the player goes free, and the next press is Attack 1 again.
Attack 3 has no next, so it always ends the chain. There is no Attack 4, no branch, no finisher
variant.

**Combo state** is three fields on `PlayerCombat`, never booleans per step:

| Field | Meaning |
| --- | --- |
| `_combo_index` (`get_combo_index()`) | where the current attack sits in the chain (0, 1, 2); `NO_ATTACK` (-1) while free |
| `_attack` (`get_current_attack()`) | the attack being performed — always `light_combo[_combo_index]` |
| `_next_attack` (`get_queued_attack()`) | the attack accepted to follow it — always `light_combo[_combo_index + 1]` — or null |

**Reset.** The chain is dropped — index `NO_ATTACK`, nothing queued, nothing buffered — whenever the
player goes free: Attack 3 ending, an attack ending with nothing queued, a dodge, `reset()`, the
player's death (combat resets on its own `died`), and a scene change (the whole combat is freed with
the player). There is no timeout while free, because nothing of the chain survives going free — the
M11.1 combo kept the chain open for 0.8 s after an attack; M11.2 removed that, so "the next attack is
Attack 2" can never outlive the attack that accepted it.

**Combo window.** A stretch of the attack's recovery, as fractions of it:
`combo_window_start` and `combo_window_end`. Both shipped attacks with a follow-up use the whole
recovery (`0.0` to `1.0`); Attack 3's are never read. A press:

| When | What happens |
| --- | --- |
| free | Attack 1 starts now |
| inside the window | the next attack is queued at once |
| up to `input_buffer_time` before the window opens (late windup, active) | held by the buffer; queued when the window opens |
| earlier than that (the start of the attack) | too early: the buffer expires and it does nothing |
| after the window closes (only if `combo_window_end` < 1) | too late: ignored, the chain ends with the attack |
| during the chain's last attack, or with a follow-up already queued | ignored |

**Input buffer.** One slot, not a queue: `PlayerCombatData.input_buffer_time` (0.15 s). Pressing again
only renews it. It exists only to catch a press made just before a window opens, and is cleared when
it is spent, when it expires, when the chain ends, on a dodge, on `reset()` and on death — so no press
ever reaches a later chain or a later scene. Fifteen presses in one frame buy one Attack 1; fifteen
inside one window buy one follow-up; mashing gives 1 → 2 → 3 → 1 … for as long as it lasts, and once
it stops at most the one attack already queued runs.

**The three attacks** are their own assets, in `resources/characters/player_attacks/`, so each is
retuned on its own and the controller never changes:

| Asset | `id` | `animation` | multiplier | windup / active / recovery | combo window | dodge cancel |
| --- | --- | --- | --- | --- | --- | --- |
| `light_attack_1.tres` | `light_attack_1` | `light_attack_01` | ×1.0 → 20 | 0.12 / 0.12 / 0.22 s | whole recovery | from 0% |
| `light_attack_2.tres` | `light_attack_2` | `light_attack_02` | ×1.25 → 25 | 0.14 / 0.14 / 0.24 s | whole recovery | from 35% |
| `light_attack_3.tres` | `light_attack_3` | `light_attack_03` | ×1.75 → 35 | 0.18 / 0.16 / 0.32 s | — (ends the chain) | from 60% |

The numbers are the M2 combo's, unchanged: the damage values are the same 20 / 25 / 35 (80 for the
chain at neutral STR, no weapon), and every duration is the same. What M11.2 changed is when a press
counts. The data is shared configuration and holds nothing of a running attack: the index, the queue,
the buffer, the timers and the hit history are all runtime state on `PlayerCombat` and the hitbox.

**Timing and frame rate.** Every attack ends on the first physics step at or past its phases, so a
chain is at most one step late per phase. Godot runs physics at a fixed 60 Hz whatever the rendering
frame rate, so a low FPS does not change it; `light_combo_test` also steps a bare controller at 30 and
144 Hz to check the chain itself.

### Attack types (M11.3)

Two chains, each a list of `AttackData` in `PlayerCombatData`, run by the same controller code:

| Type | Intent | Chain | Input action | Binding (temporary) |
| --- | --- | --- | --- | --- |
| Light | `request_light_attack()` | `light_combo`: Light 1 → 2 → 3 | `attack_light` | left mouse button |
| Heavy | `request_heavy_attack()` | `heavy_combo`: one attack, no follow-up | `attack_heavy` | right mouse button |

There is no attack-type enum: a chain is the type. `PlayerCombat` keeps the running chain by
reference (`_chain`), and every chain rule — the index, the window, the queue, the buffer — reads that
chain, so a heavy is simply a chain of one and a future charged, skill or finisher attack is another
chain in the data, not another controller. Pressing a type's button asks for its chain; `CameraRig`
turns both buttons into intents (a click while the cursor is free captures it instead), and the
player passes them on.

**The heavy attack** (`resources/characters/player_attacks/heavy_attack_1.tres`):

| `id` | `animation` | multiplier | windup / active / recovery | movement | dodge cancel |
| --- | --- | --- | --- | --- | --- |
| `heavy_attack_1` | `heavy_attack_01` | ×2.0 → 40 | 0.35 / 0.15 / 0.45 s (0.95 s) | ×0.5 | from 60% of recovery |

Against Light 1 (×1.0 → 20, 0.12 / 0.12 / 0.22 s): twice the damage, about three times the windup,
twice the recovery, and the player moves at half speed while it runs — more commitment for more
damage, not a new mechanic. It uses the same hitbox, the same damage function
(`base_damage × multiplier`, then weapon and STR), the same one-hit-per-target registry, and every
`DamageInfo` it sends carries `attack_id = heavy_attack_1`, so later systems (stagger, knockback,
crits, reactions) can tell it apart without the receiving side knowing anything about it. Its
placeholder is a 22° roll (`placeholder_attack_tilts["heavy_attack_01"]`) played over its own, slower
timeline. No charge, no stamina cost, no stagger, no knockback: those arrive with their steps.

**Light and heavy together — the policy.** One rule covers every case: *while an attack runs, only a
press of the running chain counts; a press of the other chain is ignored.*

| Pressed | During | Result |
| --- | --- | --- |
| heavy | a free player | the heavy starts |
| heavy | any light attack (windup, active, window) | ignored — it neither replaces a queued Light nor follows the chain; press it again once free |
| light | the heavy | ignored — nothing is held; the next light press, once free, is Light 1 |
| heavy | the heavy | ignored — one heavy at a time, nothing queued |
| light and heavy | the same frame, while free | the first to arrive starts its chain; the second is judged against it and ignored |

The buffer and the queue stay one slot each and only ever hold a press of the running chain, so there
is no light queue beside a heavy one and nothing can reach a later attack or a later scene. After any
attack the chain is over: the next light press is Light 1, the next heavy press is the heavy. Branches
between chains — a heavy finisher after Light 2, a light follow-up after a heavy — are deliberately
not built; they would be a window accepting another chain's press, in data and in `_request()`.

### Dodge and i-frames (M11.4)

The dodge existed since M2 and moved into `PlayerCombat` at M11.1; M11.4 makes its phases and its
invulnerability explicit, and checks it against real enemy and boss attacks.

**Input**: the `dodge` action (`Space`; temporary until key rebinding at M19). The player's
`_unhandled_input` turns it into `PlayerCombat.request_dodge()`; nothing below it reads a device.

**When**: `request_dodge()` passes one gate, `can_dodge()` — not already dodging, not dead, off
cooldown, not committed to an attack short of its dodge-cancel window, and (since M11.5) the stamina
to pay for it. Nothing else decides whether a dodge may start. A refused dodge is not held: dodges
are never buffered.

**Phases** — `PlayerCombat.DodgePhase`, inside the `DODGING` state, from `PlayerCombatData`:

```
| STARTUP | INVULNERABLE | RECOVERY |  -> IDLE, then a cooldown before the next dodge
0       0.06            0.24      0.35 s                               0.15 s
```

| Phase | Moving | Invulnerable | Attacks / another dodge |
| --- | --- | --- | --- |
| `STARTUP` (0–0.06 s) | yes | no | refused |
| `INVULNERABLE` (0.06–0.24 s) | yes | **yes** | refused |
| `RECOVERY` (0.24–0.35 s) | yes | no | refused |
| cooldown (0.15 s after) | free | no | attacks allowed; another dodge refused |

The phase is what switches the i-frames: entering `INVULNERABLE` sets them, leaving it clears them,
so the two cannot disagree (`dodge_iframes_test` checks every frame). All four numbers are
`PlayerCombatData` fields; the phase boundaries are `invulnerability_start`, `invulnerability_end`
and `dodge_duration`, and the cooldown is `dodge_cooldown`. Timing is on `delta`, like the attacks.

**Where and how fast** is the player's: the direction is fixed when the dodge starts, from the
movement keys relative to the camera — the same `_input_direction()` walking uses — and with no key
held it is a backstep, straight away from where the player faces. The body moves at
`effective_dodge_speed` (11.5 m/s, scaled by AGI) for the whole dodge, about 4 m, through
`move_and_slide()` with gravity as ever: walls, closed doors and enemies still stop it, and a dodge
off a ledge falls. Keys pressed during the dodge change nothing. The facing does not turn during a
dodge; the placeholder is a pitch of the model (`dodge_visual_tilt_degrees`, on the player).

**I-frames are the hurtbox's decision.** The dodge calls
`Hurtbox.set_invulnerable(true/false, PlayerCombat.IFRAMES_REASON)`; `Hurtbox.receive_hit()` refuses
any hit while a reason holds. The attacker never asks and never knows: an enemy's or the boss's
hitbox still connects (it emits `hit_landed`), the hurtbox simply does not pass the hit on, so health
does not change, `health_changed` is not emitted and the health HUD does not move. Because
invulnerability is kept per reason, the dodge ending its i-frames never ends another system's
invulnerability, nor can another system end them; before M11.4 it was one shared flag, and a dodge
starting or ending cleared it for everyone. There is no `ignore_iframes`: no damage in the game is
meant to pass them yet. `HealthComponent.take_damage()` called directly — not through a hurtbox — is
not a hit and does not consult it.

**Never left invulnerable**: the i-frames end with their phase, and `reset()` — which a death runs —
ends the dodge and them; a scene change frees the player, and every new hurtbox starts with no
reason set.

**Attacks and the dodge — the policies:**

| Pressed | During | Result |
| --- | --- | --- |
| dodge | windup or active of any attack | refused, not held |
| dodge | recovery of an attack, before its `dodge_cancel_recovery_fraction` | refused, not held |
| dodge | recovery of an attack, from its cancel fraction on | the attack is cancelled (hitbox shut, chain and queue dropped), the dodge starts |
| light / heavy | a dodge, any phase | ignored, not held; after it, Light 1 / the heavy start at once |
| dodge | the cooldown after a dodge | refused |

The cancel fractions are the attacks' own: Light 1 from 0% of its recovery, Light 2 from 35%,
Light 3 and the heavy from 60% — so a dodge never skips all of the heavy's recovery. There is no
cancel out of windup or active, no attack out of a dodge and no dodge buffering.

### Stamina (M11.5)

The player's first limited combat resource. It pays for the dodge, and for nothing else yet.

**One owner.** `PlayerCombat` holds the stamina left and is the only code that changes it; the
configuration is four fields of `PlayerCombatData` (`resources/characters/player_combat.tres`), next
to the dodge it pays for. No new component and no new resource: the dodge's gate and its cost are in
the same controller, which is what makes the payment atomic, and the numbers sit with the rest of the
player's combat tuning. The shared asset is never written: `PlayerCombat` copies `max_stamina` into
its own `_max_stamina` in `_ready()` and keeps `_stamina` beside it.

| Field (`PlayerCombatData`) | Value | Meaning |
| --- | --- | --- |
| `max_stamina` | 100 | the ceiling, and what every player starts with |
| `dodge_stamina_cost` | 25 | paid in full when a dodge starts — four dodges from full |
| `stamina_regen_delay` | 0.8 s | nothing comes back until this long after the last spend's action ended |
| `stamina_regen_rate` | 40 / s | then this much per second, up to the ceiling — 2.5 s from empty |

First values, chosen for the ROADMAP's "stamina gates the dodge without making ordinary combat feel
rationed": earning one dodge back takes the 0.8 s delay after the dodge and 0.63 s of regeneration.

**The API** — the one way stamina changes:

| Call | Does |
| --- | --- |
| `get_stamina()`, `get_max_stamina()` | read |
| `can_spend_stamina(amount)` | whether all of `amount` is there |
| `try_spend_stamina(amount) -> bool` | spends all of it and restarts the delay, or spends nothing and says so; never part of it |
| `restore_stamina(amount)` | gives back up to the ceiling; does not touch the delay |
| `is_regenerating_stamina()` | below the ceiling, delay over, not dodging, alive |
| `stamina_changed(current, maximum)` | emitted on a real change only |

Every change ends in one private setter that clamps into `0..max`, snaps a value within
`STAMINA_EPSILON` (0.0001) of either edge onto it — so neither a negative zero nor a sliver below
full survives float rounding — and emits only if the value moved. `can_spend_stamina()` allows the
same epsilon, so regeneration's rounding cannot refuse a dodge the bar shows as paid for.

**The dodge pays atomically.** `request_dodge()` runs `can_dodge()` — which includes the stamina —
and, in the same call, spends `dodge_stamina_cost` and starts the dodge. With less than the cost
there is no dodge at all: no `DODGING`, no i-frames, no movement, no partial dodge, and nothing spent.
A dodge refused for any other reason (dodging, cooldown, an attack not yet cancellable, dead) spends
nothing either, and since dodges are never buffered nothing is reserved: a later press checks the
stamina there is then. A paid dodge is exactly M11.4's — same phases, i-frames, distance and
collisions.

**Regeneration.** Each physics tick while no dodge runs: the delay counts down, then stamina rises by
`stamina_regen_rate × delta` until it reaches the ceiling, where it stops and signals nothing more.

- Every spend restarts the delay: there is one delay and one regeneration, never two timers.
- The delay does not run during a dodge, so it counts from the dodge's end — a dodge's own length
  never counts as waiting — and a dodge made while regenerating stops it.
- Attacks cost nothing and do not hold regeneration up: the rule is "a spend delays regeneration",
  not "being in combat does".
- A dead player does not regenerate; `reset()` leaves stamina alone — it is a resource, not an action.
- On `delta`, like everything else here: the same second of regeneration gives 40 at 30, 60 or 144 Hz.

**Exhaustion** is only this: at 0 the dodge is refused. Walking, the light combo and the heavy are
untouched — there is no exhaustion state, no slowed movement and no penalty.

**Lifecycle.** Stamina lives and dies with its player, like the combat state: every new player — a
New Game, a gate, the exit, a restart after death — starts full. It is not in `PlayerRuntimeState`,
which holds only what must outlive a scene; full stamina comes back in about three seconds anyway, so
carrying it through a gate would buy nothing. Health, which does not come back, still carries.

**What costs nothing.** The light combo, as before. The heavy attack too, on purpose: it already pays
with commitment — 0.95 s against Light 1's 0.46 s, half walking speed, no dodge until 60% into its
recovery — and a stamina cost on top would change M11.3's balance and ration ordinary attacks, which
is what the ROADMAP says stamina must not do. A cost can be added later as data if the design asks.

**Sprint** does not exist in the game — there is no sprint action or sprint speed — so there is
nothing to drain. When it arrives it spends through the same owner, per second on `delta`
(`try_spend_stamina(rate × delta)`), stops at 0, and holds regeneration while it runs, as the dodge
does.

**The HUD.** `PlayerStaminaHUD` (`scripts/ui/player_stamina_hud.gd`, `scenes/ui/player_stamina_hud.tscn`)
is a thin bar under the health bar. It hears `stamina_changed` and shows `current / maximum`; it holds
no stamina, computes no regeneration, never decides whether a dodge can be paid for, and never polls.
Because the signal carries the maximum, a future change of ceiling reaches it with no change to it.

**Later.** M16's progression, equipment or passives may raise the ceiling: `_max_stamina` is
already a per-player runtime value, and changing it would be one setter beside
`HealthComponent.set_max_health()`, emitting `stamina_changed`. Nothing of that is built.

### Hit reactions, stagger and knockback (M11.6)

A hit an enemy survives now does something to it besides the number on its bar. Three separate
things, each with its own data, none implying another:

| | What it is | Decided by | Lasts |
| --- | --- | --- | --- |
| **Hit reaction** | the visible flinch every surviving hit gets | nothing — every hit | a squash of the body, 0.17 s |
| **Stagger** | the enemy's action interrupted: its attack cut off, its AI suspended | the hit's `stagger_power` against the enemy's `stagger_resistance` | the enemy's `stagger_duration` |
| **Knockback** | the body pushed away from the attacker | the hit's `knockback_force` × the enemy's `knockback_multiplier` | until `knockback_deceleration` stops it |

**The hit carries its impact.** `DamageInfo` gained exactly three fields: `stagger_power`,
`knockback_force`, and `direction` — flat, unit length, from the attacker's position to the target's,
worked out by the `Hitbox` at the moment of impact (the way the hitbox faces if the two overlap; zero
only if even that is flat). Nothing downstream reaches back to the attacker, which may be gone by
then. The two values come from the attack: `AttackData.stagger_power` and `knockback_force`, stamped
on the player's hitbox by `PlayerCombat._open_hit_window()` beside the damage. A hitbox whose owner
sets neither — enemies, the boss, the shadow — sends 0 for both.

| Attack | Damage | `stagger_power` | `knockback_force` | On a basic enemy (resistance 25) |
| --- | --- | --- | --- | --- |
| Light 1 | 20 | 10 | 2.0 m/s | flinch, pushed ~0.07 m |
| Light 2 | 25 | 15 | 2.5 m/s | flinch, pushed ~0.1 m |
| Light 3 | 35 | 30 | 4.5 m/s | **stagger**, pushed ~0.34 m |
| Heavy | 40 | 60 | 8.0 m/s | **stagger**, pushed ~1.07 m |

So the combo's first two hits keep the enemy in reach and only flinch it; the finisher interrupts it;
the heavy interrupts it and throws it back three times as far. First values, not a balance pass.

**The target decides**, in one place, in this order — the order of operations:

```
Hitbox -> Hurtbox.receive_hit(hit)        refused here in i-frames (M11.4), otherwise:
       -> HealthComponent.take_damage(hit) damage applied
            -> health 0: died             death, and nothing else: no flinch, no stagger, no push
            -> otherwise: damaged(hit)    -> BasicMeleeEnemy._on_damaged(hit):
                                               1. flinch
                                               2. stagger, if stagger_power >= stagger_resistance
                                                  and not already staggered or immune
                                               3. knockback, if knockback_force x multiplier > 0
```

No second entry point: nobody calls `stagger()` or `knockback()` on an enemy. The rule is per hit,
not accumulated — no posture bar.

**The basic enemy** (`EnemyData`, `resources/enemies/basic_melee_enemy.tres`): `stagger_resistance`
25, `stagger_duration` 0.5 s, `stagger_immunity_time` 1.0 s, `knockback_multiplier` 1.0,
`knockback_deceleration` 30 m/s². Copied into the enemy in `_apply_stats()` like every other field;
what changes in play — the stagger left, the immunity left, the push velocity — is runtime state on
the enemy (`_stagger_timer`, `_stagger_immunity_timer`, `_knockback_velocity`), never the asset.

**Stagger** is a state, `STAGGERED`, in the enemy's own machine, ranked below `DEAD` and above
everything else. Entering it cuts the attack off at once — the hit window shut (`hitbox.deactivate()`,
which also stops the hitbox accepting a hit in the same frame), the attack phase and its timer
dropped, the telegraph undone — so a cancelled swing cannot land. While it lasts the AI decides
nothing: no turning, no pathing, no new attack. It runs out whether or not the room has the AI awake,
then hands back to `CHASE` (or `IDLE` if the room has parked the enemy), from where the AI decides
again. A new stagger cannot start during one, nor for `stagger_immunity_time` after it; damage and
knockback still land meanwhile. The immunity is there because without it heavy after heavy would keep
an enemy helpless for good (tested: back-to-back heavies stagger it at most every 1.5 s, and it is
staggered well under half the time).

**Knockback** is a velocity, `_knockback_velocity`, set by the hit — replacing any push still dying
out rather than adding to it, so a flurry never builds into a launch — and spent in `_apply_motion()`,
the one place the body moves: while it lasts it replaces whatever the AI wanted that frame, and goes
through `move_and_slide()` with gravity as ever, so walls, doors and other bodies stop it and it stays
on the ground. It dies out at `knockback_deceleration` (a heavy's lasts 0.27 s). `_drive()` skips the
navigation agent's avoidance pass while it lasts, so no RVO correction rewrites it; the AI's own speed
is zeroed when a push starts and builds up again afterwards. A push is horizontal only: no launch.
Stagger and knockback cooperate — entering a stagger zeroes the AI's speed, never the push — and are
independent: a hit can push without staggering or stagger without pushing.

**Death first.** A killing blow emits `died` and not `damaged`: the enemy dies at once, with no
flinch, no stagger and no push, and `_on_died()` clears anything still running from an earlier hit.
A room parking the enemy (`set_combat_enabled(false)`) clears them too, so a scene change or a player
death leaves nothing sliding or staggered; a new scene's enemies start clean.

**The placeholder look**: the flinch is the squash the enemy already had (now started from
`damaged`, so it no longer plays on the killing blow); a stagger also leans the body away from the
blow for as long as it lasts. Both are on the mesh, not the facing node, and M14 replaces them.

**The boss** takes damage exactly as before and keeps its tint flash on every hit, but it does not
stagger and is not pushed: it reads neither value, has no stagger state, and a hit with any power at
all neither interrupts its attack nor moves it. That is deliberate — a boss thrown about by every
heavy is no boss — and whether it gets a poise it can break is M12's boss framework.

**The shadow's** hits go through the same flow with no stagger power and no push, so they flinch what
they hit and nothing more; its AI is untouched, and its kills still pay 70/30.

**The player** is not staggered or pushed by anything yet: enemy and boss hitboxes send zero, and the
player does not listen to `damaged`. The `DamageInfo` fields are general, so when player reactions
come they are a listener, not a new pipeline.

**Debug**: `BasicMeleeEnemy.debug_log_reactions` (off by default) prints each hit's stagger power
against the resistance, whether it staggered, and the push it left.

### Damage model and critical hits (M11.7)

Every hit's damage follows one set of rules, `DamageModel` (`scripts/combat/damage_model.gd`,
static and stateless):

```
raw    = base damage x attack multiplier           DamageModel.attack_damage()      once per swing,
         then the attacker's own stats:            PlayerProgression                 when the hit
         + weapon power, x STR, rounded             .get_effective_damage()          window opens
critical = chance, rolled for this hit             DamageModel.roll_critical()       once per hit
final  = raw, or round(raw x critical multiplier)  DamageModel.final_damage()        once per hit
-- the target's mitigation goes here, when there is one: Hurtbox.receive_hit(), after the
   i-frames and before HealthComponent.take_damage(). There is none yet. --
health -= final                                    HealthComponent.take_damage()
```

The attacking side ends at `final`: `DamageInfo.amount` is the final damage and the target never
recomputes an attack multiplier or a critical. Defense and armour penetration have no formula yet and
none is invented: when they come, the target's defense is applied on the receiving side at the point
above, and whatever of the attacker it needs (a penetration value) travels in `DamageInfo` like the
M11.6 fields did.

**The player's numbers** (`PlayerCombatData`, `resources/characters/player_combat.tres`):

| | Value | Where |
| --- | --- | --- |
| Base damage | 20 | `PlayerCombatData.base_damage` — its only source; attacks hold a multiplier, never a damage |
| Critical chance | 0.1 (10%) | `PlayerCombatData.critical_chance` |
| Critical multiplier | 1.5 (150%) | `PlayerCombatData.critical_damage_multiplier` |

| Attack | Multiplier | Normal | Critical |
| --- | --- | --- | --- |
| Light 1 | 1.0 | 20 | 30 |
| Light 2 | 1.25 | 25 | 38 (37.5) |
| Light 3 | 1.75 | 35 | 53 (52.5) |
| Heavy | 2.0 | 40 | 60 |

(At STR 10 with no weapon; the weapon and STR act on the raw damage before the critical.) The
multipliers are M11.6's, so every normal hit deals exactly what it did.

**Critical chance** is a normalised float, 0.0 to 1.0, everywhere in the project (0.1 = 10%). The
field is range-limited in the editor, `PlayerCombat.get_critical_chance()` clamps it into 0..1, and
`_ready()` warns about a value outside it. At 0 nothing is ever critical and at 1 everything is,
without a random draw, so both ends are exact. The **multiplier** must not be negative (it counts as
0 if it is), and `_ready()` warns below 1.0, where a critical would hit no harder than a normal hit;
it is not forced up, in case a design ever wants that.

**One roll per hit.** The chance is read when the hit window opens and stamped on the hitbox with the
damage; the hitbox rolls once for each target it hits, so one swing through two enemies rolls twice —
one can be critical and the other not (**per target, not per swing**) — and each hit of a combo rolls
on its own: Light 1 normal, Light 2 critical, Light 3 normal is an ordinary sequence. Nothing of a
critical outlives its hit: `is_critical` lives on that hit's `DamageInfo`, never on the controller.

**The generator** is the hitbox's own `RandomNumberGenerator`, created once and seeded from the
hitbox's path, like loot drops and shadow extraction, so a run can be reproduced; there is no global
random service. `DamageModel.roll_critical()` takes the generator as an argument, as `LootTable.roll()`
does.

**Rounding.** Health is a float. A player swing's raw damage is a whole number, rounded when it is
worked out (as since M6); a critical rounds its product once, half away from zero (37.5 → 38). A
normal hit is never rounded again, so enemy, boss and shadow damage reaches its target exactly as
configured. There is no minimum damage.

**Independent of everything else.** A critical changes the damage and nothing else: stagger power and
knockback force are the attack's (M11.6), whatever the roll — a critical Light 1 still only flinches, a
critical heavy pushes exactly as far as a normal one. Hit reactions, i-frames, stamina, kill
attribution and rewards are untouched: a hit refused in the i-frames takes nothing whether or not it
was critical, and a critical killing blow is one death and one reward like any other.

**Who crits.** Only the player. The shadow, the enemies and the boss go through the same code, but
their hitboxes carry chance 0 and multiplier 1.0 (the `Hitbox` defaults), so their damage is exactly
what it was — nothing in their data or the design gives them a critical yet, and none is invented.
The model is general: giving one a chance is setting two fields on its hitbox.

**Later.** M16's derived stats (critical chance and damage from stats, equipment, buffs, skills) join
in `get_critical_chance()` / `get_critical_damage_multiplier()`, which every swing reads; no
`AttackData` changes. Per-attack critical modifiers are not built. Critical feedback — damage numbers,
a sound, a flash — reads `DamageInfo.is_critical`; there is no floating-damage system yet.

**Debug**: with `PlayerCombat.debug_log_enabled` on, each hit is logged — raw damage, base and
multiplier, critical chance, whether it was critical, final damage; when off, nothing even listens.
`BasicMeleeEnemy.debug_log_reactions` marks a critical hit too.

**Tests and randomness.** Criticals make a hit's damage random, so the suites that check exact damage
(16 of them, found by running every suite with criticals forced on) switch criticals off for their
own run; `critical_hit_test` and `m11_critical_run` test criticals at 0% and 100% — exact — and one
per-target case on a seeded generator, and `m11_critical_run` also plays a dungeon on the shipped 10%.

### Target lock (M11.8)

The player can lock onto one enemy: turn to face it, aim every attack at it, strafe around it, switch
to the next one. **`PlayerTargeting`** (`scripts/player/player_targeting.gd`), a player component
wired in `Player._wire_components()`, is the one owner of the locked target; the player's movement
and attacks read it through its API, and the indicator hears it. Its tuning is
`PlayerTargetingData` (`resources/characters/player_targeting.tres`).

**Input.** `target_lock` (`Tab`) toggles the lock; `target_switch_left` (`Z`) / `target_switch_right`
(`X`) move it. The player's `_unhandled_input` turns them into `toggle_lock()` and
`switch_target(LEFT / RIGHT)`; nothing in the targeting reads a device. Temporary bindings (M19
rebinds): the middle mouse button is the shadow's attack order.

**State.** Locked is `get_target() != null` and nothing else — no flag beside the reference. The one
signal is `target_changed(target)`, `null` when the lock ends.

**What can be locked onto.** A living `RoomCombatant` — every enemy and the boss — within
`acquisition_range` (15 m, flat) with the world (`line_of_sight_mask`, layer 1) not in the way from
the player's eyes (`eye_height` 1.2 m) to the target's anchor. Shadows, the player and anything else
are not `RoomCombatant`s and never count: the type decides, not a name or a group. No new group and no
faction system were needed.

**Finding them.** One physics query — a sphere of `acquisition_range` on the enemy-body layer
(`target_body_mask`, layer 3), filtered by type, alive, range and line of sight — run only when the
player locks on or switches (`get_search_count()` counts them). Nothing scans the tree, sorts targets
or re-evaluates candidates per frame.

**Choosing.** Lowest score wins: the degrees between the camera's forward and the target (flat) plus
`distance_weight` (3) degrees per metre. What is in front of the camera comes first, distance breaks
ties, and a target behind is chosen only when nothing is in front — so a near enemy far off to the
side loses to a further one straight ahead. No threat, level or class weighting.

**Switching** takes the nearest candidate on the asked side of the held target by *bearing* — its
angle off the camera's forward, right positive — so right and left mean what the screen shows, not an
order in a list. Nothing on that side: the lock stays (no wrapping). Candidates are filtered exactly
as for a lock: dead, out of range, out of view, non-combatants never come up.

**Holding and losing it.** While locked, only the held target is checked, once a physics tick
(`_physics_process` runs only while locked): the lock ends past `lose_range` (18 m — three more than
the reach, so a target on the edge does not flicker). It also ends, in the same call, when the target
dies (`enemy_died`) or leaves the scene (`tree_exiting`), when the player dies (`HealthComponent.died`),
and when the player presses the button again. It never jumps to another target on its own, and a
dead player locks onto nothing. A staggered
or knocked-back target stays locked — the lock follows it. Off-screen but in range, it stays held:
there is no angle limit. Line of sight is checked only when a target is chosen: a held target that
walks behind a pillar stays held.

**The target's anchor.** `RoomCombatant.target_anchor` (optional) is where a lock points: the
indicator sits there and line of sight is checked to it; without one, the body's origin. The enemy's
`TargetAnchor` is 1.1 m up, the boss's 1.5 m — the boss is a target like any other, with no
boss-specific code.

**Facing.** Unlocked, the player turns toward where it walks, as before. Locked, it turns toward the
target instead, at `rotation_speed` (12 rad/s) — progressively, never a snap, so a target that passes
behind is followed round — and only on the ground plane. Movement itself is unchanged and
camera-relative, which is what makes strafing: sideways or backwards keeps the player facing the
target. While an attack runs the facing is committed (as since M11.1); while dodging it is kept.

**Attacks.** Each attack of the combo and the heavy faces the aim when it starts, and the aim is now
the locked target (`Player._aim_direction()`), else the camera's forward. That is all a lock does to
an attack: no homing, no magnetism, no teleport. Whether the swing lands is still the hitbox's to find
out — a locked target out of reach takes nothing. Criticals, stagger and knockback are untouched.

**Switching or locking during an attack** is always accepted and moves the lock at once, but the
attack under way keeps its aim; the next attack faces the new target. Locking on mid-attack leaves the
attack exactly where it was.

**The dodge** still goes where the movement keys point, relative to the camera — never drawn toward
the target. With no key held, locked on, it goes straight away from the target (unlocked: straight
back from the facing, as in M11.4). Stamina, i-frames and cooldown are unchanged, and the lock holds.

**The camera** is unchanged: it stays under the player's control and only its forward is read, to
rank targets. There is no lock-on camera; a target can leave the screen while held.

**The indicator.** `TargetLockIndicator` (`scenes/ui/target_lock_indicator.tscn`), placed in the hub
and the dungeon like the other HUD pieces, hears `target_changed` and shows it: a red ring on the
target's anchor, turned to face the camera and drawn through whatever stands in front of it, plus the
lock's `[KEY] Action` hint bottom-left, both only while locked (CLAUDE.md §9). One ring, moved rather
than parented to each target; `_process` runs only while it is showing. PLACEHOLDER until the UI pass.
The keys in hints come from `InteractionPrompt.key_for(action)`, which reads the real InputMap —
moved there from `ActiveShadowHUD`, which now uses it too.

**Lifecycle.** The targeting lives and dies with its player: leaving the scene drops the lock without
a signal (its listeners are leaving too), and every new player starts unlocked. Nothing of a lock
survives a gate, the exit, a death or a New Game.

### Damage flow

- **Outgoing**: `PlayerCombat.calculate_damage(attack)` is the one place a player swing's raw damage
  is worked out — `DamageModel.attack_damage()`: `PlayerCombatData.base_damage` (20) × the attack's
  `damage_multiplier` (1.0 / 1.25 / 1.75 / 2.0), then `PlayerProgression.get_effective_damage()` adds
  the weapon and applies STR. Each hit's critical and final damage follow at impact (M11.7, above). It runs once per swing, when the window opens, so every target of that swing takes the same
  number. The weapon's power is added after the multiplier, exactly as before, so every M10 value is
  unchanged; whether a finisher should scale the weapon too is tuning for later in M11.
- **In transit**: the hitbox builds one `DamageInfo` per target — `amount` (the final damage),
  `source`, `attack_id`, since M11.6 `stagger_power`, `knockback_force` and `direction`, and since
  M11.7 `is_critical` — and emits it on `hit_landed`.
- **Incoming**: `Hurtbox.receive_hit(hit)` (i-frames) → `HealthComponent.take_damage(hit)`, the only
  way health goes down. It records the hit as `last_damage`, then emits `died` for a killing blow or
  `damaged(hit)` for one survived — where an enemy's reaction starts. Enemies, the boss and the
  shadow go through the same two calls: the receiving side never asks who hit it.
- **Death and reward** are unchanged: the combatant passes `last_damage_source` to
  `report_death()`, `PlayerProgression` reads `get_killer()`, the player keeps its own kills and the
  shadow takes 70% of the ones it finishes.

The enemy, the boss and the shadow still run their own attack timelines in their own scripts (where
the windup is called `startup`); they send the same `DamageInfo`, with no attack id. Their attacks
converge with M12's enemy framework.

### Multi-hit prevention

The hitbox keeps the targets it has hit since it was last activated and refuses any of them again:
**per target, not per swing**, so one swing reaches everything in the volume once. The player opens
one window per attack, so the registry is the attack instance's; `activate()` clears it for the next
swing. A target that leaves the open hitbox and comes back is still not hit twice; a target that
dies inside the window takes its one hit, and the next swing finds its hurtbox gone.

### Movement, facing and presentation

- **Movement during an attack is unchanged** — full speed. The player's movement multiplies its speed
  by `PlayerCombat.get_movement_multiplier()`, which is the current attack's `movement_multiplier`:
  1.0 on every shipped attack. A slowed, rooted or lunging attack is data from here.
- **Facing**: the player turns only while `allows_turning()` (IDLE) — toward where it walks, or,
  with a target locked, toward the target (`Player._turn_toward()`). Every attack of the chain faces
  the aim when it starts (`Player._face_aim_direction()`), and the aim is one function,
  `Player._aim_direction()`: the locked target, else the camera's forward (M11.8).
- **The hitbox no longer rolls with the placeholder.** It hangs under `VisualRoot`, which only turns
  with the facing; the model moved to `VisualRoot/Model`, and the attack and dodge tilts rotate that
  node alone. Before, the finisher's 15° roll moved its hit volume up to ~0.2 m sideways — the only
  change to a hit volume in M11.1.
- **Animation**: combat emits `attack_started(attack)`; `Player._play_attack_animation(attack)` is the
  one place an attack is shown, and it knows the attack only by `AttackData.animation`. Today that
  name picks a placeholder roll from `Player.placeholder_attack_tilts` (set in `player.tscn`:
  6° / 10° / 15° for `light_attack_01` / `02` / `03`) — the same three placeholder swings as before,
  now addressed by name. M14 plays real clips under the same names there; the attack data and the
  combat never change for a new model, skeleton or AnimationTree. Animation method tracks may later
  serve as hooks, but the timeline stays `PlayerCombat`'s.

### Death and scene change

- **The player dying mid-attack or mid-dodge**: `PlayerCombat` hears its own `died` and resets —
  attack dropped, hit window shut, dodge and i-frames ended, nothing buffered — and while dead refuses
  every intent; the dodge's movement stops with it.
  Before M11.1 a dead player could keep swinging until the dungeon reloaded.
- **A scene change mid-swing or mid-dodge** frees the whole combat with its player; `m11_combat_run`
  leaves the hub with the hit window open, and `m11_dodge_run` leaves the hub and the dungeon in the
  i-frames, and each checks that nothing survives it. `m11_stamina_run` leaves them mid-dodge with
  stamina spent: the next player is full, with one listener on `stamina_changed` (its bar).

### Debug and input actions

- `PlayerCombat.debug_log_enabled` (off by default, inspector only) prints every state change, every
  dodge-phase change, every queued follow-up, every stamina spend, a dodge refused for stamina and
  stamina reaching full, with the current attack, its place in the chain, the queued attack, the
  buffer, the dodge phase, whether the i-frames are on, and the stamina with its pending delay. The hitbox's debug mesh, visible while the window is open, is the existing placeholder.
- The input actions are `attack_light` (left mouse button), `attack_heavy` (right mouse button, M11.3),
  `dodge`, and since M11.8 `target_lock` (`Tab`), `target_switch_left` (`Z`) and `target_switch_right`
  (`X`). The heavy's and the targeting's bindings are temporary until key rebinding (M19); the middle
  mouse button, the usual lock-on key, already orders the shadow to attack.
- `PlayerTargeting.debug_log_enabled` (off by default) prints each lock, switch and release with the
  target, its distance and bearing, and how many candidates the search found.

### Left for the next M11 steps

- **Sprint**, when it exists: a drain per second through `try_spend_stamina()`, stopping at 0.
- **A changing stamina ceiling** (M16): a `set_max_stamina()` on `PlayerCombat`.
- **Dodge 2.0**: buffering an attack out of a dodge, cancelling into a dodge earlier, a perfect dodge.
- **Combo 2.0**: a follow-up cutting recovery short, windows reaching into the active phase, branches
  between chains (a heavy finisher, a light follow-up after a heavy), charged attacks, launchers and
  air combos — each a change to data and to `_request()` / `_end_attack()`, not a second system.
- **Player reactions**: the player staggered or pushed by enemy hits — a listener on its own
  `damaged`, with enemy attacks given stagger power and force.
- **Beyond single-hit stagger**: a posture / poise that builds up, a boss that can be broken (M12),
  launchers and wall slams — none of which exist.
- **Defense and mitigation**: on the receiving side, in `Hurtbox.receive_hit()` before the health
  (see *Damage model and critical hits (M11.7)*); armour penetration travels in `DamageInfo`.
- **Critical feedback**: damage numbers, sound, a flash — reading `DamageInfo.is_critical`.
- **Targeting 2.0**: soft targeting (a light aim assist with no lock), a camera that frames the
  locked target, line of sight kept while a target is held, moving the lock to the next target when
  one dies — none built; see *Target lock (M11.8)*.
- **An enemy can stall out of reach** (found at M11.4, not fixed): a `BasicMeleeEnemy` chasing a
  player who stands still can stop about 1.83 m away — its navigation counts it arrived within 0.25 m
  of its slot on the 1.6 m ring, and 1.83 m is past its 1.8 m `attack_range`, so it neither closes
  nor attacks until the player moves. Distance management is M12's; `m11_dodge_run` steps the player
  in to 1.5 m before waiting for a swing.

Still true from before M11: enemies are found by physics, not a registry; enemies acquire their
target through `Player.GROUP` (choosing between player and shadow is M12's); new runtime state goes on
its component and its tuning in a resource, never in `PlayerRuntimeState` unless it must outlive a
scene; and the session is reached through `Player.session()`.

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
