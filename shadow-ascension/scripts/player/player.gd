class_name Player
extends CharacterBody3D

## Every other group in the project is a typed constant on the class that owns
## it; this one was the last bare literal, repeated across 23 call sites.
const GROUP: StringName = &"player"

## The autoload node holding this character's persistent state. A String, not a
## StringName: it is passed where a NodePath is expected, and only String
## converts to one implicitly.
const RUNTIME_STATE_NODE: String = "PlayerRuntimeState"

## Base values. AGI scales these into the `effective_*` fields below; the bases
## themselves are never written to, so a multiplier can never compound.
@export var movement_speed: float = 6.0
@export var acceleration: float = 40.0
@export var deceleration: float = 50.0
@export var rotation_speed: float = 10.0
@export var gravity: float = 20.0

## How fast a dodge carries the body. When a dodge starts, how long it lasts and
## where its i-frames fall are combat's (PlayerCombatData); how it moves is here,
## beside the walking speed, and scales with AGI the same way.
@export var dodge_speed: float = 11.5
@export var dodge_visual_tilt_degrees: float = -15.0
## PLACEHOLDER. How far the model rolls for each attack animation, keyed by the
## animation name an AttackData asks for. It is this scene's stand-in for an
## animation set: M14 replaces it with real clips under the same names, and
## neither the combat nor the attack data changes.
@export var placeholder_attack_tilts: Dictionary[StringName, float] = {}

## Turns with the player's facing, and carries the attack hitbox with it.
@onready var visual_root: Node3D = $VisualRoot
## The placeholder model, and the only node the presentation tilts. The hitbox
## is not under it, so a cosmetic roll never moves where a swing lands.
@onready var visual_model: Node3D = $VisualRoot/Model
@onready var camera_rig: CameraRig = $CameraRig
@onready var attack_hitbox: Hitbox = $VisualRoot/AttackHitbox
@onready var health_component: HealthComponent = $HealthComponent
@onready var hurtbox: Hurtbox = $Hurtbox
@onready var progression: PlayerProgression = $PlayerProgression
@onready var inventory: PlayerInventory = $PlayerInventory
@onready var equipment: PlayerEquipment = $PlayerEquipment
@onready var shadows: PlayerShadowCollection = $PlayerShadowCollection
@onready var shadow_summoner: PlayerShadowSummoner = $PlayerShadowSummoner
@onready var shadow_commander: PlayerShadowCommander = $PlayerShadowCommander
@onready var combat: PlayerCombat = $PlayerCombat

## What the controller actually uses. Recomputed from the base values whenever
## the stats change — never from the previous effective value.
var effective_movement_speed: float
var effective_dodge_speed: float
## The player's own maximum, before VIT. Captured once so raising VIT adds to the
## original ceiling rather than to an already-raised one.
var base_max_health: float = 0.0

var _visual_tween: Tween = null
## Where the current dodge carries the body, fixed when it starts.
var _dodge_direction: Vector3 = Vector3.ZERO


func _ready() -> void:
	add_to_group(GROUP)
	attack_hitbox.source = self
	_wire_components()
	camera_rig.attack_light_pressed.connect(_on_attack_light_pressed)
	camera_rig.attack_heavy_pressed.connect(_on_attack_heavy_pressed)
	combat.attack_started.connect(_on_attack_started)
	base_max_health = health_component.max_health
	if progression != null:
		progression.stats_changed.connect(_apply_stat_effects)
	if equipment != null:
		# Taking a piece off changes max health, movement and damage, so the same
		# recompute runs for equipment as for a spent stat point.
		equipment.equipment_changed.connect(_apply_stat_effects)
	_apply_stat_effects()
	_restore_health()
	health_component.health_changed.connect(_on_health_changed)
	health_component.died.connect(_on_player_died)


## The player is the one place that knows its own layout. Each component is
## handed the siblings it needs here, rather than finding them by name from its
## own _ready() — which runs before this one, so it could only do that by walking
## the scene. Moving a node (the attack hitbox out from under VisualRoot at M13,
## say) is then a change to one @onready line and nothing else.
##
## Runs before this node connects its own handlers, so the components are wired
## in the same order they were when they wired themselves.
func _wire_components() -> void:
	if progression != null:
		progression.setup(attack_hitbox, equipment, shadows, shadow_summoner)
	if equipment != null:
		equipment.setup(inventory)
	if shadow_summoner != null:
		shadow_summoner.setup(self, shadows, health_component)
	if shadow_commander != null:
		shadow_commander.setup(self, shadow_summoner)
	combat.setup(attack_hitbox, hurtbox, health_component, progression)


## The session's persistent player state, or null where there is none.
##
## Looked up by node name rather than through the `PlayerRuntimeState` autoload
## global, and that is not a style choice: a flow test entered through
## `--script` compiles the game's scripts BEFORE the autoloads are registered,
## so the global identifier does not resolve yet and every script that named it
## would fail to compile. The name lives here, once, instead of in each of the
## seven player scripts that need the session.
static func session(from: Node) -> Node:
	return from.get_tree().root.get_node_or_null(RUNTIME_STATE_NODE)


## Health carries across a scene change, so walking through a gate is not a free
## heal. The ceiling is never restored — _apply_stat_effects() has already
## recomputed it from this player's own base plus VIT — only the wound is.
##
## Who owns what: MAX health is derived, never stored — base plus VIT plus
## equipment, recomputed by _apply_stat_effects(). CURRENT health is owned by the
## HealthComponent while the scene runs; the session holds only the value handed
## from one player to the next. A fresh session and a death both hand over
## "full", which is the negative sentinel.
func _restore_health() -> void:
	var state: Node = _runtime_state()
	if state == null:
		return
	if state.wants_full_health():
		health_component.current_health = health_component.max_health
		state.sync_health(health_component.current_health)
		return
	health_component.current_health = clampf(
		state.current_health, 0.0, health_component.max_health)
	# Written straight to the field, which emits nothing, so the session is told
	# explicitly. It matters when the clamp actually bit: without this the stored
	# value would stay above the ceiling it was just clamped to.
	state.sync_health(health_component.current_health)


func _on_health_changed(current: float, _maximum: float) -> void:
	var state: Node = _runtime_state()
	if state != null:
		state.sync_health(current)


## The run restarts, the character does not: the next player comes back at full
## health with its level, XP and stats untouched.
func _on_player_died() -> void:
	var state: Node = _runtime_state()
	if state != null:
		state.reset_health_to_max()


func _runtime_state() -> Node:
	return session(self)


## Recomputes every stat-driven value from its base. Called once at startup and
## again on each stat change — never incrementally, so nothing compounds.
func _apply_stat_effects() -> void:
	if progression == null:
		effective_movement_speed = movement_speed
		effective_dodge_speed = dodge_speed
		return
	effective_movement_speed = movement_speed * progression.get_movement_speed_multiplier()
	effective_dodge_speed = dodge_speed * progression.get_dodge_speed_multiplier()
	# Raises the ceiling without healing: HealthComponent only clamps downwards.
	health_component.set_max_health(base_max_health + progression.get_bonus_max_health())


# --- input: devices in, combat intents out -----------------------------------------------
#
# The only place the player's devices are read. Combat is told what the player
# wants — an attack, a dodge — and decides whether it happens.

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("dodge"):
		_on_dodge_pressed()


func _on_attack_light_pressed() -> void:
	combat.request_light_attack()


func _on_attack_heavy_pressed() -> void:
	combat.request_heavy_attack()


func _on_dodge_pressed() -> void:
	var direction: Vector3 = _compute_dodge_direction()
	if not combat.request_dodge():
		return
	_dodge_direction = direction
	_play_dodge_visual()


## Where the movement keys point, relative to the camera and flat on the ground.
## Never longer than 1, so a diagonal is no faster than a straight line.
func _input_direction() -> Vector3:
	var input_vec: Vector2 = Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	var cam_basis: Basis = camera_rig.global_transform.basis
	var forward: Vector3 = -cam_basis.z
	forward.y = 0.0
	if forward.length() > 0.0001:
		forward = forward.normalized()
	var right: Vector3 = cam_basis.x
	right.y = 0.0
	if right.length() > 0.0001:
		right = right.normalized()
	var direction: Vector3 = forward * -input_vec.y + right * input_vec.x
	if direction.length() > 1.0:
		direction = direction.normalized()
	return direction


# --- movement -----------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if combat.is_dodging():
		_move_dodge(delta)
		return

	var desired_dir: Vector3 = _input_direction()

	var target_horiz: Vector3 = desired_dir * effective_movement_speed * combat.get_movement_multiplier()
	var current_horiz: Vector3 = Vector3(velocity.x, 0.0, velocity.z)
	var accel_rate: float = acceleration if desired_dir.length_squared() > 0.001 else deceleration
	current_horiz = current_horiz.move_toward(target_horiz, accel_rate * delta)
	velocity.x = current_horiz.x
	velocity.z = current_horiz.z

	if is_on_floor():
		if velocity.y < 0.0:
			velocity.y = 0.0
	else:
		velocity.y -= gravity * delta

	move_and_slide()

	if combat.allows_turning() and desired_dir.length_squared() > 0.001:
		var target_yaw: float = atan2(-desired_dir.x, -desired_dir.z)
		var diff: float = wrapf(target_yaw - visual_root.rotation.y, -PI, PI)
		var max_step: float = rotation_speed * delta
		visual_root.rotation.y += clamp(diff, -max_step, max_step)


func _compute_dodge_direction() -> Vector3:
	var dir: Vector3 = _input_direction()
	if dir.length_squared() > 0.001:
		return dir.normalized()
	var facing_back: Vector3 = visual_root.global_transform.basis.z
	facing_back.y = 0.0
	if facing_back.length() < 0.0001:
		facing_back = Vector3(0, 0, 1)
	return facing_back.normalized()


func _move_dodge(delta: float) -> void:
	velocity.x = _dodge_direction.x * effective_dodge_speed
	velocity.z = _dodge_direction.z * effective_dodge_speed
	if is_on_floor():
		if velocity.y < 0.0:
			velocity.y = 0.0
	else:
		velocity.y -= gravity * delta
	move_and_slide()


# --- presentation: what combat did, shown -------------------------------------------------
#
# Combat never plays anything; it says an attack started, and this shows it.
# Everything below is placeholder, replaced by real animation at M14 without
# touching the combat that drives it.

func _on_attack_started(attack: AttackData) -> void:
	_face_aim_direction()
	_play_attack_animation(attack)


## Every attack of the chain turns to the aim when it starts. This is also what
## aims the hitbox, which turns with the facing.
func _face_aim_direction() -> void:
	var aim: Vector3 = _aim_direction()
	if aim == Vector3.ZERO:
		return
	visual_root.rotation.y = atan2(-aim.x, -aim.z)


## Where an attack should go, flat on the ground: the camera's forward. The one
## thing a target lock replaces — the combo and the facing code stay as they are.
func _aim_direction() -> Vector3:
	var forward: Vector3 = -camera_rig.global_transform.basis.z
	forward.y = 0.0
	if forward.length() < 0.0001:
		return Vector3.ZERO
	return forward.normalized()


## The one place an attack is shown. It knows the attack only by its animation
## name; today that name picks a placeholder roll.
func _play_attack_animation(attack: AttackData) -> void:
	if _visual_tween != null and _visual_tween.is_running():
		_visual_tween.kill()
	var tilt: float = deg_to_rad(placeholder_attack_tilts.get(attack.animation, 0.0))
	var to_tilt_time: float = max(0.05, attack.windup + attack.active * 0.5)
	var to_zero_time: float = max(0.05, attack.recovery)
	_visual_tween = create_tween()
	_visual_tween.tween_property(visual_model, "rotation:z", tilt, to_tilt_time)
	_visual_tween.tween_property(visual_model, "rotation:z", 0.0, to_zero_time)


func _play_dodge_visual() -> void:
	if _visual_tween != null and _visual_tween.is_running():
		_visual_tween.kill()
	var duration: float = combat.data.dodge_duration
	var tilt: float = deg_to_rad(dodge_visual_tilt_degrees)
	var to_tilt_time: float = max(0.05, duration * 0.4)
	var to_zero_time: float = max(0.05, duration * 0.6)
	_visual_tween = create_tween()
	_visual_tween.tween_property(visual_model, "rotation:x", tilt, to_tilt_time)
	_visual_tween.tween_property(visual_model, "rotation:x", 0.0, to_zero_time)
