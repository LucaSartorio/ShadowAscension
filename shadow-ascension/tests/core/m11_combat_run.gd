extends SceneTree

## M11.1 — the combat foundation through the whole game, with real scene changes.
##
##   godot --headless --path . --script res://tests/core/m11_combat_run.gd
##
## Menu -> New Game -> hub -> gate (left in the middle of a swing) -> dungeon:
## player combat, an enemy killed inside the swing that kills it, the shadow's
## own kill, the boss -> dungeon complete -> hub. Every hit is a real swing
## through PlayerCombat and the hitbox, read back as the DamageInfo that landed;
## the harness only lowers a target's health so a single swing can finish it.

const BOOT: String = "res://Main.tscn"
const HUB: String = "res://scenes/core/hub.tscn"
const DUNGEON: String = "res://scenes/dungeons/dungeon_test.tscn"
const ROOM_ANCHORS: Array[Vector3] = [
	Vector3(0, 0.1, -13), Vector3(0, 0.1, -33), Vector3(0, 0.1, -53)
]
const EXIT_POS: Vector3 = Vector3(0, 0.1, -65)
const STRIKE_RANGE: float = 1.6

var _shadow_data: ShadowData = preload("res://resources/shadows/basic_melee_shadow.tres")
var _state: Node = null
var _pass: int = 0
var _fail: int = 0
## What the session should hold, kept from what each kill paid.
var _expected_player_xp: int = 0
var _expected_shadow_xp: int = 0


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

	await _phase_hub()
	await _phase_leave_mid_swing()
	await _phase_player_combat()
	await _phase_shadow_combat()
	await _phase_boss()
	await _phase_back_to_hub()

	print("[SUMMARY] passed=%d failed=%d" % [_pass, _fail])
	await _pause(0.3)
	quit()


# --- the hub ----------------------------------------------------------------------------------

func _phase_hub() -> void:
	var p: Player = current_scene.get_node("Player")
	_record(current_scene.scene_file_path == HUB and p.combat.get_state() == PlayerCombat.State.IDLE
			and not p.attack_hitbox.is_active() and p.combat.data.light_combo.size() == 3,
		"H1) New Game reaches the hub: combat IDLE, hitbox shut, the three-attack light combo loaded")
	var shadow: ShadowInstance = p.shadows.add_shadow(_shadow_data)
	p.shadow_summoner.summon(shadow.instance_id)
	await _pause(0.4)
	# FOLLOW: the shadow fights only what it is ordered to, so which kill is whose
	# is decided here rather than by who got there first.
	p.shadow_commander.set_mode(BasicMeleeShadow.CommandMode.FOLLOW)
	_record(p.shadow_summoner.has_active_shadow(), "H2) a shadow is summoned and following")


## The player walks through the gate mid-swing. A copy of the data with a long
## hit window makes sure the scene really goes while the hitbox is open.
func _phase_leave_mid_swing() -> void:
	var p: Player = current_scene.get_node("Player")
	var gate: DungeonGate = current_scene.get_node("DungeonGate")
	var prompt: InteractionPrompt = current_scene.get_node("InteractionPrompt")
	p.global_position = gate.global_position
	await _pause(0.4)
	_record(prompt.is_showing() and prompt.get_text() == gate.prompt_text,
		"T1) standing in the gate still prompts '%s'" % prompt.get_text())

	var long: PlayerCombatData = p.combat.data.duplicate() as PlayerCombatData
	var attacks: Array[AttackData] = []
	for attack in p.combat.data.light_combo:
		attacks.append(attack.duplicate() as AttackData)
	attacks[0].active = 5.0
	long.light_combo = attacks
	p.combat.data = long

	var old_combat: PlayerCombat = p.combat
	var old_hitbox: Hitbox = p.attack_hitbox
	var at_exit: Dictionary = {}
	p.tree_exiting.connect(func() -> void:
		at_exit["state"] = old_combat.get_state()
		at_exit["open"] = old_hitbox.is_active())
	p.camera_rig.attack_light_pressed.emit()
	while p.combat.get_state() != PlayerCombat.State.ACTIVE:
		await physics_frame
	gate.activate()
	await _pause(1.6)

	var dungeon: DungeonController = current_scene as DungeonController
	var fresh: Player = dungeon.get_player()
	_record(at_exit.get("state") == PlayerCombat.State.ACTIVE and at_exit.get("open") == true,
		"T2) the hub's player left with its swing still open (%s)" % [at_exit])
	_record(not is_instance_valid(old_combat) and not is_instance_valid(old_hitbox),
		"T3) and its combat and hitbox went with it: no timer or hit window outlives the scene")
	_record(fresh.combat.get_state() == PlayerCombat.State.IDLE and not fresh.attack_hitbox.is_active()
			and fresh.combat.data.light_combo[0].active < 1.0,
		"T4) the dungeon's player starts IDLE, hitbox shut, on the shipped data")
	_record(fresh.combat.attack_started.get_connections().size() == 2
			and _stale_connections(fresh) == 0,
		"T5) its combat has its two listeners — the presentation and the hit feedback — and no signal of its combat parts reaches a freed node")
	_record(int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)) == 0,
		"T6) and nothing was left orphaned by leaving mid-swing")


# --- the player's own combat -----------------------------------------------------------------

func _phase_player_combat() -> void:
	var dungeon: DungeonController = current_scene as DungeonController
	var p: Player = dungeon.get_player()
	p.hurtbox.set_invulnerable(true)
	p.global_position = ROOM_ANCHORS[0]
	await _pause(0.8)
	var room: RoomController = dungeon.get_rooms()[0]
	var a: RoomCombatant = room.get_enemies()[0]
	var b: RoomCombatant = room.get_enemies()[1]
	var clears: Array[int] = []
	room.room_cleared.connect(func(_r: RoomController) -> void: clears.append(1))

	# One measured swing: light_attack_1 from a fresh chain.
	var a_health: HealthComponent = a.get_node("HealthComponent")
	var before: float = a_health.current_health
	var hit: DamageInfo = await _first_hit(p, a)
	var dealt: float = before - a_health.current_health
	var bar: EnemyHealthBar3D = a.get_node("EnemyHealthBar3D")
	_record(hit != null and hit.amount == 20.0 and dealt == hit.amount
			and hit.amount == p.combat.calculate_damage(p.combat.data.light_combo[0]),
		"E1) a real light_attack_1 takes exactly its calculated %.0f off the enemy (took %.0f)" % [
			p.combat.calculate_damage(p.combat.data.light_combo[0]), dealt])
	_record(hit != null and hit.source == p and hit.attack_id == &"light_attack_1"
			and is_same(a_health.last_damage, hit),
		"E2) the enemy's health recorded that hit: from the player, by light_attack_1")
	_record(is_equal_approx(bar.get_ratio(), a_health.current_health / a_health.max_health),
		"E3) its health bar follows: %.2f" % bar.get_ratio())

	var xp_before: int = p.progression.get_total_xp()
	await _kill(p, a)
	await _pause(0.3)
	var paid: int = p.progression.get_total_xp() - xp_before
	_record(a.has_died() and a.get_killer() == p and paid == a.get_xp_reward(),
		"E4) killed by the player's combo: dead, credited to the player, %d XP paid once (%d)" % [
			a.get_xp_reward(), paid])
	_expected_player_xp += paid
	var hits_on_corpse: Array[Node] = []
	var on_landed: Callable = func(target: Node, _info: DamageInfo) -> void:
		if target == a:
			hits_on_corpse.append(target)
	p.attack_hitbox.hit_landed.connect(on_landed)
	p.combat.reset()
	p.global_position = a.global_position + Vector3(0, 0, STRIKE_RANGE)
	p.camera_rig.rotation.y = 0.0
	p.camera_rig.attack_light_pressed.emit()
	await _until_idle(p)
	p.attack_hitbox.hit_landed.disconnect(on_landed)
	_record(hits_on_corpse.is_empty() and p.progression.get_total_xp() == xp_before + paid,
		"E5) a swing through the corpse hits nothing and pays nothing")

	# B has exactly one swing's worth of health left.
	var b_health: HealthComponent = b.get_node("HealthComponent")
	b_health.current_health = p.combat.calculate_damage(p.combat.data.light_combo[0])
	var death_state: Array = []
	b_health.died.connect(func() -> void: death_state.append(p.combat.get_state()), CONNECT_ONE_SHOT)
	var b_hits: Array[DamageInfo] = []
	var on_b: Callable = func(target: Node, info: DamageInfo) -> void:
		if target == b:
			b_hits.append(info)
	p.attack_hitbox.hit_landed.connect(on_b)
	xp_before = p.progression.get_total_xp()
	await _kill(p, b)
	await _pause(0.4)
	p.attack_hitbox.hit_landed.disconnect(on_b)
	paid = p.progression.get_total_xp() - xp_before
	_record(death_state == [PlayerCombat.State.ACTIVE] and b_hits.size() == 1,
		"X1) the second enemy dies inside the hit window of the swing that killed it, from one hit")
	_record(paid == b.get_xp_reward(), "X2) its XP is paid once: %d" % paid)
	_expected_player_xp += paid
	_record(room.is_cleared() and clears.size() == 1 and not room.exit_door.is_locked(),
		"X3) the room clears once and opens")


# --- the shadow's combat ----------------------------------------------------------------------

func _phase_shadow_combat() -> void:
	var dungeon: DungeonController = current_scene as DungeonController
	var p: Player = dungeon.get_player()
	var node: BasicMeleeShadow = p.shadow_summoner.get_active_node()
	p.global_position = ROOM_ANCHORS[1]
	await _pause(0.8)
	var room: RoomController = dungeon.get_rooms()[1]
	var c: RoomCombatant = room.get_enemies()[0]
	var d: RoomCombatant = room.get_enemies()[1]

	# The shadow's own swing finishes C: one real hit's worth of health left.
	var c_health: HealthComponent = c.get_node("HealthComponent")
	c_health.current_health = 1.0
	var reward: int = c.get_xp_reward()
	var shadow_cut: int = int(round(reward * PlayerProgression.SHADOW_KILL_SHARE))
	var player_before: int = p.progression.get_total_xp()
	var shadow_before: int = _shadow_total_xp(node.instance)
	p.global_position = c.global_position + Vector3(0, 0, 3.0)
	node.global_position = c.global_position + Vector3(0, 0, 2.0)
	node.set_manual_target(c)
	var waited: float = 0.0
	while waited < 8.0 and not c.has_died():
		await physics_frame
		waited += 1.0 / 60.0
	await _pause(0.4)
	var player_gain: int = p.progression.get_total_xp() - player_before
	var shadow_gain: int = _shadow_total_xp(node.instance) - shadow_before
	_record(c.has_died() and c.get_killer() == node and c_health.last_damage.source == node,
		"SH1) the shadow's own swing kills: its hit arrives as a DamageInfo from the shadow")
	_record(shadow_gain == shadow_cut and player_gain == reward - shadow_cut,
		"SH2) a shadow kill still splits 70/30: %d XP -> shadow %d, player %d (got %d / %d)" % [
			reward, shadow_cut, reward - shadow_cut, shadow_gain, player_gain])
	_expected_shadow_xp += shadow_gain
	_expected_player_xp += player_gain

	player_before = p.progression.get_total_xp()
	shadow_before = _shadow_total_xp(node.instance)
	await _kill(p, d)
	await _pause(0.4)
	player_gain = p.progression.get_total_xp() - player_before
	_record(d.get_killer() == p and player_gain == d.get_xp_reward()
			and _shadow_total_xp(node.instance) == shadow_before,
		"SH3) and the player's own kill beside it pays the player all %d" % player_gain)
	_expected_player_xp += player_gain


# --- the boss ---------------------------------------------------------------------------------

func _phase_boss() -> void:
	var dungeon: DungeonController = current_scene as DungeonController
	var p: Player = dungeon.get_player()
	p.global_position = ROOM_ANCHORS[2]
	var boss: DungeonBoss = dungeon.get_rooms()[2].get_enemies()[0] as DungeonBoss
	var bar: BossHealthBar = dungeon.get_node("BossHealthBar")
	var waited: float = 0.0
	while waited < 6.0 and not (boss.combat_enabled and bar.is_showing()):
		await _pause(0.1)
		waited += 0.1
	var health: HealthComponent = boss.health_component

	var before: float = health.current_health
	var hit: DamageInfo = await _first_hit(p, boss)
	var dealt: float = before - health.current_health
	_record(hit != null and hit.amount == 20.0 and dealt == hit.amount and hit.source == p,
		"BO1) a real swing takes its %.0f off the boss, the same road as any enemy (took %.0f)" % [
			hit.amount if hit != null else 0.0, dealt])
	_record(is_equal_approx(bar.get_ratio(), health.current_health / health.max_health),
		"BO2) and the boss bar follows: %.3f" % bar.get_ratio())

	health.current_health = p.combat.calculate_damage(p.combat.data.light_combo[0])
	var xp_before: int = p.progression.get_total_xp()
	await _kill(p, boss)
	await _pause(0.6)
	var paid: int = p.progression.get_total_xp() - xp_before
	_record(boss.has_died() and boss.get_killer() == p and paid == boss.get_xp_reward(),
		"BO3) the boss falls to the player's swing: %d XP paid once (%d)" % [boss.get_xp_reward(), paid])
	_expected_player_xp += paid
	_record(dungeon.get_state() == DungeonController.DungeonState.COMPLETED
			and dungeon.exit_portal.is_enabled(),
		"BO4) the dungeon completes as before, exit open")


# --- back to the hub --------------------------------------------------------------------------

func _phase_back_to_hub() -> void:
	var dungeon: DungeonController = current_scene as DungeonController
	var p: Player = dungeon.get_player()
	p.hurtbox.set_invulnerable(false)
	p.hurtbox.receive_hit(DamageInfo.new(13.0))
	var health_left: float = p.health_component.current_health
	var level: int = p.progression.current_level
	var dungeon_combat: PlayerCombat = p.combat
	p.global_position = EXIT_POS
	await _pause(0.4)
	var used: bool = dungeon.exit_portal.activate()
	await _pause(1.6)

	var hub_player: Player = current_scene.get_node("Player")
	_record(used and current_scene.scene_file_path == HUB and not is_instance_valid(dungeon_combat),
		"R1) the exit returns to the hub, and the dungeon's combat is gone with its player")
	_record(hub_player.progression.get_total_xp() == _expected_player_xp
			and hub_player.progression.current_level == level and level > 1,
		"R2) the session kept exactly what was paid: %d XP, level %d" % [_expected_player_xp, level])
	_record(_shadow_total_xp(_state.shadows[0]) == _expected_shadow_xp and _state.shadows.size() == 1,
		"R3) and the shadow its %d XP" % _expected_shadow_xp)
	_record(is_equal_approx(hub_player.health_component.current_health, health_left),
		"R4) health carried through the exit: %.0f" % health_left)
	_record(hub_player.combat.get_state() == PlayerCombat.State.IDLE
			and not hub_player.attack_hitbox.is_active() and not hub_player.attack_hitbox.monitoring,
		"R5) back in the hub: combat IDLE, hitbox shut and not monitoring")
	var gate: DungeonGate = current_scene.get_node("DungeonGate")
	var prompt: InteractionPrompt = current_scene.get_node("InteractionPrompt")
	hub_player.global_position = gate.global_position
	await _pause(0.4)
	_record(prompt.is_showing() and prompt.get_text() == gate.prompt_text,
		"R6) and the gate still prompts '%s'" % prompt.get_text())
	_record(get_nodes_in_group(Player.GROUP).size() == 1
			and get_nodes_in_group(BasicMeleeShadow.GROUP).size() == 1
			and int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)) == 0,
		"R7) one player, one shadow, no orphan nodes")


# --- helpers ------------------------------------------------------------------------------------

## Swings from a fresh chain, repositioned each time, until one lands on
## `target`; returns the DamageInfo that landed.
func _first_hit(player: Player, target: RoomCombatant) -> DamageInfo:
	var landed: Array[DamageInfo] = []
	var on_landed: Callable = func(hit_target: Node, info: DamageInfo) -> void:
		if hit_target == target:
			landed.append(info)
	player.attack_hitbox.hit_landed.connect(on_landed)
	for i in 6:
		player.combat.reset()
		player.global_position = target.global_position + Vector3(0, 0, STRIKE_RANGE)
		player.camera_rig.rotation.y = 0.0
		player.camera_rig.attack_light_pressed.emit()
		await _until_idle(player)
		if not landed.is_empty():
			break
	player.attack_hitbox.hit_landed.disconnect(on_landed)
	return landed[0] if not landed.is_empty() else null


## Connections on the player's combat signals whose receiver has been freed —
## what a listener left behind by the last scene would look like.
func _stale_connections(player: Player) -> int:
	var stale: int = 0
	for combat_signal in [player.combat.attack_started, player.attack_hitbox.hit_landed,
			player.attack_hitbox.hit_accepted, player.health_component.died,
			player.health_component.health_changed]:
		for connection in (combat_signal as Signal).get_connections():
			if not is_instance_valid((connection["callable"] as Callable).get_object()):
				stale += 1
	return stale


func _kill(player: Player, target: RoomCombatant, budget: float = 40.0) -> void:
	var elapsed: float = 0.0
	while elapsed < budget and not target.has_died():
		if player.combat.get_state() == PlayerCombat.State.IDLE:
			player.global_position = target.global_position + Vector3(0, 0, STRIKE_RANGE)
			player.camera_rig.rotation.y = 0.0
			player.camera_rig.attack_light_pressed.emit()
		await physics_frame
		elapsed += 1.0 / 60.0


func _until_idle(player: Player) -> void:
	await physics_frame
	var frames: int = 0
	while player.combat.get_state() != PlayerCombat.State.IDLE and frames < 180:
		await physics_frame
		frames += 1


func _shadow_total_xp(shadow: ShadowInstance) -> int:
	var total: int = shadow.current_xp
	for level in range(1, shadow.level):
		total += shadow.shadow_data.xp_required_for_level(level)
	return total


## Completing the dungeon opens the run summary, which pauses the tree until it
## is dismissed; a headless flow dismisses it the way a player would.
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
