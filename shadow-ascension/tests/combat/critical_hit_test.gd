extends Node3D

## M11.7 — critical hits and the damage model, on a real player, enemies and the
## boss.
##
##   godot --headless --path . res://tests/combat/critical_hit_test.tscn
##
## The player's hits are its real attacks landing through its real hitbox. The
## critical chance is set per test on the player's own copy of its combat data
## — 0.0 (never) and 1.0 (always) are exact, with no draw — so every number
## below is deterministic; the one test of a chance in between seeds the
## hitbox's generator. The shipped data is only read.

const COMBAT_DATA_PATH: String = "res://resources/characters/player_combat.tres"
const IN_FRONT: Vector3 = Vector3(0, 0.1, -1.5)
const PARKED: Array[Vector3] = [Vector3(-20, 0.1, 20), Vector3(-16, 0.1, 20), Vector3(-12, 0.1, 20)]
const ENEMY_HITBOX_LAYER: int = 32
const ENEMY_HITBOX_MASK: int = 320

@onready var _player: Player = $Player
@onready var _a: BasicEnemy = $EnemyA
@onready var _b: BasicEnemy = $EnemyB
@onready var _c: BasicEnemy = $EnemyC
@onready var _boss: DungeonBoss = $Boss

var _combat: PlayerCombat = null
var _shipped: PlayerCombatData = null
## The player's own copy of its combat data, whose critical chance each test sets.
var _tuned: PlayerCombatData = null
var _light: Array[AttackData] = []
var _heavy: AttackData = null
## Every hit the player's hitbox landed, and how its target stood right after.
var _hits: Array[Dictionary] = []
var _pass: int = 0
var _fail: int = 0


func _ready() -> void:
	_reset_session()
	_combat = _player.combat
	_shipped = _combat.data
	_tuned = _shipped.duplicate() as PlayerCombatData
	_combat.data = _tuned
	_light = _tuned.light_combo
	_heavy = _tuned.heavy_combo[0]
	_player.attack_hitbox.hit_landed.connect(_on_player_hit)
	_player.hurtbox.set_invulnerable(true)
	_run()


func _run() -> void:
	await _wait(0.3)
	_config_tests()
	_model_tests()
	await _never_and_always_tests()
	await _per_attack_tests()
	await _combo_tests()
	await _multi_target_tests()
	await _reaction_tests()
	await _killing_blow_tests()
	await _boss_tests()
	await _receiver_tests()
	_record(_combat.get_stamina() == _combat.get_max_stamina()
			and not _player.attack_hitbox.hit_landed.is_connected(_combat._log_hit) and not _combat.debug_log_enabled,
		"SM1) none of it touched stamina (%.0f); the damage debug log is off, and not even listening" % _combat.get_stamina())
	_record(_shipped.critical_chance == 0.1 and _shipped.critical_damage_multiplier == 1.5,
		"I1) the shipped combat data was never written")
	print("[SUMMARY] passed=%d failed=%d" % [_pass, _fail])
	get_tree().quit()


# --- configuration --------------------------------------------------------------------------------

func _config_tests() -> void:
	var multipliers: Array[float] = []
	for attack in _light:
		multipliers.append(attack.damage_multiplier)
	multipliers.append(_heavy.damage_multiplier)
	_record(_shipped.resource_path == COMBAT_DATA_PATH and _shipped.base_damage == 20.0
			and _shipped.critical_chance == 0.1 and _shipped.critical_damage_multiplier == 1.5
			and multipliers == [1.0, 1.25, 1.75, 2.0],
		"CF1) %s: base damage 20, critical chance 0.1 (10%%), critical x1.5; attack multipliers L1/L2/L3/heavy %s" % [
			COMBAT_DATA_PATH.get_file(), multipliers])
	var bare: PlayerCombat = PlayerCombat.new()
	var odd: PlayerCombatData = _shipped.duplicate() as PlayerCombatData
	bare.data = odd
	add_child(bare)
	odd.critical_chance = 1.7
	var high: float = bare.get_critical_chance()
	odd.critical_chance = -0.2
	var low: float = bare.get_critical_chance()
	odd.critical_damage_multiplier = -1.0
	var multiplier: float = bare.get_critical_damage_multiplier()
	bare.queue_free()
	_record(high == 1.0 and low == 0.0 and multiplier == 0.0,
		"CF2) the chance is clamped into 0..1 (1.7 -> %.1f, -0.2 -> %.1f) and a negative multiplier counts as 0" % [high, low])


# --- the model on its own -------------------------------------------------------------------------

func _model_tests() -> void:
	var raws: Array[float] = []
	var crits: Array[float] = []
	for multiplier in [1.0, 1.25, 1.75, 2.0]:
		var raw: float = DamageModel.attack_damage(20.0, multiplier)
		raws.append(DamageModel.final_damage(raw, false, 1.5))
		crits.append(DamageModel.final_damage(raw, true, 1.5))
	_record(raws == [20.0, 25.0, 35.0, 40.0] and crits == [30.0, 38.0, 53.0, 60.0],
		"DM1) 20 x 1.0 / 1.25 / 1.75 / 2.0 = %s; critical x1.5, rounded once = %s" % [raws, crits])
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 7
	var never: int = 0
	var always: int = 0
	var half: int = 0
	for i in 10000:
		never += 1 if DamageModel.roll_critical(0.0, rng) or DamageModel.roll_critical(-0.5, rng) else 0
		always += 1 if DamageModel.roll_critical(1.0, rng) and DamageModel.roll_critical(2.0, rng) else 0
		half += 1 if DamageModel.roll_critical(0.5, rng) else 0
	_record(never == 0 and always == 10000 and absi(half - 5000) < 300,
		"DM2) a chance of 0 (or below) never crits, 1 (or above) always does, 0.5 does %d times in 10000" % half)
	_record(DamageModel.final_damage(35.0, true, 0.0) == 0.0 and DamageModel.final_damage(35.0, true, -2.0) == 0.0
			and DamageModel.final_damage(35.0, false, 99.0) == 35.0,
		"DM3) a normal hit is its raw damage whatever the multiplier; a critical never goes negative")


# --- 0% and 100% over many hits -------------------------------------------------------------------

func _never_and_always_tests() -> void:
	for chance in [0.0, 1.0]:
		_tuned.critical_chance = chance
		var first: int = _hits.size()
		for swing in 10:
			await _line_up()
			await _swing(_light, 0)
		var critical: int = 0
		var amounts: Dictionary = {}
		for i in range(first, _hits.size()):
			critical += 1 if _hits[i]["critical"] else 0
			amounts[_hits[i]["amount"]] = true
		var expected: float = 30.0 if chance == 1.0 else 20.0
		_record(_hits.size() - first == 30 and critical == (30 if chance == 1.0 else 0) and amounts.keys() == [expected],
			"%s) critical chance %.0f%%: %d hits of Light 1 on three enemies, %d critical, every one %.0f damage" % [
				"CC100" if chance == 1.0 else "CC0", chance * 100.0, _hits.size() - first, critical, expected])


# --- each attack, normal and critical --------------------------------------------------------------

func _per_attack_tests() -> void:
	var cases: Array = [["L1", _light, 0, 20.0, 30.0], ["L2", _light, 1, 25.0, 38.0],
		["L3", _light, 2, 35.0, 53.0], ["H", _tuned.heavy_combo, 0, 40.0, 60.0]]
	for case in cases:
		var attack: AttackData = (case[1] as Array[AttackData])[case[2]]
		var got: Array[String] = []
		for chance in [0.0, 1.0]:
			_tuned.critical_chance = chance
			await _fresh(_a, IN_FRONT)
			var hp: float = _a.health_component.current_health
			var first: int = _hits.size()
			await _swing(case[1], case[2])
			var hit: Dictionary = _hits[first] if _hits.size() > first else {}
			var taken: float = hp - _a.health_component.current_health
			var want: float = case[4] if chance == 1.0 else case[3]
			if hit.get("amount", -1.0) == want and taken == want and hit.get("critical", false) == (chance == 1.0) \
					and is_equal_approx(_bar(_a).get_ratio(), _a.health_component.current_health / _a.health_component.max_health):
				got.append("%s %.0f" % ["critical" if chance == 1.0 else "normal", taken])
		_record(got.size() == 2 and _combat.calculate_damage(attack) == case[3],
			"%s1) %s: raw %.0f (20 x %.2f) -> %s — the multiplier once, the critical once; the health bar follows" % [
				case[0], attack.id, case[3], attack.damage_multiplier, got])
	_record(_heavy.damage_multiplier * _tuned.base_damage * _tuned.critical_damage_multiplier == 60.0,
		"ND1) a critical heavy is 20 x 2.0 x 1.5 = 60: not 90 (x1.5 twice) nor 120 (x2.0 twice)")


# --- a combo with its own roll per hit --------------------------------------------------------------

func _combo_tests() -> void:
	await _fresh(_a, IN_FRONT)
	var first: int = _hits.size()
	var started: Array[StringName] = []
	var on_started: Callable = func(attack: AttackData) -> void: started.append(attack.id)
	_combat.attack_started.connect(on_started)
	# The chance is read when each hit window opens: set it before each one.
	_tuned.critical_chance = 0.0
	_player.camera_rig.attack_light_pressed.emit()
	for chance in [1.0, 0.0]:
		await _frames_until_state(PlayerCombat.State.RECOVERY)
		_tuned.critical_chance = chance
		await _frames(3)
		_player.camera_rig.attack_light_pressed.emit()
		await _frames_until_state(PlayerCombat.State.WINDUP)
	await _frames_until_state(PlayerCombat.State.IDLE)
	_combat.attack_started.disconnect(on_started)
	var sequence: Array[String] = []
	for i in range(first, _hits.size()):
		sequence.append("%.0f%s" % [_hits[i]["amount"], "!" if _hits[i]["critical"] else ""])
	_record(started == [_light[0].id, _light[1].id, _light[2].id] and sequence == ["20", "38!", "35"],
		"MX1) Light 1 normal -> Light 2 critical -> Light 3 normal: %s — each hit its own, the chain intact" % [sequence])
	_tuned.critical_chance = 0.0
	await _fresh(_a, IN_FRONT)
	first = _hits.size()
	await _swing(_light, 0)
	_record(_hits.size() == first + 1 and not _hits[first]["critical"] and _hits[first]["amount"] == 20.0,
		"MX2) and nothing of the critical outlives its hit: the next Light 1 is a plain 20")


# --- one swing, several targets ---------------------------------------------------------------------

func _multi_target_tests() -> void:
	# A seed whose first two draws fall either side of 0.5: one target critical,
	# the other not, from one swing.
	var probe: RandomNumberGenerator = RandomNumberGenerator.new()
	var seed_found: int = -1
	for candidate in range(1, 1000):
		probe.seed = candidate
		if (probe.randf() < 0.5) != (probe.randf() < 0.5):
			seed_found = candidate
			break
	_tuned.critical_chance = 0.5
	await _fresh(_b, Vector3(0.55, 0.1, -1.5), false, true)
	await _fresh(_a, Vector3(-0.55, 0.1, -1.5), true, true)
	_player.attack_hitbox._rng.seed = seed_found
	var first: int = _hits.size()
	_player.camera_rig.rotation.y = 0.0
	await _swing(_tuned.heavy_combo, 0, false)
	var per_target: Dictionary = {}
	var amounts: Array[float] = []
	var staggered: int = 0
	for i in range(first, _hits.size()):
		per_target[_hits[i]["target"]] = true
		amounts.append(_hits[i]["amount"])
		staggered += 1 if _hits[i]["staggered"] and is_equal_approx(_hits[i]["push"], _heavy.knockback_force) else 0
	amounts.sort()
	_record(seed_found > 0 and per_target.size() == 2 and amounts == [40.0, 60.0] and staggered == 2,
		"MT1) one heavy, two enemies, a roll each: one critical, one not %s — and both staggered and pushed alike (%d)" % [amounts, staggered])
	_tuned.critical_chance = 0.0
	await _fresh(_b, PARKED[1], false)


# --- a critical changes damage and nothing else --------------------------------------------------------

func _reaction_tests() -> void:
	var outcome: Array[Dictionary] = []
	for chance in [0.0, 1.0]:
		_tuned.critical_chance = chance
		await _fresh(_a, IN_FRONT)
		var start: Vector3 = _a.global_position
		var first: int = _hits.size()
		await _swing(_tuned.heavy_combo, 0)
		await _until(func() -> bool: return not _a.is_knocked_back())
		var hit: Dictionary = _hits[first] if _hits.size() > first else {}
		outcome.append({"critical": hit.get("critical", false), "staggered": hit.get("staggered", false),
			"push": hit.get("push", 0.0), "moved": _flat(_a.global_position - start).length()})
	_record(not outcome[0]["critical"] and outcome[1]["critical"] and outcome[0]["staggered"] and outcome[1]["staggered"]
			and is_equal_approx(outcome[0]["push"], outcome[1]["push"]) and absf(outcome[0]["moved"] - outcome[1]["moved"]) < 0.02,
		"RX1) a normal heavy and a critical one stagger alike and push alike (%.1f m/s, %.2fm / %.2fm)" % [
			outcome[1]["push"], outcome[0]["moved"], outcome[1]["moved"]])

	_tuned.critical_chance = 1.0
	await _fresh(_a, IN_FRONT)
	var first_light: int = _hits.size()
	await _swing(_light, 0)
	var light_hit: Dictionary = _hits[first_light] if _hits.size() > first_light else {}
	_record(light_hit.get("critical", false) and light_hit.get("amount", 0.0) == 30.0 and not light_hit.get("staggered", true)
			and light_hit.get("flinched", false),
		"RX2) a critical Light 1 does 30 but still only flinches: its stagger power (10) is not raised by the critical")
	_tuned.critical_chance = 0.0


# --- the killing blow ------------------------------------------------------------------------------------

func _killing_blow_tests() -> void:
	_tuned.critical_chance = 1.0
	await _fresh(_c, IN_FRONT)
	_c.health_component.current_health = 50.0
	var damaged: Array[int] = [0]
	var deaths: Array[int] = [0]
	var on_damaged: Callable = func(_hit: DamageInfo) -> void: damaged[0] += 1
	var on_died: Callable = func(_enemy: RoomCombatant) -> void: deaths[0] += 1
	_c.health_component.damaged.connect(on_damaged)
	_c.enemy_died.connect(on_died)
	var xp: int = _player.progression.get_total_xp()
	var first: int = _hits.size()
	await _swing(_tuned.heavy_combo, 0)
	var at: Vector3 = _c.global_position
	await _frames(30)
	_c.health_component.damaged.disconnect(on_damaged)
	_c.enemy_died.disconnect(on_died)
	var paid: int = _player.progression.get_total_xp() - xp
	_record(_hits.size() == first + 1 and _hits[first]["critical"] and _c.has_died() and deaths[0] == 1 and damaged[0] == 0
			and not _c.is_staggered() and not _c.is_knocked_back() and _flat(_c.global_position - at).length() < 0.01
			and paid == _c.get_xp_reward(),
		"KB1) a critical heavy (60) on 50 HP — a blow the normal 40 would not have landed: one death, no reaction, no push, %d XP once (hits %d, deaths %d, damaged %d)" % [
			paid, _hits.size() - first, deaths[0], damaged[0]])
	_tuned.critical_chance = 0.0


# --- the boss -----------------------------------------------------------------------------------------------

func _boss_tests() -> void:
	var spot: Vector3 = Vector3(12, 0.1, -4)
	_boss.global_position = spot
	_player.global_position = spot + Vector3(0, 0, 1.6)
	await _frames(4)
	var health: HealthComponent = _boss.health_component
	var taken: Array[float] = []
	for step in [[_light, 0, 0.0], [_light, 0, 1.0], [_tuned.heavy_combo, 0, 0.0], [_tuned.heavy_combo, 0, 1.0]]:
		_tuned.critical_chance = step[2]
		var hp: float = health.current_health
		_aim_at(_boss)
		_combat.reset()
		_combat._start_attack(step[0], step[1])
		await _frames_until_state(PlayerCombat.State.IDLE)
		taken.append(hp - health.current_health)
	_record(taken == [20.0, 30.0, 40.0, 60.0] and _flat(_boss.global_position - spot).length() < 0.01
			and _boss.get_state() == DungeonBoss.State.INACTIVE,
		"BO1) the boss takes Light 1 normal / critical and the heavy normal / critical: %s — not moved, not staggered" % [taken])
	_tuned.critical_chance = 0.0
	_boss.global_position = PARKED[0] + Vector3(40, 0, 0)
	_player.global_position = Vector3(0, 0.1, 0)


# --- the receiving side --------------------------------------------------------------------------------------

func _receiver_tests() -> void:
	# An enemy-layer hitbox that did crit, x2: the i-frames still refuse it, and
	# out of them the player takes exactly the damage it sent.
	_player.hurtbox.set_invulnerable(false)
	_player.health_component.current_health = _player.health_component.max_health
	var attacker: Hitbox = Hitbox.new()
	attacker.collision_layer = ENEMY_HITBOX_LAYER
	attacker.collision_mask = ENEMY_HITBOX_MASK
	attacker.damage = 10.0
	attacker.critical_chance = 1.0
	attacker.critical_damage_multiplier = 2.0
	attacker.source = self
	var shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(3, 3, 3)
	shape.shape = box
	attacker.add_child(shape)
	_player.add_child(attacker)
	attacker.position = Vector3(0, 1, 0)
	var landed: Array[DamageInfo] = []
	var on_landed: Callable = func(_target: Node, info: DamageInfo) -> void: landed.append(info)
	attacker.hit_landed.connect(on_landed)
	await _frames(2)
	_combat.reset()
	_combat.restore_stamina(_combat.get_max_stamina())
	var event: InputEventAction = InputEventAction.new()
	event.action = &"dodge"
	event.pressed = true
	_player._unhandled_input(event)
	await _until(func() -> bool: return _combat.get_dodge_phase() == PlayerCombat.DodgePhase.INVULNERABLE)
	var hp: float = _player.health_component.current_health
	attacker.activate()
	await _frames(3)
	attacker.deactivate()
	var dodged: bool = landed.size() == 1 and landed[0].is_critical and _player.health_component.current_health == hp
	var paid: float = _combat.get_max_stamina() - _combat.get_stamina()
	await _until(func() -> bool: return not _combat.is_dodging())
	await _frames(2)
	attacker.activate()
	await _frames(3)
	attacker.deactivate()
	attacker.queue_free()
	_record(dodged and paid == _tuned.dodge_stamina_cost,
		"DG1) a critical hit met in the i-frames takes nothing, like any other; the dodge cost its %.0f stamina" % paid)
	_record(landed.size() == 2 and landed[1].amount == 20.0 and hp - _player.health_component.current_health == 20.0,
		"DG2) out of them the player takes exactly the %.0f it was sent: the receiver recomputes nothing" % landed[1].amount)
	_player.hurtbox.set_invulnerable(true)
	_player.health_component.current_health = _player.health_component.max_health
	await _until(func() -> bool: return _combat.get_stamina() == _combat.get_max_stamina(), 300)


# --- helpers ----------------------------------------------------------------------------------------------

func _on_player_hit(target: Node, info: DamageInfo) -> void:
	var entry: Dictionary = {"target": target, "amount": info.amount, "critical": info.is_critical}
	var enemy: BasicEnemy = target as BasicEnemy
	if enemy != null:
		entry["staggered"] = enemy.is_staggered()
		entry["push"] = enemy.get_knockback_velocity().length()
		entry["flinched"] = enemy._flinch_tween != null and enemy._flinch_tween.is_running()
	_hits.append(entry)


## Three enemies side by side in front of the player, whole, all inside one
## swing.
func _line_up() -> void:
	await _fresh(_b, Vector3(0.0, 0.1, -1.5), false, true)
	await _fresh(_c, Vector3(0.95, 0.1, -1.5), false, true)
	await _fresh(_a, Vector3(-0.95, 0.1, -1.5), true, true)


## Parks `enemy` at `at`, whole, with nothing of a previous hit left — and,
## unless `keep_others`, the other two back out of the way.
func _fresh(enemy: BasicEnemy, at: Vector3, reset_player: bool = true, keep_others: bool = false) -> void:
	if not keep_others:
		var enemies: Array[BasicEnemy] = [_a, _b, _c]
		for i in enemies.size():
			if enemies[i] != enemy:
				enemies[i].set_combat_enabled(false)
				enemies[i].global_position = PARKED[i]
	if reset_player:
		_combat.reset()
		_player.global_position = Vector3(0, 0.1, 0)
		_player.velocity = Vector3.ZERO
		_player.camera_rig.rotation.y = 0.0
	enemy.set_combat_enabled(false)
	enemy.global_position = at
	enemy.velocity = Vector3.ZERO
	enemy.health_component.current_health = enemy.health_component.max_health
	await _frames(3)


## The player's own attack, aimed straight ahead unless `aim` is false, run to
## its end.
func _swing(chain: Array[AttackData], index: int, aim: bool = true) -> void:
	if aim:
		_player.camera_rig.rotation.y = 0.0
	_combat.reset()
	_combat._start_attack(chain, index)
	await _frames_until_state(PlayerCombat.State.IDLE)


func _bar(enemy: BasicEnemy) -> EnemyHealthBar3D:
	return enemy.get_node("EnemyHealthBar3D") as EnemyHealthBar3D


func _aim_at(target: Node3D) -> void:
	var to: Vector3 = _flat(target.global_position - _player.global_position)
	if to.length_squared() > 0.0001:
		_player.camera_rig.rotation.y = atan2(-to.x, -to.z)


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


func _wait(t: float) -> void:
	await get_tree().create_timer(t).timeout


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
