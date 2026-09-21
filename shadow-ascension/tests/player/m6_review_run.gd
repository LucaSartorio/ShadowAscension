extends SceneTree

## M6 Player Progression — milestone review. Real scene changes, real combat, and
## the four ROADMAP exit criteria asserted by name.
##
##   godot --headless --path . --script res://tests/player/m6_review_run.gd
##
## The detail of each sub-milestone lives in its own suite; this walks the whole
## thing end to end the way a player would and checks the criteria hold.

const HUB: String = "res://scenes/core/hub.tscn"
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
	if state == null:
		_record(false, "the PlayerRuntimeState autoload is present")
		print("[SUMMARY] passed=%d failed=%d" % [_pass, _fail])
		quit()
		return
	state.reset_runtime_state()

	change_scene_to_file(HUB)
	await _pause(0.6)

	# ========== EXIT CRITERION 1: kills award XP, thresholds level up ==========
	var player: Player = current_scene.get_node("Player")
	var prog: PlayerProgression = player.progression
	var hud: ProgressionHUD = current_scene.get_node("ProgressionHUD")

	var level_ups: Array[String] = []
	prog.level_up.connect(func(level: int, points: int) -> void:
		level_ups.append("L%d(+%d)" % [level, points]))

	_record(prog.current_level == 1 and prog.current_xp == 0, "start) level 1, 0 XP")
	prog.add_xp(60)
	await _pause(0.1)
	_record(prog.current_level == 1 and prog.current_xp == 60 and level_ups.is_empty(),
		"EC1a) XP below the threshold does not level (%d/%d)" % [
			prog.current_xp, prog.get_xp_to_next_level()])
	prog.add_xp(40)
	await _pause(0.1)
	_record(prog.current_level == 2 and level_ups.size() == 1
			and prog.available_stat_points == 5,
		"EC1b) reaching the threshold levels up and awards points: %s" % [level_ups])

	# ========== EXIT CRITERION 3: the UI follows in real time ==========
	_record(hud.get_level_text() == "LV. 2" and hud.get_xp_text() == "0 / 125",
		"EC3a) the HUD followed the level-up with no prompting: '%s  %s'" % [
			hud.get_level_text(), hud.get_xp_text()])
	_record(hud.is_banner_showing(), "EC3b) and the level-up callout appeared")

	# ========== EXIT CRITERION 2: points allocate and affect combat ==========
	var menu: PlayerStatsMenu = current_scene.get_node("PlayerStatsMenu")
	menu.open()
	_record(menu.get_points_text() == "Punti disponibili: 5" and not menu.is_button_disabled("STR"),
		"EC2a) the sheet offers the points: '%s'" % menu.get_points_text())
	var damage_before: float = prog.get_effective_damage(player.combo_steps[0].damage)
	var move_before: float = player.effective_movement_speed
	var hp_before: float = player.health_component.max_health
	for i in 3:
		menu.press_stat("STR")
	menu.press_stat("AGI")
	menu.press_stat("VIT")
	_record(prog.strength == 13 and prog.agility == 11 and prog.vitality == 11
			and prog.available_stat_points == 0,
		"EC2b) five points spent: STR %d AGI %d VIT %d, %d left" % [
			prog.strength, prog.agility, prog.vitality, prog.available_stat_points])
	_record(prog.get_effective_damage(player.combo_steps[0].damage) > damage_before
			and player.effective_movement_speed > move_before
			and player.health_component.max_health > hp_before,
		"EC2c) and combat changed with them: damage %.0f -> %.0f, move %.2f -> %.2f, HP %.0f -> %.0f" % [
			damage_before, prog.get_effective_damage(player.combo_steps[0].damage),
			move_before, player.effective_movement_speed,
			hp_before, player.health_component.max_health])
	_record(menu.get_stat_value_text("STR") == "13" and menu.is_button_disabled("STR"),
		"EC3c) the sheet redrew as the points were spent")
	menu.close()
	_record(not paused, "EC3d) and closing it resumed the game")

	# wound the player, so nothing along the way is allowed to heal it
	player.health_component.receive_damage(player.health_component.current_health - 60.0)
	await _pause(0.2)
	var at_gate: Dictionary = _snapshot(player)
	print("[TEST WORLD ] %s" % [at_gate])

	# ========== the run: gate -> dungeon ==========
	var gate: DungeonGate = current_scene.get_node("DungeonGate")
	player.global_position = gate.global_position
	await _pause(0.3)
	gate.activate()
	await _pause(1.0)
	_record(current_scene.scene_file_path == DUNGEON, "flow) the gate loaded the dungeon")

	var dungeon: DungeonController = current_scene as DungeonController
	var p2: Player = current_scene.get_node("Player")
	var in_dungeon: Dictionary = _snapshot(p2)
	print("[IN DUNGEON ] %s" % [in_dungeon])
	_same(at_gate, in_dungeon, "M6.3 gate")

	# a menu left open across a scene change must not strand the pause
	var menu2: PlayerStatsMenu = current_scene.get_node("PlayerStatsMenu")
	menu2.open()
	_record(paused, "pause) the sheet pauses inside the dungeon too")
	menu2.close()

	# ========== earn inside the dungeon, then the boss ==========
	p2.hurtbox.set_invulnerable(true)
	await _clear_rooms(dungeon, p2, 2)
	var after_rooms: Dictionary = _snapshot(p2)
	print("[AFTER ROOMS] %s" % [after_rooms])
	_record(after_rooms["level"] > in_dungeon["level"],
		"EC1c) five kills in the dungeon reached level %d" % after_rooms["level"])
	p2.progression.allocate_stat(PlayerProgression.Stat.INTELLIGENCE)

	p2.global_position = ROOM_ANCHORS[2]
	await _pause(0.6)
	var boss: DungeonBoss = dungeon.get_rooms()[2].get_enemies()[0] as DungeonBoss
	var before_boss: int = _total_xp(p2.progression)
	var swings: int = await _kill(p2, boss, 60.0)
	await _pause(1.2)
	_record(boss.has_died() and _total_xp(p2.progression) - before_boss == 200,
		"EC1d) the boss paid 200 XP after %d swings" % swings)
	_record(dungeon.get_state() == DungeonController.DungeonState.COMPLETED,
		"flow) the dungeon completed")
	p2.hurtbox.set_invulnerable(false)

	p2.health_component.receive_damage(p2.health_component.current_health - 45.0)
	await _pause(0.2)
	var before_exit: Dictionary = _snapshot(p2)
	print("[BEFORE EXIT] %s" % [before_exit])

	# ========== exit -> test world ==========
	p2.global_position = EXIT_POS
	await _pause(0.4)
	dungeon.exit_portal.activate()
	await _pause(1.2)
	_record(current_scene.scene_file_path == HUB, "flow) the portal returned home")
	var p3: Player = current_scene.get_node("Player")
	var back_home: Dictionary = _snapshot(p3)
	print("[BACK HOME  ] %s" % [back_home])
	_same(before_exit, back_home, "M6.3 exit")

	# ========== second run ==========
	var gate2: DungeonGate = current_scene.get_node("DungeonGate")
	p3.global_position = gate2.global_position
	await _pause(0.3)
	gate2.activate()
	await _pause(1.0)
	var p4: Player = current_scene.get_node("Player")
	var second: Dictionary = _snapshot(p4)
	print("[SECOND RUN ] %s" % [second])
	_same(before_exit, second, "M6.3 second run")

	# ========== death in the dungeon ==========
	var dungeon2: DungeonController = current_scene as DungeonController
	p4.global_position = ROOM_ANCHORS[0]
	await _pause(0.4)
	p4.health_component.receive_damage(1000.0)
	await _pause(0.3)
	_record(dungeon2.get_state() == DungeonController.DungeonState.FAILED, "flow) the run failed")
	await _pause(2.5)
	var p5: Player = current_scene.get_node("Player")
	var after_death: Dictionary = _snapshot(p5)
	print("[AFTER DEATH] %s" % [after_death])
	for key in ["level", "xp", "points", "str", "agi", "vit", "int"]:
		_record(after_death[key] == second[key],
			"M6.3 death keeps %s: %s" % [key, after_death[key]])
	_record(is_equal_approx(after_death["hp"], after_death["max_hp"]),
		"M6.3 death restores health only: %.0f/%.0f" % [after_death["hp"], after_death["max_hp"]])

	print("[REVIEW] level-ups across the whole review: %s" % [level_ups])
	print("[SUMMARY] passed=%d failed=%d" % [_pass, _fail])
	await _pause(0.3)
	quit()


## M9.1: completing the dungeon opens the run summary, which pauses the tree
## until the player dismisses it. A headless flow has no player, so it does
## what one would — the summary itself is covered by vertical_slice_run.gd.
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


func _snapshot(player: Player) -> Dictionary:
	var p: PlayerProgression = player.progression
	return {
		"level": p.current_level, "xp": p.current_xp, "points": p.available_stat_points,
		"str": p.strength, "agi": p.agility, "vit": p.vitality, "int": p.intelligence,
		"hp": player.health_component.current_health,
		"max_hp": player.health_component.max_health,
	}


func _same(before: Dictionary, after: Dictionary, label: String) -> void:
	var drifted: Array[String] = []
	for key in before:
		if typeof(before[key]) == TYPE_FLOAT:
			if not is_equal_approx(before[key], after[key]):
				drifted.append("%s %s->%s" % [key, before[key], after[key]])
		elif before[key] != after[key]:
			drifted.append("%s %s->%s" % [key, before[key], after[key]])
	_record(drifted.is_empty(), "%s: every value survived%s" % [
		label, "" if drifted.is_empty() else " EXCEPT " + str(drifted)])


func _total_xp(prog: PlayerProgression) -> int:
	var total: int = prog.current_xp
	for level in range(1, prog.current_level):
		total += prog.xp_required_for_level(level)
	return total


func _clear_rooms(dungeon: DungeonController, player: Player, count: int) -> void:
	for i in count:
		player.global_position = ROOM_ANCHORS[i]
		await _pause(0.5)
		for enemy in dungeon.get_rooms()[i].get_enemies():
			await _kill(player, enemy)
			await _pause(0.2)


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
