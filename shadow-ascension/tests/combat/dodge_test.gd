extends Node3D

@onready var _player: Player = $Player
@onready var _wall: StaticBody3D = $Wall

var _pass: int = 0
var _fail: int = 0


func _ready() -> void:
	_reset_player()
	_run_tests()


func _run_tests() -> void:
	_reset_session()
	await get_tree().create_timer(0.15).timeout
	await _test_dodge_direction_with_input()
	await _test_diagonal_normalized()
	await _test_backstep_no_input()
	await _test_direction_locked_mid_dodge()
	await _test_dodge_hits_wall()
	await _test_no_second_dodge_during_current()
	await _test_cooldown_respected()
	await _test_iframe_timing()
	await _test_damage_ignored_during_iframes()
	await _test_damage_received_outside_iframes()
	await _test_attack_1_not_cancelable_pre_recovery()
	await _test_attack_1_cancelable_during_recovery()
	await _test_attack_2_cancel_window()
	await _test_attack_3_cancel_window()
	await _test_hitbox_disabled_on_cancel()
	await _test_queued_input_cleared_by_dodge()
	await _test_next_attack_after_dodge_is_attack_1()
	await _test_spam_space_no_break()
	print("[SUMMARY] passed=%d failed=%d" % [_pass, _fail])
	get_tree().quit()


func _wait(t: float) -> void:
	await get_tree().create_timer(t).timeout


func _record(passed: bool, description: String) -> void:
	if passed:
		_pass += 1
		print("[PASS] " + description)
	else:
		_fail += 1
		print("[FAIL] " + description)


func _reset_player() -> void:
	if _player._visual_tween != null and _player._visual_tween.is_running():
		_player._visual_tween.kill()
	_player.global_position = Vector3(0, 0.1, 0)
	_player.visual_root.rotation = Vector3.ZERO
	_player.camera_rig.rotation.y = 0.0
	_player.velocity = Vector3.ZERO
	_player._is_dodging = false
	_player._dodge_elapsed = 0.0
	_player._dodge_cooldown_remaining = 0.0
	_player._dodge_direction = Vector3.ZERO
	_player._dodge_iframes_active = false
	_player._attack_state = Player.AttackState.IDLE
	_player._attack_timer = 0.0
	_player._recovery_elapsed = 0.0
	_player._combo_index = 0
	_player._queued_next = false
	_player._current_step = null
	_player._idle_since_step_ended = 0.0
	if _player.hurtbox != null:
		_player.hurtbox.set_invulnerable(false)
	if _player.health_component != null:
		_player.health_component.current_health = _player.health_component.max_health
		_player.health_component.is_dead = false
	if _player.attack_hitbox != null and _player.attack_hitbox.is_active():
		_player.attack_hitbox.deactivate()
	if _wall != null:
		_wall.global_position = Vector3(0, 1.5, -50)


func _test_dodge_direction_with_input() -> void:
	_reset_player()
	Input.action_press("move_forward")
	await get_tree().physics_frame
	_player._on_dodge_pressed()
	await get_tree().physics_frame
	var dir: Vector3 = _player._dodge_direction
	Input.action_release("move_forward")
	var expected: Vector3 = Vector3(0, 0, -1)
	var ok: bool = dir.distance_to(expected) < 0.02
	_record(ok, "1) W+Space → forward dodge dir=%s (expect %s)" % [dir, expected])
	await _wait(0.6)


func _test_diagonal_normalized() -> void:
	_reset_player()
	Input.action_press("move_forward")
	Input.action_press("move_right")
	await get_tree().physics_frame
	_player._on_dodge_pressed()
	await get_tree().physics_frame
	var dir: Vector3 = _player._dodge_direction
	Input.action_release("move_forward")
	Input.action_release("move_right")
	var len_ok: bool = abs(dir.length() - 1.0) < 0.02
	var comp_ok: bool = abs(dir.x - 0.707) < 0.05 and abs(dir.z - (-0.707)) < 0.05
	_record(len_ok and comp_ok, "2) W+D diagonal → normalized dir=%s (len=%.3f expect 1.0)" % [dir, dir.length()])
	await _wait(0.6)


func _test_backstep_no_input() -> void:
	_reset_player()
	# no input
	await get_tree().physics_frame
	_player._on_dodge_pressed()
	await get_tree().physics_frame
	var dir: Vector3 = _player._dodge_direction
	# player faces -Z (visual_root.rotation.y = 0), backstep = +Z
	var expected: Vector3 = Vector3(0, 0, 1)
	var ok: bool = dir.distance_to(expected) < 0.02
	_record(ok, "3) Space with no input → backstep dir=%s (expect %s)" % [dir, expected])
	await _wait(0.6)


func _test_direction_locked_mid_dodge() -> void:
	_reset_player()
	Input.action_press("move_forward")
	await get_tree().physics_frame
	_player._on_dodge_pressed()
	var initial_dir: Vector3 = _player._dodge_direction
	Input.action_release("move_forward")
	Input.action_press("move_backward")
	await _wait(0.15)
	var mid_dir: Vector3 = _player._dodge_direction
	Input.action_release("move_backward")
	var ok: bool = initial_dir.distance_to(mid_dir) < 0.01 and _player._is_dodging
	_record(ok, "4) direction locked mid-dodge (initial=%s mid=%s)" % [initial_dir, mid_dir])
	await _wait(0.6)


func _test_dodge_hits_wall() -> void:
	_reset_player()
	_wall.global_position = Vector3(0, 1.5, -2)
	await get_tree().physics_frame
	await get_tree().physics_frame
	Input.action_press("move_forward")
	await get_tree().physics_frame
	_player._on_dodge_pressed()
	Input.action_release("move_forward")
	await _wait(_player.dodge_duration + 0.1)
	var final_z: float = _player.global_position.z
	_record(final_z > -1.5, "5) dodge blocked by wall (final z=%.2f expect > -1.5)" % final_z)
	_wall.global_position = Vector3(0, 1.5, -50)
	await _wait(0.4)


func _test_no_second_dodge_during_current() -> void:
	_reset_player()
	_player._on_dodge_pressed()  # backstep (no input)
	var first_dir: Vector3 = _player._dodge_direction
	await _wait(0.05)
	# try to override with W
	Input.action_press("move_forward")
	await get_tree().physics_frame
	_player._on_dodge_pressed()
	var second_dir: Vector3 = _player._dodge_direction
	Input.action_release("move_forward")
	var ok: bool = first_dir.distance_to(second_dir) < 0.01 and _player._is_dodging
	_record(ok, "6) second dodge during current fails (dir unchanged first=%s second=%s)" % [first_dir, second_dir])
	await _wait(0.6)


func _test_cooldown_respected() -> void:
	_reset_player()
	_player._on_dodge_pressed()
	await _wait(_player.dodge_duration + 0.02)
	# dodge ended, cooldown started (0.15)
	await _wait(0.03)
	var blocked_pre: bool = not _player._is_dodging
	_player._on_dodge_pressed()  # within cooldown
	var still_blocked: bool = not _player._is_dodging
	await _wait(0.2)  # past cooldown
	_player._on_dodge_pressed()
	var allowed_after: bool = _player._is_dodging
	_record(blocked_pre and still_blocked and allowed_after, "7) cooldown: mid-cooldown blocked=%s past-cooldown allowed=%s" % [still_blocked, allowed_after])
	await _wait(0.6)


func _test_iframe_timing() -> void:
	_reset_player()
	_player._on_dodge_pressed()
	await _wait(0.03)
	var pre: bool = _player.hurtbox.is_invulnerable
	await _wait(0.07)  # elapsed ~0.10
	var during: bool = _player.hurtbox.is_invulnerable
	await _wait(0.18)  # elapsed ~0.28
	var post: bool = _player.hurtbox.is_invulnerable
	_record(not pre and during and not post, "8) iframe timing pre=%s during=%s post=%s (expect false/true/false)" % [pre, during, post])
	await _wait(0.6)


func _test_damage_ignored_during_iframes() -> void:
	_reset_player()
	_player._on_dodge_pressed()
	await _wait(0.10)
	var hp_before: float = _player.health_component.current_health
	_player.hurtbox.receive_hit(25.0, self)
	var hp_after: float = _player.health_component.current_health
	_record(hp_before == hp_after, "9) damage ignored in iframe (hp %.0f -> %.0f)" % [hp_before, hp_after])
	await _wait(0.6)


func _test_damage_received_outside_iframes() -> void:
	_reset_player()
	var hp_before: float = _player.health_component.current_health
	_player.hurtbox.receive_hit(25.0, self)
	var hp_after: float = _player.health_component.current_health
	_record(hp_before - hp_after == 25.0, "10) damage applied outside iframe (delta=%.0f expect 25)" % (hp_before - hp_after))


func _test_attack_1_not_cancelable_pre_recovery() -> void:
	_reset_player()
	_player._on_attack_light_pressed()
	await _wait(0.03)  # in STARTUP
	_player._on_dodge_pressed()
	var t1: bool = not _player._is_dodging and _player._attack_state == Player.AttackState.STARTUP
	await _wait(0.14)  # in ACTIVE
	_player._on_dodge_pressed()
	var t2: bool = not _player._is_dodging and _player._attack_state == Player.AttackState.ACTIVE
	_record(t1 and t2, "11) Attack 1 not cancelable pre-recovery (startup_blocked=%s active_blocked=%s)" % [t1, t2])
	await _wait(0.6)


func _test_attack_1_cancelable_during_recovery() -> void:
	_reset_player()
	_player._on_attack_light_pressed()
	# startup 0.12 + active 0.12 = 0.24 → recovery. Fraction 0.0 → cancel immediate
	await _wait(0.28)
	_player._on_dodge_pressed()
	var ok: bool = _player._is_dodging and _player._attack_state == Player.AttackState.IDLE
	_record(ok, "12) Attack 1 cancelable during recovery (is_dodging=%s)" % _player._is_dodging)
	await _wait(0.6)


func _test_attack_2_cancel_window() -> void:
	_reset_player()
	_player._combo_index = 1  # target Attack 2 next
	_player._on_attack_light_pressed()
	# Attack 2: startup 0.14 + active 0.14 = 0.28 → recovery. Fraction 0.35 * 0.24 = 0.084s
	await _wait(0.32)  # 0.04s into recovery (< 0.084)
	_player._on_dodge_pressed()
	var early: bool = not _player._is_dodging
	await _wait(0.07)  # 0.11s into recovery (> 0.084)
	_player._on_dodge_pressed()
	var late: bool = _player._is_dodging
	_record(early and late, "13) Attack 2 cancel window (early_blocked=%s late_allowed=%s)" % [early, late])
	await _wait(0.6)


func _test_attack_3_cancel_window() -> void:
	_reset_player()
	_player._combo_index = 2
	_player._on_attack_light_pressed()
	# Attack 3: startup 0.18 + active 0.16 = 0.34 → recovery. Fraction 0.6 * 0.32 = 0.192s
	await _wait(0.42)  # 0.08s into recovery (< 0.192)
	_player._on_dodge_pressed()
	var early: bool = not _player._is_dodging
	await _wait(0.15)  # 0.23s into recovery (> 0.192)
	_player._on_dodge_pressed()
	var late: bool = _player._is_dodging
	_record(early and late, "14) Attack 3 cancel window (early_blocked=%s late_allowed=%s)" % [early, late])
	await _wait(0.6)


func _test_hitbox_disabled_on_cancel() -> void:
	_reset_player()
	_player._on_attack_light_pressed()
	await _wait(0.28)  # in recovery
	_player._on_dodge_pressed()
	var ok: bool = not _player.attack_hitbox.is_active() and not _player.attack_hitbox.monitoring
	_record(ok, "15) hitbox disabled after cancel (active=%s monitoring=%s)" % [_player.attack_hitbox.is_active(), _player.attack_hitbox.monitoring])
	await _wait(0.6)


func _test_queued_input_cleared_by_dodge() -> void:
	_reset_player()
	_player._on_attack_light_pressed()
	await _wait(0.15)
	_player._on_attack_light_pressed()  # queue Attack 2
	var was_queued: bool = _player._queued_next
	await _wait(0.15)  # move into RECOVERY
	_player._on_dodge_pressed()
	var cleared: bool = not _player._queued_next and _player._combo_index == 0
	_record(was_queued and cleared, "16) queued input cleared by dodge (was_queued=%s cleared=%s)" % [was_queued, cleared])
	await _wait(0.6)


func _test_next_attack_after_dodge_is_attack_1() -> void:
	_reset_player()
	_player._combo_index = 2  # target Attack 3
	_player._on_attack_light_pressed()
	await _wait(0.55)  # into recovery past 60% cancel
	_player._on_dodge_pressed()
	await _wait(_player.dodge_duration + _player.dodge_cooldown + 0.1)
	var idx_ok: bool = _player._combo_index == 0
	_record(idx_ok, "17) next attack after dodge starts fresh (combo_index=%d expect 0)" % _player._combo_index)
	await _wait(0.6)


func _test_spam_space_no_break() -> void:
	_reset_player()
	for i in 20:
		_player._on_dodge_pressed()
	await _wait(_player.dodge_duration + _player.dodge_cooldown + 0.2)
	# should not be stuck in dodge; single subsequent dodge should work
	_player._on_dodge_pressed()
	var recovered: bool = _player._is_dodging
	_record(recovered, "18) after spamming Space, state remains usable (is_dodging=%s)" % _player._is_dodging)
	await _wait(0.6)


## Every suite starts from a clean session: PlayerRuntimeState now carries
## progression and health across scene changes, so without this a later test
## would inherit whatever an earlier one left behind.
func _reset_session() -> void:
	var state: Node = get_tree().root.get_node_or_null("PlayerRuntimeState")
	if state != null:
		state.reset_runtime_state()
