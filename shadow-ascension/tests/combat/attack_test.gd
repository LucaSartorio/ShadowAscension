extends Node3D

const DUMMY_SCENE: PackedScene = preload("res://scenes/enemies/training_dummy.tscn")

@onready var _player: Player = $Player

var _pass_count: int = 0
var _fail_count: int = 0
var _hit_counter: int = 0


func _ready() -> void:
	_reset_session()
	_player.global_position = Vector3(0, 0.1, 0)
	_run_all_tests()


func _run_all_tests() -> void:
	await get_tree().create_timer(0.15).timeout
	await _test_single_click()
	await _test_two_clicks_combo()
	await _test_three_clicks_full_combo()
	await _test_combo_terminates_after_attack_3()
	await _test_spam_bounded()
	await _test_combo_reset_time()
	await _test_hit_once_per_swing()
	await _test_out_of_range_no_damage()
	await _test_two_dummies_both_hit()
	await _test_orientation_toward_aim()
	_print_summary()
	get_tree().quit()


func _spawn_dummy(pos: Vector3) -> TrainingDummy:
	var d: TrainingDummy = DUMMY_SCENE.instantiate() as TrainingDummy
	add_child(d)
	d.global_position = pos
	return d


func _fire() -> void:
	_player.camera_rig.attack_light_pressed.emit()


func _wait(t: float) -> void:
	await get_tree().create_timer(t).timeout


func _dummy_hp(d: TrainingDummy) -> float:
	var hc: HealthComponent = d.get_node("HealthComponent") as HealthComponent
	return hc.current_health


func _record(passed: bool, description: String) -> void:
	if passed:
		_pass_count += 1
		print("[PASS] " + description)
	else:
		_fail_count += 1
		print("[FAIL] " + description)


func _print_summary() -> void:
	print("[SUMMARY] passed=%d failed=%d" % [_pass_count, _fail_count])


func _cooldown() -> void:
	# ensures combo state resets between tests (combo_reset_time = 0.8)
	await _wait(1.0)


func _test_single_click() -> void:
	await _cooldown()
	var d: TrainingDummy = _spawn_dummy(Vector3(0, 0.1, -1.5))
	await get_tree().physics_frame
	await get_tree().physics_frame
	_fire()
	await _wait(0.7)
	var dmg: float = 100.0 - _dummy_hp(d)
	_record(abs(dmg - 20.0) < 0.01, "1) single click → Attack 1 dmg=%.0f (expect 20)" % dmg)
	d.queue_free()


func _test_two_clicks_combo() -> void:
	await _cooldown()
	var d: TrainingDummy = _spawn_dummy(Vector3(0, 0.1, -1.5))
	await get_tree().physics_frame
	await get_tree().physics_frame
	_fire()
	await _wait(0.15)
	_fire()
	await _wait(1.2)
	var dmg: float = 100.0 - _dummy_hp(d)
	_record(abs(dmg - 45.0) < 0.01, "2) two clicks → Attack 1+2 dmg=%.0f (expect 45)" % dmg)
	d.queue_free()


func _test_three_clicks_full_combo() -> void:
	await _cooldown()
	var d: TrainingDummy = _spawn_dummy(Vector3(0, 0.1, -1.5))
	await get_tree().physics_frame
	await get_tree().physics_frame
	_fire()
	await _wait(0.2)
	_fire()
	await _wait(0.5)
	_fire()
	await _wait(1.4)
	var dmg: float = 100.0 - _dummy_hp(d)
	_record(abs(dmg - 80.0) < 0.01, "3) three clicks → full combo 1+2+3 dmg=%.0f (expect 80)" % dmg)
	d.queue_free()


func _test_combo_terminates_after_attack_3() -> void:
	await _cooldown()
	var d: TrainingDummy = _spawn_dummy(Vector3(0, 0.1, -1.5))
	await get_tree().physics_frame
	await get_tree().physics_frame
	_fire()
	await _wait(0.2)
	_fire()
	await _wait(0.5)
	_fire()
	await _wait(1.4)
	var pre_hp: float = _dummy_hp(d)
	_fire()
	await _wait(0.7)
	var dmg: float = pre_hp - _dummy_hp(d)
	_record(abs(dmg - 20.0) < 0.01, "4) after Attack 3, next click starts Attack 1 dmg=%.0f (expect 20)" % dmg)
	d.queue_free()


func _test_spam_bounded() -> void:
	await _cooldown()
	var d: TrainingDummy = _spawn_dummy(Vector3(0, 0.1, -1.5))
	await get_tree().physics_frame
	await get_tree().physics_frame
	for i in 10:
		_fire()
	await _wait(2.0)
	var dmg: float = 100.0 - _dummy_hp(d)
	_record(abs(dmg - 45.0) < 0.01, "5) spam 10 clicks in one frame → only 2 attacks land dmg=%.0f (expect 45)" % dmg)
	d.queue_free()


func _test_combo_reset_time() -> void:
	await _cooldown()
	var d: TrainingDummy = _spawn_dummy(Vector3(0, 0.1, -1.5))
	await get_tree().physics_frame
	await get_tree().physics_frame
	_fire()
	await _wait(0.7)
	await _wait(1.0)
	_fire()
	await _wait(0.7)
	var dmg: float = 100.0 - _dummy_hp(d)
	_record(abs(dmg - 40.0) < 0.01, "6) two Attack 1s separated by >combo_reset_time dmg=%.0f (expect 40)" % dmg)
	d.queue_free()


func _test_hit_once_per_swing() -> void:
	await _cooldown()
	var d: TrainingDummy = _spawn_dummy(Vector3(0, 0.1, -1.5))
	await get_tree().physics_frame
	await get_tree().physics_frame
	var hc: HealthComponent = d.get_node("HealthComponent") as HealthComponent
	_hit_counter = 0
	hc.health_changed.connect(_on_test_hit)
	_fire()
	await _wait(0.7)
	_record(_hit_counter == 1, "7) single swing hits target exactly once (fired=%d expect 1)" % _hit_counter)
	hc.health_changed.disconnect(_on_test_hit)
	d.queue_free()


func _on_test_hit(_current: float, _maximum: float) -> void:
	_hit_counter += 1


func _test_out_of_range_no_damage() -> void:
	await _cooldown()
	var d: TrainingDummy = _spawn_dummy(Vector3(0, 0.1, -8))
	await get_tree().physics_frame
	await get_tree().physics_frame
	_fire()
	await _wait(0.7)
	var dmg: float = 100.0 - _dummy_hp(d)
	_record(dmg == 0.0, "8) out-of-range attack deals no damage dmg=%.0f (expect 0)" % dmg)
	d.queue_free()


func _test_two_dummies_both_hit() -> void:
	await _cooldown()
	var d1: TrainingDummy = _spawn_dummy(Vector3(-0.4, 0.1, -1.5))
	var d2: TrainingDummy = _spawn_dummy(Vector3(0.4, 0.1, -1.5))
	await get_tree().physics_frame
	await get_tree().physics_frame
	_fire()
	await _wait(0.7)
	var dmg1: float = 100.0 - _dummy_hp(d1)
	var dmg2: float = 100.0 - _dummy_hp(d2)
	_record(abs(dmg1 - 20.0) < 0.01 and abs(dmg2 - 20.0) < 0.01, "9) both dummies in hitbox take dmg (d1=%.0f d2=%.0f expect 20 each)" % [dmg1, dmg2])
	d1.queue_free()
	d2.queue_free()


func _test_orientation_toward_aim() -> void:
	await _cooldown()
	var d: TrainingDummy = _spawn_dummy(Vector3(-1.5, 0.1, 0))
	_player.camera_rig.rotation.y = deg_to_rad(90.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_fire()
	await _wait(0.05)
	var yaw: float = _player.visual_root.rotation.y
	var expected: float = PI / 2.0
	var yaw_ok: bool = abs(yaw - expected) < 0.01
	_record(yaw_ok, "10) after cam yaw=90°, player yaw=%.3f (expect %.3f)" % [yaw, expected])
	await _wait(1.4)
	_player.camera_rig.rotation.y = 0.0
	d.queue_free()


## Every suite starts from a clean session: PlayerRuntimeState now carries
## progression and health across scene changes, so without this a later test
## would inherit whatever an earlier one left behind.
func _reset_session() -> void:
	var state: Node = get_tree().root.get_node_or_null("PlayerRuntimeState")
	if state != null:
		state.reset_runtime_state()
