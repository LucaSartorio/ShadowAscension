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

**Status: Complete** — closed by M11.9 (Combat Feedback & M11 Closure), with the M11 stress run
(`tests/core/m11_feedback_run.gd`): two whole Hub → Gate → Dungeon → Boss → Hub cycles, deaths
inside a hit stop and a dodge, a menu opened mid-stop, a kill raced with the shadow.

| Step | State | What it did |
| --- | --- | --- |
| **M11.1** Combat Foundation 2.0 | **Complete** | the player's combat on its own controller (`PlayerCombat`): explicit state and attack timeline, input buffer, combo window, attacks as `AttackData`, a `DamageInfo` from hitbox to health, one damage calculation; the existing combo, dodge and numbers unchanged |
| **M11.2** Light Attack Combo Chain | **Complete** | Attack 1 → 2 → 3 as a real chain: a follow-up is accepted only inside the attack's combo window (or just before it, by a 0.15 s buffer) and the chain ends with any attack that did not accept one; one `AttackData` asset per attack, each naming its animation |
| **M11.3** Heavy Attack & Attack Variants | **Complete** | a heavy attack on its own input (`attack_heavy`): a one-attack chain on the same controller, ×2.0 damage, slower and more committed; light and heavy never interrupt each other's chains |
| **M11.4** Dodge & I-Frames | **Complete** | the dodge's phases made explicit (startup, invulnerable, recovery) and the i-frames driven by them; invulnerability decided by the hurtbox, per reason, so the dodge only ends its own; one `can_dodge()` gate for the stamina to come; checked against real enemy and boss attacks |
| **M11.5** Stamina & Combat Resource Management | **Complete** | stamina, the player's first limited resource: 100, owned by `PlayerCombat`, configured in `PlayerCombatData`; a dodge costs 25, paid atomically when it starts, and does not start without it; regeneration at 40/s after a 0.8 s delay restarted by every spend; a HUD bar driven by `stamina_changed`. Attacks stay free; sprint does not exist yet, so nothing drains |
| **M11.6** Hit Reactions, Stagger & Knockback | **Complete** | enemies answer the hits they survive: a flinch on every one; a stagger — attack cut off, AI suspended for 0.5 s, then 1 s immune — when the hit's `stagger_power` reaches the enemy's resistance; a knockback away from the attacker through the physics body. Values per attack in `AttackData` (Light 1/2/3/heavy: stagger 10/15/30/60, push 2/2.5/4.5/8 m/s), per enemy in `EnemyData`. Death first; the boss is neither staggered nor pushed; the shadow's hits only flinch |
| **M11.7** Critical Hits & Damage Model 2.0 | **Complete** | the damage rules in one place (`DamageModel`): raw = base 20 × the attack's multiplier (1.0 / 1.25 / 1.75 / 2.0), then weapon and STR; a critical rolled once per hit — per target — at 10% for ×1.5, rounded once; `DamageInfo.is_critical`; the target never recomputes. Stagger, knockback, i-frames and rewards untouched; only the player crits; defense has its insertion point documented, no formula |
| **M11.8** Target Lock & Combat Targeting | **Complete** | a target lock owned by `PlayerTargeting`: `Tab` locks the living enemy or boss best placed in front of the camera within 15 m and in view (one physics query, on demand), `Z` / `X` switch left / right by bearing, the lock drops past 18 m, on death, when the target leaves the scene, on the player's death or on `Tab` again. Locked, the player faces the target (12 rad/s) and strafes, attacks aim at it (facing only — hits stay physical), the dodge still follows the keys; a ring and a hint show it. Soft targeting and a lock-on camera are not built |
| **M11.9** Combat Feedback & M11 Closure | **Complete** | the player's hits felt, on a hit that counted (`Hitbox.hit_accepted`) and never on a miss, a refused hit or a corpse: a hit stop (`Engine.time_scale` 0 for L1/L2/L3/heavy 0.025 / 0.03 / 0.04 / 0.065 s, +0.015 s critical, one per swing, clamped to 0.1 s, always restored — on death, pause, scene change), a camera shake through the camera's offsets (0.03 / 0.045 / 0.07 / 0.12 m, ×1.35 critical, the stronger replaces, clamped) that never turns the rig, and a placeholder `CRITICO!` mark; accessibility scales for both; the shadow's hits felt as nothing. Owned by `PlayerCombatFeedback`; then the M11 audit and stress run |

**Closed without** — built later, where the roadmap puts them:
- **Sprint**, so stamina gates only the dodge (the movement pass; sprint animation is M14's).
- **Soft targeting** and a camera that frames the locked target (M14's combat camera).
- **Floating damage numbers**: a critical leaves a placeholder mark; numbers, hit sounds and hit VFX
  come with M13–M14.
- **The damage model's prospective fields** — magic, elemental and status damage, defense, armour
  penetration: the model and `DamageInfo` carry what is used (physical damage, critical, stagger,
  knockback, direction); defense has its insertion point documented (`ARCHITECTURE.md`, *Damage model
  and critical hits (M11.7)*) and no formula was invented. They arrive with M16's derived stats.

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

**Status: Complete** — closed by M12.9 (Boss Phase Mechanics & M12 Closure), with the M12 audit, the
mixed-encounter stress suite (`tests/enemies/mixed_encounter_test`) and the closure run
(`tests/core/m12_closure_run.gd`): two whole Hub → Gate → Dungeon → mixed encounter → Boss (phase 1,
phase 2, its special, the enrage, its death) → Hub cycles.

| Step | State | What it did |
| --- | --- | --- |
| **M12.1** Enemy AI 2.0 Foundation | **Complete** | the basic enemy's AI as an explicit state machine — `IDLE, ALERT, CHASE, REPOSITION, ATTACK, STAGGERED, DEAD` — with one writer of the state (`_change_state()`: exit, enter, `state_changed`), a table of legal transitions (DEAD never left, no swing from a stagger, none without a target, none doubled), enter / update / exit per state; the target owned by one component (`EnemyTargeting`): candidates from the data's `target_groups` (the player's alone — enemies still never fight the shadow), nearest in range, kept until it dies, leaves or runs off, the groups read once a second only while searching; movement separate from decisions; a path asked for only when the slot moves; a missing navigation said once; M11.6's stagger and push, M11.9's hit stop, the dodge and the lock untouched. Behaviour and numbers unchanged; the boss not migrated |
| **M12.2** Melee Archetype 2.0 | **Complete** | the first reusable enemy archetype, the melee, on the M12.1 state machine — a composition (`BasicMeleeEnemy`, `EnemyTargeting`, `EnemyMeleeAttack`) tuned by data, no archetype type anywhere. Its attack is `AttackData`, the player's resource (`melee_basic_attack.tres`), listed in `EnemyData.attacks` and chosen by `select_attack()`; the swing has one owner and one phase record (`EnemyMeleeAttack.Phase`: `NONE, TELEGRAPH, ACTIVE, RECOVERY`), then a cooldown distinct from the recovery; the telegraph always shown, the hitbox open only in ACTIVE, one hit per target per swing, the player and a shadow each hit once in one swing; the facing tracks early in the telegraph and locks 0.1 s before the hit (no homing); a stagger cancels the swing with no ghost hit, a weaker hit or a push does not; the approach now arrives on the ring (it used to freeze 1.85 m out, past its reach, at a player standing still). A heavier variant built from data alone in the tests. Numbers unchanged; the boss not migrated |
| **M12.3** Ranged Archetype 2.0 | **Complete** | the second archetype, the ranged, on the same state machine — renamed `BasicEnemy`, no second AI — with its own attack component (`EnemyRangedAttack`) and data (`basic_ranged_enemy.tres`): the range model as three `EnemyData` distances (minimum 4 m, preferred 7 m, maximum attack 10 m), approach / hold / back away to the ring (the hysteresis), a cornered fallback when the retreat times out; the attack lifecycle shared with the melee in a base (`EnemyAttack`), the ranged's ACTIVE a shot fired as the telegraph ends — aimed at the target's hurtbox now, no prediction, within the facing cone, withheld if the line is blocked; a reusable `Projectile` (straight, no homing, its speed and lifetime from `AttackData`, its hit the existing `Hitbox`/`DamageInfo` path, stopped by the world, never an enemy's), a `ProjectileSpawn` marker; line of sight cached for decisions and checked fresh at the fire; stagger before the fire cancels it, a fired shot flies on. Shipped dungeon content unchanged (placing ranged enemies is M18); the boss not migrated |
| **M12.4** Tank Archetype 2.0 | **Complete** | the third archetype, the tank, as a melee specialised by data alone — the M12.1 state machine and the M12.2 melee attack, no tank script, no archetype enum: `basic_tank_enemy.tres` (260 HP, 2.4 m/s, reach 2.3 m, stagger resistance 45, knockback ×0.35, cooldown 1.2 s) and `tank_heavy_swing.tres` (telegraph 0.8 s, active 0.2 s, recovery 1.1 s, 30 damage), and a bigger scene (body, hurtbox, hitbox, anchor, health bar). Light 1/2/3 flinch it and its swing goes on; the heavy staggers it and cancels a telegraph; knockback about an eighth of a melee's; tracking at 15% then locked 0.3 s before the blow, no homing; a 1.1 s recovery to punish. Shipped dungeon content unchanged (placing tanks is M18); the boss not migrated |
| **M12.5** Assassin Archetype 2.0 | **Complete** | the fourth archetype, the assassin — fast, fragile, mobile — on the M12.1 state machine and the M12.2 melee attack, no assassin script: `basic_assassin_enemy.tres` (60 HP, 5.6 m/s, turn 11 rad/s, reach 2.3 m, stagger resistance 20, knockback ×1.2, cooldown 1.3 s, disengage 4.5 m) and `assassin_quick_strike.tres` (telegraph 0.28 s, active 0.12 s with a 6 m/s lunge, recovery 0.35 s, 18 damage). Two generic rules added to the shared code as data, 0 for every other archetype: the disengage ring kept while the attack cools down (strike, back out on the navigation, back in — no new state or transition, the cooldown the one record) and the lunge along the locked facing through the physics (no homing, walls stop it). Light 3 and the heavy stagger it, the stagger immunity prevents stun-lock; a heavy throws it about ten times as far as a tank. Shipped dungeon content unchanged; the boss not migrated |
| **M12.6** Support Archetype 2.0 | **Complete** | the fifth archetype, the support — the first whose decisions are not all about hurting the player — on the M12.1 state machine with the ranged's distance model and shot, plus one optional part: `EnemySupport` (the support target, apart from the hostile target; the plan; the heal's and buff's cooldowns) and `EnemySupportAttack` (its casts run through the attack lifecycle), tuned by `EnemySupportData` (`EnemyData.support`). Allies found by one physics query every 0.5 s (enemies on the AI foundation, alive, awake — never the boss); the most hurt by share of health under 70% chosen and kept until healed, dead or gone; walks into 9 m and sight (round a wall); heal = a 1.2 s cast, then 25% of the ally's maximum through `HealthComponent.heal()` (clamped, never the dead), 0.6 s recovery, 6 s cooldown; a stagger cuts it (the heal spent), the ally dying or moving 12 m off drops it; a buff of +20% attack damage for 6 s, one slot on the ally's `EnemyAttack`, never stacked, cleared on death or parking — `DamageModel.buffed_damage()`; with nothing to do, the ranged's bolt (8 damage). `basic_support_enemy.tscn` / `.tres`, `support_heal` / `support_buff` / `support_bolt.tres`; `support_archetype_test` (56) and `m12_support_run` (15). The four other archetypes and the boss unchanged |
| **M12.7** Elite Enemy Framework | **Complete** | any enemy on the AI foundation made elite by data alone — the same scene, script, state machine and attacks, no elite scene or branch: `BasicEnemy.elite_profile` (an `EliteModifierData`, set per instance where it is placed; null is normal — `get_rank()` / `is_elite()` read it) scales the archetype's numbers once, at spawn, into the instance's runtime copies: health ×1.6 (filled to the effective maximum), speed ×1.05, damage ×1.2, cooldown ×0.85 (shorter), stagger resistance ×1.3, knockback taken ×0.7, XP ×2 (`elite_standard.tres`). Telegraph / active / recovery, reach, distances and hitboxes untouched; a support's heal and buff unscaled. Damage order: base × elite (static) → × a support's buff (runtime) → × the attack's multiplier — each once. Shared `EnemyData` / `AttackData` never written; normal enemies exactly their data; the reward flow unchanged — the effective XP paid once, 70/30 for a shadow's kill. A gold ELITE tag and frame on the health bar. `elite_framework_test` (43) and `m12_elite_run` (16). The boss unchanged |
| **M12.8** Boss Framework Foundation | **Complete** | a foundation of the boss's own — not an enemy with more health, not an elite: `DungeonBoss` on a `BossData` (`dungeon_boss_data.tres`, replacing `BossStats`), its own state machine (`INACTIVE, INTRO, DECIDE, CHASE, REPOSITION, ATTACK, STAGGERED, TRANSITION, DEAD`, one writer, a table of legal moves; priority DEAD > TRANSITION > STAGGERED > ATTACK > movement) and three parts: `BossPhaseController` (the phase, by health share, forward only — no rollback, a transition once), `BossCombat` (the one attack choice, asked only in DECIDE: the phase's pool, valid by hitbox, own cooldown, range band and a repeat ceiling of 2, weighted and seeded; the attack under way `NONE → TELEGRAPH → ACTIVE → (BETWEEN_HITS) → RECOVERY`; per-attack runtime cooldowns) and M12.1's `EnemyTargeting` (the player, as before). Phases as `BossPhaseData` (stable ids, `phase_1` 100–50%, `phase_2` ≤50%: a 1.5 s transition that cancels the attack and opens no hitbox, still hittable; Double Strike added, speed ×1.19, tempo ×0.8). `BossAttack` refit to compose an `AttackData`. The M11.6 rules shared through `HitReaction`: resistance 60 — the heavy staggers it, the lights never; 5 s immunity; knockback ×0.1. `start_encounter()`; death wins over a transition; completion by signal, once; the health bar by phase index. `boss_framework_test` (66) and `m12_boss_run` (19). Numbers and moveset kept; the archetypes and elites unchanged |
| **M12.9** Boss Phase Mechanics & M12 Closure | **Complete** | phase 2 made a real escalation on the M12.8 framework, by data alone: its pool adds the **Heavy Slam** (`boss_heavy_slam.tres`, phase 2 only: a 1.1 s telegraph — the longest — with a new rear-up wind-up and a ground marker, 0.2 s active, 1.4 s recovery, 50 damage, 8 s cooldown, weight 0.5, committed to its aim, dodgeable by moving or through the i-frames); its recoveries and cooldowns ×0.85, its speed ×1.19 — and **no telegraph shortened** (M12.8's `tempo_multiplier`, which shortened wind-ups, replaced by recovery and cooldown multipliers). A data-driven **enrage** (`BossEnrageData`: at 25%, a 1 s beat that is not interruptible and not invulnerable, then speed ×1.1 and cooldowns ×0.85, for good), owned with the phase by `BossPhaseController` — due only after every phase due, once, never undone; its own beat state (`ENRAGING`); modifiers recomputed base → phase → enrage, idempotent, no asset written; a lethal hit is a death through any threshold. The health bar calls "FURIA". The M12 audit: a ranged stuck for good just outside its ring behind cover, fixed ("on the ring" within its arrival tolerance); the placeholder mesh made optional for enemies, the boss and the shadow, so a definitive model replaces it without a gameplay change (M13). `boss_phase_mechanics_test` (42), `mixed_encounter_test` (14), `m12_closure_run` (20) |

**Closed without** — built later, where the roadmap puts them:
- **Target selection between the player and the shadow.** Enemies and the boss still fight the player
  only; the candidates are data (`target_groups`), so a shadow group makes shadows candidates under the
  same rules — but choosing between them (and any threat) belongs with the shadow army (M17).
- **Patrol** and **Retreat** as states: no room needs them yet; the dungeon's content does (M18).
  Stun is the stagger.
- **A group-combat coordinator or formations**: spacing comes from the approach angles, the
  navigation's avoidance and the attack desync when a fight is picked up — enough for the slice's
  encounters; a coordinator waits for denser encounters (M18).
- **The boss's ultimate and a death sequence**: the framework takes an ultimate as a `BossAttack` in a
  later phase's pool, with no FSM change; the death is a placeholder topple until M14's animation.
- **Enemy scaling by level or dungeon rank**: the elite profile is the scaling that exists; level and
  rank scaling come with M16's stats and M18's gates.

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

**Status:** not started. M12.9 left the gameplay ready for it: no AI or combat script needs a
placeholder mesh, a clip name or a model hierarchy (`ARCHITECTURE.md`, *Model and animation decoupling
(M12.9, for M13)*).

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
- **Camera and game feel:** camera collision, combat camera, boss camera, dynamic FOV; camera
  shake and hit stop exist since M11.9 (`PlayerCombatFeedback`) and are tuned here against real
  animation and audio

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
