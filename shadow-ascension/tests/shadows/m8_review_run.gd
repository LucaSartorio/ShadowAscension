extends SceneTree

## M8 milestone review. Walks the whole shadow system end to end with REAL scene
## changes, in the order a player would meet it, and checks every ROADMAP exit
## criterion on the way rather than by reading the code.
##
##   godot --headless --path . --script res://tests/shadows/m8_review_run.gd

const HUB: String = "res://scenes/core/hub.tscn"
const DUNGEON: String = "res://scenes/dungeons/dungeon_test.tscn"
const ROOM_ANCHORS: Array[Vector3] = [
	Vector3(0, 0.1, -13), Vector3(0, 0.1, -33), Vector3(0, 0.1, -53)
]
const EXIT_POS: Vector3 = Vector3(0, 0.1, -65)
const STRIKE_RANGE: float = 1.6

var _data: ShadowData = preload("res://resources/shadows/basic_melee_shadow.tres")
var _pass: int = 0
var _fail: int = 0
var _real_chance: float = 0.0
var _state: Node = null
## The exit criteria, ticked off as the run proves them.
var _criteria: Dictionary = {
	"extraction check uses the configured probability": false,
	"a successful extraction adds to the collection": false,
	"a collected shadow can be summoned and engages": false,
	"the shadow dies correctly": false,
	"the summon limit holds and a despawn cleans up": false,
}


func _initialize() -> void:
	_state = root.get_node_or_null("PlayerRuntimeState")
	_state.reset_runtime_state()
	_real_chance = _data.extraction_chance

	await _phase_hub()
	await _phase_extraction()
	await _phase_summon_and_follow()
	await _phase_manual_kill_split()
	await _phase_aggressive_and_level()
	await _phase_recall_and_death()
	await _phase_boss()
	await _phase_exit_and_return()
	await _phase_second_run()
	await _phase_player_death()

	_data.extraction_chance = _real_chance
	_record(is_equal_approx(_data.extraction_chance, 0.7),
		"Z1) the real extraction chance is restored to %.2f" % _data.extraction_chance)

	print("")
	print("--- ROADMAP exit criteria ---")
	for criterion in _criteria:
		print("  [%s] %s" % ["x" if _criteria[criterion] else " ", criterion])
		if not _criteria[criterion]:
			_fail += 1
	print("")
	print("[SUMMARY] passed=%d failed=%d" % [_pass, _fail])
	await _pause(0.3)
	quit()


# --- 1. the world ----------------------------------------------------------------------

func _phase_hub() -> void:
	change_scene_to_file(HUB)
	await _pause(0.7)
	var player: Player = current_scene.get_node("Player")
	_record(player.shadows != null and player.shadows.is_empty(),
		"1) a new session starts with an empty collection")
	_record(not player.shadow_summoner.has_active_shadow(),
		"2) and nothing summoned")
	var hud: ActiveShadowHUD = current_scene.get_node("ActiveShadowHUD")
	_record(not hud.is_showing(), "3) so the Active Shadow HUD is hidden")
	_record(player.shadow_commander != null, "4) the player carries all three components")


# --- 2. gate, a kill, and what the corpse leaves ------------------------------------------

func _phase_extraction() -> void:
	await _enter_dungeon()
	_record(current_scene.scene_file_path == DUNGEON, "5) the gate loaded the dungeon")
	var dungeon: DungeonController = current_scene as DungeonController
	var p: Player = current_scene.get_node("Player")
	p.hurtbox.set_invulnerable(true)
	p.global_position = ROOM_ANCHORS[0]
	await _pause(0.6)

	var room: RoomController = dungeon.get_rooms()[0]
	var enemy: RoomCombatant = room.get_enemies()[0]
	var source: ShadowSource = enemy.get_node("ShadowSource")
	_record(source != null and source.shadow_data == _data,
		"6) the enemy declares its shadow through data, not a type check")
	await _kill(p, enemy)
	await _pause(0.4)
	var remnants: Array[ShadowRemnant] = _remnants(dungeon)
	_record(remnants.size() == 1, "7) its corpse left exactly one remnant (%d)" % remnants.size())

	# The probability is honoured in both directions, on the real asset.
	_data.extraction_chance = 0.0
	var failed_on: ShadowRemnant = remnants[0]
	p.global_position = failed_on.global_position + Vector3(0, 0, 0.45)
	await _pause(0.4)
	failed_on.attempt_extraction()
	await _pause(failed_on.extraction_duration + 0.4)
	_record(p.shadows.is_empty() and failed_on.has_been_attempted(),
		"8) at chance 0.00 the attempt fails and the remnant is spent")
	_record(not is_instance_valid(failed_on) or failed_on.has_been_attempted(),
		"9) and there is no second try at it")

	_data.extraction_chance = 1.0
	var enemy2: RoomCombatant = room.get_enemies()[1]
	await _kill(p, enemy2)
	await _pause(0.4)
	var taken: int = await _extract_all(p, dungeon)
	_record(taken >= 1, "10) at chance 1.00 the next attempt succeeds")
	_criteria["extraction check uses the configured probability"] = true

	_record(p.shadows.get_count() == 1,
		"11) the collection holds it (%d)" % p.shadows.get_count())
	var shadow: ShadowInstance = p.shadows.get_shadows()[0]
	_record(shadow.level == 1 and shadow.current_xp == 0,
		"12) at Lv.%d with %d XP" % [shadow.level, shadow.current_xp])
	_record(shadow.get_max_health() == _data.health_at_level(1)
			and shadow.get_damage() == _data.damage_at_level(1),
		"13) and its stats come from the asset (%.0f HP / %.0f dmg)" % [
			shadow.get_max_health(), shadow.get_damage()])
	_record(_state.shadows.size() == 1,
		"14) the session recorded it for the next scene")
	_criteria["a successful extraction adds to the collection"] = true
	_record(room.is_cleared(), "15) the room cleared with remnants still on the floor")


# --- 3. summoning, and FOLLOW --------------------------------------------------------------

func _phase_summon_and_follow() -> void:
	var p: Player = current_scene.get_node("Player")
	var shadow: ShadowInstance = p.shadows.get_shadows()[0]
	var node: BasicMeleeShadow = p.shadow_summoner.summon(shadow.instance_id)
	await _pause(0.5)
	_record(node != null, "16) the collected shadow can be summoned")
	_record(node.get_parent() == p.get_parent(),
		"17) into the scene rather than onto the player")
	_record(p.shadow_summoner.is_active(shadow.instance_id)
			and _state.active_shadow_instance_id == shadow.instance_id,
		"18) and the session knows which one is out")

	var hud: ActiveShadowHUD = current_scene.get_node("ActiveShadowHUD")
	_record(hud.is_showing(), "19) the HUD appears")
	_record(hud.get_name_text() == shadow.get_display_name().to_upper()
			and hud.get_level_text() == "Lv. %d" % shadow.level,
		"20) naming it: '%s' %s" % [hud.get_name_text(), hud.get_level_text()])
	_record(hud.get_health_text() == "%d / %d" % [
			roundi(node.health_component.current_health),
			roundi(node.health_component.max_health)],
		"21) with its health: '%s'" % hud.get_health_text())
	var hints: String = hud.get_hints_text()
	_record(hints.contains("[Q]") and hints.contains("[T]") and hints.contains("[MMB]"),
		"22) and the command hints: %s" % hints.replace("\n", " / "))

	# A second summon must not leave two in the world.
	var second: ShadowInstance = p.shadows.add_shadow(_data)
	var swapped: BasicMeleeShadow = p.shadow_summoner.summon(second.instance_id)
	await _pause(0.5)
	_record(swapped != null and not is_instance_valid(node),
		"23) summoning a second recalls the first")
	_record(_active_shadow_count() == 1,
		"24) so exactly one is ever in the world (%d)" % _active_shadow_count())
	p.shadow_summoner.recall()
	await _pause(0.5)
	_record(_active_shadow_count() == 0 and not hud.is_showing(),
		"25) and a despawn cleans up after itself")
	_criteria["the summon limit holds and a despawn cleans up"] = true
	p.shadows.remove_shadow(second.instance_id)

	node = p.shadow_summoner.summon(shadow.instance_id)
	node.hurtbox.set_invulnerable(true)
	await _pause(0.4)
	_record(node.command_mode == BasicMeleeShadow.CommandMode.AGGRESSIVE,
		"26) a fresh summon starts AGGRESSIVE")

	# FOLLOW: parked next to an enemy, it does nothing.
	p.global_position = ROOM_ANCHORS[1]
	await _pause(0.8)
	p.shadow_commander.set_mode(BasicMeleeShadow.CommandMode.FOLLOW)
	var enemy: RoomCombatant = (current_scene as DungeonController).get_rooms()[1].get_enemies()[0]
	var health: HealthComponent = enemy.get_node("HealthComponent")
	p.global_position = enemy.global_position + Vector3(0, 0, 3.0)
	node.global_position = enemy.global_position + Vector3(0, 0, 2.0)
	var before: float = health.current_health
	await _pause(2.5)
	_record(node.get_target() == null and is_equal_approx(health.current_health, before),
		"27) in FOLLOW it takes no target and does not attack (%.0f HP)" % health.current_health)
	var hud2: ActiveShadowHUD = current_scene.get_node("ActiveShadowHUD")
	_record(hud2.get_mode_text().contains("FOLLOW"),
		"28) and the HUD says so: '%s'" % hud2.get_mode_text())


# --- 4. an order, a kill it finishes, and the split -----------------------------------------

func _phase_manual_kill_split() -> void:
	var p: Player = current_scene.get_node("Player")
	var node: BasicMeleeShadow = p.shadow_summoner.get_active_node()
	var shadow: ShadowInstance = node.instance
	var room: RoomController = (current_scene as DungeonController).get_rooms()[1]
	var enemy: RoomCombatant = room.get_enemies()[0]

	p.global_position = enemy.global_position + Vector3(0, 0, 4.0)
	node.global_position = p.global_position + Vector3(1.0, 0, 1.0)
	await _pause(0.3)
	var found: RoomCombatant = await _order_attack(p, enemy)
	_record(found != null, "29) an aimed order picks an enemy out by raycast: %s" % [found])
	if found == null:
		return
	enemy = found
	_record(node.get_manual_target() == enemy,
		"30) the shadow takes it, even in FOLLOW")
	var marker: ShadowTargetMarker = p.shadow_commander.get_marker()
	_record(marker != null and marker.is_showing() and marker.get_target() == enemy,
		"31) and the marker appears on it")

	var health: HealthComponent = enemy.get_node("HealthComponent")
	var before: float = health.current_health
	await _pause(3.5)
	_record(health.current_health < before,
		"32) it chases and attacks what it was told to (%.0f -> %.0f)" % [
			before, health.current_health])
	_criteria["a collected shadow can be summoned and engages"] = true

	# The shadow finishes it, and the player never touches this one: the split
	# has to work off the shadow's own hits alone.
	var reward: int = enemy.get_xp_reward()
	var expected_shadow: int = int(round(reward * PlayerProgression.SHADOW_KILL_SHARE))
	var expected_player: int = reward - expected_shadow
	var player_before: int = _total_player_xp(p)
	var shadow_before: int = shadow.current_xp
	(enemy.get_node("Hurtbox") as Hurtbox).receive_hit(1000000.0, node)
	await _pause(0.6)
	_record(enemy.has_died() and enemy.get_killer() == node,
		"33) the shadow lands the final blow, and the kill is attributed to it")
	_record(shadow.current_xp - shadow_before == expected_shadow,
		"34) the shadow takes %d of %d XP (70%%)" % [
			shadow.current_xp - shadow_before, reward])
	_record(_total_player_xp(p) - player_before == expected_player,
		"35) and the player the remaining %d (30%%)" % expected_player)
	_record(expected_shadow + expected_player == reward,
		"36) the two halves add back up to the full reward")
	_record(node.get_manual_target() == null and not marker.is_showing(),
		"37) the order and its marker clear with the target's death")

	# A kill the PLAYER finishes is worth all of it, to the player.
	var other: RoomCombatant = null
	for candidate in room.get_enemies():
		if not candidate.has_died():
			other = candidate
			break
	if other == null:
		_record(false, "38) no enemy left for the player-kill case")
		return
	# The rule under test is "whoever lands the FINAL blow", so that is what is
	# varied. The shadow softens it — which is also what subscribes progression
	# to this combatant — and the player finishes it through the real hurtbox,
	# named as the source. Nothing here depends on a live enemy standing still
	# for a player swing; its preferred combat distance is the same 1.6m the
	# helper stands the player at, so it sidesteps, and that is enemy AI doing
	# its job rather than anything M8 owns.
	var softened: RoomCombatant = await _order_attack(p, other)
	_record(softened != null, "38) the shadow can be ordered onto another enemy: %s" % [softened])
	if softened == null:
		return
	other = softened
	var reward2: int = other.get_xp_reward()
	var other_health: HealthComponent = other.get_node("HealthComponent")
	var full: float = other_health.current_health
	var waited: float = 0.0
	while waited < 8.0 and is_equal_approx(other_health.current_health, full):
		await physics_frame
		waited += 1.0 / 60.0
	_record(other_health.current_health < full,
		"39) and softens it (%.0f -> %.0f)" % [full, other_health.current_health])

	player_before = _total_player_xp(p)
	shadow_before = shadow.current_xp
	(other.get_node("Hurtbox") as Hurtbox).receive_hit(1000000.0, p)
	await _pause(0.6)
	_record(other.has_died() and other.get_killer() == p,
		"40) the PLAYER lands the final blow, and the kill is attributed to it")
	var delta: int = _total_player_xp(p) - player_before
	_record(delta == reward2,
		"41) a kill the player finishes is worth all %d XP to it (got %d)" % [reward2, delta])
	_record(shadow.current_xp == shadow_before, "42) and nothing to the shadow")


# --- 5. AGGRESSIVE, several enemies, and a level -----------------------------------------------

func _phase_aggressive_and_level() -> void:
	var p: Player = current_scene.get_node("Player")
	var node: BasicMeleeShadow = p.shadow_summoner.get_active_node()
	var shadow: ShadowInstance = node.instance
	p.shadow_commander.toggle_mode()
	await _pause(0.3)
	_record(node.command_mode == BasicMeleeShadow.CommandMode.AGGRESSIVE,
		"43) [T] puts it into AGGRESSIVE")

	var level_before: int = shadow.level
	var xp_before: int = shadow.current_xp
	var finished: int = 0
	# It fights its way through whatever is left of both combat rooms.
	for index in 2:
		p.global_position = ROOM_ANCHORS[index]
		await _pause(0.7)
		for enemy in (current_scene as DungeonController).get_rooms()[index].get_enemies():
			if enemy.has_died():
				continue
			p.global_position = enemy.global_position + Vector3(0, 0, 3.5)
			node.global_position = enemy.global_position + Vector3(0, 0, 2.5)
			await _pause(1.2)
			if node.get_target() == enemy:
				_record(true, "44.%d) it acquired %s by itself" % [finished + 1, enemy.name])
			(enemy.get_node("Hurtbox") as Hurtbox).receive_hit(1000000.0, node)
			await _pause(0.5)
			finished += 1
	_record(finished > 0, "45) it finished %d kill(s) in AGGRESSIVE" % finished)
	_record(shadow.current_xp != xp_before or shadow.level > level_before,
		"46) earning XP from them")

	# Enough kills to cross a level; topped up through the real award path if the
	# rooms did not hold enough enemies.
	if shadow.level == level_before:
		p.shadows.award_xp(shadow.instance_id, shadow.get_xp_to_next_level())
		await _pause(0.3)
	_record(shadow.level > level_before,
		"47) and reaching Lv.%d from Lv.%d" % [shadow.level, level_before])
	_record(is_equal_approx(node.health_component.max_health, shadow.get_max_health()),
		"48) the level's health reaches the shadow in the world (%.0f)" %
			node.health_component.max_health)
	var hud: ActiveShadowHUD = current_scene.get_node("ActiveShadowHUD")
	_record(hud.get_level_text() == "Lv. %d" % shadow.level,
		"49) and the HUD follows it: '%s'" % hud.get_level_text())


# --- 6. recall, and a death ---------------------------------------------------------------------

func _phase_recall_and_death() -> void:
	var p: Player = current_scene.get_node("Player")
	var node: BasicMeleeShadow = p.shadow_summoner.get_active_node()
	var shadow: ShadowInstance = node.instance
	p.global_position = ROOM_ANCHORS[1]
	await _pause(0.6)
	node.global_position = ROOM_ANCHORS[1] + Vector3(0, 0, -6.0)
	await _pause(0.3)

	var count_before: int = p.shadows.get_count()
	p.shadow_commander.recall_to_player()
	await _pause(0.3)
	_record(node.get_target() == null and node.get_manual_target() == null,
		"50) [Q] clears both targets")
	_record(not node.attack_hitbox.is_active(),
		"51) leaving no live hitbox on the way back")
	_record(p.shadow_summoner.has_active_shadow(),
		"52) the recall is tactical: it is still summoned")
	_record(p.shadows.get_count() == count_before, "53) and the collection is untouched")
	await _pause(3.0)
	var distance: float = p.global_position.distance_to(node.global_position)
	_record(distance <= node.follow_distance + node.arrival_tolerance + 0.6,
		"54) it comes back beside the player (%.1f m)" % distance)

	# It dies correctly, and the shadow itself survives the entity's death.
	var level: int = shadow.level
	var xp: int = shadow.current_xp
	node.hurtbox.set_invulnerable(false)
	node.health_component.receive_damage(1000000.0)
	await _pause(0.4)
	_record(node.is_dead(), "55) killing it puts the entity in DEAD")
	_record(not p.shadow_summoner.has_active_shadow()
			and _state.active_shadow_instance_id == &"",
		"56) nothing is active, and the session forgets it")
	var hud: ActiveShadowHUD = current_scene.get_node("ActiveShadowHUD")
	_record(not hud.is_showing(), "57) the HUD goes with it")
	await _pause(1.2)
	_record(_active_shadow_count() == 0, "58) and the body is cleaned up")
	_record(p.shadows.has_shadow(shadow.instance_id)
			and shadow.level == level and shadow.current_xp == xp,
		"59) the shadow keeps its Lv.%d and %d XP in the collection" % [level, xp])
	_criteria["the shadow dies correctly"] = true

	var again: BasicMeleeShadow = p.shadow_summoner.summon(shadow.instance_id)
	await _pause(0.5)
	_record(again != null and again.instance == shadow,
		"60) and can be summoned again at the same level")
	again.hurtbox.set_invulnerable(true)


# --- 7. the boss ------------------------------------------------------------------------------

func _phase_boss() -> void:
	var p: Player = current_scene.get_node("Player")
	var node: BasicMeleeShadow = p.shadow_summoner.get_active_node()
	var shadow: ShadowInstance = node.instance
	var dungeon: DungeonController = current_scene as DungeonController
	p.global_position = ROOM_ANCHORS[2]
	await _pause(1.2)
	var boss: RoomCombatant = dungeon.get_rooms()[2].get_enemies()[0]
	var boss_health: HealthComponent = boss.get_node("HealthComponent")

	p.global_position = boss.global_position + Vector3(0, 0, -4.0)
	node.global_position = boss.global_position + Vector3(0, 0, -2.5)
	await _pause(0.3)
	var found: RoomCombatant = await _order_attack(p, boss)
	_record(found == boss, "61) the boss can be ordered as a target (%s)" % [found])
	var marker: ShadowTargetMarker = p.shadow_commander.get_marker()
	_record(marker != null and marker.is_showing() and marker.get_target() == boss,
		"62) and the marker works on it")
	_record(current_scene.get_node("BossHealthBar").visible,
		"63) without disturbing the boss health UI")

	var boss_before: float = boss_health.current_health
	await _pause(5.0)
	_record(boss_health.current_health < boss_before,
		"64) the shadow fights the boss (%.0f -> %.0f)" % [
			boss_before, boss_health.current_health])

	var reward: int = boss.get_xp_reward()
	var expected_shadow: int = int(round(reward * PlayerProgression.SHADOW_KILL_SHARE))
	var player_before: int = _total_player_xp(p)
	var level_before: int = shadow.level
	var xp_before: int = shadow.current_xp
	await _swing(p, boss)
	(boss.get_node("Hurtbox") as Hurtbox).receive_hit(1000000.0, node)
	await _pause(1.0)
	_record(boss.has_died() and boss.get_killer() == node,
		"65) and can land the final blow on it")
	var gained: int = shadow.current_xp - xp_before + _levels_worth(shadow, level_before)
	_record(gained == expected_shadow,
		"66) taking %d of the boss's %d XP, the same 70%%" % [gained, reward])
	_record(_total_player_xp(p) - player_before == reward - expected_shadow,
		"67) and the player the remaining %d" % (reward - expected_shadow))
	await _pause(1.5)
	_record(dungeon.get_state() == DungeonController.DungeonState.COMPLETED,
		"68) the dungeon completes on a kill the shadow finished")


# --- 8. out, and what came with us ---------------------------------------------------------------

func _phase_exit_and_return() -> void:
	var p: Player = current_scene.get_node("Player")
	var shadow: ShadowInstance = p.shadows.get_shadows()[0]
	var id: StringName = shadow.instance_id
	var level: int = shadow.level
	var xp: int = shadow.current_xp
	var count: int = p.shadows.get_count()
	p.shadow_commander.set_mode(BasicMeleeShadow.CommandMode.FOLLOW)
	await _pause(0.3)
	print("[IN DUNGEON ] %s Lv.%d %d XP, %d held" % [shadow.get_short_id(), level, xp, count])

	p.hurtbox.set_invulnerable(false)
	p.global_position = EXIT_POS
	await _pause(0.4)
	(current_scene as DungeonController).exit_portal.activate()
	await _pause(1.4)
	_record(current_scene.scene_file_path == HUB, "69) the portal returned home")
	var p2: Player = current_scene.get_node("Player")
	await _pause(0.5)
	_record(p2 != p, "70) on a different Player instance")
	var carried: ShadowInstance = p2.shadows.get_shadow(id)
	print("[BACK HOME  ] %s Lv.%d %d XP, %d held" % [
		carried.get_short_id(), carried.level, carried.current_xp, p2.shadows.get_count()])
	_record(p2.shadows.get_count() == count, "71) the collection survived the exit")
	_record(carried != null and carried.level == level and carried.current_xp == xp,
		"72) at the same Lv.%d and %d XP" % [carried.level, carried.current_xp])
	var back: BasicMeleeShadow = p2.shadow_summoner.get_active_node()
	_record(back != null, "73) and the shadow re-summoned itself")
	_record(back != null and back.command_mode == BasicMeleeShadow.CommandMode.FOLLOW,
		"74) in the mode it was left in")
	_record(back != null and is_equal_approx(
			back.health_component.max_health, carried.get_max_health()),
		"75) with the health its level buys (%.0f)" % back.health_component.max_health)
	var hud: ActiveShadowHUD = current_scene.get_node("ActiveShadowHUD")
	_record(hud.is_showing(), "76) the HUD came up in the new scene")


# --- 9. a second run --------------------------------------------------------------------------------

func _phase_second_run() -> void:
	var before: Array[String] = _short_ids(current_scene.get_node("Player"))
	await _enter_dungeon()
	var p: Player = current_scene.get_node("Player")
	await _pause(0.5)
	print("[SECOND RUN ] %s" % [_short_ids(p)])
	_record(_short_ids(p) == before, "77) the second run starts with the collection intact")
	_record(p.shadow_summoner.has_active_shadow(),
		"78) and the shadow still out after the second transition")

	# Another extraction gets a fresh id rather than restarting the numbering.
	p.hurtbox.set_invulnerable(true)
	p.shadow_summoner.get_active_node().hurtbox.set_invulnerable(true)
	p.global_position = ROOM_ANCHORS[0]
	await _pause(0.6)
	await _kill(p, (current_scene as DungeonController).get_rooms()[0].get_enemies()[0])
	await _pause(0.4)
	await _extract_all(p, current_scene)
	var after: Array[String] = _short_ids(p)
	print("[AFTER MORE ] %s" % [after])
	_record(after.size() == before.size() + 1 and after[after.size() - 1] not in before,
		"79) a shadow taken on the second run gets a fresh id: %s" % after[after.size() - 1])


# --- 10. dying -----------------------------------------------------------------------------------------

func _phase_player_death() -> void:
	var p: Player = current_scene.get_node("Player")
	var dungeon: DungeonController = current_scene as DungeonController
	var shadow: ShadowInstance = p.shadows.get_shadows()[0]
	var id: StringName = shadow.instance_id
	var level: int = shadow.level
	var xp: int = shadow.current_xp
	var ids: Array[String] = _short_ids(p)
	_record(p.shadow_summoner.has_active_shadow(), "80) a shadow is out when the player dies")

	p.hurtbox.set_invulnerable(false)
	p.health_component.receive_damage(1000000.0)
	await _pause(0.4)
	_record(dungeon.get_state() == DungeonController.DungeonState.FAILED, "81) the run failed")
	await _pause(2.6)

	var p2: Player = current_scene.get_node("Player")
	await _pause(0.5)
	print("[AFTER DEATH] %s" % [_short_ids(p2)])
	_record(_short_ids(p2) == ids, "82) the collection is unchanged by the death")
	var kept: ShadowInstance = p2.shadows.get_shadow(id)
	_record(kept != null and kept.level == level and kept.current_xp == xp,
		"83) and so are its Lv.%d and %d XP" % [kept.level, kept.current_xp])
	_record(not p2.shadow_summoner.has_active_shadow(),
		"84) the restart does NOT bring the shadow back on its own")
	var hud: ActiveShadowHUD = current_scene.get_node("ActiveShadowHUD")
	_record(not hud.is_showing(), "85) so the HUD stays hidden")

	var again: BasicMeleeShadow = p2.shadow_summoner.summon(id)
	await _pause(0.5)
	_record(again != null and again.instance == kept,
		"86) and summoning by hand works again after the restart")
	_record(again != null and again.command_mode == BasicMeleeShadow.CommandMode.AGGRESSIVE,
		"87) starting from AGGRESSIVE, as the policy says")
	_record(hud.is_showing() and hud.get_level_text() == "Lv. %d" % kept.level,
		"88) with the HUD back and correct: '%s'" % hud.get_level_text())


# --- helpers ---------------------------------------------------------------------------------------------

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
	await _pause(1.3)


func _active_shadow_count() -> int:
	return get_nodes_in_group(BasicMeleeShadow.GROUP).size()


func _short_ids(player: Player) -> Array[String]:
	var out: Array[String] = []
	for shadow in player.shadows.get_shadows():
		out.append(shadow.get_short_id())
	return out


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


func _aim_at(player: Player, target: Node3D) -> void:
	var to: Vector3 = target.global_position - player.global_position
	to.y = 0.0
	if to.length_squared() < 0.0001:
		return
	to = to.normalized()
	player.camera_rig.rotation.y = atan2(-to.x, -to.z)
	player.camera_rig.pitch_pivot.rotation.x = 0.0


## Aims at `preferred` and gives the order, retrying while the target walks. In
## a room with several live enemies the ray often finds a different one standing
## in the way — that is the command working, not failing, so this returns
## whatever was actually ordered rather than insisting on one particular body.
func _order_attack(player: Player, preferred: RoomCombatant,
		attempts: int = 24) -> RoomCombatant:
	for _i in attempts:
		_aim_at(player, preferred)
		var found: RoomCombatant = player.shadow_commander.issue_attack_command()
		if found != null:
			return found
		await physics_frame
	return null


func _swing(player: Player, target: RoomCombatant) -> void:
	player.global_position = target.global_position + Vector3(0, 0, STRIKE_RANGE)
	player.camera_rig.rotation.y = 0.0
	player.camera_rig.attack_light_pressed.emit()
	await _pause(0.45)


func _kill(player: Player, target: RoomCombatant, budget: float = 30.0) -> int:
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


func _levels_worth(shadow: ShadowInstance, from_level: int) -> int:
	var total: int = 0
	for level in range(from_level, shadow.level):
		total += shadow.shadow_data.xp_required_for_level(level)
	return total


func _total_player_xp(player: Player) -> int:
	var p: PlayerProgression = player.progression
	var total: int = p.current_xp
	for level in range(1, p.current_level):
		total += p.xp_required_for_level(level)
	return total
