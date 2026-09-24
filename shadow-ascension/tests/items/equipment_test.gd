extends Node3D

## M7.2 — equipping, swapping, unequipping, what each piece does to the player,
## and the UI that drives it. Persistence across real scene changes lives in
## equipment_run.gd.

const DUNGEON: PackedScene = preload("res://scenes/dungeons/dungeon_test.tscn")
const SWORD: ItemData = preload("res://resources/items/training_sword.tres")
const BLADE: ItemData = preload("res://resources/items/swift_blade.tres")
const JACKET: ItemData = preload("res://resources/items/hunter_jacket.tres")
const HEAVY_JACKET: ItemData = preload("res://resources/items/reinforced_hunter_jacket.tres")
const FRAGMENT: ItemData = preload("res://resources/items/monster_fragment.tres")

const MAIN_HAND: ItemData.EquipmentSlot = ItemData.EquipmentSlot.MAIN_HAND
const CHEST: ItemData.EquipmentSlot = ItemData.EquipmentSlot.CHEST
const ROOM1_TRIGGER: Vector3 = Vector3(0, 0.1, -13)
const STRIKE_RANGE: float = 1.6

var _pass: int = 0
var _fail: int = 0

var _dungeon: DungeonController = null
var _player: Player = null
var _inventory: PlayerInventory = null
var _equipment: PlayerEquipment = null
var _prog: PlayerProgression = null
var _menu: InventoryMenu = null
var _stats: PlayerStatsMenu = null


func _ready() -> void:
	_run()


func _run() -> void:
	await _wait(0.2)
	_reset_session()
	await _setup()
	await _equip_tests()
	await _swap_tests()
	await _unequip_tests()
	await _armor_tests()
	await _health_clamp_tests()
	await _damage_tests()
	await _ui_tests()
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
	_equipment = _player.equipment
	_prog = _player.progression
	_menu = _dungeon.get_node("InventoryMenu")
	_stats = _dungeon.get_node("PlayerStatsMenu")
	_player.hurtbox.set_invulnerable(true)
	_inventory.clear()
	_equipment.clear()


# --- equip -----------------------------------------------------------------------

func _equip_tests() -> void:
	_inventory.add_item(SWORD, 1)
	_record(_inventory.get_quantity(SWORD.id) == 1, "1) the Training Sword is in the inventory")
	_record(SWORD.is_equippable() and SWORD.equipment_slot == MAIN_HAND,
		"2a) it declares itself a %s item" % SWORD.get_slot_label())
	_record(not FRAGMENT.is_equippable(), "2b) a material declares itself unequippable")

	var base_str: int = _prog.strength
	var base_power: float = _prog.get_melee_attack_power()
	_record(is_zero_approx(base_power), "6a) unarmed attack power is %.0f" % base_power)

	_record(_equipment.equip(SWORD), "3a) equipping succeeds")
	_record(not _inventory.has_item(SWORD.id), "3) it left the inventory")
	_record(_equipment.get_equipped_item(MAIN_HAND) == SWORD, "4) Main Hand holds it")
	_record(_prog.get_effective_strength() == base_str + 2,
		"5) STR %d allocated -> %d effective" % [base_str, _prog.get_effective_strength()])
	_record(_prog.strength == base_str, "5b) the allocated stat itself is untouched")
	_record(is_equal_approx(_prog.get_melee_attack_power(), 5.0),
		"6) melee attack power is +%.0f" % _prog.get_melee_attack_power())

	# 8) one sword, in one place
	var total: int = _inventory.get_quantity(SWORD.id)
	total += 1 if _equipment.is_equipped(SWORD.id) else 0
	_record(total == 1, "8) the item exists exactly once (%d)" % total)


# --- swap -------------------------------------------------------------------------

func _swap_tests() -> void:
	_inventory.add_item(BLADE, 1)
	_record(_inventory.get_quantity(BLADE.id) == 1, "9) the Swift Blade is in the inventory")

	var str_before: int = _prog.get_effective_strength()
	var agi_before: int = _prog.get_effective_agility()
	_record(_equipment.equip(BLADE), "10) equipping it succeeds")
	_record(_inventory.get_quantity(SWORD.id) == 1, "11) the Training Sword went back to the bag")
	_record(_equipment.get_equipped_item(MAIN_HAND) == BLADE, "12) Main Hand now holds the Blade")
	_record(not _inventory.has_item(BLADE.id), "16) and it is not also still in the bag")

	# 13/14) the old bonuses left with the old weapon
	_record(_prog.get_effective_strength() == str_before,
		"13/14a) STR: sword +2 replaced by blade +2, still %d" % _prog.get_effective_strength())
	_record(_prog.get_effective_agility() == agi_before + 2,
		"14) AGI picked up the blade's +2: %d -> %d" % [agi_before, _prog.get_effective_agility()])
	_record(is_equal_approx(_prog.get_melee_attack_power(), 8.0),
		"15) attack power went 5 -> %.0f" % _prog.get_melee_attack_power())

	var total: int = _inventory.get_quantity(BLADE.id) + (1 if _equipment.is_equipped(BLADE.id) else 0)
	var total_sword: int = _inventory.get_quantity(SWORD.id) \
		+ (1 if _equipment.is_equipped(SWORD.id) else 0)
	_record(total == 1 and total_sword == 1,
		"16b) neither weapon was duplicated (%d blade, %d sword)" % [total, total_sword])


# --- unequip -----------------------------------------------------------------------

func _unequip_tests() -> void:
	var str_with: int = _prog.get_effective_strength()
	_record(_equipment.unequip_slot(MAIN_HAND), "17) the Blade comes off")
	_record(not _equipment.is_slot_occupied(MAIN_HAND), "18) Main Hand is empty")
	_record(_inventory.get_quantity(BLADE.id) == 1, "19) it went back to the inventory")
	_record(_prog.get_effective_strength() == str_with - 2
			and is_zero_approx(_prog.get_melee_attack_power()),
		"20) its bonuses left with it: STR %d, power %.0f" % [
			_prog.get_effective_strength(), _prog.get_melee_attack_power()])

	# 21) unarmed combat still lands
	_player.global_position = ROOM1_TRIGGER
	await _wait(0.6)
	var enemy: RoomCombatant = _dungeon.get_rooms()[0].get_enemies()[0]
	var dealt: float = await _measure_swing(enemy)
	_record(dealt > 0.0, "21) the player still fights with an empty hand (%.0f damage)" % dealt)


# --- armour -------------------------------------------------------------------------

func _armor_tests() -> void:
	_inventory.add_item(JACKET, 1)
	var max_before: float = _player.health_component.max_health
	var move_before: float = _player.effective_movement_speed
	var dodge_before: float = _player.effective_dodge_speed
	# wounded first, so an equip that healed would be obvious
	_player.health_component.current_health = 50.0
	await get_tree().physics_frame

	_record(_equipment.equip(JACKET), "22) the Hunter Jacket goes on")
	_record(_equipment.get_equipped_item(CHEST) == JACKET, "23) Chest holds it")
	_record(_prog.get_equipment_bonus(PlayerProgression.Stat.VITALITY) == 2,
		"24) +%d VIT" % _prog.get_equipment_bonus(PlayerProgression.Stat.VITALITY))
	_record(_prog.get_equipment_bonus(PlayerProgression.Stat.AGILITY) == 1,
		"25) +%d AGI" % _prog.get_equipment_bonus(PlayerProgression.Stat.AGILITY))
	_record(is_equal_approx(_player.health_component.max_health, max_before + 16.0),
		"26) max health %.0f -> %.0f" % [max_before, _player.health_component.max_health])
	_record(_player.effective_movement_speed > move_before
			and _player.effective_dodge_speed > dodge_before,
		"27) movement %.2f -> %.2f and dodge %.2f -> %.2f" % [
			move_before, _player.effective_movement_speed,
			dodge_before, _player.effective_dodge_speed])
	_record(is_equal_approx(_player.health_component.current_health, 50.0),
		"28) and it healed nothing: %.0f/%.0f" % [
			_player.health_component.current_health, _player.health_component.max_health])


# --- health clamp on unequip ------------------------------------------------------------

func _health_clamp_tests() -> void:
	# 29) fill up above what the ceiling will be once the jacket comes off
	var armoured_max: float = _player.health_component.max_health
	_player.health_component.current_health = armoured_max
	await get_tree().physics_frame
	_record(is_equal_approx(_player.health_component.current_health, armoured_max),
		"29) at %.0f/%.0f with the jacket on" % [
			_player.health_component.current_health, armoured_max])

	_record(_equipment.unequip_slot(CHEST), "30) the jacket comes off")
	var bare_max: float = _player.health_component.max_health
	_record(bare_max < armoured_max, "31) max health fell %.0f -> %.0f" % [armoured_max, bare_max])
	_record(is_equal_approx(_player.health_component.current_health, bare_max),
		"32) current health was clamped to %.0f" % _player.health_component.current_health)
	_record(_player.health_component.current_health <= _player.health_component.max_health,
		"33) current never exceeds max")


# --- the damage formula ---------------------------------------------------------------

func _measure_swing(target: RoomCombatant) -> float:
	_player.combat.reset()
	var health: HealthComponent = target.get_node("HealthComponent")
	health.current_health = health.max_health
	health.is_dead = false
	_player.global_position = target.global_position + Vector3(0, 0, STRIKE_RANGE)
	_player.camera_rig.rotation.y = 0.0
	var before: float = health.current_health
	_player.camera_rig.attack_light_pressed.emit()
	var elapsed: float = 0.0
	while elapsed < 1.5:
		if health.current_health < before:
			break
		await get_tree().physics_frame
		elapsed += get_physics_process_delta_time()
	await _wait(0.6)
	return before - health.current_health


func _damage_tests() -> void:
	_equipment.clear()
	_inventory.add_item(SWORD, 1)
	_prog.strength = 15
	_prog.stats_changed.emit()
	var combat_data: PlayerCombatData = _player.combat.data
	var base: float = combat_data.base_damage * combat_data.light_combo[0].damage_multiplier

	_record(_prog.get_effective_damage(base) == 23.0,
		"D1) unarmed at STR 15: round(%.0f * 1.15) = %.0f" % [base, _prog.get_effective_damage(base)])

	_equipment.equip(SWORD)
	_record(_prog.get_effective_strength() == 17
			and is_equal_approx(_prog.get_melee_damage_multiplier(), 1.21),
		"D2) the sword's +2 lifts effective STR to %d, multiplier x%.2f" % [
			_prog.get_effective_strength(), _prog.get_melee_damage_multiplier()])

	# the brief's worked example: effective STR 15, so allocate 13 and let the
	# sword's +2 bring it to 15.
	_prog.strength = 13
	_prog.stats_changed.emit()
	_record(_prog.get_effective_strength() == 15
			and is_equal_approx(_prog.get_melee_damage_multiplier(), 1.15),
		"D3) 13 allocated +2 equip = %d effective, x%.2f" % [
			_prog.get_effective_strength(), _prog.get_melee_damage_multiplier()])
	_record(_prog.get_effective_damage(base) == 29.0,
		"D4) round((%.0f + 5) * 1.15) = %.0f" % [base, _prog.get_effective_damage(base)])

	var enemy: RoomCombatant = _dungeon.get_rooms()[0].get_enemies()[1]
	var dealt: float = await _measure_swing(enemy)
	_record(dealt == 29.0, "7/D5) a real swing deals %.0f" % dealt)
	_record(combat_data.base_damage * combat_data.light_combo[0].damage_multiplier == base,
		"D6) the base and the first attack still give %.0f" % base)


# --- the UI ---------------------------------------------------------------------------

func _ui_tests() -> void:
	_equipment.clear()
	_inventory.clear()
	_inventory.add_item(SWORD, 1)
	_inventory.add_item(FRAGMENT, 3)
	_menu.open()

	var sword_row: int = -1
	var fragment_row: int = -1
	for i in _menu.get_row_count():
		if _menu.get_row_text(i).contains("Training Sword"):
			sword_row = i
		if _menu.get_row_text(i).contains("Monster Fragment"):
			fragment_row = i

	_menu.select_row(fragment_row)
	_record(not _menu.is_equip_button_visible(),
		"U1) a material offers no Equip button")

	_menu.select_row(sword_row)
	_record(_menu.is_equip_button_visible(), "2) selecting a weapon offers Equipaggia")
	_record(_menu.get_detail_text().contains("Main Hand")
			and _menu.get_detail_text().contains("+2 STR")
			and _menu.get_detail_text().contains("+5 Melee Attack Power"),
		"U2) its slot and bonuses are shown: %s" % _menu.get_detail_text().replace("\n", " | "))

	_record(_menu.press_equip(), "U3) the button equips it")
	_record(_menu.get_equipment_row_text(MAIN_HAND).contains("Training Sword"),
		"U4) the panel reads '%s'" % _menu.get_equipment_row_text(MAIN_HAND).strip_edges())
	_record(_menu.get_equipment_row_text(CHEST).contains("Vuoto"),
		"U5) and an empty slot says so: '%s'" % _menu.get_equipment_row_text(CHEST).strip_edges())
	_record(_menu.is_unequip_button_visible() and not _menu.is_equip_button_visible(),
		"U6) the occupied slot offers Rimuovi instead")

	_record(_menu.press_unequip(), "U7) the button removes it")
	_record(_menu.get_equipment_row_text(MAIN_HAND).contains("Vuoto")
			and _inventory.get_quantity(SWORD.id) == 1,
		"U8) the slot empties and the sword is back in the bag")

	# the character sheet shows the split, live
	_menu.close()
	_inventory.add_item(HEAVY_JACKET, 1)
	_equipment.equip(HEAVY_JACKET)
	_stats.open()
	_record(_stats.get_stat_value_text("VIT") == str(_prog.get_effective_vitality()),
		"U9) the sheet shows effective VIT %s" % _stats.get_stat_value_text("VIT"))
	_record(_stats.get_stat_split_text("VIT").contains("+4 Equip."),
		"U10) with the split beneath: '%s'" % _stats.get_stat_split_text("VIT"))
	_record(_stats.get_stat_split_text("INT") == "",
		"U11) and nothing beneath a stat with no bonus")
	_equipment.equip(SWORD)
	_record(_stats.get_derived_text().contains("Melee Attack Power  +5"),
		"U12) and melee attack power, updated live while open")
	_stats.close()
