extends Node3D

## M11.2 — the light attack combo chain, on a real player against training dummies.
##
##   godot --headless --path . res://tests/combat/light_combo_test.tscn
##
## Attack 1 -> Attack 2 -> Attack 3, driven the way a device drives it (the camera
## rig's signal) and read back through PlayerCombat's queries. Throughout the
## whole suite a watcher checks, every physics frame, that the combat is never
## in an impossible state: free with an attack or a queued one, a hitbox open
## outside the active phase, a dead player holding a buffered press.

const DUMMY_SCENE: PackedScene = preload("res://scenes/enemies/training_dummy.tscn")
const IN_FRONT: Vector3 = Vector3(0, 0.1, -1.5)
const LEFT: Vector3 = Vector3(-0.4, 0.1, -1.5)
const RIGHT: Vector3 = Vector3(0.4, 0.1, -1.5)
const FRAME_SLACK: int = 2
const CHAIN: Array[StringName] = [&"light_attack_1", &"light_attack_2", &"light_attack_3"]

@onready var _player: Player = $Player

var _combat: PlayerCombat = null
var _shipped: PlayerCombatData = null
var _shipped_snapshot: Dictionary = {}
var _started: Array[StringName] = []
var _violations: Array[String] = []
var _watching: bool = false
var _pass: int = 0
var _fail: int = 0


func _ready() -> void:
	_reset_session()
	_combat = _player.combat
	_shipped = _combat.data
	_shipped_snapshot = _snapshot(_shipped)
	_combat.attack_started.connect(_on_attack_started)
	_run()


## Checked at the start of every physics frame, before the combat's own tick —
## what every other system sees of it.
func _physics_process(_delta: float) -> void:
	if _watching:
		_check_invariants()


func _run() -> void:
	await _wait(0.2)
	_watching = true
	_record(_combat.data.light_combo.size() == 3 and _ids(_combat.data.light_combo) == CHAIN
			and not _combat.debug_log_enabled,
		"A0) the light combo is three attacks, in order %s; the debug log is off" % [CHAIN])
	await _chain_tests()
	await _timing_tests()
	await _partial_tests()
	await _spam_tests()
	await _hit_tests()
	await _damage_tests()
	await _reset_tests()
	_watching = false
	_frame_rate_tests()
	_record(_violations.is_empty(),
		"I1) no impossible state in any frame of the suite (%d: %s)" % [
			_violations.size(), _violations.slice(0, 3)])
	_record(_snapshot(_shipped) == _shipped_snapshot and _combat.data == _shipped,
		"I2) the shared attack data holds exactly what it was loaded with")
	print("[SUMMARY] passed=%d failed=%d" % [_pass, _fail])
	get_tree().quit()


# --- the chain ----------------------------------------------------------------------------

func _chain_tests() -> void:
	await _fresh()
	_fire()
	_record(_attack_id() == &"light_attack_1" and _combat.get_combo_index() == 0,
		"C1) Light Attack starts Attack 1, combo index 0")

	var phases: Array[String] = []
	var indices: Array[int] = []
	for step in 3:
		indices.append(_combat.get_combo_index())
		phases.append(await _phases_of_current_attack(step < 2))
	_record(_started == CHAIN and indices == [0, 1, 2],
		"C2/C3) pressed in each window: exactly 1 -> 2 -> 3 (%s, index %s)" % [_started, indices])
	_record(phases == ["WINDUP>ACTIVE>RECOVERY", "WINDUP>ACTIVE>RECOVERY", "WINDUP>ACTIVE>RECOVERY"],
		"C4) each attack runs its own windup, active and recovery (%s)" % [phases])
	await _frames_until(PlayerCombat.State.IDLE)
	_record(_combat.get_combo_index() == PlayerCombat.NO_ATTACK and _combat.get_queued_attack() == null
			and not _combat.has_buffered_attack() and _combat.get_current_attack() == null,
		"C5) after Attack 3 the chain is over: no index, nothing queued or buffered")
	_fire()
	_record(_attack_id() == &"light_attack_1", "C6) and the next Light Attack is Attack 1")
	await _frames_until(PlayerCombat.State.IDLE)


# --- when a press counts (§14) ------------------------------------------------------------

func _timing_tests() -> void:
	var attack_1: AttackData = _shipped.light_combo[0]

	# Too early: in the windup, further from the window than the buffer reaches.
	await _fresh()
	_fire()
	await _frames(1)
	_fire()
	await _frames_until(PlayerCombat.State.IDLE)
	await _frames(3)
	_record(_started == [&"light_attack_1"],
		"T1) too early (windup): the press expires in the buffer and the chain ends with Attack 1")

	# Buffered: in the active phase, closer to the window than the buffer reaches.
	await _fresh()
	_fire()
	await _frames_until(PlayerCombat.State.ACTIVE)
	var lead_frames: int = int(ceil(attack_1.active * Engine.physics_ticks_per_second)) - 4
	await _frames(4)
	_fire()
	var held: bool = _combat.has_buffered_attack() and _combat.get_queued_attack() == null
	await _frames_until(PlayerCombat.State.RECOVERY)
	await _frames(1)
	var taken: bool = _combat.get_queued_attack() != null and not _combat.has_buffered_attack()
	await _frames_until(PlayerCombat.State.IDLE)
	_record(held and taken and _started == [&"light_attack_1", &"light_attack_2"],
		"T2) buffered (%d frames before the window): held, taken when it opens, Attack 2 follows" % lead_frames)

	# In the window: queued at once.
	await _fresh()
	_fire()
	await _frames_until(PlayerCombat.State.RECOVERY)
	await _frames(5)
	_fire()
	var queued_now: bool = _combat.get_queued_attack() != null and _combat.get_queued_attack().id == &"light_attack_2"
	await _frames_until(PlayerCombat.State.WINDUP)
	_record(queued_now and _attack_id() == &"light_attack_2",
		"T3) in the combo window: Attack 2 is queued at once and starts when Attack 1 is over")
	await _frames_until(PlayerCombat.State.IDLE)

	# Too late: the attack is over, so is the chain.
	await _fresh()
	_fire()
	await _frames_until(PlayerCombat.State.IDLE)
	_fire()
	_record(_attack_id() == &"light_attack_1" and _started == [&"light_attack_1", &"light_attack_1"],
		"T4) too late: pressed the frame after Attack 1 ended, a new chain starts at Attack 1")
	await _frames_until(PlayerCombat.State.IDLE)

	# A window that closes before the end of recovery.
	_combat.data = _copy_of_shipped()
	_combat.data.light_combo[0].combo_window_end = 0.4
	await _fresh()
	_fire()
	await _frames_until(PlayerCombat.State.RECOVERY)
	var late_frames: int = int(ceil(attack_1.recovery * 0.4 * Engine.physics_ticks_per_second)) + 2
	await _frames(late_frames)
	_fire()
	var refused: bool = _combat.get_queued_attack() == null and not _combat.has_buffered_attack()
	await _frames_until(PlayerCombat.State.IDLE)
	_combat.data = _shipped
	_record(refused and _started == [&"light_attack_1"],
		"T5) combo_window_end 0.4: a press later in recovery is too late, and the chain ends")


# --- partial chains and timeouts ------------------------------------------------------------

func _partial_tests() -> void:
	# Attack 1 alone, waited out completely.
	await _fresh()
	_fire()
	await _frames_until(PlayerCombat.State.IDLE)
	var reset_after_one: bool = _combat.get_combo_index() == PlayerCombat.NO_ATTACK
	await _wait(0.3)
	_fire()
	_record(reset_after_one and _attack_id() == &"light_attack_1",
		"P1) slow input: Attack 1, wait it out, press -> Attack 1 again (never 'Attack 2 next')")
	await _frames_until(PlayerCombat.State.IDLE)

	# 1 -> 2 -> nothing.
	await _fresh()
	_fire()
	await _frames_until(PlayerCombat.State.RECOVERY)
	_fire()
	await _frames_until(PlayerCombat.State.WINDUP)
	await _frames_until(PlayerCombat.State.IDLE)
	var reset_after_two: bool = _combat.get_combo_index() == PlayerCombat.NO_ATTACK
	_fire()
	_record(reset_after_two and _started == [&"light_attack_1", &"light_attack_2", &"light_attack_1"],
		"P2) partial chain 1 -> 2 with no third press ends there; the next press is Attack 1")
	await _frames_until(PlayerCombat.State.IDLE)


# --- spam (§10, §34) ------------------------------------------------------------------------

func _spam_tests() -> void:
	# Fifteen presses in one frame buy one attack.
	await _fresh()
	for i in 15:
		_fire()
	await _frames_until(PlayerCombat.State.IDLE)
	await _frames(3)
	_record(_started == [&"light_attack_1"], "SP1) fifteen presses in one frame: one Attack 1 (%s)" % [_started])

	# Fifteen presses inside one window buy one follow-up.
	await _fresh()
	_fire()
	await _frames_until(PlayerCombat.State.RECOVERY)
	for i in 15:
		_fire()
	await _frames_until(PlayerCombat.State.WINDUP)
	await _frames_until(PlayerCombat.State.IDLE)
	_record(_started == [&"light_attack_1", &"light_attack_2"],
		"SP2) fifteen presses in Attack 1's window: one Attack 2, and the chain stops there (%s)" % [_started])

	# Mashing every frame for three seconds, then letting go.
	await _fresh()
	var frames: int = 0
	while frames < 180:
		_fire()
		await get_tree().physics_frame
		frames += 1
	var at_release: int = _started.size()
	var drained: int = await _frames_until(PlayerCombat.State.IDLE, 120)
	await _frames(20)
	var after_release: int = _started.size() - at_release
	var in_order: bool = true
	for i in _started.size():
		if _started[i] != CHAIN[i % CHAIN.size()]:
			in_order = false
	_record(in_order and _started.size() >= 3,
		"SP3) mashing for 3s: always 1 -> 2 -> 3 -> 1 ..., never skipping or repeating (%d attacks)" % _started.size())
	_record(after_release <= 1 and drained >= 0,
		"SP4) and once the button is let go at most the one queued attack runs (%d), then IDLE" % after_release)


# --- hits: one per swing, per target ----------------------------------------------------------

func _hit_tests() -> void:
	# One dummy through the full combo.
	await _fresh()
	var dummy: TrainingDummy = _spawn(IN_FRONT)
	var health: HealthComponent = dummy.get_node("HealthComponent")
	var after_each: Array[float] = []
	var on_changed: Callable = func(current: float, _maximum: float) -> void: after_each.append(current)
	health.health_changed.connect(on_changed)
	var hits: Array[String] = []
	var on_landed: Callable = func(target: Node, hit: DamageInfo) -> void:
		hits.append("%s>%s" % [hit.attack_id, target.name])
	_player.attack_hitbox.hit_landed.connect(on_landed)
	await _frames(2)
	await _full_combo()
	health.health_changed.disconnect(on_changed)
	_record(after_each == [80.0, 55.0, 20.0],
		"H1) the full combo on one dummy: 100 -> 80 -> 55 -> 20, one health update per swing (%s)" % [after_each])
	_record(hits.size() == 3 and hits[0].begins_with("light_attack_1") and hits[1].begins_with("light_attack_2")
			and hits[2].begins_with("light_attack_3"),
		"H2) each attack hits it exactly once, and Attack 2 and 3 hit it again (%s)" % [hits])
	dummy.queue_free()

	# Two dummies inside the same hitbox.
	await _fresh()
	var left: TrainingDummy = _spawn(LEFT)
	var right: TrainingDummy = _spawn(RIGHT)
	left.name = "Left"
	right.name = "Right"
	hits.clear()
	await _frames(2)
	await _full_combo()
	hits.sort()
	var expected: Array[String] = []
	for id in CHAIN:
		expected.append("%s>Left" % id)
		expected.append("%s>Right" % id)
	expected.sort()
	_record(hits == expected,
		"H3) two dummies in the hitbox: each attack hits each once — six hits (%d)" % hits.size())
	left.queue_free()
	right.queue_free()

	# The first dies to Attack 1; the combo goes on and finds the second.
	await _fresh()
	var first: TrainingDummy = _spawn(LEFT)
	var second: TrainingDummy = _spawn(RIGHT)
	first.name = "First"
	second.name = "Second"
	hits.clear()
	await _frames(2)
	(first.get_node("HealthComponent") as HealthComponent).current_health = 20.0
	await _full_combo()
	_player.attack_hitbox.hit_landed.disconnect(on_landed)
	var first_hits: int = 0
	var second_hits: int = 0
	for hit in hits:
		if hit.ends_with(">First"):
			first_hits += 1
		elif hit.ends_with(">Second"):
			second_hits += 1
	_record((first.get_node("HealthComponent") as HealthComponent).is_dead and first_hits == 1
			and second_hits == 3 and _started == CHAIN,
		"H4) a target killed by Attack 1 takes no more hits; Attack 2 and 3 still land on the other")
	first.queue_free()
	second.queue_free()


# --- damage ----------------------------------------------------------------------------------

func _damage_tests() -> void:
	var expected: Array[float] = []
	var formula: bool = true
	for attack in _shipped.light_combo:
		var value: float = _combat.calculate_damage(attack)
		expected.append(value)
		if value != _shipped.base_damage * attack.damage_multiplier:
			formula = false
	_record(expected == [20.0, 25.0, 35.0] and formula,
		"D1) base 20 x 1.0 / 1.25 / 1.75 = %s, through the one damage function" % [expected])

	# Retuning Attack 2 alone moves Attack 2 alone.
	_combat.data = _copy_of_shipped()
	_combat.data.light_combo[1].damage_multiplier = 2.0
	await _fresh()
	var dummy: TrainingDummy = _spawn(IN_FRONT)
	var amounts: Array[float] = []
	var on_landed: Callable = func(_target: Node, hit: DamageInfo) -> void: amounts.append(hit.amount)
	_player.attack_hitbox.hit_landed.connect(on_landed)
	await _frames(2)
	await _full_combo()
	_player.attack_hitbox.hit_landed.disconnect(on_landed)
	_combat.data = _shipped
	_record(amounts == [20.0, 40.0, 35.0] and _shipped.light_combo[1].damage_multiplier == 1.25,
		"D2) Attack 2 at x2.0 on a copy: %s — only Attack 2 moved, and the shipped asset did not" % [amounts])
	dummy.queue_free()


# --- resets ----------------------------------------------------------------------------------

func _reset_tests() -> void:
	# Death during each attack, with a follow-up queued where there is one.
	for step in 3:
		await _fresh()
		_fire()
		for i in step:
			await _frames_until(PlayerCombat.State.RECOVERY)
			_fire()
			await _frames_until(PlayerCombat.State.WINDUP)
		await _frames_until(PlayerCombat.State.ACTIVE)
		if step < 2:
			await _frames(2)
			_fire()
		var dying_in: StringName = _attack_id()
		_player.hurtbox.receive_hit(DamageInfo.new(10000.0, self))
		var cleared: bool = _combat.get_state() == PlayerCombat.State.DEAD
		cleared = cleared and _combat.get_current_attack() == null and _combat.get_queued_attack() == null
		cleared = cleared and not _combat.has_buffered_attack() and not _player.attack_hitbox.is_active()
		cleared = cleared and _combat.get_combo_index() == PlayerCombat.NO_ATTACK
		var started_before: int = _started.size()
		_fire()
		await _frames(40)
		_record(cleared and _started.size() == started_before and dying_in == CHAIN[step],
			"R%d) dying in %s: attack, index, queue, buffer and hitbox cleared; nothing runs after" % [
				step + 1, dying_in])

	# The existing interruption, the dodge, ends the chain too.
	await _fresh()
	_fire()
	await _frames_until(PlayerCombat.State.RECOVERY)
	_fire()
	_player._on_dodge_pressed()
	var dodged: bool = _combat.is_dodging() and _combat.get_combo_index() == PlayerCombat.NO_ATTACK \
		and _combat.get_queued_attack() == null
	await _frames_until(PlayerCombat.State.IDLE)
	await _wait(_shipped.dodge_cooldown + 0.05)
	_fire()
	_record(dodged and _started == [&"light_attack_1", &"light_attack_1"],
		"R4) a dodge out of Attack 1's recovery drops the queued Attack 2; the next press is Attack 1")
	await _frames_until(PlayerCombat.State.IDLE)


# --- frame-rate independence ------------------------------------------------------------------

func _frame_rate_tests() -> void:
	for hz in [30.0, 144.0]:
		var dt: float = 1.0 / hz
		var bare: PlayerCombat = PlayerCombat.new()
		bare.data = _shipped
		add_child(bare)
		bare.set_physics_process(false)
		var starts: Array[float] = []
		# A lambda captures locals by value, so the clock it reads is a one-slot array.
		var clock: Array[float] = [0.0]
		bare.attack_started.connect(func(_attack: AttackData) -> void: starts.append(clock[0]))
		bare.request_light_attack()
		while clock[0] < 3.0 and bare.get_state() != PlayerCombat.State.IDLE:
			if bare.get_state() == PlayerCombat.State.RECOVERY and bare.get_queued_attack() == null:
				bare.request_light_attack()
			bare._physics_process(dt)
			clock[0] += dt
		var ok: bool = starts.size() == 3
		var boundaries: Array[float] = [0.0]
		for attack in _shipped.light_combo:
			boundaries.append(boundaries[-1] + attack.windup + attack.active + attack.recovery)
		for i in starts.size():
			# Each phase ends on the first step at or past it: up to one step late, three phases an attack.
			if starts[i] < boundaries[i] - 0.0001 or starts[i] > boundaries[i] + 3.0 * i * dt * 1.01:
				ok = false
		_record(ok, "F1) at %d Hz the chain starts its attacks at %s (configured %s)" % [
			hz, _rounded(starts), _rounded(boundaries.slice(0, 3))])

		# Too early at this rate too: a press right after the start is dropped.
		bare.reset()
		bare.request_light_attack()
		bare._physics_process(dt)
		bare.request_light_attack()
		while bare.get_state() != PlayerCombat.State.IDLE:
			bare._physics_process(dt)
		_record(bare.get_combo_index() == PlayerCombat.NO_ATTACK and starts.size() == 4,
			"F2) at %d Hz a press in the windup does not chain" % hz)
		bare.queue_free()


# --- invariants (§41) -------------------------------------------------------------------------

func _check_invariants() -> void:
	var state: PlayerCombat.State = _combat.get_state()
	var attack: AttackData = _combat.get_current_attack()
	var index: int = _combat.get_combo_index()
	var queued: AttackData = _combat.get_queued_attack()
	var open: bool = _player.attack_hitbox.is_active()
	var combo: Array[AttackData] = _combat.data.light_combo
	var name_of: String = PlayerCombat.State.keys()[state]
	if state == PlayerCombat.State.IDLE and (attack != null or index != PlayerCombat.NO_ATTACK
			or queued != null or _combat.has_buffered_attack()):
		_violations.append("IDLE holding an attack")
	if state == PlayerCombat.State.DEAD and (attack != null or queued != null or _combat.has_buffered_attack()):
		_violations.append("DEAD holding an attack or a press")
	if open != (state == PlayerCombat.State.ACTIVE):
		_violations.append("hitbox %s in %s" % ["open" if open else "shut", name_of])
	if _combat.is_attacking() and (index < 0 or index >= combo.size() or combo[index] != attack):
		_violations.append("%s with index %d" % [name_of, index])
	if queued != null and (index + 1 >= combo.size() or combo[index + 1] != queued):
		_violations.append("queued %s after index %d" % [queued.id, index])


# --- helpers ---------------------------------------------------------------------------------

func _fire() -> void:
	_player.camera_rig.attack_light_pressed.emit()


## The whole chain: each follow-up pressed a few frames into its window.
func _full_combo() -> void:
	_fire()
	for i in 2:
		await _frames_until(PlayerCombat.State.RECOVERY)
		await _frames(3)
		_fire()
		await _frames_until(PlayerCombat.State.WINDUP)
	await _frames_until(PlayerCombat.State.IDLE)
	await _frames(3)


## Follows the current attack through its phases, pressing for the next one in
## its window when `chain` is true; returns the phases it saw.
func _phases_of_current_attack(chain: bool) -> String:
	var attack: AttackData = _combat.get_current_attack()
	var seen: Array[String] = [PlayerCombat.State.keys()[_combat.get_state()]]
	var pressed: bool = false
	while _combat.get_current_attack() == attack and _combat.is_attacking():
		await get_tree().physics_frame
		var now: String = PlayerCombat.State.keys()[_combat.get_state()]
		if _combat.get_current_attack() == attack and now != seen[-1]:
			seen.append(now)
		if chain and not pressed and _combat.get_state() == PlayerCombat.State.RECOVERY:
			_fire()
			pressed = true
	return ">".join(seen)


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


## Every stored property of the combat data and its attacks, by value.
func _snapshot(combat_data: PlayerCombatData) -> Dictionary:
	var values: Dictionary = {}
	for resource in [combat_data] + combat_data.light_combo:
		for property in resource.get_property_list():
			if property["usage"] & PROPERTY_USAGE_STORAGE and property["name"] != "light_combo":
				values["%s.%s" % [resource.resource_path, property["name"]]] = resource.get(property["name"])
	return values


func _ids(attacks: Array[AttackData]) -> Array[StringName]:
	var ids: Array[StringName] = []
	for attack in attacks:
		ids.append(attack.id)
	return ids


func _rounded(values: Array) -> String:
	var parts: Array[String] = []
	for value in values:
		parts.append("%.3f" % value)
	return ", ".join(parts)


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
