extends Node3D

## M12.8 — the boss framework: its data, the encounter, the phases and their
## transition, the attack choice and lifecycle, the reactions, the lock, the bar
## and the death — on the real boss scene, with the real player's attacks.
##
##   godot --headless --path . res://tests/bosses/boss_framework_test.tscn
##
## Two bosses share one BossData: `Boss` is fought, `BossB` stays parked until
## the end, so what one does to its runtime can be checked against the other. A
## third, with a three-phase BossData built here, proves a boss needs no dungeon
## and that several thresholds resolve deterministically. The dungeon run, the
## shadow, the reward and the second run are m12_boss_run's.

const BOSS_SCENE: PackedScene = preload("res://scenes/enemies/bosses/dungeon_boss.tscn")
const DT: float = 1.0 / 60.0

@onready var _player: Player = $Player
@onready var _boss: DungeonBoss = $Boss
@onready var _boss_b: DungeonBoss = $BossB
@onready var _bar: BossHealthBar = $BossHealthBar
@onready var _indicator: TargetLockIndicator = $TargetLockIndicator
@onready var _nav_region: NavigationRegion3D = $NavigationRegion3D

## Criticals are random (M11.7): off for this suite, except where it turns them
## on to test them. Every player reads this one cached instance.
var _combat_data: PlayerCombatData = preload("res://resources/characters/player_combat.tres")

var _pass: int = 0
var _fail: int = 0
## What the boss's signals said, in order.
var _started: Array[BossAttack] = []
var _ended: Array[Dictionary] = []
var _transitions: Array[int] = []
var _phase_changes: Array[int] = []
var _encounters: int = 0
var _deaths: int = 0
## The last hit the player's own hitbox landed.
var _last_player_hit: DamageInfo = null


func _ready() -> void:
	_combat_data.critical_chance = 0.0
	_nav_region.bake_navigation_mesh(false)
	_reset_session()
	_player.hurtbox.set_invulnerable(true)
	_player.attack_hitbox.hit_landed.connect(func(_t: Node, hit: DamageInfo) -> void: _last_player_hit = hit)
	_boss.combat.attack_started.connect(func(a: BossAttack) -> void: _started.append(a))
	_boss.combat.attack_ended.connect(func(a: BossAttack, done: bool) -> void:
		_ended.append({"attack": a, "completed": done}))
	_boss.phase_transition_started.connect(func(to: int) -> void: _transitions.append(to))
	_boss.phase_changed.connect(func(i: int) -> void: _phase_changes.append(i))
	_boss.encounter_started.connect(func(_n: String, _h: HealthComponent) -> void: _encounters += 1)
	_boss.enemy_died.connect(func(_c: RoomCombatant) -> void: _deaths += 1)
	_run()


func _run() -> void:
	await _wait(0.4)
	_config_tests()
	await _encounter_tests()
	_selection_unit_tests()
	await _free_fight_tests()
	await _lifecycle_tests()
	await _reaction_tests()
	await _critical_and_threshold_tests()
	await _transition_tests()
	await _phase_2_tests()
	await _no_rollback_tests()
	_shared_data_tests()
	await _death_cleanup_tests()
	await _death_beats_transition_tests()
	await _three_phase_tests()
	_combat_data.critical_chance = 0.0
	print("[SUMMARY] passed=%d failed=%d" % [_pass, _fail])
	get_tree().quit()


# --- 75. configuration --------------------------------------------------------------------------

func _config_tests() -> void:
	var empty: BossData = BossData.new()
	var shipped: BossData = _boss.data
	_record(empty.get_problems().has("it has no phases") and shipped.get_problems().is_empty(),
		"75a) a BossData with no phases says so; the shipped one has no problems")

	var broken: BossData = BossData.new()
	var first: BossPhaseData = BossPhaseData.new()
	first.id = &"a"
	var second: BossPhaseData = BossPhaseData.new()
	second.id = &"b"
	second.health_threshold = 1.0
	var phases: Array[BossPhaseData] = [first, second]
	broken.phases = phases
	var problems: PackedStringArray = broken.get_problems()
	_record(problems.has("phase 'b' does not start below the one before it") and problems.has("phase 'a' has no attacks"),
		"75b) phases out of order and a phase with nothing to fight with are reported: %s" % [problems])
	var bare: BossAttack = BossAttack.new()
	_record(bare.get_problems().has("an attack with no AttackData"),
		"75c) an attack with no AttackData is reported")

	# A boss with no data: reported, and inert — it never starts a fight.
	var inert: DungeonBoss = BOSS_SCENE.instantiate() as DungeonBoss
	inert.data = null
	inert._apply_data()
	inert.start_encounter()
	_record(inert.get_problems().has("no BossData assigned") and inert.get_state() == DungeonBoss.State.INACTIVE,
		"75d) a boss with no BossData reports it and stays INACTIVE when asked to fight")
	inert.free()

	# Identity: a boss is its own category — not an enemy archetype, not an elite.
	var node: Node = _boss
	_record(node is RoomCombatant and not (node is BasicEnemy) and not ("elite_profile" in _boss)
			and _boss.is_in_group(DungeonBoss.GROUP),
		"104a) the boss is a RoomCombatant in the boss group, neither a BasicEnemy nor anything with an elite profile")

	# The phase controller on its own: forward only, deepest due phase wins.
	var controller: BossPhaseController = BossPhaseController.new()
	var three: Array[BossPhaseData] = [_phase(&"p1", 1.0), _phase(&"p2", 0.7), _phase(&"p3", 0.4)]
	controller.configure(three)
	var before: int = controller.due(0.1)
	controller.start()
	_record(before == -1 and controller.get_index() == 0 and controller.due(0.8) == -1
			and controller.due(0.7) == 1 and controller.due(0.3) == 2,
		"43a) phases are due by health share: none above 70%, the second at 70%, the deepest at 30%")
	controller.enter(2)
	_record(not controller.enter(1) and controller.get_index() == 2 and controller.due(1.0) == -1,
		"78a) once in the third phase, no earlier phase can be entered or fall due")


func _phase(id: StringName, threshold: float) -> BossPhaseData:
	var phase: BossPhaseData = BossPhaseData.new()
	phase.id = id
	phase.health_threshold = threshold
	return phase


# --- 76. the encounter ------------------------------------------------------------------------------

func _encounter_tests() -> void:
	var quick: BossAttack = _attack(&"boss_quick_strike")
	_record(_boss.get_state() == DungeonBoss.State.INACTIVE and _boss.get_phase_index() == -1
			and _boss.get_target() == null and not _bar.is_showing(),
		"61a) a parked boss waits: INACTIVE, no phase, no target, no health bar")

	# 61) it must not act before its fight, even with the player at hand.
	_player.hurtbox.set_invulnerable(false)
	_place_player(_boss, 1.8)
	var at: Vector3 = _boss.global_position
	var hp: float = _player.health_component.current_health
	await _wait(1.0)
	_record(_player.health_component.current_health == hp and _boss.global_position.distance_to(at) < 0.05
			and _boss.combat.get_started_count() == 0,
		"61b) before its fight it neither moves nor attacks")
	_player.hurtbox.set_invulnerable(true)

	_boss.combat.set_cooldown(quick, 5.0)
	_boss.start_encounter()
	_record(_boss.get_state() == DungeonBoss.State.INTRO and _boss.get_phase_index() == 0
			and _boss.get_phase_id() == &"phase_1",
		"76) start_encounter(): INTRO, in phase_1")
	_record(_boss.combat.get_cooldown(quick) == 0.0 and _boss.get_target() == _player,
		"62a) the encounter starts clean: cooldowns cleared, the player its target")
	_record(_bar.is_showing() and is_equal_approx(_bar.get_ratio(), 1.0)
			and _bar.name_label.text == _boss.data.display_name and _bar.get_phase_text() == "FASE 1",
		"62b/96a) the health bar shows its name '%s', full, and '%s'" % [_bar.name_label.text, _bar.get_phase_text()])
	_boss.start_encounter()
	_record(_encounters == 1 and _phase_changes == [0],
		"62c) asking again changes nothing: one encounter, one phase announcement (%d, %s)" % [
			_encounters, _phase_changes])
	await _wait(_boss.intro_duration + 0.1)
	_record(_boss.get_state() != DungeonBoss.State.INTRO and _boss.get_state() != DungeonBoss.State.INACTIVE,
		"76b) the intro ends on its own and the fight runs (state %s)" % _state_name(_boss))


# --- 81, 83, 84. choosing -----------------------------------------------------------------------------

## On the parked twin: its combat answers without ever fighting.
func _selection_unit_tests() -> void:
	var combat: BossCombat = _boss_b.combat
	var p1: Array[BossAttack] = _boss_b.data.phases[0].attacks
	var p2: Array[BossAttack] = _boss_b.data.phases[1].attacks
	var quick: BossAttack = _attack(&"boss_quick_strike")
	var slam: BossAttack = _attack(&"boss_ground_slam")
	var double: BossAttack = _attack(&"boss_double_strike")

	var seen_p1: Dictionary = {}
	for _i in 300:
		seen_p1[combat.choose(p1, 2.0)] = true
	_record(seen_p1.size() == 3 and not seen_p1.has(double) and not seen_p1.has(null),
		"81a) phase 1 chooses only among its own three attacks (%d seen, no Double Strike)" % seen_p1.size())
	var seen_p2: Dictionary = {}
	for _i in 300:
		seen_p2[combat.choose(p2, 2.0)] = true
	_record(seen_p2.size() == 4 and seen_p2.has(double),
		"82a) phase 2's pool adds Double Strike to the three it shares (%d seen)" % seen_p2.size())

	var at_3: Dictionary = {}
	for _i in 200:
		at_3[combat.choose(p1, 3.0)] = true
	_record(not at_3.has(quick) and at_3.has(slam) and combat.choose(p1, 5.0) == null
			and not combat.has_choice(p1, 5.0),
		"83a) out of range is never chosen: no Quick Strike at 3 m, nothing at all at 5 m")
	combat.set_cooldown(quick, 5.0)
	var cooling: Dictionary = {}
	for _i in 200:
		cooling[combat.choose(p1, 2.0)] = true
	_record(not cooling.has(quick), "83b) an attack on cooldown is never chosen")

	# 84) the repeat ceiling: with only Quick Strike valid, it runs at most
	# max_consecutive_repeats times in a row, then nothing is valid until another
	# attack has run.
	combat.clear_cooldowns()
	for a in _boss_b.get_attacks():
		combat.set_cooldown(a, 99.0)
	var runs: int = 0
	for _i in 5:
		combat.set_cooldown(quick, 0.0)
		var pick: BossAttack = combat.choose(p1, 2.0)
		if pick != quick:
			break
		combat.start(pick, 1.0)
		combat.interrupt()
		runs += 1
	combat.set_cooldown(slam, 0.0)
	combat.set_cooldown(quick, 0.0)
	var other: BossAttack = combat.choose(p1, 2.0)
	combat.start(other, 1.0)
	combat.interrupt()
	combat.set_cooldown(quick, 0.0)
	var again: BossAttack = combat.choose(p1, 2.0)
	_record(runs == _boss_b.data.max_consecutive_repeats and other == slam and again != null,
		"84) the same attack runs at most %d times in a row (%d), and is valid again after another" % [
			_boss_b.data.max_consecutive_repeats, runs])
	combat.clear_cooldowns()


# --- 81, 88, 106, 107. a free fight in phase 1 ------------------------------------------------------------

func _free_fight_tests() -> void:
	_player.hurtbox.set_invulnerable(true)
	_boss.combat.clear_cooldowns()
	var pool: Array[BossAttack] = _boss.data.phases[0].attacks
	var from: int = _started.size()
	var starts: Dictionary = {}
	var cooldown_ok: bool = true
	var evaluations_at_start: Dictionary = {}
	var steady_during_attack: bool = true
	var clock: float = 0.0
	var decide_frames: int = 0
	var decide_entries: int = 0
	var last_state: DungeonBoss.State = _boss.get_state()
	var evaluations_before: int = _boss.combat.get_evaluation_count()
	var refreshes_before: int = _boss.targeting.get_refresh_count()
	var seen: int = from
	while clock < 14.0:
		_player.global_position = _boss.global_position + Vector3(0, 0, -2.0)
		await get_tree().physics_frame
		clock += DT
		var state: DungeonBoss.State = _boss.get_state()
		if state == DungeonBoss.State.DECIDE:
			decide_frames += 1
			if last_state != DungeonBoss.State.DECIDE:
				decide_entries += 1
		last_state = state
		while seen < _started.size():
			var attack: BossAttack = _started[seen]
			seen += 1
			if starts.has(attack) and clock - starts[attack] < attack.cooldown - 0.05:
				cooldown_ok = false
			starts[attack] = clock
			evaluations_at_start[attack] = _boss.combat.get_evaluation_count()
		var current: BossAttack = _boss.get_current_attack()
		if current != null and evaluations_at_start.has(current) \
				and _boss.combat.get_evaluation_count() != evaluations_at_start[current]:
			steady_during_attack = false
	var used: Array[BossAttack] = _started.slice(from)
	var outside: bool = false
	for attack in used:
		if not pool.has(attack):
			outside = true
	var evaluations: int = _boss.combat.get_evaluation_count() - evaluations_before
	_record(used.size() >= 6 and not outside and starts.size() == 3,
		"81b) a free phase 1 fight uses its three attacks and nothing else (%d attacks)" % used.size())
	_record(cooldown_ok, "88) no attack starts again before its own cooldown is over")
	_record(steady_during_attack,
		"107) no choice is weighed while an attack runs — telegraph, swing or recovery")
	_record(evaluations <= 2 * (decide_frames + decide_entries),
		"106a) choices are weighed only in DECIDE: %d over %d DECIDE frames" % [evaluations, decide_frames])
	_record(_boss.targeting.get_refresh_count() - refreshes_before == 0,
		"106b) holding its target, it never searches the tree for one")


# --- 85-90. the attack lifecycle -------------------------------------------------------------------------

func _lifecycle_tests() -> void:
	var quick: BossAttack = _attack(&"boss_quick_strike")
	var hitbox: Hitbox = _boss.combat.get_hitbox(quick)
	var landings: Array[int] = [0]
	var counter: Callable = func(_t: Node, _h: DamageInfo) -> void: landings[0] += 1
	hitbox.hit_landed.connect(counter)

	# 85-87: telegraph harmless, one landing in the swing, recovery starts nothing.
	_heal_player()
	_place_player(_boss, 1.8)
	_only(_boss, quick)
	var hp: float = _player.health_component.current_health
	var telegraph_clean: bool = true
	var active_frames: int = 0
	var recovery_clean: bool = true
	var saw_recovery: bool = false
	var started_at_recovery: int = -1
	var frames: int = 0
	var ended_from: int = _ended.size()
	while frames < 240 and _ended.size() == ended_from:
		await get_tree().physics_frame
		frames += 1
		match _boss.get_attack_phase():
			BossCombat.Phase.TELEGRAPH:
				if hitbox.is_active() or _player.health_component.current_health != hp:
					telegraph_clean = false
			BossCombat.Phase.ACTIVE:
				active_frames += 1
			BossCombat.Phase.RECOVERY:
				if not saw_recovery:
					saw_recovery = true
					started_at_recovery = _started.size()
				if hitbox.is_active() or _started.size() != started_at_recovery \
						or _boss.get_state() != DungeonBoss.State.ATTACK:
					recovery_clean = false
	hitbox.hit_landed.disconnect(counter)
	var ended: Dictionary = _ended[_ended.size() - 1] if _ended.size() > ended_from else {}
	_record(telegraph_clean, "85) the telegraph deals nothing and opens no hitbox")
	_record(active_frames > 1 and landings[0] == 1 and hp - _player.health_component.current_health == 20.0,
		"86) the swing lands once on its target over its %d open frames, for 20 (%.0f)" % [
			active_frames, hp - _player.health_component.current_health])
	_record(saw_recovery and recovery_clean and ended.get("attack") == quick and ended.get("completed") == true,
		"87) recovery opens nothing and starts nothing; the attack then ends, completed")

	# 89) i-frames: the player dodges in place and is not hit; the boss's attack
	# runs its course untouched.
	_heal_player()
	_place_player(_boss, 2.5)
	_only(_boss, _attack(&"boss_ground_slam"))
	var saved: float = _player.effective_dodge_speed
	var dodged: bool = false
	ended_from = _ended.size()
	hp = _player.health_component.current_health
	frames = 0
	while frames < 240 and _ended.size() == ended_from:
		await get_tree().physics_frame
		frames += 1
		if not dodged and _boss.get_attack_phase() == BossCombat.Phase.TELEGRAPH \
				and _boss.combat.get_phase_remaining() <= 0.1:
			_player.combat._dodge_cooldown_remaining = 0.0
			_player._on_dodge_pressed()
			_player.effective_dodge_speed = 0.0
			dodged = true
	_player.effective_dodge_speed = saved
	ended = _ended[_ended.size() - 1] if _ended.size() > ended_from else {}
	_record(dodged and _player.health_component.current_health == hp and ended.get("completed") == true,
		"89) a dodge's i-frames take the hit whole (hp %.0f); the boss's attack completes as usual" % [
			_player.health_component.current_health])
	await _wait(0.4)

	# 90) walking out of the telegraph: the swing closes on air.
	_heal_player()
	_place_player(_boss, 1.8)
	_only(_boss, quick)
	var left: bool = false
	ended_from = _ended.size()
	frames = 0
	while frames < 240 and _ended.size() == ended_from:
		await get_tree().physics_frame
		frames += 1
		if not left and _boss.get_attack_phase() == BossCombat.Phase.TELEGRAPH:
			_player.global_position = _boss.global_position + Vector3(6.0, 0, 0)
			left = true
	ended = _ended[_ended.size() - 1] if _ended.size() > ended_from else {}
	_record(left and _player.health_component.current_health == _player.health_component.max_health
			and ended.get("completed") == true,
		"90) leaving during the telegraph avoids the hit; the attack still completes")
	_player.hurtbox.set_invulnerable(true)


# --- 91-93. stagger and knockback ---------------------------------------------------------------------------

func _reaction_tests() -> void:
	var slam: BossAttack = _attack(&"boss_ground_slam")
	var light: Array[AttackData] = _combat_data.light_combo
	var heavy: AttackData = _combat_data.heavy_combo[0]
	var resistance: float = _boss.stagger_resistance
	_record(light[0].stagger_power < resistance and light[1].stagger_power < resistance
			and light[2].stagger_power < resistance and heavy.stagger_power >= resistance,
		"92a) resistance %.0f: Light 1/2/3 (%.0f/%.0f/%.0f) stay below it, the heavy (%.0f) reaches it" % [
			resistance, light[0].stagger_power, light[1].stagger_power, light[2].stagger_power, heavy.stagger_power])

	# 91) each light, landed in a telegraph: the attack goes on.
	var carried_on: int = 0
	for i in 3:
		_player.hurtbox.set_invulnerable(true)
		_place_player(_boss, 1.6)
		_only(_boss, slam)
		await _until(func() -> bool: return _boss.get_attack_phase() == BossCombat.Phase.TELEGRAPH, 120)
		_last_player_hit = null
		await _swing(light, i)
		var landed: bool = _last_player_hit != null and not _boss.is_staggered()
		var swung: bool = await _until(func() -> bool: return _boss.get_attack_phase() == BossCombat.Phase.ACTIVE, 120)
		if landed and swung:
			carried_on += 1
		await _until(func() -> bool: return _boss.get_attack_phase() == BossCombat.Phase.NONE, 240)
	_record(carried_on == 3, "91) Light 1, 2 and 3 each land in a telegraph and the boss swings anyway (%d/3)" % carried_on)

	# 92) the heavy, landed in a telegraph: staggered, the attack cut off.
	_place_player(_boss, 1.6)
	_only(_boss, slam)
	await _until(func() -> bool: return _boss.get_attack_phase() == BossCombat.Phase.TELEGRAPH, 120)
	var ended_from: int = _ended.size()
	var at: Vector3 = _boss.global_position
	# Read as the hit lands, after the boss's own reaction to it.
	var pushes: Array[float] = []
	var reader: Callable = func(_hit: DamageInfo) -> void: pushes.append(_boss.get_knockback_velocity().length())
	_boss.health_component.damaged.connect(reader)
	_last_player_hit = null
	_strike(_combat_data.heavy_combo, 0)
	await _until(func() -> bool: return _last_player_hit != null, 60)
	_boss.health_component.damaged.disconnect(reader)
	var push: float = pushes[0] if not pushes.is_empty() else 0.0
	var cut: Dictionary = _ended[_ended.size() - 1] if _ended.size() > ended_from else {}
	_record(_boss.is_staggered() and _boss.get_current_attack() == null and not _boss.combat.is_hit_window_open()
			and cut.get("attack") == slam and cut.get("completed") == false,
		"92b) the heavy lands in the telegraph: STAGGERED, the slam cut off, no hitbox")
	_record(push > 0.0 and push <= heavy.knockback_force * _boss.knockback_multiplier + 0.001,
		"93a) its push is scaled down to %.2f m/s (the heavy's %.1f x %.2f)" % [
			push, heavy.knockback_force, _boss.knockback_multiplier])
	await _until(func() -> bool: return not _boss.is_staggered(), 120)
	var drift: float = _flat(_boss.global_position - at).length()
	_record(drift < 0.1, "93b) the heavy moves the boss %.3f m — it does not fly across the arena" % drift)
	_record(not _boss.is_staggered() and _boss.is_stagger_immune(),
		"92c) the stagger ends on its own, and a short immunity follows")

	# 92d) within the immunity, a second heavy does not stagger it again.
	_place_player(_boss, 1.6)
	_only(_boss, slam)
	await _until(func() -> bool: return _boss.get_attack_phase() == BossCombat.Phase.TELEGRAPH, 120)
	_last_player_hit = null
	_strike(_combat_data.heavy_combo, 0)
	await _until(func() -> bool: return _last_player_hit != null, 60)
	var standing: bool = not _boss.is_staggered() and _boss.get_current_attack() == slam
	var swung_anyway: bool = await _until(func() -> bool: return _boss.get_attack_phase() == BossCombat.Phase.ACTIVE, 120)
	_record(_last_player_hit != null and standing and swung_anyway and _boss.is_stagger_immune(),
		"92d) inside the immunity a heavy lands and the boss swings anyway")
	await _until(func() -> bool: return _boss.get_attack_phase() == BossCombat.Phase.NONE, 240)
	await _until(func() -> bool: return _player.combat.get_state() == PlayerCombat.State.IDLE, 120)


# --- 94, 95, 77. critical, lock, crossing the threshold ----------------------------------------------------

func _critical_and_threshold_tests() -> void:
	var health: HealthComponent = _boss.health_component
	_player.hurtbox.set_invulnerable(true)
	# Held still between two attacks, so every swing here lands: its hits and
	# reactions still run — they are signals — only its own tick is paused.
	await _until(func() -> bool: return _boss.get_attack_phase() == BossCombat.Phase.NONE, 240)
	_boss.set_physics_process(false)

	# 95) the lock, taken in phase 1.
	_place_player(_boss, 1.6)
	_aim_at(_boss)
	await _frames(2)
	_press(&"target_lock")
	await _frames(2)
	_record(_player.targeting.get_target() == _boss and _indicator.get_target() == _boss and _indicator.is_showing(),
		"95a) the player locks the boss in phase 1; the ring is on it")

	# 94) normal and critical, the same hit.
	_combat_data.critical_chance = 0.0
	var before: float = health.current_health
	await _swing(_combat_data.light_combo, 0)
	var normal: float = before - health.current_health
	var normal_crit: bool = _last_player_hit != null and _last_player_hit.is_critical
	_combat_data.critical_chance = 1.0
	before = health.current_health
	await _swing(_combat_data.light_combo, 0)
	var critical: float = before - health.current_health
	var crit_flag: bool = _last_player_hit != null and _last_player_hit.is_critical
	_record(normal == 20.0 and not normal_crit and critical == roundf(20.0 * _combat_data.critical_damage_multiplier)
			and crit_flag and is_equal_approx(_bar.get_ratio(), health.current_health / health.max_health),
		"94a) Light 1 lands for %.0f, and for %.0f as a critical; the health and the bar follow" % [normal, critical])

	# 77/94) a critical carries it over the threshold: the transition, once.
	var threshold: float = _boss.data.phases[1].health_threshold * health.max_health
	health.current_health = threshold + 25.0
	_combat_data.critical_chance = 0.0
	await _swing(_combat_data.light_combo, 0)
	var above: bool = _boss.get_phase_index() == 0 and not _boss.is_in_transition() and _transitions.is_empty()
	_combat_data.critical_chance = 1.0
	await _swing(_combat_data.light_combo, 0)
	_combat_data.critical_chance = 0.0
	_record(above and _transitions == [1] and _boss.is_in_transition() and _boss.get_phase_index() == 0,
		"77a/94b) a normal hit leaves it above 50%; a critical takes it under and the transition to phase 2 begins")


# --- 79, 14-18. the transition -----------------------------------------------------------------------------------

func _transition_tests() -> void:
	var health: HealthComponent = _boss.health_component
	_boss.set_physics_process(true)
	_record(_boss.get_current_attack() == null and not _boss.combat.is_hit_window_open()
			and _boss.get_attack_phase() == BossCombat.Phase.NONE,
		"79a) in the transition nothing is attacking and no hitbox is open")
	_record(_bar.is_banner_showing() and _bar.get_phase_text() == "FASE 2",
		"96b) the bar flashes its callout and reads '%s'" % _bar.get_phase_text())
	_record(_player.targeting.get_target() == _boss and _indicator.is_showing(),
		"95b) the lock holds through the transition")

	# 16) it takes damage in the beat, and the bar never resets.
	var evaluations: int = _boss.combat.get_evaluation_count()
	var ratio: float = _bar.get_ratio()
	var before: float = health.current_health
	_boss.hurtbox.receive_hit(_crafted(10.0, 1000.0, 0.0))
	await _frames(2)
	_record(health.current_health == before - 10.0 and _bar.get_ratio() < ratio and not _boss.is_staggered()
			and _boss.is_in_transition(),
		"16/96c) the boss takes damage in its transition, the bar follows down, and no stagger breaks the beat")

	var at: Vector3 = _boss.global_position
	var steady: bool = true
	while _boss.is_in_transition():
		if _boss.get_current_attack() != null or _boss.combat.is_hit_window_open():
			steady = false
		await get_tree().physics_frame
	_record(steady and _boss.global_position.distance_to(at) < 0.1
			and _boss.combat.get_evaluation_count() == evaluations,
		"14/107b) for the whole beat: no attack, no hitbox, no movement, no choice weighed")
	_record(_boss.get_phase_index() == 1 and _boss.get_phase_id() == &"phase_2" and _phase_changes == [0, 1]
			and _transitions == [1],
		"77b) the transition ends in phase_2, announced once (%s)" % [_phase_changes])
	_record(_player.targeting.get_target() == _boss and _indicator.get_target() == _boss,
		"95c) the lock still holds in phase 2")


# --- 82, 52-53. phase 2 ------------------------------------------------------------------------------------------

func _phase_2_tests() -> void:
	var phase_2: BossPhaseData = _boss.data.phases[1]
	var quick: BossAttack = _attack(&"boss_quick_strike")
	var double: BossAttack = _attack(&"boss_double_strike")
	_record(is_equal_approx(_boss.movement_speed, _boss.data.movement_speed * phase_2.movement_speed_multiplier)
			and is_equal_approx(_boss.data.movement_speed, 3.2) and is_equal_approx(phase_2.movement_speed_multiplier, 1.19),
		"53) phase 2's speed is the runtime's (%.2f); the BossData keeps its 3.2" % _boss.movement_speed)

	# 82) the new pool, the shared attacks still working.
	var from: int = _started.size()
	var clock: float = 0.0
	while clock < 12.0:
		_player.global_position = _boss.global_position + Vector3(0, 0, -2.0)
		await get_tree().physics_frame
		clock += DT
	var used: Array[BossAttack] = _started.slice(from)
	var outside: bool = false
	for attack in used:
		if not phase_2.attacks.has(attack):
			outside = true
	_record(used.has(double) and not outside,
		"82b) phase 2 fights from its own pool, Double Strike included (%d attacks)" % used.size())

	_heal_player()
	_place_player(_boss, 1.8)
	_only(_boss, quick)
	var hp: float = _player.health_component.current_health
	var telegraph: float = 0.0
	var frames: int = 0
	while frames < 180 and _player.health_component.current_health == hp:
		if _boss.get_attack_phase() == BossCombat.Phase.TELEGRAPH:
			telegraph += DT
		await get_tree().physics_frame
		frames += 1
	_record(hp - _player.health_component.current_health == 20.0
			and telegraph <= quick.attack.windup * phase_2.tempo_multiplier + 2.0 * DT,
		"82c) a shared attack still works in phase 2: Quick Strike lands for 20, after a %.2fs telegraph (tempo x%.2f)" % [
			telegraph, phase_2.tempo_multiplier])
	_player.hurtbox.set_invulnerable(true)
	await _until(func() -> bool: return _boss.get_attack_phase() == BossCombat.Phase.NONE, 240)


# --- 78. no rollback -------------------------------------------------------------------------------------------

func _no_rollback_tests() -> void:
	var health: HealthComponent = _boss.health_component
	health.heal(health.max_health)
	await _frames(3)
	_record(health.current_health == health.max_health and _boss.get_phase_index() == 1
			and not _boss.is_in_transition() and _transitions == [1] and _bar.get_phase_text() == "FASE 2",
		"78b) healed back to full, the boss stays in phase 2 — no rollback, no second transition")


# --- 57. two bosses, one BossData ------------------------------------------------------------------------------

func _shared_data_tests() -> void:
	var quick: BossAttack = _attack(&"boss_quick_strike")
	_record(_boss.data == _boss_b.data,
		"57a) both bosses read the same BossData asset")
	_record(_boss_b.get_phase_index() == -1 and _boss_b.health_component.current_health == _boss_b.health_component.max_health
			and _boss_b.combat.get_cooldown(quick) == 0.0 and _boss_b.get_target() == null
			and is_equal_approx(_boss_b.movement_speed, _boss_b.data.movement_speed),
		"57b) the twin shares none of it: no phase, full health, no cooldown, no target, phase 1's speed")
	_record(is_equal_approx(quick.cooldown, 1.0) and is_equal_approx(quick.attack.windup, 0.25)
			and is_equal_approx(_boss.data.max_health, 900.0) and _boss.data.phases.size() == 2,
		"57c) the shared assets are untouched after a whole fight")


# --- 100. the death ---------------------------------------------------------------------------------------------

func _death_cleanup_tests() -> void:
	var double: BossAttack = _attack(&"boss_double_strike")
	_player.hurtbox.set_invulnerable(true)
	_place_player(_boss, 1.8)
	_only(_boss, double)
	await _until(func() -> bool: return _boss.get_attack_phase() == BossCombat.Phase.BETWEEN_HITS, 180)
	var mid_attack: bool = _boss.get_current_attack() == double
	var started: int = _boss.combat.get_started_count()
	_boss.hurtbox.receive_hit(_crafted(10000.0, 0.0, 0.0))
	await get_tree().physics_frame
	_record(mid_attack and _boss.get_state() == DungeonBoss.State.DEAD and _deaths == 1,
		"100a) killed between Double Strike's two swings: DEAD, reported once")
	_record(_boss.get_current_attack() == null and _boss.get_attack_phase() == BossCombat.Phase.NONE
			and _boss.get_target() == null,
		"100b) no attack left, no target held")
	var at: Vector3 = _boss.global_position
	var live: bool = false
	var frames: int = 0
	while frames < 90:
		live = live or _boss.combat.is_hit_window_open()
		await get_tree().physics_frame
		frames += 1
	_record(not live and _boss.combat.get_started_count() == started and _boss.global_position.distance_to(at) < 0.01
			and _boss.velocity == Vector3.ZERO and _boss.nav_agent.target_position.distance_to(_boss.global_position) < 0.5,
		"100c) no hit window ever reopens, no attack starts, the body and its navigation stand still")
	_boss.health_component.heal(500.0)
	await _frames(2)
	_record(_boss.health_component.is_dead and _transitions == [1] and _boss.get_phase_index() == 1,
		"100d) the phases stop with it: nothing heals it, nothing transitions")
	_record(not _player.targeting.is_locked() and not _indicator.is_showing(),
		"95d/100e) the lock lets go of the dead boss and the ring goes")
	_record(not _bar.is_showing() and not _bar.is_banner_showing(), "96d/100f) the health bar is gone")
	_record(_deaths == 1, "99a) its death is reported exactly once (%d)" % _deaths)


# --- 80. death beats the transition -----------------------------------------------------------------------------------

func _death_beats_transition_tests() -> void:
	var transitions: Array[int] = []
	var deaths: Array[int] = [0]
	_boss_b.phase_transition_started.connect(func(to: int) -> void: transitions.append(to))
	_boss_b.enemy_died.connect(func(_c: RoomCombatant) -> void: deaths[0] += 1)
	_boss_b.start_encounter()
	var health: HealthComponent = _boss_b.health_component
	_boss_b.hurtbox.receive_hit(_crafted(health.max_health * 0.48, 0.0, 0.0))
	await _frames(2)
	var just_above: bool = _boss_b.get_phase_index() == 0 and not _boss_b.is_in_transition()
	_boss_b.hurtbox.receive_hit(_crafted(health.max_health, 0.0, 0.0))
	await _frames(2)
	_record(just_above and _boss_b.get_state() == DungeonBoss.State.DEAD and transitions.is_empty()
			and _boss_b.get_phase_index() == 0 and deaths[0] == 1,
		"80) a lethal blow through the threshold is a death: DEAD in phase 1, no transition, one report")


# --- 43, 58, 79, 108-109. a three-phase boss, on its own -------------------------------------------------------------

func _three_phase_tests() -> void:
	var shipped: BossData = _boss.data
	var custom: BossData = BossData.new()
	custom.id = &"test_three_phase"
	custom.display_name = "Test Boss"
	custom.max_health = 1000.0
	custom.attack_damage = shipped.attack_damage
	var p1: BossPhaseData = _phase(&"phase_1", 1.0)
	p1.attacks = shipped.phases[0].attacks.duplicate()
	var p2: BossPhaseData = _phase(&"phase_2", 0.7)
	p2.transition_duration = 1.0
	p2.attacks = shipped.phases[1].attacks.duplicate()
	var p3: BossPhaseData = _phase(&"phase_3", 0.4)
	p3.transition_duration = 0.5
	p3.tempo_multiplier = 0.6
	p3.attacks = shipped.phases[1].attacks.duplicate()
	var phases: Array[BossPhaseData] = [p1, p2, p3]
	custom.phases = phases

	var boss: DungeonBoss = BOSS_SCENE.instantiate() as DungeonBoss
	boss.data = custom
	boss.debug_state_label = true
	boss.debug_log_phases = true
	boss.position = Vector3(-15, 0.1, 15)
	var changes: Array[int] = []
	var transitions: Array[int] = []
	var ended: Array[Dictionary] = []
	boss.phase_changed.connect(func(i: int) -> void: changes.append(i))
	boss.phase_transition_started.connect(func(to: int) -> void: transitions.append(to))
	add_child(boss)
	boss.combat.attack_ended.connect(func(a: BossAttack, done: bool) -> void:
		ended.append({"attack": a, "completed": done}))
	await _frames(3)
	_record(custom.get_problems().is_empty() and boss.get_state() == DungeonBoss.State.INTRO
			and boss.get_phase_id() == &"phase_1",
		"58) a boss with no room and no dungeon starts its own encounter (INTRO, phase_1)")
	_record(not _boss.debug_state_label and not _boss.debug_log_phases and _boss._debug_label == null
			and boss._debug_label != null and boss._debug_label.text.contains("INTRO") and boss._debug_label.text.contains("phase_1"),
		"108) the debug readout is off by default, and when asked for shows state and phase: '%s'" % [
			boss._debug_label.text.replace("\n", " | ") if boss._debug_label != null else ""])

	# 79) crossing a threshold in the middle of a swing: the swing is cancelled.
	var quick: BossAttack = _attack(&"boss_quick_strike")
	_player.hurtbox.set_invulnerable(true)
	await _wait(boss.intro_duration + 0.1)
	_place_player(boss, 1.8)
	_only(boss, quick)
	var open: bool = await _until(func() -> bool: return boss.combat.is_hit_window_open(), 120)
	boss.hurtbox.receive_hit(_crafted(350.0, 0.0, 0.0))
	var cut: Dictionary = ended[ended.size() - 1] if not ended.is_empty() else {}
	_record(open and boss.is_in_transition() and not boss.combat.is_hit_window_open()
			and boss.get_current_attack() == null and cut.get("attack") == quick and cut.get("completed") == false,
		"79b) a hit across 70% in a swing's open window: the swing is cancelled on the spot, its hitbox shut, the transition begins")

	# 43) a deeper threshold crossed inside the beat: the beat leads there instead.
	boss.hurtbox.receive_hit(_crafted(300.0, 0.0, 0.0))
	await get_tree().physics_frame
	_record(boss.get_transition_target() == 2 and transitions == [1],
		"43b) crossing 40% during the beat retargets it to phase 3 — one beat, deterministically")
	await _until(func() -> bool: return not boss.is_in_transition(), 120)
	_record(boss.get_phase_index() == 2 and changes == [0, 2] and is_equal_approx(boss._tempo(), 0.6),
		"43c) it ends in phase_3, passing over phase_2 (%s), at phase 3's tempo" % [changes])
	boss.queue_free()
	await _frames(2)


# --- helpers ----------------------------------------------------------------------------------------------------------

func _attack(id: StringName) -> BossAttack:
	for attack in _boss.get_attacks():
		if attack.get_id() == id:
			return attack
	return null


## Makes `attack` the only one `boss` may choose, and sends it to decide now.
func _only(boss: DungeonBoss, attack: BossAttack) -> void:
	boss.combat.interrupt()
	boss.combat.clear_cooldowns()
	for a in boss.get_attacks():
		boss.combat.set_cooldown(a, 0.0 if a == attack else 99.0)
	boss._change_state(DungeonBoss.State.DECIDE)


## Stands the player `distance` in front of `boss`, the boss facing it.
func _place_player(boss: DungeonBoss, distance: float) -> void:
	_player.global_position = boss.global_position + Vector3(0, 0, -distance)
	boss.visual_root.rotation.y = 0.0


func _heal_player() -> void:
	_player.health_component.current_health = _player.health_component.max_health
	_player.health_component.is_dead = false
	_player.hurtbox.set_invulnerable(false)


## One of the player's real attacks, aimed at the boss, started.
func _strike(chain: Array[AttackData], index: int) -> void:
	_aim_at(_boss)
	_player.combat.reset()
	_player.combat._start_attack(chain, index)


## One of the player's real attacks, aimed at the boss, to its end.
func _swing(chain: Array[AttackData], index: int) -> void:
	_strike(chain, index)
	var frames: int = 0
	while _player.combat.get_state() != PlayerCombat.State.IDLE and frames < 180:
		await get_tree().physics_frame
		frames += 1


func _aim_at(target: Node3D) -> void:
	var to: Vector3 = _flat(target.global_position - _player.global_position)
	if to.length_squared() > 0.0001:
		_player.camera_rig.rotation.y = atan2(-to.x, -to.z)


func _press(action: StringName) -> void:
	var event: InputEventAction = InputEventAction.new()
	event.action = action
	event.pressed = true
	_player._unhandled_input(event)


func _crafted(amount: float, stagger: float, push: float) -> DamageInfo:
	var info: DamageInfo = DamageInfo.new(amount, _player, &"test_hit")
	info.stagger_power = stagger
	info.knockback_force = push
	info.direction = Vector3.FORWARD
	return info


func _until(condition: Callable, budget: int) -> bool:
	var n: int = 0
	while not condition.call():
		if n >= budget:
			return false
		await get_tree().physics_frame
		n += 1
	return true


func _state_name(boss: DungeonBoss) -> String:
	return DungeonBoss.State.keys()[boss.get_state()]


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
