extends Node3D

## M11.4 — the dodge and its i-frames, on a real player.
##
##   godot --headless --path . res://tests/combat/dodge_iframes_test.tscn
##
## Dodges go in the way a device sends them: an InputEventAction for "dodge"
## through the player's own _unhandled_input. Hits go in the way an attacker
## sends them: a DamageInfo to the hurtbox, or a real enemy-layer Hitbox opened
## on the player — nothing here tells an attacker the player is dodging. A
## watcher checks every physics frame that the combat is never in an impossible
## state, and that the hurtbox refuses hits for the dodge exactly while the dodge
## is INVULNERABLE.

const DT: float = 1.0 / 60.0
const FRAME_SLACK: int = 2
## The enemy hitbox layer, masking the player's hurtbox (64) and the shadow's (256).
const ENEMY_HITBOX_LAYER: int = 32
const ENEMY_HITBOX_MASK: int = 320

@onready var _player: Player = $Player

var _combat: PlayerCombat = null
var _data: PlayerCombatData = null
var _health: HealthComponent = null
var _violations: Array[String] = []
var _watching: bool = false
var _pass: int = 0
var _fail: int = 0


func _ready() -> void:
	_reset_session()
	_combat = _player.combat
	_data = _combat.data
	_health = _player.health_component
	_run()


func _physics_process(_delta: float) -> void:
	if _watching:
		_check_invariants()


func _run() -> void:
	await _wait(0.2)
	_watching = true
	_binding_tests()
	await _lifecycle_tests()
	await _direction_tests()
	await _movement_tests()
	await _collision_tests()
	await _invulnerability_tests()
	await _spam_tests()
	await _attack_tests()
	_watching = false
	_frame_rate_tests()
	_record(_violations.is_empty(),
		"I1) no impossible state in any frame of the suite (%d: %s)" % [
			_violations.size(), _violations.slice(0, 3)])
	print("[SUMMARY] passed=%d failed=%d" % [_pass, _fail])
	get_tree().quit()


# --- the input ------------------------------------------------------------------------------------

func _binding_tests() -> void:
	var on_space: bool = false
	for event in InputMap.action_get_events(&"dodge"):
		var key: InputEventKey = event as InputEventKey
		if key != null and key.physical_keycode == KEY_SPACE:
			on_space = true
	_record(on_space and InputMap.has_action(&"attack_light") and InputMap.has_action(&"attack_heavy"),
		"IN1) dodge is its own action (Space), beside attack_light and attack_heavy")


# --- lifecycle --------------------------------------------------------------------------------------

func _lifecycle_tests() -> void:
	await _fresh()
	_record(_combat.can_dodge() and _combat.get_dodge_phase() == PlayerCombat.DodgePhase.NONE,
		"L1) a free player can dodge; no dodge phase")
	_dodge()
	_record(_combat.get_state() == PlayerCombat.State.DODGING
			and _combat.get_dodge_phase() == PlayerCombat.DodgePhase.STARTUP
			and not _combat.can_dodge() and not _player.hurtbox.is_invulnerable,
		"L2) the dodge input starts DODGING in STARTUP — moving, not yet invulnerable")
	var to_iframes: int = await _frames_until_phase(PlayerCombat.DodgePhase.INVULNERABLE)
	var on: bool = _player.hurtbox.is_invulnerable
	var to_recovery: int = await _frames_until_phase(PlayerCombat.DodgePhase.RECOVERY)
	var off: bool = not _player.hurtbox.is_invulnerable
	var to_free: int = await _frames_until_phase(PlayerCombat.DodgePhase.NONE)
	_record(_near(to_iframes, _data.invulnerability_start) and on,
		"L3) invulnerable from %.2fs (%d frames)" % [_data.invulnerability_start, to_iframes])
	_record(_near(to_iframes + to_recovery, _data.invulnerability_end) and off,
		"L4) vulnerable again from %.2fs: RECOVERY (%d frames in)" % [
			_data.invulnerability_end, to_iframes + to_recovery])
	_record(_near(to_iframes + to_recovery + to_free, _data.dodge_duration)
			and _combat.get_state() == PlayerCombat.State.IDLE,
		"L5) free at %.2fs: IDLE (%d frames in)" % [_data.dodge_duration, to_iframes + to_recovery + to_free])
	var refused: bool = not _combat.can_dodge() and not _dodge()
	var cooldown: int = 0
	while not _combat.can_dodge() and cooldown < 60:
		await get_tree().physics_frame
		cooldown += 1
	_record(refused and _near(cooldown, _data.dodge_cooldown),
		"L6) a second dodge waits out the %.2fs cooldown (%d frames), then may start" % [
			_data.dodge_cooldown, cooldown])


# --- direction ----------------------------------------------------------------------------------------

func _direction_tests() -> void:
	var cases: Array = [
		["move_forward", Vector3(0, 0, -1)], ["move_backward", Vector3(0, 0, 1)],
		["move_left", Vector3(-1, 0, 0)], ["move_right", Vector3(1, 0, 0)],
	]
	for case in cases:
		await _fresh()
		Input.action_press(case[0])
		await get_tree().physics_frame
		var start: Vector3 = _player.global_position
		_dodge()
		await _frames_until_phase(PlayerCombat.DodgePhase.NONE)
		Input.action_release(case[0])
		var moved: Vector3 = _flat(_player.global_position - start)
		var expected: Vector3 = case[1]
		_record(_player._dodge_direction.distance_to(expected) < 0.01
				and moved.normalized().distance_to(expected) < 0.05,
			"D-%s) dodges %s and travels that way (%s)" % [case[0], expected, moved.snapped(Vector3.ONE * 0.01)])

	# No input: straight back from where the player faces.
	await _fresh()
	_player.visual_root.rotation.y = deg_to_rad(90.0)
	await get_tree().physics_frame
	_dodge()
	var back: Vector3 = _player._dodge_direction
	await _frames_until_phase(PlayerCombat.DodgePhase.NONE)
	_record(back.distance_to(Vector3(1, 0, 0)) < 0.01,
		"D-none) no input: a backstep, away from the facing (facing -X, dodged %s)" % back.snapped(Vector3.ONE * 0.01))

	# Camera-relative, like walking: forward with the camera turned 90°.
	await _fresh()
	_player.camera_rig.rotation.y = deg_to_rad(90.0)
	Input.action_press("move_forward")
	await get_tree().physics_frame
	_dodge()
	var along_camera: Vector3 = _player._dodge_direction
	await _frames_until_phase(PlayerCombat.DodgePhase.NONE)
	Input.action_release("move_forward")
	_record(along_camera.distance_to(Vector3(-1, 0, 0)) < 0.01,
		"D-camera) with the camera turned 90°, forward dodges along the camera's forward (%s)" % along_camera.snapped(Vector3.ONE * 0.01))


# --- movement -----------------------------------------------------------------------------------------

func _movement_tests() -> void:
	await _fresh()
	Input.action_press("move_forward")
	await get_tree().physics_frame
	var start: Vector3 = _player.global_position
	_dodge()
	Input.action_release("move_forward")
	Input.action_press("move_right")
	var steady: bool = true
	var frames: int = 0
	while _combat.is_dodging():
		await get_tree().physics_frame
		frames += 1
		# From the first frame the player has moved in the dodge: the one it
		# started between still carries the walking velocity.
		var velocity: Vector3 = _flat(_player.velocity)
		if frames > 1 and _combat.is_dodging() \
				and velocity.distance_to(Vector3(0, 0, -_player.effective_dodge_speed)) > 0.01:
			steady = false
	Input.action_release("move_right")
	var distance: float = _flat(_player.global_position - start).length()
	var expected: float = _player.effective_dodge_speed * _data.dodge_duration
	_record(steady, "MV1) through the dodge its own velocity holds (%.1f m/s), whatever is pressed meanwhile" % _player.effective_dodge_speed)
	_record(absf(distance - expected) < _player.effective_dodge_speed * DT * FRAME_SLACK,
		"MV2) it covers %.2fm — speed x duration, %.2fm" % [distance, expected])

	# Off the ground: gravity keeps working through a dodge.
	await _fresh()
	_player.global_position = Vector3(0, 2.0, 0)
	await get_tree().physics_frame
	var height: float = _player.global_position.y
	_dodge()
	var rose: bool = false
	while _combat.is_dodging():
		await get_tree().physics_frame
		if _player.global_position.y > height + 0.001:
			rose = true
		height = _player.global_position.y
	await _frames(40)
	_record(not rose and _player.is_on_floor() and _player.global_position.y < 0.2,
		"MV3) dodging in the air never rises and lands on the floor (y %.2f)" % _player.global_position.y)


# --- collision ----------------------------------------------------------------------------------------

func _collision_tests() -> void:
	await _fresh()
	var wall: StaticBody3D = _spawn_wall(Vector3(0, 1.5, -2.5))
	await _frames(2)
	Input.action_press("move_forward")
	await get_tree().physics_frame
	_dodge()
	var blocked_while_invulnerable: bool = true
	while _combat.is_dodging():
		await get_tree().physics_frame
		if _player.global_position.z < -1.5 - 0.45:
			blocked_while_invulnerable = false
	Input.action_release("move_forward")
	_record(blocked_while_invulnerable and _player.global_position.z > -1.6,
		"C1) dodging into a wall stops at it, i-frames or not: no passing through (z %.2f, wall face -1.5)" % _player.global_position.z)
	wall.queue_free()


# --- invulnerability: the hurtbox decides -------------------------------------------------------------

func _invulnerability_tests() -> void:
	# The three moments, on the frame each boundary is crossed.
	await _fresh()
	var changes: Array[float] = []
	var on_changed: Callable = func(current: float, _maximum: float) -> void: changes.append(current)
	_health.health_changed.connect(on_changed)
	var full: float = _health.current_health
	_player.hurtbox.receive_hit(DamageInfo.new(10.0, self))
	var before_took: bool = _health.current_health == full - 10.0
	_dodge()
	var last_startup: float = -1.0
	var first_iframe: float = -1.0
	var last_iframe: float = -1.0
	var first_recovery: float = -1.0
	var shown: Array[float] = []
	while _combat.is_dodging():
		var phase: PlayerCombat.DodgePhase = _combat.get_dodge_phase()
		var hp: float = _health.current_health
		var elapsed: float = _combat._state_elapsed
		if phase == PlayerCombat.DodgePhase.STARTUP and elapsed + DT >= _data.invulnerability_start and last_startup < 0.0:
			_player.hurtbox.receive_hit(DamageInfo.new(5.0, self))
			last_startup = hp - _health.current_health
		elif phase == PlayerCombat.DodgePhase.INVULNERABLE and first_iframe < 0.0:
			_player.hurtbox.receive_hit(DamageInfo.new(5.0, self))
			first_iframe = hp - _health.current_health
		elif phase == PlayerCombat.DodgePhase.INVULNERABLE and elapsed + DT >= _data.invulnerability_end and last_iframe < 0.0:
			_player.hurtbox.receive_hit(DamageInfo.new(5.0, self))
			last_iframe = hp - _health.current_health
		elif phase == PlayerCombat.DodgePhase.RECOVERY and first_recovery < 0.0:
			_player.hurtbox.receive_hit(DamageInfo.new(5.0, self))
			first_recovery = hp - _health.current_health
		shown.append(_health.current_health)
		await get_tree().physics_frame
	_player.hurtbox.receive_hit(DamageInfo.new(10.0, self))
	var after_took: bool = _health.current_health == full - 10.0 - 5.0 - 5.0 - 10.0
	_health.health_changed.disconnect(on_changed)
	_record(before_took, "F1) before the dodge a hit takes its 10")
	_record(last_startup == 5.0 and first_iframe == 0.0 and last_iframe == 0.0 and first_recovery == 5.0,
		"F2) boundaries: last STARTUP frame %.0f, first and last INVULNERABLE %.0f / %.0f, first RECOVERY %.0f" % [
			last_startup, first_iframe, last_iframe, first_recovery])
	_record(after_took and changes == [full - 10.0, full - 15.0, full - 20.0, full - 30.0],
		"F3) after it hits count again, and health changed only for the hits that counted %s" % [changes])

	# A real attack: an enemy-layer hitbox opened on the player mid-i-frames.
	await _fresh()
	var attacker: Hitbox = _spawn_attacker(12.0)
	var landed: Array[Node] = []
	var on_landed: Callable = func(target: Node, _hit: DamageInfo) -> void: landed.append(target)
	attacker.hit_landed.connect(on_landed)
	await _frames(2)
	_dodge()
	await _frames_until_phase(PlayerCombat.DodgePhase.INVULNERABLE)
	var hp_before: float = _health.current_health
	attacker.activate()
	await _frames(3)
	attacker.deactivate()
	var dodged: bool = landed.size() == 1 and _health.current_health == hp_before
	await _frames_until_phase(PlayerCombat.DodgePhase.NONE)
	await _frames(2)
	attacker.activate()
	await _frames(3)
	attacker.deactivate()
	_record(dodged, "F4) an enemy hitbox that reaches the player in its i-frames connects, and takes nothing")
	_record(landed.size() == 2 and _health.current_health == hp_before - 12.0,
		"F5) the same hitbox out of the dodge takes its 12")
	attacker.queue_free()

	# The dodge's invulnerability and anyone else's do not end each other.
	await _fresh()
	_player.hurtbox.set_invulnerable(true)
	_dodge()
	await _frames_until_phase(PlayerCombat.DodgePhase.NONE)
	var kept: bool = _player.hurtbox.is_invulnerable
	_player.hurtbox.set_invulnerable(false)
	await _wait(_data.dodge_cooldown + 0.05)
	_dodge()
	await _frames_until_phase(PlayerCombat.DodgePhase.INVULNERABLE)
	_player.hurtbox.set_invulnerable(false)
	var own_kept: bool = _player.hurtbox.is_invulnerable
	await _frames_until_phase(PlayerCombat.DodgePhase.NONE)
	_record(kept and own_kept and not _player.hurtbox.is_invulnerable,
		"F6) a dodge ends only its own i-frames: another system's invulnerability outlives it, and cannot end it")

	# Never left invulnerable.
	await _fresh()
	_dodge()
	await _frames_until_phase(PlayerCombat.DodgePhase.INVULNERABLE)
	_combat.reset()
	var after_reset: bool = not _player.hurtbox.is_invulnerable and not _combat.is_dodging()
	await _fresh()
	_dodge()
	await _frames_until_phase(PlayerCombat.DodgePhase.INVULNERABLE)
	_health.take_damage(DamageInfo.new(10000.0, self))
	var dead_clean: bool = _combat.get_state() == PlayerCombat.State.DEAD and not _player.hurtbox.is_invulnerable \
		and _combat.get_dodge_phase() == PlayerCombat.DodgePhase.NONE and not _combat.can_dodge()
	var start: Vector3 = _player.global_position
	await _frames(20)
	var still: bool = _flat(_player.global_position - start).length() < _player.effective_dodge_speed * DT * 12.0
	_record(after_reset, "F7) reset() in the i-frames ends the dodge and the invulnerability")
	_record(dead_clean and still,
		"F8) dying in the i-frames: DEAD, not invulnerable, no dodge, no dodge movement carrying on")


# --- spam -------------------------------------------------------------------------------------------

func _spam_tests() -> void:
	await _fresh()
	var started: int = 0
	for i in 20:
		if _dodge():
			started += 1
	await _frames_until_phase(PlayerCombat.DodgePhase.NONE)
	await _frames(20)
	_record(started == 1 and not _combat.is_dodging(), "SP1) twenty dodge presses in one frame: one dodge")

	await _fresh()
	var starts: Array[int] = []
	var invulnerable_frames: int = 0
	var frames: int = 0
	var was_dodging: bool = false
	while frames < 180:
		_dodge()
		if _combat.is_dodging() and not was_dodging:
			starts.append(frames)
		was_dodging = _combat.is_dodging()
		await get_tree().physics_frame
		frames += 1
		if _player.hurtbox.is_invulnerable:
			invulnerable_frames += 1
	var after_release: int = 0
	var waited: int = 0
	while waited < 60:
		if _combat.is_dodging() and not was_dodging:
			after_release += 1
		was_dodging = _combat.is_dodging()
		await get_tree().physics_frame
		waited += 1
	var gap: int = int(floor((_data.dodge_duration + _data.dodge_cooldown) * Engine.physics_ticks_per_second))
	var spaced: bool = starts.size() >= 3
	for i in range(1, starts.size()):
		if starts[i] - starts[i - 1] < gap:
			spaced = false
	_record(spaced, "SP2) dodge held down for 3s: %d dodges, each a full dodge and cooldown apart" % starts.size())
	_record(float(invulnerable_frames) / frames < 0.5 and after_release == 0 and not _player.hurtbox.is_invulnerable,
		"SP3) invulnerable %d of %d frames — never continuously — and nothing queued after letting go" % [
			invulnerable_frames, frames])


# --- attacks and the dodge ----------------------------------------------------------------------------

func _attack_tests() -> void:
	var light: Array[AttackData] = _data.light_combo
	var heavy: AttackData = _data.heavy_combo[0]

	# Light 1: committed through windup and active, cancellable in all of recovery.
	await _fresh()
	_light()
	var in_windup: bool = not _dodge()
	await _frames_until_state(PlayerCombat.State.ACTIVE)
	var in_active: bool = not _dodge()
	await _frames_until_state(PlayerCombat.State.RECOVERY)
	var queued_light: bool = _light_queues()
	var cancelled: bool = _dodge() and not _player.attack_hitbox.is_active() and _combat.get_current_attack() == null \
		and _combat.get_queued_attack() == null and _combat.get_combo_index() == PlayerCombat.NO_ATTACK
	_record(in_windup and in_active and queued_light and cancelled,
		"A1) Light 1: dodge refused in windup and active; in recovery (cancellable from 0%) it cancels the attack, the queued Light 2 and the chain")
	await _frames_until_phase(PlayerCombat.DodgePhase.NONE)

	# Light 2: cancellable only past 35% of its recovery.
	await _fresh()
	_combat._start_attack(light, 1)
	await _frames_until_state(PlayerCombat.State.RECOVERY)
	var early: bool = not _dodge()
	await _frames(int(ceil(light[1].recovery * light[1].dodge_cancel_recovery_fraction / DT)) + 1)
	var late: bool = _dodge()
	_record(early and late, "A2) Light 2: dodge refused early in recovery, allowed past %.0f%% of it" % (
		light[1].dodge_cancel_recovery_fraction * 100.0))
	await _frames_until_phase(PlayerCombat.DodgePhase.NONE)

	# Heavy: committed through windup, active and most of recovery.
	await _fresh()
	_heavy()
	var heavy_windup: bool = not _dodge()
	await _frames_until_state(PlayerCombat.State.ACTIVE)
	var heavy_active: bool = not _dodge()
	await _frames_until_state(PlayerCombat.State.RECOVERY)
	var heavy_early: bool = not _dodge()
	await _frames(int(ceil(heavy.recovery * heavy.dodge_cancel_recovery_fraction / DT)) + 1)
	var heavy_late: bool = _dodge() and not _player.attack_hitbox.is_active()
	_record(heavy_windup and heavy_active and heavy_early and heavy_late,
		"A3) Heavy: dodge refused in windup, active and the first %.0f%% of recovery; allowed after, never skipping all of it" % (
			heavy.dodge_cancel_recovery_fraction * 100.0))
	await _frames_until_phase(PlayerCombat.DodgePhase.NONE)

	# A refused dodge is not held for later.
	await _fresh()
	_light()
	_dodge()
	await _frames_until_state(PlayerCombat.State.IDLE)
	await _frames(3)
	_record(not _combat.is_dodging(), "A4) a dodge refused during an attack is not buffered: nothing follows the attack")

	# Attacks during a dodge are ignored; after it, both start from their first attack.
	await _fresh()
	var started: Array[StringName] = []
	var on_started: Callable = func(attack: AttackData) -> void: started.append(attack.id)
	_combat.attack_started.connect(on_started)
	_dodge()
	_light()
	_heavy()
	await _frames_until_phase(PlayerCombat.DodgePhase.INVULNERABLE)
	_light()
	_heavy()
	await _frames_until_phase(PlayerCombat.DodgePhase.RECOVERY)
	_light()
	_heavy()
	await _frames_until_phase(PlayerCombat.DodgePhase.NONE)
	var none_during: bool = started.is_empty()
	_light()
	var light_after: bool = started == [&"light_attack_1"]
	await _frames_until_state(PlayerCombat.State.IDLE)
	await _wait(_data.dodge_cooldown + 0.05)
	_dodge()
	await _frames_until_phase(PlayerCombat.DodgePhase.NONE)
	_heavy()
	var heavy_after: bool = started == [&"light_attack_1", heavy.id]
	await _frames_until_state(PlayerCombat.State.IDLE)
	_record(none_during and light_after and heavy_after,
		"A5) light and heavy pressed through a dodge are ignored; after it, Light 1 and the heavy start at once")

	# The other way round: a finished light chain, then a dodge; a finished heavy, then a dodge.
	await _fresh()
	_light()
	for i in 2:
		await _frames_until_state(PlayerCombat.State.RECOVERY)
		await _frames(3)
		_light()
		await _frames_until_state(PlayerCombat.State.WINDUP)
	await _frames_until_state(PlayerCombat.State.IDLE)
	var after_chain: bool = _dodge()
	await _frames_until_phase(PlayerCombat.DodgePhase.NONE)
	await _wait(_data.dodge_cooldown + 0.05)
	_heavy()
	await _frames_until_state(PlayerCombat.State.IDLE)
	var after_heavy: bool = _dodge()
	await _frames_until_phase(PlayerCombat.DodgePhase.NONE)
	_combat.attack_started.disconnect(on_started)
	_record(after_chain and after_heavy and started.slice(2) == [&"light_attack_1", &"light_attack_2", &"light_attack_3", heavy.id]
			and _combat.get_state() == PlayerCombat.State.IDLE,
		"A6) Light 1 -> 2 -> 3, then a dodge; the heavy, then a dodge: every sequence ends free and clean")


# --- frame-rate independence --------------------------------------------------------------------------

func _frame_rate_tests() -> void:
	for hz in [30.0, 144.0]:
		var dt: float = 1.0 / hz
		var bare: PlayerCombat = PlayerCombat.new()
		bare.data = _data
		add_child(bare)
		bare.set_physics_process(false)
		bare.request_dodge()
		var t: float = 0.0
		var marks: Dictionary = {}
		while bare.is_dodging() and t < 2.0:
			bare._physics_process(dt)
			t += dt
			var phase: String = PlayerCombat.DodgePhase.keys()[bare.get_dodge_phase()]
			if not marks.has(phase):
				marks[phase] = t
		_record(_within(marks.get("INVULNERABLE", -1.0), _data.invulnerability_start, dt)
				and _within(marks.get("RECOVERY", -1.0), _data.invulnerability_end, dt)
				and _within(marks.get("NONE", -1.0), _data.dodge_duration, dt),
			"FR1) at %d Hz: i-frames at %.3f, recovery at %.3f, free at %.3f" % [
				hz, marks.get("INVULNERABLE", -1.0), marks.get("RECOVERY", -1.0), marks.get("NONE", -1.0)])
		bare.queue_free()


# --- invariants ---------------------------------------------------------------------------------------

func _check_invariants() -> void:
	var state: PlayerCombat.State = _combat.get_state()
	var phase: PlayerCombat.DodgePhase = _combat.get_dodge_phase()
	var name_of: String = PlayerCombat.State.keys()[state]
	if (state == PlayerCombat.State.DODGING) != (phase != PlayerCombat.DodgePhase.NONE):
		_violations.append("%s with dodge phase %s" % [name_of, PlayerCombat.DodgePhase.keys()[phase]])
	if state == PlayerCombat.State.DODGING and (_combat.get_current_attack() != null
			or _player.attack_hitbox.is_active() or _combat.get_combo_index() != PlayerCombat.NO_ATTACK
			or _combat.get_queued_attack() != null or _combat.has_buffered_attack()):
		_violations.append("DODGING with an attack, a chain or an open hitbox")
	if _combat._iframes_active != (phase == PlayerCombat.DodgePhase.INVULNERABLE):
		_violations.append("i-frames %s in dodge phase %s" % [_combat._iframes_active, PlayerCombat.DodgePhase.keys()[phase]])
	if _combat._iframes_active != _player.hurtbox._invulnerable_reasons.has(PlayerCombat.IFRAMES_REASON):
		_violations.append("the hurtbox and the dodge disagree on the i-frames")


# --- helpers ------------------------------------------------------------------------------------------

## The dodge button, through the player's own input handler. True if a dodge started.
func _dodge() -> bool:
	var was_dodging: bool = _combat.is_dodging()
	var event: InputEventAction = InputEventAction.new()
	event.action = &"dodge"
	event.pressed = true
	_player._unhandled_input(event)
	return _combat.is_dodging() and not was_dodging


func _light() -> void:
	_player.camera_rig.attack_light_pressed.emit()


func _heavy() -> void:
	_player.camera_rig.attack_heavy_pressed.emit()


func _light_queues() -> bool:
	_light()
	return _combat.get_queued_attack() != null


func _spawn_wall(at: Vector3) -> StaticBody3D:
	var wall: StaticBody3D = StaticBody3D.new()
	var shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(4, 3, 2)
	shape.shape = box
	wall.add_child(shape)
	add_child(wall)
	wall.global_position = at
	return wall


## An enemy's hitbox, as the enemies build theirs, standing on the player: it
## knows nothing of the player but the hurtbox it overlaps.
func _spawn_attacker(damage: float) -> Hitbox:
	var hitbox: Hitbox = Hitbox.new()
	hitbox.collision_layer = ENEMY_HITBOX_LAYER
	hitbox.collision_mask = ENEMY_HITBOX_MASK
	hitbox.damage = damage
	hitbox.source = self
	var shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(3, 3, 3)
	shape.shape = box
	hitbox.add_child(shape)
	_player.add_child(hitbox)
	hitbox.position = Vector3(0, 1, 0)
	return hitbox


func _fresh() -> void:
	if _player._visual_tween != null and _player._visual_tween.is_running():
		_player._visual_tween.kill()
	_combat.reset()
	for action in ["move_forward", "move_backward", "move_left", "move_right"]:
		Input.action_release(action)
	_player.global_position = Vector3(0, 0.1, 0)
	_player.velocity = Vector3.ZERO
	_player.visual_root.rotation = Vector3.ZERO
	_player.visual_model.rotation = Vector3.ZERO
	_player.camera_rig.rotation.y = 0.0
	_player.hurtbox.set_invulnerable(false)
	_health.is_dead = false
	_health.current_health = _health.max_health
	# Every test starts with full stamina, as a new player does; what stamina
	# allows and costs is stamina_test's (M11.5).
	_combat.restore_stamina(_combat.get_max_stamina())
	await _frames(4)


func _frames_until_phase(phase: PlayerCombat.DodgePhase, budget: int = 120) -> int:
	var n: int = 0
	while _combat.get_dodge_phase() != phase:
		if n >= budget:
			return -1
		await get_tree().physics_frame
		n += 1
	return n


func _frames_until_state(state: PlayerCombat.State, budget: int = 180) -> int:
	var n: int = 0
	while _combat.get_state() != state:
		if n >= budget:
			return -1
		await get_tree().physics_frame
		n += 1
	return n


func _near(frames: int, seconds: float) -> bool:
	return frames >= 0 and absf(frames * DT - seconds) <= FRAME_SLACK * DT + 0.0001


func _within(measured: float, configured: float, dt: float) -> bool:
	return measured >= configured - 0.0001 and measured <= configured + dt * 1.01


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
