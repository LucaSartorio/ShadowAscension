extends Node3D

## M12.9 — the boss's phase mechanics: phase 2 as a real escalation (its own
## pool, a new attack, a quicker rhythm, more speed), the Heavy Slam, the enrage,
## the modifier pipeline and every threshold rule — on the real boss scene, with
## the real player's attacks.
##
##   godot --headless --path . res://tests/bosses/boss_phase_mechanics_test.tscn
##
## `Boss` is fought from phase 1 to its death while enraged; the threshold rules
## that each need a fresh fight run on bosses spawned here. Hits that are not
## the player's come from a stand-in node, to prove the rules care about how
## much health is left, never about who took it.

const BOSS_SCENE: PackedScene = preload("res://scenes/enemies/bosses/dungeon_boss.tscn")
const DT: float = 1.0 / 60.0

@onready var _player: Player = $Player
@onready var _boss: DungeonBoss = $Boss
@onready var _bar: BossHealthBar = $BossHealthBar
@onready var _indicator: TargetLockIndicator = $TargetLockIndicator
@onready var _nav_region: NavigationRegion3D = $NavigationRegion3D

## Criticals are random (M11.7): off for this suite except where it turns them
## on. Every player reads this one cached instance.
var _combat_data: PlayerCombatData = preload("res://resources/characters/player_combat.tres")

var _pass: int = 0
var _fail: int = 0
## The main boss's escalation, in order: "transition_1", "phase_1", "enrage_started", "enraged".
var _events: Array[String] = []
var _started: Array[BossAttack] = []
var _ended: Array[Dictionary] = []
var _deaths: Array[int] = [0]
var _last_player_hit: DamageInfo = null
## A source that is neither the player nor a shadow.
var _stand_in: Node3D = null


func _ready() -> void:
	_combat_data.critical_chance = 0.0
	_nav_region.bake_navigation_mesh(false)
	_reset_session()
	_player.hurtbox.set_invulnerable(true)
	_player.attack_hitbox.hit_landed.connect(func(_t: Node, hit: DamageInfo) -> void: _last_player_hit = hit)
	_watch(_boss, _events, _deaths)
	_boss.combat.attack_started.connect(func(a: BossAttack) -> void: _started.append(a))
	_boss.combat.attack_ended.connect(func(a: BossAttack, done: bool) -> void:
		_ended.append({"attack": a, "completed": done}))
	_stand_in = Node3D.new()
	_stand_in.name = "StandInSource"
	add_child(_stand_in)
	_run()


func _run() -> void:
	await _wait(0.4)
	_config_tests()
	await _phase_1_tests()
	await _phase_2_entry_tests()
	await _special_tests()
	await _special_death_tests()
	await _enrage_tests()
	await _enraged_combat_tests()
	await _enraged_death_tests()
	await _threshold_tests()
	await _model_swap_tests()
	_combat_data.critical_chance = 0.0
	print("[SUMMARY] passed=%d failed=%d" % [_pass, _fail])
	get_tree().quit()


# --- configuration ---------------------------------------------------------------------------------------

func _config_tests() -> void:
	var data: BossData = _boss.data
	var phase_1: BossPhaseData = data.phases[0]
	var phase_2: BossPhaseData = data.phases[1]
	var heavy: BossAttack = _attack(&"boss_heavy_slam")
	_record(heavy != null and not phase_1.attacks.has(heavy) and phase_2.attacks.has(heavy),
		"5/13) Heavy Slam is in phase 2's pool and in no other: a pool entry, no code path of its own")
	var longest_other: float = 0.0
	var lightest: bool = true
	for attack in phase_2.attacks:
		if attack != heavy:
			longest_other = maxf(longest_other, attack.attack.windup)
			lightest = lightest and attack.weight > heavy.weight and attack.cooldown < heavy.cooldown
	_record(is_equal_approx(heavy.attack.windup, 1.1) and is_equal_approx(heavy.attack.active, 0.2)
			and is_equal_approx(heavy.attack.recovery, 1.4) and heavy.attack.windup > longest_other
			and heavy.hit_count == 1 and heavy.facing_correction_fraction == 0.0
			and heavy.telegraph == BossAttack.Telegraph.RAISE and heavy.telegraph_marker_name == &"HeavySlamMarker",
		"6-12) Heavy Slam: the longest telegraph (1.1 s, next longest %.2f), a 0.2 s hit window, a 1.4 s recovery, one hit, committed from the start, its own wind-up and ground marker" % longest_other)
	var hitbox: Hitbox = _boss.combat.get_hitbox(heavy)
	_record(hitbox != null and hitbox.damage == 50.0 and hitbox.attack_id == &"boss_heavy_slam"
			and is_equal_approx(heavy.attack.damage_multiplier, 2.5),
		"9) its damage is data: the boss's base 20 x its 2.5 = %.0f, through the standard hitbox" % (hitbox.damage if hitbox != null else 0.0))
	_record(lightest and is_equal_approx(heavy.cooldown, 8.0) and is_equal_approx(heavy.weight, 0.5),
		"14/15) the lightest weight in the pool (0.5) and the longest cooldown (8 s): it cannot be spammed")

	var enrage: BossEnrageData = data.enrage
	_record(enrage != null and is_equal_approx(enrage.health_threshold, 0.25) and is_equal_approx(enrage.transition_duration, 1.0)
			and is_equal_approx(enrage.movement_speed_multiplier, 1.1) and is_equal_approx(enrage.cooldown_multiplier, 0.85)
			and enrage.health_threshold < phase_2.health_threshold,
		"24/27) the enrage is data: at 25%, a 1 s beat, speed x1.1, cooldowns x0.85 — below phase 2's 50%")

	var wrong: BossData = BossData.new()
	var p1: BossPhaseData = _phase(&"a", 1.0, phase_1.attacks)
	var p2: BossPhaseData = _phase(&"b", 0.5, phase_1.attacks)
	var phases: Array[BossPhaseData] = [p1, p2]
	wrong.phases = phases
	wrong.enrage = BossEnrageData.new()
	wrong.enrage.health_threshold = 0.6
	_record(wrong.get_problems().has("the enrage threshold is not below the last phase's"),
		"24b) an enrage above the last phase's threshold is reported")

	var controller: BossPhaseController = BossPhaseController.new()
	var enrage_at: BossEnrageData = BossEnrageData.new()
	controller.configure(phases, enrage_at)
	controller.start()
	var phase_first: bool = controller.due(0.2) == 1 and not controller.enrage_due(0.2)
	controller.enter(1)
	var gated: bool = not controller.enrage_due(0.3) and controller.enrage_due(0.2)
	var once: bool = controller.enrage() and not controller.enrage() and controller.is_enraged() and not controller.enrage_due(0.1)
	_record(phase_first and gated and once and controller.get_index() == 1,
		"25/26/39a) the controller: at 20% from phase 1 the phase comes first, the enrage after; it happens once and stays")


# --- phase 1 --------------------------------------------------------------------------------------------------

func _phase_1_tests() -> void:
	_boss.start_encounter()
	await _wait(_boss.intro_duration + 0.1)
	_record(is_equal_approx(_boss.movement_speed, _boss.data.movement_speed)
			and is_equal_approx(_boss.combat.get_recovery_scale(), 1.0) and is_equal_approx(_boss.combat.get_cooldown_scale(), 1.0)
			and not _boss.is_enraged(),
		"3) phase 1 is the baseline: speed %.1f, recovery and cooldown x1, not enraged" % _boss.movement_speed)
	var pool: Array[BossAttack] = _boss.data.phases[0].attacks
	var from: int = _started.size()
	var clock: float = 0.0
	while clock < 10.0:
		_player.global_position = _boss.global_position + Vector3(0, 0, -2.0)
		await get_tree().physics_frame
		clock += DT
	var used: Dictionary = {}
	var outside: bool = false
	for attack in _started.slice(from):
		used[attack] = true
		outside = outside or not pool.has(attack)
	_record(used.size() == 3 and not outside,
		"86) a free phase 1 fight uses all three of its attacks and nothing else — no Double Strike, no Heavy Slam (%d attacks)" % (_started.size() - from))

	# The lock, taken in phase 1 and held to the end.
	await _until(func() -> bool: return _boss.get_attack_phase() == BossCombat.Phase.NONE, 240)
	_place_player(_boss, 2.0)
	_aim_at(_boss)
	await _frames(2)
	_press(&"target_lock")
	await _frames(2)
	_record(_player.targeting.get_target() == _boss and _indicator.get_target() == _boss,
		"41a) the player locks the boss in phase 1")


# --- phase 2 --------------------------------------------------------------------------------------------------

func _phase_2_entry_tests() -> void:
	var health: HealthComponent = _boss.health_component
	_boss.hurtbox.receive_hit(_crafted(health.current_health - health.max_health * 0.6, 0.0, _stand_in))
	await _frames(2)
	var above: bool = _boss.get_phase_index() == 0 and not _boss.is_in_transition()
	_boss.hurtbox.receive_hit(_crafted(health.current_health - health.max_health * 0.49, 0.0, _stand_in))
	await _frames(2)
	_record(above and _boss.is_in_transition() and _events.has("transition_1"),
		"44a) a hit from someone who is neither the player nor a shadow takes it past 50%: the transition")
	await _until(func() -> bool: return not _boss.is_in_transition(), 180)
	var phase_2: BossPhaseData = _boss.data.phases[1]
	var base: float = _boss.data.movement_speed
	_record(_boss.get_phase_index() == 1 and is_equal_approx(_boss.movement_speed, base * phase_2.movement_speed_multiplier)
			and is_equal_approx(_boss.nav_agent.max_speed, _boss.movement_speed)
			and is_equal_approx(_boss.combat.get_recovery_scale(), 0.85) and is_equal_approx(_boss.combat.get_cooldown_scale(), 0.85),
		"4/17/19/20) phase 2: speed %.2f (base %.1f x %.2f), recovery x0.85, cooldowns x0.85" % [
			_boss.movement_speed, base, phase_2.movement_speed_multiplier])
	var speed: float = _boss.movement_speed
	_boss._apply_modifiers()
	_boss._apply_modifiers()
	_record(is_equal_approx(_boss.movement_speed, speed) and is_equal_approx(_boss.combat.get_cooldown_scale(), 0.85),
		"21/22) the modifiers are idempotent: applied again, nothing compounds (%.3f)" % _boss.movement_speed)
	_record(is_equal_approx(base, 3.2) and is_equal_approx(phase_2.movement_speed_multiplier, 1.19)
			and is_equal_approx(_attack(&"boss_quick_strike").cooldown, 1.0) and is_equal_approx(_attack(&"boss_quick_strike").attack.windup, 0.25),
		"53a) the BossData and the attacks are untouched: base 3.2, x1.19, Quick Strike's 1.0 s cooldown and 0.25 s telegraph")
	_record(_player.targeting.get_target() == _boss, "41b) the lock holds through the transition into phase 2")


# --- the Heavy Slam --------------------------------------------------------------------------------------------------

func _special_tests() -> void:
	var heavy: BossAttack = _attack(&"boss_heavy_slam")
	var hitbox: Hitbox = _boss.combat.get_hitbox(heavy)
	var marker: Node3D = _boss.combat.get_marker(heavy)
	var landings: Array[int] = [0]
	var counter: Callable = func(_t: Node, _h: DamageInfo) -> void: landings[0] += 1
	hitbox.hit_landed.connect(counter)

	# 88) the lifecycle, measured.
	_heal_player()
	_place_player(_boss, 2.5)
	_only(_boss, heavy)
	var hp: float = _player.health_component.current_health
	var telegraph: float = 0.0
	var recovery: float = 0.0
	var marker_ok: bool = true
	var harmless: bool = true
	var ended_from: int = _ended.size()
	var frames: int = 0
	while frames < 400 and _ended.size() == ended_from:
		await get_tree().physics_frame
		frames += 1
		match _boss.get_attack_phase():
			BossCombat.Phase.TELEGRAPH:
				telegraph += DT
				marker_ok = marker_ok and marker.visible
				harmless = harmless and not hitbox.is_active() and _player.health_component.current_health == hp
			BossCombat.Phase.ACTIVE:
				marker_ok = marker_ok and not marker.visible
			BossCombat.Phase.RECOVERY:
				recovery += DT
	var ended: Dictionary = _ended[_ended.size() - 1] if _ended.size() > ended_from else {}
	_record(absf(telegraph - 1.1) <= 3.0 * DT and harmless and marker_ok,
		"88a/8) its telegraph runs its full %.2f s — its marker on the ground, no hitbox, no damage — and the marker goes as it lands" % telegraph)
	_record(landings[0] == 1 and hp - _player.health_component.current_health == 50.0,
		"88b/10) the hit window lands once, for 50 (%.0f)" % (hp - _player.health_component.current_health))
	_record(absf(recovery - 1.4 * 0.85) <= 3.0 * DT and ended.get("completed") == true,
		"88c/31) then a %.2f s recovery (1.4 x phase 2's 0.85) before it is free" % recovery)
	var cooling: float = _boss.combat.get_cooldown(heavy)
	var only_heavy: Array[BossAttack] = [heavy]
	_record(cooling > 0.0 and cooling <= 8.0 * 0.85 and _boss.combat.choose(only_heavy, 2.5) == null,
		"88d/16) its cooldown (%.2f s left of 6.8) keeps it from coming straight back" % cooling)

	# 12/50) committed: step aside in the telegraph and it neither turns nor lands.
	_heal_player()
	_place_player(_boss, 2.5)
	_only(_boss, heavy)
	await _until(func() -> bool: return _boss.get_attack_phase() == BossCombat.Phase.TELEGRAPH, 120)
	var yaw: float = _boss.visual_root.rotation.y
	_player.global_position = _boss.global_position + Vector3(3.0, 0, -1.0)
	landings[0] = 0
	ended_from = _ended.size()
	await _until(func() -> bool: return _ended.size() > ended_from, 400)
	_record(absf(wrapf(_boss.visual_root.rotation.y - yaw, -PI, PI)) < 0.01 and landings[0] == 0
			and _player.health_component.current_health == _player.health_component.max_health,
		"12/50) no tracking: the player steps aside in the telegraph, the boss keeps its aim and the slam lands on empty ground")

	# 49) a dodge in place: the stamina paid, the i-frames take the hit.
	_heal_player()
	_place_player(_boss, 2.5)
	_only(_boss, heavy)
	var saved: float = _player.effective_dodge_speed
	var stamina_before: float = 0.0
	var stamina_after: float = 0.0
	var covered: bool = false
	var dodged: bool = false
	landings[0] = 0
	ended_from = _ended.size()
	frames = 0
	while frames < 400 and _ended.size() == ended_from:
		await get_tree().physics_frame
		frames += 1
		if not dodged and _boss.get_attack_phase() == BossCombat.Phase.TELEGRAPH \
				and _boss.combat.get_phase_remaining() <= 0.1:
			_player.combat._dodge_cooldown_remaining = 0.0
			stamina_before = _player.combat.get_stamina()
			_player._on_dodge_pressed()
			stamina_after = _player.combat.get_stamina()
			_player.effective_dodge_speed = 0.0
			dodged = true
		if _boss.get_attack_phase() == BossCombat.Phase.ACTIVE and _player.combat.has_iframes():
			covered = true
	_player.effective_dodge_speed = saved
	_record(dodged and is_equal_approx(stamina_before - stamina_after, _combat_data.dodge_stamina_cost) and covered
			and _player.health_component.current_health == _player.health_component.max_health,
		"49) dodged in place: %.0f stamina paid, the i-frames up in its hit window, no damage — the boss asked nothing about the dodge" % (
			stamina_before - stamina_after))
	hitbox.hit_landed.disconnect(counter)
	_player.hurtbox.set_invulnerable(true)
	await _wait(0.5)

	# 51) the heavy, landed in its telegraph: the resistance lets it through.
	_place_player(_boss, 1.6)
	_only(_boss, heavy)
	await _until(func() -> bool: return _boss.get_attack_phase() == BossCombat.Phase.TELEGRAPH, 120)
	ended_from = _ended.size()
	_last_player_hit = null
	_strike(_combat_data.heavy_combo, 0)
	await _until(func() -> bool: return _last_player_hit != null, 60)
	var cut: Dictionary = _ended[_ended.size() - 1] if _ended.size() > ended_from else {}
	_record(_boss.is_staggered() and cut.get("attack") == heavy and cut.get("completed") == false
			and not hitbox.is_active() and not marker.visible,
		"51) the player's heavy (60 against its 60) in the telegraph cuts the Heavy Slam off: staggered, no hit window, the marker gone")
	await _until(func() -> bool: return not _boss.is_staggered(), 120)
	await _until(func() -> bool: return _player.combat.get_state() == PlayerCombat.State.IDLE, 120)


## 52) a boss that dies in the telegraph never swings.
func _special_death_tests() -> void:
	# The main boss held where it is meanwhile, so it cannot walk into this.
	await _until(func() -> bool: return _boss.get_attack_phase() == BossCombat.Phase.NONE, 240)
	_boss.set_physics_process(false)
	var boss: DungeonBoss = _spawn_boss(Vector3(-20, 0.1, -6))
	boss.start_encounter()
	await _wait(boss.intro_duration + 0.1)
	var health: HealthComponent = boss.health_component
	boss.hurtbox.receive_hit(_crafted(health.max_health * 0.55, 0.0, _stand_in))
	await _until(func() -> bool: return boss.get_phase_index() == 1 and not boss.is_in_transition(), 180)
	var heavy: BossAttack = _attack(&"boss_heavy_slam")
	_place_player(boss, 2.5)
	_only(boss, heavy)
	var winding: bool = await _until(func() -> bool: return boss.get_attack_phase() == BossCombat.Phase.TELEGRAPH, 120)
	boss.hurtbox.receive_hit(_crafted(10000.0, 0.0, _stand_in))
	var swung: bool = false
	var frames: int = 0
	while frames < 90:
		swung = swung or boss.get_attack_phase() == BossCombat.Phase.ACTIVE or boss.combat.is_hit_window_open()
		await get_tree().physics_frame
		frames += 1
	_record(winding and boss.get_state() == DungeonBoss.State.DEAD and not swung
			and not boss.combat.get_marker(heavy).visible and boss.get_current_attack() == null,
		"52) killed in the Heavy Slam's telegraph: the attack is cancelled — no hit window ever, the marker gone")
	boss.queue_free()
	_boss.set_physics_process(true)
	await _frames(2)


# --- the enrage -------------------------------------------------------------------------------------------------

func _enrage_tests() -> void:
	var health: HealthComponent = _boss.health_component
	var enrage: BossEnrageData = _boss.data.enrage
	# The player went off to the spawned boss, out of the lock's reach: lock on
	# again, to follow the lock through the enrage.
	_place_player(_boss, 2.0)
	_aim_at(_boss)
	await _frames(2)
	if _player.targeting.get_target() != _boss:
		_press(&"target_lock")
		await _frames(2)
	_boss.hurtbox.receive_hit(_crafted(health.current_health - health.max_health * 0.3, 0.0, _stand_in))
	await _frames(2)
	_record(not _boss.is_enraging() and not _boss.is_enraged() and not _events.has("enrage_started"),
		"24c) at 30% nothing: the enrage waits for its 25%")

	# 38/48) a critical takes it under 25%: the enrage, with the hit stop running.
	await _until(func() -> bool: return _boss.get_attack_phase() == BossCombat.Phase.NONE, 240)
	_boss.set_physics_process(false)
	_place_player(_boss, 1.6)
	health.current_health = health.max_health * 0.26
	_combat_data.critical_chance = 1.0
	_last_player_hit = null
	await _swing(_combat_data.light_combo, 0)
	_combat_data.critical_chance = 0.0
	var critical: bool = _last_player_hit != null and _last_player_hit.is_critical
	_boss.set_physics_process(true)
	_record(critical and _boss.is_enraging() and not _boss.is_enraged() and _events.count("enrage_started") == 1,
		"38) a critical Light 1 (%.0f) from 26%% to %.1f%%: the enrage's beat begins, once" % [
			_last_player_hit.amount if _last_player_hit != null else 0.0, 100.0 * health.current_health / health.max_health])
	_record(_bar.is_banner_showing() and _bar.get_banner_text() == _bar.enrage_text,
		"30/42a) the bar calls it out: '%s' — the same bar, the same pool" % _bar.get_banner_text())

	# 31/35) the beat: no attack, no hitbox, no stagger — but it takes damage.
	var before: float = health.current_health
	var ratio: float = _bar.get_ratio()
	_boss.hurtbox.receive_hit(_crafted(10.0, 1000.0, _stand_in))
	await _frames(2)
	_record(health.current_health == before - 10.0 and _bar.get_ratio() < ratio and not _boss.is_staggered()
			and _boss.is_enraging(),
		"35/36) the enrage beat takes damage but no stagger — it is not interruptible, and not invulnerable")
	var at: Vector3 = _boss.global_position
	var clean: bool = true
	var evaluations: int = _boss.combat.get_evaluation_count()
	while _boss.is_enraging():
		clean = clean and _boss.get_current_attack() == null and not _boss.combat.is_hit_window_open()
		await get_tree().physics_frame
	_record(clean and _boss.global_position.distance_to(at) < 0.1 and _boss.combat.get_evaluation_count() == evaluations,
		"31) for the whole beat: no attack, no hitbox, no movement, no choice weighed")
	_record(_boss.is_enraged() and _events.count("enraged") == 1 and _events.find("enrage_started") < _events.find("enraged")
			and is_equal_approx(Engine.time_scale, 1.0),
		"25/48) then it is enraged — once — and the hit stop left the time scale where it was")

	var phase_2: BossPhaseData = _boss.data.phases[1]
	var expected: float = _boss.data.movement_speed * phase_2.movement_speed_multiplier * enrage.movement_speed_multiplier
	_record(is_equal_approx(_boss.movement_speed, expected) and is_equal_approx(_boss.combat.get_cooldown_scale(), 0.85 * 0.85)
			and is_equal_approx(_boss.combat.get_recovery_scale(), 0.85),
		"27/54) base -> phase -> enrage: speed 3.2 x 1.19 x 1.1 = %.3f, cooldowns x%.4f (0.85 x 0.85), recovery x0.85 untouched" % [
			_boss.movement_speed, _boss.combat.get_cooldown_scale()])
	_boss._apply_modifiers()
	_record(is_equal_approx(_boss.movement_speed, expected) and is_equal_approx(_boss.combat.get_cooldown_scale(), 0.85 * 0.85),
		"22b) applied again, the enrage does not stack on itself")
	_record(is_equal_approx(enrage.movement_speed_multiplier, 1.1) and is_equal_approx(enrage.cooldown_multiplier, 0.85)
			and is_equal_approx(_attack(&"boss_heavy_slam").cooldown, 8.0),
		"53b) the enrage's data and the attacks' cooldowns are untouched")
	_record(_bar.get_phase_text() == "FASE 2 — FURIA" and _player.targeting.get_target() == _boss and _indicator.is_showing()
			and _boss.combat._resting_color == enrage.body_color and _boss.mesh_instance.get_surface_override_material(0).emission_enabled,
		"30/41c/42b) enraged: the bar reads '%s', the lock holds, the body keeps the enrage's colour and glow" % _bar.get_phase_text())

	# 90) no rollback, no second enrage.
	health.heal(health.max_health)
	await _frames(2)
	_boss.hurtbox.receive_hit(_crafted(health.current_health - health.max_health * 0.2, 0.0, _stand_in))
	await _frames(2)
	_record(_boss.is_enraged() and not _boss.is_enraging() and _events.count("enrage_started") == 1
			and _boss.get_phase_index() == 1,
		"26/90) healed back to full and hurt below 25% again: still enraged, still phase 2, no second enrage")


## 91) enraged: the same readable attacks, more often.
func _enraged_combat_tests() -> void:
	_player.hurtbox.set_invulnerable(true)
	# _only() held the other attacks back with long cooldowns; a real fight has
	# none of those.
	_boss.combat.clear_cooldowns()
	var pool: Array[BossAttack] = _boss.data.phases[1].attacks
	var from: int = _started.size()
	var starts: Dictionary = {}
	var gaps_ok: bool = true
	var clock: float = 0.0
	var seen: int = from
	var evaluations_at_start: Dictionary = {}
	var steady: bool = true
	while clock < 12.0:
		_player.global_position = _boss.global_position + Vector3(0, 0, -2.0)
		await get_tree().physics_frame
		clock += DT
		while seen < _started.size():
			var attack: BossAttack = _started[seen]
			seen += 1
			if starts.has(attack) and clock - starts[attack] < _boss.combat.get_effective_cooldown(attack) - 0.05:
				gaps_ok = false
			starts[attack] = clock
			evaluations_at_start[attack] = _boss.combat.get_evaluation_count()
		var current: BossAttack = _boss.get_current_attack()
		if current != null and evaluations_at_start.has(current) \
				and evaluations_at_start[current] != _boss.combat.get_evaluation_count():
			steady = false
	var used: Array[BossAttack] = _started.slice(from)
	var outside: bool = false
	for attack in used:
		outside = outside or not pool.has(attack)
	_record(used.size() >= 6 and not outside and gaps_ok and steady,
		"91) enraged, it fights from phase 2's pool (%d attacks in 12 s), no attack before its shortened cooldown, no choice weighed mid-attack" % used.size())


## 92) dying enraged, mid-attack.
func _enraged_death_tests() -> void:
	await _until(func() -> bool: return _boss.get_attack_phase() == BossCombat.Phase.TELEGRAPH, 240)
	var deaths: int = _deaths[0]
	_boss.hurtbox.receive_hit(_crafted(10000.0, 0.0, _stand_in))
	await get_tree().physics_frame
	var live: bool = false
	var frames: int = 0
	while frames < 60:
		live = live or _boss.combat.is_hit_window_open()
		await get_tree().physics_frame
		frames += 1
	_record(_boss.get_state() == DungeonBoss.State.DEAD and _deaths[0] == deaths + 1 and not live
			and _boss.get_current_attack() == null and _boss.get_target() == null,
		"92a) killed enraged in a telegraph: DEAD, reported once, no hit window, no target")
	_record(not _player.targeting.is_locked() and not _indicator.is_showing() and not _bar.is_showing(),
		"41d/92b) the lock and the ring let go, the bar hides")


# --- thresholds, on fresh bosses ----------------------------------------------------------------------------------

func _threshold_tests() -> void:
	# 55/56) a new boss starts from the baseline, whatever the last one reached.
	var fresh: DungeonBoss = _spawn_boss(Vector3(20, 0.1, -6))
	var baseline: bool = fresh.get_phase_index() == -1 and not fresh.is_enraged()
	fresh.start_encounter()
	var clean: bool = true
	for attack in fresh.get_attacks():
		clean = clean and fresh.combat.get_cooldown(attack) == 0.0
	_record(baseline and fresh.get_phase_index() == 0 and clean and is_equal_approx(fresh.movement_speed, 3.2)
			and is_equal_approx(fresh.combat.get_cooldown_scale(), 1.0) and is_equal_approx(fresh.combat.get_recovery_scale(), 1.0),
		"55/56) a new boss on the same BossData: phase 1, not enraged, clean cooldowns, baseline speed and pace")

	# 39) one blow from full to 20%: the phase, then the enrage — never both at once.
	var escalation: Array[String] = []
	var deaths: Array[int] = [0]
	_watch(fresh, escalation, deaths)
	var overlap: Array[bool] = [false]
	fresh.state_changed.connect(func(_from: DungeonBoss.State, to: DungeonBoss.State) -> void:
		if to == DungeonBoss.State.ENRAGING and escalation.has("transition_1") and not escalation.has("phase_1"):
			overlap[0] = true)
	await _wait(fresh.intro_duration + 0.1)
	var health: HealthComponent = fresh.health_component
	fresh.hurtbox.receive_hit(_crafted(health.max_health * 0.8, 0.0, _stand_in))
	await _frames(2)
	var first: bool = fresh.is_in_transition() and not fresh.is_enraging() and escalation == ["transition_1"]
	await _until(func() -> bool: return not fresh.is_in_transition(), 180)
	var then: bool = fresh.is_enraging()
	await _until(func() -> bool: return fresh.is_enraged(), 120)
	_record(first and then and not overlap[0] and escalation == ["transition_1", "phase_1", "enrage_started", "enraged"],
		"39) one blow from full to 20%%: the phase 2 transition, then at once the enrage — in that order, never together: %s" % [escalation])
	fresh.queue_free()

	# 40) the same blow, lethal: a death and nothing else.
	var lethal: DungeonBoss = _spawn_boss(Vector3(20, 0.1, 6))
	var lethal_log: Array[String] = []
	var lethal_deaths: Array[int] = [0]
	_watch(lethal, lethal_log, lethal_deaths)
	lethal.start_encounter()
	lethal.hurtbox.receive_hit(_crafted(lethal.health_component.max_health * 2.0, 0.0, _stand_in))
	await _frames(3)
	_record(lethal.get_state() == DungeonBoss.State.DEAD and lethal_log.is_empty() and lethal_deaths[0] == 1
			and not lethal.is_enraged() and lethal.get_phase_index() == 0,
		"40) a lethal blow through both thresholds: DEAD — no transition, no enrage, one death")
	lethal.queue_free()

	# 34) in phase 2, a lethal blow through the enrage's threshold: no enrage first.
	var late: DungeonBoss = _spawn_boss(Vector3(-20, 0.1, 6))
	var late_log: Array[String] = []
	var late_deaths: Array[int] = [0]
	_watch(late, late_log, late_deaths)
	late.start_encounter()
	late.hurtbox.receive_hit(_crafted(late.health_component.max_health * 0.7, 0.0, _stand_in))
	await _until(func() -> bool: return late.get_phase_index() == 1 and not late.is_in_transition(), 180)
	late.hurtbox.receive_hit(_crafted(late.health_component.max_health, 0.0, _stand_in))
	await _frames(3)
	_record(late.get_state() == DungeonBoss.State.DEAD and not late_log.has("enrage_started") and late_deaths[0] == 1,
		"34) at 30%% in phase 2, a lethal blow through 25%%: DEAD, no enrage: %s" % [late_log])
	late.queue_free()
	await _frames(2)


## M13 readiness: the boss with its placeholder body swapped for a bare model
## under MeshRoot — the framework does not need the mesh: it fights, escalates
## and dies, its hitboxes, hurtbox and anchor its own.
func _model_swap_tests() -> void:
	var boss: DungeonBoss = BOSS_SCENE.instantiate() as DungeonBoss
	var mesh: Node = boss.get_node("VisualRoot/MeshRoot/MeshInstance3D")
	mesh.get_parent().remove_child(mesh)
	mesh.free()
	var model: Node3D = Node3D.new()
	model.name = "Model"
	boss.get_node("VisualRoot/MeshRoot").add_child(model)
	boss.combat_enabled = false
	boss.position = Vector3(0, 0.1, 12)
	add_child(boss)
	var escalation: Array[String] = []
	var deaths: Array[int] = [0]
	_watch(boss, escalation, deaths)
	boss.start_encounter()
	_player.hurtbox.set_invulnerable(true)
	var fought: bool = await _until(func() -> bool:
		_player.global_position = boss.global_position + Vector3(0, 0, -2.0)
		return boss.combat.get_started_count() >= 2, 600)
	boss.hurtbox.receive_hit(_crafted(boss.health_component.max_health * 0.8, 0.0, _stand_in))
	await _until(func() -> bool: return boss.is_enraged(), 300)
	var anchored: bool = boss.get_target_point().distance_to(boss.target_anchor.global_position) < 0.001
	boss.hurtbox.receive_hit(_crafted(10000.0, 0.0, _stand_in))
	await _frames(3)
	_record(boss.mesh_instance == null and fought and escalation == ["transition_1", "phase_1", "enrage_started", "enraged"]
			and anchored and boss.get_state() == DungeonBoss.State.DEAD and deaths[0] == 1,
		"M13) the boss with its placeholder body swapped for a bare model: it attacks, reaches phase 2 and the enrage, keeps its anchor and dies")
	boss.queue_free()
	await _frames(2)


# --- helpers ----------------------------------------------------------------------------------------------------------

func _watch(boss: DungeonBoss, escalation: Array[String], deaths: Array[int]) -> void:
	boss.phase_transition_started.connect(func(to: int) -> void: escalation.append("transition_%d" % to))
	boss.phase_changed.connect(func(i: int) -> void:
		if i > 0:
			escalation.append("phase_%d" % i))
	boss.enrage_started.connect(func() -> void: escalation.append("enrage_started"))
	boss.enraged.connect(func() -> void: escalation.append("enraged"))
	boss.enemy_died.connect(func(_c: RoomCombatant) -> void: deaths[0] += 1)


func _spawn_boss(at: Vector3) -> DungeonBoss:
	var boss: DungeonBoss = BOSS_SCENE.instantiate() as DungeonBoss
	boss.combat_enabled = false
	boss.position = at
	add_child(boss)
	return boss


func _phase(id: StringName, threshold: float, attacks: Array[BossAttack]) -> BossPhaseData:
	var phase: BossPhaseData = BossPhaseData.new()
	phase.id = id
	phase.health_threshold = threshold
	phase.attacks = attacks.duplicate()
	return phase


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


func _place_player(boss: DungeonBoss, distance: float) -> void:
	_player.global_position = boss.global_position + Vector3(0, 0, -distance)
	boss.visual_root.rotation.y = 0.0


func _heal_player() -> void:
	_player.health_component.current_health = _player.health_component.max_health
	_player.health_component.is_dead = false
	_player.hurtbox.set_invulnerable(false)


func _strike(chain: Array[AttackData], index: int) -> void:
	_aim_at(_boss)
	_player.combat.reset()
	_player.combat._start_attack(chain, index)


func _swing(chain: Array[AttackData], index: int) -> void:
	_strike(chain, index)
	var frames: int = 0
	while _player.combat.get_state() != PlayerCombat.State.IDLE and frames < 180:
		await get_tree().physics_frame
		frames += 1


func _aim_at(target: Node3D) -> void:
	var to: Vector3 = target.global_position - _player.global_position
	to.y = 0.0
	if to.length_squared() > 0.0001:
		_player.camera_rig.rotation.y = atan2(-to.x, -to.z)


func _press(action: StringName) -> void:
	var event: InputEventAction = InputEventAction.new()
	event.action = action
	event.pressed = true
	_player._unhandled_input(event)


func _crafted(amount: float, stagger: float, source: Node) -> DamageInfo:
	var info: DamageInfo = DamageInfo.new(amount, source, &"test_hit")
	info.stagger_power = stagger
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
