# ShadowAscension

Action RPG 3D in Godot 4.7 (GDScript). The Godot project lives in `shadow-ascension/`.

## Status

**M0–M12 complete — Vertical Slice (RC1) on its production foundation: consolidated architecture, Combat System 2.0, Enemy AI 2.0 and the Boss Framework. M13 (art) in progress: M13.1 — the art direction and the Visual Bible — is complete.**

The slice runs from the main menu through a hub, a dungeon and a boss, and back, with progression,
loot, equipment and the shadow mechanic all live. Everything you can see is a **placeholder**:
definitive art production starts at M13, deliberately, once the systems that consume it stop
moving.

M10 — Core Refactor & Game Architecture, the first milestone of the Core Production Foundation
phase, is complete. **M11 — Combat System 2.0** is complete: M11.1 (the combat foundation), M11.2
(the light attack combo chain), M11.3 (the heavy attack), M11.4 (the dodge and its i-frames), M11.5
(stamina), M11.6 (hit reactions, stagger and knockback), M11.7 (critical hits and the damage model),
M11.8 (target lock) and M11.9 (combat feedback — hit stop, camera shake — and the closure of M11).
**M12 — Enemy AI 2.0 & Boss Framework** is complete: M12.1 (the enemy AI foundation — a state
machine and a target owner), M12.2 (the melee archetype — a telegraphed swing as data), M12.3 (the
ranged archetype — distance kept, a telegraphed projectile), M12.4 (the tank archetype — a heavy melee,
from data alone), M12.5 (the assassin archetype — strike, disengage, re-engage), M12.6 (the support
archetype — heals and buffs its allies, fights when idle), M12.7 (the elite framework — any
archetype made elite by a data profile), M12.8 (the boss framework — phases, attack selection and
lifecycle as data, on a boss of its own) and M12.9 (boss phase mechanics — a phase-2 special and an
enrage — and the M12 closure) are done, and with them the Core Production Foundation phase.
**M13 — Art Direction & Character Production** is in progress: M13.1 (Art Direction & Visual Bible)
decided the visual identity — dark urban fantasy, supernatural military/arcane, clean action-RPG
readability, stylized realism — and wrote it into `shadow-ascension/docs/VISUAL_BIBLE.md`, the official
visual reference every asset follows. M13.2 (the Blender → Godot asset pipeline) is next and has not
started; the roadmap runs to Alpha 1 at M20.

```
Main Menu  ->  Hub  ->  [E] Gate  ->  Dungeon  ->  Boss  ->  Run Summary  ->  [E] Exit  ->  Hub
                 ^                                                                           |
                 +-------------------------------------------------------------------------+
```

Progression is in memory only — there is no save system yet (scheduled for M19), so closing the
game starts a fresh character.

## Running the project

From `shadow-ascension/`:

```powershell
godot -e --path .                      # open the editor
godot --path .                         # run the game (starts at the main menu)
godot --headless --path . --quit       # headless smoke test
```

Controls are documented in [`docs/GAME_DESIGN.md`](shadow-ascension/docs/GAME_DESIGN.md).

## After every `git pull`: rebuild the class cache

Godot resolves every `class_name` through `shadow-ascension/.godot/global_script_class_cache.cfg`.
That folder is generated and gitignored, so a pull that adds scripts leaves it stale and the next
run fails with something like:

```
Parse Error: Could not find type "PlayerShadowCollection" in the current scope
```

**This is not a code error.** The class it names is just the first one that failed — on a stale
cache every `class_name` in the project fails the same way, so the name in the message tells you
nothing about where the problem is.

Close Godot, then run **from the repository root**:

```powershell
# Windows / PowerShell
Remove-Item -Recurse -Force shadow-ascension\.godot
godot --headless --path shadow-ascension --import
```

```bash
# Linux / macOS
rm -rf shadow-ascension/.godot
godot --headless --path shadow-ascension --import
```

Then reopen the project. Deleting the folder first is what makes this reliable: an import on top of
a stale cache can leave the old entries in place, and the folder rebuilds itself on the next launch
anyway.

The two things that go wrong most often:

- running the command from the repository root with `--path .` — the project is in
  `shadow-ascension/`, not here;
- leaving the editor open while pulling, which is what leaves the cache stale in the first place.

Never work around this by weakening a type annotation. The cache is the problem, not the code.

## Tests

Test scenes live under `shadow-ascension/tests/`, grouped by system. Scene-based suites run with:

```powershell
godot --headless --path . res://tests/<area>/<suite>.tscn
```

The end-to-end runs swap the running scene, so they are SceneTree scripts instead:

```powershell
godot --headless --path . --script res://tests/<area>/<name>_run.gd
```

Each prints `[PASS]` / `[FAIL]` lines and a `[SUMMARY]`. To run all of them, each in its own
process, with runtime errors and exit-time leaks counted alongside the failures:

```powershell
godot --headless --path . --script res://tests/run_all.gd
```

It takes about twenty minutes and exits non-zero unless every suite is clean.

## Documentation

This README is a pointer. Each document owns one thing, and information lives in exactly one of
them:

| Document | Owns |
| --- | --- |
| [`docs/ROADMAP.md`](shadow-ascension/docs/ROADMAP.md) | Milestones, development order, the macro-phases through to Alpha 1 |
| [`docs/GAME_DESIGN.md`](shadow-ascension/docs/GAME_DESIGN.md) | Gameplay loop, progression, shadows, gates, the RPG layer, controls, art direction |
| [`docs/ARCHITECTURE.md`](shadow-ascension/docs/ARCHITECTURE.md) | Systems and structure, data-driven architecture, state separation, the content pipeline, gameplay/visual separation |
| [`docs/VISUAL_BIBLE.md`](shadow-ascension/docs/VISUAL_BIBLE.md) | The official visual reference: identity, pillars, palette, materials, silhouettes, shadows, telegraphs, scale, technical-art standards, naming, licensing |
| [`docs/PROGRESS.md`](shadow-ascension/docs/PROGRESS.md) | What shipped, what was found closing it, what is next, and Future Work |
| [`CLAUDE.md`](CLAUDE.md) | Operational rules and conventions for working in this repository |
