# ShadowAscension — Roadmap

Milestone plan for the Action RPG 3D. Each milestone is scoped, sequential, and closed by explicit
exit criteria. No milestone extends the scope of the next.

This file owns **what is built and in what order**. Design decisions live in `GAME_DESIGN.md`,
systems and their structure in `ARCHITECTURE.md`, and the record of what actually shipped in
`PROGRESS.md`.

---

## Macro-phases

| Phase | Milestones | What it is |
| --- | --- | --- |
| **Prototype / Core Foundation** | **M0–M9** — *complete* | Building and validating the fundamental mechanics. Closed at the vertical slice, RC1. |
| **Core Production Foundation** | M10–M12 | Technical consolidation before any definitive art is produced. |
| **Visual Production** | M13–M15 | Producing ShadowAscension's real visual identity. |
| **RPG & Content Production** | M16–M19 | Expanding the RPG systems, content, dungeons and progression to production shape. |
| **Alpha 1** | M20 | The first complete, playable end-to-end version. |

**Definitive art production starts at M13.** Everything up to and including M12 runs on
placeholders, primitives and temporary assets by design — see *Why art waits for M13* below.

**M20 is Alpha 1.** It introduces no large new systems; it consolidates.

---

## Why art waits for M13

Producing final assets before the systems that consume them are stable means producing them twice.
Until M12 closes, these are all still moving:

- combat shape and timings;
- hitbox and hurtbox geometry;
- skeleton requirements;
- animation requirements (which states exist, how they blend);
- enemy AI and its movement;
- interaction ranges;
- the architecture the models plug into.

A rig built against M9's capsule combat would be rebuilt against M11's. So placeholders stay until
the requirements stop moving, and M13 opens with an art direction decision rather than with a model.

This is enforced structurally, not by discipline: **gameplay logic and visual representation are
kept separate** (see `ARCHITECTURE.md`), so replacing a placeholder with a finished model is a
scene-level change that does not touch how anything behaves.

---

# Phase 1 — Prototype / Core Foundation (M0–M9, complete)

The record of what each of these shipped, and the bugs found closing them, is in
`PROGRESS.md`. The milestones below are kept as written.

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

---

# Phase 2 — Core Production Foundation (M10–M12)

Consolidating the prototype into something a much larger project can be built on without
rewriting it. No definitive art is produced in this phase.

---

## M10 — Core Refactor & Game Architecture

**Status: Complete** — closed by M10.5 on the M10 review (`tests/core/m10_review_run.gd`), with the
whole suite clean through `tests/run_all.gd`. No gameplay changed and no feature was added.

| Step | What it did |
| --- | --- |
| **M10.1** Core Architecture Audit & Refactor Foundation | the audit; one access path to the session; named owners for the state categories that exist; the duplicated cross-system lookups removed |
| **M10.2** Persistent State & Data Ownership | the character's progression and shadows have one source of truth each, held by the session and only viewed by the player scene; one New Game reset point |
| **M10.3** Data-Driven Foundation | `EnemyData`; no archetype number kept twice, in code or in a scene |
| **M10.4** Scene & Dependency Decoupling | gameplay never calls the UI; the player wires its own components; whatever acts for a player acts for a specific one |
| **M10.5** Core Architecture Validation & M10 Closure | the validation below, a committed test runner, and the fixes it found |

How each exit criterion stands:

- **Persistent data survives every scene change — met.** Level, XP, points, stats and shadows are
  held by reference in the session; inventory and equipment by copy. Proved across repeated
  transitions by `persistent_state_run`, `decoupling_run` and `m10_review_run` (three full cycles).
- **Each listed data resource exists — revised, deliberately.** `EnemyData`, `ItemData` and
  `ShadowData` exist and are their domain's single source; the player's is `ProgressionStats`.
  `SkillData`, `DungeonData`, `GateData` and a wider `PlayerData` were **not** created, by the rule
  M10.3 adopted: a resource is built when a system reads it, never as an empty file ahead of one.
  They arrive with their systems — `PlayerData` at M11, `SkillData` at M17, `DungeonData` and
  `GateData` at M18.
- **The state categories are distinct — met for the three that exist.** Persistent Player State,
  Run State and Dungeon State each have one owner. World State, Settings and Save Data have none
  because nothing needs them yet; Settings and Save Data are M19.
- **No behavioural regression — met.** Every M9 suite passes. Four were edited, none weakened: two
  renames, one claim restated through the new API, and three checks in `qa_run` and `m5_review_run`
  that had never tested anything now do.

**Goal**
Make the architecture solid enough to carry a far bigger project without the existing systems
having to be rewritten again and again.

**Deliverables**
- Refactor of the M0–M9 code; removal of temporary and debug-only code paths
- Reduced coupling between systems; signals and an event layer where they genuinely help
- Clear separation of responsibilities, one concern per system
- The main systems converted to a data-driven shape, with Godot `Resource` assets for anything
  configurable
- Data resources formalised: `PlayerData` / `PlayerStats`, `EnemyData`, `SkillData`, `ItemData`,
  `ShadowData`, `DungeonData`, `GateData`
- State formally separated into: **Persistent Player State**, **Run State**, **Dungeon State**,
  **World State**, **Settings**, **Save Data**

**Exit criteria**
- Persistent data — level, XP, allocated stats, inventory, equipment, shadows — can never be
  reinitialised by a scene change, and a test proves it across repeated transitions
- Each of the listed data resources exists and is the single source of truth for its domain
- The state categories above are distinct, with no system reading or writing outside its own
- No behavioural regression: the M9 suites still pass unchanged

---

## M11 — Combat System 2.0

**Status:** in progress.

| Step | State | What it did |
| --- | --- | --- |
| **M11.1** Combat Foundation 2.0 | **Complete** | the player's combat on its own controller (`PlayerCombat`): explicit state and attack timeline, input buffer, combo window, attacks as `AttackData`, a `DamageInfo` from hitbox to health, one damage calculation; the existing combo, dodge and numbers unchanged |
| **M11.2** Light Attack Combo Chain | **Complete** | Attack 1 → 2 → 3 as a real chain: a follow-up is accepted only inside the attack's combo window (or just before it, by a 0.15 s buffer) and the chain ends with any attack that did not accept one; one `AttackData` asset per attack, each naming its animation |
| **M11.3** Heavy Attack & Attack Variants | **Complete** | a heavy attack on its own input (`attack_heavy`): a one-attack chain on the same controller, ×2.0 damage, slower and more committed; light and heavy never interrupt each other's chains |
| **M11.4** Dodge & I-Frames | **Complete** | the dodge's phases made explicit (startup, invulnerable, recovery) and the i-frames driven by them; invulnerability decided by the hurtbox, per reason, so the dodge only ends its own; one `can_dodge()` gate for the stamina to come; checked against real enemy and boss attacks |
| **M11.5** Stamina & Combat Resource Management | **Complete** | stamina, the player's first limited resource: 100, owned by `PlayerCombat`, configured in `PlayerCombatData`; a dodge costs 25, paid atomically when it starts, and does not start without it; regeneration at 40/s after a 0.8 s delay restarted by every spend; a HUD bar driven by `stamina_changed`. Attacks stay free; sprint does not exist yet, so nothing drains |
| M11.6 onwards | Not started | the rest of the deliverables below |

**Goal**
Turn prototype combat into a real action-RPG combat system.

**Deliverables**
- Light attacks, combos, heavy attack
- Dodge with i-frames, stamina, sprint
- Hit reactions, stagger, knockback
- Critical hits
- Combat feedback: hit stop, camera shake, floating damage numbers
- Targeting: target lock, soft targeting, target switching, on-screen target indicators
- Damage model extended to carry, in prospect: Physical Damage, Magic Damage, Critical Damage,
  Defense, Armor Penetration, Elemental Damage, Status Effects

**Exit criteria**
- Every listed action is bound, readable and cancellable where the design says it should be
- Stamina gates sprint and dodge without making ordinary combat feel rationed
- The damage model carries each field end to end, even where only some are used yet
- Targeting never locks onto something dead, unreachable or off-screen

---

## M12 — Enemy AI 2.0 & Boss Framework

**Goal**
Build a reusable framework for enemies and bosses, rather than one hand-made enemy and one
hand-made boss.

**Deliverables**
- Enemy archetypes: Melee, Ranged, Tank, Assassin, Support, Elite
- A shared state machine: Idle, Patrol, Alert, Chase, Attack, Retreat, Stun, Dead
- Distance management, avoidance, group combat
- **Target selection between the player and the shadow** — enemies choose, rather than always
  aiming at the player (see the M9 finding in `PROGRESS.md`)
- Attack telegraphs as a first-class, configurable feature
- Enemy scaling
- A Boss Framework: multiple phases, special attacks, enrage, ultimate, death sequence, all
  configurable per boss

**Exit criteria**
- A new enemy archetype can be produced from data without new AI code
- A new boss can be configured — phases, attacks, enrage — without new boss code
- Group combat reads clearly: enemies space themselves and do not synchronise attacks unavoidably
- **Gameplay is technically stable.** This is the gate before definitive art production begins

---

# Phase 3 — Visual Production (M13–M15)

**Definitive art production starts here.** Godot stays the engine; Blender is a content-pipeline
tool. The pipeline is documented in `ARCHITECTURE.md`.

---

## M13 — Art Direction & Character Production

**Goal**
Establish the visual identity and produce the first definitive characters.

**Pipeline**

```
Concept / Reference -> 3D asset -> Blender (rig, materials, animation prep) -> GLB -> Godot
                                                                                -> gameplay, shader, VFX, lighting
```

**Sub-milestones**

| | |
| --- | --- |
| M13.1 | Definitive art direction |
| M13.2 | Blender setup and the Blender/Godot pipeline |
| M13.3 | First definitive Player |
| M13.4 | Player rig and animation integration |
| M13.5 | First definitive weapon |
| M13.6 | First definitive Enemy |
| M13.7 | Shadow visual system |
| M13.8 | Further enemies |
| M13.9 | First definitive Elite |
| M13.10 | First definitive Boss |
| M13.11 | Replacement of the main placeholders |
| M13.12 | Import optimisation, LOD, cleanup |

**Exit criteria**
- The art direction is written down and specific enough to judge a new asset against
- The Blender → GLB → Godot path is repeatable and documented
- A definitive model replaces a placeholder without any gameplay script changing
- The shadow visual system turns an existing enemy mesh into a shadow (see `GAME_DESIGN.md`)

---

## M14 — Animation, VFX, Audio & Game Feel

**Goal**
Bring the M13 assets to life.

**Deliverables**
- **Animation:** idle, walk/run, sprint, dodge, combo, heavy attack, skill, hit, stun, death,
  extraction, summon — with `AnimationTree` and blending where it helps
- **VFX:** weapon trails, hit effects, critical effects, skill effects, shadow effects, gate
  effects, boss attacks, level-up, loot rarity
- **Audio buses:** Music, Ambient, Combat, Player, Enemy, UI, Skills
- **Camera and game feel:** camera collision, combat camera, boss camera, dynamic FOV, camera
  shake, hit stop

**Exit criteria**
- Every combat state has an animation and no state pops or T-poses
- Each audio category is routed through its own bus and is independently mixable
- Game-feel effects are configurable and can be turned down without breaking readability

---

## M15 — Environment Art, Hub & World Building

**Goal**
Real environments, and a hub that no longer reads as a prototype.

**Deliverables**
- Hub areas: Hunter Association, Gate Area, Training Area, Blacksmith, Merchant, Quest NPC,
  Shadow Management, Storage
- A generic **NPC Framework**: dialogue, shop, quest, interaction, and room for future reputation
- Modular environment kits rather than monolithic levels — a dungeon kit of wall, floor, arch,
  column, door, stairs, statue and props, assembled in Godot
- The contextual prompt system from M4/M8 kept and extended: interactable things stay obviously
  interactable

**Exit criteria**
- The hub is composed from kit modules, not one baked mesh
- A second dungeon environment can be assembled from the same kit without new art
- Every interactable in the hub announces itself with a prompt in the established format

---

# Phase 4 — RPG & Content Production (M16–M19)

---

## M16 — RPG Progression System

**Goal**
Expand progression from the vertical slice's four stats into a real RPG layer.

**Deliverables**
- Primary stats: Level, XP, Strength, Agility, Vitality, Intelligence, **Perception**
- Derived stats: HP, Mana, Attack, Defense, Critical Chance, Critical Damage, Movement Speed
- Character screen
- Equipment slots: Weapon, Helmet, Chest, Gloves, Boots, Accessory 1, Accessory 2
- Rarity: Common, Uncommon, Rare, Epic, Legendary, Mythic
- Inventory: sorting, filters, equip, unequip, compare, sell, drop where allowed
- Configurable loot tables

**The RPG loop:** Combat → Loot → Upgrade → Higher Gate → Better Loot

**Exit criteria**
- Every primary stat feeds at least one derived stat, and the character screen shows both
- All seven equipment slots are wearable and their bonuses stack without duplication
- Loot tables are data; adding an item needs no code

---

## M17 — Skills & Shadow Army 2.0

**Goal**
Player skills, and shadows as an army rather than a single companion.

**Deliverables**
- Skill categories: Active, Passive, Ultimate, Shadow, Movement
- Skills carry cooldown, mana cost, cast time, range, area, damage, status effects
- A skill tree split at least into Combat, Movement and Shadow
- Shadows gain: Shadow Level, **Shadow Rank**, Shadow Stats, Shadow Skills, evolution, and
  team/formation management
- Shadow Management UI

**The XP split from M8 is unchanged and stays:** a kill the shadow finishes pays **70% to the
shadow and 30% to the player**.

**Exit criteria**
- A skill can be added as data, with no new code for cooldown, cost, range or area
- More than one shadow can be fielded and managed, and the UI makes the roster legible
- Shadow rank visibly changes both capability and appearance

---

## M18 — Gates & Dungeon System 2.0

**Goal**
Many gates and many dungeons, from data.

**Deliverables**
- **Gate ranks E, D, C, B, A, S**, driving enemies, elites, boss, XP, loot, dungeon complexity
  and events
- Dungeon environments: Cave, Ruins, Forest, Temple, Crypt, City/Urban, and room for more
- Room types: Entrance, Combat, Elite, Treasure, Event, Rest, Secret, Boss
- Composition: **handcrafted rooms assembled semi-procedurally** — not fully procedural generation
- Events: ambush, elite spawn, cursed chest, secret room, mini boss, challenge, shadow candidate
- **Red Gate** as a rare, high-difficulty event

**Exit criteria**
- A new gate configuration is data, not a new scene
- Two runs of the same gate rank differ in composition while staying hand-authored in the small
- Rank demonstrably changes difficulty and reward together

---

## M19 — Quest, Save, Settings & Production Systems

**Goal**
The systems a shippable build needs and a prototype does not.

**Deliverables**
- Quest types: Main, Side, Daily, Dungeon, Hunter, Shadow
- Configurable objectives: Kill, Collect, Reach, Interact, Complete Dungeon, Defeat Boss
- A story/dialogue framework independent of gameplay logic
- **The definitive save system**, storing level, XP, stats, inventory, equipment, skills, shadows,
  quests, gate progression and settings — with autosave, manual save, backup and save versioning
- Settings: resolution, fullscreen, graphics, FPS limit, audio, mouse sensitivity, controls and
  key rebinding
- Profiling of CPU, GPU, physics, AI, navigation, memory and draw calls, with particular attention
  to **many shadows active at once**

**Exit criteria**
- A save written by an older version loads, or is migrated, rather than failing
- Every setting persists and takes effect without a restart where technically possible
- A stress test with a full shadow army holds frame time within budget

---

# Phase 5 — Alpha 1 (M20)

---

## M20 — Alpha 1

**Goal**
Consolidate everything into the first complete, playable version. **No large new systems.**

**The Alpha loop**

```
New Game -> Tutorial -> Hub -> Quest -> Gate -> Dungeon -> Combat -> Loot -> Boss
         -> Shadow Extraction -> Return to Hub -> Equipment / Skills -> Shadow Upgrade
         -> Higher Rank Gate
```

**Indicative content target**
- 1 complete hub
- 3 dungeon environments
- 5–7 gate configurations
- 8–12 enemy types
- 3–4 elites
- 3 bosses
- 20–30 items
- 8–12 player skills
- several recruitable shadows
- an introductory main quest and some side quests

**Work included**
Balancing, QA, bug fixing, save/load testing, long-run testing, performance, progression tuning,
dungeon replay, inventory edge cases, and a shadow-army stress test.

**Target version:** ShadowAscension — Alpha 0.1.0

**Exit criteria**
- The Alpha loop above is traversable start to finish without developer intervention
- The content targets are met, or the shortfall is deliberate and recorded
- No progression loss, no save corruption and no soft-locks across a long session
