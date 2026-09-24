extends SceneTree

## M10.4 — who knows about whom.
##
##   godot --headless --path . --script res://tests/core/decoupling_run.gd
##
## Three things. The main scenes come up on their own, outside any level, and
## either work or stand still — they do not assume a particular world around them.
## The objects that act for a player act for THAT player — the shadow its summoner
## bound it to, the loot and the remnant the player standing on them — rather than
## for whichever player a tree search finds first. And entering the dungeon a
## second time leaves nothing behind from the first: no connection left on the
## tree, no second player, no second shadow, no listener counted twice.

const HUB: String = "res://scenes/core/hub.tscn"
const DUNGEON: String = "res://scenes/dungeons/dungeon_test.tscn"
const PLAYER_SCENE: String = "res://scenes/player/player.tscn"
const ENEMY_SCENE: String = "res://scenes/enemies/basic_melee_enemy.tscn"
const SHADOW_SCENE: String = "res://scenes/shadows/basic_melee_shadow.tscn"
const GATE_SCENE: String = "res://scenes/dungeons/components/dungeon_gate.tscn"
const REMNANT_SCENE: String = "res://scenes/shadows/shadow_remnant.tscn"
const ITEM_SCENE: String = "res://scenes/items/world_item.tscn"
const ROOM1_ANCHOR: Vector3 = Vector3(0, 0.1, -13)
const STRIKE_RANGE: float = 1.6

var _shadow_data: ShadowData = preload("res://resources/shadows/basic_melee_shadow.tres")
var _item: ItemData = preload("res://resources/items/iron_shard.tres")
var _state: Node = null
var _pass: int = 0
var _fail: int = 0
var _real_chance: float = 0.0


func _initialize() -> void:
	_state = root.get_node_or_null("PlayerRuntimeState")
	_state.reset_runtime_state()
	_real_chance = _shadow_data.extraction_chance
	_shadow_data.extraction_chance = 1.0

	await _phase_scenes_in_isolation()
	_state.reset_runtime_state()
	change_scene_to_file(HUB)
	await _pause(0.8)
	await _phase_acting_for_the_right_player()
	await _phase_re_entry()

	_shadow_data.extraction_chance = _real_chance
	_record(is_equal_approx(_shadow_data.extraction_chance, 0.7),
		"Z1) the real extraction chance is restored")
	print("[SUMMARY] passed=%d failed=%d" % [_pass, _fail])
	await _pause(0.3)
	quit()


# --- 1-9. each main scene comes up on its own ------------------------------------------------

func _phase_scenes_in_isolation() -> void:
	var p: Player = (load(PLAYER_SCENE) as PackedScene).instantiate() as Player
	root.add_child(p)
	await _frames(3)
	_record(p.progression.attack_hitbox == p.attack_hitbox
			and p.attack_hitbox.hit_landed.is_connected(p.progression._on_hit_landed),
		"1) a player on its own wires its progression to its own attack hitbox")
	_record(p.equipment.inventory == p.inventory
			and p.shadow_summoner._player == p and p.shadow_summoner._collection == p.shadows
			and p.shadow_commander._player == p and p.shadow_commander._summoner == p.shadow_summoner,
		"2) and hands every component the siblings it needs, with no world around it")
	p.queue_free()
	await _frames(2)

	var enemy: BasicMeleeEnemy = (load(ENEMY_SCENE) as PackedScene).instantiate() as BasicMeleeEnemy
	root.add_child(enemy)
	var start: Vector3 = enemy.global_position
	await _frames(30)
	_record(is_instance_valid(enemy) and enemy._get_player() == null
			and enemy._state == BasicMeleeEnemy.State.IDLE,
		"3) an enemy with no player anywhere stays idle instead of failing")
	# There is no floor out here, so it falls; what matters is that it goes
	# nowhere sideways — there is nobody to chase.
	var drift: float = _horizontal(enemy.global_position - start)
	_record(is_equal_approx(enemy.health_component.current_health, enemy.stats.max_health)
			and drift < 0.05,
		"4) at full health, not moving towards anything (drift %.3f m)" % drift)
	enemy.queue_free()

	var shadow: BasicMeleeShadow = (load(SHADOW_SCENE) as PackedScene).instantiate() as BasicMeleeShadow
	root.add_child(shadow)
	var shadow_start: Vector3 = shadow.global_position
	await _frames(30)
	_record(shadow._get_player() == null,
		"5) a shadow nobody summoned has no owner — it does not go looking for one")
	var shadow_drift: float = _horizontal(shadow.global_position - shadow_start)
	_record(shadow_drift < 0.05,
		"6) and stands still rather than following a stranger (drift %.3f m)" % shadow_drift)
	shadow.queue_free()

	var gate: DungeonGate = (load(GATE_SCENE) as PackedScene).instantiate() as DungeonGate
	root.add_child(gate)
	await _frames(3)
	_record(not gate.is_player_in_range() and not gate.activate(),
		"7) a gate on its own refuses to open with nobody in it")
	gate.queue_free()

	var remnant: ShadowRemnant = (load(REMNANT_SCENE) as PackedScene).instantiate() as ShadowRemnant
	remnant.configure(_shadow_data)
	root.add_child(remnant)
	await _frames(3)
	_record(not remnant.attempt_extraction() and not remnant.has_been_attempted(),
		"8) a remnant on its own refuses an extraction nobody is making")
	remnant.queue_free()

	var item: WorldItem = (load(ITEM_SCENE) as PackedScene).instantiate() as WorldItem
	item.configure(_item, 1)
	root.add_child(item)
	await _frames(3)
	_record(not item.pick_up() and is_instance_valid(item),
		"9) an item on its own stays on the floor with nobody to take it")
	item.queue_free()
	await _frames(2)


# --- 10-16. whoever acts for a player acts for the one in front of it ----------------------

func _phase_acting_for_the_right_player() -> void:
	var p: Player = current_scene.get_node("Player")
	var shadow: ShadowInstance = p.shadows.add_shadow(_shadow_data)
	var node: BasicMeleeShadow = p.shadow_summoner.summon(shadow.instance_id)
	await _pause(0.4)
	_record(node != null and node._get_player() == p,
		"10) a summoned shadow is bound to the player that summoned it")

	var item: WorldItem = (load(ITEM_SCENE) as PackedScene).instantiate() as WorldItem
	item.configure(_item, 2)
	current_scene.add_child(item)
	item.global_position = p.global_position + Vector3(3.0, 0.0, 0.0)
	await _pause(0.3)
	var carried: int = p.inventory.get_quantity(_item.id)
	p.global_position = item.global_position + Vector3(0.0, 0.0, 0.4)
	await _pause(0.4)
	_record(item.pick_up() and p.inventory.get_quantity(_item.id) == carried + 2,
		"11) loot goes into the inventory of the player standing on it")

	var feedback: ExtractionFeedback = current_scene.get_node("ExtractionFeedback")
	var remnant: ShadowRemnant = (load(REMNANT_SCENE) as PackedScene).instantiate() as ShadowRemnant
	remnant.configure(_shadow_data)
	current_scene.add_child(remnant)
	remnant.global_position = p.global_position + Vector3(-3.0, 0.0, 0.0)
	await _pause(0.3)
	p.global_position = remnant.global_position + Vector3(0.0, 0.0, 0.45)
	await _pause(0.4)
	var held: int = p.shadows.get_count()
	_record(remnant.attempt_extraction(), "12) the player standing at a remnant can extract it")
	_record(feedback.is_showing() and feedback.get_title() == feedback.processing_text,
		"13) the banner shows the attempt — it heard the remnant, the remnant never called it")
	await _pause(remnant.extraction_duration + 0.3)
	_record(p.shadows.get_count() == held + 1,
		"14) the shadow lands in that player's collection")
	_record(feedback.get_title() == feedback.success_text,
		"15) and the banner shows the outcome")
	await _pause(remnant.result_duration)

	# Gameplay must not need the UI: with the banner gone, an extraction still
	# lands. Before M10.4 the remnant called the banner itself.
	feedback.free()
	var second: ShadowRemnant = (load(REMNANT_SCENE) as PackedScene).instantiate() as ShadowRemnant
	second.configure(_shadow_data)
	current_scene.add_child(second)
	second.global_position = p.global_position + Vector3(0.0, 0.0, 3.0)
	await _pause(0.3)
	p.global_position = second.global_position + Vector3(0.0, 0.0, 0.45)
	await _pause(0.4)
	var before_second: int = p.shadows.get_count()
	second.attempt_extraction()
	await _pause(second.extraction_duration + 0.3)
	_record(p.shadows.get_count() == before_second + 1,
		"16) with no banner in the scene at all, the extraction still lands")
	await _pause(second.result_duration)


# --- 17-30. Hub -> Gate -> Dungeon -> Hub -> Gate -> Dungeon ---------------------------------

func _phase_re_entry() -> void:
	var first: Dictionary = await _enter_and_measure()
	await _back_to_hub()
	var second: Dictionary = await _enter_and_measure()
	print("[ENTRY 1] %s" % [first])
	print("[ENTRY 2] %s" % [second])

	_record(first["tree_listeners"] == second["tree_listeners"],
		"17) the second entry leaves the tree with as many listeners as the first (%d / %d)" % [
			first["tree_listeners"], second["tree_listeners"]])
	_record(first["players"] == 1 and second["players"] == 1,
		"18) one player each time, never two")
	_record(first["shadows"] == 1 and second["shadows"] == 1,
		"19) one shadow each time: it re-summons itself, and only once")
	_record(first["xp_listeners"] == second["xp_listeners"],
		"20) XP has as many listeners on the second entry as on the first (%d)" % second["xp_listeners"])
	_record(first["summon_listeners"] == second["summon_listeners"],
		"21) and so does summoning (%d)" % second["summon_listeners"])
	_record(second["died_listeners"] == first["died_listeners"],
		"22) and the player's death (%d)" % second["died_listeners"])
	_record(second["own_player"] and second["own_stats"],
		"23) the dungeon holds its own player and its own tally")
	_record(second["objective"] == second["first_objective"],
		"24) and its objective reads '%s' again" % second["objective"])

	# A kill on the second entry pays exactly once, to a player the dungeon and
	# its tally agree on.
	var dungeon: DungeonController = current_scene as DungeonController
	var p: Player = dungeon.get_player()
	p.hurtbox.set_invulnerable(true)
	p.shadow_summoner.recall()
	p.global_position = ROOM1_ANCHOR
	await _pause(0.8)
	var enemy: RoomCombatant = dungeon.get_rooms()[0].get_enemies()[0]
	var before: int = p.progression.get_total_xp()
	var tally_before: int = dungeon.get_run_stats().get_player_xp_earned()
	await _kill(p, enemy)
	await _pause(0.4)
	var gained: int = p.progression.get_total_xp() - before
	_record(gained == enemy.get_xp_reward(),
		"25) a kill on the second entry pays its %d XP once (got %d)" % [enemy.get_xp_reward(), gained])
	_record(dungeon.get_run_stats().get_player_xp_earned() - tally_before == gained,
		"26) and the tally counts the same %d, once" % gained)
	_record(dungeon.get_run_stats().enemies_defeated == 1,
		"27) one kill tallied, not two")
	enemy.enemy_died.emit(enemy)
	await _pause(0.2)
	_record(p.progression.get_total_xp() - before == gained
			and dungeon.get_run_stats().enemies_defeated == 1,
		"28) a repeated death announcement changes neither")
	_record(get_nodes_in_group(Player.GROUP).size() == 1,
		"29) and there is still exactly one player in the tree")
	_record(_state.shadows.size() == 3 and p.shadows.get_count() == 3,
		"30) with the three shadows this session took, no more")


func _enter_and_measure() -> Dictionary:
	var p: Player = current_scene.get_node("Player")
	var gate: DungeonGate = current_scene.get_node("DungeonGate")
	if not p.shadow_summoner.has_active_shadow():
		p.shadow_summoner.summon(p.shadows.get_shadows()[0].instance_id)
		await _pause(0.3)
	p.global_position = gate.global_position
	await _pause(0.3)
	gate.activate()
	await _pause(1.6)
	var dungeon: DungeonController = current_scene as DungeonController
	var here: Player = current_scene.get_node("Player")
	var objective: DungeonObjectiveUI = current_scene.get_node("DungeonObjectiveUI")
	return {
		"tree_listeners": node_added.get_connections().size(),
		"players": get_nodes_in_group(Player.GROUP).size(),
		"shadows": get_nodes_in_group(BasicMeleeShadow.GROUP).size(),
		"xp_listeners": here.progression.xp_changed.get_connections().size(),
		"summon_listeners": here.shadow_summoner.shadow_summoned.get_connections().size(),
		"died_listeners": here.health_component.died.get_connections().size(),
		"own_player": dungeon.get_player() == here,
		"own_stats": dungeon.get_run_stats() == current_scene.get_node("DungeonRunStats"),
		"objective": objective.get_objective(),
		"first_objective": dungeon.objective_advance,
	}


## The same transition the exit portal uses. The portal itself only opens once
## the boss is dead, and re-entry does not need the fight to be fought again.
func _back_to_hub() -> void:
	SceneTransition.find_in(self).transition_to_scene(HUB)
	await _pause(1.6)


func _kill(player: Player, target: RoomCombatant, budget: float = 40.0) -> void:
	var elapsed: float = 0.0
	while elapsed < budget and not target.has_died():
		if player.get("_attack_state") == Player.AttackState.IDLE:
			player.global_position = target.global_position + Vector3(0, 0, STRIKE_RANGE)
			player.camera_rig.rotation.y = 0.0
			player.camera_rig.attack_light_pressed.emit()
		await physics_frame
		elapsed += 1.0 / 60.0


func _horizontal(v: Vector3) -> float:
	return Vector2(v.x, v.z).length()


func _frames(count: int) -> void:
	for i in count:
		await physics_frame


func _pause(t: float) -> void:
	await create_timer(t).timeout


func _record(passed: bool, description: String) -> void:
	if passed:
		_pass += 1
		print("[PASS] " + description)
	else:
		_fail += 1
		print("[FAIL] " + description)
