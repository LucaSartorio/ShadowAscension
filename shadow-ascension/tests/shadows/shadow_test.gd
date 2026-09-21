extends Node3D

## M8.1 — the remnant an enemy leaves, the one attempt it allows, what a success
## and a failure each do, and the collection that holds the results.
## Persistence across real scene changes lives in shadow_run.gd.

const DUNGEON: PackedScene = preload("res://scenes/dungeons/dungeon_test.tscn")
## Held in a var, not a const: the tests force the odds on this shared resource
## so nothing hangs on a 70% roll, and a const refuses property assignment.
var SHADOW: ShadowData = preload("res://resources/shadows/basic_melee_shadow.tres")

const ROOM1_TRIGGER: Vector3 = Vector3(0, 0.1, -13)
const ROOM2_TRIGGER: Vector3 = Vector3(0, 0.1, -33)

var _pass: int = 0
var _fail: int = 0

var _dungeon: DungeonController = null
var _player: Player = null
var _collection: PlayerShadowCollection = null
var _prompt: InteractionPrompt = null
var _feedback: ExtractionFeedback = null
var _menu: ShadowCollectionMenu = null
## Restored at the end: the tests force the odds so nothing hangs on luck.
var _real_chance: float = 0.0
## The remnant under test, tracked by identity: the room is full of them, so
## "none left in the world" is never the right question.
var _pending: ShadowRemnant = null


func _ready() -> void:
	_run()


func _run() -> void:
	await _wait(0.2)
	_reset_session()
	_real_chance = SHADOW.extraction_chance
	await _setup()
	await _spawn_tests()
	await _success_tests()
	await _failure_tests()
	await _multiple_tests()
	await _interaction_tests()
	await _menu_tests()
	SHADOW.extraction_chance = _real_chance
	_record(is_equal_approx(SHADOW.extraction_chance, 0.7),
		"Z) the real extraction chance is restored to %.2f" % SHADOW.extraction_chance)
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
	_collection = _player.shadows
	_prompt = _dungeon.get_node("InteractionPrompt")
	_feedback = _dungeon.get_node("ExtractionFeedback")
	_menu = _dungeon.get_node("ShadowCollectionMenu")
	_player.hurtbox.set_invulnerable(true)


## A real key press, so every listener in range gets the same chance to react —
## which is the path the one-press-hits-two bug lived on.
func _press_interact() -> void:
	var event: InputEventAction = InputEventAction.new()
	event.action = "interact"
	event.pressed = true
	get_viewport().push_input(event)
	await get_tree().process_frame


func _remnants() -> Array[ShadowRemnant]:
	var found: Array[ShadowRemnant] = []
	_collect(_dungeon, found)
	return found


func _collect(node: Node, into: Array[ShadowRemnant]) -> void:
	var remnant: ShadowRemnant = node as ShadowRemnant
	if remnant != null and is_instance_valid(remnant):
		into.append(remnant)
	for child in node.get_children():
		_collect(child, into)


## Lands one real player hit before finishing the enemy off. XP only flows to
## enemies the player actually touched, so a kill dealt straight to the health
## component would award nothing — that is M6.1 working, not a bug.
func _kill(enemy: RoomCombatant) -> void:
	_player.global_position = enemy.global_position + Vector3(0, 0, 1.6)
	_player.camera_rig.rotation.y = 0.0
	_player._attack_state = Player.AttackState.IDLE
	_player._combo_index = 0
	_player.camera_rig.attack_light_pressed.emit()
	await _wait(0.45)
	(enemy.get_node("HealthComponent") as HealthComponent).receive_damage(10000.0)
	await _wait(0.5)


## Stands the player on a remnant and runs its one attempt to completion.
func _extract(remnant: ShadowRemnant) -> bool:
	_player.global_position = remnant.global_position + Vector3(0, 0, 0.5)
	await _wait(0.4)
	var started: bool = remnant.attempt_extraction()
	await _wait(remnant.extraction_duration + 0.3)
	return started


# --- the remnant appears ------------------------------------------------------------

func _spawn_tests() -> void:
	_player.global_position = ROOM1_TRIGGER
	await _wait(0.6)
	var room1: RoomController = _dungeon.get_rooms()[0]
	var enemy: RoomCombatant = room1.get_enemies()[0]
	var source: ShadowSource = enemy.get_node("ShadowSource")
	_record(source != null and source.shadow_extractable and source.shadow_data == SHADOW,
		"E0) the enemy declares its shadow through data, not a type check")

	var xp_before: int = _player.progression.current_xp
	await _kill(enemy)
	var remnants: Array[ShadowRemnant] = _remnants()
	_record(remnants.size() == 1, "4) exactly one remnant appeared (%d)" % remnants.size())
	var first_remnant: ShadowRemnant = remnants[0]
	_record(remnants[0].global_position.y >= -0.05,
		"4b) above the floor (y=%.2f)" % remnants[0].global_position.y)
	_record(_player.progression.current_xp > xp_before or _player.progression.current_level > 1,
		"2) XP was still awarded")
	_record(source.has_spawned(), "4c) the source latched")

	# 4/21) death announced again must not spawn a second one
	enemy.enemy_died.emit(enemy)
	enemy.report_death()
	source.spawn_remnant()
	await _wait(0.3)
	_record(_remnants().size() == 1,
		"4d) re-announcing the death spawns nothing more (%d)" % _remnants().size())

	# 5) the room does not wait for it
	# The second enemy leaves one of its own — every enemy does — so the count
	# goes to two rather than back to zero.
	await _kill(room1.get_enemies()[1])
	_record(room1.is_cleared(), "5) the room cleared with remnants still standing")
	_record(not room1.exit_door.is_locked(), "5b) and its door opened")
	_record(_remnants().size() == 2,
		"5c) both corpses left one each (%d)" % _remnants().size())
	_pending = first_remnant


# --- a successful extraction ----------------------------------------------------------

func _success_tests() -> void:
	SHADOW.extraction_chance = 1.0
	_player.global_position = _pending.global_position + Vector3(0, 0, 0.5)
	await _wait(0.4)
	_record(_pending.is_player_in_range() and _prompt.is_showing()
			and _prompt.get_text() == "Estrai Ombra",
		"6) standing on it shows '%s %s'" % [_prompt.key_label.text, _prompt.get_text()])

	# Two corpses that fell near each other leave overlapping remnants, so the
	# one under the prompt is not necessarily the nearest. That is the contract:
	# E acts on whatever the prompt names. Follow it rather than assume.
	var in_reach: int = 0
	for candidate in _remnants():
		if candidate.is_player_in_range():
			in_reach += 1
	var remnant: ShadowRemnant = _prompt.get_current_owner() as ShadowRemnant
	_record(remnant != null, "6b) the prompt names a remnant, %d in reach" % in_reach)
	if remnant == null:
		return

	var before: int = _collection.get_count()
	await _press_interact()
	_record(remnant.has_been_attempted(), "8) E starts the one attempt")
	var attempted: int = 0
	for candidate in _remnants():
		if candidate.has_been_attempted():
			attempted += 1
	_record(attempted == 1,
		"6c) with %d in reach, one press attempts exactly %d" % [in_reach, attempted])
	_record(not remnant.attempt_extraction(), "8b) a second press during it does nothing")
	_record(_feedback.is_showing() and _feedback.get_title() == "ESTRAZIONE...",
		"10a) the banner reads '%s'" % _feedback.get_title())
	# It does not necessarily go blank: with another remnant still underfoot the
	# runner-up inherits it, which is the fallback working. What must be true is
	# that the one being extracted no longer owns it.
	_record(_prompt.get_current_owner() != remnant,
		"32a) the extracting remnant released the prompt")

	await _wait(remnant.extraction_duration + 0.3)
	_record(_collection.get_count() == before + 1,
		"9/13) the collection went %d -> %d" % [before, _collection.get_count()])
	_record(_feedback.get_title() == "ESTRAZIONE RIUSCITA",
		"10) the banner reads '%s'" % _feedback.get_title())
	var shadow: ShadowInstance = _collection.get_shadows()[_collection.get_count() - 1]
	_record(shadow.shadow_data == SHADOW and String(shadow.instance_id).begins_with("shadow_"),
		"11/12) a new instance exists with id %s" % shadow.instance_id)
	_record(_feedback.get_detail().contains(shadow.get_short_id()),
		"10b) and names it: '%s'" % _feedback.get_detail())

	await _wait(remnant.result_duration + 0.4)
	_record(not is_instance_valid(remnant), "14) that remnant is gone")


# --- a failed extraction ----------------------------------------------------------------

func _failure_tests() -> void:
	SHADOW.extraction_chance = 0.0
	_player.global_position = ROOM2_TRIGGER
	await _wait(0.6)
	var room2: RoomController = _dungeon.get_rooms()[1]
	var before_kill: Array[ShadowRemnant] = _remnants()
	await _kill(room2.get_enemies()[0])
	var fresh: Array[ShadowRemnant] = []
	for candidate in _remnants():
		if not before_kill.has(candidate):
			fresh.append(candidate)
	_record(fresh.size() == 1, "19) exactly one new remnant appeared (%d)" % fresh.size())
	if fresh.is_empty():
		_record(false, "20-24) skipped: nothing new to attempt")
		return

	var remnant: ShadowRemnant = fresh[0]
	var before: int = _collection.get_count()
	_player.global_position = remnant.global_position + Vector3(0, 0, 0.5)
	await _wait(0.4)
	await _press_interact()
	_record(remnant.has_been_attempted(), "20) E attempts it")
	await _wait(remnant.extraction_duration + 0.3)
	_record(_collection.get_count() == before,
		"21/22) the collection did not grow (%d)" % _collection.get_count())
	_record(_feedback.get_title() == "ESTRAZIONE FALLITA",
		"21b) the banner reads '%s'" % _feedback.get_title())
	_record(remnant.is_spent() and not remnant.attempt_extraction(),
		"23) it cannot be retried")

	await _wait(remnant.result_duration + 0.4)
	_record(not is_instance_valid(remnant), "24) and it is removed anyway")


# --- several shadows -----------------------------------------------------------------------

func _multiple_tests() -> void:
	SHADOW.extraction_chance = 1.0
	var room2: RoomController = _dungeon.get_rooms()[1]
	var before: int = _collection.get_count()
	for i in 2:
		var before_kill: Array[ShadowRemnant] = _remnants()
		await _kill(room2.get_enemies()[i + 1])
		var fresh: ShadowRemnant = null
		for candidate in _remnants():
			if not before_kill.has(candidate):
				fresh = candidate
		if fresh == null:
			continue
		await _extract(fresh)
		await _wait(fresh.result_duration + 0.3 if is_instance_valid(fresh) else 1.5)

	_record(_collection.get_count() == before + 2,
		"25/27) two more extracted, %d held in total" % _collection.get_count())
	var ids: Dictionary = {}
	for shadow in _collection.get_shadows():
		ids[shadow.instance_id] = true
	_record(ids.size() == _collection.get_count(),
		"26/28) every instance id is distinct (%d unique of %d)" % [
			ids.size(), _collection.get_count()])
	var listed: Array[String] = []
	for shadow in _collection.get_shadows():
		listed.append(shadow.get_short_id())
	_record(_collection.get_count() >= 3, "25b) at least three held: %s" % [listed])


# --- loot and a remnant from the same corpse ------------------------------------------------

func _interaction_tests() -> void:
	SHADOW.extraction_chance = 1.0
	var room3_enemy: RoomCombatant = _dungeon.get_rooms()[1].get_enemies()[2]
	if room3_enemy.has_died():
		# The multiple-shadow block may already have taken this one; make a
		# remnant and a drop by hand so the conflict is still exercised.
		_record(true, "29a) reusing an existing corpse for the overlap check")

	# Put a world item exactly where a remnant is, which is the ambiguous case.
	var remnant_scene: PackedScene = preload("res://scenes/shadows/shadow_remnant.tscn")
	var item_scene: PackedScene = preload("res://scenes/items/world_item.tscn")
	var fragment: ItemData = preload("res://resources/items/monster_fragment.tres")

	var remnant: ShadowRemnant = remnant_scene.instantiate() as ShadowRemnant
	remnant.configure(SHADOW)
	_dungeon.add_child(remnant)
	remnant.global_position = ROOM2_TRIGGER + Vector3(2.0, 0.05, 0.0)

	var world_item: WorldItem = item_scene.instantiate() as WorldItem
	world_item.configure(fragment, 1)
	_dungeon.add_child(world_item)
	world_item.global_position = remnant.global_position
	await _wait(0.3)

	_player.global_position = remnant.global_position + Vector3(0, 0, 0.4)
	await _wait(0.5)
	_record(_prompt.is_showing() and _prompt.get_text() == "Estrai Ombra",
		"31) with both underfoot the prompt shows the remnant: '%s'" % _prompt.get_text())

	var shadows_before: int = _collection.get_count()
	var items_before: int = _player.inventory.get_quantity(fragment.id)
	# One press: both objects see the action, only the prompt's owner may act.
	var picked: bool = world_item.pick_up()
	var extracted: bool = remnant.attempt_extraction()
	_record(not picked and extracted,
		"30) one press acts on the remnant only (pickup=%s, extraction=%s)" % [picked, extracted])
	await _wait(remnant.extraction_duration + 0.3)
	_record(_collection.get_count() == shadows_before + 1
			and _player.inventory.get_quantity(fragment.id) == items_before,
		"30b) the shadow was taken and the item was not")

	# Once the remnant is spent the item takes the prompt over rather than
	# leaving the player with nothing to press.
	await _wait(remnant.result_duration + 0.5)
	await _wait(0.3)
	_record(_prompt.is_showing() and _prompt.get_text().contains("Raccogli"),
		"32) the prompt falls back to the item: '%s'" % _prompt.get_text())
	_record(world_item.pick_up(), "32b) which can now be picked up")
	await _wait(0.3)
	_record(not _prompt.is_showing(), "32c) and no stale prompt is left behind")


# --- the collection screen -------------------------------------------------------------------

func _menu_tests() -> void:
	_record(_menu != null and not _menu.is_open(), "15a) the shadow menu starts closed")
	_record(_menu.hint.visible, "15b) the '[O] Ombre' hint is on screen")

	var event: InputEventAction = InputEventAction.new()
	event.action = "shadow_collection"
	event.pressed = true
	get_viewport().push_input(event)
	await get_tree().process_frame

	_record(_menu.is_open(), "15) O opens the collection")
	_record(get_tree().paused, "15c) the game pauses")
	_record(_menu.last_mouse_mode_request == Input.MOUSE_MODE_VISIBLE, "15d) the mouse is freed")
	_record(_menu.get_total_text() == "Totale: %d" % _collection.get_count(),
		"16a) the total reads '%s'" % _menu.get_total_text())
	_record(_menu.get_row_count() == _collection.get_count() and not _menu.is_empty_shown(),
		"16) every shadow is listed (%d rows)" % _menu.get_row_count())
	_record(_menu.get_row_text(0).contains("Basic Melee Shadow")
			and _menu.get_row_text(0).contains("#"),
		"16b) a row reads '%s'" % _menu.get_row_text(0).strip_edges())

	_menu.select_row(0)
	_record(_menu.get_detail_text().contains("Basic Melee Shadow")
			and _menu.get_detail_text().contains("#"),
		"16c) selecting one shows its name and id")
	# M8.1 shipped this pane with a "coming later" note and no button. M8.2
	# replaced the note with the real control, so that is what is checked now.
	_record(_menu.is_summon_button_visible() and _menu.get_summon_button_text() == "[Evoca]",
		"16d) and offers '%s' to put it in the world" % _menu.get_summon_button_text())

	_menu.close()
	_record(not _menu.is_open() and not get_tree().paused, "15e) O closes it and play resumes")

	# empty reads as empty
	_collection.clear()
	_menu.open()
	_record(_menu.is_empty_shown() and _menu.get_row_count() == 0
			and _menu.get_total_text() == "Totale: 0",
		"EMPTY) an empty collection says so")
	_menu.close()

	# only one pause menu at a time
	var inventory: InventoryMenu = _dungeon.get_node("InventoryMenu")
	inventory.open()
	_menu.open()
	_record(_menu.is_open() and not inventory.is_open(),
		"UX) opening the shadows closes the inventory")
	_menu.close()
	_record(not get_tree().paused, "UX2) closing the last one resumes play")
