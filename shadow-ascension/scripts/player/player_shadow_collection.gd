class_name PlayerShadowCollection
extends Node

## Every shadow the player has torn loose. A component on the player, beside the
## inventory and the equipment.
##
## It holds ShadowInstance objects rather than a count per type, because each
## extraction is its own thing and carries its own level and XP. Minting
## the ids is this node's job; the session only remembers where the counter got
## to, so two scenes can never hand out the same number.

signal shadow_added(shadow: ShadowInstance)
signal shadow_removed(shadow: ShadowInstance)
signal shadow_xp_gained(shadow: ShadowInstance, amount: int)
## Emitted once per award, with how many levels it covered, so a burst of XP
## produces one message rather than one per level.
signal shadow_leveled_up(shadow: ShadowInstance, levels: int)
## Fired after any change, so a UI redraws once instead of listening to both.
signal collection_changed

const ID_PREFIX: String = "shadow_"
const ID_DIGITS: int = 6

var _shadows: Array[ShadowInstance] = []


func _ready() -> void:
	_restore()


# --- queries ---------------------------------------------------------------------

func get_shadows() -> Array[ShadowInstance]:
	return _shadows.duplicate()


func get_count() -> int:
	return _shadows.size()


func is_empty() -> bool:
	return _shadows.is_empty()


func get_shadow(instance_id: StringName) -> ShadowInstance:
	for shadow in _shadows:
		if shadow.instance_id == instance_id:
			return shadow
	return null


func has_shadow(instance_id: StringName) -> bool:
	return get_shadow(instance_id) != null


## How many of one type are held, for a future roster that groups them.
func count_of_type(data_id: StringName) -> int:
	var total: int = 0
	for shadow in _shadows:
		if shadow.get_data_id() == data_id:
			total += 1
	return total


# --- mutation ----------------------------------------------------------------------

## Mints an id and keeps the shadow. Returns the instance so the caller can name
## it in its feedback.
func add_shadow(data: ShadowData) -> ShadowInstance:
	if data == null:
		return null
	var shadow: ShadowInstance = ShadowInstance.new(_mint_id(), data)
	_shadows.append(shadow)
	_sync()
	shadow_added.emit(shadow)
	collection_changed.emit()
	return shadow


func remove_shadow(instance_id: StringName) -> bool:
	for i in _shadows.size():
		if _shadows[i].instance_id != instance_id:
			continue
		var shadow: ShadowInstance = _shadows[i]
		_shadows.remove_at(i)
		_sync()
		shadow_removed.emit(shadow)
		collection_changed.emit()
		return true
	return false


## XP goes to one named shadow, not to the collection: only the one that struck
## the killing blow earns it. Returns the levels gained.
func award_xp(instance_id: StringName, amount: int) -> int:
	if amount <= 0:
		return 0
	var shadow: ShadowInstance = get_shadow(instance_id)
	if shadow == null:
		return 0
	var levels: int = shadow.add_xp(amount)
	_sync()
	shadow_xp_gained.emit(shadow, amount)
	if levels > 0:
		shadow_leveled_up.emit(shadow, levels)
	collection_changed.emit()
	return levels


func clear() -> void:
	if _shadows.is_empty():
		return
	_shadows.clear()
	_sync()
	collection_changed.emit()


## The counter lives in the session, not here: a new scene builds a new
## collection, and without that the numbering would restart and collide.
func _mint_id() -> StringName:
	var state: Node = _runtime_state()
	var index: int = 1
	if state != null:
		index = state.take_next_shadow_index()
	return StringName(ID_PREFIX + str(index).pad_zeros(ID_DIGITS))


# --- session persistence ---------------------------------------------------------------

func _restore() -> void:
	var state: Node = _runtime_state()
	if state == null:
		return
	_shadows.clear()
	for row in state.shadows:
		_shadows.append(ShadowInstance.new(
			row["instance_id"],
			row["shadow_data"],
			row.get("level", 1),
			row.get("current_xp", 0)))


func _sync() -> void:
	var state: Node = _runtime_state()
	if state == null:
		return
	var rows: Array[Dictionary] = []
	for shadow in _shadows:
		rows.append({
			"instance_id": shadow.instance_id,
			"shadow_data": shadow.shadow_data,
			"level": shadow.level,
			"current_xp": shadow.current_xp,
		})
	state.sync_shadows(rows)


func _runtime_state() -> Node:
	return get_tree().root.get_node_or_null("PlayerRuntimeState")
