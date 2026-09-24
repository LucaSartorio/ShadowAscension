extends SceneTree

## M10 closure review — the architecture holding up under repetition.
##
##   godot --headless --path . --script res://tests/core/m10_review_run.gd
##
## The M10 suites each prove one property once. This one repeats the loop a
## player actually repeats — hub, gate, dungeon, fight, back — three times in one
## session and checks after every cycle that nothing has accumulated: not a
## player, not a shadow, not a listener, not a node in memory, not a point of
## XP paid twice. Each cycle also fights through the automatically re-summoned
## shadow, so the 70/30 split is checked on a shadow that crossed a scene change,
## and announces a death twice in a room that still has an enemy up. It ends by
## going back to the menu and starting a new game.

const BOOT: String = "res://Main.tscn"
const HUB: String = "res://scenes/core/hub.tscn"
const DUNGEON: String = "res://scenes/dungeons/dungeon_test.tscn"
const ROOM1_ANCHOR: Vector3 = Vector3(0, 0.1, -13)
const STRIKE_RANGE: float = 1.6
const CYCLES: int = 3

var _shadow_data: ShadowData = preload("res://resources/shadows/basic_melee_shadow.tres")
var _state: Node = null
var _pass: int = 0
var _fail: int = 0
## What the session should hold, kept by this harness from what each kill paid.
var _expected_player_xp: int = 0
var _expected_shadow_xp: int = 0
var _hub_nodes: int = -1
var _hub_orphans: int = -1
var _listeners: Dictionary = {}


func _initialize() -> void:
	_state = root.get_node_or_null("PlayerRuntimeState")
	_state.reset_runtime_state()

	change_scene_to_file(BOOT)
	await _pause(0.6)
	(current_scene.get_node("MainMenu") as MainMenu).press_play()
	await _pause(1.4)
	var p: Player = current_scene.get_node("Player")
	var shadow: ShadowInstance = p.shadows.add_shadow(_shadow_data)
	p.shadow_summoner.summon(shadow.instance_id)
	await _pause(0.4)
	# FOLLOW: the shadow fights only what it is ordered to, so which kill is
	# whose is decided by the harness rather than by who got there first.
	p.shadow_commander.set_mode(BasicMeleeShadow.CommandMode.FOLLOW)
	await _pause(0.3)
	_record(current_scene.scene_file_path == HUB and p.shadow_summoner.has_active_shadow(),
		"0) a new game reaches the hub with a shadow out")

	for cycle in range(1, CYCLES + 1):
		await _cycle(cycle)

	await _phase_new_game()
	print("[SUMMARY] passed=%d failed=%d" % [_pass, _fail])
	await _pause(0.3)
	quit()


# --- one cycle: hub -> gate -> dungeon -> two kills -> hub ----------------------------------

func _cycle(n: int) -> void:
	var p: Player = current_scene.get_node("Player")
	var gate: DungeonGate = current_scene.get_node("DungeonGate")
	var prompt: InteractionPrompt = current_scene.get_node("InteractionPrompt")
	p.global_position = gate.global_position
	await _pause(0.4)
	_record(prompt.is_showing() and prompt.get_text() == gate.prompt_text,
		"C%d.1) standing in the gate prompts '%s'" % [n, prompt.get_text()])
	gate.activate()
	await _pause(1.6)

	var dungeon: DungeonController = current_scene as DungeonController
	p = dungeon.get_player()
	p.hurtbox.set_invulnerable(true)
	var dungeon_prompt: InteractionPrompt = current_scene.get_node("InteractionPrompt")
	var node: BasicMeleeShadow = p.shadow_summoner.get_active_node()
	_record(current_scene.scene_file_path == DUNGEON and p == current_scene.get_node("Player"),
		"C%d.2) the gate leads into the dungeon, whose player is its own" % n)
	_record(get_nodes_in_group(Player.GROUP).size() == 1
			and get_nodes_in_group(BasicMeleeShadow.GROUP).size() == 1 and node != null,
		"C%d.3) one player and one shadow — it re-summoned itself, once" % n)
	_record(_fresh_dungeon(dungeon), "C%d.4) a fresh dungeon: every enemy up, every room shut" % n)
	_record(not dungeon_prompt.is_showing(), "C%d.5) no prompt carried over from the hub" % n)
	_check_listeners(n, p)

	p.global_position = ROOM1_ANCHOR
	await _pause(0.8)
	var room: RoomController = dungeon.get_rooms()[0]
	var first: RoomCombatant = room.get_enemies()[0]
	var second: RoomCombatant = room.get_enemies()[1]
	var clears: Array[int] = []
	room.room_cleared.connect(func(_r: RoomController) -> void: clears.append(1))

	# The shadow that crossed the scene change finishes the first: 70 / 30.
	var reward: int = first.get_xp_reward()
	var shadow_cut: int = int(round(reward * PlayerProgression.SHADOW_KILL_SHARE))
	var player_before: int = p.progression.get_total_xp()
	var shadow_before: int = _shadow_total_xp(node.instance)
	await _shadow_finishes(p, node, first)
	var player_gain: int = p.progression.get_total_xp() - player_before
	var shadow_gain: int = _shadow_total_xp(node.instance) - shadow_before
	_record(first.get_killer() == node and shadow_gain == shadow_cut
			and player_gain == reward - shadow_cut,
		"C%d.6) the re-summoned shadow's kill splits %d XP: %d shadow, %d player (got %d / %d)" % [
			n, reward, shadow_cut, reward - shadow_cut, shadow_gain, player_gain])
	_expected_shadow_xp += shadow_gain
	_expected_player_xp += player_gain

	# The same death announced again, with the second enemy still up.
	first.enemy_died.emit(first)
	await _pause(0.2)
	_record(not room.is_cleared() and not second.has_died() and clears.is_empty()
			and p.progression.get_total_xp() == player_before + player_gain,
		"C%d.7) a repeated death opens no room and pays nothing" % n)

	# The player finishes the second: all of it.
	var reward_2: int = second.get_xp_reward()
	player_before = p.progression.get_total_xp()
	shadow_before = _shadow_total_xp(node.instance)
	await _kill(p, second)
	await _pause(0.4)
	player_gain = p.progression.get_total_xp() - player_before
	_record(second.get_killer() == p and player_gain == reward_2
			and _shadow_total_xp(node.instance) == shadow_before,
		"C%d.8) the player's own kill pays it all %d XP and the shadow nothing (got %d)" % [
			n, reward_2, player_gain])
	_expected_player_xp += player_gain
	_record(room.is_cleared() and clears.size() == 1,
		"C%d.9) the room clears once, when its last enemy falls (%d)" % [n, clears.size()])

	SceneTransition.find_in(self).transition_to_scene(HUB)
	await _pause(1.6)
	await _check_hub(n)


# --- after each cycle, back in the hub ----------------------------------------------------------

func _check_hub(n: int) -> void:
	var p: Player = current_scene.get_node("Player")
	await _pause(0.3)
	_record(get_nodes_in_group(Player.GROUP).size() == 1
			and get_nodes_in_group(BasicMeleeShadow.GROUP).size() == 1,
		"C%d.10) back in the hub: one player, one shadow" % n)
	_record(p.progression.get_total_xp() == _expected_player_xp
			and _shadow_total_xp(_state.shadows[0]) == _expected_shadow_xp,
		"C%d.11) the session holds exactly what was paid: player %d XP, shadow %d XP" % [
			n, _expected_player_xp, _expected_shadow_xp])
	_record(_state.shadows.size() == 1 and p.shadows.get_count() == 1,
		"C%d.12) and one shadow in the collection, not one per cycle" % n)
	var nodes: int = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var orphans: int = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	if _hub_nodes < 0:
		_hub_nodes = nodes
		_hub_orphans = orphans
		_record(orphans == 0, "C%d.13) no orphan nodes after the first cycle (%d)" % [n, orphans])
	else:
		_record(nodes == _hub_nodes and orphans == _hub_orphans,
			"C%d.13) the hub holds the same %d nodes as after cycle 1, and %d orphans (now %d / %d)" % [
				n, _hub_nodes, _hub_orphans, nodes, orphans])


func _check_listeners(n: int, p: Player) -> void:
	var now: Dictionary = {
		"tree": node_added.get_connections().size(),
		"xp": p.progression.xp_changed.get_connections().size(),
		"level": p.progression.level_changed.get_connections().size(),
		"summoned": p.shadow_summoner.shadow_summoned.get_connections().size(),
		"died": p.health_component.died.get_connections().size(),
		"health": p.health_component.health_changed.get_connections().size(),
	}
	if _listeners.is_empty():
		_listeners = now
		_record(true, "C%d.L) listeners recorded: %s" % [n, now])
		return
	_record(now == _listeners, "C%d.L) the same listeners as on cycle 1: %s" % [n, now])


# --- the end: back to the menu, and a new game ----------------------------------------------------

func _phase_new_game() -> void:
	var old: PlayerProgressionData = _state.progression
	change_scene_to_file(BOOT)
	await _pause(0.6)
	(current_scene.get_node("MainMenu") as MainMenu).press_play()
	await _pause(1.4)
	var p: Player = current_scene.get_node("Player")
	_record(p.progression.current_level == 1 and p.progression.get_total_xp() == 0
			and p.shadows.is_empty() and not p.shadow_summoner.has_active_shadow(),
		"N1) a new game after three runs starts at level 1, 0 XP, no shadows, none out")
	_record(not is_same(_state.progression, old) and _state.next_shadow_index == 1,
		"N2) on a new character, numbering shadows from the start")
	_record(get_nodes_in_group(Player.GROUP).size() == 1
			and get_nodes_in_group(BasicMeleeShadow.GROUP).is_empty(),
		"N3) with one player and nothing left over from the last session")


# --- helpers ---------------------------------------------------------------------------------------

func _fresh_dungeon(dungeon: DungeonController) -> bool:
	for room in dungeon.get_rooms():
		if room.is_cleared():
			return false
		for enemy in room.get_enemies():
			if enemy.has_died():
				return false
	return dungeon.get_state() == DungeonController.DungeonState.NOT_STARTED \
		and dungeon.get_run_stats().get_total_kills() == 0


func _shadow_total_xp(shadow: ShadowInstance) -> int:
	var total: int = shadow.current_xp
	for level in range(1, shadow.level):
		total += shadow.shadow_data.xp_required_for_level(level)
	return total


## The shadow opens the enemy up, so progression hears about it through the
## shadow's own hitbox, then lands the last blow.
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


func _pause(t: float) -> void:
	await create_timer(t).timeout


func _record(passed: bool, description: String) -> void:
	if passed:
		_pass += 1
		print("[PASS] " + description)
	else:
		_fail += 1
		print("[FAIL] " + description)
