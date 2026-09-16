# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

ShadowAscension — Godot 4.7 game project. Renderer: Forward+ (D3D12 on Windows). Physics: Jolt (3D). Currently a bare-bones project skeleton — no scenes, scripts, or assets beyond the default icon.

## Layout

- Repo root contains only `README.md` and the Godot project directory `shadow-ascension/`.
- `shadow-ascension/project.godot` is the engine config. Open the editor with this directory as the project root.
- `.godot/` is generated cache (gitignored). `/android/` export dir also gitignored.

## Common commands

Run all commands from `shadow-ascension/`.

```powershell
# Open project in editor
godot -e --path .

# Run project (main scene)
godot --path .

# Run a specific scene headless-safe
godot --path . res://path/to/Scene.tscn

# Headless mode (CI / scripting)
godot --headless --path . --quit

# Export (after configuring export presets)
godot --headless --path . --export-release "<preset-name>" <output-path>
```

No test framework, lint config, or build script configured yet. If tests are added (e.g. GUT), document the runner command here.

## Conventions

- EOL: LF for all text files (`.gitattributes`).
- Charset: UTF-8 (`.editorconfig`).
- Windows rendering driver is pinned to D3D12 — Vulkan changes go in `project.godot [rendering]`.
