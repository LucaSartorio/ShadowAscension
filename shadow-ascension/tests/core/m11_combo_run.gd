extends SceneTree

## M11.2 — the light combo through the whole game, with real scene changes.
##
##   godot --headless --path . --script res://tests/core/m11_combo_run.gd
##
## Menu -> New Game -> hub -> gate (left with a follow-up queued) -> dungeon:
## a full combo through two enemies, one dying to Attack 1 and the other to
## Attack 2; a third dying to Attack 3; the shadow's own kill; a full combo on
## the boss and its death -> hub (left with a follow-up queued again) -> a
## second dungeon, where the combo has to work exactly as on the first.
##
## Every attack is a real press through the camera rig, pressed inside the
## previous attack's combo window. The harness only parks enemies so two stay
## in one hitbox, and lowers a target's health so a given attack is the one
## that kills it.

const BOOT: String = "res://Main.tscn"
const HUB: String = "res://scenes/core/hub.tscn"
const DUNGEON: String = "res://scenes/dungeons/dungeon_test.tscn"
const ROOM_ANCHORS: Array[Vector3] = [
	Vector3(0, 0.1, -13), Vector3(0, 0.1, -33), Vector3(0, 0.1, -53)
]
const EXIT_POS: Vector3 = Vector3(0, 0.1, -65)
const STRIKE_RANGE: float = 1.6
const LEFT: Vector3 = Vector3(-0.4, 0.0, -1.5)
const RIGHT: Vector3 = Vector3(0.4, 0.0, -1.5)
const CHAIN: Array[StringName] = [&"light_attack_1", &"light_attack_2", &"light_attack_3"]

var _shadow_data: ShadowData = preload("res://resources/shadows/basic_melee_shadow.tres")
var _state: Node = null
var _pass: int = 0
var _fail: int = 0
var _expected_player_xp: int = 0
var _expected_shadow_xp: int = 0
## Listener counts on the first dungeon's player, compared on the second's.
var _first_listeners: Dictionary = {}
## Every hit the player's hitbox landed while watched, as "attack_id>target".
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

	await _phase_hub()
	await _phase_into_dungeon(1)
	await _phase_two_enemies()
	await _phase_third_attack_and_shadow()
	await _phase_boss()
	await _phase_out_to_hub()
	await _phase_into_dungeon(2)
	await _phase_second_run()

	print("[SUMMARY] passed=%d failed=%d" % [_pass, _fail])
	await _pause(0.3)
	quit()


# --- hub --------------------------------------------------------------------------------------

func _phase_hub() -> void:
	var p: Player = current_scene.get_node("Player")
	_record(current_scene.scene_file_path == HUB and p.combat.get_state() == PlayerCombat.State.IDLE
			and p.combat.get_combo_index() == PlayerCombat.NO_ATTACK,
		"H1) New Game: the hub's player is free, no chain running")
	var shadow: ShadowInstance = p.shadows.add_shadow(_shadow_data)
	p.shadow_summoner.summon(shadow.instance_id)
	await _pause(0.4)
	p.shadow_commander.set_mode(BasicMeleeShadow.CommandMode.FOLLOW)


## Leaves through the gate with a follow-up queued: the next scene must not
## inherit the press.
func _phase_into_dungeon(run: int) -> void:
	var p: Player = current_scene.get_node("Player")
	var gate: DungeonGate = current_scene.get_node("DungeonGate")
	var prompt: InteractionPrompt = current_scene.get_node("InteractionPrompt")
	p.global_position = gate.global_position
	await _pause(0.4)
	_record(prompt.is_showing() and prompt.get_text() == gate.prompt_text,
		"G%d.1) the gate prompts '%s'" % [run, prompt.get_text()])
	p.combat.reset()
	_press(p)
	while p.combat.get_state() != PlayerCombat.State.RECOVERY:
		await physics_frame
	_press(p)
	var queued: bool = p.combat.get_queued_attack() != null
	gate.activate()
	await _pause(1.6)

	var dungeon: DungeonController = current_scene as DungeonController
	var fresh: Player = dungeon.get_player()
	var ghost: Array[StringName] = []
	var on_started: Callable = func(attack: AttackData) -> void: ghost.append(attack.id)
	fresh.combat.attack_started.connect(on_started)
	await _pause(0.8)
	fresh.combat.attack_started.disconnect(on_started)
	_record(queued and ghost.is_empty() and fresh.combat.get_state() == PlayerCombat.State.IDLE
			and fresh.combat.get_combo_index() == PlayerCombat.NO_ATTACK
			and fresh.combat.get_queued_attack() == null and not fresh.combat.has_buffered_attack()
			and fresh.attack_hitbox._hit_targets.is_empty(),
		"G%d.2) left with Attack 2 queued: the dungeon's player starts clean — no ghost attack, no index, no buffer, no hit history" % run)

	var listeners: Dictionary = _listeners(fresh)
	if run == 1:
		_first_listeners = listeners
		_record(listeners["attack_started"] == 1, "G1.3) its combat has one listener: %s" % [listeners])
	else:
		_record(listeners == _first_listeners,
			"G2.3) the second dungeon's player has exactly the first one's listeners: %s" % [listeners])
	fresh.hurtbox.set_invulnerable(true)


# --- room 1: two enemies in one hitbox --------------------------------------------------------

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
	# A has one Attack 1 of health left, B an Attack 1 and an Attack 2.
	_health(a).current_health = 20.0
	_health(b).current_health = 45.0
	var watch_a: Dictionary = _watch(a)
	var watch_b: Dictionary = _watch(b)
	_watch_hits(p)
	var xp_before: int = p.progression.get_total_xp()

	var started: Array[StringName] = await _full_combo(p)
	await _pause(0.4)
	_unwatch_hits(p)
	var paid: int = p.progression.get_total_xp() - xp_before
	_record(started == CHAIN, "CB1) the combo ran 1 -> 2 -> 3 (%s)" % [started])
	_record(_hits_on(a) == [&"light_attack_1"] and _health(a).last_damage.attack_id == &"light_attack_1",
		"CB2) enemy A: hit once by Attack 1, which kills it, and never touched by Attack 2 or 3")
	_record(_hits_on(b) == [&"light_attack_1", &"light_attack_2"] and _health(b).last_damage.attack_id == &"light_attack_2",
		"CB3) enemy B, in the same hitbox: Attack 1 and Attack 2 each hit it once; Attack 2 kills it")
	_record(a.get_killer() == p and b.get_killer() == p and paid == a.get_xp_reward() + b.get_xp_reward(),
		"CB4) both kills are the player's, paid once each: %d XP" % paid)
	_expected_player_xp += paid
	_record(_bars_followed(watch_a, [0.0]) and _bars_followed(watch_b, [25.0, 0.0]),
		"CB5) each hit moved its enemy's health bar once, to the right value, never below zero (A %s, B %s)" % [
			watch_a["values"], watch_b["values"]])
	_record(room.is_cleared(), "CB6) and the room clears")


# --- room 2: a kill by Attack 3, and the shadow's -----------------------------------------------

func _phase_third_attack_and_shadow() -> void:
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
	_health(c).current_health = 80.0
	var watch_c: Dictionary = _watch(c)
	var xp_before: int = p.progression.get_total_xp()
	var started: Array[StringName] = await _full_combo(p)
	await _pause(0.4)
	var paid: int = p.progression.get_total_xp() - xp_before
	_record(started == CHAIN and c.has_died() and _health(c).last_damage.attack_id == &"light_attack_3"
			and c.get_killer() == p and paid == c.get_xp_reward(),
		"K1) 80 HP through the full combo: 20, 25, 35 — Attack 3 kills, the player is paid %d once" % paid)
	_record(_bars_followed(watch_c, [60.0, 35.0, 0.0]),
		"K2) and its bar followed every hit: %s" % [watch_c["values"]])
	_expected_player_xp += paid

	# The shadow fights as it always has: its own swing, its own share.
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
		"SH1) the shadow's kill, from its own swing: %d XP -> shadow %d, player %d (got %d / %d)" % [
			reward, shadow_cut, reward - shadow_cut, shadow_gain, player_gain])
	_expected_shadow_xp += shadow_gain
	_expected_player_xp += player_gain


# --- the boss -----------------------------------------------------------------------------------

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
	var ratios: Array[float] = []
	var values: Array[float] = []
	var on_changed: Callable = func(current: float, maximum: float) -> void:
		values.append(start - current)
		ratios.append(absf(bar.get_ratio() - current / maximum))
	health.health_changed.connect(on_changed)
	var started: Array[StringName] = await _full_combo(p, boss)
	health.health_changed.disconnect(on_changed)
	var bar_exact: bool = not ratios.is_empty()
	for error in ratios:
		if error > 0.0001:
			bar_exact = false
	_record(started == CHAIN and values == [20.0, 45.0, 80.0],
		"BO1) a full combo on the boss: 20, then 25, then 35 off it (cumulative %s)" % [values])
	_record(bar_exact, "BO2) and the boss bar matched its health after every hit")

	health.current_health = p.combat.calculate_damage(p.combat.data.light_combo[0])
	var xp_before: int = p.progression.get_total_xp()
	await _full_combo(p, boss)
	await _pause(0.6)
	var paid: int = p.progression.get_total_xp() - xp_before
	_record(boss.has_died() and boss.get_killer() == p and paid == boss.get_xp_reward(),
		"BO3) the boss falls to the combo: %d XP paid once (%d)" % [boss.get_xp_reward(), paid])
	_expected_player_xp += paid
	_record(dungeon.get_state() == DungeonController.DungeonState.COMPLETED and dungeon.exit_portal.is_enabled(),
		"BO4) the dungeon completes, exit open")


# --- back to the hub --------------------------------------------------------------------------

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
	_press(p)
	while p.combat.get_state() != PlayerCombat.State.RECOVERY:
		await physics_frame
	_press(p)
	var queued: bool = p.combat.get_queued_attack() != null
	var used: bool = dungeon.exit_portal.activate()
	await _pause(1.6)

	var hub_player: Player = current_scene.get_node("Player")
	var ghost: Array[StringName] = []
	var on_started: Callable = func(attack: AttackData) -> void: ghost.append(attack.id)
	hub_player.combat.attack_started.connect(on_started)
	await _pause(0.8)
	hub_player.combat.attack_started.disconnect(on_started)
	_record(used and queued and current_scene.scene_file_path == HUB and ghost.is_empty()
			and hub_player.combat.get_state() == PlayerCombat.State.IDLE,
		"R1) left the dungeon with Attack 2 queued: the hub's player does not attack")
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


# --- the second run ---------------------------------------------------------------------------

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
	var started: Array[StringName] = await _full_combo(p)
	_unwatch_hits(p)
	_record(started == CHAIN and _hits_on(enemy) == CHAIN and _bars_followed(watch, [80.0, 55.0, 20.0]),
		"RE1) in the second dungeon the combo runs 1 -> 2 -> 3, one hit each: %s" % [watch["values"]])
	SceneTransition.find_in(self).transition_to_scene(HUB)
	await _pause(1.6)
	_record(current_scene.scene_file_path == HUB
			and int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)) == 0,
		"RE2) and back to the hub, nothing orphaned")


# --- helpers ------------------------------------------------------------------------------------

## The whole chain from a fresh start: each follow-up pressed as the previous
## attack enters its combo window. With `glue`, the player is kept at striking
## distance from it every frame. Returns the attacks that started.
func _full_combo(p: Player, glue: Node3D = null) -> Array[StringName]:
	var started: Array[StringName] = []
	var on_started: Callable = func(attack: AttackData) -> void: started.append(attack.id)
	p.combat.attack_started.connect(on_started)
	p.combat.reset()
	if glue != null:
		p.global_position = glue.global_position + Vector3(0, 0, STRIKE_RANGE)
	_press(p)
	var frames: int = 0
	while p.combat.is_attacking() and frames < 300:
		await physics_frame
		frames += 1
		if glue != null and is_instance_valid(glue):
			p.global_position = glue.global_position + Vector3(0, 0, STRIKE_RANGE)
		if p.combat.get_state() == PlayerCombat.State.RECOVERY and p.combat.get_queued_attack() == null \
				and p.combat.get_combo_index() < CHAIN.size() - 1:
			_press(p)
	p.combat.attack_started.disconnect(on_started)
	return started


func _press(p: Player) -> void:
	p.camera_rig.rotation.y = 0.0
	p.camera_rig.attack_light_pressed.emit()


## Stops an enemy thinking and moving, and puts it where the test needs it.
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


## The attacks that hit `target`, in order.
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
	}


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
