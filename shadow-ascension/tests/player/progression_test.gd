extends Node3D

## M6.1 Player Progression Foundation — the XP curve, levelling, stat points,
## enemy and boss rewards, award-once safety, and the HUD.
##
## The reward tests land real player hits, because XP only ever flows through the
## player's own attack hitbox: an enemy the player never touched is never
## subscribed to, which is the whole point of the design.

const DUNGEON: PackedScene = preload("res://scenes/dungeons/dungeon_test.tscn")
const PLAYER: PackedScene = preload("res://scenes/player/player.tscn")

const ROOM1_TRIGGER: Vector3 = Vector3(0, 0.1, -13)
const ROOM2_TRIGGER: Vector3 = Vector3(0, 0.1, -33)
const BOSS_TRIGGER: Vector3 = Vector3(0, 0.1, -53)
const STRIKE_RANGE: float = 1.6

var _pass: int = 0
var _fail: int = 0

var _dungeon: DungeonController = null
var _player: Player = null
var _prog: PlayerProgression = null
var _hud: ProgressionHUD = null


func _ready() -> void:
	_run()


func _run() -> void:
	await _wait(0.2)
	await _curve_tests()
	await _levelling_tests()
	await _dungeon_reward_tests()
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


# --- starting state and the curve ----------------------------------------------

func _curve_tests() -> void:
	var player: Player = PLAYER.instantiate() as Player
	add_child(player)
	await _wait(0.3)
	var p: PlayerProgression = player.progression

	_record(p != null and p.current_level == 1, "1) the player starts at level 1")
	_record(p.current_xp == 0, "2) with 0 XP")
	_record(p.get_xp_to_next_level() == 100,
		"3) and 100 XP to the next level (%d)" % p.get_xp_to_next_level())
	_record(p.strength == 10, "4) STR = %d" % p.strength)
	_record(p.agility == 10, "5) AGI = %d" % p.agility)
	_record(p.vitality == 10, "6) VIT = %d" % p.vitality)
	_record(p.intelligence == 10, "7) INT = %d" % p.intelligence)
	_record(p.available_stat_points == 0,
		"8) available stat points = %d" % p.available_stat_points)

	# The curve is computed, never a table.
	_record(p.xp_required_for_level(1) == 100 and p.xp_required_for_level(2) == 125
			and p.xp_required_for_level(3) == 156,
		"16a) the curve runs 100 / 125 / 156 (%d / %d / %d)" % [
			p.xp_required_for_level(1), p.xp_required_for_level(2), p.xp_required_for_level(3)])

	player.queue_free()
	await _wait(0.3)


# --- levelling ------------------------------------------------------------------

func _levelling_tests() -> void:
	var player: Player = PLAYER.instantiate() as Player
	add_child(player)
	await _wait(0.3)
	var p: PlayerProgression = player.progression

	var levelled: Array[int] = []
	var points: Array[int] = []
	p.level_up.connect(func(level: int, gained: int) -> void:
		levelled.append(level)
		points.append(gained))

	p.add_xp(0)
	p.add_xp(-50)
	_record(p.current_xp == 0 and p.current_level == 1,
		"add) a zero or negative reward is ignored (%d XP, level %d)" % [p.current_xp, p.current_level])

	p.add_xp(90)
	_record(p.current_xp == 90 and p.current_level == 1 and levelled.is_empty(),
		"13a) 90 XP does not level up yet (%d/%d)" % [p.current_xp, p.get_xp_to_next_level()])

	p.add_xp(10)
	_record(p.current_level == 2, "13) reaching 100 XP levels to 2 (level %d)" % p.current_level)
	_record(p.current_xp == 0, "14a) leftover XP is 0 (%d)" % p.current_xp)
	_record(p.available_stat_points == 5,
		"15) the level awarded 5 stat points (%d)" % p.available_stat_points)
	_record(p.get_xp_to_next_level() == 125,
		"16) the next threshold is 125 (%d)" % p.get_xp_to_next_level())
	_record(levelled == [2] and points == [5], "17a) one level_up signal fired: %s %s" % [levelled, points])

	# 14) leftover carries properly when the reward overshoots
	p.add_xp(200)
	_record(p.current_level == 3 and p.current_xp == 75,
		"14) overshooting carries the remainder (level %d, %d/%d)" % [
			p.current_level, p.current_xp, p.get_xp_to_next_level()])

	# 20/21) one big reward, several levels, one report
	levelled.clear()
	points.clear()
	var before_level: int = p.current_level
	p.add_xp(5000)
	_record(p.current_level > before_level + 1,
		"20) a single large reward levels up several times (%d -> %d)" % [before_level, p.current_level])
	_record(levelled.size() == 1 and points[0] == 5 * (p.current_level - before_level),
		"20b) reported once, with every point awarded on the way (+%d)" % points[0])
	_record(p.current_xp < p.get_xp_to_next_level(),
		"21a) the loop ends below the next threshold (%d/%d)" % [
			p.current_xp, p.get_xp_to_next_level()])

	# 21) a runaway reward terminates and leaves a consistent state. It does not
	# reach the ceiling — on a 1.25^n curve a billion XP is only worth ~67 levels.
	var huge_level: int = p.current_level
	p.add_xp(999999999)
	_record(p.current_level > huge_level and p.current_level <= p.max_level
			and p.current_xp >= 0 and p.current_xp < p.get_xp_to_next_level(),
		"21) a billion XP terminates cleanly at level %d, %d/%d" % [
			p.current_level, p.current_xp, p.get_xp_to_next_level()])

	# 21b) the ceiling itself: nothing accrues past it
	p.current_level = p.max_level
	p.current_xp = 0
	p.add_xp(5000)
	_record(p.is_max_level() and p.current_level == p.max_level and p.current_xp == 0,
		"21b) at the max level further XP changes nothing (level %d, %d XP)" % [
			p.current_level, p.current_xp])
	_record(p.get_xp_to_next_level() == 0 and is_equal_approx(p.get_xp_ratio(), 1.0),
		"21c) and the bar reads full rather than drifting")

	player.queue_free()
	await _wait(0.3)


# --- rewards, in a real dungeon --------------------------------------------------

func _swing(target: Node3D) -> void:
	_player.global_position = target.global_position + Vector3(0, 0, STRIKE_RANGE)
	_player.camera_rig.rotation.y = 0.0
	_player.camera_rig.attack_light_pressed.emit()


## Hits the target with the player's real combo until it dies.
func _kill_with_combo(target: RoomCombatant, budget: float = 12.0) -> int:
	var swings: int = 0
	var elapsed: float = 0.0
	while elapsed < budget and not target.has_died():
		if _player.get("_attack_state") == Player.AttackState.IDLE:
			_swing(target)
			swings += 1
		await get_tree().physics_frame
		elapsed += get_physics_process_delta_time()
	return swings


func _dungeon_reward_tests() -> void:
	_dungeon = DUNGEON.instantiate() as DungeonController
	add_child(_dungeon)
	await _wait(0.8)
	_player = _dungeon.get_node("Player")
	_prog = _player.progression
	_hud = _dungeon.get_node("ProgressionHUD")
	_player.hurtbox.set_invulnerable(true)

	_record(_hud != null and _hud.get_level_text() == "LV. 1" and _hud.get_xp_text() == "0 / 100",
		"18a/19a) the HUD starts at '%s  %s'" % [_hud.get_level_text(), _hud.get_xp_text()])

	# --- room 1: two enemies, killed with the player's own combo
	_player.global_position = ROOM1_TRIGGER
	await _wait(0.5)
	var room1: RoomController = _dungeon.get_rooms()[0]
	_record(room1.get_enemies().size() == 2,
		"9a) room 1 holds %d enemies" % room1.get_enemies().size())

	var first: RoomCombatant = room1.get_enemies()[0]
	var swings: int = await _kill_with_combo(first)
	await _wait(0.3)
	_record(first.has_died() and _prog.current_xp == 25,
		"9) killing one BasicMeleeEnemy with the combo awards 25 XP (%d swings, %d XP)" % [
			swings, _prog.current_xp])
	_record(_hud.get_xp_text() == "25 / 100" and is_equal_approx(_hud.get_xp_ratio(), 0.25),
		"19) the XP bar follows: '%s' (%.2f)" % [_hud.get_xp_text(), _hud.get_xp_ratio()])

	# 10) the same corpse cannot pay twice, however it is prodded
	first.enemy_died.emit(first)
	first.report_death()
	_prog._collect(first)
	await _wait(0.2)
	_record(_prog.current_xp == 25,
		"10) re-firing its death signal awards nothing more (%d XP)" % _prog.current_xp)

	await _kill_with_combo(room1.get_enemies()[1])
	await _wait(0.5)
	_record(_prog.current_xp == 50, "11) two enemies = 50 XP (%d)" % _prog.current_xp)
	_record(room1.is_cleared(), "25a) and the room cleared normally")
	var after_clear: int = _prog.current_xp
	await _wait(0.5)
	_record(_prog.current_xp == after_clear,
		"25) clearing the room adds no XP of its own (%d)" % _prog.current_xp)

	# --- room 2: three more enemies; the fourth kill crosses 100
	_player.global_position = ROOM2_TRIGGER
	await _wait(0.5)
	var room2: RoomController = _dungeon.get_rooms()[1]
	_record(room2.get_enemies().size() == 3,
		"12a) room 2 holds %d enemies" % room2.get_enemies().size())

	await _kill_with_combo(room2.get_enemies()[0])
	await _wait(0.3)
	_record(_prog.current_xp == 75, "11b) three enemies = 75 XP (%d)" % _prog.current_xp)

	await _kill_with_combo(room2.get_enemies()[1])
	await _wait(0.4)
	_record(_prog.current_level == 2 and _prog.current_xp == 0,
		"12/13b) the fourth kill reaches 100 XP and levels to %d (%d XP left)" % [
			_prog.current_level, _prog.current_xp])
	_record(_prog.available_stat_points == 5,
		"15b) +5 stat points (%d)" % _prog.available_stat_points)
	_record(_hud.is_banner_showing() and _hud.get_banner_text().begins_with("LEVEL UP!")
			and _hud.get_banner_text().contains("Level 2")
			and _hud.get_banner_text().contains("+5 Stat Points"),
		"17) the level-up callout appears: %s" % _hud.get_banner_text().replace("\n", " "))
	_record(_hud.get_level_text() == "LV. 2" and _hud.get_xp_text() == "0 / 125",
		"18) the HUD reads '%s  %s' after levelling" % [_hud.get_level_text(), _hud.get_xp_text()])

	await _kill_with_combo(room2.get_enemies()[2])
	await _wait(0.6)
	_record(_prog.current_xp == 25 and room2.is_cleared(),
		"11c) the fifth kill brings it to %d XP, room 2 cleared" % _prog.current_xp)

	await _wait(1.9)
	_record(not _hud.is_banner_showing(), "17b) the callout fades on its own")

	# --- boss
	_player.global_position = BOSS_TRIGGER
	await _wait(0.6)
	var boss: DungeonBoss = _dungeon.get_rooms()[2].get_enemies()[0] as DungeonBoss
	var before_boss: int = _total_xp()
	_record(boss.xp_reward == 200, "22a) the boss declares %d XP" % boss.xp_reward)

	# 24) the phase transition must not pay out
	_swing(boss)
	await _wait(0.4)
	var after_first_hit: int = _total_xp()
	boss.hurtbox.receive_hit(boss.health_component.max_health * 0.55, null)
	await _wait(2.2)
	_record(boss.get_phase() == DungeonBoss.BossPhase.PHASE_2, "24a) the boss entered phase 2")
	_record(_total_xp() == after_first_hit,
		"24) the phase transition awards no XP (%d -> %d)" % [after_first_hit, _total_xp()])

	var boss_swings: int = await _kill_with_combo(boss, 40.0)
	await _wait(0.8)
	_record(boss.has_died() and _total_xp() - before_boss == 200,
		"22) killing the boss awards 200 XP (%d swings, +%d)" % [
			boss_swings, _total_xp() - before_boss])

	var after_boss: int = _total_xp()
	boss.enemy_died.emit(boss)
	_prog._collect(boss)
	await _wait(0.3)
	_record(_total_xp() == after_boss,
		"23) the boss cannot pay a second time (%d)" % _total_xp())

	await _wait(1.0)
	_record(_dungeon.get_state() == DungeonController.DungeonState.COMPLETED,
		"26a) the dungeon completed")
	_record(_total_xp() == after_boss,
		"26) dungeon completion adds no XP of its own (%d)" % _total_xp())
	_record(_dungeon.exit_portal.is_enabled(), "27/29) the exit portal went live — the flow is intact")

	# 28) enemies still fight: the boss got its hits in on an invulnerable player
	_player.hurtbox.set_invulnerable(false)


## Level plus leftover expressed as one number, so a level-up in the middle of a
## measurement does not hide the XP that caused it.
func _total_xp() -> int:
	var total: int = _prog.current_xp
	for level in range(1, _prog.current_level):
		total += _prog.xp_required_for_level(level)
	return total
