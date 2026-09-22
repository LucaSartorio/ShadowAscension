class_name PlayerShadowCommander
extends Node

## The player's orders to the summoned shadow: what mode it fights in, what it
## attacks, and when it breaks off and comes back.
##
## A component on the player, beside the collection and the summoner. The
## collection owns what is HELD, the summoner owns what is OUT, and this owns
## what it is TOLD. The shadow itself never reads input — it is given orders and
## carries them out, which is what lets a test drive it without faking keys.
##
## It also owns the target marker: one node, moved between targets, because a
## marker parented to its subject would die with it.

signal command_issued(action: StringName)
## A command that found nothing to act on. Carried as a signal so the feedback
## lives in the UI layer rather than here.
signal command_rejected(reason: String)

const ACTION_RECALL: StringName = &"shadow_recall"
const ACTION_MODE_TOGGLE: StringName = &"shadow_mode_toggle"
const ACTION_ATTACK_COMMAND: StringName = &"shadow_attack_command"

@export var marker_scene: PackedScene = preload(
	"res://scenes/shadows/shadow_target_marker.tscn")
## How far the aim ray reaches. Beyond this the player is not pointing at
## anything as far as the shadow is concerned.
@export var manual_command_range: float = 25.0
## World (1) plus enemy bodies (4). The world is in the mask on purpose: without
## it the ray would pass through a wall and order an attack on something the
## player cannot see.
@export var command_ray_mask: int = 5
## Where the aim ray starts, above the player's feet. The ray uses the CAMERA's
## direction but the PLAYER's position: starting it at the camera means a wall
## close behind the player eats the order, which is a third-person camera
## artefact and not something the player did. The cost is a little parallax
## against the crosshair, which at this range is not worth the bug.
@export var aim_origin_height: float = 1.5

var _player: Player = null
var _summoner: PlayerShadowSummoner = null
var _marker: ShadowTargetMarker = null
var _shadow: BasicMeleeShadow = null


func _ready() -> void:
	_player = get_parent() as Player
	if _player == null:
		return
	_summoner = _player.get_node_or_null("PlayerShadowSummoner") as PlayerShadowSummoner
	if _summoner == null:
		return
	_summoner.shadow_summoned.connect(_on_shadow_summoned)
	_summoner.shadow_recalled.connect(_on_shadow_gone)
	_summoner.shadow_defeated.connect(_on_shadow_gone)


func _exit_tree() -> void:
	if _marker != null and is_instance_valid(_marker):
		_marker.queue_free()
	_marker = null


# --- queries ---------------------------------------------------------------------

func get_shadow() -> BasicMeleeShadow:
	return _shadow if _shadow != null and is_instance_valid(_shadow) else null


func get_marker() -> ShadowTargetMarker:
	return _marker


func has_shadow() -> bool:
	var shadow: BasicMeleeShadow = get_shadow()
	return shadow != null and not shadow.is_dead()


func get_command_mode() -> BasicMeleeShadow.CommandMode:
	var shadow: BasicMeleeShadow = get_shadow()
	return shadow.command_mode if shadow != null else _stored_mode()


# --- input -------------------------------------------------------------------------

## `_unhandled_input` rather than `_input`, and on a pausable node: an open menu
## pauses the tree, so none of these ever fire behind a UI. Nothing here needs a
## second guard for that.
func _unhandled_input(event: InputEvent) -> void:
	if not has_shadow():
		return
	if event.is_action_pressed(ACTION_MODE_TOGGLE):
		toggle_mode()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(ACTION_RECALL):
		recall_to_player()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(ACTION_ATTACK_COMMAND):
		# Deliberately not gated on a captured mouse the way the light attack
		# is: that gate exists because left-click doubles as "give the window
		# focus back", and the middle button has no such second job.
		issue_attack_command()
		get_viewport().set_input_as_handled()


# --- commands -----------------------------------------------------------------------

func toggle_mode() -> void:
	var shadow: BasicMeleeShadow = get_shadow()
	if shadow == null:
		return
	shadow.toggle_command_mode()
	command_issued.emit(ACTION_MODE_TOGGLE)


func set_mode(mode: BasicMeleeShadow.CommandMode) -> void:
	var shadow: BasicMeleeShadow = get_shadow()
	if shadow == null:
		return
	shadow.set_command_mode(mode)


## "Come back to me". Distinct from the collection menu's Richiama, which
## despawns: this leaves the shadow summoned and only changes what it is doing.
func recall_to_player() -> void:
	var shadow: BasicMeleeShadow = get_shadow()
	if shadow == null:
		return
	shadow.recall_to_player()
	command_issued.emit(ACTION_RECALL)


## Sends the shadow at whatever the player is looking at. Returns the target it
## found, or null — in which case nothing about the shadow's behaviour changes.
func issue_attack_command() -> RoomCombatant:
	var shadow: BasicMeleeShadow = get_shadow()
	if shadow == null:
		return null
	var target: RoomCombatant = _aim_target()
	if target == null:
		command_rejected.emit("Nessun bersaglio")
		return null
	if not shadow.set_manual_target(target):
		# Valid as a thing, but not as an order: out past the leash, most often.
		command_rejected.emit("Bersaglio troppo lontano")
		return null
	command_issued.emit(ACTION_ATTACK_COMMAND)
	return target


## What the camera is pointed at, if it is an enemy. The direction is the
## camera's forward axis, which for a perspective camera IS the screen centre —
## taken from the transform rather than from the viewport, so it behaves
## identically with no window to measure.
func _aim_target() -> RoomCombatant:
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null:
		return null
	var from: Vector3 = _player.global_position + Vector3.UP * aim_origin_height
	var to: Vector3 = from - camera.global_basis.z * manual_command_range
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = command_ray_mask
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var excluded: Array[RID] = []
	if _player != null:
		excluded.append(_player.get_rid())
	var shadow: BasicMeleeShadow = get_shadow()
	if shadow != null:
		excluded.append(shadow.get_rid())
	query.exclude = excluded
	var hit: Dictionary = get_viewport().world_3d.direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return null
	# A wall between the player and an enemy is a miss, not a hit on the enemy
	# behind it — which is the whole reason the world is in the mask.
	var combatant: RoomCombatant = hit["collider"] as RoomCombatant
	if combatant == null or combatant.has_died():
		return null
	return combatant


# --- the shadow coming and going -------------------------------------------------------

func _on_shadow_summoned(_instance: ShadowInstance, node: BasicMeleeShadow) -> void:
	_shadow = node
	node.manual_target_changed.connect(_on_manual_target_changed)
	node.command_mode_changed.connect(_on_command_mode_changed)
	# A shadow that re-summoned itself after a scene change comes back in the
	# mode it was fighting in, rather than reverting on every doorway.
	node.set_command_mode(_stored_mode())


func _on_shadow_gone(_instance: ShadowInstance) -> void:
	_shadow = null
	if _marker != null and is_instance_valid(_marker):
		_marker.clear()


func _on_manual_target_changed(target: RoomCombatant) -> void:
	if target == null:
		if _marker != null and is_instance_valid(_marker):
			_marker.clear()
		return
	_ensure_marker()
	if _marker != null:
		_marker.follow(target)


func _on_command_mode_changed(mode: BasicMeleeShadow.CommandMode) -> void:
	var state: Node = _runtime_state()
	if state != null:
		state.sync_active_shadow_mode(int(mode))


## Built on first use rather than on _ready: a session that never gives an order
## never needs one in the scene.
func _ensure_marker() -> void:
	if _marker != null and is_instance_valid(_marker):
		return
	if marker_scene == null or _player == null:
		return
	_marker = marker_scene.instantiate() as ShadowTargetMarker
	var host: Node = _player.get_parent()
	if host == null:
		host = get_tree().current_scene
	if host == null:
		_marker = null
		return
	host.add_child(_marker)


func _stored_mode() -> BasicMeleeShadow.CommandMode:
	var state: Node = _runtime_state()
	if state == null:
		return BasicMeleeShadow.CommandMode.AGGRESSIVE
	return state.active_shadow_mode as BasicMeleeShadow.CommandMode


func _runtime_state() -> Node:
	return Player.session(self)
