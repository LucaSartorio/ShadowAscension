extends SceneTree

## M11.9 — combat feedback through the whole game, and the stress run that
## closes M11 (Combat System 2.0).
##
##   godot --headless --path . --script res://tests/core/m11_feedback_run.gd
##
## Menu -> New Game -> hub: a training dummy hit and felt, a shadow summoned ->
## gate -> dungeon: the player dies locked on, mid-swing, inside a hit stop —
## the game is let go at once and the dungeon restarts clean; it dies again
## mid-dodge, the same -> room one: the light combo and the heavy, each hit
## felt harder; a heavy through two enemies, one stop; a critical and its mark;
## a lock held through the stops; stamina empty, just enough, full; a menu
## opened in the middle of a stop -> room two: the game's rate with every enemy
## and the shadow fighting; the player and the shadow racing for one kill, the
## shadow's hits holding and shaking nothing -> the boss fought, its swing
## dodged, killed: its last blow opens the run summary on a game at full speed
## -> hub -> a second dungeon, shorter, to its boss -> hub: the same number of
## nodes as the first time, nothing orphaned, nothing held.
##
## Attacks and dodges go in as the devices send them (the camera rig's attack
## intents, InputEventActions to the player's handler), except where a single
## attack is started on its own.

const BOOT: String = "res://Main.tscn"
const HUB: String = "res://scenes/core/hub.tscn"
const DT: float = 1.0 / 60.0
const ROOM_ANCHORS: Array[Vector3] = [
	Vector3(0, 0.1, -13), Vector3(0, 0.1, -33), Vector3(0, 0.1, -53)
]
const EXIT_POS: Vector3 = Vector3(0, 0.1, -65)
const STRIKE_RANGE: float = 1.6
const DODGE_LEAD: float = 0.15
## The ticks counted for the game's rate, and the physics time one may take.
const RATE_TICKS: int = 120
const PHYSICS_BUDGET: float = 0.008

## Criticals are random (M11.7) and this run checks exact damage, so they are
## off for its whole run except where it turns one on: every player here reads
## this one cached instance of the combat data.
var _no_crits: PlayerCombatData = preload("res://resources/characters/player_combat.tres")
var _shadow_data: ShadowData = preload("res://resources/shadows/basic_melee_shadow.tres")
var _state: Node = null
var _pass: int = 0
var _fail: int = 0
## Every hit of the player's that counted, with what the feedback had made of it
## the moment it was heard.
var _accepted: Array[Dictionary] = []
## The hub's node count each time the run comes back to it.
var _hub_nodes: Array[int] = []


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
	await _phase_deaths()
	await _phase_room_one()
	await _phase_room_two()
	await _phase_boss(1)
	await _phase_out_to_hub(1)
	await _phase_into_dungeon(2)
	await _phase_second_run()
	await _phase_boss(2)
	await _phase_out_to_hub(2)
	print("[SUMMARY] passed=%d failed=%d" % [_pass, _fail])
	await _pause(0.3)
	quit()


# --- the hub -----------------------------------------------------------------------------------------

func _phase_hub() -> void:
	var p: Player = _player()
	_watch(p)
	var shadow: ShadowInstance = p.shadows.add_shadow(_shadow_data)
	p.shadow_summoner.summon(shadow.instance_id)
	await _pause(0.4)
	p.shadow_commander.set_mode(BasicMeleeShadow.CommandMode.FOLLOW)
	var dummy: TrainingDummy = current_scene.get_node("TrainingDummy1")
	p.global_position = Vector3(dummy.global_position.x, 0.1, dummy.global_position.z + 1.4)
	p.camera_rig.rotation.y = 0.0
	await _frames(4)
	var stops: int = p.combat_feedback.get_hit_stop_count()
	var first: int = _accepted.size()
	await _single_light(p)
	var hit: Dictionary = _accepted[first] if _accepted.size() > first else {}
	_record(_accepted.size() == first + 1 and p.combat_feedback.get_hit_stop_count() == stops + 1
			and hit.get("shake", 0.0) == p.combat.data.light_combo[0].camera_shake_strength
			and not p.targeting.is_locked() and _idle(p),
		"H1) the hub: Light 1 on a training dummy is felt — one stop, one shake — and the game runs on at full speed")


func _phase_into_dungeon(run: int) -> void:
	var p: Player = _player()
	var gate: DungeonGate = current_scene.get_node("DungeonGate")
	p.global_position = gate.global_position
	await _pause(0.4)
	gate.activate()
	await _pause(1.6)
	var fresh: Player = _player()
	_watch(fresh)
	_record(current_scene is DungeonController and _idle(fresh) and _feedbacks() == 1
			and fresh.attack_hitbox.hit_accepted.get_connections().size() == 2
			and fresh.combat.attack_started.get_connections().size() == 2,
		"G%d) dungeon %d: one feedback, idle, listening once (plus this run); the game at full speed" % [run, run])


# --- deaths: locked on, mid-swing, in a stop; mid-dodge ------------------------------------------------

func _phase_deaths() -> void:
	var dungeon: DungeonController = current_scene as DungeonController
	var p: Player = dungeon.get_player()
	p.hurtbox.set_invulnerable(true)
	p.global_position = ROOM_ANCHORS[0]
	await _pause(0.8)
	var enemy: BasicMeleeEnemy = dungeon.get_rooms()[0].get_enemies()[0] as BasicMeleeEnemy
	for other in dungeon.get_rooms()[0].get_enemies():
		_park(other, other.global_position + Vector3(0, 0, -6))
	p.global_position = ROOM_ANCHORS[0]
	p.camera_rig.rotation.y = 0.0
	_park(enemy, _at(p, 0.0, 1.5))
	await _lock(p)
	var locked: bool = p.targeting.get_target() == enemy
	p.combat.reset()
	p.camera_rig.attack_heavy_pressed.emit()
	await _until(func() -> bool: return p.combat_feedback.is_hit_stop_active(), 2.0)
	var in_stop: bool = p.combat_feedback.is_hit_stop_active() and Engine.time_scale == 0.0 and p.camera_rig.is_shaking()
	p.health_component.take_damage(DamageInfo.new(1000000.0))
	var let_go: bool = Engine.time_scale == 1.0 and not p.combat_feedback.is_hit_stop_active() \
		and not p.camera_rig.is_shaking() and p.camera_rig.get_shake_offset() == Vector2.ZERO \
		and not p.targeting.is_locked() and p.combat.get_state() == PlayerCombat.State.DEAD \
		and not p.attack_hitbox.is_active()
	_record(locked and in_stop and let_go,
		"D1) killed locked on, mid-heavy, inside its hit stop: the game is let go that moment — full speed, no shake, no lock, no swing")
	await _restarted(dungeon)
	var again: Player = _player()
	_record(_idle(again) and again.combat.get_state() == PlayerCombat.State.IDLE and not again.targeting.is_locked()
			and _feedbacks() == 1 and int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)) == 0,
		"D2) the dungeon restarts with a player at full speed, idle, unlocked, one feedback, nothing orphaned")

	dungeon = current_scene as DungeonController
	again.hurtbox.set_invulnerable(true)
	await _frames(3)
	_press(again, &"dodge")
	await _until(func() -> bool: return again.combat.get_dodge_phase() == PlayerCombat.DodgePhase.INVULNERABLE, 1.0)
	var dodging: bool = again.combat.is_dodging()
	again.health_component.take_damage(DamageInfo.new(1000000.0))
	var dead_clean: bool = dodging and not again.combat.is_dodging() and not again.combat.has_iframes() \
		and not again.hurtbox._invulnerable_reasons.has(PlayerCombat.IFRAMES_REASON) and Engine.time_scale == 1.0
	await _restarted(dungeon)
	var third: Player = _player()
	_record(dead_clean and _idle(third) and third.combat.get_stamina() == third.combat.get_max_stamina()
			and _feedbacks() == 1 and int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)) == 0,
		"D3) killed mid-dodge, in its i-frames: nothing of the dodge outlives it, and the restart is clean again")


# --- room one: every attack felt ------------------------------------------------------------------------

func _phase_room_one() -> void:
	var dungeon: DungeonController = current_scene as DungeonController
	var p: Player = dungeon.get_player()
	var feedback: PlayerCombatFeedback = p.combat_feedback
	p.hurtbox.set_invulnerable(true)
	p.global_position = ROOM_ANCHORS[0]
	await _pause(0.8)
	var room: RoomController = dungeon.get_rooms()[0]
	var a: BasicMeleeEnemy = room.get_enemies()[0] as BasicMeleeEnemy
	var b: BasicMeleeEnemy = room.get_enemies()[1] as BasicMeleeEnemy
	p.global_position = ROOM_ANCHORS[0]
	p.camera_rig.rotation.y = 0.0
	_park(a, _at(p, 0.0, 1.5))
	_park(b, _at(p, 60.0, 8.0))
	await _frames(3)

	# The light combo through the real button, and the heavy.
	var stops: int = feedback.get_hit_stop_count()
	var first: int = _accepted.size()
	await _light_combo(p)
	var combo: Array[Dictionary] = _accepted.slice(first)
	var amounts: Array[float] = []
	var shakes: Array[float] = []
	var lengths: Array[float] = []
	for hit in combo:
		amounts.append(hit["amount"])
		shakes.append(hit["shake"])
		lengths.append(hit["stop"])
	_record(amounts == [20.0, 25.0, 35.0] and feedback.get_hit_stop_count() == stops + 3
			and shakes[0] < shakes[1] and shakes[1] < shakes[2] and lengths[0] <= lengths[1] and lengths[1] < lengths[2],
		"R1) the light combo lands %s — damage untouched — each hit held longer %s and shaken harder %s" % [amounts, lengths, shakes])

	# The heavy through both, the first one's killing blow among them.
	_park(a, _at(p, -20.0, 1.4))
	_park(b, _at(p, 20.0, 1.4))
	await _frames(3)
	stops = feedback.get_hit_stop_count()
	first = _accepted.size()
	await _heavy(p)
	var heavy: Array[Dictionary] = _accepted.slice(first)
	_record(heavy.size() == 2 and feedback.get_hit_stop_count() == stops + 1 and a.has_died()
			and heavy[0]["shake"] > shakes[2] and heavy[0]["stop"] > lengths[2],
		"R2) the heavy through two enemies, killing one: two hits, one stop, harder than any light")

	# A critical, and its mark.
	await _pause(0.3)
	_park(b, _at(p, 0.0, 1.5))
	await _frames(3)
	_no_crits.critical_chance = 1.0
	first = _accepted.size()
	p.combat.reset()
	p.combat._start_attack(p.combat.data.light_combo, 0)
	await _until(func() -> bool: return _accepted.size() > first, 2.0)
	var marked: bool = feedback.get_critical_mark_count() == 1
	await _until(func() -> bool: return not p.combat.is_attacking(), 2.0)
	_no_crits.critical_chance = 0.0
	var crit: Dictionary = _accepted[first] if _accepted.size() > first else {}
	_record(crit.get("critical", false) and crit.get("amount", 0.0) == 30.0 and marked
			and is_equal_approx(crit.get("stop", 0.0), 0.04),
		"R3) a critical Light 1: 30 damage, its stop 0.04 s instead of 0.025, and a mark over the target")

	# Locked on through the stops and the shakes.
	await _lock(p)
	var rig_yaw: float = p.camera_rig.rotation.y
	var held: Array[bool] = [true]
	await _single_light(p, null, func() -> void:
		held[0] = held[0] and p.targeting.get_target() == b and p.camera_rig.rotation.y == rig_yaw)
	_record(held[0] and p.targeting.get_target() == b,
		"R4) locked on: the stop and the shake move neither the lock nor the camera's view")

	# A menu opened in the middle of a stop.
	var menu: PlayerStatsMenu = dungeon.get_node("PlayerStatsMenu")
	p.combat.reset()
	p.camera_rig.attack_heavy_pressed.emit()
	await _until(func() -> bool: return feedback.is_hit_stop_active(), 2.0)
	menu.open()
	var paused_free: bool = paused and Engine.time_scale == 1.0 and not feedback.is_hit_stop_active() \
		and p.camera_rig.get_shake_offset() == Vector2.ZERO
	await create_timer(0.3).timeout
	menu.close()
	await _until(func() -> bool: return not p.combat.is_attacking(), 2.0)
	_record(paused_free and not paused and b.has_died() and room.is_cleared() and _idle(p),
		"R5) the stats menu opened mid-stop: the stop ends as the game pauses; closed, the heavy finishes the kill and the room clears")

	# Stamina: empty, just enough, full.
	p.combat.try_spend_stamina(p.combat.get_stamina())
	_press(p, &"dodge")
	var refused: bool = not p.combat.is_dodging() and p.combat.get_stamina() == 0.0
	p.combat.restore_stamina(p.combat.data.dodge_stamina_cost)
	_press(p, &"dodge")
	var just_enough: bool = p.combat.is_dodging() and p.combat.get_stamina() == 0.0
	await _until(func() -> bool: return p.combat.get_stamina() == p.combat.get_max_stamina(), 6.0)
	_record(refused and just_enough and p.combat.get_stamina() == p.combat.get_max_stamina(),
		"R6) stamina: empty refuses the dodge, exactly its cost pays for one, and it all comes back")


# --- room two: the rate, and a kill race with the shadow ------------------------------------------------

func _phase_room_two() -> void:
	var dungeon: DungeonController = current_scene as DungeonController
	var p: Player = dungeon.get_player()
	var feedback: PlayerCombatFeedback = p.combat_feedback
	var node: BasicMeleeShadow = p.shadow_summoner.get_active_node()
	if node == null:
		node = p.shadow_summoner.summon(p.shadows.get_shadows()[0].instance_id)
	p.global_position = ROOM_ANCHORS[1]
	await _pause(0.6)
	var room: RoomController = dungeon.get_rooms()[1]
	var enemies: Array = room.get_enemies()
	# Tough enough to outlast the measurement: the kill comes after it.
	for enemy in enemies:
		(enemy as BasicMeleeEnemy).health_component.set_max_health(1000.0)
		(enemy as BasicMeleeEnemy).health_component.current_health = 1000.0
	node.global_position = p.global_position + Vector3(1.5, 0, 0)
	node.set_manual_target(enemies[1])

	# Every enemy of the room at the player, the shadow at one of them, the
	# player's own light combo going: the game keeps its rate.
	var physics: float = 0.0
	var worst: float = 0.0
	var started: int = Time.get_ticks_usec()
	for i in RATE_TICKS:
		if not p.combat.is_attacking():
			p.camera_rig.attack_light_pressed.emit()
		await physics_frame
		var t: float = Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)
		physics += t
		worst = maxf(worst, t)
	var wall: float = float(Time.get_ticks_usec() - started) / 1000000.0
	var average: float = physics / RATE_TICKS
	_record(absf(wall - RATE_TICKS * DT) < 0.25 and average < PHYSICS_BUDGET,
		"FP1) %d ticks with three enemies, the shadow and the player all fighting took %.2f s (%.2f expected): %.2f ms of physics a tick on average, %.2f ms at worst" % [
			RATE_TICKS, wall, RATE_TICKS * DT, average * 1000.0, worst * 1000.0])

	# The race: the player and the shadow on one enemy with little left.
	var target: BasicMeleeEnemy = enemies[0] as BasicMeleeEnemy
	for other in enemies:
		if other != target:
			_park(other, other.global_position + Vector3(10, 0, 0))
	await _until(func() -> bool: return not p.combat.is_attacking(), 2.0)
	_park(target, _at(p, 0.0, 1.5))
	target.set_combat_enabled(true)
	target.health_component.current_health = 45.0
	node.global_position = target.global_position + Vector3(1.2, 0, 0)
	node.set_manual_target(target)
	await _frames(2)
	var stops: int = feedback.get_hit_stop_count()
	var reward: int = target.get_xp_reward()
	var player_before: int = p.progression.get_total_xp()
	var shadow_before: int = _shadow_total_xp(node.instance)
	var shadow_hits: Array[int] = [0]
	var on_shadow_hit: Callable = func(_t: Node, _h: DamageInfo) -> void: shadow_hits[0] += 1
	node.attack_hitbox.hit_accepted.connect(on_shadow_hit)
	var felt_swings: int = 0
	var budget: int = 12
	while not target.has_died() and budget > 0:
		budget -= 1
		var before: int = _accepted.size()
		await _single_light(p, target)
		felt_swings += 1 if _accepted.size() > before else 0
	await _pause(0.5)
	if is_instance_valid(node):
		node.attack_hitbox.hit_accepted.disconnect(on_shadow_hit)
	var gained: int = (p.progression.get_total_xp() - player_before) + (_shadow_total_xp(node.instance) - shadow_before)
	var killer: Node = target.get_killer()
	_record(target.has_died() and (killer == p or killer == node) and gained == reward,
		"KR1) the player and the shadow race for one kill: %s takes it, %d XP paid once" % [
			"the player" if killer == p else "the shadow", gained])
	_record(feedback.get_hit_stop_count() - stops == felt_swings and Engine.time_scale == 1.0,
		"KR2) %d stops for the player's %d swings that counted — the shadow's hits (%d) held and shook nothing" % [
			feedback.get_hit_stop_count() - stops, felt_swings, shadow_hits[0]])


# --- the boss -------------------------------------------------------------------------------------------

func _phase_boss(run: int) -> void:
	var dungeon: DungeonController = current_scene as DungeonController
	var p: Player = dungeon.get_player()
	var feedback: PlayerCombatFeedback = p.combat_feedback
	p.health_component.heal(p.health_component.max_health)
	p.hurtbox.set_invulnerable(true)
	p.global_position = ROOM_ANCHORS[2]
	var boss: DungeonBoss = dungeon.get_rooms()[2].get_enemies()[0] as DungeonBoss
	var bar: BossHealthBar = dungeon.get_node("BossHealthBar")
	await _until(func() -> bool: return boss.combat_enabled and bar.is_showing(), 6.0)
	_stick(p, boss)
	await _lock(p)

	if run == 1:
		# Its swing, dodged while locked.
		p.hurtbox.set_invulnerable(false)
		var hp_before: float = p.health_component.current_health
		var coming: bool = await _until(func() -> bool:
			_stick(p, boss)
			return boss.get_attack_phase() == DungeonBoss.AttackPhase.STARTUP and boss._phase_timer <= DODGE_LEAD, 10.0)
		var speed: float = p.effective_dodge_speed
		p.effective_dodge_speed = 0.0
		_press(p, &"dodge")
		await _until(func() -> bool: return not p.combat.is_dodging(), 1.0)
		p.effective_dodge_speed = speed
		p.hurtbox.set_invulnerable(true)
		_record(coming and p.health_component.current_health == hp_before and p.targeting.get_target() == boss,
			"B1.1) the boss swings at the locked-on player, who dodges it and takes nothing")

	var stops: int = feedback.get_hit_stop_count()
	var hp: float = boss.health_component.current_health
	await _single_light(p, boss)
	await _heavy(p, boss)
	_record(hp - boss.health_component.current_health == 60.0 and feedback.get_hit_stop_count() == stops + 2
			and p.targeting.get_target() == boss,
		"B%d.2) the boss, locked on, takes Light 1 and the heavy for 60 — damage untouched — with a stop each" % run)

	# The killing blow completes the dungeon, and the run summary pauses it.
	boss.health_component.current_health = 40.0
	stops = feedback.get_hit_stop_count()
	var marks: int = feedback.get_critical_mark_count()
	p.combat.reset()
	_stick(p, boss)
	p.camera_rig.attack_heavy_pressed.emit()
	await _until(func() -> bool:
		_stick(p, boss)
		return boss.has_died(), 3.0)
	var summary: bool = paused
	var at_death: Dictionary = {"scale": Engine.time_scale, "stops": feedback.get_hit_stop_count() - stops,
		"shaking": p.camera_rig.is_shaking(), "offset": p.camera_rig.get_shake_offset(),
		"marks": feedback.get_critical_mark_count() - marks, "locked": p.targeting.is_locked(),
		"hitboxes": boss._hitboxes.any(func(h: Hitbox) -> bool: return h != null and h.is_active())}
	RunSummary.dismiss_open(self)
	await _frames(4)
	_record(summary and at_death["scale"] == 1.0 and at_death["stops"] == 0 and not at_death["shaking"]
			and at_death["offset"] == Vector2.ZERO and at_death["marks"] == 0,
		"B%d.3) the boss's killing blow opens the run summary on a game at full speed: no stop, no shake, no mark, no slow motion" % run)
	_record(not at_death["locked"] and not at_death["hitboxes"] and boss.get_state() == DungeonBoss.State.DEAD
			and dungeon.get_state() == DungeonController.DungeonState.COMPLETED and not paused and _idle(p),
		"B%d.4) and it cleans up: the lock let go, its hitboxes closed, the dungeon complete; dismissed, the game runs on" % run)


func _phase_out_to_hub(run: int) -> void:
	var dungeon: DungeonController = current_scene as DungeonController
	var p: Player = dungeon.get_player()
	p.global_position = EXIT_POS
	await _pause(0.4)
	dungeon.exit_portal.activate()
	await _pause(1.6)
	var hub_player: Player = _player()
	await _pause(0.6)
	_hub_nodes.append(int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)))
	_record(current_scene.scene_file_path == HUB and _idle(hub_player) and _feedbacks() == 1
			and int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)) == 0,
		"O%d) back in the hub: one feedback, idle, the game at full speed, nothing orphaned" % run)
	if run == 2:
		_record(_hub_nodes.size() == 2 and _hub_nodes[0] == _hub_nodes[1],
			"O2.1) the hub holds exactly as many nodes after the second cycle as after the first (%s)" % [_hub_nodes])


# --- the second dungeon, shorter --------------------------------------------------------------------

func _phase_second_run() -> void:
	var dungeon: DungeonController = current_scene as DungeonController
	var p: Player = dungeon.get_player()
	var feedback: PlayerCombatFeedback = p.combat_feedback
	p.hurtbox.set_invulnerable(true)
	p.global_position = ROOM_ANCHORS[0]
	await _pause(0.8)
	var room: RoomController = dungeon.get_rooms()[0]
	var a: BasicMeleeEnemy = room.get_enemies()[0] as BasicMeleeEnemy
	var b: BasicMeleeEnemy = room.get_enemies()[1] as BasicMeleeEnemy
	p.global_position = ROOM_ANCHORS[0]
	p.camera_rig.rotation.y = 0.0
	_park(a, _at(p, -20.0, 1.4))
	_park(b, _at(p, 20.0, 1.4))
	await _frames(3)
	var stops: int = feedback.get_hit_stop_count()
	await _light_combo(p)
	_park(a, _at(p, -20.0, 1.4))
	_park(b, _at(p, 20.0, 1.4))
	await _frames(3)
	await _heavy(p)
	await _pause(0.3)
	_record(a.has_died() and b.has_died() and room.is_cleared() and feedback.get_hit_stop_count() == stops + 4
			and _idle(p),
		"S1) the second dungeon: the light combo and a heavy through both enemies clear the room — one stop a swing")


# --- helpers ------------------------------------------------------------------------------------------

func _player() -> Player:
	return current_scene.get_node("Player") as Player


func _watch(p: Player) -> void:
	p.attack_hitbox.hit_accepted.connect(_on_accepted.bind(p))


func _on_accepted(_target: Node, info: DamageInfo, p: Player) -> void:
	_accepted.append({"amount": info.amount, "critical": info.is_critical,
		"stop": p.combat_feedback._hit_stop_length, "shake": p.camera_rig._shake_strength})


## Nothing held, nothing shaking, nothing marked.
func _idle(p: Player) -> bool:
	return Engine.time_scale == 1.0 and not p.combat_feedback.is_hit_stop_active() \
		and not p.combat_feedback.is_physics_processing() and p.camera_rig.get_shake_offset() == Vector2.ZERO


func _feedbacks() -> int:
	return current_scene.find_children("*", "PlayerCombatFeedback", true, false).size()


## Waits for the dungeon a death restarts.
func _restarted(old: DungeonController) -> void:
	# By id: a lambda may not hold on to a scene that is about to be freed.
	var old_id: int = old.get_instance_id()
	await _until(func() -> bool:
		return not is_instance_id_valid(old_id) and current_scene is DungeonController, 6.0)
	await _pause(0.5)
	_watch(_player())


## The lock button, once the physics space has caught up with whatever was just
## put in place.
func _lock(p: Player) -> void:
	await _frames(2)
	_press(p, &"target_lock")


func _press(p: Player, action: StringName) -> void:
	var event: InputEventAction = InputEventAction.new()
	event.action = action
	event.pressed = true
	p._unhandled_input(event)


## A point `distance` m from the player, `bearing` degrees off the camera's
## view: positive to the right.
func _at(p: Player, bearing: float, distance: float) -> Vector3:
	var forward: Vector3 = _flat(-p.camera_rig.global_basis.z).normalized()
	var right: Vector3 = _flat(p.camera_rig.global_basis.x).normalized()
	var radians: float = deg_to_rad(bearing)
	return p.global_position + (forward * cos(radians) + right * sin(radians)) * distance


func _light_combo(p: Player) -> void:
	p.combat.reset()
	p.camera_rig.attack_light_pressed.emit()
	var frames: int = 0
	while p.combat.is_attacking() and frames < 300:
		await physics_frame
		frames += 1
		if p.combat.get_state() == PlayerCombat.State.RECOVERY and p.combat.get_queued_attack() == null \
				and p.combat.get_combo_index() < 2:
			p.camera_rig.attack_light_pressed.emit()


func _single_light(p: Player, glue: Node3D = null, each_frame: Callable = Callable()) -> void:
	p.combat.reset()
	_stick(p, glue)
	p.combat._start_attack(p.combat.data.light_combo, 0)
	var frames: int = 0
	while p.combat.is_attacking() and frames < 300:
		await physics_frame
		frames += 1
		_stick(p, glue)
		if each_frame.is_valid():
			each_frame.call()


func _heavy(p: Player, glue: Node3D = null) -> void:
	p.combat.reset()
	_stick(p, glue)
	p.camera_rig.attack_heavy_pressed.emit()
	var frames: int = 0
	while p.combat.is_attacking() and frames < 300:
		await physics_frame
		frames += 1
		_stick(p, glue)


## Keeps the player in front of a moving target.
func _stick(p: Player, glue: Node3D) -> void:
	if glue != null and is_instance_valid(glue):
		p.global_position = glue.global_position + Vector3(0, 0, STRIKE_RANGE)


func _until(condition: Callable, budget: float = 3.0) -> bool:
	var waited: float = 0.0
	while not condition.call():
		if waited >= budget:
			return false
		await physics_frame
		waited += DT
	return true


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _park(enemy: RoomCombatant, at: Vector3) -> void:
	enemy.set_combat_enabled(false)
	enemy.velocity = Vector3.ZERO
	enemy.global_position = at


func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


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
