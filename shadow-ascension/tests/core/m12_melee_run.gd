extends SceneTree

## M12.2 — the melee archetype through the whole game, the player vulnerable.
##
##   godot --headless --path . --script res://tests/core/m12_melee_run.gd
##
## Menu -> New Game -> hub (a shadow summoned) -> gate -> dungeon: every melee
## parked with its own attack, clean -> room one armed, the player standing its
## ground: both come in and swing — each swing telegraphed, a hit only in its
## ACTIVE window, 15 a hit, one per swing at most -> the player reads one
## telegraph and dodges it: nothing lands -> locked on, a critical heavy kills
## one: 25 XP once, the lock let go; the other killed -> room two: the shadow
## finishes one (70/30), the player the rest -> the boss, its own AI and its own
## attack, untouched -> hub -> a second dungeon: every melee's attack clean again,
## no listener doubled; room one: they swing again, one hit a swing -> hub,
## nothing orphaned.

const BOOT: String = "res://Main.tscn"
const HUB: String = "res://scenes/core/hub.tscn"
const DT: float = 1.0 / 60.0
const ROOM_ANCHORS: Array[Vector3] = [
	Vector3(0, 0.1, -13), Vector3(0, 0.1, -33), Vector3(0, 0.1, -53)
]
const EXIT_POS: Vector3 = Vector3(0, 0.1, -65)
const STRIKE_RANGE: float = 1.6
const BASIC_ATTACK: AttackData = preload("res://resources/enemies/attacks/melee_basic_attack.tres")

var _no_crits: PlayerCombatData = preload("res://resources/characters/player_combat.tres")
var _shadow_data: ShadowData = preload("res://resources/shadows/basic_melee_shadow.tres")
var _state: Node = null
var _pass: int = 0
var _fail: int = 0
## Every hit a melee's swing landed: on whom, how much, which swing, in what phase.
var _hits: Array[Dictionary] = []
## Per melee: the game time its current telegraph began (-1 while none).
var _telegraph_since: Dictionary = {}
## Per melee: the game time of every telegraph it showed.
var _telegraphs: Dictionary = {}
var _clock: float = 0.0
var _first_listeners: Dictionary = {}


func _initialize() -> void:
	_no_crits.critical_chance = 0.0
	_state = root.get_node_or_null("PlayerRuntimeState")
	_state.reset_runtime_state()
	physics_frame.connect(_on_physics_frame)
	change_scene_to_file(BOOT)
	await _pause(0.6)
	(current_scene.get_node("MainMenu") as MainMenu).press_play()
	await _pause(1.4)
	await _phase_hub()
	await _phase_into_dungeon(1)
	await _phase_room_one_swings(1)
	await _phase_room_one_dodge()
	await _phase_room_one_kills()
	await _phase_room_two()
	await _phase_boss()
	await _phase_out_to_hub()
	await _phase_into_dungeon(2)
	await _phase_room_one_swings(2)
	await _phase_room_one_kills()
	SceneTransition.find_in(self).transition_to_scene(HUB)
	await _pause(1.6)
	_record(current_scene.scene_file_path == HUB
			and int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)) == 0,
		"END) back in the hub after the second dungeon: nothing orphaned")
	_record(BASIC_ATTACK.windup == 0.35 and BASIC_ATTACK.active == 0.15 and BASIC_ATTACK.recovery == 0.65
			and BASIC_ATTACK.damage_multiplier == 1.0,
		"CFG) two dungeons of melee later, the shared melee_basic_attack.tres was never written")
	print("[SUMMARY] passed=%d failed=%d" % [_pass, _fail])
	await _pause(0.3)
	quit()


## Game time, and every melee's telegraph as it starts: read before the nodes
## run, so a hit this tick is judged against the telegraph that led to it.
func _on_physics_frame() -> void:
	_clock += DT * Engine.time_scale
	for enemy in _telegraph_since.keys():
		if not is_instance_valid(enemy):
			continue
		var e: BasicEnemy = enemy
		var telegraphing: bool = e.get_attack_phase() == EnemyAttack.Phase.TELEGRAPH
		if telegraphing and _telegraph_since[e] < 0.0:
			_telegraph_since[e] = _clock
			(_telegraphs[e] as Array).append(_clock)
		elif not telegraphing and e.get_attack_phase() == EnemyAttack.Phase.NONE:
			_telegraph_since[e] = -1.0


# --- the hub ---------------------------------------------------------------------------------------

func _phase_hub() -> void:
	var p: Player = current_scene.get_node("Player")
	var shadow: ShadowInstance = p.shadows.add_shadow(_shadow_data)
	p.shadow_summoner.summon(shadow.instance_id)
	await _pause(0.4)
	p.shadow_commander.set_mode(BasicMeleeShadow.CommandMode.FOLLOW)
	_record(p.shadow_summoner.get_active_node() != null, "H1) the hub: a shadow summoned, to take into the dungeon")


func _phase_into_dungeon(run: int) -> void:
	var p: Player = current_scene.get_node("Player")
	var gate: DungeonGate = current_scene.get_node("DungeonGate")
	p.global_position = gate.global_position
	await _pause(0.4)
	gate.activate()
	await _pause(1.6)
	var dungeon: DungeonController = current_scene as DungeonController
	var clean: bool = true
	var own: bool = true
	var listeners: Dictionary = {}
	var melee: Array[BasicEnemy] = _basic_enemies(dungeon)
	for enemy in melee:
		var attack: EnemyAttack = enemy.attack
		clean = clean and enemy.get_state() == BasicEnemy.State.IDLE and not enemy.combat_enabled \
			and attack.get_phase() == EnemyAttack.Phase.NONE and attack.get_cooldown_remaining() == 0.0 \
			and attack.get_swing_count() == 0 and not enemy.attack.hitbox.is_active() and enemy.visual_root.scale == Vector3.ONE
		own = own and attack.select_attack() == BASIC_ATTACK and attack.attack_damage == 15.0 and enemy.attack.hitbox.damage == 15.0
		listeners[String(enemy.get_path())] = [enemy.attack.hitbox.hit_accepted.get_connections().size(),
			enemy.attack.hitbox.hit_landed.get_connections().size(),
			enemy.health_component.damaged.get_connections().size(),
			enemy.state_changed.get_connections().size()]
		_watch(enemy)
	var distinct: bool = melee.size() >= 2 and not is_same(melee[0].attack, melee[1].attack)
	var same: bool = true
	if run == 1:
		_first_listeners = listeners
	else:
		same = listeners == _first_listeners
	_record(clean and own and distinct and listeners.size() == 5 and same,
		"G%d) dungeon %d: five melee, each with its own attack — melee_basic_attack, 15 — no swing under way, no cooldown, the hitbox shut, the telegraph at rest;%s" % [
			run, run, " listeners exactly as in the first dungeon — none doubled" if run == 2 else " their listeners noted"])


# --- room one: the player stands and takes the swings -------------------------------------------------

func _phase_room_one_swings(run: int) -> void:
	var dungeon: DungeonController = current_scene as DungeonController
	var p: Player = dungeon.get_player()
	var room: RoomController = dungeon.get_rooms()[0]
	var enemies: Array[BasicEnemy] = _room_enemies(room)
	p.hurtbox.set_invulnerable(false)
	p.health_component.heal(p.health_component.max_health)
	p.global_position = ROOM_ANCHORS[0]
	var taken: Array[float] = []
	var on_damaged: Callable = func(hit: DamageInfo) -> void: taken.append(hit.amount)
	p.health_component.damaged.connect(on_damaged)
	var first: int = _hits.size()
	var elapsed: float = 0.0
	while elapsed < 12.0 and _hits.size() - first < 4:
		p.global_position = ROOM_ANCHORS[0]
		if p.health_component.current_health < 50.0:
			p.health_component.heal(p.health_component.max_health)
		await physics_frame
		elapsed += DT
	p.health_component.damaged.disconnect(on_damaged)
	var mine: Array[Dictionary] = _hits.slice(first)
	var fair: bool = mine.size() >= 4 and taken.size() == mine.size()
	var swings: Dictionary = {}
	for hit in mine:
		fair = fair and hit["target"] == p and hit["amount"] == 15.0 and hit["attack_id"] == &"melee_basic_attack" \
			and hit["phase"] == EnemyAttack.Phase.ACTIVE and not hit["critical"] and enemies.has(hit["enemy"]) \
			and hit["telegraph"] >= BASIC_ATTACK.windup - 2.0 * DT
		var key: String = "%s#%d" % [hit["enemy"].name, hit["swing"]]
		fair = fair and not swings.has(key)
		swings[key] = true
	_record(fair and taken.all(func(a: float) -> bool: return a == 15.0),
		"R%d.1) room one, the player standing its ground: %d hits from %d swings — each after a telegraph of 0.35 s, in ACTIVE, 15 each, never twice from one swing" % [
			run, mine.size(), swings.size()])


func _phase_room_one_dodge() -> void:
	var dungeon: DungeonController = current_scene as DungeonController
	var p: Player = dungeon.get_player()
	var enemies: Array[BasicEnemy] = _room_enemies(dungeon.get_rooms()[0])
	p.health_component.heal(p.health_component.max_health)
	p.combat.restore_stamina(p.combat.get_max_stamina())
	var reader: Array = [null]
	var seen: bool = await _until(func() -> bool:
		p.global_position = ROOM_ANCHORS[0]
		for e in enemies:
			if e.get_attack_phase() == EnemyAttack.Phase.TELEGRAPH and e.attack.get_phase_remaining() <= 0.12:
				reader[0] = e
				return true
		return false, 6.0)
	var enemy: BasicEnemy = reader[0]
	var swing: int = enemy.attack.get_swing_count() if enemy != null else -1
	var speed: float = p.effective_dodge_speed
	p.effective_dodge_speed = 0.0
	_press(p, &"dodge")
	var dodging: bool = p.combat.get_state() == PlayerCombat.State.DODGING
	if enemy != null:
		await _until(func() -> bool: return (enemy.get_attack_phase() != EnemyAttack.Phase.ACTIVE
			and enemy.get_attack_phase() != EnemyAttack.Phase.TELEGRAPH), 1.0)
	p.effective_dodge_speed = speed
	var landed: bool = _hits.any(func(h: Dictionary) -> bool: return h["enemy"] == enemy and h["swing"] == swing)
	_record(seen and dodging and not landed,
		"R1.2) the player reads a telegraph and dodges into it: that swing's ACTIVE finds the i-frames — it lands nothing")


func _phase_room_one_kills() -> void:
	var dungeon: DungeonController = current_scene as DungeonController
	var p: Player = dungeon.get_player()
	var room: RoomController = dungeon.get_rooms()[0]
	var enemies: Array[BasicEnemy] = _room_enemies(room)
	p.hurtbox.set_invulnerable(true)
	p.health_component.heal(p.health_component.max_health)
	# Locked on, a critical heavy finishes whichever it locked.
	_stick(p, enemies[0])
	await _frames(2)
	_press(p, &"target_lock")
	var victim: BasicEnemy = p.targeting.get_target() as BasicEnemy
	var xp: int = p.progression.get_total_xp()
	var deaths: Array[int] = [0]
	var critical: Array[bool] = [false]
	var on_accepted: Callable = func(target: Node, hit: DamageInfo) -> void:
		if target == victim and hit.is_critical:
			critical[0] = true
	p.attack_hitbox.hit_accepted.connect(on_accepted)
	if victim != null:
		victim.enemy_died.connect(func(_dead: RoomCombatant) -> void: deaths[0] += 1)
		victim.health_component.current_health = 60.0
		_no_crits.critical_chance = 1.0
		await _heavy(p, victim)
		_no_crits.critical_chance = 0.0
	await _pause(0.3)
	p.attack_hitbox.hit_accepted.disconnect(on_accepted)
	var paid: int = p.progression.get_total_xp() - xp
	_record(victim != null and victim.has_died() and critical[0] and deaths[0] == 1 and paid == victim.get_xp_reward()
			and not p.targeting.is_locked() and victim.get_attack_phase() == EnemyAttack.Phase.NONE
			and not victim.attack.hitbox.is_active(),
		"K1) locked on, a critical heavy kills a melee: DEAD, its swing gone, one death, %d XP once, the lock let go" % paid)
	for enemy in enemies:
		await _kill(p, enemy)
	await _pause(0.5)
	var spent: bool = enemies.all(func(e: BasicEnemy) -> bool:
		return e.has_died() and e.get_attack_phase() == EnemyAttack.Phase.NONE and not e.attack.hitbox.is_active())
	_record(spent and room.is_cleared(),
		"K2) both dead, neither with a swing or an open hitbox left; the room clears")


# --- room two: the shadow's kill -------------------------------------------------------------------------

func _phase_room_two() -> void:
	var dungeon: DungeonController = current_scene as DungeonController
	var p: Player = dungeon.get_player()
	var shadow: BasicMeleeShadow = p.shadow_summoner.get_active_node()
	var room: RoomController = dungeon.get_rooms()[1]
	var enemies: Array[BasicEnemy] = _room_enemies(room)
	p.global_position = ROOM_ANCHORS[1]
	shadow.global_position = ROOM_ANCHORS[1] + Vector3(1.5, 0, 0)
	p.shadow_commander.set_mode(BasicMeleeShadow.CommandMode.AGGRESSIVE)
	var armed: bool = await _until(func() -> bool: return room.get_state() == RoomController.RoomState.ACTIVE, 2.0)
	var player_xp: int = p.progression.get_total_xp()
	var shadow_xp: int = _shadow_total_xp(shadow.instance)
	var shadows_own: BasicEnemy = enemies[1]
	shadows_own.health_component.current_health = 20.0
	shadow.set_manual_target(shadows_own)
	var elapsed: float = 0.0
	while elapsed < 30.0 and not enemies.all(func(e: BasicEnemy) -> bool: return e.has_died()):
		var mine: BasicEnemy = null
		for enemy in enemies:
			if not enemy.has_died() and enemy != shadows_own:
				mine = enemy
		if mine == null and not shadows_own.has_died() and elapsed > 15.0:
			mine = shadows_own
		if mine != null and p.combat.get_state() == PlayerCombat.State.IDLE:
			p.global_position = mine.global_position + Vector3(0, 0, STRIKE_RANGE)
			p.camera_rig.rotation.y = 0.0
			p.camera_rig.attack_light_pressed.emit()
		await physics_frame
		elapsed += DT
	await _pause(0.5)
	var expected_player: int = 0
	var expected_shadow: int = 0
	var by_shadow: int = 0
	for enemy in enemies:
		var reward: int = enemy.get_xp_reward()
		if enemy.get_killer() == shadow:
			by_shadow += 1
			var cut: int = int(round(reward * PlayerProgression.SHADOW_KILL_SHARE))
			expected_shadow += cut
			expected_player += reward - cut
		else:
			expected_player += reward
	var player_gain: int = p.progression.get_total_xp() - player_xp
	var shadow_gain: int = _shadow_total_xp(shadow.instance) - shadow_xp
	_record(armed and room.is_cleared() and by_shadow >= 1 and player_gain == expected_player and shadow_gain == expected_shadow,
		"S1) room two: the shadow finishes %d, the player the rest — a shadow's kill split 70/30 (player +%d, shadow +%d)" % [
			by_shadow, player_gain, shadow_gain])
	p.shadow_commander.set_mode(BasicMeleeShadow.CommandMode.FOLLOW)


# --- the boss, on its own AI ------------------------------------------------------------------------

func _phase_boss() -> void:
	var dungeon: DungeonController = current_scene as DungeonController
	var p: Player = dungeon.get_player()
	p.health_component.heal(p.health_component.max_health)
	p.global_position = ROOM_ANCHORS[2]
	var boss: DungeonBoss = _boss(dungeon)
	var bar: BossHealthBar = dungeon.get_node("BossHealthBar")
	var awake: bool = await _until(func() -> bool: return boss.combat_enabled and bar.is_showing(), 6.0)
	# The boss still swings its own attack, on its own phases.
	var winds_up: bool = await _until(func() -> bool:
		p.global_position = boss.global_position + Vector3(0, 0, 2.0)
		return boss.get_attack_phase() == BossCombat.Phase.TELEGRAPH, 6.0)
	_stick(p, boss)
	await _frames(2)
	_press(p, &"target_lock")
	var locked: bool = p.targeting.get_target() == boss
	boss.health_component.current_health = 40.0
	await _heavy(p, boss)
	await _pause(0.6)
	_record(awake and winds_up and locked and boss.has_died() and not p.targeting.is_locked()
			and boss.get_node_or_null("Attack") == null
			and dungeon.get_state() == DungeonController.DungeonState.COMPLETED,
		"B1) the boss — its own AI and its own attack, not the melee archetype — winds up, is locked and killed; the dungeon completes")


func _phase_out_to_hub() -> void:
	var dungeon: DungeonController = current_scene as DungeonController
	var p: Player = dungeon.get_player()
	p.global_position = EXIT_POS
	await _pause(0.4)
	dungeon.exit_portal.activate()
	await _pause(1.6)
	_telegraph_since.clear()
	_record(current_scene.scene_file_path == HUB
			and int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)) == 0,
		"O1) back in the hub: nothing of the first dungeon's melee left behind")


# --- helpers ------------------------------------------------------------------------------------------

func _watch(enemy: BasicEnemy) -> void:
	_telegraph_since[enemy] = -1.0
	_telegraphs[enemy] = []
	enemy.attack.hitbox.hit_accepted.connect(func(target: Node, info: DamageInfo) -> void:
		var began: float = _telegraph_since.get(enemy, -1.0)
		_hits.append({"target": target, "amount": info.amount, "attack_id": info.attack_id,
			"critical": info.is_critical, "phase": enemy.get_attack_phase(), "enemy": enemy,
			"swing": enemy.attack.get_swing_count(),
			"telegraph": _clock - began if began >= 0.0 else -1.0}))


func _basic_enemies(dungeon: DungeonController) -> Array[BasicEnemy]:
	var out: Array[BasicEnemy] = []
	for room in dungeon.get_rooms():
		out.append_array(_room_enemies(room))
	return out


func _room_enemies(room: RoomController) -> Array[BasicEnemy]:
	var out: Array[BasicEnemy] = []
	for combatant in room.get_enemies():
		var enemy: BasicEnemy = combatant as BasicEnemy
		if enemy != null:
			out.append(enemy)
	return out


func _boss(dungeon: DungeonController) -> DungeonBoss:
	for combatant in dungeon.get_rooms()[2].get_enemies():
		if combatant is DungeonBoss:
			return combatant as DungeonBoss
	return null


## The player's light attack at `target` until it dies, standing in front of it.
func _kill(p: Player, target: RoomCombatant, budget: float = 30.0) -> void:
	var elapsed: float = 0.0
	while elapsed < budget and not target.has_died():
		if p.combat.get_state() == PlayerCombat.State.IDLE:
			p.global_position = target.global_position + Vector3(0, 0, STRIKE_RANGE)
			p.camera_rig.rotation.y = 0.0
			p.camera_rig.attack_light_pressed.emit()
		await physics_frame
		elapsed += DT


## Bounded: a killing blow on the boss opens the run summary, which pauses the
## tree with the swing still in its recovery.
func _heavy(p: Player, glue: Node3D) -> void:
	p.combat.reset()
	_stick(p, glue)
	p.camera_rig.rotation.y = 0.0
	p.camera_rig.attack_heavy_pressed.emit()
	var frames: int = 0
	while p.combat.is_attacking() and frames < 300 and not paused:
		await physics_frame
		frames += 1
		_stick(p, glue)


func _stick(p: Player, glue: Node3D) -> void:
	if glue != null and is_instance_valid(glue):
		p.global_position = glue.global_position + Vector3(0, 0, STRIKE_RANGE)


func _press(p: Player, action: StringName) -> void:
	var event: InputEventAction = InputEventAction.new()
	event.action = action
	event.pressed = true
	p._unhandled_input(event)


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
