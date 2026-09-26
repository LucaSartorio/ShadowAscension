extends SceneTree

## M11.4 — the dodge and its i-frames through the whole game, against real attacks.
##
##   godot --headless --path . --script res://tests/core/m11_dodge_run.gd
##
## Menu -> New Game -> hub -> gate (left mid-dodge, in the i-frames) -> dungeon:
## an enemy's swing taken, the next one dodged, the one after taken again; the
## light combo and the heavy; the shadow's kill; the boss's swings taken and
## dodged the same way, then a dodge, the combo and the heavy on it, and its death
## -> hub (left mid-dodge again) -> a second dungeon: dodge an enemy again.
##
## The enemies and the boss attack on their own; nothing tells them the player is
## dodging. To test the i-frames and not the evasion, the dodges that meet an
## attack are made in place (the player's dodge speed held at 0 for them): the
## swing reaches the player, the hurtbox decides.

const BOOT: String = "res://Main.tscn"
const HUB: String = "res://scenes/core/hub.tscn"
const ROOM_ANCHORS: Array[Vector3] = [
	Vector3(0, 0.1, -13), Vector3(0, 0.1, -33), Vector3(0, 0.1, -53)
]
const EXIT_POS: Vector3 = Vector3(0, 0.1, -65)
const STRIKE_RANGE: float = 1.6
## Dodge this long before a swing's hit window opens: inside the i-frames with
## room to spare on both sides (they run from 0.06s to 0.24s into the dodge).
const DODGE_LEAD: float = 0.15
## Where the player stands to be swung at by a basic enemy: inside its 1.8m
## attack range. An enemy holds its ring slot to within the navigation's 0.25m
## tolerance and can stop just outside that range, so a player who never moves
## can go unattacked; this one steps in, as a player would.
const IN_REACH: float = 1.5

var _shadow_data: ShadowData = preload("res://resources/shadows/basic_melee_shadow.tres")
var _state: Node = null
var _pass: int = 0
var _fail: int = 0
var _expected_player_xp: int = 0
var _expected_shadow_xp: int = 0
var _first_listeners: Dictionary = {}
## Every hit an attacker landed on the player while watched: the dodge phase it
## arrived in, and the health it cost.
var _hits: Array[Dictionary] = []
var _watched: Player = null
## The attacker the player keeps stepping in to, or null.
var _reach: Node3D = null


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
	await _phase_enemy_swings()
	await _phase_combat_and_shadow()
	await _phase_boss()
	await _phase_out_to_hub()
	await _phase_into_dungeon(2)
	await _phase_second_run()

	print("[SUMMARY] passed=%d failed=%d" % [_pass, _fail])
	await _pause(0.3)
	quit()


# --- through the gate mid-dodge ------------------------------------------------------------------

func _phase_into_dungeon(run: int) -> void:
	var p: Player = current_scene.get_node("Player")
	var gate: DungeonGate = current_scene.get_node("DungeonGate")
	var prompt: InteractionPrompt = current_scene.get_node("InteractionPrompt")
	p.global_position = gate.global_position
	await _pause(0.4)
	_record(prompt.is_showing() and prompt.get_text() == gate.prompt_text,
		"G%d.1) the gate prompts '%s'" % [run, prompt.get_text()])
	var at_exit: Dictionary = await _leave_mid_dodge(p, func() -> void: gate.activate())
	var dungeon: DungeonController = current_scene as DungeonController
	var fresh: Player = dungeon.get_player()
	await _pause(0.3)
	_record(at_exit.get("phase") == PlayerCombat.DodgePhase.INVULNERABLE and at_exit.get("invulnerable") == true
			and _clean(fresh),
		"G%d.2) left in the i-frames of a dodge: the dungeon's player is not invulnerable, not dodging, free, standing still" % run)
	var listeners: Dictionary = _listeners(fresh)
	if run == 1:
		_first_listeners = listeners
	else:
		_record(listeners == _first_listeners,
			"G2.3) the second dungeon's player has exactly the first one's listeners: %s" % [listeners])


# --- an enemy's swings: taken, dodged, taken -------------------------------------------------------

func _phase_enemy_swings() -> void:
	var dungeon: DungeonController = current_scene as DungeonController
	var p: Player = dungeon.get_player()
	var hud: PlayerHealthHUD = dungeon.get_node("PlayerHealthHUD")
	p.global_position = ROOM_ANCHORS[0]
	await _pause(0.8)
	var enemy: BasicEnemy = dungeon.get_rooms()[0].get_enemies()[0] as BasicEnemy
	_park_other(dungeon.get_rooms()[0], enemy)
	var outcome: Dictionary = await _take_dodge_take(p, [enemy.attack.hitbox], func() -> bool:
		return enemy.get_attack_phase() == EnemyAttack.Phase.TELEGRAPH and enemy.attack.get_phase_remaining() <= DODGE_LEAD,
		hud, enemy)
	_record(outcome["taken_before"] > 0.0 and outcome["hud_before"],
		"E1) an enemy's swing on a standing player takes %.0f HP, and the health HUD shows it" % outcome["taken_before"])
	_record(outcome["connected_in_iframes"] > 0 and outcome["taken_in_iframes"] == 0.0 and outcome["hud_unchanged"],
		"E2) its next swing, dodged: it connects in the i-frames (%d hit) and takes nothing; the HUD does not move" % outcome["connected_in_iframes"])
	_record(outcome["taken_after"] > 0.0 and outcome["hud_after"],
		"E3) the swing after the dodge takes %.0f HP again, and the HUD follows" % outcome["taken_after"])
	_record(not p.hurtbox.is_invulnerable and p.combat.get_dodge_phase() == PlayerCombat.DodgePhase.NONE,
		"E4) and nothing of the dodge is left: vulnerable, no dodge phase")


# --- the light combo, the heavy, the shadow ---------------------------------------------------------

func _phase_combat_and_shadow() -> void:
	var dungeon: DungeonController = current_scene as DungeonController
	var p: Player = dungeon.get_player()
	p.hurtbox.set_invulnerable(true)
	var room: RoomController = dungeon.get_rooms()[0]
	var xp_before: int = p.progression.get_total_xp()
	for enemy in room.get_enemies():
		_park(enemy, ROOM_ANCHORS[0] + Vector3(0, 0, -1.5))
		await _pause(0.2)
		p.global_position = ROOM_ANCHORS[0]
		_health(enemy).current_health = 100.0
		var started: Array[StringName] = await _light_combo(p)
		started.append_array(await _heavy_swing(p))
		_record(started == [&"light_attack_1", &"light_attack_2", &"light_attack_3", &"heavy_attack_1"]
				and enemy.has_died() and _health(enemy).last_damage.attack_id == &"heavy_attack_1",
			"C-%s) after the dodging, the light combo (80) and the heavy (40) still finish an enemy" % enemy.name)
	await _pause(0.4)
	var paid: int = p.progression.get_total_xp() - xp_before
	_record(paid == 50 and room.is_cleared(), "C1) both paid once, %d XP, and the room clears" % paid)
	_expected_player_xp += paid

	p.global_position = ROOM_ANCHORS[1]
	await _pause(0.8)
	var room_2: RoomController = dungeon.get_rooms()[1]
	var c: RoomCombatant = room_2.get_enemies()[0]
	var d: RoomCombatant = room_2.get_enemies()[1]
	_park(c, ROOM_ANCHORS[1] + Vector3(0, 0, -1.5))
	await _pause(0.2)
	p.global_position = ROOM_ANCHORS[1]
	_health(c).current_health = 40.0
	xp_before = p.progression.get_total_xp()
	await _heavy_swing(p)
	await _pause(0.3)
	var heavy_paid: int = p.progression.get_total_xp() - xp_before
	_record(c.has_died() and heavy_paid == c.get_xp_reward(), "C2) a heavy killing blow pays %d once" % heavy_paid)
	_expected_player_xp += heavy_paid

	var node: BasicMeleeShadow = p.shadow_summoner.get_active_node()
	var d_health: HealthComponent = _health(d)
	d_health.current_health = 1.0
	var reward: int = d.get_xp_reward()
	var shadow_cut: int = int(round(reward * PlayerProgression.SHADOW_KILL_SHARE))
	var player_before: int = p.progression.get_total_xp()
	var shadow_before: int = _shadow_total_xp(node.instance)
	p.global_position = d.global_position + Vector3(0, 0, 3.0)
	node.global_position = d.global_position + Vector3(0, 0, 2.0)
	node.set_manual_target(d)
	var waited: float = 0.0
	while waited < 8.0 and not d.has_died():
		await physics_frame
		waited += 1.0 / 60.0
	await _pause(0.4)
	var player_gain: int = p.progression.get_total_xp() - player_before
	var shadow_gain: int = _shadow_total_xp(node.instance) - shadow_before
	_record(d.has_died() and d.get_killer() == node and shadow_gain == shadow_cut
			and player_gain == reward - shadow_cut,
		"SH1) the shadow's kill, unchanged by the dodge: %d XP -> shadow %d, player %d (got %d / %d)" % [
			reward, shadow_cut, reward - shadow_cut, shadow_gain, player_gain])
	_expected_shadow_xp += shadow_gain
	_expected_player_xp += player_gain
	p.hurtbox.set_invulnerable(false)


# --- the boss ---------------------------------------------------------------------------------------

func _phase_boss() -> void:
	var dungeon: DungeonController = current_scene as DungeonController
	var p: Player = dungeon.get_player()
	var hud: PlayerHealthHUD = dungeon.get_node("PlayerHealthHUD")
	p.health_component.heal(p.health_component.max_health)
	p.global_position = ROOM_ANCHORS[2]
	var boss: DungeonBoss = dungeon.get_rooms()[2].get_enemies()[0] as DungeonBoss
	var bar: BossHealthBar = dungeon.get_node("BossHealthBar")
	var waited: float = 0.0
	while waited < 6.0 and not (boss.combat_enabled and bar.is_showing()):
		await _pause(0.1)
		waited += 0.1
	var outcome: Dictionary = await _take_dodge_take(p, boss.combat.get_hitboxes(), func() -> bool:
		return boss.get_attack_phase() == BossCombat.Phase.TELEGRAPH and boss.combat.get_phase_remaining() <= DODGE_LEAD,
		hud)
	_record(outcome["taken_before"] > 0.0, "BO1) a boss swing on a standing player takes %.0f HP" % outcome["taken_before"])
	_record(outcome["connected_in_iframes"] > 0 and outcome["taken_in_iframes"] == 0.0 and outcome["hud_unchanged"],
		"BO2) a boss swing in the i-frames connects (%d hit) and takes nothing; the HUD does not move" % outcome["connected_in_iframes"])
	_record(outcome["taken_after"] > 0.0, "BO3) the boss's next swing after the dodge takes %.0f HP again" % outcome["taken_after"])

	# A real dodge, then the combo and the heavy on the boss.
	p.hurtbox.set_invulnerable(true)
	_dodge(p)
	while p.combat.is_dodging():
		await physics_frame
	var health: HealthComponent = boss.health_component
	var start: float = health.current_health
	var started: Array[StringName] = await _light_combo(p, boss)
	started.append_array(await _heavy_swing(p, boss))
	var dealt: float = start - health.current_health
	_record(started == [&"light_attack_1", &"light_attack_2", &"light_attack_3", &"heavy_attack_1"]
			and dealt == 120.0 and is_equal_approx(bar.get_ratio(), health.current_health / health.max_health),
		"BO4) a dodge, then the combo and the heavy on the boss: %.0f off it, its bar in step" % dealt)
	health.current_health = p.combat.calculate_damage(p.combat.data.heavy_combo[0])
	var xp_before: int = p.progression.get_total_xp()
	await _heavy_swing(p, boss)
	await _pause(0.6)
	var paid: int = p.progression.get_total_xp() - xp_before
	_record(boss.has_died() and paid == boss.get_xp_reward()
			and dungeon.get_state() == DungeonController.DungeonState.COMPLETED,
		"BO5) the boss falls, %d XP once, and the dungeon completes" % paid)
	_expected_player_xp += paid


# --- back to the hub, mid-dodge --------------------------------------------------------------------

func _phase_out_to_hub() -> void:
	var dungeon: DungeonController = current_scene as DungeonController
	var p: Player = dungeon.get_player()
	p.hurtbox.set_invulnerable(false)
	p.hurtbox.receive_hit(DamageInfo.new(13.0))
	var health_left: float = p.health_component.current_health
	var level: int = p.progression.current_level
	p.global_position = EXIT_POS
	await _pause(0.4)
	var at_exit: Dictionary = await _leave_mid_dodge(p, func() -> void: dungeon.exit_portal.activate())
	var hub_player: Player = current_scene.get_node("Player")
	await _pause(0.3)
	_record(current_scene.scene_file_path == HUB and at_exit.get("phase") == PlayerCombat.DodgePhase.INVULNERABLE
			and _clean(hub_player),
		"R1) left the dungeon in the i-frames: the hub's player is not invulnerable, not dodging, free")
	_record(hub_player.progression.get_total_xp() == _expected_player_xp
			and hub_player.progression.current_level == level
			and _shadow_total_xp(_state.shadows[0]) == _expected_shadow_xp,
		"R2) the session holds exactly what was paid: %d XP (level %d), shadow %d XP" % [
			_expected_player_xp, level, _expected_shadow_xp])
	_record(is_equal_approx(hub_player.health_component.current_health, health_left),
		"R3) health carried through the exit: %.0f" % health_left)
	_record(get_nodes_in_group(Player.GROUP).size() == 1
			and get_nodes_in_group(BasicMeleeShadow.GROUP).size() == 1
			and int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)) == 0,
		"R4) one player, one shadow, no orphan nodes")


# --- the second run -----------------------------------------------------------------------------------

func _phase_second_run() -> void:
	var dungeon: DungeonController = current_scene as DungeonController
	var p: Player = dungeon.get_player()
	var hud: PlayerHealthHUD = dungeon.get_node("PlayerHealthHUD")
	p.health_component.heal(p.health_component.max_health)
	p.global_position = ROOM_ANCHORS[0]
	await _pause(0.8)
	var enemy: BasicEnemy = dungeon.get_rooms()[0].get_enemies()[0] as BasicEnemy
	_park_other(dungeon.get_rooms()[0], enemy)
	var outcome: Dictionary = await _take_dodge_take(p, [enemy.attack.hitbox], func() -> bool:
		return enemy.get_attack_phase() == EnemyAttack.Phase.TELEGRAPH and enemy.attack.get_phase_remaining() <= DODGE_LEAD,
		hud, enemy)
	_record(outcome["taken_before"] > 0.0 and outcome["connected_in_iframes"] > 0
			and outcome["taken_in_iframes"] == 0.0 and outcome["taken_after"] > 0.0,
		"RE1) second dungeon: taken, dodged in the i-frames, taken again — exactly as on the first")
	p.hurtbox.set_invulnerable(true)
	_park(enemy, ROOM_ANCHORS[0] + Vector3(0, 0, -1.5))
	await _pause(0.2)
	p.global_position = ROOM_ANCHORS[0]
	var before: float = _health(enemy).current_health
	var started: Array[StringName] = await _light_combo(p)
	started.append_array(await _heavy_swing(p))
	_record(started == [&"light_attack_1", &"light_attack_2", &"light_attack_3", &"heavy_attack_1"]
			and before - _health(enemy).current_health == minf(before, 120.0),
		"RE2) and the light combo and the heavy work there too")
	SceneTransition.find_in(self).transition_to_scene(HUB)
	await _pause(1.6)
	var hub_player: Player = current_scene.get_node("Player")
	_record(current_scene.scene_file_path == HUB and _clean(hub_player)
			and int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)) == 0,
		"RE3) back to the hub: a clean player, nothing orphaned")


# --- helpers ------------------------------------------------------------------------------------------

## Stands the player in the attacker's reach and lets it swing: one swing taken,
## the next dodged in place so it meets the i-frames, the one after taken again.
func _take_dodge_take(p: Player, hitboxes: Array, swing_coming: Callable, hud: PlayerHealthHUD,
		reach: Node3D = null) -> Dictionary:
	p.hurtbox.set_invulnerable(false)
	_watch_hits(p, hitboxes)
	_reach = reach
	var outcome: Dictionary = {}

	var hp: float = p.health_component.current_health
	await _until_hit(_hits.size() + 1, 10.0, true)
	outcome["taken_before"] = hp - p.health_component.current_health
	outcome["hud_before"] = is_equal_approx(hud.get_ratio(), p.health_component.current_health / p.health_component.max_health)
	await _until_attack_over(swing_coming)

	var waited: float = 0.0
	while waited < 10.0 and not swing_coming.call():
		await physics_frame
		_step_in(p)
		waited += 1.0 / 60.0
	var speed: float = p.effective_dodge_speed
	p.effective_dodge_speed = 0.0
	var hits_before: int = _hits.size()
	hp = p.health_component.current_health
	var hud_ratio: float = hud.get_ratio()
	_dodge(p)
	while p.combat.is_dodging():
		await physics_frame
	p.effective_dodge_speed = speed
	var in_iframes: int = 0
	var taken_in_iframes: float = 0.0
	for i in range(hits_before, _hits.size()):
		if _hits[i]["phase"] == PlayerCombat.DodgePhase.INVULNERABLE:
			in_iframes += 1
			taken_in_iframes += _hits[i]["taken"]
	outcome["connected_in_iframes"] = in_iframes
	outcome["taken_in_iframes"] = taken_in_iframes
	outcome["hud_unchanged"] = is_equal_approx(hud.get_ratio(), hud_ratio) and taken_in_iframes == 0.0

	hp = p.health_component.current_health
	await _until_attack_over(swing_coming)
	await _until_hit(_hits.size() + 1, 10.0, true)
	outcome["taken_after"] = hp - p.health_component.current_health
	outcome["hud_after"] = is_equal_approx(hud.get_ratio(), p.health_component.current_health / p.health_component.max_health)
	_unwatch_hits(hitboxes)
	_reach = null
	return outcome


## Keeps the player within the attacker's reach, on the line between them, while
## it is not dodging.
func _step_in(p: Player) -> void:
	if _reach == null or p == null or p.combat.is_dodging():
		return
	var away: Vector3 = p.global_position - _reach.global_position
	away.y = 0.0
	if away.length() > IN_REACH:
		p.global_position = _reach.global_position + away.normalized() * IN_REACH + Vector3(0, p.global_position.y - _reach.global_position.y, 0)


## Waits until at least `count` watched hits have landed; with `damaging`, until
## the last one cost health.
func _until_hit(count: int, budget: float, damaging: bool = false) -> void:
	var waited: float = 0.0
	while waited < budget:
		if _hits.size() >= count and (not damaging or _hits[-1]["taken"] > 0.0):
			return
		await physics_frame
		_step_in(_watched)
		waited += 1.0 / 60.0


## Lets the current swing finish, so the next wait sees a new one.
func _until_attack_over(swing_coming: Callable) -> void:
	var waited: float = 0.0
	while waited < 3.0 and swing_coming.call():
		await physics_frame
		waited += 1.0 / 60.0
	await _pause(0.3)


func _watch_hits(p: Player, hitboxes: Array) -> void:
	_watched = p
	for hitbox in hitboxes:
		if hitbox != null:
			(hitbox as Hitbox).hit_landed.connect(_on_attacker_hit)


func _unwatch_hits(hitboxes: Array) -> void:
	for hitbox in hitboxes:
		if hitbox != null and (hitbox as Hitbox).hit_landed.is_connected(_on_attacker_hit):
			(hitbox as Hitbox).hit_landed.disconnect(_on_attacker_hit)
	_watched = null


## Runs after the hurtbox had its say: the health already shows whether it counted.
func _on_attacker_hit(target: Node, info: DamageInfo) -> void:
	if target != _watched:
		return
	var health: HealthComponent = _watched.health_component
	var before: float = health.current_health + (info.amount if health.last_damage == info else 0.0)
	_hits.append({"phase": _watched.combat.get_dodge_phase(), "taken": before - health.current_health})


## Starts a dodge that lasts long enough for the scene to change in its i-frames
## (on a copy of the data, held in place), then does `leave`. Returns what the
## leaving player was doing as it left.
func _leave_mid_dodge(p: Player, leave: Callable) -> Dictionary:
	var long: PlayerCombatData = p.combat.data.duplicate() as PlayerCombatData
	long.dodge_duration = 4.0
	long.invulnerability_end = 3.5
	p.combat.data = long
	p.effective_dodge_speed = 0.0
	var at_exit: Dictionary = {}
	var combat: PlayerCombat = p.combat
	var hurtbox: Hurtbox = p.hurtbox
	p.tree_exiting.connect(func() -> void:
		at_exit["phase"] = combat.get_dodge_phase()
		at_exit["invulnerable"] = hurtbox.is_invulnerable)
	_dodge(p)
	while p.combat.get_dodge_phase() != PlayerCombat.DodgePhase.INVULNERABLE:
		await physics_frame
	leave.call()
	await _pause(1.6)
	return at_exit


func _clean(p: Player) -> bool:
	return not p.hurtbox.is_invulnerable and not p.combat.is_dodging() \
		and p.combat.get_dodge_phase() == PlayerCombat.DodgePhase.NONE \
		and p.combat.get_state() == PlayerCombat.State.IDLE and p.combat.can_dodge() \
		and p.combat.data.dodge_duration < 1.0 and Vector2(p.velocity.x, p.velocity.z).length() < 1.0 \
		and not p.combat.has_buffered_attack() and p.combat.get_combo_index() == PlayerCombat.NO_ATTACK


func _dodge(p: Player) -> void:
	var event: InputEventAction = InputEventAction.new()
	event.action = &"dodge"
	event.pressed = true
	p._unhandled_input(event)


func _light_combo(p: Player, glue: Node3D = null) -> Array[StringName]:
	var started: Array[StringName] = []
	var on_started: Callable = func(attack: AttackData) -> void: started.append(attack.id)
	p.combat.attack_started.connect(on_started)
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
	p.combat.attack_started.disconnect(on_started)
	return started


func _heavy_swing(p: Player, glue: Node3D = null) -> Array[StringName]:
	var started: Array[StringName] = []
	var on_started: Callable = func(attack: AttackData) -> void: started.append(attack.id)
	p.combat.attack_started.connect(on_started)
	_stick(p, glue)
	p.camera_rig.rotation.y = 0.0
	p.camera_rig.attack_heavy_pressed.emit()
	var frames: int = 0
	while p.combat.is_attacking() and frames < 300:
		await physics_frame
		frames += 1
		_stick(p, glue)
	p.combat.attack_started.disconnect(on_started)
	return started


func _stick(p: Player, glue: Node3D) -> void:
	if glue != null and is_instance_valid(glue):
		p.global_position = glue.global_position + Vector3(0, 0, STRIKE_RANGE)


func _light(p: Player) -> void:
	p.camera_rig.rotation.y = 0.0
	p.camera_rig.attack_light_pressed.emit()


func _park(enemy: RoomCombatant, at: Vector3) -> void:
	enemy.set_combat_enabled(false)
	enemy.velocity = Vector3.ZERO
	enemy.global_position = at


## Keeps the room's other enemies out of it, so only `attacker` swings.
func _park_other(room: RoomController, attacker: RoomCombatant) -> void:
	for enemy in room.get_enemies():
		if enemy != attacker:
			_park(enemy, enemy.global_position + Vector3(8, 0, 0))


func _health(enemy: RoomCombatant) -> HealthComponent:
	return enemy.get_node("HealthComponent") as HealthComponent


func _listeners(p: Player) -> Dictionary:
	return {
		"attack_started": p.combat.attack_started.get_connections().size(),
		"hit_landed": p.attack_hitbox.hit_landed.get_connections().size(),
		"died": p.health_component.died.get_connections().size(),
		"health_changed": p.health_component.health_changed.get_connections().size(),
	}


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
