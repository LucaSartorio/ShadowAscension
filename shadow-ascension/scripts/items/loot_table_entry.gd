class_name LootTableEntry
extends Resource

## One possible drop. Pure data: whether it lands is decided by LootTable.

@export var item: ItemData
## Independent chance for this entry, 0..1.
@export_range(0.0, 1.0) var drop_chance: float = 0.25
@export var min_quantity: int = 1
@export var max_quantity: int = 1
