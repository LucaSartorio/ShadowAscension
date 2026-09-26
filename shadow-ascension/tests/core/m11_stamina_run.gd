extends SceneTree

## M11.5 — stamina through the whole game.
##
##   godot --headless --path . --script res://tests/core/m11_stamina_run.gd
##
## Menu -> New Game -> hub (full, a dodge spends) -> gate (left mid-dodge with
## stamina spent) -> dungeon: a new player, full; an enemy's swing taken, the
## next dodged — paid once, no damage — the one after taken; the light combo and
## the heavy (free); stamina spent to empty, the fifth dodge refused, the delay,
## regeneration at its rate, back to full; the shadow's kill at 70/30; the boss's
## swings taken and dodged the same way, then the combo and the heavy to finish
## it -> hub -> a second dungeon: the same, with the first one's listeners and no
## second regeneration -> hub -> back to the menu and New Game: full again.
##
## As in m11_dodge_run, the dodges that meet an attack are made in place (dodge
## speed held at 0 for them), so what is tested is the i-frames, not the evasion.

const BOOT: String = "res://Main.tscn"
const HUB: String = "res://scenes/core/hub.tscn"
const DT: float = 1.0 / 60.0
const ROOM_ANCHORS: Array[Vector3] = [
	Vector3(0, 0.1, -13), Vector3(0, 0.1, -33), Vector3(0, 0.1, -53)
]
const EXIT_POS: Vector3 = Vector3(0, 0.1, -65)
const STRIKE_RANGE: float = 1.6
## Dodge this long before a swing's hit window opens: inside the i-frames with
## room to spare on both sides.
const DODGE_LEAD: float = 0.15
## Where the player stands to be swung at by a basic enemy (see m11_dodge_run).
const IN_REACH: float = 1.5

var _shadow_data: ShadowData = preload("res://resources/shadows/basic_melee_shadow.tres")
var _state: Node = null
var _pass: int = 0
var _fail: int = 0
var _expected_player_xp: int = 0
var _expected_shadow_xp: int = 0
var _first_listeners: Dictionary = {}
var _hits: Array[Dictionary] = []
var _watched: Player = null
var _reach: Node3D = null
## Every stamina decrease the tracked player signalled, and what it last said.
var _spends: Array[float] = []
var _last_stamina: float = 0.0
var _tracked: PlayerCombat = null


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

	await _phase_into_dungeon(1)
	await _phase_enemy_swings()
	await _phase_combat_and_shadow()
	await _phase_stamina_cycle("S")
	await _phase_boss()
	await _phase_out_to_hub()
	await _phase_into_dungeon(2)
	await _phase_second_run()
	await _phase_new_game()

	print("[SUMMARY] passed=%d failed=%d" % [_pass, _fail])
	await _pause(0.3)
	quit()


# --- the hub: a new game starts full ---------------------------------------------------------------

func _phase_hub() -> void:
	var p: Player = current_scene.get_node("Player")
	var bar: PlayerStaminaHUD = current_scene.get_node("PlayerStaminaHUD")
	_record(current_scene.scene_file_path == HUB and _full(p) and bar.is_showing()
			and is_equal_approx(bar.get_ratio(), 1.0),
		"H1) New Game: the hub's player has %.0f / %.0f stamina, and the bar shows it full" % [
			p.combat.get_stamina(), p.combat.get_max_stamina()])
	var shadow: ShadowInstance = p.shadows.add_shadow(_shadow_data)
	p.shadow_summoner.summon(shadow.instance_id)
	await _pause(0.4)
	p.shadow_commander.set_mode(BasicMeleeShadow.CommandMode.FOLLOW)
	_track(p)
	var started: bool = _dodge(p)
	await _until(func() -> bool: return not p.combat.is_dodging())
	_record(started and _spends == [p.combat.data.dodge_stamina_cost] and is_equal_approx(bar.get_ratio(), 0.75),
		"H2) a dodge in the hub costs %s; the bar follows to %.2f" % [_spends, bar.get_ratio()])


# --- through the gate mid-dodge, stamina spent ----------------------------------------------------------

func _phase_into_dungeon(run: int) -> void:
	var p: Player = current_scene.get_node("Player")
	var gate: DungeonGate = current_scene.get_node("DungeonGate")
	p.global_position = gate.global_position
	await _pause(0.4)
	var at_exit: Dictionary = await _leave_mid_dodge(p, func() -> void: gate.activate())
	var dungeon: DungeonController = current_scene as DungeonController
	var fresh: Player = dungeon.get_player()
	var bar: PlayerStaminaHUD = dungeon.get_node("PlayerStaminaHUD")
	await _pause(0.3)
	_record(at_exit.get("stamina", 100.0) < at_exit.get("max", 0.0) and _clean(fresh) and _full(fresh)
			and is_equal_approx(bar.get_ratio(), 1.0),
		"G%d.1) left mid-dodge with %.0f stamina: the dungeon's player starts full and idle, its bar full" % [
			run, at_exit.get("stamina", -1.0)])
	var listeners: Dictionary = _listeners(fresh)
	if run == 1:
		_first_listeners = listeners
		_record(listeners["stamina_changed"] == 1,
			"G1.2) one listener on stamina_changed — the bar — and no drain or regeneration carried over")
	else:
		_record(listeners == _first_listeners,
			"G2.2) the second dungeon's player has exactly the first one's listeners: %s" % [listeners])
	_track(fresh)


# --- an enemy's swings: taken, dodged (paid once), taken -------------------------------------------------

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
	_record(outcome["taken_before"] > 0.0 and outcome["stamina_untouched_by_hits"],
		"E1) an enemy's swing on a standing player takes %.0f HP, and no stamina" % outcome["taken_before"])
	_record(outcome["connected_in_iframes"] > 0 and outcome["taken_in_iframes"] == 0.0 and outcome["hud_unchanged"]
			and outcome["dodge_spends"] == [p.combat.data.dodge_stamina_cost],
		"E2) its next swing, dodged: it connects in the i-frames and takes nothing; the dodge paid %s, once" % [
			outcome["dodge_spends"]])
	_record(outcome["taken_after"] > 0.0, "E3) the swing after the dodge takes %.0f HP again" % outcome["taken_after"])


# --- the light combo and the heavy cost nothing; the shadow ------------------------------------------------

func _phase_combat_and_shadow() -> void:
	var dungeon: DungeonController = current_scene as DungeonController
	var p: Player = dungeon.get_player()
	p.hurtbox.set_invulnerable(true)
	var room: RoomController = dungeon.get_rooms()[0]
	var xp_before: int = p.progression.get_total_xp()
	_spends.clear()
	for enemy in room.get_enemies():
		_park(enemy, ROOM_ANCHORS[0] + Vector3(0, 0, -1.5))
		await _pause(0.2)
		p.global_position = ROOM_ANCHORS[0]
		_health(enemy).current_health = 100.0
		var started: Array[StringName] = await _light_combo(p)
		started.append_array(await _heavy_swing(p))
		_record(started == [&"light_attack_1", &"light_attack_2", &"light_attack_3", &"heavy_attack_1"]
				and enemy.has_died() and _health(enemy).last_damage.attack_id == &"heavy_attack_1",
			"C-%s) the light combo (80) and the heavy (40) finish an enemy" % enemy.name)
	await _pause(0.4)
	var paid: int = p.progression.get_total_xp() - xp_before
	_record(paid == 50 and room.is_cleared() and _spends.is_empty(),
		"C1) both paid once, %d XP, the room clears — and the attacks spent no stamina (%s)" % [paid, _spends])
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
	await _until(func() -> bool: return d.has_died(), 8.0)
	await _pause(0.4)
	var player_gain: int = p.progression.get_total_xp() - player_before
	var shadow_gain: int = _shadow_total_xp(node.instance) - shadow_before
	_record(d.has_died() and d.get_killer() == node and shadow_gain == shadow_cut
			and player_gain == reward - shadow_cut,
		"SH1) the shadow's kill, untouched by stamina: %d XP -> shadow %d, player %d (got %d / %d)" % [
			reward, shadow_cut, reward - shadow_cut, shadow_gain, player_gain])
	_expected_shadow_xp += shadow_gain
	_expected_player_xp += player_gain
	p.hurtbox.set_invulnerable(false)


# --- empty, refused, the delay, regeneration, full ---------------------------------------------------------

func _phase_stamina_cycle(tag: String) -> void:
	var dungeon: DungeonController = current_scene as DungeonController
	var p: Player = dungeon.get_player()
	var bar: PlayerStaminaHUD = dungeon.get_node("PlayerStaminaHUD")
	var data: PlayerCombatData = p.combat.data
	p.global_position = ROOM_ANCHORS[0]
	await _until(func() -> bool: return _full(p), 6.0)
	var speed: float = p.effective_dodge_speed
	p.effective_dodge_speed = 0.0
	_spends.clear()
	var dodges: int = 0
	var ended_at: int = 0
	for i in 6:
		if not _dodge(p):
			break
		dodges += 1
		await _until(func() -> bool: return not p.combat.is_dodging())
		ended_at = Engine.get_physics_frames()
		await _until(func() -> bool: return p.combat._dodge_cooldown_remaining <= 0.0)
	var refused: bool = not _dodge(p) and not p.combat.is_dodging()
	_record(dodges == 4 and refused and p.combat.get_stamina() == 0.0 and bar.get_ratio() == 0.0
			and _spends.size() == 4,
		"%s1) from full: %d dodges at %.0f each, then empty — the bar at 0 — and the next dodge refused" % [
			tag, dodges, data.dodge_stamina_cost])

	await _until(func() -> bool: return p.combat.get_stamina() > 0.0)
	var delay: float = (Engine.get_physics_frames() - ended_at) * DT
	# Both reads at the same point of a physics tick, exactly 30 ticks apart.
	var s0: float = p.combat.get_stamina()
	for i in 30:
		await physics_frame
	var rate: float = (p.combat.get_stamina() - s0) / (30.0 * DT)
	_record(absf(delay - data.stamina_regen_delay) <= 3.0 * DT and absf(rate - data.stamina_regen_rate) <= 1.0,
		"%s2) it comes back %.2fs after the last dodge ended, at %.1f per second — one regeneration" % [tag, delay, rate])
	await _until(func() -> bool: return _full(p), 4.0)
	var at_full: int = _spends.size()
	_record(_full(p) and is_equal_approx(bar.get_ratio(), 1.0) and at_full == 4,
		"%s3) back to %.0f, the bar full, and nothing more was spent" % [tag, p.combat.get_stamina()])
	p.effective_dodge_speed = speed


# --- the boss ---------------------------------------------------------------------------------------------

func _phase_boss() -> void:
	var dungeon: DungeonController = current_scene as DungeonController
	var p: Player = dungeon.get_player()
	var hud: PlayerHealthHUD = dungeon.get_node("PlayerHealthHUD")
	p.health_component.heal(p.health_component.max_health)
	p.global_position = ROOM_ANCHORS[2]
	var boss: DungeonBoss = dungeon.get_rooms()[2].get_enemies()[0] as DungeonBoss
	var bar: BossHealthBar = dungeon.get_node("BossHealthBar")
	await _until(func() -> bool: return boss.combat_enabled and bar.is_showing(), 6.0)
	var outcome: Dictionary = await _take_dodge_take(p, boss.combat.get_hitboxes(), func() -> bool:
		return boss.get_attack_phase() == BossCombat.Phase.TELEGRAPH and boss.combat.get_phase_remaining() <= DODGE_LEAD,
		hud)
	_record(outcome["taken_before"] > 0.0 and outcome["connected_in_iframes"] > 0 and outcome["taken_in_iframes"] == 0.0
			and outcome["taken_after"] > 0.0 and outcome["dodge_spends"] == [p.combat.data.dodge_stamina_cost],
		"BO1) the boss: a swing taken (%.0f), one dodged in the i-frames for nothing — paid %s once — one taken again (%.0f)" % [
			outcome["taken_before"], outcome["dodge_spends"], outcome["taken_after"]])

	p.hurtbox.set_invulnerable(true)
	_spends.clear()
	_dodge(p)
	await _until(func() -> bool: return not p.combat.is_dodging())
	var health: HealthComponent = boss.health_component
	var start: float = health.current_health
	var started: Array[StringName] = await _light_combo(p, boss)
	started.append_array(await _heavy_swing(p, boss))
	var dealt: float = start - health.current_health
	_record(started == [&"light_attack_1", &"light_attack_2", &"light_attack_3", &"heavy_attack_1"]
			and dealt == 120.0 and _spends == [p.combat.data.dodge_stamina_cost],
		"BO2) a dodge (%s), then the combo and the heavy on the boss for nothing more: %.0f off it" % [_spends, dealt])
	health.current_health = p.combat.calculate_damage(p.combat.data.heavy_combo[0])
	var xp_before: int = p.progression.get_total_xp()
	await _heavy_swing(p, boss)
	await _pause(0.6)
	var paid: int = p.progression.get_total_xp() - xp_before
	_record(boss.has_died() and paid == boss.get_xp_reward()
			and dungeon.get_state() == DungeonController.DungeonState.COMPLETED,
		"BO3) the boss falls, %d XP once, and the dungeon completes" % paid)
	_expected_player_xp += paid


# --- back to the hub ----------------------------------------------------------------------------------------

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
	var bar: PlayerStaminaHUD = current_scene.get_node("PlayerStaminaHUD")
	await _pause(0.3)
	_record(current_scene.scene_file_path == HUB and at_exit.get("stamina", 100.0) < at_exit.get("max", 0.0)
			and _clean(hub_player) and _full(hub_player) and is_equal_approx(bar.get_ratio(), 1.0)
			and hub_player.combat.stamina_changed.get_connections().size() == 1,
		"R1) left the dungeon mid-dodge with %.0f stamina: the hub's player is full, its bar full, one listener" % at_exit.get("stamina", -1.0))
	_record(hub_player.progression.get_total_xp() == _expected_player_xp
			and hub_player.progression.current_level == level
			and _shadow_total_xp(_state.shadows[0]) == _expected_shadow_xp,
		"R2) the session holds exactly what was paid: %d XP (level %d), shadow %d XP" % [
			_expected_player_xp, level, _expected_shadow_xp])
	_record(is_equal_approx(hub_player.health_component.current_health, health_left),
		"R3) health carried through the exit (%.0f); stamina did not — it is a new player's" % health_left)
	_record(get_nodes_in_group(Player.GROUP).size() == 1
			and get_nodes_in_group(BasicMeleeShadow.GROUP).size() == 1
			and int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)) == 0,
		"R4) one player, one shadow, no orphan nodes")


# --- the second run ---------------------------------------------------------------------------------------

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
			and outcome["taken_in_iframes"] == 0.0 and outcome["taken_after"] > 0.0
			and outcome["dodge_spends"] == [p.combat.data.dodge_stamina_cost],
		"RE1) second dungeon: taken, dodged in the i-frames (paid once), taken again — as on the first")
	p.hurtbox.set_invulnerable(true)
	_park(enemy, ROOM_ANCHORS[0] + Vector3(0, 0, -1.5))
	await _pause(0.2)
	p.global_position = ROOM_ANCHORS[0]
	var before: float = _health(enemy).current_health
	var started: Array[StringName] = await _light_combo(p)
	started.append_array(await _heavy_swing(p))
	_record(started == [&"light_attack_1", &"light_attack_2", &"light_attack_3", &"heavy_attack_1"]
			and before - _health(enemy).current_health == minf(before, 120.0),
		"RE2) the light combo and the heavy work there too")
	await _phase_stamina_cycle("RS")
	SceneTransition.find_in(self).transition_to_scene(HUB)
	await _pause(1.6)
	var hub_player: Player = current_scene.get_node("Player")
	_record(current_scene.scene_file_path == HUB and _clean(hub_player) and _full(hub_player)
			and int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)) == 0,
		"RE3) back to the hub: a clean, full player, nothing orphaned")


# --- New Game again ---------------------------------------------------------------------------------------

func _phase_new_game() -> void:
	var p: Player = current_scene.get_node("Player")
	_dodge(p)
	await _until(func() -> bool: return not p.combat.is_dodging())
	var spent: float = p.combat.get_stamina()
	# Nothing in the game leads back to the menu yet, so the harness goes there
	# itself, as persistent_state_run does.
	change_scene_to_file(BOOT)
	await _pause(0.6)
	(current_scene.get_node("MainMenu") as MainMenu).press_play()
	await _pause(1.4)
	var fresh: Player = current_scene.get_node("Player")
	var bar: PlayerStaminaHUD = current_scene.get_node("PlayerStaminaHUD")
	_record(spent < fresh.combat.get_max_stamina() and _full(fresh) and is_equal_approx(bar.get_ratio(), 1.0)
			and fresh.progression.get_total_xp() == 0,
		"NG1) New Game after spending (%.0f left): a new character with full stamina, its bar full" % spent)


# --- helpers ------------------------------------------------------------------------------------------------

## One swing taken, the next dodged in place so it meets the i-frames, the one
## after taken again; with what the dodge and the hits spent.
func _take_dodge_take(p: Player, hitboxes: Array, swing_coming: Callable, hud: PlayerHealthHUD,
		reach: Node3D = null) -> Dictionary:
	p.hurtbox.set_invulnerable(false)
	_watch_hits(p, hitboxes)
	_reach = reach
	var outcome: Dictionary = {}
	await _until(func() -> bool: return p.combat.can_spend_stamina(p.combat.data.dodge_stamina_cost) and _full(p), 5.0)

	_spends.clear()
	var hp: float = p.health_component.current_health
	await _until_hit(_hits.size() + 1, 10.0, true)
	outcome["taken_before"] = hp - p.health_component.current_health
	outcome["stamina_untouched_by_hits"] = _spends.is_empty()
	await _until_attack_over(swing_coming)

	var waited: float = 0.0
	while waited < 10.0 and not swing_coming.call():
		await physics_frame
		_step_in(p)
		waited += DT
	var speed: float = p.effective_dodge_speed
	p.effective_dodge_speed = 0.0
	var hits_before: int = _hits.size()
	var hud_ratio: float = hud.get_ratio()
	_spends.clear()
	_dodge(p)
	while p.combat.is_dodging():
		await physics_frame
	outcome["dodge_spends"] = _spends.duplicate()
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
	_unwatch_hits(hitboxes)
	_reach = null
	return outcome


func _step_in(p: Player) -> void:
	if _reach == null or p == null or p.combat.is_dodging():
		return
	var away: Vector3 = p.global_position - _reach.global_position
	away.y = 0.0
	if away.length() > IN_REACH:
		p.global_position = _reach.global_position + away.normalized() * IN_REACH + Vector3(0, p.global_position.y - _reach.global_position.y, 0)


func _until_hit(count: int, budget: float, damaging: bool = false) -> void:
	var waited: float = 0.0
	while waited < budget:
		if _hits.size() >= count and (not damaging or _hits[-1]["taken"] > 0.0):
			return
		await physics_frame
		_step_in(_watched)
		waited += DT


func _until_attack_over(swing_coming: Callable) -> void:
	await _until(func() -> bool: return not swing_coming.call(), 3.0)
	await _pause(0.3)


func _until(condition: Callable, budget: float = 3.0) -> void:
	var waited: float = 0.0
	while waited < budget and not condition.call():
		await physics_frame
		waited += DT


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


func _on_attacker_hit(target: Node, info: DamageInfo) -> void:
	if target != _watched:
		return
	var health: HealthComponent = _watched.health_component
	var before: float = health.current_health + (info.amount if health.last_damage == info else 0.0)
	_hits.append({"phase": _watched.combat.get_dodge_phase(), "taken": before - health.current_health})


## Follows one player's stamina_changed, recording every decrease.
func _track(p: Player) -> void:
	if _tracked != null and is_instance_valid(_tracked) and _tracked.stamina_changed.is_connected(_on_stamina_changed):
		_tracked.stamina_changed.disconnect(_on_stamina_changed)
	_tracked = p.combat
	_last_stamina = _tracked.get_stamina()
	_spends.clear()
	_tracked.stamina_changed.connect(_on_stamina_changed)


func _on_stamina_changed(current: float, _maximum: float) -> void:
	if current < _last_stamina:
		_spends.append(_last_stamina - current)
	_last_stamina = current


## Starts a dodge that lasts long enough for the scene to change in it (on a copy
## of the data, held in place), then does `leave`. Returns the leaving player's
## stamina as it left.
func _leave_mid_dodge(p: Player, leave: Callable) -> Dictionary:
	var long: PlayerCombatData = p.combat.data.duplicate() as PlayerCombatData
	long.dodge_duration = 4.0
	long.invulnerability_end = 3.5
	p.combat.data = long
	p.effective_dodge_speed = 0.0
	var at_exit: Dictionary = {}
	var combat: PlayerCombat = p.combat
	p.tree_exiting.connect(func() -> void:
		at_exit["stamina"] = combat.get_stamina()
		at_exit["max"] = combat.get_max_stamina())
	await _until(func() -> bool: return combat.can_dodge(), 5.0)
	_dodge(p)
	await _until(func() -> bool: return combat.get_dodge_phase() == PlayerCombat.DodgePhase.INVULNERABLE)
	leave.call()
	await _pause(1.6)
	return at_exit


func _full(p: Player) -> bool:
	return p.combat.get_stamina() == p.combat.get_max_stamina() and p.combat.get_max_stamina() == 100.0 \
		and not p.combat.is_regenerating_stamina()


func _clean(p: Player) -> bool:
	return not p.hurtbox.is_invulnerable and not p.combat.is_dodging() \
		and p.combat.get_dodge_phase() == PlayerCombat.DodgePhase.NONE \
		and p.combat.get_state() == PlayerCombat.State.IDLE and p.combat.can_dodge() \
		and p.combat.data.dodge_duration < 1.0 and Vector2(p.velocity.x, p.velocity.z).length() < 1.0 \
		and not p.combat.has_buffered_attack() and p.combat.get_combo_index() == PlayerCombat.NO_ATTACK


## The dodge button, through the player's own input handler. True if a dodge started.
func _dodge(p: Player) -> bool:
	var was_dodging: bool = p.combat.is_dodging()
	var event: InputEventAction = InputEventAction.new()
	event.action = &"dodge"
	event.pressed = true
	p._unhandled_input(event)
	return p.combat.is_dodging() and not was_dodging


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


func _park_other(room: RoomController, attacker: RoomCombatant) -> void:
	for enemy in room.get_enemies():
		if enemy != attacker:
			_park(enemy, enemy.global_position + Vector3(8, 0, 0))


func _health(enemy: RoomCombatant) -> HealthComponent:
	return enemy.get_node("HealthComponent") as HealthComponent


func _listeners(p: Player) -> Dictionary:
	return {
		"attack_started": p.combat.attack_started.get_connections().size(),
		"stamina_changed": p.combat.stamina_changed.get_connections().size(),
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
