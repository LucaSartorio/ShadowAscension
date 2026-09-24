extends Node3D

## M11.5 — stamina, on a real player with the real HUD bar.
##
##   godot --headless --path . res://tests/combat/stamina_test.tscn
##
## Dodges go in the way a device sends them: an InputEventAction for "dodge"
## through the player's own _unhandled_input; attacks through the camera rig's
## intents. Stamina is read only through PlayerCombat's API and its
## stamina_changed signal. A watcher checks every physics frame that the stamina
## is inside 0..max and that the HUD bar shows what the signal last said.

const DT: float = 1.0 / 60.0
const FRAME_SLACK: int = 2
const ENEMY_HITBOX_LAYER: int = 32
const ENEMY_HITBOX_MASK: int = 320
const COMBAT_DATA_PATH: String = "res://resources/characters/player_combat.tres"

@onready var _player: Player = $Player
@onready var _hud: PlayerStaminaHUD = $PlayerStaminaHUD

var _combat: PlayerCombat = null
var _data: PlayerCombatData = null
var _health: HealthComponent = null
var _emissions: int = 0
var _last_signal: Vector2 = Vector2(-1.0, -1.0)
var _violations: Array[String] = []
var _watching: bool = false
var _pass: int = 0
var _fail: int = 0


func _ready() -> void:
	_reset_session()
	_combat = _player.combat
	_data = _combat.data
	_health = _player.health_component
	_combat.stamina_changed.connect(_on_stamina_changed)
	_run()


func _physics_process(_delta: float) -> void:
	if _watching:
		_check_invariants()


func _run() -> void:
	await _wait(0.2)
	_watching = true
	_config_tests()
	await _dodge_cost_tests()
	await _limit_tests()
	await _insufficient_tests()
	await _regen_tests()
	await _repeated_consumption_tests()
	await _attack_tests()
	await _atomicity_tests()
	await _iframe_tests()
	await _death_tests()
	await _api_tests()
	await _hud_tests()
	_watching = false
	_frame_rate_tests()
	_record(_violations.is_empty(),
		"I1) every frame of the suite: 0 <= stamina <= max, and the bar shows the last value signalled (%d: %s)" % [
			_violations.size(), _violations.slice(0, 3)])
	var asset: PlayerCombatData = load(COMBAT_DATA_PATH) as PlayerCombatData
	_record(asset == _data and asset.max_stamina == 100.0 and asset.dodge_stamina_cost == 25.0
			and asset.stamina_regen_rate == 40.0 and asset.stamina_regen_delay == 0.8,
		"I2) the shared configuration was never written: still 100 / 25 / 40 per s / 0.8s")
	print("[SUMMARY] passed=%d failed=%d" % [_pass, _fail])
	get_tree().quit()


# --- configuration and a new player -------------------------------------------------------------

func _config_tests() -> void:
	_record(_data.resource_path == COMBAT_DATA_PATH and _data.max_stamina == 100.0
			and _data.dodge_stamina_cost == 25.0 and _data.stamina_regen_rate == 40.0
			and _data.stamina_regen_delay == 0.8,
		"CF1) configured in %s: max %.0f, dodge %.0f, regen %.0f/s after %.1fs" % [
			COMBAT_DATA_PATH.get_file(), _data.max_stamina, _data.dodge_stamina_cost,
			_data.stamina_regen_rate, _data.stamina_regen_delay])
	_record(_combat.get_stamina() == _data.max_stamina and _combat.get_max_stamina() == _data.max_stamina
			and _emissions == 0 and not _combat.is_regenerating_stamina(),
		"CF2) a new player starts full: %.0f / %.0f, nothing signalled, not regenerating" % [
			_combat.get_stamina(), _combat.get_max_stamina()])
	_record(_hud.is_showing() and is_equal_approx(_hud.get_ratio(), 1.0),
		"CF3) and the stamina bar shows it full")
	_record(not InputMap.has_action(&"sprint"),
		"CF4) there is no sprint in the game (no sprint action): the dodge is stamina's only cost")


# --- the dodge's cost -----------------------------------------------------------------------------------

func _dodge_cost_tests() -> void:
	await _fresh()
	var before: float = _combat.get_stamina()
	var emitted: int = _emissions
	var started: bool = _dodge()
	var after: float = _combat.get_stamina()
	_record(started and is_equal_approx(before - _data.dodge_stamina_cost, after) and _emissions == emitted + 1
			and _last_signal == Vector2(after, _combat.get_max_stamina()),
		"DC1) a dodge costs %.0f when it starts: %.0f -> %.0f, one stamina_changed(%.0f, %.0f)" % [
			_data.dodge_stamina_cost, before, after, _last_signal.x, _last_signal.y])

	var lowest: float = after
	var highest: float = after
	var to_iframes: int = await _frames_until_phase(PlayerCombat.DodgePhase.INVULNERABLE)
	var to_recovery: int = await _frames_until_phase(PlayerCombat.DodgePhase.RECOVERY)
	var to_free: int = await _frames_until_phase(PlayerCombat.DodgePhase.NONE)
	lowest = minf(lowest, _combat.get_stamina())
	highest = maxf(highest, _combat.get_stamina())
	_record(lowest == after and highest == after and _emissions == emitted + 1,
		"DC2) paid once: nothing more is spent, and nothing regenerates, through the dodge")
	_record(_near(to_iframes, _data.invulnerability_start)
			and _near(to_iframes + to_recovery, _data.invulnerability_end)
			and _near(to_iframes + to_recovery + to_free, _data.dodge_duration),
		"DC3) a paid dodge is M11.4's dodge: i-frames at %d, recovery at %d, free at %d frames" % [
			to_iframes, to_iframes + to_recovery, to_iframes + to_recovery + to_free])

	await _fresh()
	Input.action_press("move_forward")
	await get_tree().physics_frame
	var start: Vector3 = _player.global_position
	_dodge()
	await _frames_until_phase(PlayerCombat.DodgePhase.NONE)
	Input.action_release("move_forward")
	var moved: float = _flat(_player.global_position - start).length()
	var expected: float = _player.effective_dodge_speed * _data.dodge_duration
	_record(absf(moved - expected) <= _player.effective_dodge_speed * DT * 2.0,
		"DC4) and it goes as far: %.2fm (speed x duration, %.2fm)" % [moved, expected])


# --- how many dodges full stamina buys ---------------------------------------------------------------

func _limit_tests() -> void:
	await _fresh()
	var dodges: int = 0
	var attempts: int = 0
	while attempts < 6:
		attempts += 1
		if not _dodge():
			break
		dodges += 1
		await _frames_until_phase(PlayerCombat.DodgePhase.NONE)
		await _frames_until_can(func() -> bool: return _combat._dodge_cooldown_remaining <= 0.0)
	var allowed: int = int(floor(_data.max_stamina / _data.dodge_stamina_cost))
	_record(dodges == allowed and _combat.get_stamina() == 0.0,
		"LM1) from full, dodging as soon as each cooldown ends: %d dodges (%.0f / %.0f), then 0 left" % [
			dodges, _data.max_stamina, _data.dodge_stamina_cost])

	# Let the last dodge's slide die out (well inside the regeneration delay), so
	# any movement below would be a dodge's.
	await _frames(20)
	var emitted: int = _emissions
	var start: Vector3 = _player.global_position
	var fifth: bool = _dodge()
	await _frames(10)
	_record(not fifth and not _combat.is_dodging() and _combat.get_dodge_phase() == PlayerCombat.DodgePhase.NONE
			and not _player.hurtbox.is_invulnerable and _combat.get_stamina() == 0.0 and _emissions == emitted
			and not _combat.can_dodge() and _flat(_player.global_position - start).length() < 0.05,
		"LM2) dodge %d refused: no DODGING, no i-frames, no movement, stamina still 0, nothing signalled" % (allowed + 1))


# --- too little stamina ---------------------------------------------------------------------------------

func _insufficient_tests() -> void:
	await _fresh()
	_combat.try_spend_stamina(_data.max_stamina - 20.0)
	var emitted: int = _emissions
	var start: Vector3 = _player.global_position
	var started: bool = _dodge()
	await _frames(10)
	_record(not started and _combat.get_stamina() == 20.0 and _emissions == emitted
			and _combat.get_state() == PlayerCombat.State.IDLE and not _player.hurtbox.is_invulnerable
			and _combat.get_dodge_phase() == PlayerCombat.DodgePhase.NONE
			and _flat(_player.global_position - start).length() < 0.05,
		"NS1) with 20 of the 25 a dodge needs: no dodge — not DODGING, no i-frames, no movement, 20 kept")

	await _fresh()
	_combat.try_spend_stamina(_data.max_stamina - _data.dodge_stamina_cost)
	var exact: bool = _dodge() and _combat.get_stamina() == 0.0
	await _frames_until_phase(PlayerCombat.DodgePhase.NONE)
	_record(exact, "NS2) with exactly 25: the dodge starts, a whole one, and leaves exactly 0")

	await _fresh()
	_combat.try_spend_stamina(_data.max_stamina)
	_combat.restore_stamina(_data.dodge_stamina_cost - PlayerCombat.STAMINA_EPSILON * 0.5)
	var sliver: bool = _dodge()
	var left: float = _combat.get_stamina()
	await _frames_until_phase(PlayerCombat.DodgePhase.NONE)
	_record(sliver and left == 0.0 and _non_negative(left),
		"NS3) a float's width short of 25 still pays it, and leaves 0 — not a negative sliver (%s)" % left)


# --- regeneration ----------------------------------------------------------------------------------------

func _regen_tests() -> void:
	await _fresh()
	_dodge()
	var spent: float = _combat.get_stamina()
	await _frames_until_phase(PlayerCombat.DodgePhase.NONE)
	var waited: int = 0
	while _combat.get_stamina() == spent and waited < 120:
		await get_tree().physics_frame
		waited += 1
	_record(_near(waited, _data.stamina_regen_delay),
		"RG1) after the dodge ends, nothing comes back for the %.1fs delay: %d frames (%.2fs)" % [
			_data.stamina_regen_delay, waited, waited * DT])
	_record(_combat.get_stamina() > spent and _combat.is_regenerating_stamina(), "RG2) then it regenerates")

	await _fresh()
	_combat.try_spend_stamina(_data.max_stamina)
	await _frames_until_can(func() -> bool: return _combat.get_stamina() > 0.0)
	var s0: float = _combat.get_stamina()
	await _frames(60)
	var gained: float = _combat.get_stamina() - s0
	_record(absf(gained - _data.stamina_regen_rate) <= _data.stamina_regen_rate * DT,
		"RG3) %.0f per second: %.2f in 60 frames" % [_data.stamina_regen_rate, gained])

	var highest: float = 0.0
	var frames: int = 0
	while _combat.get_stamina() < _combat.get_max_stamina() and frames < 600:
		await get_tree().physics_frame
		highest = maxf(highest, _combat.get_stamina())
		frames += 1
	var at_full: int = _emissions
	await _frames(60)
	_record(_combat.get_stamina() == _combat.get_max_stamina() and highest <= _combat.get_max_stamina(),
		"RG4) it fills to exactly %.0f and never past it" % _combat.get_max_stamina())
	_record(_emissions == at_full and not _combat.is_regenerating_stamina(),
		"RG5) and stops there: no stamina_changed in a second at full")


# --- a second spend restarts the delay ------------------------------------------------------------------

func _repeated_consumption_tests() -> void:
	await _fresh()
	_dodge()
	await _frames_until_phase(PlayerCombat.DodgePhase.NONE)
	await _wait(_data.stamina_regen_delay * 0.5)
	var second: bool = _dodge()
	var after_second: float = _combat.get_stamina()
	await _frames_until_phase(PlayerCombat.DodgePhase.NONE)
	# Where the first delay would have ended, and a little past it.
	await _wait(_data.stamina_regen_delay * 0.5 + 0.1)
	var held: bool = _combat.get_stamina() == after_second
	var waited: int = 0
	while _combat.get_stamina() == after_second and waited < 120:
		await get_tree().physics_frame
		waited += 1
	var total: float = (_data.stamina_regen_delay * 0.5 + 0.1) + waited * DT
	_record(second and held and absf(total - _data.stamina_regen_delay) <= (FRAME_SLACK + 1) * DT + 0.05,
		"RP1) dodge, half the delay, dodge again: the first delay is gone — regeneration starts %.2fs after the second dodge" % total)

	var s0: float = _combat.get_stamina()
	await _frames(30)
	var rate: float = (_combat.get_stamina() - s0) / (30.0 * DT)
	_record(absf(rate - _data.stamina_regen_rate) <= 1.0,
		"RP2) one regeneration, not two: %.1f per second" % rate)

	# A dodge in the middle of regenerating stops it, and restarts the delay.
	var mid: bool = _dodge()
	var paid: float = _combat.get_stamina()
	await _frames_until_phase(PlayerCombat.DodgePhase.NONE)
	await _wait(_data.stamina_regen_delay * 0.75)
	_record(mid and _combat.get_stamina() == paid,
		"RP3) a dodge while regenerating stops it, and the delay starts over")


# --- attacks cost nothing -----------------------------------------------------------------------------------

func _attack_tests() -> void:
	var light: Array[AttackData] = _data.light_combo
	var heavy: AttackData = _data.heavy_combo[0]
	var started: Array[StringName] = []
	var on_started: Callable = func(attack: AttackData) -> void: started.append(attack.id)
	_combat.attack_started.connect(on_started)

	await _fresh()
	var emitted: int = _emissions
	await _light_combo()
	_record(started == [light[0].id, light[1].id, light[2].id] and _combat.get_stamina() == _data.max_stamina
			and _emissions == emitted,
		"AT1) Light 1 -> 2 -> 3 as ever, and free: stamina still %.0f" % _combat.get_stamina())
	started.clear()
	_heavy()
	await _frames_until_state(PlayerCombat.State.IDLE)
	_record(started == [heavy.id] and _combat.get_stamina() == _data.max_stamina and _emissions == emitted,
		"AT2) the heavy as ever, and free: stamina still %.0f" % _combat.get_stamina())

	# They do not hold regeneration up: each from empty, so the maximum never
	# cuts the measurement short.
	var through: Array[String] = []
	for heavy_one in [false, true]:
		await _fresh()
		_combat.try_spend_stamina(_data.max_stamina)
		await _frames_until_can(func() -> bool: return _combat.is_regenerating_stamina())
		var s0: float = _combat.get_stamina()
		var frames_before: int = Engine.get_physics_frames()
		started.clear()
		if heavy_one:
			_heavy()
			await _frames_until_state(PlayerCombat.State.IDLE)
		else:
			await _light_combo()
		var elapsed: float = (Engine.get_physics_frames() - frames_before) * DT
		var expected: float = s0 + _data.stamina_regen_rate * elapsed
		if started.size() == (1 if heavy_one else 3) and absf(_combat.get_stamina() - expected) <= _data.stamina_regen_rate * DT * 2.0:
			through.append("%.1f -> %.1f in %.2fs" % [s0, _combat.get_stamina(), elapsed])
	_record(through.size() == 2,
		"AT3) regeneration runs straight through a light combo and a heavy: %s" % [through])

	# At 0: no dodge, but everything else.
	await _fresh()
	_combat.try_spend_stamina(_data.max_stamina)
	var no_dodge: bool = not _dodge()
	started.clear()
	_light()
	await _frames_until_state(PlayerCombat.State.IDLE)
	_heavy()
	await _frames_until_state(PlayerCombat.State.IDLE)
	Input.action_press("move_forward")
	await _frames(20)
	var speed: float = _flat(_player.velocity).length()
	Input.action_release("move_forward")
	_record(no_dodge and started == [light[0].id, heavy.id] and absf(speed - _player.effective_movement_speed) < 0.05,
		"AT4) with no stamina: the dodge is refused, but Light 1 and the heavy start and walking is full speed (%.2f)" % speed)
	_combat.attack_started.disconnect(on_started)


# --- one action, one payment ----------------------------------------------------------------------------------

func _atomicity_tests() -> void:
	await _fresh()
	var emitted: int = _emissions
	var started: int = 0
	for i in 20:
		if _dodge():
			started += 1
	await _frames_until_phase(PlayerCombat.DodgePhase.NONE)
	_record(started == 1 and _combat.get_stamina() == _data.max_stamina - _data.dodge_stamina_cost
			and _emissions == emitted + 1,
		"AC1) twenty dodge presses in one frame: one dodge, paid once")

	# A dodge refused by an attack costs nothing and reserves nothing: the next
	# press checks the stamina there is then.
	await _fresh()
	_light()
	var refused: bool = not _dodge() and _combat.get_stamina() == _data.max_stamina
	_combat.try_spend_stamina(_data.max_stamina - 10.0)
	await _frames_until_state(PlayerCombat.State.RECOVERY)
	var later: bool = _dodge()
	await _frames_until_state(PlayerCombat.State.IDLE)
	_record(refused and not later and _combat.get_stamina() == 10.0,
		"AC2) a dodge refused in an attack's windup costs nothing and holds nothing; in the cancel window, with 10 left, it is refused")

	# Enough for one dodge; a dodge and a heavy in the same frame, both ways round.
	var heavy_started: Array[bool] = [false]
	var on_started: Callable = func(_attack: AttackData) -> void: heavy_started[0] = true
	_combat.attack_started.connect(on_started)
	await _fresh()
	_combat.try_spend_stamina(_data.max_stamina - _data.dodge_stamina_cost)
	emitted = _emissions
	var dodge_first: bool = _dodge()
	_heavy()
	var first_way: bool = dodge_first and not heavy_started[0] and _combat.get_stamina() == 0.0 and _emissions == emitted + 1
	await _frames_until_phase(PlayerCombat.DodgePhase.NONE)
	await _fresh()
	_combat.try_spend_stamina(_data.max_stamina - _data.dodge_stamina_cost)
	emitted = _emissions
	heavy_started[0] = false
	_heavy()
	var dodge_second: bool = _dodge()
	var second_way: bool = heavy_started[0] and not dodge_second \
		and _combat.get_stamina() == _data.dodge_stamina_cost and _emissions == emitted
	await _frames_until_state(PlayerCombat.State.IDLE)
	_combat.attack_started.disconnect(on_started)
	_record(first_way and second_way,
		"AC3) stamina for one dodge, dodge and heavy in one frame: dodge first — it alone runs and pays; heavy first — it runs, the dodge is refused, nothing paid")


# --- the i-frames are untouched ----------------------------------------------------------------------------

func _iframe_tests() -> void:
	await _fresh()
	var attacker: Hitbox = _spawn_attacker(12.0)
	var landed: Array[Node] = []
	var on_landed: Callable = func(target: Node, _hit: DamageInfo) -> void: landed.append(target)
	attacker.hit_landed.connect(on_landed)
	await _frames(2)
	var emitted: int = _emissions
	_dodge()
	await _frames_until_phase(PlayerCombat.DodgePhase.INVULNERABLE)
	var hp: float = _health.current_health
	attacker.activate()
	await _frames(3)
	attacker.deactivate()
	var dodged: bool = landed.size() == 1 and _health.current_health == hp
	await _frames_until_phase(PlayerCombat.DodgePhase.NONE)
	_record(dodged and _combat.get_stamina() == _data.max_stamina - _data.dodge_stamina_cost and _emissions == emitted + 1,
		"IF1) an enemy hitbox in the i-frames connects and takes nothing; the dodge paid once, 25")
	await _frames(2)
	var stamina: float = _combat.get_stamina()
	attacker.activate()
	await _frames(3)
	attacker.deactivate()
	_record(landed.size() == 2 and _health.current_health == hp - 12.0 and _combat.get_stamina() >= stamina,
		"IF2) out of the dodge it takes its 12, as ever; being hit costs no stamina")
	attacker.queue_free()


# --- death ---------------------------------------------------------------------------------------------------

func _death_tests() -> void:
	await _fresh()
	_combat.try_spend_stamina(_data.max_stamina * 0.5)
	_health.take_damage(DamageInfo.new(10000.0, self))
	var emitted: int = _emissions
	await _wait(_data.stamina_regen_delay + 1.0)
	var dodged: bool = _dodge()
	_record(_combat.get_state() == PlayerCombat.State.DEAD and _combat.get_stamina() == _data.max_stamina * 0.5
			and _emissions == emitted and not dodged and not _combat.is_regenerating_stamina(),
		"DE1) dead: stamina stays where it was (%.0f), nothing regenerates, no dodge is paid for" % _combat.get_stamina())


# --- the API's edges -------------------------------------------------------------------------------------------

func _api_tests() -> void:
	await _fresh()
	_combat.try_spend_stamina(_data.max_stamina - 30.0)
	var emitted: int = _emissions
	var too_much: bool = _combat.try_spend_stamina(31.0)
	_record(not too_much and _combat.get_stamina() == 30.0 and _emissions == emitted,
		"AP1) spending 31 of 30: refused whole, nothing taken — never part of it")
	var nothing: bool = _combat.try_spend_stamina(0.0) and _combat.try_spend_stamina(-5.0)
	_combat.restore_stamina(-5.0)
	_record(nothing and _combat.get_stamina() == 30.0 and _emissions == emitted,
		"AP2) spending or restoring zero or less changes nothing and signals nothing")
	_combat.restore_stamina(500.0)
	var capped: bool = _combat.get_stamina() == _combat.get_max_stamina() and _emissions == emitted + 1
	_combat.restore_stamina(10.0)
	_record(capped and _emissions == emitted + 1,
		"AP3) restoring past the maximum stops at %.0f, once; restoring when full signals nothing" % _combat.get_max_stamina())

	# A refused spend does not restart the delay.
	await _fresh()
	_combat.try_spend_stamina(_data.max_stamina - 10.0)
	await _frames_until_can(func() -> bool: return _combat.is_regenerating_stamina())
	_combat.try_spend_stamina(50.0)
	var s0: float = _combat.get_stamina()
	await _frames(3)
	_record(_combat.get_stamina() > s0, "AP4) a refused spend leaves regeneration running")


# --- the bar ----------------------------------------------------------------------------------------------

func _hud_tests() -> void:
	await _fresh()
	var full: bool = is_equal_approx(_hud.get_ratio(), 1.0)
	_dodge()
	var after_dodge: float = _hud.get_ratio()
	await _frames_until_phase(PlayerCombat.DodgePhase.NONE)
	_combat.try_spend_stamina(_combat.get_stamina())
	var empty: float = _hud.get_ratio()
	var empty_value: float = _hud.bar.value
	await _frames_until_can(func() -> bool: return _combat.is_regenerating_stamina())
	await _frames(20)
	var rising: float = _hud.get_ratio()
	await _frames_until_can(func() -> bool: return _combat.get_stamina() == _combat.get_max_stamina(), 400)
	await _frames(2)
	_record(full and is_equal_approx(after_dodge, 0.75) and empty == 0.0 and empty_value == 0.0 and _non_negative(empty_value)
			and rising > 0.0 and rising < 1.0 and is_equal_approx(_hud.get_ratio(), 1.0),
		"HU1) the bar: full 1.0 -> dodge %.2f -> empty %.2f (value %s) -> regenerating %.2f -> full %.2f" % [
			after_dodge, empty, empty_value, rising, _hud.get_ratio()])
	_record(not _hud.is_processing() and not _hud.is_physics_processing()
			and _combat.stamina_changed.get_connections().size() == 2,
		"HU2) the bar never polls (no _process, no _physics_process): it listens to stamina_changed, once")


# --- frame-rate independence -----------------------------------------------------------------------------

func _frame_rate_tests() -> void:
	for hz in [30.0, 144.0]:
		var dt: float = 1.0 / hz
		var bare: PlayerCombat = PlayerCombat.new()
		bare.data = _data
		add_child(bare)
		bare.set_physics_process(false)
		bare.try_spend_stamina(80.0)
		var t: float = 0.0
		var spent: float = bare.get_stamina()
		while bare.get_stamina() == spent and t < 3.0:
			bare._physics_process(dt)
			t += dt
		var regen_start: float = t
		var s0: float = bare.get_stamina()
		var t0: float = t
		while t - t0 < 1.0 - dt * 0.5:
			bare._physics_process(dt)
			t += dt
		var gained: float = bare.get_stamina() - s0
		_record(regen_start >= _data.stamina_regen_delay and regen_start <= _data.stamina_regen_delay + dt * 2.01
				and absf(gained - _data.stamina_regen_rate) <= _data.stamina_regen_rate * dt * 1.01,
			"FR1) at %d Hz: regeneration starts at %.3fs, and a second of it gives %.2f" % [hz, regen_start, gained])
		bare.queue_free()


# --- invariants -------------------------------------------------------------------------------------------

func _check_invariants() -> void:
	var stamina: float = _combat.get_stamina()
	if stamina < 0.0 or stamina > _combat.get_max_stamina() or not _non_negative(stamina):
		_violations.append("stamina %s outside 0..%s" % [stamina, _combat.get_max_stamina()])
	if absf(_hud.bar.value - clampf(stamina, 0.0, _hud.bar.max_value)) > 0.011 or _hud.bar.value < 0.0:
		_violations.append("bar %s for stamina %s" % [_hud.bar.value, stamina])


func _on_stamina_changed(current: float, maximum: float) -> void:
	_emissions += 1
	_last_signal = Vector2(current, maximum)
	if current != _combat.get_stamina() or maximum != _combat.get_max_stamina():
		_violations.append("stamina_changed(%s, %s) does not match the owner" % [current, maximum])


# --- helpers ------------------------------------------------------------------------------------------------

## A free, living player at the origin with full stamina and no delay pending.
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
	_combat.restore_stamina(_combat.get_max_stamina())
	_combat._stamina_regen_delay_remaining = 0.0
	await _frames(4)


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


## Light 1 -> 2 -> 3, each follow-up pressed in its attack's combo window.
func _light_combo() -> void:
	_light()
	for i in 2:
		await _frames_until_state(PlayerCombat.State.RECOVERY)
		await _frames(3)
		_light()
		await _frames_until_state(PlayerCombat.State.WINDUP)
	await _frames_until_state(PlayerCombat.State.IDLE)


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


func _frames_until_can(condition: Callable, budget: int = 180) -> int:
	var n: int = 0
	while not condition.call():
		if n >= budget:
			return -1
		await get_tree().physics_frame
		n += 1
	return n


func _near(frames: int, seconds: float) -> bool:
	return frames >= 0 and absf(frames * DT - seconds) <= FRAME_SLACK * DT + 0.0001


## Not below zero, and not a negative zero either — what a display would print as "-0".
func _non_negative(x: float) -> bool:
	return x >= 0.0 and not str(x).begins_with("-")


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
