class_name PlayerInventory
extends Node

## What the player is carrying. A component on the player, not part of its
## controller — the same split as PlayerProgression.
##
## M7.1 model: one stack per item, `item id -> quantity`, with no capacity limit
## on the inventory itself. A stackable item is capped at its own `max_stack`;
## anything else (weapons, armour) accumulates a plain count, since M7.1 has no
## per-instance stats to keep apart. Multi-slot stacks, durability and affixes
## are deliberately out of scope.
##
## The contents survive a scene change through PlayerRuntimeState, which stores
## them and nothing more — every rule below stays here.

signal item_added(item: ItemData, quantity: int)
signal item_removed(item: ItemData, quantity: int)
## Fired after any change, so the UI redraws once instead of listening to both.
signal inventory_changed

## id -> { "item": ItemData, "quantity": int }
var _stacks: Dictionary = {}


func _ready() -> void:
	_restore()


# --- queries -------------------------------------------------------------------

func has_item(id: StringName) -> bool:
	return _stacks.has(id)


func get_quantity(id: StringName) -> int:
	return _stacks[id]["quantity"] if _stacks.has(id) else 0


func get_item(id: StringName) -> ItemData:
	return _stacks[id]["item"] if _stacks.has(id) else null


func is_empty() -> bool:
	return _stacks.is_empty()


func get_distinct_count() -> int:
	return _stacks.size()


## Sorted so the list reads the same every time it is opened: rarest first, then
## by name. Returns copies of the rows, not the storage.
func get_entries() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for id in _stacks:
		rows.append({
			"id": id,
			"item": _stacks[id]["item"],
			"quantity": _stacks[id]["quantity"],
		})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var item_a: ItemData = a["item"]
		var item_b: ItemData = b["item"]
		if item_a.rarity != item_b.rarity:
			return item_a.rarity > item_b.rarity
		return item_a.display_name < item_b.display_name)
	return rows


# --- mutation ------------------------------------------------------------------

## Adds what fits and returns how much was actually taken, so a caller holding a
## dropped stack can leave the remainder on the floor instead of losing it.
func add_item(item: ItemData, quantity: int = 1) -> int:
	if item == null or quantity <= 0:
		return 0
	var current: int = get_quantity(item.id)
	var accepted: int = quantity
	if item.stackable:
		var room: int = maxi(0, item.max_stack - current)
		accepted = mini(quantity, room)
	if accepted <= 0:
		return 0
	_stacks[item.id] = {"item": item, "quantity": current + accepted}
	_sync()
	item_added.emit(item, accepted)
	inventory_changed.emit()
	return accepted


## Removes up to `quantity`. Returns false and changes nothing when the stack
## cannot cover it, so a caller never half-spends.
func remove_item(id: StringName, quantity: int = 1) -> bool:
	if quantity <= 0 or not _stacks.has(id):
		return false
	var current: int = get_quantity(id)
	if current < quantity:
		return false
	var item: ItemData = get_item(id)
	if current == quantity:
		_stacks.erase(id)
	else:
		_stacks[id]["quantity"] = current - quantity
	_sync()
	item_removed.emit(item, quantity)
	inventory_changed.emit()
	return true


func clear() -> void:
	if _stacks.is_empty():
		return
	_stacks.clear()
	_sync()
	inventory_changed.emit()


# --- session persistence --------------------------------------------------------

## Picks up whatever the last player was carrying. Items already collected
## survive a scene change; items still lying on a floor do not, which is the
## intended behaviour for M7.1.
func _restore() -> void:
	var state: Node = _runtime_state()
	if state == null:
		return
	_stacks = state.get_inventory_copy()


func _sync() -> void:
	var state: Node = _runtime_state()
	if state != null:
		state.sync_inventory(_stacks)


func _runtime_state() -> Node:
	return get_tree().root.get_node_or_null("PlayerRuntimeState")
