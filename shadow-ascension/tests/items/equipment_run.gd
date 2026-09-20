extends SceneTree

## M7.2 persistence with REAL scene changes: what is worn, and what it is worth,
## across a gate, an exit, a second run and a death.
##
##   godot --headless --path . --script res://tests/items/equipment_run.gd

const TEST_WORLD: String = "res://scenes/core/test_world.tscn"
const DUNGEON: String = "res://scenes/dungeons/dungeon_test.tscn"
const SWORD: ItemData = preload("res://resources/items/training_sword.tres")
const JACKET: ItemData = preload("res://resources/items/hunter_jacket.tres")
const BLADE: ItemData = preload("res://resources/items/swift_blade.tres")

const MAIN_HAND: ItemData.EquipmentSlot = ItemData.EquipmentSlot.MAIN_HAND
const CHEST: ItemData.EquipmentSlot = ItemData.EquipmentSlot.CHEST
const ROOM_ANCHORS: Array[Vector3] = [
	Vector3(0, 0.1, -13), Vector3(0, 0.1, -33), Vector3(0, 0.1, -53)
]
const EXIT_POS: Vector3 = Vector3(0, 0.1, -65)

var _pass: int = 0
var _fail: int = 0


func _initialize() -> void:
	var state: Node = root.get_node_or_null("PlayerRuntimeState")
	state.reset_runtime_state()

	change_scene_to_file(TEST_WORLD)
	await _pause(0.6)

	var player: Player = current_scene.get_node("Player")
	_record(player.equipment != null
			and not player.equipment.is_slot_occupied(MAIN_HAND)
			and not player.equipment.is_slot_occupied(CHEST),
		"1) a new session starts with both slots empty")

	# 34/35) kit up in the test world
	player.inventory.add_item(SWORD, 1)
	player.inventory.add_item(JACKET, 1)
	player.inventory.add_item(BLADE, 1)
	_record(player.equipment.equip(SWORD), "34) Training Sword equipped")
	_record(player.equipment.equip(JACKET), "35) Hunter Jacket equipped")
	player.health_component.receive_damage(player.health_component.current_health - 60.0)
	await _pause(0.2)

	var before: Dictionary = _snapshot(player)
	print("[TEST WORLD ] %s" % [before])
	_record(before["main_hand"] == "training_sword" and before["chest"] == "hunter_jacket",
		"35b) both slots filled")

	# 36/37/38) through the gate
	var gate: DungeonGate = current_scene.get_node("DungeonGate")
	player.global_position = gate.global_position
	await _pause(0.3)
	gate.activate()
	await _pause(1.0)
	_record(current_scene.scene_file_path == DUNGEON, "36) the gate loaded the dungeon")
	var p2: Player = current_scene.get_node("Player")
	_record(p2 != player, "36b) on a different Player instance")
	var in_dungeon: Dictionary = _snapshot(p2)
	print("[IN DUNGEON ] %s" % [in_dungeon])
	_same(before, in_dungeon, "37/38) gate")

	# the panel shows it without being poked
	var menu: InventoryMenu = current_scene.get_node("InventoryMenu")
	menu.open()
	_record(menu.get_equipment_row_text(MAIN_HAND).contains("Training Sword")
			and menu.get_equipment_row_text(CHEST).contains("Hunter Jacket"),
		"38b) the equipment panel reads it straight away")
	menu.close()

	# swap inside the dungeon, so the change itself has to travel too
	p2.equipment.equip(BLADE)
	await _pause(0.2)
	var swapped: Dictionary = _snapshot(p2)
	print("[AFTER SWAP ] %s" % [swapped])
	_record(swapped["main_hand"] == "swift_blade" and swapped["power"] == 8.0,
		"38c) swapped to the Swift Blade inside the dungeon")

	# 39/40) out again
	p2.hurtbox.set_invulnerable(true)
	for i in 2:
		p2.global_position = ROOM_ANCHORS[i]
		await _pause(0.4)
		for enemy in (current_scene as DungeonController).get_rooms()[i].get_enemies():
			enemy.hurtbox.receive_hit(10000.0, null)
		await _pause(0.5)
	p2.global_position = ROOM_ANCHORS[2]
	await _pause(0.5)
	var boss: DungeonBoss = (current_scene as DungeonController).get_rooms()[2].get_enemies()[0] as DungeonBoss
	boss.hurtbox.receive_hit(10000.0, null)
	await _pause(1.2)
	p2.hurtbox.set_invulnerable(false)

	p2.global_position = EXIT_POS
	await _pause(0.4)
	(current_scene as DungeonController).exit_portal.activate()
	await _pause(1.2)
	_record(current_scene.scene_file_path == TEST_WORLD, "39) the portal returned home")
	var p3: Player = current_scene.get_node("Player")
	var home: Dictionary = _snapshot(p3)
	print("[BACK HOME  ] %s" % [home])
	_same(swapped, home, "40) exit")

	# 41) second run
	var gate2: DungeonGate = current_scene.get_node("DungeonGate")
	p3.global_position = gate2.global_position
	await _pause(0.3)
	gate2.activate()
	await _pause(1.0)
	var p4: Player = current_scene.get_node("Player")
	var second: Dictionary = _snapshot(p4)
	print("[SECOND RUN ] %s" % [second])
	_same(swapped, second, "41) second run")

	# 42) death keeps the kit
	var dungeon2: DungeonController = current_scene as DungeonController
	p4.global_position = ROOM_ANCHORS[0]
	await _pause(0.4)
	p4.health_component.receive_damage(1000.0)
	await _pause(0.3)
	_record(dungeon2.get_state() == DungeonController.DungeonState.FAILED, "42a) the run failed")
	await _pause(2.5)
	var p5: Player = current_scene.get_node("Player")
	var after_death: Dictionary = _snapshot(p5)
	print("[AFTER DEATH] %s" % [after_death])
	for key in ["main_hand", "chest", "str", "agi", "vit", "power", "max_hp"]:
		_record(after_death[key] == swapped[key],
			"42) death keeps %s: %s" % [key, after_death[key]])
	_record(is_equal_approx(after_death["hp"], after_death["max_hp"]),
		"42b) and restores health only: %.0f/%.0f" % [after_death["hp"], after_death["max_hp"]])

	# 43) an explicit fresh session strips it
	state.reset_runtime_state()
	p5.equipment.clear()
	p5.inventory.clear()
	_record(state.equipment.is_empty() and not p5.equipment.is_slot_occupied(MAIN_HAND)
			and not p5.equipment.is_slot_occupied(CHEST),
		"43) reset_runtime_state() empties both slots")

	print("[SUMMARY] passed=%d failed=%d" % [_pass, _fail])
	await _pause(0.3)
	quit()


func _pause(t: float) -> void:
	await create_timer(t).timeout


func _record(passed: bool, description: String) -> void:
	if passed:
		_pass += 1
		print("[PASS] " + description)
	else:
		_fail += 1
		print("[FAIL] " + description)


## What is worn, and everything it is worth. Derived values are included on
## purpose: they are recomputed on the far side, so if the restore were wrong
## they would drift even when the slots looked right.
func _snapshot(player: Player) -> Dictionary:
	var e: PlayerEquipment = player.equipment
	var p: PlayerProgression = player.progression
	var main: ItemData = e.get_equipped_item(MAIN_HAND)
	var chest: ItemData = e.get_equipped_item(CHEST)
	return {
		"main_hand": String(main.id) if main != null else "-",
		"chest": String(chest.id) if chest != null else "-",
		"str": p.get_effective_strength(),
		"agi": p.get_effective_agility(),
		"vit": p.get_effective_vitality(),
		"power": p.get_melee_attack_power(),
		"hp": player.health_component.current_health,
		"max_hp": player.health_component.max_health,
	}


func _same(before: Dictionary, after: Dictionary, label: String) -> void:
	var drifted: Array[String] = []
	for key in before:
		if typeof(before[key]) == TYPE_FLOAT:
			if not is_equal_approx(before[key], after[key]):
				drifted.append("%s %s->%s" % [key, before[key], after[key]])
		elif before[key] != after[key]:
			drifted.append("%s %s->%s" % [key, before[key], after[key]])
	_record(drifted.is_empty(), "%s: equipment and every bonus survived%s" % [
		label, "" if drifted.is_empty() else " EXCEPT " + str(drifted)])
