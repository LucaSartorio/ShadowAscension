extends Node3D

## M11.9 — combat feedback: the hit stop, the camera shake and the critical's
## mark, on a real player hitting real enemies and the boss.
##
##   godot --headless --path . res://tests/combat/combat_feedback_test.tscn
##
## Every hit is the player's real attack landing through its real hitbox. Time
## is measured two ways: in physics ticks, which keep coming through a hit stop,
## and in game time — every tick's delta, summed — which a hit stop holds
## still. A tick whose delta is 0 is a tick the game was held.
##
## Criticals are set per test on the player's own copy of its combat data: 0.0
## (never) and 1.0 (always) are exact, so every number below is deterministic.
## The shipped data is only read.

const FEEDBACK_DATA_PATH: String = "res://resources/characters/player_combat_feedback.tres"
const IN_FRONT: Vector3 = Vector3(0, 0.1, -1.5)
const PARKED: Array[Vector3] = [Vector3(-20, 0.1, 20), Vector3(-16, 0.1, 20), Vector3(-12, 0.1, 20)]
const BOSS_PARKED: Vector3 = Vector3(20, 0.1, 20)
const DT: float = 1.0 / 60.0
## The enemy hurtbox layer, which a shadow's hitbox reaches.
const ENEMY_HURTBOX_LAYER: int = 16
const SHADOW_HITBOX_LAYER: int = 512
const TEST_REASON: StringName = &"feedback_test"

@onready var _player: Player = $Player
@onready var _a: BasicEnemy = $EnemyA
@onready var _b: BasicEnemy = $EnemyB
@onready var _c: BasicEnemy = $EnemyC
@onready var _boss: DungeonBoss = $Boss

var _combat: PlayerCombat = null
var _feedback: PlayerCombatFeedback = null
var _rig: CameraRig = null
var _data: PlayerCombatFeedbackData = null
var _tuned: PlayerCombatData = null
var _light: Array[AttackData] = []
var _heavy: AttackData = null
## Game time, and the ticks it stood still.
var _clock: float = 0.0
var _held_ticks: int = 0
## The largest offset the shake gave the camera since it was last cleared.
var _max_offset: Vector2 = Vector2.ZERO
## Every hit of the player's that counted, with what the feedback had made of it
## the moment it was heard (the feedback hears it first).
var _accepted: Array[Dictionary] = []
var _landed: int = 0
var _violations: Array[String] = []
## A second feedback, made by a test of its own, whose stop the invariant allows.
var _other_feedback: PlayerCombatFeedback = null
var _pass: int = 0
var _fail: int = 0


func _ready() -> void:
	_reset_session()
	_combat = _player.combat
	_feedback = _player.combat_feedback
	_rig = _player.camera_rig
	_data = _feedback.data
	_tuned = _combat.data.duplicate() as PlayerCombatData
	_tuned.critical_chance = 0.0
	_combat.data = _tuned
	_light = _tuned.light_combo
	_heavy = _tuned.heavy_combo[0]
	_player.attack_hitbox.hit_landed.connect(func(_t: Node, _h: DamageInfo) -> void: _landed += 1)
	_player.attack_hitbox.hit_accepted.connect(_on_player_hit)
	_player.hurtbox.set_invulnerable(true)
	_run()


## Runs before the player and everything under it each tick, so it sees what the
## previous tick left.
func _physics_process(delta: float) -> void:
	_clock += delta
	if delta == 0.0:
		_held_ticks += 1
	var offset: Vector2 = _rig.get_shake_offset()
	_max_offset = Vector2(maxf(_max_offset.x, absf(offset.x)), maxf(_max_offset.y, absf(offset.y)))
	var holding: bool = _feedback.is_hit_stop_active() or (_other_feedback != null
		and is_instance_valid(_other_feedback) and _other_feedback.is_hit_stop_active())
	if holding != (Engine.time_scale != PlayerCombatFeedback.NORMAL_TIME_SCALE):
		_violations.append("hit stop %s with time scale %.2f" % [holding, Engine.time_scale])
	if not _rig.is_processing() and offset != Vector2.ZERO:
		_violations.append("camera offset %s with no shake running" % offset)
	if _feedback.is_hit_stop_active() and _feedback.get_hit_stop_remaining() > _data.max_hit_stop_duration + 0.001:
		_violations.append("a hit stop of %.3fs" % _feedback.get_hit_stop_remaining())


func _run() -> void:
	await _wait(0.3)
	_config_tests()
	_rule_tests()
	await _per_attack_tests()
	await _no_feedback_tests()
	await _multi_target_tests()
	await _critical_tests()
	await _game_time_tests()
	await _buffer_tests()
	await _dodge_tests()
	await _shake_rule_tests()
	await _target_lock_tests()
	await _safety_tests()
	await _accessibility_tests()
	await _boss_tests()
	await _wait(0.4)
	_record(_violations.is_empty(),
		"IV1) every tick: a hit stop held exactly while the time scale was down, never past its ceiling, and the camera sat still with no shake running %s" % [
			_violations.slice(0, 3)])
	_record(Engine.time_scale == 1.0 and not _feedback.is_hit_stop_active() and not _feedback.is_physics_processing()
			and not _rig.is_processing() and _rig.get_shake_offset() == Vector2.ZERO,
		"IV2) at the end the game runs at full speed, the feedback is idle and the camera where it belongs")
	_record(_shipped_intact(), "IV3) the shipped feedback data and attacks were never written")
	print("[SUMMARY] passed=%d failed=%d" % [_pass, _fail])
	get_tree().quit()


# --- configuration -----------------------------------------------------------------------------------

func _config_tests() -> void:
	var stops: Array[float] = []
	var shakes: Array[float] = []
	for attack in [_light[0], _light[1], _light[2], _heavy]:
		stops.append(attack.hit_stop_duration)
		shakes.append(attack.camera_shake_strength)
	var rising: bool = true
	for i in range(1, stops.size()):
		rising = rising and stops[i] > stops[i - 1] and shakes[i] > shakes[i - 1]
	_record(rising and stops[0] >= 0.02 and stops[2] <= 0.04 and stops[3] >= 0.05 and stops[3] <= 0.08,
		"CF1) hit stop L1/L2/L3/heavy %s s and shake %s m: each stronger than the last, lights within 0.02–0.04 s, the heavy within 0.05–0.08 s" % [
			stops, shakes])
	_record(_data.resource_path == FEEDBACK_DATA_PATH and _data.hit_stop_time_scale == 0.0
			and _data.critical_hit_stop_bonus == 0.015 and _data.max_hit_stop_duration == 0.1
			and _data.critical_shake_multiplier == 1.35 and _data.max_camera_shake_strength == 0.2
			and _data.camera_shake_scale == 1.0 and _data.hit_stop_scale == 1.0,
		"CF2) %s: a stop holds the game dead (time scale 0), a critical adds 0.015 s and x1.35 shake, ceilings 0.1 s and 0.2 m, accessibility scales 1.0" % [
			FEEDBACK_DATA_PATH.get_file()])


func _rule_tests() -> void:
	var l1: float = _feedback.hit_stop_duration_for(_light[0], false)
	var heavy_crit: float = _feedback.hit_stop_duration_for(_heavy, true)
	var none: float = _feedback.hit_stop_duration_for(null, true)
	var long: AttackData = _heavy.duplicate() as AttackData
	long.hit_stop_duration = 1.0
	long.camera_shake_strength = 2.0
	long.camera_shake_duration = 3.0
	_record(is_equal_approx(l1, 0.025) and is_equal_approx(heavy_crit, 0.08) and none == 0.0
			and _feedback.hit_stop_duration_for(long, false) == _data.max_hit_stop_duration,
		"RU1) a stop is its attack's (L1 %.3f s), a critical adds its bonus (heavy %.3f s), and none goes past the %.2f s ceiling" % [
			l1, heavy_crit, _data.max_hit_stop_duration])
	var shake: float = _feedback.camera_shake_strength_for(_heavy, false)
	var shake_crit: float = _feedback.camera_shake_strength_for(_heavy, true)
	_record(is_equal_approx(shake, 0.12) and is_equal_approx(shake_crit, 0.12 * 1.35)
			and _feedback.camera_shake_strength_for(long, true) == _data.max_camera_shake_strength
			and _feedback.camera_shake_duration_for(long) == _data.max_camera_shake_duration,
		"RU2) the heavy shakes %.3f m, %.3f m critical; strength and duration are clamped to %.2f m / %.2f s" % [
			shake, shake_crit, _data.max_camera_shake_strength, _data.max_camera_shake_duration])
	_feedback.set_hit_stop_scale(0.5)
	_feedback.set_camera_shake_scale(0.5)
	var half_stop: float = _feedback.hit_stop_duration_for(_heavy, false)
	var half_shake: float = _feedback.camera_shake_strength_for(_heavy, false)
	_feedback.set_hit_stop_scale(3.0)
	var high: float = _feedback.get_hit_stop_scale()
	_feedback.set_camera_shake_scale(-1.0)
	var low: float = _feedback.get_camera_shake_scale()
	_feedback.set_hit_stop_scale(1.0)
	_feedback.set_camera_shake_scale(1.0)
	_record(is_equal_approx(half_stop, 0.0325) and is_equal_approx(half_shake, 0.06) and high == 1.0 and low == 0.0,
		"RU3) the accessibility scales halve both at 0.5 (%.4f s, %.3f m) and are held within 0..1" % [half_stop, half_shake])


# --- one stop and one shake per swing, by attack -----------------------------------------------------

func _per_attack_tests() -> void:
	var held: Array[int] = []
	var expected: Array[int] = []
	var shakes: Array[float] = []
	var stops_started: Array[int] = []
	var game_time_ok: bool = true
	for attack in [_light[0], _light[1], _light[2], _heavy]:
		await _fresh(_a, IN_FRONT)
		var count: int = _feedback.get_hit_stop_count()
		var first: int = _accepted.size()
		var ticks: int = _held_ticks
		var started_clock: float = _clock
		var started_tick: int = Engine.get_physics_frames()
		await _swing_attack(attack)
		var wall: float = (Engine.get_physics_frames() - started_tick) * DT
		held.append(_held_ticks - ticks)
		expected.append(_ticks_for(attack.hit_stop_duration))
		stops_started.append(_feedback.get_hit_stop_count() - count)
		shakes.append(_accepted[first]["shake"] if _accepted.size() > first else -1.0)
		var timeline: float = attack.windup + attack.active + attack.recovery
		game_time_ok = game_time_ok and absf((_clock - started_clock) - timeline) <= 3.0 * DT and wall > _clock - started_clock
	var close: bool = true
	for i in held.size():
		close = close and absi(held[i] - expected[i]) <= 1
	_record(close and stops_started == [1, 1, 1, 1],
		"HS1) one hit, one stop: L1/L2/L3/heavy hold the game %s ticks (the data says %s)" % [held, expected])
	_record(shakes == [_light[0].camera_shake_strength, _light[1].camera_shake_strength,
			_light[2].camera_shake_strength, _heavy.camera_shake_strength],
		"HS2) and shake the camera %s m: the heavy hardest, the finisher next" % [shakes])
	_record(game_time_ok and Engine.time_scale == 1.0,
		"HS3) every attack still lasts exactly its windup + active + recovery in game time; only the wall clock grew; full speed after")
	await _frames(20)
	_record(not _rig.is_shaking() and _rig.get_shake_offset() == Vector2.ZERO and not _rig.is_processing(),
		"HS4) each shake settles: the camera back at no offset, the rig no longer processing")


func _no_feedback_tests() -> void:
	# A miss: nobody in front.
	await _fresh(_a, PARKED[0])
	var before: Dictionary = _feedback_state()
	await _swing_attack(_heavy)
	var miss: bool = _unchanged(before)

	# A hit the target refuses: it lands, it does not count.
	await _fresh(_a, IN_FRONT)
	_a.hurtbox.set_invulnerable(true, TEST_REASON)
	var hp: float = _a.health_component.current_health
	before = _feedback_state()
	await _swing_attack(_heavy)
	var refused: bool = _unchanged(before) and _landed == before["landed"] + 1 and _a.health_component.current_health == hp
	_a.hurtbox.set_invulnerable(false, TEST_REASON)

	# A target already dead whose hurtbox is still there: the same.
	await _fresh(_a, IN_FRONT)
	_a.health_component.is_dead = true
	before = _feedback_state()
	await _swing_attack(_heavy)
	var dead: bool = _unchanged(before) and _landed == before["landed"] + 1
	_a.health_component.is_dead = false

	# Somebody else's hit — a shadow's hitbox, critical every time — on an enemy.
	await _fresh(_a, IN_FRONT)
	var other: Hitbox = _spawn_other_hitbox()
	var others: Array[DamageInfo] = []
	other.hit_accepted.connect(func(_t: Node, info: DamageInfo) -> void: others.append(info))
	await _frames(2)
	before = _feedback_state()
	hp = _a.health_component.current_health
	other.activate()
	await _frames(4)
	other.deactivate()
	await _frames(4)
	var shadow: bool = _unchanged(before) and others.size() == 1 and others[0].is_critical \
		and _a.health_component.current_health < hp
	other.queue_free()
	_record(miss, "NF1) a swing that hits nothing: no stop, no shake")
	_record(refused, "NF2) a hit the target refuses lands but does not count: no stop, no shake, no damage")
	_record(dead, "NF3) a hit on a target already dead: no stop, no shake")
	_record(shadow, "NF4) a shadow's hit — critical, and counted by its own hitbox — holds nothing, shakes nothing, marks nothing")


func _multi_target_tests() -> void:
	await _line_up()
	var count: int = _feedback.get_hit_stop_count()
	var first: int = _accepted.size()
	var ticks: int = _held_ticks
	await _swing_attack(_heavy)
	var hits: int = _accepted.size() - first
	var held: int = _held_ticks - ticks
	var lengths: Array[float] = []
	for i in range(first, _accepted.size()):
		lengths.append(_accepted[i]["stop"])
	_record(hits == 3 and _feedback.get_hit_stop_count() == count + 1
			and absi(held - _ticks_for(_heavy.hit_stop_duration)) <= 1
			and lengths.all(func(l: float) -> bool: return is_equal_approx(l, _heavy.hit_stop_duration)),
		"MT1) a heavy through three enemies: three hits count, one stop of %d ticks — never three, never longer" % held)

	# Lengthened, never added: one swing asking for 0.03, then 0.08, then 0.05.
	await _frames(2)
	_feedback._on_attack_started(null)
	_feedback._play_hit_stop(0.03)
	_feedback._play_hit_stop(0.08)
	_feedback._play_hit_stop(0.05)
	var length: float = _feedback._hit_stop_length
	var started: int = _feedback.get_hit_stop_count() - count
	await _until(func() -> bool: return not _feedback.is_hit_stop_active())
	_feedback._play_hit_stop(0.05)
	var again: bool = _feedback.is_hit_stop_active()
	_record(is_equal_approx(length, 0.08) and started == 2 and not again,
		"MT2) one swing asking for 0.03, 0.08 and 0.05 s holds 0.08 s, once; the same swing gets no second stop after it")


# --- criticals --------------------------------------------------------------------------------------

func _critical_tests() -> void:
	_tuned.critical_chance = 1.0
	await _fresh(_a, IN_FRONT)
	var ticks: int = _held_ticks
	var first: int = _accepted.size()
	_combat.reset()
	_combat._start_attack(_tuned.heavy_combo, 0)
	await _until(func() -> bool: return _accepted.size() > first, 90)
	var mark: Label3D = _mark()
	var fresh_mark: bool = mark != null and mark.text == _data.critical_label_text \
		and absf(mark.position.y - (_a.get_target_point().y + _data.critical_label_height)) < 0.05
	var start_y: float = mark.position.y if mark != null else 0.0
	await _wait(_data.critical_label_duration * 0.5)
	var rising: bool = mark != null and is_instance_valid(mark) and mark.position.y > start_y and mark.modulate.a < 1.0
	await _until(func() -> bool: return _combat.get_state() == PlayerCombat.State.IDLE)
	var held: int = _held_ticks - ticks
	var hit: Dictionary = _accepted[first] if _accepted.size() > first else {}
	_record(hit.get("critical", false) and absi(held - _ticks_for(_heavy.hit_stop_duration + _data.critical_hit_stop_bonus)) <= 1
			and is_equal_approx(hit.get("shake", 0.0), _heavy.camera_shake_strength * _data.critical_shake_multiplier),
		"CR1) a critical heavy holds %d ticks instead of %d and shakes %.3f m instead of %.3f" % [
			held, _ticks_for(_heavy.hit_stop_duration), hit.get("shake", 0.0), _heavy.camera_shake_strength])
	_record(fresh_mark and rising,
		"CR2) it leaves its mark: \"%s\" above the target, rising and fading" % _data.critical_label_text)
	await _wait(_data.critical_label_duration)
	_record(_feedback.get_critical_mark_count() == 0, "CR3) and the mark is gone once it has faded")

	_tuned.critical_chance = 0.0
	await _fresh(_a, IN_FRONT)
	await _swing_attack(_light[0], false)
	var plain: bool = _feedback.get_critical_mark_count() == 0
	_record(plain, "CR4) a normal hit leaves no mark")

	# Never more marks than the data allows.
	var capped: PlayerCombatFeedbackData = _data.duplicate() as PlayerCombatFeedbackData
	capped.max_critical_labels = 2
	_feedback.data = capped
	_tuned.critical_chance = 1.0
	await _line_up()
	var before: int = _accepted.size()
	_combat.reset()
	_combat._start_attack(_tuned.heavy_combo, 0)
	await _until(func() -> bool: return _accepted.size() >= before + 3, 90)
	var shown: int = _feedback.get_critical_mark_count()
	await _until(func() -> bool: return _combat.get_state() == PlayerCombat.State.IDLE)
	_feedback.data = _data
	_tuned.critical_chance = 0.0
	await _wait(_data.critical_label_duration + 0.1)
	_record(shown == 2 and _feedback.get_critical_mark_count() == 0,
		"CR5) three criticals in one swing with room for two marks show two (%d)" % shown)


# --- the game holds, and carries on from where it was ----------------------------------------------

func _game_time_tests() -> void:
	# A heavy's push, the stagger it starts and the attack's own timeline stand
	# still through the stop, and resume.
	await _fresh(_a, IN_FRONT)
	_combat.restore_stamina(_combat.get_max_stamina())
	_combat.try_spend_stamina(60.0)
	await _wait(_tuned.stamina_regen_delay + 0.1)
	var regenerating: bool = _combat.is_regenerating_stamina()
	var start: Vector3 = _a.global_position
	_aim_straight()
	_combat.reset()
	_combat._start_attack(_tuned.heavy_combo, 0)
	await _until(func() -> bool: return _feedback.is_hit_stop_active(), 90)
	var snapshots: Array[Dictionary] = []
	while _feedback.is_hit_stop_active():
		snapshots.append({"position": _a.global_position, "push": _a.get_knockback_velocity(),
			"stagger": _a._stagger_timer, "elapsed": _combat._state_elapsed, "stamina": _combat.get_stamina(),
			"state": _combat.get_state()})
		await get_tree().physics_frame
	# The first snapshot is the tick the hit landed in, which still runs at full
	# speed — its time scale was set before the hit. Every one after it is held.
	var still: bool = snapshots.size() >= 3
	for i in range(2, snapshots.size()):
		var same: Dictionary = snapshots[i]
		var held: Dictionary = snapshots[1]
		still = still and (same["position"] as Vector3).distance_to(held["position"]) < 0.001 \
			and (same["push"] as Vector3).is_equal_approx(held["push"]) \
			and same["stagger"] == held["stagger"] and same["elapsed"] == held["elapsed"] \
			and same["stamina"] == held["stamina"] and same["state"] == held["state"]
	await _frames(3)
	var resumed: bool = snapshots.size() >= 2 and _a.global_position.distance_to(snapshots[-1]["position"]) > 0.05 \
		and _a.get_knockback_velocity().length() < (snapshots[-1]["push"] as Vector3).length() \
		and _combat.get_stamina() > snapshots[-1]["stamina"]
	_record(regenerating and still and resumed and _a.is_staggered(),
		"GT1) through the stop (%d held ticks) the push, the stagger, the heavy's timeline and stamina regeneration all stand still, then carry on" % [
			snapshots.size() - 1])
	await _until(func() -> bool: return _combat.get_state() == PlayerCombat.State.IDLE and not _a.is_knocked_back())
	var pushed_with: float = _flat(_a.global_position - start).length()

	# The same heavy with no hit stop pushes exactly as far.
	await _fresh(_a, IN_FRONT)
	_feedback.set_hit_stop_scale(0.0)
	start = _a.global_position
	await _swing_attack(_heavy)
	await _until(func() -> bool: return not _a.is_knocked_back())
	var pushed_without: float = _flat(_a.global_position - start).length()
	_feedback.set_hit_stop_scale(1.0)
	_record(pushed_with > 0.5 and absf(pushed_with - pushed_without) < 0.02,
		"GT2) the push goes %.2f m with the stop and %.2f m without: resumed, not lost, not doubled" % [pushed_with, pushed_without])

	# A stagger lasts its game time, the stop included in the wall time only.
	await _fresh(_a, IN_FRONT)
	_aim_straight()
	_combat.reset()
	_combat._start_attack(_light, 2)
	await _until(func() -> bool: return _a.is_staggered(), 90)
	var clock: float = _clock
	var tick: int = Engine.get_physics_frames()
	await _until(func() -> bool: return not _a.is_staggered(), 120)
	var game: float = _clock - clock
	var wall: float = (Engine.get_physics_frames() - tick) * DT
	_record(absf(game - _a.stagger_duration) <= 2.0 * DT and wall > game and _a.is_stagger_immune(),
		"GT3) Light 3's stagger lasts %.2f s of game time (%.2f s on the wall): the stop never stretches it, and one stagger is all it gives" % [
			game, wall])
	_combat.restore_stamina(_combat.get_max_stamina())
	await _until(func() -> bool: return _combat.get_state() == PlayerCombat.State.IDLE)


func _buffer_tests() -> void:
	# The next press lands in the stop — the attack is still ACTIVE, so it is
	# buffered, and the buffer does not drain while the game is held.
	await _fresh(_a, IN_FRONT)
	var started: Array[StringName] = []
	var on_started: Callable = func(attack: AttackData) -> void: started.append(attack.id)
	_combat.attack_started.connect(on_started)
	var buffered_held: bool = true
	var count: int = _feedback.get_hit_stop_count()
	_aim_straight()
	_combat.reset()
	_combat.request_light_attack()
	for step in 2:
		var stops: int = _feedback.get_hit_stop_count()
		await _until(func() -> bool: return _feedback.get_hit_stop_count() > stops, 90)
		# Pressed in the tick the hit landed in: the stop has begun, the attack
		# is still ACTIVE, so the press is buffered. That tick still runs at full
		# speed; from the next, held, the buffer must not drain.
		_combat.request_light_attack()
		var pressed: float = _combat._buffered_attack
		await get_tree().physics_frame
		var buffer: float = _combat._buffered_attack
		while _feedback.is_hit_stop_active():
			if _combat._buffered_attack != buffer:
				buffered_held = false
			await get_tree().physics_frame
		buffered_held = buffered_held and pressed == _tuned.input_buffer_time and buffer > 0.0
	await _until(func() -> bool: return _combat.get_state() == PlayerCombat.State.IDLE, 240)
	_combat.attack_started.disconnect(on_started)
	_record(buffered_held and started == [_light[0].id, _light[1].id, _light[2].id]
			and _feedback.get_hit_stop_count() == count + 3,
		"BF1) a press during each stop is buffered and kept — %s follow each other, three hits, three stops" % [started])


func _dodge_tests() -> void:
	await _fresh(_a, IN_FRONT)
	_combat.restore_stamina(_combat.get_max_stamina())
	_aim_straight()
	_combat.reset()
	_combat._start_attack(_tuned.heavy_combo, 0)
	await _until(func() -> bool: return _feedback.is_hit_stop_active(), 90)
	var refused: bool = not _combat.request_dodge() and _combat.get_stamina() == _combat.get_max_stamina()
	await _until(func() -> bool: return _combat.can_dodge(), 90)
	var dodged: bool = _combat.request_dodge()
	var phases: Array[PlayerCombat.DodgePhase] = [_combat.get_dodge_phase()]
	var iframe_clock: float = -1.0
	var iframe_time: float = 0.0
	while _combat.is_dodging():
		await get_tree().physics_frame
		var phase: PlayerCombat.DodgePhase = _combat.get_dodge_phase()
		if phase != phases[-1]:
			phases.append(phase)
			if phase == PlayerCombat.DodgePhase.INVULNERABLE:
				iframe_clock = _clock
			elif iframe_clock >= 0.0 and iframe_time == 0.0:
				iframe_time = _clock - iframe_clock
	_record(refused and dodged and phases == [PlayerCombat.DodgePhase.STARTUP, PlayerCombat.DodgePhase.INVULNERABLE,
			PlayerCombat.DodgePhase.RECOVERY, PlayerCombat.DodgePhase.NONE]
			and absf(iframe_time - (_tuned.invulnerability_end - _tuned.invulnerability_start)) <= 2.0 * DT,
		"DG1) a dodge pressed in the heavy's stop is refused as it always is mid-swing, costing nothing; in the cancel window it runs, its i-frames %.2f s" % iframe_time)
	_combat.restore_stamina(_combat.get_max_stamina())
	await _wait(_tuned.dodge_cooldown + 0.1)


# --- the camera -------------------------------------------------------------------------------------

func _shake_rule_tests() -> void:
	await _fresh(_a, PARKED[0])
	var local_before: Transform3D = _rig.transform
	var basis_before: Basis = _rig.global_basis
	var camera_before: Transform3D = _rig.camera.transform
	var played: bool = _rig.shake(0.1, 0.3)
	var weaker: bool = _rig.shake(0.05, 0.3)
	var kept: float = _rig._shake_strength
	var stronger: bool = _rig.shake(0.15, 0.2)
	_max_offset = Vector2.ZERO
	var rig_still: bool = true
	for i in 6:
		await get_tree().physics_frame
		rig_still = rig_still and _rig.transform.is_equal_approx(local_before) \
			and _rig.global_basis.is_equal_approx(basis_before) and _rig.camera.transform.is_equal_approx(camera_before)
	var moved: bool = _max_offset.length() > 0.0 and _max_offset.x <= 0.15 + 0.001 and _max_offset.y <= 0.15 + 0.001
	_record(played and not weaker and is_equal_approx(kept, 0.1) and stronger and _rig._shake_strength == 0.15,
		"SH1) one shake at a time: a weaker one is ignored, a stronger one replaces it — nothing adds up")
	_record(moved and rig_still,
		"SH2) the camera is thrown (up to %s m) through its offsets alone: the rig, and the camera node, never move" % [_max_offset])
	_rig.stop_shake()
	_record(not _rig.is_shaking() and _rig.get_shake_offset() == Vector2.ZERO and not _rig.is_processing(),
		"SH3) stopping a shake puts the camera straight back")
	_rig.shake(0.1, 0.3)
	get_tree().paused = true
	var cleared: bool = _rig.get_shake_offset() == Vector2.ZERO and not _rig.is_shaking()
	var while_paused: bool = _rig.shake(0.1, 0.3)
	get_tree().paused = false
	await get_tree().physics_frame
	_record(cleared and not while_paused, "SH4) a pause ends the shake at once, and none starts while paused")


func _target_lock_tests() -> void:
	await _fresh(_a, Vector3(0.6, 0.1, -1.4))
	_player.camera_rig.rotation.y = deg_to_rad(20.0)
	await _frames(3)
	var locked: bool = _player.targeting.lock_on() and _player.targeting.get_target() == _a
	var rig_yaw: float = _rig.rotation.y
	var bearing: float = _player.targeting._bearing(_a)
	var held: bool = true
	var same_view: bool = true
	var shook: bool = false
	_combat.reset()
	_combat._start_attack(_tuned.heavy_combo, 0)
	while _combat.get_state() != PlayerCombat.State.IDLE:
		await get_tree().physics_frame
		shook = shook or _rig.is_shaking()
		held = held and _player.targeting.get_target() == _a
		same_view = same_view and _rig.rotation.y == rig_yaw \
			and absf(_player.targeting._bearing(_a) - bearing) < 0.01
	_record(locked and shook and held and same_view,
		"TL1) locked on, the heavy stops and shakes: the lock holds the same target, and what the camera faces — its bearing to the target — never moves")
	_player.targeting.unlock()


# --- time scale safety --------------------------------------------------------------------------------

func _safety_tests() -> void:
	# The player dies in the middle of a stop.
	await _fresh(_a, IN_FRONT)
	_aim_straight()
	_combat.reset()
	_combat._start_attack(_tuned.heavy_combo, 0)
	await _until(func() -> bool: return _feedback.is_hit_stop_active(), 90)
	var shaking: bool = _rig.is_shaking()
	_player.health_component.take_damage(DamageInfo.new(10000.0))
	var death: bool = shaking and Engine.time_scale == 1.0 and not _feedback.is_hit_stop_active() \
		and not _rig.is_shaking() and _rig.get_shake_offset() == Vector2.ZERO
	await _frames(3)
	_record(death and _player.health_component.is_dead and _combat.get_state() == PlayerCombat.State.DEAD,
		"TS1) the player dies mid-stop: the game is let go that very moment, the shake stops, and the death goes on at full speed")
	_player.health_component.reset_to(_player.health_component.max_health)
	_combat.reset()

	# The game pauses in the middle of a stop, and a hit is reported while paused.
	await _fresh(_a, IN_FRONT)
	_aim_straight()
	_combat.reset()
	_combat._start_attack(_tuned.heavy_combo, 0)
	await _until(func() -> bool: return _feedback.is_hit_stop_active(), 90)
	get_tree().paused = true
	var paused_free: bool = Engine.time_scale == 1.0 and not _feedback.is_hit_stop_active()
	var count: int = _feedback.get_hit_stop_count()
	var crit: DamageInfo = DamageInfo.new(1.0, _player)
	crit.is_critical = true
	_feedback._on_attack_started(null)
	_player.attack_hitbox.hit_accepted.emit(_b, crit)
	var nothing_while_paused: bool = _feedback.get_hit_stop_count() == count and Engine.time_scale == 1.0 \
		and not _rig.is_shaking() and _feedback.get_critical_mark_count() == 0
	await get_tree().physics_frame
	get_tree().paused = false
	await _until(func() -> bool: return _combat.get_state() == PlayerCombat.State.IDLE)
	_record(paused_free, "TS2) the game pauses mid-stop: the stop ends there — a menu never opens on a held game")
	_record(nothing_while_paused,
		"TS3) a hit reported while the game is paused — the boss's last, which opens the run summary — holds nothing, shakes nothing, marks nothing")

	# The node leaves the tree, or is freed, in the middle of a stop.
	var bare: PlayerCombatFeedback = PlayerCombatFeedback.new()
	bare.data = _data
	_other_feedback = bare
	add_child(bare)
	bare._on_attack_started(null)
	bare._play_hit_stop(0.1)
	var held: bool = Engine.time_scale == 0.0
	remove_child(bare)
	var removed: bool = Engine.time_scale == 1.0
	add_child(bare)
	bare._on_attack_started(null)
	bare._play_hit_stop(0.1)
	bare.queue_free()
	await get_tree().process_frame
	await get_tree().physics_frame
	_record(held and removed and Engine.time_scale == 1.0,
		"TS4) a feedback taken out of the scene, or freed, mid-stop hands the game back at full speed — a scene change or a quit can never leave it held")

	# Rapid requests in one tick never stack past the ceiling.
	_feedback._on_attack_started(null)
	for i in 10:
		_feedback._play_hit_stop(_feedback.hit_stop_duration_for(_heavy, true))
	var one: bool = _feedback._hit_stop_length <= _data.max_hit_stop_duration
	await _until(func() -> bool: return not _feedback.is_hit_stop_active())
	_record(one and Engine.time_scale == 1.0, "TS5) ten stops asked for at once are one, within the ceiling, and it ends")


func _accessibility_tests() -> void:
	_tuned.critical_chance = 1.0
	_feedback.set_hit_stop_scale(0.0)
	_feedback.set_camera_shake_scale(0.0)
	await _fresh(_a, IN_FRONT)
	var ticks: int = _held_ticks
	var count: int = _feedback.get_hit_stop_count()
	_max_offset = Vector2.ZERO
	var hp: float = _a.health_component.current_health
	await _swing_attack(_heavy, false)
	var off: bool = _held_ticks == ticks and _feedback.get_hit_stop_count() == count and _max_offset == Vector2.ZERO \
		and hp - _a.health_component.current_health == 60.0
	_feedback.set_hit_stop_scale(1.0)
	_feedback.set_camera_shake_scale(1.0)
	_tuned.critical_chance = 0.0
	await _wait(_data.critical_label_duration + 0.1)
	_record(off, "AC1) with both accessibility scales at 0 a critical heavy holds nothing and shakes nothing — and still deals its 60")


func _boss_tests() -> void:
	var spot: Vector3 = Vector3(12, 0.1, -4)
	_boss.global_position = spot
	_player.global_position = spot + Vector3(0, 0, 1.6)
	_player.velocity = Vector3.ZERO
	await _frames(4)
	var count: int = _feedback.get_hit_stop_count()
	var hp: float = _boss.health_component.current_health
	_aim_at(_boss)
	_combat.reset()
	_combat._start_attack(_tuned.heavy_combo, 0)
	await _until(func() -> bool: return _boss.health_component.current_health < hp, 90)
	var flashing: bool = _boss.is_flashing()
	await _until(func() -> bool: return _combat.get_state() == PlayerCombat.State.IDLE)
	_record(flashing and _feedback.get_hit_stop_count() == count + 1 and _flat(_boss.global_position - spot).length() < 0.05
			and not _boss.is_staggered(),
		"BO1) the boss hit: its own flash, one stop, one shake — barely nudged, and a parked boss is not staggered")
	_boss.health_component.current_health = 1.0
	_aim_at(_boss)
	_combat.reset()
	_combat._start_attack(_light, 0)
	await _until(func() -> bool: return _boss.get_state() == DungeonBoss.State.DEAD, 90)
	var stopped: bool = _feedback.get_hit_stop_count() == count + 2
	await _until(func() -> bool: return not _feedback.is_hit_stop_active())
	await _frames(2)
	_record(stopped and Engine.time_scale == 1.0,
		"BO2) its killing blow is a hit like any other — one light stop, no slow motion, no cinematic — and the game runs on")
	_boss.global_position = BOSS_PARKED


# --- helpers ------------------------------------------------------------------------------------------

func _on_player_hit(target: Node, info: DamageInfo) -> void:
	_accepted.append({"target": target, "critical": info.is_critical, "amount": info.amount,
		"stop": _feedback._hit_stop_length, "shake": _rig._shake_strength, "shake_time": _rig._shake_duration})


func _feedback_state() -> Dictionary:
	_max_offset = Vector2.ZERO
	return {"stops": _feedback.get_hit_stop_count(), "accepted": _accepted.size(), "held": _held_ticks,
		"landed": _landed, "marks": _feedback.get_critical_mark_count()}


func _unchanged(before: Dictionary) -> bool:
	return _feedback.get_hit_stop_count() == before["stops"] and _held_ticks == before["held"] \
		and _accepted.size() == before["accepted"] and _max_offset == Vector2.ZERO and not _rig.is_shaking() \
		and _feedback.get_critical_mark_count() == before["marks"] and Engine.time_scale == 1.0


## Held ticks for a stop of `duration`: the whole ticks it takes to reach it.
func _ticks_for(duration: float) -> int:
	return ceili((duration - PlayerCombatFeedback.TIME_EPSILON) / DT)


func _mark() -> Label3D:
	for child in _feedback.get_children():
		if child is Label3D:
			return child as Label3D
	return null


func _spawn_other_hitbox() -> Hitbox:
	var hitbox: Hitbox = Hitbox.new()
	hitbox.collision_layer = SHADOW_HITBOX_LAYER
	hitbox.collision_mask = ENEMY_HURTBOX_LAYER
	hitbox.damage = 5.0
	hitbox.critical_chance = 1.0
	hitbox.critical_damage_multiplier = 2.0
	hitbox.source = _boss
	var shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(2, 2, 2)
	shape.shape = box
	hitbox.add_child(shape)
	add_child(hitbox)
	hitbox.global_position = _a.global_position + Vector3(0, 1, 0)
	return hitbox


## Three enemies side by side in front of the player, whole, all inside one
## swing.
func _line_up() -> void:
	await _fresh(_b, Vector3(0.0, 0.1, -1.5), false, true)
	await _fresh(_c, Vector3(0.95, 0.1, -1.5), false, true)
	await _fresh(_a, Vector3(-0.95, 0.1, -1.5), true, true)


## Parks `enemy` at `at`, whole, with nothing of a previous hit left — and,
## unless `keep_others`, the other two back out of the way.
func _fresh(enemy: BasicEnemy, at: Vector3, reset_player: bool = true, keep_others: bool = false) -> void:
	if not keep_others:
		var enemies: Array[BasicEnemy] = [_a, _b, _c]
		for i in enemies.size():
			if enemies[i] != enemy:
				_park(enemies[i], PARKED[i])
	if reset_player:
		_combat.reset()
		_player.global_position = Vector3(0, 0.1, 0)
		_player.velocity = Vector3.ZERO
		_aim_straight()
	_park(enemy, at)
	await _frames(3)


func _park(enemy: BasicEnemy, at: Vector3) -> void:
	enemy.set_combat_enabled(false)
	enemy._clear_reactions()
	enemy.global_position = at
	enemy.velocity = Vector3.ZERO
	enemy.health_component.current_health = enemy.health_component.max_health


## The player's own attack, aimed straight ahead unless `aim` is false, run to
## its end.
func _swing_attack(attack: AttackData, aim: bool = true) -> void:
	if aim:
		_aim_straight()
	_combat.reset()
	if _heavy == attack:
		_combat._start_attack(_tuned.heavy_combo, 0)
	else:
		_combat._start_attack(_light, _light.find(attack))
	await _until(func() -> bool: return _combat.get_state() == PlayerCombat.State.IDLE, 180)


func _aim_straight() -> void:
	_player.camera_rig.rotation.y = 0.0


func _aim_at(target: Node3D) -> void:
	var to: Vector3 = _flat(target.global_position - _player.global_position)
	if to.length_squared() > 0.0001:
		_player.camera_rig.rotation.y = atan2(-to.x, -to.z)


func _shipped_intact() -> bool:
	return _data.hit_stop_time_scale == 0.0 and _data.max_hit_stop_duration == 0.1 \
		and _data.max_critical_labels == 4 and _data.camera_shake_scale == 1.0 and _data.hit_stop_scale == 1.0 \
		and _light[0].hit_stop_duration == 0.025 and _heavy.hit_stop_duration == 0.065 \
		and _heavy.camera_shake_strength == 0.12


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
