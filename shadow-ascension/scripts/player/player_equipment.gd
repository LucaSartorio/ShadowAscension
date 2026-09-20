class_name PlayerEquipment
extends Node

## What the player is wearing. A component on the player, like the inventory and
## the progression it sits beside.
##
## It is the source of truth for *equipment bonuses only*. The allocated stats
## stay in PlayerProgression and are never written to: a bonus is added when the
## stats layer asks for an effective value, so taking a piece off can never leave
## a stat permanently inflated.
##
## Items move rather than being copied. Equipping takes one out of the inventory,
## unequipping puts it back, and a swap does both — so the same item is never in
## a slot and in the bag at once.

signal equipment_changed

## Nothing is worn in this slot.
const EMPTY: ItemData = null

@export var inventory: PlayerInventory

## EquipmentSlot -> ItemData. A slot with nothing in it is simply absent.
var _slots: Dictionary = {}


func _ready() -> void:
	if inventory == null:
		inventory = get_parent().get_node_or_null("PlayerInventory") as PlayerInventory
	_restore()


# --- queries ---------------------------------------------------------------------

func get_equipped_item(slot: ItemData.EquipmentSlot) -> ItemData:
	return _slots.get(slot, EMPTY)


func is_slot_occupied(slot: ItemData.EquipmentSlot) -> bool:
	return _slots.has(slot)


func is_equipped(id: StringName) -> bool:
	for slot in _slots:
		if (_slots[slot] as ItemData).id == id:
			return true
	return false


func get_occupied_slots() -> Array[ItemData.EquipmentSlot]:
	var slots: Array[ItemData.EquipmentSlot] = []
	for slot in _slots:
		slots.append(slot)
	return slots


# --- bonuses ----------------------------------------------------------------------

func get_bonus_strength() -> int:
	return _sum("bonus_strength")


func get_bonus_agility() -> int:
	return _sum("bonus_agility")


func get_bonus_vitality() -> int:
	return _sum("bonus_vitality")


func get_bonus_intelligence() -> int:
	return _sum("bonus_intelligence")


## Only the main hand contributes attack power. An empty hand is 0, and combat
## keeps working unarmed.
func get_melee_attack_power() -> float:
	var weapon: ItemData = get_equipped_item(ItemData.EquipmentSlot.MAIN_HAND)
	return weapon.melee_attack_power if weapon != null else 0.0


func _sum(field: StringName) -> int:
	var total: int = 0
	for slot in _slots:
		total += (_slots[slot] as ItemData).get(field)
	return total


# --- equip / unequip ----------------------------------------------------------------

## Moves an item out of the inventory and into its slot, returning whatever was
## already there. Nothing is lost on any path: the item is only placed after the
## inventory has actually given it up, and the displaced piece goes straight back.
func equip(item: ItemData) -> bool:
	if item == null or not item.is_equippable() or inventory == null:
		return false
	if not inventory.has_item(item.id):
		return false
	if not inventory.remove_item(item.id, 1):
		return false
	var slot: ItemData.EquipmentSlot = item.equipment_slot
	var displaced: ItemData = get_equipped_item(slot)
	_slots[slot] = item
	if displaced != null:
		inventory.add_item(displaced, 1)
	_sync()
	equipment_changed.emit()
	return true


func unequip_slot(slot: ItemData.EquipmentSlot) -> bool:
	if not _slots.has(slot) or inventory == null:
		return false
	var item: ItemData = _slots[slot]
	_slots.erase(slot)
	inventory.add_item(item, 1)
	_sync()
	equipment_changed.emit()
	return true


func clear() -> void:
	if _slots.is_empty():
		return
	_slots.clear()
	_sync()
	equipment_changed.emit()


# --- session persistence -------------------------------------------------------------

## Only what is worn travels. Bonuses, effective stats and everything derived
## from them are recomputed on the far side, never restored.
func _restore() -> void:
	var state: Node = _runtime_state()
	if state == null:
		return
	_slots = state.get_equipment_copy()


func _sync() -> void:
	var state: Node = _runtime_state()
	if state != null:
		state.sync_equipment(_slots)


func _runtime_state() -> Node:
	return get_tree().root.get_node_or_null("PlayerRuntimeState")
