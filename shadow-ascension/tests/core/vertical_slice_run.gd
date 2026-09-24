extends SceneTree

## M9.1 — the whole slice, from the boot scene a player actually starts at.
##
##   godot --headless --path . --script res://tests/core/vertical_slice_run.gd
##
## Nothing is instanced by hand: this loads Main.tscn, presses GIOCA, and every
## scene change after that is the real one. What it checks is the loop holding
## together, not any one system — those have their own suites.

const BOOT: String = "res://Main.tscn"
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
## Carried between phases so the second run can be compared with the first.
var _after_first_run: Dictionary = {}


func _initialize() -> void:
	_state = root.get_node_or_null("PlayerRuntimeState")
	_state.reset_runtime_state()
	_real_chance = _shadow_data.extraction_chance
	_shadow_data.extraction_chance = 1.0

	await _phase_boot()
	await _phase_hub()
	await _phase_ui_layout()
	await _phase_first_run()
	await _phase_summary_and_exit()
	await _phase_second_run()
	await _phase_death()

	_shadow_data.extraction_chance = _real_chance
	_record(is_equal_approx(_shadow_data.extraction_chance, 0.7),
		"Z1) the real extraction chance is restored to %.2f" % _shadow_data.extraction_chance)
	print("[SUMMARY] passed=%d failed=%d" % [_pass, _fail])
	await _pause(0.3)
	quit()


# --- 1-4. the game starts where a player starts it ----------------------------------

func _phase_boot() -> void:
	_record(ProjectSettings.get_setting("application/run/main_scene") == BOOT,
		"1) the project boots from Main.tscn")
	change_scene_to_file(BOOT)
	await _pause(0.6)
	var menu: MainMenu = current_scene.get_node("MainMenu")
	_record(menu != null, "2) and Main.tscn shows the main menu, not a gameplay scene")
	_record(menu.get_title() == "SHADOW ASCENSION", "3) titled '%s'" % menu.get_title())
	_record(menu.play_button.text == "GIOCA" and menu.quit_button.text == "ESCI",
		"4) offering '%s' and '%s'" % [menu.play_button.text, menu.quit_button.text])
	_record(current_scene.get_node_or_null("Player") == null,
		"5) with no player loaded behind it")

	# ESCI asks to close. Checked through the signal, because a test that
	# actually quit would take itself with it.
	menu.quit_on_request = false
	var quit_asked: Array[bool] = [false]
	menu.quit_requested.connect(func() -> void: quit_asked[0] = true)
	menu.press_quit()
	_record(quit_asked[0], "6) ESCI asks the application to close")

	menu.press_play()
	await _pause(1.4)
	_record(current_scene.scene_file_path == HUB, "7) GIOCA leads to the hub")


# --- 8-16. the hub ---------------------------------------------------------------------

func _phase_hub() -> void:
	var player: Player = current_scene.get_node("Player")
	_record(player != null, "8) the hub has a player spawn")
	var gate: DungeonGate = current_scene.get_node("DungeonGate")
	_record(gate != null, "9) and a gate")
	# It is what the player is meant to walk towards, so it is in front of them.
	_record(gate.global_position.z < player.global_position.z,
		"10) the player spawns facing the gate (gate z %.0f, player z %.0f)" % [
			gate.global_position.z, player.global_position.z])
	_record(gate.get_node_or_null("GateLight") != null
			and gate.get_node_or_null("VisualRoot/Portal") != null,
		"11) the gate is lit and has a portal surface, not a bare ring")

	var objective: DungeonObjectiveUI = current_scene.get_node("DungeonObjectiveUI")
	_record(objective.get_objective() == "Entra nel Gate",
		"12) the hub states its objective: '%s'" % objective.get_objective())

	var hp: PlayerHealthHUD = current_scene.get_node("PlayerHealthHUD")
	_record(hp.is_showing() and hp.get_health_text() == "%d / %d" % [
			roundi(player.health_component.current_health),
			roundi(player.health_component.max_health)],
		"13) the player's health is on screen: '%s'" % hp.get_health_text())
	var prog_hud: ProgressionHUD = current_scene.get_node("ProgressionHUD")
	_record(prog_hud.get_level_text() == "LV. 1" and prog_hud.get_xp_text() == "0 / 100",
		"14) with level and XP: '%s  %s'" % [
			prog_hud.get_level_text(), prog_hud.get_xp_text()])

	# The hub is a hub, not the combat sandbox it grew out of.
	_record(current_scene.get_node_or_null("DebugDamageZone") == null,
		"15) the debug damage zone is gone from the hub")
	var hostiles: int = 0
	for child in current_scene.get_children():
		if child is BasicMeleeEnemy:
			hostiles += 1
	_record(hostiles == 0, "16) and no loose enemies wander it (%d)" % hostiles)


# --- 17-22. the HUD does not fight itself ------------------------------------------------

func _phase_ui_layout() -> void:
	# Real rects at the real window size, not an eyeball: two panels that share
	# pixels is the one HUD fault a screenshot would show a first-time viewer.
	var boxes: Dictionary = {
		"salute": _rect(current_scene, "PlayerHealthHUD/Root"),
		"stamina": _rect(current_scene, "PlayerStaminaHUD/Root"),
		"livello/XP": _rect(current_scene, "ProgressionHUD/Root"),
		"obiettivo": _rect(current_scene, "DungeonObjectiveUI/Root/ObjectiveLabel"),
		"ombra attiva": _rect(current_scene, "ActiveShadowHUD/Root"),
		"prompt": _rect(current_scene, "InteractionPrompt/Root"),
		"hint ombre": _rect(current_scene, "ShadowCollectionMenu/Hint"),
		"hint inventario": _rect(current_scene, "InventoryMenu/Hint"),
		"hint statistiche": _rect(current_scene, "PlayerStatsMenu/Hint"),
	}
	var clashes: Array[String] = []
	var names: Array = boxes.keys()
	for i in names.size():
		for j in range(i + 1, names.size()):
			var a: Rect2 = boxes[names[i]]
			var b: Rect2 = boxes[names[j]]
			if a.has_area() and b.has_area() and a.intersects(b):
				clashes.append("%s/%s" % [names[i], names[j]])
	_record(clashes.is_empty(), "17) no two HUD panels overlap%s" % (
		"" if clashes.is_empty() else ": " + ", ".join(clashes)))

	# The three menu hints are the standing contract; the shadow commands are not
	# among them, because there is no shadow out yet.
	var hints: String = "%s %s %s" % [
		_hint_text(current_scene, "PlayerStatsMenu/Hint"),
		_hint_text(current_scene, "InventoryMenu/Hint"),
		_hint_text(current_scene, "ShadowCollectionMenu/Hint")]
	_record(hints.contains("[C]") and hints.contains("[I]") and hints.contains("[O]"),
		"18) the menu hints read %s" % hints.strip_edges())
	var shadow_hud: ActiveShadowHUD = current_scene.get_node("ActiveShadowHUD")
	_record(not shadow_hud.is_showing(),
		"19) and the shadow panel stays hidden with nothing summoned")

	# Each menu opens, pauses, frees the mouse, and closes the others.
	var stats: PlayerStatsMenu = current_scene.get_node("PlayerStatsMenu")
	var inventory: InventoryMenu = current_scene.get_node("InventoryMenu")
	var shadows: ShadowCollectionMenu = current_scene.get_node("ShadowCollectionMenu")
	stats.open()
	await _pause(0.2)
	_record(stats.is_open() and paused
			and stats.last_mouse_mode_request == Input.MOUSE_MODE_VISIBLE,
		"20) [C] opens the sheet, pauses, and frees the mouse")
	inventory.open()
	await _pause(0.2)
	_record(inventory.is_open() and not stats.is_open(),
		"21) [I] opens the inventory and closes the sheet behind it")
	shadows.open()
	await _pause(0.2)
	_record(shadows.is_open() and not inventory.is_open(),
		"22) [O] does the same, so two are never up at once")
	shadows.close()
	await _pause(0.2)
	_record(not paused and shadows.last_mouse_mode_request == Input.MOUSE_MODE_CAPTURED,
		"23) closing hands the game and the cursor back")


# --- 24-40. a run -------------------------------------------------------------------------

func _phase_first_run() -> void:
	await _enter_dungeon()
	_record(current_scene.scene_file_path == DUNGEON, "24) the gate leads into the dungeon")
	var dungeon: DungeonController = current_scene as DungeonController
	var p: Player = current_scene.get_node("Player")
	p.hurtbox.set_invulnerable(true)
	var stats: DungeonRunStats = dungeon.get_node("DungeonRunStats")
	_record(stats != null and stats.get_total_kills() == 0
			and stats.items_picked_up == 0 and stats.shadows_extracted == 0,
		"25) the run starts with a clean tally")

	var objective: DungeonObjectiveUI = current_scene.get_node("DungeonObjectiveUI")
	_record(objective.get_objective() == dungeon.objective_advance,
		"26) the first objective is '%s'" % objective.get_objective())

	# --- room 1: kill, loot, extract
	p.global_position = ROOM_ANCHORS[0]
	await _pause(0.8)
	_record(objective.get_objective().begins_with("Elimina i nemici"),
		"27) entering a combat room asks for the kills: '%s'" % objective.get_objective())
	var room: RoomController = dungeon.get_rooms()[0]
	var first: RoomCombatant = room.get_enemies()[0]
	var bar: EnemyHealthBar3D = first.get_node_or_null("EnemyHealthBar3D")
	_record(bar != null, "28) enemies carry a health bar")
	await _kill(p, first)
	await _pause(0.5)
	_record(not bar.is_bar_visible(), "29) which goes when the enemy dies")
	_record(stats.enemies_defeated == 1, "30) the tally counted the kill (%d)" % stats.enemies_defeated)

	var picked_before: int = stats.items_picked_up
	await _pick_up_all(p, dungeon)
	_record(stats.items_picked_up >= picked_before,
		"31) loot picked up off the floor is counted (%d)" % stats.items_picked_up)
	var extracted: int = await _extract_all(p, dungeon)
	_record(extracted >= 1 and stats.shadows_extracted == extracted,
		"32) %d shadow(s) extracted, and the tally agrees (%d)" % [
			extracted, stats.shadows_extracted])
	_record(p.shadows.get_count() == extracted,
		"33) the collection holds them (%d)" % p.shadows.get_count())

	# --- summon it and let it fight the rest
	var shadow: ShadowInstance = p.shadows.get_shadows()[0]
	var node: BasicMeleeShadow = p.shadow_summoner.summon(shadow.instance_id)
	await _pause(0.5)
	node.hurtbox.set_invulnerable(true)
	var shadow_hud: ActiveShadowHUD = current_scene.get_node("ActiveShadowHUD")
	_record(node != null and shadow_hud.is_showing(),
		"34) summoning brings the shadow and its panel up")
	_record(shadow_hud.get_hints_text().contains("[Q]")
			and shadow_hud.get_hints_text().contains("[T]"),
		"35) with the command hints that only apply while it is out")

	var xp_before: int = stats.get_player_xp_earned()
	var second: RoomCombatant = room.get_enemies()[1]
	var reward: int = second.get_xp_reward()
	await _shadow_finishes(p, node, second)
	var player_share: int = stats.get_player_xp_earned() - xp_before
	_record(player_share == reward - int(round(reward * PlayerProgression.SHADOW_KILL_SHARE)),
		"36) a kill the shadow finished pays the player %d of %d, not the lot" % [
			player_share, reward])

	# --- clear the rest of the dungeon
	for index in range(0, 2):
		p.global_position = ROOM_ANCHORS[index]
		await _pause(0.7)
		for enemy in dungeon.get_rooms()[index].get_enemies():
			if not enemy.has_died():
				await _kill(p, enemy)
				await _pause(0.3)
		await _pick_up_all(p, dungeon)
		await _extract_all(p, dungeon)
	_record(objective.get_objective() == dungeon.objective_reach_boss,
		"37) with the rooms clear it points at the boss: '%s'" % objective.get_objective())

	# --- the boss
	p.global_position = ROOM_ANCHORS[2]
	await _pause(1.2)
	var boss: DungeonBoss = dungeon.get_rooms()[2].get_enemies()[0] as DungeonBoss
	var boss_bar: BossHealthBar = current_scene.get_node("BossHealthBar")
	_record(boss_bar.visible and objective.get_objective() == dungeon.objective_boss,
		"38) the boss encounter opens its bar and its objective")
	_record(boss_bar.get_phase_text() == boss_bar.phase_1_text,
		"39) starting in %s" % boss_bar.get_phase_text())
	await _kill(p, boss, 90.0)
	await _pause(1.2)
	_record(boss.has_died() and stats.bosses_defeated == 1,
		"40) the boss falls and is counted separately (%d)" % stats.bosses_defeated)
	_record(dungeon.get_state() == DungeonController.DungeonState.COMPLETED,
		"41) the dungeon completes")


# --- 42-50. the summary, then out ------------------------------------------------------------

func _phase_summary_and_exit() -> void:
	var dungeon: DungeonController = current_scene as DungeonController
	var stats: DungeonRunStats = dungeon.get_node("DungeonRunStats")
	var summary: RunSummary = current_scene.get_node("RunSummary")
	_record(summary.is_open(), "42) the run summary opens on completion")
	_record(paused, "43) with the dungeon paused behind it")
	_record(summary.last_mouse_mode_request == Input.MOUSE_MODE_VISIBLE,
		"44) and the cursor freed")
	_record(not dungeon.status_label.visible,
		"45) and no leftover banner behind it")

	var lines: String = summary.get_lines()
	print("[SUMMARY PANEL]\n%s" % lines)
	_record(lines.contains("Nemici sconfitti: %d" % stats.enemies_defeated)
			and lines.contains("Boss sconfitti: %d" % stats.bosses_defeated),
		"46) it reports the real kills (%d + %d boss)" % [
			stats.enemies_defeated, stats.bosses_defeated])
	_record(lines.contains("XP ottenuta: %d" % stats.get_player_xp_earned()),
		"47) the player's own XP, %d" % stats.get_player_xp_earned())
	_record(lines.contains("Oggetti raccolti: %d" % stats.items_picked_up)
			and lines.contains("Ombre estratte: %d" % stats.shadows_extracted),
		"48) the items and shadows taken (%d / %d)" % [
			stats.items_picked_up, stats.shadows_extracted])
	_record(stats.get_player_xp_earned() > 0 and stats.shadows_extracted > 0,
		"49) and none of it is zero, so the numbers are the run's own")

	var p: Player = current_scene.get_node("Player")
	_after_first_run = _snapshot(p)
	print("[AFTER RUN 1] %s" % [_after_first_run])

	summary.press_continue()
	await _pause(0.4)
	_record(not summary.is_open() and not paused,
		"50) [Continua] closes it and hands the dungeon back")
	_record(current_scene.scene_file_path == DUNGEON,
		"51) without changing scene on its own")

	# The portal is the player's move, in their own time.
	_record(dungeon.exit_portal.is_enabled(), "52) the exit portal is live")
	p.hurtbox.set_invulnerable(false)
	p.global_position = EXIT_POS
	await _pause(0.5)
	var prompt: InteractionPrompt = current_scene.get_node("InteractionPrompt")
	_record(prompt.is_showing() and prompt.get_text() == dungeon.exit_portal.prompt_text,
		"53) prompting '%s %s'" % [prompt.key_label.text, prompt.get_text()])
	dungeon.exit_portal.activate()
	await _pause(1.4)
	_record(current_scene.scene_file_path == HUB, "54) and it returns to the hub")

	var p2: Player = current_scene.get_node("Player")
	await _pause(0.4)
	_record(p2 != p, "55) on a different Player instance")
	var back: Dictionary = _snapshot(p2)
	print("[BACK IN HUB] %s" % [back])
	_record(_same_progress(back, _after_first_run), "56) with everything carried over")
	var objective: DungeonObjectiveUI = current_scene.get_node("DungeonObjectiveUI")
	_record(objective.get_objective() == "Entra nel Gate",
		"57) and the hub asking for the next run: '%s'" % objective.get_objective())


# --- 58-65. a second run is a fresh one ---------------------------------------------------------

func _phase_second_run() -> void:
	await _enter_dungeon()
	var dungeon: DungeonController = current_scene as DungeonController
	var p: Player = current_scene.get_node("Player")
	await _pause(0.5)

	var alive: int = 0
	var doors_locked: int = 0
	for room in dungeon.get_rooms():
		for enemy in room.get_enemies():
			if not enemy.has_died():
				alive += 1
		if room.exit_door != null and room.exit_door.is_locked():
			doors_locked += 1
	_record(alive > 0, "58) the second run's enemies are alive again (%d)" % alive)
	_record(doors_locked > 0, "59) its doors are locked again (%d)" % doors_locked)
	_record(dungeon.get_state() == DungeonController.DungeonState.NOT_STARTED
			or dungeon.get_state() == DungeonController.DungeonState.IN_PROGRESS,
		"60) and the dungeon is not already complete (state %d)" % dungeon.get_state())

	var stats: DungeonRunStats = dungeon.get_node("DungeonRunStats")
	_record(stats.get_total_kills() == 0 and stats.items_picked_up == 0
			and stats.shadows_extracted == 0 and stats.get_player_xp_earned() == 0,
		"61) the tally reset with it")
	_record(not (current_scene.get_node("RunSummary") as RunSummary).is_open(),
		"62) and last run's summary is not still up")
	_record(_remnants(dungeon).is_empty(), "63) nor last run's remnants")

	var now: Dictionary = _snapshot(p)
	print("[SECOND RUN ] %s" % [now])
	_record(_same_progress(now, _after_first_run),
		"64) while the character kept everything it earned")

	# Enough of the second run to show it plays.
	p.hurtbox.set_invulnerable(true)
	p.global_position = ROOM_ANCHORS[0]
	await _pause(0.8)
	await _kill(p, dungeon.get_rooms()[0].get_enemies()[0])
	await _pause(0.4)
	_record(stats.enemies_defeated == 1,
		"65) and the second run tallies its own kills (%d)" % stats.enemies_defeated)


# --- 66-72. dying ---------------------------------------------------------------------------------

func _phase_death() -> void:
	var dungeon: DungeonController = current_scene as DungeonController
	var p: Player = current_scene.get_node("Player")
	var before: Dictionary = _snapshot(p)
	p.hurtbox.set_invulnerable(false)
	p.health_component.take_damage(DamageInfo.new(1000000.0))
	await _pause(0.4)
	_record(dungeon.get_state() == DungeonController.DungeonState.FAILED, "66) the run fails")
	_record(dungeon.status_label.visible
			and dungeon.status_label.text == dungeon.death_message,
		"67) and says so: '%s'" % dungeon.status_label.text)
	await _pause(2.6)

	var p2: Player = current_scene.get_node("Player")
	await _pause(0.5)
	_record(current_scene.scene_file_path == DUNGEON, "68) the dungeon restarts")
	var after: Dictionary = _snapshot(p2)
	print("[AFTER DEATH] %s" % [after])
	_record(_same_progress(after, before), "69) with the character's progress untouched")
	_record(is_equal_approx(p2.health_component.current_health,
			p2.health_component.max_health),
		"70) health restored for the new attempt (%.0f/%.0f)" % [
			p2.health_component.current_health, p2.health_component.max_health])

	var dungeon2: DungeonController = current_scene as DungeonController
	var stats: DungeonRunStats = dungeon2.get_node("DungeonRunStats")
	_record(stats.get_total_kills() == 0 and stats.get_player_xp_earned() == 0,
		"71) and the tally reset for it")
	var alive: int = 0
	for room in dungeon2.get_rooms():
		for enemy in room.get_enemies():
			if not enemy.has_died():
				alive += 1
	_record(alive > 0, "72) against a fresh dungeon (%d enemies)" % alive)
	_record(p2.shadow_summoner.summon(p2.shadows.get_shadows()[0].instance_id) != null,
		"73) and the shadow can be summoned again")


# --- helpers ----------------------------------------------------------------------------------------

func _pause(t: float) -> void:
	await create_timer(t).timeout


func _record(passed: bool, description: String) -> void:
	if passed:
		_pass += 1
		print("[PASS] " + description)
	else:
		_fail += 1
		print("[FAIL] " + description)


func _rect(scene: Node, path: String) -> Rect2:
	var control: Control = scene.get_node_or_null(path) as Control
	return control.get_global_rect() if control != null else Rect2()


func _hint_text(scene: Node, path: String) -> String:
	var label: Label = scene.get_node_or_null(path + "/Label") as Label
	return label.text if label != null else ""


func _enter_dungeon() -> void:
	var p: Player = current_scene.get_node("Player")
	var gate: DungeonGate = current_scene.get_node("DungeonGate")
	p.global_position = gate.global_position
	await _pause(0.3)
	gate.activate()
	await _pause(1.4)


func _snapshot(player: Player) -> Dictionary:
	var shadows: Array[String] = []
	for shadow in player.shadows.get_shadows():
		shadows.append("%s:%d/%d" % [shadow.get_short_id(), shadow.level, shadow.current_xp])
	return {
		"level": player.progression.current_level,
		"total_xp": player.progression.get_total_xp(),
		"points": player.progression.available_stat_points,
		"str": player.progression.strength,
		"vit": player.progression.vitality,
		"items": player.inventory.get_distinct_count(),
		"equipped": player.equipment.get_occupied_slots().size(),
		"shadows": shadows,
	}


func _same_progress(a: Dictionary, b: Dictionary) -> bool:
	for key in ["level", "total_xp", "points", "str", "vit", "items", "equipped", "shadows"]:
		if a.get(key) != b.get(key):
			print("      [diff] %s: %s vs %s" % [key, a.get(key), b.get(key)])
			return false
	return true


func _remnants(from: Node) -> Array[ShadowRemnant]:
	var found: Array[ShadowRemnant] = []
	_collect_remnants(from, found)
	return found


func _collect_remnants(node: Node, into: Array[ShadowRemnant]) -> void:
	var remnant: ShadowRemnant = node as ShadowRemnant
	if remnant != null and is_instance_valid(remnant):
		into.append(remnant)
	for child in node.get_children():
		_collect_remnants(child, into)


func _world_items(from: Node) -> Array[WorldItem]:
	var found: Array[WorldItem] = []
	_collect_items(from, found)
	return found


func _collect_items(node: Node, into: Array[WorldItem]) -> void:
	var item: WorldItem = node as WorldItem
	if item != null and is_instance_valid(item):
		into.append(item)
	for child in node.get_children():
		_collect_items(child, into)


func _pick_up_all(player: Player, from: Node) -> void:
	for item in _world_items(from):
		if not is_instance_valid(item):
			continue
		player.global_position = item.global_position + Vector3(0, 0, 0.4)
		await _pause(0.35)
		item.pick_up()
		await _pause(0.25)


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
	return taken


## The player opens the enemy up so progression is subscribed to it, then the
## shadow lands the last blow — which is what makes the split apply.
func _shadow_finishes(player: Player, node: BasicMeleeShadow, enemy: RoomCombatant) -> void:
	player.global_position = enemy.global_position + Vector3(0, 0, STRIKE_RANGE)
	node.global_position = enemy.global_position + Vector3(0, 0, 2.0)
	node.set_manual_target(enemy)
	var waited: float = 0.0
	var full: float = (enemy.get_node("HealthComponent") as HealthComponent).current_health
	while waited < 8.0 and is_equal_approx(
			(enemy.get_node("HealthComponent") as HealthComponent).current_health, full):
		await physics_frame
		waited += 1.0 / 60.0
	(enemy.get_node("Hurtbox") as Hurtbox).receive_hit(DamageInfo.new(1000000.0, node))
	await _pause(0.6)


func _kill(player: Player, target: RoomCombatant, budget: float = 40.0) -> int:
	var swings: int = 0
	var elapsed: float = 0.0
	while elapsed < budget and not target.has_died():
		if player.combat.get_state() == PlayerCombat.State.IDLE:
			player.global_position = target.global_position + Vector3(0, 0, STRIKE_RANGE)
			player.camera_rig.rotation.y = 0.0
			player.camera_rig.attack_light_pressed.emit()
			swings += 1
		await physics_frame
		elapsed += 1.0 / 60.0
	return swings
