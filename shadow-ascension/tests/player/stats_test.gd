extends Node3D

## M6.2 Stat Allocation and Derived Stats — the menu and its pause, spending
## points, and what each stat actually changes in the running game.

const DUNGEON: PackedScene = preload("res://scenes/dungeons/dungeon_test.tscn")

const ROOM1_TRIGGER: Vector3 = Vector3(0, 0.1, -13)
const ROOM2_TRIGGER: Vector3 = Vector3(0, 0.1, -33)
const BOSS_TRIGGER: Vector3 = Vector3(0, 0.1, -53)
const STRIKE_RANGE: float = 1.6

var _pass: int = 0
var _fail: int = 0

var _dungeon: DungeonController = null
var _player: Player = null
var _prog: PlayerProgression = null
var _menu: PlayerStatsMenu = null
var _hud: ProgressionHUD = null


## Criticals are random (M11.7) and this suite checks exact damage, so they are
## off for its whole run: every player here reads this one cached instance of
## the combat data. critical_hit_test and m11_critical_run test criticals.
var _no_crits: PlayerCombatData = preload("res://resources/characters/player_combat.tres")


func _ready() -> void:
	_no_crits.critical_chance = 0.0
	_run()


func _run() -> void:
	await _wait(0.2)
	_reset_session()
	await _setup()
	await _menu_tests()
	await _allocation_tests()
	await _strength_tests()
	await _agility_tests()
	await _vitality_tests()
	await _intelligence_tests()
	await _pause_tests()
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


func _setup() -> void:
	_dungeon = DUNGEON.instantiate() as DungeonController
	# This test node runs while paused so its own coroutine survives the pause.
	# The dungeon would inherit that and never freeze, which it would not do as
	# a real scene root, so it is pinned back to pausable.
	_dungeon.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(_dungeon)
	await _wait(0.8)
	_player = _dungeon.get_node("Player")
	_prog = _player.progression
	_menu = _dungeon.get_node("PlayerStatsMenu")
	_hud = _dungeon.get_node("ProgressionHUD")


func _press_action(action: String) -> void:
	var event: InputEventAction = InputEventAction.new()
	event.action = action
	event.pressed = true
	get_viewport().push_input(event)
	await get_tree().process_frame


func _press_escape() -> void:
	var event: InputEventKey = InputEventKey.new()
	event.keycode = KEY_ESCAPE
	event.pressed = true
	get_viewport().push_input(event)
	await get_tree().process_frame


# --- the menu ---------------------------------------------------------------------

func _menu_tests() -> void:
	_record(_menu != null and not _menu.is_open(), "0) the stats menu starts closed")
	_record(_menu.hint.visible, "8) the '[C] Statistiche' hint is on screen while it is closed")

	await _press_action("character_stats")
	_record(_menu.is_open(), "1) C opens the stats menu")
	_record(get_tree().paused, "2) the game pauses")
	_record(_menu.last_mouse_mode_request == Input.MOUSE_MODE_VISIBLE,
		"3) the mouse is freed")
	_record(not _menu.hint.visible, "8b) the hint steps aside while the menu is up")

	await _press_action("character_stats")
	_record(not _menu.is_open(), "4) C closes it again")
	_record(not get_tree().paused, "6) the game resumes")
	# Headless refuses to capture the mouse, so the request is what is checkable.
	_record(_menu.last_mouse_mode_request == Input.MOUSE_MODE_CAPTURED,
		"7) the mouse is recaptured")

	await _press_action("character_stats")
	await _press_escape()
	_record(not _menu.is_open() and not get_tree().paused, "5) ESC closes it too")

	# ESC with the menu shut must keep doing what it always did.
	var before: int = _menu.last_mouse_mode_request
	await _press_escape()
	_record(not _menu.is_open() and not get_tree().paused
			and _menu.last_mouse_mode_request == before,
		"5b) ESC with the menu shut opens nothing, pauses nothing, touches nothing")


# --- allocation ---------------------------------------------------------------------

func _allocation_tests() -> void:
	await _press_action("character_stats")

	_record(_menu.get_level_text() == _menu.level_format % 1, "9) level shown: '%s'" % _menu.get_level_text())
	_record(_menu.get_points_text() == "Punti disponibili: 0",
		"10) points shown: '%s'" % _menu.get_points_text())
	_record(_menu.get_stat_value_text("STR") == "10" and _menu.get_stat_value_text("AGI") == "10"
			and _menu.get_stat_value_text("VIT") == "10" and _menu.get_stat_value_text("INT") == "10",
		"11) STR/AGI/VIT/INT all start at 10")
	_record(_menu.is_button_disabled("STR") and _menu.is_button_disabled("AGI")
			and _menu.is_button_disabled("VIT") and _menu.is_button_disabled("INT"),
		"12/30) with 0 points every [+] is disabled")

	# 12b) a press with nothing to spend must change nothing at all
	_menu.press_stat("STR")
	_record(_prog.strength == 10 and _prog.available_stat_points == 0,
		"12b) pressing [+] with no points does nothing (STR %d, points %d)" % [
			_prog.strength, _prog.available_stat_points])

	_prog.add_xp(100)
	await _wait(0.1)
	_record(_prog.current_level == 2 and _prog.available_stat_points == 5,
		"13) levelling awards 5 points (level %d, %d points)" % [
			_prog.current_level, _prog.available_stat_points])
	_record(not _menu.is_button_disabled("STR"), "14) the [+] buttons become usable")
	_record(_menu.get_points_text() == "Punti disponibili: 5",
		"10b) and the panel says so: '%s'" % _menu.get_points_text())

	_menu.press_stat("STR")
	_record(_prog.strength == 11, "16) one click raises STR to %d" % _prog.strength)
	_record(_prog.available_stat_points == 4,
		"15/29) and spends exactly one point (%d left)" % _prog.available_stat_points)
	_record(_menu.get_stat_value_text("STR") == "11"
			and _menu.get_points_text() == "Punti disponibili: 4",
		"31) the panel updates immediately: STR %s, '%s'" % [
			_menu.get_stat_value_text("STR"), _menu.get_points_text()])

	# spend the rest, then confirm the buttons lock again
	for i in 4:
		_menu.press_stat("INT")
	_record(_prog.available_stat_points == 0 and _prog.intelligence == 14,
		"29b) spending the rest leaves %d points, INT %d" % [
			_prog.available_stat_points, _prog.intelligence])
	_record(_menu.is_button_disabled("STR") and _menu.is_button_disabled("INT"),
		"30b) at zero the [+] buttons disable again")

	await _press_action("character_stats")


# --- STR ---------------------------------------------------------------------------

func _set_stat(stat: PlayerProgression.Stat, value: int) -> void:
	# Straight to the number under test: allocation itself is covered above.
	match stat:
		PlayerProgression.Stat.STRENGTH:
			_prog.strength = value
		PlayerProgression.Stat.AGILITY:
			_prog.agility = value
		PlayerProgression.Stat.VITALITY:
			_prog.vitality = value
		PlayerProgression.Stat.INTELLIGENCE:
			_prog.intelligence = value
	_prog.stats_changed.emit()


func _strength_tests() -> void:
	var combat_data: PlayerCombatData = _player.combat.data
	var step_1: AttackData = combat_data.light_combo[0]
	var step_2: AttackData = combat_data.light_combo[1]
	var base_damage: float = combat_data.base_damage
	var base_1: float = base_damage * step_1.damage_multiplier
	var base_2: float = base_damage * step_2.damage_multiplier

	_set_stat(PlayerProgression.Stat.STRENGTH, 10)
	_record(is_equal_approx(_prog.get_melee_damage_multiplier(), 1.0)
			and _prog.get_effective_damage(base_1) == base_1,
		"NUM-STR-1) STR 10: multiplier x%.2f, attack 1 stays %.0f" % [
			_prog.get_melee_damage_multiplier(), _prog.get_effective_damage(base_1)])

	_set_stat(PlayerProgression.Stat.STRENGTH, 15)
	_record(is_equal_approx(_prog.get_melee_damage_multiplier(), 1.15),
		"17) STR 15 gives x%.2f" % _prog.get_melee_damage_multiplier())
	_record(_prog.get_effective_damage(base_1) == 23.0,
		"NUM-STR-2) attack 1: %.0f base -> %.0f effective" % [
			base_1, _prog.get_effective_damage(base_1)])
	_record(_prog.get_effective_damage(base_2) == 29.0,
		"NUM-STR-3) attack 2: %.0f base -> %.0f effective" % [
			base_2, _prog.get_effective_damage(base_2)])
	_record(combat_data.base_damage == base_damage
			and combat_data.base_damage * step_1.damage_multiplier == base_1
			and combat_data.base_damage * step_2.damage_multiplier == base_2,
		"19) the base and the attacks are never written (%.0f / %.0f)" % [base_1, base_2])

	# 18) and it actually lands: swing at a real enemy and read its health
	_player.global_position = ROOM1_TRIGGER
	await _wait(0.5)
	var enemy: RoomCombatant = _dungeon.get_rooms()[0].get_enemies()[0]
	var dealt_15: float = await _measure_one_swing(enemy)
	_set_stat(PlayerProgression.Stat.STRENGTH, 10)
	var dealt_10: float = await _measure_one_swing(enemy)
	_record(dealt_15 == 23.0 and dealt_10 == 20.0,
		"18) a real swing deals %.0f at STR 15 and %.0f at STR 10" % [dealt_15, dealt_10])
	_record(combat_data.base_damage * step_1.damage_multiplier == base_1,
		"19b) still uncorrupted after real swings (%.0f)" % base_1)


## One swing of combo step 1 against `target`, returning the damage it took.
func _measure_one_swing(target: RoomCombatant) -> float:
	_player.combat.reset()
	var health: HealthComponent = target.get_node("HealthComponent")
	health.current_health = health.max_health
	health.is_dead = false
	_player.global_position = target.global_position + Vector3(0, 0, STRIKE_RANGE)
	_player.camera_rig.rotation.y = 0.0
	var before: float = health.current_health
	_player.camera_rig.attack_light_pressed.emit()
	var elapsed: float = 0.0
	while elapsed < 1.5:
		if health.current_health < before:
			break
		await get_tree().physics_frame
		elapsed += get_physics_process_delta_time()
	await _wait(0.6)
	return before - health.current_health


# --- AGI ---------------------------------------------------------------------------

func _agility_tests() -> void:
	var base_move: float = _player.movement_speed
	var base_dodge: float = _player.dodge_speed
	var combat_data: PlayerCombatData = _player.combat.data
	var iframe_start: float = combat_data.invulnerability_start
	var iframe_end: float = combat_data.invulnerability_end
	var dodge_duration: float = combat_data.dodge_duration
	var dodge_cooldown: float = combat_data.dodge_cooldown
	var step_1: AttackData = combat_data.light_combo[0]
	var step_timings: Array[float] = [step_1.windup, step_1.active, step_1.recovery]

	_set_stat(PlayerProgression.Stat.AGILITY, 10)
	_record(is_equal_approx(_player.effective_movement_speed, base_move)
			and is_equal_approx(_player.effective_dodge_speed, base_dodge),
		"NUM-AGI-1) AGI 10 is the baseline: move %.2f, dodge %.2f" % [
			_player.effective_movement_speed, _player.effective_dodge_speed])

	_set_stat(PlayerProgression.Stat.AGILITY, 15)
	_record(is_equal_approx(_player.effective_movement_speed, base_move * 1.05),
		"20/NUM-AGI-2) AGI 15: movement %.2f -> %.2f (x1.05)" % [
			base_move, _player.effective_movement_speed])
	_record(is_equal_approx(_player.effective_dodge_speed, base_dodge * 1.025),
		"21/NUM-AGI-3) AGI 15: dodge %.2f -> %.2f (x1.025)" % [
			base_dodge, _player.effective_dodge_speed])
	_record(is_equal_approx(_player.movement_speed, base_move)
			and is_equal_approx(_player.dodge_speed, base_dodge),
		"20b) the base values are untouched, so nothing compounds")

	# applying it twice must not stack
	_prog.stats_changed.emit()
	_prog.stats_changed.emit()
	_record(is_equal_approx(_player.effective_movement_speed, base_move * 1.05),
		"20c) recomputing twice gives the same %.2f" % _player.effective_movement_speed)

	_record(is_equal_approx(combat_data.invulnerability_start, iframe_start)
			and is_equal_approx(combat_data.invulnerability_end, iframe_end)
			and is_equal_approx(combat_data.dodge_duration, dodge_duration)
			and is_equal_approx(combat_data.dodge_cooldown, dodge_cooldown),
		"22) AGI leaves i-frames, dodge duration and cooldown alone")
	_record(is_equal_approx(step_1.windup, step_timings[0])
			and is_equal_approx(step_1.active, step_timings[1])
			and is_equal_approx(step_1.recovery, step_timings[2]),
		"23) and attack timings alone (%.2f/%.2f/%.2f)" % step_timings)

	_set_stat(PlayerProgression.Stat.AGILITY, 10)


# --- VIT ---------------------------------------------------------------------------

func _vitality_tests() -> void:
	var base_hp: float = _player.base_max_health
	_set_stat(PlayerProgression.Stat.VITALITY, 10)
	_record(is_equal_approx(_player.health_component.max_health, base_hp),
		"NUM-VIT-1) VIT 10: max health %.0f" % _player.health_component.max_health)

	# 25) wounded, then invest: the ceiling rises, the wound stays
	_player.health_component.current_health = 50.0
	_set_stat(PlayerProgression.Stat.VITALITY, 11)
	_record(is_equal_approx(_player.health_component.max_health, base_hp + 8.0),
		"24) one point of VIT adds 8: %.0f -> %.0f" % [base_hp, _player.health_component.max_health])
	_record(is_equal_approx(_player.health_component.current_health, 50.0),
		"25) and heals nothing: %.0f/%.0f" % [
			_player.health_component.current_health, _player.health_component.max_health])

	_set_stat(PlayerProgression.Stat.VITALITY, 15)
	_record(is_equal_approx(_player.health_component.max_health, base_hp + 40.0),
		"NUM-VIT-2) VIT 15: %.0f -> %.0f" % [base_hp, _player.health_component.max_health])

	# 26) nothing else in the world moved
	var enemy: RoomCombatant = _dungeon.get_rooms()[0].get_enemies()[0]
	var boss: DungeonBoss = _dungeon.get_rooms()[2].get_enemies()[0] as DungeonBoss
	var enemy_hp: float = (enemy.get_node("HealthComponent") as HealthComponent).max_health
	# Read from the stats assets rather than repeated here: this checks that the
	# player's VIT did not reach anything else, not what the boss is tuned to.
	_record(is_equal_approx(enemy_hp, enemy.stats.max_health)
			and is_equal_approx(boss.health_component.max_health, boss.stats.max_health),
		"26) enemy (%.0f) and boss (%.0f) keep their own maximums" % [
			enemy_hp, boss.health_component.max_health])

	_set_stat(PlayerProgression.Stat.VITALITY, 10)
	_player.health_component.current_health = _player.health_component.max_health


# --- INT ---------------------------------------------------------------------------

func _intelligence_tests() -> void:
	var move_before: float = _player.effective_movement_speed
	var hp_before: float = _player.health_component.max_health
	var melee_before: float = _prog.get_melee_damage_multiplier()

	_set_stat(PlayerProgression.Stat.INTELLIGENCE, 10)
	_record(is_equal_approx(_prog.get_ability_power_multiplier(), 1.0),
		"NUM-INT-1) INT 10: ability power x%.2f" % _prog.get_ability_power_multiplier())

	_set_stat(PlayerProgression.Stat.INTELLIGENCE, 15)
	_record(is_equal_approx(_prog.get_ability_power_multiplier(), 1.15),
		"27/NUM-INT-2) INT 15: x%.2f" % _prog.get_ability_power_multiplier())
	_record(is_equal_approx(_player.effective_movement_speed, move_before)
			and is_equal_approx(_player.health_component.max_health, hp_before)
			and is_equal_approx(_prog.get_melee_damage_multiplier(), melee_before),
		"28) and it changes nothing else — no system consumes it yet")

	await _press_action("character_stats")
	_record(_menu.get_derived_text().contains("x1.15")
			and _menu.get_derived_text().contains("Ability Power"),
		"31b) the panel shows it and says what it is for")
	_record(_menu.get_derived_text().contains("abilità future"),
		"28b) the panel is explicit that it is not used yet")
	await _press_action("character_stats")
	_set_stat(PlayerProgression.Stat.INTELLIGENCE, 10)


# --- pause -------------------------------------------------------------------------

func _pause_tests() -> void:
	# 33) an enemy mid-fight must actually stop
	_player.global_position = ROOM1_TRIGGER
	await _wait(0.6)
	var room1: RoomController = _dungeon.get_rooms()[0]
	var enemy: RoomCombatant = room1.get_enemies()[0]
	var room_state_before: int = room1.get_state()

	await _press_action("character_stats")
	var enemy_pos: Vector3 = enemy.global_position
	var player_hp: float = _player.health_component.current_health
	await _wait(0.8)
	_record(enemy.global_position.distance_to(enemy_pos) < 0.01
			and _player.health_component.current_health == player_hp,
		"33) an enemy in combat freezes while the menu is open (drift %.4f)" % [
			enemy.global_position.distance_to(enemy_pos)])
	_record(room1.get_state() == room_state_before,
		"32) the room keeps its state across the pause (%d)" % room1.get_state())

	# 34) the boss too
	await _press_action("character_stats")
	_player.global_position = BOSS_TRIGGER
	await _wait(0.8)
	var boss: DungeonBoss = _dungeon.get_rooms()[2].get_enemies()[0] as DungeonBoss
	_record(boss.combat_enabled, "34a) the boss encounter is live")
	await _press_action("character_stats")
	var boss_pos: Vector3 = boss.global_position
	var boss_state: int = boss.get_state()
	await _wait(1.0)
	_record(boss.global_position.distance_to(boss_pos) < 0.01 and boss.get_state() == boss_state,
		"34) the boss freezes too (drift %.4f, state %d)" % [
			boss.global_position.distance_to(boss_pos), boss.get_state()])

	# 35) and everything picks back up
	await _press_action("character_stats")
	await _wait(0.8)
	_record(not get_tree().paused and boss.global_position.distance_to(boss_pos) > 0.01,
		"35) closing the menu resumes the fight (moved %.3f)" % [
			boss.global_position.distance_to(boss_pos)])


## Every suite starts from a clean session: PlayerRuntimeState now carries
## progression and health across scene changes, so without this a later test
## would inherit whatever an earlier one left behind.
func _reset_session() -> void:
	var state: Node = get_tree().root.get_node_or_null("PlayerRuntimeState")
	if state != null:
		state.reset_runtime_state()
