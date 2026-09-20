extends Node3D

## Physical traversal and contextual UI. Everything here walks the player's body
## with move_and_slide instead of teleporting it — the bug this suite exists to
## catch (the boss room sealed by its own door) was invisible to every test that
## teleported past the doorway.

const TEST_WORLD: PackedScene = preload("res://scenes/core/test_world.tscn")
const DUNGEON: PackedScene = preload("res://scenes/dungeons/dungeon_test.tscn")

const WALK_SPEED: float = 6.0
const BOSS_TRIGGER_Z: float = -53.0

var _pass: int = 0
var _fail: int = 0


func _ready() -> void:
	_run()


func _run() -> void:
	_reset_session()
	await _wait(0.2)
	await _gate_prompt_tests()
	await _traversal_tests()
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


func _spawn(packed: PackedScene) -> Node3D:
	var scene: Node3D = packed.instantiate() as Node3D
	add_child(scene)
	var transition: SceneTransition = scene.get_node("SceneTransition")
	transition.perform_scene_change = false
	return scene


## Drives the body exactly as the player's own controller does — velocity,
## gravity, move_and_slide — just without input. Returns true if it got there.
func _walk_to_z(player: Player, target_z: float, budget_seconds: float = 12.0) -> bool:
	player.set_physics_process(false)
	var direction: float = signf(target_z - player.global_position.z)
	var elapsed: float = 0.0
	var stuck: float = 0.0
	var last_z: float = player.global_position.z
	while elapsed < budget_seconds:
		player.velocity.x = 0.0
		player.velocity.z = WALK_SPEED * direction
		if player.is_on_floor():
			if player.velocity.y < 0.0:
				player.velocity.y = 0.0
		else:
			player.velocity.y -= 20.0 * get_physics_process_delta_time()
		player.move_and_slide()
		await get_tree().physics_frame
		elapsed += get_physics_process_delta_time()
		if absf(player.global_position.z - last_z) < 0.002:
			stuck += get_physics_process_delta_time()
			if stuck > 1.0:
				break
		else:
			stuck = 0.0
		last_z = player.global_position.z
		if (direction < 0.0 and player.global_position.z <= target_z) \
				or (direction > 0.0 and player.global_position.z >= target_z):
			player.set_physics_process(true)
			return true
	player.set_physics_process(true)
	return false


func _kill_room(room: RoomController) -> void:
	for enemy in room.get_enemies():
		enemy.hurtbox.receive_hit(10000.0, null)


# --- gate prompt ----------------------------------------------------------------

func _gate_prompt_tests() -> void:
	var world: Node3D = _spawn(TEST_WORLD)
	await _wait(0.7)
	var player: Player = world.get_node("Player")
	var gate: DungeonGate = world.get_node("DungeonGate")
	gate.change_scene_on_activate = false
	var ui: InteractionPrompt = world.get_node("InteractionPrompt")

	_record(player != null and gate != null and ui != null, "1) test world starts with player, gate and prompt UI")
	_record(get_tree().get_nodes_in_group(InteractionPrompt.GROUP).size() == 1,
		"dup) exactly one interaction prompt exists in the scene")
	_record(not ui.is_showing(), "1b) prompt hidden by default")

	player.global_position = gate.global_position
	await _wait(0.3)
	_record(ui.is_showing() and ui.get_text() == "Entra nel Gate" and ui.key_label.text == "[E]",
		"2) near the gate: '%s %s'" % [ui.key_label.text, ui.get_text()])

	player.global_position = Vector3(0, 0.1, 6)
	await _wait(0.3)
	_record(not ui.is_showing(), "3) walking away hides the prompt")

	# ownership: a stranger must not be able to clear someone else's prompt
	player.global_position = gate.global_position
	await _wait(0.3)
	ui.hide_prompt(self)
	_record(ui.is_showing(), "dup2) only the owner can clear a prompt")

	var activations: Array[String] = []
	gate.gate_activated.connect(func(t: String) -> void: activations.append(t))
	_record(gate.activate() and activations.size() == 1
			and activations[0] == "res://scenes/dungeons/dungeon_test.tscn",
		"4) interact enters the dungeon")
	_record(not ui.is_showing(), "4b) interacting clears the prompt immediately")

	world.queue_free()
	await _wait(0.4)


# --- physical traversal ----------------------------------------------------------

func _traversal_tests() -> void:
	var dungeon: DungeonController = _spawn(DUNGEON) as DungeonController
	await _wait(0.8)
	var player: Player = dungeon.get_node("Player")
	var objective: DungeonObjectiveUI = dungeon.get_node("DungeonObjectiveUI")
	var prompt: InteractionPrompt = dungeon.get_node("InteractionPrompt")
	var rooms: Array[RoomController] = dungeon.get_rooms()
	var room1: RoomController = rooms[0]
	var room2: RoomController = rooms[1]
	var boss_room: RoomController = rooms[2]

	_record(objective.get_objective() == "Avanza nel dungeon",
		"5a) objective starts at '%s'" % objective.get_objective())

	# 5) start room -> room 1 trigger, on foot
	_record(await _walk_to_z(player, -13.0), "5/6a) the player walks the start room and corridor to room 1")
	await _wait(0.3)
	_record(room1.get_state() == RoomController.RoomState.ACTIVE, "6) room 1 arms on arrival")
	_record(objective.get_objective() == "Elimina i nemici: 2 rimasti",
		"7) objective shows the enemy count: '%s'" % objective.get_objective())

	# 8) counter follows each death
	room1.get_enemies()[0].hurtbox.receive_hit(10000.0, null)
	await _wait(0.3)
	_record(objective.get_objective() == "Elimina i nemici: 1 rimasto",
		"8) counter decrements and reads singular: '%s'" % objective.get_objective())

	room1.get_enemies()[1].hurtbox.receive_hit(10000.0, null)
	await _wait(0.4)
	_record(room1.is_cleared(), "9) room 1 clears at zero")
	_record(objective.get_objective() == "Camera completata - Procedi",
		"9b) objective points onward: '%s'" % objective.get_objective())
	_record(not room1.exit_door.is_locked() and room1.exit_door.blocker_collision.disabled,
		"10) room 1 door unlocks and its collider really goes away")
	_record(room1.exit_door.open_marker.visible, "10b) the open door is marked so the way on is obvious")

	# 11/12) through the door and into room 2, on foot
	_record(await _walk_to_z(player, -33.0), "11/12a) the player walks through the door into room 2")
	await _wait(0.3)
	_record(room2.get_state() == RoomController.RoomState.ACTIVE, "12) room 2 arms")
	_record(objective.get_objective() == "Elimina i nemici: 3 rimasti",
		"13) objective shows room 2's count: '%s'" % objective.get_objective())

	# 14/15) clear it and check the right door opened
	_kill_room(room2)
	await _wait(0.5)
	_record(room2.is_cleared(), "14) room 2 clears")
	_record(not room2.exit_door.is_locked() and room2.exit_door.blocker_collision.disabled,
		"15) the door towards the boss room opens, collider disabled")
	_record(objective.get_objective() == "Camera completata - Raggiungi la Boss Room",
		"17) objective names the boss room: '%s'" % objective.get_objective())

	# 16) nothing invisible left between here and the boss room
	var space: PhysicsDirectSpaceState3D = player.get_world_3d().direct_space_state
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		Vector3(0, 0.9, -44.0), Vector3(0, 0.9, BOSS_TRIGGER_Z), 1)
	query.exclude = [player.get_rid()]
	var blocker: Dictionary = space.intersect_ray(query)
	_record(blocker.is_empty(), "16) the corridor to the boss room is clear (%s)" % [
		"nothing in the way" if blocker.is_empty() else blocker["collider"].name])

	# backtracking happens between CLEARED rooms — the boss arena seals behind the
	# player by design, so that is checked separately below.
	_record(await _walk_to_z(player, -13.0), "back) the player can walk back into cleared room 1")
	await _wait(0.4)
	_record(room1.get_state() == RoomController.RoomState.CLEARED
			and room2.get_state() == RoomController.RoomState.CLEARED,
		"back2) re-entering a cleared room does not re-arm it")
	_record(not room1.exit_door.is_locked() and not room2.exit_door.is_locked(),
		"back3) cleared rooms keep their doors open")
	_record(not prompt.is_showing(), "back4) no stale prompt after backtracking")

	# 18/19/20) the whole way to the boss, on foot
	_record(await _walk_to_z(player, BOSS_TRIGGER_Z, 20.0),
		"18) the physical path to the boss room is walkable")
	await _wait(0.4)
	_record(boss_room.get_state() == RoomController.RoomState.ACTIVE,
		"19/20) the player enters the boss trigger and the room activates")
	_record(objective.get_objective() == "Sconfiggi il Boss",
		"20b) objective switches to the boss: '%s'" % objective.get_objective())
	_record(boss_room.exit_door.is_locked() and not boss_room.exit_door.blocker_collision.disabled,
		"20c) the boss room seals behind the player, collider live")
	_record(not await _walk_to_z(player, -45.0, 4.0),
		"20d) the seal really holds — the player cannot walk back out mid-fight")
	_record(not prompt.is_showing(), "20e) no stale interaction prompt on screen")

	# the exit portal only prompts once the dungeon is done
	_kill_room(boss_room)
	await _wait(0.6)
	_record(dungeon.get_state() == DungeonController.DungeonState.COMPLETED
			and objective.get_objective() == "Dungeon completato",
		"done) dungeon completes and the objective says so: '%s'" % objective.get_objective())
	player.global_position = dungeon.exit_portal.global_position
	await _wait(0.4)
	_record(prompt.is_showing() and prompt.get_text() == "Esci dal Dungeon",
		"done2) the live exit prompts '%s %s'" % [prompt.key_label.text, prompt.get_text()])


## Every suite starts from a clean session: PlayerRuntimeState now carries
## progression and health across scene changes, so without this a later test
## would inherit whatever an earlier one left behind.
func _reset_session() -> void:
	var state: Node = get_tree().root.get_node_or_null("PlayerRuntimeState")
	if state != null:
		state.reset_runtime_state()
