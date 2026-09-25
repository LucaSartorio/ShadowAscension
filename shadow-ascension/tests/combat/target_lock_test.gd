extends Node3D

## M11.8 — the target lock, on a real player, real enemies, the boss and the
## real indicator.
##
##   godot --headless --path . res://tests/combat/target_lock_test.tscn
##
## Every lock, release and switch goes in the way a device sends it: an
## InputEventAction through the player's own _unhandled_input. Attacks are the
## player's real attacks landing through its real hitbox. The camera looks down
## -Z unless a test turns it. A watcher checks every physics frame that the lock
## is never in an impossible state once the frame's physics has run.

const DT: float = 1.0 / 60.0
const PARKED: Array[Vector3] = [
	Vector3(-20, 0.1, 40), Vector3(-16, 0.1, 40), Vector3(-12, 0.1, 40), Vector3(-8, 0.1, 40), Vector3(-4, 0.1, 40)]
const BOSS_PARKED: Vector3 = Vector3(20, 0.1, 40)
const PROP_PARKED: Vector3 = Vector3(0, 0.1, 50)

## Criticals are random (M11.7) and this suite checks exact damage, so they are
## off for its whole run: every player here reads this one cached instance of
## the combat data. critical_hit_test and m11_critical_run test criticals.
var _no_crits: PlayerCombatData = preload("res://resources/characters/player_combat.tres")

@onready var _player: Player = $Player
@onready var _a: BasicMeleeEnemy = $EnemyA
@onready var _b: BasicMeleeEnemy = $EnemyB
@onready var _c: BasicMeleeEnemy = $EnemyC
@onready var _d: BasicMeleeEnemy = $EnemyD
@onready var _e: BasicMeleeEnemy = $EnemyE
@onready var _boss: DungeonBoss = $Boss
@onready var _prop: CharacterBody3D = $EnemyLayerProp
@onready var _indicator: TargetLockIndicator = $TargetLockIndicator

var _targeting: PlayerTargeting = null
var _combat: PlayerCombat = null
var _changes: Array[String] = []
var _violations: Array[String] = []
var _watching: bool = false
var _pass: int = 0
var _fail: int = 0


func _ready() -> void:
	_no_crits.critical_chance = 0.0
	_reset_session()
	_targeting = _player.targeting
	_combat = _player.combat
	_targeting.target_changed.connect(_on_target_changed)
	_player.hurtbox.set_invulnerable(true)
	_run()


## After the frame's physics, so the targeting has had its tick: a target freed
## or walked out of range is let go on that tick, not before it.
func _process(_delta: float) -> void:
	if _watching:
		_check_invariants()


func _run() -> void:
	await _frames(10)
	_watching = true
	_config_tests()
	await _no_target_tests()
	await _initial_lock_tests()
	await _scoring_tests()
	await _line_of_sight_tests()
	await _unlock_tests()
	await _range_tests()
	await _switch_tests()
	await _attack_tests()
	await _dodge_tests()
	await _death_and_freeing_tests()
	await _boss_tests()
	await _player_death_tests()
	_watching = false
	_record(_violations.is_empty(),
		"I1) every frame: locked exactly while a target is held, the held target alive and within %.0f m, the indicator shown exactly while locked (%d: %s)" % [
			_targeting.data.lose_range, _violations.size(), _violations.slice(0, 3)])
	print("[SUMMARY] passed=%d failed=%d" % [_pass, _fail])
	get_tree().quit()


# --- configuration --------------------------------------------------------------------------------

func _config_tests() -> void:
	var data: PlayerTargetingData = _targeting.data
	_record(data.resource_path == "res://resources/characters/player_targeting.tres" and data.acquisition_range == 15.0
			and data.lose_range == 18.0 and data.distance_weight == 3.0 and data.rotation_speed == 12.0
			and data.target_body_mask == 4 and data.line_of_sight_mask == 1,
		"CF1) player_targeting.tres: acquire within 15 m, let go past 18 m, 3 degrees a metre, turn at 12 rad/s, enemy bodies, the world blocking the view")
	var keys: Array[String] = [InteractionPrompt.key_for(&"target_lock"), InteractionPrompt.key_for(&"target_switch_left"),
		InteractionPrompt.key_for(&"target_switch_right")]
	_record(keys == ["Tab", "Z", "X"] and InputMap.has_action(&"attack_light") and InputMap.has_action(&"dodge")
			and InteractionPrompt.key_for(&"shadow_attack_command") == "MMB",
		"CF2) target_lock on %s, switch left / right on %s / %s — beside the attacks, the dodge and the shadow's MMB" % keys)
	_record(_indicator.get_hint_text() == "[Tab] Sblocca bersaglio\n[Z] [X] Cambia bersaglio",
		"CF3) the lock's hint, from the real bindings: %s" % _indicator.get_hint_text().replace("\n", " | "))


# --- nothing to lock onto -------------------------------------------------------------------------

func _no_target_tests() -> void:
	await _fresh()
	var searches: int = _targeting.get_search_count()
	await _lock()
	await _frames(2)
	_record(not _targeting.is_locked() and _changes.is_empty() and not _indicator.is_showing()
			and _targeting.get_search_count() == searches + 1,
		"NT1) no enemy within reach: the lock button searches once, finds nothing, stays unlocked, shows nothing")

	await _fresh()
	_place(_a, _at(0.0, 16.0))
	await _lock()
	await _frames(2)
	_record(not _targeting.is_locked(), "NT2) an enemy at 16 m, past the 15 m reach, is not acquired")

	await _fresh()
	_prop.global_position = _at(0.0, 3.0)
	await _frames(2)
	await _lock()
	await _frames(2)
	_prop.global_position = PROP_PARKED
	_record(not _targeting.is_locked(),
		"NT3) a body on the enemy layer that is not a combatant, 3 m ahead: not a target — the type decides, not the layer")


# --- the first lock ------------------------------------------------------------------------------

func _initial_lock_tests() -> void:
	await _fresh()
	_place(_a, _at(90.0, 5.0))
	var yaw_before: float = _player.visual_root.rotation.y
	await _lock()
	var locked: bool = _targeting.get_target() == _a and _changes == ["EnemyA"]
	await get_tree().physics_frame
	await get_tree().physics_frame
	var first_step: float = absf(wrapf(_player.visual_root.rotation.y - yaw_before, -PI, PI))
	await get_tree().process_frame
	# Within a frame's settling: the enemy was just put down and is still coming
	# to rest on the floor, and the ring follows it a frame behind.
	var on_anchor: bool = _indicator.is_showing() and _indicator.get_target() == _a \
		and _indicator.global_position.distance_to(_a.get_target_point()) < 0.1
	await _frames(40)
	var facing_error: float = _facing_error(_a)
	_record(locked and on_anchor,
		"IL1) one enemy in reach: the lock holds it, says so once, and the ring sits on its anchor (%.1f m up)" % (
			_a.get_target_point().y - _a.global_position.y))
	_record(first_step <= 2.0 * _targeting.data.rotation_speed * DT + 0.001 and first_step > 0.0 and facing_error < deg_to_rad(3.0),
		"IL2) the player turns to face it at 12 rad/s — %.1f degrees in the first frames, not a snap — and ends on it (%.1f degrees off)" % [
			rad_to_deg(first_step), rad_to_deg(facing_error)])


# --- which one ---------------------------------------------------------------------------------------

func _scoring_tests() -> void:
	await _fresh()
	_place(_a, _at(100.0, 3.0))
	_place(_b, _at(5.0, 7.0))
	_place(_c, _at(180.0, 2.0))
	await _lock()
	_record(_targeting.get_target() == _b,
		"SC1) near but off to the side (3 m, 100 deg), right behind (2 m), or further but in front (7 m, 5 deg): the lock takes the one in front")

	await _fresh()
	_place(_c, _at(180.0, 3.0))
	await _lock()
	_record(_targeting.get_target() == _c, "SC2) with only one behind the player, it takes that one")

	await _fresh()
	_player.camera_rig.rotation.y = deg_to_rad(-90.0)
	_place(_a, _at(90.0, 6.0))
	_place(_b, _at(0.0, 4.0))
	await _lock()
	_record(_targeting.get_target() == _a,
		"SC3) the camera turned right: what is in front of the camera wins, not what is in front of the player")


func _line_of_sight_tests() -> void:
	# A wall 8 m wide, its near face 3.5 m ahead of the player.
	var spot: Vector3 = Vector3(30, 0.1, -8)
	await _fresh(spot)
	_place(_b, Vector3(30, 0.1, -14))
	_place(_a, Vector3(36, 0.1, -11))
	await _lock()
	var took_visible: bool = _targeting.get_target() == _a
	await _fresh(spot)
	_place(_b, Vector3(30, 0.1, -14))
	await _lock()
	_record(took_visible and not _targeting.is_locked(),
		"LS1) behind a wall, 6 m straight ahead, an enemy is not taken: the one in view off to the side is; alone, nothing is")


# --- letting go ---------------------------------------------------------------------------------------

func _unlock_tests() -> void:
	await _fresh()
	_place(_a, _at(0.0, 5.0))
	await _lock()
	await _frames(3)
	_changes.clear()
	await _lock()
	await get_tree().process_frame
	var released: bool = not _targeting.is_locked() and _changes == ["-"] and not _indicator.is_showing() \
		and not _targeting.is_physics_processing() and not _indicator.is_processing()
	Input.action_press("move_right")
	await _frames(40)
	Input.action_release("move_right")
	var facing: Vector3 = _flat(-_player.visual_root.global_basis.z).normalized()
	_record(released and facing.dot(Vector3.RIGHT) > 0.95,
		"MU1) the lock button again: unlocked, the ring and its hint gone, nothing left ticking — and the player faces where it walks again")


func _range_tests() -> void:
	await _fresh()
	_place(_a, _at(0.0, 5.0))
	await _lock()
	var searches: int = _targeting.get_search_count()
	_player.global_position = _a.global_position + Vector3(0, 0, 17.0)
	await _frames(5)
	var held_at_17: bool = _targeting.get_target() == _a
	await _frames(60)
	var no_search: bool = _targeting.get_search_count() == searches
	_player.global_position = _a.global_position + Vector3(0, 0, 19.0)
	await _frames(2)
	_record(held_at_17 and not _targeting.is_locked() and not _indicator.is_showing(),
		"OR1) a held target at 17 m stays held (acquired within 15, let go past 18); at 19 m the lock drops and the ring goes")
	_record(no_search, "OR2) holding a lock for a second ran no search: only the held target is checked")


# --- switching -----------------------------------------------------------------------------------------

func _switch_tests() -> void:
	await _fresh()
	_place(_a, _at(-35.0, 6.0))
	_place(_b, _at(0.0, 6.0))
	_place(_c, _at(35.0, 6.0))
	await _lock()
	var steps: Array[String] = [_name(_targeting.get_target())]
	for action in [&"target_switch_right", &"target_switch_right", &"target_switch_left", &"target_switch_left", &"target_switch_left"]:
		_press(action)
		steps.append(_name(_targeting.get_target()))
	_record(steps == ["EnemyB", "EnemyC", "EnemyC", "EnemyB", "EnemyA", "EnemyA"],
		"SW1) left / centre / right: locks the centre; right, right, left, left, left goes %s — as the camera sees them, no wrapping" % [steps])

	# To the right of the held one: a far enemy, a non-combatant on the enemy layer.
	await _fresh()
	_place(_b, _at(0.0, 6.0))
	_place(_c, _at(25.0, 16.5))
	_prop.global_position = _at(30.0, 5.0)
	await _frames(2)
	await _lock()
	var switched: bool = _targeting.switch_target(PlayerTargeting.RIGHT)
	_prop.global_position = PROP_PARKED
	_record(_targeting.get_target() == _b and not switched,
		"SW2) to the right only an enemy at 16.5 m (past the reach) and a non-combatant body: the switch has nowhere to go and stays")


# --- attacking while locked ----------------------------------------------------------------------------------

func _attack_tests() -> void:
	# A target off to the side: unlocked, the swing goes where the camera looks and misses.
	await _fresh()
	_place(_a, _at(70.0, 1.5))
	var hp: float = _a.health_component.current_health
	await _swing(_combat.data.light_combo, 0)
	var missed: bool = _a.health_component.current_health == hp
	await _lock()
	var landed: Array[float] = []
	var staggers: Array[bool] = []
	var on_hit: Callable = func(target: Node, info: DamageInfo) -> void:
		if target == _a:
			landed.append(info.amount)
			staggers.append(_a.is_staggered())
	_player.attack_hitbox.hit_landed.connect(on_hit)
	var indicator_off: Array[float] = [0.0]
	var facings: Array[float] = []
	var on_started: Callable = func(_attack: AttackData) -> void:
		facings.append(rad_to_deg(_facing_error(_a)))
	_combat.attack_started.connect(on_started)
	_player.camera_rig.attack_light_pressed.emit()
	for i in 2:
		await _frames_until_state(PlayerCombat.State.RECOVERY)
		await _frames(3)
		_player.camera_rig.attack_light_pressed.emit()
		await _frames_until_state(PlayerCombat.State.WINDUP)
	while _combat.get_state() != PlayerCombat.State.IDLE or _a.is_knocked_back():
		await get_tree().process_frame
		indicator_off[0] = maxf(indicator_off[0], _indicator.global_position.distance_to(_a.get_target_point()))
	_combat.attack_started.disconnect(on_started)
	var worst: float = facings.max() if not facings.is_empty() else -1.0
	_record(missed and landed == [20.0, 25.0, 35.0] and staggers == [false, false, true] and _targeting.get_target() == _a,
		"AT1) Light 1 unlocked misses an enemy 70 deg to the side; locked on, Light 1 -> 2 -> 3 turn to it and land %s, the finisher staggers, the lock holds" % [landed])
	_record(facings.size() == 3 and worst >= 0.0 and worst < 1.0 and indicator_off[0] < 0.1,
		"AT2) each attack of the chain starts facing the target (%.1f deg off at most); the ring follows it as it is knocked back (%.2fm behind at most, a frame's push)" % [
			worst, indicator_off[0]])

	# The critical, and the heavy, on the same held target.
	_no_crits.critical_chance = 1.0
	landed.clear()
	await _fresh(Vector3(0, 0.1, 0), false)
	_place(_a, _at(-60.0, 1.5))
	await _frames(3)
	await _lock()
	await _swing(_combat.data.light_combo, 0)
	_no_crits.critical_chance = 0.0
	var crit_landed: Array[float] = landed.duplicate()
	landed.clear()
	_place(_a, _at(-60.0, 1.5), false)
	await _frames(3)
	var start: Vector3 = _a.global_position
	await _swing(_combat.data.heavy_combo, 0)
	await _until(func() -> bool: return not _a.is_knocked_back())
	var pushed: Vector3 = _flat(_a.global_position - start)
	var away: Vector3 = _flat(start - _player.global_position).normalized()
	_record(crit_landed == [30.0] and landed == [40.0] and staggers[-1] and pushed.normalized().dot(away) > 0.98
			and _targeting.get_target() == _a,
		"AT3) locked on a target 60 deg the other way: a critical Light 1 lands for 30, the heavy for 40, staggers it and throws it %.2fm away from the player; the lock holds" % pushed.length())

	# Out of the hitbox's reach, locked or not: nothing.
	_place(_a, _at(0.0, 4.0), false)
	await _frames(3)
	hp = _a.health_component.current_health
	await _swing(_combat.data.light_combo, 0)
	_record(_targeting.get_target() == _a and _a.health_component.current_health == hp,
		"AT4) locked on an enemy 4 m away, a Light 1 faces it but does not reach it: no damage — the lock turns, it never hits for the hitbox")
	_player.attack_hitbox.hit_landed.disconnect(on_hit)

	# Switching during a swing: the swing keeps its aim; the next attack takes the new one.
	await _fresh()
	_place(_a, _at(-35.0, 6.0))
	_place(_b, _at(0.0, 6.0))
	await _lock()
	_press(&"target_switch_left")
	await _frames(40)
	_combat._start_attack(_combat.data.heavy_combo, 0)
	await _frames_until_state(PlayerCombat.State.ACTIVE)
	var yaw_in_swing: float = _player.visual_root.rotation.y
	_press(&"target_switch_right")
	var switched_to: RoomCombatant = _targeting.get_target()
	await _frames(4)
	var kept_aim: bool = is_equal_approx(_player.visual_root.rotation.y, yaw_in_swing)
	await _frames_until_state(PlayerCombat.State.IDLE)
	_combat._start_attack(_combat.data.light_combo, 0)
	var faces_new: float = _facing_error(_b)
	await _frames_until_state(PlayerCombat.State.IDLE)
	_record(switched_to == _b and kept_aim and faces_new < deg_to_rad(1.0),
		"AT5) a switch mid-swing moves the lock at once, but the swing keeps its aim; the next attack starts facing the new target")

	# Locking on in the middle of an attack: the attack runs on untouched.
	await _fresh()
	_place(_b, _at(0.0, 6.0))
	_combat._start_attack(_combat.data.light_combo, 0)
	await _frames(2)
	await _lock()
	var mid: bool = _targeting.get_target() == _b and _combat.get_state() == PlayerCombat.State.WINDUP \
		and _combat.get_current_attack() == _combat.data.light_combo[0]
	await _frames_until_state(PlayerCombat.State.IDLE)
	_record(mid, "AT6) locking on during an attack's windup takes the target and leaves the attack exactly where it was")


# --- dodging while locked --------------------------------------------------------------------------------------

func _dodge_tests() -> void:
	var cases: Array = [["move_left", Vector3.LEFT], ["move_forward", Vector3.FORWARD], ["", Vector3.BACK]]
	var results: Array[String] = []
	for case in cases:
		await _fresh()
		_place(_b, _at(0.0, 8.0))
		await _lock()
		await _frames(3)
		if case[0] != "":
			Input.action_press(case[0])
		await get_tree().physics_frame
		var stamina: float = _combat.get_stamina()
		_press(&"dodge")
		var direction: Vector3 = _player._dodge_direction
		var paid: float = stamina - _combat.get_stamina()
		var reached_iframes: bool = await _until(func() -> bool:
			return _combat.get_dodge_phase() == PlayerCombat.DodgePhase.INVULNERABLE and _player.hurtbox.is_invulnerable)
		await _until(func() -> bool: return not _combat.is_dodging())
		if case[0] != "":
			Input.action_release(case[0])
		if direction.distance_to(case[1]) < 0.01 and paid == _combat.data.dodge_stamina_cost and reached_iframes \
				and _targeting.get_target() == _b:
			results.append(case[0] if case[0] != "" else "none")
	_record(results == ["move_left", "move_forward", "none"],
		"DG1) locked on: a dodge goes where the keys point — left is left, forward is forward, never drawn to the target — and with no key, straight back from it; each costs 25 stamina, has its i-frames, and keeps the lock (%s)" % [results])
	await _until(func() -> bool: return _combat.get_stamina() == _combat.get_max_stamina(), 300)
	_record(_combat.get_stamina() == _combat.get_max_stamina(),
		"ST1) and stamina regenerates as ever while locked")


# --- the target dies, or is freed ---------------------------------------------------------------------------

func _death_and_freeing_tests() -> void:
	await _fresh()
	_place(_d, _at(0.0, 3.0))
	await _lock()
	_changes.clear()
	_d.hurtbox.receive_hit(DamageInfo.new(1000.0, _player))
	var dropped_at_once: bool = not _targeting.is_locked() and _changes == ["-"] and not _indicator.is_showing()
	await _frames(5)
	_record(_d.has_died() and dropped_at_once and _targeting.get_target() == null,
		"TD1) the held target dies: the lock drops in the same call — no frame late — and the ring goes")

	await _fresh()
	_place(_e, _at(0.0, 3.0))
	await _lock()
	var had: bool = _targeting.get_target() == _e
	_changes.clear()
	_e.queue_free()
	await get_tree().process_frame
	await _frames(2)
	_record(had and _changes == ["-"] and is_same(_targeting.get_target(), null) and not _indicator.is_showing()
			and not _targeting.is_physics_processing(),
		"TD2) the held target is freed outright: the lock lets go as it leaves — signalled, no reference left behind, nothing ticking, no error")


# --- the boss -----------------------------------------------------------------------------------------------

func _boss_tests() -> void:
	await _fresh()
	_boss.global_position = _at(0.0, 5.0)
	await _frames(3)
	await _lock()
	await get_tree().process_frame
	var anchor_height: float = _boss.get_target_point().y - _boss.global_position.y
	var on_boss: bool = _targeting.get_target() == _boss and _indicator.get_target() == _boss \
		and _indicator.global_position.distance_to(_boss.get_target_point()) < 0.01
	_boss.global_position = _at(0.0, 1.6)
	await _frames(3)
	var health: HealthComponent = _boss.health_component
	var hp: float = health.current_health
	await _swing(_combat.data.light_combo, 0)
	await _swing(_combat.data.heavy_combo, 0)
	var dealt: float = hp - health.current_health
	health.current_health = 40.0
	await _swing(_combat.data.heavy_combo, 0)
	await _frames(3)
	_record(on_boss and is_equal_approx(anchor_height, 1.5) and dealt == 60.0,
		"BO1) the boss locks like any enemy, the ring on its own anchor (%.1f m up, above an enemy's 1.1); Light 1 and the heavy land for %.0f" % [anchor_height, dealt])
	_record(_boss.has_died() and not _targeting.is_locked() and not _indicator.is_showing(),
		"BO2) and when the boss dies the lock lets go of it")


# --- the player dies -----------------------------------------------------------------------------------------

func _player_death_tests() -> void:
	await _fresh()
	_place(_a, _at(0.0, 5.0))
	await _lock()
	var had: bool = _targeting.is_locked()
	_player.hurtbox.set_invulnerable(false)
	_player.health_component.take_damage(DamageInfo.new(10000.0, self))
	await get_tree().process_frame
	var released: bool = had and not _targeting.is_locked() and not _indicator.is_showing() \
		and not _targeting.is_physics_processing()
	await _lock()
	_record(released and not _targeting.is_locked(),
		"PD1) the player dies with a lock on: unlocked, the ring gone, nothing left turning the body — and a dead player locks onto nothing")


# --- invariants -------------------------------------------------------------------------------------------------

func _check_invariants() -> void:
	var target: RoomCombatant = _targeting.get_target()
	if _targeting.is_locked() != (target != null):
		_violations.append("locked %s with target %s" % [_targeting.is_locked(), target])
	if target != null and not _targeting.is_valid_target(target, _targeting.data.lose_range):
		_violations.append("holding an invalid target")
	if _indicator.is_showing() != (target != null):
		_violations.append("indicator %s while locked %s" % [_indicator.is_showing(), target != null])


func _on_target_changed(target: RoomCombatant) -> void:
	_changes.append(_name(target))


# --- helpers ----------------------------------------------------------------------------------------------------

## A free, unlocked player at `at`, camera and body facing -Z, full stamina, and
## every enemy and the boss parked out of reach.
func _fresh(at: Vector3 = Vector3(0, 0.1, 0), park: bool = true) -> void:
	if _targeting.is_locked():
		_targeting.unlock()
	_combat.reset()
	_combat.restore_stamina(_combat.get_max_stamina())
	for action in ["move_forward", "move_backward", "move_left", "move_right"]:
		Input.action_release(action)
	_player.global_position = at
	_player.velocity = Vector3.ZERO
	_player.visual_root.rotation = Vector3.ZERO
	_player.camera_rig.rotation.y = 0.0
	if park:
		# Untyped: one of them is freed on purpose, and a typed array refuses it.
		var enemies: Array = [_a, _b, _c, _d, _e]
		for i in enemies.size():
			if is_instance_valid(enemies[i]) and not (enemies[i] as BasicMeleeEnemy).has_died():
				_place(enemies[i] as BasicMeleeEnemy, PARKED[i], false)
		if not _boss.has_died():
			_boss.global_position = BOSS_PARKED
	await _frames(3)
	_changes.clear()


## Parks `enemy` at `at`, whole and still.
func _place(enemy: BasicMeleeEnemy, at: Vector3, face: bool = true) -> void:
	enemy.set_combat_enabled(false)
	enemy.global_position = at
	enemy.velocity = Vector3.ZERO
	enemy.health_component.current_health = enemy.health_component.max_health
	if face:
		var to: Vector3 = _flat(_player.global_position - at)
		if to.length_squared() > 0.0001:
			enemy.visual_root.rotation.y = atan2(-to.x, -to.z)


## A point `distance` m from the player, `bearing` degrees off the camera's
## default view (-Z): positive to the right.
func _at(bearing: float, distance: float) -> Vector3:
	var radians: float = deg_to_rad(bearing)
	return _player.global_position + Vector3(sin(radians) * distance, 0.0, -cos(radians) * distance)


## The lock button, once the physics space has caught up with whatever was just
## put in place: a body moved by hand is found by a search a tick later.
func _lock() -> void:
	await _frames(2)
	_press(&"target_lock")


func _press(action: StringName) -> void:
	var event: InputEventAction = InputEventAction.new()
	event.action = action
	event.pressed = true
	_player._unhandled_input(event)


func _swing(chain: Array[AttackData], index: int) -> void:
	_combat.reset()
	_combat._start_attack(chain, index)
	await _frames_until_state(PlayerCombat.State.IDLE)


func _facing_error(target: Node3D) -> float:
	var facing: Vector3 = _flat(-_player.visual_root.global_basis.z).normalized()
	var to: Vector3 = _flat(target.global_position - _player.global_position).normalized()
	return absf(facing.signed_angle_to(to, Vector3.UP))


func _name(target: RoomCombatant) -> String:
	return String(target.name) if target != null else "-"


func _until(condition: Callable, budget: int = 120) -> bool:
	var n: int = 0
	while not condition.call():
		if n >= budget:
			return false
		await get_tree().physics_frame
		n += 1
	return true


func _frames_until_state(state: PlayerCombat.State, budget: int = 180) -> int:
	var n: int = 0
	while _combat.get_state() != state:
		if n >= budget:
			return -1
		await get_tree().physics_frame
		n += 1
	return n


func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _record(passed: bool, description: String) -> void:
	if passed:
		_pass += 1
		print("[PASS] " + description)
	else:
		_fail += 1
		print("[FAIL] " + description)


func _reset_session() -> void:
	var state: Node = get_tree().root.get_node_or_null("PlayerRuntimeState")
	if state != null:
		state.reset_runtime_state()
