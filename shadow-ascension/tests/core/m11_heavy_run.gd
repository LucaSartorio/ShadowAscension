extends SceneTree

## M11.3 — the heavy attack through the whole game, with real scene changes.
##
##   godot --headless --path . --script res://tests/core/m11_heavy_run.gd
##
## Menu -> New Game -> hub -> gate (left mid-heavy, with both buttons pressed on
## the way) -> dungeon: a light combo and then a heavy through two enemies in one
## hitbox, the heavy killing both; a heavy killing blow; the shadow's own kill; a
## light combo and a heavy on the boss, and a heavy to finish it -> hub (left
## mid-heavy again) -> a second dungeon: heavy first, then the light combo.
##
## Every attack is a real press through the camera rig. The harness only parks
## enemies so two stay in one hitbox, and lowers a target's health so a given
## attack is the one that kills it.

const BOOT: String = "res://Main.tscn"
const HUB: String = "res://scenes/core/hub.tscn"
const ROOM_ANCHORS: Array[Vector3] = [
	Vector3(0, 0.1, -13), Vector3(0, 0.1, -33), Vector3(0, 0.1, -53)
]
const EXIT_POS: Vector3 = Vector3(0, 0.1, -65)
const STRIKE_RANGE: float = 1.6
const LEFT: Vector3 = Vector3(-0.4, 0.0, -1.5)
const RIGHT: Vector3 = Vector3(0.4, 0.0, -1.5)
const LIGHT_CHAIN: Array[StringName] = [&"light_attack_1", &"light_attack_2", &"light_attack_3"]
const HEAVY: StringName = &"heavy_attack_1"

var _shadow_data: ShadowData = preload("res://resources/shadows/basic_melee_shadow.tres")
var _state: Node = null
var _pass: int = 0
var _fail: int = 0
var _expected_player_xp: int = 0
var _expected_shadow_xp: int = 0
var _first_listeners: Dictionary = {}
var _hit_log: Array[String] = []


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
	await _phase_two_enemies()
	await _phase_killing_blow_and_shadow()
	await _phase_boss()
	await _phase_out_to_hub()
	await _phase_into_dungeon(2)
	await _phase_second_run()

	print("[SUMMARY] passed=%d failed=%d" % [_pass, _fail])
	await _pause(0.3)
	quit()


## Walks through the gate in the middle of a heavy, pressing both buttons on
## the way: nothing of it may reach the next scene.
func _phase_into_dungeon(run: int) -> void:
	var p: Player = current_scene.get_node("Player")
	var gate: DungeonGate = current_scene.get_node("DungeonGate")
	var prompt: InteractionPrompt = current_scene.get_node("InteractionPrompt")
	p.global_position = gate.global_position
	await _pause(0.4)
	_record(prompt.is_showing() and prompt.get_text() == gate.prompt_text,
		"G%d.1) the gate prompts '%s'" % [run, prompt.get_text()])
	p.combat.reset()
	_heavy(p)
	while p.combat.get_state() != PlayerCombat.State.ACTIVE:
		await physics_frame
	_light(p)
	_heavy(p)
	var mid_heavy: bool = p.combat.get_current_attack().id == HEAVY and p.attack_hitbox.is_active()
	gate.activate()
	await _pause(1.6)

	var dungeon: DungeonController = current_scene as DungeonController
	var fresh: Player = dungeon.get_player()
	var ghost: Array[StringName] = []
	var on_started: Callable = func(attack: AttackData) -> void: ghost.append(attack.id)
	fresh.combat.attack_started.connect(on_started)
	await _pause(0.8)
	fresh.combat.attack_started.disconnect(on_started)
	_record(mid_heavy and ghost.is_empty() and fresh.combat.get_state() == PlayerCombat.State.IDLE
			and fresh.combat.get_current_attack() == null and not fresh.attack_hitbox.is_active()
			and fresh.combat.get_combo_index() == PlayerCombat.NO_ATTACK
			and not fresh.combat.has_buffered_attack() and fresh.attack_hitbox._hit_targets.is_empty(),
		"G%d.2) left mid-heavy with the hitbox open: the dungeon's player starts clean — no heavy, no hitbox, no buffer, no ghost attack" % run)
	var listeners: Dictionary = _listeners(fresh)
	if run == 1:
		_first_listeners = listeners
	else:
		_record(listeners == _first_listeners,
			"G2.3) the second dungeon's player has exactly the first one's listeners: %s" % [listeners])
	fresh.hurtbox.set_invulnerable(true)


# --- room 1: light combo, then a heavy through two enemies ---------------------------------------

func _phase_two_enemies() -> void:
	var dungeon: DungeonController = current_scene as DungeonController
	var p: Player = dungeon.get_player()
	p.global_position = ROOM_ANCHORS[0]
	await _pause(0.8)
	var room: RoomController = dungeon.get_rooms()[0]
	var a: RoomCombatant = room.get_enemies()[0]
	var b: RoomCombatant = room.get_enemies()[1]
	_park(a, ROOM_ANCHORS[0] + LEFT)
	_park(b, ROOM_ANCHORS[0] + RIGHT)
	await _pause(0.3)
	p.global_position = ROOM_ANCHORS[0]
	var watch_a: Dictionary = _watch(a)
	var watch_b: Dictionary = _watch(b)
	_watch_hits(p)
	var xp_before: int = p.progression.get_total_xp()

	var started: Array[StringName] = await _light_combo(p)
	var xp_after_combo: int = p.progression.get_total_xp()
	started.append_array(await _heavy_swing(p))
	await _pause(0.4)
	_unwatch_hits(p)
	var paid: int = p.progression.get_total_xp() - xp_before
	var expected_hits: Array[StringName] = [&"light_attack_1", &"light_attack_2", &"light_attack_3", HEAVY]
	_record(started == expected_hits, "E1) light combo, then a heavy: %s" % [started])
	_record(_hits_on(a) == expected_hits and _hits_on(b) == expected_hits,
		"E2) each enemy in the hitbox was hit once by every attack, the heavy included")
	_record(_bars_followed(watch_a, [80.0, 55.0, 20.0, 0.0]) and _bars_followed(watch_b, [80.0, 55.0, 20.0, 0.0]),
		"E3) each hit — light or heavy — moved both health bars once, to the right value (%s)" % [watch_a["values"]])
	_record(a.has_died() and b.has_died() and _health(a).last_damage.attack_id == HEAVY
			and _health(b).last_damage.attack_id == HEAVY and a.get_killer() == p and b.get_killer() == p,
		"E4) the heavy's 40 finished both: two deaths, both the player's")
	_record(xp_after_combo == xp_before and paid == a.get_xp_reward() + b.get_xp_reward(),
		"E5) and each paid once, separately: %d XP" % paid)
	_expected_player_xp += paid
	_record(room.is_cleared(), "E6) the room clears")


# --- room 2: a heavy killing blow, and the shadow's kill ------------------------------------------

func _phase_killing_blow_and_shadow() -> void:
	var dungeon: DungeonController = current_scene as DungeonController
	var p: Player = dungeon.get_player()
	p.global_position = ROOM_ANCHORS[1]
	await _pause(0.8)
	var room: RoomController = dungeon.get_rooms()[1]
	var c: RoomCombatant = room.get_enemies()[0]
	var d: RoomCombatant = room.get_enemies()[1]
	_park(c, ROOM_ANCHORS[1] + Vector3(0, 0, -1.5))
	await _pause(0.3)
	p.global_position = ROOM_ANCHORS[1]
	_health(c).current_health = 30.0
	var watch_c: Dictionary = _watch(c)
	var deaths: Array[int] = []
	c.enemy_died.connect(func(_dead: RoomCombatant) -> void: deaths.append(1))
	_watch_hits(p)
	var xp_before: int = p.progression.get_total_xp()
	await _heavy_swing(p)
	await _heavy_swing(p)
	await _pause(0.4)
	_unwatch_hits(p)
	var paid: int = p.progression.get_total_xp() - xp_before
	_record(deaths.size() == 1 and _hits_on(c) == [HEAVY] and _bars_followed(watch_c, [0.0])
			and paid == c.get_xp_reward(),
		"K1) a heavy on 30 HP: one death, one hit, one bar update, %d XP once; the next heavy finds nothing" % paid)
	_expected_player_xp += paid

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
	_record(d.has_died() and d.get_killer() == node and d_health.last_damage.attack_id == &""
			and shadow_gain == shadow_cut and player_gain == reward - shadow_cut,
		"SH1) the shadow's kill, from its own swing, unchanged: %d XP -> shadow %d, player %d (got %d / %d)" % [
			reward, shadow_cut, reward - shadow_cut, shadow_gain, player_gain])
	_expected_shadow_xp += shadow_gain
	_expected_player_xp += player_gain


# --- the boss -------------------------------------------------------------------------------------

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
	var start: float = health.current_health
	var dealt: Array[float] = []
	var bar_errors: Array[float] = []
	var on_changed: Callable = func(current: float, maximum: float) -> void:
		dealt.append(start - current)
		bar_errors.append(absf(bar.get_ratio() - current / maximum))
	health.health_changed.connect(on_changed)
	var started: Array[StringName] = await _light_combo(p, boss)
	started.append_array(await _heavy_swing(p, boss))
	health.health_changed.disconnect(on_changed)
	var bar_exact: bool = not bar_errors.is_empty() and bar_errors.max() < 0.0001
	_record(started == [&"light_attack_1", &"light_attack_2", &"light_attack_3", HEAVY]
			and dealt == [20.0, 45.0, 80.0, 120.0],
		"BO1) light combo, then a heavy, on the boss: 20, 25, 35, then 40 off it (cumulative %s)" % [dealt])
	_record(bar_exact, "BO2) the boss bar matched its health after every hit, light or heavy")

	health.current_health = p.combat.calculate_damage(p.combat.data.heavy_combo[0])
	var xp_before: int = p.progression.get_total_xp()
	await _heavy_swing(p, boss)
	await _pause(0.6)
	var paid: int = p.progression.get_total_xp() - xp_before
	_record(boss.has_died() and boss.get_killer() == p and health.last_damage.attack_id == HEAVY
			and paid == boss.get_xp_reward(),
		"BO3) a heavy finishes the boss: %d XP paid once (%d)" % [boss.get_xp_reward(), paid])
	_expected_player_xp += paid
	_record(dungeon.get_state() == DungeonController.DungeonState.COMPLETED and dungeon.exit_portal.is_enabled(),
		"BO4) the dungeon completes, exit open")


# --- back to the hub --------------------------------------------------------------------------------

func _phase_out_to_hub() -> void:
	var dungeon: DungeonController = current_scene as DungeonController
	var p: Player = dungeon.get_player()
	p.hurtbox.set_invulnerable(false)
	p.hurtbox.receive_hit(DamageInfo.new(13.0))
	var health_left: float = p.health_component.current_health
	var level: int = p.progression.current_level
	p.global_position = EXIT_POS
	await _pause(0.4)
	p.combat.reset()
	_heavy(p)
	while p.combat.get_state() != PlayerCombat.State.ACTIVE:
		await physics_frame
	_light(p)
	_heavy(p)
	var used: bool = dungeon.exit_portal.activate()
	await _pause(1.6)

	var hub_player: Player = current_scene.get_node("Player")
	var ghost: Array[StringName] = []
	var on_started: Callable = func(attack: AttackData) -> void: ghost.append(attack.id)
	hub_player.combat.attack_started.connect(on_started)
	await _pause(0.8)
	hub_player.combat.attack_started.disconnect(on_started)
	_record(used and current_scene.scene_file_path == HUB and ghost.is_empty()
			and hub_player.combat.get_state() == PlayerCombat.State.IDLE and not hub_player.attack_hitbox.is_active(),
		"R1) left the dungeon mid-heavy: the hub's player does not attack, its hitbox shut")
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


# --- the second run ---------------------------------------------------------------------------------

func _phase_second_run() -> void:
	var dungeon: DungeonController = current_scene as DungeonController
	var p: Player = dungeon.get_player()
	p.global_position = ROOM_ANCHORS[0]
	await _pause(0.8)
	var enemy: RoomCombatant = dungeon.get_rooms()[0].get_enemies()[0]
	_park(enemy, ROOM_ANCHORS[0] + Vector3(0, 0, -1.5))
	await _pause(0.3)
	p.global_position = ROOM_ANCHORS[0]
	var watch: Dictionary = _watch(enemy)
	_watch_hits(p)
	var started: Array[StringName] = await _heavy_swing(p)
	started.append_array(await _light_combo(p))
	await _pause(0.4)
	_unwatch_hits(p)
	_record(started == [HEAVY, &"light_attack_1", &"light_attack_2", &"light_attack_3"]
			and _hits_on(enemy) == started and _bars_followed(watch, [60.0, 40.0, 15.0, 0.0])
			and _health(enemy).last_damage.attack_id == &"light_attack_3",
		"RE1) second dungeon: a heavy, then the light combo from Light 1: %s, the third light kills" % [watch["values"]])
	SceneTransition.find_in(self).transition_to_scene(HUB)
	await _pause(1.6)
	_record(current_scene.scene_file_path == HUB
			and int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)) == 0,
		"RE2) and back to the hub, nothing orphaned")


# --- helpers ----------------------------------------------------------------------------------------

## The light combo from a fresh start, each follow-up pressed as the previous
## attack enters its window. With `glue`, the player is kept at striking
## distance from it every frame. Returns the attacks that started.
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
				and p.combat.get_combo_index() < LIGHT_CHAIN.size() - 1:
			_light(p)
	p.combat.attack_started.disconnect(on_started)
	return started


## One heavy from a free player, waited out.
func _heavy_swing(p: Player, glue: Node3D = null) -> Array[StringName]:
	var started: Array[StringName] = []
	var on_started: Callable = func(attack: AttackData) -> void: started.append(attack.id)
	p.combat.attack_started.connect(on_started)
	_stick(p, glue)
	_heavy(p)
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


func _heavy(p: Player) -> void:
	p.camera_rig.rotation.y = 0.0
	p.camera_rig.attack_heavy_pressed.emit()


func _park(enemy: RoomCombatant, at: Vector3) -> void:
	enemy.set_combat_enabled(false)
	enemy.velocity = Vector3.ZERO
	enemy.global_position = at


func _health(enemy: RoomCombatant) -> HealthComponent:
	return enemy.get_node("HealthComponent") as HealthComponent


## Every health change of `enemy`, and whether its bar agreed at that moment.
func _watch(enemy: RoomCombatant) -> Dictionary:
	var watch: Dictionary = {"values": [], "bar_ok": true}
	var bar: EnemyHealthBar3D = enemy.get_node("EnemyHealthBar3D")
	_health(enemy).health_changed.connect(func(current: float, maximum: float) -> void:
		watch["values"].append(current)
		if current < 0.0 or absf(bar.get_ratio() - current / maximum) > 0.0001:
			watch["bar_ok"] = false)
	return watch


func _bars_followed(watch: Dictionary, expected: Array) -> bool:
	return watch["bar_ok"] and watch["values"] == expected


func _watch_hits(p: Player) -> void:
	_hit_log.clear()
	p.attack_hitbox.hit_landed.connect(_on_hit_landed)


func _unwatch_hits(p: Player) -> void:
	p.attack_hitbox.hit_landed.disconnect(_on_hit_landed)


func _on_hit_landed(target: Node, info: DamageInfo) -> void:
	_hit_log.append("%s>%s" % [info.attack_id, target.name])


func _hits_on(target: Node) -> Array[StringName]:
	var attacks: Array[StringName] = []
	for entry in _hit_log:
		var parts: PackedStringArray = entry.split(">")
		if parts[1] == target.name:
			attacks.append(StringName(parts[0]))
	return attacks


func _listeners(p: Player) -> Dictionary:
	return {
		"attack_started": p.combat.attack_started.get_connections().size(),
		"hit_landed": p.attack_hitbox.hit_landed.get_connections().size(),
		"died": p.health_component.died.get_connections().size(),
		"health_changed": p.health_component.health_changed.get_connections().size(),
		"heavy_pressed": p.camera_rig.attack_heavy_pressed.get_connections().size(),
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
