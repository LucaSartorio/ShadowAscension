extends Node3D

## M11.1 — the combat foundation, on a real player against training dummies.
##
##   godot --headless --path . res://tests/combat/combat_foundation_test.tscn
##
## Attacks go in the way a device sends them (the camera rig's signal), and are
## read back through PlayerCombat's own queries: the state, the attack, the
## buffer. Frame-rate independence is checked on a bare controller stepped by
## hand at 30 Hz and 144 Hz, since a scene only ever runs at one rate.
##
## Tests that need a window the shipped attacks do not have (a long active phase,
## a narrower combo window, an attack that roots the player) run on a copy of the
## data, never on the shared .tres — and the last check is that the .tres came
## through untouched.
##
## Updated for M11.2: the chain now ends with any attack that did not accept a
## follow-up, and a press is held only for the short buffer before a window.

const DUMMY_SCENE: PackedScene = preload("res://scenes/enemies/training_dummy.tscn")
const IN_FRONT: Vector3 = Vector3(0, 0.1, -1.5)
const FAR_AWAY: Vector3 = Vector3(0, 0.1, -8.0)
## Two physics frames: how far a measured duration may sit from its configured
## value in a real scene (one for where the press fell, one for the step that
## crossed the boundary).
const FRAME_SLACK: int = 2

@onready var _player: Player = $Player

var _combat: PlayerCombat = null
var _shipped: PlayerCombatData = null
var _started: Array[StringName] = []
var _pass: int = 0
var _fail: int = 0


## Criticals are random (M11.7) and this suite checks exact damage, so they are
## off for its whole run: every player here reads this one cached instance of
## the combat data. critical_hit_test and m11_critical_run test criticals.
var _no_crits: PlayerCombatData = preload("res://resources/characters/player_combat.tres")


func _ready() -> void:
	_no_crits.critical_chance = 0.0
	_reset_session()
	_combat = _player.combat
	_shipped = _combat.data
	_combat.attack_started.connect(_on_attack_started)
	_run()


func _run() -> void:
	await _wait(0.2)
	await _state_tests()
	await _buffer_tests()
	await _combo_window_tests()
	await _movement_tests()
	await _hit_tests()
	await _damage_tests()
	await _enemy_death_tests()
	await _player_death_tests()
	await _pause_tests()
	_frame_rate_tests()
	_record(_shipped_untouched(), "Z9) the shipped PlayerCombatData came through every test untouched")
	print("[SUMMARY] passed=%d failed=%d" % [_pass, _fail])
	get_tree().quit()


# --- combat state -------------------------------------------------------------------------

func _state_tests() -> void:
	await _fresh()
	_record(_combat.get_state() == PlayerCombat.State.IDLE and _combat.get_current_attack() == null
			and not _combat.has_buffered_attack() and not _player.attack_hitbox.is_active(),
		"S1) a fresh player's combat is IDLE: no attack, nothing buffered, hitbox shut")

	_fire()
	_record(_combat.get_state() == PlayerCombat.State.WINDUP and _attack_id() == &"light_attack_1"
			and _started == [&"light_attack_1"],
		"S2/B-A) a press on a free player starts light_attack_1 at once (%s, started %s)" % [
			_state_name(), _started])
	_record(not _player.attack_hitbox.is_active(), "S3) the hitbox stays shut through the windup")
	_fire()
	_record(_started.size() == 1 and _attack_id() == &"light_attack_1"
			and _combat.get_state() == PlayerCombat.State.WINDUP,
		"S4) a second press mid-attack starts nothing: still light_attack_1, one attack started")

	var to_active: int = await _frames_until(PlayerCombat.State.ACTIVE)
	var open_in_active: bool = _player.attack_hitbox.is_active()
	var to_recovery: int = await _frames_until(PlayerCombat.State.RECOVERY)
	var shut_in_recovery: bool = not _player.attack_hitbox.is_active()
	var to_idle: int = await _frames_until(PlayerCombat.State.IDLE)
	var attack: AttackData = _shipped.light_combo[0]
	_record(_near(to_active, attack.windup) and open_in_active,
		"S5) windup %.2fs, then ACTIVE with the hitbox open (%d frames)" % [attack.windup, to_active])
	_record(_near(to_recovery, attack.active) and shut_in_recovery,
		"S6) active %.2fs, then RECOVERY with the hitbox shut (%d frames)" % [attack.active, to_recovery])
	_record(_near(to_idle, attack.recovery) and _combat.get_current_attack() == null,
		"S7) recovery %.2fs, then IDLE with no attack (%d frames)" % [attack.recovery, to_idle])
	await get_tree().physics_frame
	_record(not _player.attack_hitbox.monitoring, "S8) and the hitbox is no longer monitoring")
	_record(_started == [&"light_attack_1"],
		"S9) the press made in the windup expired: nothing followed light_attack_1 (%s)" % [_started])
	_fire()
	_record(_attack_id() == &"light_attack_1",
		"S10) the player is free again, and the chain ended with the attack: the next press is light_attack_1")
	await _frames_until(PlayerCombat.State.IDLE)


# --- the input buffer ---------------------------------------------------------------------

func _buffer_tests() -> void:
	# B: pressed in the combo window (the recovery): queued, started as it ends.
	await _fresh()
	_fire()
	await _frames_until(PlayerCombat.State.RECOVERY)
	_fire()
	var buffered: bool = _combat.get_queued_attack() != null and _started.size() == 1
	var frames: int = 0
	while _started.size() < 2 and frames < 60:
		await get_tree().physics_frame
		frames += 1
	var recovery: float = _shipped.light_combo[0].recovery
	_record(buffered and _started == [&"light_attack_1", &"light_attack_2"] and _near(frames, recovery)
			and not _combat.has_buffered_attack(),
		"B-B) pressed in recovery: queued, then light_attack_2 starts as recovery ends (%d frames, %s)" % [
			frames, _started])
	await _frames_until(PlayerCombat.State.IDLE)

	# C, too early: a press at the start of an attack outlives the buffer.
	await _fresh()
	_fire()
	await get_tree().physics_frame
	_fire()
	var kept_at_first: bool = _combat.has_buffered_attack()
	var expired_after: int = 0
	while _combat.has_buffered_attack() and expired_after < 120:
		await get_tree().physics_frame
		expired_after += 1
	var still_light_1: bool = _attack_id() == &"light_attack_1"
	await _frames_until(PlayerCombat.State.IDLE)
	await _wait(0.1)
	_record(kept_at_first and _near(expired_after, _shipped.input_buffer_time) and still_light_1
			and _started == [&"light_attack_1"],
		"B-C1) too early: held %.2fs (%d frames), dropped before light_attack_1 ended, nothing followed" % [
			_shipped.input_buffer_time, expired_after])

	# C, too late: once the attack is over, so is the chain.
	_fire()
	_record(_attack_id() == &"light_attack_1",
		"B-C2) too late: a press after the attack ended starts the combo over at light_attack_1")
	await _frames_until(PlayerCombat.State.IDLE)

	# One slot, not a queue.
	await _fresh()
	_fire()
	await _frames_until(PlayerCombat.State.RECOVERY)
	for i in 6:
		_fire()
	await _frames_until(PlayerCombat.State.ACTIVE)
	await _frames_until(PlayerCombat.State.IDLE)
	_record(_started == [&"light_attack_1", &"light_attack_2"],
		"B-D) six presses in one recovery buy one attack, not six (%s)" % [_started])

	# Dodging: an attack press is not buffered.
	await _fresh()
	_player._on_dodge_pressed()
	_fire()
	var ignored: bool = _combat.is_dodging() and not _combat.has_buffered_attack()
	await _frames_until(PlayerCombat.State.IDLE)
	await get_tree().physics_frame
	_record(ignored and _started.is_empty() and _combat.get_state() == PlayerCombat.State.IDLE,
		"B-E) a press during a dodge is ignored, not held for after it")


# --- the combo window ---------------------------------------------------------------------

func _combo_window_tests() -> void:
	# After the attack is over the chain is not waiting any more.
	await _fresh()
	_fire()
	await _frames_until(PlayerCombat.State.IDLE)
	await _wait(0.3)
	_fire()
	_record(_attack_id() == &"light_attack_1",
		"W1) 0.3s after light_attack_1 ended without a follow-up: light_attack_1 again")
	await _frames_until(PlayerCombat.State.IDLE)

	# The last attack ends the chain, whatever is buffered.
	await _fresh()
	await _run_chain(3)
	_fire()
	await _frames_until(PlayerCombat.State.IDLE)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var after_three: Array[StringName] = _started.duplicate()
	_fire()
	_record(after_three == [&"light_attack_1", &"light_attack_2", &"light_attack_3"] and _attack_id() == &"light_attack_1",
		"W2) light_attack_3 ends the chain: a press during it is ignored, the next press is light_attack_1")
	await _frames_until(PlayerCombat.State.IDLE)

	# A window that opens halfway through recovery: a press at its start is held,
	# taken when the window opens, and the follow-up still waits for the end.
	_combat.data = _copy_of_shipped()
	_combat.data.light_combo[0].combo_window_start = 0.5
	await _fresh()
	_fire()
	await _frames_until(PlayerCombat.State.RECOVERY)
	_fire()
	var held_first: bool = _combat.has_buffered_attack() and _combat.get_queued_attack() == null
	var frames: int = 0
	while _combat.get_queued_attack() == null and frames < 60:
		await get_tree().physics_frame
		frames += 1
	var half: float = _shipped.light_combo[0].recovery * 0.5
	var queued_at_half: bool = _near(frames, half)
	while _started.size() < 2 and frames < 60:
		await get_tree().physics_frame
		frames += 1
	_record(held_first and queued_at_half and _started == [&"light_attack_1", &"light_attack_2"]
			and _near(frames, _shipped.light_combo[0].recovery),
		"W3) combo_window_start 0.5: held, queued at half recovery, light_attack_2 at its end (%d frames)" % frames)
	await _frames_until(PlayerCombat.State.IDLE)
	_combat.data = _shipped


# --- movement and facing during an attack -------------------------------------------------

func _movement_tests() -> void:
	await _fresh()
	Input.action_press("move_forward")
	var start: Vector3 = _player.global_position
	_fire()
	await _frames_until(PlayerCombat.State.IDLE)
	var walked: float = _flat_distance(start, _player.global_position)
	Input.action_release("move_forward")
	_record(walked > 1.0,
		"M1) the shipped attacks leave movement as it was: walked %.2fm through light_attack_1" % walked)

	_combat.data = _copy_of_shipped()
	_combat.data.light_combo[0].movement_multiplier = 0.0
	await _fresh()
	Input.action_press("move_forward")
	start = _player.global_position
	_fire()
	var rooted: bool = true
	while _combat.is_attacking():
		await get_tree().physics_frame
		if _flat_distance(start, _player.global_position) > 0.01:
			rooted = false
	Input.action_release("move_forward")
	_combat.data = _shipped
	_record(rooted, "M2) an attack with movement_multiplier 0 roots the player for its duration")

	await _fresh()
	_fire()
	var aimed: float = _player.visual_root.rotation.y
	Input.action_press("move_right")
	var held: bool = true
	while _combat.is_attacking():
		await get_tree().physics_frame
		if not is_equal_approx(_player.visual_root.rotation.y, aimed):
			held = false
	await _frames(20)
	Input.action_release("move_right")
	var turned: bool = not is_equal_approx(_player.visual_root.rotation.y, aimed)
	_record(held and turned,
		"M3) the swing keeps its aim while it runs, and the player turns again once free")


# --- hit detection ------------------------------------------------------------------------

func _hit_tests() -> void:
	await _fresh()
	var inside: TrainingDummy = _spawn(IN_FRONT)
	var outside: TrainingDummy = _spawn(FAR_AWAY)
	await _frames(2)
	await _swing()
	_record(_damage_taken(inside) == 20.0 and _damage_taken(outside) == 0.0,
		"H1/H2) a dummy inside the hitbox takes 20, one outside takes nothing (%.0f / %.0f)" % [
			_damage_taken(inside), _damage_taken(outside)])
	inside.queue_free()
	outside.queue_free()

	# Two different targets, one swing: both hit, each once.
	await _fresh()
	var left: TrainingDummy = _spawn(Vector3(-0.4, 0.1, -1.5))
	var right: TrainingDummy = _spawn(Vector3(0.4, 0.1, -1.5))
	var landed: Array[Node] = []
	var on_landed: Callable = func(target: Node, _hit: DamageInfo) -> void: landed.append(target)
	_player.attack_hitbox.hit_landed.connect(on_landed)
	await _frames(2)
	await _swing()
	_player.attack_hitbox.hit_landed.disconnect(on_landed)
	_record(landed.size() == 2 and landed.has(left) and landed.has(right)
			and _damage_taken(left) == 20.0 and _damage_taken(right) == 20.0,
		"H3) one swing reaches two dummies, each once (%d hits)" % landed.size())
	left.queue_free()
	right.queue_free()

	# The same target, in and out and back into a long active window: one hit.
	_combat.data = _copy_of_shipped()
	_combat.data.light_combo[0].active = 0.8
	await _fresh()
	var dummy: TrainingDummy = _spawn(IN_FRONT)
	var changes: Array[float] = []
	var health: HealthComponent = dummy.get_node("HealthComponent")
	var on_changed: Callable = func(current: float, _maximum: float) -> void: changes.append(current)
	health.health_changed.connect(on_changed)
	await _frames(2)
	_fire()
	await _frames_until(PlayerCombat.State.ACTIVE)
	await _frames(6)
	var hit_once: bool = changes.size() == 1
	dummy.global_position = FAR_AWAY
	await _frames(6)
	dummy.global_position = IN_FRONT
	await _frames(6)
	var still_active: bool = _combat.get_state() == PlayerCombat.State.ACTIVE
	await _frames_until(PlayerCombat.State.IDLE)
	_record(hit_once and still_active and changes.size() == 1,
		"H4) a target that leaves and re-enters the open hitbox is not hit twice by one swing (%d)" % changes.size())

	# A new swing forgets whom the last one hit.
	_combat.data = _shipped
	_combat.reset()
	await _swing()
	_record(changes.size() == 2, "H5) and the next swing hits it again (%d hits in two swings)" % changes.size())
	health.health_changed.disconnect(on_changed)
	dummy.queue_free()


# --- damage: the source, the attack, the number ------------------------------------------

func _damage_tests() -> void:
	await _fresh()
	var dummy: TrainingDummy = _spawn(IN_FRONT)
	var health: HealthComponent = dummy.get_node("HealthComponent")
	var hits: Array[DamageInfo] = []
	var on_landed: Callable = func(_target: Node, hit: DamageInfo) -> void: hits.append(hit)
	_player.attack_hitbox.hit_landed.connect(on_landed)
	await _frames(2)
	_fire()
	await _frames_until(PlayerCombat.State.RECOVERY)
	await _frames(2)
	var first: DamageInfo = hits[0] if not hits.is_empty() else null
	_record(first != null and first.amount == 20.0 and first.source == _player
			and first.attack_id == &"light_attack_1",
		"D1) the hit carries its source (the player), its attack (light_attack_1) and its amount (20)")
	_record(first != null and is_same(health.last_damage, first) and health.last_damage_source == _player,
		"D2) the dummy's health recorded that very hit, and whom it came from")
	_fire()
	await _frames_until(PlayerCombat.State.IDLE)
	_player.attack_hitbox.hit_landed.disconnect(on_landed)
	var second: DamageInfo = hits[1] if hits.size() > 1 else null
	_record(second != null and second.attack_id == &"light_attack_2" and second.amount == 25.0,
		"D3) the next attack of the chain names itself and hits for 25")
	dummy.queue_free()

	var amounts: Array[float] = []
	for attack in _shipped.light_combo:
		amounts.append(_combat.calculate_damage(attack))
	_record(amounts == [20.0, 25.0, 35.0],
		"D4) calculate_damage: base 20 x 1.0 / 1.25 / 1.75 = %s, the values of M10" % [amounts])

	# The receiving side cannot tell attackers apart: any DamageInfo lands the same.
	var other: TrainingDummy = _spawn(FAR_AWAY)
	var other_health: HealthComponent = other.get_node("HealthComponent")
	await _frames(1)
	var hurtbox: Hurtbox = other.get_node("Hurtbox")
	hurtbox.receive_hit(DamageInfo.new(7.0, self, &"test"))
	_record(other_health.current_health == other_health.max_health - 7.0
			and other_health.last_damage_source == self and other_health.last_damage.attack_id == &"test",
		"D5) a hit from anything else takes the same road: -7, source and attack recorded")
	other.queue_free()


# --- a target dying inside the swing that kills it ---------------------------------------

func _enemy_death_tests() -> void:
	await _fresh()
	var dummy: TrainingDummy = _spawn(IN_FRONT)
	var health: HealthComponent = dummy.get_node("HealthComponent")
	await _frames(2)
	health.current_health = 10.0
	var deaths: Array[int] = []
	var changes: Array[float] = []
	var landed: Array[Node] = []
	var on_died: Callable = func() -> void: deaths.append(1)
	var on_changed: Callable = func(current: float, _maximum: float) -> void: changes.append(current)
	var on_landed: Callable = func(target: Node, _hit: DamageInfo) -> void: landed.append(target)
	health.died.connect(on_died)
	health.health_changed.connect(on_changed)
	_player.attack_hitbox.hit_landed.connect(on_landed)
	_fire()
	await _frames_until(PlayerCombat.State.ACTIVE)
	var died_in_window: bool = false
	while _combat.get_state() == PlayerCombat.State.ACTIVE:
		await get_tree().physics_frame
		if health.is_dead and _combat.get_state() == PlayerCombat.State.ACTIVE:
			died_in_window = true
	await _frames_until(PlayerCombat.State.IDLE)
	_record(died_in_window and deaths.size() == 1 and changes == [0.0] and landed.size() == 1,
		"X1) a dummy killed inside the active window dies once, from one hit (%d deaths, %d hits)" % [
			deaths.size(), landed.size()])

	_combat.reset()
	await _swing()
	_record(deaths.size() == 1 and changes.size() == 1 and landed.size() == 1,
		"X2) and the next swing through its body finds nothing to hit")
	health.died.disconnect(on_died)
	health.health_changed.disconnect(on_changed)
	_player.attack_hitbox.hit_landed.disconnect(on_landed)
	dummy.queue_free()


# --- the player dying mid-attack ----------------------------------------------------------

func _player_death_tests() -> void:
	await _fresh()
	_fire()
	await _frames_until(PlayerCombat.State.ACTIVE)
	var was_open: bool = _player.attack_hitbox.is_active()
	_player.hurtbox.receive_hit(DamageInfo.new(10000.0, self))
	_record(was_open and _combat.get_state() == PlayerCombat.State.DEAD
			and _combat.get_current_attack() == null and not _player.attack_hitbox.is_active(),
		"P1) killed mid-swing: combat is DEAD, the attack is gone, the hitbox shut")
	var attacked: bool = _combat.request_light_attack()
	var dodged: bool = _combat.request_dodge()
	await get_tree().physics_frame
	_record(not attacked and not dodged and not _combat.has_buffered_attack()
			and not _player.attack_hitbox.monitoring and _started.size() == 1,
		"P2) a dead player can neither attack, buffer nor dodge")
	_player.health_component.is_dead = false
	_player.health_component.current_health = _player.health_component.max_health
	_fire()
	_record(_attack_id() == &"light_attack_1", "P3) brought back, it attacks again, from the first attack")
	await _frames_until(PlayerCombat.State.IDLE)


# --- pause ----------------------------------------------------------------------------------

## Paused for longer than the buffer lives: if either the attack or the buffer
## kept counting through the pause, light_attack_2 would never run. The press is
## made in the active phase, before the window, so it sits in the buffer.
func _pause_tests() -> void:
	await _fresh()
	_fire()
	await _frames_until(PlayerCombat.State.ACTIVE)
	await _frames(2)
	_fire()
	var state: PlayerCombat.State = _combat.get_state()
	var elapsed: float = _combat._state_elapsed
	get_tree().paused = true
	await _wait(_shipped.input_buffer_time + 0.3)
	var frozen: bool = _combat.get_state() == state and is_equal_approx(_combat._state_elapsed, elapsed)
	var buffer_kept: bool = _combat.has_buffered_attack()
	get_tree().paused = false
	await _frames_until(PlayerCombat.State.IDLE)
	_record(frozen and buffer_kept,
		"Z1) a paused tree freezes the attack and its buffer (state %s, %.3fs in)" % [
			PlayerCombat.State.keys()[state], elapsed])
	_record(_started == [&"light_attack_1", &"light_attack_2"],
		"Z2) and once unpaused it carries on: the buffered light_attack_2 ran (%s)" % [_started])


# --- frame-rate independence ---------------------------------------------------------------

func _frame_rate_tests() -> void:
	for hz in [30.0, 144.0]:
		var dt: float = 1.0 / hz
		var bare: PlayerCombat = PlayerCombat.new()
		bare.data = _shipped
		add_child(bare)
		bare.set_physics_process(false)
		var attack: AttackData = _shipped.light_combo[0]

		bare.request_light_attack()
		var windup: float = _step_until(bare, PlayerCombat.State.ACTIVE, dt)
		var active: float = _step_until(bare, PlayerCombat.State.RECOVERY, dt)
		var recovery: float = _step_until(bare, PlayerCombat.State.IDLE, dt)
		_record(_within(windup, attack.windup, dt) and _within(active, attack.active, dt)
				and _within(recovery, attack.recovery, dt),
			"F1) at %d Hz the phases last %.3f / %.3f / %.3f (configured %.2f / %.2f / %.2f)" % [
				hz, windup, active, recovery, attack.windup, attack.active, attack.recovery])

		bare.reset()
		bare.request_light_attack()
		bare.request_light_attack()
		var held: float = 0.0
		while bare.has_buffered_attack() and held < 2.0:
			bare._physics_process(dt)
			held += dt
		_record(_within(held, _shipped.input_buffer_time, dt),
			"F2) at %d Hz a buffered press lives %.3fs (configured %.2f)" % [
				hz, held, _shipped.input_buffer_time])

		bare.reset()
		bare.request_dodge()
		var t: float = 0.0
		var iframes_on: float = -1.0
		var iframes_off: float = -1.0
		while bare.is_dodging() and t < 2.0:
			bare._physics_process(dt)
			t += dt
			if bare.has_iframes() and iframes_on < 0.0:
				iframes_on = t
			if not bare.has_iframes() and iframes_on >= 0.0 and iframes_off < 0.0:
				iframes_off = t
		_record(_within(iframes_on, _shipped.invulnerability_start, dt)
				and _within(iframes_off, _shipped.invulnerability_end, dt)
				and _within(t, _shipped.dodge_duration, dt),
			"F3) at %d Hz the dodge: i-frames %.3f-%.3f, over at %.3f" % [hz, iframes_on, iframes_off, t])

		_record(bare.calculate_damage(attack) == _shipped.base_damage * attack.damage_multiplier,
			"F4) with no progression to scale it, a swing is base x multiplier (%.0f)" % bare.calculate_damage(attack))
		bare.queue_free()


# --- helpers ---------------------------------------------------------------------------------

func _fire() -> void:
	_player.camera_rig.attack_light_pressed.emit()


## One whole attack from a fresh chain, waited out.
func _swing() -> void:
	_fire()
	await _frames_until(PlayerCombat.State.IDLE)
	await _frames(2)


## The first `count` attacks of the chain, each buffered in the previous one's recovery.
func _run_chain(count: int) -> void:
	_fire()
	for i in count - 1:
		await _frames_until(PlayerCombat.State.RECOVERY)
		_fire()
		await _frames_until(PlayerCombat.State.WINDUP)
	await _frames_until(PlayerCombat.State.RECOVERY)


func _fresh() -> void:
	if _player._visual_tween != null and _player._visual_tween.is_running():
		_player._visual_tween.kill()
	_combat.reset()
	_player.global_position = Vector3(0, 0.1, 0)
	_player.velocity = Vector3.ZERO
	_player.visual_root.rotation = Vector3.ZERO
	_player.visual_model.rotation = Vector3.ZERO
	_player.camera_rig.rotation.y = 0.0
	_player.hurtbox.set_invulnerable(false)
	_player.health_component.is_dead = false
	_player.health_component.current_health = _player.health_component.max_health
	await _frames(3)
	_started.clear()


func _copy_of_shipped() -> PlayerCombatData:
	var copy: PlayerCombatData = _shipped.duplicate() as PlayerCombatData
	var attacks: Array[AttackData] = []
	for attack in _shipped.light_combo:
		attacks.append(attack.duplicate() as AttackData)
	copy.light_combo = attacks
	return copy


func _shipped_untouched() -> bool:
	var first: AttackData = _shipped.light_combo[0]
	return _shipped.base_damage == 20.0 and _shipped.input_buffer_time == 0.15 \
		and first.active == 0.12 and first.combo_window_start == 0.0 \
		and first.movement_multiplier == 1.0 and _combat.data == _shipped


func _spawn(pos: Vector3) -> TrainingDummy:
	var dummy: TrainingDummy = DUMMY_SCENE.instantiate() as TrainingDummy
	add_child(dummy)
	dummy.global_position = pos
	return dummy


func _damage_taken(dummy: TrainingDummy) -> float:
	var health: HealthComponent = dummy.get_node("HealthComponent")
	return health.max_health - health.current_health


func _frames_until(state: PlayerCombat.State, budget: int = 180) -> int:
	var n: int = 0
	while _combat.get_state() != state:
		if n >= budget:
			return -1
		await get_tree().physics_frame
		n += 1
	return n


func _step_until(bare: PlayerCombat, state: PlayerCombat.State, dt: float) -> float:
	var t: float = 0.0
	while bare.get_state() != state and t < 3.0:
		bare._physics_process(dt)
		t += dt
	return t


## `frames` physics frames is `seconds`, give or take FRAME_SLACK.
func _near(frames: int, seconds: float) -> bool:
	var dt: float = 1.0 / Engine.physics_ticks_per_second
	return frames >= 0 and absf(frames * dt - seconds) <= FRAME_SLACK * dt + 0.0001


## Stepped at `dt`, a boundary is crossed on the first step at or past it — or,
## where the boundary is an exact multiple of `dt`, on the one after, which float
## rounding can decide either way.
func _within(measured: float, configured: float, dt: float) -> bool:
	return measured >= configured - 0.0001 and measured <= configured + dt * 1.01


func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _wait(t: float) -> void:
	await get_tree().create_timer(t).timeout


func _attack_id() -> StringName:
	var attack: AttackData = _combat.get_current_attack()
	return attack.id if attack != null else &""


func _state_name() -> String:
	return PlayerCombat.State.keys()[_combat.get_state()]


func _on_attack_started(attack: AttackData) -> void:
	_started.append(attack.id)


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
