class_name LootTable
extends Resource

## What a combatant can drop. Data-driven so no enemy script ever branches on
## its own type to decide loot.
##
## Each entry rolls independently, so overall drop odds come from the entries
## rather than from a hidden rule here.

@export var entries: Array[LootTableEntry] = []
## Used by the boss: if every entry misses, the rarest one is granted anyway, so
## a boss fight is never worth nothing.
@export var guarantee_at_least_one: bool = false


## Returns `[{ "item": ItemData, "quantity": int }, ...]`. Rolling is the
## caller's decision and happens exactly once — see LootDropper.
func roll(rng: RandomNumberGenerator) -> Array[Dictionary]:
	var drops: Array[Dictionary] = []
	for entry in entries:
		if entry == null or entry.item == null:
			continue
		if rng.randf() > entry.drop_chance:
			continue
		drops.append(_make_drop(entry, rng))
	if drops.is_empty() and guarantee_at_least_one:
		var best: LootTableEntry = _rarest_entry()
		if best != null:
			drops.append(_make_drop(best, rng))
	return drops


func _make_drop(entry: LootTableEntry, rng: RandomNumberGenerator) -> Dictionary:
	var low: int = maxi(1, entry.min_quantity)
	var high: int = maxi(low, entry.max_quantity)
	return {"item": entry.item, "quantity": rng.randi_range(low, high)}


func _rarest_entry() -> LootTableEntry:
	var best: LootTableEntry = null
	for entry in entries:
		if entry == null or entry.item == null:
			continue
		if best == null or entry.item.rarity > best.item.rarity:
			best = entry
	return best
