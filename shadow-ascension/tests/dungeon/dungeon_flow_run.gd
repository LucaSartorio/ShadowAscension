extends SceneTree

## End-to-end M4 loop with REAL scene changes. It swaps the running scene, so it
## cannot live as a normal test scene — run it as a SceneTree script:
##
##   godot --headless --path . --script res://tests/dungeon/dungeon_flow_run.gd
##
## The component-level assertions (fade, spam guards, exit portal states) live in
## dungeon_loop_test.tscn, which fakes the scene change. This one proves the real
## change_scene_to_file / reload_current_scene calls actually land.

const TEST_WORLD: String = "res://scenes/core/test_world.tscn"
const DUNGEON: String = "res://scenes/dungeons/dungeon_test.tscn"
const ROOM_ANCHORS: Array[Vector3] = [
	Vector3(0, 0.1, -13), Vector3(0, 0.1, -33), Vector3(0, 0.1, -53)
]
const EXIT_POS: Vector3 = Vector3(0, 0.1, -65)

var _pass: int = 0
var _fail: int = 0


func _initialize() -> void:
	change_scene_to_file(TEST_WORLD)
	await _pause(0.6)
	_record(current_scene.scene_file_path == TEST_WORLD, "1) test world is the running scene")

	# --- gate: real scene change ---
	var player: Player = current_scene.get_node("Player")
	var gate: DungeonGate = current_scene.get_node("DungeonGate")
	player.global_position = gate.global_position
	await _pause(0.3)
	_record(gate.activate(), "2) gate accepts interact from inside")
	await _pause(1.0)
	_record(current_scene.scene_file_path == DUNGEON, "3) the gate really loaded the dungeon (%s)" % current_scene.scene_file_path)

	# --- the run ---
	var dungeon: DungeonController = current_scene as DungeonController
	player = current_scene.get_node("Player")
	_record(player.global_position.z > -6.0, "4) the player spawned in the start room")
	_record(not dungeon.exit_portal.is_enabled(), "5) the exit portal starts dead")

	var all_cleared: bool = true
	for i in 3:
		player.global_position = ROOM_ANCHORS[i]
		await _pause(0.4)
		var room: RoomController = dungeon.get_rooms()[i]
		for enemy in room.get_enemies():
			enemy.hurtbox.receive_hit(1000.0, null)
		await _pause(0.5)
		if not room.is_cleared() or room.exit_door.is_locked():
			all_cleared = false
	_record(all_cleared, "6) all three rooms cleared and opened in sequence")
	_record(dungeon.get_state() == DungeonController.DungeonState.COMPLETED
			and dungeon.exit_portal.is_enabled()
			and dungeon.status_label.text == "DUNGEON COMPLETE",
		"7) dungeon COMPLETED, banner shown, exit portal live")

	# --- exit: real scene change back ---
	player.global_position = EXIT_POS
	await _pause(0.4)
	_record(dungeon.exit_portal.activate(), "8) the live exit accepts interact")
	await _pause(1.0)
	_record(current_scene.scene_file_path == TEST_WORLD, "9) the exit really returned to the test world (%s)" % current_scene.scene_file_path)
	var back: Player = current_scene.get_node("Player")
	_record(back.health_component.current_health == back.health_component.max_health and not back._is_dodging,
		"10) the returned player is controllable at full health")

	# --- second run, death, real reload ---
	var gate2: DungeonGate = current_scene.get_node("DungeonGate")
	back.global_position = gate2.global_position
	await _pause(0.3)
	gate2.activate()
	await _pause(1.0)
	var second: DungeonController = current_scene as DungeonController
	_record(current_scene.scene_file_path == DUNGEON
			and second.get_state() == DungeonController.DungeonState.NOT_STARTED,
		"11) a second run loads clean (state=%d)" % second.get_state())

	var player2: Player = current_scene.get_node("Player")
	player2.global_position = ROOM_ANCHORS[0]
	await _pause(0.4)
	_record(second.get_rooms()[0].get_state() == RoomController.RoomState.ACTIVE, "12) room 1 armed in the second run")

	var doomed_id: int = current_scene.get_instance_id()
	player2.health_component.receive_damage(1000.0)
	await _pause(0.3)
	_record(second.status_label.text == "YOU DIED"
			and second.get_state() == DungeonController.DungeonState.FAILED,
		"13) death shows YOU DIED and marks the run FAILED")

	await _pause(2.5)
	var restarted: DungeonController = current_scene as DungeonController
	var fresh_player: Player = current_scene.get_node("Player")
	_record(current_scene.get_instance_id() != doomed_id, "14) the dungeon really reloaded (new scene instance)")
	_record(restarted.get_state() == DungeonController.DungeonState.NOT_STARTED
			and restarted.get_rooms()[0].get_state() == RoomController.RoomState.IDLE
			and restarted.get_rooms()[0].exit_door.is_locked()
			and not restarted.exit_portal.is_enabled(),
		"15) the restarted run is back to its initial state")
	_record(fresh_player.health_component.current_health == fresh_player.health_component.max_health,
		"16) the restarted player is at full health (%.0f/%.0f)" % [
			fresh_player.health_component.current_health, fresh_player.health_component.max_health])

	print("[SUMMARY] passed=%d failed=%d" % [_pass, _fail])
	await _pause(0.3)
	quit()


func _record(passed: bool, description: String) -> void:
	if passed:
		_pass += 1
		print("[PASS] " + description)
	else:
		_fail += 1
		print("[FAIL] " + description)


## Real time, not frame counts: headless runs frames far faster than wall clock,
## so frame counting would skip past timers like death_restart_delay.
func _pause(seconds: float) -> void:
	await create_timer(seconds).timeout
