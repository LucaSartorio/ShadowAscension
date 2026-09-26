extends SceneTree

## M12.7 — elite enemies through the whole game.
##
##   godot --headless --path . --script res://tests/core/m12_elite_run.gd
##
## The shipped dungeon holds normal melee only: placing elites in it is content
## (M18). This run brings its own — the same scenes, an elite profile set where
## they are placed — into the real dungeon, on its real navigation:
##
## Menu -> New Game -> hub (a shadow summoned) -> gate -> dungeon: the shipped
## melee normal, at their base -> room one, an elite melee beside its two normal
## melee: heavier blows, more health, a tag; the room clears; locked on, a
## critical heavy brings the elite down: 50 XP once -> room two: a support heals
## a hurt elite tank on its effective maximum; the shadow kills an elite melee
## (35 / 15 of its 50) -> the boss, untouched by any of it -> leaving with elites
## alive: nothing of them survives -> hub -> a second dungeon: the normals normal,
## a new elite fresh, no listener doubled -> hub, nothing orphaned -> New Game
## again: a new character, the dungeon's enemies at their base.

const BOOT: String = "res://Main.tscn"
const HUB: String = "res://scenes/core/hub.tscn"
const MELEE_SCENE: PackedScene = preload("res://scenes/enemies/basic_melee_enemy.tscn")
const RANGED_SCENE: PackedScene = preload("res://scenes/enemies/basic_ranged_enemy.tscn")
const TANK_SCENE: PackedScene = preload("res://scenes/enemies/basic_tank_enemy.tscn")
const SUPPORT_SCENE: PackedScene = preload("res://scenes/enemies/basic_support_enemy.tscn")
const ELITE: EliteModifierData = preload("res://resources/enemies/elite_standard.tres")
const MELEE_DATA: EnemyData = preload("res://resources/enemies/basic_melee_enemy.tres")
const DT: float = 1.0 / 60.0
const ROOM_ANCHORS: Array[Vector3] = [
	Vector3(0, 0.1, -13), Vector3(0, 0.1, -33), Vector3(0, 0.1, -53)
]
const ROOM_ONE_ELITE: Vector3 = Vector3(-3, 0.1, -19)
const ROOM_TWO_TANK: Vector3 = Vector3(-3, 0.1, -38)
const ROOM_TWO_SUPPORT: Vector3 = Vector3(3, 0.1, -41)
const ROOM_TWO_ELITE: Vector3 = Vector3(4, 0.1, -37)
const EXIT_POS: Vector3 = Vector3(0, 0.1, -65)
const STRIKE_RANGE: float = 1.6

var _no_crits: PlayerCombatData = preload("res://resources/characters/player_combat.tres")
var _shadow_data: ShadowData = preload("res://resources/shadows/basic_melee_shadow.tres")
var _state: Node = null
var _pass: int = 0
var _fail: int = 0
## Every hit a melee's swing landed: {source, target, amount}.
var _hits: Array[Dictionary] = []
var _first_listeners: Array = []


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
	await _phase_room_one(1)
	await _phase_room_two()
	await _phase_boss()
	await _phase_out_with_elites()
	await _phase_into_dungeon(2)
	await _phase_room_one(2)
	SceneTransition.find_in(self).transition_to_scene(HUB)
	await _pause(1.6)
	_record(current_scene.scene_file_path == HUB and _elites_anywhere() == 0
			and int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)) == 0,
		"END) back in the hub after the second dungeon: no elite left anywhere, nothing orphaned")
	await _phase_new_game()
	print("[SUMMARY] passed=%d failed=%d" % [_pass, _fail])
	await _pause(0.3)
	quit()


# --- the hub -------------------------------------------------------------------------------------------

func _phase_hub() -> void:
	var p: Player = current_scene.get_node("Player")
	var shadow: ShadowInstance = p.shadows.add_shadow(_shadow_data)
	p.shadow_summoner.summon(shadow.instance_id)
	await _pause(0.4)
	p.shadow_commander.set_mode(BasicMeleeShadow.CommandMode.FOLLOW)
	_record(p.shadow_summoner.get_active_node() != null, "H1) the hub: a shadow summoned, to take into the dungeon")


func _phase_into_dungeon(run: int) -> void:
	var p: Player = current_scene.get_node("Player")
	var gate: DungeonGate = current_scene.get_node("DungeonGate")
	p.global_position = gate.global_position
	await _pause(0.4)
	gate.activate()
	await _pause(1.6)
	var dungeon: DungeonController = current_scene as DungeonController
	_record(_all_normal(dungeon) and _elites_anywhere() == 0,
		"G%d) dungeon %d: the shipped five melee, all NORMAL at their base — 100 HP, 15 damage, 25 XP; no elite in it%s" % [
			run, run, " — nothing of the first dungeon's elites leaked into them" if run == 2 else ""])


# --- room one: an elite beside the room's normal melee -----------------------------------------------------------

func _phase_room_one(run: int) -> void:
	var dungeon: DungeonController = current_scene as DungeonController
	var p: Player = dungeon.get_player()
	var room: RoomController = dungeon.get_rooms()[0]
	var melee: Array[BasicEnemy] = _room_enemies(room)
	for e in melee:
		_watch(e)
	var elite: BasicEnemy = _spawn(dungeon, MELEE_SCENE, ROOM_ONE_ELITE, ELITE)
	var bar: EnemyHealthBar3D = elite.get_node("EnemyHealthBar3D") as EnemyHealthBar3D
	var fresh: bool = elite.is_elite() and elite.health_component.max_health == 160.0 \
		and elite.health_component.current_health == 160.0 and elite.attack.get_swing_count() == 0 \
		and bar.is_elite_tag_visible()
	var listeners: Array = [elite.state_changed.get_connections().size(),
		elite.health_component.died.get_connections().size(),
		elite.health_component.damaged.get_connections().size(),
		elite.attack.hitbox.hit_landed.get_connections().size()]
	var same: bool = true
	if run == 1:
		_first_listeners = listeners
	else:
		same = listeners == _first_listeners
	p.hurtbox.set_invulnerable(true)
	p.global_position = ROOM_ANCHORS[0]
	var shadow: BasicMeleeShadow = p.shadow_summoner.get_active_node()
	if shadow != null:
		shadow.hurtbox.set_invulnerable(true)
	var first: int = _hits.size()
	var swung: bool = await _until(func() -> bool:
		p.global_position = ROOM_ANCHORS[0]
		var sources: Dictionary = {}
		for h in _hits.slice(first):
			sources[h["source"]] = true
		return sources.has(elite) and melee.any(func(e: BasicEnemy) -> bool: return sources.has(e)), 12.0)
	var elite_blow: float = _first_amount(elite, first)
	var normal_blow: float = _first_amount(melee[0], first) if _first_amount(melee[0], first) > 0.0 \
		else _first_amount(melee[1], first)
	_record(fresh and same and swung and is_equal_approx(elite_blow, 18.0) and normal_blow == 15.0
			and melee.all(func(e: BasicEnemy) -> bool: return not e.is_elite() and e.health_component.max_health == 100.0),
		"R%d.1) room one, an elite melee beside its two normal melee: tagged ELITE, 160 HP, blows of %.0f against the normals' %.0f — the same scene and state machine%s" % [
			run, elite_blow, normal_blow, "; fresh, its listeners as in the first dungeon" if run == 2 else ""])

	# The room's melee killed: the room clears, the elite — not the room's —
	# changing nothing of it.
	elite.health_component.set_max_health(2000.0)
	elite.health_component.current_health = 2000.0
	for e in melee:
		await _kill(p, e)
	await _pause(0.5)
	_record(room.is_cleared(), "R%d.2) the room's normal melee killed: the room clears" % run)

	# Locked on, and brought down: its effective reward, once.
	p.global_position = ROOM_ANCHORS[0]
	p.camera_rig.rotation.y = 0.0
	await _frames(2)
	_press(p, &"target_lock")
	var locked: bool = p.targeting.get_target() == elite
	var xp: int = p.progression.get_total_xp()
	var deaths: Array[int] = [0]
	elite.enemy_died.connect(func(_dead: RoomCombatant) -> void: deaths[0] += 1)
	elite.health_component.current_health = 50.0
	_no_crits.critical_chance = 1.0
	var tries: int = 0
	while not elite.has_died() and tries < 4:
		await _heavy(p, elite)
		tries += 1
	_no_crits.critical_chance = 0.0
	await _pause(0.4)
	_record(locked and elite.has_died() and deaths[0] == 1 and p.progression.get_total_xp() - xp == 50
			and not p.targeting.is_locked() and not bar.is_elite_tag_visible(),
		"R%d.3) locked on the elite, a critical heavy brings it down — 50 XP (25 x 2) once, its tag gone, the lock let go" % run)
	if shadow != null and is_instance_valid(shadow):
		shadow.hurtbox.set_invulnerable(false)


# --- room two: a support and an elite tank; the shadow's kill ----------------------------------------------------

func _phase_room_two() -> void:
	var dungeon: DungeonController = current_scene as DungeonController
	var p: Player = dungeon.get_player()
	var shadow: BasicMeleeShadow = p.shadow_summoner.get_active_node()
	var room: RoomController = dungeon.get_rooms()[1]
	var melee: Array[BasicEnemy] = _room_enemies(room)
	p.hurtbox.set_invulnerable(true)
	p.global_position = ROOM_ANCHORS[1]
	shadow.global_position = ROOM_ANCHORS[1] + Vector3(1.5, 0, 1.0)
	shadow.hurtbox.set_invulnerable(true)
	var armed: bool = await _until(func() -> bool: return room.get_state() == RoomController.RoomState.ACTIVE, 2.0)
	# A hurt elite tank, and a support that finds it.
	var tank: BasicEnemy = _spawn(dungeon, TANK_SCENE, ROOM_TWO_TANK, ELITE)
	var support: BasicEnemy = _spawn(dungeon, SUPPORT_SCENE, ROOM_TWO_SUPPORT, null)
	await _frames(3)
	tank.health_component.current_health = 166.4
	var healed: Array[float] = [0.0]
	support.support.support_applied.connect(func(ally: RoomCombatant, action: AttackData, amount: float) -> void:
		if ally == tank and action == support.support.heal_action:
			healed[0] = amount)
	var bar: EnemyHealthBar3D = tank.get_node("EnemyHealthBar3D") as EnemyHealthBar3D
	var done: bool = await _until(func() -> bool:
		p.global_position = ROOM_ANCHORS[1]
		return healed[0] > 0.0, 12.0)
	_record(armed and done and is_equal_approx(healed[0], 104.0) and tank.health_component.current_health > 260.0
			and is_equal_approx(bar.get_ratio(), tank.health_component.current_health / 416.0),
		"S1) room two, an elite tank at 40%% of its 416 and a support: healed for %.0f — a quarter of its effective maximum — past the tank's base 260, its bar drawn on 416" % healed[0])
	# The shadow's kill of an elite melee: 70/30 of the effective reward.
	var elite: BasicEnemy = _spawn(dungeon, MELEE_SCENE, ROOM_TWO_ELITE, ELITE)
	await _frames(3)
	elite.health_component.current_health = 10.0
	var player_xp: int = p.progression.get_total_xp()
	var shadow_xp: int = _shadow_total_xp(shadow.instance)
	p.shadow_commander.set_mode(BasicMeleeShadow.CommandMode.AGGRESSIVE)
	shadow.set_manual_target(elite)
	var killed: bool = await _until(func() -> bool:
		p.global_position = ROOM_ANCHORS[1]
		return elite.has_died(), 15.0)
	await _pause(0.3)
	var reward: int = elite.get_xp_reward()
	var cut: int = int(round(reward * PlayerProgression.SHADOW_KILL_SHARE))
	var player_gain: int = p.progression.get_total_xp() - player_xp
	var shadow_gain: int = _shadow_total_xp(shadow.instance) - shadow_xp
	_record(killed and elite.get_killer() == shadow and reward == 50 and shadow_gain == cut and cut == 35
			and player_gain == 15,
		"S2) the shadow kills an elite melee: its 50, split 70/30 — shadow +%d, player +%d — the split of the effective reward" % [
			shadow_gain, player_gain])
	p.shadow_commander.set_mode(BasicMeleeShadow.CommandMode.FOLLOW)
	shadow.hurtbox.set_invulnerable(false)
	for e in melee:
		await _kill(p, e)
	await _pause(0.5)
	_record(room.is_cleared(), "S3) room two's melee killed: the room clears")


# --- the boss, and leaving with elites alive -----------------------------------------------------------------------

func _phase_boss() -> void:
	var dungeon: DungeonController = current_scene as DungeonController
	var p: Player = dungeon.get_player()
	p.global_position = ROOM_ANCHORS[2]
	var boss: DungeonBoss = _boss(dungeon)
	var untouched: bool = boss.health_component.max_health == boss.data.max_health and boss.get_xp_reward() == boss.data.xp_reward \
		and not boss.has_method("is_elite")
	var awake: bool = await _until(func() -> bool: return boss.combat_enabled, 6.0)
	_stick(p, boss)
	await _frames(2)
	_press(p, &"target_lock")
	var locked: bool = p.targeting.get_target() == boss
	boss.health_component.current_health = 40.0
	await _heavy(p, boss)
	await _pause(0.6)
	_record(untouched and awake and locked and boss.has_died() and not p.targeting.is_locked()
			and dungeon.get_state() == DungeonController.DungeonState.COMPLETED,
		"B1) the boss is no elite: its own stats (%.0f HP, %d XP), its own AI; locked and killed, the dungeon completes" % [
			boss.data.max_health, boss.data.xp_reward])


func _phase_out_with_elites() -> void:
	var dungeon: DungeonController = current_scene as DungeonController
	var p: Player = dungeon.get_player()
	p.global_position = EXIT_POS
	var melee: BasicEnemy = _spawn(dungeon, MELEE_SCENE, EXIT_POS + Vector3(-2, 0, 5), ELITE)
	var ranged: BasicEnemy = _spawn(dungeon, RANGED_SCENE, EXIT_POS + Vector3(2, 0, 7), ELITE)
	var fighting: bool = await _until(func() -> bool:
		p.global_position = EXIT_POS
		return melee.get_target() == p and ranged.attack.get_swing_count() >= 1, 6.0)
	dungeon.exit_portal.activate()
	await _pause(1.6)
	_record(fighting and not is_instance_valid(melee) and not is_instance_valid(ranged) and current_scene.scene_file_path == HUB
			and _elites_anywhere() == 0 and int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)) == 0
			and ELITE.health_multiplier == 1.6 and MELEE_DATA.max_health == 100.0,
		"O1) leaving through the exit with two elites fighting: they go with the dungeon — no state, timer, tag or reference survives, the shared data as it was, nothing orphaned")


# --- a new game --------------------------------------------------------------------------------------------------

func _phase_new_game() -> void:
	change_scene_to_file(BOOT)
	await _pause(0.6)
	(current_scene.get_node("MainMenu") as MainMenu).press_play()
	await _pause(1.4)
	var p: Player = current_scene.get_node("Player")
	var fresh: bool = current_scene.scene_file_path == HUB and p.progression.get_total_xp() == 0
	var gate: DungeonGate = current_scene.get_node("DungeonGate")
	p.global_position = gate.global_position
	await _pause(0.4)
	gate.activate()
	await _pause(1.6)
	var dungeon: DungeonController = current_scene as DungeonController
	_record(fresh and dungeon != null and _all_normal(dungeon) and _elites_anywhere() == 0
			and ELITE.health_multiplier == 1.6 and MELEE_DATA.max_health == 100.0 and MELEE_DATA.attack_damage == 15.0,
		"NG1) New Game again: a new character (0 XP), and its dungeon's melee all NORMAL at their base — nothing elite carried over")


# --- helpers ------------------------------------------------------------------------------------------------

func _spawn(dungeon: DungeonController, scene: PackedScene, at: Vector3, profile: EliteModifierData) -> BasicEnemy:
	var enemy: BasicEnemy = scene.instantiate() as BasicEnemy
	# Set where it is placed, before it enters the tree — as a room's own
	# enemies carry theirs from the scene file.
	enemy.elite_profile = profile
	enemy.position = at
	dungeon.add_child(enemy)
	_watch(enemy)
	enemy.set_combat_enabled(true)
	return enemy


func _watch(enemy: BasicEnemy) -> void:
	var melee: EnemyMeleeAttack = enemy.attack as EnemyMeleeAttack
	if melee == null:
		return
	melee.hitbox.hit_landed.connect(func(target: Node, hit: DamageInfo) -> void:
		_hits.append({"source": hit.source, "target": target, "amount": hit.amount}))


func _first_amount(enemy: BasicEnemy, from: int) -> float:
	for h in _hits.slice(from):
		if is_same(h["source"], enemy):
			return h["amount"]
	return -1.0


## Every melee the dungeon ships, normal, at its archetype's numbers.
func _all_normal(dungeon: DungeonController) -> bool:
	var enemies: Array[BasicEnemy] = []
	for room in dungeon.get_rooms():
		enemies.append_array(_room_enemies(room))
	return enemies.size() == 5 and enemies.all(func(e: BasicEnemy) -> bool:
		return (e.get_rank() == BasicEnemy.Rank.NORMAL and e.health_component.max_health == 100.0
			and e.health_component.current_health == 100.0 and e.attack.attack_damage == 15.0
			and e.movement_speed == 3.8 and e.get_xp_reward() == 25 and e.stats == MELEE_DATA))


func _elites_anywhere() -> int:
	var n: int = 0
	for node in root.find_children("*", "BasicEnemy", true, false):
		var enemy: BasicEnemy = node as BasicEnemy
		if enemy != null and enemy.is_elite():
			n += 1
	return n


func _room_enemies(room: RoomController) -> Array[BasicEnemy]:
	var out: Array[BasicEnemy] = []
	for combatant in room.get_enemies():
		var enemy: BasicEnemy = combatant as BasicEnemy
		if enemy != null:
			out.append(enemy)
	return out


func _boss(dungeon: DungeonController) -> DungeonBoss:
	for combatant in dungeon.get_rooms()[2].get_enemies():
		if combatant is DungeonBoss:
			return combatant as DungeonBoss
	return null


## The player's light attack at `target` until it dies, standing in front of it.
func _kill(p: Player, target: RoomCombatant, budget: float = 30.0) -> void:
	var elapsed: float = 0.0
	while elapsed < budget and not target.has_died():
		if p.combat.get_state() == PlayerCombat.State.IDLE:
			p.global_position = target.global_position + Vector3(0, 0, STRIKE_RANGE)
			p.camera_rig.rotation.y = 0.0
			p.camera_rig.attack_light_pressed.emit()
		await physics_frame
		elapsed += DT


## Bounded: a killing blow on the boss opens the run summary, which pauses the
## tree with the swing still in its recovery.
func _heavy(p: Player, glue: Node3D) -> void:
	p.combat.reset()
	_stick(p, glue)
	p.camera_rig.rotation.y = 0.0
	p.camera_rig.attack_heavy_pressed.emit()
	var frames: int = 0
	while p.combat.is_attacking() and frames < 300 and not paused:
		await physics_frame
		frames += 1
		_stick(p, glue)


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
