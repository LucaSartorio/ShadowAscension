extends SceneTree

## End-to-end M4 loop with REAL scene changes: two consecutive full runs, then a
## death and restart. It swaps the running scene, so it cannot live as a normal
## test scene — run it as a SceneTree script:
##
##   godot --headless --path . --script res://tests/dungeon/dungeon_flow_run.gd
##
## Component-level assertions (fade, spam guards, portal states) live in
## dungeon_loop_test.tscn, which fakes the scene change. This one proves the real
## change_scene_to_file / reload_current_scene calls land, and that repeating the
## loop does not accumulate nodes.

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

	var after_run_1: Dictionary = await _full_run(1)
	var after_run_2: Dictionary = await _full_run(2)

	# ROADMAP exit criterion: room transitions must not leak nodes. Two identical
	# loops ending in the same scene should end with the same node count.
	var node_growth: int = after_run_2["nodes"] - after_run_1["nodes"]
	_record(absi(node_growth) <= 2,
		"12) a second identical loop leaks no nodes (run1=%d run2=%d delta=%+d)" % [
			after_run_1["nodes"], after_run_2["nodes"], node_growth])
	_record(after_run_2["orphans"] <= after_run_1["orphans"],
		"13) no orphan nodes accumulate across loops (run1=%d run2=%d)" % [
			after_run_1["orphans"], after_run_2["orphans"]])

	await _death_and_restart()

	print("[SUMMARY] passed=%d failed=%d" % [_pass, _fail])
	await _pause(0.3)
	quit()


## Test world -> gate -> dungeon -> clear all rooms -> complete -> exit -> test
## world. Returns node/orphan counts measured back in the test world.
func _full_run(n: int) -> Dictionary:
	var player: Player = current_scene.get_node("Player")
	var gate: DungeonGate = current_scene.get_node("DungeonGate")
	player.global_position = gate.global_position
	await _pause(0.3)
	_record(gate.activate(), "RUN %d/2) gate accepts interact from inside" % n)
	await _pause(1.0)
	_record(current_scene.scene_file_path == DUNGEON,
		"RUN %d/2) the gate really loaded the dungeon" % n)

	var dungeon: DungeonController = current_scene as DungeonController
	player = current_scene.get_node("Player")
	_record(player.global_position.z > -6.0
			and dungeon.get_state() == DungeonController.DungeonState.NOT_STARTED
			and not dungeon.exit_portal.is_enabled(),
		"RUN %d/2) fresh dungeon: player in the start room, NOT_STARTED, exit dead" % n)

	var all_ok: bool = true
	for i in 3:
		player.global_position = ROOM_ANCHORS[i]
		await _pause(0.4)
		var room: RoomController = dungeon.get_rooms()[i]
		if room.get_state() != RoomController.RoomState.ACTIVE or not room.exit_door.is_locked():
			all_ok = false
		if i == 2:
			# The boss is fought down in player-sized bites rather than one-shot,
			# so the encounter actually runs: it acts, takes damage over time and
			# dies at zero. The player is shielded so the run cannot fail here.
			if not await _fight_boss(dungeon, player, n):
				all_ok = false
		else:
			for enemy in room.get_enemies():
				enemy.hurtbox.receive_hit(1000.0, null)
		await _pause(0.5)
		if not room.is_cleared() or room.exit_door.is_locked():
			all_ok = false
	_record(all_ok, "RUN %d/2) all three rooms arm, gate progression, clear and open in order" % n)
	_record(dungeon.get_state() == DungeonController.DungeonState.COMPLETED
			and dungeon.exit_portal.is_enabled()
			and dungeon.status_label.text == "DUNGEON COMPLETE",
		"RUN %d/2) COMPLETED, banner shown, exit portal live" % n)

	player.global_position = EXIT_POS
	await _pause(0.4)
	_record(dungeon.exit_portal.activate(), "RUN %d/2) the live exit accepts interact" % n)
	await _pause(1.0)
	_record(current_scene.scene_file_path == TEST_WORLD,
		"RUN %d/2) the exit really returned to the test world" % n)

	var back: Player = current_scene.get_node("Player")
	_record(back.health_component.current_health == back.health_component.max_health
			and not back._is_dodging
			and back._attack_state == Player.AttackState.IDLE,
		"RUN %d/2) the returned player is controllable at full health" % n)

	return {
		"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"orphans": int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),
	}


## Chips the boss down at the player's Attack 1 damage, letting it act between
## hits, and checks the health bar follows the fight.
func _fight_boss(dungeon: DungeonController, player: Player, n: int) -> bool:
	var boss: DungeonBoss = dungeon.get_rooms()[2].get_enemies()[0] as DungeonBoss
	var bar: BossHealthBar = dungeon.get_node("BossHealthBar")
	if boss == null or bar == null:
		_record(false, "RUN %d/2) boss room holds a DungeonBoss with a health bar" % n)
		return false
	_record(bar.is_showing(), "RUN %d/2) boss health bar appears when the encounter starts" % n)

	player.hurtbox.set_invulnerable(true)
	var swings: int = 0
	var bar_tracked: bool = true
	while not boss.health_component.is_dead and swings < 40:
		player.global_position = boss.global_position + Vector3(0, 0, 2.0)
		boss.hurtbox.receive_hit(20.0, null)
		swings += 1
		await _pause(0.12)
		var expected: float = boss.health_component.current_health / boss.health_component.max_health
		if not is_equal_approx(bar.get_ratio(), expected):
			bar_tracked = false
	player.hurtbox.set_invulnerable(false)
	await _pause(0.5)

	_record(swings == 30, "RUN %d/2) the boss took %d hits of 20 to fell (600 HP)" % [n, swings])
	_record(bar_tracked, "RUN %d/2) the health bar tracked the whole fight" % n)
	_record(boss.get_state() == DungeonBoss.State.DEAD and not bar.is_showing(),
		"RUN %d/2) boss dead, health bar gone" % n)
	return boss.health_component.is_dead


func _death_and_restart() -> void:
	var back: Player = current_scene.get_node("Player")
	var gate: DungeonGate = current_scene.get_node("DungeonGate")
	back.global_position = gate.global_position
	await _pause(0.3)
	gate.activate()
	await _pause(1.0)
	var dungeon: DungeonController = current_scene as DungeonController
	var player: Player = current_scene.get_node("Player")

	player.global_position = ROOM_ANCHORS[0]
	await _pause(0.4)
	_record(dungeon.get_rooms()[0].get_state() == RoomController.RoomState.ACTIVE,
		"14) room 1 armed before the fatal hit")

	var doomed_id: int = current_scene.get_instance_id()
	player.health_component.receive_damage(1000.0)
	await _pause(0.3)
	_record(dungeon.status_label.text == "YOU DIED"
			and dungeon.get_state() == DungeonController.DungeonState.FAILED,
		"15) death shows YOU DIED and marks the run FAILED")

	await _pause(2.5)
	var restarted: DungeonController = current_scene as DungeonController
	var fresh_player: Player = current_scene.get_node("Player")
	_record(current_scene.get_instance_id() != doomed_id, "16) the dungeon really reloaded")
	_record(restarted.get_state() == DungeonController.DungeonState.NOT_STARTED
			and restarted.get_rooms()[0].get_state() == RoomController.RoomState.IDLE
			and restarted.get_rooms()[0].exit_door.is_locked()
			and not restarted.exit_portal.is_enabled(),
		"17) the restarted run is back to its initial state")
	_record(fresh_player.health_component.current_health == fresh_player.health_component.max_health,
		"18) the restarted player is at full health (%.0f/%.0f)" % [
			fresh_player.health_component.current_health, fresh_player.health_component.max_health])


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
