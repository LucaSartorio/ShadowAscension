extends Node3D

## M12.3 — the ranged archetype: the same state machine as the melee, its own
## attack (a telegraphed shot) and its own distances; the projectile it fires,
## from spawn to its end; line of sight; the dodge; interruptions; targets;
## several at once, and beside a melee.
##
##   godot --headless --path . res://tests/enemies/ranged_archetype_test.tscn
##
## Every section spawns what it needs and frees it again, projectiles included.
## Every tick a watcher checks each enemy's attack against its state, and every
## shot is recorded — who fired it, from where, in what state, whom it reached
## and how it ended.

const RANGED_SCENE: PackedScene = preload("res://scenes/enemies/basic_ranged_enemy.tscn")
const MELEE_SCENE: PackedScene = preload("res://scenes/enemies/basic_melee_enemy.tscn")
const PROJECTILE_SCENE: PackedScene = preload("res://scenes/enemies/enemy_projectile.tscn")
const INDICATOR_SCENE: PackedScene = preload("res://scenes/ui/target_lock_indicator.tscn")
const RANGED_DATA: EnemyData = preload("res://resources/enemies/basic_ranged_enemy.tres")
const SHADOW_DATA: ShadowData = preload("res://resources/shadows/basic_melee_shadow.tres")
const HOME: Vector3 = Vector3(0, 0.1, 0)
const PARK: Vector3 = Vector3(35, 0.1, 35)
## The screen wall stands at x 17..23, z -5.3..-4.7; the back wall along z -30.
const SCREEN_X: float = 20.0
const CORNER: Vector3 = Vector3(-20, 0.1, -28.8)
const DT: float = 1.0 / 60.0
const CROWD: int = 8
## A physics tick must fit in one 60 Hz tick, or the game falls behind.
const PHYSICS_BUDGET: float = 1.0 / 60.0

@onready var _player: Player = $Player
@onready var _nav_region: NavigationRegion3D = $NavigationRegion3D

var _bolt: AttackData = null
var _spawned: Array = []
var _watched: Array = []
var _violations: Array[String] = []
## Every shot fired: {enemy, projectile, id, clock, state, from_spawn, direction, speed}.
var _shots: Array[Dictionary] = []
## Every hit a projectile landed: {id, enemy, target, amount, attack_id, source, critical, accepted}.
var _hits: Array[Dictionary] = []
## How each projectile ended, by its instance id.
var _ends: Dictionary = {}
## Per enemy: its transitions as "FROM>TO", and the game time of each.
var _transitions: Dictionary = {}
var _transition_times: Dictionary = {}
var _clock: float = 0.0
var _count: int = 0
var _pass: int = 0
var _fail: int = 0

var _no_crits: PlayerCombatData = preload("res://resources/characters/player_combat.tres")


func _ready() -> void:
	_no_crits.critical_chance = 0.0
	_nav_region.bake_navigation_mesh(false)
	_reset_session()
	_bolt = RANGED_DATA.attacks[0]
	_run()


func _physics_process(delta: float) -> void:
	_clock += delta
	for candidate in _watched:
		if not is_instance_valid(candidate) or not (candidate as Node).is_inside_tree():
			continue
		var e: BasicEnemy = candidate
		var phase: EnemyAttack.Phase = e.get_attack_phase()
		if (e.get_state() == BasicEnemy.State.ATTACK) != (phase != EnemyAttack.Phase.NONE):
			_violations.append("%s %s/%s" % [e.name, BasicEnemy.State.keys()[e.get_state()],
				EnemyAttack.Phase.keys()[phase]])
		var melee: EnemyMeleeAttack = e.attack as EnemyMeleeAttack
		if melee != null and melee.hitbox.is_active() != (phase == EnemyAttack.Phase.ACTIVE):
			_violations.append("%s hitbox" % e.name)


func _run() -> void:
	await _wait(0.4)
	await _config_tests()
	await _detection_and_range_tests()
	await _cornered_tests()
	await _lifecycle_tests()
	await _dodge_tests()
	await _wall_and_sight_tests()
	await _projectile_tests()
	await _interrupt_tests()
	await _death_tests()
	await _multiple_tests()
	await _mixed_tests()
	await _shadow_tests()
	await _lock_tests()
	await _reaction_tests()
	await _performance_tests()
	await _wait(0.3)
	_record(_violations.is_empty(),
		"IV1) every tick, on every enemy: an attack phase exactly in ATTACK, a melee's hitbox open exactly in ACTIVE %s" % [
			_violations.slice(0, 4)])
	_record(_shots.all(func(s: Dictionary) -> bool: return s["state"] == BasicEnemy.State.ATTACK and s["from_spawn"] < 0.05),
		"IV2) all %d shots were fired in ATTACK, from the spawn point — never from a stagger, a death or anywhere else" % _shots.size())
	var ended: bool = _shots.all(func(s: Dictionary) -> bool: return _ends.has(s["id"]))
	_record(ended and _alive_projectiles() == 0,
		"IV3) every one of the %d projectiles ended — %s — and none is left in the scene" % [_shots.size(), _end_counts()])
	_record(_bolt.windup == 0.6 and _bolt.projectile_speed == 12.0 and RANGED_DATA.attack_cooldown == 1.6
			and RANGED_DATA.preferred_combat_distance == 7.0,
		"IV4) the shared EnemyData and AttackData were never written")
	print("[SUMMARY] passed=%d failed=%d" % [_pass, _fail])
	get_tree().quit()


# --- configuration ------------------------------------------------------------------------------------

func _config_tests() -> void:
	var ranged: BasicEnemy = await _spawn(RANGED_SCENE, PARK)
	var melee: BasicEnemy = await _spawn(MELEE_SCENE, PARK + Vector3(4, 0, 0))
	var data: EnemyData = ranged.stats
	_record(data.minimum_combat_distance == 4.0 and data.preferred_combat_distance == 7.0 and data.attack_range == 10.0
			and data.detection_range == 12.0 and data.alert_duration == 0.3 and data.attack_damage == 12.0
			and data.attack_cooldown == 1.6,
		"CF1) the ranged's range model is data: minimum 4 m, preferred 7 m, maximum attack range 10 m; it sees 12 m, alerts 0.3 s, deals 12, cools down 1.6 s")
	_record(_bolt.id == &"ranged_basic_bolt" and _bolt.windup == 0.6 and _bolt.active == 0.1 and _bolt.recovery == 0.5
			and _bolt.damage_multiplier == 1.0 and _bolt.projectile_scene == PROJECTILE_SCENE
			and _bolt.projectile_speed == 12.0 and _bolt.projectile_lifetime == 2.5,
		"CF2) its attack is an AttackData, `ranged_basic_bolt`: telegraph 0.6 s, release 0.1 s, recovery 0.5 s, x1.0, a projectile at 12 m/s living 2.5 s")
	var spawn: Node3D = (ranged.attack as EnemyRangedAttack).projectile_spawn
	_record(ranged.get_script() == melee.get_script() and ranged.attack is EnemyRangedAttack and melee.attack is EnemyMeleeAttack
			and spawn is Marker3D and spawn.get_parent() == ranged.visual_root
			and ranged.find_children("*", "Hitbox", true, false).is_empty(),
		"CF3) the same state machine as the melee (BasicEnemy); only the Attack differs — EnemyRangedAttack, with a ProjectileSpawn marker under VisualRoot and no hitbox on its body")
	_record(ranged.get_state() == BasicEnemy.State.IDLE and ranged.get_target() == null
			and ranged.get_attack_phase() == EnemyAttack.Phase.NONE and (ranged.attack as EnemyRangedAttack).get_shot_count() == 0
			and not ranged.is_engaged(),
		"SP1) spawned: IDLE, no target, no attack under way, nothing fired, not engaged")
	await _clear()


# --- detection and the range model ------------------------------------------------------------------------

func _detection_and_range_tests() -> void:
	# Too far: noticed at 11.5 m, it closes in, and fires only once within 10 m.
	_home_player()
	_player.hurtbox.set_invulnerable(true)
	var ranged: BasicEnemy = await _spawn(RANGED_SCENE, HOME + Vector3(0, 0, -11.5))
	var first_shot: int = _shots.size()
	ranged.set_combat_enabled(true)
	await _until(func() -> bool: return ranged.get_state() == BasicEnemy.State.CHASE, 60)
	var seen: Array = _transitions[ranged]
	var alert: float = _time_of(ranged, "ALERT>CHASE") - _time_of(ranged, "IDLE>ALERT")
	_record(seen.size() >= 2 and seen[0] == "IDLE>ALERT" and seen[1] == "ALERT>CHASE" and absf(alert - 0.3) <= 2.0 * DT,
		"DT1) the player 11.5 m away, inside its 12 m: IDLE -> ALERT, %.2f s facing it, then CHASE" % alert)
	var early: Array[bool] = [false]
	var telegraph_at: Array[float] = [-1.0]
	await _until(func() -> bool:
		var d: float = ranged.targeting.get_distance()
		if ranged.get_attack_phase() == EnemyAttack.Phase.TELEGRAPH and telegraph_at[0] < 0.0:
			telegraph_at[0] = d
		if d > ranged.attack_range + 0.01 and ranged.get_attack_phase() != EnemyAttack.Phase.NONE:
			early[0] = true
		return _shots.size() > first_shot, 300)
	_record(not early[0] and telegraph_at[0] >= 6.9 and telegraph_at[0] <= 10.0,
		"AP1) too far: it closes in, never attacking beyond its 10 m, and starts its telegraph at %.2f m" % telegraph_at[0])
	await _until(func() -> bool: return ranged.get_state() == BasicEnemy.State.CHASE, 60)
	await _wait(1.2)
	var held: float = ranged.targeting.get_distance()
	_record(absf(held - 7.0) < 0.3 and _flat(ranged.velocity).length() < 0.1,
		"AP2) then it closes the rest of the way to its preferred 7 m and stops there (%.2f m)" % held)
	await _clear()

	# In the band: it neither approaches nor backs away — it stands and shoots.
	_home_player()
	_player.hurtbox.set_invulnerable(true)
	ranged = await _spawn(RANGED_SCENE, HOME + Vector3(0, 0, -6))
	var start: Vector3 = ranged.global_position
	first_shot = _shots.size()
	ranged.set_combat_enabled(true)
	var drift: Array[float] = [0.0]
	await _until(func() -> bool:
		drift[0] = maxf(drift[0], _flat(ranged.global_position - start).length())
		return _shots.size() >= first_shot + 2, 400)
	var two: bool = _shots.size() >= first_shot + 2
	_record(two and drift[0] < 0.15,
		"PR1) in the band (6 m, between 4 and 7): it holds its ground — %.2f m of drift over two shots — no approach, no backing away" % drift[0])
	await _clear()

	# Too close: the player at 2.5 m — it backs away before it shoots.
	_home_player()
	_player.hurtbox.set_invulnerable(true)
	ranged = await _spawn(RANGED_SCENE, HOME + Vector3(0, 0, -2.5))
	first_shot = _shots.size()
	ranged.set_combat_enabled(true)
	var shot_from: Array[float] = [-1.0]
	await _until(func() -> bool:
		if ranged.get_attack_phase() == EnemyAttack.Phase.TELEGRAPH and shot_from[0] < 0.0:
			shot_from[0] = ranged.targeting.get_distance()
		return _shots.size() > first_shot, 300)
	var backed: bool = (_transitions[ranged] as Array).has("CHASE>REPOSITION")
	_record(backed and shot_from[0] >= ranged.minimum_combat_distance - 0.01,
		"TC1) too close (2.5 m): CHASE -> REPOSITION, it backs away, facing the player, and shoots only from %.2f m — outside its 4 m minimum" % shot_from[0])
	# Pressed again, and it goes on backing off to its ring rather than turning round at 4 m.
	_player.global_position = ranged.global_position + _flat(_player.global_position - ranged.global_position).normalized() * 3.0
	await _until(func() -> bool: return ranged.get_state() == BasicEnemy.State.REPOSITION, 120)
	var peak: Array[float] = [0.0]
	await _until(func() -> bool:
		peak[0] = maxf(peak[0], ranged.targeting.get_distance())
		return ranged.get_state() != BasicEnemy.State.REPOSITION, 150)
	_record(peak[0] >= 5.5,
		"TC2) pressed inside 4 m again, it backs off toward its 7 m ring (%.2f m reached) rather than turning round at the edge: the hysteresis" % peak[0])
	await _clear()


func _cornered_tests() -> void:
	# Its back to a wall, the player 2.8 m in front: the retreat fails, and it
	# fights from where it stands — without looping, without error.
	_home_player(CORNER + Vector3(0, 0, 2.8))
	_player.hurtbox.set_invulnerable(true)
	var ranged: BasicEnemy = await _spawn(RANGED_SCENE, CORNER)
	var start: Vector3 = ranged.global_position
	var first_shot: int = _shots.size()
	ranged.set_combat_enabled(true)
	var cornered_shot: Array[float] = [-1.0]
	await _until(func() -> bool:
		if _shots.size() > first_shot and cornered_shot[0] < 0.0:
			cornered_shot[0] = ranged.targeting.get_distance()
		return _shots.size() >= first_shot + 2, 480)
	var seen: Array = _transitions[ranged]
	var retreats: int = seen.count("CHASE>REPOSITION")
	_record(retreats >= 1 and seen.has("REPOSITION>CHASE") and cornered_shot[0] > 0.0
			and cornered_shot[0] < ranged.minimum_combat_distance and _flat(ranged.global_position - start).length() < 1.0
			and seen.size() < 30,
		"BR1) cornered against a wall, the player 2.8 m away: REPOSITION times out (%d tries), and it shoots from %.2f m rather than retrying for ever — %d transitions in all" % [
			retreats, cornered_shot[0], seen.size()])
	await _clear()


# --- telegraph -> fire -> recovery -> cooldown ------------------------------------------------------------------

func _lifecycle_tests() -> void:
	_home_player()
	var ranged: BasicEnemy = await _spawn(RANGED_SCENE, HOME + Vector3(0, 0, -7))
	var hp: float = _player.health_component.current_health
	var first_shot: int = _shots.size()
	ranged.set_combat_enabled(true)
	await _until(func() -> bool: return ranged.get_attack_phase() == EnemyAttack.Phase.TELEGRAPH, 90)
	var began: float = _clock
	var none_yet: bool = true
	var tinted: bool = false
	while ranged.get_attack_phase() == EnemyAttack.Phase.TELEGRAPH:
		none_yet = none_yet and _alive_projectiles() == 0 and _player.health_component.current_health == hp
		tinted = tinted or (ranged.visual_root.scale.y > 1.05 and _body_color(ranged).b > 0.8)
		await get_tree().physics_frame
	var telegraph: float = _clock - began
	_record(none_yet and tinted and absf(telegraph - _bolt.windup) <= 2.0 * DT,
		"TG1) the telegraph: %.2f s, no projectile in the scene and no damage, the body rising and turning violet" % telegraph)
	var shot: Dictionary = _shots[first_shot] if _shots.size() > first_shot else {}
	var aim: Vector3 = _player.hurtbox.get_center() - (shot.get("origin", Vector3.ZERO) as Vector3)
	var off: float = rad_to_deg((shot.get("direction", Vector3.FORWARD) as Vector3).angle_to(aim))
	_record(_shots.size() == first_shot + 1 and shot["from_spawn"] < 0.05 and off < 2.0 and shot["speed"] == 12.0
			and shot["enemy"] == ranged,
		"FR1) at its end: one projectile, from the spawn point, aimed at the player's hurtbox (%.1f deg off), at 12 m/s" % off)
	# Release, recovery, while the shot flies.
	await _until(func() -> bool: return ranged.get_attack_phase() == EnemyAttack.Phase.RECOVERY, 30)
	var recovery_start: float = _clock
	await _until(func() -> bool: return ranged.get_attack_phase() == EnemyAttack.Phase.NONE, 60)
	var recovery: float = _clock - recovery_start
	var over: float = _clock
	var id: int = shot.get("id", 0)
	await _until(func() -> bool: return _ends.has(id), 90)
	await get_tree().physics_frame
	var mine: Array[Dictionary] = _hits_of(id)
	_record(_ends.get(id) == Projectile.REASON_HIT and mine.size() == 1 and mine[0]["target"] == _player
			and mine[0]["accepted"] and mine[0]["amount"] == 12.0 and mine[0]["attack_id"] == &"ranged_basic_bolt"
			and mine[0]["source"] == ranged and not mine[0]["critical"] and hp - _player.health_component.current_health == 12.0
			and not is_instance_valid(shot["projectile"]),
		"HT1) it reaches the player: 12 damage, once, from the enemy, named ranged_basic_bolt, never critical — and the projectile is gone")
	# Then the cooldown before the next telegraph.
	await _until(func() -> bool: return ranged.get_attack_phase() == EnemyAttack.Phase.TELEGRAPH, 180)
	var cooldown: float = _clock - over
	_record(absf(recovery - _bolt.recovery) <= 2.0 * DT and absf(cooldown - 1.6) <= 3.0 * DT,
		"RC1) then %.2f s of recovery and %.2f s of cooldown before the next telegraph — never a volley" % [recovery, cooldown])
	await _clear()


# --- the dodge ------------------------------------------------------------------------------------------------

func _dodge_tests() -> void:
	# Through the i-frames: the shot reaches the player mid-dodge and is refused.
	_home_player()
	var ranged: BasicEnemy = await _spawn(RANGED_SCENE, HOME + Vector3(0, 0, -7))
	var hp: float = _player.health_component.current_health
	ranged.set_combat_enabled(true)
	var shot: Dictionary = await _next_shot(ranged)
	var projectile: Projectile = shot["projectile"]
	var speed: float = _player.effective_dodge_speed
	_player.effective_dodge_speed = 0.0
	await _until(func() -> bool:
		return not is_instance_valid(projectile) or projectile.global_position.distance_to(_player.hurtbox.get_center()) < 2.2, 90)
	var stamina: float = _player.combat.get_stamina()
	_press(&"dodge")
	var paid: float = stamina - _player.combat.get_stamina()
	await _until(func() -> bool: return _ends.has(shot["id"]), 200)
	_player.effective_dodge_speed = speed
	var reached: Array[Dictionary] = _hits_of(shot["id"])
	_record(reached.size() == 1 and not reached[0]["accepted"] and _player.health_component.current_health == hp
			and paid == _player.combat.data.dodge_stamina_cost and _ends.get(shot["id"]) != Projectile.REASON_HIT,
		"IF1) the shot reaches the player inside a dodge's i-frames: refused — no damage — and it flies on through (%s); the dodge cost its %.0f stamina" % [
			_ends.get(shot["id"]), paid])
	await _clear()

	# Sideways, for real: the dodge carries the player out of the line and the
	# shot passes by without touching them.
	_home_player()
	ranged = await _spawn(RANGED_SCENE, HOME + Vector3(0, 0, -7))
	hp = _player.health_component.current_health
	ranged.set_combat_enabled(true)
	shot = await _next_shot(ranged)
	Input.action_press(&"move_right")
	await get_tree().physics_frame
	stamina = _player.combat.get_stamina()
	_press(&"dodge")
	paid = stamina - _player.combat.get_stamina()
	await _frames(4)
	Input.action_release(&"move_right")
	await _until(func() -> bool: return _ends.has(shot["id"]), 200)
	_record(_hits_of(shot["id"]).is_empty() and _player.health_component.current_health == hp
			and paid == _player.combat.data.dodge_stamina_cost and _flat(_player.global_position - HOME).length() > 1.0,
		"DG1) a dodge to the side as it fires: the player is out of the line — the shot never touches them — and the dodge cost %.0f stamina" % paid)
	await _clear()

	# Stepping aside after the fire: no homing, the shot keeps its line and misses.
	_home_player()
	ranged = await _spawn(RANGED_SCENE, HOME + Vector3(0, 0, -7))
	hp = _player.health_component.current_health
	ranged.set_combat_enabled(true)
	shot = await _next_shot(ranged)
	projectile = shot["projectile"]
	var launched_at: Vector3 = projectile.global_position
	_player.global_position = HOME + Vector3(2.5, 0, 0)
	await _frames(12)
	var travelled: Vector3 = projectile.global_position - launched_at if is_instance_valid(projectile) else Vector3.ZERO
	var bend: float = rad_to_deg(travelled.angle_to(shot["direction"])) if travelled != Vector3.ZERO else 180.0
	await _until(func() -> bool: return _ends.has(shot["id"]), 200)
	_record(bend < 0.5 and _hits_of(shot["id"]).is_empty() and _player.health_component.current_health == hp
			and _ends.get(shot["id"]) != Projectile.REASON_HIT,
		"MV1) the player steps 2.5 m aside after the fire: the shot keeps its line (%.2f deg of bend) and misses — it ends by %s" % [
			bend, _ends.get(shot["id"])])
	await _clear()


# --- walls and sight -----------------------------------------------------------------------------------------------

func _wall_and_sight_tests() -> void:
	# The shot passes a player it cannot hurt and strikes the wall behind them.
	_home_player(Vector3(SCREEN_X, 0.1, -3.4))
	_player.hurtbox.set_invulnerable(true)
	var ranged: BasicEnemy = await _spawn(RANGED_SCENE, Vector3(SCREEN_X, 0.1, 3.4))
	ranged.set_combat_enabled(true)
	var shot: Dictionary = await _next_shot(ranged)
	await _until(func() -> bool: return _ends.has(shot["id"]), 120)
	await get_tree().physics_frame
	_record(_ends.get(shot["id"]) == Projectile.REASON_WORLD and not is_instance_valid(shot["projectile"]),
		"WL1) a shot that finds the wall stops there: it ends against it (%s) and is freed" % _ends.get(shot["id"]))
	await _clear()

	# The player behind the wall: no shot at the wall — it goes round until it sees them.
	_home_player(Vector3(SCREEN_X, 0.1, 0))
	var hp: float = _player.health_component.current_health
	ranged = await _spawn(RANGED_SCENE, Vector3(SCREEN_X, 0.1, -9.5))
	var first_shot: int = _shots.size()
	ranged.set_combat_enabled(true)
	var blind_telegraph: Array[bool] = [false]
	await _until(func() -> bool:
		if ranged.get_attack_phase() == EnemyAttack.Phase.TELEGRAPH and not _clear_line(ranged):
			blind_telegraph[0] = true
		return _shots.size() > first_shot, 600)
	var fired: bool = _shots.size() > first_shot
	var moved: float = _flat(ranged.global_position - Vector3(SCREEN_X, 0.1, -9.5)).length()
	var landed: bool = false
	if fired:
		var id: int = _shots[first_shot]["id"]
		await _until(func() -> bool: return _ends.has(id), 120)
		landed = _ends.get(id) == Projectile.REASON_HIT
	_record(fired and not blind_telegraph[0] and moved > 2.0 and landed and _player.health_component.current_health < hp,
		"LS1) the player hidden behind a wall 9.5 m away: never a telegraph without a clear line; it walks %.1f m round the wall, then shoots — and hits" % moved)
	await _clear()

	# Hidden during the telegraph: the shot is withheld at the fire moment.
	_home_player(Vector3(SCREEN_X + 5.0, 0.1, -6))
	ranged = await _spawn(RANGED_SCENE, Vector3(SCREEN_X, 0.1, 2))
	first_shot = _shots.size()
	var ranged_attack: EnemyRangedAttack = ranged.attack as EnemyRangedAttack
	ranged.set_combat_enabled(true)
	var telegraphed: bool = await _until(func() -> bool: return ranged.get_attack_phase() == EnemyAttack.Phase.TELEGRAPH, 120)
	_player.global_position = Vector3(SCREEN_X, 0.1, -8)
	await _until(func() -> bool: return ranged.get_attack_phase() != EnemyAttack.Phase.TELEGRAPH, 60)
	_record(telegraphed and _shots.size() == first_shot and ranged_attack.get_withheld_count() == 1
			and ranged.get_attack_phase() == EnemyAttack.Phase.NONE and ranged_attack.get_cooldown_remaining() == 0.0
			and ranged.get_state() != BasicEnemy.State.ATTACK,
		"LS2) the player slips behind the wall mid-telegraph: at the fire moment the line is checked again — no projectile, the attack withheld with no cooldown, back to CHASE")
	await _clear()


# --- the projectile itself ---------------------------------------------------------------------------------------

func _projectile_tests() -> void:
	# Lifetime: in the open with nothing to hit, it is gone when its time is up.
	var short: AttackData = _bolt.duplicate() as AttackData
	short.projectile_lifetime = 0.5
	var loose: Projectile = PROJECTILE_SCENE.instantiate() as Projectile
	add_child(loose)
	loose.global_position = Vector3(0, 6, 30)
	var reason: Array[StringName] = [&""]
	loose.finished.connect(func(why: StringName) -> void: reason[0] = why)
	var began: float = _clock
	loose.launch(null, Vector3.RIGHT, short, 12.0)
	await _until(func() -> bool: return reason[0] != &"", 60)
	var lived: float = _clock - began
	await _frames(2)
	_record(reason[0] == Projectile.REASON_LIFETIME and absf(lived - 0.5) <= 2.0 * DT and not is_instance_valid(loose),
		"LT1) a shot that hits nothing lives its lifetime (%.2f s of 0.5) and frees itself" % lived)

	# Its own shooter, and a fellow enemy in the line, are never hit.
	_home_player()
	_player.hurtbox.set_invulnerable(true)
	var ranged: BasicEnemy = await _spawn(RANGED_SCENE, HOME + Vector3(0, 0, -7))
	var fellow: BasicEnemy = await _spawn(MELEE_SCENE, HOME + Vector3(0, 0, -3.5))
	var own_hp: float = ranged.health_component.current_health
	var fellow_hp: float = fellow.health_component.current_health
	ranged.set_combat_enabled(true)
	var shot: Dictionary = await _next_shot(ranged)
	await _until(func() -> bool: return _ends.has(shot["id"]), 150)
	var inside: Projectile = PROJECTILE_SCENE.instantiate() as Projectile
	add_child(inside)
	inside.global_position = ranged.hurtbox.get_center()
	inside.launch(ranged, Vector3.BACK, _bolt, 12.0)
	await _frames(8)
	var touched: bool = _hits.any(func(h: Dictionary) -> bool: return h["target"] == ranged or h["target"] == fellow)
	_record(not touched and ranged.health_component.current_health == own_hp and fellow.health_component.current_health == fellow_hp
			and (_hits_of(shot["id"]).size() == 1 and _hits_of(shot["id"])[0]["target"] == _player),
		"SC1) a shot leaving its shooter never hits it — not even launched from inside its body — and passes a fellow enemy in the line to reach the player: no friendly fire")
	if is_instance_valid(inside):
		inside.queue_free()
	await _clear()


# --- interruptions -----------------------------------------------------------------------------------------------

func _interrupt_tests() -> void:
	# Staggered in the telegraph: no shot.
	_home_player()
	var ranged: BasicEnemy = await _spawn(RANGED_SCENE, HOME + Vector3(0, 0, -7))
	var first_shot: int = _shots.size()
	ranged.set_combat_enabled(true)
	await _until(func() -> bool: return ranged.get_attack_phase() == EnemyAttack.Phase.TELEGRAPH, 90)
	ranged.hurtbox.receive_hit(_crafted_hit(1.0, 60.0, 0.0))
	var cut: bool = ranged.is_staggered() and ranged.get_attack_phase() == EnemyAttack.Phase.NONE
	await _wait(0.8)
	_record(cut and _shots.size() == first_shot and _alive_projectiles() == 0,
		"ST1) staggered in the telegraph: the attack is cancelled — STAGGERED, and no projectile, ever")
	await _clear()

	# Staggered on the very tick the telegraph would end: the stagger is first.
	_home_player()
	ranged = await _spawn(RANGED_SCENE, HOME + Vector3(0, 0, -7))
	first_shot = _shots.size()
	ranged.set_combat_enabled(true)
	var due: bool = await _until(func() -> bool:
		return (ranged.get_attack_phase() == EnemyAttack.Phase.TELEGRAPH
			and ranged.attack.get_phase_remaining() <= DT * 1.01), 120)
	ranged.hurtbox.receive_hit(_crafted_hit(1.0, 60.0, 0.0))
	await _frames(10)
	_record(due and ranged.is_staggered() and _shots.size() == first_shot,
		"ST2) staggered on the tick the telegraph runs out: the stagger lands before the enemy runs that tick — STAGGERED, and nothing is fired")
	await _clear()

	# Staggered after the fire: the projectile is already its own.
	_home_player()
	var hp: float = _player.health_component.current_health
	ranged = await _spawn(RANGED_SCENE, HOME + Vector3(0, 0, -7))
	ranged.set_combat_enabled(true)
	var shot: Dictionary = await _next_shot(ranged)
	ranged.hurtbox.receive_hit(_crafted_hit(1.0, 60.0, 0.0))
	var staggered: bool = ranged.is_staggered()
	await _until(func() -> bool: return _ends.has(shot["id"]), 90)
	_record(staggered and _ends.get(shot["id"]) == Projectile.REASON_HIT and hp - _player.health_component.current_health == 12.0,
		"ST3) staggered just after it fired: STAGGERED — and the shot flies on regardless and lands its 12")
	await _clear()


func _death_tests() -> void:
	# Killed in the telegraph: nothing is fired.
	_home_player()
	var ranged: BasicEnemy = await _spawn(RANGED_SCENE, HOME + Vector3(0, 0, -7))
	var first_shot: int = _shots.size()
	ranged.set_combat_enabled(true)
	await _until(func() -> bool: return ranged.get_attack_phase() == EnemyAttack.Phase.TELEGRAPH, 90)
	ranged.hurtbox.receive_hit(_crafted_hit(1000.0, 0.0, 0.0))
	await _wait(0.8)
	_record(ranged.get_state() == BasicEnemy.State.DEAD and _shots.size() == first_shot and ranged.get_target() == null,
		"DE1) killed in the telegraph: DEAD, no target, and no projectile")
	await _clear()

	# Killed by the player's own strike just after it fired: the shot still lands,
	# and the kill is paid once. Cornered, so it shoots from within reach.
	_home_player()
	var hp: float = _player.health_component.current_health
	ranged = await _spawn(RANGED_SCENE, HOME + Vector3(0, 0, -1.4))
	ranged._reposition_block_timer = 30.0
	var deaths: Array[int] = [0]
	ranged.enemy_died.connect(func(_dead: RoomCombatant) -> void: deaths[0] += 1)
	var xp: int = _player.progression.get_total_xp()
	ranged.set_combat_enabled(true)
	var shot: Dictionary = await _next_shot(ranged)
	ranged.health_component.current_health = 1.0
	_player.combat.reset()
	_player.combat._start_attack(_player.combat.data.light_combo, 0)
	await _until(func() -> bool: return ranged.get_state() == BasicEnemy.State.DEAD, 60)
	await _until(func() -> bool: return _ends.has(shot["id"]), 90)
	var landed: Array[Dictionary] = _hits_of(shot["id"])
	await _frames(5)
	_record(ranged.get_state() == BasicEnemy.State.DEAD and _ends.get(shot["id"]) == Projectile.REASON_HIT
			and hp - _player.health_component.current_health == 12.0 and landed[0]["source"] == ranged
			and deaths[0] == 1 and _player.progression.get_total_xp() - xp == ranged.get_xp_reward(),
		"DE2) killed by the player's strike just after it fired: the shot still lands its 12, still its; the kill pays %d XP, once" % ranged.get_xp_reward())
	await _clear()

	# Gone from the scene altogether while its shot flies: the shot lands, with no source.
	_home_player()
	hp = _player.health_component.current_health
	ranged = await _spawn(RANGED_SCENE, HOME + Vector3(0, 0, -7))
	ranged.set_combat_enabled(true)
	shot = await _next_shot(ranged)
	ranged.queue_free()
	await _until(func() -> bool: return _ends.has(shot["id"]), 90)
	landed = _hits_of(shot["id"])
	_record(_ends.get(shot["id"]) == Projectile.REASON_HIT and hp - _player.health_component.current_health == 12.0
			and landed.size() == 1 and landed[0]["source"] == null,
		"DE3) its shooter freed while it flies: the shot keeps no hold on it — it lands its 12 with no source, and nothing breaks")
	await _clear()


# --- several, and a melee beside them --------------------------------------------------------------------------------

func _multiple_tests() -> void:
	_home_player()
	_player.hurtbox.set_invulnerable(true)
	var group: Array[BasicEnemy] = []
	var delays: Array[float] = [0.0, 0.5, 1.0]
	for i in 3:
		var angle: float = deg_to_rad(-40.0 + 40.0 * i)
		var enemy: BasicEnemy = await _spawn(RANGED_SCENE, HOME + Vector3(sin(angle), 0, -cos(angle)) * 7.0)
		enemy.initial_attack_delay = delays[i]
		group.append(enemy)
	var first_shot: int = _shots.size()
	for enemy in group:
		enemy.set_combat_enabled(true)
	await _until(func() -> bool:
		return group.all(func(e: BasicEnemy) -> bool: return (e.attack as EnemyRangedAttack).get_shot_count() >= 1), 300)
	var cooling: Array[Array] = [[]]
	await _until(func() -> bool:
		cooling[0] = group.map(func(e: BasicEnemy) -> float: return e.attack.get_cooldown_remaining())
		return cooling[0].all(func(left: float) -> bool: return left > 0.0), 120)
	var c: Array = cooling[0]
	var cooldowns_differ: Array[bool] = [c.size() == 3 and c[0] < c[1] and c[1] < c[2]]
	var theirs: Array[Dictionary] = _shots.slice(first_shot)
	var first_of: Array[float] = []
	for enemy in group:
		var own: Array[Dictionary] = theirs.filter(func(s: Dictionary) -> bool: return s["enemy"] == enemy)
		first_of.append(own[0]["clock"] if not own.is_empty() else -1.0)
	var distinct: bool = first_of[0] >= 0.0 and first_of[0] < first_of[1] and first_of[1] < first_of[2]
	var own_targets: bool = group.all(func(e: BasicEnemy) -> bool: return e.get_target() == _player)
	_record(distinct and cooldowns_differ[0] and own_targets
			and theirs.all(func(s: Dictionary) -> bool: return group.has(s["enemy"])),
		"MU1) three ranged on the player: each fires its own projectile on its own clock (first shots at %.2f / %.2f / %.2f s), their cooldowns apart, each on its own target" % [
			first_of[0] - first_of[0], first_of[1] - first_of[0], first_of[2] - first_of[0]])
	await _clear()


func _mixed_tests() -> void:
	# A melee and a ranged together: one closes in, the other keeps its distance,
	# while the player fights them with everything M11 gave it.
	_home_player()
	_player.hurtbox.set_invulnerable(true)
	var melee: BasicEnemy = await _spawn(MELEE_SCENE, HOME + Vector3(-1.5, 0, -5))
	var ranged: BasicEnemy = await _spawn(RANGED_SCENE, HOME + Vector3(3, 0, -8))
	var first_shot: int = _shots.size()
	melee.set_combat_enabled(true)
	ranged.set_combat_enabled(true)
	var closest_ranged: Array[float] = [100.0]
	var melee_closed: bool = await _until(func() -> bool:
		if ranged.get_target() != null:
			closest_ranged[0] = minf(closest_ranged[0], ranged.targeting.get_distance())
		return melee.get_target() != null and melee.targeting.get_distance() <= melee.attack_range, 180)
	_record(melee_closed and closest_ranged[0] >= ranged.minimum_combat_distance and melee.get_target() == _player
			and ranged.get_target() == _player,
		"MX1) a melee and a ranged on the player: the melee closes to its reach while the ranged keeps its distance (never nearer than %.2f m) — the same target foundation, each its own state" % closest_ranged[0])
	# The player's whole kit against them.
	_press(&"target_lock")
	var first_lock: RoomCombatant = _player.targeting.get_target()
	_press(&"target_switch_right")
	var switched: RoomCombatant = _player.targeting.get_target()
	if switched == first_lock:
		_press(&"target_switch_left")
		switched = _player.targeting.get_target()
	var stamina_start: float = _player.combat.get_stamina()
	_player.combat.reset()
	_player.camera_rig.attack_light_pressed.emit()
	await _until(func() -> bool: return not _player.combat.is_attacking(), 90)
	_no_crits.critical_chance = 1.0
	_player.camera_rig.attack_heavy_pressed.emit()
	await _until(func() -> bool: return not _player.combat.is_attacking(), 120)
	_no_crits.critical_chance = 0.0
	_press(&"dodge")
	var after_dodge: float = _player.combat.get_stamina()
	await _wait(2.5)
	var ranged_fired: bool = _shots.slice(first_shot).any(func(s: Dictionary) -> bool: return s["enemy"] == ranged)
	var sane: bool = [melee, ranged].all(func(e: BasicEnemy) -> bool:
		return e.get_state() == BasicEnemy.State.DEAD or e.get_target() == _player)
	_record(first_lock != null and switched != null and switched != first_lock and after_dodge < stamina_start
			and _player.combat.get_stamina() > after_dodge and ranged_fired and melee.attack.get_swing_count() >= 1 and sane
			and _violations.is_empty(),
		"MX2) locked, switched, a light, a critical heavy and a dodge against the pair: the lock moves between them, stamina spent and back, the melee swinging and the ranged firing throughout — nothing corrupted")
	_player.targeting.unlock()
	await _clear()


# --- shadows -------------------------------------------------------------------------------------------------------------

func _shadow_tests() -> void:
	var shadow: BasicMeleeShadow = await _summon(HOME + Vector3(0, 0, -2))
	shadow.set_physics_process(false)

	# In the line of a shot at the player, the shadow takes it.
	_home_player()
	shadow.global_position = HOME + Vector3(0, 0, -3.5)
	var ranged: BasicEnemy = await _spawn(RANGED_SCENE, HOME + Vector3(0, 0, -7))
	var hp: float = _player.health_component.current_health
	var shadow_hp: float = shadow.health_component.current_health
	ranged.set_combat_enabled(true)
	var shot: Dictionary = await _next_shot(ranged)
	await _until(func() -> bool: return _ends.has(shot["id"]), 90)
	var landed: Array[Dictionary] = _hits_of(shot["id"])
	_record(ranged.get_target() == _player and _ends.get(shot["id"]) == Projectile.REASON_HIT and landed.size() == 1
			and landed[0]["target"] == shadow and shadow_hp - shadow.health_component.current_health == 12.0
			and _player.health_component.current_health == hp,
		"SH1) aimed at the player, with the shadow in the way: the shadow takes the shot — 12 — and it stops there; the player behind is untouched")
	await _clear()

	# An archetype whose groups include the shadow's hunts it, and hits it.
	var hunter_data: EnemyData = RANGED_DATA.duplicate() as EnemyData
	hunter_data.target_groups = [Player.GROUP, BasicMeleeShadow.GROUP]
	_home_player(Vector3(-30, 0.1, 30))
	shadow.global_position = HOME + Vector3(0, 0, -1)
	shadow_hp = shadow.health_component.current_health
	var hunter: BasicEnemy = await _spawn(RANGED_SCENE, HOME + Vector3(0, 0, -8), hunter_data)
	hunter.set_combat_enabled(true)
	shot = await _next_shot(hunter)
	await _until(func() -> bool: return _ends.has(shot["id"]), 90)
	landed = _hits_of(shot["id"])
	_record(hunter.get_target() == shadow and landed.size() == 1 and landed[0]["target"] == shadow
			and shadow_hp - shadow.health_component.current_health == 12.0,
		"SH2) a ranged whose data lists the shadow's group targets the shadow, as M12.1's policy says, and its shot hits it for 12")
	await _clear()
	shadow.set_physics_process(true)
	_player.shadow_summoner.recall()
	await _frames(3)


# --- the player's lock ---------------------------------------------------------------------------------------------------

func _lock_tests() -> void:
	var indicator: TargetLockIndicator = INDICATOR_SCENE.instantiate() as TargetLockIndicator
	add_child(indicator)
	await _frames(3)
	_home_player()
	_player.hurtbox.set_invulnerable(true)
	var ranged: BasicEnemy = await _spawn(RANGED_SCENE, HOME + Vector3(0, 0, -6))
	ranged.set_combat_enabled(true)
	await _frames(2)
	_press(&"target_lock")
	var locked: bool = _player.targeting.get_target() == ranged
	var states: Dictionary = {}
	var followed: Array[bool] = [true]
	var watch: Callable = func() -> void:
		states[BasicEnemy.State.keys()[ranged.get_state()]] = true
		followed[0] = followed[0] and indicator.is_showing() \
			and indicator.global_position.distance_to(ranged.get_target_point()) < 0.1
	await _until(func() -> bool:
		watch.call()
		return ranged.get_attack_phase() == EnemyAttack.Phase.TELEGRAPH, 120)
	# Pressed: it backs away, the lock and its ring with it.
	_player.global_position = ranged.global_position + Vector3(0, 0, 2.5)
	var start: Vector3 = ranged.global_position
	await _until(func() -> bool:
		watch.call()
		return ranged.get_state() == BasicEnemy.State.REPOSITION and _flat(ranged.global_position - start).length() > 1.0, 180)
	ranged.hurtbox.receive_hit(_crafted_hit(1.0, 60.0, 0.0))
	watch.call()
	var still_locked: bool = _player.targeting.get_target() == ranged
	await _frames(3)
	ranged.hurtbox.receive_hit(DamageInfo.new(1000.0, _player, &"test"))
	await _frames(3)
	_record(locked and still_locked and followed[0] and states.has("ATTACK") and states.has("REPOSITION")
			and states.has("STAGGERED") and not _player.targeting.is_locked() and not indicator.is_showing(),
		"LK1) locked on the ranged through %s: the lock held and the indicator stayed on it as it backed away; killed, the lock let go and the ring went" % [
			states.keys()])
	indicator.queue_free()
	await _clear()


# --- reactions: knockback, critical, hit stop ---------------------------------------------------------------------------------

func _reaction_tests() -> void:
	# Pushed back: after the stagger it takes up the fight from where it landed.
	_home_player()
	_player.hurtbox.set_invulnerable(true)
	var ranged: BasicEnemy = await _spawn(RANGED_SCENE, HOME + Vector3(0, 0, -4.6))
	ranged.set_combat_enabled(true)
	await _until(func() -> bool: return ranged.get_state() == BasicEnemy.State.CHASE, 60)
	ranged.hurtbox.receive_hit(_crafted_hit(1.0, 60.0, 6.0))
	await _until(func() -> bool: return not ranged.is_knocked_back(), 60)
	var landed: Vector3 = ranged.global_position
	var pushed: float = ranged.targeting.get_distance()
	await _until(func() -> bool: return not ranged.is_staggered(), 90)
	var resumed: bool = await _until(func() -> bool: return ranged.get_attack_phase() == EnemyAttack.Phase.TELEGRAPH, 180)
	var from: float = _flat(ranged.global_position - landed).length()
	_record(pushed > 5.0 and resumed and from < 0.3,
		"KB1) a heavy pushes it from 4.6 to %.2f m: after the stagger it takes the fight up from there — its next telegraph %.2f m from where it landed, no walking back to the old spot" % [
			pushed, from])
	await _clear()

	# A critical light hit, and the hit stop it brings, in the middle of a telegraph.
	_home_player()
	_player.hurtbox.set_invulnerable(true)
	ranged = await _spawn(RANGED_SCENE, HOME + Vector3(0, 0, -1.4))
	ranged.health_component.set_max_health(1000.0)
	ranged.health_component.current_health = 1000.0
	ranged.set_combat_enabled(true)
	ranged._reposition_block_timer = 30.0
	await _until(func() -> bool: return ranged.get_attack_phase() == EnemyAttack.Phase.TELEGRAPH, 90)
	var began: float = _clock
	var tick: int = Engine.get_physics_frames()
	var taken: Array[DamageInfo] = []
	ranged.health_component.damaged.connect(func(hit: DamageInfo) -> void: taken.append(hit))
	var marks: int = _player.combat_feedback.get_critical_mark_count()
	var stops: int = _player.combat_feedback.get_hit_stop_count()
	_no_crits.critical_chance = 1.0
	_player.combat.reset()
	_player.combat._start_attack(_player.combat.data.light_combo, 0)
	await _until(func() -> bool: return ranged.get_attack_phase() != EnemyAttack.Phase.TELEGRAPH, 90)
	_no_crits.critical_chance = 0.0
	var game: float = _clock - began
	var wall: float = (Engine.get_physics_frames() - tick) * DT
	var light: AttackData = _player.combat.data.light_combo[0]
	var expected: float = DamageModel.final_damage(_player.combat.calculate_damage(light), true,
		_player.combat.data.critical_damage_multiplier)
	_record(taken.size() == 1 and taken[0].is_critical and is_equal_approx(taken[0].amount, expected)
			and _player.combat_feedback.get_critical_mark_count() > marks and not ranged.is_staggered()
			and ranged.get_state() == BasicEnemy.State.ATTACK,
		"CR1) a critical light hit on the ranged mid-telegraph: %.0f damage, critical, its mark shown; no stagger, and its state untouched" % expected)
	_record(_player.combat_feedback.get_hit_stop_count() > stops and absf(game - _bolt.windup) <= 2.0 * DT
			and wall > game + DT and ranged.get_attack_phase() == EnemyAttack.Phase.ACTIVE,
		"HS1) through the hit stop it brought, the telegraph still lasts %.2f s of game time (%.2f s on the wall) and goes on to fire" % [
			game, wall])
	await _clear()


# --- many at once --------------------------------------------------------------------------------------------------------------

func _performance_tests() -> void:
	_home_player()
	_player.hurtbox.set_invulnerable(true)
	var crowd: Array[BasicEnemy] = []
	for i in CROWD:
		var angle: float = TAU * float(i) / CROWD
		crowd.append(await _spawn(RANGED_SCENE, HOME + Vector3(cos(angle), 0, sin(angle)) * 7.0))
	for enemy in crowd:
		enemy.set_combat_enabled(true)
	await _frames(120)
	var objects: float = Performance.get_monitor(Performance.OBJECT_COUNT)
	var reads: int = 0
	for enemy in crowd:
		reads -= enemy.targeting.get_refresh_count()
	var first_shot: int = _shots.size()
	var physics: float = 0.0
	var worst: float = 0.0
	var most: int = 0
	for tick in 240:
		await get_tree().physics_frame
		var t: float = Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)
		physics += t
		worst = maxf(worst, t)
		most = maxi(most, _alive_projectiles())
	for enemy in crowd:
		reads += enemy.targeting.get_refresh_count()
	var fired: int = _shots.size() - first_shot
	var grown: float = Performance.get_monitor(Performance.OBJECT_COUNT) - objects
	var average: float = physics / 240.0
	await _clear()
	await _wait(_bolt.projectile_lifetime + 0.2)
	_record(fired >= CROWD and average < PHYSICS_BUDGET and most <= CROWD and reads == 0 and grown <= CROWD * 2
			and _alive_projectiles() == 0,
		"PF1) %d ranged firing at the player for 4 s: %d shots, at most %d in flight, %.2f ms of physics a tick (%.2f at worst), no group read with targets held, %+d objects; freed, no shot outlives its lifetime" % [
			CROWD, fired, most, average * 1000.0, worst * 1000.0, int(grown)])


# --- helpers ------------------------------------------------------------------------------------------------------------------

func _spawn(scene: PackedScene, at: Vector3, data: EnemyData = null) -> BasicEnemy:
	var enemy: BasicEnemy = scene.instantiate() as BasicEnemy
	_count += 1
	enemy.name = "%s%d" % ["Ranged" if scene == RANGED_SCENE else "Melee", _count]
	enemy.combat_enabled = false
	if data != null:
		enemy.stats = data
	# Placed before it enters the tree: added first, it would stand at the origin
	# for a physics step and shove whatever is there.
	enemy.position = at
	add_child(enemy)
	_face(enemy, _player.global_position)
	_watch(enemy)
	_spawned.append(enemy)
	await _frames(3)
	return enemy


func _watch(enemy: BasicEnemy) -> void:
	_watched.append(enemy)
	_transitions[enemy] = []
	_transition_times[enemy] = []
	enemy.state_changed.connect(func(from: BasicEnemy.State, to: BasicEnemy.State) -> void:
		(_transitions[enemy] as Array).append("%s>%s" % [BasicEnemy.State.keys()[from], BasicEnemy.State.keys()[to]])
		(_transition_times[enemy] as Array).append(_clock))
	var ranged: EnemyRangedAttack = enemy.attack as EnemyRangedAttack
	if ranged != null:
		ranged.fired.connect(_on_fired.bind(enemy))


func _on_fired(projectile: Projectile, enemy: BasicEnemy) -> void:
	var ranged: EnemyRangedAttack = enemy.attack as EnemyRangedAttack
	var id: int = projectile.get_instance_id()
	_shots.append({"enemy": enemy, "projectile": projectile, "id": id, "clock": _clock, "state": enemy.get_state(),
		"origin": projectile.global_position, "from_spawn": projectile.global_position.distance_to(ranged.projectile_spawn.global_position),
		"direction": projectile.get_direction(), "speed": projectile.get_speed()})
	# Captures the id alone: the shooter may be freed while the shot flies.
	projectile.hitbox.hit_landed.connect(func(target: Node, hit: DamageInfo) -> void:
		_hits.append({"id": id, "target": target, "amount": hit.amount, "attack_id": hit.attack_id,
			"source": hit.source, "critical": hit.is_critical, "accepted": false}))
	projectile.hitbox.hit_accepted.connect(func(_target: Node, _hit: DamageInfo) -> void:
		_hits[-1]["accepted"] = true)
	projectile.finished.connect(func(reason: StringName) -> void: _ends[id] = reason)


## The next shot `enemy` fires, once it is out of the muzzle.
func _next_shot(enemy: BasicEnemy) -> Dictionary:
	var before: int = _shots.size()
	await _until(func() -> bool:
		return _shots.slice(before).any(func(s: Dictionary) -> bool: return s["enemy"] == enemy), 400)
	for shot in _shots.slice(before):
		if shot["enemy"] == enemy:
			return shot
	return {"id": -1, "projectile": null, "direction": Vector3.FORWARD, "origin": Vector3.ZERO}


func _hits_of(id: int) -> Array[Dictionary]:
	return _hits.filter(func(h: Dictionary) -> bool: return h["id"] == id)


func _time_of(enemy: BasicEnemy, transition: String) -> float:
	var at: int = (_transitions[enemy] as Array).find(transition)
	return (_transition_times[enemy] as Array)[at] if at >= 0 else -1.0


func _alive_projectiles() -> int:
	var n: int = 0
	for child in get_children():
		if child is Projectile and not (child as Projectile).is_queued_for_deletion():
			n += 1
	return n


func _end_counts() -> Dictionary:
	var counts: Dictionary = {}
	for reason in _ends.values():
		counts[reason] = counts.get(reason, 0) + 1
	return counts


## Whether the enemy's eye sees the player's: what a telegraph needs.
func _clear_line(enemy: BasicEnemy) -> bool:
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		enemy.global_position + Vector3.UP * enemy.eye_height, _player.global_position + Vector3.UP * enemy.eye_height, 1)
	query.exclude = [enemy.get_rid(), _player.get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func _body_color(enemy: BasicEnemy) -> Color:
	var mat: StandardMaterial3D = enemy.mesh_instance.get_surface_override_material(0) as StandardMaterial3D
	return mat.albedo_color if mat != null else Color.BLACK


## Frees every enemy spawned and every projectile still flying.
func _clear() -> void:
	for enemy in _spawned:
		if is_instance_valid(enemy):
			(enemy as Node).queue_free()
	_spawned.clear()
	for child in get_children():
		if child is Projectile:
			_ends[child.get_instance_id()] = &"cleared"
			child.queue_free()
	_player.targeting.unlock()
	await _frames(3)


func _summon(at: Vector3) -> BasicMeleeShadow:
	var shadow: ShadowInstance = _player.shadows.add_shadow(SHADOW_DATA)
	var node: BasicMeleeShadow = _player.shadow_summoner.summon(shadow.instance_id)
	await _frames(2)
	node.global_position = at
	node.hurtbox.set_invulnerable(false)
	await _frames(2)
	return node


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


func _crafted_hit(amount: float, stagger_power: float, knockback: float) -> DamageInfo:
	var hit: DamageInfo = DamageInfo.new(amount, _player, &"test")
	hit.stagger_power = stagger_power
	hit.knockback_force = knockback
	hit.direction = Vector3.FORWARD
	return hit


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
