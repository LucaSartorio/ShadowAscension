extends SceneTree

## M12.4 — the tank archetype through the whole game, beside the melee and the
## ranged.
##
##   godot --headless --path . --script res://tests/core/m12_tank_run.gd
##
## The shipped dungeon holds melee only: placing tanks in it is content (M18).
## This run brings its own into the real dungeon, on its real navigation:
##
## Menu -> New Game -> hub (a shadow summoned) -> gate -> dungeon: the shipped
## melee untouched -> room one, the player vulnerable, a tank and a ranged beside
## its two melee: the melee arrive first, the tank later, the ranged keeps its
## distance; the tank's blow lands 30, once a swing; one of its blows dodged
## through; the lock switched across all three archetypes; critical heavies bring
## the tank down: 50 XP once, the lock let go -> room two: a tank the shadow
## finishes (70/30) -> the boss, untouched -> hub, nothing left over -> a second
## dungeon: the tank fresh, no listener doubled, the same again -> hub, nothing
## orphaned.

const BOOT: String = "res://Main.tscn"
const HUB: String = "res://scenes/core/hub.tscn"
const TANK_SCENE: PackedScene = preload("res://scenes/enemies/basic_tank_enemy.tscn")
const RANGED_SCENE: PackedScene = preload("res://scenes/enemies/basic_ranged_enemy.tscn")
const DT: float = 1.0 / 60.0
const ROOM_ANCHORS: Array[Vector3] = [
	Vector3(0, 0.1, -13), Vector3(0, 0.1, -33), Vector3(0, 0.1, -53)
]
const ROOM_ONE_TANK: Vector3 = Vector3(-3, 0.1, -21.5)
const ROOM_ONE_RANGED: Vector3 = Vector3(4, 0.1, -22)
const ROOM_TWO_TANK: Vector3 = Vector3(4, 0.1, -41)
const EXIT_POS: Vector3 = Vector3(0, 0.1, -65)
const STRIKE_RANGE: float = 1.6

var _no_crits: PlayerCombatData = preload("res://resources/characters/player_combat.tres")
var _shadow_data: ShadowData = preload("res://resources/shadows/basic_melee_shadow.tres")
var _state: Node = null
var _pass: int = 0
var _fail: int = 0
## Every hit a tank's swing landed: {swing, target, amount, accepted}.
var _tank_hits: Array[Dictionary] = []
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
	await _phase_out_to_hub()
	await _phase_into_dungeon(2)
	await _phase_room_one(2)
	SceneTransition.find_in(self).transition_to_scene(HUB)
	await _pause(1.6)
	_record(current_scene.scene_file_path == HUB and _tanks_anywhere() == 0
			and int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)) == 0,
		"END) back in the hub after the second dungeon: no tank left anywhere, nothing orphaned")
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
	var melee: Array[BasicEnemy] = _basic_enemies(dungeon)
	var shipped: bool = melee.size() == 5 and melee.all(func(e: BasicEnemy) -> bool:
		return (e.stats.resource_path.ends_with("basic_melee_enemy.tres") and e.get_state() == BasicEnemy.State.IDLE
			and not e.combat_enabled))
	_record(shipped and _tanks_anywhere() == 0,
		"G%d) dungeon %d: the shipped five, all melee, parked; no tank in it%s" % [
			run, run, " — nothing left of the first dungeon's" if run == 2 else ""])


# --- room one: the three archetypes together ---------------------------------------------------------------

func _phase_room_one(run: int) -> void:
	var dungeon: DungeonController = current_scene as DungeonController
	var p: Player = dungeon.get_player()
	var room: RoomController = dungeon.get_rooms()[0]
	var melee: Array[BasicEnemy] = _room_enemies(room)
	var tank: BasicEnemy = _spawn(dungeon, TANK_SCENE, ROOM_ONE_TANK)
	var ranged: BasicEnemy = _spawn(dungeon, RANGED_SCENE, ROOM_ONE_RANGED)
	var fresh: bool = tank.health_component.current_health == 260.0 and tank.get_attack_phase() == EnemyAttack.Phase.NONE \
		and tank.attack.get_cooldown_remaining() == 0.0 and tank.attack.get_swing_count() == 0
	var listeners: Array = [tank.state_changed.get_connections().size(),
		tank.health_component.died.get_connections().size(),
		tank.health_component.damaged.get_connections().size(),
		tank.attack.hitbox.hit_landed.get_connections().size()]
	var same: bool = true
	if run == 1:
		_first_listeners = listeners
	else:
		same = listeners == _first_listeners
	p.hurtbox.set_invulnerable(false)
	p.health_component.heal(p.health_component.max_health)
	p.global_position = ROOM_ANCHORS[0]
	var first_hit: int = _tank_hits.size()
	var arrived: Dictionary = {}
	var closest_ranged: float = 100.0
	var elapsed: float = 0.0
	while elapsed < 15.0 and _tank_hits.slice(first_hit).filter(func(h: Dictionary) -> bool: return h["accepted"]).is_empty():
		p.global_position = ROOM_ANCHORS[0]
		if p.health_component.current_health < 50.0:
			p.health_component.heal(p.health_component.max_health)
		if ranged.get_target() != null:
			closest_ranged = minf(closest_ranged, ranged.targeting.get_distance())
		for e in melee + [tank]:
			var enemy: BasicEnemy = e
			if not arrived.has(enemy) and enemy.get_target() == p and enemy.targeting.get_distance() <= enemy.attack_range:
				arrived[enemy] = elapsed
		await physics_frame
		elapsed += DT
	var mine: Array[Dictionary] = _tank_hits.slice(first_hit)
	var one_each: bool = true
	var swings: Dictionary = {}
	for h in mine:
		if h["target"] != p:
			continue
		one_each = one_each and not swings.has(h["swing"]) and h["amount"] == 30.0
		swings[h["swing"]] = true
	var melee_first: float = INF
	for e in melee:
		melee_first = minf(melee_first, arrived.get(e, INF))
	_record(fresh and same and not swings.is_empty() and one_each and arrived.has(tank) and melee_first < arrived[tank]
			and closest_ranged >= ranged.minimum_combat_distance,
		"R%d.1) room one, a tank and a ranged beside its melee: the melee arrive first, the tank %.1f s later, the ranged keeps %.1f m; the tank's blow lands 30, once a swing%s" % [
			run, arrived.get(tank, 0.0) - melee_first, closest_ranged,
			"; the tank fresh and its listeners as in the first dungeon" if run == 2 else ""])

	if run == 1:
		# One of its blows dodged through: the i-frames take it.
		p.health_component.heal(p.health_component.max_health)
		p.combat.restore_stamina(p.combat.get_max_stamina())
		var due: bool = await _until(func() -> bool:
			p.global_position = ROOM_ANCHORS[0]
			return (tank.get_attack_phase() == EnemyAttack.Phase.TELEGRAPH
				and tank.attack.get_phase_remaining() <= 0.1), 8.0)
		var swing: int = tank.attack.get_swing_count()
		var speed: float = p.effective_dodge_speed
		p.effective_dodge_speed = 0.0
		_press(p, &"dodge")
		await _until(func() -> bool: return (tank.get_attack_phase() != EnemyAttack.Phase.ACTIVE
			and tank.get_attack_phase() != EnemyAttack.Phase.TELEGRAPH), 1.0)
		p.effective_dodge_speed = speed
		var this_swing: Array[Dictionary] = _tank_hits.filter(func(h: Dictionary) -> bool:
			return h["swing"] == swing and h["target"] == p)
		_record(due and this_swing.size() == 1 and not this_swing[0]["accepted"],
			"R1.2) a tank's blow read and dodged into: it reaches the player inside the i-frames and is refused — no damage")

	# The lock across the three archetypes, then critical heavies on the tank.
	p.hurtbox.set_invulnerable(true)
	p.global_position = ROOM_ANCHORS[0]
	p.camera_rig.rotation.y = 0.0
	await _frames(2)
	_press(p, &"target_lock")
	var locked: Dictionary = {}
	for action in [&"target_switch_left", &"target_switch_left", &"target_switch_left", &"target_switch_right",
			&"target_switch_right", &"target_switch_right", &"target_switch_right"]:
		var target: RoomCombatant = p.targeting.get_target()
		if target != null:
			locked[target] = true
		_press(p, action)
		await _frames(1)
	var kinds: Dictionary = {}
	for target in locked.keys():
		var enemy: BasicEnemy = target as BasicEnemy
		if enemy != null:
			kinds[enemy.stats.resource_path.get_file()] = true
	_record(kinds.size() == 3,
		"R%d.3) the lock switched across melee, ranged and tank: %s" % [run, kinds.keys()])
	p.targeting.unlock()
	_stick(p, tank)
	await _frames(2)
	_press(p, &"target_lock")
	var on_tank: bool = p.targeting.get_target() == tank
	var xp: int = p.progression.get_total_xp()
	var deaths: Array[int] = [0]
	tank.enemy_died.connect(func(_dead: RoomCombatant) -> void: deaths[0] += 1)
	tank.health_component.current_health = 110.0
	_no_crits.critical_chance = 1.0
	var tries: int = 0
	while not tank.has_died() and tries < 6:
		await _heavy(p, tank)
		tries += 1
	_no_crits.critical_chance = 0.0
	await _pause(0.4)
	_record(on_tank and tank.has_died() and deaths[0] == 1 and p.progression.get_total_xp() - xp == 50
			and not p.targeting.is_locked(),
		"R%d.4) locked on the tank, %d critical heavies bring it down: one death, 50 XP once, the lock let go" % [run, tries])
	for e in melee:
		await _kill(p, e)
	await _kill(p, ranged)
	await _pause(0.5)
	_record(room.is_cleared(), "R%d.5) the melee killed too: the room clears, the tank and the ranged — not the room's — changing nothing of it" % run)


# --- room two: the shadow's kill ------------------------------------------------------------------------

func _phase_room_two() -> void:
	var dungeon: DungeonController = current_scene as DungeonController
	var p: Player = dungeon.get_player()
	var shadow: BasicMeleeShadow = p.shadow_summoner.get_active_node()
	var room: RoomController = dungeon.get_rooms()[1]
	var melee: Array[BasicEnemy] = _room_enemies(room)
	p.global_position = ROOM_ANCHORS[1]
	shadow.global_position = ROOM_ANCHORS[1] + Vector3(1.5, 0, 0)
	var armed: bool = await _until(func() -> bool: return room.get_state() == RoomController.RoomState.ACTIVE, 2.0)
	var tank: BasicEnemy = _spawn(dungeon, TANK_SCENE, ROOM_TWO_TANK)
	await _frames(3)
	tank.health_component.current_health = 10.0
	var player_xp: int = p.progression.get_total_xp()
	var shadow_xp: int = _shadow_total_xp(shadow.instance)
	p.shadow_commander.set_mode(BasicMeleeShadow.CommandMode.AGGRESSIVE)
	shadow.set_manual_target(tank)
	var killed: bool = await _until(func() -> bool:
		p.global_position = ROOM_ANCHORS[1]
		return tank.has_died(), 15.0)
	await _pause(0.3)
	var reward: int = tank.get_xp_reward()
	var cut: int = int(round(reward * PlayerProgression.SHADOW_KILL_SHARE))
	var player_gain: int = p.progression.get_total_xp() - player_xp
	var shadow_gain: int = _shadow_total_xp(shadow.instance) - shadow_xp
	_record(armed and killed and tank.get_killer() == shadow and shadow_gain == cut and player_gain == reward - cut,
		"S1) the shadow brings down a tank: its kill, split 70/30 — shadow +%d, player +%d of its %d" % [shadow_gain, player_gain, reward])
	p.shadow_commander.set_mode(BasicMeleeShadow.CommandMode.FOLLOW)
	p.hurtbox.set_invulnerable(true)
	for e in melee:
		await _kill(p, e)
	await _pause(0.5)
	_record(room.is_cleared(), "S2) room two's melee killed: the room clears")


# --- the boss, and out ------------------------------------------------------------------------------------------

func _phase_boss() -> void:
	var dungeon: DungeonController = current_scene as DungeonController
	var p: Player = dungeon.get_player()
	p.global_position = ROOM_ANCHORS[2]
	var boss: DungeonBoss = _boss(dungeon)
	var awake: bool = await _until(func() -> bool: return boss.combat_enabled, 6.0)
	_stick(p, boss)
	await _frames(2)
	_press(p, &"target_lock")
	var locked: bool = p.targeting.get_target() == boss
	boss.health_component.current_health = 40.0
	await _heavy(p, boss)
	await _pause(0.6)
	_record(awake and locked and boss.has_died() and not p.targeting.is_locked()
			and dungeon.get_state() == DungeonController.DungeonState.COMPLETED,
		"B1) the boss, on its own AI, locked and killed; the dungeon completes")


func _phase_out_to_hub() -> void:
	var dungeon: DungeonController = current_scene as DungeonController
	var p: Player = dungeon.get_player()
	p.global_position = EXIT_POS
	await _pause(0.4)
	dungeon.exit_portal.activate()
	await _pause(1.6)
	_record(current_scene.scene_file_path == HUB and _tanks_anywhere() == 0
			and int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)) == 0,
		"O1) back in the hub: nothing of the first dungeon's tanks left behind, nothing orphaned")


# --- helpers ------------------------------------------------------------------------------------------------

func _spawn(dungeon: DungeonController, scene: PackedScene, at: Vector3) -> BasicEnemy:
	var enemy: BasicEnemy = scene.instantiate() as BasicEnemy
	enemy.position = at
	dungeon.add_child(enemy)
	var melee: EnemyMeleeAttack = enemy.attack as EnemyMeleeAttack
	if melee != null:
		melee.hitbox.hit_landed.connect(func(target: Node, hit: DamageInfo) -> void:
			_tank_hits.append({"swing": enemy.attack.get_swing_count(), "target": target, "amount": hit.amount,
				"accepted": false}))
		melee.hitbox.hit_accepted.connect(func(_target: Node, _hit: DamageInfo) -> void:
			_tank_hits[-1]["accepted"] = true)
	enemy.set_combat_enabled(true)
	return enemy


func _tanks_anywhere() -> int:
	var n: int = 0
	for node in root.find_children("*", "BasicEnemy", true, false):
		var enemy: BasicEnemy = node as BasicEnemy
		if enemy != null and enemy.stats != null and enemy.stats.resource_path.ends_with("basic_tank_enemy.tres"):
			n += 1
	return n


func _basic_enemies(dungeon: DungeonController) -> Array[BasicEnemy]:
	var out: Array[BasicEnemy] = []
	for room in dungeon.get_rooms():
		out.append_array(_room_enemies(room))
	return out


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
