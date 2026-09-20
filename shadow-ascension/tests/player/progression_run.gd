extends SceneTree

## M6.1 progression run with REAL scene changes and REAL combat: test world ->
## gate -> dungeon -> room 1 -> room 2 -> boss -> completion, reporting XP after
## every kill. Nothing here calls receive_hit to kill: the player swings its own
## combo, because XP only flows through the player's own attack hitbox.
##
##   godot --headless --path . --script res://tests/player/progression_run.gd

const TEST_WORLD: String = "res://scenes/core/test_world.tscn"
const DUNGEON: String = "res://scenes/dungeons/dungeon_test.tscn"
const ROOM_ANCHORS: Array[Vector3] = [
	Vector3(0, 0.1, -13), Vector3(0, 0.1, -33), Vector3(0, 0.1, -53)
]
const STRIKE_RANGE: float = 1.6

var _pass: int = 0
var _fail: int = 0
var _kills: int = 0


func _initialize() -> void:
	# A clean session: progression and health now survive scene changes.
	var state: Node = root.get_node_or_null("PlayerRuntimeState")
	if state != null:
		state.reset_runtime_state()
	change_scene_to_file(TEST_WORLD)
	await _pause(0.6)
	_record(current_scene.scene_file_path == TEST_WORLD, "1) test world is running")

	var player_out: Player = current_scene.get_node("Player")
	var gate: DungeonGate = current_scene.get_node("DungeonGate")
	_record(player_out.progression != null and player_out.progression.current_level == 1
			and player_out.progression.current_xp == 0,
		"2) the player enters at level 1 with 0 XP")

	player_out.global_position = gate.global_position
	await _pause(0.3)
	gate.activate()
	await _pause(1.0)
	_record(current_scene.scene_file_path == DUNGEON, "3) the gate loaded the dungeon")

	var dungeon: DungeonController = current_scene as DungeonController
	var player: Player = current_scene.get_node("Player")
	var prog: PlayerProgression = player.progression
	var hud: ProgressionHUD = current_scene.get_node("ProgressionHUD")
	player.hurtbox.set_invulnerable(true)

	var level_ups: Array[String] = []
	prog.level_up.connect(func(level: int, points: int) -> void:
		level_ups.append("level %d (+%d points)" % [level, points]))

	var expected: int = 0
	for i in 2:
		player.global_position = ROOM_ANCHORS[i]
		await _pause(0.5)
		var room: RoomController = dungeon.get_rooms()[i]
		print("[ROOM %d] %d enemies" % [i + 1, room.get_enemies().size()])
		for enemy in room.get_enemies():
			expected += enemy.get_xp_reward()
			var swings: int = await _kill(player, enemy)
			await _pause(0.3)
			_kills += 1
			print("[KILL %d] %s worth %d  ->  level %d, %d/%d XP  (total %d, %d swings)" % [
				_kills, enemy.name, enemy.get_xp_reward(), prog.current_level, prog.current_xp,
				prog.get_xp_to_next_level(), _total(prog), swings])
			_record(_total(prog) == expected,
				"4.%d) after that kill the run total is %d XP" % [_kills, _total(prog)])
		_record(room.is_cleared(), "5.%d) room %d cleared" % [i + 1, i + 1])
		_record(_total(prog) == expected,
			"6.%d) clearing room %d added nothing extra (%d)" % [i + 1, i + 1, _total(prog)])

	player.global_position = ROOM_ANCHORS[2]
	await _pause(0.6)
	var boss: DungeonBoss = dungeon.get_rooms()[2].get_enemies()[0] as DungeonBoss
	var before_boss: int = _total(prog)
	expected += boss.get_xp_reward()
	var boss_swings: int = await _kill(player, boss, 60.0)
	await _pause(0.9)
	_kills += 1
	print("[KILL %d] %s worth %d  ->  level %d, %d/%d XP  (total %d, %d swings)" % [
		_kills, boss.name, boss.get_xp_reward(), prog.current_level, prog.current_xp,
		prog.get_xp_to_next_level(), _total(prog), boss_swings])
	_record(boss.has_died() and _total(prog) - before_boss == 200,
		"7) the boss paid 200 XP (+%d)" % [_total(prog) - before_boss])

	await _pause(1.2)
	_record(dungeon.get_state() == DungeonController.DungeonState.COMPLETED,
		"8) the dungeon completed")
	_record(_total(prog) == expected,
		"9) completion added nothing: %d XP total, expected %d" % [_total(prog), expected])
	_record(dungeon.exit_portal.is_enabled(), "10) the exit portal went live")
	_record(hud.get_level_text() == "LV. %d" % prog.current_level
			and hud.get_xp_text() == "%d / %d" % [prog.current_xp, prog.get_xp_to_next_level()],
		"11) the HUD agrees: '%s  %s'" % [hud.get_level_text(), hud.get_xp_text()])

	print("[RUN] total XP %d over %d kills  ->  level %d, %d/%d" % [
		_total(prog), _kills, prog.current_level, prog.current_xp, prog.get_xp_to_next_level()])
	print("[RUN] level-ups: %s" % [level_ups])
	print("[RUN] stat points available: %d" % prog.available_stat_points)

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


## Level plus leftover as one number, so a level-up mid-run does not hide XP.
func _total(prog: PlayerProgression) -> int:
	var total: int = prog.current_xp
	for level in range(1, prog.current_level):
		total += prog.xp_required_for_level(level)
	return total
