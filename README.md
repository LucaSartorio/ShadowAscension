# ShadowAscension

Action RPG 3D in Godot 4.7 (GDScript). The Godot project lives in `shadow-ascension/`.

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

## Running the project

From `shadow-ascension/`:

```powershell
godot -e --path .                      # open the editor
godot --path .                         # run Main.tscn
godot --headless --path . --quit       # headless smoke test
```

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
