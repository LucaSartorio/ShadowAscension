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

- **`HealthComponent`** (`Node`) — tracks `current_health` / `max_health`; `take_damage(hit: DamageInfo)` is the only way health goes down, and returns whether it took the hit (M11.9). Emits `health_changed(current, maximum)` and `died`, and — for a hit that leaves it alive, never with `died` — `damaged(hit)`, which hit reactions listen to (M11.6), and records the last hit as `last_damage` (with `last_damage_source` read off it) for the owner to read. `reset_to(maximum)` sets a new maximum *and* refills, which is what an actor calls when its real maximum arrives after the component's own `_ready()`.
- **`Hitbox`** (`Area3D`) — active only during an attack's hit window via `activate()` / `deactivate()`; carries the swing's `damage`, `source`, `attack_id`, `stagger_power`, `knockback_force` and critical chance and multiplier (`use_attack(attack, base_damage)` stamps all but the critical from an `AttackData`, M12.3), sends each target one `DamageInfo` — its critical rolled for that hit, its direction worked out at impact — emits `hit_landed(target, hit)`, then `hit_accepted(target, hit)` if the target took it (M11.9), and will not hit the same target twice within one activation.
- **`DamageModel`** (`scripts/combat/damage_model.gd`, static, M11.7) — the damage rules in one place: `attack_damage(base, multiplier)`, `roll_critical(chance, rng)`, `final_damage(raw, critical, multiplier)`. Stateless; see *Damage model and critical hits (M11.7)*.
- **`Hurtbox`** (`Area3D`) — `receive_hit(hit: DamageInfo)`: the one place that decides whether a hit counts. It refuses hits while `is_invulnerable`, which holds while any *reason* set through `set_invulnerable(value, reason)` holds (the dodge's i-frames are one reason, since M11.4), and forwards the rest to the `HealthComponent` it is wired to; it returns whether the hit counted (M11.9). `get_center()` (M12.3) is the middle of its shape — where a ranged attack aims.
- **`DamageInfo`** (`RefCounted`) — one hit in transit: `amount`, `source`, `attack_id` (M11.1); `stagger_power`, `knockback_force` and the flat `direction` from attacker to target (M11.6); `is_critical` (M11.7), with `amount` already the final damage.
- **`AttackData`** (`Resource`) — one attack as data: windup / active / recovery, damage multiplier, combo and dodge-cancel windows, movement multiplier, the name of its animation (M11.1, replacing `AttackStep`; one asset per attack since M11.2), its stagger power and push (M11.6), and its hit stop and camera shake (M11.9). Since M12.2 it is the melee enemy's attack too, which reads only its timing, damage and impact fields.

An enemy's AI (M12.1) is its state machine in `BasicEnemy` (`BasicMeleeEnemy` until M12.3) plus two
components: **`EnemyTargeting`** (`scripts/enemies/enemy_targeting.gd`), the one owner of whom it
fights, and an **`EnemyAttack`** (`scripts/enemies/enemy_attack.gd`, M12.2, a base since M12.3), the one
owner of what it attacks with and of the attack under way — **`EnemyMeleeAttack`** for the melee
archetype, **`EnemyRangedAttack`** for the ranged. See *Enemy AI (M12.1)*, *Melee archetype (M12.2)*
and *Ranged archetype (M12.3)*.

- **`Projectile`** (`scripts/combat/projectile.gd`, M12.3) — a shot in flight: launched with a source, a direction and its `AttackData`, it flies straight until a hit counts, it strikes the world, or its lifetime runs out, and frees itself. Its hit is a `Hitbox` child's — the same `DamageInfo`, source filtering and one hit per target as a swing. The enemy's projectile scene is `scenes/enemies/enemy_projectile.tscn`.

The player's combat controller, **`PlayerCombat`**, is a player component (`scripts/player/`); so are its target lock, **`PlayerTargeting`** (M11.8), the one owner of which enemy the player is locked onto, and **`PlayerCombatFeedback`** (M11.9), which plays the hit stop, the camera shake (`CameraRig.shake()`) and a critical's mark for the player's hits that count. See *Combat architecture (M11)*.

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
works on the copies: `BasicEnemy`, `DungeonBoss` and `PlayerProgression` each seed their own
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
| `EnemyData` (`scripts/enemies/enemy_data.gd`) | one enemy archetype — `basic_melee_enemy.tres`, `basic_ranged_enemy.tres` (M12.3) | `xp_reward`, `max_health`, movement, perception (target groups and ALERT duration since M12.1, the line-of-sight interval since M12.3), spacing — the range model: minimum, preferred and maximum attack distance — the attack — its `attacks` (`AttackData`, M12.2), base damage, cooldown, facing cone and the telegraph's turn and facing lock — hit reactions (stagger resistance / duration / immunity, knockback multiplier and deceleration), the telegraph's look | `BasicEnemy._apply_stats()`, which hands the attack's part to `EnemyMeleeAttack.configure()` | current health or any fight state — a stagger or a push in progress included; AI state (the state, the target, the swing's phase, the cooldown and stagger left, the navigation); placement (approach angle, attack desync — set per instance in the room); loot and shadow drops, which `LootDropper` and `ShadowSource` declare |
| `BossStats` (`scripts/enemies/bosses/`) | the boss's body | `xp_reward`, `max_health`, movement, spacing, decision, phase 2, encounter beats | `DungeonBoss._apply_stats()` | its attacks (each a `BossAttack`); its display name, still on the node; phase or health state; hit-reaction tuning — the boss does not stagger or move under hits (M11.6), so it has none |
| `BossAttack` (`scripts/enemies/bosses/`) | one boss attack | damage, timings, range, multi-hit, phase-2 variants, weights, telegraph | `DungeonBoss` | cooldown remaining or any per-fight state |
| `ProgressionStats` (`scripts/player/`) | the player's progression rules | starting level and stat block, XP curve, points per level, cap, derived-stat rates | `PlayerProgression._apply_tuning()`; `PlayerProgressionData.from_stats()`, once per session | level, XP or allocated points — those are `PlayerProgressionData`, runtime state |
| `PlayerTargetingData` (`scripts/player/`, M11.8) | the player's target lock | acquisition and lose ranges, the distance weight of the pick, the facing turn speed, the body and line-of-sight masks, eye height, candidate cap | `PlayerTargeting` | which target is locked — `PlayerTargeting`'s runtime state |
| `PlayerCombatFeedbackData` (`scripts/player/`, M11.9) | how the player's hits are felt | the hit stop's time scale and ceiling, a critical's stop bonus and shake multiplier, the shake's ceilings, the critical mark's text, colour, rise, duration and cap, the accessibility scales' defaults | `PlayerCombatFeedback` | a stop or a shake in progress, or the scales in use — `PlayerCombatFeedback`'s and `CameraRig`'s runtime state |
| `PlayerCombatData` (`scripts/player/`) | the player's combat | base damage, critical chance and multiplier, the light combo and the heavy attack (chains of `AttackData`), input-buffer time, dodge duration / i-frames / cooldown / stamina cost, maximum stamina and its regeneration delay and rate | `PlayerCombat` | the combat state, timers, combo position, buffered input or the stamina left — `PlayerCombat`'s runtime state; the dodge's speed, which is movement and scales with AGI on `player.gd` |
| `AttackData` (`scripts/combat/`) | one attack; the light combo's three and the heavy are `resources/characters/player_attacks/*.tres`, the melee enemy's `resources/enemies/attacks/melee_basic_attack.tres` (M12.2), the ranged enemy's `ranged_basic_bolt.tres` (M12.3) | `id`, `animation` (a name the presentation resolves), damage multiplier, windup / active / recovery, combo window, dodge-cancel window, movement multiplier, stagger power and knockback force, hit stop and camera shake (M11.9), debug colour, a ranged attack's projectile scene, speed and lifetime (M12.3) | `PlayerCombat`; the presentation reads `animation`, `PlayerCombatFeedback` the feedback; `EnemyAttack` reads `id`, the multiplier, the three timings, the impact and the debug colour (M12.2), `EnemyRangedAttack` the projectile (M12.3) | a damage number of its own — it scales the owner's base; any per-swing state (index, queue, timers, hit history); how the attack looks |
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

The engine's own globals get the same care. **`Engine.time_scale`** has exactly one writer,
`PlayerCombatFeedback` (M11.9, the hit stop): a scene-owned player component, not an autoload, which
puts it back to 1.0 whenever it stops holding — the stop over, its player dead, the tree paused, the
node leaving the tree. Nothing else in the project writes it.

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
**49 suites and 1845 assertions**; at M11.8, **51 suites and 1896 assertions**; at the close of M11
(M11.9), **53 suites and 1963 assertions**; at M12.1, **55 suites and 2011 assertions**; at M12.2, **57 suites and 2059 assertions**; at M12.3, **59 suites and 2117 assertions**, all clean. Since M11.9 a hit stop holds the
game for a few ticks on every player hit: a suite that measures a duration the game lives measures it
in game time — each tick's delta, summed — not by counting ticks. Since M11.7 a player hit can be critical at
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
| **Typed groups** | genuinely "whoever that is" lookups, done once | an enemy's candidates are the members of its data's target groups (`Player.GROUP`), read at most once a second while it searches (M12.1); HUDs find the player once on ready; `BossHealthBar` finds `DungeonBoss.GROUP` |

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
- **No lookups per frame.** An enemy holds the target it acquires (`EnemyTargeting`, M12.1) and reads
  its groups on a one-second cadence only while it has none; the boss caches the player it acquires;
  the character sheet caches its player instead of searching on every refresh.
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

**Deliberately unchanged**, with the reason. Enemies choose their own target from their target groups
(M12.1, *Enemy AI (M12.1)*): the room could hand them the player that walked in, but an enemy that
chooses is what lets an archetype fight a shadow too — the shipped enemy's only group is the
player's. And the rule for which interactable answers [E] when two overlap lives in
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

The critical mark (M11.9) is not a HUD panel: it is a label in the world, over the target, and takes
no screen corner; see *Combat feedback (M11.9)*.

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
swings reach both. An enemy projectile's hitbox (M12.3) is on layer 32 and masks 321 — the same two
hurtboxes, plus the world, which stops it: never an enemy's hurtbox or body, so there is no friendly
fire and a shot cannot hit its own shooter, whatever it leaves from.

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
(Critical Hits & Damage Model 2.0) put the damage rules in one place and added critical hits,
M11.8 (Target Lock & Combat Targeting) let the player lock onto an enemy, and M11.9 (Combat Feedback &
M11 Closure) made the player's hits felt — hit stop, camera shake, a critical's mark — and closed M11:
see *Light attack combo (M11.2)*, *Attack types (M11.3)*, *Dodge and i-frames (M11.4)*, *Stamina
(M11.5)*, *Hit reactions, stagger and knockback (M11.6)*, *Damage model and critical hits (M11.7)*,
*Target lock (M11.8)* and *Combat feedback (M11.9)* below, and *Combat System 2.0 at the close of M11*
for the whole.

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
   |             hit_landed(target, hit) for every hit that reached a hurtbox;
   |             hit_accepted(target, hit) right after, only if it counted
   v
Health         health_changed -> health bars;  damaged(hit) -> the target's hit reaction
   |             (flinch, stagger, knockback) — only for a hit it survives;
   |           died -> the combatant's owner
                 -> RoomCombatant.report_death(last_damage_source) -> enemy_died
                 -> PlayerProgression (XP, split by the killer), room, loot, remnant, run tally

Presentation   attack_started(attack) -> Player faces the aim (the locked target, else the
                 camera's forward) and plays the placeholder
Feedback       hit_accepted -> PlayerCombatFeedback: the hit stop (Engine.time_scale), the
                 camera shake (CameraRig.shake()), a critical's mark — one per swing
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
| Hit feedback | `PlayerCombatFeedback` (`scripts/player/player_combat_feedback.gd`), `CameraRig.shake()` | damage, timing, targeting: it shows a hit that counted, and nothing reads it back |

`PlayerCombat` is wired by the player like every other component —
`Player._wire_components()` hands it the attack hitbox, the hurtbox (for i-frames), the health
component (to hear its own death) and the progression (to scale damage). It reads progression; it
owns none of it. `PlayerTargeting` and `PlayerCombatFeedback` are wired there too.

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
attack, whichever chain it belongs to. `is_attacking()`, `is_dodging()`, `has_iframes()`, `get_current_attack()`,
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
            -> otherwise: damaged(hit)    -> BasicEnemy._on_damaged(hit):
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

**Debug**: `BasicEnemy.debug_log_reactions` (off by default) prints each hit's stagger power
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
`BasicEnemy.debug_log_reactions` marks a critical hit too.

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

### Combat feedback (M11.9)

What a hit of the player's feels like: the game holds for a moment (**hit stop**), the camera is
thrown and settles (**camera shake**), and a critical leaves a mark above its target.
**`PlayerCombatFeedback`** (`scripts/player/player_combat_feedback.gd`), a player component wired in
`Player._wire_components()`, plays all three. Its rules are `PlayerCombatFeedbackData`
(`resources/characters/player_combat_feedback.tres`); each attack's own values are the *Feedback*
group of its `AttackData`. It is presentation only — nothing reads anything back from it — so damage,
criticals, stamina, stagger, knockback, the target lock and every timeline are the same with it or
without it (`combat_feedback_test` turns it off and compares).

**A hit that counted.** Feedback plays for a hit its target took, and for nothing else.
`HealthComponent.take_damage()` and `Hurtbox.receive_hit()` return whether the hit counted — false
when it was refused (i-frames), found the target dead, or carried no damage. The `Hitbox` emits
`hit_landed` for every hit that reached a hurtbox, as before, and right after it **`hit_accepted`**
only for one that counted. That is the one event the feedback hears — one common event for light,
heavy and critical hits rather than a signal per kind: the attack is combat's current one
(`PlayerCombat.get_current_attack()`, whose hit window is open) and whether it was critical is on the
hit. The attacker still decides nothing on it. A miss, a hit into i-frames, a hit on a corpse and a
target already hit by this swing (refused by the hitbox's registry before any hurtbox) are felt as
nothing.

**Hit stop.** The whole game holds: `Engine.time_scale` drops to `hit_stop_time_scale` — 0, the game
stands still — and every timeline that runs on `delta` holds with it: the player's attack and its
input buffer, the dodge and its i-frames, stamina and its delay, every enemy with its stagger and its
push, the boss, the shadow, every tween. Nothing gets ahead of anything else, and each carries on
from exactly where it was: a push resumes and goes exactly as far, a stagger lasts its 0.5 s of game
time, an attack its windup + active + recovery — only the wall clock grows. Input is not held: a
press during a stop is buffered or queued as it would have been, and the buffer does not age while
the game is held. The stop is timed in physics ticks, which keep coming at 60 a second whatever the
time scale. The tick the hit lands in still runs at full speed — its time scale was read before the
hit — so a stop of *d* seconds holds the next ⌈*d* × 60⌉ ticks.

| Attack | Hit stop | Ticks held | Shake | Settles in |
| --- | --- | --- | --- | --- |
| Light 1 | 0.025 s | 2 | 0.03 m | 0.10 s |
| Light 2 | 0.030 s | 2 | 0.045 m | 0.12 s |
| Light 3 | 0.040 s | 3 | 0.07 m | 0.16 s |
| Heavy | 0.065 s | 4 | 0.12 m | 0.22 s |
| a critical | + 0.015 s | + 1 | × 1.35 | the same |

**Light versus heavy.** The light combo builds — each hit held a little longer and shaken a little
harder, the finisher most — and the heavy is plainly the biggest hit of the set, on top of its slower
windup and its stronger placeholder roll. The damage, the stagger and the push are the attack's own
and none of this touches them.

**One stop per swing.** The first hit of a swing that counts starts the stop; another target of the
same swing can only lengthen it to its own length (a critical among them), never add to it; once the
swing's stop is over, the rest of the swing starts no other. A heavy through three enemies is one
stop of 4 ticks, not three. Every stop is clamped to `max_hit_stop_duration` (0.1 s): ten requests in
one tick are one stop.

**Time scale safety.** `PlayerCombatFeedback` is the only writer of `Engine.time_scale` in the
project, and puts it back to 1.0 when the stop runs out; when the player dies (a death is never held:
the death, the restart delay and the fade run at full speed); when the tree pauses
(`NOTIFICATION_PAUSED` — a menu never opens on a held game); and when it leaves the tree — a scene
change, a restart, a quit. It never starts a stop while the tree is paused. That is the boss's case:
its killing blow completes the dungeon, which opens the run summary, which pauses the tree — all
before the hit is reported — so the boss dies with no stop, no shake, no mark and no slow motion (and,
by design, no cinematic). `combat_feedback_test` checks at every tick that the time scale is down
exactly while a stop holds.

**Camera shake** is `CameraRig`'s (`shake(strength, duration)`, `stop_shake()`): the camera is thrown
through the `Camera3D`'s own `h_offset` / `v_offset` — two sines of unrelated frequencies
(`shake_frequency`, 19 Hz), easing out — so the picture moves and no node does. The rig's rotation,
which is what "forward" means to movement, aiming and the target lock, is never touched: a shake
cannot turn the player, bend an attack, or move a lock or its bearing. One shake at a time: one at
least as strong as what is left of the current one replaces it, a weaker one is ignored, nothing
adds up, and the feedback clamps strength (0.2 m) and duration (0.35 s). The shake runs on the clock,
not on game time, so it plays through a hit stop; a pause ends it and none starts while paused. This
is the camera's one feedback controller: there is no second camera system.

**The critical mark** — PLACEHOLDER until damage numbers exist: a critical hit pops `CRITICO!` 0.5 m
above the target's anchor, rising 0.6 m and fading over 0.5 s before it frees itself; at most
`max_critical_labels` (4) at once. The labels are the feedback node's children — a plain `Node`, so
they stay where they were put in the world — and go with the player at a scene change. With the
longer stop and the harder shake, that is all a critical adds: its damage is the model's (M11.7).

**Enemies and the boss** keep their own answer to a hit: the enemy's squash, stagger lean and push
(M11.6), the boss's white tint pulse. Nothing of theirs changed.

**Shadow feedback policy.** Only the player's own hits are felt this way. A shadow's hit — like an
enemy's or the boss's — goes through a hitbox the feedback never listens to: its target reacts as it
always has, and the clock and the camera stay still, so an army of shadows (M15) can never stutter
the game or shake the screen. If shadows are ever given feedback of their own, it goes through this
component, rate-limited — never a second system.

**Accessibility (preparation).** `camera_shake_scale` and `hit_stop_scale` (0..1, 1.0 by default)
scale every shake and every stop; 0 turns either off, and at 0 the time scale is never touched. The
defaults are in the data; the values in use are the component's (`set_camera_shake_scale()`,
`set_hit_stop_scale()`), which is where a settings screen (M19) will write. There is no settings UI.

**Cost.** Nothing runs while nothing happens: the feedback's `_physics_process` runs only while a stop
holds, the rig's `_process` only while it shakes. A hit costs a few assignments; a critical, one
`Label3D` and its tween. `m11_feedback_run` measures the whole: 120 ticks of the player, the shadow
and three enemies fighting take their 2.0 s, at about 2–3 ms of physics a tick headless.

### Damage flow

- **Outgoing**: `PlayerCombat.calculate_damage(attack)` is the one place a player swing's raw damage
  is worked out — `DamageModel.attack_damage()`: `PlayerCombatData.base_damage` (20) × the attack's
  `damage_multiplier` (1.0 / 1.25 / 1.75 / 2.0), then `PlayerProgression.get_effective_damage()` adds
  the weapon and applies STR. Each hit's critical and final damage follow at impact (M11.7, above). It runs once per swing, when the window opens, so every target of that swing takes the same
  number. The weapon's power is added after the multiplier, exactly as before, so every M10 value is
  unchanged; whether a finisher should scale the weapon too is tuning for later in M11.
- **In transit**: the hitbox builds one `DamageInfo` per target — `amount` (the final damage),
  `source`, `attack_id`, since M11.6 `stagger_power`, `knockback_force` and `direction`, and since
  M11.7 `is_critical` — and emits it on `hit_landed`, then, if it counted, on `hit_accepted` (M11.9).
- **Incoming**: `Hurtbox.receive_hit(hit)` (i-frames) → `HealthComponent.take_damage(hit)`, the only
  way health goes down. It records the hit as `last_damage`, then emits `died` for a killing blow or
  `damaged(hit)` for one survived — where an enemy's reaction starts. Both return whether the hit
  counted. Enemies, the boss and the
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
- **In a hit stop**: a death, a pause or a scene change gives the game back at full speed at once
  (*Combat feedback (M11.9)*); `m11_feedback_run` dies locked on, mid-heavy, inside a stop, and dies
  again mid-dodge, and the dungeon restarts clean both times.

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

### Combat System 2.0 at the close of M11

What exists at the close of M11, and who owns it:

| System | Owner | Tuning |
| --- | --- | --- |
| Combat state, attack timelines, chains, input buffer, hit window | `PlayerCombat` | `PlayerCombatData`, `AttackData` |
| Light combo (three hits) and heavy attack | `PlayerCombat`: two chains | `light_combo`, `heavy_combo` |
| Dodge: phases, i-frames, cooldown, cancel windows | `PlayerCombat`; the `Hurtbox` refuses hits by reason | `PlayerCombatData`, `AttackData.dodge_cancel_recovery_fraction` |
| Stamina, the dodge's cost | `PlayerCombat` → `PlayerStaminaHUD` | `PlayerCombatData` |
| Damage rules and critical hits | `DamageModel` (static), rolled per hit by the `Hitbox` | `PlayerCombatData`, `AttackData.damage_multiplier` |
| A hit | `Hitbox` → `DamageInfo` → `Hurtbox` → `HealthComponent` | — |
| Hit reactions: flinch, stagger, knockback | `BasicEnemy`; the boss only flashes | `AttackData` impact, `EnemyData` hit reactions |
| Target lock | `PlayerTargeting` → `TargetLockIndicator` | `PlayerTargetingData` |
| Hit feedback: hit stop, camera shake, critical mark | `PlayerCombatFeedback`, `CameraRig.shake()` | `PlayerCombatFeedbackData`, `AttackData` feedback |

Each is one component with one owner of its state; its tuning is a resource never written in play;
they talk by signals and by the queries of whoever owns the answer. The combat input actions are
`attack_light`, `attack_heavy`, `dodge`, `target_lock`, `target_switch_left` and
`target_switch_right`, each read in one place.

**The M11.9 audit** removed `PlayerCombat._iframes_active` — a flag kept beside the dodge phase that
always equalled `phase == INVULNERABLE`, now the query `has_iframes()` — `PlayerTargeting.get_candidates()`,
which nothing called, and the training dummy's print on every hit. It found no duplicated formula, no
second owner of any state, no older system running beside a newer one, no unused combat state and no
unread `AttackData` or `DamageInfo` field (`attack_id` names the attack in logs and tests;
`is_critical` is read by the feedback). The input buffer is cleared wherever a chain ends — the end of
a chain, a dodge, a reset, a death.

**What M12 inherits** — constraints, not a design:
- Enemy and boss attacks still run their own timelines in their scripts (`startup` / active /
  recovery) and send the same `DamageInfo`; they carry no critical chance, stagger power or push.
- The player has no hit reaction of its own: nothing listens to its `damaged`.
- Enemies acquire their target through `Player.GROUP`; nothing chooses between the player and a
  shadow. (Since M12.1: through `EnemyTargeting` and the data's target groups — still the player's
  alone; see *Enemy AI (M12.1)*.)
- An enemy can stall out of reach of a still player (below).
- Only the player's hits have feedback; any other source goes through `PlayerCombatFeedback`.

### Not built in M11

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
- **Damage numbers, hit sounds and hit VFX**: the critical mark is a placeholder; what replaces it
  hears `Hitbox.hit_accepted` and reads `DamageInfo` (M13 art, M14 animation and audio).
- **Feedback on the player being hit**, and a **settings screen** for the accessibility scales (M19).
- **Targeting 2.0**: soft targeting (a light aim assist with no lock), a camera that frames the
  locked target, line of sight kept while a target is held, moving the lock to the next target when
  one dies — none built; see *Target lock (M11.8)*.
- **An enemy could stall out of reach** (found at M11.4, fixed at M12.2): a `BasicEnemy`
  chasing a player who stood still stopped about 1.83 m away — its navigation counted it arrived
  within 0.25 m of its slot on the 1.6 m ring, and 1.83 m is past its 1.8 m `attack_range`. See
  *Enemy AI (M12.1)*, *The last stretch (M12.2)*.

Still true from before M11: enemies are found by physics, not a registry; enemies choose their target
from their data's target groups — the player's alone (M12.1; a shadow group is data); new runtime state goes on
its component and its tuning in a resource, never in `PlayerRuntimeState` unless it must outlive a
scene; and the session is reached through `Player.session()`.

## Enemy AI (M12.1)

M12.1 (Enemy AI 2.0 Foundation) rebuilt the basic enemy's AI as the base the rest of M12 extends. Its
behaviour is the one M4–M11 shipped — the same detection, chase, spacing, reposition, telegraphed
swing, cooldown, stagger, push and death, and the same numbers — reorganised so that the AI state has
one owner and one way to change, the target has one owner, and moving is separate from deciding.
Before it the AI was one `_physics_process()` that looked the player up as "the first node in the
`player` group", wrote `_state` from seven places with no exit or enter logic, kept the lose-target
timer among the AI's own, and asked the navigation server for a path five times a second whether or
not anything had moved.

```
BasicEnemy (scripts/enemies/basic_enemy.gd — BasicMeleeEnemy until M12.3; scenes/enemies/basic_*_enemy.tscn)
├── Data        EnemyData (`stats`), copied into runtime fields once in _ready()
├── AI state    `_state`, changed only by _change_state(): exit -> enter -> state_changed
├── Target      EnemyTargeting (child node): the one reference to whom it fights
├── Movement    _hold_position(), _drive() -> NavigationAgent3D avoidance -> _apply_motion():
│               the push, gravity, the one move_and_slide()
├── Combat      _can_start_attack() decides WHEN; the `Attack` child — an EnemyAttack: EnemyMeleeAttack
│               (M12.2) or EnemyRangedAttack (M12.3) — owns WHAT, and the attack under way: its
│               phase, the cooldown, the telegraph, and what ACTIVE does (a hitbox, a shot)
├── Health      HealthComponent — the AI hears damaged and died, owns none of it
└── Visual      the flinch, the stagger lean, the topple (placeholders until M14)
```

Not one script per part: at seven states and one attack a single, sectioned script reads better than
a framework. What matters is that the states say *what* to do — hold, go toward the target, swing —
and the movement and attack sections decide *how*, so a future archetype changes a section, not the
state machine.

### The state machine

`BasicEnemy.State`: `IDLE, ALERT, CHASE, REPOSITION, ATTACK, STAGGERED, DEAD`. `_state` is the
only record of it — no `is_attacking` / `is_chasing` flag beside it; `is_staggered()` and
`get_state()` read it. REPOSITION is not new: it is the chase's own manoeuvre since M5 (too close, or
in range but facing away), kept because the behaviour needs it.

| State | Enter | Update (each physics tick) | Exit |
| --- | --- | --- | --- |
| `IDLE` | lets the target go | holds still (inside avoidance); looks for a target in detection range -> `ALERT` | — |
| `ALERT` | stops; starts `alert_duration`; starts the per-instance attack desync (`initial_attack_delay`, the attack's hold-off) | holds still, turns toward the target; target lost -> `IDLE`; duration over -> `CHASE`. At 0 s — the basic enemy's — IDLE's update runs it in the same tick, so noticing costs no time | — |
| `CHASE` | asks for a path on its first tick | target lost -> `IDLE`; can swing -> `ATTACK`; too close or facing away -> `REPOSITION`; else paths to its slot beside the target, braking on the way in and holding on the ring (M12.2), turning with its movement (or to the target once there) | — |
| `REPOSITION` | starts its timeout; asks for a path | target lost -> `IDLE`; timed out -> `CHASE` (and blocks re-entry for `reposition_cooldown`); can swing -> `ATTACK`; else steps round to its slot, always facing the target | — |
| `ATTACK` | starts the swing the attack selects: TELEGRAPH | holds still; turns slowly early in the telegraph only; advances the swing; over -> `CHASE` | cuts off a swing still under way (hitbox shut, telegraph undone) |
| `STAGGERED` | starts `stagger_duration`; stops the AI's own speed | no decision, no turning, no path: the body moves only if pushed; over -> `CHASE` with a target and combat on, else `IDLE` | starts the immunity, releases the lean |
| `DEAD` | clears the reactions, lets the target go, stops the navigation (path to where it lies, out of avoidance), turns its collision off, topples | nothing: `_physics_process` returns first | never left |

Parked (`combat_enabled` off — a room not yet entered, or suspended) the enemy perceives, paths and
counts nothing: a stagger still runs its course and a push still plays out, and that is all.

**Transitions.** `_change_state(to)` is the only writer of `_state`. It runs the old state's exit,
the new one's enter, refreshes the engagement (the health bar's signal), logs when asked, and emits
`state_changed(from, to)`. It refuses — changing nothing, emitting nothing — a transition not listed
in `TRANSITIONS`, the same state again, and a fighting state (`ALERT, CHASE, REPOSITION, ATTACK`)
without a target or with combat off:

```
IDLE --target in detection range--> ALERT --alert_duration--> CHASE <--> REPOSITION
CHASE / REPOSITION --swing possible--> ATTACK --recovery over--> CHASE
ALERT / CHASE / REPOSITION / ATTACK --target lost--> IDLE
any but DEAD --a hit strong enough--> STAGGERED --over--> CHASE (target, combat on) or IDLE
any --died--> DEAD
```

So, by construction: DEAD is never left; STAGGERED cannot start a swing (it has no edge to ATTACK) and
ends only when its time does; ATTACK is never re-entered, so a swing is never restarted or doubled;
IDLE cannot jump to CHASE or ATTACK; no swing starts without a target in range (the one edge to
ATTACK is taken only when `_can_start_attack()` says so). Priority falls out of the same rules: a
death is always taken, a stagger from any living state, and nothing the AI decides runs during a
stagger.

### Targeting

**`EnemyTargeting`** (`scripts/enemies/enemy_targeting.gd`), a child node wired by the enemy in
`_ready()`, is the one owner of whom the enemy fights: `get_target()`, `has_target()`, the flat
offset and distance to it, and `target_changed(target)`. The navigation, the facing, the slot and the
swing all read the target from it; nothing keeps a copy. Untargeted is `get_target() == null`, and
nothing else.

- **Candidates** are the living members of the enemy's `target_groups` (`EnemyData`): a `Node3D` in
  the scene, not the enemy itself, carrying a `health_component` that is not dead. The groups are read
  at most once a second (`CANDIDATE_REFRESH_INTERVAL`), and only while the enemy is searching; between
  two readings the cached candidates are only measured, which allocates nothing.
- **Policy**: the nearest candidate closer than `detection_range`, flat, with no line of sight
  required — as before. The basic enemy's only group is `Player.GROUP`, so **it fights the player and
  never a shadow** (the behaviour since M4, and the finding M9 recorded). Adding the shadow's group
  (`BasicMeleeShadow.GROUP`) to an archetype's data makes shadows candidates under the same rules —
  `enemy_ai_test` does exactly that. Choosing between them by anything but distance (threat, damage
  taken) is not built.
- **Stickiness**: a target once held is kept. No candidate replaces it for being nearer; it is let go
  only when it dies (`HealthComponent.died`), leaves the scene (`tree_exiting`) — both signals, so in
  the same call — is otherwise no longer valid (checked each tick in a fighting state, cheaply), or
  stays past `lose_target_range` (14 m) for `lose_target_delay` (1 s) while chased. So an enemy never
  flickers between targets; with nothing held it goes back to IDLE, and searches again.
- **Enemies never know** whether their target is dodging, invulnerable or locking onto them: they
  swing, and the target's hurtbox decides (M11.4); the player's lock is the player's (M11.8).

### Navigation

In CHASE and REPOSITION the enemy paths to its **slot**: on the `preferred_combat_distance` ring
around the target, biased by its `combat_angle_offset_degrees` so a group does not stack. The path is
asked for on the state's first tick, then at most every `target_update_interval` (0.2 s) — and only
when the slot has moved 10 cm or more since the last request, so a target standing still costs no
query at all (`enemy_ai_test` counts one path in a second of chasing where there used to be five).
The desired velocity goes through the agent's RVO avoidance to `_apply_motion()`, the one place the
body moves; with avoidance unavailable it moves anyway after ten ticks. Turning is smooth, at
`rotation_speed` (and `telegraph_turn_fraction` of it early in the telegraph), never a snap.

**Out of sight on the ring (M12.3).** Holding on the ring assumes the target can be seen from it.
When it cannot — a wall or a pillar between them — CHASE closes in on the target itself instead of
its slot, down to `minimum_combat_distance`, until the cached line of sight says it is visible again.
For a melee on a 1.6 m ring this is an edge case; for a ranged on a 7 m ring it is what walks it round
a wall rather than waiting behind it for ever.

**The last stretch (M12.2).** The agent calls a path finished `target_desired_distance` (0.25 m) short
of its end, and from then on stops passing velocities to avoidance, whose answer is zero. Short of a
slot on the 1.6 m ring that is 1.85 m out — past the 1.8 m reach — and an enemy walking straight at a
player standing still froze there and never swung. A finished path's last stretch now moves without
the avoidance pass, and the chase brakes on the way in (`_arrival_speed()`: the speed from which the
distance left is just enough to stop at `acceleration`), so it ends on the ring instead of sliding
0.2 m past it.

**No navigation.** An enemy whose navigation map has no region — a scene with no baked
`NavigationRegion3D` — says so once, as a warning naming it, and steers straight at its slot rather
than standing still in silence. Checked once, the first time a path is needed.

### The attack

`_can_start_attack(distance)`: the attack ready (`EnemyAttack.is_ready()`: none under way, off
cooldown, past the initial desync), inside the band `minimum_combat_distance`..`attack_range` (a
melee's 1.15–1.8 m) — or nearer than the minimum while *cornered* (M12.3: a REPOSITION just timed out)
— facing the target within `max_attack_facing_angle`, and seeing it (a ray on `line_of_sight_mask`,
cached for `line_of_sight_interval`, M12.3). The attack itself — TELEGRAPH -> ACTIVE -> RECOVERY, then
the cooldown — is the archetype's: see *Melee archetype (M12.2)* and *Ranged archetype (M12.3)*. No hysteresis is needed at the edge of
the range: every swing is a full, committed lifecycle followed by a cooldown, so CHASE and ATTACK
cannot alternate tick by tick.

### Stagger and knockback (M11.6)

The AI does not reimplement them: `HealthComponent.damaged` reaches `_on_damaged()` as since M11.6 —
a flinch, a stagger if the hit's power reaches the resistance (outside a stagger and its immunity), a
push. The stagger *is* the `STAGGERED` state: entering it from ATTACK cuts the swing off through
ATTACK's exit; while in it no decision runs and the navigation is not followed; leaving it starts the
immunity. A push lives beside the state, not in it: `_apply_motion()` gives it the body for as long
as it lasts, whatever the state wanted — the avoidance pass never rewrites it — and the AI's own
movement resumes where it was when it has died out. A hit stop (M11.9) holds all of it: every clock
here runs on `delta`.

### Death

`HealthComponent.died` -> `_change_state(DEAD)` -> `report_death(last_damage_source)`. DEAD outranks
everything and is never left; its enter logic is the cleanup listed above. The reward is not the
AI's: `enemy_died` goes on to the room, the loot, the remnant and `PlayerProgression`, which pays the
player the whole of its own kills and a shadow 70% of its (30% to the player), once
(`claim_xp()`).

### EnemyData (M12.1)

Two fields, both read: `target_groups` (`[Player.GROUP]` for the basic enemy) and `alert_duration`
(0 s for the basic enemy — its behaviour before ALERT existed). Every other number is M11's,
unchanged. The runtime AI state — state, target, cooldown and stagger left, alert left, navigation —
is the enemy's; nothing of it is written to the shared asset.

### Debug

Off by default and free when off: `debug_log_ai` prints every transition, every refusal and every
change of target, with the distance; `debug_state_label` puts a label over the enemy with its state
and attack phase, its target and the distance, and whether its navigation is pathing (its `_process`
runs only then); `debug_log_reactions` (M11.6) prints each hit's reaction. `state_changed(from, to)` is
what the tests and the label read.

### The boss and the shadow

**The boss is not on this foundation.** `DungeonBoss` keeps its own AI (`INTRO / DECIDE / CHASE /
REPOSITION / ATTACK / RECOVERY / DEAD`, phases, multi-hit attacks) and still finds the player as the
first member of `Player.GROUP`; migrating it is the M12 Boss Framework's, and forcing it here would
risk the encounter for nothing. It shares everything common: the same `DamageInfo` in and out, the same
`HealthComponent` and death report, the player's lock, the hit feedback — and `m12_ai_run` fights it
through to the dungeon's completion. The shadow's AI is untouched; enemies simply do not target it.

### Extending it (M12.2 onwards)

An archetype is data first: its numbers, its target groups, its ALERT. What differs in behaviour goes
where the behaviour lives — a ranged enemy is a different attack component (what "can start", what the
swing does) and a different slot distance, not an `if enemy_type == RANGED` in the state machine;
there is no enemy type anywhere in it. The transitions table is the place a new state (a retreat, a
stun) is allowed in, with its enter, update and exit. M12.2 built the first archetype on it, the melee,
and M12.3 the second, the ranged — both on this one state machine; the rest is M12.4 onwards.

## Melee archetype (M12.2)

M12.2 (Melee Archetype 2.0) made the basic enemy's swing the first reusable enemy archetype, on the
M12.1 state machine. Its behaviour and numbers are the ones M4–M12.1 shipped — the same reach, spacing,
telegraph, damage and cooldown — with the swing moved out of the enemy script into a component that
owns it, its attack described by the same `AttackData` as the player's, and two things the swing did
not do before: its facing now **locks** just before the hit, and an enemy walking up to a player
standing still now **arrives** (see *Navigation*, *The last stretch*).

An archetype is **not a type**: there is no enum, no `if archetype == MELEE`. The melee archetype is a
composition — the state machine (`BasicEnemy`), `EnemyTargeting`, `EnemyMeleeAttack` (an
`EnemyAttack` since M12.3, which holds the lifecycle it shares with the ranged) — and the
data that tunes it: an `EnemyData` and the `AttackData` it lists. A heavier melee is a new `.tres`
pair, not code; `melee_archetype_test` builds one from data alone (a 2.2 m reach, a 0.6 s telegraph,
×2.0, a 1 s cooldown) and it behaves accordingly.

```
BasicEnemy                           WHEN: the state machine decides to swing
├── EnemyTargeting                   WHOM: the target (M12.1)
└── EnemyMeleeAttack (`Attack`)      WHAT: the attack selected, the swing under way —
        configure(EnemyData)             its phase, its clock, the cooldown, the telegraph's
        setup(enemy, targeting,          look (EnemyAttack's); the hitbox (`hitbox`, wired in
              visual, mesh)              the scene), open for ACTIVE
EnemyData ── attacks: [AttackData]   resources/enemies/basic_melee_enemy.tres
                                     resources/enemies/attacks/melee_basic_attack.tres
```

### Behaviour

- **Detection** is M12.1's: the nearest living member of `target_groups` within `detection_range`
  (10 m), kept until it dies, leaves or stays past 14 m for a second. IDLE -> ALERT -> CHASE, with a
  zero `alert_duration` in the same tick.
- **Chase and approach.** It paths to its slot on the `preferred_combat_distance` ring (1.6 m) and,
  since M12.2, brakes on the way in so it stops *on* the ring: no creeping into the target, no jitter
  on it, the target not pushed. It never swings on the way: outside `attack_range` (1.8 m) no swing can
  start.
- **In range.** Inside `minimum_combat_distance`..`attack_range` (1.15–1.8 m), facing the target within
  `max_attack_facing_angle` (25°), seeing it, and with the attack ready: CHASE -> ATTACK, and the swing
  starts. Too close, or in range but facing away: REPOSITION (M5).
- **The swing** runs its lifecycle standing still; over, CHASE; still in range, the next swing waits
  for the cooldown; the target walked off, it follows.

### Attack lifecycle

`EnemyAttack.Phase`: `NONE, TELEGRAPH, ACTIVE, RECOVERY` — the one record of the swing. The
enemy's `get_attack_phase()` reads it; nothing else keeps a phase or an "is attacking" flag.

| Phase | Lasts (`AttackData`) | The hitbox | Facing | The telegraph (placeholder) |
| --- | --- | --- | --- | --- |
| `TELEGRAPH` | `windup` — 0.35 s | shut: it cannot hit | tracks at `telegraph_turn_fraction` (30%) of `rotation_speed`, then **locked** for the last `telegraph_facing_lock` (0.1 s) | the body rears up to `startup_scale` and turns `telegraph_color` (yellow) |
| `ACTIVE` | `active` — 0.15 s | open | locked | it lunges to `active_scale`, `active_color` (red) |
| `RECOVERY` | `recovery` — 0.65 s | shut | locked | it settles back |
| then **cooldown** | `attack_cooldown` — 0.4 s, plus the instance's variation | shut | — | — |

- The phases are timed on `delta` alone, so a swing always ends and a hit stop holds it with the game
  (`melee_archetype_test` PR2: a telegraph struck by the player still lasts 0.35 s of game time).
- **Recovery is not cooldown.** Recovery is the swing's own commitment — ATTACK, standing, open to
  punishment. The cooldown is the gap after it, the attack's own clock, which runs whatever the enemy
  is doing (chasing, repositioning, staggered). With a target standing in reach the rhythm is one
  swing every 1.55 s (0.35 + 0.15 + 0.65 + 0.4), never faster.
- **No homing.** From the lock to the end of the swing the enemy does not turn. A player who steps
  aside in the last 0.1 s, or dodges through ACTIVE, is missed — the swing goes where it was aimed.
- **The desync** of a group: ALERT sets the attack's hold-off (`initial_attack_delay`, per instance
  in the room), and each swing's cooldown carries the instance's `attack_cooldown_variation`, so
  enemies that notice the player together do not swing in step.

### Telegraph

What the player reads: 0.35 s during which the enemy rears up and turns yellow, its hitbox shut, then
the red lunge. It is the whole of the warning, and it is always shown — no swing reaches ACTIVE without
a full TELEGRAPH. Everything visible is a placeholder until M14's clips: a tween on the enemy's
`VisualRoot` scale and on its own copy of the body material (duplicated in `setup()`, so enemies never
telegraph each other's swings). The clips will be timed to the phases, not the other way round.

### Hit detection

The hitbox (`VisualRoot/AttackOrigin/Hitbox`, layer 32, mask 320: the player's and the shadows'
hurtboxes) is open exactly while the phase is ACTIVE — `melee_archetype_test` checks it on every tick of
every enemy — and when it opens it takes the swing's numbers from the attack:

- damage: `DamageModel.attack_damage(attack_damage, damage_multiplier)` — 15 × 1.0 = 15;
- `attack_id`: the attack's `id`, `melee_basic_attack`;
- `stagger_power`, `knockback_force`: 0 — the player has no hit reaction (yet);
- `source`: the enemy; the direction is worked out at impact. Enemies roll no critical.

**One hit per target per swing**: the hitbox's registry, cleared by `activate()`, lets each hurtbox
take one hit per ACTIVE window however many ticks it stays inside. **Several targets per swing**: the
player and a shadow standing in the same swing are each hit once. The enemy's target decides where it
goes and whether it swings; *who is hit* is the hitbox's alone. The target's hurtbox decides whether it
counts — a dodge's i-frames refuse it (M11.4) — and the enemy never knows.

### Interruptions

| What happens | During | Result |
| --- | --- | --- |
| A hit reaching `stagger_resistance` (25) | TELEGRAPH or ACTIVE (or RECOVERY) | STAGGERED; ATTACK's exit calls `interrupt()`: the hitbox shut at once — no hit can land after — the phase NONE, the telegraph undone at once. No cooldown: the stagger is the delay |
| A weaker hit | any | a flinch; the swing goes on and lands |
| A push without a stagger | any | the push moves the body (the AI never fights it); the swing goes on from wherever it lands, standing there |
| A push with a stagger (a heavy) | any | cancelled as above, and thrown |
| Death | any | DEAD; the swing cut off the same way; nothing resumes |
| The target dies or leaves | any | IDLE, the swing cut off; no window opens against nothing |
| The target walks off | RECOVERY | the recovery plays out, then CHASE after it |

### Targeting

Unchanged from M12.1, and the swing inherits it: the basic melee's `target_groups` is `[player]`, so it
chases and swings at the player and never picks a shadow; a shadow caught in a swing aimed at the
player is still hit. An archetype listing the shadow's group (`active_shadow`) chases, telegraphs at
and hits a shadow with the same swing — `melee_archetype_test` SH2.

### Configuration

What the archetype reads, and where. Nothing here is written during play: the attack copies its part
of `EnemyData` in `configure()` (a copy of the `attacks` list; the `AttackData` in it shared,
read-only), and everything a swing is doing is the attack component's, one per enemy.

| Resource | Fields the melee reads | Shipped |
| --- | --- | --- |
| `EnemyData` | `attacks`, `attack_damage`, `attack_cooldown`, `max_attack_facing_angle`, `telegraph_turn_fraction`, `telegraph_facing_lock`, `telegraph_color`, `active_color`, `startup_scale`, `active_scale`; the spacing (`attack_range`, `preferred_combat_distance`, `minimum_combat_distance`) and the perception, as in M12.1 | 15, 0.4 s, 25°, 0.3, 0.1 s; 1.8 / 1.6 / 1.15 m |
| `AttackData` | `id`, `damage_multiplier`, `windup`, `active`, `recovery`, `stagger_power`, `knockback_force`, `debug_color` | `melee_basic_attack`: ×1.0, 0.35 / 0.15 / 0.65 s, 0, 0 |

`AttackData`'s player-only fields — the combo and dodge-cancel windows, the movement multiplier, the
hit stop and camera shake, `animation` — are not read for an enemy. Removed from `EnemyData`:
`attack_startup`, `attack_active`, `attack_recovery` (now the attack's `windup` / `active` /
`recovery`) and `attack_startup_turn_fraction` (renamed `telegraph_turn_fraction`).

`EnemyAttack.select_attack()` returns the first attack — the only one the basic melee has. It is
where choosing between several (a heavier swing, a special) will go; M12.2 chooses nothing.

### Several at once

Every swing's state is its own enemy's: three melee on the player telegraph, hit and cool down each on
its own clock, and the shared assets are never touched. Nothing coordinates them — no attack tokens, no
flanking; that is later M12 work. Eight swinging at once cost about 2 ms of physics a tick in
`melee_archetype_test` PF1, and nothing is kept per swing: one tween per phase change, nothing per
tick, no `load()` anywhere in the enemy's scripts.

### The boss

Not on the archetype. `DungeonBoss` keeps its own AI and its own `BossAttack`s; it shares the hitbox,
`DamageInfo`, `HealthComponent` and the lock, and `m12_melee_run` fights it through to the dungeon's
completion.

## Ranged archetype (M12.3)

M12.3 (Ranged Archetype 2.0) built the second archetype on the M12.1 state machine: an enemy that keeps
its distance and fires a telegraphed projectile. It is not a second AI. It is the same `BasicEnemy`
(renamed from `BasicMeleeEnemy`, which it no longer only was), the same `EnemyTargeting`, the same
states and transitions, reactions and death, with two things of its own — its attack component and its
data:

```
scenes/enemies/basic_ranged_enemy.tscn
BasicEnemy                            the state machine — the melee's, line for line
├── EnemyTargeting                    whom (M12.1)
├── EnemyRangedAttack (`Attack`)      what: TELEGRAPH -> fire -> ACTIVE (release) -> RECOVERY -> cooldown
│       projectile_spawn ────────────> VisualRoot/ProjectileSpawn (Marker3D)
└── ...                               health, hurtbox, health bar, loot — as the melee's
resources/enemies/basic_ranged_enemy.tres       its numbers: the range model, speed, cooldown...
resources/enemies/attacks/ranged_basic_bolt.tres  its attack: timings, projectile scene, speed, lifetime
scenes/enemies/enemy_projectile.tscn             the shot: a Projectile with a Hitbox
```

**Nothing in the state machine asks which archetype it is.** The shared lifecycle moved from
`EnemyMeleeAttack` into a base, `EnemyAttack` (the phases, the clock, the cooldown, the desync, the
facing rule, the telegraph's look); each archetype writes only what ACTIVE *is* — `_begin_active()`,
`_end_active()`, `_cancel()`. The melee opens its hitbox; the ranged fires. Where the two differ in
movement, the difference is data (their rings are 1.6 m and 7 m) plus two rules the state machine now
applies to everyone, which matter for the ranged: *out of sight on the ring* and *cornered* (below).
The attack component takes what it works with from the enemy in `setup(enemy, targeting, visual_root,
mesh)`, and its own parts — the melee's hitbox, the ranged's spawn point — are wired to it in the
scene, so the attack never reaches for a sibling and M13 can move them to a weapon without code. (A
first version passed the enemy itself, typed; the two scripts then referenced each other, and Godot
kept both alive at exit — `hit_reaction_test` reported the leak. Passing the parts ended the cycle.)

### Range model

The same three `EnemyData` distances as the melee, with ranged values:

| | Field | Ranged | Melee |
| --- | --- | --- | --- |
| minimum range | `minimum_combat_distance` | 4 m | 1.15 m |
| preferred range | `preferred_combat_distance` | 7 m | 1.6 m |
| maximum attack range | `attack_range` | 10 m | 1.8 m |

- **Beyond the maximum** it only closes in: no attack starts past `attack_range`.
- **Between the preferred and the maximum** it closes in to the ring, and may attack on the way.
- **Between the minimum and the preferred** it holds its ground and attacks: no approach, no backing
  away (`ranged_archetype_test` PR1: no drift over two shots).
- **Nearer than the minimum** it backs away (REPOSITION) — to its 7 m ring, not to 4 m. That is the
  hysteresis: once it turns to back off it keeps going until it has room, or can attack from where it
  is, so it does not flip between approaching and retreating on the 4 m edge.

### Movement strategy

- **Approach**: CHASE paths to its slot on the ring, braking on the way in (M12.2).
- **Hold range**: on the ring and in sight, it stands and faces the target.
- **Retreat**: REPOSITION paths to its slot on the ring — away from the target along the line from it
  to the enemy, biased by `combat_angle_offset_degrees` — through the navigation, so walls, obstacles
  and the edges of the navmesh are respected; never a teleport, never a straight line through a wall. It
  faces the target throughout, at `reposition_speed_fraction` of its speed.
- **Blocked retreat (cornered)**: when there is nowhere to go — a wall at its back, the navmesh ending,
  a player pressing faster than it can back away — the REPOSITION times out (`reposition_timeout`,
  1.5 s), and for `reposition_cooldown` (0.8 s) the enemy is *cornered*: `_can_start_attack()` accepts a
  target nearer than the minimum, and it fights from where it stands. Then it may try to back away
  again. No loop runs every frame and no retreat is retried for ever: `BR1` corners one against a wall,
  2.8 m from the player — two tries, then shots from 2.75 m, nine transitions in all. A lateral step
  aside was not built: simpler, and it cannot walk into a second wall.
- **Out of sight**: see *Out of sight on the ring* under *Enemy AI (M12.1)*: it closes in on the
  target until it can see it.

### Attack lifecycle

`EnemyRangedAttack`, on `ranged_basic_bolt.tres`:

| Phase | Lasts | What happens |
| --- | --- | --- |
| `TELEGRAPH` | `windup` — 0.6 s | no projectile exists, nothing can hit; it tracks the target at 60% of its turn speed, then its facing locks for the last 0.15 s; the body rises and turns violet (placeholder) |
| fire | the moment the telegraph ends | the shot is decided and, if clear, the projectile spawned — once |
| `ACTIVE` | `active` — 0.1 s | the release; the projectile is on its own |
| `RECOVERY` | `recovery` — 0.5 s | committed, standing |
| cooldown | `attack_cooldown` — 1.6 s | no new telegraph; the enemy moves as the range model says |

One shot every 2.8 s at most: readable, dodgeable, never a volley. With the projectile's travel (7 m at
12 m/s, 0.6 s) the player has about 1.2 s from the first sign to the hit.

**The fire moment** decides the shot, and nothing before it:
- the target must still be the valid one `EnemyTargeting` holds;
- the aim point is where the target is *now* — `EnemyTargeting.get_aim_point()`, the middle of its
  hurtbox (`Hurtbox.get_center()`: the chest, not the feet) — with no prediction;
- the direction is from the spawn point to that point, but never more than `max_attack_facing_angle`
  (20°) off the facing: a target that got round the enemy during the telegraph gets a shot along the
  edge of the cone, where it is not;
- one ray, spawn point to aim point, against the world: blocked, no shot;
- the aim point must be within the projectile's reach (speed × lifetime).
If any fails the attack is **withheld**: it ends there, with no cooldown, and the enemy is free to move
where it can shoot (`LS2`: the player slipping behind a wall mid-telegraph).

### Projectile

`Projectile` (`scripts/combat/projectile.gd`) on `scenes/enemies/enemy_projectile.tscn`: a glowing
0.22 m sphere — a placeholder, big and bright enough to see coming — and a `Hitbox` child.

- **Spawn**: instanced by the attack into the scene the enemy stands in (its parent), placed at the
  `ProjectileSpawn` marker, then `launch(source, direction, attack, base_damage)`.
- **Speed and lifetime**: the attack's — `projectile_speed` 12 m/s, `projectile_lifetime` 2.5 s — read
  at launch; nothing about speed is in the AI.
- **Flight**: straight, at constant speed, on `delta`: no homing, no gravity, no prediction. A player
  who moves after the fire is simply missed (`MV1`: 0.00° of bend).
- **Collision**: its hitbox's mask — the player's and the shadows' hurtboxes, and the world. A hurtbox
  that takes the hit ends it (`"hit"`); the world ends it (`"world"`: walls, floor, doors); the
  shooter and every other enemy are never in its mask.
- **Damage**: the hitbox's `DamageInfo` — `DamageModel.attack_damage(attack_damage, multiplier)` (12),
  `attack_id` `ranged_basic_bolt`, `source` the enemy — through `Hurtbox.receive_hit()`, the one damage
  path. The projectile never asks whether the target is dodging.
- **One hit**: the hitbox registry allows one hit per target, and a hit that counts ends the shot.
- **A refused hit** (i-frames) does not end it: the body was not there to be hit, and the shot flies on
  through it — and cannot hit it again.
- **Lifetime and cleanup**: past its lifetime it ends (`"lifetime"`); ending, it emits
  `finished(reason)` and frees itself. It lives under the scene it was fired into, so a scene change
  frees it with everything else (`m12_ranged_run` O1: a shot in the air as the player leaves — nothing
  of it in the hub). Nothing global refers to it; no pool.
- **Its runtime is its own**: position, direction, remaining life, whom it hit. The `AttackData` is only
  read. It keeps the source only as its hitbox's `source`, cleared when the source leaves the scene, so
  a shot outliving its shooter lands with no source rather than a dangling one (`DE3`).

### Line of sight

Checked where a decision needs it, never scanned:
- **to start an attack** and **to hold on the ring**: `BasicEnemy._target_in_sight()`, eye to eye, one
  ray at most every `line_of_sight_interval` (0.2 s) — for every archetype;
- **at the fire moment**: a fresh ray, spawn point to aim point.
Blocked at the start, no telegraph begins and the enemy closes in (`LS1`: it walks 5.9 m round a wall,
then shoots and hits). Blocked at the fire, the shot is withheld (above). A shot fired in an edge case
that still meets a wall ends against it (`WL1`).

### Dodge

The player's two answers, both tested: **moving** — the shot keeps its line, and a step or a dodge to
the side takes the player out of it (`DG1`, `MV1`: no contact at all); **the i-frames** — a shot that
reaches the player during a dodge's invulnerability is refused by the hurtbox, deals nothing, and flies
on (`IF1`). Either way the dodge costs its stamina, because the cost is the dodge's, not the attack's.

### Stagger, knockback, death

- **Before the fire**: a stagger or a death takes the enemy out of ATTACK; ATTACK's exit interrupts the
  attack, and the attack only fires from ATTACK's update — so no projectile. On the very tick the
  telegraph would end, the order is fixed: a hit lands before the enemy runs that tick, and the
  stagger wins (`ST2`).
- **After the fire**: the projectile is independent — a stagger or death of the enemy does not recall
  it (`ST3`, `DE2`); the kill is paid once, by the usual path.
- **Knockback**: the push moves the body as for any enemy; after the stagger the range model is
  re-evaluated from where it landed — it fires from there if in band, it does not walk back to the old
  spot (`KB1`).
- Light hits flinch it, criticals and the hit stop reach it like any enemy; the hit stop holds its
  telegraph with the game (`HS1`).

### Player and shadow targeting

M12.1's policy, unchanged: the basic ranged fights the player (`target_groups` `[player]`); an
archetype that lists the shadow's group targets a shadow the same way, and its shots hit it (`SH2`). A
shadow standing in the line of a shot at the player takes it (`SH1`): collisions decide, not the
target. Enemy projectiles do not hurt enemies (the mask), and no faction combat exists.

### Melee compatibility

Both archetypes share the state machine, the target lifecycle, health, damage reception, stagger,
knockback and death; they differ in their attack component and their numbers. The melee's behaviour is
M12.2's: every melee suite and flow passes unchanged in what it checks. The two rules added to the
shared state machine for the ranged — out of sight on the ring, cornered — only change what a melee
does in those edge cases (a melee cornered 1.15 m from the player now swings instead of standing still).
The boss keeps its own AI and `BossAttack`s. No coordinator: several ranged, or ranged and melee
together, each keep their own state, cooldown, target and projectiles (`MU1`, `MX1`).

### Where it is in the game

The shipped dungeon is unchanged — its five enemies are melee. Placing ranged enemies in rooms is
content, M18's; `m12_ranged_run` brings its own into the real dungeon instead. The ranged has no shadow
of its own to extract yet (no `ShadowSource`); its loot is the melee's table.

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
