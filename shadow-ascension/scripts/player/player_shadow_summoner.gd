class_name PlayerShadowSummoner
extends Node

## Puts one shadow from the collection into the world, and takes it back.
##
## A component on the player, beside the collection: the collection owns what is
## held, this owns what is out. One at a time — summoning a second recalls the
## first, so "max one active" is a rule of this node rather than a check every
## caller has to remember.
##
## The summoned entity is spawned beside the player but parented to the scene,
## not to the player, so it moves under its own power.

signal shadow_summoned(shadow: ShadowInstance, node: BasicMeleeShadow)
signal shadow_recalled(shadow: ShadowInstance)
## The entity was killed. Separate from `shadow_recalled`, which is the player's
## own choice: a death is worth different feedback.
signal shadow_defeated(shadow: ShadowInstance)
signal active_shadow_changed(instance_id: StringName)

## Where it appears relative to the player, before it starts following.
@export var summon_offset: Vector3 = Vector3(1.2, 0.0, 1.2)

var _collection: PlayerShadowCollection = null
var _player: Player = null
var _active_node: BasicMeleeShadow = null
var _active_id: StringName = &""


func _ready() -> void:
	# One frame, so the scene (and its navigation map) is up before anything is
	# placed in it — and so the player has handed over its pieces by then.
	call_deferred("_restore_active")


## Called once by the player with what this needs: the player itself (the owner
## every summoned shadow is bound to), the collection it summons from, and the
## health whose death sends the shadow back.
func setup(player: Player, collection: PlayerShadowCollection,
		health: HealthComponent) -> void:
	_player = player
	_collection = collection
	if _collection != null:
		# A shadow that is dismissed from the collection cannot stay in the world.
		_collection.shadow_removed.connect(_on_shadow_removed)
		# A level earned mid-fight has to reach the entity that is fighting, or
		# the health it just bought would only appear on the next summon.
		_collection.shadow_leveled_up.connect(_on_shadow_leveled_up)
	if health != null:
		health.died.connect(_on_player_died)


# --- queries ---------------------------------------------------------------------

func get_active_instance_id() -> StringName:
	return _active_id


func get_active_node() -> BasicMeleeShadow:
	return _active_node


func has_active_shadow() -> bool:
	return _active_node != null and is_instance_valid(_active_node) and not _active_node.is_dead()


func is_active(instance_id: StringName) -> bool:
	return has_active_shadow() and _active_id == instance_id


# --- summoning ----------------------------------------------------------------------

## Returns the entity, or null when it could not be summoned (unknown id, no
## summon scene, nowhere to put it).
func summon(instance_id: StringName) -> BasicMeleeShadow:
	if _collection == null or _player == null:
		return null
	var shadow: ShadowInstance = _collection.get_shadow(instance_id)
	if shadow == null or shadow.shadow_data == null:
		return null
	var scene: PackedScene = shadow.shadow_data.summon_scene
	if scene == null:
		return null
	var host: Node = _spawn_host()
	if host == null:
		return null

	# Summoning is also how you swap: whatever is out goes back first.
	recall()

	var node: BasicMeleeShadow = scene.instantiate() as BasicMeleeShadow
	if node == null:
		return null
	# Bound before entering the tree, so its first frame already has the health
	# and damage its level says it should, and already knows whose shadow it is.
	node.bind(shadow, _player)
	host.add_child(node)
	node.global_position = _player.global_position + _spawn_offset()
	node.shadow_died.connect(_on_shadow_node_died)

	_active_node = node
	_set_active_id(instance_id)
	shadow_summoned.emit(shadow, node)
	return node


## Takes the active shadow back. Safe to call with nothing out.
func recall() -> bool:
	if _active_node == null or not is_instance_valid(_active_node):
		_active_node = null
		if _active_id != &"":
			_set_active_id(&"")
		return false
	var shadow: ShadowInstance = _active_node.instance
	var node: BasicMeleeShadow = _active_node
	_active_node = null
	_set_active_id(&"")
	# Disconnected first: this is a recall, not a death, and the death handler
	# would otherwise fire and report it as one.
	if node.shadow_died.is_connected(_on_shadow_node_died):
		node.shadow_died.disconnect(_on_shadow_node_died)
	node.queue_free()
	shadow_recalled.emit(shadow)
	return true


## What the UI's one button does: summon it, or take it back if it is already out.
func toggle(instance_id: StringName) -> void:
	if is_active(instance_id):
		recall()
	else:
		summon(instance_id)


# --- session ------------------------------------------------------------------------

## After a scene change the shadow that was out comes back on its own. The player
## asked for it once; walking through a gate is not a reason to ask again.
func _restore_active() -> void:
	var state: Node = _runtime_state()
	if state == null:
		return
	var wanted: StringName = state.active_shadow_instance_id
	if wanted == &"":
		return
	if summon(wanted) == null:
		# The shadow is gone (dismissed, or its data failed to load). Forget it
		# rather than retrying on every scene for the rest of the session.
		_set_active_id(&"")


func _set_active_id(instance_id: StringName) -> void:
	if _active_id == instance_id:
		return
	_active_id = instance_id
	var state: Node = _runtime_state()
	if state != null:
		state.sync_active_shadow(instance_id)
	active_shadow_changed.emit(instance_id)


func _spawn_host() -> Node:
	if _player == null:
		return null
	var host: Node = _player.get_parent()
	if host != null:
		return host
	return get_tree().current_scene


## Offset rotated behind the player, so it never appears in front of a swing.
func _spawn_offset() -> Vector3:
	var yaw: float = _player.visual_root.rotation.y if _player.visual_root != null else 0.0
	return Vector3(summon_offset.x, summon_offset.y, summon_offset.z).rotated(Vector3.UP, yaw)


# --- reactions -------------------------------------------------------------------------

## A dead shadow does not come back by itself: it stays in the collection, and
## the player has to summon it again.
func _on_shadow_node_died(node: BasicMeleeShadow) -> void:
	if node != _active_node:
		return
	var shadow: ShadowInstance = node.instance
	_active_node = null
	_set_active_id(&"")
	shadow_defeated.emit(shadow)


## The player died. Clearing the id is what stops the next scene from summoning
## it again — the run restarts without a shadow already out.
func _on_player_died() -> void:
	recall()
	_set_active_id(&"")


## Only the one that is out, and only through apply_level(), which recomputes
## from the level rather than adding to what is already there.
func _on_shadow_leveled_up(shadow: ShadowInstance, _levels: int) -> void:
	if shadow == null or not is_active(shadow.instance_id):
		return
	_active_node.apply_level()


func _on_shadow_removed(shadow: ShadowInstance) -> void:
	if shadow != null and _active_id == shadow.instance_id:
		recall()


func _runtime_state() -> Node:
	return Player.session(self)
