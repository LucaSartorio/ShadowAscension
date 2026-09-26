extends SceneTree

## M9.2 — the three full QA runs, played end to end and measured.
##
##   godot --headless --path . --script res://tests/core/full_runs_run.gd
##
## A: the player takes the kills.
## B: the shadow takes them.
## C: things go wrong — a failed extraction, a dead shadow, a dead player — and
##    the run is finished anyway.
##
## Times are simulated combat time from entering the dungeon to the summary. A
## person also spends time walking, reading and deciding, none of which a script
## does, so these are floors rather than predictions.

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
var _state: Node = null


func _initialize() -> void:
	_state = root.get_node_or_null("PlayerRuntimeState")
	_state.reset_runtime_state()
	change_scene_to_file(HUB)
	await _pause(0.8)

	await _run_a()
	await _run_b()
	await _run_c()

	print("")
	print("[SUMMARY] passed=%d failed=%d" % [_pass, _fail])
	await _pause(0.3)
	quit()


# --- RUN A: the player's run ------------------------------------------------------------

func _run_a() -> void:
	print("")
	print("############ RUN A - player takes the kills ############")
	await _enter_dungeon()
	var dungeon: DungeonController = current_scene as DungeonController
	var p: Player = current_scene.get_node("Player")
	p.hurtbox.set_invulnerable(true)
	var stats: DungeonRunStats = dungeon.get_node("DungeonRunStats")
	var started: int = Time.get_ticks_msec()
	var boss_started: int = 0

	# Rooms 1 and 2, taking the loot and the shadows on the way.
	for index in 2:
		p.global_position = ROOM_ANCHORS[index]
		await _pause(0.8)
		for enemy in dungeon.get_rooms()[index].get_enemies():
			if not enemy.has_died():
				await _kill(p, enemy)
				await _pause(0.3)
		await _take_everything(p, dungeon)
		# The first shadow found comes along for the rest of the run.
		if not p.shadows.is_empty() and not p.shadow_summoner.has_active_shadow():
			var node: BasicMeleeShadow = p.shadow_summoner.summon(
				p.shadows.get_shadows()[0].instance_id)
			await _pause(0.4)
			if node != null:
				print("  summoned %s at Lv.%d" % [
					p.shadows.get_shadows()[0].get_short_id(),
					p.shadows.get_shadows()[0].level])

	# Spend what the rooms paid for, the way a player would before the boss.
	var spent: int = 0
	while p.progression.available_stat_points > 0 and spent < 20:
		p.progression.allocate_stat(PlayerProgression.Stat.STRENGTH)
		spent += 1
	# And wear the best weapon that dropped.
	for entry in p.inventory.get_entries():
		var item: ItemData = entry["item"]
		if item.equipment_slot != ItemData.EquipmentSlot.NONE:
			p.equipment.equip(item)
	await _pause(0.3)
	print("  before the boss: Lv.%d, STR %d (x%.2f), attack power %.0f, %d items" % [
		p.progression.current_level, p.progression.get_effective_strength(),
		p.progression.get_melee_damage_multiplier(),
		p.progression.get_melee_attack_power(), p.inventory.get_distinct_count()])

	p.global_position = ROOM_ANCHORS[2]
	await _pause(1.2)
	boss_started = Time.get_ticks_msec()
	var boss: DungeonBoss = dungeon.get_rooms()[2].get_enemies()[0] as DungeonBoss
	var node2: BasicMeleeShadow = p.shadow_summoner.get_active_node()
	var shadow_hp_before: float = node2.health_component.current_health if node2 != null else 0.0
	await _fight_boss(p, boss)
	var boss_seconds: float = (Time.get_ticks_msec() - boss_started) / 1000.0
	await _pause(1.5)

	var summary: RunSummary = current_scene.get_node("RunSummary")
	print("  boss down in %.0fs" % boss_seconds)
	print("  run to summary: %.0fs of simulated play" % (
		(Time.get_ticks_msec() - started) / 1000.0))
	print("[SUMMARY PANEL A]\n%s" % summary.get_lines())
	if node2 != null and is_instance_valid(node2):
		print("  shadow took %.0f damage during the boss" % (
			shadow_hp_before - node2.health_component.current_health))
	else:
		print("  the shadow did not survive the boss")

	_record(summary.is_open(), "A1) the run reaches its summary")
	_record(stats.bosses_defeated == 1 and stats.enemies_defeated == 5,
		"A2) with every enemy accounted for (%d + %d boss)" % [
			stats.enemies_defeated, stats.bosses_defeated])
	_record(stats.get_player_xp_earned() >= 280,
		"A3) and the player took most of the XP (%d of 325 available)" %
			stats.get_player_xp_earned())
	_record(p.progression.current_level >= 3,
		"A4) reaching Lv.%d" % p.progression.current_level)
	_record(stats.items_picked_up > 0, "A5) picking up %d items" % stats.items_picked_up)
	_record(stats.shadows_extracted > 0,
		"A6) and extracting %d shadow(s)" % stats.shadows_extracted)

	summary.press_continue()
	await _pause(0.4)
	p.hurtbox.set_invulnerable(false)
	p.global_position = EXIT_POS
	await _pause(0.5)
	dungeon.exit_portal.activate()
	await _pause(1.5)
	_record(current_scene.scene_file_path == HUB, "A7) and the portal returns to the hub")


# --- RUN B: the shadow's run ----------------------------------------------------------------

func _run_b() -> void:
	print("")
	print("############ RUN B - the shadow takes the kills ############")
	var carried: Dictionary = _snapshot(current_scene.get_node("Player"))
	await _enter_dungeon()
	var dungeon: DungeonController = current_scene as DungeonController
	var p: Player = current_scene.get_node("Player")
	p.hurtbox.set_invulnerable(true)
	var stats: DungeonRunStats = dungeon.get_node("DungeonRunStats")
	_record(_same(_snapshot(p), carried), "B1) the second run starts with run A's character")

	var shadow: ShadowInstance = p.shadows.get_shadows()[0]
	var level_before: int = shadow.level
	var xp_before: int = shadow.current_xp
	var node: BasicMeleeShadow = p.shadow_summoner.get_active_node()
	if node == null:
		node = p.shadow_summoner.summon(shadow.instance_id)
		await _pause(0.5)
	node.hurtbox.set_invulnerable(true)
	var started: int = Time.get_ticks_msec()

	var shadow_kills: int = 0
	var expected_player_xp: int = 0
	for index in 2:
		p.global_position = ROOM_ANCHORS[index]
		await _pause(0.8)
		for enemy in dungeon.get_rooms()[index].get_enemies():
			if enemy.has_died():
				continue
			var reward: int = enemy.get_xp_reward()
			# The player stands with the fight before ordering: the leash is
			# measured from the PLAYER, so an order given from across the room
			# is correctly refused and the shadow never engages.
			p.global_position = enemy.global_position + Vector3(0, 0, 3.5)
			node.global_position = enemy.global_position + Vector3(0, 0, 2.2)
			await _pause(0.4)
			# Ordered, softened by the shadow, finished by the shadow.
			node.set_manual_target(enemy)
			var engaged: bool = await _wait_for_damage(enemy, 25.0)
			(enemy.get_node("Hurtbox") as Hurtbox).receive_hit(DamageInfo.new(1000000.0, node))
			await _pause(0.5)
			if enemy.get_killer() == node and engaged:
				shadow_kills += 1
				expected_player_xp += reward - int(round(
					reward * PlayerProgression.SHADOW_KILL_SHARE))
		await _take_everything(p, dungeon)

	print("  shadow finished %d kills" % shadow_kills)
	print("  shadow Lv.%d -> Lv.%d (%d -> %d XP)" % [
		level_before, shadow.level, xp_before, shadow.current_xp])
	_record(shadow_kills >= 4, "B2) the shadow landed %d final blows" % shadow_kills)
	_record(shadow.level > level_before or shadow.current_xp > xp_before,
		"B3) and gained levels or XP for them (Lv.%d, %d XP)" % [
			shadow.level, shadow.current_xp])
	_record(stats.get_player_xp_earned() == expected_player_xp,
		"B4) the player took exactly the 30%% share: %d, expected %d" % [
			stats.get_player_xp_earned(), expected_player_xp])

	p.global_position = ROOM_ANCHORS[2]
	await _pause(1.2)
	var boss: DungeonBoss = dungeon.get_rooms()[2].get_enemies()[0] as DungeonBoss
	node.hurtbox.set_invulnerable(false)
	var boss_started: int = Time.get_ticks_msec()
	node.set_manual_target(boss)
	await _fight_boss(p, boss)
	print("  boss down in %.0fs with the shadow committed" % (
		(Time.get_ticks_msec() - boss_started) / 1000.0))
	print("  run to summary: %.0fs of simulated play" % (
		(Time.get_ticks_msec() - started) / 1000.0))
	await _pause(1.5)
	var summary: RunSummary = current_scene.get_node("RunSummary")
	print("[SUMMARY PANEL B]\n%s" % summary.get_lines())
	_record(summary.get_lines().contains("XP ottenuta: %d" % stats.get_player_xp_earned()),
		"B5) and the panel reports the player's share, not the enemies' worth")
	_record(shadow.level >= level_before,
		"B6) the shadow ended at Lv.%d" % shadow.level)

	summary.press_continue()
	await _pause(0.4)
	p.hurtbox.set_invulnerable(false)
	p.global_position = EXIT_POS
	await _pause(0.5)
	dungeon.exit_portal.activate()
	await _pause(1.5)
	_record(current_scene.scene_file_path == HUB, "B7) run B returns to the hub")


# --- RUN C: it goes wrong, and recovers -------------------------------------------------------

func _run_c() -> void:
	print("")
	print("############ RUN C - failure and recovery ############")
	var real_chance: float = _shadow_data.extraction_chance
	await _enter_dungeon()
	var dungeon: DungeonController = current_scene as DungeonController
	var p: Player = current_scene.get_node("Player")
	p.hurtbox.set_invulnerable(true)
	var before: Dictionary = _snapshot(p)

	# 1) an extraction that fails
	p.global_position = ROOM_ANCHORS[0]
	await _pause(0.8)
	var enemy: RoomCombatant = dungeon.get_rooms()[0].get_enemies()[0]
	await _kill(p, enemy)
	await _pause(0.5)
	var remnant: ShadowRemnant = _first_remnant(dungeon)
	var held: int = p.shadows.get_count()
	var stats: DungeonRunStats = dungeon.get_node("DungeonRunStats")
	_shadow_data.extraction_chance = 0.0
	p.global_position = remnant.global_position + Vector3(0, 0, 0.45)
	await _pause(0.4)
	remnant.attempt_extraction()
	await _pause(remnant.extraction_duration + 0.5)
	_shadow_data.extraction_chance = real_chance
	_record(p.shadows.get_count() == held and stats.shadows_extracted == 0,
		"C1) a failed extraction adds nothing, and the tally stays at %d" %
			stats.shadows_extracted)
	_record(remnant == null or not is_instance_valid(remnant) or remnant.has_been_attempted(),
		"C2) and the remnant is spent either way")

	# 2) the shadow dies
	var shadow: ShadowInstance = p.shadows.get_shadows()[0]
	var node: BasicMeleeShadow = p.shadow_summoner.get_active_node()
	if node == null:
		node = p.shadow_summoner.summon(shadow.instance_id)
		await _pause(0.5)
	var s_level: int = shadow.level
	var s_xp: int = shadow.current_xp
	node.hurtbox.set_invulnerable(false)
	node.health_component.take_damage(DamageInfo.new(1000000.0))
	await _pause(1.4)
	_record(not p.shadow_summoner.has_active_shadow()
			and p.shadows.has_shadow(shadow.instance_id)
			and shadow.level == s_level and shadow.current_xp == s_xp,
		"C3) the shadow dies without costing its Lv.%d or its %d XP" % [s_level, s_xp])
	_record(p.shadow_summoner.summon(shadow.instance_id) != null,
		"C4) and can be summoned again")
	await _pause(0.5)

	# 3) the player dies
	p.hurtbox.set_invulnerable(false)
	p.health_component.take_damage(DamageInfo.new(1000000.0))
	await _pause(0.4)
	_record(dungeon.get_state() == DungeonController.DungeonState.FAILED, "C5) the run fails")
	await _pause(2.8)
	var p2: Player = current_scene.get_node("Player")
	await _pause(0.5)
	# XP is allowed to have grown between the snapshot and the death; what must
	# not change is anything the death could have taken away.
	var after: Dictionary = _snapshot(p2)
	var kept: bool = after["shadows"] == before["shadows"] \
		and after["items"] == before["items"] and after["equipped"] == before["equipped"] \
		and after["str"] == before["str"] and after["xp"] >= before["xp"]
	_record(kept, "C6) and the restart keeps the character (Lv.%d, %d XP, %s)" % [
		after["level"], after["xp"], after["shadows"]])
	var d2: DungeonController = current_scene as DungeonController
	var alive: int = 0
	for room in d2.get_rooms():
		for candidate in room.get_enemies():
			if not candidate.has_died():
				alive += 1
	_record(alive == 6, "C7) against a fresh dungeon (%d alive)" % alive)

	# 4) and finish it anyway
	p2.hurtbox.set_invulnerable(true)
	var node2: BasicMeleeShadow = p2.shadow_summoner.summon(
		p2.shadows.get_shadows()[0].instance_id)
	await _pause(0.5)
	if node2 != null:
		node2.hurtbox.set_invulnerable(true)
	var started: int = Time.get_ticks_msec()
	for index in 3:
		p2.global_position = ROOM_ANCHORS[index]
		await _pause(0.9)
		for candidate in d2.get_rooms()[index].get_enemies():
			if not candidate.has_died():
				await _kill(p2, candidate, 240.0)
				await _pause(0.3)
	await _pause(1.5)
	print("  recovery run to summary: %.0fs of simulated play" % (
		(Time.get_ticks_msec() - started) / 1000.0))
	_record(d2.get_state() == DungeonController.DungeonState.COMPLETED,
		"C8) the dungeon completes after the death")
	var summary: RunSummary = current_scene.get_node("RunSummary")
	print("[SUMMARY PANEL C]\n%s" % summary.get_lines())
	summary.press_continue()
	await _pause(0.4)
	p2.hurtbox.set_invulnerable(false)
	p2.global_position = EXIT_POS
	await _pause(0.5)
	d2.exit_portal.activate()
	await _pause(1.5)
	_record(current_scene.scene_file_path == HUB, "C9) and the portal still returns to the hub")
	_record(is_equal_approx(_shadow_data.extraction_chance, 0.7),
		"C10) the real extraction chance is restored to %.2f" % _shadow_data.extraction_chance)


# --- helpers -----------------------------------------------------------------------------------

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
	await _pause(1.5)


func _fight_boss(p: Player, boss: DungeonBoss) -> void:
	var elapsed: float = 0.0
	var reapproach: float = 3.4 / p.movement_speed
	var reapproach_left: float = 0.0
	while elapsed < 400.0 and not boss.has_died():
		var winding_up: bool = boss.get_attack_phase() in [
			BossCombat.Phase.TELEGRAPH, BossCombat.Phase.ACTIVE,
			BossCombat.Phase.BETWEEN_HITS]
		if winding_up:
			var away: Vector3 = p.global_position - boss.global_position
			away.y = 0.0
			if away.length() < 0.001:
				away = Vector3.BACK
			p.global_position = boss.global_position + away.normalized() * 5.0
			reapproach_left = reapproach
		elif reapproach_left > 0.0:
			reapproach_left -= 1.0 / 60.0
		elif p.combat.get_state() == PlayerCombat.State.IDLE:
			p.global_position = boss.global_position + Vector3(0, 0, STRIKE_RANGE)
			p.camera_rig.rotation.y = 0.0
			p.camera_rig.attack_light_pressed.emit()
		await physics_frame
		elapsed += 1.0 / 60.0


## Waits until the shadow has actually hurt the target, and says whether it did.
## It matters: XP only flows from combatants the player's side really engaged,
## so a kill dealt to something the shadow never touched pays nobody — which is
## M6.1 working, not a split gone missing.
func _wait_for_damage(enemy: RoomCombatant, budget: float) -> bool:
	var health: HealthComponent = enemy.get_node("HealthComponent")
	var full: float = health.current_health
	var waited: float = 0.0
	while waited < budget and is_equal_approx(health.current_health, full):
		await physics_frame
		waited += 1.0 / 60.0
	return health.current_health < full


func _take_everything(p: Player, from: Node) -> void:
	for item in _all(from, true):
		if is_instance_valid(item):
			p.global_position = item.global_position + Vector3(0, 0, 0.4)
			await _pause(0.3)
			item.pick_up()
			await _pause(0.2)
	for remnant in _all(from, false):
		if is_instance_valid(remnant) and not remnant.has_been_attempted():
			p.global_position = remnant.global_position + Vector3(0, 0, 0.45)
			await _pause(0.35)
			remnant.attempt_extraction()
			await _pause(remnant.extraction_duration + 0.35)


func _all(from: Node, items: bool) -> Array:
	var found: Array = []
	if items and from is WorldItem:
		found.append(from)
	elif not items and from is ShadowRemnant:
		found.append(from)
	for child in from.get_children():
		found.append_array(_all(child, items))
	return found


func _first_remnant(from: Node) -> ShadowRemnant:
	var all: Array = _all(from, false)
	for remnant in all:
		if not remnant.has_been_attempted():
			return remnant
	return null


func _snapshot(player: Player) -> Dictionary:
	var shadows: Array[String] = []
	for shadow in player.shadows.get_shadows():
		shadows.append("%s:%d/%d" % [shadow.get_short_id(), shadow.level, shadow.current_xp])
	return {
		"level": player.progression.current_level,
		"xp": player.progression.get_total_xp(),
		"str": player.progression.strength,
		"items": player.inventory.get_distinct_count(),
		"equipped": player.equipment.get_occupied_slots().size(),
		"shadows": shadows,
	}


func _same(a: Dictionary, b: Dictionary) -> bool:
	for key in a:
		if a[key] != b[key]:
			print("      [diff] %s: %s vs %s" % [key, a[key], b[key]])
			return false
	return true


func _kill(player: Player, target: RoomCombatant, budget: float = 90.0) -> void:
	var elapsed: float = 0.0
	while elapsed < budget and not target.has_died():
		if player.combat.get_state() == PlayerCombat.State.IDLE:
			player.global_position = target.global_position + Vector3(0, 0, STRIKE_RANGE)
			player.camera_rig.rotation.y = 0.0
			player.camera_rig.attack_light_pressed.emit()
		await physics_frame
		elapsed += 1.0 / 60.0
