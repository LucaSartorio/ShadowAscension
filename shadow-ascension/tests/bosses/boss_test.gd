extends Node3D

## M5.1 First Boss Foundation — activation, the three attacks, decision logic,
## cooldowns, commitment, hit feedback, death and dungeon integration.
## M4's room/door/progression coverage lives in the dungeon suites.

const DUNGEON: PackedScene = preload("res://scenes/dungeons/dungeon_test.tscn")

const ROOM1_TRIGGER: Vector3 = Vector3(0, 0.1, -13)
const ROOM2_TRIGGER: Vector3 = Vector3(0, 0.1, -33)
const BOSS_TRIGGER: Vector3 = Vector3(0, 0.1, -53)

const QUICK: int = 0
const SWEEP: int = 1
const SLAM: int = 2

var _pass: int = 0
var _fail: int = 0

var _dungeon: DungeonController = null
var _player: Player = null
var _boss: DungeonBoss = null
var _bar: BossHealthBar = null
var _boss_room: RoomController = null


func _ready() -> void:
	_run()


func _run() -> void:
	await _wait(0.2)
	_reset_session()
	await _setup()
	await _activation_tests()
	await _attack_tests()
	await _commitment_tests()
	await _decision_tests()
	await _receiving_damage_tests()
	await _death_tests()
	print("[SUMMARY] passed=%d failed=%d" % [_pass, _fail])
	get_tree().quit()


func _wait(t: float) -> void:
	await get_tree().create_timer(t).timeout


func _record(passed: bool, description: String) -> void:
	if passed:
		_pass += 1
		print("[PASS] " + description)
	else:
		_fail += 1
		print("[FAIL] " + description)


# --- helpers ------------------------------------------------------------------

func _setup() -> void:
	_dungeon = DUNGEON.instantiate() as DungeonController
	add_child(_dungeon)
	await _wait(0.8)
	_player = _dungeon.get_node("Player")
	_bar = _dungeon.get_node("BossHealthBar")
	_boss_room = _dungeon.get_rooms()[2]
	_boss = _boss_room.get_enemies()[0] as DungeonBoss


## Parks the player at `distance` straight in front of the boss and points the
## boss at it, so an attack that starts will actually reach.
func _place_player(distance: float) -> void:
	_player.global_position = _boss.global_position + Vector3(0, 0, -distance)
	_boss.visual_root.rotation.y = 0.0
	await get_tree().physics_frame


## Makes `index` the only attack the decision layer can choose, then waits for it
## to land. Returns the damage the player took.
func _force_attack(index: int, distance: float, timeout: float = 4.0) -> float:
	_player.health_component.current_health = _player.health_component.max_health
	_player.health_component.is_dead = false
	_player.hurtbox.set_invulnerable(false)
	await _place_player(distance)
	for i in _boss.attacks.size():
		_boss._cooldowns[i] = 0.0 if i == index else 99.0
	_boss._last_attack = -1
	_boss._consecutive = 0
	_boss._state = DungeonBoss.State.DECIDE

	var hp_before: float = _player.health_component.current_health
	var elapsed: float = 0.0
	while elapsed < timeout:
		await get_tree().physics_frame
		elapsed += get_physics_process_delta_time()
		if _player.health_component.current_health < hp_before:
			break
	return hp_before - _player.health_component.current_health


func _reset_boss_to_decide() -> void:
	_boss._state = DungeonBoss.State.DECIDE
	_boss._attack_phase = DungeonBoss.AttackPhase.NONE
	_boss._active_attack = -1
	for i in _boss.attacks.size():
		_boss._cooldowns[i] = 0.0


# --- activation ---------------------------------------------------------------

func _activation_tests() -> void:
	_record(_boss != null and _boss is DungeonBoss, "2) the boss room holds a DungeonBoss")
	_record(not _boss.combat_enabled and _boss.get_state() == DungeonBoss.State.INACTIVE,
		"3) boss is INACTIVE before the player arrives (combat=%s state=%d)" % [
			_boss.combat_enabled, _boss.get_state()])
	_record(not _bar.is_showing(), "6a) boss health bar hidden before the encounter")

	# a dormant boss must not act even with the player right next to it
	_player.global_position = _boss.global_position + Vector3(1.5, 0, 0)
	var hp: float = _player.health_component.current_health
	var boss_pos: Vector3 = _boss.global_position
	await _wait(1.5)
	_record(_player.health_component.current_health == hp
			and _boss.global_position.distance_to(boss_pos) < 0.1,
		"3b) dormant boss neither moves nor attacks")

	# clear the first two rooms so the dungeon reaches the boss properly
	for i in 2:
		_player.global_position = [ROOM1_TRIGGER, ROOM2_TRIGGER][i]
		await _wait(0.4)
		for enemy in _dungeon.get_rooms()[i].get_enemies():
			enemy.hurtbox.receive_hit(DamageInfo.new(1000.0, null))
		await _wait(0.5)

	_player.global_position = BOSS_TRIGGER
	await _wait(0.4)
	_record(_boss.combat_enabled and _boss_room.get_state() == RoomController.RoomState.ACTIVE,
		"4) entering the boss room wakes the boss")
	_record(_boss.get_state() == DungeonBoss.State.INTRO,
		"4b) the wake goes INACTIVE -> INTRO (state=%d)" % _boss.get_state())
	await _wait(_boss.intro_duration + 0.2)
	_record(_boss.get_state() != DungeonBoss.State.INACTIVE
			and _boss.get_state() != DungeonBoss.State.INTRO,
		"4c) INTRO ends on its own and the encounter runs (state=%d)" % _boss.get_state())
	_record(_boss_room.exit_door.is_locked(), "5) boss room door locks on entry")
	_record(_bar.is_showing() and is_equal_approx(_bar.get_ratio(), 1.0),
		"6) boss health bar appears full (ratio=%.2f)" % _bar.get_ratio())

	# 7) chase: from across the room the boss should close in
	_player.global_position = _boss.global_position + Vector3(0, 0, 7.0)
	var start_dist: float = _boss.global_position.distance_to(_player.global_position)
	var saw_chase: bool = false
	var chase_elapsed: float = 0.0
	while chase_elapsed < 1.6:
		if _boss.get_state() == DungeonBoss.State.CHASE:
			saw_chase = true
		await get_tree().physics_frame
		chase_elapsed += get_physics_process_delta_time()
	var end_dist: float = _boss.global_position.distance_to(_player.global_position)
	_record(start_dist - end_dist > 1.0, "7) boss closes distance (%.2f -> %.2f)" % [start_dist, end_dist])
	_record(saw_chase, "7b) it does it in CHASE, not by drifting")

	# 8) reposition: standing on top of it, the boss should back off, not stay glued.
	# The budget has to outlast an attack already in flight — a Ground Slam commits
	# the boss for 2.05s, and refusing to abandon it is the feature, not a stall.
	_player.global_position = _boss.global_position + Vector3(0, 0, 0.9)
	var saw_reposition: bool = false
	var rep_elapsed: float = 0.0
	while rep_elapsed < 5.0:
		if _boss.get_state() == DungeonBoss.State.REPOSITION:
			saw_reposition = true
		if saw_reposition and _boss.get_state() != DungeonBoss.State.REPOSITION:
			break
		await get_tree().physics_frame
		rep_elapsed += get_physics_process_delta_time()
	_record(saw_reposition, "8b) it enters REPOSITION to do it")
	var gap: float = _boss.global_position.distance_to(_player.global_position)
	_record(gap >= _boss.minimum_combat_distance,
		"8) boss repositions out of the player's lap (gap=%.2f >= %.2f)" % [gap, _boss.minimum_combat_distance])


# --- the three attacks ---------------------------------------------------------

func _attack_tests() -> void:
	var quick: float = await _force_attack(QUICK, 1.8)
	_record(quick == 20.0, "9/10) Quick Strike lands for 20 (%.0f)" % quick)

	var sweep: float = await _force_attack(SWEEP, 2.0)
	_record(sweep == 30.0, "11/12) Wide Sweep lands for 30 (%.0f)" % sweep)

	var slam: float = await _force_attack(SLAM, 2.5)
	_record(slam == 40.0, "13/14) Ground Slam lands for 40 (%.0f)" % slam)

	# 15) every attack drives a real Hitbox that is only live during ACTIVE.
	# _force_attack returns the instant damage lands, so wait out the swing first.
	await _wait(1.4)
	var names: Array[String] = []
	var gated: bool = true
	for i in 3:
		var hitbox: Hitbox = _boss._hitboxes[i]
		names.append(hitbox.name)
		if hitbox.is_active():
			gated = false
	_record(names.size() == 3 and gated,
		"15) all three attacks own a real Hitbox, idle between swings: %s" % str(names))

	# 16) damage is overlap-driven, never distance-driven: blind the player's
	# hurtbox and the same attack at the same range must do nothing
	_player.health_component.current_health = _player.health_component.max_health
	_player.hurtbox.monitorable = false
	var blind: float = await _force_attack(SLAM, 2.5, 3.0)
	_player.hurtbox.monitorable = true
	_record(blind == 0.0, "16) with the hurtbox unreachable the attack deals nothing (%.0f)" % blind)


# --- telegraph and commitment ---------------------------------------------------

func _commitment_tests() -> void:
	# 17) each wind-up deforms a different channel, so they read apart
	var shapes: Array[String] = []
	for index in [QUICK, SWEEP, SLAM]:
		await _place_player(2.0)
		for i in _boss.attacks.size():
			_boss._cooldowns[i] = 0.0 if i == index else 99.0
		_boss._last_attack = -1
		_boss._consecutive = 0
		_boss._state = DungeonBoss.State.DECIDE
		_player.hurtbox.set_invulnerable(true)
		await _wait(_boss.attacks[index].startup * 0.8)
		# Compare each channel against its own target magnitude and take the
		# dominant one, instead of trusting a fixed check order.
		var m: Node3D = _boss.mesh_root
		var lean: float = absf(m.rotation.x) / deg_to_rad(22.0)
		var spin: float = absf(m.rotation.y) / TAU
		var compress: float = absf(1.0 - m.scale.y) / 0.45
		var best: float = maxf(lean, maxf(spin, compress))
		if best < 0.1:
			shapes.append("none")
		elif is_equal_approx(best, lean):
			shapes.append("lean")
		elif is_equal_approx(best, spin):
			shapes.append("spin")
		else:
			shapes.append("compress")
		await _wait(1.8)
		# settle the body so the next sample reads a clean wind-up, not a reset
		_boss._reset_telegraph_instantly()
		await get_tree().physics_frame
	var distinct: bool = shapes.size() == 3 and shapes[0] != shapes[1] and shapes[1] != shapes[2] and shapes[0] != shapes[2]
	_record(distinct and not shapes.has("none"),
		"17) the three wind-ups are visually distinct: %s" % str(shapes))

	# 18) ACTIVE does not track
	await _place_player(2.0)
	for i in _boss.attacks.size():
		_boss._cooldowns[i] = 0.0 if i == SLAM else 99.0
	_boss._last_attack = -1
	_boss._state = DungeonBoss.State.DECIDE
	var locked: bool = false
	var elapsed: float = 0.0
	while elapsed < 3.0:
		await get_tree().physics_frame
		elapsed += get_physics_process_delta_time()
		if _boss.get_attack_phase() == DungeonBoss.AttackPhase.ACTIVE:
			var yaw_before: float = _boss.visual_root.rotation.y
			_player.global_position = _boss.global_position + Vector3(2.0, 0, 0)
			await get_tree().physics_frame
			await get_tree().physics_frame
			locked = is_equal_approx(yaw_before, _boss.visual_root.rotation.y)
			break
	_record(locked, "18) facing is locked during ACTIVE")
	_player.hurtbox.set_invulnerable(false)
	await _wait(1.5)

	# 19) the player can make an attack miss by leaving during the wind-up
	_player.health_component.current_health = _player.health_component.max_health
	await _place_player(2.0)
	for i in _boss.attacks.size():
		_boss._cooldowns[i] = 0.0 if i == QUICK else 99.0
	_boss._last_attack = -1
	_boss._state = DungeonBoss.State.DECIDE
	var hp: float = _player.health_component.current_health
	await _wait(0.12)
	_player.global_position = _boss.global_position + Vector3(0, 0, 9.0)
	await _wait(0.9)
	_record(_player.health_component.current_health == hp,
		"19) stepping out during startup avoids the hit (hp %.0f)" % _player.health_component.current_health)

	# 20/21) dodge and i-frames still gate boss damage with no boss-side logic
	_player.health_component.current_health = _player.health_component.max_health
	await _place_player(2.5)
	for i in _boss.attacks.size():
		_boss._cooldowns[i] = 0.0 if i == SLAM else 99.0
	_boss._last_attack = -1
	_boss._state = DungeonBoss.State.DECIDE
	var saved_speed: float = _player.dodge_speed
	_player.dodge_speed = 0.0  # isolate the i-frame window from displacement
	var dodged: bool = false
	var iframe_hp: float = _player.health_component.current_health
	elapsed = 0.0
	while elapsed < 3.0:
		await get_tree().physics_frame
		elapsed += get_physics_process_delta_time()
		if _boss.get_attack_phase() == DungeonBoss.AttackPhase.STARTUP and not dodged:
			if _boss._phase_timer <= 0.1:
				_player.combat._dodge_cooldown_remaining = 0.0
				_player._on_dodge_pressed()
				dodged = true
		if _boss.get_attack_phase() == DungeonBoss.AttackPhase.NONE and dodged:
			break
	_player.dodge_speed = saved_speed
	_record(dodged and _player.hurtbox != null and _player.health_component.current_health == iframe_hp,
		"20/21) dodge i-frames shrug off a boss attack (dodged=%s hp %.0f -> %.0f)" % [
			dodged, iframe_hp, _player.health_component.current_health])
	await _wait(1.2)


# --- decision logic -------------------------------------------------------------

func _decision_tests() -> void:
	_player.health_component.current_health = _player.health_component.max_health
	_player.hurtbox.set_invulnerable(true)
	await _place_player(2.0)
	_reset_boss_to_decide()

	# 22) let it fight freely and watch what it picks
	var sequence: Array[int] = []
	var elapsed: float = 0.0
	var last_seen: int = -1
	while elapsed < 22.0:
		await get_tree().physics_frame
		elapsed += get_physics_process_delta_time()
		_player.global_position = _boss.global_position + Vector3(0, 0, -2.0)
		var active: int = _boss.get_active_attack_index()
		if active >= 0 and active != last_seen:
			sequence.append(active)
			last_seen = active
		elif active < 0:
			last_seen = -1

	var max_run: int = 0
	var run: int = 0
	var prev: int = -1
	for a in sequence:
		run = run + 1 if a == prev else 1
		prev = a
		max_run = maxi(max_run, run)
	var used: Dictionary = {}
	for a in sequence:
		used[a] = true
	_record(sequence.size() >= 6 and max_run <= _boss.max_consecutive_repeats,
		"22) no attack repeats more than %d in a row (longest run=%d over %d attacks)" % [
			_boss.max_consecutive_repeats, max_run, sequence.size()])
	_record(used.size() == 3, "22b) all three attacks appear in a free fight (%d distinct, %s)" % [
		used.size(), str(sequence)])

	# 23) individual cooldowns: using one must not arm the others
	_reset_boss_to_decide()
	await _place_player(2.0)
	for i in _boss.attacks.size():
		_boss._cooldowns[i] = 0.0 if i == QUICK else 99.0
	_boss._last_attack = -1
	_boss._state = DungeonBoss.State.DECIDE
	var saw_attack: bool = false
	elapsed = 0.0
	while elapsed < 3.0:
		await get_tree().physics_frame
		elapsed += get_physics_process_delta_time()
		if _boss.get_active_attack_index() == QUICK:
			saw_attack = true
			break
	await _wait(0.1)
	var quick_cd: float = _boss.get_attack_cooldown(QUICK)
	_record(saw_attack and is_equal_approx(_boss.attacks[QUICK].cooldown, 1.0) and quick_cd > 0.0,
		"23) using an attack starts its own cooldown (quick=%.2f of %.1f)" % [
			quick_cd, _boss.attacks[QUICK].cooldown])
	await _wait(1.2)
	_record(_boss.get_attack_cooldown(QUICK) == 0.0 and _boss.get_attack_cooldown(SLAM) > 0.0,
		"23b) cooldowns are per attack, not shared (quick=%.2f slam=%.2f)" % [
			_boss.get_attack_cooldown(QUICK), _boss.get_attack_cooldown(SLAM)])


# --- taking damage ---------------------------------------------------------------

func _receiving_damage_tests() -> void:
	_boss._state = DungeonBoss.State.INTRO
	_boss._intro_timer = 99.0  # hold it still while the player swings
	_boss.health_component.current_health = _boss.health_component.max_health
	_boss._last_health = _boss.health_component.max_health
	await _wait(0.2)

	# 24/25) a player swing lands exactly once, for its own damage
	var hits: Array[float] = []
	var counter: Callable = func(current: float, _maximum: float) -> void:
		hits.append(current)
	_boss.health_component.health_changed.connect(counter)
	_player.global_position = _boss.global_position + Vector3(0, 0, 1.6)
	_player.camera_rig.rotation.y = 0.0
	_player.visual_root.rotation.y = 0.0
	var before: float = _boss.health_component.current_health
	_player.camera_rig.attack_light_pressed.emit()
	await _wait(0.7)
	_boss.health_component.health_changed.disconnect(counter)
	var dealt: float = before - _boss.health_component.current_health
	_record(dealt == 20.0, "24) the player's Attack 1 damages the boss for 20 (%.0f)" % dealt)
	_record(hits.size() == 1, "25) one player swing hits the boss exactly once (%d)" % hits.size())

	# 26) hit feedback fires, without stagger
	var boss_pos: Vector3 = _boss.global_position
	_boss.hurtbox.receive_hit(DamageInfo.new(25.0, null))
	await get_tree().physics_frame
	var feedback: bool = _boss._feedback_tween != null and _boss._feedback_tween.is_running()
	await _wait(0.3)
	_record(feedback and _boss.global_position.distance_to(boss_pos) < 0.05,
		"26) hit feedback plays with no positional recoil (tween=%s)" % feedback)

	# 27) the bar follows the health component
	var ratio_before: float = _bar.get_ratio()
	_boss.hurtbox.receive_hit(DamageInfo.new(100.0, null))
	await _wait(0.2)
	var expected: float = _boss.health_component.current_health / _boss.health_component.max_health
	_record(_bar.get_ratio() < ratio_before and is_equal_approx(_bar.get_ratio(), expected),
		"27) boss health bar tracks the health component (%.3f, expected %.3f)" % [_bar.get_ratio(), expected])


# --- death and dungeon integration ------------------------------------------------

func _death_tests() -> void:
	_player.hurtbox.set_invulnerable(false)
	_player.health_component.current_health = _player.health_component.max_health
	_boss.hurtbox.receive_hit(DamageInfo.new(10000.0, null))
	await _wait(0.4)

	_record(_boss.get_state() == DungeonBoss.State.DEAD and _boss.health_component.is_dead,
		"28) the boss dies at zero HP (state=%d)" % _boss.get_state())

	var pos: Vector3 = _boss.global_position
	var player_hp: float = _player.health_component.current_health
	_player.global_position = _boss.global_position + Vector3(0, 0, 1.5)
	await _wait(1.5)
	_record(_boss.global_position.distance_to(pos) < 0.05 and _boss.velocity == Vector3.ZERO,
		"29) a dead boss does not move (drift=%.3f)" % _boss.global_position.distance_to(pos))
	var any_live: bool = false
	for hitbox in _boss._hitboxes:
		if hitbox != null and hitbox.is_active():
			any_live = true
	_record(not any_live and _player.health_component.current_health == player_hp,
		"30) a dead boss has no live hitbox and deals no damage")
	_record(not _bar.is_showing(), "31) boss health bar disappears on death")

	_record(_boss_room.is_cleared() and not _boss_room.exit_door.is_locked(),
		"32) the boss room clears and opens")
	_record(_dungeon.get_state() == DungeonController.DungeonState.COMPLETED,
		"33) the dungeon reaches COMPLETED (state=%d)" % _dungeon.get_state())
	_record(_dungeon.exit_portal.is_enabled(), "34) the exit portal goes live")


## Every suite starts from a clean session: PlayerRuntimeState now carries
## progression and health across scene changes, so without this a later test
## would inherit whatever an earlier one left behind.
func _reset_session() -> void:
	var state: Node = get_tree().root.get_node_or_null("PlayerRuntimeState")
	if state != null:
		state.reset_runtime_state()
