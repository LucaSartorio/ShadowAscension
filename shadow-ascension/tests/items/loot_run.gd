extends SceneTree

## M7.1 end to end with REAL scene changes and REAL combat: the loop the brief
## asks for, from an empty inventory to one that survives two dungeon runs and a
## death.
##
##   godot --headless --path . --script res://tests/items/loot_run.gd
##
## Enemy combat happens in the dungeon's first room, because the test world has
## no enemies in it — the health bars are observed there.

const HUB: String = "res://scenes/core/hub.tscn"
const DUNGEON: String = "res://scenes/dungeons/dungeon_test.tscn"
const ROOM_ANCHORS: Array[Vector3] = [
	Vector3(0, 0.1, -13), Vector3(0, 0.1, -33), Vector3(0, 0.1, -53)
]
const EXIT_POS: Vector3 = Vector3(0, 0.1, -65)
const STRIKE_RANGE: float = 1.6

var _pass: int = 0
var _fail: int = 0


func _initialize() -> void:
	var state: Node = root.get_node_or_null("PlayerRuntimeState")
	state.reset_runtime_state()

	change_scene_to_file(HUB)
	await _pause(0.6)

	var player: Player = current_scene.get_node("Player")
	_record(player.inventory != null and player.inventory.is_empty(),
		"1) a new session starts with an empty inventory")
	_record((current_scene.get_node("InventoryMenu") as InventoryMenu).hint.visible,
		"2) the '[I] Inventario' hint is on screen")

	# --- into the dungeon
	var gate: DungeonGate = current_scene.get_node("DungeonGate")
	player.global_position = gate.global_position
	await _pause(0.3)
	gate.activate()
	await _pause(1.0)
	_record(current_scene.scene_file_path == DUNGEON, "3) the gate loaded the dungeon")

	var dungeon: DungeonController = current_scene as DungeonController
	var p: Player = current_scene.get_node("Player")
	p.hurtbox.set_invulnerable(true)

	# --- room 1: real combat, and the bars that go with it
	p.global_position = ROOM_ANCHORS[0]
	await _pause(0.6)
	var room1: RoomController = dungeon.get_rooms()[0]
	var first: RoomCombatant = room1.get_enemies()[0]
	var bar: EnemyHealthBar3D = first.get_node("EnemyHealthBar3D")
	_record(bar.is_bar_visible(), "4) the enemy's health bar appeared when it engaged")

	await _swing_once(p, first)
	_record(bar.get_ratio() < 1.0,
		"5) a real hit moved it to %.2f" % bar.get_ratio())

	var collected: int = 0
	for i in 2:
		collected += await _clear_room(dungeon, p, i)
	_record(collected > 0, "6/7) %d drops collected across both combat rooms" % collected)
	_record(not p.inventory.is_empty(),
		"8) the inventory holds %d distinct items: %s" % [
			p.inventory.get_distinct_count(), _summary(p.inventory)])

	var menu: InventoryMenu = current_scene.get_node("InventoryMenu")
	menu.open()
	_record(menu.get_row_count() == p.inventory.get_distinct_count() and not menu.is_empty_shown(),
		"9) the inventory menu lists all %d of them" % menu.get_row_count())
	menu.close()

	# --- the boss, and its guaranteed drop
	p.global_position = ROOM_ANCHORS[2]
	await _pause(0.6)
	var boss: DungeonBoss = dungeon.get_rooms()[2].get_enemies()[0] as DungeonBoss
	_record(boss.get_node_or_null("EnemyHealthBar3D") == null,
		"10) the boss has no world-space bar, only its own")
	var before_boss: int = _count_world_items(dungeon)
	await _kill(p, boss, 60.0)
	await _pause(1.0)
	var boss_drops: int = _count_world_items(dungeon) - before_boss
	_record(boss_drops >= 1, "11) the boss dropped %d item(s) — guaranteed" % boss_drops)

	var best: int = -1
	for world_item in _world_items(dungeon):
		best = maxi(best, world_item.item.rarity)
	_record(best >= ItemData.Rarity.UNCOMMON,
		"12) its best drop is %s or better" % ItemData.rarity_label(best))

	var picked: int = await _collect_nearby(p, dungeon)
	_record(picked > 0, "13) %d boss drop(s) picked up" % picked)
	_record(dungeon.get_state() == DungeonController.DungeonState.COMPLETED,
		"14) the dungeon completed")
	p.hurtbox.set_invulnerable(false)

	var in_dungeon: Dictionary = _snapshot(p.inventory)
	print("[IN DUNGEON ] %s" % [in_dungeon])

	# --- out, and back again
	p.global_position = EXIT_POS
	await _pause(0.4)
	dungeon.exit_portal.activate()
	await _pause(1.2)
	_record(current_scene.scene_file_path == HUB, "15) the portal returned home")
	var p2: Player = current_scene.get_node("Player")
	var home: Dictionary = _snapshot(p2.inventory)
	print("[BACK HOME  ] %s" % [home])
	_record(home == in_dungeon, "16/17) the inventory survived the exit unchanged")

	var gate2: DungeonGate = current_scene.get_node("DungeonGate")
	p2.global_position = gate2.global_position
	await _pause(0.3)
	gate2.activate()
	await _pause(1.0)
	var p3: Player = current_scene.get_node("Player")
	var second: Dictionary = _snapshot(p3.inventory)
	print("[SECOND RUN ] %s" % [second])
	_record(second == in_dungeon, "18) and the second run starts with it intact")
	_record(p3 != p2, "18b) on a different Player instance")

	# --- items left on the floor do not follow; collected ones do
	_record(_count_world_items(current_scene as DungeonController) == 0,
		"19) items left on a floor do not follow a scene change (%d found)" % [
			_count_world_items(current_scene as DungeonController)])

	# --- death keeps everything
	var dungeon2: DungeonController = current_scene as DungeonController
	p3.global_position = ROOM_ANCHORS[0]
	await _pause(0.4)
	p3.health_component.take_damage(DamageInfo.new(1000.0))
	await _pause(0.3)
	_record(dungeon2.get_state() == DungeonController.DungeonState.FAILED, "20) the run failed")
	await _pause(2.5)
	var p4: Player = current_scene.get_node("Player")
	var after_death: Dictionary = _snapshot(p4.inventory)
	print("[AFTER DEATH] %s" % [after_death])
	_record(after_death == in_dungeon, "21) dying costs no items")

	# --- and an explicit fresh session does clear it
	state.reset_runtime_state()
	p4.inventory.clear()
	_record(state.inventory.is_empty() and p4.inventory.is_empty(),
		"22) reset_runtime_state() empties the inventory when asked")

	print("[SUMMARY] passed=%d failed=%d" % [_pass, _fail])
	await _pause(0.3)
	quit()


## M9.1: completing the dungeon opens the run summary, which pauses the tree
## until the player dismisses it. A headless flow has no player, so it does
## what one would — the summary itself is covered by vertical_slice_run.gd.
func _pause(t: float) -> void:
	RunSummary.dismiss_open(self)
	await create_timer(t).timeout


func _record(passed: bool, description: String) -> void:
	if passed:
		_pass += 1
		print("[PASS] " + description)
	else:
		_fail += 1
		print("[FAIL] " + description)


func _snapshot(inventory: PlayerInventory) -> Dictionary:
	var out: Dictionary = {}
	for entry in inventory.get_entries():
		out[String(entry["id"])] = entry["quantity"]
	return out


func _summary(inventory: PlayerInventory) -> String:
	var parts: Array[String] = []
	for entry in inventory.get_entries():
		parts.append("%s x%d" % [(entry["item"] as ItemData).display_name, entry["quantity"]])
	return ", ".join(parts)


func _world_items(from: Node) -> Array[WorldItem]:
	var found: Array[WorldItem] = []
	_collect(from, found)
	return found


func _collect(node: Node, into: Array[WorldItem]) -> void:
	var world_item: WorldItem = node as WorldItem
	if world_item != null and is_instance_valid(world_item):
		into.append(world_item)
	for child in node.get_children():
		_collect(child, into)


func _count_world_items(from: Node) -> int:
	return _world_items(from).size()


func _swing_once(player: Player, target: RoomCombatant) -> void:
	player.global_position = target.global_position + Vector3(0, 0, STRIKE_RANGE)
	player.camera_rig.rotation.y = 0.0
	player.camera_rig.attack_light_pressed.emit()
	await _pause(0.5)


## Kills every enemy in a room with the player's own combo, then picks up what
## fell. Returns how many drops were collected.
func _clear_room(dungeon: DungeonController, player: Player, index: int) -> int:
	player.global_position = ROOM_ANCHORS[index]
	await _pause(0.5)
	for enemy in dungeon.get_rooms()[index].get_enemies():
		await _kill(player, enemy)
		await _pause(0.3)
	return await _collect_nearby(player, dungeon)


func _collect_nearby(player: Player, from: Node) -> int:
	var taken: int = 0
	for world_item in _world_items(from):
		if not is_instance_valid(world_item):
			continue
		player.global_position = world_item.global_position + Vector3(0, 0, 0.5)
		await _pause(0.35)
		if world_item.pick_up():
			taken += 1
		await _pause(0.1)
	return taken


func _kill(player: Player, target: RoomCombatant, budget: float = 20.0) -> int:
	var swings: int = 0
	var elapsed: float = 0.0
	while elapsed < budget and not target.has_died():
		if player.combat.get_state() == PlayerCombat.State.IDLE:
			player.global_position = target.global_position + Vector3(0, 0, STRIKE_RANGE)
			player.camera_rig.rotation.y = 0.0
			player.camera_rig.attack_light_pressed.emit()
			swings += 1
		await physics_frame
		elapsed += 1.0 / 60.0
	return swings
