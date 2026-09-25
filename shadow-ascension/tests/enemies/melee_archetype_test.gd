extends Node3D

## M12.2 — the melee archetype: its attack as data, the swing's lifecycle
## (telegraph -> active -> recovery -> cooldown), the facing commitment, the
## hits, the interruptions, the targets, several at once, and a variant built
## from data alone.
##
##   godot --headless --path . res://tests/enemies/melee_archetype_test.tscn
##
## The player is vulnerable unless a test says otherwise: a swing that lands is
## health lost, so "no damage" means exactly that. Enemies that die are spawned
## for it and freed. An every-tick watcher checks the attack's one source of
## truth: the hitbox open exactly in ACTIVE, a phase exactly in ATTACK, none in
## STAGGERED or DEAD.

const ENEMY_SCENE: PackedScene = preload("res://scenes/enemies/basic_melee_enemy.tscn")
const BASIC_ATTACK_PATH: String = "res://resources/enemies/attacks/melee_basic_attack.tres"
const SHADOW_DATA: ShadowData = preload("res://resources/shadows/basic_melee_shadow.tres")
const PARKED: Array[Vector3] = [Vector3(-20, 0.1, 20), Vector3(-16, 0.1, 20), Vector3(-12, 0.1, 20)]
const HOME: Vector3 = Vector3(0, 0.1, 0)
const IN_FRONT: Vector3 = Vector3(0, 0.1, -1.5)
const DT: float = 1.0 / 60.0
const CROWD: int = 8
## A physics tick must fit in one 60 Hz tick, or the game falls behind.
const PHYSICS_BUDGET: float = 1.0 / 60.0

@onready var _player: Player = $Player
@onready var _a: BasicEnemy = $EnemyA
@onready var _b: BasicEnemy = $EnemyB
@onready var _c: BasicEnemy = $EnemyC
@onready var _nav_region: NavigationRegion3D = $NavigationRegion3D

var _data: EnemyData = null
var _basic: AttackData = null
var _watched: Array = []
var _violations: Array[String] = []
## Every hit an enemy's swing landed and the target took: what, on whom, and
## the attack phase it was in.
var _hits: Array[Dictionary] = []
## Game time: every physics tick's delta, summed (a hit stop holds it still).
var _clock: float = 0.0
var _spawned: int = 0
var _pass: int = 0
var _fail: int = 0

var _no_crits: PlayerCombatData = preload("res://resources/characters/player_combat.tres")


func _ready() -> void:
	_no_crits.critical_chance = 0.0
	_nav_region.bake_navigation_mesh(false)
	_reset_session()
	_data = _a.stats
	_basic = _data.attacks[0]
	for enemy in [_a, _b, _c]:
		_watch(enemy)
	_run()


func _physics_process(delta: float) -> void:
	_clock += delta
	for candidate in _watched:
		if not is_instance_valid(candidate) or not (candidate as Node).is_inside_tree():
			continue
		var e: BasicEnemy = candidate
		var phase: EnemyAttack.Phase = e.get_attack_phase()
		var label: String = "%s %s/%s" % [e.name, BasicEnemy.State.keys()[e.get_state()],
			EnemyAttack.Phase.keys()[phase]]
		if e.attack.hitbox.is_active() != (phase == EnemyAttack.Phase.ACTIVE):
			_violations.append("%s, hitbox %s" % [label, e.attack.hitbox.is_active()])
		if (e.get_state() == BasicEnemy.State.ATTACK) != (phase != EnemyAttack.Phase.NONE):
			_violations.append(label)


func _run() -> void:
	await _wait(0.4)
	_config_tests()
	await _approach_tests()
	await _lifecycle_tests()
	await _cooldown_tests()
	await _dodge_tests()
	await _commitment_tests()
	await _interrupt_tests()
	await _knockback_tests()
	await _range_and_target_tests()
	await _shadow_tests()
	await _multi_melee_tests()
	await _death_tests()
	await _player_regression_tests()
	await _variant_tests()
	await _performance_tests()
	await _wait(0.3)
	_record(_violations.is_empty(),
		"IV1) every tick, on every melee: the hitbox open exactly in ACTIVE, an attack phase exactly in ATTACK %s" % [
			_violations.slice(0, 4)])
	_record(_hits.all(func(h: Dictionary) -> bool: return h["phase"] == EnemyAttack.Phase.ACTIVE),
		"IV2) every one of the %d hits a melee landed landed in ACTIVE — never in the telegraph or the recovery" % _hits.size())
	_record(_basic.windup == 0.35 and _basic.active == 0.15 and _basic.recovery == 0.65
			and _basic.damage_multiplier == 1.0 and _data.attack_damage == 15.0 and _data.attack_cooldown == 0.4,
		"IV3) the shared EnemyData and AttackData were never written")
	print("[SUMMARY] passed=%d failed=%d" % [_pass, _fail])
	get_tree().quit()


# --- configuration ----------------------------------------------------------------------------------

func _config_tests() -> void:
	_record(_basic.resource_path == BASIC_ATTACK_PATH and _basic is AttackData and _basic.id == &"melee_basic_attack"
			and _basic.windup == 0.35 and _basic.active == 0.15 and _basic.recovery == 0.65
			and _basic.damage_multiplier == 1.0 and _basic.stagger_power == 0.0 and _basic.knockback_force == 0.0
			and _data.attacks.size() == 1,
		"CF1) the basic melee's one attack is an AttackData — the player's resource — `melee_basic_attack`: telegraph 0.35 s, active 0.15 s, recovery 0.65 s, x1.0, no stagger or push")
	_record(_data.attack_damage == 15.0 and _data.attack_cooldown == 0.4 and _data.attack_range == 1.8
			and _data.preferred_combat_distance == 1.6 and _data.minimum_combat_distance == 1.15
			and _data.max_attack_facing_angle == 25.0 and _data.telegraph_turn_fraction == 0.3
			and _data.telegraph_facing_lock == 0.1,
		"CF2) EnemyData: base damage 15, cooldown 0.4 s, attack range 1.8 m, preferred 1.6 m, minimum 1.15 m, facing cone 25 deg, telegraph turn 30%, facing locked for the last 0.1 s — M11's numbers")
	var own: bool = not is_same(_a.attack, _b.attack) and _a.attack.select_attack() == _basic \
		and not is_same(_a.attack.attacks, _data.attacks) and _a.attack.hitbox.damage == 15.0
	_record(own, "CF3) each enemy has its own MeleeAttack, a copy of the list — the AttackData itself shared, read-only — and select_attack() is the basic attack")


# --- approach -------------------------------------------------------------------------------------------

func _approach_tests() -> void:
	await _fresh(_a, HOME + Vector3(0, 0, -6))
	_a.set_combat_enabled(true)
	await _until(func() -> bool: return _a.get_target() != null, 10)
	var no_swing: bool = true
	var frames: int = 0
	while _a.targeting.get_distance() > _a.attack_range + 0.05 and frames < 180:
		await get_tree().physics_frame
		frames += 1
		no_swing = no_swing and _a.get_attack_phase() == EnemyAttack.Phase.NONE
	# Let it settle on the ring; it must stop there rather than push into the player.
	await _until(func() -> bool: return _a.get_state() == BasicEnemy.State.ATTACK, 60)
	var at_swing: float = _a.targeting.get_distance()
	_record(no_swing and frames < 180 and at_swing >= _a.minimum_combat_distance and at_swing <= _a.attack_range,
		"AP1) out of range it closes in — no swing on the way — and swings from %.2f m, inside the band %.2f–%.2f m" % [
			at_swing, _a.minimum_combat_distance, _a.attack_range])
	# Between swings it finishes closing to its preferred distance, and holds
	# there: no creeping into the player, no jitter. (The next swing held off a
	# second, to watch it stand.)
	_player.hurtbox.set_invulnerable(true)
	await _until(func() -> bool: return _a.get_state() == BasicEnemy.State.CHASE, 90)
	_a.attack.hold_off(1.0)
	var settled: bool = await _until(func() -> bool:
		return _a.targeting.get_distance() <= _a.preferred_combat_distance + 0.02 and _flat(_a.velocity).length() < 0.05, 40)
	var ring: Vector3 = _a.global_position
	var still: bool = true
	var sampled: int = 0
	while _a.get_state() == BasicEnemy.State.CHASE and sampled < 20:
		await get_tree().physics_frame
		sampled += 1
		still = still and _flat(_a.global_position - ring).length() < 0.02
	var held_at: float = _a.targeting.get_distance()
	_record(settled and still and sampled == 20 and absf(held_at - _a.preferred_combat_distance) < 0.05
			and _flat(_player.global_position - HOME).length() < 0.01,
		"AP2) between swings it closes the rest of the way to its preferred distance and holds there (%.2f m): no creeping into the player, no jitter, the player not pushed" % held_at)
	_player.hurtbox.set_invulnerable(false)


# --- telegraph -> active -> recovery ----------------------------------------------------------------------

func _lifecycle_tests() -> void:
	await _fresh(_a, IN_FRONT)
	var hp: float = _player.health_component.current_health
	var first: int = _hits.size()
	_a.set_combat_enabled(true)
	await _until(func() -> bool: return _a.get_state() == BasicEnemy.State.ATTACK, 30)
	var telegraph_start: float = _clock
	var shut: bool = _a.get_attack_phase() == EnemyAttack.Phase.TELEGRAPH and not _a.attack.hitbox.is_active()
	var no_damage_early: bool = true
	var reared: bool = false
	while _a.get_attack_phase() == EnemyAttack.Phase.TELEGRAPH:
		no_damage_early = no_damage_early and _player.health_component.current_health == hp and not _a.attack.hitbox.is_active()
		reared = reared or (_a.visual_root.scale.y > 1.05 and _body_color(_a).g > 0.3)
		await get_tree().physics_frame
	var telegraph_time: float = _clock - telegraph_start
	_record(shut and no_damage_early and reared and absf(telegraph_time - _basic.windup) <= 2.0 * DT,
		"LC1) in range: CHASE -> ATTACK in TELEGRAPH for %.2f s — the hitbox shut, the player standing in reach untouched; it rears up and turns yellow" % telegraph_time)
	# ACTIVE: one hit, 15, with the attack's name on it.
	var active_start: float = _clock
	while _a.get_attack_phase() == EnemyAttack.Phase.ACTIVE:
		await get_tree().physics_frame
	var active_time: float = _clock - active_start
	var mine: Array[Dictionary] = _hits.slice(first)
	var hit: Dictionary = mine[0] if not mine.is_empty() else {}
	_record(mine.size() == 1 and hp - _player.health_component.current_health == 15.0
			and hit.get("target") == _player and hit.get("attack_id") == &"melee_basic_attack"
			and hit.get("source") == _a and not hit.get("critical", true) and absf(active_time - _basic.active) <= 2.0 * DT,
		"LC2) ACTIVE for %.2f s: one hit, 15 damage, from the enemy, named melee_basic_attack, never critical — however many ticks the player stood in it" % active_time)
	# RECOVERY: shut, committed, and nothing more lands.
	var recovery_start: float = _clock
	var quiet: bool = true
	while _a.get_attack_phase() == EnemyAttack.Phase.RECOVERY:
		quiet = quiet and not _a.attack.hitbox.is_active() and _a.get_state() == BasicEnemy.State.ATTACK
		await get_tree().physics_frame
	var recovery_time: float = _clock - recovery_start
	_record(quiet and _hits.size() == first + 1 and absf(recovery_time - _basic.recovery) <= 2.0 * DT
			and _a.get_state() == BasicEnemy.State.CHASE,
		"LC3) RECOVERY for %.2f s: the hitbox shut, still committed, no second hit; then back to CHASE" % recovery_time)


func _cooldown_tests() -> void:
	# Straight on from the swing above: the player still in reach.
	var ended: float = _clock
	await _until(func() -> bool: return _a.get_attack_phase() == EnemyAttack.Phase.TELEGRAPH, 90)
	var gap: float = _clock - ended
	_record(absf(gap - _data.attack_cooldown) <= 3.0 * DT,
		"CD1) the player still in reach: the next telegraph waits out the %.1f s cooldown (%.2f s)" % [_data.attack_cooldown, gap])
	# Five seconds of standing in reach: never swing on swing.
	_player.hurtbox.set_invulnerable(true)
	var swings: int = _a.attack.get_swing_count()
	await _wait(5.0)
	var in_five: int = _a.attack.get_swing_count() - swings
	var cycle: float = _basic.windup + _basic.active + _basic.recovery + _data.attack_cooldown
	_record(in_five <= ceili(5.0 / cycle) and in_five >= floori(5.0 / cycle),
		"CD2) no spam: %d swings in 5 s, one every %.2f s at most (telegraph + active + recovery + cooldown)" % [in_five, cycle])
	_player.hurtbox.set_invulnerable(false)


# --- the player's answers: the dodge, and stepping aside ----------------------------------------------------

func _dodge_tests() -> void:
	await _fresh(_a, IN_FRONT)
	_player.combat.restore_stamina(_player.combat.get_max_stamina())
	var hp: float = _player.health_component.current_health
	_a.set_combat_enabled(true)
	await _until(func() -> bool:
		return _a.get_attack_phase() == EnemyAttack.Phase.TELEGRAPH and _a.attack.get_phase_remaining() <= 0.12, 60)
	var speed: float = _player.effective_dodge_speed
	_player.effective_dodge_speed = 0.0
	var stamina: float = _player.combat.get_stamina()
	_press(&"dodge")
	var paid: float = stamina - _player.combat.get_stamina()
	var landed: int = _hits.size()
	await _until(func() -> bool: return _a.get_state() == BasicEnemy.State.CHASE, 90)
	_player.effective_dodge_speed = speed
	_record(_player.health_component.current_health == hp and paid == _player.combat.data.dodge_stamina_cost
			and _hits.size() == landed,
		"DG1) the telegraph read, a dodge into ACTIVE: its i-frames take the hit — no damage — and it cost its %.0f stamina" % paid)


func _commitment_tests() -> void:
	# The player steps well aside once the facing has locked: the swing goes on
	# where it was aimed and hits nothing.
	await _fresh(_a, IN_FRONT)
	var hp: float = _player.health_component.current_health
	_a.set_combat_enabled(true)
	await _until(func() -> bool:
		return (_a.get_attack_phase() == EnemyAttack.Phase.TELEGRAPH
			and _a.attack.get_phase_remaining() < _data.telegraph_facing_lock), 60)
	var locked_yaw: float = _a.visual_root.rotation.y
	var locked_factor: float = _a.attack.get_turn_factor()
	_player.global_position = HOME + Vector3(2.6, 0, 0)
	var steady: bool = true
	while _a.get_state() == BasicEnemy.State.ATTACK:
		steady = steady and is_equal_approx(_a.visual_root.rotation.y, locked_yaw)
		await get_tree().physics_frame
	_record(locked_factor == 0.0 and steady and _player.health_component.current_health == hp,
		"FC1) the player steps 2.6 m aside in the last 0.1 s of the telegraph: the facing is locked, ACTIVE and RECOVERY never turn — no homing — and the swing misses")

	# Early in the telegraph it may still track, but only slowly.
	await _fresh(_a, IN_FRONT)
	_a.set_combat_enabled(true)
	await _until(func() -> bool: return _a.get_attack_phase() == EnemyAttack.Phase.TELEGRAPH, 30)
	var early_factor: float = _a.attack.get_turn_factor()
	var yaw: float = _a.visual_root.rotation.y
	_player.global_position = IN_FRONT + Vector3(1.5, 0, 0)
	await _until(func() -> bool: return _a.get_attack_phase() != EnemyAttack.Phase.TELEGRAPH, 30)
	var turned: float = rad_to_deg(absf(wrapf(_a.visual_root.rotation.y - yaw, -PI, PI)))
	_record(early_factor == _data.telegraph_turn_fraction and turned > 1.0 and turned < 45.0,
		"FC2) the player circles 90 deg at the start of the telegraph: it follows at %.0f%% of its turn speed until the lock — %.0f deg, never the full 90" % [
			early_factor * 100.0, turned])
	await _until(func() -> bool: return _a.get_state() == BasicEnemy.State.CHASE, 90)


# --- interruptions --------------------------------------------------------------------------------------

func _interrupt_tests() -> void:
	# Staggered in the telegraph: the hitbox never opens.
	await _fresh(_a, IN_FRONT)
	var hp: float = _player.health_component.current_health
	_a.set_combat_enabled(true)
	await _until(func() -> bool: return _a.get_attack_phase() == EnemyAttack.Phase.TELEGRAPH, 30)
	_a.hurtbox.receive_hit(_crafted_hit(1.0, 60.0, 0.0))
	var cut: bool = _a.is_staggered() and _a.get_attack_phase() == EnemyAttack.Phase.NONE
	var never_opened: bool = true
	for i in 30:
		await get_tree().physics_frame
		never_opened = never_opened and not _a.attack.hitbox.is_active()
	_record(cut and never_opened and _player.health_component.current_health == hp,
		"ST1) staggered in the telegraph: the swing is cancelled there — the hitbox never opens, no damage — STAGGERED")
	await _until(func() -> bool: return not _a.is_staggered(), 60)

	# Staggered while the hitbox is open: shut at once, and nothing lands after.
	await _fresh(_a, IN_FRONT)
	_player.hurtbox.set_invulnerable(true)
	_a.set_combat_enabled(true)
	await _until(func() -> bool: return _a.get_attack_phase() == EnemyAttack.Phase.ACTIVE, 60)
	_player.hurtbox.set_invulnerable(false)
	hp = _player.health_component.current_health
	_a.hurtbox.receive_hit(_crafted_hit(1.0, 60.0, 0.0))
	var shut: bool = not _a.attack.hitbox.is_active() and _a.is_staggered() and _a.get_attack_phase() == EnemyAttack.Phase.NONE
	await _wait(0.4)
	_record(shut and _player.health_component.current_health == hp,
		"ST2) staggered in ACTIVE: the hitbox shut that moment — no ghost hit after — STAGGERED")
	await _until(func() -> bool: return not _a.is_staggered(), 60)

	# A hit too weak to stagger: it takes it, flinches, and swings on.
	await _fresh(_a, IN_FRONT)
	hp = _player.health_component.current_health
	_a.set_combat_enabled(true)
	await _until(func() -> bool: return _a.get_attack_phase() == EnemyAttack.Phase.TELEGRAPH, 30)
	var enemy_hp: float = _a.health_component.current_health
	_a.hurtbox.receive_hit(_crafted_hit(20.0, 10.0, 0.0))
	var flinched: bool = _a._flinch_tween != null and _a._flinch_tween.is_running()
	var carried_on: bool = await _until(func() -> bool: return _a.get_attack_phase() == EnemyAttack.Phase.ACTIVE, 30)
	await _until(func() -> bool: return _a.get_attack_phase() != EnemyAttack.Phase.ACTIVE, 30)
	_record(enemy_hp - _a.health_component.current_health == 20.0 and flinched and carried_on and not _a.is_staggered()
			and hp - _player.health_component.current_health == 15.0,
		"ST3) a hit below its resistance: 20 damage and a flinch, but the swing goes on — ACTIVE — and lands its 15")
	await _until(func() -> bool: return _a.get_state() == BasicEnemy.State.CHASE, 90)


func _knockback_tests() -> void:
	# A push with no stagger in the telegraph: it slides back, and the swing
	# goes on from where the push left it — the AI neither resists the push nor
	# walks back mid-swing; after it, it closes in again.
	await _fresh(_a, IN_FRONT)
	_player.hurtbox.set_invulnerable(true)
	_a.set_combat_enabled(true)
	await _until(func() -> bool: return _a.get_attack_phase() == EnemyAttack.Phase.TELEGRAPH, 30)
	var start: Vector3 = _a.global_position
	var swing: int = _a.attack.get_swing_count()
	_a.hurtbox.receive_hit(_crafted_hit(1.0, 0.0, 8.0))
	var pushed_while_swinging: bool = _a.is_knocked_back() and _a.get_attack_phase() == EnemyAttack.Phase.TELEGRAPH
	var carried_on: bool = await _until(func() -> bool: return _a.get_attack_phase() == EnemyAttack.Phase.ACTIVE, 30)
	await _until(func() -> bool: return not _a.is_knocked_back(), 60)
	var landed_at: Vector3 = _a.global_position
	var pushed: float = _flat(landed_at - start).length()
	var held: bool = true
	while _a.get_state() == BasicEnemy.State.ATTACK:
		held = held and _flat(_a.global_position - landed_at).length() < 0.01
		await get_tree().physics_frame
	var same_swing: bool = _a.attack.get_swing_count() == swing
	var resumed: bool = await _until(func() -> bool: return _a.attack.get_swing_count() > swing, 90)
	_record(pushed_while_swinging and carried_on and same_swing and pushed > 0.5 and held and resumed,
		"KB1) pushed in the telegraph, not staggered: the push carries it %.2f m — the AI does not fight it — the same swing goes on to ACTIVE from where it landed, standing there; then it closes back in and swings again" % pushed)

	# A heavy — stagger and push — in the telegraph: cancelled and thrown.
	await _fresh(_a, IN_FRONT)
	_a.set_combat_enabled(true)
	await _until(func() -> bool: return _a.get_attack_phase() == EnemyAttack.Phase.TELEGRAPH, 30)
	start = _a.global_position
	_a.hurtbox.receive_hit(_crafted_hit(1.0, 60.0, 8.0))
	var cancelled: bool = _a.is_staggered() and _a.get_attack_phase() == EnemyAttack.Phase.NONE
	await _until(func() -> bool: return not _a.is_knocked_back(), 60)
	var thrown: float = _flat(_a.global_position - start).length()
	var back: bool = await _until(func() -> bool: return _a.get_state() == BasicEnemy.State.CHASE, 60)
	_record(cancelled and thrown > 0.5 and back,
		"KB2) a heavy in the telegraph: the swing cancelled, the enemy thrown %.2f m through the physics, then CHASE again" % thrown)


# --- range and target -------------------------------------------------------------------------------------

func _range_and_target_tests() -> void:
	# The player walks off during the recovery: the swing ends, and it follows.
	await _fresh(_a, IN_FRONT)
	_player.hurtbox.set_invulnerable(true)
	_a.set_combat_enabled(true)
	await _until(func() -> bool: return _a.get_attack_phase() == EnemyAttack.Phase.RECOVERY, 90)
	_player.global_position = HOME + Vector3(0, 0, 5)
	var committed: bool = _a.get_state() == BasicEnemy.State.ATTACK
	await _until(func() -> bool: return _a.get_state() == BasicEnemy.State.CHASE, 90)
	var followed: bool = await _until(func() -> bool: return _a.velocity.z > 1.0, 60)
	_record(committed and followed,
		"RG1) the player leaves during the recovery: the recovery plays out, then CHASE — navigation resumes toward it")
	_player.global_position = HOME
	_player.hurtbox.set_invulnerable(false)

	# The target dies in the telegraph: the swing is cancelled, and nothing lands.
	await _fresh(_a, IN_FRONT)
	_a.set_combat_enabled(true)
	await _until(func() -> bool: return _a.get_attack_phase() == EnemyAttack.Phase.TELEGRAPH, 30)
	var landed: int = _hits.size()
	_player.health_component.take_damage(DamageInfo.new(100000.0, _b))
	var cancelled: bool = _a.get_attack_phase() == EnemyAttack.Phase.NONE and _a.get_state() == BasicEnemy.State.IDLE
	var never_opened: bool = true
	for i in 20:
		await get_tree().physics_frame
		never_opened = never_opened and not _a.attack.hitbox.is_active()
	_record(cancelled and never_opened and _hits.size() == landed and _a.get_target() == null,
		"TG1) the target dies in the telegraph: the swing is cancelled safely — no window opens, no reference kept — IDLE")
	_player.health_component.reset_to(_player.health_component.max_health)
	_player.combat.reset()


# --- shadows ---------------------------------------------------------------------------------------------------

func _shadow_tests() -> void:
	var shadow: BasicMeleeShadow = await _summon(HOME + Vector3(6, 0, 0))
	shadow.set_physics_process(false)

	# The player and a shadow side by side in one swing: each hit once.
	await _fresh(_a, IN_FRONT + Vector3(0.3, 0, 0))
	shadow.global_position = HOME + Vector3(0.7, 0, 0)
	await _frames(3)
	var player_hp: float = _player.health_component.current_health
	var shadow_hp: float = shadow.health_component.current_health
	var first: int = _hits.size()
	_a.set_combat_enabled(true)
	await _until(func() -> bool: return _a.get_attack_phase() == EnemyAttack.Phase.RECOVERY, 90)
	var swing_hits: Array[Dictionary] = _hits.slice(first)
	var on_player: int = swing_hits.filter(func(h: Dictionary) -> bool: return h["target"] == _player).size()
	var on_shadow: int = swing_hits.filter(func(h: Dictionary) -> bool: return h["target"] == shadow).size()
	_record(_a.get_target() == _player and on_player == 1 and on_shadow == 1
			and player_hp - _player.health_component.current_health == 15.0
			and shadow_hp - shadow.health_component.current_health == 15.0,
		"SH1) the player and a shadow both in the swing: its target is the player, but the hitbox decides — each hit once, 15 apiece")
	await _park_all()

	# An archetype whose groups include the shadow's: it goes for the shadow,
	# telegraphs at it, and hits it.
	var hunter_data: EnemyData = _data.duplicate() as EnemyData
	hunter_data.target_groups = [Player.GROUP, BasicMeleeShadow.GROUP]
	_player.global_position = HOME + Vector3(0, 0, 12)
	shadow.global_position = HOME + Vector3(-4, 0, -2)
	var hunter: BasicEnemy = await _spawn(HOME + Vector3(-4, 0, -7), hunter_data)
	shadow_hp = shadow.health_component.current_health
	first = _hits.size()
	var phases: Array[String] = []
	hunter.set_combat_enabled(true)
	var frames: int = 0
	while frames < 300 and _hits.size() == first:
		var phase: String = EnemyAttack.Phase.keys()[hunter.get_attack_phase()]
		if phases.is_empty() or phases[-1] != phase:
			phases.append(phase)
		await get_tree().physics_frame
		frames += 1
	var landed: Array[Dictionary] = _hits.slice(first)
	_record(hunter.get_target() == shadow and phases == ["NONE", "TELEGRAPH"] and not landed.is_empty()
			and landed[0]["phase"] == EnemyAttack.Phase.ACTIVE and landed.size() == 1 and landed[0]["target"] == shadow and shadow_hp - shadow.health_component.current_health == 15.0,
		"SH2) a melee whose data lists the shadow's group: it chases the shadow, telegraphs at it and hits it for 15 — the same swing as at the player")
	hunter.queue_free()
	shadow.set_physics_process(true)
	_player.shadow_summoner.recall()
	_player.global_position = HOME
	await _frames(3)


# --- several at once -------------------------------------------------------------------------------------------

func _multi_melee_tests() -> void:
	_player.hurtbox.set_invulnerable(true)
	await _fresh(_a, HOME + Vector3(0, 0, -1.5))
	await _fresh(_b, HOME + Vector3(1.3, 0, 0.75), false, true)
	await _fresh(_c, HOME + Vector3(-1.3, 0, 0.75), false, true)
	_a.initial_attack_delay = 0.0
	_b.initial_attack_delay = 0.3
	_c.initial_attack_delay = 0.6
	var opened: Array[int] = [-1, -1, -1]
	var enemies: Array[BasicEnemy] = [_a, _b, _c]
	for enemy in enemies:
		enemy.set_combat_enabled(true)
	for tick in 150:
		await get_tree().physics_frame
		for i in enemies.size():
			if opened[i] < 0 and enemies[i].attack.hitbox.is_active():
				opened[i] = tick
	var apart: bool = opened.all(func(t: int) -> bool: return t >= 0) and opened[0] < opened[1] and opened[1] < opened[2]
	var own: bool = enemies.all(func(e: BasicEnemy) -> bool: return e.get_target() == _player and e.attack.get_swing_count() >= 1)
	for enemy in enemies:
		enemy.initial_attack_delay = 0.0
	_record(apart and own and _basic.windup == 0.35,
		"ME1) three melee on the player, each on its own clock: their hit windows open at ticks %s — their own telegraphs, cooldowns and targets, nothing of it in the shared data" % [opened])
	await _park_all()
	_player.hurtbox.set_invulnerable(false)


# --- death -----------------------------------------------------------------------------------------------------

func _death_tests() -> void:
	# In the telegraph: no ACTIVE ever follows.
	var one: BasicEnemy = await _spawn(IN_FRONT)
	_face(one, _player.global_position)
	var hp: float = _player.health_component.current_health
	one.set_combat_enabled(true)
	await _until(func() -> bool: return one.get_attack_phase() == EnemyAttack.Phase.TELEGRAPH, 30)
	one.hurtbox.receive_hit(_crafted_hit(1000.0, 0.0, 0.0))
	var dead: bool = one.get_state() == BasicEnemy.State.DEAD and one.get_attack_phase() == EnemyAttack.Phase.NONE
	var never_opened: bool = true
	for i in 40:
		await get_tree().physics_frame
		never_opened = never_opened and not one.attack.hitbox.is_active()
	_record(dead and never_opened and _player.health_component.current_health == hp,
		"DE1) killed in the telegraph: DEAD, the swing cancelled — no ACTIVE ever follows")
	one.queue_free()

	# In ACTIVE: the hitbox shut that moment.
	_player.hurtbox.set_invulnerable(true)
	var two: BasicEnemy = await _spawn(IN_FRONT)
	_face(two, _player.global_position)
	two.set_combat_enabled(true)
	await _until(func() -> bool: return two.get_attack_phase() == EnemyAttack.Phase.ACTIVE, 60)
	two.hurtbox.receive_hit(_crafted_hit(1000.0, 0.0, 0.0))
	var shut: bool = not two.attack.hitbox.is_active() and two.get_state() == BasicEnemy.State.DEAD
	await _wait(0.5)
	_record(shut and two.get_state() == BasicEnemy.State.DEAD and two.get_attack_phase() == EnemyAttack.Phase.NONE,
		"DE2) killed in ACTIVE: the hitbox shut that moment, DEAD, nothing resumes")
	two.queue_free()

	# A critical killing blow from the player, locked on: paid once, the lock let go.
	var three: BasicEnemy = await _spawn(IN_FRONT)
	_face(three, _player.global_position)
	three.health_component.current_health = 60.0
	three.set_combat_enabled(true)
	await _frames(2)
	_press(&"target_lock")
	var locked: bool = _player.targeting.get_target() == three
	var xp: int = _player.progression.get_total_xp()
	var deaths: Array[int] = [0]
	three.enemy_died.connect(func(_dead: RoomCombatant) -> void: deaths[0] += 1)
	_no_crits.critical_chance = 1.0
	_player.combat.reset()
	_player.combat._start_attack(_player.combat.data.heavy_combo, 0)
	await _until(func() -> bool: return three.get_state() == BasicEnemy.State.DEAD, 90)
	_no_crits.critical_chance = 0.0
	await _frames(30)
	_record(locked and three.get_state() == BasicEnemy.State.DEAD and deaths[0] == 1
			and _player.progression.get_total_xp() - xp == three.get_xp_reward() and not _player.targeting.is_locked()
			and three.claim_xp() == 0,
		"DE3) a critical heavy kills it, locked on: DEAD, one death, %d XP once, the lock let go" % three.get_xp_reward())
	three.queue_free()
	_player.hurtbox.set_invulnerable(false)
	await _frames(2)


# --- the player's combat against it ---------------------------------------------------------------------------------

func _player_regression_tests() -> void:
	# The light combo: 20 / 25 / 35, flinch, flinch, stagger — and the melee's
	# own swing, cut off by the third.
	await _fresh(_a, IN_FRONT)
	_a.health_component.set_max_health(1000.0)
	_a.health_component.current_health = 1000.0
	_player.hurtbox.set_invulnerable(true)
	var taken: Array[float] = []
	var staggered: Array[bool] = []
	var on_damaged: Callable = func(hit: DamageInfo) -> void:
		taken.append(hit.amount)
		staggered.append(_a.is_staggered())
	_a.health_component.damaged.connect(on_damaged)
	_a.set_combat_enabled(true)
	await _frames(2)
	_press(&"target_lock")
	_player.combat.reset()
	_player.camera_rig.attack_light_pressed.emit()
	var frames: int = 0
	while _player.combat.is_attacking() and frames < 300:
		await get_tree().physics_frame
		frames += 1
		if _player.combat.get_state() == PlayerCombat.State.RECOVERY and _player.combat.get_queued_attack() == null \
				and _player.combat.get_combo_index() < 2:
			_player.camera_rig.attack_light_pressed.emit()
	_a.health_component.damaged.disconnect(on_damaged)
	_record(taken == [20.0, 25.0, 35.0] and staggered == [false, false, true] and _player.targeting.get_target() == _a,
		"PR1) against the melee: the light combo lands %s — flinch, flinch, stagger — and the lock holds throughout" % [taken])

	# Through a hit stop: the telegraph's clock stands still with the game.
	await _until(func() -> bool: return not _a.is_staggered(), 60)
	await _until(func() -> bool: return _a.get_attack_phase() == EnemyAttack.Phase.TELEGRAPH, 120)
	var started: float = _clock
	var tick: int = Engine.get_physics_frames()
	_player.combat.reset()
	_player.combat._start_attack(_player.combat.data.light_combo, 0)
	await _until(func() -> bool: return _a.get_attack_phase() != EnemyAttack.Phase.TELEGRAPH, 60)
	var game: float = _clock - started
	var wall: float = (Engine.get_physics_frames() - tick) * DT
	_record(absf(game - _basic.windup) <= 2.0 * DT and wall > game + DT and _player.combat_feedback.get_hit_stop_count() > 0,
		"PR2) struck in its telegraph (a hit stop): the telegraph still lasts %.2f s of game time (%.2f s on the wall) and goes on to ACTIVE" % [
			game, wall])
	_player.targeting.unlock()
	await _until(func() -> bool: return _a.get_state() == BasicEnemy.State.CHASE, 90)
	_a.health_component.set_max_health(100.0)
	_player.hurtbox.set_invulnerable(false)
	await _park_all()


# --- a variant, from data alone -------------------------------------------------------------------------------------

func _variant_tests() -> void:
	# A heavier melee: a slower, harder swing from further out, and a longer
	# pause after it. Only data changes; no script is touched.
	var slam: AttackData = _basic.duplicate() as AttackData
	slam.id = &"melee_brute_slam"
	slam.windup = 0.6
	slam.active = 0.2
	slam.recovery = 0.8
	slam.damage_multiplier = 2.0
	var brute_data: EnemyData = _data.duplicate() as EnemyData
	brute_data.attacks = [slam]
	brute_data.attack_range = 2.2
	brute_data.preferred_combat_distance = 2.0
	brute_data.attack_cooldown = 1.0
	_home_player()
	var brute: BasicEnemy = await _spawn(HOME + Vector3(0, 0, -2.1), brute_data)
	_face(brute, _player.global_position)
	await _frames(2)
	var hp: float = _player.health_component.current_health
	var first: int = _hits.size()
	brute.set_combat_enabled(true)
	await _until(func() -> bool: return brute.get_attack_phase() == EnemyAttack.Phase.TELEGRAPH, 30)
	var from: float = brute.targeting.get_distance()
	var started: float = _clock
	await _until(func() -> bool: return brute.get_attack_phase() == EnemyAttack.Phase.ACTIVE, 60)
	var telegraph: float = _clock - started
	await _until(func() -> bool: return brute.get_state() == BasicEnemy.State.CHASE, 90)
	var ended: float = _clock
	await _until(func() -> bool: return brute.get_attack_phase() == EnemyAttack.Phase.TELEGRAPH, 120)
	var cooldown: float = _clock - ended
	var landed: Array[Dictionary] = _hits.slice(first)
	_record(from > _data.attack_range and absf(telegraph - 0.6) <= 2.0 * DT and absf(cooldown - 1.0) <= 3.0 * DT
			and landed.size() >= 1 and landed[0]["attack_id"] == &"melee_brute_slam"
			and hp - _player.health_component.current_health >= 30.0,
		"VR1) a variant from data alone — range 2.2 m, a 0.6 s telegraph, x2.0, a 1 s cooldown: it swings from %.2f m (past the basic's reach), telegraphs %.2f s, hits for 30 as melee_brute_slam, waits %.2f s" % [
			from, telegraph, cooldown])
	brute.queue_free()
	await _frames(2)


# --- many swinging at once ---------------------------------------------------------------------------------------

func _performance_tests() -> void:
	await _park_all()
	_home_player()
	_player.hurtbox.set_invulnerable(true)
	var crowd: Array[BasicEnemy] = []
	for i in CROWD:
		var angle: float = TAU * float(i) / CROWD
		crowd.append(await _spawn(HOME + Vector3(cos(angle), 0, sin(angle)) * 4.0))
	for enemy in crowd:
		_face(enemy, HOME)
		enemy.set_combat_enabled(true)
	await _frames(120)
	var objects: float = Performance.get_monitor(Performance.OBJECT_COUNT)
	var swings: int = 0
	for enemy in crowd:
		swings -= enemy.attack.get_swing_count()
	var physics: float = 0.0
	var worst: float = 0.0
	for tick in 240:
		await get_tree().physics_frame
		var t: float = Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)
		physics += t
		worst = maxf(worst, t)
	for enemy in crowd:
		swings += enemy.attack.get_swing_count()
	var grown: float = Performance.get_monitor(Performance.OBJECT_COUNT) - objects
	var average: float = physics / 240.0
	_record(swings >= CROWD and average < PHYSICS_BUDGET and grown <= CROWD,
		"PF1) %d melee swinging at the player for 4 s: %d swings, %.2f ms of physics a tick (%.2f at worst), %+d objects — nothing kept per swing" % [
			CROWD, swings, average * 1000.0, worst * 1000.0, int(grown)])
	for enemy in crowd:
		enemy.queue_free()
	_player.hurtbox.set_invulnerable(false)
	await _frames(3)


# --- helpers ---------------------------------------------------------------------------------------------------------

func _watch(enemy: BasicEnemy) -> void:
	_watched.append(enemy)
	enemy.attack.hitbox.hit_accepted.connect(_on_enemy_hit.bind(enemy))


func _on_enemy_hit(target: Node, info: DamageInfo, enemy: BasicEnemy) -> void:
	_hits.append({"target": target, "amount": info.amount, "attack_id": info.attack_id, "source": info.source,
		"critical": info.is_critical, "phase": enemy.get_attack_phase(), "enemy": enemy})


func _body_color(enemy: BasicEnemy) -> Color:
	var mat: StandardMaterial3D = enemy.mesh_instance.get_surface_override_material(0) as StandardMaterial3D
	return mat.albedo_color if mat != null else Color.BLACK


func _spawn(at: Vector3, data: EnemyData = null) -> BasicEnemy:
	var enemy: BasicEnemy = ENEMY_SCENE.instantiate() as BasicEnemy
	_spawned += 1
	enemy.name = "Melee%d" % _spawned
	enemy.combat_enabled = false
	if data != null:
		enemy.stats = data
	add_child(enemy)
	enemy.global_position = at
	_watch(enemy)
	await _frames(3)
	return enemy


func _summon(at: Vector3) -> BasicMeleeShadow:
	var shadow: ShadowInstance = _player.shadows.add_shadow(SHADOW_DATA)
	var node: BasicMeleeShadow = _player.shadow_summoner.summon(shadow.instance_id)
	await _frames(2)
	node.global_position = at
	node.hurtbox.set_invulnerable(false)
	await _frames(2)
	return node


## Parks `enemy` at `at` facing the player, whole — and, unless `keep_others`,
## the other two out of the way; the player home, whole, unless `reset_player`
## is false.
func _fresh(enemy: BasicEnemy, at: Vector3, reset_player: bool = true, keep_others: bool = false) -> void:
	if not keep_others:
		var enemies: Array[BasicEnemy] = [_a, _b, _c]
		for i in enemies.size():
			if enemies[i] != enemy:
				_park(enemies[i], PARKED[i])
	if reset_player:
		_home_player()
	_park(enemy, at)
	_face(enemy, _player.global_position)
	await _frames(3)


func _home_player() -> void:
	_player.combat.reset()
	_player.global_position = HOME
	_player.velocity = Vector3.ZERO
	_player.camera_rig.rotation.y = 0.0
	_player.health_component.current_health = _player.health_component.max_health
	_player.hurtbox.set_invulnerable(false)


func _park(enemy: BasicEnemy, at: Vector3) -> void:
	enemy.set_combat_enabled(false)
	enemy.global_position = at
	enemy.velocity = Vector3.ZERO
	enemy.health_component.current_health = enemy.health_component.max_health
	enemy._reposition_block_timer = 0.0


func _park_all() -> void:
	var enemies: Array[BasicEnemy] = [_a, _b, _c]
	for i in enemies.size():
		_park(enemies[i], PARKED[i])
	await _frames(3)


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
