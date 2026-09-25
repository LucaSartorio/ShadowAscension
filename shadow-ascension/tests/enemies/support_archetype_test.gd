extends Node3D

## M12.6 — the support archetype: on the M12.1 state machine, a ranged fallback
## (M12.3), and its own part, EnemySupport: it finds its allies, chooses the most
## hurt under a threshold, walks into reach and sight, casts a heal — or a damage
## buff when nobody needs healing — through the attack lifecycle, and fights when
## there is nothing to do for anyone. Against the player's whole M11 kit, beside
## the other four archetypes.
##
##   godot --headless --path . res://tests/enemies/support_archetype_test.tscn
##
## Every section spawns what it needs and frees it again. Allies that only need
## to be there — hurt, still — are "frozen": awake (in the fight) but not
## processing, so they stay where they are and keep the health they are given.
## Every tick a watcher checks each enemy's attack against its state; every
## health change is checked against its maximum and against death.

const SUPPORT_SCENE: PackedScene = preload("res://scenes/enemies/basic_support_enemy.tscn")
const MELEE_SCENE: PackedScene = preload("res://scenes/enemies/basic_melee_enemy.tscn")
const RANGED_SCENE: PackedScene = preload("res://scenes/enemies/basic_ranged_enemy.tscn")
const TANK_SCENE: PackedScene = preload("res://scenes/enemies/basic_tank_enemy.tscn")
const ASSASSIN_SCENE: PackedScene = preload("res://scenes/enemies/basic_assassin_enemy.tscn")
const INDICATOR_SCENE: PackedScene = preload("res://scenes/ui/target_lock_indicator.tscn")
const SUPPORT_DATA: EnemyData = preload("res://resources/enemies/basic_support_enemy.tres")
const MELEE_DATA: EnemyData = preload("res://resources/enemies/basic_melee_enemy.tres")
const RANGED_DATA: EnemyData = preload("res://resources/enemies/basic_ranged_enemy.tres")
const TANK_DATA: EnemyData = preload("res://resources/enemies/basic_tank_enemy.tres")
const ASSASSIN_DATA: EnemyData = preload("res://resources/enemies/basic_assassin_enemy.tres")
const HEAL: AttackData = preload("res://resources/enemies/attacks/support_heal.tres")
const BUFF: AttackData = preload("res://resources/enemies/attacks/support_buff.tres")
const BOLT: AttackData = preload("res://resources/enemies/attacks/support_bolt.tres")
const SHADOW_DATA: ShadowData = preload("res://resources/shadows/basic_melee_shadow.tres")
const HOME: Vector3 = Vector3(0, 0.1, 0)
const SUPPORT_SPOT: Vector3 = Vector3(0, 0.1, -7)
const IN_REACH: Vector3 = Vector3(0, 0.1, -2.1)
const PARK: Vector3 = Vector3(35, 0.1, 35)
## The back wall's face is at z -29.5; the screen wall spans x 17..23, z -5.3..-4.7.
const WALL_FACE_Z: float = -29.5
const DT: float = 1.0 / 60.0
## A physics tick must fit in one 60 Hz tick, or the game falls behind.
const PHYSICS_BUDGET: float = 1.0 / 60.0

@onready var _player: Player = $Player
@onready var _nav_region: NavigationRegion3D = $NavigationRegion3D

var _spawned: Array = []
var _watched: Array = []
var _violations: Array[String] = []
var _health_violations: Array[String] = []
## Every support action that landed: {support, ally, action, amount, time, state, attack, swing, dead}.
var _applied: Array[Dictionary] = []
## Every hit a melee's swing or a projectile landed: {target, amount, attack_id, source, accepted}.
var _hits: Array[Dictionary] = []
var _transitions: Dictionary = {}
var _clock: float = 0.0
var _count: int = 0
var _pass: int = 0
var _fail: int = 0

var _no_crits: PlayerCombatData = preload("res://resources/characters/player_combat.tres")


func _ready() -> void:
	_no_crits.critical_chance = 0.0
	_nav_region.bake_navigation_mesh(false)
	_reset_session()
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
		if e.support != null and is_same(e.support.get_support_target(), e):
			_violations.append("%s supports itself" % e.name)


func _run() -> void:
	await _wait(0.4)
	await _config_tests()
	await _selection_tests()
	await _threshold_tests()
	await _heal_tests()
	await _loop_tests()
	await _interrupt_tests()
	await _ally_gone_tests()
	await _support_death_tests()
	await _solo_tests()
	await _offense_tests()
	await _reposition_tests()
	await _sight_tests()
	await _buff_tests()
	await _multiple_tests()
	await _stagger_tests()
	await _critical_tests()
	await _lock_tests()
	await _shadow_tests()
	await _mixed_tests()
	await _stress_tests()
	await _wait(0.3)
	_record(_violations.is_empty(),
		"IV1) every tick, on every enemy: an attack phase exactly in ATTACK; no support ever its own support target %s" % [
			_violations.slice(0, 4)])
	var clean: bool = _applied.all(func(a: Dictionary) -> bool:
		return a["state"] == BasicEnemy.State.ATTACK and a["attack"] == a["action"] and not a["dead"])
	var casts: Dictionary = {}
	var once: bool = true
	for a in _applied:
		var key: String = "%s#%d" % [a["support"], a["swing"]]
		once = once and not casts.has(key)
		casts[key] = true
	_record(clean and once and _health_violations.is_empty(),
		"IV2) all %d support actions landed from an ATTACK running that very action, once a cast, on a living ally; no health ever above its maximum, none raised from the dead %s" % [
			_applied.size(), _health_violations.slice(0, 3)])
	_record(SUPPORT_DATA.max_health == 65.0 and SUPPORT_DATA.support.heal_threshold == 0.7
			and SUPPORT_DATA.support.buff_action == BUFF and HEAL.windup == 1.2 and MELEE_DATA.support == null
			and MELEE_DATA.attack_damage == 15.0,
		"IV3) the shared EnemyData, EnemySupportData and AttackData were never written")
	print("[SUMMARY] passed=%d failed=%d" % [_pass, _fail])
	get_tree().quit()


# --- configuration --------------------------------------------------------------------------------------

func _config_tests() -> void:
	var support: BasicEnemy = await _spawn(SUPPORT_SCENE, PARK)
	var melee: BasicEnemy = await _spawn(MELEE_SCENE, PARK + Vector3(4, 0, 0))
	var d: EnemyData = SUPPORT_DATA
	_record(d.max_health == 65.0 and TANK_DATA.max_health > MELEE_DATA.max_health and MELEE_DATA.max_health > d.max_health
			and d.max_health > ASSASSIN_DATA.max_health and d.max_health < RANGED_DATA.max_health + 1.0
			and d.movement_speed == 3.6 and d.movement_speed < ASSASSIN_DATA.movement_speed
			and d.preferred_combat_distance == 6.5 and d.minimum_combat_distance == 3.5 and d.attack_range == 9.0
			and d.stagger_resistance == 20.0 and d.stagger_resistance < MELEE_DATA.stagger_resistance
			and d.attack_damage == 8.0 and d.attack_damage < RANGED_DATA.attack_damage and d.attack_cooldown == 2.0
			and d.xp_reward == 30,
		"CF1) the support is data: 65 HP (tank 260 > melee 100 > support 65 ~ ranged 70 / assassin 60), 3.6 m/s, keeps 3.5 / 6.5 / 9 m, stagger resistance 20 (melee 25), an 8-damage bolt (ranged 12) every 2 s")
	var s: EnemySupportData = d.support
	_record(s.ally_detection_range == 14.0 and s.support_range == 9.0 and s.cast_break_margin == 3.0
			and s.ally_scan_interval == 0.5 and s.heal_threshold == 0.7 and s.heal_fraction == 0.25 and s.heal_cooldown == 6.0
			and HEAL.windup == 1.2 and HEAL.active == 0.1 and HEAL.recovery == 0.6
			and s.buff_damage_bonus == 0.2 and s.buff_duration == 6.0 and s.buff_cooldown == 10.0 and BUFF.windup == 0.9
			and BOLT.projectile_scene == RANGED_DATA.attacks[0].projectile_scene and BOLT.damage_multiplier == 1.0,
		"CF2) its support: allies noticed within 14 m, supported within 9 (dropped past 12); heal under 70% for 25% of the ally's maximum, a 1.2 s cast, 0.1 s, 0.6 s recovery, 6 s cooldown; buff +20% for 6 s, a 0.9 s cast, 10 s cooldown; its bolt the ranged's projectile")
	var others: bool = [MELEE_DATA, RANGED_DATA, TANK_DATA, ASSASSIN_DATA].all(func(o: EnemyData) -> bool: return o.support == null)
	_record(support.get_script() == melee.get_script() and support.attack is EnemySupportAttack
			and support.attack is EnemyRangedAttack and support.support != null and melee.support == null and others,
		"CF3) the same state machine as every enemy; its attack a ranged attack that also runs its casts; its support a part of its scene — none on the other four, whose data has none")
	_record(support.get_state() == BasicEnemy.State.IDLE and support.health_component.current_health == 65.0
			and support.support.get_support_target() == null and not support.support.has_plan()
			and support.support.get_current_action() == EnemySupport.Action.NONE and support.get_target() == null,
		"SP1) spawned: IDLE, 65 of 65 HP, no hostile target, no support target, no action")
	await _clear()


# --- whom it supports ---------------------------------------------------------------------------------------

func _selection_tests() -> void:
	_home_player()
	_player.hurtbox.set_invulnerable(true)
	var tank: BasicEnemy = await _ally(TANK_SCENE, HOME + Vector3(-3, 0, -3), 0.4)
	var melee: BasicEnemy = await _ally(MELEE_SCENE, HOME + Vector3(3, 0, -3), 0.6)
	var assassin: BasicEnemy = await _ally(ASSASSIN_SCENE, HOME + Vector3(0, 0, -3.5), 0.9)
	var parked: BasicEnemy = await _spawn(MELEE_SCENE, HOME + Vector3(5, 0, -8))
	parked.health_component.current_health = 10.0
	var dead: BasicEnemy = await _ally(MELEE_SCENE, HOME + Vector3(-5, 0, -8), 0.2)
	dead.hurtbox.receive_hit(DamageInfo.new(1000.0, _player, &"test"))
	var support: BasicEnemy = await _spawn(SUPPORT_SCENE, SUPPORT_SPOT, _data(false))
	support.set_combat_enabled(true)
	await _until(func() -> bool: return support.support.get_support_target() != null, 120)
	var allies: Array = support.support.get_allies()
	_record(allies.size() == 3 and allies.has(tank) and allies.has(melee) and allies.has(assassin)
			and not allies.has(parked) and not allies.has(dead) and not allies.has(support),
		"AL1) its allies found by one physics query on the enemy layer: the tank, the melee and the assassin — not itself, not a parked enemy, not a dead one, not the player")
	_record(support.support.get_support_target() == tank and support.support.get_planned_action() == HEAL,
		"PR1) tank 40%, melee 60%, assassin 90%: it chooses the tank — the lowest share of health, not the fewest points (the tank's 104 are more than the melee's 60)")
	# Stickiness: while it casts on the tank, the melee drops below it.
	var changes: Array[int] = [0]
	support.support.support_target_changed.connect(func(_chosen: RoomCombatant) -> void: changes[0] += 1)
	await _until(func() -> bool: return support.support.is_casting(), 120)
	melee.health_component.current_health = 20.0
	var held: bool = true
	while support.support.is_casting():
		held = held and support.support.get_support_target() == tank
		await get_tree().physics_frame
	var landed: Dictionary = (_applied[-1] as Dictionary) if not _applied.is_empty() else {}
	_record(held and changes[0] == 1 and not landed.is_empty() and landed["ally"] == tank,
		"SK1) the melee falls to 20% during the cast: the support target stays the tank until the heal has landed — no switch mid-cast")
	var scans: int = support.support.get_scan_count()
	var reads: int = support.targeting.get_refresh_count()
	await _wait(2.0)
	var looked: int = support.support.get_scan_count() - scans
	_record(looked >= 3 and looked <= 5 and support.targeting.get_refresh_count() == reads,
		"AL2) it looks around every 0.5 s, not every frame: %d looks in 2 s, and its hostile target, held, costs no search" % looked)
	await _clear()


func _threshold_tests() -> void:
	# Above the threshold, and exactly on it: not hurt enough to heal.
	_home_player()
	_player.hurtbox.set_invulnerable(true)
	var melee: BasicEnemy = await _ally(MELEE_SCENE, HOME + Vector3(-3, 0, -4), 0.75)
	var assassin: BasicEnemy = await _ally(ASSASSIN_SCENE, HOME + Vector3(3, 0, -4), 0.7)
	var support: BasicEnemy = await _spawn(SUPPORT_SCENE, SUPPORT_SPOT, _data(false))
	var first: int = _applied.size()
	support.set_combat_enabled(true)
	var chose: Array[bool] = [false]
	await _until(func() -> bool:
		chose[0] = chose[0] or support.support.has_plan()
		return false, 150)
	_record(not chose[0] and _applied.size() == first and melee.health_component.current_health == 75.0
			and assassin.health_component.current_health == 42.0 and support.attack.get_shot_count() >= 1,
		"TH1) a melee at 75% and an assassin at exactly 70% — the threshold: neither is healed, nobody is chosen, and it fires at the player instead")
	await _clear()

	# Everyone whole, and no buff to give: the offence alone.
	_home_player()
	_player.hurtbox.set_invulnerable(true)
	await _ally(MELEE_SCENE, HOME + Vector3(-3, 0, -4), 1.0)
	await _ally(TANK_SCENE, HOME + Vector3(3, 0, -4), 1.0)
	support = await _spawn(SUPPORT_SCENE, SUPPORT_SPOT, _data(false))
	first = _applied.size()
	support.set_combat_enabled(true)
	chose[0] = false
	await _until(func() -> bool:
		chose[0] = chose[0] or support.support.has_plan()
		return false, 150)
	_record(not chose[0] and _applied.size() == first and support.attack.get_shot_count() >= 1,
		"FH1) every ally at full health, and no buff in its data: no heal, no plan — it fights (%d bolts in 2.5 s)" % support.attack.get_shot_count())
	await _clear()


# --- the heal ------------------------------------------------------------------------------------------------

func _heal_tests() -> void:
	_home_player()
	_player.hurtbox.set_invulnerable(true)
	var tank: BasicEnemy = await _ally(TANK_SCENE, HOME + Vector3(-2, 0, -3.5), 0.4)
	var support: BasicEnemy = await _spawn(SUPPORT_SCENE, SUPPORT_SPOT, _data(false))
	var bar: EnemyHealthBar3D = tank.get_node("EnemyHealthBar3D") as EnemyHealthBar3D
	var marker: MeshInstance3D = support.support.cast_marker
	var first: int = _applied.size()
	support.set_combat_enabled(true)
	await _until(func() -> bool: return support.support.is_casting(), 120)
	var began: float = _clock
	var untouched: bool = true
	var green: bool = false
	var marked: bool = true
	while support.support.is_casting():
		untouched = untouched and tank.health_component.current_health == 104.0
		var c: Color = _body_color(support)
		green = green or (c.g > 0.8 and c.r < 0.5)
		marked = marked and marker.visible and _flat(marker.global_position - tank.global_position).length() < 0.05
		await get_tree().physics_frame
	var cast: float = _clock - began
	var turned: float = rad_to_deg(support._facing_error_to(tank))
	var landed: Array[Dictionary] = _applied.slice(first)
	_record(landed.size() == 1 and landed[0]["ally"] == tank and landed[0]["action"] == HEAL
			and landed[0]["amount"] == 65.0 and tank.health_component.current_health == 169.0
			and is_equal_approx(bar.get_ratio(), 169.0 / 260.0),
		"HL1) the heal: the tank 104 -> 169 of 260 — 25%% of its own maximum, 65 — once, through its HealthComponent; its health bar redrawn from the same signal (%.2f)" % bar.get_ratio())
	_record(untouched and absf(cast - HEAL.windup) <= 2.0 * DT and green and marked and turned < 15.0,
		"HL2) before it: a %.2f s cast — nothing healed yet, the body glowing green, a green ring under the tank, the support turned to it (%.0f deg off)" % [
			cast, turned])
	var active_began: float = _clock
	while support.get_attack_phase() == EnemyAttack.Phase.ACTIVE:
		await get_tree().physics_frame
	var active: float = _clock - active_began
	var recovery_began: float = _clock
	while support.get_attack_phase() == EnemyAttack.Phase.RECOVERY:
		await get_tree().physics_frame
	var recovery: float = _clock - recovery_began
	await _wait(0.4)
	_record(absf(active - HEAL.active) <= 2.0 * DT and absf(recovery - HEAL.recovery) <= 2.0 * DT and not marker.visible
			and support.support.get_heal_cooldown_remaining() > 4.5,
		"HL3) then %.2f s of effect and %.2f s of recovery — the lifecycle of any attack — the ring flared and gone, the heal on its 6 s cooldown" % [
			active, recovery])
	# Hurt again at once: no second heal before the cooldown is over, and the
	# offence fills the gap.
	tank.health_component.current_health = 104.0
	var landed_at: float = float(landed[0]["time"]) if not landed.is_empty() else _clock
	var shots: int = support.attack.get_shot_count()
	var again: bool = await _until(func() -> bool: return support.support.is_casting(), 60 * 8)
	var gap: float = _clock - landed_at
	# Ready again, a heal still waits for a bolt already under way and the attack
	# cooldown after it: an enemy does one thing at a time.
	var latest: float = 6.0 + SUPPORT_DATA.support.ally_scan_interval + BOLT.windup + BOLT.active + BOLT.recovery \
		+ SUPPORT_DATA.attack_cooldown + 3.0 * DT
	_record(again and gap >= 6.0 - DT and gap <= latest and support.attack.get_shot_count() > shots,
		"CD1) the tank hurt again at once: the next heal starts %.2f s after the last landed — never before its 6 s cooldown, at most a bolt's round later — and %d bolts at the player fill the gap" % [
			gap, support.attack.get_shot_count() - shots])
	# Mid-cast the tank is healed to 250 by something else: the committed heal
	# lands and clamps.
	tank.health_component.current_health = 250.0
	await _until(func() -> bool: return _applied.size() > first + 1, 120)
	var last: Dictionary = _applied[-1]
	_record(_applied.size() == first + 2 and last["amount"] == 10.0 and tank.health_component.current_health == 260.0,
		"CL1) mid-cast the tank is brought to 250 of 260: the heal, committed, still lands — and restores 10, not 65: never past the maximum")
	await _clear()


func _loop_tests() -> void:
	# A tank under constant fire: healed, but with windows between.
	_home_player()
	_player.hurtbox.set_invulnerable(true)
	var tank: BasicEnemy = await _ally(TANK_SCENE, HOME + Vector3(-2, 0, -3.5), 0.5)
	var support: BasicEnemy = await _spawn(SUPPORT_SCENE, SUPPORT_SPOT, _data(false))
	var first: int = _applied.size()
	var shots: int = support.attack.get_shot_count()
	support.set_combat_enabled(true)
	for i in 60 * 15:
		if i % 30 == 0 and tank.health_component.current_health > 60.0:
			tank.health_component.take_damage(DamageInfo.new(12.0, _player, &"test"))
		await get_tree().physics_frame
	var heals: Array[Dictionary] = _applied.slice(first)
	var gaps: Array[float] = []
	for i in range(1, heals.size()):
		gaps.append((heals[i]["time"] as float) - (heals[i - 1]["time"] as float))
	_record(heals.size() >= 2 and heals.size() <= 3 and gaps.all(func(g: float) -> bool: return g >= 6.0 - DT)
			and support.attack.get_shot_count() - shots >= 2,
		"LP1) a tank losing 12 HP every 0.5 s for 15 s: %d heals, %s s apart — never back to back — and %d bolts at the player between them" % [
			heals.size(), gaps.map(func(g: float) -> String: return "%.1f" % g), support.attack.get_shot_count() - shots])
	await _clear()


# --- interrupting it ------------------------------------------------------------------------------------------

func _interrupt_tests() -> void:
	# A heavy mid-cast: staggered, nothing healed, the heal spent.
	_home_player()
	_player.hurtbox.set_invulnerable(true)
	var tank: BasicEnemy = await _ally(TANK_SCENE, HOME + Vector3(-2, 0, -3.5), 0.4)
	var support: BasicEnemy = await _spawn(SUPPORT_SCENE, SUPPORT_SPOT, _data(false))
	support.health_component.set_max_health(1000.0)
	support.health_component.current_health = 1000.0
	var first: int = _applied.size()
	support.set_combat_enabled(true)
	await _until(func() -> bool: return support.support.is_casting(), 120)
	_strike(support, _player.combat.data.heavy_combo, 0)
	var staggered: bool = await _until(func() -> bool: return support.is_staggered(), 60)
	var reached_active: bool = false
	for i in 90:
		reached_active = reached_active or (support.get_attack_phase() == EnemyAttack.Phase.ACTIVE
			and support.attack.get_current_attack() == HEAL)
		await get_tree().physics_frame
	_record(staggered and not reached_active and _applied.size() == first and tank.health_component.current_health == 104.0
			and support.support.get_heal_cooldown_remaining() > 4.0 and not support.support.has_plan(),
		"IN1) a heavy (stagger 60) mid-cast: STAGGERED, the cast cut off — no heal, the tank still at 104 — and the heal spent: %.1f s of cooldown left" % [
			support.support.get_heal_cooldown_remaining()])
	await _clear()

	# A Light 1 (stagger 10) mid-cast, from 1.6 m: hurt, not interrupted.
	_home_player()
	_player.hurtbox.set_invulnerable(true)
	tank = await _ally(TANK_SCENE, HOME + Vector3(-2, 0, -3.5), 0.4)
	support = await _spawn(SUPPORT_SCENE, SUPPORT_SPOT, _data(false))
	first = _applied.size()
	support.set_combat_enabled(true)
	await _until(func() -> bool: return support.support.is_casting(), 120)
	var began: float = _clock
	var tick: int = Engine.get_physics_frames()
	var taken: Array[float] = []
	support.health_component.damaged.connect(func(hit: DamageInfo) -> void: taken.append(hit.amount))
	var stops: int = _player.combat_feedback.get_hit_stop_count()
	_strike(support, _player.combat.data.light_combo, 0)
	var casting: bool = true
	while support.support.is_casting():
		casting = casting and support.get_state() == BasicEnemy.State.ATTACK
		await get_tree().physics_frame
	var game: float = _clock - began
	var wall: float = (Engine.get_physics_frames() - tick) * DT
	var landed: bool = _applied.size() == first + 1 and tank.health_component.current_health == 169.0
	_record(taken == [20.0] and not support.is_staggered() and casting and landed,
		"IN2) a Light 1 (stagger 10, under its 20) mid-cast: 20 damage taken, a flinch, and the cast goes on — the heal lands")
	_record(casting and landed and taken.size() == 1,
		"RP3) the player 1.6 m from it — well inside its 3.5 m — during the cast: it does not break off; a cast, once begun, is committed")
	_record(_player.combat_feedback.get_hit_stop_count() > stops and absf(game - HEAL.windup) <= 2.0 * DT and wall > game + DT,
		"HS1) through the hit stop that Light brought, the cast ran on game time: its %.2f s took %.2f s on the wall" % [game, wall])
	await _clear()


# --- the ally going away mid-cast ---------------------------------------------------------------------------------

func _ally_gone_tests() -> void:
	# Its ally killed mid-cast: dropped, nothing healed, free to choose again.
	_home_player()
	_player.hurtbox.set_invulnerable(true)
	var tank: BasicEnemy = await _ally(TANK_SCENE, HOME + Vector3(-2, 0, -3.5), 0.3)
	var melee: BasicEnemy = await _ally(MELEE_SCENE, HOME + Vector3(2, 0, -3.5), 0.5)
	var support: BasicEnemy = await _spawn(SUPPORT_SCENE, SUPPORT_SPOT, _data(false))
	var first: int = _applied.size()
	support.set_combat_enabled(true)
	await _until(func() -> bool: return support.support.is_casting(), 120)
	var on_tank: bool = support.support.get_support_target() == tank
	var dropped: int = support.attack.get_dropped_count()
	tank.hurtbox.receive_hit(DamageInfo.new(5000.0, _player, &"test"))
	await _frames(1)
	var cut: bool = support.attack.get_dropped_count() == dropped + 1 and not support.support.is_casting() \
		and support.support.get_heal_cooldown_remaining() == 0.0
	var dropped_at: float = _clock
	var next: bool = await _until(func() -> bool:
		return support.support.is_casting() and support.support.get_support_target() == melee, 120)
	var after: float = _clock - dropped_at
	await _until(func() -> bool: return _applied.size() > first, 120)
	_record(on_tank and cut and next and _applied.size() == first + 1 and _applied[-1]["ally"] == melee
			and melee.health_component.current_health == 75.0 and tank.health_component.current_health == 0.0,
		"AD1) the tank killed mid-cast: the cast dropped that tick — nothing healed, the heal not spent — and %.2f s later it casts on the melee instead (50 -> 75)" % after)
	await _clear()

	# Its ally carried off mid-cast: a step out of reach is tolerated, far out is not.
	_home_player()
	_player.hurtbox.set_invulnerable(true)
	melee = await _ally(MELEE_SCENE, HOME + Vector3(2, 0, -3.5), 0.4)
	support = await _spawn(SUPPORT_SCENE, SUPPORT_SPOT, _data(false, func(d: EnemyData) -> void:
		d.support.heal_cooldown = 0.5))
	first = _applied.size()
	support.set_combat_enabled(true)
	await _until(func() -> bool: return support.support.is_casting(), 120)
	melee.global_position = support.global_position + Vector3(10.5, 0, 0)
	await _until(func() -> bool: return not support.support.is_casting(), 120)
	var tolerated: bool = _applied.size() == first + 1 and _applied[-1]["ally"] == melee
	await _until(func() -> bool: return support.support.is_casting(), 60 * 6)
	dropped = support.attack.get_dropped_count()
	var hp: float = melee.health_component.current_health
	melee.global_position = support.global_position + Vector3(0, 0, -13.0)
	await _frames(3)
	_record(tolerated and support.attack.get_dropped_count() == dropped + 1 and _applied.size() == first + 1
			and melee.health_component.current_health == hp,
		"OR1) its ally carried 10.5 m off mid-cast — past the 9 m reach, inside the 3 m margin: the heal still lands; carried 13 m off: the cast is dropped, nothing healed")
	await _clear()


# --- its own death ------------------------------------------------------------------------------------------------

func _support_death_tests() -> void:
	_home_player()
	_player.hurtbox.set_invulnerable(true)
	var tank: BasicEnemy = await _ally(TANK_SCENE, HOME + Vector3(-2, 0, -3.5), 0.4)
	var support: BasicEnemy = await _spawn(SUPPORT_SCENE, SUPPORT_SPOT, _data(false))
	var first: int = _applied.size()
	support.set_combat_enabled(true)
	await _until(func() -> bool: return support.support.is_casting(), 120)
	support.hurtbox.receive_hit(DamageInfo.new(1000.0, _player, &"test"))
	var dead: bool = support.get_state() == BasicEnemy.State.DEAD
	await _wait(2.0)
	_record(dead and _applied.size() == first and tank.health_component.current_health == 104.0
			and not support.support.cast_marker.visible and support.support.get_support_target() == null
			and support.get_target() == null and _projectiles().is_empty(),
		"SD1) killed mid-cast: DEAD at once — no heal later, the tank still at 104, the ring gone, no support target, no hostile target, nothing fired")
	await _clear()

	# Killed in its bolt's telegraph: nothing fired, ever.
	_home_player()
	_player.hurtbox.set_invulnerable(true)
	support = await _spawn(SUPPORT_SCENE, SUPPORT_SPOT)
	support.set_combat_enabled(true)
	await _until(func() -> bool:
		return support.get_attack_phase() == EnemyAttack.Phase.TELEGRAPH and support.attack.get_current_attack() == BOLT, 120)
	support.hurtbox.receive_hit(DamageInfo.new(1000.0, _player, &"test"))
	await _wait(1.0)
	_record(support.get_state() == BasicEnemy.State.DEAD and support.attack.get_shot_count() == 0 and _projectiles().is_empty(),
		"DE1) killed in its bolt's telegraph: no shot then or later")
	await _clear()

	# The player's kill: its XP, once; no XP for anything it healed.
	_home_player()
	_player.hurtbox.set_invulnerable(true)
	support = await _spawn(SUPPORT_SCENE, HOME + Vector3(0, 0, -1.6))
	support.health_component.set_max_health(1000.0)
	support.health_component.current_health = 1000.0
	var deaths: Array[int] = [0]
	support.enemy_died.connect(func(_dead: RoomCombatant) -> void: deaths[0] += 1)
	_player.combat.reset()
	_player.combat._start_attack(_player.combat.data.light_combo, 0)
	await _until(func() -> bool: return not _player.combat.is_attacking(), 60)
	var xp: int = _player.progression.get_total_xp()
	support.hurtbox.receive_hit(DamageInfo.new(5000.0, _player, &"test"))
	await _frames(5)
	_record(deaths[0] == 1 and _player.progression.get_total_xp() - xp == 30 and support.claim_xp() == 0,
		"DE2) the player's kill: 30 XP, once; healing earns nothing and changes no attribution")
	await _clear()


# --- alone, and the offence ---------------------------------------------------------------------------------------

func _solo_tests() -> void:
	_home_player()
	var support: BasicEnemy = await _spawn(SUPPORT_SCENE, SUPPORT_SPOT)
	var hp: float = _player.health_component.current_health
	var first: int = _hits.size()
	support.set_combat_enabled(true)
	await _until(func() -> bool: return support.get_attack_phase() == EnemyAttack.Phase.TELEGRAPH, 120)
	var began: float = _clock
	while support.get_attack_phase() == EnemyAttack.Phase.TELEGRAPH:
		await get_tree().physics_frame
	var telegraph: float = _clock - began
	var fired: bool = support.attack.get_shot_count() == 1
	while support.get_attack_phase() != EnemyAttack.Phase.NONE:
		await get_tree().physics_frame
	var recovered_at: float = _clock
	await _until(func() -> bool: return _hits.size() > first, 90)
	var landed: Array[Dictionary] = _hits.slice(first)
	await _until(func() -> bool: return support.get_attack_phase() == EnemyAttack.Phase.TELEGRAPH, 240)
	var cooldown: float = _clock - recovered_at
	_record(support.support.get_allies().is_empty() and not support.support.has_plan()
			and support.support.get_scan_count() >= 2,
		"SO1) alone: its looks find nobody — no allies, no plan, nothing to wait for — and it fights at once")
	_record(fired and absf(telegraph - BOLT.windup) <= 2.0 * DT and landed.size() == 1 and landed[0]["amount"] == 8.0
			and landed[0]["accepted"] and landed[0]["attack_id"] == &"support_bolt"
			and hp - _player.health_component.current_health == 8.0 and absf(cooldown - 2.0) <= 3.0 * DT,
		"OF1) its offence: a %.2f s telegraph, a bolt — the ranged's projectile — 8 damage (the ranged's 12), recovery, then %.2f s of cooldown" % [
			telegraph, cooldown])
	await _clear()

	# The last of its group: its ally dies, and it does not go on looking for it.
	_home_player()
	_player.hurtbox.set_invulnerable(true)
	var melee: BasicEnemy = await _ally(MELEE_SCENE, HOME + Vector3(2, 0, -3.5), 0.4)
	support = await _spawn(SUPPORT_SCENE, SUPPORT_SPOT, _data(false))
	support.set_combat_enabled(true)
	await _until(func() -> bool: return support.support.has_plan(), 120)
	melee.hurtbox.receive_hit(DamageInfo.new(5000.0, _player, &"test"))
	var died_at: float = _clock
	var shots: int = support.attack.get_shot_count()
	var fought: bool = await _until(func() -> bool: return support.attack.get_shot_count() > shots, 180)
	_record(fought and not support.support.has_plan() and support.support.get_allies().is_empty(),
		"SO2) the last one standing: its ally dies, the plan goes with it, and %.2f s later it is firing at the player — no search for someone who is not there" % [
			_clock - died_at])
	await _clear()


func _offense_tests() -> void:
	# Dodging into the bolt: the i-frames take it.
	_home_player()
	var support: BasicEnemy = await _spawn(SUPPORT_SCENE, SUPPORT_SPOT)
	var hp: float = _player.health_component.current_health
	var first: int = _hits.size()
	support.set_combat_enabled(true)
	var shot: Array = [null]
	(support.attack as EnemyRangedAttack).fired.connect(func(p: Projectile) -> void: shot[0] = p)
	await _until(func() -> bool: return shot[0] != null, 180)
	await _until(func() -> bool:
		return not is_instance_valid(shot[0]) \
			or (shot[0] as Projectile).global_position.distance_to(_player.hurtbox.get_center()) < 2.2, 90)
	var speed: float = _player.effective_dodge_speed
	_player.effective_dodge_speed = 0.0
	_press(&"dodge")
	await _until(func() -> bool: return not is_instance_valid(shot[0]), 120)
	_player.effective_dodge_speed = speed
	var reached: Array[Dictionary] = _hits.slice(first)
	_record(reached.size() == 1 and not reached[0]["accepted"] and _player.health_component.current_health == hp,
		"DG1) dodging into its bolt: it reaches the player inside the i-frames and is refused — no damage")
	await _clear()

	# Stepping aside once it is fired: it flies straight on, and misses.
	_home_player()
	support = await _spawn(SUPPORT_SCENE, SUPPORT_SPOT)
	hp = _player.health_component.current_health
	first = _hits.size()
	support.set_combat_enabled(true)
	shot[0] = null
	(support.attack as EnemyRangedAttack).fired.connect(func(p: Projectile) -> void: shot[0] = p)
	await _until(func() -> bool: return shot[0] != null, 180)
	_player.global_position = HOME + Vector3(3, 0, 0)
	await _until(func() -> bool: return not is_instance_valid(shot[0]), 240)
	_record(_hits.size() == first and _player.health_component.current_health == hp,
		"MV1) the player steps 3 m aside once it has fired: the bolt flies straight on — no homing — and misses")
	await _clear()


# --- keeping its distance -----------------------------------------------------------------------------------------

func _reposition_tests() -> void:
	_home_player()
	_player.hurtbox.set_invulnerable(true)
	var support: BasicEnemy = await _spawn(SUPPORT_SCENE, SUPPORT_SPOT)
	support.set_combat_enabled(true)
	await _until(func() -> bool: return support.get_state() == BasicEnemy.State.CHASE, 90)
	_player.global_position = support.global_position + Vector3(0, 0, 2.0)
	var farthest: Array[float] = [0.0]
	var faced: Array[bool] = [true]
	var entered: Array[bool] = [false]
	var repositioned: bool = await _until(func() -> bool:
		if support.get_state() == BasicEnemy.State.REPOSITION:
			entered[0] = true
			farthest[0] = maxf(farthest[0], support.targeting.get_distance())
			if support.targeting.get_distance() > 3.0:
				faced[0] = faced[0] and support._facing_error_to(_player) < deg_to_rad(35.0)
		return entered[0] and support.get_state() != BasicEnemy.State.REPOSITION, 240)
	var after: String = BasicEnemy.State.keys()[support.get_state()]
	_record(repositioned and faced[0] and farthest[0] >= SUPPORT_DATA.minimum_combat_distance - 0.1
			and (_transitions[support] as Array).has("CHASE>REPOSITION"),
		"RP1) the player 2 m from it: CHASE -> REPOSITION, backing out to %.1f m on the navigation, facing the player — the ranged's retreat — and out of its minimum it is free to act again (%s)" % [
			farthest[0], after])
	await _clear()

	# Its back to a wall: the retreat goes nowhere; cornered, it fires from there.
	_home_player(Vector3(0, 0.1, WALL_FACE_Z + 2.4))
	_player.hurtbox.set_invulnerable(true)
	support = await _spawn(SUPPORT_SCENE, Vector3(0, 0.1, WALL_FACE_Z + 0.6))
	support.set_combat_enabled(true)
	var closest_shot: Array[float] = [100.0]
	var deepest: Array[float] = [0.0]
	var shots: Array[int] = [0]
	(support.attack as EnemyRangedAttack).fired.connect(func(_p: Projectile) -> void:
		shots[0] += 1
		closest_shot[0] = minf(closest_shot[0], support.targeting.get_distance()))
	await _until(func() -> bool:
		deepest[0] = minf(deepest[0], support.global_position.z)
		return shots[0] >= 1, 360)
	_record(shots[0] >= 1 and closest_shot[0] < SUPPORT_DATA.minimum_combat_distance
			and (_transitions[support] as Array).has("CHASE>REPOSITION") and deepest[0] >= WALL_FACE_Z + 0.3,
		"RP2) its back to a wall, the player 1.8 m off: the retreat times out, and cornered it fires from %.1f m — never through the wall" % closest_shot[0])
	await _clear()


func _sight_tests() -> void:
	# A wall between it and its ally: it walks round, then heals.
	_home_player(Vector3(26.5, 0.1, -9))
	_player.hurtbox.set_invulnerable(true)
	var tank: BasicEnemy = await _ally(TANK_SCENE, Vector3(20, 0.1, -1.5), 0.4)
	var support: BasicEnemy = await _spawn(SUPPORT_SCENE, Vector3(20, 0.1, -8.5), _data(false))
	var first: int = _applied.size()
	support.set_combat_enabled(true)
	var widest: Array[float] = [0.0]
	var shot_meanwhile: Array[bool] = [false]
	var shots: int = support.attack.get_shot_count()
	var healed: bool = await _until(func() -> bool:
		widest[0] = maxf(widest[0], absf(support.global_position.x - 20.0))
		shot_meanwhile[0] = shot_meanwhile[0] or (support.attack.get_shot_count() > shots and _applied.size() == first)
		return _applied.size() > first, 60 * 8)
	_record(healed and _applied[-1]["ally"] == tank and widest[0] > 2.5 and not shot_meanwhile[0],
		"LS1) its ally 7 m off — in reach — but behind a wall: no heal through it; it walks round (%.1f m out to the side), sees it, heals — and fires nothing at the player on the way" % widest[0])
	await _clear()

	# Unreachable in time: it gives up on the ally, and fights.
	_home_player(Vector3(26.5, 0.1, -9))
	_player.hurtbox.set_invulnerable(true)
	tank = await _ally(TANK_SCENE, Vector3(20, 0.1, -1.5), 0.4)
	support = await _spawn(SUPPORT_SCENE, Vector3(20, 0.1, -8.5), _data(false, func(d: EnemyData) -> void:
		d.support.approach_timeout = 0.4))
	first = _applied.size()
	support.set_combat_enabled(true)
	var gave_up: bool = await _until(func() -> bool: return support.support.get_abandoned_count() == 1, 120)
	shots = support.attack.get_shot_count()
	var fought: bool = await _until(func() -> bool: return support.attack.get_shot_count() > shots, 240)
	_record(gave_up and fought and _applied.size() == first and support.support.get_heal_cooldown_remaining() > 0.0,
		"LS2) with 0.4 s to reach it: it gives up on the ally behind the wall — the heal waits out its cooldown — and fights meanwhile, never stuck")
	await _clear()


# --- the buff ---------------------------------------------------------------------------------------------------

func _buff_tests() -> void:
	_home_player()
	_player.hurtbox.set_invulnerable(true)
	var melee: BasicEnemy = await _spawn(MELEE_SCENE, IN_REACH)
	melee.set_combat_enabled(true)
	var first_hit: int = _hits.size()
	await _until(func() -> bool: return _swings_of(melee, first_hit).size() >= 1, 120)
	var before: float = _swings_of(melee, first_hit)[0]["amount"]
	var support: BasicEnemy = await _spawn(SUPPORT_SCENE, SUPPORT_SPOT)
	var first: int = _applied.size()
	support.set_combat_enabled(true)
	var casting: bool = await _until(func() -> bool:
		return support.support.is_casting() and support.support.get_current_action() == EnemySupport.Action.BUFF, 120)
	var began: float = _clock
	var orange: bool = false
	while support.support.is_casting():
		var c: Color = _body_color(support)
		orange = orange or (c.r > 0.8 and c.b < 0.4)
		await get_tree().physics_frame
	var cast: float = _clock - began
	var landed_at: float = _clock
	var glow: StandardMaterial3D = melee.mesh_instance.get_surface_override_material(0) as StandardMaterial3D
	var buffed: bool = _applied.size() == first + 1 and _applied[-1]["ally"] == melee and _applied[-1]["action"] == BUFF \
		and melee.attack.has_damage_buff() and is_equal_approx(melee.attack.get_attack_damage(), 18.0) \
		and glow.emission_enabled and glow.emission == SUPPORT_DATA.support.buff_color
	# A swing begun after the buff landed.
	await _until(func() -> bool: return melee.get_attack_phase() == EnemyAttack.Phase.TELEGRAPH, 120)
	var after_hit: int = _hits.size()
	await _until(func() -> bool: return _swings_of(melee, after_hit).size() >= 1, 120)
	var during: float = _swings_of(melee, after_hit)[0]["amount"]
	_record(casting and orange and absf(cast - BUFF.windup) <= 2.0 * DT and buffed and before == 15.0
			and is_equal_approx(during, 18.0),
		"BF1) everyone whole: it buffs the melee fighting the player instead — a %.2f s cast, the body orange; the melee glows, and its swing goes from %.0f to %.0f (+20%%)" % [
			cast, before, during])
	var over: bool = await _until(func() -> bool: return not melee.attack.has_damage_buff(), 60 * 7)
	var lasted: float = _clock - landed_at
	await _until(func() -> bool: return melee.get_attack_phase() == EnemyAttack.Phase.TELEGRAPH, 120)
	var expiry_hit: int = _hits.size()
	await _until(func() -> bool: return _swings_of(melee, expiry_hit).size() >= 1, 120)
	var after: float = _swings_of(melee, expiry_hit)[0]["amount"]
	_record(over and absf(lasted - 6.0) <= 3.0 * DT and melee.attack.get_attack_damage() == MELEE_DATA.attack_damage
			and melee.attack.get_damage_bonus() == 0.0 and after == 15.0 and not glow.emission_enabled,
		"BF2) the buff lasts %.2f s, then the melee's damage is exactly its own again — %.0f, no residue — and the glow goes" % [lasted, after])
	await _clear()

	# Two supports, one melee: the buff never stacks.
	_home_player()
	_player.hurtbox.set_invulnerable(true)
	melee = await _spawn(MELEE_SCENE, IN_REACH)
	melee.set_combat_enabled(true)
	var a: BasicEnemy = await _spawn(SUPPORT_SCENE, SUPPORT_SPOT + Vector3(-3, 0, 0))
	var b: BasicEnemy = await _spawn(SUPPORT_SCENE, SUPPORT_SPOT + Vector3(3, 0, 0))
	first = _applied.size()
	a.set_combat_enabled(true)
	b.set_combat_enabled(true)
	var highest: Array[float] = [0.0]
	await _until(func() -> bool:
		highest[0] = maxf(highest[0], melee.attack.get_attack_damage())
		return false, 180)
	var buffs: Array[Dictionary] = _applied.slice(first).filter(func(x: Dictionary) -> bool: return x["action"] == BUFF)
	var took: Array[Dictionary] = buffs.filter(func(x: Dictionary) -> bool: return x["amount"] > 0.0)
	_record(melee.attack.has_damage_buff() and is_equal_approx(highest[0], 18.0) and took.size() == 1
			and melee.attack.get_damage_bonus() == 0.2,
		"BF3) two supports, one melee: one buff takes (+20%%), the other is refused or never cast — its damage never above 18: no stacking (%d buff casts landed, %d took)" % [
			buffs.size(), took.size()])
	# The buffed melee dies: nothing of the buff outlives it.
	melee.hurtbox.receive_hit(DamageInfo.new(5000.0, _player, &"test"))
	await _frames(5)
	var melee_glow: StandardMaterial3D = melee.mesh_instance.get_surface_override_material(0) as StandardMaterial3D
	_record(not melee.attack.has_damage_buff() and melee.attack.get_attack_damage() == MELEE_DATA.attack_damage
			and not melee_glow.emission_enabled,
		"BF4) the buffed melee killed: its buff ends with it — no timer, no glow, no reference left")
	await _clear()

	# A heal comes before a buff.
	_home_player()
	_player.hurtbox.set_invulnerable(true)
	melee = await _spawn(MELEE_SCENE, IN_REACH)
	melee.set_combat_enabled(true)
	melee.health_component.current_health = 30.0
	support = await _spawn(SUPPORT_SCENE, SUPPORT_SPOT)
	first = _applied.size()
	support.set_combat_enabled(true)
	await _until(func() -> bool: return _applied.size() >= first + 2, 60 * 8)
	var order: Array = _applied.slice(first).map(func(x: Dictionary) -> String:
		return "heal" if x["action"] == HEAL else "buff")
	_record(order.size() >= 2 and order[0] == "heal" and order[1] == "buff",
		"BF5) a melee at 30%% it could heal or buff: the heal first (30 -> 55), then — the heal cooling down — the buff %s" % [order])
	await _clear()


# --- several supports --------------------------------------------------------------------------------------------

func _multiple_tests() -> void:
	# The same ally, two heals at once: the second clamps.
	_home_player()
	_player.hurtbox.set_invulnerable(true)
	var tank: BasicEnemy = await _ally(TANK_SCENE, HOME + Vector3(0, 0, -3.5), 0.6)
	var a: BasicEnemy = await _spawn(SUPPORT_SCENE, SUPPORT_SPOT + Vector3(-3, 0, 0), _data(false))
	var b: BasicEnemy = await _spawn(SUPPORT_SCENE, SUPPORT_SPOT + Vector3(3, 0, 0), _data(false))
	var first: int = _applied.size()
	a.set_combat_enabled(true)
	b.set_combat_enabled(true)
	await _until(func() -> bool: return _applied.size() >= first + 2, 180)
	var amounts: Array = _applied.slice(first).map(func(x: Dictionary) -> float: return x["amount"])
	_record(amounts.size() == 2 and amounts.has(65.0) and amounts.has(39.0) and tank.health_component.current_health == 260.0,
		"MS1) two supports heal the same tank at 60%% at once: +65 from the first, +39 from the second — clamped to 260: no overheal %s" % [amounts])
	await _clear()

	# Two supports, each its own ally: independent in everything.
	_home_player()
	_player.hurtbox.set_invulnerable(true)
	var tank2: BasicEnemy = await _ally(TANK_SCENE, Vector3(-8, 0.1, -2.5), 0.4)
	var melee: BasicEnemy = await _ally(MELEE_SCENE, Vector3(8, 0.1, -2.5), 0.4)
	a = await _spawn(SUPPORT_SCENE, Vector3(-8, 0.1, -6), _data(false))
	b = await _spawn(SUPPORT_SCENE, Vector3(8, 0.1, -6), _data(false))
	first = _applied.size()
	a.set_combat_enabled(true)
	b.set_combat_enabled(true)
	await _until(func() -> bool: return a.support.is_casting() and b.support.is_casting(), 120)
	var own: bool = a.support.get_support_target() == tank2 and b.support.get_support_target() == melee
	a.hurtbox.receive_hit(_crafted_hit(1.0, 60.0, 0.0))
	var a_staggered: bool = a.is_staggered() and not a.support.has_plan()
	var b_casting: bool = b.support.is_casting()
	await _until(func() -> bool: return _applied.size() > first, 120)
	_record(own and a_staggered and b_casting and _applied.size() == first + 1 and _applied[-1]["support"] == b.name
			and a.support.get_heal_cooldown_remaining() > 4.0 and tank2.health_component.current_health == 104.0
			and melee.health_component.current_health == 65.0,
		"MS2) two supports, each its own ally: one staggered mid-cast (its heal spent), the other's cast untouched — lands on its melee (40 -> 65): targets, casts and cooldowns their own")
	await _clear()


# --- stagger, knockback, critical ------------------------------------------------------------------------------------

func _stagger_tests() -> void:
	var combo: Array = await _light_combo_against(SUPPORT_SCENE)
	_record(combo[0] == [20.0, 25.0, 35.0] and combo[1] == [false, false, true],
		"ST1) the light combo on a support: %s — Light 1 (10) and Light 2 (15) flinch it, Light 3 (30) beats its 20 and staggers it %s" % [
			combo[0], combo[1]])

	# Staggered while it repositions, in its bolt's telegraph, and mid-buff.
	_home_player()
	_player.hurtbox.set_invulnerable(true)
	var support: BasicEnemy = await _spawn(SUPPORT_SCENE, SUPPORT_SPOT)
	support.health_component.set_max_health(1000.0)
	support.health_component.current_health = 1000.0
	support.set_combat_enabled(true)
	await _until(func() -> bool: return support.get_state() == BasicEnemy.State.CHASE, 90)
	_player.global_position = support.global_position + Vector3(0, 0, 2.0)
	await _until(func() -> bool: return support.get_state() == BasicEnemy.State.REPOSITION, 60)
	support.hurtbox.receive_hit(_crafted_hit(1.0, 30.0, 0.0))
	var from_reposition: bool = support.is_staggered()
	await _until(func() -> bool: return not support.is_staggered(), 90)
	_player.global_position = HOME
	support._stagger_immunity_timer = 0.0
	await _until(func() -> bool:
		return support.get_attack_phase() == EnemyAttack.Phase.TELEGRAPH and support.attack.get_current_attack() == BOLT, 240)
	var shots: int = support.attack.get_shot_count()
	support.hurtbox.receive_hit(_crafted_hit(1.0, 30.0, 0.0))
	var from_telegraph: bool = support.is_staggered()
	await _frames(40)
	var no_shot: bool = support.attack.get_shot_count() == shots
	await _clear()
	_home_player()
	_player.hurtbox.set_invulnerable(true)
	var melee: BasicEnemy = await _spawn(MELEE_SCENE, IN_REACH)
	melee.set_combat_enabled(true)
	support = await _spawn(SUPPORT_SCENE, SUPPORT_SPOT)
	support.set_combat_enabled(true)
	await _until(func() -> bool:
		return support.support.is_casting() and support.support.get_current_action() == EnemySupport.Action.BUFF, 120)
	support.hurtbox.receive_hit(_crafted_hit(1.0, 30.0, 0.0))
	var from_buff: bool = support.is_staggered() and not melee.attack.has_damage_buff()
	await _until(func() -> bool: return not support.is_staggered(), 90)
	var back: bool = support.get_state() == BasicEnemy.State.CHASE and support.get_target() == _player
	_record(from_reposition and from_telegraph and no_shot and from_buff and back and not melee.attack.has_damage_buff()
			and support.support.get_buff_cooldown_remaining() > 8.0,
		"ST2) staggered while it backs away, in its bolt's telegraph (no shot, then or later) and mid-buff (no buff, the buff spent): STAGGERED each time, then back in CHASE on the player, deciding afresh")
	await _clear()

	# A heavy mid-heal: pushed, interrupted, and back to work.
	_home_player()
	_player.hurtbox.set_invulnerable(true)
	var tank: BasicEnemy = await _ally(TANK_SCENE, HOME + Vector3(-2, 0, -3.5), 0.4)
	support = await _spawn(SUPPORT_SCENE, SUPPORT_SPOT, _data(false))
	support.health_component.set_max_health(1000.0)
	support.health_component.current_health = 1000.0
	var first: int = _applied.size()
	support.set_combat_enabled(true)
	await _until(func() -> bool: return support.support.is_casting(), 120)
	var start: Vector3 = support.global_position
	var push: Array[float] = [0.0]
	support.health_component.damaged.connect(func(_hit: DamageInfo) -> void:
		push[0] = maxf(push[0], support.get_knockback_velocity().length()))
	_strike(support, _player.combat.data.heavy_combo, 0)
	var staggered: bool = await _until(func() -> bool: return support.is_staggered(), 60)
	await _until(func() -> bool: return not support.is_knocked_back(), 90)
	var moved: float = _flat(support.global_position - start).length()
	_player.global_position = HOME
	var resumed: bool = await _until(func() -> bool:
		return support.get_state() == BasicEnemy.State.CHASE and support.get_target() == _player \
			and _flat(support.velocity).length() > 0.5, 180)
	_record(staggered and absf(push[0] - 8.0 * 1.2) < 0.01 and moved > 1.0 and _applied.size() == first
			and tank.health_component.current_health == 104.0 and resumed,
		"KB1) a heavy mid-heal: pushed at %.1f m/s (%.2f m), the cast cut off — nothing healed — and, the stagger over, it is moving again on the player's ring" % [
			push[0], moved])
	await _clear()


func _critical_tests() -> void:
	_home_player()
	_player.hurtbox.set_invulnerable(true)
	var tank: BasicEnemy = await _ally(TANK_SCENE, HOME + Vector3(-2, 0, -3.5), 0.4)
	var support: BasicEnemy = await _spawn(SUPPORT_SCENE, SUPPORT_SPOT, _data(false))
	support.health_component.set_max_health(1000.0)
	support.health_component.current_health = 1000.0
	var first: int = _applied.size()
	support.set_combat_enabled(true)
	await _until(func() -> bool: return support.support.is_casting(), 120)
	var taken: Array[DamageInfo] = []
	support.health_component.damaged.connect(func(hit: DamageInfo) -> void: taken.append(hit))
	var marks: int = _player.combat_feedback.get_critical_mark_count()
	_no_crits.critical_chance = 1.0
	_strike(support, _player.combat.data.light_combo, 0)
	await _until(func() -> bool: return taken.size() >= 1, 60)
	var marked: bool = _player.combat_feedback.get_critical_mark_count() > marks
	await _until(func() -> bool: return _applied.size() > first, 120)
	_no_crits.critical_chance = 0.0
	_record(taken.size() == 1 and taken[0].is_critical and taken[0].amount == 30.0 and not support.is_staggered()
			and marked and _applied.size() == first + 1
			and tank.health_component.current_health == 169.0,
		"CR1) a critical Light 1 mid-cast: 30 damage (20 x1.5), its mark shown — no stagger, a critical changing only the damage — and the heal lands")
	await _clear()


func _light_combo_against(scene: PackedScene) -> Array:
	_home_player()
	_player.hurtbox.set_invulnerable(true)
	var enemy: BasicEnemy = await _spawn(scene, HOME + Vector3(0, 0, -1.6))
	enemy.health_component.set_max_health(1000.0)
	enemy.health_component.current_health = 1000.0
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


# --- the player's lock --------------------------------------------------------------------------------------------

func _lock_tests() -> void:
	var indicator: TargetLockIndicator = INDICATOR_SCENE.instantiate() as TargetLockIndicator
	add_child(indicator)
	await _frames(3)
	_home_player()
	_player.hurtbox.set_invulnerable(true)
	await _ally(TANK_SCENE, HOME + Vector3(-4, 0, -7), 0.4)
	var support: BasicEnemy = await _spawn(SUPPORT_SCENE, SUPPORT_SPOT, _data(false))
	support.health_component.set_max_health(1000.0)
	support.health_component.current_health = 1000.0
	support.set_combat_enabled(true)
	await _frames(2)
	_press(&"target_lock")
	var locked: bool = _player.targeting.get_target() == support
	var held: Array[bool] = [true]
	var ringed: Array[bool] = [true]
	var states: Dictionary = {}
	var worst: Array[float] = [0.0]
	var watch: Callable = func() -> void:
		states[BasicEnemy.State.keys()[support.get_state()]] = true
		if support.support.is_casting():
			states["CASTING"] = true
		held[0] = held[0] and _player.targeting.get_target() == support
		ringed[0] = ringed[0] and indicator.is_showing() \
			and indicator.global_position.distance_to(support.get_target_point()) < 0.15
	await _until(func() -> bool:
		watch.call()
		return states.has("CASTING") and not support.support.is_casting(), 240)
	# Pressed: it backs away, the player turning after it.
	_player.global_position = support.global_position + Vector3(0, 0, 2.0)
	await _until(func() -> bool:
		watch.call()
		if support.get_state() == BasicEnemy.State.REPOSITION:
			var to: Vector3 = _flat(support.global_position - _player.global_position).normalized()
			var facing: Vector3 = _flat(-_player.visual_root.global_basis.z).normalized()
			worst[0] = maxf(worst[0], rad_to_deg(facing.angle_to(to)))
		return states.has("REPOSITION") and support.targeting.get_distance() > 4.5, 240)
	support.hurtbox.receive_hit(_crafted_hit(1.0, 30.0, 0.0))
	await _frames(2)
	watch.call()
	support.hurtbox.receive_hit(DamageInfo.new(5000.0, _player, &"test"))
	await _frames(3)
	_record(locked and held[0] and ringed[0] and worst[0] < 35.0 and states.has("CHASE") and states.has("CASTING")
			and states.has("REPOSITION") and states.has("STAGGERED") and not _player.targeting.is_locked()
			and not indicator.is_showing(),
		"LK1) locked on the support through %s: the lock held, the ring stayed on it, the player turned after it (%.0f deg behind at worst); dead, the lock and ring let go" % [
			states.keys(), worst[0]])
	indicator.queue_free()
	await _clear()


# --- shadows --------------------------------------------------------------------------------------------------------

func _shadow_tests() -> void:
	_home_player()
	_player.hurtbox.set_invulnerable(true)
	var shadow: BasicMeleeShadow = await _summon(HOME + Vector3(2, 0, -2))
	var tank: BasicEnemy = await _ally(TANK_SCENE, HOME + Vector3(-2, 0, -3.5), 0.4)
	var support: BasicEnemy = await _spawn(SUPPORT_SCENE, SUPPORT_SPOT, _data(false))
	support.health_component.set_max_health(1000.0)
	support.health_component.current_health = 1000.0
	var first: int = _applied.size()
	support.set_combat_enabled(true)
	await _until(func() -> bool: return support.support.is_casting(), 120)
	var struck: Array[int] = [0]
	support.health_component.damaged.connect(func(hit: DamageInfo) -> void:
		if hit.source == shadow:
			struck[0] += 1)
	_player.shadow_commander.set_mode(BasicMeleeShadow.CommandMode.AGGRESSIVE)
	shadow.global_position = support.global_position + Vector3(0, 0, 1.4)
	shadow.set_manual_target(support)
	await _until(func() -> bool: return _applied.size() > first, 120)
	var kept: bool = support.get_target() == _player
	_record(struck[0] >= 1 and _applied.size() == first + 1 and tank.health_component.current_health == 169.0 and kept,
		"SH1) a shadow on it mid-cast: its hits (%d) take health but do not stagger — the heal lands — and its hostile target stays the player, the M12.1 policy its data names" % struck[0])
	# The shadow's kill: 70 / 30.
	var player_xp: int = _player.progression.get_total_xp()
	var shadow_xp: int = _shadow_total_xp(shadow.instance)
	support.health_component.current_health = 5.0
	var killed: bool = await _until(func() -> bool: return support.has_died(), 60 * 8)
	await _frames(5)
	var reward: int = support.get_xp_reward()
	var cut: int = int(round(reward * PlayerProgression.SHADOW_KILL_SHARE))
	var player_gain: int = _player.progression.get_total_xp() - player_xp
	var shadow_gain: int = _shadow_total_xp(shadow.instance) - shadow_xp
	_record(killed and support.get_killer() == shadow and shadow_gain == cut and player_gain == reward - cut
			and support.support.get_support_target() == null,
		"SH2) the shadow kills it: its kill, split 70/30 — shadow +%d, player +%d of its %d — and nothing of its support left" % [
			shadow_gain, player_gain, reward])
	_player.shadow_commander.set_mode(BasicMeleeShadow.CommandMode.FOLLOW)
	_player.shadow_summoner.recall()
	await _clear()


# --- the five archetypes, a crowd -----------------------------------------------------------------------------------

func _mixed_tests() -> void:
	_home_player()
	_player.hurtbox.set_invulnerable(true)
	var melee: BasicEnemy = await _spawn(MELEE_SCENE, HOME + Vector3(-3, 0, -8))
	var ranged: BasicEnemy = await _spawn(RANGED_SCENE, HOME + Vector3(0, 0, -10))
	var tank: BasicEnemy = await _spawn(TANK_SCENE, HOME + Vector3(3, 0, -8))
	var assassin: BasicEnemy = await _spawn(ASSASSIN_SCENE, HOME + Vector3(-6, 0, -8))
	var support: BasicEnemy = await _spawn(SUPPORT_SCENE, HOME + Vector3(6, 0, -10))
	support.health_component.set_max_health(1000.0)
	support.health_component.current_health = 1000.0
	var five: Array[BasicEnemy] = [melee, ranged, tank, assassin, support]
	var first: int = _applied.size()
	for e in five:
		e.set_combat_enabled(true)
	var arrived: Dictionary = {}
	var closest_ranged: Array[float] = [100.0]
	var closest_support: Array[float] = [100.0]
	var ticks: Array[int] = [0]
	await _until(func() -> bool:
		ticks[0] += 1
		if ranged.get_target() == _player:
			closest_ranged[0] = minf(closest_ranged[0], ranged.targeting.get_distance())
		if support.get_target() == _player:
			closest_support[0] = minf(closest_support[0], support.targeting.get_distance())
		for e in [melee, tank, assassin]:
			var enemy: BasicEnemy = e
			if not arrived.has(enemy) and enemy.get_attack_phase() == EnemyAttack.Phase.TELEGRAPH:
				arrived[enemy] = _clock
		return (arrived.size() == 3 and _applied.size() > first) or ticks[0] > 480, 540)
	var buffed: Array = [melee, ranged, tank, assassin].filter(func(e: BasicEnemy) -> bool: return e.attack.has_damage_buff())
	_record(arrived.size() == 3 and arrived[assassin] < arrived[melee] and arrived[melee] < arrived[tank]
			and closest_ranged[0] >= ranged.minimum_combat_distance and closest_support[0] >= support.minimum_combat_distance
			and buffed.size() == 1 and _applied[-1]["action"] == BUFF,
		"MX1) the five together, their roles apart: the assassin strikes first, then the melee, then the tank — the front; the ranged keeps %.1f m, the support %.1f m, and, nobody hurt, buffs the %s" % [
			closest_ranged[0], closest_support[0], String((buffed[0] as Node).name) if not buffed.is_empty() else "-"])
	# The tank hurt: the support turns to it — and the player cuts the heal off.
	tank.health_component.current_health = 104.0
	var targeted: bool = await _until(func() -> bool:
		return support.support.is_casting() and support.support.get_support_target() == tank, 60 * 4)
	_strike(support, _player.combat.data.heavy_combo, 0)
	var cut: bool = await _until(func() -> bool: return support.is_staggered(), 60)
	await _frames(60)
	_record(targeted and cut and tank.health_component.current_health <= 104.0
			and _applied.slice(first).filter(func(x: Dictionary) -> bool: return x["action"] == HEAL).is_empty(),
		"MX2) the tank brought to 40%: the support picks it and starts healing — the player reaches it and a heavy cuts the cast off: STAGGERED, the tank not healed")
	# The player's kit against them all.
	var shadow: BasicMeleeShadow = await _summon(HOME + Vector3(1.5, 0, 1))
	_player.shadow_commander.set_mode(BasicMeleeShadow.CommandMode.AGGRESSIVE)
	_player.global_position = HOME + Vector3(0, 0, 3)
	_player.camera_rig.rotation.y = 0.0
	await _frames(2)
	_press(&"target_lock")
	var locked: Dictionary = {}
	for action in [&"target_switch_left", &"target_switch_left", &"target_switch_left", &"target_switch_left",
			&"target_switch_right", &"target_switch_right", &"target_switch_right", &"target_switch_right",
			&"target_switch_right", &"target_switch_right"]:
		var target: RoomCombatant = _player.targeting.get_target()
		if target != null:
			locked[target] = true
		_press(action)
		await _frames(1)
	var physics: Array[float] = [0.0]
	var measured: Array[int] = [0]
	var stamina: float = _player.combat.get_stamina()
	_player.combat.reset()
	_player.camera_rig.attack_light_pressed.emit()
	await _until(func() -> bool:
		physics[0] += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)
		measured[0] += 1
		return not _player.combat.is_attacking(), 90)
	_no_crits.critical_chance = 1.0
	_player.camera_rig.attack_heavy_pressed.emit()
	await _until(func() -> bool:
		physics[0] += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)
		measured[0] += 1
		return not _player.combat.is_attacking(), 120)
	_no_crits.critical_chance = 0.0
	_press(&"dodge")
	var spent: bool = _player.combat.get_stamina() < stamina
	await _until(func() -> bool:
		physics[0] += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)
		measured[0] += 1
		return false, 120)
	var average: float = physics[0] / maxf(measured[0], 1.0)
	var standing: bool = five.all(func(e: BasicEnemy) -> bool:
		return e.get_state() == BasicEnemy.State.DEAD or e.get_target() != null)
	_record(locked.size() == 5 and spent and standing and _violations.is_empty() and average < PHYSICS_BUDGET
			and is_instance_valid(shadow),
		"MX3) with the shadow fighting too: the lock switched across all five archetypes, a light, a critical heavy and a dodge thrown in, stamina spent — every state machine consistent, %.2f ms of physics a tick" % [
			average * 1000.0])
	_player.targeting.unlock()
	_player.shadow_commander.set_mode(BasicMeleeShadow.CommandMode.FOLLOW)
	_player.shadow_summoner.recall()
	await _clear()


func _stress_tests() -> void:
	_home_player()
	_player.hurtbox.set_invulnerable(true)
	var supports: Array[BasicEnemy] = []
	var allies: Array[BasicEnemy] = []
	for i in 4:
		var angle: float = TAU * float(i) / 4.0 + 0.4
		var s: BasicEnemy = await _spawn(SUPPORT_SCENE, HOME + Vector3(cos(angle), 0, sin(angle)) * 8.0, _data(false))
		s.combat_angle_offset_degrees = -30.0 + 20.0 * i
		supports.append(s)
	for i in 8:
		var angle: float = TAU * float(i) / 8.0
		var scene: PackedScene = TANK_SCENE if i % 2 == 0 else MELEE_SCENE
		var e: BasicEnemy = await _spawn(scene, HOME + Vector3(cos(angle), 0, sin(angle)) * 4.0)
		e.combat_angle_offset_degrees = float(i * 45 % 180) - 90.0
		allies.append(e)
	for e in supports + allies:
		e.set_combat_enabled(true)
	await _frames(60)
	var scans: Array[int] = []
	var reads: int = 0
	for s in supports:
		scans.append(s.support.get_scan_count())
		reads -= s.targeting.get_refresh_count()
	var first: int = _applied.size()
	var physics: float = 0.0
	var worst: float = 0.0
	for tick in 240:
		if tick % 60 == 0:
			for j in 2:
				var hurt: BasicEnemy = allies[(int(tick / 60.0) * 2 + j) % allies.size()]
				hurt.health_component.current_health = hurt.health_component.max_health * 0.4
		await get_tree().physics_frame
		var t: float = Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)
		physics += t
		worst = maxf(worst, t)
	var looked: Array[int] = []
	for i in supports.size():
		looked.append(supports[i].support.get_scan_count() - scans[i])
		reads += supports[i].targeting.get_refresh_count()
	var average: float = physics / 240.0
	var heals: int = _applied.slice(first).filter(func(x: Dictionary) -> bool: return x["action"] == HEAL).size()
	_record(average < PHYSICS_BUDGET and looked.all(func(n: int) -> bool: return n >= 7 and n <= 10) and reads == 0
			and heals >= 1 and _health_violations.is_empty(),
		"PF1) 4 supports and 8 allies for 4 s, allies hurt every second: %d heals, %s looks around per support (one every 0.5 s), no hostile search with targets held, %.2f ms of physics a tick (%.2f at worst)" % [
			heals, looked, average * 1000.0, worst * 1000.0])
	await _clear()
	_record(_spawned.is_empty() and get_children().filter(func(c: Node) -> bool: return c is BasicEnemy).is_empty()
			and _projectiles().is_empty(),
		"PF2) and freed again: nothing of the crowd left behind")


# --- helpers ---------------------------------------------------------------------------------------------------------

## A support's data, its own copy: `buff` false leaves the buff out (the heal
## alone); `tweak` changes anything else on the copy — the shared asset never.
func _data(buff: bool = true, tweak: Callable = Callable()) -> EnemyData:
	var d: EnemyData = SUPPORT_DATA.duplicate() as EnemyData
	d.support = SUPPORT_DATA.support.duplicate() as EnemySupportData
	if not buff:
		d.support.buff_action = null
	if tweak.is_valid():
		tweak.call(d)
	return d


func _spawn(scene: PackedScene, at: Vector3, data: EnemyData = null) -> BasicEnemy:
	var enemy: BasicEnemy = scene.instantiate() as BasicEnemy
	_count += 1
	enemy.name = "%s%d" % [String(enemy.name).trim_prefix("Basic").trim_suffix("Enemy"), _count]
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


## An ally that only has to be there: awake — in the fight — but frozen where it
## stands, at `share` of its health.
func _ally(scene: PackedScene, at: Vector3, share: float) -> BasicEnemy:
	var enemy: BasicEnemy = await _spawn(scene, at)
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
			var ally_health: HealthComponent = ally.get("health_component") as HealthComponent
			_applied.append({"support": enemy.name, "ally": ally, "action": action, "amount": amount, "time": _clock,
				"state": enemy.get_state(), "attack": enemy.attack.get_current_attack(),
				"swing": enemy.attack.get_swing_count(), "dead": ally_health == null or ally_health.is_dead}))
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


## The swings of `enemy` that reached anyone, since hit number `from`.
func _swings_of(enemy: BasicEnemy, from: int) -> Array[Dictionary]:
	return _hits.slice(from).filter(func(h: Dictionary) -> bool: return h["source"] == enemy)


func _projectiles() -> Array:
	return get_children().filter(func(c: Node) -> bool: return c is Projectile)


func _body_color(enemy: BasicEnemy) -> Color:
	var mat: StandardMaterial3D = enemy.mesh_instance.get_surface_override_material(0) as StandardMaterial3D
	return mat.albedo_color if mat != null else Color.BLACK


## The player in front of `enemy`, 1.6 m off, and swinging `combo` from `index`.
func _strike(enemy: BasicEnemy, combo: Array[AttackData], index: int) -> void:
	_player.global_position = enemy.global_position + Vector3(0, 0, 1.6)
	_player.velocity = Vector3.ZERO
	_player.camera_rig.rotation.y = 0.0
	_player.combat.reset()
	_player.combat._start_attack(combo, index)


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
