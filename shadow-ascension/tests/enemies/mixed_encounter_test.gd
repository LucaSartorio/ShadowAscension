extends Node3D

## M12.9 — every archetype at once, and an elite: the M12 closure's stress test.
##
##   godot --headless --path . res://tests/enemies/mixed_encounter_test.tscn
##
## A melee, a ranged, a tank, an assassin, a support and two elites (a melee and
## a hurt tank) fight the real player round two pillars, on real navigation. The
## run checks that each keeps its role together with the others, that the
## support heals on the elite's effective maximum, that nothing stays stuck or
## has its push overwritten, that the lock can walk the whole encounter, that a
## shadow can fight and kill in it and be paid, that an enemy killed in any state
## does nothing afterwards, and that the searches stay on their cadence.

const MELEE: PackedScene = preload("res://scenes/enemies/basic_melee_enemy.tscn")
const RANGED: PackedScene = preload("res://scenes/enemies/basic_ranged_enemy.tscn")
const TANK: PackedScene = preload("res://scenes/enemies/basic_tank_enemy.tscn")
const ASSASSIN: PackedScene = preload("res://scenes/enemies/basic_assassin_enemy.tscn")
const SUPPORT: PackedScene = preload("res://scenes/enemies/basic_support_enemy.tscn")
const ELITE: EliteModifierData = preload("res://resources/enemies/elite_standard.tres")
const DT: float = 1.0 / 60.0

@onready var _player: Player = $Player
@onready var _indicator: TargetLockIndicator = $TargetLockIndicator
@onready var _nav_region: NavigationRegion3D = $NavigationRegion3D

var _combat_data: PlayerCombatData = preload("res://resources/characters/player_combat.tres")
var _shadow_data: ShadowData = preload("res://resources/shadows/basic_melee_shadow.tres")

var _pass: int = 0
var _fail: int = 0
var _melee: BasicEnemy = null
var _ranged: BasicEnemy = null
var _tank: BasicEnemy = null
var _assassin: BasicEnemy = null
var _support: BasicEnemy = null
var _elite_melee: BasicEnemy = null
var _elite_tank: BasicEnemy = null
var _shadow: BasicMeleeShadow = null
## Every enemy of the run, dead or alive, for the invariants. Untyped: a freed
## one is skipped by the validity check, never assigned to a typed variable.
var _all: Array = []
var _violations: Array[String] = []


func _ready() -> void:
	_combat_data.critical_chance = 0.0
	_nav_region.bake_navigation_mesh(false)
	_reset_session()
	_player.hurtbox.set_invulnerable(true)
	_run()


func _physics_process(_delta: float) -> void:
	for entry in _all:
		if not is_instance_valid(entry):
			continue
		var enemy: BasicEnemy = entry as BasicEnemy
		if enemy.has_died() and (enemy.get_attack_phase() != EnemyAttack.Phase.NONE or _hitbox_open(enemy)):
			_violations.append("%s acting while dead" % enemy.name)


func _run() -> void:
	await _wait(0.5)
	await _setup()
	await _encounter_tests()
	await _knockback_test()
	await _lock_tests()
	await _shadow_tests()
	await _death_tests()
	await _model_swap_tests()
	await _aftermath_tests()
	print("[SUMMARY] passed=%d failed=%d" % [_pass, _fail])
	get_tree().quit()


func _setup() -> void:
	var shadow: ShadowInstance = _player.shadows.add_shadow(_shadow_data)
	_shadow = _player.shadow_summoner.summon(shadow.instance_id)
	await _frames(3)
	_shadow.hurtbox.set_invulnerable(true)
	_player.shadow_commander.set_mode(BasicMeleeShadow.CommandMode.FOLLOW)
	# All within their detection ranges of the player (10-12 m), round the pillars.
	_melee = _spawn(MELEE, Vector3(-5, 0.1, -6), null)
	_ranged = _spawn(RANGED, Vector3(6, 0.1, -8), null)
	_tank = _spawn(TANK, Vector3(0, 0.1, -8), null)
	_assassin = _spawn(ASSASSIN, Vector3(-7, 0.1, 4), null)
	_support = _spawn(SUPPORT, Vector3(7, 0.1, 4), null)
	_elite_melee = _spawn(MELEE, Vector3(4, 0.1, -6), ELITE)
	_elite_tank = _spawn(TANK, Vector3(-3, 0.1, -8), ELITE)
	await _frames(2)
	_elite_tank.health_component.current_health = _elite_tank.health_component.max_health * 0.4
	_record(_elite_melee.is_elite() and _elite_melee.health_component.max_health == 160.0
			and _elite_tank.is_elite() and _elite_tank.health_component.max_health == 416.0
			and not _melee.is_elite() and _melee.health_component.max_health == 100.0
			and _tank.health_component.max_health == 260.0,
		"S1) seven enemies: the five archetypes normal at their data, an elite melee (160) and an elite tank (416)")


# --- 77-79, 81, 94. the encounter -----------------------------------------------------------------------------

func _encounter_tests() -> void:
	var starts: Dictionary = {}
	var min_dist: Dictionary = {}
	var engaged: Dictionary = {}
	for e in _all:
		starts[e] = e.global_position
		min_dist[e] = INF
		engaged[e] = false
	var ranged_samples: int = 0
	var ranged_in_band: int = 0
	var disengaged: bool = false
	var healed: Array[float] = [0.0]
	_support.support.support_applied.connect(func(ally: RoomCombatant, action: AttackData, amount: float) -> void:
		if ally == _elite_tank and action == _support.support.heal_action:
			healed[0] = amount)
	var refreshes_before: int = 0
	for e in _all:
		refreshes_before += e.targeting.get_refresh_count()
	var scans_before: int = _support.support.get_scan_count()
	var projectiles_peak: int = 0
	var clock: float = 0.0
	while clock < 14.0:
		_player.global_position = Vector3(0, 0.1, 0)
		await get_tree().physics_frame
		clock += DT
		for e in _all:
			min_dist[e] = minf(min_dist[e], _flat(e.global_position - _player.global_position).length())
			engaged[e] = engaged[e] or e.get_target() == _player
		if clock > 4.0:
			ranged_samples += 1
			var d: float = _flat(_ranged.global_position - _player.global_position).length()
			if d >= 3.5 and d <= 10.5:
				ranged_in_band += 1
		disengaged = disengaged or _assassin.is_disengaging()
		projectiles_peak = maxi(projectiles_peak, _projectiles())
	var refreshes: int = -refreshes_before
	for e in _all:
		refreshes += e.targeting.get_refresh_count()

	_record(min_dist[_melee] <= 2.2 and _melee.attack.get_swing_count() >= 1
			and min_dist[_elite_melee] <= 2.2 and _elite_melee.attack.get_swing_count() >= 1,
		"78a) the melee and the elite melee close in and swing (%.1f m, %.1f m)" % [min_dist[_melee], min_dist[_elite_melee]])
	_record(ranged_samples > 0 and float(ranged_in_band) / ranged_samples >= 0.8
			and (_ranged.attack as EnemyRangedAttack).get_shot_count() >= 1,
		"78b) the ranged keeps its 4-10 m (%.0f%% of the time) and fires (%d shots)" % [
			100.0 * ranged_in_band / maxi(ranged_samples, 1), (_ranged.attack as EnemyRangedAttack).get_shot_count()])
	_record(min_dist[_tank] <= 2.8 and _tank.attack.get_swing_count() >= 1,
		"78c) the tank reaches the front and swings (%.1f m)" % min_dist[_tank])
	_record(_assassin.attack.get_swing_count() >= 1 and disengaged,
		"78d) the assassin strikes and backs out to its ring")
	_record(is_equal_approx(healed[0], 104.0) and _elite_tank.health_component.current_health > 260.0,
		"78e/81) the support heals the hurt elite tank for %.0f — a quarter of its effective 416 — past a normal tank's whole 260" % healed[0])
	var stuck: Array[String] = []
	for e in _all:
		var moved: float = _flat(e.global_position - starts[e]).length()
		if not engaged[e] or (moved < 1.0 and e.attack.get_swing_count() < 1):
			stuck.append(e.name)
	_record(stuck.is_empty(), "79a) no one stays stuck: each takes the player on and moves or attacks%s" % [
		"" if stuck.is_empty() else " — stuck: %s" % [stuck]])
	_record(refreshes <= _all.size() * 2 and _support.support.get_scan_count() - scans_before <= int(14.0 / 0.5) + 2
			and projectiles_peak <= 4,
		"94) the searches stay on their cadence: %d target searches for 7 enemies holding a target, %d ally looks in 14 s, at most %d projectiles in the air" % [
			refreshes, _support.support.get_scan_count() - scans_before, projectiles_peak])


## 79) a push is the physics', never overwritten by the AI.
func _knockback_test() -> void:
	var at: Vector3 = _melee.global_position
	var away: Vector3 = _flat(_melee.global_position - _player.global_position).normalized()
	var hit: DamageInfo = DamageInfo.new(1.0, _player, &"test_push")
	hit.knockback_force = 8.0
	hit.direction = away
	_melee.hurtbox.receive_hit(hit)
	var pushed: bool = _melee.is_knocked_back()
	await _frames(12)
	var moved: float = _flat(_melee.global_position - at).dot(away)
	var resumed: bool = await _until(func() -> bool:
		_player.global_position = Vector3(0, 0.1, 0)
		return not _melee.is_knocked_back() and _melee.get_target() == _player, 120)
	_record(pushed and moved > 0.3 and resumed,
		"79b) a push carries the melee %.2f m away from the blow before its AI moves it again" % moved)


## 82) the lock walks the encounter and cleans up after a kill.
func _lock_tests() -> void:
	_aim_at(_tank)
	await _frames(2)
	_press(&"target_lock")
	await _frames(2)
	var seen: Dictionary = {}
	var consistent: bool = _player.targeting.is_locked()
	for i in 7:
		var target: RoomCombatant = _player.targeting.get_target()
		consistent = consistent and target != null and not target.has_died() and _indicator.get_target() == target
		if target != null:
			seen[target] = true
		_press(&"target_switch_right" if i % 2 == 0 else &"target_switch_left")
		await _frames(3)
	var locked: RoomCombatant = _player.targeting.get_target()
	locked.hurtbox.receive_hit(DamageInfo.new(100000.0, _player))
	await _frames(3)
	_record(consistent and seen.size() >= 2 and not _player.targeting.is_locked() and not _indicator.is_showing(),
		"82) lock and switch across %d enemies, the ring always on the one locked; killing it lets the lock go" % seen.size())


## 80) a shadow in the fight: it kills, and is paid 70/30.
func _shadow_tests() -> void:
	var prey: BasicEnemy = _elite_melee if not _elite_melee.has_died() else _melee
	if prey.has_died():
		prey = _spawn(MELEE, Vector3(3, 0.1, -4), null)
		await _frames(2)
	prey.health_component.current_health = 5.0
	var player_xp: int = _player.progression.get_total_xp()
	var shadow_xp: int = _shadow_total_xp(_shadow.instance)
	_player.shadow_commander.set_mode(BasicMeleeShadow.CommandMode.AGGRESSIVE)
	var killed: bool = await _until(func() -> bool:
		_player.global_position = Vector3(0, 0.1, 0)
		_shadow.set_manual_target(prey)
		return prey.has_died(), 900)
	await _wait(0.3)
	var reward: int = prey.get_xp_reward()
	var cut: int = int(round(reward * PlayerProgression.SHADOW_KILL_SHARE))
	var shadow_gain: int = _shadow_total_xp(_shadow.instance) - shadow_xp
	var player_gain: int = _player.progression.get_total_xp() - player_xp
	_record(killed and prey.get_killer() == _shadow and shadow_gain == cut and player_gain == reward - cut,
		"80) in the mixed fight the shadow kills %s: %d XP split 70/30 — shadow +%d, player +%d" % [
			prey.name, reward, shadow_gain, player_gain])
	_player.shadow_commander.set_mode(BasicMeleeShadow.CommandMode.FOLLOW)


## 83) killed in any state, an enemy does nothing afterwards.
func _death_tests() -> void:
	# The first wave's melee have done their part: out of the way, so each
	# newcomer here reaches the player without a crowd in front of it.
	for enemy in [_melee, _tank, _assassin, _elite_melee, _elite_tank]:
		if not (enemy as BasicEnemy).has_died():
			(enemy as BasicEnemy).hurtbox.receive_hit(DamageInfo.new(100000.0, _player))
	await _wait(0.5)
	var results: Array[String] = []
	var chaser: BasicEnemy = _spawn(MELEE, Vector3(0, 0.1, 9.5), null)
	var ok: String = await _kill_when(chaser, func() -> bool: return chaser.get_state() == BasicEnemy.State.CHASE)
	results.append("chase=%s" % ok)
	var telegraphing: BasicEnemy = _spawn(TANK, Vector3(-2, 0.1, 6), null)
	ok = await _kill_when(telegraphing, func() -> bool: return telegraphing.get_attack_phase() == EnemyAttack.Phase.TELEGRAPH)
	results.append("telegraph=%s" % ok)
	var striking: BasicEnemy = _spawn(ASSASSIN, Vector3(2, 0.1, 7), null)
	ok = await _kill_when(striking, func() -> bool: return striking.get_attack_phase() == EnemyAttack.Phase.ACTIVE)
	results.append("active=%s" % ok)
	var recovering: BasicEnemy = _spawn(MELEE, Vector3(-6, 0.1, 3), null)
	ok = await _kill_when(recovering, func() -> bool: return recovering.get_attack_phase() == EnemyAttack.Phase.RECOVERY)
	results.append("recovery=%s" % ok)
	var backing: BasicEnemy = _spawn(ASSASSIN, Vector3(6, 0.1, 4), null)
	ok = await _kill_when(backing, func() -> bool: return backing.is_disengaging())
	results.append("reposition=%s" % ok)
	var shooter: BasicEnemy = _ranged if not _ranged.has_died() else _spawn(RANGED, Vector3(0, 0.1, -9), null)
	ok = await _kill_when(shooter, func() -> bool: return shooter.get_attack_phase() == EnemyAttack.Phase.TELEGRAPH)
	results.append("ranged_telegraph=%s" % ok)
	# A heal cast: a hurt ally for the support to start on.
	var healer: BasicEnemy = _support if not _support.has_died() else _spawn(SUPPORT, Vector3(8, 0.1, 5), null)
	var patient: BasicEnemy = _spawn(TANK, healer.global_position + Vector3(2, 0, 0), null)
	await _frames(2)
	patient.health_component.current_health = patient.health_component.max_health * 0.3
	var patient_hp: Array[float] = [0.0]
	ok = await _kill_when(healer, func() -> bool:
		patient_hp[0] = patient.health_component.current_health
		return healer.support.is_casting(), 900)
	await _wait(1.5)
	if ok == "ok" and patient.health_component.current_health > patient_hp[0] + 0.01:
		ok = "healed after death"
	results.append("heal_cast=%s" % ok)
	_record(not results.any(func(r: String) -> bool: return not r.ends_with("ok")) and _violations.is_empty(),
		"83) killed in chase, telegraph, active, recovery, reposition, a ranged telegraph and a heal cast: no swing, shot, heal or hit window after death %s%s" % [
			results, "" if _violations.is_empty() else " — %s" % [_violations.slice(0, 3)]])


## M13 readiness: a definitive model replaces the placeholder mesh without any
## gameplay script changing. Each archetype here has its MeshInstance3D swapped
## for a bare "Model" node before it enters the tree — the AI, the attack, the
## projectile spawn, the hitbox, the hurtbox and the lock's anchor are not the
## mesh's, so it still fights, reacts, is locked on its anchor and dies.
func _model_swap_tests() -> void:
	var results: Array[String] = []
	for scene in [MELEE, RANGED, TANK, ASSASSIN, SUPPORT]:
		var enemy: BasicEnemy = (scene as PackedScene).instantiate() as BasicEnemy
		var mesh: Node = enemy.get_node("VisualRoot/MeshInstance3D")
		mesh.get_parent().remove_child(mesh)
		mesh.free()
		var model: Node3D = Node3D.new()
		model.name = "Model"
		enemy.get_node("VisualRoot").add_child(model)
		enemy.position = Vector3(0, 0.1, -7)
		add_child(enemy)
		enemy.set_combat_enabled(true)
		_all.append(enemy)
		var fought: bool = await _until(func() -> bool:
			_player.global_position = Vector3(0, 0.1, 0)
			return enemy.attack.get_swing_count() >= 1, 900)
		var hit: DamageInfo = DamageInfo.new(1.0, _player, &"test_hit")
		hit.stagger_power = 1000.0
		hit.knockback_force = 4.0
		hit.direction = _flat(enemy.global_position - _player.global_position).normalized()
		enemy.hurtbox.receive_hit(hit)
		var reacted: bool = enemy.is_staggered() and enemy.is_knocked_back()
		var anchored: bool = enemy.get_target_point().distance_to(enemy.target_anchor.global_position) < 0.001
		enemy.hurtbox.receive_hit(DamageInfo.new(100000.0, _player))
		await _frames(3)
		results.append("%s=%s" % [(scene as PackedScene).resource_path.get_file().get_basename(), fought and reacted and anchored and enemy.has_died() and enemy.mesh_instance == null])
	_record(not results.any(func(r: String) -> bool: return r.ends_with("false")),
		"M13) every archetype with its placeholder mesh swapped for a bare model fights, is staggered and pushed, keeps its lock anchor and dies: %s" % [results])


func _aftermath_tests() -> void:
	for entry in _all:
		if is_instance_valid(entry) and not (entry as BasicEnemy).has_died():
			(entry as BasicEnemy).hurtbox.receive_hit(DamageInfo.new(100000.0, _player))
	await _wait(3.0)
	var leftovers: Array[String] = []
	for entry in _all:
		if not is_instance_valid(entry):
			continue
		var e: BasicEnemy = entry as BasicEnemy
		if e.get_target() != null or e.attack.has_damage_buff() or e.attack.is_attacking() or _hitbox_open(e):
			leftovers.append(e.name)
		if e.support != null and (e.support.get_support_target() != null or e.support.is_casting()):
			leftovers.append(e.name + " (support)")
	_record(leftovers.is_empty() and _projectiles() == 0 and _violations.is_empty(),
		"84a) everyone dead: no target, buff, attack or hit window left, no projectile in the air%s" % [
			"" if leftovers.is_empty() else " — %s" % [leftovers]])


# --- helpers ----------------------------------------------------------------------------------------------------

func _spawn(scene: PackedScene, at: Vector3, profile: EliteModifierData) -> BasicEnemy:
	var enemy: BasicEnemy = scene.instantiate() as BasicEnemy
	enemy.elite_profile = profile
	enemy.position = at
	add_child(enemy)
	enemy.set_combat_enabled(true)
	_all.append(enemy)
	return enemy


## Waits for `condition` on `enemy`, kills it there, and watches it do nothing
## for a second: no swing, no shot, no heal, no hit window. "ok", "unreached" or
## "acted".
func _kill_when(enemy: BasicEnemy, condition: Callable, budget: int = 900) -> String:
	var reached: bool = await _until(func() -> bool:
		_player.global_position = Vector3(0, 0.1, 0)
		return condition.call(), budget)
	if not reached:
		return "unreached"
	var swings: int = enemy.attack.get_swing_count()
	var ranged: EnemyRangedAttack = enemy.attack as EnemyRangedAttack
	var shots: int = ranged.get_shot_count() if ranged != null else 0
	var heals: int = enemy.support.get_heal_count() if enemy.support != null else 0
	enemy.hurtbox.receive_hit(DamageInfo.new(100000.0, _player))
	var quiet: bool = true
	for i in 60:
		await get_tree().physics_frame
		quiet = quiet and enemy.get_attack_phase() == EnemyAttack.Phase.NONE and not _hitbox_open(enemy)
	quiet = quiet and enemy.attack.get_swing_count() == swings \
		and (ranged == null or ranged.get_shot_count() == shots) \
		and (enemy.support == null or enemy.support.get_heal_count() == heals)
	return "ok" if enemy.has_died() and quiet else "acted"


func _hitbox_open(enemy: BasicEnemy) -> bool:
	var melee: EnemyMeleeAttack = enemy.attack as EnemyMeleeAttack
	return melee != null and melee.hitbox != null and melee.hitbox.is_active()


func _projectiles() -> int:
	var n: int = 0
	for node in find_children("*", "Projectile", true, false):
		if not node.is_queued_for_deletion():
			n += 1
	return n


func _shadow_total_xp(shadow: ShadowInstance) -> int:
	var total: int = shadow.current_xp
	for level in range(1, shadow.level):
		total += shadow.shadow_data.xp_required_for_level(level)
	return total


func _aim_at(target: Node3D) -> void:
	var to: Vector3 = _flat(target.global_position - _player.global_position)
	if to.length_squared() > 0.0001:
		_player.camera_rig.rotation.y = atan2(-to.x, -to.z)


func _press(action: StringName) -> void:
	var event: InputEventAction = InputEventAction.new()
	event.action = action
	event.pressed = true
	_player._unhandled_input(event)


func _until(condition: Callable, budget: int) -> bool:
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
