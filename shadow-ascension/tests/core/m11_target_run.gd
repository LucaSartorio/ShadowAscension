extends SceneTree

## M11.8 — the target lock through the whole game.
##
##   godot --headless --path . --script res://tests/core/m11_target_run.gd
##
## Menu -> New Game -> hub (nothing to lock onto; the shadow in front is not a
## target) -> gate -> dungeon: two enemies, lock one, switch right and back;
## the light combo and the heavy on a target off to the side, the lock turning
## the player to it; the kill lets the lock go; lock the other, dodge while
## locked, a critical and a heavy; a heavy killing blow in the next room; the
## shadow's kill on a locked target, 70/30; the boss locked, its swing dodged,
## hit, killed — the lock lets go, the dungeon completes -> hub -> a second
## dungeon: no lock left over, one indicator, lock and switch again -> hub.
##
## Locks and switches go in as the device sends them (an InputEventAction to
## the player's own handler); attacks are the player's real attacks.

const BOOT: String = "res://Main.tscn"
const HUB: String = "res://scenes/core/hub.tscn"
const DT: float = 1.0 / 60.0
const ROOM_ANCHORS: Array[Vector3] = [
	Vector3(0, 0.1, -13), Vector3(0, 0.1, -33), Vector3(0, 0.1, -53)
]
const EXIT_POS: Vector3 = Vector3(0, 0.1, -65)
const STRIKE_RANGE: float = 1.6
const DODGE_LEAD: float = 0.15

## Criticals are random (M11.7) and this run checks exact damage, so they are
## off for its whole run except where it turns one on: every player here reads
## this one cached instance of the combat data.
var _no_crits: PlayerCombatData = preload("res://resources/characters/player_combat.tres")
var _shadow_data: ShadowData = preload("res://resources/shadows/basic_melee_shadow.tres")
var _state: Node = null
var _pass: int = 0
var _fail: int = 0
var _expected_player_xp: int = 0
var _expected_shadow_xp: int = 0
var _hits: Array[Dictionary] = []
var _changes: Array[String] = []


func _initialize() -> void:
	_no_crits.critical_chance = 0.0
	_state = root.get_node_or_null("PlayerRuntimeState")
	_state.reset_runtime_state()
	change_scene_to_file(BOOT)
	await _pause(0.6)
	(current_scene.get_node("MainMenu") as MainMenu).press_play()
	await _pause(1.4)
	await _phase_hub()
	await _phase_into_dungeon(1)
	await _phase_room_one()
	await _phase_room_two_and_shadow()
	await _phase_boss()
	await _phase_out_to_hub()
	await _phase_into_dungeon(2)
	await _phase_second_run()
	print("[SUMMARY] passed=%d failed=%d" % [_pass, _fail])
	await _pause(0.3)
	quit()


# --- the hub: nothing to lock onto -----------------------------------------------------------------

func _phase_hub() -> void:
	var p: Player = current_scene.get_node("Player")
	var shadow: ShadowInstance = p.shadows.add_shadow(_shadow_data)
	p.shadow_summoner.summon(shadow.instance_id)
	await _pause(0.4)
	p.shadow_commander.set_mode(BasicMeleeShadow.CommandMode.FOLLOW)
	var node: BasicMeleeShadow = p.shadow_summoner.get_active_node()
	p.camera_rig.rotation.y = 0.0
	node.global_position = p.global_position + Vector3(0, 0, -2.0)
	await _lock(p)
	var indicator: TargetLockIndicator = current_scene.get_node("TargetLockIndicator")
	_record(not p.targeting.is_locked() and not indicator.is_showing() and _indicators() == 1,
		"H1) the hub: the lock finds nothing — the shadow standing 2 m in front is no target — and shows nothing")


func _phase_into_dungeon(run: int) -> void:
	var p: Player = current_scene.get_node("Player")
	var gate: DungeonGate = current_scene.get_node("DungeonGate")
	p.global_position = gate.global_position
	await _pause(0.4)
	gate.activate()
	await _pause(1.6)
	var dungeon: DungeonController = current_scene as DungeonController
	var fresh: Player = dungeon.get_player()
	var indicator: TargetLockIndicator = dungeon.get_node("TargetLockIndicator")
	fresh.attack_hitbox.hit_landed.connect(_on_player_hit)
	fresh.targeting.target_changed.connect(_on_target_changed)
	_record(not fresh.targeting.is_locked() and not indicator.is_showing() and indicator.get_target() == null
			and _indicators() == 1 and fresh.targeting.target_changed.get_connections().size() == 2,
		"G%d) dungeon %d: the new player holds no lock, one indicator, hidden, listening once (plus this run)" % [run, run])


# --- room one: lock, switch, combo, heavy, death, dodge ---------------------------------------------

func _phase_room_one() -> void:
	var dungeon: DungeonController = current_scene as DungeonController
	var p: Player = dungeon.get_player()
	var indicator: TargetLockIndicator = dungeon.get_node("TargetLockIndicator")
	p.hurtbox.set_invulnerable(true)
	p.global_position = ROOM_ANCHORS[0]
	await _pause(0.8)
	var room: RoomController = dungeon.get_rooms()[0]
	var first_enemy: BasicEnemy = room.get_enemies()[0] as BasicEnemy
	var second_enemy: BasicEnemy = room.get_enemies()[1] as BasicEnemy
	p.global_position = ROOM_ANCHORS[0]
	p.camera_rig.rotation.y = 0.0
	_park(first_enemy, _at(p, -15.0, 5.0))
	_park(second_enemy, _at(p, 35.0, 5.0))
	await _lock(p)
	var order: Array[String] = [_name(p.targeting.get_target())]
	_press(p, &"target_switch_right")
	order.append(_name(p.targeting.get_target()))
	_press(p, &"target_switch_left")
	order.append(_name(p.targeting.get_target()))
	await process_frame
	_record(order == [String(first_enemy.name), String(second_enemy.name), String(first_enemy.name)]
			and indicator.get_target() == first_enemy,
		"R1) two enemies: the lock takes the one nearer the view, switches right to the other and back; the ring follows (%s)" % [order])

	# The light combo and the heavy on the locked one, off to the side of the camera.
	_park(first_enemy, _at(p, -50.0, 1.5))
	await _frames(3)
	var first: int = _hits.size()
	await _light_combo(p)
	var combo: Array[String] = _sequence(first)
	var start: Vector3 = first_enemy.global_position
	first = _hits.size()
	var xp_before: int = p.progression.get_total_xp()
	_changes.clear()
	await _heavy(p)
	await _pause(0.3)
	_record(combo == ["20/flinch", "25/flinch", "35/stagger"] and p.targeting.get_target() == null,
		"R2) locked on a target 50 deg to the camera's left, the light combo turns to it and lands %s" % [combo])
	_record(first_enemy.has_died() and _hits.size() == first + 1 and _changes == ["-"] and not indicator.is_showing()
			and p.progression.get_total_xp() - xp_before == 25,
		"R3) the heavy kills it (%.2fm from where the combo left it): the lock lets go at once, the ring goes, 25 XP once" % _flat(
			first_enemy.global_position - start).length())

	# The other one: lock, dodge, a critical, the heavy.
	_park(second_enemy, _at(p, 30.0, 6.0))
	await _lock(p)
	var locked_second: bool = p.targeting.get_target() == second_enemy
	Input.action_press("move_left")
	await physics_frame
	var stamina: float = p.combat.get_stamina()
	_press(p, &"dodge")
	var direction: Vector3 = p._dodge_direction
	var paid: float = stamina - p.combat.get_stamina()
	var iframes: bool = await _until(func() -> bool: return p.hurtbox._invulnerable_reasons.has(PlayerCombat.IFRAMES_REASON), 1.0)
	await _until(func() -> bool: return not p.combat.is_dodging(), 1.0)
	Input.action_release("move_left")
	_record(locked_second and direction.distance_to(Vector3.LEFT) < 0.01 and paid == 25.0 and iframes
			and p.targeting.get_target() == second_enemy,
		"R4) locked on the other: a dodge with left held goes left, not at it — 25 stamina, its i-frames — and the lock holds")

	# Let the dodge's slide die out before putting the target within reach.
	await _until(func() -> bool: return Vector2(p.velocity.x, p.velocity.z).length() < 0.01, 1.0)
	_park(second_enemy, _at(p, 40.0, 1.5))
	await _frames(3)
	_no_crits.critical_chance = 1.0
	first = _hits.size()
	await _single_light(p)
	_no_crits.critical_chance = 0.0
	var crit: Dictionary = _hits[first] if _hits.size() > first else {}
	start = second_enemy.global_position
	first = _hits.size()
	await _heavy(p)
	await _until(func() -> bool: return not second_enemy.is_knocked_back(), 1.0)
	var heavy: Dictionary = _hits[first] if _hits.size() > first else {}
	var away: Vector3 = _flat(start - p.global_position).normalized()
	var thrown: Vector3 = _flat(second_enemy.global_position - start)
	_record(crit.get("amount", 0.0) == 30.0 and crit.get("critical", false) and heavy.get("amount", 0.0) == 40.0
			and heavy.get("staggered", false) and thrown.normalized().dot(away) > 0.98 and p.targeting.get_target() == second_enemy,
		"R5) on the locked target: a critical Light 1 for 30, a heavy for 40 that staggers it and throws it %.2fm away — still locked" % thrown.length())
	_park(second_enemy, _at(p, 0.0, 1.5))
	await _frames(3)
	await _heavy(p)
	await _pause(0.4)
	_record(second_enemy.has_died() and not p.targeting.is_locked() and room.is_cleared(),
		"R6) a second heavy kills it, the lock lets go, the room clears")


# --- room two: a killing blow; the shadow's kill on a locked target ------------------------------------

func _phase_room_two_and_shadow() -> void:
	var dungeon: DungeonController = current_scene as DungeonController
	var p: Player = dungeon.get_player()
	p.global_position = ROOM_ANCHORS[1]
	await _pause(0.8)
	var room: RoomController = dungeon.get_rooms()[1]
	var c: BasicEnemy = room.get_enemies()[0] as BasicEnemy
	var d: BasicEnemy = room.get_enemies()[1] as BasicEnemy
	for extra in room.get_enemies().slice(2):
		_park(extra, extra.global_position + Vector3(8, 0, 0))
	p.global_position = ROOM_ANCHORS[1]
	p.camera_rig.rotation.y = 0.0
	_park(d, _at(p, 0.0, 12.0))
	_park(c, _at(p, 0.0, 1.5))
	(c.get_node("HealthComponent") as HealthComponent).current_health = 40.0
	await _lock(p)
	var xp_before: int = p.progression.get_total_xp()
	await _heavy(p)
	await _pause(0.3)
	_record(c.has_died() and not p.targeting.is_locked() and p.progression.get_total_xp() - xp_before == c.get_xp_reward(),
		"K1) locked on, a heavy killing blow: the lock lets go, %d XP once" % c.get_xp_reward())

	var node: BasicMeleeShadow = p.shadow_summoner.get_active_node()
	(d.get_node("HealthComponent") as HealthComponent).current_health = 30.0
	p.global_position = d.global_position + Vector3(0, 0, 3.0)
	node.global_position = d.global_position + Vector3(0, 0, 2.0)
	await _lock(p)
	var locked_d: bool = p.targeting.get_target() == d
	var reward: int = d.get_xp_reward()
	var shadow_cut: int = int(round(reward * PlayerProgression.SHADOW_KILL_SHARE))
	var player_before: int = p.progression.get_total_xp()
	var shadow_before: int = _shadow_total_xp(node.instance)
	node.set_manual_target(d)
	var shadow_kept: Array[bool] = [true]
	await _until(func() -> bool:
		if not d.has_died() and node.get_target() != d:
			shadow_kept[0] = false
		return d.has_died(), 8.0)
	await _pause(0.4)
	var player_gain: int = p.progression.get_total_xp() - player_before
	var shadow_gain: int = _shadow_total_xp(node.instance) - shadow_before
	_record(locked_d and shadow_kept[0] and d.get_killer() == node and not p.targeting.is_locked(),
		"SH1) the player locked on the shadow's target: the shadow keeps its own target and kills it; the player's lock lets go")
	_record(shadow_gain == shadow_cut and player_gain == reward - shadow_cut,
		"SH2) its kill: %d XP -> shadow %d, player %d (got %d / %d)" % [reward, shadow_cut, reward - shadow_cut, shadow_gain, player_gain])
	_expected_shadow_xp += shadow_gain


# --- the boss ---------------------------------------------------------------------------------------

func _phase_boss() -> void:
	var dungeon: DungeonController = current_scene as DungeonController
	var p: Player = dungeon.get_player()
	var indicator: TargetLockIndicator = dungeon.get_node("TargetLockIndicator")
	p.health_component.heal(p.health_component.max_health)
	p.global_position = ROOM_ANCHORS[2]
	var boss: DungeonBoss = dungeon.get_rooms()[2].get_enemies()[0] as DungeonBoss
	var bar: BossHealthBar = dungeon.get_node("BossHealthBar")
	await _until(func() -> bool: return boss.combat_enabled and bar.is_showing(), 6.0)
	_stick(p, boss)
	await _lock(p)
	await process_frame
	var anchor: float = boss.get_target_point().y - boss.global_position.y
	_record(p.targeting.get_target() == boss and indicator.get_target() == boss and is_equal_approx(anchor, 1.5)
			and indicator.global_position.distance_to(boss.get_target_point()) < 0.3,
		"BO1) the boss locks like any enemy, the ring on its own anchor, %.1f m up" % anchor)

	# Its swing, dodged while locked.
	p.hurtbox.set_invulnerable(false)
	var taken: Array[float] = [0.0]
	var on_landed: Callable = func(target: Node, info: DamageInfo) -> void:
		if target == p and p.combat.get_dodge_phase() == PlayerCombat.DodgePhase.INVULNERABLE:
			taken[0] += info.amount if p.health_component.last_damage == info else 0.0
	for hitbox in boss.combat.get_hitboxes():
		if hitbox != null:
			hitbox.hit_landed.connect(on_landed)
	var coming: bool = await _until(func() -> bool:
		_stick(p, boss)
		return boss.get_attack_phase() == BossCombat.Phase.TELEGRAPH and boss.combat.get_phase_remaining() <= DODGE_LEAD, 10.0)
	var speed: float = p.effective_dodge_speed
	p.effective_dodge_speed = 0.0
	var stamina: float = p.combat.get_stamina()
	_press(p, &"dodge")
	var paid: float = stamina - p.combat.get_stamina()
	await _until(func() -> bool: return not p.combat.is_dodging(), 1.0)
	p.effective_dodge_speed = speed
	for hitbox in boss.combat.get_hitboxes():
		if hitbox != null:
			hitbox.hit_landed.disconnect(on_landed)
	p.hurtbox.set_invulnerable(true)
	_record(coming and taken[0] == 0.0 and paid == 25.0 and p.targeting.get_target() == boss,
		"BO2) locked on, a boss swing met in the i-frames takes nothing; the dodge cost 25; the lock holds")

	var health: HealthComponent = boss.health_component
	var hp: float = health.current_health
	await _single_light(p, boss)
	await _heavy(p, boss)
	var dealt: float = hp - health.current_health
	health.current_health = 40.0
	var xp_before: int = p.progression.get_total_xp()
	_changes.clear()
	await _heavy(p, boss)
	await _pause(0.6)
	var paid_xp: int = p.progression.get_total_xp() - xp_before
	_record(dealt == 60.0 and boss.has_died() and _changes == ["-"] and not indicator.is_showing()
			and paid_xp == boss.get_xp_reward() and dungeon.get_state() == DungeonController.DungeonState.COMPLETED,
		"BO3) Light 1 and the heavy land for 60; the finishing heavy kills it: the lock lets go, the ring goes, %d XP, the dungeon completes" % paid_xp)
	_expected_player_xp = p.progression.get_total_xp()


func _phase_out_to_hub() -> void:
	var dungeon: DungeonController = current_scene as DungeonController
	var p: Player = dungeon.get_player()
	var level: int = p.progression.current_level
	p.global_position = EXIT_POS
	await _pause(0.4)
	dungeon.exit_portal.activate()
	await _pause(1.6)
	var hub_player: Player = current_scene.get_node("Player")
	var indicator: TargetLockIndicator = current_scene.get_node("TargetLockIndicator")
	_record(current_scene.scene_file_path == HUB and hub_player.progression.get_total_xp() == _expected_player_xp
			and _expected_player_xp == 282 and hub_player.progression.current_level == level
			and _shadow_total_xp(_state.shadows[0]) == _expected_shadow_xp and _expected_shadow_xp == 18,
		"R7) the hub: 282 XP (level %d), shadow 18 XP" % level)
	_record(not hub_player.targeting.is_locked() and not indicator.is_showing() and _indicators() == 1
			and hub_player.combat.get_stamina() == hub_player.combat.get_max_stamina()
			and int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)) == 0,
		"R8) no lock carried to the hub, one hidden indicator, full stamina, no orphan nodes")


# --- the second run -----------------------------------------------------------------------------------

func _phase_second_run() -> void:
	var dungeon: DungeonController = current_scene as DungeonController
	var p: Player = dungeon.get_player()
	var indicator: TargetLockIndicator = dungeon.get_node("TargetLockIndicator")
	p.hurtbox.set_invulnerable(true)
	p.global_position = ROOM_ANCHORS[0]
	await _pause(0.8)
	var room: RoomController = dungeon.get_rooms()[0]
	var first_enemy: BasicEnemy = room.get_enemies()[0] as BasicEnemy
	var second_enemy: BasicEnemy = room.get_enemies()[1] as BasicEnemy
	p.global_position = ROOM_ANCHORS[0]
	p.camera_rig.rotation.y = 0.0
	_park(first_enemy, _at(p, 35.0, 5.0))
	_park(second_enemy, _at(p, -10.0, 5.0))
	await _lock(p)
	var order: Array[String] = [_name(p.targeting.get_target())]
	_press(p, &"target_switch_right")
	order.append(_name(p.targeting.get_target()))
	_record(order == [String(second_enemy.name), String(first_enemy.name)] and indicator.get_target() == first_enemy,
		"RE1) second dungeon: lock and switch work again (%s), one ring" % [order])
	_park(first_enemy, _at(p, 35.0, 1.5))
	await _frames(3)
	var first: int = _hits.size()
	await _light_combo(p)
	(first_enemy.get_node("HealthComponent") as HealthComponent).current_health = 30.0
	_changes.clear()
	await _heavy(p)
	await _pause(0.3)
	var landed: Array[String] = _sequence(first)
	_record(landed.size() == 4 and landed.slice(0, 3) == ["20/flinch", "25/flinch", "35/stagger"] and first_enemy.has_died()
			and _changes == ["-"] and not p.targeting.is_locked(),
		"RE2) the light combo on the locked target 35 deg to the right lands %s, the heavy finishes it, and its death lets the lock go" % [
			landed.slice(0, 3)])
	SceneTransition.find_in(self).transition_to_scene(HUB)
	await _pause(1.6)
	_record(current_scene.scene_file_path == HUB and not (current_scene.get_node("Player") as Player).targeting.is_locked()
			and _indicators() == 1 and int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)) == 0,
		"RE3) back to the hub: no lock, one indicator, nothing orphaned")


# --- helpers ------------------------------------------------------------------------------------------

func _on_player_hit(target: Node, info: DamageInfo) -> void:
	var entry: Dictionary = {"target": target, "amount": info.amount, "critical": info.is_critical}
	var enemy: BasicEnemy = target as BasicEnemy
	if enemy != null:
		entry["staggered"] = enemy.is_staggered()
	_hits.append(entry)


func _on_target_changed(target: RoomCombatant) -> void:
	_changes.append(_name(target))


func _sequence(first: int) -> Array[String]:
	var out: Array[String] = []
	for i in range(first, _hits.size()):
		out.append("%.0f/%s" % [_hits[i]["amount"], "stagger" if _hits[i].get("staggered", false) else "flinch"])
	return out


func _indicators() -> int:
	return get_nodes_in_group(TargetLockIndicator.GROUP).size()


## The lock button, once the physics space has caught up with whatever was just
## put in place.
func _lock(p: Player) -> void:
	await _frames(2)
	_press(p, &"target_lock")


func _press(p: Player, action: StringName) -> void:
	var event: InputEventAction = InputEventAction.new()
	event.action = action
	event.pressed = true
	p._unhandled_input(event)


## A point `distance` m from the player, `bearing` degrees off the camera's
## view: positive to the right.
func _at(p: Player, bearing: float, distance: float) -> Vector3:
	var forward: Vector3 = _flat(-p.camera_rig.global_basis.z).normalized()
	var right: Vector3 = _flat(p.camera_rig.global_basis.x).normalized()
	var radians: float = deg_to_rad(bearing)
	return p.global_position + (forward * cos(radians) + right * sin(radians)) * distance


func _light_combo(p: Player) -> void:
	p.combat.reset()
	p.camera_rig.attack_light_pressed.emit()
	var frames: int = 0
	while p.combat.is_attacking() and frames < 300:
		await physics_frame
		frames += 1
		if p.combat.get_state() == PlayerCombat.State.RECOVERY and p.combat.get_queued_attack() == null \
				and p.combat.get_combo_index() < 2:
			p.camera_rig.attack_light_pressed.emit()


func _single_light(p: Player, glue: Node3D = null) -> void:
	p.combat.reset()
	_stick(p, glue)
	p.combat._start_attack(p.combat.data.light_combo, 0)
	var frames: int = 0
	while p.combat.is_attacking() and frames < 300:
		await physics_frame
		frames += 1
		_stick(p, glue)


## Bounded: a killing blow on the boss opens the run summary, which pauses the
## tree with the swing still in its recovery.
func _heavy(p: Player, glue: Node3D = null) -> void:
	p.combat.reset()
	_stick(p, glue)
	p.camera_rig.attack_heavy_pressed.emit()
	var frames: int = 0
	while p.combat.is_attacking() and frames < 300:
		await physics_frame
		frames += 1
		_stick(p, glue)


## Keeps the player in front of a moving target; the lock does the aiming.
func _stick(p: Player, glue: Node3D) -> void:
	if glue != null and is_instance_valid(glue):
		p.global_position = glue.global_position + Vector3(0, 0, STRIKE_RANGE)


func _until(condition: Callable, budget: float = 3.0) -> bool:
	var waited: float = 0.0
	while not condition.call():
		if waited >= budget:
			return false
		await physics_frame
		waited += DT
	return true


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _park(enemy: RoomCombatant, at: Vector3) -> void:
	enemy.set_combat_enabled(false)
	enemy.velocity = Vector3.ZERO
	enemy.global_position = at


func _name(target: RoomCombatant) -> String:
	return String(target.name) if target != null else "-"


func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


func _shadow_total_xp(shadow: ShadowInstance) -> int:
	var total: int = shadow.current_xp
	for level in range(1, shadow.level):
		total += shadow.shadow_data.xp_required_for_level(level)
	return total


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
