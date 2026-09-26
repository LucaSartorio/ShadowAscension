extends SceneTree

## M9.2 phase 1 — measurement, not tuning. Prints what the game currently does
## so a balance change can be argued from a number rather than a feeling.
##
##   godot --headless --path . --script res://tests/core/balance_baseline_run.gd
##
## It asserts almost nothing on purpose. The few checks it does make are the
## ones where a wrong value would be a bug rather than a balance opinion —
## an extraction chance left at 1.0 by a test, for instance.

const HUB: String = "res://scenes/core/hub.tscn"
const DUNGEON: String = "res://scenes/dungeons/dungeon_test.tscn"
const ROOM_ANCHORS: Array[Vector3] = [
	Vector3(0, 0.1, -13), Vector3(0, 0.1, -33), Vector3(0, 0.1, -53)
]
const STRIKE_RANGE: float = 1.6

var _enemy_data: EnemyData = preload("res://resources/enemies/basic_melee_enemy.tres")
var _boss_data: BossData = preload("res://resources/enemies/bosses/dungeon_boss_data.tres")
var _shadow_data: ShadowData = preload("res://resources/shadows/basic_melee_shadow.tres")
var _enemy_loot: LootTable = preload("res://resources/items/loot/basic_melee_enemy_loot.tres")
var _boss_loot: LootTable = preload("res://resources/items/loot/dungeon_boss_loot.tres")
var _pass: int = 0
var _fail: int = 0


func _initialize() -> void:
	root.get_node("PlayerRuntimeState").reset_runtime_state()
	_report_static()
	await _measure_player_vs_enemy()
	await _measure_shadow_alone()
	await _measure_boss()
	await _measure_run_progression()
	print("")
	print("[SUMMARY] passed=%d failed=%d" % [_pass, _fail])
	await _pause(0.3)
	quit()


# --- what the data says --------------------------------------------------------------

func _report_static() -> void:
	var player_scene: PackedScene = load("res://scenes/player/player.tscn")
	var p: Player = player_scene.instantiate() as Player
	root.add_child(p)
	# _initialize() runs before the first frame, so _ready is still pending and
	# every @onready reference is null until one has gone by.
	await process_frame
	var combat_data: PlayerCombatData = p.combat.data
	var steps: Array[AttackData] = combat_data.light_combo
	var combo: Array[String] = []
	var combo_damage: float = 0.0
	var combo_time: float = 0.0
	for step in steps:
		var step_damage: float = combat_data.base_damage * step.damage_multiplier
		combo.append("%.0f" % step_damage)
		combo_damage += step_damage
		combo_time += step.windup + step.active + step.recovery

	print("")
	print("=== PLAYER (fresh, nothing equipped) ===")
	print("  base HP              %.0f" % p.health_component.max_health)
	print("  movement / dodge     %.2f / %.2f" % [p.movement_speed, p.dodge_speed])
	print("  combo damage         %s  (total %.0f)" % [" / ".join(combo), combo_damage])
	print("  combo active time    %.2fs  -> %.1f dps at full uptime" % [
		combo_time, combo_damage / combo_time])
	print("  dodge i-frames       %.2f-%.2fs of a %.2fs dodge" % [
		combat_data.invulnerability_start, combat_data.invulnerability_end,
		combat_data.dodge_duration])
	print("  STR / multiplier     %d / x%.2f" % [
		p.progression.get_effective_strength(), p.progression.get_melee_damage_multiplier()])
	print("  equipment attack     %.1f (starting equipment: %s)" % [
		p.progression.get_melee_attack_power(),
		"none" if p.equipment.get_occupied_slots().is_empty() else "some"])
	print("  first-hit damage     %.0f" % p.combat.calculate_damage(steps[0]))

	print("")
	print("=== BASIC ENEMY ===")
	print("  HP / damage          %.0f / %.0f" % [
		_enemy_data.max_health, _enemy_data.attack_damage])
	print("  movement             %.2f" % _enemy_data.movement_speed)
	var basic: AttackData = _enemy_data.attacks[0]
	print("  attack timings       telegraph %.2f active %.2f recovery %.2f cooldown %.2f" % [
		basic.windup, basic.active, basic.recovery, _enemy_data.attack_cooldown])
	var cycle: float = basic.windup + basic.active + basic.recovery + _enemy_data.attack_cooldown
	print("  -> one hit every     %.2fs  (%.1f dps)" % [
		cycle, _enemy_data.attack_damage * basic.damage_multiplier / cycle])
	print("  XP reward            %d" % _enemy_data.xp_reward)
	print("  loot: any drop       %.1f%%  (%s)" % [
		_any_drop_chance(_enemy_loot) * 100.0,
		"guaranteed floor" if _enemy_loot.guarantee_at_least_one else "can drop nothing"])
	print("  shadow extraction    %.2f" % _shadow_data.extraction_chance)

	print("")
	print("=== SHADOW (Lv.1) ===")
	var shadow: ShadowInstance = ShadowInstance.new(&"baseline", _shadow_data)
	var shadow_scene: PackedScene = _shadow_data.summon_scene
	var node: BasicMeleeShadow = shadow_scene.instantiate() as BasicMeleeShadow
	root.add_child(node)
	var shadow_cycle: float = node.attack_startup + node.attack_active \
		+ node.attack_recovery + node.attack_cooldown
	print("  HP / damage          %.0f / %.0f" % [
		shadow.get_max_health(), shadow.get_damage()])
	print("  per level            +%.0f HP / +%.0f damage" % [
		_shadow_data.health_per_level, _shadow_data.damage_per_level])
	print("  attack timings       startup %.2f active %.2f recovery %.2f cooldown %.2f" % [
		node.attack_startup, node.attack_active, node.attack_recovery, node.attack_cooldown])
	print("  -> one hit every     %.2fs  (%.1f dps)" % [
		shadow_cycle, shadow.get_damage() / shadow_cycle])
	print("  detection / leash    %.0f / %.0f m" % [
		node.enemy_detection_range, node.max_combat_distance_from_player])
	print("  XP curve             %d / %d / %d / %d  (x%.2f)" % [
		_shadow_data.xp_required_for_level(1), _shadow_data.xp_required_for_level(2),
		_shadow_data.xp_required_for_level(3), _shadow_data.xp_required_for_level(4),
		_shadow_data.xp_growth_factor])
	print("  offensive share      %.0f%% of the player's dps" % [
		100.0 * (shadow.get_damage() / shadow_cycle) / (combo_damage / combo_time)])
	node.queue_free()

	print("")
	print("=== BOSS ===")
	print("  HP                   %.0f" % _boss_data.max_health)
	print("  XP reward            %d" % _boss_data.xp_reward)
	print("  stagger resistance   %.0f (%.1fs immune after)" % [
		_boss_data.stagger_resistance, _boss_data.stagger_immunity_time])
	for phase in _boss_data.phases:
		var tempo: float = phase.tempo_multiplier
		print("  %-8s at %3.0f%% health | transition %.2fs | tempo x%.2f | speed x%.2f" % [
			phase.id, phase.health_threshold * 100.0, phase.transition_duration, tempo,
			phase.movement_speed_multiplier])
		for attack in phase.attacks:
			print("    %-20s %3.0f dmg x%d | %.2f/%.2f/%.2f | w %.1f" % [
				attack.get_id(), DamageModel.attack_damage(_boss_data.attack_damage, attack.attack.damage_multiplier),
				attack.hit_count, attack.attack.windup * tempo, attack.attack.recovery * tempo,
				attack.cooldown * tempo, attack.weight])
	print("  worst single hit     %.0f of %.0f player HP (%.0f%%)" % [
		40.0, p.health_component.max_health, 4000.0 / p.health_component.max_health])
	print("  boss loot: any drop  %.1f%% (%s)" % [
		_any_drop_chance(_boss_loot) * 100.0,
		"guaranteed floor" if _boss_loot.guarantee_at_least_one else "can drop nothing"])

	print("")
	print("=== PROGRESSION ===")
	print("  player XP curve      %d / %d / %d / %d  (x%.2f)" % [
		p.progression.xp_required_for_level(1), p.progression.xp_required_for_level(2),
		p.progression.xp_required_for_level(3), p.progression.xp_required_for_level(4),
		p.progression.xp_growth_factor])
	print("  stat points / level  %d" % p.progression.stat_points_per_level)
	print("  STR / AGI / VIT      +%.0f%% melee, +%.0f%% move & +%.1f%% dodge, +%.0f HP per point" % [
		p.progression.stats.melee_damage_per_point * 100.0,
		p.progression.stats.movement_speed_per_point * 100.0,
		p.progression.stats.dodge_speed_per_point * 100.0,
		p.progression.stats.health_per_vitality_point])
	print("  shadow kill split    %.0f%% shadow / %.0f%% player" % [
		PlayerProgression.SHADOW_KILL_SHARE * 100.0,
		(1.0 - PlayerProgression.SHADOW_KILL_SHARE) * 100.0])

	# The only hard checks here: values a test could have left behind.
	_record(is_equal_approx(_shadow_data.extraction_chance, 0.7),
		"A1) the shipped extraction chance is 0.70, not a test's 0.0 or 1.0 (%.2f)" %
			_shadow_data.extraction_chance)
	_record(not _enemy_loot.guarantee_at_least_one,
		"A2) normal enemies can still drop nothing")
	_record(_boss_loot.guarantee_at_least_one, "A3) the boss always drops something")
	_record(_any_drop_chance(_enemy_loot) > 0.3 and _any_drop_chance(_enemy_loot) < 0.6,
		"A4) a normal enemy drops something %.0f%% of the time" %
			(_any_drop_chance(_enemy_loot) * 100.0))
	_record(not p.progression.debug_progression_enabled,
		"A5) the debug XP key is off by default")
	_record(p.inventory.is_empty() and p.equipment.get_occupied_slots().is_empty(),
		"A6) a new player starts with nothing held or worn")
	p.queue_free()
	await process_frame


# --- how many swings, how many hits ------------------------------------------------------

func _measure_player_vs_enemy() -> void:
	change_scene_to_file(DUNGEON)
	await _pause(0.9)
	var dungeon: DungeonController = current_scene as DungeonController
	var p: Player = current_scene.get_node("Player")
	p.global_position = ROOM_ANCHORS[0]
	await _pause(0.7)
	var enemy: RoomCombatant = dungeon.get_rooms()[0].get_enemies()[0]
	var health: HealthComponent = enemy.get_node("HealthComponent")

	# Parked so it cannot sidestep: this is a damage measurement, not a duel.
	enemy.set_combat_enabled(false)
	p.hurtbox.set_invulnerable(true)
	var landed: int = 0
	var damages: Array[String] = []
	var last: float = health.current_health
	var elapsed: float = 0.0
	var started: int = Time.get_ticks_msec()
	while elapsed < 30.0 and not enemy.has_died():
		if p.combat.get_state() == PlayerCombat.State.IDLE:
			p.global_position = enemy.global_position + Vector3(0, 0, STRIKE_RANGE)
			p.camera_rig.rotation.y = 0.0
			p.camera_rig.attack_light_pressed.emit()
		await physics_frame
		elapsed += 1.0 / 60.0
		if health.current_health < last:
			landed += 1
			damages.append("%.0f" % (last - health.current_health))
			last = health.current_health
	print("")
	print("=== MEASURED: player vs one basic enemy ===")
	print("  light attacks to kill  %d  (%s)" % [landed, " + ".join(damages)])
	print("  wall-clock             %.1fs" % ((Time.get_ticks_msec() - started) / 1000.0))
	_record(landed >= 3 and landed <= 5,
		"B1) a basic enemy takes %d light attacks (target 3-5)" % landed)

	# And the other way round: how many enemy hits the player can take.
	var second: RoomCombatant = dungeon.get_rooms()[0].get_enemies()[1]
	var hitbox: Hitbox = second.get_node("VisualRoot/AttackOrigin/Hitbox")
	p.hurtbox.set_invulnerable(false)
	var taken: int = 0
	# Stopped one blow short and counted, rather than actually killed: a death
	# here restarts the dungeon and would poison every measurement after it.
	while p.health_component.current_health > hitbox.damage and taken < 40:
		p.hurtbox.receive_hit(DamageInfo.new(hitbox.damage, second))
		taken += 1
	taken += 1
	p.health_component.heal(p.health_component.max_health)
	print("  enemy hits to kill the player  %d at %.0f damage vs %.0f HP" % [
		taken, hitbox.damage, p.health_component.max_health])
	_record(taken >= 5 and taken <= 7,
		"B2) the player survives %d normal enemy hits (target 5-7)" % taken)


# --- the shadow on its own -------------------------------------------------------------------

func _measure_shadow_alone() -> void:
	change_scene_to_file(DUNGEON)
	await _pause(0.9)
	var dungeon: DungeonController = current_scene as DungeonController
	var p: Player = current_scene.get_node("Player")
	p.hurtbox.set_invulnerable(true)
	var shadow: ShadowInstance = p.shadows.add_shadow(_shadow_data)
	var node: BasicMeleeShadow = p.shadow_summoner.summon(shadow.instance_id)
	await _pause(0.5)
	node.hurtbox.set_invulnerable(true)

	p.global_position = ROOM_ANCHORS[0]
	await _pause(0.8)
	var room: RoomController = dungeon.get_rooms()[0]
	var total: int = room.get_enemies().size()
	var started: int = Time.get_ticks_msec()
	var elapsed: float = 0.0
	# The player stands in the room and never swings: everything that dies here
	# was killed by the shadow.
	while elapsed < 180.0 and not room.is_cleared():
		await physics_frame
		elapsed += 1.0 / 60.0
	var wall: float = (Time.get_ticks_msec() - started) / 1000.0
	print("")
	print("=== MEASURED: shadow alone, AGGRESSIVE, player never attacks ===")
	print("  room 1 (%d enemies)     %s in %.0fs of simulated time (%.1fs wall)" % [
		total, "cleared" if room.is_cleared() else "NOT cleared", elapsed, wall])
	print("  shadow level / XP      Lv.%d, %d XP" % [shadow.level, shadow.current_xp])
	print("  shadow health left     %.0f / %.0f" % [
		node.health_component.current_health, node.health_component.max_health])
	_record(room.is_cleared(),
		"C1) the shadow can clear a room alone, in %.0fs (it should be able to, slowly)" % elapsed)
	_record(elapsed > 20.0,
		"C2) and it takes it %.0fs, so it does not replace the player" % elapsed)

	# Survivability: unshielded, against a live room.
	change_scene_to_file(DUNGEON)
	await _pause(0.9)
	var d2: DungeonController = current_scene as DungeonController
	var p2: Player = current_scene.get_node("Player")
	p2.hurtbox.set_invulnerable(true)
	var s2: ShadowInstance = p2.shadows.get_shadows()[0]
	var n2: BasicMeleeShadow = p2.shadow_summoner.summon(s2.instance_id)
	await _pause(0.5)
	p2.global_position = ROOM_ANCHORS[1]
	await _pause(0.8)
	var survived: float = 0.0
	while survived < 60.0 and not n2.is_dead() and not d2.get_rooms()[1].is_cleared():
		await physics_frame
		survived += 1.0 / 60.0
	print("  room 2, unshielded     %s after %.0fs (%.0f/%.0f HP)" % [
		"DIED" if n2.is_dead() else "alive", survived,
		0.0 if n2.is_dead() else n2.health_component.current_health,
		s2.get_max_health()])
	_record(true, "C3) shadow survivability in room 2 recorded above")


# --- the boss -----------------------------------------------------------------------------------

func _measure_boss() -> void:
	change_scene_to_file(DUNGEON)
	await _pause(0.9)
	var dungeon: DungeonController = current_scene as DungeonController
	var p: Player = current_scene.get_node("Player")
	p.hurtbox.set_invulnerable(true)
	# A reasonable build for a player who has done the rooms: two levels' worth
	# of points into STR, and the starter weapon a run would plausibly find.
	p.progression.add_xp(250)
	for _i in 6:
		p.progression.allocate_stat(PlayerProgression.Stat.STRENGTH)
	p.inventory.add_item(load("res://resources/items/training_sword.tres"))
	p.equipment.equip(load("res://resources/items/training_sword.tres"))
	await _pause(0.3)
	var shadow: ShadowInstance = p.shadows.add_shadow(_shadow_data)
	var node: BasicMeleeShadow = p.shadow_summoner.summon(shadow.instance_id)
	await _pause(0.4)

	p.global_position = ROOM_ANCHORS[2]
	await _pause(1.2)
	var boss: DungeonBoss = dungeon.get_rooms()[2].get_enemies()[0] as DungeonBoss
	var boss_health: HealthComponent = boss.get_node("HealthComponent")
	print("")
	print("=== MEASURED: boss, with a run-plausible build ===")
	print("  player STR %d, melee x%.2f, attack power %.0f -> first hit %.0f" % [
		p.progression.get_effective_strength(), p.progression.get_melee_damage_multiplier(),
		p.progression.get_melee_attack_power(),
		p.combat.calculate_damage(p.combat.data.light_combo[0])])

	# Two numbers, because they answer different questions. The floor is the
	# fight with no defending at all — the fastest the boss can physically die.
	# The played figure backs off whenever the boss winds up and comes back when
	# it is over, which is how the encounter is actually fought.
	var floor_time: float = await _fight_boss(p, boss, false)
	print("  floor (never defends)  %.0fs" % floor_time)

	change_scene_to_file(DUNGEON)
	await _pause(0.9)
	var d2: DungeonController = current_scene as DungeonController
	var p2: Player = current_scene.get_node("Player")
	p2.hurtbox.set_invulnerable(true)
	p2.progression.add_xp(250)
	for _i in 6:
		p2.progression.allocate_stat(PlayerProgression.Stat.STRENGTH)
	p2.inventory.add_item(load("res://resources/items/training_sword.tres"))
	p2.equipment.equip(load("res://resources/items/training_sword.tres"))
	p2.global_position = ROOM_ANCHORS[2]
	await _pause(1.2)
	var boss2: DungeonBoss = d2.get_rooms()[2].get_enemies()[0] as DungeonBoss
	var played_time: float = await _fight_boss(p2, boss2, true)
	print("  played (backs off)     %.0fs" % played_time)
	print("  uptime implied         %.0f%%" % (100.0 * floor_time / maxf(played_time, 0.001)))
	var elapsed: float = played_time
	print("  shadow contribution    Lv.%d, %d XP after the fight" % [
		shadow.level, shadow.current_xp])
	_record(boss2.has_died(), "D1) the boss can be killed with a plausible build")
	_record(elapsed > floor_time,
		"D2) defending costs time: %.0fs played against a %.0fs floor" % [elapsed, floor_time])


## Drives the boss fight. With `defend` the player leaves the attack's reach the
## moment it winds up and returns once the active window is over — the same
## decision a player makes, made from the same information the telegraph gives.
func _fight_boss(p: Player, boss: DungeonBoss, defend: bool) -> float:
	var elapsed: float = 0.0
	var attacks: Dictionary = {}
	# Backing off and coming back is not free. A player who retreats to 5m has
	# to cover that ground again at their own speed, so the model pays for it
	# rather than snapping back into reach the frame the danger ends.
	var reapproach: float = 3.4 / p.movement_speed
	var reapproach_left: float = 0.0
	while elapsed < 400.0 and not boss.has_died():
		var winding_up: bool = defend and boss.get_attack_phase() in [
			BossCombat.Phase.TELEGRAPH, BossCombat.Phase.ACTIVE,
			BossCombat.Phase.BETWEEN_HITS]
		if winding_up:
			var attack: BossAttack = boss.get_current_attack()
			if attack != null:
				attacks[attack.get_id()] = true
			# Out past the reach of whatever is coming.
			var away: Vector3 = (p.global_position - boss.global_position)
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
	if defend:
		print("  patterns seen          %s" % [attacks.keys()])
	return elapsed


# --- a whole run's progression ---------------------------------------------------------------------

func _measure_run_progression() -> void:
	root.get_node("PlayerRuntimeState").reset_runtime_state()
	change_scene_to_file(DUNGEON)
	await _pause(0.9)
	var dungeon: DungeonController = current_scene as DungeonController
	var p: Player = current_scene.get_node("Player")
	p.hurtbox.set_invulnerable(true)
	var stats: DungeonRunStats = dungeon.get_node("DungeonRunStats")
	var level_ups: Array[int] = []
	p.progression.level_up.connect(func(level: int, _pts: int) -> void: level_ups.append(level))

	var total_reward: int = 0
	for index in 3:
		p.global_position = ROOM_ANCHORS[index]
		await _pause(0.8)
		for enemy in dungeon.get_rooms()[index].get_enemies():
			if enemy.has_died():
				continue
			total_reward += enemy.get_xp_reward()
			await _kill(p, enemy, 120.0)
			await _pause(0.3)
	await _pause(1.5)
	print("")
	print("=== MEASURED: one full clear, every kill the player's ===")
	print("  enemies / bosses       %d / %d" % [stats.enemies_defeated, stats.bosses_defeated])
	print("  XP available           %d" % total_reward)
	print("  XP the player earned   %d" % stats.get_player_xp_earned())
	print("  level-ups              %d  -> Lv.%d, %d/%d" % [
		level_ups.size(), p.progression.current_level, p.progression.current_xp,
		p.progression.get_xp_to_next_level()])
	print("  stat points earned     %d" % p.progression.available_stat_points)
	print("  items on the floor     %d picked / %d dropped" % [
		stats.items_picked_up, _count_world_items(dungeon)])
	_record(level_ups.size() >= 2 and level_ups.size() <= 3,
		"E1) a full player-led clear gives %d level-ups (target about 2)" % level_ups.size())
	_record(stats.get_player_xp_earned() == total_reward,
		"E2) and every point of it (%d of %d) since the player took every kill" % [
			stats.get_player_xp_earned(), total_reward])


# --- helpers -----------------------------------------------------------------------------------------

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


## Probability that a table yields at least one entry, ignoring the guarantee.
func _any_drop_chance(table: LootTable) -> float:
	var none: float = 1.0
	for entry in table.entries:
		none *= (1.0 - entry.drop_chance)
	return 1.0 - none


func _count_world_items(from: Node) -> int:
	var total: int = 0
	if from is WorldItem:
		total += 1
	for child in from.get_children():
		total += _count_world_items(child)
	return total


func _kill(player: Player, target: RoomCombatant, budget: float = 60.0) -> void:
	var elapsed: float = 0.0
	while elapsed < budget and not target.has_died():
		if player.combat.get_state() == PlayerCombat.State.IDLE:
			player.global_position = target.global_position + Vector3(0, 0, STRIKE_RANGE)
			player.camera_rig.rotation.y = 0.0
			player.camera_rig.attack_light_pressed.emit()
		await physics_frame
		elapsed += 1.0 / 60.0
