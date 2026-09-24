extends SceneTree

## M11.7 — critical hits and the damage model through the whole game.
##
##   godot --headless --path . --script res://tests/core/m11_critical_run.gd
##
## Menu -> New Game -> hub -> gate -> dungeon: an enemy's swing dodged; the
## light combo normal / critical / normal, the enemy's bar in step, a critical
## heavy finishing it; a normal heavy staggering and pushing the other, a
## critical one killing it; a critical heavy killing blow; the shadow's kill
## (never critical) at 70/30; the boss's swing dodged, then normal and critical
## light and heavy hits on it and a critical finish -> hub -> a second dungeon on
## the shipped 10% chance: every hit either its raw damage or its critical, the
## combo and the heavy's reactions as ever -> hub.
##
## Each player gets its own copy of the combat data, whose critical chance the
## run sets hit by hit — 0.0 and 1.0 are exact — so every number is known. The
## second dungeon uses the shipped data as it is.

const BOOT: String = "res://Main.tscn"
const HUB: String = "res://scenes/core/hub.tscn"
const DT: float = 1.0 / 60.0
const ROOM_ANCHORS: Array[Vector3] = [
	Vector3(0, 0.1, -13), Vector3(0, 0.1, -33), Vector3(0, 0.1, -53)
]
const EXIT_POS: Vector3 = Vector3(0, 0.1, -65)
const STRIKE_RANGE: float = 1.6
const DODGE_LEAD: float = 0.15
const IN_REACH: float = 1.5

var _shadow_data: ShadowData = preload("res://resources/shadows/basic_melee_shadow.tres")
var _state: Node = null
var _pass: int = 0
var _fail: int = 0
var _expected_player_xp: int = 0
var _expected_shadow_xp: int = 0
var _hits: Array[Dictionary] = []
## The current player's own copy of its combat data.
var _tuned: PlayerCombatData = null


func _initialize() -> void:
	_state = root.get_node_or_null("PlayerRuntimeState")
	_state.reset_runtime_state()
	change_scene_to_file(BOOT)
	await _pause(0.6)
	(current_scene.get_node("MainMenu") as MainMenu).press_play()
	await _pause(1.4)
	var p: Player = current_scene.get_node("Player")
	var shadow: ShadowInstance = p.shadows.add_shadow(_shadow_data)
	p.shadow_summoner.summon(shadow.instance_id)
	await _pause(0.4)
	p.shadow_commander.set_mode(BasicMeleeShadow.CommandMode.FOLLOW)

	await _phase_into_dungeon(true)
	await _phase_dodge()
	await _phase_room_one()
	await _phase_room_two_and_shadow()
	await _phase_boss()
	await _phase_out_to_hub()
	await _phase_into_dungeon(false)
	await _phase_shipped_chance()

	print("[SUMMARY] passed=%d failed=%d" % [_pass, _fail])
	await _pause(0.3)
	quit()


func _phase_into_dungeon(tuned: bool) -> void:
	var p: Player = current_scene.get_node("Player")
	var gate: DungeonGate = current_scene.get_node("DungeonGate")
	p.global_position = gate.global_position
	await _pause(0.4)
	gate.activate()
	await _pause(1.6)
	var fresh: Player = (current_scene as DungeonController).get_player()
	if tuned:
		_tuned = fresh.combat.data.duplicate() as PlayerCombatData
		fresh.combat.data = _tuned
	fresh.attack_hitbox.hit_landed.connect(_on_player_hit)
	var shipped: PlayerCombatData = load("res://resources/characters/player_combat.tres") as PlayerCombatData
	_record(fresh.combat.get_critical_chance() == shipped.critical_chance
			and fresh.combat.get_critical_damage_multiplier() == 1.5 and shipped.critical_chance == 0.1,
		"G%d) the dungeon's player: critical chance %.0f%%, x%.1f, from the shipped data" % [
			1 if tuned else 2, fresh.combat.get_critical_chance() * 100.0, fresh.combat.get_critical_damage_multiplier()])


# --- a swing dodged -----------------------------------------------------------------------------

func _phase_dodge() -> void:
	var dungeon: DungeonController = current_scene as DungeonController
	var p: Player = dungeon.get_player()
	p.global_position = ROOM_ANCHORS[0]
	await _pause(0.8)
	var enemy: BasicMeleeEnemy = dungeon.get_rooms()[0].get_enemies()[0] as BasicMeleeEnemy
	_park_other(dungeon.get_rooms()[0], enemy)
	var in_iframes: Array[int] = [0]
	var on_landed: Callable = func(target: Node, _info: DamageInfo) -> void:
		if target == p and p.combat.get_dodge_phase() == PlayerCombat.DodgePhase.INVULNERABLE:
			in_iframes[0] += 1
	enemy.hitbox.hit_landed.connect(on_landed)
	var coming: bool = await _until(func() -> bool:
		_step_in(p, enemy)
		return enemy._attack_phase == BasicMeleeEnemy.AttackPhase.STARTUP and enemy._phase_timer <= DODGE_LEAD, 10.0)
	var speed: float = p.effective_dodge_speed
	p.effective_dodge_speed = 0.0
	var hp: float = p.health_component.current_health
	var stamina: float = p.combat.get_stamina()
	_dodge(p)
	var paid: float = stamina - p.combat.get_stamina()
	await _until(func() -> bool: return not p.combat.is_dodging(), 1.0)
	p.effective_dodge_speed = speed
	enemy.hitbox.hit_landed.disconnect(on_landed)
	_record(coming and in_iframes[0] >= 1 and p.health_component.current_health == hp and paid == 25.0,
		"D1) an enemy swing met in the i-frames: it connects and takes nothing; the dodge cost 25 stamina")
	_park(enemy, enemy.global_position)
	await _until(func() -> bool: return p.combat.get_stamina() == p.combat.get_max_stamina(), 4.0)
	_record(p.combat.get_stamina() == 100.0, "D2) stamina regenerates to 100")


# --- room one: a mixed combo, criticals and the heavy -------------------------------------------

func _phase_room_one() -> void:
	var dungeon: DungeonController = current_scene as DungeonController
	var p: Player = dungeon.get_player()
	p.hurtbox.set_invulnerable(true)
	var room: RoomController = dungeon.get_rooms()[0]
	var first_enemy: BasicMeleeEnemy = room.get_enemies()[0] as BasicMeleeEnemy
	var second_enemy: BasicMeleeEnemy = room.get_enemies()[1] as BasicMeleeEnemy
	var bar: EnemyHealthBar3D = first_enemy.get_node("EnemyHealthBar3D") as EnemyHealthBar3D
	var xp_before: int = p.progression.get_total_xp()
	_park(second_enemy, ROOM_ANCHORS[0] + Vector3(6, 0, -1.5))
	_park(first_enemy, ROOM_ANCHORS[0] + Vector3(0, 0, -1.5))
	await _pause(0.3)
	p.global_position = ROOM_ANCHORS[0]

	var first: int = _hits.size()
	await _light_combo(p, [0.0, 1.0, 0.0])
	var sequence: Array[String] = _sequence(first)
	_record(sequence == ["20/flinch", "38!/flinch", "35/stagger"]
			and first_enemy.health_component.current_health == 7.0
			and is_equal_approx(bar.get_ratio(), 0.07),
		"C1) the light combo normal / critical / normal: %s — 7 HP left, its bar at 7%%" % [sequence])

	_tuned.critical_chance = 1.0
	first = _hits.size()
	await _heavy(p, first_enemy)
	await _pause(0.3)
	_record(first_enemy.has_died() and _hits.size() == first + 1 and _hits[first]["critical"]
			and not first_enemy.is_staggered() and not first_enemy.is_knocked_back(),
		"C2) a critical heavy finishes it: dead once, no stagger, no push")

	_tuned.critical_chance = 0.0
	_park(second_enemy, ROOM_ANCHORS[0] + Vector3(0, 0, -1.5))
	await _pause(0.3)
	p.global_position = ROOM_ANCHORS[0]
	var start: Vector3 = second_enemy.global_position
	first = _hits.size()
	await _heavy(p, second_enemy)
	await _until(func() -> bool: return not second_enemy.is_knocked_back(), 1.0)
	var normal: Dictionary = _hits[first] if _hits.size() > first else {}
	var thrown: float = _flat(second_enemy.global_position - start).length()
	_record(normal.get("amount", 0.0) == 40.0 and not normal.get("critical", true) and normal.get("staggered", false)
			and is_equal_approx(normal.get("push", 0.0), 8.0) and thrown > 0.9,
		"C3) a normal heavy on the other: 40, staggered, thrown %.2fm" % thrown)
	_tuned.critical_chance = 1.0
	_park(second_enemy, ROOM_ANCHORS[0] + Vector3(0, 0, -1.5))
	await _pause(0.3)
	p.global_position = ROOM_ANCHORS[0]
	first = _hits.size()
	await _heavy(p, second_enemy)
	await _pause(0.4)
	var paid: int = p.progression.get_total_xp() - xp_before
	_record(_hits.size() == first + 1 and _hits[first]["amount"] == 60.0 and second_enemy.has_died()
			and paid == 50 and room.is_cleared(),
		"C4) a critical heavy (60) on its last 60 HP kills it; both paid once, %d XP, the room clears" % paid)
	_expected_player_xp += paid
	_tuned.critical_chance = 0.0


# --- room two: a critical killing blow, the shadow ------------------------------------------------

func _phase_room_two_and_shadow() -> void:
	var dungeon: DungeonController = current_scene as DungeonController
	var p: Player = dungeon.get_player()
	p.global_position = ROOM_ANCHORS[1]
	await _pause(0.8)
	var room: RoomController = dungeon.get_rooms()[1]
	var c: RoomCombatant = room.get_enemies()[0]
	var d: BasicMeleeEnemy = room.get_enemies()[1] as BasicMeleeEnemy
	_park(c, ROOM_ANCHORS[1] + Vector3(0, 0, -1.5))
	await _pause(0.2)
	p.global_position = ROOM_ANCHORS[1]
	(c.get_node("HealthComponent") as HealthComponent).current_health = 50.0
	_tuned.critical_chance = 1.0
	var xp_before: int = p.progression.get_total_xp()
	await _heavy(p, c)
	await _pause(0.3)
	var heavy_paid: int = p.progression.get_total_xp() - xp_before
	_record(c.has_died() and heavy_paid == c.get_xp_reward(),
		"K1) a critical heavy killing blow on 50 HP pays %d once" % heavy_paid)
	_expected_player_xp += heavy_paid
	_tuned.critical_chance = 0.0

	var node: BasicMeleeShadow = p.shadow_summoner.get_active_node()
	(d.get_node("HealthComponent") as HealthComponent).current_health = 30.0
	var shadow_hits: Array[String] = []
	var on_shadow_hit: Callable = func(target: Node, info: DamageInfo) -> void:
		if target == d:
			shadow_hits.append("%.0f%s" % [info.amount, "!" if info.is_critical else ""])
	node.attack_hitbox.hit_landed.connect(on_shadow_hit)
	var reward: int = d.get_xp_reward()
	var shadow_cut: int = int(round(reward * PlayerProgression.SHADOW_KILL_SHARE))
	var player_before: int = p.progression.get_total_xp()
	var shadow_before: int = _shadow_total_xp(node.instance)
	var shadow_damage: float = node.get_attack_damage()
	p.global_position = d.global_position + Vector3(0, 0, 3.0)
	node.global_position = d.global_position + Vector3(0, 0, 2.0)
	node.set_manual_target(d)
	await _until(func() -> bool: return d.has_died(), 8.0)
	await _pause(0.4)
	node.attack_hitbox.hit_landed.disconnect(on_shadow_hit)
	var player_gain: int = p.progression.get_total_xp() - player_before
	var shadow_gain: int = _shadow_total_xp(node.instance) - shadow_before
	var plain: bool = not shadow_hits.is_empty()
	for entry in shadow_hits:
		if entry != "%.0f" % shadow_damage:
			plain = false
	_record(d.has_died() and d.get_killer() == node and plain,
		"SH1) the shadow's hits are never critical, its damage as before: %s" % [shadow_hits])
	_record(shadow_gain == shadow_cut and player_gain == reward - shadow_cut,
		"SH2) its kill: %d XP -> shadow %d, player %d (got %d / %d)" % [
			reward, shadow_cut, reward - shadow_cut, shadow_gain, player_gain])
	_expected_shadow_xp += shadow_gain
	_expected_player_xp += player_gain


# --- the boss ---------------------------------------------------------------------------------------

func _phase_boss() -> void:
	var dungeon: DungeonController = current_scene as DungeonController
	var p: Player = dungeon.get_player()
	p.health_component.heal(p.health_component.max_health)
	p.global_position = ROOM_ANCHORS[2]
	var boss: DungeonBoss = dungeon.get_rooms()[2].get_enemies()[0] as DungeonBoss
	var bar: BossHealthBar = dungeon.get_node("BossHealthBar")
	await _until(func() -> bool: return boss.combat_enabled and bar.is_showing(), 6.0)

	p.hurtbox.set_invulnerable(false)
	var in_iframes: Array[float] = [0.0, 0.0]
	var on_landed: Callable = func(target: Node, info: DamageInfo) -> void:
		if target == p and p.combat.get_dodge_phase() == PlayerCombat.DodgePhase.INVULNERABLE:
			in_iframes[0] += 1.0
			in_iframes[1] += info.amount if p.health_component.last_damage == info else 0.0
	for hitbox in boss._hitboxes:
		if hitbox != null:
			hitbox.hit_landed.connect(on_landed)
	var coming: bool = await _until(func() -> bool:
		_stick(p, boss)
		return boss.get_attack_phase() == DungeonBoss.AttackPhase.STARTUP and boss._phase_timer <= DODGE_LEAD, 10.0)
	var speed: float = p.effective_dodge_speed
	p.effective_dodge_speed = 0.0
	_dodge(p)
	await _until(func() -> bool: return not p.combat.is_dodging(), 1.0)
	p.effective_dodge_speed = speed
	for hitbox in boss._hitboxes:
		if hitbox != null:
			hitbox.hit_landed.disconnect(on_landed)
	_record(coming and in_iframes[0] >= 1.0 and in_iframes[1] == 0.0,
		"BO1) a boss swing met in the i-frames takes nothing")

	p.hurtbox.set_invulnerable(true)
	var health: HealthComponent = boss.health_component
	var taken: Array[float] = []
	for step in [[false, 0.0], [false, 1.0], [true, 0.0], [true, 1.0]]:
		_tuned.critical_chance = step[1]
		var hp: float = health.current_health
		if step[0]:
			await _heavy(p, boss)
		else:
			await _single_light(p, boss)
		taken.append(hp - health.current_health)
	_record(taken == [20.0, 30.0, 40.0, 60.0] and is_equal_approx(bar.get_ratio(), health.current_health / health.max_health),
		"BO2) the boss takes Light 1 normal / critical and the heavy normal / critical: %s, its bar in step" % [taken])
	health.current_health = 60.0
	_tuned.critical_chance = 1.0
	var xp_before: int = p.progression.get_total_xp()
	await _heavy(p, boss)
	await _pause(0.6)
	var paid: int = p.progression.get_total_xp() - xp_before
	_record(boss.has_died() and paid == boss.get_xp_reward()
			and dungeon.get_state() == DungeonController.DungeonState.COMPLETED,
		"BO3) a critical heavy finishes it: %d XP once, the dungeon completes" % paid)
	_expected_player_xp += paid
	_tuned.critical_chance = 0.0


func _phase_out_to_hub() -> void:
	var dungeon: DungeonController = current_scene as DungeonController
	var p: Player = dungeon.get_player()
	var level: int = p.progression.current_level
	p.global_position = EXIT_POS
	await _pause(0.4)
	dungeon.exit_portal.activate()
	await _pause(1.6)
	var hub_player: Player = current_scene.get_node("Player")
	_record(current_scene.scene_file_path == HUB and hub_player.progression.get_total_xp() == _expected_player_xp
			and hub_player.progression.current_level == level
			and _shadow_total_xp(_state.shadows[0]) == _expected_shadow_xp
			and hub_player.combat.get_stamina() == hub_player.combat.get_max_stamina(),
		"R1) the hub: %d XP (level %d), shadow %d XP — criticals paid nobody twice; stamina full" % [
			_expected_player_xp, level, _expected_shadow_xp])
	_record(get_nodes_in_group(Player.GROUP).size() == 1
			and int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)) == 0,
		"R2) one player, no orphan nodes")


# --- the shipped chance ----------------------------------------------------------------------------

func _phase_shipped_chance() -> void:
	var dungeon: DungeonController = current_scene as DungeonController
	var p: Player = dungeon.get_player()
	p.hurtbox.set_invulnerable(true)
	p.global_position = ROOM_ANCHORS[0]
	await _pause(0.8)
	var room: RoomController = dungeon.get_rooms()[0]
	var enemy: BasicMeleeEnemy = room.get_enemies()[0] as BasicMeleeEnemy
	_park(room.get_enemies()[1], ROOM_ANCHORS[0] + Vector3(6, 0, -1.5))
	var first: int = _hits.size()
	var consistent: bool = true
	for i in 6:
		_park(enemy, ROOM_ANCHORS[0] + Vector3(0, 0, -1.5))
		# Enough that no run of criticals kills it mid-combo.
		enemy.health_component.current_health = 1000.0
		await _pause(0.2)
		p.global_position = ROOM_ANCHORS[0]
		await _light_combo(p, [])
	for i in range(first, _hits.size()):
		var info: DamageInfo = _hits[i]["info"]
		var raw: float = p.combat.calculate_damage(_attack_named(p, info.attack_id))
		var expected: float = DamageModel.final_damage(raw, info.is_critical, 1.5)
		if info.amount != expected:
			consistent = false
	var staggers: Array[bool] = []
	for i in range(first, _hits.size()):
		staggers.append(_hits[i]["staggered"])
	var reactions_hold: bool = true
	for i in range(first, _hits.size()):
		if _hits[i]["staggered"] != (_hits[i]["info"].attack_id == &"light_attack_3"):
			reactions_hold = false
	_record(_hits.size() - first == 18 and consistent and reactions_hold,
		"S1) second dungeon, the shipped 10%%: 18 hits, each its raw damage or its critical (%d critical), each staggering exactly as its attack does" % _count_critical(first))
	SceneTransition.find_in(self).transition_to_scene(HUB)
	await _pause(1.6)
	_record(current_scene.scene_file_path == HUB
			and int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)) == 0,
		"S2) back to the hub, nothing orphaned")


# --- helpers ------------------------------------------------------------------------------------------

func _on_player_hit(target: Node, info: DamageInfo) -> void:
	var entry: Dictionary = {"target": target, "info": info, "amount": info.amount, "critical": info.is_critical}
	var enemy: BasicMeleeEnemy = target as BasicMeleeEnemy
	if enemy != null:
		entry["staggered"] = enemy.is_staggered()
		entry["push"] = enemy.get_knockback_velocity().length()
	_hits.append(entry)


func _sequence(first: int) -> Array[String]:
	var out: Array[String] = []
	for i in range(first, _hits.size()):
		out.append("%.0f%s/%s" % [_hits[i]["amount"], "!" if _hits[i]["critical"] else "",
			"stagger" if _hits[i].get("staggered", false) else "flinch"])
	return out


func _count_critical(first: int) -> int:
	var n: int = 0
	for i in range(first, _hits.size()):
		n += 1 if _hits[i]["critical"] else 0
	return n


func _attack_named(p: Player, id: StringName) -> AttackData:
	for attack in p.combat.data.light_combo + p.combat.data.heavy_combo:
		if attack.id == id:
			return attack
	return null


## The light combo, with the critical chance for each hit set before its window
## opens (none given: the data's own).
func _light_combo(p: Player, chances: Array) -> void:
	p.combat.reset()
	p.camera_rig.rotation.y = 0.0
	if not chances.is_empty():
		_tuned.critical_chance = chances[0]
	p.camera_rig.attack_light_pressed.emit()
	var frames: int = 0
	while p.combat.is_attacking() and frames < 300:
		await physics_frame
		frames += 1
		if p.combat.get_state() == PlayerCombat.State.RECOVERY and p.combat.get_queued_attack() == null \
				and p.combat.get_combo_index() < 2:
			if chances.size() > p.combat.get_combo_index() + 1:
				_tuned.critical_chance = chances[p.combat.get_combo_index() + 1]
			p.camera_rig.attack_light_pressed.emit()


func _single_light(p: Player, target: Node3D) -> void:
	p.combat.reset()
	_stick(p, target)
	p.combat._start_attack(p.combat.data.light_combo, 0)
	var frames: int = 0
	while p.combat.is_attacking() and frames < 300:
		await physics_frame
		frames += 1
		_stick(p, target)


func _heavy(p: Player, target: Node3D) -> void:
	p.combat.reset()
	var glue: Node3D = target if target is DungeonBoss else null
	_stick(p, glue)
	_aim(p, target)
	p.camera_rig.attack_heavy_pressed.emit()
	# Bounded: a killing blow on the boss opens the run summary, which pauses the
	# tree with the swing still in its recovery.
	var frames: int = 0
	while p.combat.is_attacking() and frames < 300:
		await physics_frame
		frames += 1
		_stick(p, glue)


func _stick(p: Player, glue: Node3D) -> void:
	if glue != null and is_instance_valid(glue):
		p.global_position = glue.global_position + Vector3(0, 0, STRIKE_RANGE)
		p.camera_rig.rotation.y = 0.0


func _aim(p: Player, target: Node3D) -> void:
	var to: Vector3 = _flat(target.global_position - p.global_position)
	if to.length_squared() > 0.0001:
		p.camera_rig.rotation.y = atan2(-to.x, -to.z)


func _step_in(p: Player, attacker: Node3D) -> void:
	if p.combat.is_dodging():
		return
	var away: Vector3 = _flat(p.global_position - attacker.global_position)
	if away.length() > IN_REACH:
		p.global_position = attacker.global_position + away.normalized() * IN_REACH + Vector3(0, p.global_position.y - attacker.global_position.y, 0)


func _until(condition: Callable, budget: float = 3.0) -> bool:
	var waited: float = 0.0
	while not condition.call():
		if waited >= budget:
			return false
		await physics_frame
		waited += DT
	return true


func _dodge(p: Player) -> void:
	var event: InputEventAction = InputEventAction.new()
	event.action = &"dodge"
	event.pressed = true
	p._unhandled_input(event)


func _park(enemy: RoomCombatant, at: Vector3) -> void:
	enemy.set_combat_enabled(false)
	enemy.velocity = Vector3.ZERO
	enemy.global_position = at


func _park_other(room: RoomController, attacker: RoomCombatant) -> void:
	for enemy in room.get_enemies():
		if enemy != attacker:
			_park(enemy, enemy.global_position + Vector3(8, 0, 0))


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
