extends SceneTree

## M10.2 — who owns the character's state, across every scene change a session
## makes.
##
##   godot --headless --path . --script res://tests/core/persistent_state_run.gd
##
## The other suites check that progression SURVIVES. This one checks why: that
## there is one PlayerProgressionData and one shadow array per session, that
## every player scene is a view onto them rather than a copy, that a New Game is
## the only thing that replaces them, and that a kill pays once. It walks the
## real route — menu, hub, gate, dungeon, boss, exit, death, menu again — so the
## identity checks are made on the players the game actually builds.

const BOOT: String = "res://Main.tscn"
const HUB: String = "res://scenes/core/hub.tscn"
const DUNGEON: String = "res://scenes/dungeons/dungeon_test.tscn"
const ROOM_ANCHORS: Array[Vector3] = [
	Vector3(0, 0.1, -13), Vector3(0, 0.1, -33), Vector3(0, 0.1, -53)
]
const EXIT_POS: Vector3 = Vector3(0, 0.1, -65)
const STRIKE_RANGE: float = 1.6

var _stats: ProgressionStats = preload("res://resources/characters/player_progression.tres")
var _shadow_data: ShadowData = preload("res://resources/shadows/basic_melee_shadow.tres")
var _pass: int = 0
var _fail: int = 0
var _state: Node = null
## Carried between phases: the objects the session held, to prove they are the
## same ones later — or, after a New Game, that they are not.
var _data: PlayerProgressionData = null
var _shadow_array: Array[ShadowInstance] = []
var _shadow: ShadowInstance = null


func _initialize() -> void:
	_state = root.get_node_or_null("PlayerRuntimeState")
	_state.reset_runtime_state()

	await _phase_new_game()
	await _phase_hub_xp()
	await _phase_into_the_dungeon()
	await _phase_kills_pay_once()
	await _phase_shadow_kill()
	await _phase_boss_and_home()
	await _phase_death()
	await _phase_new_game_again()

	print("[SUMMARY] passed=%d failed=%d" % [_pass, _fail])
	await _pause(0.3)
	quit()


# --- 1-8. GIOCA is a New Game, and the player is a view onto the session -------------------

func _phase_new_game() -> void:
	# A previous game's character, left behind in the session. GIOCA must not
	# carry it into the new one.
	var stale: PlayerProgressionData = _state.get_or_create_progression(_stats)
	stale.current_level = 7
	stale.current_xp = 40
	_state.shadows.append(ShadowInstance.new(&"shadow_999999", _shadow_data, 3, 5))

	change_scene_to_file(BOOT)
	await _pause(0.6)
	var menu: MainMenu = current_scene.get_node("MainMenu")
	menu.press_play()
	await _pause(1.4)
	_record(current_scene.scene_file_path == HUB, "1) GIOCA leads to the hub")

	var p: Player = current_scene.get_node("Player")
	var prog: PlayerProgression = p.progression
	_record(prog.current_level == _stats.starting_level and prog.current_xp == 0
			and prog.available_stat_points == 0,
		"2) a new game starts at level %d, 0 XP, 0 points (got Lv.%d, %d XP, %d)" % [
			_stats.starting_level, prog.current_level, prog.current_xp,
			prog.available_stat_points])
	_record(prog.strength == _stats.strength and prog.agility == _stats.agility
			and prog.vitality == _stats.vitality and prog.intelligence == _stats.intelligence,
		"3) with the starting stat block from ProgressionStats")
	_record(p.shadows.is_empty(), "4) and no shadows")
	_record(not is_same(_state.progression, stale),
		"5) the previous game's character was replaced, not reused")

	_data = _state.progression
	_shadow_array = _state.shadows
	_record(_data != null and is_same(prog._data, _data),
		"6) the player's progression IS the session's object, not a copy of it")
	_record(is_same(p.shadows._shadows, _shadow_array),
		"7) and its shadow collection IS the session's array")
	_record(is_equal_approx(p.health_component.current_health, p.health_component.max_health),
		"8) the new character starts at full health (%.0f)" % p.health_component.current_health)


# --- 9-19. XP: one owner, level-ups once, the remainder kept, the UI only reads ------------

func _phase_hub_xp() -> void:
	var p: Player = current_scene.get_node("Player")
	var prog: PlayerProgression = p.progression
	var fired: Dictionary = {"level_up": 0, "level_changed": 0, "xp_changed": 0,
		"last_level": 0, "last_points": 0}
	prog.level_up.connect(func(level: int, points: int) -> void:
		fired["level_up"] += 1
		fired["last_level"] = level
		fired["last_points"] = points)
	prog.level_changed.connect(func(_level: int) -> void: fired["level_changed"] += 1)
	prog.xp_changed.connect(func(_xp: int, _required: int) -> void: fired["xp_changed"] += 1)

	var first_step: int = prog.xp_required_for_level(1)
	prog.add_xp(first_step + 30)
	_record(prog.current_level == 2 and prog.current_xp == 30,
		"9) %d XP crosses level 1 and keeps the 30 left over (Lv.%d, %d XP)" % [
			first_step + 30, prog.current_level, prog.current_xp])
	_record(prog.available_stat_points == prog.stat_points_per_level,
		"10) paying one level's points (%d)" % prog.available_stat_points)
	_record(fired["level_up"] == 1 and fired["level_changed"] == 1 and fired["xp_changed"] == 1,
		"11) level_up, level_changed and xp_changed each fired once (%d/%d/%d)" % [
			fired["level_up"], fired["level_changed"], fired["xp_changed"]])
	_record(_data.current_level == 2 and _data.current_xp == 30,
		"12) and the session already has it, with no sync step")

	# Two levels in one award: one level-up, carrying both.
	var two_levels: int = (prog.xp_required_for_level(2) - 30) + prog.xp_required_for_level(3) + 10
	prog.add_xp(two_levels)
	_record(prog.current_level == 4 and prog.current_xp == 10,
		"13) %d XP crosses two levels at once and keeps the 10 left over (Lv.%d, %d XP)" % [
			two_levels, prog.current_level, prog.current_xp])
	_record(fired["level_up"] == 2 and fired["last_level"] == 4
			and fired["last_points"] == 2 * prog.stat_points_per_level,
		"14) announced as ONE level-up to Lv.%d worth %d points" % [
			fired["last_level"], fired["last_points"]])
	_record(prog.available_stat_points == 3 * prog.stat_points_per_level,
		"15) every level paid its points exactly once (%d)" % prog.available_stat_points)

	# A spent point goes through the owner's API and lands in the session.
	prog.allocate_stat(PlayerProgression.Stat.STRENGTH)
	_record(_data.strength == _stats.strength + 1
			and _data.available_stat_points == 3 * prog.stat_points_per_level - 1,
		"16) allocating a point writes the session's own stat block")

	var hud: ProgressionHUD = get_first_node_in_group(ProgressionHUD.GROUP) as ProgressionHUD
	_record(hud != null and hud.get_level_text() == hud.level_format % 4,
		"17) the HUD shows '%s', read from the owner" % (hud.get_level_text() if hud else "?"))
	_record(hud != null and hud.get_xp_text() == hud.xp_format % [10, prog.get_xp_to_next_level()],
		"18) and '%s' for XP" % (hud.get_xp_text() if hud else "?"))
	_record(prog.get_total_xp() == first_step + 30 + two_levels,
		"19) the total XP ever earned is exactly what was given (%d)" % prog.get_total_xp())


# --- 20-25. a scene change rebuilds the player, never the character ------------------------

func _phase_into_the_dungeon() -> void:
	var p: Player = current_scene.get_node("Player")
	var before: Dictionary = _snapshot(p)
	var old_id: int = p.get_instance_id()
	_shadow = p.shadows.add_shadow(_shadow_data)
	_record(_shadow_array.size() == 1 and is_same(_shadow_array[0], _shadow),
		"20) an extracted shadow is the very instance the session holds")
	before["shadows"] = _shadow_list(p)

	await _enter_dungeon()
	var p2: Player = current_scene.get_node("Player")
	_record(current_scene.scene_file_path == DUNGEON and p2.get_instance_id() != old_id,
		"21) the gate leads into the dungeon with a newly built player")
	_record(is_same(p2.progression._data, _data),
		"22) which attaches to the same progression object")
	var after: Dictionary = _snapshot(p2)
	after["shadows"] = _shadow_list(p2)
	_record(_same(before, after),
		"23) so level, XP, points, stats and shadows are untouched: %s" % [after])
	_record(is_same(p2.shadows._shadows, _shadow_array)
			and is_same(p2.shadows.get_shadow(_shadow.instance_id), _shadow),
		"24) and to the same shadow array, holding the same instance")
	_record(is_same(_state.progression, _data),
		"25) the scene change did not replace or rebuild the session's character")


# --- 26-29. a kill pays once, however often its death is announced ------------------------

func _phase_kills_pay_once() -> void:
	var dungeon: DungeonController = current_scene as DungeonController
	var p: Player = current_scene.get_node("Player")
	p.hurtbox.set_invulnerable(true)
	p.global_position = ROOM_ANCHORS[0]
	await _pause(0.8)

	var enemy: RoomCombatant = dungeon.get_rooms()[0].get_enemies()[0]
	var reward: int = enemy.get_xp_reward()
	var total_before: int = p.progression.get_total_xp()
	await _kill(p, enemy)
	await _pause(0.4)
	_record(enemy.has_died() and p.progression.get_total_xp() - total_before == reward,
		"26) a kill the player lands pays its %d XP" % reward)

	var total_after: int = p.progression.get_total_xp()
	enemy.enemy_died.emit(enemy)
	await _pause(0.2)
	_record(p.progression.get_total_xp() == total_after,
		"27) announcing the same death again pays nothing")
	_record(enemy.claim_xp() == 0, "28) the reward is latched on the combatant itself")
	_record(_data.current_xp == p.progression.current_xp
			and _data.current_level == p.progression.current_level,
		"29) and the session holds exactly what the player reads")


# --- 30-36. a shadow kill: 70% to the shadow, 30% to the player, owned by the data ----------

func _phase_shadow_kill() -> void:
	var dungeon: DungeonController = current_scene as DungeonController
	var p: Player = current_scene.get_node("Player")
	var node: BasicMeleeShadow = p.shadow_summoner.summon(_shadow.instance_id)
	await _pause(0.5)
	node.hurtbox.set_invulnerable(true)
	_record(is_same(node.instance, _shadow),
		"30) the summoned entity is a view onto the session's instance")

	var enemy: RoomCombatant = dungeon.get_rooms()[0].get_enemies()[1]
	var reward: int = enemy.get_xp_reward()
	var expected_shadow: int = int(round(reward * PlayerProgression.SHADOW_KILL_SHARE))
	var player_before: int = p.progression.get_total_xp()
	var shadow_before: int = _shadow_total_xp(_shadow)
	await _shadow_finishes(p, node, enemy)
	_record(enemy.get_killer() == node, "31) the shadow is recorded as the killer")
	_record(_shadow_total_xp(_shadow) - shadow_before == expected_shadow,
		"32) the shadow took %d of %d (70%%)" % [_shadow_total_xp(_shadow) - shadow_before, reward])
	_record(p.progression.get_total_xp() - player_before == reward - expected_shadow,
		"33) the player took the remaining %d (30%%)" % [p.progression.get_total_xp() - player_before])

	var level: int = _shadow.level
	var xp: int = _shadow.current_xp
	enemy.enemy_died.emit(enemy)
	await _pause(0.2)
	_record(_shadow.level == level and _shadow.current_xp == xp,
		"34) a repeated death announcement pays the shadow nothing either")

	p.shadow_summoner.recall()
	await _pause(0.3)
	_record(not is_instance_valid(node) or node.is_queued_for_deletion(),
		"35) recalling frees the entity")
	_record(_shadow.level == level and _shadow.current_xp == xp
			and is_same(_shadow_array[0], _shadow),
		"36) and the shadow's Lv.%d and %d XP stay in the session" % [_shadow.level, _shadow.current_xp])


# --- 37-43. the boss, the way home, and the character unchanged by both ---------------------

func _phase_boss_and_home() -> void:
	var dungeon: DungeonController = current_scene as DungeonController
	var p: Player = current_scene.get_node("Player")
	for index in range(0, 2):
		p.global_position = ROOM_ANCHORS[index]
		await _pause(0.7)
		for enemy in dungeon.get_rooms()[index].get_enemies():
			if not enemy.has_died():
				await _kill(p, enemy)
				await _pause(0.3)
	p.global_position = ROOM_ANCHORS[2]
	await _pause(1.2)
	var boss: DungeonBoss = dungeon.get_rooms()[2].get_enemies()[0] as DungeonBoss
	var total_before: int = p.progression.get_total_xp()
	await _kill(p, boss, 90.0)
	await _pause(1.2)
	_record(boss.has_died() and dungeon.get_state() == DungeonController.DungeonState.COMPLETED,
		"37) the boss falls and the dungeon completes")
	_record(p.progression.get_total_xp() - total_before == boss.get_xp_reward(),
		"38) the boss pays its %d XP once" % boss.get_xp_reward())
	RunSummary.dismiss_open(self)
	await _pause(0.4)

	var before: Dictionary = _snapshot(p)
	before["shadows"] = _shadow_list(p)
	var old_id: int = p.get_instance_id()
	p.global_position = EXIT_POS
	await _pause(0.5)
	dungeon.exit_portal.activate()
	await _pause(1.4)

	var home: Player = current_scene.get_node("Player")
	_record(current_scene.scene_file_path == HUB and home.get_instance_id() != old_id,
		"39) the exit returns to the hub with a newly built player")
	var after: Dictionary = _snapshot(home)
	after["shadows"] = _shadow_list(home)
	_record(_same(before, after), "40) carrying everything: %s" % [after])
	_record(is_same(home.progression._data, _data) and is_same(_state.progression, _data),
		"41) through the same progression object")
	_record(is_same(home.shadows._shadows, _shadow_array)
			and is_same(home.shadows.get_shadow(_shadow.instance_id), _shadow),
		"42) and the same shadow instance")
	_record(home.progression.available_stat_points == before["points"],
		"43) no level-up was replayed on the way in (points %d)" % home.progression.available_stat_points)


# --- 44-47. death restarts the run and touches nothing the character owns ------------------

func _phase_death() -> void:
	await _enter_dungeon()
	var p: Player = current_scene.get_node("Player")
	var old_id: int = p.get_instance_id()
	var before: Dictionary = _snapshot(p)
	before["shadows"] = _shadow_list(p)
	p.hurtbox.set_invulnerable(false)
	p.health_component.receive_damage(1000000.0)
	await _pause(3.1)

	var p2: Player = current_scene.get_node("Player")
	await _pause(0.3)
	_record(current_scene.scene_file_path == DUNGEON and p2.get_instance_id() != old_id,
		"44) dying reloads the dungeon with a new player")
	var after: Dictionary = _snapshot(p2)
	after["shadows"] = _shadow_list(p2)
	_record(_same(before, after), "45) with no level, XP or point lost or gained: %s" % [after])
	_record(is_same(p2.progression._data, _data) and p2.shadows.get_count() == 1,
		"46) the same character, and still exactly one shadow — none duplicated")
	_record(is_equal_approx(p2.health_component.current_health, p2.health_component.max_health),
		"47) at full health for the new attempt")


# --- 48-54. back to the menu: a New Game replaces the character, and the old one is inert ---

func _phase_new_game_again() -> void:
	var old_data: PlayerProgressionData = _data
	var old_shadows: Array[ShadowInstance] = _shadow_array
	var old_level: int = old_data.current_level

	# Nothing in the game leads back to the menu yet, so the harness goes there
	# itself: what is under test is GIOCA, not the route to it.
	change_scene_to_file(BOOT)
	await _pause(0.6)
	var menu: MainMenu = current_scene.get_node("MainMenu")
	menu.press_play()
	await _pause(1.4)

	var p: Player = current_scene.get_node("Player")
	_record(current_scene.scene_file_path == HUB, "48) GIOCA again leads to the hub")
	_record(p.progression.current_level == _stats.starting_level
			and p.progression.current_xp == 0 and p.progression.available_stat_points == 0
			and p.progression.strength == _stats.strength,
		"49) as a new character (Lv.%d, %d XP) — not the old Lv.%d" % [
			p.progression.current_level, p.progression.current_xp, old_level])
	_record(p.shadows.is_empty() and _state.next_shadow_index == 1,
		"50) with no shadows, and numbering from the start again")
	_record(not is_same(_state.progression, old_data) and is_same(p.progression._data, _state.progression),
		"51) on a new progression object the player is attached to")
	_record(not is_same(_state.shadows, old_shadows) and is_same(p.shadows._shadows, _state.shadows),
		"52) and a new shadow array")

	# Something still holding the old game can no longer reach the new one.
	old_data.current_xp += 999
	old_shadows.append(ShadowInstance.new(&"shadow_888888", _shadow_data))
	_record(p.progression.current_xp == 0 and _state.progression.current_xp == 0,
		"53) writing to the old character changes nothing in the new game")
	_record(p.shadows.is_empty() and _state.shadows.is_empty(),
		"54) nor does adding to the old shadow array")


# --- helpers ----------------------------------------------------------------------------------

func _pause(t: float) -> void:
	await create_timer(t).timeout


func _record(passed: bool, description: String) -> void:
	if passed:
		_pass += 1
		print("[PASS] " + description)
	else:
		_fail += 1
		print("[FAIL] " + description)


func _enter_dungeon() -> void:
	var p: Player = current_scene.get_node("Player")
	var gate: DungeonGate = current_scene.get_node("DungeonGate")
	p.global_position = gate.global_position
	await _pause(0.3)
	gate.activate()
	await _pause(1.4)


func _snapshot(player: Player) -> Dictionary:
	var prog: PlayerProgression = player.progression
	return {
		"level": prog.current_level,
		"xp": prog.current_xp,
		"total_xp": prog.get_total_xp(),
		"points": prog.available_stat_points,
		"str": prog.strength,
		"agi": prog.agility,
		"vit": prog.vitality,
		"int": prog.intelligence,
	}


func _shadow_list(player: Player) -> Array[String]:
	var out: Array[String] = []
	for shadow in player.shadows.get_shadows():
		out.append("%s:%d/%d" % [shadow.get_short_id(), shadow.level, shadow.current_xp])
	return out


func _same(a: Dictionary, b: Dictionary) -> bool:
	for key in a:
		if a[key] != b.get(key):
			print("      [diff] %s: %s vs %s" % [key, a[key], b.get(key)])
			return false
	return true


## Every point of XP this shadow has earned, levels included, so a level-up in
## the middle of an award cannot hide part of it.
func _shadow_total_xp(shadow: ShadowInstance) -> int:
	var total: int = shadow.current_xp
	for level in range(1, shadow.level):
		total += shadow.shadow_data.xp_required_for_level(level)
	return total


## The shadow opens the enemy up, so progression hears about it through the
## shadow's own hitbox, then lands the last blow — which is what makes the split
## apply.
func _shadow_finishes(player: Player, node: BasicMeleeShadow, enemy: RoomCombatant) -> void:
	player.global_position = enemy.global_position + Vector3(0, 0, STRIKE_RANGE)
	node.global_position = enemy.global_position + Vector3(0, 0, 2.0)
	node.set_manual_target(enemy)
	var health: HealthComponent = enemy.get_node("HealthComponent") as HealthComponent
	var full: float = health.current_health
	var waited: float = 0.0
	while waited < 8.0 and is_equal_approx(health.current_health, full):
		await physics_frame
		waited += 1.0 / 60.0
	(enemy.get_node("Hurtbox") as Hurtbox).receive_hit(1000000.0, node)
	await _pause(0.6)


func _kill(player: Player, target: RoomCombatant, budget: float = 40.0) -> void:
	var elapsed: float = 0.0
	while elapsed < budget and not target.has_died():
		if player.get("_attack_state") == Player.AttackState.IDLE:
			player.global_position = target.global_position + Vector3(0, 0, STRIKE_RANGE)
			player.camera_rig.rotation.y = 0.0
			player.camera_rig.attack_light_pressed.emit()
		await physics_frame
		elapsed += 1.0 / 60.0
