# ShadowAscension — Progress

> **Maintenance note:** This file MUST be kept in sync with the actual state of the project. Update it whenever a milestone changes status, a task moves between sections, or a blocker appears/clears. Stale progress data is worse than none.

---

## Current Milestone

**M10 — Core Refactor & Game Architecture** (In progress — M10.1 to M10.4 complete)

First milestone of the **Core Production Foundation** phase. M10.1 consolidated the M0–M9
architecture without changing behaviour; M10.2 gave the character's persistent state a single
source of truth; M10.3 did the same for configuration; M10.4 decoupled the scenes. The rest of the
data-resource set and of the formal state split are the later steps.
See `ROADMAP.md` for the deliverables and exit criteria.

## Where the project is

| Phase | Milestones | State |
| --- | --- | --- |
| Prototype / Core Foundation | M0–M9 | **Complete** — vertical slice at RC1 |
| Core Production Foundation | M10–M12 | **In progress** — M10.1 to M10.4 complete |
| Visual Production | M13–M15 | Not started — **definitive art begins at M13** |
| RPG & Content Production | M16–M19 | Not started |
| Alpha 1 | M20 | Not started |

**Everything visible in the game is a placeholder.** That is the plan, not a shortfall: definitive
assets are produced from M13, once combat, hitboxes, skeleton and animation requirements, AI,
movement, interaction and architecture have stopped moving. `ROADMAP.md` explains why.

M9 closed on M9.2, which measured the game before touching it, changed one number, fixed four
bugs, and ran the loop end to end three ways. See *Done* below for the milestone record and
*Future Work* for what was deliberately left alone.

---

## Done

- **M10.4 — Scene & Dependency Decoupling** (Completed). Every lookup in the code was classified
  against one question — does this system know only what it needs? — and the answer was mostly yes
  already: no `get_node("../..")`, no absolute paths, no `current_scene.get_node()`, no identity by
  node name, no `find_child`, and nothing added to the root by hand. Boss death, dungeon completion,
  the gate and kill attribution were already signal- or reference-based. What was not:

    - **Gameplay drove the UI.** `ShadowRemnant` found the extraction banner through its group and
      called it, although it already emitted `extraction_started` / `extraction_finished`. The banner
      now watches remnants appear (the `node_added` pattern `DungeonRunStats` already used for loot)
      and listens; the remnant knows nothing about it, and an extraction lands with no banner at all.
    - **"The first player in the group" stood in for "my player"** in three places: the summoned
      shadow followed whichever player a search found, and the remnant and the loot paid it. The
      summoner now binds each shadow to its own player before it enters the tree, and the remnant and
      the item act for the body that walked in — the remnant keeps the one that made the attempt,
      because switching its collision off reports that player as having left.
    - **The player's components found each other by name**, from their own `_ready()` — which runs
      before the player's, so they had to walk the scene, and `PlayerProgression` knew the path
      `VisualRoot/AttackHitbox`. The player now wires them (`_wire_components()` → `setup()`), in the
      same order they used to wire themselves; the hitbox's path exists once, for M13 to move.
    - **The dungeon found its player through the global group**, the lookup M9.2 had already caught
      returning the player about to be freed. `DungeonController` now resolves its own player inside
      its own scene, and `DungeonRunStats` asks it instead of keeping a second copy of that walk.
    - **Two UI scripts carried identical parent walks** to find their controller; both now take it as
      their `owner`. The run summary asks the controller for its tally rather than fetching a child by
      name. The shadow-order marker finds an enemy's health bar by type, not by its node name, and the
      character sheet stops searching for the player on every refresh.
    - Two `SceneTree.node_added` listeners now disconnect in `_exit_tree()` (CLAUDE.md §8).

  One finding about the verification rather than the game. The first version gave
  `DungeonController` a static `find_for()` helper, and every flow run through the dungeon then
  reported GDScript instances and RIDs leaked at exit — while still passing every assertion, because
  the runner only counted `[PASS]` / `[FAIL]`. Bisecting to that one function and removing it cleared
  it. The runner now records runtime errors and exit-time leaks per suite, so that class of regression
  is visible.

  Deliberately unchanged: enemies still acquire the player through the typed group, since target
  selection is M12's; and the arbitration of which interactable answers [E] still lives in
  `InteractionPrompt`, as CLAUDE.md §9 prescribes — moving it is a change to the interaction system
  as a whole. Both are recorded in `ARCHITECTURE.md`, *Scene communication*, with the main event flows.

  New suite: `tests/core/decoupling_run.gd` (31 assertions). The player, an enemy, a shadow, a gate, a
  remnant and an item each come up alone, outside any level, and either work or stand still. On the
  real hub, a shadow follows its summoner and loot and remnants pay the player standing on them. Then
  Hub → Gate → Dungeon → Hub → Gate → Dungeon, comparing the two entries: listeners on the tree, on
  XP, on summoning and on death; players and shadows in the tree; and a kill paying and tallying once.

  **1381 assertions across 34 suites, zero failures, and — newly checked — zero runtime errors and
  zero exit-time leaks in any suite.** The 33 suites that existed before have the same pass counts as
  M10.3's run; the other 31 are the new suite. Cold-cache reimport and headless boot are clean.

- **M10.3 — Data-Driven Foundation** (Completed). Every archetype number now lives in exactly one
  place: its `.tres`. The project was already data-driven in shape — `EnemyStats`, `BossStats`,
  `BossAttack`, `ProgressionStats`, `ShadowData`, `AttackStep` and the item resources all existed
  and were all read — so the milestone was not about creating resources. It was about the copies.

  What the audit of every hardcoded value found:

    - **Each enemy number existed three times**: in the resource script's defaults, in the `.tres`,
      and as a literal on one of the 33 runtime fields `basic_melee_enemy.gd` seeds from it — plus a
      fourth copy of max health in the enemy scene's `HealthComponent`. The script "knew" the basic
      enemy's numbers.
    - **The boss's copies had already drifted.** `dungeon_boss.gd` said 600 HP and so did
      `dungeon_boss.tscn`; the asset has said 900 since M9.2. Nothing broke only because `reset_to()`
      overwrote the scene's value and the script's copy was never read — but a boss spawned without
      its asset would have been a 600 HP boss, and the scene's 600 is what caused the M9.2 bug.
    - **The player's progression tuning had the same shape**: ten literal fields in
      `PlayerProgression` mirroring `ProgressionStats`, and `PlayerProgressionData` (M10.2) repeating
      its starting stat block.
    - **Nothing wrote to a shared resource during play.** The copy-in-`_ready()` pattern was already
      right, and tested (enemy test #21); materials and navigation meshes were already duplicated
      before being changed. The only problem was the literals.

  What changed:

    - **`EnemyStats` is now `EnemyData`** (`scripts/enemies/enemy_data.gd`, asset
      `resources/enemies/basic_melee_enemy.tres`), the name the roadmap and the rest of the data
      layer use. Same fields, same values, plus inspector ranges so a negative health, speed or
      reward cannot be typed in. The enemy's export keeps the name `stats`, as the boss's and the
      progression's do, so no scene property was renamed.
    - **The runtime fields carry no values of their own** in `BasicMeleeEnemy`, `DungeonBoss` and
      `PlayerProgression`. Each is seeded in one apply function; with no asset assigned it warns
      and seeds from a fresh instance of the resource class, so even the fallback reads the one set
      of defaults. `PlayerProgressionData.from_stats()` does the same, and `Player` lost two literals
      that repeated its own exports.
    - **The scenes no longer carry health values** for the enemy (100), the boss (600) and the
      shadow (80). Each owner sets its `HealthComponent` explicitly through `reset_to()` or `bind()`.

  Deliberately not done, each for a stated reason in `ARCHITECTURE.md` (*Data-driven architecture*):
  no `PlayerData` (one consumer, no variant, and M11 reshapes the block), no `SkillData`,
  `DungeonData` or `GateData` (nothing reads them yet), no `BossData` (M12), the shadow's AI tuning
  left on its scene (M17), and the 70/30 split left a rule constant. Only one enemy archetype exists,
  so no variant assets were invented.

  New suite: `tests/core/game_data_run.gd` (31 assertions) pins every configuration value the game
  shipped with, proves each entity is seeded from its asset and nothing else, and — on the real
  dungeon — damages and retunes one of two enemies sharing an `EnemyData` and checks that the other
  and the asset are untouched. It does the same for the boss, for two shadows sharing a `ShadowData`,
  and for an enemy given an edited copy of its asset, which is the editor workflow: change the
  numbers, run, see them.

  **1350 assertions across 33 suites, zero failures.** The 32 suites that existed before are
  line-for-line identical to M10.2's result, so no behaviour moved; the other 31 are the new suite.
  The fallback path — an entity with no asset — was checked field by field as well: the 60 literals
  removed from the three scripts equal the resource classes' defaults, so even that path seeds the
  same numbers as before. Cold-cache reimport and headless boot are clean.

- **M10.2 — Persistent State & Data Ownership** (Completed). Level, XP, points, stats and every
  shadow's progression now have one source of truth each, held by the session; the player scene only
  views them. Traced from the code, not the docs: the session was already surviving scene changes
  correctly — the M6.3 fix held — but it did so by keeping **two copies of everything** and
  reconciling them by hand.

  What the trace found:

    - **Level, XP, points and stats existed twice.** `PlayerProgression` held its own fields and
      `PlayerRuntimeState` held a second set; the component wrote back through
      `_sync_to_runtime_state()` after each change and read back through `_restore_or_capture()` on
      each `_ready()`. Every new write path had to remember the sync.
    - **`_ready()` re-applied the starting values every time a player came up** — level, STR, AGI,
      VIT, INT from `ProgressionStats` — and relied on the restore right after to overwrite them.
      That is the exact shape of the M6.3 bug; it was only correct because the two calls were
      adjacent.
    - **Every shadow existed twice.** The collection rebuilt fresh `ShadowInstance` objects from
      flat rows on every scene and flattened them back after every extraction, removal and XP award.
    - **GIOCA did not start a new game.** Nothing reset the session except the tests. It was
      invisible only because nothing leads back to the menu, so the session is always fresh when
      GIOCA can be pressed; the first route back would have carried the old character into the new
      game. A latent defect rather than an observed bug, fixed as part of centralising the reset.

  What changed:

    - **`PlayerProgressionData`** (new, `scripts/player/`) — plain data: level, XP, points, the
      allocated stats. One per session, held by `PlayerRuntimeState.progression`, created once by
      `get_or_create_progression(stats)` — the only place starting values are applied.
      `PlayerProgression` attaches to it on `_ready()`; its `current_level`, `current_xp`, stat
      fields and so on are now properties that read and write that object, so every consumer and
      test kept its API and nothing needs syncing. `_apply_stats()` became `_apply_tuning()` and no
      longer touches a starting value.
    - **`PlayerRuntimeState.shadows` holds the `ShadowInstance` objects themselves**, and the
      collection takes that array by reference. The summoned entity was already a view onto its
      instance, so a shadow's level and XP now have exactly one home.
    - **One New Game point.** GIOCA calls `reset_runtime_state()`, which *replaces* the progression
      and the shadow array rather than emptying them, so a scene still holding the old game can no
      longer write into the new one.
    - Removed as dead: `capture_initial()`, `sync_progression()`, `sync_shadows()`, `initialized`,
      the `DEFAULT_LEVEL` / `DEFAULT_STAT` constants, the flat row format, the component-side
      restore and sync, and the `runtime_state_reset` signal, which nothing had ever connected to.

  What was checked and deliberately left as it is: **health** keeps its behaviour — max health
  derived and never stored, current health owned by the `HealthComponent` and handed to the next
  player through the session, full after a death. The **70/30 split** was already owned in one
  place (`PlayerProgression._collect()`, with the reward latched on the combatant) and is unchanged.
  The **UI** owned no copies and wrote only through owner APIs. A cross-scene **Run State** was not
  introduced: one gate leads to one dungeon and the run lives and ends inside that scene. **Inventory
  and equipment** still use the copy-and-sync pattern; they were outside this step's scope.

  New suite: `tests/core/persistent_state_run.gd` (54 assertions) walks menu → hub → gate → dungeon
  → kills → shadow kill → boss → exit → death → menu → GIOCA, and proves the ownership by object
  identity: the player's progression and shadow array *are* the session's, the same objects survive
  every scene change, a New Game replaces them, and a stale reference to the old game cannot reach
  the new one. It also covers level-up with remainder, two levels in one award announced once, a
  repeated death announcement paying nothing, and the 70/30 split on a real shadow kill.

  **1319 assertions across 32 suites, zero failures.** The 31 suites that existed before are
  line-for-line identical to the pre-change baseline (1265), so no behaviour moved; the other 54 are
  the new suite. One existing assertion was rewritten rather than weakened: `persistence_run` #31
  read the removed fields, and now checks the same claim — a reset session yields level 1, 0 XP,
  stats 10 — through `get_or_create_progression()`. Cold-cache reimport and headless boot are clean.

- **M10.1 — Core Architecture Audit & Refactor Foundation** (Completed). A behaviour-preserving
  consolidation of everything M0–M9 built, taken as read before anything was changed: the real
  dependency graph between player, dungeon, gate, enemies, shadows, XP, UI and the one autoload,
  rather than the one the filenames suggest.

  What the audit found, and what was done about it:

    - **The persistent-state access path was duplicated seven times.** `player.gd`,
      `player_progression.gd`, `player_inventory.gd`, `player_equipment.gd`,
      `player_shadow_collection.gd`, `player_shadow_summoner.gd` and `player_shadow_commander.gd`
      each carried an identical private `_runtime_state()` that looked the autoload up by its node
      name. There is now one accessor, `Player.session(node)`, and the name lives once in
      `Player.RUNTIME_STATE_NODE` instead of in seven string literals.

      The first attempt went further and used the `PlayerRuntimeState` autoload global directly,
      dropping the lookup altogether. **That was wrong, and the flow harnesses caught it**: a test
      entered through `--script` compiles the game's scripts before the autoloads are registered, so
      the identifier does not resolve and `player.gd` fails to compile, taking the boss, the rooms,
      the dungeon and the gate with it. `m5_review_run` went from 37 passes to 23 failures — the
      player swung 5401 times for 0 damage, because there was no compiled player. A probe had shown
      the global resolving from a `Node` script, but that probe loaded the script *after* the
      autoloads existed, which is not the harness's order. Reverted, and the constraint is now
      written down in `ARCHITECTURE.md` and in `player.gd` so it is not rediscovered a third time.
      Nothing about the scene suites or a normal boot reveals it.
    - **The scene-transition lookup was duplicated four times**, in `dungeon_controller.gd`,
      `dungeon_gate.gd`, `dungeon_exit.gd` and `main_menu.gd` — three copies of one caching helper
      plus a fourth written differently. Now `SceneTransition.find_in(tree)`, matching how
      `InteractionPrompt` and `RunSummary` already publish their own lookups.
    - **`"player"` was the last bare group literal**, repeated across 23 call sites while every
      other group in the project is a typed constant on its owner. Now `Player.GROUP`.
    - **The state categories had no names in code.** `PlayerRuntimeState` (Persistent Player State),
      `DungeonRunStats` (Run State) and `DungeonController` (Dungeon State) now say which category
      they own and what must not be put in them. World State, Settings and Save Data have no owner
      because nothing needs them yet; none was invented.

  What the audit checked and found already sound, so nothing was touched: one autoload with one
  responsibility and no scene-specific state in it; enemies, bosses, loot, items and shadows already
  data-driven through `EnemyStats`, `BossStats`, `BossAttack`, `LootTable`, `ItemData`, `ShadowData`,
  `ProgressionStats` and `AttackStep`, with no repeated hardcoded tuning left to extract and no
  collision layers written in code; XP owned by `PlayerProgression` alone, including the 70/30
  shadow split, with every HUD and menu observing signals rather than holding a copy; rooms and
  dungeons that only ever walk their own subtree; and no `get_parent().get_parent()` chains or deep
  absolute paths anywhere. The sibling lookups that do exist are `@export`-with-fallback, which is
  the project's existing injection pattern. This is why M10.1's diff is small: most of what the
  audit looks for was not there to find.

  What the audit found and deliberately did **not** change: the player's attack hitbox is parented
  under `VisualRoot`, which also carries the cosmetic attack and dodge tilts, so moving it to a
  gameplay anchor — as the enemy already has in `VisualRoot/AttackOrigin` — would change the swept
  hit volume. That is a behaviour change, so it is M10's next step to decide, not this one's to
  slip in. Debug output was reviewed and kept: what exists is intentional tooling, not leftovers.

  **1265 assertions across 31 suites, identical to the pre-refactor baseline, zero failures**, plus
  a cold-cache reimport and a headless boot with no errors, parser errors or warnings.

- **M9 — Vertical Slice** (Completed). Closed on M9.2: balance, QA and release candidate.

    **Measurement came first, and it changed the conclusions.** A baseline harness
    (`balance_baseline_run.gd`) reported what the game actually does before a single number moved.
    Most of it was already on target: a basic enemy takes **4 light attacks** (target 3–5), the
    player survives **7 enemy hits** (target 5–7), a normal enemy drops something **45%** of the
    time (target 40–50%), the boss always drops, extraction is **0.70**, and a full player-led
    clear gives **2 level-ups** (target ~2). None of those were touched.

    **Two measurements were wrong until the harness was.** A boss fight first read as 9 seconds,
    because the simulated player snapped back into melee the instant each active window ended.
    Making it pay for the ground it gave up — 3.4m at its own speed — put the same fight at 48s.
    And the shadow first read as "cannot clear a room in 180 seconds" because the phase before it
    had killed the player and restarted the dungeon underneath it.

    **One balance change: boss health 600 → 900.** At 600 the fight measured 48s against an
    indicative 90–180s; at 900 it measures **120s**, because phase 2 begins later and its faster
    attacks cost the player more uptime. The increase is not linear with health for that reason.
    Raising health is the lever the brief cautions against, and it is the only one that does not
    regress something already on target — the normal-enemy numbers or the pattern readability,
    which is the criterion that matters more and which all four attacks still satisfy in a
    measured fight.

    **Four bugs found and fixed:**
    - *The boss did not start at full health.* `HealthComponent` fills to `max_health` in its own
      `_ready()`, which runs before its parent's, so a boss that then wrote `max_health` alone
      began the fight at the scene's old value — 600 of 900. `reset_to()` sets the ceiling and
      fills to it, and both the boss and the basic enemy use it. This was latent for as long as
      the two numbers happened to agree.
    - *The run summary could report another run's XP.* `DungeonRunStats` found the player through
      the global group, and during a scene change the outgoing scene is still in the tree — so it
      could take its baseline from the player about to be freed. It now looks inside its own
      dungeon. Symptom: a full clear reporting 0 XP of 325.
    - *The kill tally was not latched.* XP and remnants are both latched at their source, so a
      death announced twice pays nothing twice; the tally was not, and counted it. It is now.
    - *The M9.1 summary could render before the last kill was counted* — fixed in M9.1 and
      re-verified here.

    **QA: 100 checks, all passing** (`qa_run.gd`). Duplicate rewards (XP, loot, remnants,
    extraction, room clear, dungeon completion, equipment stacking, inventory), rapid input on
    every interactable and every menu, one prompt for overlapping interactions, menus during
    combat, shadow commands against corpses and leashes, health bars, deaths in each room and in
    boss phase 2, and three hub→dungeon→hub cycles with nothing accumulating.

    **Three full runs** (`full_runs_run.gd`, 24/24): player-led, shadow-led and failure/recovery.
    Measured in simulated combat time, excluding the walking and reading a person does:

    | Run | To the summary | Boss | Result |
    | --- | --- | --- | --- |
    | A — player takes the kills | 212s | 186s | 325/325 XP, Lv.3, 4 shadows extracted |
    | B — shadow takes the kills | 204s | 186s | 5 shadow final blows, shadow Lv.1→2, player 235 XP |
    | C — failure and recovery | 30s (after the death) | — | failed extraction, dead shadow, dead player, then a clean clear |

    Run B is the 70/30 rule end to end: five shadow-finished kills paid the player 7 each, and the
    summary reported the player's share rather than what the enemies were worth.

    **Whole-project state: 1265 assertions across 31 suites, zero failures**, zero parser errors,
    zero runtime errors, zero warnings, from a cold class cache.

- **M8 — Shadow System** (Completed). Milestone review passed. All four ROADMAP exit criteria were
  verified by walking the whole system end to end with real scene changes rather than by reading it
  (`m8_review_run.gd`, 89/89, stable across three consecutive runs):
    - *Killing an enemy triggers an extraction check using the configured probability* — driven from
      the real asset in both directions: at 0.00 the attempt fails and the remnant is spent, at 1.00
      the next one succeeds, and the shipped 0.70 is restored and asserted.
    - *Successful extraction adds a shadow to the collection* — one remnant per corpse, Lv.1 with
      0 XP, stats read from the asset, and the session recorded it for the next scene.
    - *Player can summon a collected shadow; it engages enemies and dies correctly* — summoned into
      the scene rather than onto the player, it took an order and fought, and when killed the entity
      died and cleaned up while the shadow kept its level and XP and could be summoned again.
    - *Summon respects limits and cleans up on despawn* — summoning a second recalls the first,
      exactly one is ever in the world, and a despawn leaves nothing behind.

    The review also covered the full loop the brief asked for: test world, gate, kill, extraction,
    collection, summon, FOLLOW, manual order, a kill the shadow finished, the 70/30 split,
    AGGRESSIVE, multi-enemy combat, a level-up, recall, the boss, dungeon completion, the exit
    portal, back to the test world with level and XP intact, a second run with a fresh id, and a
    player death followed by a restart with the collection untouched and summoning working again.

    **No code bugs were found.** Two review-time failures both turned out to be the harness, not the
    system, and are recorded here because the distinction matters: the test helper stands the player
    at 1.6m to swing, which is exactly `BasicMeleeEnemy.preferred_combat_distance`, so a live enemy
    sidesteps a player that teleports onto it and 53 swings landed one hit — enemy AI doing its job.
    And an aimed order in a room with several live enemies often finds a different one standing in
    the way, which is the command working rather than failing. Both assertions were rewritten to
    test the rule they claimed to test.

    M8.1 delivered extraction, remnants and the collection; M8.2 summoning, shadow AI, combat,
    levels and the XP split; M8.3 command modes, orders, the recall, the leash, stuck recovery and
    the Active Shadow HUD. Each sub-milestone's own record is below.

    Whole-project state at review: **1051 assertions across 27 suites, zero failures**, zero parser
    errors, zero runtime errors, zero warnings.

- **M8.3 — Shadow Commands and Combat Polish** (Completed). Two command modes on the summoned
  entity (FOLLOW never starts a fight, AGGRESSIVE does, both obey an order), an aimed attack order
  resolved by raycast, a tactical recall distinct from the menu's despawn, one target-priority rule,
  a world-space marker, a leash measured from the player, progress-based stuck recovery that
  repaths before it ever repositions, and an Active Shadow HUD carrying name, level, health, mode
  and the command hints. Inputs Q / T / middle mouse, none of them rebinding anything.
  Three real bugs were found and fixed while building: the shadow froze when asked to path to an
  off-navmesh point, an enemy could pin it because their bodies collided in one direction only, and
  a wall behind the player ate the attack order because the ray started at the camera. Verified by
  `command_test.tscn` 91/91 and `command_run.gd` 22/22.

- **M8.2 — Shadow Summoning, Combat and Progression** (Completed). A shadow could be put into the
  world, fought on its own, levelled from the kills it finished, and re-summoned itself after a
  scene change. `ShadowData` carries the curve (50 XP at Lv.1, x1.2 per level) and the scaling
  (80 HP + 8/level, 12 damage + 2/level); a `ShadowInstance` carries the progress. A kill is split
  by who finished it: the player keeps its own kills whole, and the shadow takes 70% of the ones it
  finishes with the player taking the remainder, so the halves always sum to the full reward.
  No friendly-fire check exists anywhere, because the collision masks make it unrepresentable.
  Verified by `summon_test.tscn` 72/72 and `summon_run.gd` 24/24.

- **M8.1 — Shadow Extraction and Collection Foundation** (Completed).
  M8.1 delivered: enemies leave remnants, a remnant grants one attempt, and what comes out is an
  individual shadow the player keeps for the session. No summoning, no shadow AI, no shadow
  progression — those are M8.2 and later.

  M8.1 deliverable status (verified by `shadow_test.tscn` 52/52 and `shadow_run.gd` 20/20, the latter
  with real scene changes):

  - ShadowData — implemented
  - Shadow Instance foundation — implemented
  - Shadow Remnant — implemented
  - extraction chance — implemented
  - extraction success/failure — implemented
  - PlayerShadowCollection — implemented
  - Shadow Collection UI — implemented
  - runtime Shadow persistence — implemented

  The extraction chance lives only on the `ShadowData` asset, and an instance is a real object rather
  than a tally, so M8.2 can give each shadow its own level and XP without reworking the collection.
  Ids are minted by the collection but counted by the session, which is what stops a new scene from
  restarting the numbering and colliding: a shadow extracted on the second run came back `#000006`
  after five from the first.

  A remnant is not an enemy. Both combat rooms cleared and opened their doors with remnants still
  standing, which the tests assert directly.

  **One real bug was found and fixed while building, and it is the one the brief warned about.** A
  single press on a corpse that left several things reached all of them: the acting interactable
  releases the prompt, the next one in range inherits it within the same frame, and its own
  `_unhandled_input` then fires too — two shadows from one key. Whoever acts now consumes the event.
  The fix needed both halves of the design: the prompt stack decides *who* may act, and consuming the
  input stops the rest of the frame from asking again. Found by driving a real key press rather than
  calling the method, which is exactly where the earlier version of the test was blind.

  `InteractionPrompt` grew from a single owner into a small priority stack to make that possible —
  documented in ARCHITECTURE.md. A remnant outranks ordinary loot, and when the winner goes away the
  runner-up takes the prompt over rather than leaving the player with nothing to press. Both are
  tested with a dropped item and a remnant on the same spot.

  Measured across a real loop — gate, both combat rooms, boss, exit, second gate, one more extraction,
  then a death — five shadows carried through every transition, a sixth joined them on the second run
  with a fresh id, and dying cost none of them.

  The tests force the extraction chance to 1.0 and 0.0 rather than hoping for a 70% roll, and restore
  it afterwards; both suites assert the restore.

- **M6 — Player Progression** (Completed). Milestone review passed; all four ROADMAP exit criteria
  verified by walking the whole thing end to end rather than by reading it:
    - Killing enemies awards XP; hitting the threshold levels up — 60 XP does not level, 100 does,
      and five kills plus a boss inside a dungeon carried the character from level 2 to level 4.
    - Points can be allocated to stats; stats affect combat as expected — five points spent on the
      sheet moved attack damage 20 → 22, movement 6.00 → 6.06 and max health 100 → 108 in the same
      frame.
    - Level and stats update UI or debug readout in real time — the HUD followed the level-up with
      no prompting, the callout fired, and the sheet redrew as each point was spent.
    - Zero errors on level-up transitions and stat mutations — 531/531 across every suite with zero
      runtime errors, zero warnings and zero leaked instances.
    - The review also covered the full loop with real scene changes: test world, progression, gate,
      dungeon, more progression, boss, exit, second run, and a death. `m6_review_run.gd` 28/28.
    - One latent inconsistency was found and fixed (below); nothing else in M6 needed changing.

    Review fix — `Player._restore_health()` did not re-sync the session in its clamping branch. The
    other two branches did, so the stored health only went stale when the clamp actually bit: a
    restore above the new ceiling would be trimmed for this player and left untrimmed in the
    session. Not reachable today, because VIT only ever rises and so the ceiling only ever grows,
    but it would have become a real desync the moment anything lowered max health. The branch now
    reports the clamped value like the others.

    M6.1 delivered: XP, levels, a computed curve, stat points that accumulate, base stats as data, XP
    rewards declared by enemies and the boss, a progression HUD and a level-up callout. No allocation,
    no stat screen, no effects — those are M6.2.

    M6.1 deliverable status (verified by `progression_test.tscn` 47/47 and a full real run 17/17):

    - XP foundation — implemented
    - level system — implemented
    - XP curve — implemented
    - stat points — implemented
    - base stats — implemented (data only)
    - enemy XP rewards — implemented
    - boss XP reward — implemented
    - progression HUD — implemented
    - level-up feedback — implemented

    `PlayerProgression` is a component on the player, not part of its controller. It is the active
    receiver: a combatant only *declares* what it is worth (`RoomCombatant.get_xp_reward()`, which the
    enemy and the boss override to answer from their own stats Resource), and this node decides whether
    to take it. The base asks rather than being written to, so no subclass assigns an inherited field
    while it is initialising and nothing about initialisation order can decide what a kill is worth. It learns which combatants exist by
    listening to the player's own attack hitbox — `Hitbox.hit_landed` already fired for every hit the
    player lands — so the only enemies it ever subscribes to are ones the player actually fought.
    Nothing searches the tree, no controller wires enemies to the player, and it works in the test world
    and the dungeon alike with no extra plumbing.

    Paying twice is guarded at the source rather than at each call site: `RoomCombatant.claim_xp()`
    hands its reward out once and returns 0 forever after, and `report_death()` makes the death hook
    fire once however the death was reached. A duplicated signal, a room clearing, a boss phase
    transition and a dungeon completing were each tested and add nothing.

    A full run — test world, gate, both combat rooms, boss, completion — with real player combos awards
    **325 XP**: two enemies at 25, three at 25, and the boss at 200, over six kills and 23 boss swings.
    That takes the player to **level 3 with 100/156 XP and 10 unspent stat points**, through two
    level-ups.

    **Progression does not survive a scene reload.** Dying in a dungeon reloads the scene and builds a
    fresh player, which starts at level 1 again. Persisting progression across scene changes needs a
    save or session layer; introducing an autoload solely for that was explicitly out of scope here, so
    it is deferred to its own milestone. The limitation is recorded in `player_progression.gd` as well.

    Bug found and fixed while building: `PlayerProgression` is a child of the player, so its `_ready()`
    runs *before* the player's — `player.attack_hitbox` was still null and the subscription was never
    made, leaving every kill worth nothing. It now resolves the hitbox itself, the way `Hurtbox` already
    resolves its siblings. One existing assertion was corrected alongside it: `enemy_test` revives a
    single enemy instance between sub-tests, which nothing in the game does, so its reset now clears the
    new death and XP latches too.

    M6.2 delivered: a character sheet on C that pauses the game, points that buy stats, and four stats
    that now do something. No respec, no decrement, no caps, no equipment, no save.

    M6.2 deliverable status (verified by `stats_test.tscn` 53/53):

    - Stats Menu — implemented
    - stat allocation — implemented
    - STR — implemented
    - AGI — implemented
    - VIT — implemented
    - INT — implemented
    - derived stats — implemented
    - STR combat integration — implemented
    - AGI movement/dodge integration — implemented
    - VIT health integration — implemented
    - character stats HUD hint — implemented

    `PlayerProgression` stays the single source of truth: it owns the four stats and every derived
    getter, and nothing else keeps a copy. The player holds `effective_movement_speed`,
    `effective_dodge_speed` and `base_max_health` beside its untouched base exports, and recomputes all
    three from the bases on `stats_changed` — never incrementally, so a multiplier cannot compound. The
    same rule covers damage: STR is applied when a swing is prepared, and the `AttackStep` keeps its
    base value, which the tests check after real swings.

    `HealthComponent` gained `set_max_health()`, which clamps current health down to a new ceiling and
    never tops it up. It is generic and knows nothing about VIT — the enemy and the boss keep their own
    maximums, verified in the same run.

    The menu runs with `PROCESS_MODE_ALWAYS` and pauses the tree, so its buttons work while everything
    else is frozen: an enemy mid-fight and the boss mid-encounter both drift 0.0000 units while it is
    open and resume when it closes. It consumes C and, only while open, ESC — so the existing
    release-the-mouse behaviour of a bare ESC is untouched. A scene change with the menu still open
    unpauses on the way out.

    Numbers confirmed against the project's real base values: attack 1 goes 20 → 23 at STR 15 and 25 →
    29 for attack 2, measured both through the formula and through a real swing at an enemy; movement
    6.00 → 6.30 and dodge 11.50 → 11.79 at AGI 15; max health 100 → 140 at VIT 15, and investing at
    50/100 gives 50/108 rather than a free heal.

    M6.3 delivered, and with it the bug M6.1 had flagged: level, XP, stat points and stats were reset
    every time the player changed scene. They now survive.

    M6.3 deliverable status (verified by `persistence_run.gd` 48/48, all with real scene changes):

    - runtime progression persistence — implemented
    - scene transition persistence — implemented
    - runtime stat persistence — implemented
    - runtime XP/Level persistence — implemented
    - runtime health persistence — implemented
    - death health reset — implemented
    - second dungeon run persistence — implemented

    **Cause of the reset.** Nothing was broken in the progression system itself. A scene change destroys
    the player and instantiates a new one, and `PlayerProgression` seeded itself from its
    `ProgressionStats` asset every time — which is exactly the starting values. There was nowhere for a
    session to live, so every gate, every exit portal and every death restart handed back a level 1
    character.

    `PlayerRuntimeState` is a new autoload holding only that session data; it is documented in
    ARCHITECTURE.md, including that it is explicitly **not** a save system. The first player of a
    session hands it its starting values, every later player restores from it, and `PlayerProgression`
    writes back through one `_sync_to_runtime_state()` so a new field does not have to be remembered in
    each callback. Max health is deliberately not stored — it is recomputed from the player's base plus
    VIT on every load, so the two cannot desync — and health is reported by the player through
    `HealthComponent.health_changed` rather than polled.

    Death is the one case that restores health without touching progress. A negative stored health means
    "full", which is both what a death leaves behind and the fresh-session state.

    Measured across a real run — test world, gate, dungeon, five kills, a boss, exit portal, a second
    gate, then a death — every value held: level 4, 84 XP, 8 unspent points, STR 12 / AGI 11 / VIT 12 /
    INT 12, and 37/116 health carried unchanged through the gate, the exit and the second entry. After
    dying at 20/116 the character came back at 116/116 with all of that intact.

    One real bug was found and fixed while building: `capture_initial()` took a health argument that
    `PlayerProgression` could not know, so it passed `0.0` and the first player of the session restored
    itself to zero health. Health is now the player's to report, and the autoload's default means
    "full" rather than "empty".

    Every suite now begins by resetting the session. Without that, one test would inherit whatever an
    earlier one left behind — which is the persistence working, not a defect.

    The M6 milestone review then ran and passed; its result is at the top of this entry.


- **M5 — First Boss** (Completed). Milestone review passed; all four ROADMAP exit criteria verified:
    - Boss executes each attack correctly with readable telegraphs — two full fights used all four
      attacks, and each wind-up was read off the body rather than the resource: lean, spin, compress
      and recoil, four distinct shapes.
    - Phase transition triggers on an HP threshold and swaps behavior — `PHASE_1 -> TRANSITION ->
      PHASE_2` exactly once per fight, on swing 15 of 23, with movement speed, attack timings,
      cooldowns and the attack set all changing after it.
    - Player can defeat the boss without engine errors — killed twice with the player's own combo,
      driven through `camera_rig.attack_light_pressed` rather than by calling `receive_hit`, so the
      whole damage path ran: 23 swings for 600 damage each time, zero runtime errors.
    - Boss death emits an event other systems can subscribe to — `enemy_died`, which
      `RoomController` already consumes and M6/M7/M8 will subscribe to for XP, loot and shadow
      extraction.
    - The review also covered a player death in phase 2, the restart it forces, and a second full
      fight on the reloaded dungeon. Validation: `m5_review_run.gd` 37/37, and 338/338 across every
      suite with zero runtime errors and zero leaked instances.
    - One real bug was found and fixed (see below); nothing else in M5 needed changing.

    M5.1 delivered: `DungeonBoss` replaces the boss-room placeholder — its own state logic, three
    distinct attacks with a decision layer, per-attack cooldowns, a temporary health bar, and death
    that feeds the existing room/dungeon completion flow. No phase 2, no cutscene, no loot.

    M5.1 deliverable status (verified by `boss_test.tscn` 37/37 and the real-scene-change flow 45/45):

    - boss base scene — implemented
    - boss state foundation — implemented
    - boss decision logic — implemented
    - Quick Strike — implemented
    - Wide Sweep — implemented
    - Ground Slam — implemented
    - boss cooldowns — implemented
    - boss UI prototype — implemented
    - boss room integration — implemented
    - boss death/completion integration — implemented

    A later conformance pass added the explicit `INACTIVE` state. The boss was already dormant before
    the player arrived — the room parks it and `combat_enabled` gated every system — but it reported
    `INTRO` while parked, so "dormant" and "winding up" were the same value to anything reading the
    state. They are now distinct: a parked boss is `INACTIVE`, the wake goes `INACTIVE -> INTRO ->
    DECIDE`, and a boss placed in a scene with no room still starts its own encounter from `_ready()`.
    The hitbox nodes `SweepHitbox` and `SlamHitbox` were renamed to `WideSweepHitbox` and
    `GroundSlamHitbox`, so every node name matches its attack's name.

    M5.2 delivered: the fight has two halves. The boss opens in phase 1 exactly as M5.1 shipped it,
    drops into a harmless, committed beat at half health, and comes out faster with a fourth attack.
    No phase 3, no loot, no enrage timer, no adds.

    M5.2 deliverable status (verified by `boss_phase_test.tscn` 51/51 and the real-scene-change flow
    45/45):

    - Phase 1 — implemented (unchanged from M5.1)
    - Phase Transition — implemented
    - Phase 2 — implemented
    - Phase 2 timing — implemented
    - Double Strike — implemented
    - Phase 2 decision logic — implemented
    - Phase UI — implemented
    - encounter polish — implemented

    `BossPhase` is a separate concept from `State`: the boss stays in `PHASE_2` while it chases,
    attacks and recovers, so the two never have to be kept in sync by hand. Only the beat between them
    is both at once — `State.TRANSITION` and `BossPhase.TRANSITION`. The transition is latched the
    moment it starts, so no amount of further damage, or a heal and re-damage, can run it twice.

    Crossing the threshold tears down whatever was in flight rather than waiting for it: hitboxes off,
    the queued attack cancelled, navigation parked, the boss harmless for the whole 1.5s. That is
    tested by catching the boss mid-Ground-Slam and cutting its health at that instant. It is not
    invulnerable there, and dying inside the beat is covered: the boss stays dead, never reaches phase
    2, opens no hit window, and the room still clears exactly once.

    Phase-2 tuning lives on the same resources as phase 1 rather than a duplicate set: each
    `BossAttack` carries its phase-2 startup, recovery and cooldown, and the boss asks the resource for
    a timing instead of branching on the phase itself. Damage and reach never change between phases —
    phase 2 changes the rhythm, not the numbers. Attack choice moved from uniform to weighted, so
    Ground Slam stays rarer than the standard melee without ever being impossible.

    Double Strike is phase 2 only, and is the first multi-hit attack: `hit_count` and
    `delay_between_hits` drive a `BETWEEN_HITS` window in the attack machine. Each swing re-activates
    one real hitbox, and `Hitbox.activate()` already clears its hit registry, so a swing lands once and
    the next starts fresh — no bespoke dedup logic was needed. The gap allows a quarter of the boss's
    turn rate, enough to track a little and not enough to snap onto a player who left.

    Arena: checked, not changed. A full dodge (4.0 units) fits in every direction from where the fight
    happens, with 5.0 clear at the tightest; the player can walk into all four corners and back out;
    and the navmesh reaches every corner. Nothing needed moving, so nothing was moved.

    One existing assertion was corrected, not a behaviour: `boss_test`'s reposition check gave the boss
    1.8s to back out of the player's lap, which is shorter than a Ground Slam's 2.05s commitment.
    Weighted selection changed the seeded RNG stream, the boss happened to be mid-slam, and the test
    failed. A probe showed the boss entering REPOSITION at T=0.05 and reaching 1.78 units — the
    behaviour was correct and the window was too short. The test now outlasts a committed attack.

    Balance is still deliberately untuned:
    600 HP against a 20/25/35 combo is thirty swings, and the phase transition lands on swing 15.

    A fix + UX pass landed between M5.1 and M5.2, before any further boss work: the boss room was
    physically unreachable, and the dungeon gave the player no contextual guidance. Both are fixed —
    see the entry under In Progress.

    Review fix — `Hitbox.deactivate()` wrote `monitoring` directly. A blow that kills the player runs
    `area_entered -> receive_hit -> died -> DungeonController._on_player_died -> RoomController.suspend()
    -> set_combat_enabled(false)`, which deactivates whatever the boss had mid-swing — all inside a
    physics signal, where Godot refuses a direct write and logs `Function blocked during in/out signal`.
    Only reachable when the killing blow lands during an attacker's own active window, which is why
    every earlier suite missed it: they damaged the player with `receive_hit` directly instead of
    letting the boss do it. The write is now deferred; `_active` is already false and `_on_area_entered`
    refuses on that, so nothing can land in the deferred frame. The fix is in a shared M2 component but
    the same path exists for `BasicMeleeEnemy`, so it closes both.

    - **M5.1 — First Boss Foundation**:
        - `scripts/enemies/room_combatant.gd` (`RoomCombatant`) — a behaviourless base holding only what
          a `RoomController` drives: the `enemy_died` drop hook and `set_combat_enabled()`. It exists so
          a room can hold an enemy or a boss without either inheriting the other's AI. `BasicMeleeEnemy`
          now implements it (two lines changed, no behavior touched) and `RoomController` is typed to it.
        - `scripts/enemies/bosses/dungeon_boss.gd` (`DungeonBoss`) — its own state logic,
          `INTRO / DECIDE / CHASE / REPOSITION / ATTACK / RECOVERY / DEAD`, sharing only the common
          components: `HealthComponent`, `Hurtbox`, `Hitbox`, `NavigationAgent3D`. No boss state machine
          framework, no manager.
        - Data-driven per `CLAUDE.md` §7: `BossStats` (`resources/enemies/bosses/dungeon_boss_stats.tres`)
          holds the body tuning, and `BossAttack` holds one attack each —
          `boss_quick_strike.tres`, `boss_wide_sweep.tres`, `boss_ground_slam.tres`. The boss copies
          stats into its own fields on `_ready()`, so the shared assets are never written to.
        - Decision layer: from DECIDE it filters the attack set by cooldown, by the attack's own range
          band, and by how many times that attack has already run back to back (`max_consecutive_repeats`
          = 2), then picks among what survives with a **seeded** RNG so a run is reproducible. Too far →
          CHASE. Too close, or aimed outside the 30° cone → REPOSITION. Measured over a 22-second free
          fight: 16 attacks, all three used, longest identical run 1.
        - Attacks — Quick Strike 20 dmg, 0.25/0.12/0.45, cd 1.0, reach ≤ 2.6; Wide Sweep 30 dmg,
          0.50/0.20/0.70, cd 2.0, reach ≤ 3.4 over a 4.4-wide box; Ground Slam 40 dmg, 0.85/0.20/1.00,
          cd 3.5, a 3.2-radius cylinder centred on the boss. Each drives its own real `Hitbox` on layer
          32 / mask 64 — there is no distance check anywhere in the damage path, proven by blinding the
          player's hurtbox and watching the same attack at the same range deal nothing.
        - Commitment: STARTUP may correct facing, and only by its own fraction of `rotation_speed`
          (0.35 / 0.15 / 0.00); ACTIVE and RECOVERY do not turn at all. The player can walk out of a
          wind-up, and dodge i-frames stop a boss attack with no boss-side logic.
        - Telegraphs animate a `MeshRoot` **below** the facing node, so a wind-up can lean, spin or
          compress the body without moving the hitboxes or changing where the boss aims. The three read
          apart — measured as lean / spin / compress on their dominant channel.
        - Hit feedback is a brief albedo pulse with no displacement: a boss should not read as flinching.
          No stagger.
        - `scripts/ui/boss_health_bar.gd` + `scenes/ui/boss_health_bar.tscn` — a temporary CanvasLayer
          readout. It finds the boss through the `boss` group and listens to `encounter_started` and
          `enemy_died`, so the boss knows nothing about any UI. Explicitly not a HUD framework; M5.2
          replaces it.
        - Death emits the inherited `enemy_died`, which the room already counts — the boss never
          references `DungeonController`. The M4 completion flow continues untouched: room clears, exit
          portal wakes, banner shows, return trip works.
        - **Bug found and fixed during the build:** all three attacks have `min_range = 0`, so the
          decision layer considered attacking valid even standing inside the player, and the boss never
          unglued itself. DECIDE now sends it to REPOSITION below `minimum_combat_distance`. Verified:
          dropped at 0.9 from the player it backs off to 1.78.
        - Automated validation `res://tests/bosses/boss_test.tscn` — **33/33 PASS**, covering dormancy
          before entry, activation and door lock, health bar appearing full, chase and reposition, each
          attack's exact damage, hitbox gating, the no-distance-damage proof, distinct wind-ups, ACTIVE
          facing lock, escaping a wind-up, dodge i-frames, the repeat ceiling and all-three usage,
          per-attack cooldowns, player combo damage and one-hit-per-swing, hit feedback without recoil,
          bar tracking, death, and the room/dungeon/exit-portal chain.
        - The real-scene-change flow `dungeon_flow_run.gd` now **fights the boss** rather than one-shotting
          it: 30 hits of 20 to fell 600 HP, twice in a row, with the bar tracked throughout — and the
          node count across two loops is still identical (127 vs 127, 0 orphans).
        - Regression: combo 10/10, dodge 18/18, enemy 22/22, enemy polish 17/17, dungeon suite 31/31,
          loop 34/34, boss 33/33, real flow 32/32 — **197/197**. `--check-only` clean; `Main.tscn` and
          `dungeon_test.tscn` each 600 verbose frames with zero ERROR / WARNING / Failed / Parse Error /
          SCRIPT ERROR and no leaked instances.
    - **Dungeon fix + UX polish** (between M5.1 and M5.2):
        - **Blocking bug: the boss room was sealed shut.** `RoomController._ready()` called
          `exit_door.lock()` unconditionally, and the boss room's door sits in its *entrance* — placed
          there in M4.1 so it would seal behind the player. It sealed at load instead, walling the room
          off before the player could arrive. Reproduced by physically walking the body down the
          dungeon: it stopped at `z = -49.35`, blocked by `ExitDoor/Blocker` at `z = -49.75`, with both
          combat rooms cleared and their doors open behind it.
        - Why no test caught it: every dungeon test *teleported* the player to the boss trigger at
          `z = -53`, past the doorway. State transitions were all correct; nobody had ever walked the
          floor. Fixed by letting each door's own `start_locked` decide its initial state (the boss
          room's now starts open) and adding `dungeon_traversal_test.tscn`, which drives the body with
          `move_and_slide` end to end instead of teleporting.
        - `InteractionPrompt` (`scripts/ui/interaction_prompt.gd`) — bottom-centre contextual strip,
          `[E]` keycap tinted apart from the label. One per scene, found through a group, so it dies
          with the scene and cannot leave a stale prompt after a transition. Prompts are owned: only the
          node that raised one may clear it, so two overlapping interactables cannot blank each other.
          `DungeonGate` and `DungeonExit` use it; their world `Label3D` remains as a fallback for a
          scene without the UI. The static `raise()`/`clear()` helpers keep that fallback rule in one
          place rather than duplicated in each interactable.
        - `DungeonObjectiveUI` (`scripts/ui/dungeon_objective_ui.gd`) — top-left objective line. It is
          pure display: `DungeonController` owns the wording and emits `objective_changed`. Not a quest
          system. Text runs "Avanza nel dungeon" → "Elimina i nemici: N rimasti" (singular at 1) →
          "Camera completata - Procedi" → "Camera completata - Raggiungi la Boss Room" → "Sconfiggi il
          Boss" → "Dungeon completato", with "Sei morto" on a failed run.
        - `RoomController.remaining_enemies_changed(room, remaining)` — emitted on arming and on each
          death, so the UI never polls. No manager was introduced.
        - Door feedback: an unlocked door now also glows and raises a bobbing marker above the doorway,
          so the way on is readable across a room. Locked doors are unchanged — closed, red, collider
          live. Doors that open automatically on a room clear still do so; nothing became a manual
          interaction.
        - Automated validation `res://tests/dungeon/dungeon_traversal_test.tscn` — **36/36 PASS**:
          the gate prompt appearing, hiding and clearing on use; prompt ownership; walking the start
          room, both combat rooms and the corridors on foot; the enemy counter and every objective
          string; each door's collider actually going away; the corridor to the boss room being clear;
          the boss room arming on arrival; backtracking through cleared rooms without re-arming them;
          the boss room's seal holding mid-fight; and the exit prompt once the run is done.
        - Regression: combo 10/10, dodge 18/18, enemy 22/22, enemy polish 17/17, dungeon suite 31/31,
          loop 34/34, traversal 36/36, boss 33/33, real two-run flow 32/32 — **233/233**. Three
          pre-existing assertions were updated to the new intended behavior: the gate and exit prompts
          now assert the on-screen UI rather than the world label, and the boss room's door is expected
          to start open.

- Godot 4.7.x project created
- Git repository configured
- Claude Code configured
- Godot MCP installed / verified
- `Main.tscn` created
- Project starts successfully
- Repository folder structure created
- `CLAUDE.md` created
- Documentation files created
- **M0 — Project Foundation** (Completed)
- **M1 — Player Controller** (Completed)
- **M2 — Basic Combat** (Completed). Exit criteria verified:
    - Attack registers on stationary dummy — combo test #1 (dmg = 20)
    - Combo chains within window, resets outside — combo tests #2, #3, #6 (Attack 1+2 = 45, full combo = 80, two Attack 1s across `combo_reset_time` = 40)
    - Hitboxes activate only during attack frames — dodge test #15 (post-cancel `active=false, monitoring=false`) + combo test #7 (single swing hits exactly once)
    - Damage values match expected — combo tests #1–#4 (20 / 25 / 35 per step)
    - Death transition clean, no orphan nodes / errors — dummy topple + collision disable on `died`; Player `HealthComponent.died` fires cleanly, no crash. Player-side death *reaction* (input lockout) deferred as polish, not blocking.
    - Additional M2.3 deliverables also verified: dodge direction / diagonals normalized / backstep / direction latch / wall collision / cooldown; i-frame timing + damage gating; per-step attack cancel windows (0.0 / 0.35 / 0.6); hitbox cleanup on cancel; combo state reset by dodge; spam-Space state integrity.
    - Automated validation: `attack_test.tscn` 10/10 PASS, `dodge_test.tscn` 18/18 PASS, Main.tscn 300 frames zero ERROR/WARNING/Failed/Parse Error/SCRIPT ERROR.
- **M2 progress — Combat Foundation**:
    - `HealthComponent`, `Hitbox`, `Hurtbox` reusable components under `scripts/combat/`
    - Damage pipeline: `Hitbox.area_entered` → `Hurtbox.receive_hit` → `HealthComponent.receive_damage`
    - Training dummy with sibling `HealthComponent`, `Hurtbox`, on-death disable + topple tween. No AI.
- **M2 progress — 3-Step Light Combo**:
    - `AttackStep` Resource (`scripts/combat/attack_step.gd`) — data-only, per-step tuning
    - Player exports `combo_steps: Array[AttackStep]` and `combo_reset_time`
    - 3 combo steps as inline sub-resources in `player.tscn`
    - Attack 1: dmg 20, 0.12 / 0.12 / 0.22
    - Attack 2: dmg 25, 0.14 / 0.14 / 0.24
    - Attack 3: dmg 35, 0.18 / 0.16 / 0.32
    - Single-slot input buffer, spam bounded to next step, combo termination after Attack 3, `combo_reset_time` = 0.8
    - Per-step aim orientation, per-step debug color, `VisualRoot.rotation:z` tween per step (bigger tilt on Attack 3)
    - `Hitbox.set_debug_color()` swaps material tint per swing; material duplicated on `_ready` for per-instance state
- **M2 progress — Dodge, i-Frames, Attack Cancel Windows** (M2.3):
    - Input action `dodge = Space` in `project.godot`
    - Player exports: `dodge_duration = 0.35`, `dodge_speed = 11.5`, `invulnerability_start = 0.06`, `invulnerability_end = 0.24`, `dodge_cooldown = 0.15`, `dodge_visual_tilt_degrees = -15`
    - Dodge direction: camera-relative on XZ when movement input present, backstep along `-VisualRoot.forward` when no input; diagonals normalized via `Input.get_vector`
    - Dodge uses `move_and_slide` with `dodge_direction * dodge_speed` — respects world collisions, no teleport, no wall clipping
    - Direction latched at dodge start; cannot be changed mid-dodge; cannot restart another dodge until current + cooldown finish
    - Player `Hurtbox` extended with `is_invulnerable` flag + `set_invulnerable(value)`; `receive_hit` ignores damage while invulnerable — no dodge-specific logic in `HealthComponent`
    - i-frame window driven by `Player._tick_dodge`: enables `Hurtbox.set_invulnerable(true)` when `_dodge_elapsed ∈ [invulnerability_start, invulnerability_end)`, disables otherwise, ensures cleanup on `_end_dodge`
    - `AttackStep.dodge_cancel_recovery_fraction` — per-step fraction of recovery after which dodge can cancel the attack
        - Attack 1: 0.0 (immediate on recovery)
        - Attack 2: 0.35
        - Attack 3: 0.6
    - `Player._in_cancel_window()` gates dodge input during attacks. Startup and Active always block dodge. Recovery admits dodge once `_recovery_elapsed >= recovery * fraction`
    - `Player._cancel_current_attack()` deactivates any active Hitbox, resets `_attack_state`, `_attack_timer`, `_recovery_elapsed`, `_combo_index`, `_queued_next`, `_idle_since_step_ended`, `_current_step` — no dangling active hitbox after cancel
    - `_start_dodge()` also resets combo state (`_combo_index = 0`, `_queued_next = false`) so next attack after any dodge starts fresh at Attack 1
    - `VisualRoot.rotation:x` tween lean forward during dodge for prototype visual feedback (kills any conflicting attack tween)
    - Player `HealthComponent` + `Hurtbox` added to `player.tscn`. Collision layers:
        - Layer 8: player-dealt hitboxes (Player AttackHitbox)
        - Layer 16: enemy hurtboxes (Dummy Hurtbox)
        - Layer 32: enemy-dealt hitboxes (test-only debug damage zone)
        - Layer 64: player hurtboxes (Player Hurtbox)
        - Player AttackHitbox: layer 8, mask 16. Dummy Hurtbox: layer 16, mask 0. Player Hurtbox: layer 64, mask 0. Debug damage zone: layer 32, mask 64.
    - Debug damage zone in `test_world.tscn` — Area3D + `tests/combat/debug_damage_zone.gd`, ticks damage every 0.5s on overlapping Hurtboxes, layer 32 mask 64, clearly marked as prototype/test object; only damages Player (not dummies)
    - `_unhandled_input` on Player consumes the `dodge` action and calls `_on_dodge_pressed`
- **M3 — Enemy Foundation** (Completed). Exit criteria verified:
    - *One concrete enemy variant instantiated from a Resource works end-to-end* — `BasicMeleeEnemy`
      reads its tuning from `resources/enemies/basic_melee_enemy_stats.tres` (`EnemyStats`, defined in
      `scripts/enemies/enemy_stats.gd`). Enemy test #21 asserts the asset is wired, that the runtime
      fields are seeded from it, and that writing an instance field does not mutate the shared
      definition.
    - *Transitions Idle → Detect → Chase → Attack → (Damaged) → Dead run cleanly* — enemy suite 22/22
      plus an 18s scripted encounter that covered CHASE, REPOSITION, ATTACK and DEAD across instances.
    - *Multiple enemy instances coexist without cross-talk or shared-state bugs* — per-instance body
      materials and `HealthComponent`s confirmed distinct objects; damaging one enemy left the other
      two at full health (65 / 100 / 100).
    - *Zero runtime errors during a combat encounter with 3+ enemies* — 18s encounter with three
      engaged enemies, zero engine errors; `Main.tscn` 600 frames clean.
    - Deliverables: enemy base architecture data-driven via `EnemyStats`; idle; player detection;
      chase; basic attack; damage reception through the M2 pipeline; death with a drop hook stub
      (`enemy_died` signal carrying the enemy — nothing subscribes yet, loot lands in M7).
    - Architecture: the Resource is a definition, never runtime state. The enemy copies its values
      into its own fields on `_ready()`, so debug tweaks and future buffs mutate the instance and the
      shared `.tres` stays untouched. Only genuinely per-instance values stay `@export` on the node:
      `combat_angle_offset_degrees`, `initial_attack_delay`, `attack_cooldown_variation`.
    - Final validation: combo 10/10, dodge 18/18, enemy 22/22, enemy polish 17/17 — **67/67**;
      `--check-only` clean across `scripts/` and `tests/`; `Main.tscn` 600 frames zero ERROR /
      WARNING / Failed / Parse Error / SCRIPT ERROR.
    - Known non-blocking observations, left unfixed for want of profiling evidence:
      `_has_line_of_sight()` allocates per call on the paths that reach it (only when an enemy is in
      range, facing, off cooldown *and* blocked); `_hit_flash()` tweens overlap during a fast combo,
      visual only. `Orphan StringName: servers` at shutdown is vanilla engine noise.
First iteration delivered: `BasicMeleeEnemy` scene + local enum state machine (IDLE / CHASE / ATTACK / DEAD), player detection via distance + `player` group, chase via `NavigationAgent3D` with periodic target updates, telegraphed melee attack that flows through the existing `Hitbox` / `Hurtbox` / `HealthComponent` pipeline, hit-flash feedback, death state that disables body/hurtbox/hitbox and topples the visual. Test world updated with `NavigationRegion3D` + 3 concrete enemies + navigation-obstacle wall.

    M3.1 deliverable status:

- enemy base scene — implemented
- basic state logic (IDLE / CHASE / ATTACK / DEAD enum) — implemented
- detection (with `detection_range` / `lose_target_range` hysteresis) — implemented
- navigation (`NavigationAgent3D` + baked `NavigationMesh`, obstacle detour confirmed) — implemented
- chase — implemented
- melee attack (STARTUP / ACTIVE / RECOVERY + cooldown) — implemented
- player damage (via Hitbox -> Hurtbox -> HealthComponent) — implemented
- hit reaction (visual squash only, no stagger) — implemented
- death — implemented

    M3.2 deliverable status (verified by `enemy_polish_test.tscn`, 17/17):

- local avoidance — implemented (NavigationAgent3D RVO, no second navigation system)
- enemy spacing — implemented (`preferred`/`minimum_combat_distance` + `enemy_spacing_radius`)
- reposition — implemented (`REPOSITION` state with timeout + re-entry block)
- facing refinement — implemented (per-state turn rates, `max_attack_facing_angle` gate)
- attack telegraph refinement — implemented (per-phase scale + albedo, per-instance material)
- aggro refinement — implemented (`lose_target_delay`)
- multi-enemy combat polish — implemented (per-instance approach angle + attack desync)
- **M3 progress — Enemy Foundation, M3.1 Basic Melee Enemy**:
    - `scripts/enemies/basic_melee_enemy.gd` (`class_name BasicMeleeEnemy`) — local enum state machine `State { IDLE, CHASE, ATTACK, DEAD }` and `AttackPhase { NONE, STARTUP, ACTIVE, RECOVERY }`. No generic StateMachine framework; no `EnemyManager` / `AIManager` singleton.
    - `scenes/enemies/basic_melee_enemy.tscn` — `CharacterBody3D` root + `CollisionShape3D` + `VisualRoot` (mesh + `AttackOrigin` + `Hitbox`) + `NavigationAgent3D` + `HealthComponent` + `Hurtbox`. All combat components reused from M2 (no duplication).
    - Player detection: `distance_to(player.global_position) < detection_range`; Player added to group `player`; enemy caches the reference lazily via `get_tree().get_first_node_in_group("player")` — no per-frame tree scan.
    - Hysteresis: separate `detection_range` (10) and `lose_target_range` (14) prevent oscillation at the edge.
    - Navigation: `NavigationAgent3D` with `target_position` updated every 0.2s; `get_next_path_position()` drives velocity via `move_toward` + `move_and_slide`. `NavigationRegion3D` in test world bakes `NavigationMesh` from static colliders on `_ready`. Nav test confirms an enemy behind a wall from the player pathfinds sideways rather than stalling against geometry (2.23u sideways displacement over 3s, final z crossed the wall front).
    - Chase rotation: `VisualRoot` yaws toward movement direction at `rotation_speed` rad/s — no snap.
    - Attack: on entering `attack_range`, enemy snaps `VisualRoot` yaw once to face the player and enters `STARTUP`. Telegraph = short `VisualRoot.scale` tween up during startup. `Hitbox.activate()` only during `ACTIVE`. `Hitbox.deactivate()` on transition to `RECOVERY`. After recovery, `attack_cooldown` (0.4s) blocks re-entry to `ATTACK` and enemy returns to `CHASE`.
    - Damage: enemy → player exclusively via `Hitbox` → `Hurtbox` → `HealthComponent`. No `player.take_damage()` shortcuts. Player's dodge i-frames automatically block damage through the existing `Hurtbox.is_invulnerable` gate.
    - Hit feedback: enemy `mesh_instance.scale` pulses on `health_changed` when HP decreases. No stagger system, no interruption of movement/nav.
    - Death: on `HealthComponent.died` → state `DEAD`, `velocity = 0`, hitbox deactivated, body collision + hurtbox collision + hurtbox monitorable all disabled via `call_deferred`, `VisualRoot` topples via short rotation tween. Dead enemy skips `_physics_process`. Verified no further attacks / no damage post-death.
    - Player integration: Player added to `player` group in `_ready`; existing `HealthComponent` + `Hurtbox` from M2.3 reused unchanged; no HUD.
    - Collision layers (documented):
        - Layer 1: world + physical bodies (floor, walls, Player body, Enemy body, Dummy body)
        - Layer 8: player-dealt hitbox (Player `AttackHitbox`, mask 16)
        - Layer 16: enemy-receiving hurtboxes (Dummy `Hurtbox`, Enemy `Hurtbox`; mask 0)
        - Layer 32: enemy-dealt hitbox + debug damage zone (Enemy `Hitbox`, DebugDamageZone; mask 64)
        - Layer 64: player-receiving hurtbox (Player `Hurtbox`; mask 0)
    - Test world (`scenes/core/test_world.tscn`) updated: `NavigationRegion3D` wraps floor + walls + big wall (`8x3x1` at z=10); 3 `BasicMeleeEnemy` instances at distinct positions; existing 2 `TrainingDummy` + `DebugDamageZone` preserved (dummy on layer 16 still hit by player attacks; debug zone on layer 32 targets layer 64 so it damages Player without affecting dummies). `scripts/core/test_world.gd` synchronously bakes the nav mesh in `_ready`.
    - NavigationMesh tuning: `cell_size = 0.25`, `cell_height = 0.25`, `agent_radius = 0.5`, `agent_height = 2.0`, `agent_max_climb = 0.5`, `geometry_parsed_geometry_type = 1` (STATIC_COLLIDERS). Avoids the RenderingServer parse + agent-value rounding warnings that fired with defaults.
    - Automated headless validation `res://tests/enemies/enemy_test.tscn` — **20/20 PASS**:
        1. Enemy IDLE when player > `detection_range`
        2. Enemy CHASE when player < `detection_range`, and actually closes distance (5.95 -> 3.97 in 0.6s)
        3. Enemy ATTACK when player < `attack_range`
        4. Attack phase gating: hitbox off during STARTUP + telegraph visible; hitbox on during ACTIVE; hitbox off during RECOVERY
        5. Enemy deals exactly 15 damage to Player (`100 -> 85`)
        6. Player dodge i-frame during ACTIVE avoids enemy damage
        7. Attack cooldown: enemy returns to CHASE with cooldown active; re-attacks after cooldown expires
        8. Real CHASE -> IDLE transition when the *player* moves past `lose_target_range`
        9. Player Attack 1 damages enemy 20
        10. Player full combo damages enemy 80
        11. Enemy dies (`state = DEAD`, hitbox off, body collision disabled, hurtbox not monitorable, `velocity == 0`)
        12. Dead enemy in attack range deals no damage and stays DEAD
        13. 3 concurrently spawned enemies all reach CHASE independently
        14. Navigation around big wall (`2.27u` sideways, crosses wall Z from 13.65 to 4.28 over 3s)
        15. Mistimed dodge (too early / too late) still takes the full 15 damage — i-frame window measured with `dodge_speed = 0` so displacement cannot mask it
        16. Player stepping out of the swing during STARTUP takes no damage (attack does not home)
        17. Enemy stays committed for the full RECOVERY (phase + state hold, hitbox off throughout)
        18. Enemy returns to CHASE when the player leaves `attack_range` mid-attack
        19. Enemy takes exactly one hit per player swing (1 `health_changed` emission, 20 damage)
        20. Hit feedback squash plays (`scale.y` 0.875) and settles back to rest
    - Engine-level checks on `test_world.tscn`: baked `NavigationMesh` has 53 vertices / 50 polygons, navigation map active with 1 region; `NavigationServer3D.map_get_path()` from Enemy1 `(0, 16)` to Player `(0, 4)` returns a 7-point path routing around `BigWall` at `x = -4.5` (wall spans `x` -4..4) — confirmed detour, not a straight line through geometry.
    - Regression: combo suite 10/10 PASS, dodge suite 18/18 PASS, `Main.tscn` 300 frames verbose scan zero ERROR / WARNING / Failed / Parse Error / SCRIPT ERROR, `--check-only` parse of every `.gd` under `scripts/` and `tests/` clean.
    - Validation engine note: this pass was executed on **Godot 4.5.stable** headless (no 4.7 binary available in the CI container). The project declares `config/features = ("4.7", "Forward Plus")`; it imported and ran without complaint, but 4.7-specific behavior is unverified.
- **M3.2 — Enemy Combat Polish**. Refinement of M3.1, not a rewrite: the enum state
  machine, the Hitbox/Hurtbox/HealthComponent pipeline and NavigationAgent3D pathfinding
  are unchanged in kind.
    - New state `REPOSITION` — enum is now `IDLE / CHASE / REPOSITION / ATTACK / DEAD`.
      Entered from CHASE when the enemy is inside `minimum_combat_distance` or in range but
      mis-facing. It paths to its combat slot, turns to face the player, and leaves for
      ATTACK once distance + facing + line of sight + cooldown all pass. `reposition_timeout`
      (1.5s) hands control back to CHASE and `reposition_cooldown` (0.6s) blocks immediate
      re-entry, so the two states cannot ping-pong.
    - Local avoidance via `NavigationAgent3D` RVO: `avoidance_enabled = true`, `radius` driven
      by `enemy_spacing_radius` (0.8), `neighbor_distance` 4.0, `max_neighbors` 6,
      `time_horizon_agents` 1.0, `time_horizon_obstacles` 0.5, `max_speed` = `movement_speed`,
      `use_3d_avoidance` false. Desired velocity goes through `set_velocity()`; the move happens
      in the `velocity_computed` callback. A 10-frame watchdog falls back to direct motion if the
      agent never joins a navigation map, so an enemy can never freeze waiting for a callback.
    - **Navigation fix:** the baked navmesh surface sits 0.5 above the walkable floor, so raw path
      points came back 0.5 above the agent and waypoint advancement compared against that vertical
      gap. `path_height_offset = 0.5` puts path points on the agent plane; `path_desired_distance`
      0.4, `target_desired_distance` 0.25. Before this, a reposition target 0.7 away was reported
      unreachable and the enemy stood still.
    - Spacing: CHASE stops advancing once inside `preferred_combat_distance` (1.6) instead of
      grinding into the player. `minimum_combat_distance` 1.15.
    - Per-instance combat slots: `combat_angle_offset_degrees` biases each instance's approach
      bearing, so instances converge on different points on the ring rather than one point.
    - Facing per state — CHASE: toward movement direction at `rotation_speed`. REPOSITION: toward
      the player at `rotation_speed`. ATTACK STARTUP: toward the player at
      `rotation_speed * attack_startup_turn_fraction` (0.3). ATTACK ACTIVE and RECOVERY: no
      rotation at all. `max_attack_facing_angle` (25 deg) gates attack entry. The M3.1 snap-to-player
      on attack entry is gone.
    - Telegraph per phase: STARTUP rears up (`scale` 0.88/1.22/0.88) and the body tints to
      `telegraph_color`; ACTIVE squashes forward and tints to `active_color` with the hitbox debug
      mesh visible; RECOVERY returns both to rest. The body material is duplicated per instance in
      `_ready` — shared sub-resources would otherwise make every enemy telegraph in unison.
    - Line of sight: a ray on `line_of_sight_mask` (world layer only) gates attack entry, so an
      enemy cannot swing through a wall. Evaluated only after the cheap distance and cooldown
      checks fail-fast, never unconditionally per frame.
    - Aggro: `lose_target_delay` (1.0s) must elapse beyond `lose_target_range` before the target is
      dropped, so a momentary distance spike no longer ends the fight.
    - Attack desync: `initial_attack_delay` and `attack_cooldown_variation`, both per-instance and
      deterministic (no RNG). Test world uses 0.0 / 0.3 / 0.6 and 0.0 / 0.15 / 0.3.
    - Range coherence (asserted, not assumed): hitbox covers 0.4–2.0 in front of the enemy;
      `attack_range` 1.8 <= 2.0 and `minimum_combat_distance` 1.15 >= 0.4, with
      `preferred_combat_distance` inside the band.
    - Collision layers split so physics intent is explicit — see the table below. Correction to an
      earlier claim in this file and in commit 29ee6db: the camera SpringArm never collided with the
      player's own body, because `camera_rig.gd` already excludes it via `add_excluded_object()`.
      What the split actually changed is that the SpringArm (mask 1) no longer collides with *enemy*
      bodies, which moved from layer 1 to layer 4. Enemies are not geometry, so the camera pushing
      in for them was not required by GAME_DESIGN's camera-collision rule.
    - Death: `_physics_process` returns early, and `nav_agent.avoidance_enabled` is set false so a
      corpse leaves the RVO simulation and stops steering the living. Telegraph is reset instantly.
      The topple tween is death feedback, not AI facing.
    - Collision layers after M3.2:
        - Layer 1: world geometry (Floor, Wall1, Wall2, BigWall) — mask 1
        - Layer 2: Player body — mask 5 (world + enemy bodies)
        - Layer 4: Enemy + Dummy bodies — enemy mask 7 (world + player + enemies), dummy mask 1
        - Layer 8: player-dealt hitbox (Player AttackHitbox, mask 16)
        - Layer 16: enemy-receiving hurtboxes (Enemy + Dummy Hurtbox, mask 0)
        - Layer 32: enemy-dealt hitbox + DebugDamageZone (mask 64)
        - Layer 64: player-receiving hurtbox (Player Hurtbox, mask 0)
    - Test world rebuilt for the five required scenarios, still one scene with no new node types:
      `EnemySolo` (14, 4) single engagement; `EnemyTrio1/2/3` (-13, -2/1/4) two-then-three from a
      similar direction with staggered delays; `EnemyBehindWall` (0, 16) behind `BigWall`;
      `EnemyLateral` (9, 13) with a 70 deg approach bias. Dummies and DebugDamageZone preserved.
    - Automated validation `res://tests/enemies/enemy_polish_test.tscn` — **17/17 PASS**: avoidance
      configured; two enemies keep separate targets (gap 2.45) and bodies (2.26); three enemies
      spread 165 deg with 1.96 min gap; too-close enemy repositions and backs off to 1.20; reposition
      exits via timeout at 1.53s; attack gated at 140 deg then fires once aligned; startup correction
      gradual (24 deg turned, 66 deg residual); zero yaw change during ACTIVE; player sidesteps the
      swing unharmed; range/hitbox coherence incl. an edge-of-range connect; no attack through wall
      (1.70 < 1.80, phase stayed NONE); enemy never enters the wall volume; three converging enemies
      move the player 0.000; dead enemy leaves avoidance and drifts 0.000; enemies die independently;
      first-ACTIVE times 0.42 / 0.72 / 1.00 with 0.28s min gap; aggro survives a sub-delay spike.
    - Engine-level check of `test_world.tscn`: navmesh 53 verts / 50 polys, map active with 1 region;
      after dropping the player next to the trio they settle at 1.84 / 1.57 / 1.76 from the player
      with a 1.61 min pairwise gap and states `[CHASE, CHASE, ATTACK]` — spread out, not stacked, not
      swinging in unison.
    - M3.1 regression `enemy_test.tscn` **20/20 PASS** against the refactored enemy. Two assertions
      were updated for deliberate behavior changes: the telegraph check is now shape-agnostic (the
      startup pose rears up instead of scaling uniformly), and the aggro-drop check now waits out
      `lose_target_delay` and additionally asserts the target is *held* during the grace period.
    - Regression: combo 10/10, dodge 18/18, `Main.tscn` 360 frames zero ERROR / WARNING / Failed /
      Parse Error / SCRIPT ERROR, `--check-only` clean across `scripts/` and `tests/`.
- **M4 — Dungeon Foundation** (Completed). Exit criteria verified:
    - *Interacting with a Gate loads the dungeon scene* — proven with real `change_scene_to_file`
      calls, twice in a row, by `dungeon_flow_run.gd`.
    - *Player traverses start → combat rooms → boss room* — both full runs walked start room,
      Combat 1, Combat 2 and the boss placeholder in order, clearing each.
    - *Room transitions do not leak nodes, signals or physics bodies* — two identical loops ending
      in the same scene finished with an **identical node count (127 vs 127, delta +0) and zero
      orphan nodes**. An earlier leak (a coroutine stranded by an awaited `SceneTreeTimer`) was
      found and fixed during M4.2; the node-count assertion now guards against regressions.
    - *Combat rooms gate progression until cleared* — each room locks its exit on arming and only
      opens when its last enemy dies; the M4.1 suite proves the locked door physically blocks the
      player with a `test_move()` collision probe, and that killing one of two leaves it shut.
    - Deliverables: gate entry, dungeon scene container, start room, combat rooms populated from M3
      enemies, boss room placeholder, room transitions via trigger volumes and doors. Plus M4.2's
      exit portal, fade transitions, reusable gate target and death/restart.
    - Final validation: combo 10/10, dodge 18/18, enemy 22/22, enemy polish 17/17, dungeon suite
      31/31, loop 34/34, real two-run flow 24/24 — **156/156**. `--check-only` clean across
      `scripts/` and `tests/`; `Main.tscn` and `dungeon_test.tscn` each 600 verbose frames with zero
      ERROR / WARNING / Failed / Parse Error / SCRIPT ERROR and no leaked instances.
    - Carried into M5, non-blocking: the layout is a functional grey-box, not shaped for play, and
      the return lands the player at the test world's default spawn rather than back at the gate —
      both waiting on a real hub.

M4.1 delivered: a static, deterministic dungeon that runs end to end — Gate in the test world,
start room, two combat rooms gated by locking doors, a boss-room placeholder, and dungeon
completion. No procedural generation, no real boss, no loot/XP/shadow systems.

M4.1 deliverable status (verified by `dungeon_test_suite.tscn`, 31/31):

- dungeon gate — implemented
- dungeon scene — implemented
- start room — implemented
- room controller — implemented
- combat rooms — implemented
- door locking — implemented
- room clearing — implemented
- sequential progression — implemented
- boss room placeholder — implemented
- dungeon completion foundation — implemented

M4.2 delivered: the loop closes. Fade transitions both ways, an exit portal that only wakes on
completion, the return trip to the test world, and a minimal death/restart.

M4.2 deliverable status (verified by `dungeon_loop_test.tscn` 34/34 and the real-scene-change run
`dungeon_flow_run.gd` 16/16):

- dungeon completion — implemented
- exit portal — implemented
- return transition — implemented
- reusable gate target — implemented
- scene fade transition — implemented
- dungeon death/restart flow — implemented
- full dungeon loop — implemented
- **M4 progress — M4.1 Dungeon Foundation**:
    - `scripts/dungeon/dungeon_controller.gd` (`DungeonController`) — dungeon state
      `NOT_STARTED / IN_PROGRESS / COMPLETED`, room order taken from tree order under its `Rooms`
      container, completion when the last room reports cleared. No combat, AI, health or door
      details. No global manager of any kind.
    - `scripts/dungeon/room_controller.gd` (`RoomController`) — one room's lifecycle:
      `IDLE / ACTIVE / CLEARED`, arms on player entry, locks its exit, wakes its own enemies,
      counts their deaths, unlocks and emits. A cleared room never re-arms, so backtracking is
      safe. It only ever touches its own subtree — no global enemy search, no per-frame scan.
    - `scripts/dungeon/dungeon_door.gd` (`DungeonDoor`) — `lock()` / `unlock()` / `is_locked()`.
      Locked: collider on, slab down, red. Unlocked: collider off, slab raised by tween, green.
      It knows nothing above itself.
    - `scripts/dungeon/dungeon_gate.gd` (`DungeonGate`) — Area3D that tracks the player, shows a
      `Label3D` prompt, and answers `interact` only while the player is inside. `activate()` is
      public so a future scene router (M4.2) can drive it; `change_scene_on_activate` lets it
      announce without switching scenes.
    - Enemy interface added, AI untouched: `BasicMeleeEnemy.set_combat_enabled(bool)` plus a
      `combat_enabled` export. While false `_physics_process` applies gravity and returns —
      no perception, no chase, no attack, no navigation, and the agent leaves the avoidance
      simulation. Rooms park their enemies in `_ready()` so a room can never ship with live ones.
    - Rooms subscribe to the enemy `enemy_died` drop hook added in M3, which is its first consumer.
      `BasicMeleeEnemy` still knows nothing about rooms.
    - **Bug found and fixed during the build:** the `NavigationMesh` is a sub-resource of
      `combat_room.tscn`, so both instances of that scene shared one object and the second bake
      overwrote the first — room 2's obstacles were never carved. `RoomController` now duplicates
      the navmesh before baking. Same class of shared-sub-resource bug as the enemy body material
      in M3.2. Verified: room 1 bakes 4 polygons, room 2 bakes 33, and a path straight through
      room 2's obstacle deviates 1.75 laterally while an open lane stays at 0.00.
    - Navigation: one `NavigationRegion3D` per room, baked by that room. Rooms are walled off, so
      each navmesh is an island and no enemy can path out of its own room. No runtime rebaking
      beyond the one bake per room at load.
    - Input map: `interact` = E added to `project.godot`.
    - Layout (static, grey-box): Start (0) → corridor → Combat 1 (z −18, 2 enemies) → corridor →
      Combat 2 (z −38, 3 enemies + 2 obstacles) → corridor → Boss placeholder (z −59, 1 clearly
      labelled `BasicMeleeEnemy`). The boss room's door seals behind the player on entry and opens
      on clear.
    - Collision layers reuse the M3 scheme: doors, floors, walls and corridors on world layer 1;
      room entry triggers are layer 0 / mask 2 (player body only); the Gate likewise. No new layers.
    - Test world: `DungeonGate` at (0, −16), 19.1 units from the nearest testing enemy — outside
      both `detection_range` (10) and `lose_target_range` (14), so the player is not harassed while
      using it.
    - Automated validation `res://tests/dungeon/dungeon_test_suite.tscn` — **31/31 PASS**, covering
      gate in/out of range, spawn, dormant enemies, one-shot room arming, door lock/unlock with a
      real `test_move()` collision probe, partial kills holding the door, backtracking, room 2 on
      the same controller, obstacle navigation, boss placeholder, `COMPLETED` firing once, the
      visible DUNGEON COMPLETE label and the cleared-room ordering.
    - Regression: combo 10/10, dodge 18/18, enemy 22/22, enemy polish 17/17 — with the dungeon suite,
      **98/98**. `--check-only` clean; `Main.tscn` and `dungeon_test.tscn` each 480 frames verbose
      with zero ERROR / WARNING / Failed / Parse Error / SCRIPT ERROR.
- **M4.2 — Dungeon Completion & Transition Polish**. Refinement of M4.1; the dungeon system itself
  was not rewritten.
    - `scripts/ui/scene_transition.gd` + `scenes/ui/scene_transition.tscn` (`SceneTransition`) — a
      per-scene fade curtain on a `CanvasLayer`, **not** an autoload. `fade_duration` 0.35,
      `fade_in_on_ready` so an incoming transition lands softly. `transition_to_scene()` and
      `reload_current_scene()` both refuse while `is_busy()`, and `_busy` deliberately stays latched
      after a hand-off so nothing can queue a second one on the way out. Callers find it through the
      `scene_transition` group, so a scene drops it in with no rewiring.
    - `scripts/dungeon/dungeon_exit.gd` + `scenes/dungeons/components/dungeon_exit.tscn`
      (`DungeonExit`) — starts dead: `monitoring` off, collider disabled, dimmed and squashed. The
      controller switches it on at completion, which tints and emits it and scales it up by tween.
      `activate()` refuses unless it is live, the player is inside, it has not been used, and no
      transition is running.
    - `DungeonGate` — `target_scene` was already an `@export_file`; added `prompt_text` for reuse, a
      `_used` latch and a busy-transition check, and it now hands off to `SceneTransition` instead of
      calling `change_scene_to_file` directly. Duplicating the gate for another dungeon needs no code.
    - `DungeonController` — gained `FAILED`, `run_failed`, the exit portal hookup, banner timing and
      the death/restart flow. A single `_run_ended` latch guards everything: completion, death,
      restart and room events all check it, so no path can fire twice or interleave.
    - Player death: the controller connects to the player's `HealthComponent.died` (one group lookup
      at startup), suspends every room, kills the exit portal, shows `YOU DIED`, then reloads the
      dungeon after `death_restart_delay` (1.2s). `RoomController.suspend()` was added for this — it
      stops the trigger and parks the enemies, which is room lifecycle, not a new responsibility.
      Health resets on its own: `HealthComponent._ready()` already sets current to max.
    - **Bug found and fixed:** `_show_status()` and `_restart_after_delay()` originally awaited
      `SceneTreeTimer`s. When the player left the dungeon before the completion banner's 1.8s timer
      fired, the coroutine was stranded holding a reference to the label, and Godot reported
      `ObjectDB instances leaked at exit`. Both now use node-bound tweens, which die with the node.
      Isolated by bisecting: neither scene alone nor a single transition nor a single reload leaked,
      only the full loop.
    - Input: `interact` = E, unchanged. Gate and exit each gate on their own `_player_in_range`, so
      only the area the player is actually standing in can answer.
    - Automated validation `res://tests/dungeon/dungeon_loop_test.tscn` — **34/34 PASS**: fade in and
      out, gate target, interact refused outside, ten spammed activations producing exactly one
      transition, exit dead before completion and refusing interact from inside it, the three rooms,
      COMPLETED once, banner shown then auto-hidden while the portal stays live, exit prompt, one
      exit transition to the right target, death after completion queuing nothing, a clean second
      run (6 enemies, rooms IDLE, doors locked, exit dead), `YOU DIED`, `FAILED` once, every room
      suspended, a room refusing to arm after death, exactly one reload after the delay, a second
      death during the restart ignored, and full health on the restarted run.
    - Real-scene-change validation `res://tests/dungeon/dungeon_flow_run.gd` — **16/16 PASS**. It
      swaps the running scene, so it is a SceneTree script rather than a test scene:
      `godot --headless --path . --script res://tests/dungeon/dungeon_flow_run.gd`. It walks the
      whole loop for real — test world → gate → dungeon → three rooms → COMPLETE → exit → test world
      → second run → death → reload — and asserts the scene actually changed each time, including a
      fresh scene instance after the restart. Note for future test authors: it waits on real time,
      not frame counts; headless runs frames far faster than wall clock, and frame counting silently
      skipped past `death_restart_delay` the first time.
    - Regression: combo 10/10, dodge 18/18, enemy 22/22, enemy polish 17/17, dungeon suite 31/31,
      loop 34/34, real flow 16/16 — **148/148**. `--check-only` clean; `Main.tscn` and
      `dungeon_test.tscn` each 480 verbose frames with zero ERROR / WARNING / Failed / Parse Error /
      SCRIPT ERROR and no leaked instances.
- Automated headless validation:
    - **Combo test** `res://tests/combat/attack_test.tscn` — 10/10 PASS (single click, chained combo, spam bounding, reset time, per-swing dedup, out-of-range, multi-target, orientation)
    - **Dodge test** `res://tests/combat/dodge_test.tscn` — 18/18 PASS:
        1. W+Space → forward dodge direction
        2. W+D diagonal → normalized dodge direction
        3. Space with no input → backstep along `+VisualRoot.z`
        4. Direction latched mid-dodge (changing input mid-dodge has no effect)
        5. Dodge blocked by wall (`move_and_slide` collision honored)
        6. Second dodge during current dodge is blocked (direction unchanged)
        7. Cooldown: mid-cooldown blocked, past-cooldown allowed
        8. i-frame timing: false before 0.06, true in [0.06, 0.24), false after
        9. Damage ignored during i-frames
        10. Damage applied outside i-frames (25 damage → 100 → 75)
        11. Attack 1 not cancelable during Startup / Active
        12. Attack 1 cancelable during Recovery (fraction 0.0)
        13. Attack 2 cancel window (blocked early, allowed after 35% of recovery)
        14. Attack 3 cancel window (blocked early, allowed after 60% of recovery)
        15. `attack_hitbox.is_active()` and `.monitoring` both false after cancel
        16. `_queued_next` cleared and `_combo_index` reset to 0 on dodge cancel
        17. `_combo_index == 0` after dodge + cooldown (next attack starts at Attack 1)
        18. Spam Space (20 rapid calls) leaves player state valid; subsequent single dodge works
    - `godot --headless --verbose --path . --quit-after 180` on `Main.tscn` — no ERROR / WARNING / Failed / Parse Error / SCRIPT ERROR

---

## In Progress

Nothing in flight. M0–M9 are complete and the slice is at RC1; **M10 has not been started.**

One definition stays deliberately open: the **definitive art direction**, which is decided at M13
and written into `GAME_DESIGN.md` then. Everything else that was open during the prototype phase —
camera, movement, aim, combat feel, progression, loot and equipment, the shadow mechanic, the run
loop — is settled and recorded.

`GAME_DESIGN.md` and `ARCHITECTURE.md` are living documents that grow with each milestone; that is
their normal condition, not an outstanding task.

---

## Todo

Carried forward from the prototype phase. Each item names where it now belongs.

- **Manual editor playtest of the whole slice** — feel-tuning by hand, which no headless run can
  do. Not blocking, and the one kind of validation the automated suites cannot replace.
- **Playtest-tune the enemy parameters** in `resources/enemies/basic_melee_enemy.tres`. The
  M9.2 baseline says the numbers are in target on paper; how they feel is a different question.
- **Player-side death reaction** — input lockout and a visual state. Folds into hit reactions and
  stagger at **M11**.
- **Dungeon layout pass.** The grey-box is functional, not shaped for play. Belongs with the
  modular environment kits at **M15** and the room types at **M18**.
- **Return the player to the gate on exit**, rather than to the hub's default spawn. Small, and
  best done alongside the hub build-out at **M15**.
- **More enemy archetypes.** Now a deliverable of the archetype framework at **M12**, rather than
  one-off `EnemyData` assets.

---

## Future Work

Findings and decisions from the prototype phase that were deliberately left alone. Several are now
**scheduled** by the M10–M20 roadmap; each note says where. Nothing here is started.

- **Enemies never target the summoned shadow.** It can be damaged and killed — the masks allow it
  and the boss does hit it — but normal enemies aim only at the player, so in a measured room the
  shadow took **0 damage in 60 seconds**. → **M12**, which makes target selection between the
  player and the shadow an explicit deliverable.
- **The shadow's offensive share.** At Lv.1 it is ~19% of the player's peak DPS against an
  indicative ~50%. Measured in practice the gap is much smaller, because the shadow fights
  continuously while the player spends most of a fight repositioning — it clears a two-enemy room
  alone in 26s. Left alone: both inequalities the design asks for hold, and closing the gap on
  paper would make the shadow rival the player.
- **Boss fight length.** 120s measured with a cautious defender. Reaching the top of the
  indicative band would need either far more health or a faster player, and neither is a change
  worth making blind.
- **A save system.** → **M19**. Progression is in memory for the length of a session, by design
  since M6.
- **No export preset.** `export_presets.cfg` does not exist and the roadmap never asked for a
  build, so RC1 is a scope statement rather than an artifact. Adding one means choosing a target
  platform, which is the user's call.
- **INT does nothing yet.** → **M17**, when skills arrive to read the ability power it scales.
  As designed in M6.2.
- **The shadow has no art of its own.** → **M13.7**, as a material and shader pass over the source
  enemy's mesh rather than a second model. See `GAME_DESIGN.md`, *Shadow visual system*.

---

## Blocked

None
