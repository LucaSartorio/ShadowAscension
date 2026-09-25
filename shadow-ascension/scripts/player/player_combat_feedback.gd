class_name PlayerCombatFeedback
extends Node

## What a hit of the player's feels like (M11.9): the hit stop, the camera
## shake, and the mark a critical leaves. Presentation only. It hears a hit of
## the player's that counted — Hitbox.hit_accepted — and shows it; nothing reads
## anything back from it, so damage, criticals, stamina, stagger, knockback and
## the target lock are exactly the same with it or without it.
##
## Only the player's own hits are felt this way. A shadow's hit, an enemy's or
## the boss's goes through a hitbox this never listens to: the target flinches
## or flashes as it always has, and the camera and the clock stay still. An army
## of shadows can therefore never shake the screen or stutter the game.
##
## Hit stop. The whole game holds for a moment: Engine.time_scale drops to the
## data's hit_stop_time_scale, and everything that runs on delta holds with it —
## the player's attack and its input buffer, a dodge and its i-frames, stamina,
## every enemy and its stagger and push, the boss, every tween — so nothing gets
## ahead of anything else, and all of it carries on from where it was. Input is
## not held: a press during a stop lands in the buffer or the combo window as it
## would have. The stop is timed in physics ticks, which keep coming at their
## rate whatever the time scale.
##
## One per swing: the first hit of a swing that counts starts it, and another
## target of the same swing can only lengthen it to its own length, never add
## to it. Every stop is clamped to max_hit_stop_duration.
##
## This is the one writer of Engine.time_scale in the project, and it always
## puts it back to NORMAL_TIME_SCALE: when the stop runs out, when the player
## dies (a death is never held), when the game pauses (a stop never carries
## over into a menu, and none starts while paused — a boss's killing blow opens the
## run summary before its hit is reported), and when this node leaves the tree:
## a scene change, a restart, quitting.

const NORMAL_TIME_SCALE: float = 1.0
## Float slack on the stop's clock, so a stop of exactly N ticks ends on the Nth.
const TIME_EPSILON: float = 0.0001
## PLACEHOLDER look of the critical mark.
const CRITICAL_LABEL_FONT_SIZE: int = 44
const CRITICAL_LABEL_OUTLINE_SIZE: int = 10
const CRITICAL_LABEL_PIXEL_SIZE: float = 0.005

@export var data: PlayerCombatFeedbackData

# Handed over by the player in setup().
var _combat: PlayerCombat = null
var _camera_rig: CameraRig = null

## The accessibility scales in use, copied from the data and changed only
## through their setters.
var _hit_stop_scale: float = 1.0
var _camera_shake_scale: float = 1.0
## The stop holding now: how long it holds and how long it has held, in
## unscaled seconds; both 0 when none.
var _hit_stop_length: float = 0.0
var _hit_stop_elapsed: float = 0.0
## The physics tick the stop began on. It does not count: the engine had set
## that tick's time scale before the hit landed in it.
var _hit_stop_began_tick: int = -1
## Whether the swing under way has had its stop.
var _swing_stopped: bool = false
## Stops started since this node was made — never lengthened ones.
var _hit_stops: int = 0


func _ready() -> void:
	if data == null:
		push_warning("%s has no PlayerCombatFeedbackData; using the class defaults." % name)
		data = PlayerCombatFeedbackData.new()
	_hit_stop_scale = clampf(data.hit_stop_scale, 0.0, 1.0)
	_camera_shake_scale = clampf(data.camera_shake_scale, 0.0, 1.0)
	set_physics_process(false)


## Called once by the player with what this listens to and what it moves: the
## combat (a new swing), the attack hitbox (a hit that counted), the camera,
## and the health (a death ends everything at once).
func setup(combat: PlayerCombat, hitbox: Hitbox, camera_rig: CameraRig,
		health: HealthComponent) -> void:
	_combat = combat
	_camera_rig = camera_rig
	if combat != null:
		combat.attack_started.connect(_on_attack_started)
	if hitbox != null:
		hitbox.hit_accepted.connect(_on_hit_accepted)
	if health != null:
		health.died.connect(_on_owner_died)


func _exit_tree() -> void:
	end_hit_stop()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PAUSED:
		end_hit_stop()


# --- accessibility ---------------------------------------------------------------------------

func get_hit_stop_scale() -> float:
	return _hit_stop_scale


## 1.0 as designed, 0.0 no hit stop at all. A stop already holding is not
## changed.
func set_hit_stop_scale(value: float) -> void:
	_hit_stop_scale = clampf(value, 0.0, 1.0)


func get_camera_shake_scale() -> float:
	return _camera_shake_scale


## 1.0 as designed, 0.0 no camera shake at all. Turning it off also ends the
## shake playing now.
func set_camera_shake_scale(value: float) -> void:
	_camera_shake_scale = clampf(value, 0.0, 1.0)
	if _camera_shake_scale <= 0.0 and _camera_rig != null:
		_camera_rig.stop_shake()


# --- what a hit is worth ---------------------------------------------------------------------

## How long a hit of `attack` holds the game: its own stop, a critical's bonus
## on top, scaled for accessibility, clamped. 0 when it holds nothing.
func hit_stop_duration_for(attack: AttackData, critical: bool) -> float:
	if attack == null or attack.hit_stop_duration <= 0.0:
		return 0.0
	var duration: float = attack.hit_stop_duration
	if critical:
		duration += data.critical_hit_stop_bonus
	return clampf(duration * _hit_stop_scale, 0.0, data.max_hit_stop_duration)


## How far a hit of `attack` throws the camera: its own strength, a critical's
## multiplier on it, scaled for accessibility, clamped.
func camera_shake_strength_for(attack: AttackData, critical: bool) -> float:
	if attack == null or attack.camera_shake_strength <= 0.0:
		return 0.0
	var strength: float = attack.camera_shake_strength
	if critical:
		strength *= data.critical_shake_multiplier
	return clampf(strength * _camera_shake_scale, 0.0, data.max_camera_shake_strength)


func camera_shake_duration_for(attack: AttackData) -> float:
	if attack == null:
		return 0.0
	return clampf(attack.camera_shake_duration, 0.0, data.max_camera_shake_duration)


# --- the hit stop ------------------------------------------------------------------------------

func is_hit_stop_active() -> bool:
	return _hit_stop_length > 0.0


## Unscaled seconds the current stop still holds; 0 when none.
func get_hit_stop_remaining() -> float:
	return maxf(0.0, _hit_stop_length - _hit_stop_elapsed)


func get_hit_stop_count() -> int:
	return _hit_stops


## Lets the game go at once, if it is held. Safe to call at any time.
func end_hit_stop() -> void:
	if _hit_stop_length <= 0.0:
		return
	_hit_stop_length = 0.0
	_hit_stop_elapsed = 0.0
	set_physics_process(false)
	Engine.time_scale = NORMAL_TIME_SCALE


func _physics_process(_delta: float) -> void:
	if Engine.get_physics_frames() == _hit_stop_began_tick:
		return
	_hit_stop_elapsed += 1.0 / Engine.physics_ticks_per_second
	if _hit_stop_elapsed + TIME_EPSILON >= _hit_stop_length:
		end_hit_stop()


func _play_hit_stop(duration: float) -> void:
	if duration <= 0.0:
		return
	if is_hit_stop_active():
		_hit_stop_length = maxf(_hit_stop_length, duration)
		return
	if _swing_stopped:
		return
	_swing_stopped = true
	_hit_stop_length = duration
	_hit_stop_elapsed = 0.0
	_hit_stop_began_tick = Engine.get_physics_frames()
	_hit_stops += 1
	Engine.time_scale = clampf(data.hit_stop_time_scale, 0.0, NORMAL_TIME_SCALE)
	set_physics_process(true)


# --- hearing the hits ------------------------------------------------------------------------

func _on_attack_started(_attack: AttackData) -> void:
	_swing_stopped = false


## A hit of the player's counted. The attack it belongs to is the one whose hit
## window is open — combat's current attack, whose feedback the hit plays.
func _on_hit_accepted(target: Node, hit: DamageInfo) -> void:
	if not can_process() or _combat == null:
		return
	var attack: AttackData = _combat.get_current_attack()
	if attack == null:
		return
	_play_hit_stop(hit_stop_duration_for(attack, hit.is_critical))
	if _camera_rig != null:
		_camera_rig.shake(camera_shake_strength_for(attack, hit.is_critical),
			camera_shake_duration_for(attack))
	if hit.is_critical:
		_show_critical_mark(target)


func _on_owner_died() -> void:
	end_hit_stop()
	if _camera_rig != null:
		_camera_rig.stop_shake()


# --- the critical mark ------------------------------------------------------------------------

## PLACEHOLDER. A word above the target that rises and fades, until damage
## numbers take its place. Parented here — a plain Node, so it stays where it
## was put in the world — and gone with the player at a scene change.
func _show_critical_mark(target: Node) -> void:
	var body: Node3D = target as Node3D
	if body == null or get_child_count() >= data.max_critical_labels:
		return
	var point: Vector3 = body.global_position
	var combatant: RoomCombatant = target as RoomCombatant
	if combatant != null:
		point = combatant.get_target_point()
	var label: Label3D = Label3D.new()
	label.text = data.critical_label_text
	label.modulate = data.critical_label_color
	label.font_size = CRITICAL_LABEL_FONT_SIZE
	label.outline_size = CRITICAL_LABEL_OUTLINE_SIZE
	label.pixel_size = CRITICAL_LABEL_PIXEL_SIZE
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	add_child(label)
	label.position = point + Vector3.UP * data.critical_label_height
	var tween: Tween = label.create_tween().set_parallel()
	tween.tween_property(label, "position:y", label.position.y + data.critical_label_rise,
		data.critical_label_duration).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	for faded in ["modulate:a", "outline_modulate:a"]:
		tween.tween_property(label, faded, 0.0, data.critical_label_duration) \
			.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tween.chain().tween_callback(label.queue_free)


func get_critical_mark_count() -> int:
	return get_child_count()
