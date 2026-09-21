extends Node3D

## M8.3 — what the player can order the shadow to do, and what the shadow does
## about it: the two command modes, the aimed attack order, the tactical recall,
## the leash, stuck recovery and the Active Shadow HUD.
## Persistence across real scene changes lives in command_run.gd.

const DUNGEON: PackedScene = preload("res://scenes/dungeons/dungeon_test.tscn")
var SHADOW: ShadowData = preload("res://resources/shadows/basic_melee_shadow.tres")

const ROOM1_TRIGGER: Vector3 = Vector3(0, 0.1, -13)
const ROOM2_TRIGGER: Vector3 = Vector3(0, 0.1, -33)
const ROOM3_TRIGGER: Vector3 = Vector3(0, 0.1, -53)
## The shadow hurtbox layer, as the scenes set it.
const L_SHADOW_HURTBOX: int = 256

var _pass: int = 0
var _fail: int = 0

var _dungeon: DungeonController = null
var _player: Player = null
var _collection: PlayerShadowCollection = null
var _summoner: PlayerShadowSummoner = null
var _commander: PlayerShadowCommander = null
var _menu: ShadowCollectionMenu = null
var _stats_menu: PlayerStatsMenu = null
var _hud: ActiveShadowHUD = null
var _state: Node = null
var _shadow: ShadowInstance = null


func _ready() -> void:
	_run()


func _run() -> void:
	await _wait(0.2)
	_reset_session()
	_input_tests()
	await _setup()
	await _follow_mode_tests()
	await _aggressive_mode_tests()
	await _manual_command_tests()
	await _recall_tests()
	await _leash_tests()
	await _stuck_tests()
	await _hud_tests()
	await _menu_safety_tests()
	await _boss_tests()
	print("[SUMMARY] passed=%d failed=%d" % [_pass, _fail])
	get_tree().quit()


func _wait(t: float) -> void:
	await get_tree().create_timer(t).timeout


## A live shadow to give orders to. Shielded by default: these tests are about
## what it is TOLD, and a shadow that dies mid-block would only test survival.
## The blocks that are about damage unshield it where they need to.
func _live_shadow(shielded: bool = true) -> BasicMeleeShadow:
	var node: BasicMeleeShadow = _summoner.get_active_node()
	if node == null or not is_instance_valid(node) or node.is_dead():
		node = _summoner.summon(_shadow.instance_id)
		await _wait(0.4)
	node.hurtbox.set_invulnerable(shielded)
	return node


func _record(passed: bool, description: String) -> void:
	if passed:
		_pass += 1
		print("[PASS] " + description)
	else:
		_fail += 1
		print("[FAIL] " + description)


func _reset_session() -> void:
	_state = get_tree().root.get_node_or_null("PlayerRuntimeState")
	if _state != null:
		_state.reset_runtime_state()


func _setup() -> void:
	_dungeon = DUNGEON.instantiate() as DungeonController
	_dungeon.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(_dungeon)
	await _wait(0.8)
	_player = _dungeon.get_node("Player")
	_collection = _player.shadows
	_summoner = _player.shadow_summoner
	_commander = _player.shadow_commander
	_menu = _dungeon.get_node("ShadowCollectionMenu")
	_stats_menu = _dungeon.get_node("PlayerStatsMenu")
	_hud = _dungeon.get_node("ActiveShadowHUD")
	_player.hurtbox.set_invulnerable(true)
	_shadow = _collection.add_shadow(SHADOW)


# --- the bindings themselves --------------------------------------------------------

func _input_tests() -> void:
	for action in [PlayerShadowCommander.ACTION_RECALL,
			PlayerShadowCommander.ACTION_MODE_TOGGLE,
			PlayerShadowCommander.ACTION_ATTACK_COMMAND]:
		_record(InputMap.has_action(action), "1) the InputMap declares %s" % action)
	# The three new actions must not have been bolted onto a key that already
	# does something.
	var taken: Dictionary = {}
	var clash: String = ""
	for action in InputMap.get_actions():
		if String(action).begins_with("ui_"):
			continue
		for event in InputMap.action_get_events(action):
			var signature: String = event.as_text()
			if taken.has(signature):
				clash = "%s and %s both use %s" % [taken[signature], action, signature]
			taken[signature] = action
	_record(clash == "", "2) no two gameplay actions share a binding%s" % (
		"" if clash == "" else ": " + clash))


# --- FOLLOW ------------------------------------------------------------------------------

func _follow_mode_tests() -> void:
	_player.global_position = ROOM1_TRIGGER
	await _wait(0.8)
	var node: BasicMeleeShadow = await _live_shadow()
	_record(node.command_mode == BasicMeleeShadow.CommandMode.AGGRESSIVE,
		"3) a freshly summoned shadow starts AGGRESSIVE")

	_commander.set_mode(BasicMeleeShadow.CommandMode.FOLLOW)
	await _wait(0.2)
	_record(node.command_mode == BasicMeleeShadow.CommandMode.FOLLOW,
		"4) it can be put into FOLLOW")

	# Stand it right next to an enemy and leave it there.
	var room: RoomController = _dungeon.get_rooms()[0]
	var enemy: RoomCombatant = room.get_enemies()[0]
	var enemy_health: HealthComponent = enemy.get_node("HealthComponent")
	_player.global_position = enemy.global_position + Vector3(0, 0, 3.0)
	node.global_position = enemy.global_position + Vector3(0, 0, 2.0)
	var before: float = enemy_health.current_health
	await _wait(2.5)
	_record(node.get_target() == null,
		"5) in FOLLOW it takes no target of its own next to an enemy")
	_record(is_equal_approx(enemy_health.current_health, before),
		"6) and does not attack it (%.0f HP, unchanged)" % enemy_health.current_health)
	_record(node.get_state() == BasicMeleeShadow.State.FOLLOW,
		"7) it just keeps following")

	# It still takes an order.
	_record(node.set_manual_target(enemy), "8) a manual order is still accepted in FOLLOW")
	await _wait(3.0)
	_record(enemy_health.current_health < before,
		"9) and it attacks what it was told to (%.0f -> %.0f)" % [
			before, enemy_health.current_health])

	# Order carried out: back to the player, and no hunting for a replacement.
	var second: RoomCombatant = room.get_enemies()[1]
	second.global_position = enemy.global_position + Vector3(2.0, 0, 0)
	await _kill_directly(enemy)
	await _wait(1.5)
	_record(node.get_manual_target() == null, "10) the order clears when the target dies")
	_record(node.get_target() == null,
		"11) and in FOLLOW it does not pick up the next enemy standing there")
	_record(node.get_state() in [BasicMeleeShadow.State.FOLLOW,
			BasicMeleeShadow.State.RETURN_TO_PLAYER],
		"12) it goes back to the player (state %d)" % node.get_state())


# --- AGGRESSIVE ---------------------------------------------------------------------------

func _aggressive_mode_tests() -> void:
	var node: BasicMeleeShadow = await _live_shadow()
	var room: RoomController = _dungeon.get_rooms()[0]
	var second: RoomCombatant = room.get_enemies()[1]
	var second_health: HealthComponent = second.get_node("HealthComponent")

	_commander.toggle_mode()
	await _wait(0.2)
	_record(node.command_mode == BasicMeleeShadow.CommandMode.AGGRESSIVE,
		"13) the toggle puts it back into AGGRESSIVE")

	_player.global_position = second.global_position + Vector3(0, 0, 3.5)
	node.global_position = second.global_position + Vector3(0, 0, 2.5)
	await _wait(1.0)
	_record(node.get_target() == second,
		"14) with an enemy in range it acquires one by itself")
	var before: float = second_health.current_health
	await _wait(3.0)
	_record(second_health.current_health < before,
		"15) and fights it (%.0f -> %.0f)" % [before, second_health.current_health])

	# Toggling back to FOLLOW mid-hunt drops the target and sends it home.
	_commander.toggle_mode()
	await _wait(0.4)
	_record(node.get_target() == null,
		"16) switching to FOLLOW cancels the automatic target")
	_record(node.get_state() in [BasicMeleeShadow.State.RETURN_TO_PLAYER,
			BasicMeleeShadow.State.FOLLOW],
		"17) and it heads back (state %d)" % node.get_state())
	_commander.toggle_mode()
	await _wait(0.3)

	# Kill what it is fighting and it moves to the next one on its own.
	var third: RoomCombatant = null
	for candidate in room.get_enemies():
		if not candidate.has_died() and candidate != second:
			third = candidate
			break
	if third != null:
		third.global_position = second.global_position + Vector3(2.5, 0, 0)
	await _wait(0.5)
	await _kill_directly(second)
	await _wait(1.5)
	if third != null:
		_record(node.get_target() == third,
			"18) when its target dies it takes the next enemy in range")
	else:
		_record(node.get_target() == null, "18) no second enemy left, so it takes none")

	# Nothing left to fight: back to the player.
	if third != null:
		await _kill_directly(third)
	await _wait(2.0)
	_record(node.get_target() == null and node.get_state() in [
			BasicMeleeShadow.State.FOLLOW, BasicMeleeShadow.State.RETURN_TO_PLAYER],
		"19) with the room clear it returns to the player")


# --- the aimed order -----------------------------------------------------------------------

func _manual_command_tests() -> void:
	_player.global_position = ROOM2_TRIGGER
	await _wait(0.9)
	var node: BasicMeleeShadow = await _live_shadow()
	var room: RoomController = _dungeon.get_rooms()[1]
	var enemies: Array[RoomCombatant] = room.get_enemies()
	var wanted: RoomCombatant = enemies[1] if enemies.size() > 1 else enemies[0]

	# Aiming at nothing must change nothing.
	_player.global_position = ROOM2_TRIGGER
	_aim_away()
	await _wait(0.3)
	_record(_commander.issue_attack_command() == null,
		"20) an order aimed at nothing finds no target")
	_record(node.get_manual_target() == null, "21) and assigns none")

	# Aim at a real enemy through the real raycast.
	_player.global_position = wanted.global_position + Vector3(0, 0, 4.0)
	node.global_position = _player.global_position + Vector3(1.0, 0, 1.0)
	await _wait(0.3)
	# Enemies move. Aiming and ordering happen in the same beat, or the ray is
	# pointed at where the target used to be.
	_aim_at(wanted)
	var found: RoomCombatant = _commander.issue_attack_command()
	_record(found == wanted, "22) aiming at an enemy and commanding picks it out by raycast%s" %
		("" if found == wanted else " (hit %s instead)" % [_ray_hit()]))
	_record(node.get_manual_target() == wanted, "23) the shadow takes it as its order")
	_record(node.get_auto_target() == null,
		"24) and drops whatever it had chosen for itself")

	var marker: ShadowTargetMarker = _commander.get_marker()
	_record(marker != null and marker.is_showing() and marker.get_target() == wanted,
		"25) the target marker appears on it")
	await _wait(0.3)
	var bar: EnemyHealthBar3D = wanted.get_node_or_null("EnemyHealthBar3D")
	if bar != null:
		_record(marker.global_position.y - wanted.global_position.y
				> bar.health_bar_height_offset,
			"26) sitting above the health bar, not across it (%.2f vs %.2f)" % [
				marker.global_position.y - wanted.global_position.y,
				bar.health_bar_height_offset])
	else:
		_record(true, "26) the target carries no world-space bar to clash with")

	var health: HealthComponent = wanted.get_node("HealthComponent")
	var before: float = health.current_health
	await _wait(3.5)
	_record(health.current_health < before,
		"27) the shadow chases and attacks the ordered target (%.0f -> %.0f)" % [
			before, health.current_health])

	await _kill_directly(wanted)
	await _wait(0.8)
	_record(node.get_manual_target() == null, "28) the order clears when the target dies")
	_record(not marker.is_showing(), "29) and the marker goes with it")
	_record(node.command_mode == BasicMeleeShadow.CommandMode.AGGRESSIVE,
		"30) the mode is unchanged by any of it")

	# A real middle-click, not just the method: the binding has to work too.
	var next: RoomCombatant = null
	for candidate in room.get_enemies():
		if not candidate.has_died():
			next = candidate
			break
	if next != null:
		_player.global_position = next.global_position + Vector3(0, 0, 4.0)
		await _wait(0.3)
		_aim_at(next)
		await _press(PlayerShadowCommander.ACTION_ATTACK_COMMAND)
		await _wait(0.2)
		_record(node.get_manual_target() == next,
			"31) and a real press of the bound input gives the same order")
	else:
		_record(false, "31) no enemy left to test the real input against")


# --- coming back ----------------------------------------------------------------------------

func _recall_tests() -> void:
	var node: BasicMeleeShadow = await _live_shadow()
	var room: RoomController = _dungeon.get_rooms()[1]
	var enemy: RoomCombatant = null
	for candidate in room.get_enemies():
		if not candidate.has_died():
			enemy = candidate
			break
	if enemy == null:
		_record(false, "32) no enemy left to recall away from")
		return

	# The player stands on the room's own anchor rather than at an offset from a
	# roaming enemy: a spot off the navmesh is one the shadow correctly cannot
	# reach, and that would be testing the level, not the recall.
	_player.global_position = ROOM2_TRIGGER
	enemy.global_position = ROOM2_TRIGGER + Vector3(0, 0, -5.0)
	await _wait(0.3)
	node.global_position = enemy.global_position + Vector3(0, 0, 1.4)
	node.set_manual_target(enemy)
	await _wait(1.2)
	var count_before: int = _collection.get_count()
	var id_before: StringName = _summoner.get_active_instance_id()

	await _press(PlayerShadowCommander.ACTION_RECALL)
	await _wait(0.1)
	_record(node.get_manual_target() == null, "32) the recall clears the manual target")
	_record(node.get_auto_target() == null, "33) and the automatic one")
	# It may still be finishing an active window; either way the hitbox must be
	# down by the time it is walking.
	await _wait(0.5)
	_record(not node.attack_hitbox.is_active(),
		"34) no hitbox is left live while it comes back")
	_record(node.get_state() in [BasicMeleeShadow.State.RETURN_TO_PLAYER,
			BasicMeleeShadow.State.FOLLOW],
		"35) it is on its way back (state %d)" % node.get_state())

	_record(_summoner.has_active_shadow() and _summoner.get_active_instance_id() == id_before,
		"36) the recall is tactical: the shadow is still summoned")
	_record(_collection.get_count() == count_before,
		"37) and the collection is untouched")
	_record(_commander.get_marker() == null or not _commander.get_marker().is_showing(),
		"38) the marker is cleared with the order")

	await _wait(3.0)
	var distance: float = _player.global_position.distance_to(node.global_position)
	_record(distance <= node.follow_distance + node.arrival_tolerance + 0.5,
		"39) it settles beside the player at %.1f m (state %d)" % [distance, node.get_state()])

	# Oscillation, not braking distance, and not the recall hold expiring: in
	# FOLLOW it has nothing to run off to, so what is left is the standing
	# behaviour this is about.
	_commander.set_mode(BasicMeleeShadow.CommandMode.FOLLOW)
	for _i in 240:
		await get_tree().physics_frame
		if Vector2(node.velocity.x, node.velocity.z).length() < 0.05:
			break
	var anchor: Vector3 = node.global_position
	var drift: float = 0.0
	for _i in 120:
		await get_tree().physics_frame
		drift = maxf(drift, anchor.distance_to(node.global_position))
	_record(drift < 0.25,
		"40) and once stopped it stays put instead of oscillating (%.3f m of drift)" % drift)
	_commander.set_mode(BasicMeleeShadow.CommandMode.AGGRESSIVE)

	# The hold is a pause, not a mode change: AGGRESSIVE comes back on its own.
	var live: RoomCombatant = null
	for candidate in room.get_enemies():
		if not candidate.has_died():
			live = candidate
			break
	if live != null:
		live.global_position = _player.global_position + Vector3(0, 0, -4.0)
		node.recall_to_player()
		await _wait(0.4)
		_record(node.get_target() == null and node.command_mode
				== BasicMeleeShadow.CommandMode.AGGRESSIVE,
			"41) right after a recall it holds off, still in AGGRESSIVE")
		await _wait(node.recall_hold_duration + 1.0)
		_record(node.get_target() == live,
			"42) and once the hold expires it hunts again on its own")
		# An order outranks a hold that is still running.
		node.recall_to_player()
		await _wait(0.2)
		_record(node.set_manual_target(live) and node.get_manual_target() == live,
			"43) an order given during a hold overrides it")
		node.clear_manual_target()
	else:
		_record(false, "41-43) no live enemy left to test the recall hold against")

	# Recall with nothing out is not an error.
	_summoner.recall()
	await _wait(0.4)
	_commander.recall_to_player()
	_record(true, "44) a recall with no shadow out does nothing and raises nothing")


# --- the leash -----------------------------------------------------------------------------

func _leash_tests() -> void:
	var node: BasicMeleeShadow = await _live_shadow()
	_player.global_position = ROOM3_TRIGGER
	await _wait(0.9)
	var boss: RoomCombatant = _dungeon.get_rooms()[2].get_enemies()[0]

	# Far past the leash: the order is refused outright rather than started and
	# abandoned.
	_player.global_position = boss.global_position + Vector3(0, 0, 30.0)
	node.global_position = _player.global_position + Vector3(1.0, 0, 1.0)
	await _wait(0.4)
	_record(not node.is_valid_target(boss),
		"45) a target past the leash is not a valid one")
	_record(not node.set_manual_target(boss),
		"46) so an order to attack it is refused")
	_record(node.get_manual_target() == null, "47) and nothing is assigned")

	# Ordered inside the leash, then the player walks away and takes it out.
	_player.global_position = boss.global_position + Vector3(0, 0, 8.0)
	node.global_position = _player.global_position + Vector3(1.0, 0, 1.0)
	await _wait(0.4)
	_record(node.set_manual_target(boss), "48) inside the leash the same order is accepted")
	_player.global_position = ROOM1_TRIGGER
	await _wait(1.0)
	_record(node.get_manual_target() == null,
		"49) walking away past the leash drops the order")
	_record(node.get_target() == null, "50) leaving it nothing to chase")
	await _wait(2.0)
	_record(node.get_state() in [BasicMeleeShadow.State.RETURN_TO_PLAYER,
			BasicMeleeShadow.State.FOLLOW],
		"51) and it comes back to the player (state %d)" % node.get_state())


# --- stuck ------------------------------------------------------------------------------------

func _stuck_tests() -> void:
	var node: BasicMeleeShadow = await _live_shadow()
	_player.global_position = ROOM2_TRIGGER
	await _wait(0.8)
	node.recovery_count = 0

	# Pinned in place, far from the player: it should be walking and is not.
	# Polled rather than counted in frames — what matters is that the cheap
	# answer is tried BEFORE anything is moved, not exactly when.
	var pinned: Vector3 = ROOM2_TRIGGER + Vector3(0, 0, 16.0)
	node.global_position = pinned
	var repath_at: int = -1
	var recovery_at: int = -1
	var budget: int = int(node.stuck_check_duration * 60.0 * 4.0)
	for frame in budget:
		await get_tree().physics_frame
		node.global_position = pinned
		if repath_at < 0 and node.has_tried_repath():
			repath_at = frame
		if recovery_at < 0 and node.recovery_count > 0:
			recovery_at = frame
			break
	_record(repath_at >= 0, "52) no progress makes it repath (frame %d)" % repath_at)
	_record(recovery_at >= 0 and repath_at >= 0 and repath_at < recovery_at,
		"53) and the repath comes first, before it is moved (%d then %d)" % [
			repath_at, recovery_at])
	_record(node.recovery_count == 1,
		"54) still stuck and %.0f m out, it is repositioned (%d)" % [
			pinned.distance_to(_player.global_position), node.recovery_count])

	# And only once: the cooldown is what stops recovery becoming locomotion.
	for _i in int(node.recovery_cooldown * 60.0 * 0.6):
		await get_tree().physics_frame
		node.global_position = pinned
	_record(node.recovery_count == 1,
		"55) the cooldown holds it to that one, with no teleport spam (%d)" %
			node.recovery_count)

	# Close to the player it is left alone, whatever it is doing.
	node.recovery_count = 0
	var near: Vector3 = _player.global_position + Vector3(0, 0, 3.0)
	node.global_position = near
	var long_hold: int = int(node.stuck_check_duration * 60.0 * 4.0)
	for _i in long_hold:
		await get_tree().physics_frame
		node.global_position = near
	_record(node.recovery_count == 0,
		"56) a shadow stuck within sight of the player is never teleported (%d)" %
			node.recovery_count)

	# Standing still mid-melee is fighting, not being stuck.
	var room: RoomController = _dungeon.get_rooms()[1]
	var enemy: RoomCombatant = null
	for candidate in room.get_enemies():
		if not candidate.has_died():
			enemy = candidate
			break
	if enemy == null:
		_record(true, "57) no enemy left to hold a melee against")
		return
	# The enemy is pinned first and everything placed around where it will stay:
	# one that drifts out past the leash would be dropped, and this is about a
	# shadow that is fighting, not one that has lost its target.
	var enemy_held: Vector3 = enemy.global_position
	_player.global_position = enemy_held + Vector3(0, 0, 12.0)
	node.global_position = enemy_held + Vector3(0, 0, 1.2)
	# And it survives the hold: left mortal, the shadow simply kills it and the
	# target is gone for the right reason, which is not what this is measuring.
	var enemy_hurtbox: Hurtbox = enemy.get_node("Hurtbox")
	enemy_hurtbox.set_invulnerable(true)
	await _wait(0.3)
	node.recovery_count = 0
	var ordered: bool = node.set_manual_target(enemy)
	var held: Vector3 = node.global_position
	var kept_target: bool = true
	for _i in long_hold:
		await get_tree().physics_frame
		node.global_position = held
		enemy.global_position = enemy_held
		kept_target = kept_target and node.get_target() != null
	enemy_hurtbox.set_invulnerable(false)
	_record(ordered and kept_target and node.recovery_count == 0,
		"57) toe to toe with an enemy it is fighting, not stuck (%d recoveries, target held %s)" % [
			node.recovery_count, kept_target])
	node.clear_manual_target()


# --- the panel -----------------------------------------------------------------------------

func _hud_tests() -> void:
	_summoner.recall()
	await _wait(0.4)
	_record(not _hud.is_showing(), "58) with nothing summoned the HUD is hidden")

	var node: BasicMeleeShadow = await _live_shadow()
	_record(_hud.is_showing(), "59) summoning brings it up")
	_record(_hud.get_name_text() == _shadow.get_display_name().to_upper(),
		"60) with the right name: '%s'" % _hud.get_name_text())
	_record(_hud.get_level_text() == "Lv. %d" % _shadow.level,
		"61) and the right level: '%s'" % _hud.get_level_text())
	_record(_hud.get_health_text() == "%d / %d" % [
			roundi(node.health_component.current_health),
			roundi(node.health_component.max_health)],
		"62) and its health: '%s'" % _hud.get_health_text())

	var before: String = _hud.get_health_text()
	node.hurtbox.set_invulnerable(false)
	node.hurtbox.receive_hit(15.0, _player)
	await get_tree().process_frame
	_record(_hud.get_health_text() != before,
		"63) damage updates the bar at once, with no polling: '%s'" % _hud.get_health_text())
	_record(_hud.get_health_ratio() < 1.0,
		"64) and the bar itself follows (%.2f)" % _hud.get_health_ratio())

	_record(_hud.get_mode_text().contains("AGGRESSIVE"),
		"65) the mode is shown: '%s'" % _hud.get_mode_text())
	_commander.toggle_mode()
	await _wait(0.2)
	_record(_hud.get_mode_text().contains("FOLLOW"),
		"66) and the toggle updates it: '%s'" % _hud.get_mode_text())
	_commander.toggle_mode()
	await _wait(0.2)

	var hints: String = _hud.get_hints_text()
	_record(hints.contains("[Q]") and hints.contains("[T]") and hints.contains("[MMB]"),
		"67) the command hints name the real keys: %s" % hints.replace("\n", " / "))

	# A level earned while it is out has to reach both the panel and the entity.
	var max_before: float = node.health_component.max_health
	_collection.award_xp(_shadow.instance_id, 500)
	await _wait(0.3)
	_record(_hud.get_level_text() == "Lv. %d" % _shadow.level,
		"68) a level-up mid-fight updates the panel: '%s'" % _hud.get_level_text())
	_record(node.health_component.max_health > max_before,
		"69) and the health it bought reaches the shadow in the world (%.0f -> %.0f)" % [
			max_before, node.health_component.max_health])

	node.health_component.receive_damage(100000.0)
	await _wait(0.3)
	_record(not _hud.is_showing(), "70) the HUD goes when the shadow dies")


# --- menus -----------------------------------------------------------------------------------

func _menu_safety_tests() -> void:
	var node: BasicMeleeShadow = await _live_shadow()
	var mode_before: BasicMeleeShadow.CommandMode = node.command_mode

	_stats_menu.open()
	await _wait(0.2)
	_record(get_tree().paused, "71) opening the character sheet pauses the game")
	await _press(PlayerShadowCommander.ACTION_MODE_TOGGLE)
	await _wait(0.2)
	_record(node.command_mode == mode_before,
		"72) and a press of the mode key behind it commands nothing")
	await _press(PlayerShadowCommander.ACTION_RECALL)
	await _wait(0.2)
	_record(_summoner.has_active_shadow(), "73) nor does the recall key")
	_stats_menu.close()
	await _wait(0.3)
	_record(not get_tree().paused, "74) closing it resumes")

	await _press(PlayerShadowCommander.ACTION_MODE_TOGGLE)
	await _wait(0.2)
	_record(node.command_mode != mode_before,
		"75) and the same key works again once the menu is gone")
	_commander.set_mode(BasicMeleeShadow.CommandMode.AGGRESSIVE)

	# The menu's Richiama still despawns — it is not the quick recall.
	_menu.open()
	await _wait(0.2)
	_menu.select_row(0)
	await _wait(0.1)
	_record(_menu.get_summon_button_text() == "[Richiama]",
		"76) the collection menu still offers '%s' for the active shadow" %
			_menu.get_summon_button_text())
	_menu.press_summon()
	await _wait(0.4)
	_record(not _summoner.has_active_shadow(),
		"77) and it DESPAWNS, unlike the quick recall")
	_record(_collection.has_shadow(_shadow.instance_id),
		"78) while the shadow stays in the collection")
	_menu.close()
	await _wait(0.3)


# --- the boss ---------------------------------------------------------------------------------

func _boss_tests() -> void:
	_player.global_position = ROOM3_TRIGGER
	await _wait(1.2)
	var boss: RoomCombatant = _dungeon.get_rooms()[2].get_enemies()[0]
	var boss_health: HealthComponent = boss.get_node("HealthComponent")
	# Shielded like every other block: whether a given boss swing connects is up
	# to the fight, and 83/83b below prove the damage path without leaving it to
	# chance.
	var node: BasicMeleeShadow = await _live_shadow()

	# Deeper into the room than the boss, not back towards the door: the door
	# shuts behind the player, and an order through a closed door is correctly
	# refused — that would be testing the wall, not the command.
	_player.global_position = boss.global_position + Vector3(0, 0, -4.0)
	node.global_position = boss.global_position + Vector3(0, 0, -2.5)
	await _wait(0.3)
	# The boss is chasing the player, so aiming and ordering have to happen in
	# the same beat: a gap between them and the ray is pointed where it WAS.
	_aim_at(boss)
	var found: RoomCombatant = _commander.issue_attack_command()
	_record(found == boss, "79) the boss can be picked out by the aimed order%s" %
		("" if found == boss else " (hit %s instead)" % [_ray_hit()]))
	var marker: ShadowTargetMarker = _commander.get_marker()
	_record(marker != null and marker.is_showing() and marker.get_target() == boss,
		"80) and the marker works on it too")
	_record(_dungeon.get_node("BossHealthBar").visible,
		"81) without disturbing the boss health UI")

	var boss_before: float = boss_health.current_health
	await _wait(5.0)
	_record(boss_health.current_health < boss_before,
		"82) the shadow damages the boss (%.0f -> %.0f, %.1f m away)" % [
			boss_before, boss_health.current_health,
			node.global_position.distance_to(boss.global_position)])

	# Whether a given swing connects is up to the fight; that every boss hitbox
	# can reach the shadow at all is not, so that is what is asserted, and the
	# damage itself is driven through the real hurtbox path.
	var reachable: bool = true
	for hitbox in _boss_hitboxes(boss):
		reachable = reachable and (hitbox.collision_mask & L_SHADOW_HURTBOX) != 0
	_record(reachable, "83) every boss hitbox can reach the shadow's hurtbox")
	var shadow_before: float = node.health_component.current_health
	node.hurtbox.set_invulnerable(false)
	node.hurtbox.receive_hit(20.0, boss)
	await get_tree().process_frame
	_record(node.health_component.current_health < shadow_before
			and node.health_component.last_damage_source == boss,
		"83b) and a boss hit wounds it (%.0f -> %.0f)" % [
			shadow_before, node.health_component.current_health])
	_record(_hud.is_showing() and _hud.get_health_text() == "%d / %d" % [
			roundi(node.health_component.current_health),
			roundi(node.health_component.max_health)],
		"84) the HUD follows it through the boss fight: '%s'" % _hud.get_health_text())

	# The XP split is M8.2's rule and must survive all of this.
	var reward: int = boss.get_xp_reward()
	var expected_shadow: int = int(round(reward * PlayerProgression.SHADOW_KILL_SHARE))
	var shadow_xp_before: int = _shadow.current_xp
	var level_before: int = _shadow.level
	var player_before: int = _total_player_xp()
	# The player has to have touched it for M6.1 to subscribe at all.
	await _swing_at(boss)
	(boss.get_node("Hurtbox") as Hurtbox).receive_hit(1000000.0, node)
	await _wait(1.0)
	_record(boss.has_died() and boss.get_killer() == node,
		"85) the shadow can land the final blow on the boss")
	var gained: int = _shadow.current_xp - shadow_xp_before + _levels_worth(_shadow, level_before)
	_record(gained == expected_shadow,
		"86) taking %d of the boss's %d XP, exactly 70%% as in M8.2" % [gained, reward])
	_record(_total_player_xp() - player_before == reward - expected_shadow,
		"87) and the player the remaining %d" % (reward - expected_shadow))
	await _wait(1.5)
	_record(_dungeon.get_state() == DungeonController.DungeonState.COMPLETED,
		"88) the dungeon still completes on a kill the shadow finished")


# --- helpers ------------------------------------------------------------------------------------

## Points the camera at something, the way a player lining up a command would.
func _aim_at(target: Node3D) -> void:
	var to: Vector3 = target.global_position - _player.global_position
	to.y = 0.0
	if to.length_squared() < 0.0001:
		return
	to = to.normalized()
	_player.camera_rig.rotation.y = atan2(-to.x, -to.z)
	_player.camera_rig.pitch_pivot.rotation.x = 0.0


func _aim_away() -> void:
	_player.camera_rig.rotation.y = 0.0
	_player.camera_rig.pitch_pivot.rotation.x = -1.2


## What the aim ray actually hit, for a failure message that says something.
func _ray_hit() -> String:
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null:
		return "no camera"
	var from: Vector3 = _player.global_position + Vector3.UP * _commander.aim_origin_height
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		from, from - camera.global_basis.z * _commander.manual_command_range)
	query.collision_mask = _commander.command_ray_mask
	query.exclude = [_player.get_rid()]
	var hit: Dictionary = get_viewport().world_3d.direct_space_state.intersect_ray(query)
	return str(hit.get("collider", "nothing"))


## A real input event, so the binding is exercised and not just the method.
func _press(action: StringName) -> void:
	var event: InputEventAction = InputEventAction.new()
	event.action = action
	event.pressed = true
	get_viewport().push_input(event)
	await get_tree().process_frame


func _kill_directly(enemy: RoomCombatant) -> void:
	(enemy.get_node("HealthComponent") as HealthComponent).receive_damage(1000000.0, _player)
	await _wait(0.4)


func _swing_at(enemy: RoomCombatant) -> void:
	_player.global_position = enemy.global_position + Vector3(0, 0, 1.6)
	_player.camera_rig.rotation.y = 0.0
	_player._attack_state = Player.AttackState.IDLE
	_player._combo_index = 0
	_player.camera_rig.attack_light_pressed.emit()
	await _wait(0.45)


func _boss_hitboxes(boss: RoomCombatant) -> Array[Hitbox]:
	var found: Array[Hitbox] = []
	_gather_hitboxes(boss, found)
	return found


func _gather_hitboxes(node: Node, into: Array[Hitbox]) -> void:
	var hitbox: Hitbox = node as Hitbox
	if hitbox != null:
		into.append(hitbox)
	for child in node.get_children():
		_gather_hitboxes(child, into)


func _levels_worth(shadow: ShadowInstance, from_level: int) -> int:
	var total: int = 0
	for level in range(from_level, shadow.level):
		total += shadow.shadow_data.xp_required_for_level(level)
	return total


func _total_player_xp() -> int:
	var p: PlayerProgression = _player.progression
	var total: int = p.current_xp
	for level in range(1, p.current_level):
		total += p.xp_required_for_level(level)
	return total
