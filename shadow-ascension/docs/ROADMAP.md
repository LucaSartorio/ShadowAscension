# ShadowAscension — Roadmap

Milestone plan for the Action RPG 3D. Each milestone is scoped, sequential, and closed by explicit exit criteria. No milestone extends the scope of the next.

**M0–M9 are complete.** The vertical slice is at RC1; see `PROGRESS.md` for the record of each milestone and for the Future Work left deliberately unstarted.

---

## M0 — Project Foundation

**Goal**
Establish a clean, scalable Godot project and the development environment needed to build the rest of the game.

**Deliverables**
- Godot 4.7.x project configured (Forward+, D3D12 on Windows, Jolt Physics)
- Git repository initialized with sensible `.gitignore`, `.gitattributes`, `.editorconfig`
- Claude Code integration working
- Godot MCP addon installed and connected
- Repository structure created (`assets/`, `scenes/`, `scripts/`, `resources/`, `docs/`, `tests/` with sub-domains)
- `CLAUDE.md` at repo root defining operational rules, conventions, and Definition of Done
- Documentation foundation under `docs/` (this roadmap + a place for future architecture notes)

**Exit criteria**
- `godot --headless --path . --quit` runs without errors or warnings
- `Main.tscn` opens as project entry point
- Directory tree matches the layout defined in `CLAUDE.md`
- `CLAUDE.md` and `docs/ROADMAP.md` present and committed-ready

---

## M1 — Player Controller

**Goal**
Deliver a playable third-person / isometric character that moves, rotates, collides, and dashes reliably.

**Deliverables**
- Player scene under `scenes/player/`
- Third-person or isometric movement (final camera style locked during this milestone)
- Camera rig (follow / orbit / isometric — one chosen and implemented)
- Character rotation aligned with movement / camera
- Collision using `CharacterBody3D` + Jolt
- Dash ability (cooldown + short i-frame window optional, tunable via Resource)

**Exit criteria**
- Player moves in all directions with no jitter or stuck states
- Camera follows without clipping through geometry in a simple test scene
- Rotation feels correct at all movement angles
- Dash triggers on input, respects cooldown, and cannot be spammed
- Zero runtime errors during a 2-minute play session

---

## M2 — Basic Combat

**Goal**
Introduce the core melee combat loop: swing, connect, damage, die.

**Deliverables**
- Basic attack (single swing)
- Combo foundation (input buffer + chain window, no full combo tree yet)
- Hitbox / hurtbox nodes with clear ownership and lifetime
- Health component (Resource-driven max HP)
- Damage pipeline (attacker → hitbox → hurtbox → health)
- Death state (player and a dummy target)

**Exit criteria**
- Attack registers on a stationary training dummy
- Combo chains within the window, resets outside the window
- Hitboxes activate only during attack frames
- Damage values match expected numbers
- Death transition plays without leaving orphan nodes or errors

---

## M3 — Enemy Foundation

**Goal**
Build a reusable enemy base capable of perceiving the player and engaging in basic combat.

**Deliverables**
- Enemy base architecture (composition-based, data-driven via `EnemyStats` Resource)
- Idle state
- Player detection (vision cone / radius, configurable)
- Chase behavior
- Basic attack
- Damage reception (reuses M2 pipeline)
- Death (drop hook stub only, no loot yet)

**Exit criteria**
- One concrete enemy variant instantiated from a Resource works end-to-end
- Transitions Idle → Detect → Chase → Attack → (Damaged) → Dead run cleanly
- Multiple enemy instances coexist without cross-talk or shared-state bugs
- Zero runtime errors during a combat encounter with 3+ enemies

---

## M4 — Dungeon Foundation

**Goal**
Deliver the "enter a Gate, clear rooms, reach the boss room" structural loop.

**Deliverables**
- Gate entry (interactable that loads a dungeon scene)
- Dungeon scene container
- Start room
- Combat rooms (populated from M3 enemies)
- Boss room (empty placeholder for M5)
- Basic room transitions (trigger volumes / doors)

**Exit criteria**
- Interacting with a Gate loads the dungeon scene
- Player traverses start → combat rooms → boss room
- Room transitions do not leak nodes, signals, or physics bodies
- Combat rooms gate progression until cleared (or an explicit debug skip flag)

---

## M5 — First Boss

**Goal**
Ship a first boss encounter that showcases telegraphed, phased combat.

**Deliverables**
- Boss architecture (extends enemy base or dedicated composition, data-driven)
- Multiple distinct attacks (≥ 3)
- Telegraphed attacks (visual / audio cue before hit frames)
- Phase system (≥ 2 phases with different move sets or intensity)
- Boss death sequence (state cleanup + event hook for loot / progression)

**Exit criteria**
- Boss executes each attack correctly with readable telegraphs
- Phase transition triggers on an HP threshold and swaps behavior
- Player can defeat the boss without engine errors
- Boss death emits an event other systems can subscribe to

---

## M6 — Player Progression

**Goal**
Introduce XP-driven character growth and stat allocation.

**Deliverables**
- XP gain from enemies and boss
- Level curve
- Stats (baseline set: HP, attack, defense, plus any progression-tied derived values)
- Stat allocation (manual point spend, driven by Resource-defined rules)
- Progression data in Resources (definitions) and in-memory runtime state (persistence comes later)

**Exit criteria**
- Killing enemies awards XP; hitting threshold levels up
- Points can be allocated to stats; stats affect combat as expected
- Level and stats update UI or debug readout in real time
- Zero errors on level-up transitions and stat mutations

---

## M7 — Loot and Equipment

**Goal**
Deliver drops, inventory, and equipped gear that modifies combat.

**Deliverables**
- Item Resources (`resources/items/`) for weapons and consumables
- Inventory system (add / remove / query)
- Equipment slots (weapon + minimum needed for the vertical slice)
- Weapon stats affect damage / range / speed
- Rarity foundation (rarity enum + hooks; no full generator yet)

**Exit criteria**
- Enemies and boss drop items defined as Resources
- Items can be picked up, appear in inventory, and be equipped
- Equipped weapon changes combat behavior measurably
- Rarity tier is visible in UI/debug and drives at least one behavior (e.g. drop weight)

---

## M8 — Shadow System

**Goal**
Introduce the signature mechanic: extract shadows from defeated enemies and summon them in combat.

**Deliverables**
- Shadow extraction interaction on enemy death
- Extraction probability (per-enemy, configurable in `EnemyStats` or a dedicated Resource)
- Shadow data Resources (`resources/shadows/`)
- Shadow collection (persistent list of owned shadows, in-memory this milestone)
- Summon action (spawn one owned shadow into the current scene)
- Shadow combat behavior (basic ally AI — target nearest hostile, attack)

**Exit criteria**
- Killing an enemy triggers an extraction check using the configured probability
- Successful extraction adds a shadow to the player's collection
- Player can summon a collected shadow; it engages enemies and dies correctly
- Shadow summon respects any configured limits and cleans up on despawn

---

## M9 — Vertical Slice

**Goal**
Assemble prior milestones into a complete, replayable minimum loop demonstrating the game's identity.

**Deliverables**
- Main menu (new run, quit)
- Basic hub scene
- Gate in the hub leading to a dungeon
- Dungeon run (rooms + enemies + boss from M4 / M3 / M5)
- XP and level-up flow active
- Loot drops and equipment application active
- Shadow extraction and summon active
- Return to hub after boss defeat (or death)

**Exit criteria**
- Fresh session: menu → hub → Gate → dungeon → boss → hub is fully traversable
- All systems (combat, progression, loot, shadows) function end-to-end without desync
- No blockers, no fatal errors during a full clear
- Slice is demoable to a first-time viewer without developer narration
