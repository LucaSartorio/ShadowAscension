extends SceneTree

## M8.1 end to end with REAL scene changes: extract shadows in a dungeon, carry
## them out, back in, and through a death.
##
##   godot --headless --path . --script res://tests/shadows/shadow_run.gd

const TEST_WORLD: String = "res://scenes/core/test_world.tscn"
const DUNGEON: String = "res://scenes/dungeons/dungeon_test.tscn"
const ROOM_ANCHORS: Array[Vector3] = [
	Vector3(0, 0.1, -13), Vector3(0, 0.1, -33), Vector3(0, 0.1, -53)
]
const EXIT_POS: Vector3 = Vector3(0, 0.1, -65)
const STRIKE_RANGE: float = 1.6

var _shadow: ShadowData = preload("res://resources/shadows/basic_melee_shadow.tres")
var _pass: int = 0
var _fail: int = 0
var _real_chance: float = 0.0


func _initialize() -> void:
	var state: Node = root.get_node_or_null("PlayerRuntimeState")
	state.reset_runtime_state()
	_real_chance = _shadow.extraction_chance
	# Forced so the run does not hinge on three 70% rolls. Restored at the end.
	_shadow.extraction_chance = 1.0

	change_scene_to_file(TEST_WORLD)
	await _pause(0.6)

	var player: Player = current_scene.get_node("Player")
	_record(player.shadows != null and player.shadows.is_empty(),
		"1) a new session starts with no shadows")
	_record((current_scene.get_node("ShadowCollectionMenu") as ShadowCollectionMenu).hint.visible,
		"2) the '[O] Ombre' hint is on screen")

	var gate: DungeonGate = current_scene.get_node("DungeonGate")
	player.global_position = gate.global_position
	await _pause(0.3)
	gate.activate()
	await _pause(1.0)
	_record(current_scene.scene_file_path == DUNGEON, "3) the gate loaded the dungeon")

	var dungeon: DungeonController = current_scene as DungeonController
	var p: Player = current_scene.get_node("Player")
	p.hurtbox.set_invulnerable(true)

	# --- clear both combat rooms, extracting whatever each corpse leaves
	var extracted: int = 0
	for i in 2:
		p.global_position = ROOM_ANCHORS[i]
		await _pause(0.5)
		var room: RoomController = dungeon.get_rooms()[i]
		for enemy in room.get_enemies():
			await _kill(p, enemy)
			await _pause(0.3)
		extracted += await _extract_all(p, dungeon)
		_record(room.is_cleared(), "4.%d) room %d cleared regardless of remnants" % [i + 1, i + 1])

	_record(extracted >= 3, "5) %d shadows extracted across both rooms" % extracted)
	_record(p.shadows.get_count() == extracted,
		"5b) the collection holds all %d" % p.shadows.get_count())
	var ids: Dictionary = {}
	for shadow in p.shadows.get_shadows():
		ids[shadow.instance_id] = true
	_record(ids.size() == p.shadows.get_count(), "5c) with distinct ids: %s" % [_short_ids(p)])

	# --- the boss leaves nothing to extract, by design for M8.1
	p.global_position = ROOM_ANCHORS[2]
	await _pause(0.6)
	var boss: DungeonBoss = dungeon.get_rooms()[2].get_enemies()[0] as DungeonBoss
	_record(boss.get_node_or_null("ShadowSource") == null,
		"6) the boss yields no shadow yet")
	await _kill(p, boss, 60.0)
	await _pause(1.2)
	_record(_remnants(dungeon).is_empty(), "6b) and left no remnant behind")
	_record(dungeon.get_state() == DungeonController.DungeonState.COMPLETED,
		"7) the dungeon completed")
	p.hurtbox.set_invulnerable(false)

	var in_dungeon: Array[String] = _short_ids(p)
	print("[IN DUNGEON ] %s" % [in_dungeon])

	# --- out, back in, and a death
	p.global_position = EXIT_POS
	await _pause(0.4)
	dungeon.exit_portal.activate()
	await _pause(1.2)
	_record(current_scene.scene_file_path == TEST_WORLD, "8) the portal returned home")
	var p2: Player = current_scene.get_node("Player")
	print("[BACK HOME  ] %s" % [_short_ids(p2)])
	_record(_short_ids(p2) == in_dungeon, "9) the collection survived the exit")
	_record(p2 != p, "9b) on a different Player instance")

	var gate2: DungeonGate = current_scene.get_node("DungeonGate")
	p2.global_position = gate2.global_position
	await _pause(0.3)
	gate2.activate()
	await _pause(1.0)
	var p3: Player = current_scene.get_node("Player")
	print("[SECOND RUN ] %s" % [_short_ids(p3)])
	_record(_short_ids(p3) == in_dungeon, "10) and the second run starts with it intact")

	# ids keep counting up rather than restarting and colliding
	var room1: RoomController = (current_scene as DungeonController).get_rooms()[0]
	p3.hurtbox.set_invulnerable(true)
	p3.global_position = ROOM_ANCHORS[0]
	await _pause(0.5)
	await _kill(p3, room1.get_enemies()[0])
	await _pause(0.3)
	await _extract_all(p3, current_scene)
	var after: Array[String] = _short_ids(p3)
	print("[AFTER MORE ] %s" % [after])
	_record(after.size() == in_dungeon.size() + 1 and after[after.size() - 1] not in in_dungeon,
		"11) a shadow extracted in the second run gets a fresh id: %s" % after[after.size() - 1])

	# --- death keeps them
	var dungeon2: DungeonController = current_scene as DungeonController
	p3.hurtbox.set_invulnerable(false)
	p3.health_component.receive_damage(1000.0)
	await _pause(0.3)
	_record(dungeon2.get_state() == DungeonController.DungeonState.FAILED, "12) the run failed")
	await _pause(2.5)
	var p4: Player = current_scene.get_node("Player")
	print("[AFTER DEATH] %s" % [_short_ids(p4)])
	_record(_short_ids(p4) == after, "13) dying costs no shadows")

	# --- and a fresh session clears them
	state.reset_runtime_state()
	p4.shadows.clear()
	_record(state.shadows.is_empty() and state.next_shadow_index == 1
			and p4.shadows.is_empty(),
		"14) reset_runtime_state() empties the collection and the counter")

	_shadow.extraction_chance = _real_chance
	_record(is_equal_approx(_shadow.extraction_chance, 0.7),
		"15) the real extraction chance is restored to %.2f" % _shadow.extraction_chance)

	print("[SUMMARY] passed=%d failed=%d" % [_pass, _fail])
	await _pause(0.3)
	quit()


func _pause(t: float) -> void:
	await create_timer(t).timeout


func _record(passed: bool, description: String) -> void:
	if passed:
		_pass += 1
		print("[PASS] " + description)
	else:
		_fail += 1
		print("[FAIL] " + description)


func _short_ids(player: Player) -> Array[String]:
	var out: Array[String] = []
	for shadow in player.shadows.get_shadows():
		out.append(shadow.get_short_id())
	return out


func _remnants(from: Node) -> Array[ShadowRemnant]:
	var found: Array[ShadowRemnant] = []
	_collect(from, found)
	return found


func _collect(node: Node, into: Array[ShadowRemnant]) -> void:
	var remnant: ShadowRemnant = node as ShadowRemnant
	if remnant != null and is_instance_valid(remnant):
		into.append(remnant)
	for child in node.get_children():
		_collect(child, into)


## Walks to each remnant in turn and takes its one attempt. Remnants can overlap,
## so this steps to each one and lets the prompt decide, as a player would.
func _extract_all(player: Player, from: Node) -> int:
	var taken: int = 0
	for remnant in _remnants(from):
		if not is_instance_valid(remnant) or remnant.has_been_attempted():
			continue
		player.global_position = remnant.global_position + Vector3(0, 0, 0.45)
		await _pause(0.4)
		var before: int = player.shadows.get_count()
		remnant.attempt_extraction()
		await _pause(remnant.extraction_duration + 0.4)
		if player.shadows.get_count() > before:
			taken += 1
		await _pause(0.2)
	return taken


func _kill(player: Player, target: RoomCombatant, budget: float = 20.0) -> int:
	var swings: int = 0
	var elapsed: float = 0.0
	while elapsed < budget and not target.has_died():
		if player.get("_attack_state") == Player.AttackState.IDLE:
			player.global_position = target.global_position + Vector3(0, 0, STRIKE_RANGE)
			player.camera_rig.rotation.y = 0.0
			player.camera_rig.attack_light_pressed.emit()
			swings += 1
		await physics_frame
		elapsed += 1.0 / 60.0
	return swings
