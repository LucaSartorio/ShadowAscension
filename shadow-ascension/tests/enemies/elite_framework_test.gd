extends Node3D

## M12.7 — the elite framework: any archetype made elite by one data profile
## (`EliteModifierData`, `BasicEnemy.elite_profile`), with the same scene, script,
## state machine and attacks. Normal against elite, archetype by archetype, under
## the player's whole M11 kit; the shared assets checked untouched throughout.
##
##   godot --headless --path . res://tests/enemies/elite_framework_test.tscn
##
## Every section spawns what it needs and frees it again. Allies that only need
## to be there are "frozen": awake but not processing. Every tick a watcher
## checks each enemy's attack phase against its state, and every health change
## against its maximum.

const MELEE_SCENE: PackedScene = preload("res://scenes/enemies/basic_melee_enemy.tscn")
const RANGED_SCENE: PackedScene = preload("res://scenes/enemies/basic_ranged_enemy.tscn")
const TANK_SCENE: PackedScene = preload("res://scenes/enemies/basic_tank_enemy.tscn")
const ASSASSIN_SCENE: PackedScene = preload("res://scenes/enemies/basic_assassin_enemy.tscn")
const SUPPORT_SCENE: PackedScene = preload("res://scenes/enemies/basic_support_enemy.tscn")
const INDICATOR_SCENE: PackedScene = preload("res://scenes/ui/target_lock_indicator.tscn")
const ELITE: EliteModifierData = preload("res://resources/enemies/elite_standard.tres")
const MELEE_DATA: EnemyData = preload("res://resources/enemies/basic_melee_enemy.tres")
const RANGED_DATA: EnemyData = preload("res://resources/enemies/basic_ranged_enemy.tres")
const TANK_DATA: EnemyData = preload("res://resources/enemies/basic_tank_enemy.tres")
const ASSASSIN_DATA: EnemyData = preload("res://resources/enemies/basic_assassin_enemy.tres")
const SUPPORT_DATA: EnemyData = preload("res://resources/enemies/basic_support_enemy.tres")
const SHADOW_DATA: ShadowData = preload("res://resources/shadows/basic_melee_shadow.tres")
const HOME: Vector3 = Vector3(0, 0.1, 0)
const IN_REACH: Vector3 = Vector3(0, 0.1, -2.1)
const PARK: Vector3 = Vector3(35, 0.1, 35)
const DT: float = 1.0 / 60.0
const PHYSICS_BUDGET: float = 1.0 / 60.0
const CROWD: int = 10
## The heavy's push, before the target's own multiplier.
const HEAVY_PUSH: float = 8.0

@onready var _player: Player = $Player
@onready var _nav_region: NavigationRegion3D = $NavigationRegion3D

var _spawned: Array = []
var _watched: Array = []
var _violations: Array[String] = []
var _health_violations: Array[String] = []
## Every hit an enemy's swing or projectile landed: {target, amount, attack_id, source, accepted}.
var _hits: Array[Dictionary] = []
## Every support action that landed: {support, ally, action, amount}.
var _applied: Array[Dictionary] = []
var _transitions: Dictionary = {}
var _clock: float = 0.0
var _count: int = 0
var _pass: int = 0
var _fail: int = 0
## The shared assets as they were at the start — compared at the end.
var _snapshot: Array = []

var _no_crits: PlayerCombatData = preload("res://resources/characters/player_combat.tres")


func _ready() -> void:
	_no_crits.critical_chance = 0.0
	_nav_region.bake_navigation_mesh(false)
	_reset_session()
	_snapshot = _shared_values()
	_run()


func _physics_process(delta: float) -> void:
	_clock += delta
	for candidate in _watched:
		if not is_instance_valid(candidate) or not (candidate as Node).is_inside_tree():
			continue
		var e: BasicEnemy = candidate
		var phase: EnemyAttack.Phase = e.get_attack_phase()
		if (e.get_state() == BasicEnemy.State.ATTACK) != (phase != EnemyAttack.Phase.NONE):
			_violations.append("%s %s/%s" % [e.name, BasicEnemy.State.keys()[e.get_state()], EnemyAttack.Phase.keys()[phase]])


func _run() -> void:
	await _wait(0.4)
	_profile_tests()
	await _resource_safety_tests()
	await _health_tests()
	await _melee_tests()
	await _ranged_tests()
	await _tank_tests()
	await _assassin_tests()
	await _support_tests()
	await _support_heals_elite_tests()
	await _buff_tests()
	await _player_kit_tests()
	await _reward_tests()
	await _multiple_tests()
	await _lock_tests()
	await _validation_tests()
	await _normal_regression_tests()
	await _mixed_tests()
	await _stress_tests()
	await _wait(0.3)
	_record(_violations.is_empty() and _health_violations.is_empty(),
		"IV1) every tick, on every enemy: an attack phase exactly in ATTACK; no health ever above its maximum %s %s" % [
			_violations.slice(0, 3), _health_violations.slice(0, 3)])
	_record(_shared_values() == _snapshot,
		"IV2) after everything: every EnemyData, AttackData, EnemySupportData and the elite profile exactly as they were — nothing shared was ever written")
	print("[SUMMARY] passed=%d failed=%d" % [_pass, _fail])
	get_tree().quit()


# --- the profile --------------------------------------------------------------------------------------

func _profile_tests() -> void:
	var neutral: EliteModifierData = EliteModifierData.new()
	_record(ELITE.health_multiplier == 1.6 and ELITE.damage_multiplier == 1.2 and ELITE.move_speed_multiplier == 1.05
			and ELITE.cooldown_multiplier == 0.85 and ELITE.stagger_resistance_multiplier == 1.3
			and ELITE.knockback_taken_multiplier == 0.7 and ELITE.xp_reward_multiplier == 2.0 and ELITE.is_valid(),
		"CF1) elite_standard: health x1.6, damage x1.2, speed x1.05, cooldown x0.85 (15% shorter), stagger resistance x1.3, knockback taken x0.7, XP x2")
	var fields: Array = []
	for property in ELITE.get_property_list():
		if int(property["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE:
			fields.append(property["name"])
	var only_multipliers: bool = fields.size() == 7 and fields.all(func(f: String) -> bool: return f.ends_with("_multiplier"))
	var identity: bool = [neutral.health_multiplier, neutral.damage_multiplier, neutral.move_speed_multiplier,
		neutral.cooldown_multiplier, neutral.stagger_resistance_multiplier, neutral.knockback_taken_multiplier,
		neutral.xp_reward_multiplier].all(func(m: float) -> bool: return m == 1.0)
	_record(only_multipliers and identity and neutral.effective_max_health(100.0) == 100.0
			and neutral.effective_xp_reward(25) == 25,
		"CF2) the profile holds seven multipliers and nothing else — no base value repeated — and its defaults, a normal enemy's, change nothing (%s)" % [fields])


# --- resource safety --------------------------------------------------------------------------------------

func _resource_safety_tests() -> void:
	var a: BasicEnemy = await _spawn(MELEE_SCENE, PARK)
	var b: BasicEnemy = await _spawn(MELEE_SCENE, PARK + Vector3(4, 0, 0), null, ELITE)
	_record(a.stats == b.stats and a.stats == MELEE_DATA and a.attack.attacks[0] == b.attack.attacks[0]
			and a.get_script() == b.get_script() and a.scene_file_path == b.scene_file_path
			and a.attack.get_script() == b.attack.get_script()
			and a.get_rank() == BasicEnemy.Rank.NORMAL and b.get_rank() == BasicEnemy.Rank.ELITE
			and not a.is_elite() and b.is_elite(),
		"RS1) a normal and an elite melee: the same EnemyData, AttackData, scene, script and attack component — NORMAL and ELITE, the rank read from the profile alone")
	_record(a.max_health == 100.0 and a.attack.attack_damage == 15.0 and a.movement_speed == 3.8
			and a.stagger_resistance == 25.0 and a.knockback_multiplier == 1.0 and a.attack.attack_cooldown == 0.4
			and a.get_xp_reward() == 25,
		"RS2) the normal one keeps the base exactly: 100 HP, 15 damage, 3.8 m/s, stagger 25, knockback x1.0, cooldown 0.4 s, 25 XP")
	_record(b.max_health == 160.0 and is_equal_approx(b.attack.attack_damage, 18.0) and is_equal_approx(b.movement_speed, 3.99)
			and is_equal_approx(b.stagger_resistance, 32.5) and is_equal_approx(b.knockback_multiplier, 0.7)
			and is_equal_approx(b.attack.attack_cooldown, 0.34) and b.get_xp_reward() == 50
			and is_equal_approx(b.nav_agent.max_speed, 3.99),
		"RS3) the elite, from the same assets: 160 HP, 18 damage, 3.99 m/s (its navigation too), stagger 32.5, knockback x0.7, cooldown 0.34 s, 50 XP")
	_record(_shared_values() == _snapshot and MELEE_DATA.max_health == 100.0 and MELEE_DATA.attack_damage == 15.0
			and MELEE_DATA.attacks[0].damage_multiplier == 1.0 and ELITE.health_multiplier == 1.6,
		"RS4) and the melee's EnemyData, its AttackData and the elite profile are unchanged: the elite's values are its own runtime copies")
	await _clear()


func _health_tests() -> void:
	var elite: BasicEnemy = await _spawn(MELEE_SCENE, PARK, null, ELITE)
	var normal: BasicEnemy = await _spawn(MELEE_SCENE, PARK + Vector3(4, 0, 0))
	var bar: EnemyHealthBar3D = elite.get_node("EnemyHealthBar3D") as EnemyHealthBar3D
	var normal_bar: EnemyHealthBar3D = normal.get_node("EnemyHealthBar3D") as EnemyHealthBar3D
	var started_full: bool = elite.health_component.max_health == 160.0 and elite.health_component.current_health == 160.0 \
		and bar.label.text == "160 / 160" and bar.get_ratio() == 1.0
	elite.hurtbox.receive_hit(DamageInfo.new(40.0, _player, &"test"))
	_record(started_full and elite.health_component.current_health == 120.0 and is_equal_approx(bar.get_ratio(), 0.75)
			and bar.label.text == "120 / 160",
		"HP1) base 100 x 1.6: the elite starts at 160 of 160 — full at the effective maximum, never at the base — and 40 damage leaves its bar at 120 / 160 (0.75)")
	var frame: StandardMaterial3D = bar.background.get_surface_override_material(0) as StandardMaterial3D
	var plain: StandardMaterial3D = normal_bar.background.get_surface_override_material(0) as StandardMaterial3D
	_record(bar.is_elite_tag_visible() and bar.elite_tag.text == "ELITE" and not normal_bar.is_elite_tag_visible()
			and frame.albedo_color.r > 0.8 and frame.albedo_color.g > 0.6 and plain.albedo_color.r < 0.2,
		"VS1) the elite reads as one: an ELITE tag over its bar, up even while the bar is hidden, and a gold frame round the bar; the normal one has neither")
	elite.hurtbox.receive_hit(DamageInfo.new(1000.0, _player, &"test"))
	await _frames(3)
	_record(elite.get_state() == BasicEnemy.State.DEAD and not bar.is_elite_tag_visible(),
		"VS2) dead, its tag goes at once — and the rest of it with the node")
	await _clear()


# --- archetype by archetype ----------------------------------------------------------------------------------

func _melee_tests() -> void:
	var normal: Dictionary = await _melee_cycle(null)
	var elite: Dictionary = await _melee_cycle(ELITE)
	_record(normal["damage"] == 15.0 and is_equal_approx(elite["damage"], 18.0),
		"ME1) melee, normal against elite: a swing of %.1f against %.1f — 15 x 1.2, applied once" % [normal["damage"], elite["damage"]])
	_record(absf(elite["telegraph"] - normal["telegraph"]) <= 2.0 * DT and absf(elite["active"] - normal["active"]) <= 2.0 * DT
			and absf(elite["recovery"] - normal["recovery"]) <= 2.0 * DT and absf(elite["telegraph"] - 0.35) <= 2.0 * DT,
		"ME2) the same swing: telegraph %.2f / %.2f s, active %.2f / %.2f s, recovery %.2f / %.2f s — the archetype's timing, untouched" % [
			normal["telegraph"], elite["telegraph"], normal["active"], elite["active"], normal["recovery"], elite["recovery"]])
	_record(absf(normal["cooldown"] - 0.4) <= 2.0 * DT and absf(elite["cooldown"] - 0.34) <= 2.0 * DT,
		"ME3) only the gap between swings shortens: %.2f s against %.2f s (0.4 x 0.85)" % [normal["cooldown"], elite["cooldown"]])
	var speeds: Array = await _race(MELEE_SCENE)
	_record(speeds[0] <= 3.81 and speeds[1] > speeds[0] + 0.1 and speeds[1] <= 4.0,
		"ME4) side by side from 8 m: the normal runs at up to %.2f m/s, the elite at %.2f (3.8 x 1.05)" % [speeds[0], speeds[1]])
	var normal_combo: Array = await _light_combo_against(MELEE_SCENE, null)
	var elite_combo: Array = await _light_combo_against(MELEE_SCENE, ELITE)
	_record(normal_combo[0] == [20.0, 25.0, 35.0] and elite_combo[0] == normal_combo[0]
			and normal_combo[1] == [false, false, true] and elite_combo[1] == [false, false, false],
		"ME5) the same light combo: %s on both; Light 3 (30) staggers the normal (25) but not the elite (32.5) %s / %s" % [
			elite_combo[0], normal_combo[1], elite_combo[1]])
	var normal_heavy: Array = await _heavy_against(MELEE_SCENE, null)
	var elite_heavy: Array = await _heavy_against(MELEE_SCENE, ELITE)
	_record(normal_heavy[2] and elite_heavy[2] and normal_heavy[0] == elite_heavy[0]
			and absf(normal_heavy[1] - HEAVY_PUSH) < 0.01 and absf(elite_heavy[1] - HEAVY_PUSH * 0.7) < 0.01,
		"ME6) the same heavy: %.0f damage to both, both staggered (60 beats 25 and 32.5), pushed at %.1f against %.1f m/s — 30%% less" % [
			normal_heavy[0], normal_heavy[1], elite_heavy[1]])


## One enemy's second attack cycle, measured: its telegraph, active, recovery,
## the cooldown before the third, and its swing's damage.
func _melee_cycle(profile: EliteModifierData) -> Dictionary:
	_home_player()
	_player.hurtbox.set_invulnerable(true)
	var enemy: BasicEnemy = await _spawn(MELEE_SCENE, IN_REACH, null, profile)
	enemy.set_combat_enabled(true)
	var result: Dictionary = await _cycle_of(enemy)
	await _clear()
	return result


func _cycle_of(enemy: BasicEnemy) -> Dictionary:
	var first: int = _hits.size()
	await _until(func() -> bool: return enemy.get_attack_phase() == EnemyAttack.Phase.TELEGRAPH, 240)
	await _until(func() -> bool: return enemy.get_attack_phase() == EnemyAttack.Phase.NONE, 240)
	await _until(func() -> bool: return enemy.get_attack_phase() == EnemyAttack.Phase.TELEGRAPH, 360)
	var began: float = _clock
	await _until(func() -> bool: return enemy.get_attack_phase() != EnemyAttack.Phase.TELEGRAPH, 120)
	var telegraph: float = _clock - began
	began = _clock
	await _until(func() -> bool: return enemy.get_attack_phase() != EnemyAttack.Phase.ACTIVE, 120)
	var active: float = _clock - began
	began = _clock
	await _until(func() -> bool: return enemy.get_attack_phase() != EnemyAttack.Phase.RECOVERY, 120)
	var recovery: float = _clock - began
	began = _clock
	await _until(func() -> bool: return enemy.get_attack_phase() == EnemyAttack.Phase.TELEGRAPH, 360)
	var cooldown: float = _clock - began
	var mine: Array[Dictionary] = _hits.slice(first).filter(func(h: Dictionary) -> bool: return h["source"] == enemy)
	return {"telegraph": telegraph, "active": active, "recovery": recovery, "cooldown": cooldown,
		"damage": mine[0]["amount"] if not mine.is_empty() else -1.0}


## The fastest a normal and an elite of `scene` run, side by side from 8 m.
func _race(scene: PackedScene) -> Array:
	_home_player()
	_player.hurtbox.set_invulnerable(true)
	var normal: BasicEnemy = await _spawn(scene, HOME + Vector3(-1.5, 0, -8))
	var elite: BasicEnemy = await _spawn(scene, HOME + Vector3(1.5, 0, -8), null, ELITE)
	normal.set_combat_enabled(true)
	elite.set_combat_enabled(true)
	var fastest: Array[float] = [0.0, 0.0]
	await _until(func() -> bool:
		if normal.get_state() == BasicEnemy.State.CHASE:
			fastest[0] = maxf(fastest[0], _flat(normal.velocity).length())
		if elite.get_state() == BasicEnemy.State.CHASE:
			fastest[1] = maxf(fastest[1], _flat(elite.velocity).length())
		return false, 150)
	await _clear()
	return fastest


func _ranged_tests() -> void:
	var normal: Dictionary = await _ranged_cycle(null)
	var elite: Dictionary = await _ranged_cycle(ELITE)
	_record(normal["damage"] == 12.0 and is_equal_approx(elite["damage"], 14.4) and normal["scene"] == elite["scene"]
			and normal["speed"] == elite["speed"] and normal["lifetime"] == elite["lifetime"],
		"RA1) ranged, normal against elite: a bolt of %.1f against %.1f (12 x 1.2, snapshot at the shot) — the same projectile scene, speed (%.0f m/s) and lifetime" % [
			normal["damage"], elite["damage"], elite["speed"]])
	_record(absf(normal["cooldown"] - 1.6) <= 2.0 * DT and absf(elite["cooldown"] - 1.36) <= 2.0 * DT
			and absf(elite["telegraph"] - normal["telegraph"]) <= 2.0 * DT,
		"RA2) the same %.2f s telegraph; the cooldown %.2f s against %.2f s (1.6 x 0.85)" % [
			elite["telegraph"], normal["cooldown"], elite["cooldown"]])
	var e: BasicEnemy = await _spawn(RANGED_SCENE, PARK, null, ELITE)
	_record(e.max_health == 112.0 and is_equal_approx(e.stagger_resistance, 32.5) and e.get_xp_reward() == 50
			and e.preferred_combat_distance == 7.0 and e.minimum_combat_distance == 4.0 and e.attack_range == 10.0,
		"RA3) the elite ranged: 112 HP (70 x 1.6), stagger 32.5, 50 XP — and the same 4 / 7 / 10 m it keeps")
	await _clear()


func _ranged_cycle(profile: EliteModifierData) -> Dictionary:
	_home_player()
	_player.hurtbox.set_invulnerable(true)
	var enemy: BasicEnemy = await _spawn(RANGED_SCENE, HOME + Vector3(0, 0, -7), null, profile)
	var shots: Array = []
	(enemy.attack as EnemyRangedAttack).fired.connect(func(p: Projectile) -> void:
		shots.append({"speed": p.get_speed(), "lifetime": p.get_lifetime_remaining(), "damage": p.hitbox.damage,
			"scene": p.scene_file_path}))
	enemy.set_combat_enabled(true)
	var result: Dictionary = await _cycle_of(enemy)
	await _clear()
	if not shots.is_empty():
		result["damage"] = shots[0]["damage"]
		result["speed"] = shots[0]["speed"]
		result["lifetime"] = shots[0]["lifetime"]
		result["scene"] = shots[0]["scene"]
	return result


func _tank_tests() -> void:
	var tank: BasicEnemy = await _spawn(TANK_SCENE, PARK, null, ELITE)
	var assassin: BasicEnemy = await _spawn(ASSASSIN_SCENE, PARK + Vector3(4, 0, 0))
	_record(tank.max_health == 416.0 and is_equal_approx(tank.stagger_resistance, 58.5)
			and is_equal_approx(tank.knockback_multiplier, 0.245) and is_equal_approx(tank.attack.attack_damage, 24.0)
			and is_equal_approx(tank.movement_speed, 2.52) and tank.movement_speed < assassin.movement_speed
			and tank.get_xp_reward() == 100,
		"TK1) the elite tank: 416 HP (260 x 1.6), stagger 58.5, knockback x0.245, base damage 24, 2.52 m/s — still far slower than an assassin (5.6) — 100 XP")
	await _clear()
	var normal_combo: Array = await _light_combo_against(TANK_SCENE, null)
	var elite_combo: Array = await _light_combo_against(TANK_SCENE, ELITE)
	var normal_heavy: Array = await _heavy_against(TANK_SCENE, null)
	var elite_heavy: Array = await _heavy_against(TANK_SCENE, ELITE)
	_record(normal_combo[1] == [false, false, false] and elite_combo[1] == [false, false, false]
			and normal_heavy[2] and elite_heavy[2] and absf(normal_heavy[1] - HEAVY_PUSH * 0.35) < 0.01
			and absf(elite_heavy[1] - HEAVY_PUSH * 0.245) < 0.01,
		"TK2) still a tank, still manageable: the light combo staggers neither; the heavy (60) staggers both — 58.5 stays under it — and pushes %.2f against %.2f m/s, never 0" % [
			normal_heavy[1], elite_heavy[1]])
	# Its heavy swing: the attack's own multiplier on the elite base, once.
	_home_player()
	_player.hurtbox.set_invulnerable(true)
	var swinger: BasicEnemy = await _spawn(TANK_SCENE, HOME + Vector3(0, 0, -2.2), null, ELITE)
	var first: int = _hits.size()
	swinger.set_combat_enabled(true)
	await _until(func() -> bool: return _swings_of(swinger, first).size() >= 1, 240)
	var swing: Array[Dictionary] = _swings_of(swinger, first)
	_record(not swing.is_empty() and is_equal_approx(swing[0]["amount"], 36.0),
		"TK3) its heavy swing: 36 — its base 20 x 1.2 = 24, then the swing's own x1.5: each multiplier once")
	await _clear()


func _assassin_tests() -> void:
	_home_player()
	_player.hurtbox.set_invulnerable(true)
	var elite: BasicEnemy = await _spawn(ASSASSIN_SCENE, IN_REACH, null, ELITE)
	var first: int = _hits.size()
	elite.set_combat_enabled(true)
	var farthest: Array[float] = [0.0]
	var disengaged: bool = await _until(func() -> bool:
		if elite.get_state() == BasicEnemy.State.REPOSITION and elite.is_disengaging():
			farthest[0] = maxf(farthest[0], elite.targeting.get_distance())
		return farthest[0] >= 4.0 and elite.get_attack_phase() == EnemyAttack.Phase.TELEGRAPH, 480)
	var strikes: Array[Dictionary] = _swings_of(elite, first)
	_record(elite.max_health == 96.0 and is_equal_approx(elite.movement_speed, 5.88) and elite.movement_speed < 6.0
			and is_equal_approx(elite.stagger_resistance, 26.0) and elite.disengage_distance == 4.5
			and not strikes.is_empty() and is_equal_approx(strikes[0]["amount"], 21.6) and disengaged,
		"AS1) the elite assassin: 96 HP, 5.88 m/s — still under the player's 6 — stagger 26, a strike of 21.6 (18 x 1.2); and the same loop: in, strike, out to %.1f m, back in" % farthest[0])
	await _clear()
	var combo: Array = await _light_combo_against(ASSASSIN_SCENE, ELITE)
	_record(combo[1] == [false, false, true],
		"AS2) Light 3 (30) still staggers the elite assassin (26): fragile stays fragile %s" % [combo[1]])


func _support_tests() -> void:
	_home_player()
	_player.hurtbox.set_invulnerable(true)
	var tank: BasicEnemy = await _ally(TANK_SCENE, HOME + Vector3(-2, 0, -3.5), 0.4)
	var elite: BasicEnemy = await _spawn(SUPPORT_SCENE, Vector3(0, 0.1, -7), _heal_only(), ELITE)
	var first: int = _applied.size()
	elite.set_combat_enabled(true)
	await _until(func() -> bool: return _applied.size() > first, 180)
	var healed: float = _applied[-1]["amount"] if _applied.size() > first else -1.0
	var hit_first: int = _hits.size()
	await _until(func() -> bool: return _swings_of(elite, hit_first).size() >= 1, 60 * 6)
	var bolt: Array[Dictionary] = _swings_of(elite, hit_first)
	_record(elite.max_health == 104.0 and is_equal_approx(elite.stagger_resistance, 26.0) and elite.get_xp_reward() == 60
			and healed == 65.0 and tank.health_component.current_health == 169.0 and elite.support.heal_fraction == 0.25
			and not bolt.is_empty() and is_equal_approx(bolt[0]["amount"], 9.6),
		"SU1) the elite support: 104 HP, stagger 26, 60 XP, a bolt of 9.6 (8 x 1.2) — and its heal the same as any support's, 25% of the ally's maximum (+65 on a tank): its rank never scales the heal")
	await _clear()


func _support_heals_elite_tests() -> void:
	# The one it heals is elite: the share and the amount read its effective maximum.
	_home_player()
	_player.hurtbox.set_invulnerable(true)
	var elite_tank: BasicEnemy = await _ally(TANK_SCENE, HOME + Vector3(-2, 0, -3.5), 0.4, ELITE)
	var normal_tank: BasicEnemy = await _ally(TANK_SCENE, HOME + Vector3(2, 0, -3.5), 0.5)
	var support: BasicEnemy = await _spawn(SUPPORT_SCENE, Vector3(0, 0.1, -7), _heal_only())
	var bar: EnemyHealthBar3D = elite_tank.get_node("EnemyHealthBar3D") as EnemyHealthBar3D
	var first: int = _applied.size()
	support.set_combat_enabled(true)
	await _until(func() -> bool: return support.support.get_support_target() != null, 120)
	var chose: RoomCombatant = support.support.get_support_target()
	await _until(func() -> bool: return _applied.size() > first, 180)
	var landed: Dictionary = _applied[-1] if _applied.size() > first else {}
	_record(chose == elite_tank and chose != normal_tank and normal_tank.health_component.current_health == 130.0
			and not landed.is_empty() and landed["ally"] == elite_tank
			and is_equal_approx(landed["amount"], 104.0) and is_equal_approx(elite_tank.health_component.current_health, 270.4)
			and is_equal_approx(bar.get_ratio(), 270.4 / 416.0),
		"SE1) an elite tank at 166 of 416 (40%%) beside a normal one at 130 of 260 (50%%): the support picks the elite — by share of its effective maximum — and heals 104, a quarter of 416, not of 260; its bar at %.2f" % bar.get_ratio())
	# Healed past the base maximum: clamped at the effective one.
	elite_tank.health_component.current_health = 166.4
	# Its heal cooldown, then possibly a bolt already under way and its cooldown.
	var casting: bool = await _until(func() -> bool:
		return support.support.is_casting() and support.support.get_support_target() == elite_tank, 60 * 12)
	elite_tank.health_component.current_health = 400.0
	await _until(func() -> bool: return _applied.size() > first + 1, 120)
	_record(casting and _applied.size() == first + 2 and is_equal_approx(_applied[-1]["amount"], 16.0)
			and elite_tank.health_component.current_health == 416.0,
		"SE2) healed from 400: to 416 — its effective maximum, far past the tank's base 260 — and no further")
	await _clear()


func _buff_tests() -> void:
	# An elite buffed: the buff on top of the elite damage, and back to it after.
	_home_player()
	_player.hurtbox.set_invulnerable(true)
	var melee: BasicEnemy = await _spawn(MELEE_SCENE, IN_REACH, null, ELITE)
	melee.set_combat_enabled(true)
	var quick: EnemyData = SUPPORT_DATA.duplicate() as EnemyData
	quick.support = SUPPORT_DATA.support.duplicate() as EnemySupportData
	quick.support.buff_duration = 2.0
	var support: BasicEnemy = await _spawn(SUPPORT_SCENE, Vector3(0, 0.1, -7), quick)
	var before: float = melee.attack.get_attack_damage()
	support.set_combat_enabled(true)
	var buffed: bool = await _until(func() -> bool: return melee.attack.has_damage_buff(), 180)
	var during: float = melee.attack.get_attack_damage()
	await _until(func() -> bool: return melee.get_attack_phase() == EnemyAttack.Phase.TELEGRAPH, 120)
	var from_hit: int = _hits.size()
	await _until(func() -> bool: return _swings_of(melee, from_hit).size() >= 1, 120)
	var swing: Array[Dictionary] = _swings_of(melee, from_hit)
	await _until(func() -> bool: return not melee.attack.has_damage_buff(), 60 * 3)
	var after: float = melee.attack.get_attack_damage()
	_record(buffed and is_equal_approx(before, 18.0) and is_equal_approx(during, 21.6) and not swing.is_empty()
			and is_equal_approx(swing[0]["amount"], 21.6) and after == melee.attack.attack_damage and is_equal_approx(after, 18.0)
			and MELEE_DATA.attack_damage == 15.0,
		"BU1) an elite melee buffed by a support: base 15 -> elite 18 (static, at spawn) -> buffed 21.6 (runtime, a swing of %.1f) -> 18 again when it ends — the elite's, not the base's, and nothing written" % [
			swing[0]["amount"] if not swing.is_empty() else -1.0])
	await _clear()


# --- the player's kit against an elite ----------------------------------------------------------------------------

func _player_kit_tests() -> void:
	# A critical Light 1: the player's damage, not the elite's rank, decides it.
	_home_player()
	_player.hurtbox.set_invulnerable(true)
	var elite: BasicEnemy = await _spawn(MELEE_SCENE, HOME + Vector3(0, 0, -1.6), null, ELITE)
	var normal: BasicEnemy = await _spawn(MELEE_SCENE, PARK)
	var taken: Array[DamageInfo] = []
	elite.health_component.damaged.connect(func(hit: DamageInfo) -> void: taken.append(hit))
	var marks: int = _player.combat_feedback.get_critical_mark_count()
	var stops: int = _player.combat_feedback.get_hit_stop_count()
	_no_crits.critical_chance = 1.0
	_player.combat.reset()
	_player.combat._start_attack(_player.combat.data.light_combo, 0)
	await _until(func() -> bool: return taken.size() >= 1, 60)
	var marked: bool = _player.combat_feedback.get_critical_mark_count() > marks
	var stopped: bool = _player.combat_feedback.get_hit_stop_count() > stops
	var shaking: bool = _player.camera_rig.is_shaking()
	_no_crits.critical_chance = 0.0
	await _until(func() -> bool: return not _player.combat.is_attacking(), 60)
	_record(taken.size() == 1 and taken[0].is_critical and taken[0].amount == 30.0 and not elite.is_staggered()
			and marked and stopped and shaking,
		"CR1) a critical Light 1 on an elite: 30 (20 x 1.5) — the elite's rank takes nothing off and adds nothing on; no stagger (10 < 32.5); its mark, the hit stop and the camera shake as for anyone")
	await _clear()

	# Its swing dodged through: the i-frames take it, the hitbox no bigger.
	_home_player()
	elite = await _spawn(MELEE_SCENE, IN_REACH, null, ELITE)
	normal = await _spawn(MELEE_SCENE, PARK)
	var elite_box: Vector3 = (elite.attack.hitbox.get_node("CollisionShape3D").shape as BoxShape3D).size
	var normal_box: Vector3 = (normal.attack.hitbox.get_node("CollisionShape3D").shape as BoxShape3D).size
	var hp: float = _player.health_component.current_health
	var first: int = _hits.size()
	elite.set_combat_enabled(true)
	await _until(func() -> bool:
		return elite.get_attack_phase() == EnemyAttack.Phase.TELEGRAPH and elite.attack.get_phase_remaining() <= 0.08, 120)
	var speed: float = _player.effective_dodge_speed
	_player.effective_dodge_speed = 0.0
	var stamina: float = _player.combat.get_stamina()
	_press(&"dodge")
	var paid: float = stamina - _player.combat.get_stamina()
	await _until(func() -> bool: return elite.get_attack_phase() == EnemyAttack.Phase.RECOVERY, 60)
	_player.effective_dodge_speed = speed
	var reached: Array[Dictionary] = _swings_of(elite, first)
	_record(reached.size() == 1 and not reached[0]["accepted"] and _player.health_component.current_health == hp
			and paid == _player.combat.data.dodge_stamina_cost and elite_box == normal_box,
		"DG1) an elite's swing dodged into: refused inside the i-frames — no damage, %.0f stamina — its hitbox the melee's own size: more dangerous, not unavoidable" % paid)
	await _clear()


# --- rewards --------------------------------------------------------------------------------------------------

func _reward_tests() -> void:
	# The player's kill: the effective reward, once.
	_home_player()
	_player.hurtbox.set_invulnerable(true)
	var elite: BasicEnemy = await _spawn(MELEE_SCENE, HOME + Vector3(0, 0, -1.6), null, ELITE)
	var deaths: Array[int] = [0]
	elite.enemy_died.connect(func(_dead: RoomCombatant) -> void: deaths[0] += 1)
	_player.combat.reset()
	_player.combat._start_attack(_player.combat.data.light_combo, 0)
	await _until(func() -> bool: return not _player.combat.is_attacking(), 60)
	var xp: int = _player.progression.get_total_xp()
	elite.hurtbox.receive_hit(DamageInfo.new(5000.0, _player, &"test"))
	elite.hurtbox.receive_hit(DamageInfo.new(5000.0, _player, &"test"))
	await _frames(5)
	_record(deaths[0] == 1 and _player.progression.get_total_xp() - xp == 50 and elite.claim_xp() == 0,
		"XP1) the player kills an elite melee: base 25 x 2 = 50 XP, once — a second blow on the dead changes nothing")
	await _clear()

	# The shadow's kill: the split is of the effective reward.
	var shadow: BasicMeleeShadow = await _summon(HOME + Vector3(2, 0, -2))
	_home_player()
	_player.hurtbox.set_invulnerable(true)
	elite = await _spawn(MELEE_SCENE, HOME + Vector3(0, 0, -5), null, ELITE)
	elite.health_component.current_health = 5.0
	var player_xp: int = _player.progression.get_total_xp()
	var shadow_xp: int = _shadow_total_xp(shadow.instance)
	_player.shadow_commander.set_mode(BasicMeleeShadow.CommandMode.AGGRESSIVE)
	shadow.global_position = elite.global_position + Vector3(0, 0, 1.4)
	shadow.set_manual_target(elite)
	var killed: bool = await _until(func() -> bool: return elite.has_died(), 60 * 8)
	await _frames(5)
	var shadow_gain: int = _shadow_total_xp(shadow.instance) - shadow_xp
	var player_gain: int = _player.progression.get_total_xp() - player_xp
	_record(killed and elite.get_killer() == shadow and shadow_gain == 35 and player_gain == 15,
		"XP2) the shadow kills an elite melee: 50 effective — shadow +%d (70%%), player +%d (30%%) — not 70/30 of the base 25" % [
			shadow_gain, player_gain])
	await _clear()

	# Player and shadow on it at once: one death, one reward, to the blow that killed.
	_home_player()
	_player.hurtbox.set_invulnerable(true)
	elite = await _spawn(MELEE_SCENE, HOME + Vector3(0, 0, -1.6), null, ELITE)
	elite.health_component.current_health = 6.0
	deaths = [0]
	elite.enemy_died.connect(func(_dead: RoomCombatant) -> void: deaths[0] += 1)
	player_xp = _player.progression.get_total_xp()
	shadow_xp = _shadow_total_xp(shadow.instance)
	shadow.global_position = elite.global_position + Vector3(1.2, 0, 0.6)
	shadow.set_manual_target(elite)
	_player.combat.reset()
	_player.combat._start_attack(_player.combat.data.light_combo, 0)
	killed = await _until(func() -> bool: return elite.has_died(), 60 * 6)
	await _frames(10)
	shadow_gain = _shadow_total_xp(shadow.instance) - shadow_xp
	player_gain = _player.progression.get_total_xp() - player_xp
	var by_shadow: bool = elite.get_killer() == shadow
	var split_right: bool = (by_shadow and shadow_gain == 35 and player_gain == 15) \
		or (not by_shadow and elite.get_killer() == _player and shadow_gain == 0 and player_gain == 50)
	_record(killed and deaths[0] == 1 and split_right and shadow_gain + player_gain == 50 and elite.claim_xp() == 0,
		"XP3) player and shadow strike it together: one death, one reward of 50 — to the killing blow (%s: shadow +%d, player +%d), never twice" % [
			"the shadow's" if by_shadow else "the player's", shadow_gain, player_gain])
	_player.shadow_commander.set_mode(BasicMeleeShadow.CommandMode.FOLLOW)
	_player.shadow_summoner.recall()
	await _clear()


# --- several elites, the lock, validation -----------------------------------------------------------------------

func _multiple_tests() -> void:
	_home_player()
	_player.hurtbox.set_invulnerable(true)
	var group: Array[BasicEnemy] = []
	for i in 3:
		var angle: float = deg_to_rad(-50.0 + 50.0 * i)
		var scene: PackedScene = TANK_SCENE if i == 2 else MELEE_SCENE
		var e: BasicEnemy = await _spawn(scene, HOME + Vector3(sin(angle), 0, -cos(angle)) * 5.0, null, ELITE)
		e.initial_attack_delay = 0.3 * i
		e.combat_angle_offset_degrees = -40.0 + 40.0 * i
		group.append(e)
	for e in group:
		e.set_combat_enabled(true)
	group[0].hurtbox.receive_hit(DamageInfo.new(50.0, _player, &"test"))
	var apart: Array[bool] = [false]
	await _until(func() -> bool:
		var cooling: Array = group.map(func(e: BasicEnemy) -> float: return e.attack.get_cooldown_remaining())
		if cooling.max() > 0.0 and not (cooling[0] == cooling[1] and cooling[1] == cooling[2]):
			apart[0] = true
		return group.all(func(e: BasicEnemy) -> bool: return e.attack.get_swing_count() >= 1) and apart[0], 600)
	_record(group[0].health_component.current_health == 110.0 and group[1].health_component.current_health == 160.0
			and group[2].health_component.current_health == 416.0 and apart[0]
			and group.all(func(e: BasicEnemy) -> bool: return e.elite_profile == ELITE and e.attack.get_swing_count() >= 1)
			and ELITE.health_multiplier == 1.6,
		"MU1) three elites sharing one profile: each its own health (110 / 160 / 416), cooldown, state and swings — the profile shared, read, never written")
	await _clear()


func _lock_tests() -> void:
	var indicator: TargetLockIndicator = INDICATOR_SCENE.instantiate() as TargetLockIndicator
	add_child(indicator)
	await _frames(3)
	_home_player()
	_player.hurtbox.set_invulnerable(true)
	var elite: BasicEnemy = await _spawn(MELEE_SCENE, HOME + Vector3(0, 0, -6), null, ELITE)
	var normal: BasicEnemy = await _spawn(MELEE_SCENE, HOME + Vector3(4, 0, -6))
	await _frames(2)
	_press(&"target_lock")
	var locked: bool = _player.targeting.get_target() == elite and indicator.is_showing()
	var tag: Label3D = (elite.get_node("EnemyHealthBar3D") as EnemyHealthBar3D).elite_tag
	var apart: float = tag.global_position.y - indicator.global_position.y
	_press(&"target_switch_right")
	await _frames(1)
	var switched: bool = _player.targeting.get_target() == normal
	_press(&"target_switch_left")
	await _frames(1)
	var back: bool = _player.targeting.get_target() == elite
	_record(locked and switched and back and tag.visible and apart > 1.0,
		"LK1) the player locks an elite like any enemy, switches to a normal one and back — no priority either way; the ELITE tag stands %.1f m above the lock's ring, both readable" % apart)
	_player.targeting.unlock()
	indicator.queue_free()
	await _clear()


func _validation_tests() -> void:
	var broken: EliteModifierData = ELITE.duplicate() as EliteModifierData
	broken.health_multiplier = 0.0
	broken.damage_multiplier = -2.0
	var enemy: BasicEnemy = await _spawn(MELEE_SCENE, PARK, null, broken)
	_record(not broken.is_valid() and ELITE.is_valid() and is_equal_approx(enemy.max_health, 10.0)
			and enemy.health_component.current_health > 0.0 and is_equal_approx(enemy.attack.attack_damage, 1.5)
			and enemy.get_state() != BasicEnemy.State.DEAD,
		"VA1) a profile with a zero health and a negative damage multiplier is reported invalid, and clamped (x0.1): an enemy of 10 HP and 1.5 damage, alive — never 0 or negative")
	await _clear()


# --- normal enemies untouched -------------------------------------------------------------------------------------

func _normal_regression_tests() -> void:
	var scenes: Array[PackedScene] = [MELEE_SCENE, RANGED_SCENE, TANK_SCENE, ASSASSIN_SCENE, SUPPORT_SCENE]
	var datas: Array[EnemyData] = [MELEE_DATA, RANGED_DATA, TANK_DATA, ASSASSIN_DATA, SUPPORT_DATA]
	var exact: bool = true
	var wrong: Array[String] = []
	for i in scenes.size():
		var e: BasicEnemy = await _spawn(scenes[i], PARK + Vector3(4 * i, 0, 0))
		var d: EnemyData = datas[i]
		var same: bool = e.max_health == d.max_health and e.health_component.current_health == d.max_health \
			and e.movement_speed == d.movement_speed and e.stagger_resistance == d.stagger_resistance \
			and e.knockback_multiplier == d.knockback_multiplier and e.attack.attack_damage == d.attack_damage \
			and e.attack.attack_cooldown == d.attack_cooldown and e.get_xp_reward() == d.xp_reward \
			and e.get_rank() == BasicEnemy.Rank.NORMAL \
			and not (e.get_node("EnemyHealthBar3D") as EnemyHealthBar3D).is_elite_tag_visible()
		if not same:
			wrong.append(String(e.name))
		exact = exact and same
	_record(exact,
		"RG1) the five archetypes, normal: health, speed, stagger resistance, knockback, damage, cooldown and XP exactly their EnemyData's — the neutral profile changes nothing %s" % [wrong])
	await _clear()


# --- normal and elite together ------------------------------------------------------------------------------------

func _mixed_tests() -> void:
	var indicator: TargetLockIndicator = INDICATOR_SCENE.instantiate() as TargetLockIndicator
	add_child(indicator)
	await _frames(3)
	_home_player()
	_player.hurtbox.set_invulnerable(true)
	var melee: BasicEnemy = await _spawn(MELEE_SCENE, HOME + Vector3(-3, 0, -8))
	var elite_melee: BasicEnemy = await _spawn(MELEE_SCENE, HOME + Vector3(-1, 0, -8), null, ELITE)
	var ranged: BasicEnemy = await _spawn(RANGED_SCENE, HOME + Vector3(0, 0, -10))
	var elite_tank: BasicEnemy = await _spawn(TANK_SCENE, HOME + Vector3(2, 0, -8), null, ELITE)
	var assassin: BasicEnemy = await _spawn(ASSASSIN_SCENE, HOME + Vector3(-5, 0, -8))
	var support: BasicEnemy = await _spawn(SUPPORT_SCENE, HOME + Vector3(5, 0, -10), _heal_only())
	var six: Array[BasicEnemy] = [melee, elite_melee, ranged, elite_tank, assassin, support]
	for e in six:
		e.set_combat_enabled(true)
	var first_hit: int = _hits.size()
	var disengaged: Array[bool] = [false]
	var physics: Array[float] = [0.0]
	var ticks: Array[int] = [0]
	await _until(func() -> bool:
		ticks[0] += 1
		physics[0] += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)
		disengaged[0] = disengaged[0] or (assassin.get_state() == BasicEnemy.State.REPOSITION and assassin.is_disengaging())
		return false, 360)
	var hits: Array[Dictionary] = _hits.slice(first_hit)
	var amounts: Dictionary = {}
	for h in hits:
		var source: Node = h["source"]
		if not amounts.has(source):
			amounts[source] = h["amount"]
	var tags: Array = six.filter(func(e: BasicEnemy) -> bool:
		return (e.get_node("EnemyHealthBar3D") as EnemyHealthBar3D).is_elite_tag_visible())
	_record(tags.size() == 2 and tags.has(elite_melee) and tags.has(elite_tank)
			and amounts.get(melee, 0.0) == 15.0 and is_equal_approx(amounts.get(elite_melee, 0.0), 18.0)
			and amounts.get(ranged, 0.0) == 12.0 and disengaged[0]
			and six.all(func(e: BasicEnemy) -> bool: return e.get_script() == melee.get_script() and e.get_target() == _player),
		"MX1) normal melee, elite melee, ranged, elite tank, assassin and support together: two ELITE tags, the elites' blows heavier (18 against 15), the ranged's bolt 12, the assassin disengaging — one state machine for all six")
	# The elite tank hurt: the support heals it on its effective maximum.
	elite_tank.health_component.current_health = 166.4
	var first: int = _applied.size()
	var healed: bool = await _until(func() -> bool: return _applied.size() > first, 60 * 5)
	_record(healed and _applied[-1]["ally"] == elite_tank and is_equal_approx(_applied[-1]["amount"], 104.0),
		"MX2) the elite tank brought to 40% mid-fight: the support heals it for 104 — a quarter of its 416")
	# The player's kit across them: lock, switch, light, critical heavy, dodge.
	_player.global_position = HOME + Vector3(0, 0, 2)
	_player.camera_rig.rotation.y = 0.0
	await _frames(2)
	_press(&"target_lock")
	var locked: Dictionary = {}
	for action in [&"target_switch_left", &"target_switch_left", &"target_switch_left", &"target_switch_left",
			&"target_switch_left", &"target_switch_right", &"target_switch_right", &"target_switch_right",
			&"target_switch_right", &"target_switch_right", &"target_switch_right", &"target_switch_right"]:
		var target: RoomCombatant = _player.targeting.get_target()
		if target != null:
			locked[target] = true
		_press(action)
		await _frames(1)
	var stamina: float = _player.combat.get_stamina()
	_player.combat.reset()
	_player.camera_rig.attack_light_pressed.emit()
	await _until(func() -> bool: return not _player.combat.is_attacking(), 90)
	_no_crits.critical_chance = 1.0
	_player.camera_rig.attack_heavy_pressed.emit()
	await _until(func() -> bool: return not _player.combat.is_attacking(), 120)
	_no_crits.critical_chance = 0.0
	_press(&"dodge")
	var spent: bool = _player.combat.get_stamina() < stamina
	await _frames(30)
	var average: float = physics[0] / maxf(ticks[0], 1.0)
	_record(locked.size() == 6 and locked.has(elite_melee) and locked.has(elite_tank) and spent and _violations.is_empty()
			and average < PHYSICS_BUDGET,
		"MX3) the lock switched across all six, elite or not, a light, a critical heavy and a dodge thrown in, stamina spent — every state machine consistent, %.2f ms of physics a tick" % [
			average * 1000.0])
	_player.targeting.unlock()
	indicator.queue_free()
	await _clear()


func _stress_tests() -> void:
	_home_player()
	_player.hurtbox.set_invulnerable(true)
	var crowd: Array[BasicEnemy] = []
	for i in CROWD * 2:
		var angle: float = TAU * float(i) / float(CROWD * 2)
		var e: BasicEnemy = await _spawn(MELEE_SCENE, HOME + Vector3(cos(angle), 0, sin(angle)) * 7.0, null,
			ELITE if i % 2 == 0 else null)
		e.combat_angle_offset_degrees = float(i * 23 % 90) - 45.0
		crowd.append(e)
	for e in crowd:
		e.set_combat_enabled(true)
	await _frames(60)
	var physics: float = 0.0
	var worst: float = 0.0
	for tick in 180:
		await get_tree().physics_frame
		var t: float = Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)
		physics += t
		worst = maxf(worst, t)
	var average: float = physics / 180.0
	var elites: Array = crowd.filter(func(e: BasicEnemy) -> bool: return e.is_elite())
	_record(average < PHYSICS_BUDGET and elites.size() == CROWD
			and elites.all(func(e: BasicEnemy) -> bool: return is_same(e.elite_profile, ELITE) and e.max_health == 160.0)
			and crowd.all(func(e: BasicEnemy) -> bool: return e.get_target() == _player),
		"PF1) %d elites and %d normals on the player for 3 s: %.2f ms of physics a tick (%.2f at worst) — the rank applied once at spawn, one shared profile, nothing duplicated or recomputed per tick" % [
			CROWD, CROWD, average * 1000.0, worst * 1000.0])
	await _clear()
	_record(_spawned.is_empty() and get_children().filter(func(c: Node) -> bool: return c is BasicEnemy).is_empty(),
		"PF2) and freed again: nothing of the crowd left behind")


# --- helpers ---------------------------------------------------------------------------------------------------------

func _light_combo_against(scene: PackedScene, profile: EliteModifierData) -> Array:
	_home_player()
	_player.hurtbox.set_invulnerable(true)
	var enemy: BasicEnemy = await _spawn(scene, HOME + Vector3(0, 0, -1.6), null, profile)
	enemy.health_component.set_max_health(5000.0)
	enemy.health_component.current_health = 5000.0
	var taken: Array[float] = []
	var staggered: Array[bool] = []
	enemy.health_component.damaged.connect(func(hit: DamageInfo) -> void:
		taken.append(hit.amount)
		staggered.append(enemy.is_staggered()))
	_player.combat.reset()
	_player.camera_rig.attack_light_pressed.emit()
	var frames: int = 0
	while _player.combat.is_attacking() and frames < 300:
		await get_tree().physics_frame
		frames += 1
		if _player.combat.get_state() == PlayerCombat.State.RECOVERY and _player.combat.get_queued_attack() == null \
				and _player.combat.get_combo_index() < 2:
			_player.camera_rig.attack_light_pressed.emit()
	await _clear()
	return [taken, staggered]


## The heavy on one enemy of `scene`: [its damage, the push's speed, whether it staggered].
func _heavy_against(scene: PackedScene, profile: EliteModifierData) -> Array:
	_home_player()
	_player.hurtbox.set_invulnerable(true)
	var enemy: BasicEnemy = await _spawn(scene, HOME + Vector3(0, 0, -1.6), null, profile)
	enemy.health_component.set_max_health(5000.0)
	enemy.health_component.current_health = 5000.0
	var result: Array = [0.0, 0.0, false]
	enemy.health_component.damaged.connect(func(hit: DamageInfo) -> void:
		result[0] = hit.amount
		result[1] = enemy.get_knockback_velocity().length()
		result[2] = enemy.is_staggered())
	_player.combat.reset()
	_player.combat._start_attack(_player.combat.data.heavy_combo, 0)
	await _until(func() -> bool: return result[0] > 0.0, 90)
	await _clear()
	return result


func _heal_only() -> EnemyData:
	var d: EnemyData = SUPPORT_DATA.duplicate() as EnemyData
	d.support = SUPPORT_DATA.support.duplicate() as EnemySupportData
	d.support.buff_action = null
	return d


func _spawn(scene: PackedScene, at: Vector3, data: EnemyData = null, profile: EliteModifierData = null) -> BasicEnemy:
	var enemy: BasicEnemy = scene.instantiate() as BasicEnemy
	_count += 1
	enemy.name = "%s%s%d" % ["Elite" if profile != null else "",
		String(enemy.name).trim_prefix("Basic").trim_suffix("Enemy"), _count]
	enemy.combat_enabled = false
	if data != null:
		enemy.stats = data
	# Set before it enters the tree, as whatever places it would: the rank is
	# applied when the enemy readies.
	enemy.elite_profile = profile
	# Placed before it enters the tree: added first, it would stand at the origin
	# for a physics step and shove whatever is there.
	enemy.position = at
	add_child(enemy)
	_face(enemy, _player.global_position)
	_watch(enemy)
	_spawned.append(enemy)
	await _frames(3)
	return enemy


## An ally that only has to be there: awake — in the fight — but frozen where it
## stands, at `share` of its (effective) health.
func _ally(scene: PackedScene, at: Vector3, share: float, profile: EliteModifierData = null) -> BasicEnemy:
	var enemy: BasicEnemy = await _spawn(scene, at, null, profile)
	enemy.set_combat_enabled(true)
	enemy.set_physics_process(false)
	enemy.health_component.current_health = enemy.health_component.max_health * share
	return enemy


func _watch(enemy: BasicEnemy) -> void:
	_watched.append(enemy)
	_transitions[enemy] = []
	enemy.state_changed.connect(func(from: BasicEnemy.State, to: BasicEnemy.State) -> void:
		(_transitions[enemy] as Array).append("%s>%s" % [BasicEnemy.State.keys()[from], BasicEnemy.State.keys()[to]]))
	var health: HealthComponent = enemy.health_component
	health.health_changed.connect(func(current: float, maximum: float) -> void:
		if current > maximum + 0.0001 or (health.is_dead and current > 0.0):
			_health_violations.append("%s %.1f/%.1f" % [enemy.name, current, maximum]))
	if enemy.support != null:
		enemy.support.support_applied.connect(func(ally: RoomCombatant, action: AttackData, amount: float) -> void:
			_applied.append({"support": enemy.name, "ally": ally, "action": action, "amount": amount}))
	var melee: EnemyMeleeAttack = enemy.attack as EnemyMeleeAttack
	if melee != null:
		melee.hitbox.hit_landed.connect(func(target: Node, hit: DamageInfo) -> void:
			_hits.append({"target": target, "amount": hit.amount, "attack_id": hit.attack_id, "source": hit.source,
				"accepted": false}))
		melee.hitbox.hit_accepted.connect(func(_target: Node, _hit: DamageInfo) -> void:
			_hits[-1]["accepted"] = true)
	var ranged: EnemyRangedAttack = enemy.attack as EnemyRangedAttack
	if ranged != null:
		ranged.fired.connect(func(projectile: Projectile) -> void:
			projectile.hitbox.hit_landed.connect(func(target: Node, hit: DamageInfo) -> void:
				_hits.append({"target": target, "amount": hit.amount, "attack_id": hit.attack_id, "source": hit.source,
					"accepted": false}))
			projectile.hitbox.hit_accepted.connect(func(_target: Node, _hit: DamageInfo) -> void:
				_hits[-1]["accepted"] = true))


## The hits of `enemy` that reached anyone, since hit number `from`.
func _swings_of(enemy: BasicEnemy, from: int) -> Array[Dictionary]:
	return _hits.slice(from).filter(func(h: Dictionary) -> bool: return h["source"] == enemy)


## Every number the shared assets hold that an elite could have been tempted to
## write: compared before and after.
func _shared_values() -> Array:
	var values: Array = []
	for d in [MELEE_DATA, RANGED_DATA, TANK_DATA, ASSASSIN_DATA, SUPPORT_DATA]:
		var data: EnemyData = d
		values.append([data.max_health, data.movement_speed, data.attack_damage, data.attack_cooldown,
			data.stagger_resistance, data.knockback_multiplier, data.xp_reward])
		for a in data.attacks:
			var attack: AttackData = a
			values.append([attack.damage_multiplier, attack.windup, attack.active, attack.recovery,
				attack.stagger_power, attack.knockback_force, attack.projectile_speed])
	var s: EnemySupportData = SUPPORT_DATA.support
	values.append([s.heal_fraction, s.heal_threshold, s.buff_damage_bonus, s.buff_duration])
	values.append([ELITE.health_multiplier, ELITE.damage_multiplier, ELITE.move_speed_multiplier,
		ELITE.cooldown_multiplier, ELITE.stagger_resistance_multiplier, ELITE.knockback_taken_multiplier,
		ELITE.xp_reward_multiplier])
	return values


func _clear() -> void:
	for enemy in _spawned:
		if is_instance_valid(enemy):
			(enemy as Node).queue_free()
	_spawned.clear()
	for child in get_children():
		if child is Projectile:
			child.queue_free()
	_player.targeting.unlock()
	_no_crits.critical_chance = 0.0
	await _frames(3)


func _summon(at: Vector3) -> BasicMeleeShadow:
	var shadow: ShadowInstance = _player.shadows.add_shadow(SHADOW_DATA)
	var node: BasicMeleeShadow = _player.shadow_summoner.summon(shadow.instance_id)
	await _frames(2)
	node.global_position = at
	node.hurtbox.set_invulnerable(false)
	await _frames(2)
	return node


func _shadow_total_xp(shadow: ShadowInstance) -> int:
	var total: int = shadow.current_xp
	for level in range(1, shadow.level):
		total += shadow.shadow_data.xp_required_for_level(level)
	return total


func _home_player(at: Vector3 = HOME) -> void:
	_player.combat.reset()
	_player.global_position = at
	_player.velocity = Vector3.ZERO
	_player.camera_rig.rotation.y = 0.0
	_player.health_component.current_health = _player.health_component.max_health
	_player.hurtbox.set_invulnerable(false)
	_player.combat.restore_stamina(_player.combat.get_max_stamina())


func _face(enemy: BasicEnemy, point: Vector3) -> void:
	var to: Vector3 = _flat(point - enemy.global_position)
	if to.length_squared() > 0.0001:
		enemy.visual_root.rotation.y = atan2(-to.x, -to.z)


func _press(action: StringName) -> void:
	var event: InputEventAction = InputEventAction.new()
	event.action = action
	event.pressed = true
	_player._unhandled_input(event)


func _until(condition: Callable, budget: int = 120) -> bool:
	var n: int = 0
	while not condition.call():
		if n >= budget:
			return false
		await get_tree().physics_frame
		n += 1
	return true


func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


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
	var state: Node = get_tree().root.get_node_or_null("PlayerRuntimeState")
	if state != null:
		state.reset_runtime_state()
