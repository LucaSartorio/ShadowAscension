extends SceneTree

## M12.3 — the ranged archetype through the whole game.
##
##   godot --headless --path . --script res://tests/core/m12_ranged_run.gd
##
## The shipped dungeon holds melee only: placing ranged enemies in it is content
## (M18). So this run brings its own — a ranged spawned into the real dungeon,
## on its real navigation, beside its real melee:
##
## Menu -> New Game -> hub (a shadow summoned) -> gate -> dungeon: the shipped
## melee as M12.2 left them, nothing ranged, no projectile -> room one, the player
## vulnerable, a ranged beside its two melee: the melee close in, the ranged keeps
## its distance and fires — each shot one hit of 12 at most — the player dodges
## one through its i-frames; locked on, the ring over it, a critical heavy kills
## it: 25 XP once, the lock let go -> room two: a ranged the shadow finishes
## (70/30) -> the boss, untouched -> a ranged shot in flight as the player leaves:
## gone with the dungeon -> hub -> a second dungeon: the same again, no listener
## doubled, nothing left over -> hub, nothing orphaned.

const BOOT: String = "res://Main.tscn"
const HUB: String = "res://scenes/core/hub.tscn"
const RANGED_SCENE: PackedScene = preload("res://scenes/enemies/basic_ranged_enemy.tscn")
const DT: float = 1.0 / 60.0
const ROOM_ANCHORS: Array[Vector3] = [
	Vector3(0, 0.1, -13), Vector3(0, 0.1, -33), Vector3(0, 0.1, -53)
]
const ROOM_ONE_RANGED: Vector3 = Vector3(4, 0.1, -22)
const ROOM_TWO_RANGED: Vector3 = Vector3(4, 0.1, -44)
const EXIT_POS: Vector3 = Vector3(0, 0.1, -65)
const STRIKE_RANGE: float = 1.6

var _no_crits: PlayerCombatData = preload("res://resources/characters/player_combat.tres")
var _shadow_data: ShadowData = preload("res://resources/shadows/basic_melee_shadow.tres")
var _state: Node = null
var _pass: int = 0
var _fail: int = 0
## Every shot fired: {enemy_name, id, projectile}; every hit a shot landed:
## {id, target, amount, accepted}; how each shot ended, by id.
var _shots: Array[Dictionary] = []
var _hits: Array[Dictionary] = []
var _ends: Dictionary = {}
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
	await _phase_out_with_a_shot_in_flight()
	await _phase_into_dungeon(2)
	await _phase_room_one(2)
	SceneTransition.find_in(self).transition_to_scene(HUB)
	await _pause(1.6)
	_record(current_scene.scene_file_path == HUB and _projectiles_anywhere() == 0
			and int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)) == 0,
		"END) back in the hub after the second dungeon: no projectile anywhere, nothing orphaned")
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
		return e.attack is EnemyMeleeAttack and e.get_state() == BasicEnemy.State.IDLE and not e.combat_enabled)
	_record(shipped and _projectiles_anywhere() == 0,
		"G%d) dungeon %d: the shipped five, all melee, parked as M12.2 left them; no projectile in the scene%s" % [
			run, run, " — nothing left of the first dungeon's shots" if run == 2 else ""])


# --- room one: a ranged beside the melee -----------------------------------------------------------------

func _phase_room_one(run: int) -> void:
	var dungeon: DungeonController = current_scene as DungeonController
	var p: Player = dungeon.get_player()
	var room: RoomController = dungeon.get_rooms()[0]
	var melee: Array[BasicEnemy] = _room_enemies(room)
	var ranged: BasicEnemy = _spawn_ranged(dungeon, ROOM_ONE_RANGED)
	var listeners: Array = [ranged.state_changed.get_connections().size(),
		ranged.health_component.died.get_connections().size(),
		ranged.health_component.damaged.get_connections().size(),
		(ranged.attack as EnemyRangedAttack).fired.get_connections().size()]
	var same: bool = true
	if run == 1:
		_first_listeners = listeners
	else:
		same = listeners == _first_listeners
	p.hurtbox.set_invulnerable(false)
	p.health_component.heal(p.health_component.max_health)
	p.global_position = ROOM_ANCHORS[0]
	var first_shot: int = _shots.size()
	var first_hit: int = _hits.size()
	var closest_ranged: float = 100.0
	var melee_closed: bool = false
	var elapsed: float = 0.0
	while elapsed < 12.0 and not (melee_closed and _hits_on(p, first_hit) >= 2):
		p.global_position = ROOM_ANCHORS[0]
		if p.health_component.current_health < 50.0:
			p.health_component.heal(p.health_component.max_health)
		if ranged.get_target() != null:
			closest_ranged = minf(closest_ranged, ranged.targeting.get_distance())
		for e in melee:
			melee_closed = melee_closed or (e.get_target() == p and e.targeting.get_distance() <= e.attack_range)
		await physics_frame
		elapsed += DT
	var mine: Array[Dictionary] = _hits.slice(first_hit).filter(func(h: Dictionary) -> bool: return h["target"] == p)
	var once_each: bool = true
	var ids: Dictionary = {}
	for h in mine:
		once_each = once_each and not ids.has(h["id"]) and h["amount"] == 12.0 and h["accepted"]
		ids[h["id"]] = true
	_record(same and melee_closed and closest_ranged >= ranged.minimum_combat_distance and _shots.size() > first_shot
			and mine.size() >= 2 and once_each,
		"R%d.1) room one, a ranged beside its melee: the melee close in, the ranged keeps its distance (never nearer than %.1f m) and fires — %d shots landed on the player, 12 each, one hit a shot%s" % [
			run, closest_ranged, mine.size(), "; its listeners as in the first dungeon" if run == 2 else ""])

	if run == 1:
		# A shot read and dodged through: the i-frames refuse it.
		p.health_component.heal(p.health_component.max_health)
		p.combat.restore_stamina(p.combat.get_max_stamina())
		var before: int = _shots.size()
		await _until(func() -> bool:
			p.global_position = ROOM_ANCHORS[0]
			return _shots.size() > before, 6.0)
		var shot: Dictionary = _shots[before] if _shots.size() > before else {}
		var projectile: Projectile = shot.get("projectile")
		await _until(func() -> bool:
			p.global_position = ROOM_ANCHORS[0]
			return not is_instance_valid(projectile) or projectile.global_position.distance_to(p.hurtbox.get_center()) < 2.2, 2.0)
		var speed: float = p.effective_dodge_speed
		p.effective_dodge_speed = 0.0
		_press(p, &"dodge")
		var dodging: bool = p.combat.get_state() == PlayerCombat.State.DODGING
		await _until(func() -> bool: return _ends.has(shot.get("id", -1)), 3.0)
		p.effective_dodge_speed = speed
		var refused: bool = _hits.any(func(h: Dictionary) -> bool: return h["id"] == shot.get("id", -1) and not h["accepted"])
		var took: bool = _hits.any(func(h: Dictionary) -> bool: return h["id"] == shot.get("id", -1) and h["accepted"])
		_record(dodging and refused and not took,
			"R1.2) a shot read and dodged into: it reaches the player inside the i-frames and is refused — no damage — and flies on")

	# Locked on, the ring over it, a critical heavy kills the ranged.
	p.hurtbox.set_invulnerable(true)
	var indicator: TargetLockIndicator = get_first_node_in_group(TargetLockIndicator.GROUP) as TargetLockIndicator
	_stick(p, ranged)
	await _frames(2)
	_press(p, &"target_lock")
	var locked: bool = p.targeting.get_target() == ranged
	await _frames(2)
	var ringed: bool = indicator != null and indicator.get_target() == ranged and indicator.is_showing()
	var xp: int = p.progression.get_total_xp()
	var deaths: Array[int] = [0]
	ranged.enemy_died.connect(func(_dead: RoomCombatant) -> void: deaths[0] += 1)
	ranged.health_component.current_health = 60.0
	_no_crits.critical_chance = 1.0
	await _heavy(p, ranged)
	_no_crits.critical_chance = 0.0
	await _pause(0.4)
	_record(locked and ringed and ranged.has_died() and deaths[0] == 1 and p.progression.get_total_xp() - xp == ranged.get_xp_reward()
			and not p.targeting.is_locked() and not indicator.is_showing(),
		"R%d.3) locked on the ranged, the ring over it, a critical heavy kills it: one death, %d XP once, the lock and the ring let go" % [
			run, ranged.get_xp_reward()])
	for e in melee:
		await _kill(p, e)
	await _pause(0.5)
	_record(room.is_cleared(), "R%d.4) the melee killed too: the room clears — the ranged, not the room's, changes nothing of it" % run)


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
	var ranged: BasicEnemy = _spawn_ranged(dungeon, ROOM_TWO_RANGED)
	await _frames(3)
	ranged.health_component.current_health = 10.0
	var player_xp: int = p.progression.get_total_xp()
	var shadow_xp: int = _shadow_total_xp(shadow.instance)
	p.shadow_commander.set_mode(BasicMeleeShadow.CommandMode.AGGRESSIVE)
	shadow.set_manual_target(ranged)
	var killed: bool = await _until(func() -> bool:
		p.global_position = ROOM_ANCHORS[1]
		return ranged.has_died(), 15.0)
	await _pause(0.3)
	var reward: int = ranged.get_xp_reward()
	var cut: int = int(round(reward * PlayerProgression.SHADOW_KILL_SHARE))
	var player_gain: int = p.progression.get_total_xp() - player_xp
	var shadow_gain: int = _shadow_total_xp(shadow.instance) - shadow_xp
	_record(armed and killed and ranged.get_killer() == shadow and shadow_gain == cut and player_gain == reward - cut,
		"S1) the shadow hunts down a ranged and kills it: 70/30 — shadow +%d, player +%d of its %d" % [shadow_gain, player_gain, reward])
	p.shadow_commander.set_mode(BasicMeleeShadow.CommandMode.FOLLOW)
	p.hurtbox.set_invulnerable(true)
	for e in melee:
		await _kill(p, e)
	await _pause(0.5)
	_record(room.is_cleared(), "S2) room two's melee killed: the room clears")


# --- the boss, and leaving with a shot in the air ---------------------------------------------------------

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
	_record(awake and locked and boss.has_died() and boss.get_node_or_null("Attack") == null
			and dungeon.get_state() == DungeonController.DungeonState.COMPLETED,
		"B1) the boss — its own AI, no archetype attack — is locked and killed; the dungeon completes")


func _phase_out_with_a_shot_in_flight() -> void:
	var dungeon: DungeonController = current_scene as DungeonController
	var p: Player = dungeon.get_player()
	p.global_position = EXIT_POS
	var ranged: BasicEnemy = _spawn_ranged(dungeon, EXIT_POS + Vector3(0, 0, 6))
	var before: int = _shots.size()
	var fired: bool = await _until(func() -> bool:
		p.global_position = EXIT_POS
		return _shots.size() > before, 6.0)
	var in_flight: bool = fired and is_instance_valid(_shots[before]["projectile"])
	dungeon.exit_portal.activate()
	await _pause(1.6)
	_record(in_flight and is_instance_valid(ranged) == false and current_scene.scene_file_path == HUB
			and _projectiles_anywhere() == 0 and int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)) == 0,
		"O1) leaving through the exit with a ranged's shot in the air: the shot goes with the dungeon — in the hub no projectile, nothing orphaned")


# --- helpers ------------------------------------------------------------------------------------------------

func _spawn_ranged(dungeon: DungeonController, at: Vector3) -> BasicEnemy:
	var enemy: BasicEnemy = RANGED_SCENE.instantiate() as BasicEnemy
	enemy.position = at
	dungeon.add_child(enemy)
	var ranged: EnemyRangedAttack = enemy.attack as EnemyRangedAttack
	ranged.fired.connect(func(projectile: Projectile) -> void:
		var id: int = projectile.get_instance_id()
		_shots.append({"enemy_name": String(enemy.name), "id": id, "projectile": projectile})
		projectile.hitbox.hit_landed.connect(func(target: Node, hit: DamageInfo) -> void:
			_hits.append({"id": id, "target": target, "amount": hit.amount, "accepted": false}))
		projectile.hitbox.hit_accepted.connect(func(_target: Node, _hit: DamageInfo) -> void:
			_hits[-1]["accepted"] = true)
		projectile.finished.connect(func(reason: StringName) -> void: _ends[id] = reason))
	enemy.set_combat_enabled(true)
	return enemy


func _hits_on(target: Node, since: int) -> int:
	return _hits.slice(since).filter(func(h: Dictionary) -> bool: return h["target"] == target and h["accepted"]).size()


func _projectiles_anywhere() -> int:
	return root.find_children("*", "Projectile", true, false).size()


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
