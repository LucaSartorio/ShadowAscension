extends SceneTree

## M10.3 — configuration versus runtime state.
##
##   godot --headless --path . --script res://tests/core/game_data_run.gd
##
## Three things. The configuration assets still hold exactly the numbers the game
## shipped with, so moving a value between files cannot quietly change it. Every
## runtime entity is seeded from its asset and from nothing else, so editing the
## asset is enough to change the game. And — the one that matters most — two
## enemies that share an EnemyData share configuration only: damaging or retuning
## one touches neither its sibling nor the asset. The same holds for shadows and
## their ShadowData.

const DUNGEON: String = "res://scenes/dungeons/dungeon_test.tscn"
const ENEMY_SCENE: String = "res://scenes/enemies/basic_melee_enemy.tscn"
const ROOM1_ANCHOR: Vector3 = Vector3(0, 0.1, -13)
const PARKING: Vector3 = Vector3(40, 0.1, 40)
const STRIKE_RANGE: float = 1.6

var _enemy_data: EnemyData = preload("res://resources/enemies/basic_melee_enemy.tres")
var _boss_data: BossData = preload("res://resources/enemies/bosses/dungeon_boss_data.tres")
var _progression: ProgressionStats = preload("res://resources/characters/player_progression.tres")
var _shadow_data: ShadowData = preload("res://resources/shadows/basic_melee_shadow.tres")
var _pass: int = 0
var _fail: int = 0


func _initialize() -> void:
	root.get_node_or_null("PlayerRuntimeState").reset_runtime_state()

	_phase_assets()
	change_scene_to_file(DUNGEON)
	await _pause(0.8)
	await _phase_enemies_share_configuration_only()
	await _phase_boss()
	_phase_progression()
	await _phase_editing_the_asset()
	await _phase_shadow_template()
	await _phase_reward_comes_from_the_asset()

	print("[SUMMARY] passed=%d failed=%d" % [_pass, _fail])
	await _pause(0.3)
	quit()


# --- 1-6. the assets hold the numbers the game shipped with ------------------------------

func _phase_assets() -> void:
	_record(_enemy_data is EnemyData
			and _enemy_data.resource_path == "res://resources/enemies/basic_melee_enemy.tres",
		"1) the basic melee enemy's configuration loads as an EnemyData asset")
	_record(is_equal_approx(_enemy_data.max_health, 100.0)
			and is_equal_approx(_enemy_data.attack_damage, 15.0)
			and _enemy_data.xp_reward == 25,
		"2) 100 HP, 15 damage, 25 XP (got %.0f / %.0f / %d)" % [
			_enemy_data.max_health, _enemy_data.attack_damage, _enemy_data.xp_reward])
	_record(is_equal_approx(_enemy_data.movement_speed, 3.8)
			and is_equal_approx(_enemy_data.detection_range, 10.0)
			and is_equal_approx(_enemy_data.attack_range, 1.8),
		"3) moving at 3.8, seeing 10 m, striking at 1.8 m")
	_record(is_equal_approx(_boss_data.max_health, 900.0) and _boss_data.xp_reward == 200
			and _boss_data.phases.size() == 2 and is_equal_approx(_boss_data.phases[1].health_threshold, 0.5),
		"4) the boss: 900 HP, 200 XP, phase 2 at half health")
	_record(_progression.starting_level == 1 and _progression.strength == 10
			and _progression.stat_points_per_level == 5 and _progression.max_level == 100
			and _progression.base_xp_requirement == 100
			and is_equal_approx(_progression.xp_growth_factor, 1.25),
		"5) the player: level 1, stats 10, 5 points a level, curve 100 x 1.25, cap 100")
	_record(is_equal_approx(_shadow_data.health_at_level(1), 80.0)
			and is_equal_approx(_shadow_data.damage_at_level(1), 12.0)
			and is_equal_approx(_shadow_data.health_at_level(2), 88.0)
			and is_equal_approx(_shadow_data.damage_at_level(2), 14.0)
			and _shadow_data.xp_required_for_level(1) == 50
			and _shadow_data.xp_required_for_level(2) == 60
			and is_equal_approx(_shadow_data.extraction_chance, 0.7),
		"6) the shadow: 80 HP / 12 dmg at Lv.1, +8 / +2 a level, XP 50 then 60, 70% extraction")


# --- 7-14. two enemies, one asset: configuration shared, state not ------------------------

func _phase_enemies_share_configuration_only() -> void:
	var dungeon: DungeonController = current_scene as DungeonController
	var enemies: Array[RoomCombatant] = dungeon.get_rooms()[0].get_enemies()
	var a: BasicEnemy = enemies[0] as BasicEnemy
	var b: BasicEnemy = enemies[1] as BasicEnemy
	_record(is_same(a.stats, _enemy_data) and is_same(b.stats, _enemy_data),
		"7) both enemies in room 1 read the same EnemyData — configuration is shared by design")
	_record(_seeded_from(a, _enemy_data) and _seeded_from(b, _enemy_data),
		"8) and each is seeded from it: health, damage, XP, speed, ranges, navigation")

	a.health_component.take_damage(DamageInfo.new(30.0))
	await _pause(0.1)
	_record(is_equal_approx(a.health_component.current_health, 70.0),
		"9) damaging enemy A takes it to 70 (%.0f)" % a.health_component.current_health)
	_record(is_equal_approx(b.health_component.current_health, 100.0),
		"10) enemy B keeps its own 100 (%.0f)" % b.health_component.current_health)
	_record(is_equal_approx(_enemy_data.max_health, 100.0),
		"11) and the asset's max_health is still 100 — nothing wrote to it")
	var bar: EnemyHealthBar3D = a.get_node("EnemyHealthBar3D")
	_record(is_equal_approx(bar.get_ratio(), 0.7),
		"12) A's health bar reads A's runtime health (ratio %.2f)" % bar.get_ratio())

	var speed: float = a.movement_speed
	var damage: float = a.attack.attack_damage
	a.movement_speed = 0.0
	a.attack.attack_damage = 99.0
	_record(is_equal_approx(b.movement_speed, 3.8) and is_equal_approx(b.attack.attack_damage, 15.0),
		"13) retuning A in play leaves B at 3.8 speed and 15 damage")
	_record(is_equal_approx(_enemy_data.movement_speed, 3.8)
			and is_equal_approx(_enemy_data.attack_damage, 15.0),
		"14) and leaves the asset untouched too")
	a.movement_speed = speed
	a.attack.attack_damage = damage


# --- 15-17. the boss is seeded from BossData, not from its scene ------------------------

func _phase_boss() -> void:
	var dungeon: DungeonController = current_scene as DungeonController
	var boss: DungeonBoss = dungeon.get_rooms()[2].get_enemies()[0] as DungeonBoss
	_record(is_equal_approx(boss.max_health, 900.0)
			and is_equal_approx(boss.health_component.max_health, 900.0)
			and is_equal_approx(boss.health_component.current_health, 900.0),
		"15) the boss starts at 900 / 900 — its scene no longer carries a stale 600")
	_record(boss.get_xp_reward() == _boss_data.xp_reward,
		"16) and is worth the asset's %d XP" % _boss_data.xp_reward)
	boss.health_component.take_damage(DamageInfo.new(50.0))
	await _pause(0.1)
	_record(is_equal_approx(boss.health_component.current_health, 850.0)
			and is_equal_approx(_boss_data.max_health, 900.0),
		"17) a wound lowers the boss's health, never the asset's (%.0f, asset %.0f)" % [
			boss.health_component.current_health, _boss_data.max_health])


# --- 18-20. the player's progression reads its curve from ProgressionStats ----------------

func _phase_progression() -> void:
	var p: Player = current_scene.get_node("Player")
	var prog: PlayerProgression = p.progression
	var curve: Array[int] = []
	for level in range(1, 6):
		curve.append(prog.xp_required_for_level(level))
	var expected: Array[int] = [100, 125, 156, 195, 244]
	_record(curve == expected, "18) the XP curve is unchanged: %s" % [curve])
	_record(prog.stat_points_per_level == _progression.stat_points_per_level
			and prog.max_level == _progression.max_level
			and is_equal_approx(prog.melee_damage_per_point, _progression.melee_damage_per_point)
			and is_equal_approx(prog.health_per_vitality_point, _progression.health_per_vitality_point),
		"19) points per level, the cap and the derived-stat rates all come from the asset")
	_record(prog.current_level == _progression.starting_level
			and prog.strength == _progression.strength and prog.current_xp == 0,
		"20) and a new character starts from its starting block (Lv.%d, STR %d)" % [
			prog.current_level, prog.strength])


# --- 21-24. editing an asset is enough to change an enemy ---------------------------------

func _phase_editing_the_asset() -> void:
	# What a designer does in the editor: a variant of the archetype with other
	# numbers, dropped on an enemy. No script is touched.
	var variant: EnemyData = _enemy_data.duplicate() as EnemyData
	variant.max_health = 250.0
	variant.attack_damage = 40.0
	variant.xp_reward = 99
	variant.movement_speed = 5.0
	var enemy: BasicEnemy = (load(ENEMY_SCENE) as PackedScene).instantiate() as BasicEnemy
	enemy.stats = variant
	enemy.combat_enabled = false
	current_scene.add_child(enemy)
	enemy.global_position = PARKING
	await _pause(0.2)
	_record(is_equal_approx(enemy.health_component.max_health, 250.0)
			and is_equal_approx(enemy.health_component.current_health, 250.0),
		"21) an enemy given a 250 HP asset starts at 250 / 250")
	_record(is_equal_approx(enemy.attack.hitbox.damage, 40.0) and enemy.get_xp_reward() == 99
			and is_equal_approx(enemy.nav_agent.max_speed, 5.0),
		"22) hits for 40, is worth 99 XP and moves at 5.0 — all from the asset")
	_record(is_equal_approx(_enemy_data.max_health, 100.0) and _enemy_data.xp_reward == 25,
		"23) the archetype it was copied from is unchanged")
	var dungeon: DungeonController = current_scene as DungeonController
	var b: BasicEnemy = dungeon.get_rooms()[0].get_enemies()[1] as BasicEnemy
	_record(is_equal_approx(b.health_component.max_health, 100.0),
		"24) and the dungeon's own enemies still read 100")
	enemy.queue_free()


# --- 25-30. one ShadowData, many shadows: the template never carries progress --------------

func _phase_shadow_template() -> void:
	var first: ShadowInstance = ShadowInstance.new(&"shadow_900001", _shadow_data, 1, 0)
	var third: ShadowInstance = ShadowInstance.new(&"shadow_900003", _shadow_data, 3, 0)
	_record(is_same(first.shadow_data, third.shadow_data),
		"25) two shadows of one type share one ShadowData")
	_record(is_equal_approx(first.get_max_health(), 80.0) and is_equal_approx(third.get_max_health(), 96.0)
			and is_equal_approx(first.get_damage(), 12.0) and is_equal_approx(third.get_damage(), 16.0),
		"26) and each reads its own level through it: 80 / 12 at Lv.1, 96 / 16 at Lv.3")
	first.add_xp(30)
	_record(first.current_xp == 30 and third.current_xp == 0
			and _shadow_data.base_xp_requirement == 50,
		"27) XP earned by one lands on that instance, not on its sibling or the template")

	var p: Player = current_scene.get_node("Player")
	var shadow: ShadowInstance = p.shadows.add_shadow(_shadow_data)
	var node: BasicMeleeShadow = p.shadow_summoner.summon(shadow.instance_id)
	await _pause(0.4)
	_record(node != null and is_equal_approx(node.health_component.max_health, 80.0)
			and is_equal_approx(node.health_component.current_health, 80.0),
		"28) a summoned shadow takes its 80 HP from its instance — its scene carries no number")
	node.health_component.take_damage(DamageInfo.new(20.0))
	await _pause(0.1)
	_record(is_equal_approx(node.health_component.current_health, 60.0)
			and is_equal_approx(shadow.get_max_health(), 80.0)
			and is_equal_approx(_shadow_data.base_health, 80.0),
		"29) a wound is the entity's alone: the instance and the template still say 80")
	p.shadow_summoner.recall()
	await _pause(0.3)
	_record(shadow.level == 1 and shadow.current_xp == 0 and p.shadows.has_shadow(shadow.instance_id),
		"30) recalling it frees the entity and leaves the instance as it was")


# --- 31. the reward a kill pays is the asset's --------------------------------------------

func _phase_reward_comes_from_the_asset() -> void:
	var dungeon: DungeonController = current_scene as DungeonController
	var p: Player = current_scene.get_node("Player")
	p.hurtbox.set_invulnerable(true)
	p.global_position = ROOM1_ANCHOR
	await _pause(0.8)
	var b: BasicEnemy = dungeon.get_rooms()[0].get_enemies()[1] as BasicEnemy
	var before: int = p.progression.get_total_xp()
	await _kill(p, b)
	await _pause(0.4)
	_record(b.has_died() and p.progression.get_total_xp() - before == _enemy_data.xp_reward,
		"31) killing an enemy pays the player its EnemyData's %d XP" % _enemy_data.xp_reward)


# --- helpers ----------------------------------------------------------------------------------

func _seeded_from(enemy: BasicEnemy, data: EnemyData) -> bool:
	return is_equal_approx(enemy.max_health, data.max_health) \
		and is_equal_approx(enemy.health_component.max_health, data.max_health) \
		and is_equal_approx(enemy.health_component.current_health, data.max_health) \
		and is_equal_approx(enemy.attack.hitbox.damage, data.attack_damage) \
		and enemy.get_xp_reward() == data.xp_reward \
		and is_equal_approx(enemy.movement_speed, data.movement_speed) \
		and is_equal_approx(enemy.detection_range, data.detection_range) \
		and is_equal_approx(enemy.attack_range, data.attack_range) \
		and is_equal_approx(enemy.nav_agent.max_speed, data.movement_speed) \
		and is_equal_approx(enemy.nav_agent.radius, data.enemy_spacing_radius) \
		and enemy.attack.telegraph_color == data.telegraph_color


func _kill(player: Player, target: RoomCombatant, budget: float = 40.0) -> void:
	var elapsed: float = 0.0
	while elapsed < budget and not target.has_died():
		if player.combat.get_state() == PlayerCombat.State.IDLE:
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
