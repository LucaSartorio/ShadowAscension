extends SceneTree

## M6.3 Runtime Player Progression Persistence, with REAL scene changes.
##
##   godot --headless --path . --script res://tests/player/persistence_run.gd
##
## The whole point is what happens *across* a scene change, so nothing here is
## faked: the gate and the exit portal really swap the running scene, and the
## player on the far side is a different instance every time.

const TEST_WORLD: String = "res://scenes/core/test_world.tscn"
const DUNGEON: String = "res://scenes/dungeons/dungeon_test.tscn"
const ROOM_ANCHORS: Array[Vector3] = [
	Vector3(0, 0.1, -13), Vector3(0, 0.1, -33), Vector3(0, 0.1, -53)
]
const EXIT_POS: Vector3 = Vector3(0, 0.1, -65)
const STRIKE_RANGE: float = 1.6

var _pass: int = 0
var _fail: int = 0


func _initialize() -> void:
	var state: Node = root.get_node_or_null("PlayerRuntimeState")
	_record(state != null, "AUTO) the PlayerRuntimeState autoload is present")
	if state == null:
		print("[SUMMARY] passed=%d failed=%d" % [_pass, _fail])
		quit()
		return
	_record(root.get_children().filter(func(n: Node) -> bool:
		return n.name == "PlayerRuntimeState").size() == 1,
		"AUTO2) exactly one instance of it exists")
	state.reset_runtime_state()

	change_scene_to_file(TEST_WORLD)
	await _pause(0.6)

	# --- 1) a fresh session starts clean
	var player: Player = current_scene.get_node("Player")
	var prog: PlayerProgression = player.progression
	_record(prog.current_level == 1 and prog.current_xp == 0
			and prog.strength == 10 and prog.agility == 10
			and prog.vitality == 10 and prog.intelligence == 10
			and prog.available_stat_points == 0,
		"1/2/3) a new session starts at level 1, 0 XP, all stats 10, 0 points")

	# --- build the exact state the brief asks to carry through the gate
	prog.add_xp(140)
	await _pause(0.2)
	_record(prog.current_level == 2 and prog.current_xp == 40
			and prog.available_stat_points == 5,
		"4/5) 165 XP takes it to level %d, %d/%d, %d points" % [
			prog.current_level, prog.current_xp, prog.get_xp_to_next_level(),
			prog.available_stat_points])
	prog.allocate_stat(PlayerProgression.Stat.STRENGTH)
	prog.allocate_stat(PlayerProgression.Stat.STRENGTH)
	prog.allocate_stat(PlayerProgression.Stat.AGILITY)
	prog.allocate_stat(PlayerProgression.Stat.VITALITY)
	prog.allocate_stat(PlayerProgression.Stat.VITALITY)
	_record(prog.strength == 12 and prog.agility == 11 and prog.vitality == 12
			and prog.intelligence == 10 and prog.available_stat_points == 0,
		"6) five points spent: STR %d AGI %d VIT %d INT %d" % [
			prog.strength, prog.agility, prog.vitality, prog.intelligence])

	# wound the player, so the gate must not heal it
	player.health_component.receive_damage(player.health_component.current_health - 50.0)
	await _pause(0.2)
	var before: Dictionary = _snapshot(player)
	print("[BEFORE GATE] %s" % [before])
	_record(is_equal_approx(before["max_hp"], 116.0) and is_equal_approx(before["hp"], 50.0),
		"18a) wounded to %.0f/%.0f before the gate" % [before["hp"], before["max_hp"]])

	# --- 7) through the gate
	var gate: DungeonGate = current_scene.get_node("DungeonGate")
	player.global_position = gate.global_position
	await _pause(0.3)
	gate.activate()
	await _pause(1.0)
	_record(current_scene.scene_file_path == DUNGEON, "7) the gate really loaded the dungeon")

	var dungeon: DungeonController = current_scene as DungeonController
	var player2: Player = current_scene.get_node("Player")
	_record(player2 != player, "7b) it is a different Player instance on the far side")
	var after: Dictionary = _snapshot(player2)
	print("[AFTER GATE ] %s" % [after])
	_compare(before, after, "8-14/18/19) gate")

	var hud: ProgressionHUD = current_scene.get_node("ProgressionHUD")
	var menu: PlayerStatsMenu = current_scene.get_node("PlayerStatsMenu")
	_record(hud.get_level_text() == "LV. 2" and hud.get_xp_text() == "40 / 125",
		"16) the HUD shows it without prompting: '%s  %s'" % [
			hud.get_level_text(), hud.get_xp_text()])
	menu.open()
	_record(menu.get_level_text() == "Level 2"
			and menu.get_stat_value_text("STR") == "12"
			and menu.get_stat_value_text("VIT") == "12",
		"17) so does the stats menu, first time it is opened")
	menu.close()

	# --- 15) derived stats are recomputed, not restored
	_record(is_equal_approx(player2.progression.get_melee_damage_multiplier(), 1.06)
			and is_equal_approx(player2.effective_movement_speed, 6.0 * 1.01)
			and is_equal_approx(player2.health_component.max_health, 116.0),
		"15/19) derived recomputed: melee x%.2f, move %.2f, max HP %.0f" % [
			player2.progression.get_melee_damage_multiplier(),
			player2.effective_movement_speed, player2.health_component.max_health])

	# --- earn more inside the dungeon, and spend it there
	await _clear_rooms(dungeon, player2, 2)
	var prog2: PlayerProgression = player2.progression
	_record(prog2.current_level == 3,
		"23a) five kills in the dungeon reach level %d, %d/%d" % [
			prog2.current_level, prog2.current_xp, prog2.get_xp_to_next_level()])
	prog2.allocate_stat(PlayerProgression.Stat.INTELLIGENCE)
	prog2.allocate_stat(PlayerProgression.Stat.INTELLIGENCE)
	_record(prog2.intelligence == 12, "24a) INT raised to %d inside the dungeon" % prog2.intelligence)

	# --- the boss, then out through the portal
	player2.global_position = ROOM_ANCHORS[2]
	await _pause(0.6)
	var boss: DungeonBoss = dungeon.get_rooms()[2].get_enemies()[0] as DungeonBoss
	player2.hurtbox.set_invulnerable(true)
	await _kill(player2, boss, 60.0)
	await _pause(1.2)
	player2.hurtbox.set_invulnerable(false)
	_record(dungeon.get_state() == DungeonController.DungeonState.COMPLETED,
		"20a) the dungeon completed")

	player2.health_component.current_health = 37.0
	player2.health_component.health_changed.emit(37.0, player2.health_component.max_health)
	var before_exit: Dictionary = _snapshot(player2)
	print("[BEFORE EXIT] %s" % [before_exit])

	player2.global_position = EXIT_POS
	await _pause(0.4)
	dungeon.exit_portal.activate()
	await _pause(1.2)
	_record(current_scene.scene_file_path == TEST_WORLD, "20) the portal returned to the test world")
	var player3: Player = current_scene.get_node("Player")
	var after_exit: Dictionary = _snapshot(player3)
	print("[AFTER EXIT ] %s" % [after_exit])
	_compare(before_exit, after_exit, "21/23/24) exit")

	# --- 22) a second run keeps everything
	var gate2: DungeonGate = current_scene.get_node("DungeonGate")
	player3.global_position = gate2.global_position
	await _pause(0.3)
	gate2.activate()
	await _pause(1.0)
	var player4: Player = current_scene.get_node("Player")
	var second_run: Dictionary = _snapshot(player4)
	print("[SECOND RUN ] %s" % [second_run])
	_compare(before_exit, second_run, "22) second run")

	# --- 25-29) death restores health only
	var dungeon2: DungeonController = current_scene as DungeonController
	player4.health_component.receive_damage(player4.health_component.current_health - 20.0)
	await _pause(0.2)
	var before_death: Dictionary = _snapshot(player4)
	_record(is_equal_approx(before_death["hp"], 20.0),
		"25a) down to %.0f/%.0f before dying" % [before_death["hp"], before_death["max_hp"]])

	player4.global_position = ROOM_ANCHORS[0]
	await _pause(0.4)
	player4.health_component.receive_damage(1000.0)
	await _pause(0.3)
	_record(dungeon2.get_state() == DungeonController.DungeonState.FAILED, "25b) the run failed")
	await _pause(2.5)

	var player5: Player = current_scene.get_node("Player")
	var after_death: Dictionary = _snapshot(player5)
	print("[AFTER DEATH] %s" % [after_death])
	_record(after_death["level"] == before_death["level"]
			and after_death["xp"] == before_death["xp"]
			and after_death["points"] == before_death["points"]
			and after_death["str"] == before_death["str"]
			and after_death["agi"] == before_death["agi"]
			and after_death["vit"] == before_death["vit"]
			and after_death["int"] == before_death["int"],
		"26/27/28/29) death keeps level %d, %d XP and every stat" % [
			after_death["level"], after_death["xp"]])
	_record(is_equal_approx(after_death["hp"], after_death["max_hp"]),
		"25) and restores health only: %.0f/%.0f" % [after_death["hp"], after_death["max_hp"]])

	# --- 30) nothing temporary rode along. The pre-death dungeon is gone, so the
	# reloaded one has to be read off current_scene rather than the stale handle.
	var reloaded: DungeonController = current_scene as DungeonController
	_record(player5._combo_index == 0 and not player5._is_dodging
			and player5._attack_state == Player.AttackState.IDLE
			and reloaded != null
			and reloaded.get_rooms()[0].get_state() == RoomController.RoomState.IDLE
			and reloaded.get_state() == DungeonController.DungeonState.NOT_STARTED,
		"30) no combat, dodge, combo, room or dungeon state was carried over")

	# --- 31) an explicit fresh session
	var state2: Node = root.get_node_or_null("PlayerRuntimeState")
	state2.reset_runtime_state()
	_record(not state2.initialized and state2.current_level == 1 and state2.current_xp == 0
			and state2.strength == 10 and state2.available_stat_points == 0,
		"31) reset_runtime_state() returns the session to level 1, 0 XP, stats 10")

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


func _snapshot(player: Player) -> Dictionary:
	var p: PlayerProgression = player.progression
	return {
		"level": p.current_level, "xp": p.current_xp, "points": p.available_stat_points,
		"str": p.strength, "agi": p.agility, "vit": p.vitality, "int": p.intelligence,
		"hp": player.health_component.current_health,
		"max_hp": player.health_component.max_health,
	}


## Every persisted field, one assertion per field, so a failure names what drifted.
func _compare(before: Dictionary, after: Dictionary, label: String) -> void:
	for key in ["level", "xp", "points", "str", "agi", "vit", "int"]:
		_record(before[key] == after[key],
			"%s %s: %s -> %s" % [label, key, before[key], after[key]])
	_record(is_equal_approx(before["hp"], after["hp"]),
		"%s current health: %.0f -> %.0f" % [label, before["hp"], after["hp"]])
	_record(is_equal_approx(before["max_hp"], after["max_hp"]),
		"%s max health recomputed to the same %.0f" % [label, after["max_hp"]])


func _clear_rooms(dungeon: DungeonController, player: Player, count: int) -> void:
	player.hurtbox.set_invulnerable(true)
	for i in count:
		player.global_position = ROOM_ANCHORS[i]
		await _pause(0.5)
		for enemy in dungeon.get_rooms()[i].get_enemies():
			await _kill(player, enemy)
			await _pause(0.2)
	player.hurtbox.set_invulnerable(false)


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
