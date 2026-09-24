extends Node3D

## M11.3 — the heavy attack, on a real player against training dummies.
##
##   godot --headless --path . res://tests/combat/heavy_attack_test.tscn
##
## The heavy attack is a chain of one on the same controller as the light combo:
## its own AttackData, the same hitbox, the same damage function. Presses go in
## the way a device sends them (the camera rig's signals). A watcher checks every
## physics frame that the combat is never in an impossible state, and the light
## combo's own suite (light_combo_test) still runs unchanged beside this one.

const DUMMY_SCENE: PackedScene = preload("res://scenes/enemies/training_dummy.tscn")
const IN_FRONT: Vector3 = Vector3(0, 0.1, -1.5)
const LEFT: Vector3 = Vector3(-0.4, 0.1, -1.5)
const RIGHT: Vector3 = Vector3(0.4, 0.1, -1.5)
const FRAME_SLACK: int = 2
const HEAVY: StringName = &"heavy_attack_1"

@onready var _player: Player = $Player

var _combat: PlayerCombat = null
var _shipped: PlayerCombatData = null
var _heavy: AttackData = null
var _light_1: AttackData = null
var _started: Array[StringName] = []
var _violations: Array[String] = []
var _watching: bool = false
var _pass: int = 0
var _fail: int = 0


func _ready() -> void:
	_reset_session()
	_combat = _player.combat
	_shipped = _combat.data
	_heavy = _shipped.heavy_combo[0]
	_light_1 = _shipped.light_combo[0]
	_combat.attack_started.connect(_on_attack_started)
	_run()


func _physics_process(_delta: float) -> void:
	if _watching:
		_check_invariants()


func _run() -> void:
	await _wait(0.2)
	_watching = true
	_binding_tests()
	await _lifecycle_tests()
	await _damage_tests()
	await _hit_tests()
	await _spam_tests()
	await _interaction_tests()
	await _movement_tests()
	await _death_tests()
	_watching = false
	_frame_rate_tests()
	_record(_violations.is_empty(),
		"I1) no impossible state in any frame of the suite (%d: %s)" % [
			_violations.size(), _violations.slice(0, 3)])
	_record(_heavy.damage_multiplier == 2.0 and _heavy.windup == 0.35 and _combat.data == _shipped,
		"I2) the shared heavy attack data holds exactly what it was loaded with")
	print("[SUMMARY] passed=%d failed=%d" % [_pass, _fail])
	get_tree().quit()


# --- the input ----------------------------------------------------------------------------------

func _binding_tests() -> void:
	var bound_to_right_button: bool = false
	for event in InputMap.action_get_events(&"attack_heavy"):
		var button: InputEventMouseButton = event as InputEventMouseButton
		if button != null and button.button_index == MOUSE_BUTTON_RIGHT:
			bound_to_right_button = true
	var light_unchanged: bool = false
	for event in InputMap.action_get_events(&"attack_light"):
		var button: InputEventMouseButton = event as InputEventMouseButton
		if button != null and button.button_index == MOUSE_BUTTON_LEFT:
			light_unchanged = true
	_record(bound_to_right_button and light_unchanged,
		"IN1) attack_heavy is its own action, on the right mouse button; attack_light stays on the left")
	_record(_shipped.heavy_combo.size() == 1 and _heavy.id == HEAVY and _heavy.animation == &"heavy_attack_01",
		"IN2) the heavy attack is a chain of one: %s, shown as %s" % [_heavy.id, _heavy.animation])


# --- windup, active, recovery ---------------------------------------------------------------------

func _lifecycle_tests() -> void:
	await _fresh()
	_heavy_press()
	_record(_attack_id() == HEAVY and _combat.get_state() == PlayerCombat.State.WINDUP
			and _combat.get_combo_index() == 0 and _combat.is_running_chain(_shipped.heavy_combo)
			and _started == [HEAVY],
		"L1) from IDLE, the heavy input starts the heavy attack at once")
	_record(not _player.attack_hitbox.is_active(), "L2) its hitbox stays shut through the windup")
	var to_active: int = await _frames_until(PlayerCombat.State.ACTIVE)
	var open: bool = _player.attack_hitbox.is_active()
	var to_recovery: int = await _frames_until(PlayerCombat.State.RECOVERY)
	var shut: bool = not _player.attack_hitbox.is_active()
	var to_idle: int = await _frames_until(PlayerCombat.State.IDLE)
	_record(_near(to_active, _heavy.windup) and open,
		"L3) windup %.2fs, then ACTIVE with the hitbox open (%d frames)" % [_heavy.windup, to_active])
	_record(_near(to_recovery, _heavy.active) and shut,
		"L4) active %.2fs, then RECOVERY with the hitbox shut (%d frames)" % [_heavy.active, to_recovery])
	_record(_near(to_idle, _heavy.recovery) and _combat.get_current_attack() == null
			and _combat.get_combo_index() == PlayerCombat.NO_ATTACK,
		"L5) recovery %.2fs, then IDLE with no attack and no chain (%d frames)" % [_heavy.recovery, to_idle])
	_record(_heavy.windup > _light_1.windup and _heavy.recovery > _light_1.recovery
			and _duration(_heavy) > _duration(_shipped.light_combo[2]),
		"L6) more commitment than any light attack: windup %.2f vs %.2f, recovery %.2f vs %.2f, %.2fs in all" % [
			_heavy.windup, _light_1.windup, _heavy.recovery, _light_1.recovery, _duration(_heavy)])


# --- damage -------------------------------------------------------------------------------------

func _damage_tests() -> void:
	var heavy_damage: float = _combat.calculate_damage(_heavy)
	var light_damages: Array[float] = []
	for attack in _shipped.light_combo:
		light_damages.append(_combat.calculate_damage(attack))
	_record(heavy_damage == _shipped.base_damage * _heavy.damage_multiplier and heavy_damage == 40.0
			and heavy_damage > light_damages.max(),
		"DM1) heavy = base %.0f x %.2f = %.0f, above every light attack %s" % [
			_shipped.base_damage, _heavy.damage_multiplier, heavy_damage, [light_damages]])

	await _fresh()
	var dummy: TrainingDummy = _spawn(IN_FRONT)
	var health: HealthComponent = dummy.get_node("HealthComponent")
	var hits: Array[DamageInfo] = []
	var on_landed: Callable = func(_target: Node, info: DamageInfo) -> void: hits.append(info)
	_player.attack_hitbox.hit_landed.connect(on_landed)
	await _frames(2)
	await _heavy_swing()
	_player.attack_hitbox.hit_landed.disconnect(on_landed)
	var landed: DamageInfo = hits[0] if hits.size() == 1 else null
	_record(landed != null and landed.amount == 40.0 and landed.source == _player and landed.attack_id == HEAVY
			and is_same(health.last_damage, landed) and health.current_health == 60.0,
		"DM2) a heavy on a dummy: one hit, from the player, by %s, for 40 (100 -> %.0f)" % [
			HEAVY, health.current_health])
	dummy.queue_free()


# --- hits ---------------------------------------------------------------------------------------

func _hit_tests() -> void:
	# Two targets in the hitbox: each hit once; the next heavy hits them again.
	await _fresh()
	var left: TrainingDummy = _spawn(LEFT)
	var right: TrainingDummy = _spawn(RIGHT)
	left.name = "Left"
	right.name = "Right"
	var hit_log: Array[String] = []
	var on_landed: Callable = func(target: Node, hit: DamageInfo) -> void:
		hit_log.append("%s>%s" % [hit.attack_id, target.name])
	_player.attack_hitbox.hit_landed.connect(on_landed)
	await _frames(2)
	await _heavy_swing()
	hit_log.sort()
	var first_swing: bool = hit_log == ["heavy_attack_1>Left", "heavy_attack_1>Right"]
	await _heavy_swing()
	_record(first_swing and hit_log.size() == 4 and _hp(left) == 20.0 and _hp(right) == 20.0,
		"H1) one heavy reaches both dummies once each; a second heavy hits both again (%d hits, %.0f / %.0f HP)" % [
			hit_log.size(), _hp(left), _hp(right)])
	left.queue_free()
	right.queue_free()

	# A killing blow: one death, one hit, nothing after.
	await _fresh()
	var dummy: TrainingDummy = _spawn(IN_FRONT)
	dummy.name = "Low"
	var health: HealthComponent = dummy.get_node("HealthComponent")
	var deaths: Array[int] = []
	var changes: Array[float] = []
	var on_died: Callable = func() -> void: deaths.append(1)
	var on_changed: Callable = func(current: float, _maximum: float) -> void: changes.append(current)
	health.died.connect(on_died)
	health.health_changed.connect(on_changed)
	hit_log.clear()
	await _frames(2)
	health.current_health = 30.0
	await _heavy_swing()
	await _heavy_swing()
	health.died.disconnect(on_died)
	health.health_changed.disconnect(on_changed)
	_player.attack_hitbox.hit_landed.disconnect(on_landed)
	_record(deaths.size() == 1 and changes == [0.0] and hit_log == ["heavy_attack_1>Low"],
		"H2) a heavy on a 30 HP dummy: one death, one hit, one health update; the next heavy finds nothing")
	dummy.queue_free()


# --- spam -----------------------------------------------------------------------------------------

func _spam_tests() -> void:
	await _fresh()
	for i in 15:
		_heavy_press()
	var buffered: bool = _combat.has_buffered_attack() or _combat.get_queued_attack() != null
	await _frames_until(PlayerCombat.State.IDLE)
	await _frames(3)
	_record(_started == [HEAVY] and not buffered,
		"SP1) fifteen heavy presses in one frame: one heavy, nothing held or queued")

	# Mashing heavy every frame for three seconds.
	await _fresh()
	# A lambda captures locals by value, so the frame count it reads is a one-slot array.
	var frames: Array[int] = [0]
	var starts: Array[int] = []
	var on_started: Callable = func(_attack: AttackData) -> void: starts.append(frames[0])
	_combat.attack_started.connect(on_started)
	while frames[0] < 180:
		_heavy_press()
		await get_tree().physics_frame
		frames[0] += 1
	var at_release: int = _started.size()
	await _frames_until(PlayerCombat.State.IDLE, 120)
	await _frames(10)
	_combat.attack_started.disconnect(on_started)
	var spaced: bool = true
	var minimum: int = int(floor(_duration(_heavy) * Engine.physics_ticks_per_second))
	for i in range(1, starts.size()):
		if starts[i] - starts[i - 1] < minimum:
			spaced = false
	var all_heavy: bool = not _started.is_empty()
	for id in _started:
		if id != HEAVY:
			all_heavy = false
	_record(all_heavy and spaced and _started.size() >= 2 and _started.size() == at_release,
		"SP2) mashing heavy for 3s: %d heavies, each only after the last was over, none after letting go" % _started.size())


# --- light and heavy together ---------------------------------------------------------------------

func _interaction_tests() -> void:
	# Heavy pressed through a light chain: ignored in every phase; the chain goes on.
	await _fresh()
	_light_press()
	_heavy_press()
	var ignored_in_windup: bool = _attack_id() == &"light_attack_1" and not _combat.has_buffered_attack()
	await _frames_until(PlayerCombat.State.ACTIVE)
	_heavy_press()
	await _frames_until(PlayerCombat.State.RECOVERY)
	_light_press()
	_heavy_press()
	var light_kept: bool = _combat.get_queued_attack() != null \
		and _combat.get_queued_attack().id == &"light_attack_2"
	await _frames_until(PlayerCombat.State.WINDUP)
	await _frames_until(PlayerCombat.State.RECOVERY)
	_heavy_press()
	var nothing_queued: bool = _combat.get_queued_attack() == null
	await _frames_until(PlayerCombat.State.IDLE)
	await _frames(3)
	var chain_only: bool = _started == [&"light_attack_1", &"light_attack_2"]
	_heavy_press()
	_record(ignored_in_windup and light_kept and nothing_queued and chain_only,
		"X1) heavy during a light chain is ignored in windup, active and window: it neither replaces nor follows Light 2 (%s)" % [
			_started.slice(0, 2)])
	_record(_attack_id() == HEAVY and _combat.get_combo_index() == 0,
		"X2) once the chain is over, the next heavy press starts the heavy attack")
	await _frames_until(PlayerCombat.State.IDLE)

	# Light pressed through a heavy: ignored; the next light press is Light 1.
	await _fresh()
	_heavy_press()
	_light_press()
	await _frames_until(PlayerCombat.State.ACTIVE)
	_light_press()
	await _frames_until(PlayerCombat.State.RECOVERY)
	for i in 5:
		_light_press()
		await get_tree().physics_frame
	var nothing_held: bool = _combat.get_queued_attack() == null and not _combat.has_buffered_attack()
	await _frames_until(PlayerCombat.State.IDLE)
	await _frames(3)
	var heavy_alone: bool = _started == [HEAVY] and _combat.get_combo_index() == PlayerCombat.NO_ATTACK
	_light_press()
	_record(nothing_held and heavy_alone and _attack_id() == &"light_attack_1",
		"X3) light during a heavy is ignored — nothing held — and the next light press is Light 1")
	await _frames_until(PlayerCombat.State.IDLE)

	# Both in the same frame: the first one pressed wins.
	await _fresh()
	_light_press()
	_heavy_press()
	var light_first: bool = _started == [&"light_attack_1"]
	await _frames_until(PlayerCombat.State.IDLE)
	await _fresh()
	_heavy_press()
	_light_press()
	var heavy_first: bool = _started == [HEAVY]
	await _frames_until(PlayerCombat.State.IDLE)
	await _frames(3)
	_record(light_first and heavy_first and _started == [HEAVY],
		"X4) light and heavy in the same frame: whichever arrived first runs, the other is dropped")

	# Both buttons every frame for three seconds, in an order that cycles every
	# three frames: whichever frame the player comes free on, the first press of it
	# wins, so both chains get their turn.
	await _fresh()
	var frames: int = 0
	while frames < 180:
		if frames % 3 == 0:
			_heavy_press()
			_light_press()
		else:
			_light_press()
			_heavy_press()
		await get_tree().physics_frame
		frames += 1
	var at_release: int = _started.size()
	await _frames_until(PlayerCombat.State.IDLE, 120)
	await _frames(10)
	var valid: bool = _started.has(HEAVY) and _started.has(&"light_attack_1") \
		and _started.size() - at_release <= 1
	var previous: StringName = &""
	for id in _started:
		if (id == &"light_attack_2" and previous != &"light_attack_1") \
				or (id == &"light_attack_3" and previous != &"light_attack_2"):
			valid = false
		previous = id
	_record(valid and _combat.get_state() == PlayerCombat.State.IDLE
			and _combat.get_combo_index() == PlayerCombat.NO_ATTACK and not _combat.has_buffered_attack(),
		"X5) light and heavy mashed together for 3s: %s — every chain in order, never overlapping, then IDLE and clean" % [_started])


# --- movement and facing -----------------------------------------------------------------------------

func _movement_tests() -> void:
	await _fresh()
	Input.action_press("move_forward")
	await _frames(30)
	var walking: float = _flat_speed()
	_heavy_press()
	await _frames_until(PlayerCombat.State.ACTIVE)
	var during: float = _flat_speed()
	var aimed: float = _player.visual_root.rotation.y
	Input.action_press("move_right")
	var held: bool = true
	while _combat.is_attacking():
		await get_tree().physics_frame
		if not is_equal_approx(_player.visual_root.rotation.y, aimed):
			held = false
	Input.action_release("move_right")
	Input.action_release("move_forward")
	_record(absf(during - walking * _heavy.movement_multiplier) < 0.05,
		"MV1) a heavy slows the player to x%.1f: %.2f m/s walking, %.2f m/s swinging" % [
			_heavy.movement_multiplier, walking, during])
	_record(held, "MV2) and keeps its aim while it runs, like every attack")


# --- death ----------------------------------------------------------------------------------------

func _death_tests() -> void:
	await _fresh()
	_heavy_press()
	await _frames_until(PlayerCombat.State.ACTIVE)
	_player.hurtbox.receive_hit(DamageInfo.new(10000.0, self))
	var cleared: bool = _combat.get_state() == PlayerCombat.State.DEAD and _combat.get_current_attack() == null \
		and not _player.attack_hitbox.is_active() and _combat.get_combo_index() == PlayerCombat.NO_ATTACK
	_heavy_press()
	_light_press()
	await _frames(40)
	_record(cleared and _started == [HEAVY],
		"DE1) dying mid-heavy: attack, chain and hitbox cleared; neither heavy nor light runs after")


# --- frame-rate independence -----------------------------------------------------------------------

func _frame_rate_tests() -> void:
	for hz in [30.0, 144.0]:
		var dt: float = 1.0 / hz
		var bare: PlayerCombat = PlayerCombat.new()
		bare.data = _shipped
		add_child(bare)
		bare.set_physics_process(false)
		bare.request_heavy_attack()
		var windup: float = _step_until(bare, PlayerCombat.State.ACTIVE, dt)
		var active: float = _step_until(bare, PlayerCombat.State.RECOVERY, dt)
		var recovery: float = _step_until(bare, PlayerCombat.State.IDLE, dt)
		_record(_within(windup, _heavy.windup, dt) and _within(active, _heavy.active, dt)
				and _within(recovery, _heavy.recovery, dt),
			"F1) at %d Hz the heavy's phases last %.3f / %.3f / %.3f" % [hz, windup, active, recovery])
		bare.queue_free()


# --- invariants -------------------------------------------------------------------------------------

func _check_invariants() -> void:
	var state: PlayerCombat.State = _combat.get_state()
	var attack: AttackData = _combat.get_current_attack()
	var open: bool = _player.attack_hitbox.is_active()
	var name_of: String = PlayerCombat.State.keys()[state]
	if state == PlayerCombat.State.IDLE and (attack != null or _combat.get_combo_index() != PlayerCombat.NO_ATTACK
			or _combat.get_queued_attack() != null or _combat.has_buffered_attack()):
		_violations.append("IDLE holding an attack")
	if state == PlayerCombat.State.DEAD and (attack != null or _combat.has_buffered_attack()):
		_violations.append("DEAD holding an attack or a press")
	if open != (state == PlayerCombat.State.ACTIVE):
		_violations.append("hitbox %s in %s" % ["open" if open else "shut", name_of])
	if _combat.is_attacking() and attack == null:
		_violations.append("%s without an attack" % name_of)
	if attack == _heavy and (_combat.get_queued_attack() != null or _combat.has_buffered_attack()
			or _combat.get_combo_index() != 0):
		_violations.append("the heavy holding a follow-up")


# --- helpers ---------------------------------------------------------------------------------------

func _heavy_press() -> void:
	_player.camera_rig.attack_heavy_pressed.emit()


func _light_press() -> void:
	_player.camera_rig.attack_light_pressed.emit()


func _heavy_swing() -> void:
	_heavy_press()
	await _frames_until(PlayerCombat.State.IDLE)
	await _frames(3)


func _duration(attack: AttackData) -> float:
	return attack.windup + attack.active + attack.recovery


func _hp(dummy: TrainingDummy) -> float:
	return (dummy.get_node("HealthComponent") as HealthComponent).current_health


func _flat_speed() -> float:
	return Vector2(_player.velocity.x, _player.velocity.z).length()


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


func _spawn(pos: Vector3) -> TrainingDummy:
	var dummy: TrainingDummy = DUMMY_SCENE.instantiate() as TrainingDummy
	add_child(dummy)
	dummy.global_position = pos
	return dummy


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


func _near(frames: int, seconds: float) -> bool:
	var dt: float = 1.0 / Engine.physics_ticks_per_second
	return frames >= 0 and absf(frames * dt - seconds) <= FRAME_SLACK * dt + 0.0001


func _within(measured: float, configured: float, dt: float) -> bool:
	return measured >= configured - 0.0001 and measured <= configured + dt * 1.01


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _wait(t: float) -> void:
	await get_tree().create_timer(t).timeout


func _attack_id() -> StringName:
	var attack: AttackData = _combat.get_current_attack()
	return attack.id if attack != null else &""


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
