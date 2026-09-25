extends Node3D

## M7.1 — enemy health bars, loot rolling, world drops, the inventory and its UI.
## Session persistence across real scene changes lives in loot_run.gd.

const DUNGEON: PackedScene = preload("res://scenes/dungeons/dungeon_test.tscn")
const FRAGMENT: ItemData = preload("res://resources/items/monster_fragment.tres")
const IRON: ItemData = preload("res://resources/items/iron_shard.tres")
const SWORD: ItemData = preload("res://resources/items/training_sword.tres")

const ROOM1_TRIGGER: Vector3 = Vector3(0, 0.1, -13)
const BOSS_TRIGGER: Vector3 = Vector3(0, 0.1, -53)
const STRIKE_RANGE: float = 1.6

var _pass: int = 0
var _fail: int = 0

var _dungeon: DungeonController = null
var _player: Player = null
var _inventory: PlayerInventory = null
var _menu: InventoryMenu = null
var _stats_menu: PlayerStatsMenu = null
var _prompt: InteractionPrompt = null


func _ready() -> void:
	_run()


func _run() -> void:
	await _wait(0.2)
	_reset_session()
	await _setup()
	await _health_bar_tests()
	await _loot_tests()
	await _inventory_tests()
	await _menu_tests()
	print("[SUMMARY] passed=%d failed=%d" % [_pass, _fail])
	get_tree().quit()


func _wait(t: float) -> void:
	await get_tree().create_timer(t).timeout


func _record(passed: bool, description: String) -> void:
	if passed:
		_pass += 1
		print("[PASS] " + description)
	else:
		_fail += 1
		print("[FAIL] " + description)


func _reset_session() -> void:
	var state: Node = get_tree().root.get_node_or_null("PlayerRuntimeState")
	if state != null:
		state.reset_runtime_state()


func _setup() -> void:
	_dungeon = DUNGEON.instantiate() as DungeonController
	_dungeon.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(_dungeon)
	await _wait(0.8)
	_player = _dungeon.get_node("Player")
	_inventory = _player.inventory
	_menu = _dungeon.get_node("InventoryMenu")
	_stats_menu = _dungeon.get_node("PlayerStatsMenu")
	_prompt = _dungeon.get_node("InteractionPrompt")
	_player.hurtbox.set_invulnerable(true)


func _press(action: String) -> void:
	var event: InputEventAction = InputEventAction.new()
	event.action = action
	event.pressed = true
	get_viewport().push_input(event)
	await get_tree().process_frame


func _press_escape() -> void:
	var event: InputEventKey = InputEventKey.new()
	event.keycode = KEY_ESCAPE
	event.pressed = true
	get_viewport().push_input(event)
	await get_tree().process_frame


func _bar_of(enemy: Node) -> EnemyHealthBar3D:
	return enemy.get_node_or_null("EnemyHealthBar3D") as EnemyHealthBar3D


# --- Part A: health bars -------------------------------------------------------

func _health_bar_tests() -> void:
	var room1: RoomController = _dungeon.get_rooms()[0]
	var enemies: Array[RoomCombatant] = room1.get_enemies()
	var bar: EnemyHealthBar3D = _bar_of(enemies[0])

	_record(bar != null, "A0) every BasicEnemy carries a health bar")
	_record(not bar.is_bar_visible(),
		"1) at full health and out of combat the bar stays hidden")

	_player.global_position = ROOM1_TRIGGER
	await _wait(0.8)
	_record(bar.is_bar_visible(), "2) it appears once the enemy engages")

	var health: HealthComponent = enemies[0].get_node("HealthComponent")
	health.take_damage(DamageInfo.new(20.0))
	await _wait(0.1)
	_record(is_equal_approx(bar.get_ratio(), 0.8),
		"3/4) 100 -> 80 reads as %.2f" % bar.get_ratio())
	health.take_damage(DamageInfo.new(25.0))
	await _wait(0.1)
	_record(is_equal_approx(bar.get_ratio(), 0.55),
		"5) each further hit updates it (%.2f)" % bar.get_ratio())

	# 6) nearly dead has to be tellable at a glance, not only by the numbers
	var healthy_colour: Color = bar._colour_for(0.85)
	var dying_colour: Color = bar._colour_for(0.1)
	_record(dying_colour.r > healthy_colour.r and dying_colour.g < healthy_colour.g,
		"6) a nearly dead bar reads apart from a healthy one (%s vs %s)" % [
			dying_colour, healthy_colour])

	# 8) three enemies, three independent readings
	var room2: RoomController = _dungeon.get_rooms()[1]
	_player.global_position = Vector3(0, 0.1, -33)
	await _wait(0.8)
	var three: Array[RoomCombatant] = room2.get_enemies()
	(three[0].get_node("HealthComponent") as HealthComponent).take_damage(DamageInfo.new(10.0))
	(three[1].get_node("HealthComponent") as HealthComponent).take_damage(DamageInfo.new(70.0))
	await _wait(0.2)
	var ratios: Array[float] = []
	for enemy in three:
		ratios.append(_bar_of(enemy).get_ratio())
	_record(is_equal_approx(ratios[0], 0.9) and is_equal_approx(ratios[1], 0.3)
			and is_equal_approx(ratios[2], 1.0),
		"8) three enemies show three independent values: %s" % [ratios])

	# 7) dead enemies take their bar with them
	(three[1].get_node("HealthComponent") as HealthComponent).take_damage(DamageInfo.new(1000.0))
	await _wait(0.5)
	_record(not _bar_of(three[1]).is_bar_visible(), "7) a dead enemy's bar is gone")

	# 9/10) the boss keeps its own bar and gains no second one
	var boss: DungeonBoss = _dungeon.get_rooms()[2].get_enemies()[0] as DungeonBoss
	_record(_bar_of(boss) == null, "9) the boss has no duplicate world-space bar")
	var boss_bar: BossHealthBar = _dungeon.get_node("BossHealthBar")
	_record(boss_bar != null and not boss_bar.is_showing(),
		"10) its own bar exists and is still dormant")


# --- Part C/D: loot ---------------------------------------------------------------

func _loot_tests() -> void:
	var enemy: RoomCombatant = _dungeon.get_rooms()[0].get_enemies()[0]
	var dropper: LootDropper = enemy.get_node("LootDropper")
	_record(dropper != null and dropper.loot_table != null,
		"C0) the enemy carries a configurable loot table")

	var overall: float = 1.0
	for entry in dropper.loot_table.entries:
		overall *= (1.0 - entry.drop_chance)
	overall = 1.0 - overall
	_record(overall >= 0.35 and overall <= 0.55,
		"C1) its overall drop chance is %.0f%%" % (overall * 100.0))

	# 11/21) one roll per death, however many times death is announced
	var before: int = _world_items().size()
	(enemy.get_node("HealthComponent") as HealthComponent).take_damage(DamageInfo.new(1000.0))
	await _wait(0.5)
	var rolled_once: bool = dropper.has_rolled()
	var after_first: int = _world_items().size()
	enemy.enemy_died.emit(enemy)
	enemy.report_death()
	dropper.drop_now()
	await _wait(0.3)
	_record(rolled_once and _world_items().size() == after_first,
		"11/21) the table rolls once; re-announcing the death drops nothing more (%d items)" % [
			_world_items().size() - before])

	# 12/13) whatever dropped is in the world and above the floor
	var drops: Array[WorldItem] = _world_items()
	if drops.is_empty():
		# This enemy's roll missed. Force one so the rest still runs honestly.
		var forced: LootDropper = _dungeon.get_rooms()[0].get_enemies()[1].get_node("LootDropper")
		(_dungeon.get_rooms()[0].get_enemies()[1].get_node("HealthComponent") as HealthComponent).take_damage(DamageInfo.new(1000.0))
		await _wait(0.5)
		drops = _world_items()
	_record(not drops.is_empty(), "12) a drop exists in the world (%d)" % drops.size())
	if drops.is_empty():
		_record(false, "13-19) skipped: nothing dropped to walk up to")
		return
	var lowest: float = 999.0
	for drop in drops:
		lowest = minf(lowest, drop.global_position.y)
	_record(lowest >= -0.05, "13) nothing spawned below the floor (lowest y=%.2f)" % lowest)

	# 14/15) walking up to it raises the shared prompt
	var target: WorldItem = drops[0]
	_player.global_position = target.global_position + Vector3(0, 0, 0.6)
	await _wait(0.4)
	_record(target.is_player_in_range() and _prompt.is_showing(),
		"14/15) standing on it shows '%s %s'" % [_prompt.key_label.text, _prompt.get_text()])
	_record(_prompt.get_text() == target.get_prompt_text(),
		"15b) the prompt names the item: '%s'" % _prompt.get_text())

	# 16/17/18/19) picking it up
	var item: ItemData = target.item
	var quantity: int = target.quantity
	var had: int = _inventory.get_quantity(item.id)
	_record(target.pick_up(), "16) interact picks it up")
	await _wait(0.3)
	_record(not is_instance_valid(target), "17) the world item is gone")
	_record(_inventory.get_quantity(item.id) == had + quantity,
		"18/19) the inventory holds %d x %s" % [
			_inventory.get_quantity(item.id), item.display_name])
	_record(not _prompt.is_showing(), "17b) and the prompt does not go stale")


func _world_items() -> Array[WorldItem]:
	var found: Array[WorldItem] = []
	_collect_world_items(_dungeon, found)
	return found


func _collect_world_items(node: Node, into: Array[WorldItem]) -> void:
	var world_item: WorldItem = node as WorldItem
	if world_item != null and is_instance_valid(world_item):
		into.append(world_item)
	for child in node.get_children():
		_collect_world_items(child, into)


# --- Part E: the inventory model ---------------------------------------------------

func _inventory_tests() -> void:
	_inventory.clear()
	_record(_inventory.is_empty() and _inventory.get_distinct_count() == 0,
		"E0) the inventory starts empty")

	_record(_inventory.add_item(FRAGMENT, 2) == 2, "20a) two fragments accepted")
	_record(_inventory.add_item(FRAGMENT, 3) == 3, "20b) three more accepted")
	_record(_inventory.get_quantity(FRAGMENT.id) == 5,
		"20) two drops of the same stackable item stack to %d" % _inventory.get_quantity(FRAGMENT.id))
	_record(_inventory.get_distinct_count() == 1, "20c) as one entry, not two")

	_inventory.add_item(IRON, 1)
	_inventory.add_item(SWORD, 1)
	_record(_inventory.has_item(IRON.id) and _inventory.has_item(SWORD.id)
			and _inventory.get_distinct_count() == 3,
		"E1) three distinct items held")

	# max_stack is respected, and the overflow is reported rather than swallowed
	var accepted: int = _inventory.add_item(FRAGMENT, FRAGMENT.max_stack)
	_record(_inventory.get_quantity(FRAGMENT.id) == FRAGMENT.max_stack
			and accepted == FRAGMENT.max_stack - 5,
		"E2) a stackable item caps at %d; only %d of the overflow was taken" % [
			FRAGMENT.max_stack, accepted])

	_record(_inventory.remove_item(IRON.id, 1) and not _inventory.has_item(IRON.id),
		"E3) removing the last of a stack drops the entry")
	_record(not _inventory.remove_item(SWORD.id, 5),
		"E4) removing more than is held changes nothing")
	_record(_inventory.get_quantity(SWORD.id) == 1, "E4b) the sword is still there")

	# a non-stackable item is counted, not capped — M7.1 has no per-instance data
	_inventory.add_item(SWORD, 2)
	_record(_inventory.get_quantity(SWORD.id) == 3,
		"E5) non-stackable items accumulate a count (%d)" % _inventory.get_quantity(SWORD.id))

	var rows: Array[Dictionary] = _inventory.get_entries()
	_record(rows.size() == 2 and (rows[0]["item"] as ItemData).rarity
			>= (rows[1]["item"] as ItemData).rarity,
		"E6) the listing comes back rarest first")


# --- Part E: the UI -----------------------------------------------------------------

func _menu_tests() -> void:
	_record(_menu != null and not _menu.is_open(), "23a) the inventory menu starts closed")
	_record(_menu.hint.visible, "29) the '[I] Inventario' hint is on screen")

	await _press("inventory")
	_record(_menu.is_open(), "23) I opens the inventory")
	_record(get_tree().paused, "24) the game pauses")
	_record(_menu.last_mouse_mode_request == Input.MOUSE_MODE_VISIBLE, "25) the mouse is freed")

	_record(_menu.get_row_count() == 2 and not _menu.is_empty_shown(),
		"31) the collected items are listed (%d rows)" % _menu.get_row_count())
	# Rows come back rarest first and then alphabetically, so the sword is not
	# necessarily row 0. Find it rather than assuming a position.
	var sword_row: int = -1
	for i in _menu.get_row_count():
		if _menu.get_row_text(i).contains("Training Sword"):
			sword_row = i
	_record(sword_row >= 0 and _menu.get_row_text(sword_row).contains("x3"),
		"32) quantity shown: '%s'" % _menu.get_row_text(maxi(0, sword_row)).strip_edges())
	_record(sword_row >= 0 and _menu.get_row_text(sword_row).contains("Common")
			and _menu.get_row_text(sword_row).contains("Weapon"),
		"33/34) rarity and type shown on the row")

	_menu.select_row(sword_row)
	_record(_menu.get_detail_text().contains("Training Sword")
			and _menu.get_detail_text().contains("addestramento"),
		"35) selecting a row shows its description: '%s'" % [
			_menu.get_detail_text().replace("\n", " | ")])

	# 36) nothing equippable yet
	var has_equip: bool = false
	for i in _menu.get_row_count():
		if _menu.get_row_text(i).to_lower().contains("equip"):
			has_equip = true
	_record(not has_equip, "36) no Equip control exists yet")

	await _press("inventory")
	_record(not _menu.is_open() and not get_tree().paused, "26/28) I closes it and play resumes")
	_record(_menu.last_mouse_mode_request == Input.MOUSE_MODE_CAPTURED, "25b) the mouse is recaptured")

	await _press("inventory")
	await _press_escape()
	_record(not _menu.is_open() and not get_tree().paused, "27) ESC closes it too")

	# 30) empty reads as empty, not as a broken list
	_inventory.clear()
	await _press("inventory")
	_record(_menu.is_empty_shown() and _menu.get_row_count() == 0,
		"30) an empty inventory says so")
	_record(_menu.get_detail_text().contains("Seleziona"),
		"30b) and the detail pane falls back cleanly")

	# only one pause menu at a time
	_stats_menu.open()
	_record(_stats_menu.is_open() and not _menu.is_open(),
		"UX) opening the character sheet closes the inventory")
	_menu.open()
	_record(_menu.is_open() and not _stats_menu.is_open(),
		"UX2) and the other way round")
	_menu.close()
	_record(not get_tree().paused, "UX3) closing the last one resumes play")
