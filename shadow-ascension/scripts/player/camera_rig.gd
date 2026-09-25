class_name CameraRig
extends Node3D

## The player's camera: mouse look, the attack buttons, and the camera shake.
##
## Camera shake (M11.9). A shake throws the camera sideways and up and lets it
## settle, through the Camera3D's own h_offset and v_offset: the picture moves,
## no node does. This rig's rotation — what "forward" means to movement, aiming
## and the target lock — is never touched, so a shake cannot turn the player,
## bend an attack or move a lock. One shake at a time: a stronger one replaces
## what is left of the current one, a weaker one is ignored, and nothing ever
## adds up. It runs on the clock, not on game time, so a hit stop holding the
## game does not hold the shake; a pause, which is not a moment to shake in,
## ends it.

## The attack buttons, as intents. Here rather than on the player because a
## click while the cursor is free captures it instead of attacking.
signal attack_light_pressed
signal attack_heavy_pressed

## Two sines of unrelated frequencies make the shake's path, so it never settles
## into a line or a circle; this ties the second to the first.
const SHAKE_VERTICAL_RATIO: float = 0.77
const SHAKE_VERTICAL_PHASE: float = 1.3
const USEC_PER_SECOND: float = 1000000.0

@export var mouse_sensitivity: float = 0.005
@export var minimum_pitch: float = -1.2
@export var maximum_pitch: float = 1.2
@export var camera_distance: float = 4.0
## How many times a second the shake swings side to side.
@export var shake_frequency: float = 19.0

@onready var pitch_pivot: Node3D = $PitchPivot
@onready var spring_arm: SpringArm3D = $PitchPivot/SpringArm3D
@onready var camera: Camera3D = $PitchPivot/SpringArm3D/Camera3D

## The shake running now: how far it throws the camera at its start, in metres,
## how long it takes to settle, in seconds, and when it began; 0 when none.
var _shake_strength: float = 0.0
var _shake_duration: float = 0.0
var _shake_started_usec: int = 0


func _ready() -> void:
	spring_arm.spring_length = camera_distance
	set_process(false)
	_clear_shake_offset()
	var body: CollisionObject3D = get_parent() as CollisionObject3D
	if body != null:
		spring_arm.add_excluded_object(body.get_rid())
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			var motion: InputEventMouseMotion = event
			rotation.y -= motion.relative.x * mouse_sensitivity
			pitch_pivot.rotation.x -= motion.relative.y * mouse_sensitivity
			pitch_pivot.rotation.x = clamp(pitch_pivot.rotation.x, minimum_pitch, maximum_pitch)
		return

	if event is InputEventKey:
		var key: InputEventKey = event
		if key.pressed and not key.echo and key.keycode == KEY_ESCAPE:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		return

	if event.is_action_pressed("attack_light"):
		_attack_pressed(attack_light_pressed)
	elif event.is_action_pressed("attack_heavy"):
		_attack_pressed(attack_heavy_pressed)


func _attack_pressed(intent: Signal) -> void:
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		intent.emit()
	else:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	get_viewport().set_input_as_handled()


# --- camera shake --------------------------------------------------------------------

## Shakes the camera `strength` metres at most, settling over `duration`
## seconds. A shake weaker than what is left of the current one is ignored; one
## at least as strong replaces it. Nothing shakes while the game is paused.
## True when this shake is the one playing.
func shake(strength: float, duration: float) -> bool:
	if strength <= 0.0 or duration <= 0.0 or not can_process():
		return false
	if strength < get_shake_strength():
		return false
	_shake_strength = strength
	_shake_duration = duration
	_shake_started_usec = Time.get_ticks_usec()
	set_process(true)
	return true


## Ends the shake at once and puts the camera back where it belongs.
func stop_shake() -> void:
	_shake_strength = 0.0
	_shake_duration = 0.0
	set_process(false)
	_clear_shake_offset()


## How far the current shake throws the camera now: its strength, easing out
## to nothing over its duration. 0 when nothing shakes.
func get_shake_strength() -> float:
	if _shake_duration <= 0.0:
		return 0.0
	var remaining: float = 1.0 - _shake_elapsed() / _shake_duration
	if remaining <= 0.0:
		return 0.0
	return _shake_strength * remaining * remaining


func is_shaking() -> bool:
	return get_shake_strength() > 0.0


## Where the shake has put the camera this frame: sideways, up.
func get_shake_offset() -> Vector2:
	if camera == null:
		return Vector2.ZERO
	return Vector2(camera.h_offset, camera.v_offset)


func _process(_delta: float) -> void:
	var strength: float = get_shake_strength()
	if strength <= 0.0:
		stop_shake()
		return
	var phase: float = _shake_elapsed() * shake_frequency * TAU
	camera.h_offset = strength * sin(phase)
	camera.v_offset = strength * sin(phase * SHAKE_VERTICAL_RATIO + SHAKE_VERTICAL_PHASE)


func _notification(what: int) -> void:
	if what == NOTIFICATION_PAUSED:
		stop_shake()


func _shake_elapsed() -> float:
	return float(Time.get_ticks_usec() - _shake_started_usec) / USEC_PER_SECOND


func _clear_shake_offset() -> void:
	if camera == null:
		return
	camera.h_offset = 0.0
	camera.v_offset = 0.0
