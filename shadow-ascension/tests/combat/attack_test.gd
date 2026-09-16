extends Node3D

const ATTACK_CYCLE: float = 0.55

@onready var _player: Player = $Player
@onready var _dummy: TrainingDummy = $TrainingDummy
@onready var _health: HealthComponent = _dummy.get_node("HealthComponent")

var _phase: int = 0
var _phase_timer: float = 0.0
var _prev_hp: float = 0.0
var _spam_prev_hp: float = 0.0
var _spam_verified: bool = false
var _hits_landed: int = 0
var _died_fired: bool = false


func _ready() -> void:
	_prev_hp = _health.current_health
	_health.health_changed.connect(_on_hp_changed)
	_health.died.connect(_on_died)
	print("[TEST] setup: player at %s, dummy at %s, hp %.0f" % [_player.global_position, _dummy.global_position, _health.current_health])


func _physics_process(delta: float) -> void:
	_phase_timer += delta
	match _phase:
		0:
			if _phase_timer > 0.2:
				_fire("attack #1 (against dummy)")
				_phase = 1
				_phase_timer = 0.0
		1:
			# spam attempt during active window — must be blocked
			if _phase_timer > 0.05:
				_spam_prev_hp = _health.current_health
				var state_before: int = _player._attack_state
				_fire("spam attempt (should be blocked)")
				var state_after: int = _player._attack_state
				if state_before == state_after:
					print("[TEST] PASS: spam blocked (state unchanged: %d)" % state_before)
					_spam_verified = true
				else:
					print("[TEST] FAIL: spam not blocked (state %d -> %d)" % [state_before, state_after])
				_phase = 2
				_phase_timer = 0.0
		2:
			# wait for first-attack cycle to finish, then chain 3 more
			if _phase_timer > ATTACK_CYCLE + 0.15:
				_fire("attack #2")
				_phase = 3
				_phase_timer = 0.0
		3:
			if _phase_timer > ATTACK_CYCLE + 0.15:
				_fire("attack #3")
				_phase = 4
				_phase_timer = 0.0
		4:
			if _phase_timer > ATTACK_CYCLE + 0.15:
				_fire("attack #4 (kill blow)")
				_phase = 5
				_phase_timer = 0.0
		5:
			if _phase_timer > ATTACK_CYCLE + 0.3:
				print("[TEST] final hp=%.0f is_dead=%s hits=%d died_signal=%s spam_pass=%s" % [_health.current_health, _health.is_dead, _hits_landed, _died_fired, _spam_verified])
				var ok: bool = _hits_landed >= 4 and _health.is_dead and _died_fired and _spam_verified
				print("[TEST] RESULT: %s" % ("PASS" if ok else "FAIL"))
				get_tree().quit()


func _fire(label: String) -> void:
	print("[TEST] fire: %s (t=%.3f)" % [label, Time.get_ticks_msec() / 1000.0])
	_player._on_attack_light_pressed()


func _on_hp_changed(current: float, maximum: float) -> void:
	print("[TEST] hp change: %.0f -> %.0f / %.0f" % [_prev_hp, current, maximum])
	if current < _prev_hp:
		_hits_landed += 1
	_prev_hp = current


func _on_died() -> void:
	_died_fired = true
	print("[TEST] died signal fired at attack #%d" % _hits_landed)
