extends SceneTree

## M12.8 — the boss framework through the whole game.
##
##   godot --headless --path . --script res://tests/core/m12_boss_run.gd
##
## Menu -> New Game -> hub (a shadow summoned) -> gate -> dungeon: rooms one and
## two, their normal melee fought with the player's real attacks, the boss
## asleep throughout -> the boss room: the encounter starts (phase 1, its bar,
## its attacks), locked on; the player and the shadow wear it down past half:
## the transition, phase 2, its attacks; the shadow lands the killing blow — one
## death, the 70/30 reward, one completion -> the exit -> hub -> a second dungeon:
## the boss fresh — phase 1, full health, clean cooldowns, no attack left over,
## its UI hidden; the player dies in the fight: the boss parks cleanly and the
## dungeon reloads it whole -> every archetype and an elite still fight as they
## did beside the boss -> leaving mid-fight: nothing of the boss survives.

const BOOT: String = "res://Main.tscn"
const HUB: String = "res://scenes/core/hub.tscn"
const DT: float = 1.0 / 60.0
const ROOM_ANCHORS: Array[Vector3] = [
	Vector3(0, 0.1, -13), Vector3(0, 0.1, -33), Vector3(0, 0.1, -53)
]
const STRIKE_RANGE: float = 1.6
const EXIT_POS: Vector3 = Vector3(0, 0.1, -65)
const ARCHETYPES: Array[String] = [
	"res://scenes/enemies/basic_melee_enemy.tscn", "res://scenes/enemies/basic_ranged_enemy.tscn",
	"res://scenes/enemies/basic_tank_enemy.tscn", "res://scenes/enemies/basic_assassin_enemy.tscn",
	"res://scenes/enemies/basic_support_enemy.tscn",
]
const ELITE: EliteModifierData = preload("res://resources/enemies/elite_standard.tres")
const BOSS_DATA: BossData = preload("res://resources/enemies/bosses/dungeon_boss_data.tres")

var _no_crits: PlayerCombatData = preload("res://resources/characters/player_combat.tres")
var _shadow_data: ShadowData = preload("res://resources/shadows/basic_melee_shadow.tres")
var _state: Node = null
var _pass: int = 0
var _fail: int = 0


func _initialize() -> void:
	_no_crits.critical_chance = 0.0
	_state = root.get_node_or_null("PlayerRuntimeState")
	_state.reset_runtime_state()
	change_scene_to_file(BOOT)
	await _pause(0.6)
	(current_scene.get_node("MainMenu") as MainMenu).press_play()
	await _pause(1.4)
	await _phase_hub()
	await _phase_into_dungeon(1)
	await _phase_rooms()
	await _phase_boss_fight()
	await _phase_exit()
	await _phase_into_dungeon(2)
	await _phase_second_boss()
	await _phase_player_death()
	await _phase_archetypes()
	await _phase_leave_mid_fight()
	print("[SUMMARY] passed=%d failed=%d" % [_pass, _fail])
	await _pause(0.3)
	quit()


# --- the hub and the gate ----------------------------------------------------------------------------------

func _phase_hub() -> void:
	var p: Player = current_scene.get_node("Player")
	var shadow: ShadowInstance = p.shadows.add_shadow(_shadow_data)
	p.shadow_summoner.summon(shadow.instance_id)
	await _pause(0.4)
	p.shadow_commander.set_mode(BasicMeleeShadow.CommandMode.FOLLOW)
	_record(current_scene.scene_file_path == HUB and p.shadow_summoner.get_active_node() != null,
		"H1) New Game: the hub, a shadow summoned to take into the dungeon")


func _phase_into_dungeon(run: int) -> void:
	var p: Player = current_scene.get_node("Player")
	var gate: DungeonGate = current_scene.get_node("DungeonGate")
	p.global_position = gate.global_position
	await _pause(0.4)
	gate.activate()
	await _pause(1.6)
	var dungeon: DungeonController = current_scene as DungeonController
	var boss: DungeonBoss = _boss(dungeon)
	_record(dungeon != null and boss != null and boss.get_state() == DungeonBoss.State.INACTIVE
			and boss.get_phase_index() == -1 and boss.data == BOSS_DATA,
		"G%d) dungeon %d: its boss is there, asleep — INACTIVE, no phase yet, on the shipped BossData" % [run, run])


# --- 105. rooms one and two, the boss asleep ---------------------------------------------------------------------

func _phase_rooms() -> void:
	var dungeon: DungeonController = current_scene as DungeonController
	var p: Player = dungeon.get_player()
	var boss: DungeonBoss = _boss(dungeon)
	p.hurtbox.set_invulnerable(true)
	var fought: bool = true
	var detail: Array[String] = []
	for i in 2:
		var room: RoomController = dungeon.get_rooms()[i]
		p.global_position = ROOM_ANCHORS[i]
		await _pause(0.6)
		var enemies: Array[RoomCombatant] = room.get_enemies()
		# The room's fight is on: its melee take the player on — those that can
		# see it from where they stand; the rest are walked up to and killed.
		var acquired: bool = await _until(func() -> bool:
			p.global_position = ROOM_ANCHORS[i]
			return enemies.any(func(e: RoomCombatant) -> bool: return (e as BasicEnemy).get_target() == p), 4.0)
		for e in enemies:
			await _kill(p, e)
		await _pause(0.5)
		fought = fought and acquired and room.is_cleared()
		detail.append("room %d: acquired=%s cleared=%s" % [i + 1, acquired, room.is_cleared()])
	_record(fought and boss.get_state() == DungeonBoss.State.INACTIVE and boss.combat.get_started_count() == 0
			and not boss.combat_enabled,
		"105) rooms one and two: their melee take the player on and die to its real attacks; the boss slept through it (%s)" % [detail])


# --- 101, 95-99. the boss fight ------------------------------------------------------------------------------------

func _phase_boss_fight() -> void:
	var dungeon: DungeonController = current_scene as DungeonController
	var p: Player = dungeon.get_player()
	var boss: DungeonBoss = _boss(dungeon)
	var bar: BossHealthBar = dungeon.get_node("BossHealthBar")
	var indicator: TargetLockIndicator = dungeon.get_node("TargetLockIndicator")
	var shadow: BasicMeleeShadow = p.shadow_summoner.get_active_node()
	var completions: Array[int] = [0]
	var deaths: Array[int] = [0]
	var phases: Array[int] = []
	var started: Array[BossAttack] = []
	var sources: Dictionary = {}
	dungeon.dungeon_completed.connect(func() -> void: completions[0] += 1)
	boss.enemy_died.connect(func(_c: RoomCombatant) -> void: deaths[0] += 1)
	boss.phase_changed.connect(func(i: int) -> void: phases.append(i))
	boss.combat.attack_started.connect(func(a: BossAttack) -> void: started.append(a))
	boss.health_component.damaged.connect(func(hit: DamageInfo) -> void:
		sources[hit.source] = sources.get(hit.source, 0) + 1)

	p.hurtbox.set_invulnerable(true)
	shadow.hurtbox.set_invulnerable(true)
	p.global_position = ROOM_ANCHORS[2]
	var woke: bool = await _until(func() -> bool: return boss.combat_enabled, 4.0)
	await _frames(2)
	_record(woke and boss.get_state() == DungeonBoss.State.INTRO and boss.get_phase_id() == &"phase_1"
			and bar.is_showing() and is_equal_approx(bar.get_ratio(), 1.0) and bar.get_phase_text() == "FASE 1"
			and dungeon.get_rooms()[2].exit_door.is_locked(),
		"101a) walking into the boss room starts the encounter: INTRO, phase_1, its bar full, the arena sealed")

	# Phase 1: it attacks from its phase 1 pool.
	await _until(func() -> bool:
		_stick(p, boss)
		return started.size() >= 3, 12.0)
	var phase_1_only: bool = started.size() >= 3 and started.all(func(a: BossAttack) -> bool:
		return BOSS_DATA.phases[0].attacks.has(a))
	_record(phase_1_only, "101b) in phase 1 it fights with its phase 1 attacks (%d started)" % started.size())

	# 95) locked on for the rest of the fight.
	_stick(p, boss)
	p.camera_rig.rotation.y = 0.0
	await _frames(2)
	_press(p, &"target_lock")
	await _frames(2)
	var locked: bool = p.targeting.get_target() == boss and indicator.get_target() == boss

	# 97) the player and the shadow wear it down past its threshold together.
	p.shadow_commander.set_mode(BasicMeleeShadow.CommandMode.AGGRESSIVE)
	shadow.global_position = boss.global_position + Vector3(1.5, 0, 0)
	shadow.set_manual_target(boss)
	boss.health_component.current_health = boss.health_component.max_health * 0.56
	var crossed: bool = await _until(func() -> bool:
		shadow.set_manual_target(boss)
		_swing(p, boss)
		return boss.is_in_transition() or boss.get_phase_index() == 1, 40.0)
	var both_hit: bool = sources.get(p, 0) > 0 and sources.get(shadow, 0) > 0
	_record(crossed and both_hit and bar.get_phase_text() == "FASE 2" and p.targeting.get_target() == boss,
		"97/101c) the player (%d hits) and the shadow (%d hits) take it past half: the transition, the bar calls phase 2, the lock holds" % [
			sources.get(p, 0), sources.get(shadow, 0)])
	var in_phase_2: bool = await _until(func() -> bool:
		_stick(p, boss)
		return boss.get_phase_index() == 1 and not boss.is_in_transition(), 4.0)
	var from: int = started.size()
	await _until(func() -> bool:
		_stick(p, boss)
		return started.size() >= from + 3, 12.0)
	var phase_2_pool: bool = started.size() >= from + 3 and started.slice(from).all(func(a: BossAttack) -> bool:
		return BOSS_DATA.phases[1].attacks.has(a))
	_record(in_phase_2 and phases == [0, 1] and phase_2_pool and locked and p.targeting.get_target() == boss,
		"101d) phase 2 begins once and fights from its own pool (%d attacks), still locked" % (started.size() - from))

	# 98) the shadow's killing blow: one death, one completion, the 70/30 reward.
	var player_xp: int = p.progression.get_total_xp()
	var shadow_xp: int = _shadow_total_xp(shadow.instance)
	boss.health_component.current_health = 5.0
	var killed: bool = await _until(func() -> bool:
		_stick(p, boss)
		shadow.set_manual_target(boss)
		return boss.has_died(), 20.0)
	await _pause(0.8)
	var reward: int = BOSS_DATA.xp_reward
	var cut: int = int(round(reward * PlayerProgression.SHADOW_KILL_SHARE))
	var player_gain: int = p.progression.get_total_xp() - player_xp
	var shadow_gain: int = _shadow_total_xp(shadow.instance) - shadow_xp
	_record(killed and boss.get_killer() == shadow and shadow_gain == cut and player_gain == reward - cut,
		"98) the shadow lands the killing blow: the boss's %d XP split 70/30 — shadow +%d, player +%d" % [
			reward, shadow_gain, player_gain])
	await _pause(1.0)
	_record(deaths[0] == 1 and completions[0] == 1 and dungeon.get_state() == DungeonController.DungeonState.COMPLETED
			and dungeon.exit_portal.is_enabled(),
		"99) one death, one completion (%d, %d): the dungeon COMPLETED, its exit open" % [deaths[0], completions[0]])
	_record(not p.targeting.is_locked() and not indicator.is_showing() and not bar.is_showing()
			and boss.get_current_attack() == null and not boss.combat.is_hit_window_open(),
		"100) after its death: the lock and the ring gone, its bar gone, no attack and no hitbox left")
	p.shadow_commander.set_mode(BasicMeleeShadow.CommandMode.FOLLOW)
	shadow.hurtbox.set_invulnerable(false)


func _phase_exit() -> void:
	var dungeon: DungeonController = current_scene as DungeonController
	var p: Player = dungeon.get_player()
	p.global_position = EXIT_POS
	await _pause(0.4)
	dungeon.exit_portal.activate()
	await _pause(1.6)
	_record(current_scene.scene_file_path == HUB and _bosses_anywhere() == 0
			and int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)) == 0,
		"101e) the exit takes the player to the hub: no boss survives the dungeon, nothing orphaned")


# --- 102. the second run ----------------------------------------------------------------------------------------------

func _phase_second_boss() -> void:
	var dungeon: DungeonController = current_scene as DungeonController
	var p: Player = dungeon.get_player()
	var boss: DungeonBoss = _boss(dungeon)
	var bar: BossHealthBar = dungeon.get_node("BossHealthBar")
	var clean: bool = true
	for attack in boss.get_attacks():
		clean = clean and boss.combat.get_cooldown(attack) == 0.0
	_record(boss.health_component.current_health == BOSS_DATA.max_health and clean and boss.get_current_attack() == null
			and boss.combat.get_started_count() == 0 and not bar.is_showing() and BOSS_DATA.max_health == 900.0,
		"102a) the second dungeon's boss is new: full health, clean cooldowns, no attack, its bar hidden — the data as shipped")
	p.hurtbox.set_invulnerable(true)
	await _clear_rooms(dungeon)
	p.global_position = ROOM_ANCHORS[2]
	await _until(func() -> bool: return boss.combat_enabled, 4.0)
	await _frames(2)
	_record(boss.get_phase_index() == 0 and bar.is_showing() and is_equal_approx(bar.get_ratio(), 1.0)
			and bar.get_phase_text() == "FASE 1" and boss.get_target() == p,
		"102b) its encounter starts in phase 1, its bar full, the player its target")


# --- 64. the player dies in the fight -------------------------------------------------------------------------------------

func _phase_player_death() -> void:
	var dungeon: DungeonController = current_scene as DungeonController
	var p: Player = dungeon.get_player()
	var boss: DungeonBoss = _boss(dungeon)
	var attacking: bool = await _until(func() -> bool:
		_stick(p, boss)
		return boss.get_current_attack() != null, 6.0)
	var doomed: int = current_scene.get_instance_id()
	p.hurtbox.set_invulnerable(false)
	p.health_component.take_damage(DamageInfo.new(100000.0))
	await _frames(3)
	_record(attacking and dungeon.get_state() == DungeonController.DungeonState.FAILED
			and boss.get_state() == DungeonBoss.State.INACTIVE and boss.get_current_attack() == null
			and not boss.combat.is_hit_window_open() and boss.get_target() == null,
		"64a) the player dies mid-attack: the run fails and the boss parks — no attack, no hitbox, no target")
	await _pause(3.0)
	var restarted: DungeonController = current_scene as DungeonController
	var fresh: DungeonBoss = _boss(restarted) if restarted != null else null
	_record(current_scene.get_instance_id() != doomed and fresh != null and fresh.get_state() == DungeonBoss.State.INACTIVE
			and fresh.get_phase_index() == -1 and fresh.health_component.current_health == BOSS_DATA.max_health,
		"64b) the dungeon reloads with its boss whole and asleep")


# --- 103-104. the archetypes and an elite beside the boss ----------------------------------------------------------------

func _phase_archetypes() -> void:
	var dungeon: DungeonController = current_scene as DungeonController
	var p: Player = dungeon.get_player()
	var boss: DungeonBoss = _boss(dungeon)
	p.hurtbox.set_invulnerable(true)
	# The rooms cleared first, and one at a time: none is kept out of reach by a
	# crowd round the player.
	await _clear_rooms(dungeon)
	p.global_position = ROOM_ANCHORS[0]
	var silent: Array[String] = []
	var spawned: Array[BasicEnemy] = []
	for i in ARCHETYPES.size() + 1:
		# The last round is an elite melee.
		var scene: PackedScene = load(ARCHETYPES[i] if i < ARCHETYPES.size() else ARCHETYPES[0])
		var enemy: BasicEnemy = _spawn(dungeon, scene, ROOM_ANCHORS[0] + Vector3(0, 0, -5.0),
			ELITE if i == ARCHETYPES.size() else null)
		spawned.append(enemy)
		var attacked: bool = await _until(func() -> bool:
			p.global_position = ROOM_ANCHORS[0]
			return enemy.attack.get_swing_count() >= 1, 12.0)
		if not attacked:
			silent.append(enemy.scene_file_path.get_file())
		if i < ARCHETYPES.size():
			enemy.hurtbox.receive_hit(DamageInfo.new(100000.0, null))
		await _pause(0.3)
	var elite: BasicEnemy = spawned[spawned.size() - 1]
	_record(silent.is_empty(), "103) melee, ranged, tank, assassin, support and an elite melee each take the player on and attack%s" % [
		"" if silent.is_empty() else " — silent: %s" % [silent]])
	_record(elite.is_elite() and elite.health_component.max_health == 160.0
			and spawned[0].get_rank() == BasicEnemy.Rank.NORMAL and spawned[0].health_component.max_health == 100.0
			and boss.health_component.max_health == BOSS_DATA.max_health and not ("elite_profile" in boss),
		"104b) the elite is elite (160 HP), the normal normal (100 HP), and the boss has no elite profile to take")
	elite.hurtbox.receive_hit(DamageInfo.new(100000.0, null))
	await _pause(0.4)


# --- 65. leaving mid-fight -------------------------------------------------------------------------------------------------

func _phase_leave_mid_fight() -> void:
	var dungeon: DungeonController = current_scene as DungeonController
	var p: Player = dungeon.get_player()
	var boss: DungeonBoss = _boss(dungeon)
	p.hurtbox.set_invulnerable(true)
	await _clear_rooms(dungeon)
	p.global_position = ROOM_ANCHORS[2]
	await _until(func() -> bool: return boss.combat_enabled, 4.0)
	var busy: bool = await _until(func() -> bool:
		_stick(p, boss)
		return boss.get_attack_phase() == BossCombat.Phase.TELEGRAPH or boss.get_attack_phase() == BossCombat.Phase.ACTIVE, 8.0)
	SceneTransition.find_in(self).transition_to_scene(HUB)
	await _pause(1.8)
	_record(busy and current_scene.scene_file_path == HUB and _bosses_anywhere() == 0
			and int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)) == 0,
		"65) leaving mid-attack: back in the hub, the boss gone with its dungeon — nothing orphaned, nothing left running")


# --- helpers ---------------------------------------------------------------------------------------------------------------

func _boss(dungeon: DungeonController) -> DungeonBoss:
	for combatant in dungeon.get_rooms()[2].get_enemies():
		if combatant is DungeonBoss:
			return combatant as DungeonBoss
	return null


func _bosses_anywhere() -> int:
	return get_nodes_in_group(DungeonBoss.GROUP).size()


func _clear_rooms(dungeon: DungeonController) -> void:
	var p: Player = dungeon.get_player()
	for i in 2:
		p.global_position = ROOM_ANCHORS[i]
		await _pause(0.4)
		for enemy in dungeon.get_rooms()[i].get_enemies():
			enemy.hurtbox.receive_hit(DamageInfo.new(10000.0, null))
		await _pause(0.5)


func _spawn(dungeon: DungeonController, scene: PackedScene, at: Vector3, profile: EliteModifierData) -> BasicEnemy:
	var enemy: BasicEnemy = scene.instantiate() as BasicEnemy
	enemy.elite_profile = profile
	enemy.position = at
	dungeon.add_child(enemy)
	enemy.set_combat_enabled(true)
	return enemy


## The player's light attack at `target` until it dies, standing in front of it.
func _kill(p: Player, target: RoomCombatant, budget: float = 30.0) -> void:
	var elapsed: float = 0.0
	while elapsed < budget and not target.has_died():
		_swing(p, target)
		await physics_frame
		elapsed += DT


## A light attack at `target` if the player is free to swing, from in front of it.
func _swing(p: Player, target: Node3D) -> void:
	if p.combat.get_state() != PlayerCombat.State.IDLE:
		return
	_stick(p, target)
	p.camera_rig.rotation.y = 0.0
	p.camera_rig.attack_light_pressed.emit()


func _stick(p: Player, glue: Node3D) -> void:
	if glue != null and is_instance_valid(glue):
		p.global_position = glue.global_position + Vector3(0, 0, STRIKE_RANGE)


func _press(p: Player, action: StringName) -> void:
	var event: InputEventAction = InputEventAction.new()
	event.action = action
	event.pressed = true
	p._unhandled_input(event)


func _until(condition: Callable, budget: float = 3.0) -> bool:
	var waited: float = 0.0
	while not condition.call():
		if waited >= budget:
			return false
		await physics_frame
		waited += DT
	return true


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _shadow_total_xp(shadow: ShadowInstance) -> int:
	var total: int = shadow.current_xp
	for level in range(1, shadow.level):
		total += shadow.shadow_data.xp_required_for_level(level)
	return total


## A killing blow on the boss opens the run summary, which pauses the tree: a
## headless flow dismisses it, as a player would.
func _pause(t: float) -> void:
	RunSummary.dismiss_open(self)
	await create_timer(t).timeout


func _record(passed: bool, description: String) -> void:
	if passed:
		_pass += 1
		print("[PASS] " + description)
	else:
		_fail += 1
		print("[FAIL] " + description)
