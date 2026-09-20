extends Node3D

## M4.1 Dungeon Foundation — gate, room lifecycle, door locking, sequential
## progression, dungeon completion.

const TEST_WORLD: PackedScene = preload("res://scenes/core/test_world.tscn")
const DUNGEON: PackedScene = preload("res://scenes/dungeons/dungeon_test.tscn")

# world-space anchors, derived from the room transforms in dungeon_test.tscn
const ROOM1_TRIGGER: Vector3 = Vector3(0, 0.1, -13)
const ROOM1_DOOR_Z: float = -26.0
const ROOM2_TRIGGER: Vector3 = Vector3(0, 0.1, -33)
const BOSS_TRIGGER: Vector3 = Vector3(0, 0.1, -53)

var _pass: int = 0
var _fail: int = 0

var _dungeon: DungeonController = null
var _player: Player = null
var _room1: RoomController = null
var _room2: RoomController = null
var _boss: RoomController = null
var _started_events: Array[String] = []
var _cleared_events: Array[String] = []
var _completed_count: int = 0


func _ready() -> void:
	_run()


func _run() -> void:
	_reset_session()
	await _wait(0.2)
	await _gate_tests()
	await _dungeon_tests()
	print("[SUMMARY] passed=%d failed=%d" % [_pass, _fail])
	get_tree().quit()


func _wait(t: float) -> void:
	await get_tree().create_timer(t).timeout


func _record(passed: bool, description: String) -> void:
	if passed:
		_pass += 1
		print("[PASS] " + description)
	else:
		_fail += 1
		print("[FAIL] " + description)


# --- gate ---------------------------------------------------------------------

func _gate_tests() -> void:
	var world: Node3D = TEST_WORLD.instantiate() as Node3D
	add_child(world)
	await _wait(0.5)

	var player: Player = world.get_node("Player")
	var gate: DungeonGate = world.get_node("DungeonGate")
	# drive the gate directly instead of changing scene mid-suite
	gate.change_scene_on_activate = false
	var activations: Array[String] = []
	gate.gate_activated.connect(func(target: String) -> void: activations.append(target))

	_record(player != null and gate != null, "1) test_world instantiates with player and gate")
	var ui_idle: InteractionPrompt = get_tree().get_first_node_in_group(InteractionPrompt.GROUP) as InteractionPrompt
	_record(gate.visible and ui_idle != null and not ui_idle.is_showing(),
		"2) gate is visible, prompt hidden until the player is close")

	# far away: interacting must do nothing
	player.global_position = Vector3(0, 0.1, 10)
	await _wait(0.3)
	var far_result: bool = gate.activate()
	_record(not far_result and activations.is_empty() and not gate.is_player_in_range(),
		"3) interact outside the gate does nothing (activated=%s events=%d)" % [far_result, activations.size()])

	# step into the gate
	player.global_position = gate.global_position + Vector3(0, 0.1, 0)
	await _wait(0.3)
	var in_range: bool = gate.is_player_in_range()
	var ui: InteractionPrompt = get_tree().get_first_node_in_group(InteractionPrompt.GROUP) as InteractionPrompt
	var prompt_shown: bool = ui != null and ui.is_showing() and ui.get_text() == gate.prompt_text
	_record(in_range and prompt_shown, "4) player inside the gate area shows the prompt (in_range=%s prompt='%s')" % [
		in_range, ui.get_text() if ui != null else "<no ui>"])

	var near_result: bool = gate.activate()
	var target_ok: bool = activations.size() == 1 and activations[0] == "res://scenes/dungeons/dungeon_test.tscn"
	_record(near_result and target_ok, "5) interact inside the gate targets the dungeon (%s)" % [
		activations[0] if activations.size() > 0 else "<none>"])

	world.queue_free()
	await _wait(0.3)


# --- dungeon ------------------------------------------------------------------

func _dungeon_tests() -> void:
	_dungeon = DUNGEON.instantiate() as DungeonController
	add_child(_dungeon)
	await _wait(0.6)

	_player = _dungeon.get_node("Player")
	var rooms: Array[RoomController] = _dungeon.get_rooms()
	_room1 = rooms[0]
	_room2 = rooms[1]
	_boss = rooms[2]
	for room in rooms:
		room.room_started.connect(func(r: RoomController) -> void: _started_events.append(r.name))
		room.room_cleared.connect(func(r: RoomController) -> void: _cleared_events.append(r.name))
	_dungeon.dungeon_completed.connect(func() -> void: _completed_count += 1)

	# 6) spawn
	var in_start: bool = _player.global_position.z > -6.0 and absf(_player.global_position.x) < 6.0
	var single_player: bool = get_tree().get_nodes_in_group("player").size() == 1
	_record(in_start and single_player, "6) player spawns in the start room, exactly one player (pos=%s count=%d)" % [
		_player.global_position, get_tree().get_nodes_in_group("player").size()])

	# 7) enemies parked
	var all_parked: bool = true
	for room in rooms:
		for enemy in room.get_enemies():
			if enemy.combat_enabled:
				all_parked = false
	_record(all_parked, "7) every room's enemies start dormant")

	# 26) dormant enemies really do nothing: park the player right next to one
	var r1_enemy: BasicMeleeEnemy = _room1.get_enemies()[0] as BasicMeleeEnemy
	var enemy_pos: Vector3 = r1_enemy.global_position
	_player.global_position = enemy_pos + Vector3(1.2, 0, 0)
	var hp_before: float = _player.health_component.current_health
	await _wait(1.5)
	var idle_state: bool = r1_enemy._state == BasicMeleeEnemy.State.IDLE
	var no_damage: bool = _player.health_component.current_health == hp_before
	var no_drift: bool = r1_enemy.global_position.distance_to(enemy_pos) < 0.1
	_record(idle_state and no_damage and no_drift,
		"26) dormant enemy does not detect, chase or attack (state=%d dmg=%.0f drift=%.2f)" % [
			r1_enemy._state, hp_before - _player.health_component.current_health,
			r1_enemy.global_position.distance_to(enemy_pos)])

	# 28) locked door really blocks
	_player.global_position = Vector3(0, 0.1, ROOM1_DOOR_Z + 1.5)
	await get_tree().physics_frame
	var blocked_while_locked: bool = _player.test_move(_player.global_transform, Vector3(0, 0, -3.0))
	_record(_room1.exit_door.is_locked() and blocked_while_locked,
		"28) locked door blocks the player (locked=%s blocked=%s)" % [_room1.exit_door.is_locked(), blocked_while_locked])

	# 8/9/10) entering room 1
	_player.global_position = ROOM1_TRIGGER
	await _wait(0.4)
	var started_once: bool = _started_events.count("CombatRoom1") == 1
	var active: bool = _room1.get_state() == RoomController.RoomState.ACTIVE
	_record(started_once and active, "8) entering room 1 arms it exactly once (events=%d state=%d)" % [
		_started_events.count("CombatRoom1"), _room1.get_state()])
	_record(_room1.exit_door.is_locked(), "9) room 1 exit door locks on start")
	var r1_live: bool = true
	for enemy in _room1.get_enemies():
		if not enemy.combat_enabled:
			r1_live = false
	_record(r1_live, "10) room 1 enemies wake up")

	# 27) later rooms untouched
	var later_parked: bool = true
	for room in [_room2, _boss]:
		for enemy in room.get_enemies():
			if enemy.combat_enabled:
				later_parked = false
	_record(later_parked, "27) rooms 2 and boss stay dormant while room 1 fights")

	# 11/30) player combat inside the dungeon
	var target: BasicMeleeEnemy = _room1.get_enemies()[0] as BasicMeleeEnemy
	_player.global_position = target.global_position + Vector3(0, 0, 1.4)
	_player.camera_rig.rotation.y = 0.0
	_player.visual_root.rotation.y = 0.0
	var enemy_hp: float = target.health_component.current_health
	_player.camera_rig.attack_light_pressed.emit()
	await _wait(0.6)
	var dealt: float = enemy_hp - target.health_component.current_health
	_record(dealt == 20.0, "11) player attack damages a dungeon enemy (%.0f damage)" % dealt)

	# 31) enemy combat inside the dungeon
	var php: float = _player.health_component.current_health
	await _wait(2.5)
	var took: bool = _player.health_component.current_health < php
	_record(took, "31) dungeon enemies damage the player (hp %.0f -> %.0f)" % [
		php, _player.health_component.current_health])

	# 32) dodge still works in the dungeon
	_player.health_component.current_health = 100.0
	_player._dodge_cooldown_remaining = 0.0
	_player._on_dodge_pressed()
	var dodging: bool = _player._is_dodging
	await _wait(0.1)
	var iframes: bool = _player.hurtbox.is_invulnerable
	await _wait(0.5)
	_record(dodging and iframes, "32) dodge and i-frames work in the dungeon (dodging=%s iframe=%s)" % [dodging, iframes])

	# 12) one of two dead -> still locked
	_player.global_position = Vector3(0, 0.1, -13)
	_room1.get_enemies()[0].hurtbox.receive_hit(1000.0, null)
	await _wait(0.3)
	var still_locked: bool = _room1.exit_door.is_locked()
	var not_cleared: bool = not _room1.is_cleared()
	_record(still_locked and not_cleared, "12) killing one of two leaves room 1 locked (locked=%s cleared=%s)" % [
		still_locked, _room1.is_cleared()])

	# 13/14/15) clear room 1
	_room1.get_enemies()[1].hurtbox.receive_hit(1000.0, null)
	await _wait(0.6)
	_record(_room1.is_cleared() and _cleared_events.count("CombatRoom1") == 1,
		"13) room 1 clears when the last enemy dies (state=%d events=%d)" % [
			_room1.get_state(), _cleared_events.count("CombatRoom1")])
	_record(not _room1.exit_door.is_locked(), "14) room 1 exit door unlocks")

	_player.global_position = Vector3(0, 0.1, ROOM1_DOOR_Z + 1.5)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var passable: bool = not _player.test_move(_player.global_transform, Vector3(0, 0, -3.0))
	_record(passable, "15/29) unlocked door is passable (blocked=%s)" % [not passable])

	# 16) backtracking does not restart it
	_player.global_position = ROOM1_TRIGGER
	await _wait(0.4)
	_record(_started_events.count("CombatRoom1") == 1 and _room1.is_cleared(),
		"16) re-entering a cleared room does not restart it (starts=%d cleared=%s)" % [
			_started_events.count("CombatRoom1"), _room1.is_cleared()])

	# 17/18/19/20) room 2, same controller
	_record(_room2.get_script() == _room1.get_script(), "17) room 2 runs the same RoomController script")
	_player.global_position = ROOM2_TRIGGER
	await _wait(0.4)
	var r2_enemies: Array[RoomCombatant] = _room2.get_enemies()
	var r2_live: bool = r2_enemies.size() == 3
	for enemy in r2_enemies:
		if not enemy.combat_enabled:
			r2_live = false
	_record(r2_live, "18) room 2 activates 3 enemies (count=%d)" % r2_enemies.size())

	var map: RID = _room2.navigation_region.get_navigation_map()
	var detour: PackedVector3Array = NavigationServer3D.map_get_path(
		map, Vector3(-3.5, 0, -33.0), Vector3(-3.5, 0, -39.0), true)
	var dev: float = 0.0
	for point in detour:
		dev = maxf(dev, absf(point.x + 3.5))
	_record(detour.size() >= 2 and dev > 0.6,
		"19) room 2 navigation routes around its obstacle (lateral deviation %.2f)" % dev)

	# 20) door holds until every enemy is dead
	r2_enemies[0].hurtbox.receive_hit(1000.0, null)
	r2_enemies[1].hurtbox.receive_hit(1000.0, null)
	await _wait(0.4)
	var held: bool = _room2.exit_door.is_locked() and not _room2.is_cleared()
	r2_enemies[2].hurtbox.receive_hit(1000.0, null)
	await _wait(0.5)
	var opened: bool = not _room2.exit_door.is_locked() and _room2.is_cleared()
	_record(held and opened, "20) room 2 door holds until all three die (held=%s opened=%s)" % [held, opened])

	# 21/22/23/24/25) boss placeholder
	_player.global_position = BOSS_TRIGGER
	await _wait(0.4)
	var boss_active: bool = _boss.get_state() == RoomController.RoomState.ACTIVE
	var boss_enemy_live: bool = _boss.get_enemies()[0].combat_enabled
	_record(boss_active and boss_enemy_live, "21) boss room activates (state=%d enemy_live=%s)" % [
		_boss.get_state(), boss_enemy_live])

	var boss_enemy: RoomCombatant = _boss.get_enemies()[0]
	boss_enemy.hurtbox.receive_hit(1000.0, null)
	await _wait(0.5)
	_record(boss_enemy.health_component.is_dead, "22) the boss-room occupant can be killed")
	_record(_boss.is_cleared() and not _boss.exit_door.is_locked(), "23) boss room clears and opens")
	_record(_dungeon.get_state() == DungeonController.DungeonState.COMPLETED and _completed_count == 1,
		"24) dungeon reaches COMPLETED exactly once (state=%d signals=%d)" % [
			_dungeon.get_state(), _completed_count])
	_record(_dungeon.status_label.visible and _dungeon.status_label.text == "DUNGEON COMPLETE",
		"25) DUNGEON COMPLETE feedback is visible ('%s')" % _dungeon.status_label.text)

	# progression order
	_record(",".join(_cleared_events) == "CombatRoom1,CombatRoom2,BossRoom",
		"seq) rooms cleared in dungeon order: %s" % str(_cleared_events))


## Every suite starts from a clean session: PlayerRuntimeState now carries
## progression and health across scene changes, so without this a later test
## would inherit whatever an earlier one left behind.
func _reset_session() -> void:
	var state: Node = get_tree().root.get_node_or_null("PlayerRuntimeState")
	if state != null:
		state.reset_runtime_state()
