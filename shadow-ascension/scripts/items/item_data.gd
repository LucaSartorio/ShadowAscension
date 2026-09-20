class_name ItemData
extends Resource

## One item definition. Instances live under `resources/items/` as `.tres`.
##
## Pure data: an item describes itself and nothing else. What rarity *means*
## mechanically is not decided here — M7.1 only displays it. Equipment
## modifiers arrive in M7.2.

enum Rarity { COMMON, UNCOMMON, RARE, EPIC, LEGENDARY }
## WEAPON and ARMOR exist as types in M7.1 but are not equippable yet.
enum ItemType { MATERIAL, CONSUMABLE, WEAPON, ARMOR }

@export var id: StringName = &""
@export var display_name: String = "Item"
@export_multiline var description: String = ""
@export var rarity: Rarity = Rarity.COMMON
@export var item_type: ItemType = ItemType.MATERIAL
## Stackable items share one stack capped at max_stack. Everything else
## accumulates a count without a cap — see PlayerInventory.
@export var stackable: bool = true
@export var max_stack: int = 99


## Presentation for a rarity, kept in one place so the world drop, the tooltip
## and the inventory list can never disagree about what "Rare" looks like.
static func rarity_color(value: Rarity) -> Color:
	match value:
		Rarity.UNCOMMON:
			return Color(0.45, 0.85, 0.45)
		Rarity.RARE:
			return Color(0.4, 0.65, 1.0)
		Rarity.EPIC:
			return Color(0.75, 0.5, 1.0)
		Rarity.LEGENDARY:
			return Color(1.0, 0.7, 0.25)
	return Color(0.82, 0.84, 0.88)


static func rarity_label(value: Rarity) -> String:
	match value:
		Rarity.UNCOMMON:
			return "Uncommon"
		Rarity.RARE:
			return "Rare"
		Rarity.EPIC:
			return "Epic"
		Rarity.LEGENDARY:
			return "Legendary"
	return "Common"


static func type_label(value: ItemType) -> String:
	match value:
		ItemType.CONSUMABLE:
			return "Consumable"
		ItemType.WEAPON:
			return "Weapon"
		ItemType.ARMOR:
			return "Armor"
	return "Material"


func get_rarity_color() -> Color:
	return rarity_color(rarity)


func get_rarity_label() -> String:
	return rarity_label(rarity)


func get_type_label() -> String:
	return type_label(item_type)
