# CLAUDE.md

Operational rules for Claude Code (claude.ai/code) when working in this repository. These rules OVERRIDE default behavior and MUST be followed.

---

## 1. Project overview

**ShadowAscension** — Action RPG 3D built with Godot 4.7.x and GDScript.

Core pillars:
- Player-driven combat with shadow/soul mechanics — **implemented** (M2, M8)
- Curated dungeon runs — **implemented** (M4); semi-procedural composition is M18
- Data-driven progression: enemies, skills, items, shadows as `Resource` assets — **implemented
  for every system that exists** (M10); a domain gets its resource when a system reads it, so skills,
  gates and dungeons get theirs with their systems (M17, M18)

**Current state: M0–M10 complete; M11 in progress (M11.1 done).** A playable vertical slice (RC1) — main menu, hub, gate, a
three-room dungeon with a two-phase boss, XP and stat allocation, loot and equipment, and the full
shadow mechanic (extraction, collection, summoning, ally AI, commands, levels) — on the architecture
M10 consolidated: one source of truth per piece of state, data-driven configuration, decoupled
scenes. The player's combat runs on its own controller (`PlayerCombat`) since M11.1. Everything
visible is a **placeholder**: definitive art production starts at M13.

Next: **M11 — Combat System 2.0**, from M11.2 (M11.1, the combat foundation, is complete). See
`shadow-ascension/docs/ROADMAP.md` for the M11–M20 plan, `shadow-ascension/docs/PROGRESS.md` for what
shipped, and `docs/ARCHITECTURE.md`, *Combat architecture (M11)*, for how combat is built today.

---

## 2. Technology stack

- **Engine:** Godot 4.7.x (stable)
- **Language:** GDScript (static typing preferred)
- **Renderer:** Forward+ (D3D12 pinned on Windows via `project.godot [rendering]`)
- **Physics:** Jolt Physics (3D)
- **Editor integration:** Godot MCP addon (`addons/godot_mcp`)
- **VCS:** Git

Do **not** introduce C# without explicit user approval. Do **not** add external addons or dependencies without approval.

---

## 3. Repository structure

Repo root:
```
CLAUDE.md
README.md
shadow-ascension/          # Godot project root
```

Godot project (`shadow-ascension/`):
```
Main.tscn                  # entry point — do not rename without user approval
project.godot
icon.svg
addons/
    godot_mcp/             # editor integration

assets/                    # raw art/audio (import source)
    audio/
    characters/
    environments/
    fx/
    materials/
    models/
    textures/

scenes/                    # .tscn files, grouped by domain
    core/                  # bootstrap, root controllers, global scene wiring
    player/
    enemies/
    world/
    dungeons/
    ui/

scripts/                   # .gd files, grouped by system
    core/                  # framework, autoloads, base classes
    player/
    combat/
    enemies/
    dungeon/
    shadow/                # shadow/soul mechanic
    ui/

resources/                 # custom Resource (.tres) data
    characters/
    enemies/
    items/
    skills/
    shadows/

docs/                      # architecture notes, design docs
tests/                     # test scenes + SceneTree flow scripts, grouped by system
```

Every new feature MUST live in the correct directory. Do not create parallel/ad-hoc folders.

---

## 4. Godot architecture rules

- **Composition over deep inheritance.** Build behavior from small nodes/components; avoid inheritance chains deeper than 2 levels except when extending engine base types.
- **No monolithic scenes.** Split large scenes into sub-scenes by responsibility. Instance, don't inline.
- **Separate data from behavior.** Data lives in `Resource` assets (`resources/`). Behavior lives in scripts (`scripts/`). Nodes glue them together in scenes (`scenes/`).
- **Custom Resources for gameplay data.** Enemies, skills, items, shadows, and similar tuning MUST be `Resource` subclasses stored under `resources/<domain>/`. No hardcoded stats in scripts once a value becomes configurable.
- **Signals for decoupling.** Cross-system communication uses signals. Do not reach across the tree with `get_node("../../..")` when a signal or bus works.
- **Gameplay never calls the UI.** The UI subscribes to gameplay signals; gameplay must work with no UI in the scene at all.
- **An owner wires its parts.** A component does not look its siblings up by name: the entity's root hands them over (`Player._wire_components()` → `setup()`), and a node created at runtime is given what it needs when it is made. Anything acting for a player acts for a specific one — the one that summoned it, or the body that walked in — never "the first player in the group". See `docs/ARCHITECTURE.md`, *Scene communication*.
- **No unnecessary globals.** Autoload (`AutoLoad`/singleton) ONLY for genuine global services (save system, event bus, audio bus, scene router). Gameplay state does not belong in autoload — with one documented exception: `PlayerRuntimeState` holds the Persistent Player State, the data that must outlive a scene change, and nothing else (`docs/ARCHITECTURE.md` §7).
- **Single responsibility.** Each system owns one clear concern. If a script mixes input + combat + audio, split it.
- **No logic duplication.** If the same rule appears twice, extract it (helper, base component, resource, or signal).

---

## 5. GDScript coding conventions

Naming:
- **Files & directories:** `snake_case` (e.g. `player_controller.gd`, `basic_melee_enemy.tres`)
- **Classes / `class_name`:** `PascalCase` (e.g. `class_name PlayerController`)
- **Variables & functions:** `snake_case`
- **Constants & enum values:** `UPPER_SNAKE_CASE`
- **Signals:** `snake_case`, past-tense or event-shaped (e.g. `health_changed`, `died`)
- **Private members:** prefix `_` (e.g. `_internal_state`)

Typing:
- Use **static typing** where reasonable: `var hp: int = 100`, `func take_damage(amount: int) -> void:`.
- Prefer typed arrays / dictionaries when element type is stable.
- Declare `class_name` for scripts meant to be referenced by type or attached to Resources.

Style:
- Tabs for indentation (Godot default).
- One class per file. Filename matches `class_name` in snake_case.
- `@export` for editor-tunable values on nodes; Resource fields for data assets.
- No magic numbers in gameplay code — extract to `const` or Resource field.

---

## 6. Scene conventions

- Scenes live in `scenes/<domain>/`. Filename `snake_case.tscn`. Root node name `PascalCase`.
- One responsibility per scene. Composed scenes reference sub-scenes by instancing.
- Scripts attached to a scene root live in `scripts/<same_domain>/` with a matching name when practical.
- `Main.tscn` is the project entry point (`application/run/main_scene`). Do not repurpose it as a gameplay scene; keep it as a bootstrap/router.
- Groups (`add_to_group`) are OK for tagging; do not use them as a replacement for typed references.

---

## 7. Resource conventions

- Custom Resources under `resources/<domain>/` as `.tres` (text) assets, not `.res` (binary), for diff-ability.
- Resource *scripts* (the `extends Resource` class definitions) live in `scripts/<domain>/` (e.g. `scripts/enemies/enemy_data.gd` defines `class_name EnemyData`, instances live in `resources/enemies/*.tres`).
- Resources hold pure data + minimal derived getters. No per-frame logic, no scene-tree access.
- **Configuration resources are never written during play.** They are shared by every entity of their kind. An entity that needs per-instance values copies them from its asset once in `_ready()` and works on the copies; those fields carry no literal values of their own, so a number exists in exactly one place — its `.tres`. See `docs/ARCHITECTURE.md` §5.
- Reuse instances via `preload`/`load` — do not duplicate data in code.

---

## 8. Signal / event conventions

- Prefer signals emitted by the owning node over polling.
- For truly global events (run started, player died, save requested), use a dedicated autoload event bus rather than reaching into arbitrary nodes.
- Connect signals in `_ready()` (or via editor) and disconnect in `_exit_tree()` when the connection outlives the emitter's parent.
- Signal names describe *what happened*, not what to do: `health_changed`, not `update_health_bar`.

---

## 9. UX and player feedback

- **Every gameplay action that requires an explicit contextual input from the player MUST have a clear on-screen prompt.** If the player has to press something, the game has to say so — no hidden verbs, no "you just have to know".
- Prompt format is `[KEY] Action`, with the key visually distinct from the label:

```
[E] Entra nel Gate
[E] Esci dal Dungeon
[E] Interagisci
[E] Raccogli
[E] Parla
```

- **Automatic actions MUST NOT ask for extra input.** Doors opening after a fight, room triggers arming on entry, and enemy aggro all happen on their own; adding a confirmation press to any of them is a regression.
- Reuse the existing `InteractionPrompt` (`scripts/ui/interaction_prompt.gd`, `scenes/ui/interaction_prompt.tscn`) rather than building a second prompt system. Raise and clear it through the `InteractionPrompt.raise()` / `InteractionPrompt.clear()` helpers so the world-label fallback rule stays in one place.
- A prompt is owned by whoever raised it: only that node may clear it. An interactable that goes dead (a spent portal, a used gate) clears its own prompt.
- Keep prompt text short and in the player's language, and keep it readable without dominating the screen.

---

## 10. Performance rules

- Avoid per-frame allocations in `_process` / `_physics_process` (no `Array`/`Dictionary` literals in hot paths — reuse).
- Cache `get_node` results in `_ready`. Do not call `get_node` every frame.
- Use `_physics_process` for physics/movement, `_process` for visuals/UI. Do not mix.
- Prefer signals over polling for state changes.
- Static typing helps the compiler — use it in hot paths.
- Profile before optimizing (Godot profiler / `print_debug` + timers). No speculative micro-optimizations.

---

## 11. Git workflow

- **Commit and push to `main` at milestone completion without asking.** This is the standing default. It applies only once the work is validated: relevant test suites green, zero parser errors, zero runtime errors, docs updated.
- Outside milestone completion, do **not** commit or push unless the user explicitly requests it. Never commit partial, unvalidated, or work-in-progress state.
- Do **not** add files to staging speculatively.
- When asked to commit: small, focused commits. Conventional-style subject preferred (`feat:`, `fix:`, `refactor:`, `docs:`, `chore:`). Subject ≤ 72 chars.
- Never force-push to `main`. Never rewrite shared history without approval.
- `.godot/`, `/android/`, and other generated dirs stay gitignored.

---

## 12. Testing and validation

- No third-party test framework. The project uses its own harnesses, and they are the runner:
  **scene suites** (`tests/<area>/<suite>.tscn`, run by passing the scene to Godot) and **flow
  scripts** (`tests/<area>/<name>_run.gd`, `extends SceneTree`, run with `--script`) for anything
  that needs real scene changes. Each prints `[PASS]` / `[FAIL]` lines and a `[SUMMARY]`. The
  invocations are in the repository README.
- Tests live under `tests/`, grouped by system, plus `tests/core/` for whole-game runs.
- **`tests/run_all.gd` runs every suite** and reports passes, failures, runtime errors and exit-time
  leaks per suite: `godot --headless --path . --script res://tests/run_all.gd`. A clean run is part of
  closing a milestone; a suite that passes but leaks or errors is not clean.
- A change that touches a system runs that system's suite **and** the end-to-end runs before it is
  called done.
- After significant changes: **launch the project** and confirm zero runtime errors and zero parser warnings before declaring the task done.

Manual validation commands (run from `shadow-ascension/`):

```powershell
# Rebuild the global class cache. Run this FIRST after any pull that adds or
# renames a script — see the note below.
godot --headless --path . --import

# Open editor
godot -e --path .

# Run project (Main.tscn)
godot --path .

# Headless smoke test (loads project, quits)
godot --headless --path . --quit
```

### After pulling: rebuild the class cache

Godot resolves every `class_name` through `.godot/global_script_class_cache.cfg`, which is
generated, gitignored, and only rebuilt when the editor scans the project. Pulling a commit that
adds a script while the editor is open leaves that cache stale, and the next run fails with:

```
Parse Error: Could not find type "<SomeClass>" in the current scope
```

This is **not** a code error, and the named class is just the first one that failed — on a stale
cache every `class_name` in the project fails the same way, so the name in the message says nothing
about where the problem is.

Close Godot, then run **from the repository root** (the project is in `shadow-ascension/`, not
there):

```powershell
Remove-Item -Recurse -Force shadow-ascension\.godot
godot --headless --path shadow-ascension --import
```

Deleting the folder first is what makes this reliable: an import on top of a stale cache can leave
the old entries in place. The folder is generated and rebuilds itself on the next launch anyway.
The same steps are in the repository README, which is where someone looks after a pull.

Do not work around this by weakening a type annotation. The cache is the problem, not the code.

Fix all errors and parser warnings before considering a task complete. Warnings that are legitimately intentional must be silenced with an explicit `@warning_ignore` and a comment explaining why.

---

## 13. Documentation rules

- `docs/` holds architecture notes, design decisions, system diagrams.
- Update `docs/` and this `CLAUDE.md` when architecture changes (new autoload, new core system, changed folder layout, changed conventions).
- Do NOT create documentation files unless the change warrants it — no speculative or per-feature READMEs.
- Comments in code: only for non-obvious *why*. Do not narrate *what* — code + names cover that.

---

## 14. Definition of Done

A task is Done only when ALL of these hold:

1. **Project launches** — `godot --path .` starts without crash.
2. **Zero runtime errors** in the Godot output.
3. **Zero GDScript parser errors**; warnings addressed or explicitly justified.
4. **Structure is coherent** — new files placed in the correct directory per §3, naming per §5.
5. **Feature is verifiable** — reproducible manual steps or a test scene exists.
6. **Documentation updated** if the change touched architecture, conventions, or the folder layout.

---

## Operational reminders (Claude)

- Use **Godot MCP** when work touches scenes, nodes, or editor configuration. Prefer MCP over hand-editing `.tscn` when the operation is expressive in MCP.
- After significant changes, **run the project** (or at minimum `--headless --quit`) to catch parser/runtime issues.
- Do **not** modify unrelated systems. No opportunistic refactors during simple features.
- Do **not** perform mass refactors while implementing a small feature — propose them separately.
- Ask before adding external dependencies (addons, plugins, third-party GDScript libs).
- Do **not** commit or push without an explicit request.
