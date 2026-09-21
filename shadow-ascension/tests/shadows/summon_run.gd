extends SceneTree

## M8.2 end to end with REAL scene changes: summon a shadow, carry it out of the
## dungeon, back in, and through a death.
##
##   godot --headless --path . --script res://tests/shadows/summon_run.gd

const HUB: String = "res://scenes/core/hub.tscn"
const DUNGEON: String = "res://scenes/dungeons/dungeon_test.tscn"
const ROOM_ANCHORS: Array[Vector3] = [
	Vector3(0, 0.1, -13), Vector3(0, 0.1, -33), Vector3(0, 0.1, -53)
]
const EXIT_POS: Vector3 = Vector3(0, 0.1, -65)
const STRIKE_RANGE: float = 1.6

var _shadow_data: ShadowData = preload("res://resources/shadows/basic_melee_shadow.tres")
var _pass: int = 0
var _fail: int = 0
var _real_chance: float = 0.0
var _state: Node = null


func _initialize() -> void:
	_state = root.get_node_or_null("PlayerRuntimeState")
	_state.reset_runtime_state()
	_real_chance = _shadow_data.extraction_chance
	# Forced so the run does not hinge on a 70% roll. Restored at the end.
	_shadow_data.extraction_chance = 1.0

	change_scene_to_file(HUB)
	await _pause(0.6)
	var player: Player = current_scene.get_node("Player")
	_record(player.shadow_summoner != null, "1) the player carries a summoner")
	_record(not player.shadow_summoner.has_active_shadow()
			and _state.active_shadow_instance_id == &"",
		"2) a new session starts with nothing summoned")

	await _enter_dungeon()
	var dungeon: DungeonController = current_scene as DungeonController
	var p: Player = current_scene.get_node("Player")
	p.hurtbox.set_invulnerable(true)

	# --- get a shadow, and put it in the world
	p.global_position = ROOM_ANCHORS[0]
	await _pause(0.5)
	var room1: RoomController = dungeon.get_rooms()[0]
	await _kill(p, room1.get_enemies()[0])
	await _pause(0.3)
	await _extract_all(p, dungeon)
	_record(p.shadows.get_count() >= 1,
		"3) a shadow was extracted (%d held)" % p.shadows.get_count())
	var shadow: ShadowInstance = p.shadows.get_shadows()[0]
	var shadow_id: StringName = shadow.instance_id

	var node: BasicMeleeShadow = p.shadow_summoner.summon(shadow_id)
	await _pause(0.5)
	_record(node != null, "4) and summoned into the dungeon")
	_record(_state.active_shadow_instance_id == shadow_id,
		"5) the session records which one is out")

	# --- it earns XP of its own by finishing a kill
	var second: RoomCombatant = room1.get_enemies()[1]
	var reward: int = second.get_xp_reward()
	await _kill(p, second, 20.0, false)
	(second.get_node("Hurtbox") as Hurtbox).receive_hit(10000.0, node)
	await _pause(0.5)
	var expected: int = int(round(reward * PlayerProgression.SHADOW_KILL_SHARE))
	_record(shadow.current_xp == expected,
		"6) a kill it finished paid it %d of %d XP" % [shadow.current_xp, reward])

	# Levelled on purpose, so "it came back the same" is a claim with substance.
	p.shadows.award_xp(shadow_id, 200)
	_record(shadow.level > 1, "7) topped up to Lv.%d for the trip" % shadow.level)
	var level_out: int = shadow.level
	var xp_out: int = shadow.current_xp
	print("[IN DUNGEON ] %s Lv.%d %d XP" % [shadow.get_short_id(), level_out, xp_out])

	# --- clear the rest so the exit portal opens
	# Shielded for the clear, as the player already is: a boss can genuinely
	# kill a Lv.4 shadow, and that is tested in summon_test.gd. What this run is
	# about is whether the shadow survives the SCENE CHANGE.
	node.hurtbox.set_invulnerable(true)
	for i in range(1, 3):
		p.global_position = ROOM_ANCHORS[i]
		await _pause(0.6)
		for enemy in dungeon.get_rooms()[i].get_enemies():
			await _kill(p, enemy, 60.0)
			await _pause(0.3)
	_record(dungeon.get_state() == DungeonController.DungeonState.COMPLETED,
		"8) the dungeon completed")
	_record(p.shadow_summoner.has_active_shadow(),
		"9) with the shadow still out at the end of it")
	p.hurtbox.set_invulnerable(false)

	# --- out through the portal: it should come back on its own
	p.global_position = EXIT_POS
	await _pause(0.4)
	dungeon.exit_portal.activate()
	await _pause(1.4)
	_record(current_scene.scene_file_path == HUB, "10) the portal returned home")
	var p2: Player = current_scene.get_node("Player")
	_record(p2 != p, "11) on a different Player instance")
	var back: BasicMeleeShadow = p2.shadow_summoner.get_active_node()
	_record(back != null and back != node,
		"12) and the shadow re-summoned itself, as a new entity")
	_record(p2.shadow_summoner.get_active_instance_id() == shadow_id,
		"13) the same one that was out (%s)" % shadow_id)
	var carried: ShadowInstance = p2.shadows.get_shadow(shadow_id)
	print("[BACK HOME  ] %s Lv.%d %d XP" % [
		carried.get_short_id(), carried.level, carried.current_xp])
	_record(carried.level == level_out and carried.current_xp == xp_out,
		"14) at the same Lv.%d and %d XP" % [carried.level, carried.current_xp])
	var back_health: float = back.health_component.max_health if back != null else -1.0
	_record(is_equal_approx(back_health, carried.get_max_health()),
		"15) and with the health its level buys (%.0f of %.0f)" % [
			back_health, carried.get_max_health()])

	# --- back in: still out
	await _enter_dungeon()
	var p3: Player = current_scene.get_node("Player")
	await _pause(0.5)
	_record(p3.shadow_summoner.is_active(shadow_id),
		"16) it is out again on the second run too")

	# --- recalled shadows stay recalled across a change
	p3.shadow_summoner.recall()
	await _pause(0.3)
	_record(_state.active_shadow_instance_id == &"", "17) recalling clears the session id")

	# --- a death does not bring it back
	p3.shadow_summoner.summon(shadow_id)
	await _pause(0.4)
	_record(p3.shadow_summoner.has_active_shadow(), "18) summoned again before dying")
	var dungeon2: DungeonController = current_scene as DungeonController
	p3.hurtbox.set_invulnerable(false)
	p3.health_component.receive_damage(10000.0)
	await _pause(0.3)
	_record(dungeon2.get_state() == DungeonController.DungeonState.FAILED, "19) the run failed")
	_record(_state.active_shadow_instance_id == &"",
		"20) the player's death cleared the active shadow")
	await _pause(2.5)
	var p4: Player = current_scene.get_node("Player")
	_record(not p4.shadow_summoner.has_active_shadow(),
		"21) so the next run does NOT start with one already summoned")
	var after_death: ShadowInstance = p4.shadows.get_shadow(shadow_id)
	print("[AFTER DEATH] %s Lv.%d %d XP" % [
		after_death.get_short_id(), after_death.level, after_death.current_xp])
	_record(after_death != null and after_death.level == level_out
			and after_death.current_xp == xp_out,
		"22) but the shadow itself is unharmed, at Lv.%d" % after_death.level)
	_record(p4.shadow_summoner.summon(shadow_id) != null,
		"23) and can be summoned again by hand")

	_shadow_data.extraction_chance = _real_chance
	_record(is_equal_approx(_shadow_data.extraction_chance, 0.7),
		"24) the real extraction chance is restored to %.2f" % _shadow_data.extraction_chance)

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


func _enter_dungeon() -> void:
	var p: Player = current_scene.get_node("Player")
	var gate: DungeonGate = current_scene.get_node("DungeonGate")
	p.global_position = gate.global_position
	await _pause(0.3)
	gate.activate()
	await _pause(1.2)


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


## `finish` false leaves the target alive on purpose, so the caller can decide
## who lands the last blow.
func _kill(player: Player, target: RoomCombatant, budget: float = 20.0,
		finish: bool = true) -> int:
	var swings: int = 0
	var elapsed: float = 0.0
	var health: HealthComponent = target.get_node("HealthComponent")
	while elapsed < budget and not target.has_died():
		if not finish and health.current_health < health.max_health:
			break
		if player.get("_attack_state") == Player.AttackState.IDLE:
			player.global_position = target.global_position + Vector3(0, 0, STRIKE_RANGE)
			player.camera_rig.rotation.y = 0.0
			player.camera_rig.attack_light_pressed.emit()
			swings += 1
		await physics_frame
		elapsed += 1.0 / 60.0
	return swings
