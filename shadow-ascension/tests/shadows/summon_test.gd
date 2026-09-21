extends Node3D

## M8.2 — the level and XP a shadow carries, summoning one into the world, what
## it does there, who it can and cannot hit, and how a kill's XP is split.
## Persistence across real scene changes lives in summon_run.gd.

const DUNGEON: PackedScene = preload("res://scenes/dungeons/dungeon_test.tscn")
var SHADOW: ShadowData = preload("res://resources/shadows/basic_melee_shadow.tres")

const ROOM1_TRIGGER: Vector3 = Vector3(0, 0.1, -13)
const ROOM2_TRIGGER: Vector3 = Vector3(0, 0.1, -33)

## Collision layer bits, as the scenes set them. Named here so a failure reads
## as "the shadow's hitbox can see the player" rather than as a number.
const L_ENEMY_HURTBOX: int = 16
const L_PLAYER_HURTBOX: int = 64
const L_SHADOW_BODY: int = 128
const L_SHADOW_HURTBOX: int = 256
const L_SHADOW_HITBOX: int = 512

var _pass: int = 0
var _fail: int = 0

var _dungeon: DungeonController = null
var _player: Player = null
var _collection: PlayerShadowCollection = null
var _summoner: PlayerShadowSummoner = null
var _menu: ShadowCollectionMenu = null
var _state: Node = null


func _ready() -> void:
	_run()


func _run() -> void:
	await _wait(0.2)
	_reset_session()
	_level_tests()
	await _setup()
	await _summon_tests()
	await _follow_tests()
	await _combat_tests()
	await _friendly_fire_tests()
	await _xp_split_tests()
	await _death_tests()
	await _menu_tests()
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
	_menu = _dungeon.get_node("ShadowCollectionMenu")
	_player.hurtbox.set_invulnerable(true)


# --- level and XP, before anything is in the world -------------------------------

func _level_tests() -> void:
	_record(SHADOW.summon_scene != null, "1) the shadow data names a summon scene")
	_record(SHADOW.xp_required_for_level(1) == 50 and SHADOW.xp_required_for_level(2) == 60
			and SHADOW.xp_required_for_level(3) == 72,
		"2) the curve is 50 / 60 / 72 (got %d / %d / %d)" % [
			SHADOW.xp_required_for_level(1), SHADOW.xp_required_for_level(2),
			SHADOW.xp_required_for_level(3)])

	var s: ShadowInstance = ShadowInstance.new(&"test_shadow", SHADOW)
	_record(s.level == 1 and s.current_xp == 0, "3) a new shadow starts at Lv.1, 0 XP")
	_record(is_equal_approx(s.get_max_health(), 80.0)
			and is_equal_approx(s.get_damage(), 12.0),
		"4) Lv.1 is 80 HP / 12 damage (%.0f / %.0f)" % [s.get_max_health(), s.get_damage()])

	# The brief's worked example: 70 XP onto a fresh shadow.
	var gained: int = s.add_xp(70)
	_record(gained == 1 and s.level == 2 and s.current_xp == 20
			and s.get_xp_to_next_level() == 60,
		"5) 70 XP at Lv.1 gives Lv.%d with %d/%d" % [
			s.level, s.current_xp, s.get_xp_to_next_level()])
	_record(is_equal_approx(s.get_max_health(), 88.0)
			and is_equal_approx(s.get_damage(), 14.0),
		"6) and Lv.2 is 88 HP / 14 damage (%.0f / %.0f)" % [
			s.get_max_health(), s.get_damage()])

	# One award can cover several levels; it is reported once, not per level.
	var multi: ShadowInstance = ShadowInstance.new(&"multi_shadow", SHADOW)
	var jumped: int = multi.add_xp(500)
	_record(jumped >= 3 and multi.level == 1 + jumped,
		"7) a 500 XP award reports %d levels at once, reaching Lv.%d" % [jumped, multi.level])
	_record(multi.add_xp(0) == 0 and multi.add_xp(-40) == 0,
		"8) zero and negative XP change nothing")
	_record(s.get_xp_ratio() > 0.0 and s.get_xp_ratio() < 1.0,
		"9) the ratio to the next level is %.2f" % s.get_xp_ratio())


# --- putting one in the world ------------------------------------------------------

func _summon_tests() -> void:
	var first: ShadowInstance = _collection.add_shadow(SHADOW)
	var second: ShadowInstance = _collection.add_shadow(SHADOW)
	_record(_collection.get_count() == 2, "10) two shadows in the collection to work with")
	_record(not _summoner.has_active_shadow(), "11) nothing is out to begin with")

	var node: BasicMeleeShadow = _summoner.summon(first.instance_id)
	await _wait(0.4)
	_record(node != null and is_instance_valid(node), "12) summoning produced an entity")
	if node == null:
		return
	_record(node.get_parent() == _player.get_parent(),
		"13) parented to the scene, not to the player (%s)" % node.get_parent().name)
	_record(node.instance == first, "14) it knows which shadow it is")
	_record(_summoner.is_active(first.instance_id)
			and _summoner.get_active_instance_id() == first.instance_id,
		"15) and the summoner reports it as the active one")
	_record(_state.active_shadow_instance_id == first.instance_id,
		"16) the session recorded the active id")
	_record(_player.global_position.distance_to(node.global_position) < 4.0,
		"17) it appeared beside the player (%.1f m)" %
			_player.global_position.distance_to(node.global_position))
	_record(is_equal_approx(node.health_component.max_health, 80.0)
			and is_equal_approx(node.health_component.current_health, 80.0),
		"18) at its level's full health (%.0f/%.0f)" % [
			node.health_component.current_health, node.health_component.max_health])

	# Max one at a time: the second summon takes the first back.
	var swapped: BasicMeleeShadow = _summoner.summon(second.instance_id)
	await _wait(0.4)
	_record(swapped != null and not is_instance_valid(node),
		"19) summoning a second one recalls the first")
	_record(_count_shadow_nodes() == 1,
		"20) exactly one shadow in the world (%d)" % _count_shadow_nodes())
	_record(_summoner.is_active(second.instance_id), "21) and the second is now active")

	_record(_summoner.recall(), "22) recall takes it back")
	await _wait(0.3)
	_record(_count_shadow_nodes() == 0 and not _summoner.has_active_shadow(),
		"23) leaving nothing in the world")
	_record(_state.active_shadow_instance_id == &"",
		"24) and clearing the session's active id")
	_record(not _summoner.recall(), "25) recalling again does nothing")
	_record(_summoner.summon(&"shadow_999999") == null,
		"26) an unknown id summons nothing")

	_summoner.toggle(first.instance_id)
	await _wait(0.3)
	_record(_summoner.is_active(first.instance_id), "27) toggle summons")
	_summoner.toggle(first.instance_id)
	await _wait(0.3)
	_record(not _summoner.has_active_shadow(), "28) and toggle again recalls")


# --- following ------------------------------------------------------------------------

func _follow_tests() -> void:
	_player.global_position = ROOM1_TRIGGER + Vector3(0, 0, 8)
	await _wait(0.4)
	var shadow: ShadowInstance = _collection.get_shadows()[0]
	var node: BasicMeleeShadow = _summoner.summon(shadow.instance_id)
	await _wait(0.5)
	_record(node.get_state() == BasicMeleeShadow.State.FOLLOW,
		"29) with no enemy around it follows")

	# Walk away and let it catch up.
	node.global_position = _player.global_position + Vector3(0, 0, 7.0)
	await _wait(0.2)
	var far: float = _player.global_position.distance_to(node.global_position)
	await _wait(2.5)
	var near: float = _player.global_position.distance_to(node.global_position)
	_record(near < far - 1.0,
		"30) left behind at %.1f m it closes to %.1f m" % [far, near])
	_record(near <= node.max_follow_distance,
		"31) settling inside its %.0f m leash" % node.max_follow_distance)

	# M8.3 replaced the old "far for three seconds" teleport with progress-based
	# stuck detection, so distance alone no longer moves a shadow. One with a
	# clear path walks back under its own power.
	# Measured per PHYSICS FRAME, not per second: headless runs physics far
	# faster than the wall clock, so a rate in m/s means nothing here. What
	# separates walking from teleporting is how far it can move in one step.
	# Into the level (-z), not out of it: dropped outside the geometry it would
	# only fall, and the fall recovery below is a different rule.
	node.global_position = _player.global_position + Vector3(0, 0, -14.0)
	await _wait(0.3)
	var step_ceiling: float = node.movement_speed / Engine.physics_ticks_per_second * 1.6
	var biggest: float = 0.0
	var total: float = 0.0
	var previous: Vector3 = node.global_position
	for _i in 60:
		await get_tree().physics_frame
		var moved: float = previous.distance_to(node.global_position)
		biggest = maxf(biggest, moved)
		total += moved
		previous = node.global_position
	_record(total > 0.5 and biggest <= step_ceiling,
		"32) left 14 m out it walks back, never jumping (%.2f m covered, biggest step %.3f m of %.3f)" % [
			total, biggest, step_ceiling])

	# Falling out of the level is the one case still recovered at once: every
	# extra second of it is another ten metres down.
	node.global_position = _player.global_position - Vector3(0, 20.0, 0)
	await _wait(0.4)
	_record(_player.global_position.y - node.global_position.y < node.fall_recovery_depth,
		"32b) a shadow that fell out of the world comes back immediately (%.1f m below)" %
			(_player.global_position.y - node.global_position.y))
	_summoner.recall()
	await _wait(0.3)


# --- fighting --------------------------------------------------------------------------

func _combat_tests() -> void:
	_player.global_position = ROOM1_TRIGGER
	await _wait(0.8)
	var room: RoomController = _dungeon.get_rooms()[0]
	var enemy: RoomCombatant = room.get_enemies()[0]
	var shadow: ShadowInstance = _collection.get_shadows()[0]

	# Stand the player next to the enemy but never swing: anything the enemy
	# loses from here was dealt by the shadow.
	_player.global_position = enemy.global_position + Vector3(0, 0, 3.0)
	var node: BasicMeleeShadow = _summoner.summon(shadow.instance_id)
	await _wait(0.3)
	node.global_position = enemy.global_position + Vector3(0, 0, 2.2)
	await _wait(0.6)
	_record(node.get_target() == enemy or node.get_state() != BasicMeleeShadow.State.FOLLOW,
		"33) an enemy in range is acquired (state %d, target %s)" % [
			node.get_state(), node.get_target()])

	var enemy_health: HealthComponent = enemy.get_node("HealthComponent")
	var before: float = enemy_health.current_health
	await _wait(3.0)
	var after: float = enemy_health.current_health
	_record(after < before,
		"34) and it damages the enemy on its own (%.0f -> %.0f)" % [before, after])
	_record(node.get_attack_damage() > 0.0,
		"35) hitting for its level's damage (%.0f)" % node.get_attack_damage())

	# An enemy in reach of the shadow, but far from the player, is not chased
	# past the leash: the player comes first. The player moves to a real spot in
	# the level — dropping it outside the geometry would only test the fall
	# recovery.
	_player.global_position = ROOM1_TRIGGER + Vector3(0, 0, -14.0)
	await _wait(4.0)
	_record(_player.global_position.distance_to(node.global_position)
			<= node.max_follow_distance * 1.8,
		"36) it breaks off rather than being dragged away (%.1f m)" %
			_player.global_position.distance_to(node.global_position))
	_summoner.recall()
	await _wait(0.3)


# --- who can hit whom ----------------------------------------------------------------

func _friendly_fire_tests() -> void:
	var shadow: ShadowInstance = _collection.get_shadows()[0]
	var node: BasicMeleeShadow = _summoner.summon(shadow.instance_id)
	await _wait(0.4)

	var shadow_hitbox: Hitbox = node.attack_hitbox
	var shadow_hurtbox: Hurtbox = node.hurtbox
	_record(shadow.instance_id != &"" and node.collision_layer == L_SHADOW_BODY,
		"37) the shadow body sits on its own layer (%d)" % node.collision_layer)
	_record(shadow_hurtbox.collision_layer == L_SHADOW_HURTBOX,
		"38) and its hurtbox on another (%d)" % shadow_hurtbox.collision_layer)
	_record(shadow_hitbox.collision_layer == L_SHADOW_HITBOX,
		"39) as does its hitbox (%d)" % shadow_hitbox.collision_layer)

	# The mask is the whole guarantee: the shadow's swing cannot see the player.
	_record(shadow_hitbox.collision_mask == L_ENEMY_HURTBOX,
		"40) the shadow's hitbox looks only at enemy hurtboxes (mask %d)" %
			shadow_hitbox.collision_mask)
	_record(shadow_hitbox.collision_mask & L_PLAYER_HURTBOX == 0,
		"41) so it can never reach the player — no friendly fire")
	_record(_player.attack_hitbox.collision_mask & L_SHADOW_HURTBOX == 0,
		"42) and the player's swing cannot reach the shadow (mask %d)" %
			_player.attack_hitbox.collision_mask)

	var enemy: RoomCombatant = _dungeon.get_rooms()[0].get_enemies()[0]
	var enemy_hitbox: Hitbox = enemy.get_node("VisualRoot/AttackOrigin/Hitbox")
	_record(enemy_hitbox.collision_mask & L_SHADOW_HURTBOX != 0,
		"43) an enemy swing does reach the shadow (mask %d)" % enemy_hitbox.collision_mask)
	_record(enemy_hitbox.collision_mask & L_PLAYER_HURTBOX != 0,
		"44) without losing the player")

	# And empirically, through the real damage path.
	var health: HealthComponent = node.health_component
	var before: float = health.current_health
	shadow_hurtbox.receive_hit(20.0, enemy)
	_record(is_equal_approx(health.current_health, before - 20.0),
		"45) a hit taken from an enemy wounds it (%.0f -> %.0f)" % [
			before, health.current_health])
	_record(health.last_damage_source == enemy,
		"46) and the health component remembers who dealt it")
	_summoner.recall()
	await _wait(0.3)


# --- splitting the reward --------------------------------------------------------------

func _xp_split_tests() -> void:
	_player.global_position = ROOM2_TRIGGER
	await _wait(0.8)
	var room: RoomController = _dungeon.get_rooms()[1]
	var shadow: ShadowInstance = _collection.get_shadows()[0]
	var node: BasicMeleeShadow = _summoner.summon(shadow.instance_id)
	await _wait(0.4)

	# The player finishes this one itself.
	var enemy: RoomCombatant = room.get_enemies()[0]
	var reward: int = enemy.get_xp_reward()
	var player_before: int = _total_player_xp()
	var shadow_before: int = shadow.current_xp
	await _player_kill(enemy)
	_record(_total_player_xp() - player_before == reward,
		"47) a kill the player finishes is worth all %d XP to it" % reward)
	_record(shadow.current_xp == shadow_before,
		"48) and nothing to the shadow")

	# This one the shadow finishes, after the player has opened it up.
	var second: RoomCombatant = room.get_enemies()[1]
	var second_reward: int = second.get_xp_reward()
	var expected_shadow: int = int(round(second_reward * PlayerProgression.SHADOW_KILL_SHARE))
	var expected_player: int = second_reward - expected_shadow
	player_before = _total_player_xp()
	shadow_before = shadow.current_xp
	var shadow_level_before: int = shadow.level
	await _shadow_kill(node, second)
	_record(second.has_died(), "49) the shadow landed the killing blow")
	_record(second.get_killer() == node,
		"50) and the combatant recorded it as the killer (%s)" % second.get_killer())
	var shadow_gain: int = shadow.current_xp - shadow_before \
		+ _levels_worth(shadow, shadow_level_before)
	_record(shadow_gain == expected_shadow,
		"51) the shadow took %d of %d XP (expected %d)" % [
			shadow_gain, second_reward, expected_shadow])
	_record(_total_player_xp() - player_before == expected_player,
		"52) the player took the remaining %d" % expected_player)
	_record(expected_shadow + expected_player == second_reward,
		"53) and the two halves add back up to the full reward")

	# The brief's worked example, on the formula rather than on a live enemy.
	var sample: int = 25
	var sample_shadow: int = int(round(sample * PlayerProgression.SHADOW_KILL_SHARE))
	_record(sample_shadow == 18 and sample - sample_shadow == 7,
		"54) a 25 XP kill splits 18 / 7 (got %d / %d)" % [
			sample_shadow, sample - sample_shadow])


# --- the shadow dies ---------------------------------------------------------------------

func _death_tests() -> void:
	var shadow: ShadowInstance = _collection.get_shadows()[0]
	if not _summoner.has_active_shadow():
		_summoner.summon(shadow.instance_id)
		await _wait(0.4)
	var node: BasicMeleeShadow = _summoner.get_active_node()
	var level_before: int = shadow.level
	var xp_before: int = shadow.current_xp
	var count_before: int = _collection.get_count()

	node.health_component.receive_damage(10000.0)
	await _wait(0.3)
	_record(node.is_dead(), "55) killing it puts it in the DEAD state")
	_record(not _summoner.has_active_shadow()
			and _summoner.get_active_instance_id() == &"",
		"56) and nothing is active any more")
	_record(_state.active_shadow_instance_id == &"",
		"57) the session forgets it, so a scene change will not bring it back")
	_record(_collection.get_count() == count_before
			and _collection.has_shadow(shadow.instance_id),
		"58) the shadow itself stays in the collection")
	_record(shadow.level == level_before and shadow.current_xp == xp_before,
		"59) keeping its Lv.%d and %d XP" % [shadow.level, shadow.current_xp])

	await _wait(1.2)
	_record(_count_shadow_nodes() == 0, "60) and the corpse is cleaned up")

	# It can be summoned again — death costs the run, not the shadow.
	var again: BasicMeleeShadow = _summoner.summon(shadow.instance_id)
	await _wait(0.4)
	_record(again != null and again.instance == shadow,
		"61) it can be summoned again at the same level")
	_summoner.recall()
	await _wait(0.3)


# --- the roster ----------------------------------------------------------------------------

func _menu_tests() -> void:
	var shadow: ShadowInstance = _collection.get_shadows()[0]
	_menu.open()
	await _wait(0.2)
	_menu.select_row(0)
	await _wait(0.1)
	var detail: String = _menu.get_detail_text()
	_record(detail.contains("Livello %d" % shadow.level),
		"62) the detail pane shows the level")
	_record(detail.contains("XP: %d/%d" % [shadow.current_xp, shadow.get_xp_to_next_level()]),
		"63) and the XP towards the next one")
	_record(_menu.get_row_text(0).contains("Lv.%d" % shadow.level),
		"64) the row carries the level too: '%s'" % _menu.get_row_text(0).strip_edges())

	_record(_menu.is_summon_button_visible() and _menu.get_summon_button_text() == "[Evoca]",
		"65) a selected shadow offers '%s'" % _menu.get_summon_button_text())
	_menu.press_summon()
	await _wait(0.4)
	_record(_summoner.is_active(shadow.instance_id), "66) pressing it summons")
	_record(_menu.get_summon_button_text() == "[Richiama]",
		"67) and the button becomes '%s'" % _menu.get_summon_button_text())
	_record(_menu.get_row_text(0).contains("ATTIVA"),
		"68) the active row is marked: '%s'" % _menu.get_row_text(0).strip_edges())

	_menu.press_summon()
	await _wait(0.4)
	_record(not _summoner.has_active_shadow(), "69) pressing it again recalls")
	_record(not _menu.get_row_text(0).contains("ATTIVA"), "70) clearing the marker")
	_menu.close()
	await _wait(0.2)
	_record(not get_tree().paused, "71) closing the menu unpauses")


# --- helpers ---------------------------------------------------------------------------------

func _count_shadow_nodes() -> int:
	return get_tree().get_nodes_in_group(BasicMeleeShadow.GROUP).size()


## Level-ups make a raw XP difference meaningless, so the levels crossed are
## converted back into the XP they cost.
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


## The player opens the enemy up and finishes it. A hit has to land for the
## player to be subscribed at all — that is M6.1, not something M8.2 changed.
func _player_kill(enemy: RoomCombatant) -> void:
	await _swing_at(enemy)
	(enemy.get_node("HealthComponent") as HealthComponent).receive_damage(
		10000.0, _player)
	await _wait(0.5)


## The player softens the enemy, the shadow finishes it. The last blow has to be
## the shadow's for the split to apply, so it is dealt through the shadow's own
## hurtbox path with the shadow named as the source.
func _shadow_kill(node: BasicMeleeShadow, enemy: RoomCombatant) -> void:
	await _swing_at(enemy)
	var hurtbox: Hurtbox = enemy.get_node("Hurtbox")
	hurtbox.receive_hit(10000.0, node)
	await _wait(0.5)


func _swing_at(enemy: RoomCombatant) -> void:
	_player.global_position = enemy.global_position + Vector3(0, 0, 1.6)
	_player.camera_rig.rotation.y = 0.0
	_player._attack_state = Player.AttackState.IDLE
	_player._combo_index = 0
	_player.camera_rig.attack_light_pressed.emit()
	await _wait(0.45)
