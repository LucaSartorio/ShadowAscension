extends SceneTree

## M8.3 across REAL scene changes: does the command mode survive a doorway, does
## the marker survive it, and what does the player's death reset.
##
##   godot --headless --path . --script res://tests/shadows/command_run.gd

const HUB: String = "res://scenes/core/hub.tscn"
const DUNGEON: String = "res://scenes/dungeons/dungeon_test.tscn"
const ROOM1_ANCHOR: Vector3 = Vector3(0, 0.1, -13)

var _data: ShadowData = preload("res://resources/shadows/basic_melee_shadow.tres")
var _pass: int = 0
var _fail: int = 0
var _state: Node = null


func _initialize() -> void:
	_state = root.get_node_or_null("PlayerRuntimeState")
	_state.reset_runtime_state()

	change_scene_to_file(HUB)
	await _pause(0.7)
	var player: Player = current_scene.get_node("Player")
	_record(player.shadow_commander != null, "1) the player carries a commander")
	_record(_state.active_shadow_mode == PlayerRuntimeState.DEFAULT_SHADOW_MODE,
		"2) a new session remembers no mode yet (%d)" % _state.active_shadow_mode)

	var shadow: ShadowInstance = player.shadows.add_shadow(_data)
	var id: StringName = shadow.instance_id
	var node: BasicMeleeShadow = player.shadow_summoner.summon(id)
	await _pause(0.5)
	_record(node != null and node.command_mode == BasicMeleeShadow.CommandMode.AGGRESSIVE,
		"3) a fresh summon starts AGGRESSIVE")

	player.shadow_commander.set_mode(BasicMeleeShadow.CommandMode.FOLLOW)
	await _pause(0.3)
	_record(_state.active_shadow_mode == int(BasicMeleeShadow.CommandMode.FOLLOW),
		"4) switching to FOLLOW is recorded in the session")

	# --- through the gate
	await _enter_dungeon()
	_record(current_scene.scene_file_path == DUNGEON, "5) the gate loaded the dungeon")
	var p2: Player = current_scene.get_node("Player")
	await _pause(0.5)
	_record(p2 != player, "6) on a different Player instance")
	var node2: BasicMeleeShadow = p2.shadow_summoner.get_active_node()
	_record(node2 != null and node2 != node, "7) the shadow re-summoned itself")
	_record(node2 != null and node2.command_mode == BasicMeleeShadow.CommandMode.FOLLOW,
		"8) and came back in FOLLOW, not reset to the default")
	var hud: ActiveShadowHUD = current_scene.get_node("ActiveShadowHUD")
	_record(hud.is_showing(), "9) the HUD picked it up in the new scene")
	_record(hud.get_mode_text().contains("FOLLOW"),
		"10) showing the mode it came back in: '%s'" % hud.get_mode_text())

	# --- a manual order, then the scene changes under it
	p2.hurtbox.set_invulnerable(true)
	p2.global_position = ROOM1_ANCHOR
	await _pause(0.8)
	var enemy: RoomCombatant = (current_scene as DungeonController).get_rooms()[0].get_enemies()[0]
	node2.hurtbox.set_invulnerable(true)
	node2.global_position = enemy.global_position + Vector3(0, 0, 2.0)
	_record(node2.set_manual_target(enemy), "11) an order can be given in the dungeon")
	await _pause(0.4)
	var marker: ShadowTargetMarker = p2.shadow_commander.get_marker()
	_record(marker != null and marker.is_showing(), "12) and the marker is up")

	p2.shadow_commander.set_mode(BasicMeleeShadow.CommandMode.AGGRESSIVE)
	await _pause(0.3)

	# --- the player dies
	p2.hurtbox.set_invulnerable(false)
	p2.health_component.take_damage(DamageInfo.new(1000000.0))
	await _pause(0.4)
	_record(_state.active_shadow_instance_id == &"",
		"13) the player's death clears the active shadow")
	_record(_state.active_shadow_mode == PlayerRuntimeState.DEFAULT_SHADOW_MODE,
		"14) and the remembered mode goes back to the default (%d)" % _state.active_shadow_mode)
	await _pause(2.6)

	var p3: Player = current_scene.get_node("Player")
	await _pause(0.4)
	_record(not p3.shadow_summoner.has_active_shadow(),
		"15) the next run starts with nothing summoned")
	var hud3: ActiveShadowHUD = current_scene.get_node("ActiveShadowHUD")
	_record(not hud3.is_showing(), "16) so the HUD stays hidden")
	var marker3: ShadowTargetMarker = p3.shadow_commander.get_marker()
	_record(marker3 == null or not marker3.is_showing(),
		"17) and no marker was left behind by the old scene")

	var node3: BasicMeleeShadow = p3.shadow_summoner.summon(id)
	await _pause(0.5)
	_record(node3 != null and node3.command_mode == BasicMeleeShadow.CommandMode.AGGRESSIVE,
		"18) a summon after a death starts from AGGRESSIVE again")
	_record(p3.shadows.has_shadow(id), "19) with the shadow itself never lost")
	_record(hud3.is_showing() and hud3.get_mode_text().contains("AGGRESSIVE"),
		"20) and the HUD says so: '%s'" % hud3.get_mode_text())

	# --- a despawn from the menu also forgets the mode
	p3.shadow_commander.set_mode(BasicMeleeShadow.CommandMode.FOLLOW)
	await _pause(0.3)
	p3.shadow_summoner.recall()
	await _pause(0.4)
	_record(_state.active_shadow_mode == PlayerRuntimeState.DEFAULT_SHADOW_MODE,
		"21) despawning forgets the mode too (%d)" % _state.active_shadow_mode)
	_record(not hud3.is_showing(), "22) and takes the HUD with it")

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


func _enter_dungeon() -> void:
	var p: Player = current_scene.get_node("Player")
	var gate: DungeonGate = current_scene.get_node("DungeonGate")
	p.global_position = gate.global_position
	await _pause(0.3)
	gate.activate()
	await _pause(1.3)
