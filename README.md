# ShadowAscension

Action RPG 3D in Godot 4.7 (GDScript). The Godot project lives in `shadow-ascension/`.

**Status: Vertical Slice — RC1.** The M0–M9 roadmap is complete: the slice runs from the main menu
through a hub, a dungeon and a boss, and back, with progression, loot, equipment and the shadow
mechanic all live. There is no versioning convention in the project and no export preset; "RC1"
here is a statement about scope, not a build artifact.

## The loop

```
Main Menu  ->  Hub  ->  [E] Gate  ->  Dungeon  ->  Boss  ->  Run Summary  ->  [E] Exit  ->  Hub
                 ^                                                                           |
                 +-------------------------------------------------------------------------+
```

The dungeon is Start → Combat Room 1 → Combat Room 2 → Boss Room. Doors open as rooms clear.
Enemies drop loot and leave **remnants** you can try to extract a shadow from; the shadow you
collect can be summoned, commanded and levelled. Dying restarts the dungeon and costs the run —
never the character.

## Controls

| Action | Binding |
| --- | --- |
| Move | `W` `A` `S` `D` |
| Camera | mouse |
| Light attack (3-hit combo) | left mouse button |
| Dodge (i-frames) | `Space` |
| Interact — gate, exit, loot, remnant | `E` |
| Character sheet | `C` |
| Inventory and equipment | `I` |
| Shadow collection | `O` |
| Shadow: come back to me | `Q` |
| Shadow: FOLLOW / AGGRESSIVE | `T` |
| Shadow: attack what I am aiming at | middle mouse button |
| Close a menu / release the cursor | `Esc` |

The shadow bindings only do anything while a shadow is summoned, and the on-screen hints appear
with it.

## Systems

Player movement and a camera-relative third-person camera · a three-hit light combo with a dodge
that cancels late recovery and grants i-frames · enemies that perceive, space themselves and
telegraph · a three-room dungeon with a four-pattern, two-phase boss · XP, levels and five
allocatable stat points per level (STR/AGI/VIT/INT) · loot with rarities, an inventory and two
equipment slots · shadow extraction, a collection, summoning, ally AI, shadow levels and a 70/30
kill split · a run summary · everything above surviving scene changes and a death for the length
of a session.

Progression is in memory only: there is no save system, so closing the game starts a fresh
character.

## Running the project

From `shadow-ascension/`:

```powershell
godot -e --path .                      # open the editor
godot --path .                         # run the game (starts at the main menu)
godot --headless --path . --quit       # headless smoke test
```

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

Each prints `[PASS]` / `[FAIL]` lines and a `[SUMMARY]`.

## Documentation

- `CLAUDE.md` — operational rules for working in this repository
- `shadow-ascension/docs/GAME_DESIGN.md` — confirmed design decisions
- `shadow-ascension/docs/ARCHITECTURE.md` — systems and how they fit together
- `shadow-ascension/docs/ROADMAP.md` — milestones and their exit criteria
- `shadow-ascension/docs/PROGRESS.md` — what is done, in progress and next
