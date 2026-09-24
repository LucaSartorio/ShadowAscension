class_name LootDropper
extends Node

## Rolls a combatant's loot table when it dies and scatters the results on the
## floor. A component, so the combatant itself never learns what it is worth —
## the same split as XP.
##
## RoomCombatant.report_death() fires its hook exactly once however the death was
## reached, and this node also latches, so a duplicated signal, a boss phase
## transition, a room clearing or a dungeon completing cannot roll a second time.

@export var loot_table: LootTable
@export var world_item_scene: PackedScene
## Drops land in a small ring around the corpse rather than inside it.
@export var scatter_radius: float = 0.9
@export var drop_height: float = 0.05
## Base seed. It is mixed with this dropper's own scene path before use: sharing
## one seed across every instance would make an entire room drop identically,
## which is degenerate rather than deterministic. The path is stable between
## runs, so a given enemy still rolls the same thing every time.
@export var drop_seed: int = 20260921

var _rolled: bool = false
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _combatant: RoomCombatant = null


func _ready() -> void:
	_rng.seed = drop_seed ^ hash(String(get_path()))
	_combatant = get_parent() as RoomCombatant
	if _combatant == null:
		push_warning("%s expects to be a child of a RoomCombatant." % name)
		return
	_combatant.enemy_died.connect(_on_died)


func has_rolled() -> bool:
	return _rolled


## Public so a test can roll deterministically without killing anything.
func drop_now() -> Array[Dictionary]:
	if _rolled or loot_table == null or world_item_scene == null or _combatant == null:
		return []
	_rolled = true
	var drops: Array[Dictionary] = loot_table.roll(_rng)
	for i in drops.size():
		_spawn(drops[i], i, drops.size())
	return drops


func _on_died(_dead: RoomCombatant) -> void:
	drop_now()


func _spawn(drop: Dictionary, index: int, total: int) -> void:
	var parent: Node = _combatant.get_parent()
	if parent == null:
		return
	var world_item: WorldItem = world_item_scene.instantiate() as WorldItem
	world_item.configure(drop["item"], drop["quantity"])
	parent.add_child(world_item)
	# Spread around the corpse, and never below it: the corpse is standing on
	# the floor, so its own Y is the floor.
	var angle: float = TAU * (float(index) / float(maxi(1, total))) + _rng.randf() * 0.6
	var offset: Vector3 = Vector3(cos(angle), 0.0, sin(angle)) * scatter_radius
	world_item.global_position = _combatant.global_position + offset + Vector3(0.0, drop_height, 0.0)
