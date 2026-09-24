# ShadowAscension

Action RPG 3D in Godot 4.7 (GDScript). The Godot project lives in `shadow-ascension/`.

## Status

**M0–M10 complete, M11 in progress — Vertical Slice (RC1) on a consolidated architecture.**

The slice runs from the main menu through a hub, a dungeon and a boss, and back, with progression,
loot, equipment and the shadow mechanic all live. Everything you can see is a **placeholder**:
definitive art production starts at M13, deliberately, once the systems that consume it stop
moving.

M10 — Core Refactor & Game Architecture, the first milestone of the Core Production Foundation
phase, is complete. **M11 — Combat System 2.0** is in progress: M11.1 (the combat foundation), M11.2
(the light attack combo chain), M11.3 (the heavy attack), M11.4 (the dodge and its i-frames), M11.5
(stamina) and M11.6 (hit reactions, stagger and knockback) are done; the phase runs to Alpha 1 at
M20.

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
| [`docs/PROGRESS.md`](shadow-ascension/docs/PROGRESS.md) | What shipped, what was found closing it, what is next, and Future Work |
| [`CLAUDE.md`](CLAUDE.md) | Operational rules and conventions for working in this repository |
