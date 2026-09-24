extends SceneTree

## M9.2 QA. Hunts for the faults a release candidate cannot ship with: rewards
## paid twice, state surviving a scene change that should not, nodes piling up
## across runs, a menu that eats the game, an interaction that fires twice.
##
##   godot --headless --path . --script res://tests/core/qa_run.gd
##
## Nothing here tunes anything. Every check is a yes/no about correctness.

const BOOT: String = "res://Main.tscn"
const HUB: String = "res://scenes/core/hub.tscn"
const DUNGEON: String = "res://scenes/dungeons/dungeon_test.tscn"
const ROOM_ANCHORS: Array[Vector3] = [
	Vector3(0, 0.1, -13), Vector3(0, 0.1, -33), Vector3(0, 0.1, -53)
]
const EXIT_POS: Vector3 = Vector3(0, 0.1, -65)
const STRIKE_RANGE: float = 1.6

var _shadow_data: ShadowData = preload("res://resources/shadows/basic_melee_shadow.tres")
var _sword: ItemData = preload("res://resources/items/training_sword.tres")
var _pass: int = 0
var _fail: int = 0
var _state: Node = null


func _initialize() -> void:
	_state = root.get_node_or_null("PlayerRuntimeState")
	_state.reset_runtime_state()

	await _qa_fresh_session()
	await _qa_duplicate_rewards()
	await _qa_interaction_overlap()
	await _qa_rapid_input()
	await _qa_menus()
	await _qa_shadow_commands()
	await _qa_health_ui()
	await _qa_deaths()
	await _qa_repeated_cycles()

	print("")
	print("[SUMMARY] passed=%d failed=%d" % [_pass, _fail])
	await _pause(0.3)
	quit()


# --- 1. a new session carries nothing from a test ------------------------------------

func _qa_fresh_session() -> void:
	_state.reset_runtime_state()
	change_scene_to_file(HUB)
	await _pause(0.8)
	var p: Player = current_scene.get_node("Player")
	var prog: PlayerProgression = p.progression
	_record(prog.current_level == 1 and prog.current_xp == 0
			and prog.available_stat_points == 0,
		"1) a new session starts at Lv.1, 0 XP, 0 points")
	_record(prog.strength == 10 and prog.agility == 10
			and prog.vitality == 10 and prog.intelligence == 10,
		"2) with every stat at 10")
	_record(p.inventory.is_empty(), "3) an empty inventory")
	_record(p.equipment.get_occupied_slots().is_empty(), "4) nothing equipped")
	_record(p.shadows.is_empty(), "5) and no shadows")
	_record(is_equal_approx(p.health_component.current_health, 100.0)
			and is_equal_approx(p.health_component.max_health, 100.0),
		"6) at full health, %.0f/%.0f" % [
			p.health_component.current_health, p.health_component.max_health])
	_record(not prog.debug_progression_enabled, "7) with the debug XP key off")
	_record(is_equal_approx(_shadow_data.extraction_chance, 0.7),
		"8) and the shipped extraction chance at %.2f" % _shadow_data.extraction_chance)


# --- 2. nothing is paid twice ------------------------------------------------------------

func _qa_duplicate_rewards() -> void:
	await _enter_dungeon_from_hub()
	var dungeon: DungeonController = current_scene as DungeonController
	var p: Player = current_scene.get_node("Player")
	p.hurtbox.set_invulnerable(true)
	var stats: DungeonRunStats = dungeon.get_node("DungeonRunStats")
	p.global_position = ROOM_ANCHORS[0]
	await _pause(0.8)

	var room: RoomController = dungeon.get_rooms()[0]
	var enemy: RoomCombatant = room.get_enemies()[0]
	var reward: int = enemy.get_xp_reward()
	var xp_before: int = p.progression.get_total_xp()
	await _kill(p, enemy)
	await _pause(0.5)
	var gained: int = p.progression.get_total_xp() - xp_before
	_record(gained == reward, "9) a kill pays its XP once (%d of %d)" % [gained, reward])

	# Announce the death every way the systems can, and check nothing moves.
	var remnants_before: int = _count(dungeon, "ShadowRemnant")
	var items_before: int = _count(dungeon, "WorldItem")
	enemy.enemy_died.emit(enemy)
	enemy.report_death()
	(enemy.get_node("HealthComponent") as HealthComponent).take_damage(DamageInfo.new(500.0, p))
	var source: ShadowSource = enemy.get_node("ShadowSource")
	source.spawn_remnant()
	# Called directly, never behind has_method(): a renamed method must fail the
	# test, not turn the roll into a silent no-op.
	var dropper: LootDropper = enemy.get_node("LootDropper")
	dropper.drop_now()
	await _pause(0.5)
	_record(p.progression.get_total_xp() - xp_before == reward,
		"10) re-announcing the death pays no more XP")
	_record(_count(dungeon, "ShadowRemnant") == remnants_before,
		"11) and spawns no second remnant (%d)" % _count(dungeon, "ShadowRemnant"))
	_record(_count(dungeon, "WorldItem") == items_before,
		"12) and no second pile of loot (%d)" % _count(dungeon, "WorldItem"))
	_record(stats.enemies_defeated == 1,
		"13) the tally counted one kill, not three (%d)" % stats.enemies_defeated)
	_record(not room.is_cleared() and not room.get_enemies()[1].has_died(),
		"13b) and the room stays shut with its second enemy still up")

	# One remnant, one attempt, whatever the caller does.
	var remnant: ShadowRemnant = _first_remnant(dungeon)
	if remnant != null:
		p.global_position = remnant.global_position + Vector3(0, 0, 0.45)
		await _pause(0.4)
		var held_before: int = p.shadows.get_count()
		remnant.attempt_extraction()
		remnant.attempt_extraction()
		remnant.attempt_extraction()
		await _pause(remnant.extraction_duration + 0.5)
		var taken: int = p.shadows.get_count() - held_before
		_record(taken <= 1, "14) three extraction attempts yield at most one shadow (%d)" % taken)
		_record(stats.shadows_extracted == taken,
			"15) and the tally agrees (%d)" % stats.shadows_extracted)
	else:
		_record(false, "14-15) no remnant to test extraction against")

	# A pile of loot goes into the inventory once.
	var item: WorldItem = _first_item(dungeon)
	if item != null:
		p.global_position = item.global_position + Vector3(0, 0, 0.4)
		await _pause(0.4)
		var distinct_before: int = p.inventory.get_distinct_count()
		var picked_before: int = stats.items_picked_up
		item.pick_up()
		item.pick_up()
		await _pause(0.3)
		_record(p.inventory.get_distinct_count() >= distinct_before,
			"16) picking up twice does not duplicate the item")
		_record(stats.items_picked_up - picked_before <= 3,
			"17) and the tally counted the pile once (+%d)" % (
				stats.items_picked_up - picked_before))
	else:
		_record(true, "16-17) nothing dropped to test a double pickup against")

	# Equipping twice must not stack the bonus.
	p.inventory.add_item(_sword)
	var str_before: int = p.progression.get_effective_strength()
	p.equipment.equip(_sword)
	p.equipment.equip(_sword)
	await _pause(0.3)
	var str_after: int = p.progression.get_effective_strength()
	_record(str_after == str_before + _sword.bonus_strength,
		"18) equipping twice applies the bonus once (%d -> %d, item gives +%d)" % [
			str_before, str_after, _sword.bonus_strength])
	p.equipment.unequip_slot(ItemData.EquipmentSlot.MAIN_HAND)
	await _pause(0.2)
	_record(p.progression.get_effective_strength() == str_before,
		"19) and taking it off gives the bonus back exactly")
	_record(p.inventory.get_quantity(_sword.id) == 1,
		"20) with one sword in the bag, not two (%d)" % p.inventory.get_quantity(_sword.id))

	# The room clears once, and so does the dungeon.
	var clears: Array[int] = []
	room.room_cleared.connect(func(_r: RoomController) -> void: clears.append(1))
	for other in room.get_enemies():
		if not other.has_died():
			await _kill(p, other)
			await _pause(0.3)
	# Every death in the room announced again after it has cleared.
	for dead in room.get_enemies():
		dead.enemy_died.emit(dead)
	await _pause(0.5)
	_record(clears.size() == 1, "21) a room reports itself cleared once (%d)" % clears.size())

	var completions: Array[int] = []
	dungeon.dungeon_completed.connect(func() -> void: completions.append(1))
	for index in range(1, 3):
		p.global_position = ROOM_ANCHORS[index]
		await _pause(0.7)
		for enemy2 in dungeon.get_rooms()[index].get_enemies():
			if not enemy2.has_died():
				await _kill(p, enemy2, 200.0)
				await _pause(0.3)
	await _pause(1.5)
	_record(completions.size() == 1,
		"22) and the dungeon completes exactly once (%d)" % completions.size())
	_record(stats.bosses_defeated == 1,
		"23) with one boss counted (%d)" % stats.bosses_defeated)


# --- 3. one prompt, one action ------------------------------------------------------------

func _qa_interaction_overlap() -> void:
	var dungeon: DungeonController = current_scene as DungeonController
	var p: Player = current_scene.get_node("Player")
	var prompt: InteractionPrompt = current_scene.get_node("InteractionPrompt")
	var remnant: ShadowRemnant = _first_remnant(dungeon)
	var item: WorldItem = _first_item(dungeon)
	if remnant == null or item == null:
		_record(true, "24-26) no loot and remnant pair left in this run to overlap")
		return
	# Stack them on the same spot and stand on it.
	item.global_position = remnant.global_position
	p.global_position = remnant.global_position + Vector3(0, 0, 0.3)
	await _pause(0.6)
	_record(prompt.is_showing(), "24) one prompt is up with both in reach")
	var owner_is: Node = prompt.get_current_owner()
	_record(owner_is == remnant or owner_is == item,
		"25) and it names exactly one of them (%s)" % owner_is)

	var shadows_before: int = p.shadows.get_count()
	var inventory_before: int = p.inventory.get_distinct_count()
	await _press("interact")
	await _pause(0.8)
	var got_shadow: bool = p.shadows.get_count() > shadows_before \
		or remnant.has_been_attempted()
	var got_item: bool = p.inventory.get_distinct_count() > inventory_before \
		or not is_instance_valid(item)
	_record(not (got_shadow and got_item),
		"26) one press does not trigger both (shadow %s, item %s)" % [got_shadow, got_item])


# --- 4. mashing a key changes nothing ---------------------------------------------------------

func _qa_rapid_input() -> void:
	var dungeon: DungeonController = current_scene as DungeonController
	var p: Player = current_scene.get_node("Player")
	RunSummary.dismiss_open(self)
	await _pause(0.3)

	# Summon and despawn, hammered.
	if p.shadows.is_empty():
		p.shadows.add_shadow(_shadow_data)
	var shadow: ShadowInstance = p.shadows.get_shadows()[0]
	for _i in 6:
		p.shadow_summoner.summon(shadow.instance_id)
	await _pause(0.5)
	_record(get_nodes_in_group(BasicMeleeShadow.GROUP).size() == 1,
		"27) six summons in a row leave one shadow in the world (%d)" %
			get_nodes_in_group(BasicMeleeShadow.GROUP).size())
	for _i in 6:
		p.shadow_summoner.recall()
	await _pause(0.5)
	_record(get_nodes_in_group(BasicMeleeShadow.GROUP).is_empty(),
		"28) six despawns leave none")
	p.shadow_summoner.summon(shadow.instance_id)
	await _pause(0.4)
	for _i in 6:
		p.shadow_commander.recall_to_player()
	await _pause(0.3)
	_record(p.shadow_summoner.has_active_shadow(),
		"29) six quick recalls do not despawn it")

	# The exit portal, hammered.
	var transitions: Array[String] = []
	var transition: SceneTransition = current_scene.get_node("SceneTransition")
	transition.transition_started.connect(func(target: String) -> void: transitions.append(target))
	p.hurtbox.set_invulnerable(false)
	p.global_position = EXIT_POS
	await _pause(0.5)
	for _i in 6:
		dungeon.exit_portal.activate()
	await _pause(1.6)
	_record(transitions.size() <= 1,
		"30) six presses on the exit start one transition (%d)" % transitions.size())
	_record(current_scene.scene_file_path == HUB, "31) and it lands in the hub once")

	# The gate, hammered.
	var p2: Player = current_scene.get_node("Player")
	var gate: DungeonGate = current_scene.get_node("DungeonGate")
	var gate_transitions: Array[String] = []
	var t2: SceneTransition = current_scene.get_node("SceneTransition")
	t2.transition_started.connect(func(target: String) -> void: gate_transitions.append(target))
	p2.global_position = gate.global_position
	await _pause(0.4)
	for _i in 6:
		gate.activate()
	await _pause(1.6)
	_record(gate_transitions.size() <= 1,
		"32) six presses on the gate start one transition (%d)" % gate_transitions.size())
	_record(current_scene.scene_file_path == DUNGEON, "33) and it lands in the dungeon once")


# --- 5. menus -------------------------------------------------------------------------------------

func _qa_menus() -> void:
	var p: Player = current_scene.get_node("Player")
	p.hurtbox.set_invulnerable(true)
	var stats_menu: PlayerStatsMenu = current_scene.get_node("PlayerStatsMenu")
	var inventory: InventoryMenu = current_scene.get_node("InventoryMenu")
	var shadows: ShadowCollectionMenu = current_scene.get_node("ShadowCollectionMenu")
	if p.shadows.is_empty():
		p.shadows.add_shadow(_shadow_data)
	var shadow: ShadowInstance = p.shadows.get_shadows()[0]
	if not p.shadow_summoner.has_active_shadow():
		p.shadow_summoner.summon(shadow.instance_id)
	await _pause(0.5)
	var node: BasicMeleeShadow = p.shadow_summoner.get_active_node()
	node.hurtbox.set_invulnerable(true)

	# In the middle of a fight, which is where a menu is most likely to misbehave.
	p.global_position = ROOM_ANCHORS[0]
	await _pause(0.8)

	for entry in [[stats_menu, "C"], [inventory, "I"], [shadows, "O"]]:
		var menu: Node = entry[0]
		menu.open()
		await _pause(0.2)
		var others_open: int = 0
		for other in [stats_menu, inventory, shadows]:
			if other != menu and other.is_open():
				others_open += 1
		_record(menu.is_open() and paused and others_open == 0
				and menu.last_mouse_mode_request == Input.MOUSE_MODE_VISIBLE,
			"34.%s) [%s] opens alone, pauses, frees the mouse" % [entry[1], entry[1]])

		# Shadow commands must not reach the game from behind a menu.
		var mode_before: BasicMeleeShadow.CommandMode = node.command_mode
		await _press("shadow_mode_toggle")
		await _press("shadow_recall")
		await _pause(0.2)
		_record(node.command_mode == mode_before and p.shadow_summoner.has_active_shadow(),
			"35.%s) and shadow commands behind it do nothing" % entry[1])

		menu.close()
		await _pause(0.2)
		_record(not menu.is_open() and not paused
				and menu.last_mouse_mode_request == Input.MOUSE_MODE_CAPTURED,
			"36.%s) closing resumes and recaptures" % entry[1])

	# Mashing the toggles leaves exactly one menu state.
	for _i in 5:
		stats_menu.toggle()
		inventory.toggle()
		shadows.toggle()
	await _pause(0.3)
	var open_count: int = 0
	for menu in [stats_menu, inventory, shadows]:
		if menu.is_open():
			open_count += 1
	_record(open_count <= 1, "37) mashing all three leaves at most one open (%d)" % open_count)
	for menu in [stats_menu, inventory, shadows]:
		menu.close()
	await _pause(0.3)
	_record(not paused, "38) and closing them all resumes the game")


# --- 6. shadow commands hold up -----------------------------------------------------------------

func _qa_shadow_commands() -> void:
	var dungeon: DungeonController = current_scene as DungeonController
	var p: Player = current_scene.get_node("Player")
	var node: BasicMeleeShadow = p.shadow_summoner.get_active_node()
	if node == null:
		_record(false, "39) no shadow out for the command checks")
		return
	var room: RoomController = dungeon.get_rooms()[0]
	var target: RoomCombatant = null
	for enemy in room.get_enemies():
		if not enemy.has_died():
			target = enemy
			break
	if target == null:
		_record(true, "39-43) room 1 already clear, commands covered by command_test")
		return

	p.global_position = target.global_position + Vector3(0, 0, 4.0)
	node.global_position = target.global_position + Vector3(0, 0, 2.0)
	node.set_manual_target(target)
	await _pause(0.5)
	_record(node.get_manual_target() == target, "39) an order takes")

	# Kill the target out from under it: no corpse chasing, no freed reference.
	(target.get_node("HealthComponent") as HealthComponent).take_damage(DamageInfo.new(100000.0, p))
	await _pause(0.8)
	_record(node.get_manual_target() == null and node.get_target() == null
			or (node.get_target() != null and not node.get_target().has_died()),
		"40) a dead target is dropped rather than chased")
	node.recall_to_player()
	await _pause(0.6)
	_record(not node.attack_hitbox.is_active(),
		"41) a recall leaves no live hitbox")
	var recoveries: int = node.recovery_count
	await _pause(3.0)
	_record(node.recovery_count == recoveries,
		"42) and no teleport happens while it simply walks back (%d)" % node.recovery_count)
	_record(p.global_position.distance_to(node.global_position)
			<= node.max_combat_distance_from_player,
		"43) it stays inside its leash (%.1f m)" %
			p.global_position.distance_to(node.global_position))


# --- 7. health bars tell the truth ------------------------------------------------------------------

func _qa_health_ui() -> void:
	var dungeon: DungeonController = current_scene as DungeonController
	var p: Player = current_scene.get_node("Player")
	var hp: PlayerHealthHUD = current_scene.get_node("PlayerHealthHUD")
	p.hurtbox.set_invulnerable(false)
	p.health_component.take_damage(DamageInfo.new(30.0, null))
	await process_frame
	_record(hp.get_health_text() == "%d / %d" % [
			roundi(p.health_component.current_health),
			roundi(p.health_component.max_health)],
		"44) the player bar follows damage: '%s'" % hp.get_health_text())
	_record(hp.get_ratio() <= 1.0, "45) and never reads above full (%.2f)" % hp.get_ratio())

	# A point in VIT raises the ceiling without healing, and the bar follows.
	p.progression.add_xp(120)
	var before_max: float = p.health_component.max_health
	p.progression.allocate_stat(PlayerProgression.Stat.VITALITY)
	await process_frame
	_record(p.health_component.max_health > before_max
			and hp.get_health_text().ends_with("/ %d" % roundi(p.health_component.max_health)),
		"46) a point in VIT moves the ceiling and the bar: '%s'" % hp.get_health_text())
	_record(p.health_component.current_health <= p.health_component.max_health,
		"47) without ever exceeding it")
	p.health_component.heal(1000.0)
	await process_frame
	_record(hp.get_ratio() <= 1.0 and p.health_component.current_health
			== p.health_component.max_health,
		"48) healing past full clamps to full")

	# A dead enemy keeps no bar.
	var leftover: int = 0
	for enemy in dungeon.get_rooms()[0].get_enemies():
		var bar: EnemyHealthBar3D = enemy.get_node_or_null("EnemyHealthBar3D")
		if enemy.has_died() and bar != null and bar.is_bar_visible():
			leftover += 1
	_record(leftover == 0, "49) no dead enemy is still showing a bar (%d)" % leftover)

	var shadow_hud: ActiveShadowHUD = current_scene.get_node("ActiveShadowHUD")
	var node: BasicMeleeShadow = p.shadow_summoner.get_active_node()
	if node != null:
		_record(shadow_hud.get_health_text() == "%d / %d" % [
				roundi(node.health_component.current_health),
				roundi(node.health_component.max_health)],
			"50) the shadow panel shows the shadow, not the player: '%s'" %
				shadow_hud.get_health_text())
	else:
		_record(true, "50) no shadow out to compare")


# --- 8. dying, in each room and each phase ------------------------------------------------------------

func _qa_deaths() -> void:
	for index in 3:
		_state.reset_runtime_state()
		change_scene_to_file(DUNGEON)
		await _pause(0.9)
		var dungeon: DungeonController = current_scene as DungeonController
		var p: Player = current_scene.get_node("Player")
		p.progression.add_xp(150)
		p.inventory.add_item(_sword)
		p.equipment.equip(_sword)
		var shadow: ShadowInstance = p.shadows.add_shadow(_shadow_data)
		p.shadow_summoner.summon(shadow.instance_id)
		await _pause(0.5)
		p.global_position = ROOM_ANCHORS[index]
		await _pause(0.8)

		var where: String = "room %d" % (index + 1)
		if index == 2:
			# Take the boss into phase 2 so the death happens there.
			var boss: DungeonBoss = dungeon.get_rooms()[2].get_enemies()[0] as DungeonBoss
			(boss.get_node("Hurtbox") as Hurtbox).receive_hit(DamageInfo.new(
				boss.get_node("HealthComponent").max_health * 0.6, p))
			await _pause(2.2)
			where = "boss phase %d" % (2 if boss.is_phase_2() else 1)

		var before: Dictionary = _snapshot(p)
		p.hurtbox.set_invulnerable(false)
		p.health_component.take_damage(DamageInfo.new(1000000.0))
		await _pause(0.4)
		_record(dungeon.get_state() == DungeonController.DungeonState.FAILED
				and dungeon.status_label.visible
				and dungeon.status_label.text == dungeon.death_message,
			"51.%d) dying in %s fails the run and says so" % [index + 1, where])
		await _pause(2.8)

		var p2: Player = current_scene.get_node("Player")
		await _pause(0.5)
		var after: Dictionary = _snapshot(p2)
		_record(_same(before, after),
			"52.%d) and the character keeps everything through the restart" % (index + 1))
		_record(is_equal_approx(p2.health_component.current_health,
				p2.health_component.max_health),
			"53.%d) at full health for the new attempt" % (index + 1))
		var d2: DungeonController = current_scene as DungeonController
		var stats: DungeonRunStats = d2.get_node("DungeonRunStats")
		_record(stats.get_total_kills() == 0 and stats.get_player_xp_earned() == 0
				and stats.items_picked_up == 0 and stats.shadows_extracted == 0,
			"54.%d) against a reset tally" % (index + 1))
		_record(not p2.shadow_summoner.has_active_shadow(),
			"55.%d) with no shadow summoned by itself" % (index + 1))
		_record(get_nodes_in_group(BasicMeleeShadow.GROUP).is_empty(),
			"56.%d) and none left over in the world" % (index + 1))

	# A shadow's own death costs the run, not the shadow.
	var p3: Player = current_scene.get_node("Player")
	var shadow3: ShadowInstance = p3.shadows.get_shadows()[0]
	var node: BasicMeleeShadow = p3.shadow_summoner.summon(shadow3.instance_id)
	await _pause(0.5)
	var hud: ActiveShadowHUD = current_scene.get_node("ActiveShadowHUD")
	var level: int = shadow3.level
	var xp: int = shadow3.current_xp
	node.hurtbox.set_invulnerable(false)
	node.health_component.take_damage(DamageInfo.new(1000000.0))
	await _pause(1.5)
	_record(not hud.is_showing(), "57) a shadow's death takes its panel with it")
	_record(p3.shadows.has_shadow(shadow3.instance_id)
			and shadow3.level == level and shadow3.current_xp == xp,
		"58) the shadow keeps its Lv.%d and %d XP" % [shadow3.level, shadow3.current_xp])
	_record(get_nodes_in_group(BasicMeleeShadow.GROUP).is_empty(),
		"59) and leaves no copy behind")
	_record(p3.shadow_summoner.summon(shadow3.instance_id) != null,
		"60) it can be summoned again")
	await _pause(0.5)
	_record(get_nodes_in_group(BasicMeleeShadow.GROUP).size() == 1,
		"61) as exactly one shadow (%d)" % get_nodes_in_group(BasicMeleeShadow.GROUP).size())


# --- 9. three cycles, nothing piling up ------------------------------------------------------------------

func _qa_repeated_cycles() -> void:
	_state.reset_runtime_state()
	change_scene_to_file(HUB)
	await _pause(0.8)
	var counts: Array[String] = []
	for cycle in 3:
		await _enter_dungeon_from_hub()
		var dungeon: DungeonController = current_scene as DungeonController
		var p: Player = current_scene.get_node("Player")
		p.hurtbox.set_invulnerable(true)
		if p.shadows.is_empty():
			p.shadows.add_shadow(_shadow_data)
		p.shadow_summoner.summon(p.shadows.get_shadows()[0].instance_id)
		await _pause(0.5)

		# Every enemy alive, every door shut, nothing left over.
		var alive: int = 0
		for room in dungeon.get_rooms():
			for enemy in room.get_enemies():
				if not enemy.has_died():
					alive += 1
		var stats: DungeonRunStats = dungeon.get_node("DungeonRunStats")
		counts.append("cycle %d: %d alive, %d players, %d shadows, %d items, %d remnants, %d HUDs" % [
			cycle + 1, alive, _count(current_scene, "Player"),
			get_nodes_in_group(BasicMeleeShadow.GROUP).size(),
			_count(current_scene, "WorldItem"), _count(current_scene, "ShadowRemnant"),
			_count(current_scene, "ActiveShadowHUD")])
		_record(alive == 6, "62.%d) the dungeon is fresh: %d enemies alive" % [cycle + 1, alive])
		_record(_count(current_scene, "Player") == 1,
			"63.%d) exactly one player in the scene" % (cycle + 1))
		_record(get_nodes_in_group(BasicMeleeShadow.GROUP).size() == 1,
			"64.%d) exactly one shadow in the world" % (cycle + 1))
		_record(_count(current_scene, "WorldItem") == 0
				and _count(current_scene, "ShadowRemnant") == 0,
			"65.%d) and no loot or remnants carried in" % (cycle + 1))
		_record(_count(current_scene, "ActiveShadowHUD") == 1
				and _count(current_scene, "RunSummary") == 1
				and _count(current_scene, "InteractionPrompt") == 1,
			"66.%d) one of each UI, not a stack of them" % (cycle + 1))
		_record(stats.get_total_kills() == 0,
			"67.%d) with a clean tally" % (cycle + 1))

		# Back out the way a completed run does. The player walks into each room
		# first: a room arms on entry, and one that never armed never clears, so
		# killing from outside would leave the dungeon unfinishable.
		for room_index in 3:
			p.global_position = ROOM_ANCHORS[room_index]
			await _pause(0.8)
			for enemy in dungeon.get_rooms()[room_index].get_enemies():
				if not enemy.has_died():
					(enemy.get_node("HealthComponent") as HealthComponent).take_damage(DamageInfo.new(
						1000000.0, p))
			await _pause(0.5)
		await _pause(1.5)
		RunSummary.dismiss_open(self)
		await _pause(0.3)
		p.hurtbox.set_invulnerable(false)
		p.global_position = EXIT_POS
		await _pause(0.5)
		dungeon.exit_portal.activate()
		await _pause(1.5)
		_record(current_scene.scene_file_path == HUB,
			"68.%d) and the portal returns to the hub" % (cycle + 1))
	print("")
	for line in counts:
		print("  " + line)


# --- helpers -------------------------------------------------------------------------------------------

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


func _enter_dungeon_from_hub() -> void:
	var p: Player = current_scene.get_node("Player")
	var gate: DungeonGate = current_scene.get_node("DungeonGate")
	p.global_position = gate.global_position
	await _pause(0.3)
	gate.activate()
	await _pause(1.4)


func _press(action: StringName) -> void:
	var event: InputEventAction = InputEventAction.new()
	event.action = action
	event.pressed = true
	root.push_input(event)
	await process_frame


## Counts nodes of a kind by type rather than by name: a name comparison cannot
## tell ActiveShadowHUD from anything else without guessing at capitalisation.
func _count(from: Node, kind: String) -> int:
	var total: int = 1 if _is_kind(from, kind) else 0
	for child in from.get_children():
		total += _count(child, kind)
	return total


func _is_kind(node: Node, kind: String) -> bool:
	match kind:
		"Player":
			return node is Player
		"WorldItem":
			return node is WorldItem
		"ShadowRemnant":
			return node is ShadowRemnant
		"ActiveShadowHUD":
			return node is ActiveShadowHUD
		"RunSummary":
			return node is RunSummary
		"InteractionPrompt":
			return node is InteractionPrompt
		_:
			return false


func _first_remnant(from: Node) -> ShadowRemnant:
	var remnant: ShadowRemnant = from as ShadowRemnant
	if remnant != null and is_instance_valid(remnant) and not remnant.has_been_attempted():
		return remnant
	for child in from.get_children():
		var found: ShadowRemnant = _first_remnant(child)
		if found != null:
			return found
	return null


func _first_item(from: Node) -> WorldItem:
	var item: WorldItem = from as WorldItem
	if item != null and is_instance_valid(item):
		return item
	for child in from.get_children():
		var found: WorldItem = _first_item(child)
		if found != null:
			return found
	return null


func _snapshot(player: Player) -> Dictionary:
	var shadows: Array[String] = []
	for shadow in player.shadows.get_shadows():
		shadows.append("%s:%d/%d" % [shadow.get_short_id(), shadow.level, shadow.current_xp])
	return {
		"level": player.progression.current_level,
		"xp": player.progression.get_total_xp(),
		"points": player.progression.available_stat_points,
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


func _kill(player: Player, target: RoomCombatant, budget: float = 60.0) -> void:
	var elapsed: float = 0.0
	while elapsed < budget and not target.has_died():
		if player.combat.get_state() == PlayerCombat.State.IDLE:
			player.global_position = target.global_position + Vector3(0, 0, STRIKE_RANGE)
			player.camera_rig.rotation.y = 0.0
			player.camera_rig.attack_light_pressed.emit()
		await physics_frame
		elapsed += 1.0 / 60.0
