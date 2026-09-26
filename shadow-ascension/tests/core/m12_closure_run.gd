extends SceneTree

## M12.9 — the M12 closure run: the whole game, twice.
##
##   godot --headless --path . --script res://tests/core/m12_closure_run.gd
##
## Menu -> New Game -> hub (a shadow summoned) -> gate -> dungeon, twice over:
## room one fought with the player's real attacks beside a ranged, a tank, an
## assassin, a support and an elite melee brought into it; room two cleared; the
## boss — phase 1 and its attacks; the player and the shadow past half: the
## transition and phase 2, its Heavy Slam dodged; past a quarter: the enrage;
## killed — one death, one completion — the exit, the hub. The second loop
## starts from a boss as new as the first (phase 1, not enraged, clean cooldowns,
## its baseline speed) and nothing of the first loop — no enemy, projectile,
## buff, target or boss — survives into the hub either time.

const BOOT: String = "res://Main.tscn"
const HUB: String = "res://scenes/core/hub.tscn"
const DT: float = 1.0 / 60.0
const ROOM_ANCHORS: Array[Vector3] = [
	Vector3(0, 0.1, -13), Vector3(0, 0.1, -33), Vector3(0, 0.1, -53)
]
const EXIT_POS: Vector3 = Vector3(0, 0.1, -65)
const STRIKE_RANGE: float = 1.6
const ARCHETYPES: Array[String] = [
	"res://scenes/enemies/basic_ranged_enemy.tscn", "res://scenes/enemies/basic_tank_enemy.tscn",
	"res://scenes/enemies/basic_assassin_enemy.tscn", "res://scenes/enemies/basic_support_enemy.tscn",
	"res://scenes/enemies/basic_melee_enemy.tscn",
]
const ELITE: EliteModifierData = preload("res://resources/enemies/elite_standard.tres")
const BOSS_DATA: BossData = preload("res://resources/enemies/bosses/dungeon_boss_data.tres")
const MELEE_DATA: EnemyData = preload("res://resources/enemies/basic_melee_enemy.tres")

var _no_crits: PlayerCombatData = preload("res://resources/characters/player_combat.tres")
var _shadow_data: ShadowData = preload("res://resources/shadows/basic_melee_shadow.tres")
var _pass: int = 0
var _fail: int = 0


func _initialize() -> void:
	_no_crits.critical_chance = 0.0
	root.get_node_or_null("PlayerRuntimeState").reset_runtime_state()
	change_scene_to_file(BOOT)
	await _pause(0.6)
	(current_scene.get_node("MainMenu") as MainMenu).press_play()
	await _pause(1.4)
	var p: Player = current_scene.get_node("Player")
	var shadow: ShadowInstance = p.shadows.add_shadow(_shadow_data)
	p.shadow_summoner.summon(shadow.instance_id)
	await _pause(0.4)
	p.shadow_commander.set_mode(BasicMeleeShadow.CommandMode.FOLLOW)
	_record(current_scene.scene_file_path == HUB and p.shadow_summoner.get_active_node() != null,
		"H) New Game: the hub, a shadow summoned")
	for loop in [1, 2]:
		await _loop(loop)
	_record(is_equal_approx(BOSS_DATA.phases[1].cooldown_multiplier, 0.85) and is_equal_approx(BOSS_DATA.enrage.cooldown_multiplier, 0.85)
			and BOSS_DATA.max_health == 900.0 and MELEE_DATA.max_health == 100.0 and ELITE.health_multiplier == 1.6,
		"END) two whole runs later the shared data is as shipped: the boss's, the melee's, the elite profile's")
	print("[SUMMARY] passed=%d failed=%d" % [_pass, _fail])
	await _pause(0.3)
	quit()


func _loop(n: int) -> void:
	var p: Player = current_scene.get_node("Player")
	var gate: DungeonGate = current_scene.get_node("DungeonGate")
	p.global_position = gate.global_position
	await _pause(0.4)
	gate.activate()
	await _pause(1.6)
	var dungeon: DungeonController = current_scene as DungeonController
	var boss: DungeonBoss = _boss(dungeon)
	var clean: bool = true
	for attack in boss.get_attacks():
		clean = clean and boss.combat.get_cooldown(attack) == 0.0
	_record(boss.get_state() == DungeonBoss.State.INACTIVE and boss.get_phase_index() == -1 and not boss.is_enraged()
			and clean and is_equal_approx(boss.movement_speed, BOSS_DATA.movement_speed)
			and is_equal_approx(boss.combat.get_cooldown_scale(), 1.0) and boss.health_component.current_health == BOSS_DATA.max_health,
		"L%d.1) dungeon %d's boss is new: asleep, no phase, not enraged, clean cooldowns, baseline speed and pace, full health" % [n, n])
	await _mixed_room(n, dungeon)
	await _clear_room_two(dungeon)
	await _boss_fight(n, dungeon)
	p = dungeon.get_player()
	p.global_position = EXIT_POS
	await _pause(0.4)
	dungeon.exit_portal.activate()
	await _pause(1.8)
	_record(current_scene.scene_file_path == HUB and get_nodes_in_group(DungeonBoss.GROUP).is_empty()
			and root.find_children("*", "BasicEnemy", true, false).is_empty()
			and root.find_children("*", "Projectile", true, false).is_empty()
			and int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)) == 0,
		"L%d.9) back in the hub: no boss, no enemy, no projectile left, nothing orphaned" % n)


# --- 77-78, 84. room one, with every archetype and an elite ------------------------------------------------------

func _mixed_room(n: int, dungeon: DungeonController) -> void:
	var p: Player = dungeon.get_player()
	var room: RoomController = dungeon.get_rooms()[0]
	p.hurtbox.set_invulnerable(true)
	p.global_position = ROOM_ANCHORS[0]
	await _until(func() -> bool: return room.get_state() == RoomController.RoomState.ACTIVE, 3.0)
	var guests: Array[BasicEnemy] = []
	for i in ARCHETYPES.size():
		var enemy: BasicEnemy = (load(ARCHETYPES[i]) as PackedScene).instantiate() as BasicEnemy
		enemy.elite_profile = ELITE if i == ARCHETYPES.size() - 1 else null
		enemy.position = ROOM_ANCHORS[0] + Vector3(-4.0 + 2.0 * i, 0, -5.0)
		dungeon.add_child(enemy)
		enemy.set_combat_enabled(true)
		guests.append(enemy)
	var hosts: Array[RoomCombatant] = room.get_enemies()
	# The room's own melee hurt, so the support has someone to look after.
	(hosts[0] as BasicEnemy).health_component.current_health = 40.0
	var fought: bool = await _until(func() -> bool:
		p.global_position = ROOM_ANCHORS[0]
		return guests.all(func(e: BasicEnemy) -> bool: return e.attack.get_swing_count() >= 1), 20.0)
	var support: BasicEnemy = guests[3]
	var helped: bool = support.support.get_heal_count() + support.support.get_buff_count() >= 1
	var elite: BasicEnemy = guests[4]
	_record(fought and helped and elite.is_elite() and elite.health_component.max_health == 160.0
			and not (hosts[1] as BasicEnemy).is_elite(),
		"L%d.2) room one: the ranged, the tank, the assassin, the support and an elite melee all fight beside the room's melee; the support helps (%d heals, %d buffs)" % [
			n, support.support.get_heal_count(), support.support.get_buff_count()])
	for e in hosts:
		await _kill(p, e)
	for e in guests:
		if not e.has_died():
			e.hurtbox.receive_hit(DamageInfo.new(100000.0, p))
	# A bolt already in the air flies on (M12.3) until its lifetime runs out.
	await _pause(2.5)
	_record(room.is_cleared() and _projectiles() == 0,
		"L%d.3) the room's melee die to the player's real attacks, the guests with them: the room clears, no projectile left (cleared=%s, projectiles=%d)" % [
			n, room.is_cleared(), _projectiles()])


func _clear_room_two(dungeon: DungeonController) -> void:
	var p: Player = dungeon.get_player()
	p.global_position = ROOM_ANCHORS[1]
	await _pause(0.5)
	for enemy in dungeon.get_rooms()[1].get_enemies():
		enemy.hurtbox.receive_hit(DamageInfo.new(10000.0, p))
	await _pause(0.5)


# --- 85. the boss, whole ---------------------------------------------------------------------------------------------

func _boss_fight(n: int, dungeon: DungeonController) -> void:
	var p: Player = dungeon.get_player()
	var boss: DungeonBoss = _boss(dungeon)
	var shadow: BasicMeleeShadow = p.shadow_summoner.get_active_node()
	var bar: BossHealthBar = dungeon.get_node("BossHealthBar")
	var events_log: Array[String] = []
	var started: Array[BossAttack] = []
	var completions: Array[int] = [0]
	var deaths: Array[int] = [0]
	boss.phase_transition_started.connect(func(to: int) -> void: events_log.append("transition_%d" % to))
	boss.phase_changed.connect(func(i: int) -> void: events_log.append("phase_%d" % i))
	boss.enrage_started.connect(func() -> void: events_log.append("enrage_started"))
	boss.enraged.connect(func() -> void: events_log.append("enraged"))
	boss.combat.attack_started.connect(func(a: BossAttack) -> void: started.append(a))
	boss.enemy_died.connect(func(_c: RoomCombatant) -> void: deaths[0] += 1)
	dungeon.dungeon_completed.connect(func() -> void: completions[0] += 1)
	p.hurtbox.set_invulnerable(true)
	shadow.hurtbox.set_invulnerable(true)
	p.global_position = ROOM_ANCHORS[2]
	await _until(func() -> bool: return boss.combat_enabled, 4.0)
	await _until(func() -> bool:
		_stick(p, boss)
		return started.size() >= 3, 12.0)
	_record(started.size() >= 3 and started.all(func(a: BossAttack) -> bool: return BOSS_DATA.phases[0].attacks.has(a))
			and bar.is_showing() and bar.get_phase_text() == "FASE 1",
		"L%d.4) the encounter: phase 1, its bar, its own attacks (%d)" % [n, started.size()])

	# The player and the shadow past half.
	p.shadow_commander.set_mode(BasicMeleeShadow.CommandMode.AGGRESSIVE)
	boss.health_component.current_health = BOSS_DATA.max_health * 0.56
	var crossed: bool = await _until(func() -> bool:
		shadow.set_manual_target(boss)
		_swing(p, boss)
		return boss.is_in_transition(), 40.0)
	await _until(func() -> bool:
		_stick(p, boss)
		return boss.get_phase_index() == 1 and not boss.is_in_transition(), 4.0)
	_record(crossed and events_log.has("transition_1") and events_log.has("phase_1") and boss.get_phase_index() == 1
			and is_equal_approx(boss.combat.get_cooldown_scale(), 0.85) and boss.movement_speed > BOSS_DATA.movement_speed,
		"L%d.5) past half: the transition, then phase 2 — quicker cooldowns, faster on its feet" % n)

	# The Heavy Slam: the others held back so it comes up within the run (its
	# natural rarity is boss_phase_test's), and the player dodges it for real.
	p.shadow_commander.set_mode(BasicMeleeShadow.CommandMode.FOLLOW)
	var heavy: BossAttack = null
	for attack in boss.get_attacks():
		if attack.get_id() == &"boss_heavy_slam":
			heavy = attack
		else:
			boss.combat.set_cooldown(attack, 30.0)
	p.hurtbox.set_invulnerable(false)
	p.health_component.current_health = p.health_component.max_health
	var dodged: Array[bool] = [false]
	var slammed: bool = await _until(func() -> bool:
		if boss.get_current_attack() != heavy:
			_stick(p, boss)
		elif not dodged[0] and boss.get_attack_phase() == BossCombat.Phase.TELEGRAPH \
				and boss.combat.get_phase_remaining() <= 0.1:
			p.combat._dodge_cooldown_remaining = 0.0
			p._on_dodge_pressed()
			dodged[0] = true
		return dodged[0] and boss.get_current_attack() != heavy, 20.0)
	_record(slammed and dodged[0] and p.health_component.current_health == p.health_component.max_health
			and started.has(heavy),
		"L%d.6) phase 2's Heavy Slam comes, the player dodges it: no damage" % n)
	p.hurtbox.set_invulnerable(true)
	boss.combat.clear_cooldowns()

	# Past a quarter: the enrage.
	p.shadow_commander.set_mode(BasicMeleeShadow.CommandMode.AGGRESSIVE)
	boss.health_component.current_health = BOSS_DATA.max_health * 0.3
	var enraging: bool = await _until(func() -> bool:
		shadow.set_manual_target(boss)
		_swing(p, boss)
		return boss.is_enraging() or boss.is_enraged(), 30.0)
	await _until(func() -> bool:
		_stick(p, boss)
		return boss.is_enraged(), 3.0)
	_record(enraging and boss.is_enraged() and events_log.count("enrage_started") == 1 and events_log.find("phase_1") < events_log.find("enrage_started")
			and is_equal_approx(boss.combat.get_cooldown_scale(), 0.85 * 0.85) and bar.get_phase_text() == "FASE 2 — FURIA",
		"L%d.7) past a quarter: the enrage, once, after phase 2 — cooldowns x0.7225, the bar reads '%s'" % [n, bar.get_phase_text()])

	# Killed, enraged.
	var killed: bool = await _until(func() -> bool:
		shadow.set_manual_target(boss)
		_swing(p, boss)
		return boss.has_died(), 60.0)
	await _pause(1.0)
	_record(killed and deaths[0] == 1 and completions[0] == 1 and dungeon.get_state() == DungeonController.DungeonState.COMPLETED
			and not bar.is_showing() and boss.get_current_attack() == null,
		"L%d.8) enraged, it dies: one death, one completion, the bar gone, no attack left" % n)
	p.shadow_commander.set_mode(BasicMeleeShadow.CommandMode.FOLLOW)


# --- helpers ------------------------------------------------------------------------------------------------------------

func _boss(dungeon: DungeonController) -> DungeonBoss:
	for combatant in dungeon.get_rooms()[2].get_enemies():
		if combatant is DungeonBoss:
			return combatant as DungeonBoss
	return null


func _projectiles() -> int:
	var count: int = 0
	for node in root.find_children("*", "Projectile", true, false):
		if not node.is_queued_for_deletion():
			count += 1
	return count


func _kill(p: Player, target: RoomCombatant, budget: float = 30.0) -> void:
	var elapsed: float = 0.0
	while elapsed < budget and not target.has_died():
		_swing(p, target)
		await physics_frame
		elapsed += DT


func _swing(p: Player, target: Node3D) -> void:
	if p.combat.get_state() != PlayerCombat.State.IDLE:
		return
	_stick(p, target)
	p.camera_rig.rotation.y = 0.0
	p.camera_rig.attack_light_pressed.emit()


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


## A killing blow on the boss opens the run summary, which pauses the tree: a
## headless flow dismisses it, as a player would.
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
