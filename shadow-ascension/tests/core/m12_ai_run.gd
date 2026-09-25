extends SceneTree

## M12.1 — the enemy AI foundation through the whole game.
##
##   godot --headless --path . --script res://tests/core/m12_ai_run.gd
##
## Menu -> New Game -> hub (a shadow summoned) -> gate -> dungeon: every enemy
## parked, IDLE, no target -> room one armed: both notice the player (IDLE ->
## ALERT -> CHASE, the same tick), come to it and swing at it; the player kills
## them — X -> DEAD, 25 XP each, once — and the room clears -> room two: the
## player and the shadow against three; the enemies keep to the player (the
## shipped policy), never flicker between targets, and every kill is paid to
## whoever made it, a shadow's 70/30 -> the boss, on its own AI: locked, hit,
## killed, the dungeon completed -> hub -> a second dungeon: every enemy parked
## and clean again, no listener doubled; room one armed, they find their way to
## the player, and die -> hub, nothing orphaned.
##
## The player is invulnerable throughout: this is about what the enemies decide.

const BOOT: String = "res://Main.tscn"
const HUB: String = "res://scenes/core/hub.tscn"
const DT: float = 1.0 / 60.0
const ROOM_ANCHORS: Array[Vector3] = [
	Vector3(0, 0.1, -13), Vector3(0, 0.1, -33), Vector3(0, 0.1, -53)
]
const EXIT_POS: Vector3 = Vector3(0, 0.1, -65)
const STRIKE_RANGE: float = 1.6

var _no_crits: PlayerCombatData = preload("res://resources/characters/player_combat.tres")
var _shadow_data: ShadowData = preload("res://resources/shadows/basic_melee_shadow.tres")
var _state: Node = null
var _pass: int = 0
var _fail: int = 0
## Per enemy: its transitions ("FROM>TO") and every target it took (a name, or
## "-" for none), since it was watched.
var _transitions: Dictionary = {}
var _targets: Dictionary = {}
var _first_listeners: Dictionary = {}


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
	_record(current_scene.scene_file_path == HUB
			and int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)) == 0,
		"END) back in the hub after the second dungeon: nothing orphaned")
	print("[SUMMARY] passed=%d failed=%d" % [_pass, _fail])
	await _pause(0.3)
	quit()


# --- the hub ---------------------------------------------------------------------------------------

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
	var clean: bool = true
	var listeners: Dictionary = {}
	for enemy in _basic_enemies(dungeon):
		clean = clean and enemy.get_state() == BasicMeleeEnemy.State.IDLE and enemy.get_target() == null \
			and not enemy.combat_enabled and enemy._attack_phase == BasicMeleeEnemy.AttackPhase.NONE \
			and enemy._cooldown_timer == 0.0
		listeners[String(enemy.get_path())] = [enemy.state_changed.get_connections().size(),
			enemy.targeting.target_changed.get_connections().size(),
			enemy.health_component.died.get_connections().size(),
			enemy.health_component.damaged.get_connections().size()]
		_watch(enemy)
	var boss: DungeonBoss = _boss(dungeon)
	var same: bool = true
	if run == 1:
		_first_listeners = listeners
	else:
		same = listeners == _first_listeners
	_record(clean and listeners.size() == 5 and same and boss != null and not boss.combat_enabled,
		"G%d) dungeon %d: all five enemies parked, IDLE, no target, no swing, no cooldown; the boss parked;%s" % [
			run, run, " listeners exactly as in the first dungeon — none doubled" if run == 2 else " their listeners noted"])


# --- room one: noticed, chased, swung at; killed -------------------------------------------------------

func _phase_room_one(run: int) -> void:
	var dungeon: DungeonController = current_scene as DungeonController
	var p: Player = dungeon.get_player()
	p.hurtbox.set_invulnerable(true)
	var room: RoomController = dungeon.get_rooms()[0]
	var enemies: Array[BasicMeleeEnemy] = []
	for combatant in room.get_enemies():
		enemies.append(combatant as BasicMeleeEnemy)
	var start: Array[float] = []
	p.global_position = ROOM_ANCHORS[0]
	await _frames(2)
	for enemy in enemies:
		start.append(_flat(enemy.global_position - p.global_position).length())
	var noticed: bool = await _until(func() -> bool:
		return enemies.all(func(e: BasicMeleeEnemy) -> bool: return e.get_state() != BasicMeleeEnemy.State.IDLE), 2.0)
	var same_tick: bool = true
	for enemy in enemies:
		var seen: Array = _transitions[enemy]
		same_tick = same_tick and seen.size() >= 2 and seen[0] == "IDLE>ALERT" and seen[1] == "ALERT>CHASE"
	# They come to the player, and swing at it.
	var arrived: bool = await _until(func() -> bool:
		return enemies.any(func(e: BasicMeleeEnemy) -> bool: return e.get_state() == BasicMeleeEnemy.State.ATTACK), 8.0)
	var closed: bool = true
	for i in enemies.size():
		closed = closed and _flat(enemies[i].global_position - p.global_position).length() < start[i]
	_record(noticed and same_tick and arrived and closed,
		"R%d.1) room one armed: both notice the player — IDLE -> ALERT -> CHASE — find their way to it and swing at it" % run)

	var xp: int = p.progression.get_total_xp()
	for enemy in enemies:
		await _kill(p, enemy)
	await _pause(0.5)
	var ended: bool = true
	for enemy in enemies:
		var seen: Array = _transitions[enemy]
		ended = ended and enemy.has_died() and seen[-1].ends_with(">DEAD") and enemy.get_target() == null \
			and enemy.get_state() == BasicMeleeEnemy.State.DEAD
	var reward: int = 0
	for enemy in enemies:
		reward += enemy.get_xp_reward()
	_record(ended and room.is_cleared() and p.progression.get_total_xp() - xp == reward,
		"R%d.2) the player kills both: each ends X -> DEAD with no target, %d XP paid once in all, the room clears" % [run, reward])


# --- room two: the player and the shadow against three --------------------------------------------------

func _phase_room_two() -> void:
	var dungeon: DungeonController = current_scene as DungeonController
	var p: Player = dungeon.get_player()
	var shadow: BasicMeleeShadow = p.shadow_summoner.get_active_node()
	var room: RoomController = dungeon.get_rooms()[1]
	var enemies: Array[BasicMeleeEnemy] = []
	for combatant in room.get_enemies():
		enemies.append(combatant as BasicMeleeEnemy)
	p.global_position = ROOM_ANCHORS[1]
	shadow.global_position = ROOM_ANCHORS[1] + Vector3(1.5, 0, 0)
	p.shadow_commander.set_mode(BasicMeleeShadow.CommandMode.AGGRESSIVE)
	var armed: bool = await _until(func() -> bool: return room.get_state() == RoomController.RoomState.ACTIVE, 2.0)
	await _until(func() -> bool:
		return enemies.all(func(e: BasicMeleeEnemy) -> bool: return e.get_target() != null), 3.0)
	var player_xp: int = p.progression.get_total_xp()
	var shadow_xp: int = _shadow_total_xp(shadow.instance)
	# The shadow is sent at one, nearly finished; the player takes the other two.
	var shadows_own: BasicMeleeEnemy = enemies[1]
	shadows_own.health_component.current_health = 20.0
	shadow.set_manual_target(shadows_own)
	var elapsed: float = 0.0
	while elapsed < 30.0 and not enemies.all(func(e: BasicMeleeEnemy) -> bool: return e.has_died()):
		var mine: BasicMeleeEnemy = null
		for enemy in enemies:
			if not enemy.has_died() and enemy != shadows_own:
				mine = enemy
		if mine == null and not shadows_own.has_died() and elapsed > 15.0:
			mine = shadows_own
		if mine != null and p.combat.get_state() == PlayerCombat.State.IDLE:
			p.global_position = mine.global_position + Vector3(0, 0, STRIKE_RANGE)
			p.camera_rig.rotation.y = 0.0
			p.camera_rig.attack_light_pressed.emit()
		await physics_frame
		elapsed += DT
	await _pause(0.5)
	var by_player: int = 0
	var by_shadow: int = 0
	var expected_player: int = 0
	var expected_shadow: int = 0
	for enemy in enemies:
		var reward: int = enemy.get_xp_reward()
		if enemy.get_killer() == p:
			by_player += 1
			expected_player += reward
		elif enemy.get_killer() == shadow:
			by_shadow += 1
			var cut: int = int(round(reward * PlayerProgression.SHADOW_KILL_SHARE))
			expected_shadow += cut
			expected_player += reward - cut
	var player_gain: int = p.progression.get_total_xp() - player_xp
	var shadow_gain: int = _shadow_total_xp(shadow.instance) - shadow_xp
	_record(armed and enemies.all(func(e: BasicMeleeEnemy) -> bool: return e.has_died()) and room.is_cleared()
			and by_player + by_shadow == 3 and by_shadow >= 1 and by_player >= 1
			and player_gain == expected_player and shadow_gain == expected_shadow,
		"PS1) the player and the shadow clear three: %d kills the player's, %d the shadow's — XP to whoever made it, a shadow's split 70/30 (player +%d, shadow +%d)" % [
			by_player, by_shadow, player_gain, shadow_gain])
	var only_player: bool = true
	var steady: bool = true
	for enemy in enemies:
		var taken: Array = _targets[enemy]
		for name in taken:
			only_player = only_player and (name == "-" or name == String(p.name))
		steady = steady and not taken.is_empty() and taken.size() <= 4
	_record(only_player and steady,
		"PS2) with the shadow among them, every enemy fought the player — the shipped policy — and took a target at most twice (%s)" % [
			enemies.map(func(e: BasicMeleeEnemy) -> Array: return _targets[e])])
	p.shadow_commander.set_mode(BasicMeleeShadow.CommandMode.FOLLOW)


# --- the boss, on its own AI ------------------------------------------------------------------------

func _phase_boss() -> void:
	var dungeon: DungeonController = current_scene as DungeonController
	var p: Player = dungeon.get_player()
	p.health_component.heal(p.health_component.max_health)
	p.global_position = ROOM_ANCHORS[2]
	var boss: DungeonBoss = _boss(dungeon)
	var bar: BossHealthBar = dungeon.get_node("BossHealthBar")
	var awake: bool = await _until(func() -> bool: return boss.combat_enabled and bar.is_showing(), 6.0)
	_stick(p, boss)
	await _frames(2)
	_press(p, &"target_lock")
	var locked: bool = p.targeting.get_target() == boss
	var hp: float = boss.health_component.current_health
	await _heavy(p, boss)
	var hit: bool = boss.health_component.current_health < hp
	boss.health_component.current_health = 40.0
	await _heavy(p, boss)
	await _pause(0.6)
	_record(awake and locked and hit and boss.has_died() and not p.targeting.is_locked()
			and dungeon.get_state() == DungeonController.DungeonState.COMPLETED,
		"B1) the boss — its own AI, not migrated — wakes, is locked, hit and killed: the lock lets go, the dungeon completes")


func _phase_out_to_hub() -> void:
	var dungeon: DungeonController = current_scene as DungeonController
	var p: Player = dungeon.get_player()
	p.global_position = EXIT_POS
	await _pause(0.4)
	dungeon.exit_portal.activate()
	await _pause(1.6)
	_record(current_scene.scene_file_path == HUB
			and int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)) == 0,
		"O1) back in the hub: nothing of the first dungeon's enemies left behind")


# --- helpers ------------------------------------------------------------------------------------------

func _watch(enemy: BasicMeleeEnemy) -> void:
	_transitions[enemy] = []
	_targets[enemy] = []
	enemy.state_changed.connect(func(from: BasicMeleeEnemy.State, to: BasicMeleeEnemy.State) -> void:
		(_transitions[enemy] as Array).append("%s>%s" % [BasicMeleeEnemy.State.keys()[from], BasicMeleeEnemy.State.keys()[to]]))
	enemy.targeting.target_changed.connect(func(target: Node3D) -> void:
		(_targets[enemy] as Array).append(String(target.name) if target != null else "-"))


func _basic_enemies(dungeon: DungeonController) -> Array[BasicMeleeEnemy]:
	var out: Array[BasicMeleeEnemy] = []
	for room in dungeon.get_rooms():
		for combatant in room.get_enemies():
			var enemy: BasicMeleeEnemy = combatant as BasicMeleeEnemy
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


func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


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
