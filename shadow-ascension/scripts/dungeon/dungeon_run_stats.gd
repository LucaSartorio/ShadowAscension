class_name DungeonRunStats
extends Node

## What one dungeon run amounted to, for the summary at the end of it.
##
## Deliberately small and deliberately local: a component on the DungeonController,
## counting five things about THIS run and nothing else. It is not an analytics
## service, nothing global reads it, and it keeps no history — a new dungeon
## scene builds a new one, which is what "reset on entry" means here.
##
## Everything is counted from signals the systems already emit. Nothing polls,
## and no system was changed to report to it.

signal stats_changed

var enemies_defeated: int = 0
var bosses_defeated: int = 0
var items_picked_up: int = 0
var shadows_extracted: int = 0

## Total player XP when the run began. The player's share of a kill is what
## lands here — a kill the shadow finished pays the player 30%, and 30% is what
## this reports, because it reads the player's own total rather than the
## enemy's reward.
var _player_xp_at_start: int = 0
var _progression: PlayerProgression = null


func _ready() -> void:
	# One frame: the player and the rooms come up in the same scene as this.
	call_deferred("_subscribe")


func _subscribe() -> void:
	var player: Player = get_tree().get_first_node_in_group("player") as Player
	if player != null:
		_progression = player.progression
		if _progression != null:
			_player_xp_at_start = _progression.get_total_xp()
		if player.shadows != null:
			# Only a successful extraction adds to the collection, so a failed
			# attempt cannot reach this.
			player.shadows.shadow_added.connect(_on_shadow_added)
	var controller: DungeonController = get_parent() as DungeonController
	if controller != null:
		for room in controller.get_rooms():
			for combatant in room.get_enemies():
				combatant.enemy_died.connect(_on_enemy_died)
	# Loot is picked up off the floor, and the floor is stocked while the run is
	# under way, so the items announce themselves as they appear. Counting the
	# inventory instead would also count a piece of equipment being taken off.
	get_tree().node_added.connect(_on_node_added)


func get_player_xp_earned() -> int:
	if _progression == null:
		return 0
	return maxi(0, _progression.get_total_xp() - _player_xp_at_start)


func get_total_kills() -> int:
	return enemies_defeated + bosses_defeated


func _on_enemy_died(combatant: RoomCombatant) -> void:
	if combatant is DungeonBoss:
		bosses_defeated += 1
	else:
		enemies_defeated += 1
	stats_changed.emit()


func _on_node_added(node: Node) -> void:
	var item: WorldItem = node as WorldItem
	if item != null:
		item.picked_up.connect(_on_item_picked_up)


func _on_item_picked_up(_item: ItemData, quantity: int) -> void:
	# Quantity, not stacks: three fragments in one pile are three items.
	items_picked_up += maxi(1, quantity)
	stats_changed.emit()


func _on_shadow_added(_shadow: ShadowInstance) -> void:
	shadows_extracted += 1
	stats_changed.emit()
