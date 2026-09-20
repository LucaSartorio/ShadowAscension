class_name ItemData
extends Resource

## One item definition. Instances live under `resources/items/` as `.tres`.
##
## Pure data: an item describes itself and nothing else. What rarity *means*
## mechanically is not decided here — M7.1 only displays it. Equipment
## modifiers arrive in M7.2.

enum Rarity { COMMON, UNCOMMON, RARE, EPIC, LEGENDARY }
enum ItemType { MATERIAL, CONSUMABLE, WEAPON, ARMOR }
## Where an item can be worn. NONE covers everything that cannot be.
enum EquipmentSlot { NONE, MAIN_HAND, CHEST }

@export var id: StringName = &""
@export var display_name: String = "Item"
@export_multiline var description: String = ""
@export var rarity: Rarity = Rarity.COMMON
@export var item_type: ItemType = ItemType.MATERIAL
## Stackable items share one stack capped at max_stack. Everything else
## accumulates a count without a cap — see PlayerInventory.
@export var stackable: bool = true
@export var max_stack: int = 99

@export_group("Equipment")
## NONE for anything that is not worn. A weapon belongs in MAIN_HAND and a piece
## of armour in CHEST; nothing enforces that beyond what each asset declares.
@export var equipment_slot: EquipmentSlot = EquipmentSlot.NONE
## Added to the player's allocated stats while this is worn. Never written into
## those stats — see PlayerEquipment.
@export var bonus_strength: int = 0
@export var bonus_agility: int = 0
@export var bonus_vitality: int = 0
@export var bonus_intelligence: int = 0
## Flat damage added to every melee swing before the STR multiplier applies.
## Only a main-hand item contributes it.
@export var melee_attack_power: float = 0.0


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


func is_equippable() -> bool:
	return equipment_slot != EquipmentSlot.NONE


static func slot_label(value: EquipmentSlot) -> String:
	match value:
		EquipmentSlot.MAIN_HAND:
			return "Main Hand"
		EquipmentSlot.CHEST:
			return "Chest"
	return "-"


func get_slot_label() -> String:
	return slot_label(equipment_slot)


## The bonus lines this item contributes, ready to print. Empty for anything
## that is not worn, so a material's detail pane simply has nothing to show.
func get_bonus_lines() -> Array[String]:
	var lines: Array[String] = []
	if bonus_strength != 0:
		lines.append("%+d STR" % bonus_strength)
	if bonus_agility != 0:
		lines.append("%+d AGI" % bonus_agility)
	if bonus_vitality != 0:
		lines.append("%+d VIT" % bonus_vitality)
	if bonus_intelligence != 0:
		lines.append("%+d INT" % bonus_intelligence)
	if not is_zero_approx(melee_attack_power):
		lines.append("%+d Melee Attack Power" % roundi(melee_attack_power))
	return lines


func get_rarity_color() -> Color:
	return rarity_color(rarity)


func get_rarity_label() -> String:
	return rarity_label(rarity)


func get_type_label() -> String:
	return type_label(item_type)
