extends Node3D

## M4.2 Dungeon Completion & Transition Polish — scene fade, gate reuse, exit
## portal, return trip, death restart, double-interaction safety.
## M4.1 room/door/progression coverage lives in dungeon_test_suite.tscn.

const TEST_WORLD: PackedScene = preload("res://scenes/core/test_world.tscn")
const DUNGEON: PackedScene = preload("res://scenes/dungeons/dungeon_test.tscn")

const ROOM1_TRIGGER: Vector3 = Vector3(0, 0.1, -13)
const ROOM2_TRIGGER: Vector3 = Vector3(0, 0.1, -33)
const BOSS_TRIGGER: Vector3 = Vector3(0, 0.1, -53)
const EXIT_POS: Vector3 = Vector3(0, 0.1, -65)

var _pass: int = 0
var _fail: int = 0


func _ready() -> void:
	_run()


func _run() -> void:
	await _wait(0.2)
	await _gate_and_fade()
	await _full_dungeon_loop()
	await _fresh_run_state()
	await _death_restart()
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


## Instantiate a scene with its transition neutered, so a fade can run to
## completion without tearing this suite down.
func _spawn(packed: PackedScene) -> Node3D:
	var scene: Node3D = packed.instantiate() as Node3D
	add_child(scene)
	var transition: SceneTransition = scene.get_node("SceneTransition")
	transition.perform_scene_change = false
	return scene


func _clear_scene(scene: Node3D) -> void:
	scene.queue_free()
	await _wait(0.4)


# --- gate, fade, spam protection ----------------------------------------------

func _gate_and_fade() -> void:
	var world: Node3D = _spawn(TEST_WORLD)
	await _wait(0.8)  # let the opening fade-in settle

	var player: Player = world.get_node("Player")
	var gate: DungeonGate = world.get_node("DungeonGate")
	var transition: SceneTransition = world.get_node("SceneTransition")
	var starts: Array[String] = []
	transition.transition_started.connect(func(t: String) -> void: starts.append(t))

	_record(player != null and gate != null and transition != null,
		"1) test world starts with player, gate and transition")
	_record(gate.target_scene == "res://scenes/dungeons/dungeon_test.tscn",
		"2) gate target_scene is configurable and points at the dungeon (%s)" % gate.target_scene)
	_record(transition.fade_rect.modulate.a < 0.05,
		"5a) opening fade-in reached clear (alpha=%.2f)" % transition.fade_rect.modulate.a)

	player.global_position = Vector3(0, 0.1, 10)
	await _wait(0.3)
	_record(not gate.activate() and starts.is_empty(), "3) interact outside the gate does nothing")

	player.global_position = gate.global_position
	await _wait(0.3)
	# 4 + 31: one real activation, then nine more that must all be refused
	var first: bool = gate.activate()
	var extras: int = 0
	for i in 9:
		if gate.activate():
			extras += 1
	_record(first and extras == 0 and starts.size() == 1,
		"4/31) spamming interact starts exactly one transition (first=%s extra=%d starts=%d)" % [
			first, extras, starts.size()])

	await _wait(0.6)  # fade_duration 0.35
	_record(transition.fade_rect.modulate.a > 0.95 and transition.is_busy(),
		"5b) fade-to-black completed and the transition stays locked (alpha=%.2f busy=%s)" % [
			transition.fade_rect.modulate.a, transition.is_busy()])

	await _clear_scene(world)


# --- full loop: dungeon -> completion -> exit ---------------------------------

func _full_dungeon_loop() -> void:
	var dungeon: DungeonController = _spawn(DUNGEON) as DungeonController
	await _wait(0.8)

	var player: Player = dungeon.get_node("Player")
	var transition: SceneTransition = dungeon.get_node("SceneTransition")
	var exit_portal: DungeonExit = dungeon.exit_portal
	var rooms: Array[RoomController] = dungeon.get_rooms()
	var completions: Array[int] = []
	dungeon.dungeon_completed.connect(func() -> void: completions.append(1))
	var starts: Array[String] = []
	transition.transition_started.connect(func(t: String) -> void: starts.append(t))

	_record(player.global_position.z > -6.0, "6/7) dungeon loads with the player in the start room (%s)" % player.global_position)
	_record(not exit_portal.is_enabled() and not exit_portal.monitoring,
		"14) exit portal is dead before completion (enabled=%s monitoring=%s)" % [
			exit_portal.is_enabled(), exit_portal.monitoring])

	# 16) the exit must ignore interact while disabled, even standing in it
	player.global_position = EXIT_POS
	await _wait(0.3)
	_record(not exit_portal.activate() and starts.is_empty(),
		"16) disabled exit ignores interact even from inside it")

	# 9/10/11) clear the three rooms
	for i in 3:
		var room: RoomController = rooms[i]
		player.global_position = [ROOM1_TRIGGER, ROOM2_TRIGGER, BOSS_TRIGGER][i]
		await _wait(0.4)
		var armed: bool = room.get_state() == RoomController.RoomState.ACTIVE
		for enemy in room.get_enemies():
			enemy.hurtbox.receive_hit(1000.0, null)
		await _wait(0.5)
		_record(armed and room.is_cleared() and not room.exit_door.is_locked(),
			"%d) %s arms, clears and opens" % [9 + i, room.name])

	_record(dungeon.get_state() == DungeonController.DungeonState.COMPLETED and completions.size() == 1,
		"12) dungeon reaches COMPLETED exactly once (state=%d signals=%d)" % [
			dungeon.get_state(), completions.size()])
	_record(dungeon.status_label.visible and dungeon.status_label.text == "DUNGEON COMPLETE",
		"13) DUNGEON COMPLETE banner is visible")
	_record(exit_portal.is_enabled() and exit_portal.monitoring,
		"15) exit portal goes live on completion")

	# banner auto-hides, portal does not
	await _wait(dungeon.completion_message_duration + 0.4)
	_record(not dungeon.status_label.visible and exit_portal.is_enabled(),
		"13b) banner clears after %.1fs while the portal stays live" % dungeon.completion_message_duration)

	# 17) prompt on entry
	player.global_position = EXIT_POS
	await _wait(0.4)
	var ui: InteractionPrompt = dungeon.get_node("InteractionPrompt")
	_record(exit_portal.is_player_in_range() and ui.is_showing() and ui.get_text() == exit_portal.prompt_text,
		"17) standing in the live exit shows the prompt ('%s')" % ui.get_text())

	# 18) one transition only, spam-safe
	var first_exit: bool = exit_portal.activate()
	var extra_exits: int = 0
	for i in 5:
		if exit_portal.activate():
			extra_exits += 1
	_record(first_exit and extra_exits == 0 and starts.size() == 1
			and starts[0] == "res://scenes/core/test_world.tscn",
		"18) exit starts exactly one transition back to the test world (extra=%d target=%s)" % [
			extra_exits, starts[0] if starts.size() > 0 else "<none>"])

	await _wait(0.6)
	_record(transition.fade_rect.modulate.a > 0.95, "19) exit fade-to-black completed (alpha=%.2f)" % transition.fade_rect.modulate.a)

	# 32) dying after the run already ended must not start a second transition
	player.health_component.receive_damage(1000.0)
	await _wait(0.5)
	_record(starts.size() == 1 and dungeon.get_state() == DungeonController.DungeonState.COMPLETED,
		"32) death after completion does not queue a second transition (starts=%d state=%d)" % [
			starts.size(), dungeon.get_state()])

	await _clear_scene(dungeon)


# --- a second run starts clean -------------------------------------------------

func _fresh_run_state() -> void:
	var world: Node3D = _spawn(TEST_WORLD)
	await _wait(0.6)
	var world_player: Player = world.get_node("Player")
	var gate: DungeonGate = world.get_node("DungeonGate")
	var controllable: bool = (
		world_player.health_component.current_health == world_player.health_component.max_health
		and not world_player._is_dodging
		and world_player._attack_state == Player.AttackState.IDLE
	)
	_record(controllable, "20/21) test world reloads and the player is controllable at full health (%.0f/%.0f)" % [
		world_player.health_component.current_health, world_player.health_component.max_health])
	world_player.global_position = gate.global_position
	await _wait(0.3)
	_record(gate.is_player_in_range() and gate.activate(), "22) the gate is usable again for a new run")
	await _clear_scene(world)

	var dungeon: DungeonController = _spawn(DUNGEON) as DungeonController
	await _wait(0.8)
	var fresh_state: bool = dungeon.get_state() == DungeonController.DungeonState.NOT_STARTED and not dungeon.is_run_over()
	_record(fresh_state, "23) a new run starts at NOT_STARTED (state=%d)" % dungeon.get_state())

	var enemies: int = 0
	var rooms_idle: bool = true
	var doors_locked: bool = true
	var rooms: Array[RoomController] = dungeon.get_rooms()
	for i in rooms.size():
		var room: RoomController = rooms[i]
		enemies += room.get_enemies().size()
		if room.get_state() != RoomController.RoomState.IDLE:
			rooms_idle = false
		# The last room's door sits in its entrance, so it starts open and seals
		# behind the player instead.
		var should_be_locked: bool = i < rooms.size() - 1
		if room.exit_door.is_locked() != should_be_locked:
			doors_locked = false
	_record(enemies == 6, "24) every enemy is back in the new run (%d)" % enemies)
	_record(rooms_idle, "25) every room is back to IDLE")
	_record(doors_locked and not dungeon.exit_portal.is_enabled(),
		"26) combat doors start locked, the boss entrance starts open, the exit starts dead")
	await _clear_scene(dungeon)


# --- death restart --------------------------------------------------------------

func _death_restart() -> void:
	var dungeon: DungeonController = _spawn(DUNGEON) as DungeonController
	await _wait(0.8)
	var player: Player = dungeon.get_node("Player")
	var transition: SceneTransition = dungeon.get_node("SceneTransition")
	var reloads: Array[String] = []
	transition.transition_started.connect(func(t: String) -> void: reloads.append(t))
	var failures: Array[int] = []
	dungeon.run_failed.connect(func() -> void: failures.append(1))

	# get a fight going so there is progression to lose
	player.global_position = ROOM1_TRIGGER
	await _wait(0.4)
	var room1: RoomController = dungeon.get_rooms()[0]
	var was_active: bool = room1.get_state() == RoomController.RoomState.ACTIVE

	player.health_component.receive_damage(1000.0)
	await _wait(0.3)
	_record(dungeon.status_label.visible and dungeon.status_label.text == "YOU DIED",
		"27) player death shows YOU DIED ('%s')" % dungeon.status_label.text)
	_record(dungeon.get_state() == DungeonController.DungeonState.FAILED and failures.size() == 1,
		"27b) the run is marked FAILED exactly once (state=%d signals=%d)" % [dungeon.get_state(), failures.size()])

	# 30) progression is stopped dead: no room may arm or clear after death
	var suspended: bool = true
	for room in dungeon.get_rooms():
		if room.entry_trigger.monitoring:
			suspended = false
		for enemy in room.get_enemies():
			if enemy.combat_enabled:
				suspended = false
	_record(was_active and suspended, "30) every room is suspended and every enemy parked after death")

	player.global_position = ROOM2_TRIGGER
	await _wait(0.4)
	_record(dungeon.get_rooms()[1].get_state() == RoomController.RoomState.IDLE,
		"30b) walking into another room after death does not arm it")

	# 28) exactly one reload, after the delay
	_record(reloads.is_empty(), "28a) restart waits out death_restart_delay (%.1fs)" % dungeon.death_restart_delay)
	await _wait(dungeon.death_restart_delay + 0.5)
	_record(reloads.size() == 1, "28) death triggers exactly one reload (%d)" % reloads.size())

	# a second death during the restart must not queue another one
	player.health_component.is_dead = false
	player.health_component.current_health = 10.0
	player.health_component.receive_damage(1000.0)
	await _wait(0.4)
	_record(reloads.size() == 1 and failures.size() == 1,
		"28b) a second death during the restart is ignored (reloads=%d failures=%d)" % [reloads.size(), failures.size()])

	await _clear_scene(dungeon)

	# 29) the reloaded dungeon gives the player full health again
	var fresh: DungeonController = _spawn(DUNGEON) as DungeonController
	await _wait(0.6)
	var fresh_player: Player = fresh.get_node("Player")
	_record(fresh_player.health_component.current_health == fresh_player.health_component.max_health
			and not fresh_player.health_component.is_dead,
		"29) the restarted run gives the player full health (%.0f/%.0f)" % [
			fresh_player.health_component.current_health, fresh_player.health_component.max_health])
	await _clear_scene(fresh)
