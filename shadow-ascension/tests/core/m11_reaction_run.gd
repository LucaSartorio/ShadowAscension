extends SceneTree

## M11.6 — hit reactions, stagger and knockback through the whole game.
##
##   godot --headless --path . --script res://tests/core/m11_reaction_run.gd
##
## Menu -> New Game -> hub -> gate -> dungeon: an enemy winding up is staggered
## by Light 3 before its swing lands, and goes back to its AI; an enemy swing is
## dodged in the i-frames (stamina paid once, and back); the light combo reacts
## hit by hit and the heavy finishes an enemy without a reaction; a heavy
## staggers and throws the other one back; a heavy killing blow; the shadow's
## kill, its hits only flinching, at 70/30; the boss's swing dodged, the combo
## and the heavy on it — not moved, not interrupted — and its death -> hub ->
## a second dungeon, nobody left staggered or sliding: stagger and knockback
## again, the combo, back to the hub.

const BOOT: String = "res://Main.tscn"
const HUB: String = "res://scenes/core/hub.tscn"
const DT: float = 1.0 / 60.0
const ROOM_ANCHORS: Array[Vector3] = [
	Vector3(0, 0.1, -13), Vector3(0, 0.1, -33), Vector3(0, 0.1, -53)
]
const EXIT_POS: Vector3 = Vector3(0, 0.1, -65)
const STRIKE_RANGE: float = 1.6
const DODGE_LEAD: float = 0.15
## Where the player stands to be swung at by a basic enemy (see m11_dodge_run).
const IN_REACH: float = 1.5

var _shadow_data: ShadowData = preload("res://resources/shadows/basic_melee_shadow.tres")
var _state: Node = null
var _pass: int = 0
var _fail: int = 0
var _expected_player_xp: int = 0
var _expected_shadow_xp: int = 0
## Every hit the player's own hitbox landed, and how its target stood after it.
var _hits: Array[Dictionary] = []


## Criticals are random (M11.7) and this suite checks exact damage, so they are
## off for its whole run: every player here reads this one cached instance of
## the combat data. critical_hit_test and m11_critical_run test criticals.
var _no_crits: PlayerCombatData = preload("res://resources/characters/player_combat.tres")


func _initialize() -> void:
	_no_crits.critical_chance = 0.0
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

	await _phase_into_dungeon(1)
	await _phase_interrupt_and_dodge()
	await _phase_combo_and_heavy()
	await _phase_room_two_and_shadow()
	await _phase_boss()
	await _phase_out_to_hub()
	await _phase_into_dungeon(2)
	await _phase_second_run()

	print("[SUMMARY] passed=%d failed=%d" % [_pass, _fail])
	await _pause(0.3)
	quit()


# --- through the gate: nobody reacting to anything yet ---------------------------------------------

func _phase_into_dungeon(run: int) -> void:
	var p: Player = current_scene.get_node("Player")
	var gate: DungeonGate = current_scene.get_node("DungeonGate")
	p.global_position = gate.global_position
	await _pause(0.4)
	gate.activate()
	await _pause(1.6)
	var dungeon: DungeonController = current_scene as DungeonController
	var fresh: Player = dungeon.get_player()
	var calm: bool = true
	var wired: bool = true
	for enemy in _enemies(dungeon):
		if enemy.is_staggered() or enemy.is_knocked_back() or enemy.is_stagger_immune():
			calm = false
		if enemy.health_component.damaged.get_connections().size() != 1:
			wired = false
	fresh.attack_hitbox.hit_landed.connect(_on_player_hit)
	var count: int = _enemies(dungeon).size()
	_record(current_scene is DungeonController and calm and wired and count == 5,
		"G%d) dungeon %d: all %d enemies standing clean — not staggered, not sliding, not immune — with one reaction listener each" % [run, run, count])


# --- a windup cut short, a swing dodged ------------------------------------------------------------

func _phase_interrupt_and_dodge() -> void:
	var dungeon: DungeonController = current_scene as DungeonController
	var p: Player = dungeon.get_player()
	p.global_position = ROOM_ANCHORS[0]
	await _pause(0.8)
	var enemy: BasicMeleeEnemy = dungeon.get_rooms()[0].get_enemies()[0] as BasicMeleeEnemy
	_park_other(dungeon.get_rooms()[0], enemy)

	# Staggered out of its windup by Light 3.
	var winding: bool = await _until(func() -> bool:
		_step_in(p, enemy)
		return enemy._attack_phase == BasicMeleeEnemy.AttackPhase.STARTUP and enemy._phase_timer > 0.25, 10.0)
	var hp: float = p.health_component.current_health
	var first: int = _hits.size()
	_aim(p, enemy)
	p.combat._start_attack(p.combat.data.light_combo, 2)
	await _until(func() -> bool: return _hits.size() > first or not p.combat.is_attacking(), 1.0)
	var hit: Dictionary = _hits[first] if _hits.size() > first else {}
	await _until(func() -> bool: return not enemy.is_staggered(), 2.0)
	var untouched: bool = p.health_component.current_health == hp
	var awake: Array[BasicMeleeEnemy.State] = [
		BasicMeleeEnemy.State.CHASE, BasicMeleeEnemy.State.ATTACK, BasicMeleeEnemy.State.REPOSITION]
	await _until(func() -> bool: return enemy._state in awake, 1.0)
	_record(winding and hit.get("staggered", false) and hit.get("attack_cut", false) and untouched,
		"E1) an enemy winding up, hit by Light 3: STAGGERED, its swing cut off before it lands — the player keeps %.0f HP" % hp)
	_record(enemy._state != BasicMeleeEnemy.State.STAGGERED and enemy._state != BasicMeleeEnemy.State.IDLE,
		"E2) the stagger over, it is back on its AI (%s)" % BasicMeleeEnemy.State.keys()[enemy._state])

	# Its next swing, dodged in the i-frames, in place.
	await _until(func() -> bool: return p.combat.can_dodge() and p.combat.get_stamina() == p.combat.get_max_stamina(), 5.0)
	var landed: Array[int] = [0]
	var in_iframes: Array[int] = [0]
	var on_landed: Callable = func(target: Node, _info: DamageInfo) -> void:
		if target == p:
			landed[0] += 1
			if p.combat.get_dodge_phase() == PlayerCombat.DodgePhase.INVULNERABLE:
				in_iframes[0] += 1
	enemy.hitbox.hit_landed.connect(on_landed)
	var coming: bool = await _until(func() -> bool:
		_step_in(p, enemy)
		return enemy._attack_phase == BasicMeleeEnemy.AttackPhase.STARTUP and enemy._phase_timer <= DODGE_LEAD, 10.0)
	var speed: float = p.effective_dodge_speed
	p.effective_dodge_speed = 0.0
	hp = p.health_component.current_health
	var stamina: float = p.combat.get_stamina()
	_dodge(p)
	var paid: float = stamina - p.combat.get_stamina()
	await _until(func() -> bool: return not p.combat.is_dodging(), 1.0)
	p.effective_dodge_speed = speed
	enemy.hitbox.hit_landed.disconnect(on_landed)
	_record(coming and in_iframes[0] >= 1 and p.health_component.current_health == hp
			and is_equal_approx(paid, p.combat.data.dodge_stamina_cost),
		"D1) its next swing, dodged: it connects in the i-frames (%d) and takes nothing; the dodge cost %.0f stamina, once" % [in_iframes[0], paid])
	_park(enemy, enemy.global_position)
	await _until(func() -> bool: return p.combat.get_stamina() == p.combat.get_max_stamina(), 4.0)
	_record(p.combat.get_stamina() == p.combat.get_max_stamina(),
		"D2) and stamina regenerates back to %.0f" % p.combat.get_stamina())


# --- the combo reacting hit by hit, the heavy -----------------------------------------------------

func _phase_combo_and_heavy() -> void:
	var dungeon: DungeonController = current_scene as DungeonController
	var p: Player = dungeon.get_player()
	p.hurtbox.set_invulnerable(true)
	var room: RoomController = dungeon.get_rooms()[0]
	var first_enemy: BasicMeleeEnemy = room.get_enemies()[0] as BasicMeleeEnemy
	var second_enemy: BasicMeleeEnemy = room.get_enemies()[1] as BasicMeleeEnemy
	var xp_before: int = p.progression.get_total_xp()

	_park(first_enemy, ROOM_ANCHORS[0] + Vector3(0, 0, -1.5))
	_park(second_enemy, ROOM_ANCHORS[0] + Vector3(6, 0, -1.5))
	await _pause(0.3)
	p.global_position = ROOM_ANCHORS[0]
	_health(first_enemy).current_health = 100.0
	var first: int = _hits.size()
	await _light_combo(p)
	var reactions: Array[String] = []
	for i in range(first, _hits.size()):
		reactions.append("%.0f%s" % [_hits[i]["amount"], "/stagger" if _hits[i]["staggered"] else "/flinch"])
	_record(reactions == ["20/flinch", "25/flinch", "35/stagger"],
		"C1) the light combo on an enemy: each hit reacts — %s" % [reactions])
	first = _hits.size()
	await _heavy_swing(p, first_enemy)
	await _pause(0.3)
	_record(first_enemy.has_died() and _hits.size() == first + 1 and not first_enemy.is_staggered()
			and not first_enemy.is_knocked_back(),
		"C2) the heavy that finishes it: dead at once, no stagger and no push on the killing blow")

	_park(second_enemy, ROOM_ANCHORS[0] + Vector3(0, 0, -1.5))
	await _pause(0.3)
	p.global_position = ROOM_ANCHORS[0]
	var start: Vector3 = second_enemy.global_position
	first = _hits.size()
	await _heavy_swing(p, second_enemy)
	var hit: Dictionary = _hits[first] if _hits.size() > first else {}
	await _until(func() -> bool: return not second_enemy.is_knocked_back(), 1.0)
	var thrown: float = _flat(second_enemy.global_position - start).length()
	_record(hit.get("staggered", false) and is_equal_approx(hit.get("push", 0.0), 8.0) and thrown > 0.9
			and _flat(second_enemy.global_position - start).normalized().dot(Vector3.FORWARD) > 0.98,
		"C3) a heavy on the other: STAGGERED and thrown %.2fm straight back, away from the player" % thrown)
	_park(second_enemy, ROOM_ANCHORS[0] + Vector3(0, 0, -1.5))
	await _pause(0.3)
	p.global_position = ROOM_ANCHORS[0]
	await _light_combo(p)
	await _pause(0.4)
	var paid: int = p.progression.get_total_xp() - xp_before
	_record(second_enemy.has_died() and paid == 50 and room.is_cleared(),
		"C4) both dead, %d XP paid once each, the room clears" % paid)
	_expected_player_xp += paid


# --- room two: a heavy killing blow, the shadow ---------------------------------------------------

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
	_health(c).current_health = 40.0
	var xp_before: int = p.progression.get_total_xp()
	await _heavy_swing(p, c)
	await _pause(0.3)
	var heavy_paid: int = p.progression.get_total_xp() - xp_before
	_record(c.has_died() and heavy_paid == c.get_xp_reward(), "K1) a heavy killing blow pays %d once" % heavy_paid)
	_expected_player_xp += heavy_paid

	var node: BasicMeleeShadow = p.shadow_summoner.get_active_node()
	var d_health: HealthComponent = _health(d)
	d_health.current_health = 30.0
	var shadow_hits: Array[String] = []
	var on_shadow_hit: Callable = func(target: Node, info: DamageInfo) -> void:
		if target == d:
			shadow_hits.append("%.0f%s" % [info.amount, "/stagger" if d.is_staggered() else ""])
	node.attack_hitbox.hit_landed.connect(on_shadow_hit)
	var ever_staggered: Array[bool] = [false]
	var reward: int = d.get_xp_reward()
	var shadow_cut: int = int(round(reward * PlayerProgression.SHADOW_KILL_SHARE))
	var player_before: int = p.progression.get_total_xp()
	var shadow_before: int = _shadow_total_xp(node.instance)
	p.global_position = d.global_position + Vector3(0, 0, 3.0)
	node.global_position = d.global_position + Vector3(0, 0, 2.0)
	node.set_manual_target(d)
	await _until(func() -> bool:
		ever_staggered[0] = ever_staggered[0] or d.is_staggered() or d.is_knocked_back()
		return d.has_died(), 8.0)
	await _pause(0.4)
	node.attack_hitbox.hit_landed.disconnect(on_shadow_hit)
	var player_gain: int = p.progression.get_total_xp() - player_before
	var shadow_gain: int = _shadow_total_xp(node.instance) - shadow_before
	_record(d.has_died() and d.get_killer() == node and not shadow_hits.is_empty() and not ever_staggered[0],
		"SH1) the shadow's hits go through the same damage flow (%s): they flinch its target, nothing more, and kill it" % [shadow_hits])
	_record(shadow_gain == shadow_cut and player_gain == reward - shadow_cut,
		"SH2) the shadow's kill: %d XP -> shadow %d, player %d (got %d / %d)" % [
			reward, shadow_cut, reward - shadow_cut, shadow_gain, player_gain])
	_expected_shadow_xp += shadow_gain
	_expected_player_xp += player_gain


# --- the boss -------------------------------------------------------------------------------------

func _phase_boss() -> void:
	var dungeon: DungeonController = current_scene as DungeonController
	var p: Player = dungeon.get_player()
	p.health_component.heal(p.health_component.max_health)
	p.global_position = ROOM_ANCHORS[2]
	var boss: DungeonBoss = dungeon.get_rooms()[2].get_enemies()[0] as DungeonBoss
	var bar: BossHealthBar = dungeon.get_node("BossHealthBar")
	await _until(func() -> bool: return boss.combat_enabled and bar.is_showing(), 6.0)

	# A boss swing, dodged: what connects in the i-frames takes nothing.
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
		"BO1) a boss swing met in the i-frames connects (%d) and takes nothing" % int(in_iframes[0]))

	# The combo and the heavy on it.
	p.hurtbox.set_invulnerable(true)
	var health: HealthComponent = boss.health_component
	var start: float = health.current_health
	var first: int = _hits.size()
	await _light_combo(p, boss)
	# The heavy, watching the boss for five frames from the moment it lands: a
	# push at 8 m/s would carry it well past what its own feet can.
	_stick(p, boss)
	p.camera_rig.attack_heavy_pressed.emit()
	var at: Vector3 = Vector3.ZERO
	var after: int = -1
	var moved: float = -1.0
	while p.combat.is_attacking():
		await physics_frame
		_stick(p, boss)
		if after < 0 and _hits.size() > first + 3:
			at = boss.global_position
			after = 0
		elif after >= 0 and after < 5:
			after += 1
			if after == 5:
				moved = _flat(boss.global_position - at).length()
	var heavy_hit: Dictionary = _hits[-1] if _hits.size() > first else {}
	var dealt: float = start - health.current_health
	_record(_hits.size() == first + 4 and dealt == 120.0 and is_equal_approx(bar.get_ratio(), health.current_health / health.max_health)
			and heavy_hit.get("info") != null and (heavy_hit["info"] as DamageInfo).stagger_power == 60.0
			and moved >= 0.0 and moved < 0.3,
		"BO2) Light 1/2/3 and the heavy on the boss: %.0f off it, its bar in step; the heavy carried 60 stagger and 8 m/s, and the boss did not budge (%.2fm)" % [
			dealt, moved])
	health.current_health = p.combat.calculate_damage(p.combat.data.heavy_combo[0])
	var xp_before: int = p.progression.get_total_xp()
	await _heavy_swing(p, boss)
	await _pause(0.6)
	var paid: int = p.progression.get_total_xp() - xp_before
	_record(boss.has_died() and paid == boss.get_xp_reward()
			and dungeon.get_state() == DungeonController.DungeonState.COMPLETED,
		"BO3) the boss falls, %d XP once, and the dungeon completes" % paid)
	_expected_player_xp += paid


# --- back to the hub ---------------------------------------------------------------------------------

func _phase_out_to_hub() -> void:
	var dungeon: DungeonController = current_scene as DungeonController
	var p: Player = dungeon.get_player()
	p.hurtbox.set_invulnerable(false)
	p.hurtbox.receive_hit(DamageInfo.new(13.0))
	var health_left: float = p.health_component.current_health
	var level: int = p.progression.current_level
	p.global_position = EXIT_POS
	await _pause(0.4)
	dungeon.exit_portal.activate()
	await _pause(1.6)
	var hub_player: Player = current_scene.get_node("Player")
	_record(current_scene.scene_file_path == HUB and hub_player.progression.get_total_xp() == _expected_player_xp
			and hub_player.progression.current_level == level
			and _shadow_total_xp(_state.shadows[0]) == _expected_shadow_xp,
		"R1) the hub: exactly what was paid — %d XP (level %d), shadow %d XP" % [_expected_player_xp, level, _expected_shadow_xp])
	_record(is_equal_approx(hub_player.health_component.current_health, health_left)
			and hub_player.combat.get_stamina() == hub_player.combat.get_max_stamina(),
		"R2) health carried (%.0f), stamina full" % health_left)
	_record(get_nodes_in_group(Player.GROUP).size() == 1
			and get_nodes_in_group(BasicMeleeShadow.GROUP).size() == 1
			and int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)) == 0,
		"R3) one player, one shadow, no orphan nodes")


# --- the second run -------------------------------------------------------------------------------------

func _phase_second_run() -> void:
	var dungeon: DungeonController = current_scene as DungeonController
	var p: Player = dungeon.get_player()
	p.hurtbox.set_invulnerable(true)
	p.global_position = ROOM_ANCHORS[0]
	await _pause(0.8)
	var room: RoomController = dungeon.get_rooms()[0]
	var enemy: BasicMeleeEnemy = room.get_enemies()[0] as BasicMeleeEnemy
	var other: BasicMeleeEnemy = room.get_enemies()[1] as BasicMeleeEnemy
	_park(other, ROOM_ANCHORS[0] + Vector3(6, 0, -1.5))
	_park(enemy, ROOM_ANCHORS[0] + Vector3(0, 0, -1.5))
	await _pause(0.3)
	p.global_position = ROOM_ANCHORS[0]
	var start: Vector3 = enemy.global_position
	var first: int = _hits.size()
	await _heavy_swing(p, enemy)
	var hit: Dictionary = _hits[first] if _hits.size() > first else {}
	await _until(func() -> bool: return not enemy.is_knocked_back(), 1.0)
	var thrown: float = _flat(enemy.global_position - start).length()
	# Woken while still staggered: the stagger runs out, then the AI picks up.
	enemy.set_combat_enabled(true)
	await _until(func() -> bool: return not enemy.is_staggered(), 1.0)
	var resumed: bool = await _until(func() -> bool: return _flat(p.global_position - enemy.global_position).length() < 2.2, 3.0)
	_record(hit.get("staggered", false) and thrown > 0.9 and resumed,
		"RE1) second dungeon: a heavy staggers an enemy and throws it %.2fm; the stagger over, it comes back at the player" % thrown)
	_park(enemy, ROOM_ANCHORS[0] + Vector3(0, 0, -1.5))
	await _pause(0.3)
	p.global_position = ROOM_ANCHORS[0]
	first = _hits.size()
	await _light_combo(p)
	var reactions: Array[String] = []
	for i in range(first, _hits.size()):
		reactions.append("%s" % ("stagger" if _hits[i]["staggered"] else "flinch"))
	_record(reactions.size() == 3 and reactions[0] == "flinch" and reactions[1] == "flinch" and enemy.has_died(),
		"RE2) and the light combo there reacts the same way, and finishes it (%s)" % [reactions])
	SceneTransition.find_in(self).transition_to_scene(HUB)
	await _pause(1.6)
	_record(current_scene.scene_file_path == HUB
			and int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)) == 0,
		"RE3) back to the hub, nothing orphaned")


# --- helpers ------------------------------------------------------------------------------------------

func _on_player_hit(target: Node, info: DamageInfo) -> void:
	var entry: Dictionary = {"target": target, "info": info, "amount": info.amount}
	var enemy: BasicMeleeEnemy = target as BasicMeleeEnemy
	if enemy != null:
		entry["staggered"] = enemy.is_staggered()
		entry["push"] = enemy.get_knockback_velocity().length()
		entry["attack_cut"] = enemy._attack_phase == BasicMeleeEnemy.AttackPhase.NONE and not enemy.hitbox.is_active()
	_hits.append(entry)


func _enemies(dungeon: DungeonController) -> Array[BasicMeleeEnemy]:
	var found: Array[BasicMeleeEnemy] = []
	for room in dungeon.get_rooms():
		for combatant in room.get_enemies():
			if combatant is BasicMeleeEnemy:
				found.append(combatant as BasicMeleeEnemy)
	return found


func _step_in(p: Player, attacker: Node3D) -> void:
	if p.combat.is_dodging():
		return
	var away: Vector3 = _flat(p.global_position - attacker.global_position)
	if away.length() > IN_REACH:
		p.global_position = attacker.global_position + away.normalized() * IN_REACH + Vector3(0, p.global_position.y - attacker.global_position.y, 0)


func _aim(p: Player, target: Node3D) -> void:
	var to: Vector3 = _flat(target.global_position - p.global_position)
	if to.length_squared() > 0.0001:
		p.camera_rig.rotation.y = atan2(-to.x, -to.z)


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


func _light_combo(p: Player, glue: Node3D = null) -> void:
	p.combat.reset()
	_stick(p, glue)
	_light(p)
	var frames: int = 0
	while p.combat.is_attacking() and frames < 300:
		await physics_frame
		frames += 1
		_stick(p, glue)
		if p.combat.get_state() == PlayerCombat.State.RECOVERY and p.combat.get_queued_attack() == null \
				and p.combat.get_combo_index() < 2:
			_light(p)


func _heavy_swing(p: Player, target: Node3D) -> void:
	_stick(p, target if target is DungeonBoss else null)
	_aim(p, target)
	p.camera_rig.attack_heavy_pressed.emit()
	var frames: int = 0
	while p.combat.is_attacking() and frames < 300:
		await physics_frame
		frames += 1
		_stick(p, target if target is DungeonBoss else null)


func _stick(p: Player, glue: Node3D) -> void:
	if glue != null and is_instance_valid(glue):
		p.global_position = glue.global_position + Vector3(0, 0, STRIKE_RANGE)
		p.camera_rig.rotation.y = 0.0


func _light(p: Player) -> void:
	p.camera_rig.rotation.y = 0.0
	p.camera_rig.attack_light_pressed.emit()


func _park(enemy: RoomCombatant, at: Vector3) -> void:
	enemy.set_combat_enabled(false)
	enemy.velocity = Vector3.ZERO
	enemy.global_position = at


func _park_other(room: RoomController, attacker: RoomCombatant) -> void:
	for enemy in room.get_enemies():
		if enemy != attacker:
			_park(enemy, enemy.global_position + Vector3(8, 0, 0))


func _health(enemy: RoomCombatant) -> HealthComponent:
	return enemy.get_node("HealthComponent") as HealthComponent


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
