extends SceneTree

## M5 First Boss — milestone review, with REAL scene changes and REAL player
## attacks. It drives the player's own combo through camera_rig.attack_light_pressed
## rather than calling receive_hit, so the whole damage path is exercised: player
## hitbox -> boss hurtbox -> health component.
##
##   godot --headless --path . --script res://tests/bosses/m5_review_run.gd
##
## Three passes: a full boss fight, a death in phase 2 with the restart it forces,
## and a second full fight on the reloaded dungeon.

const HUB: String = "res://scenes/core/hub.tscn"
const DUNGEON: String = "res://scenes/dungeons/dungeon_test.tscn"
const ROOM_ANCHORS: Array[Vector3] = [
	Vector3(0, 0.1, -13), Vector3(0, 0.1, -33), Vector3(0, 0.1, -53)
]
const EXIT_POS: Vector3 = Vector3(0, 0.1, -65)
const STRIKE_RANGE: float = 1.6

var _pass: int = 0
var _fail: int = 0


func _initialize() -> void:
	# A clean session: progression and health now survive scene changes.
	var state: Node = root.get_node_or_null("PlayerRuntimeState")
	if state != null:
		state.reset_runtime_state()
	change_scene_to_file(HUB)
	await _pause(0.6)

	await _fight(1, false)
	await _exit_dungeon(1)
	await _fight(2, true)
	await _fight(3, false)
	await _exit_dungeon(3)

	print("[SUMMARY] passed=%d failed=%d" % [_pass, _fail])
	await _pause(0.3)
	quit()


## M9.1: completing the dungeon opens the run summary, which pauses the tree
## until the player dismisses it. A headless flow has no player, so it does
## what one would — the summary itself is covered by vertical_slice_run.gd.
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


## Enters the dungeon from the test world unless one is already running (the
## restart leaves us inside one), then clears both combat rooms.
func _reach_boss_room() -> Dictionary:
	if current_scene.scene_file_path != DUNGEON:
		var player_out: Player = current_scene.get_node("Player")
		var gate: DungeonGate = current_scene.get_node("DungeonGate")
		player_out.global_position = gate.global_position
		await _pause(0.3)
		gate.activate()
		await _pause(1.0)

	var dungeon: DungeonController = current_scene as DungeonController
	var player: Player = current_scene.get_node("Player")
	for i in 2:
		player.global_position = ROOM_ANCHORS[i]
		await _pause(0.4)
		for enemy in dungeon.get_rooms()[i].get_enemies():
			enemy.hurtbox.receive_hit(DamageInfo.new(10000.0, null))
		await _pause(0.5)
	player.global_position = ROOM_ANCHORS[2]
	await _pause(0.6)
	return {"dungeon": dungeon, "player": player}


## One swing of the player's real combo, from real striking distance, aimed by
## the camera the way the controller aims it.
func _swing(player: Player, boss: DungeonBoss) -> void:
	player.global_position = boss.global_position + Vector3(0, 0, STRIKE_RANGE)
	player.camera_rig.rotation.y = 0.0
	player.camera_rig.attack_light_pressed.emit()


## Fights the boss with real attacks. `die_in_phase_2` stops swinging once the
## second phase is up and lets the boss finish the player instead.
func _fight(n: int, die_in_phase_2: bool) -> void:
	var ctx: Dictionary = await _reach_boss_room()
	var dungeon: DungeonController = ctx["dungeon"]
	var player: Player = ctx["player"]
	var boss: DungeonBoss = dungeon.get_rooms()[2].get_enemies()[0] as DungeonBoss
	var bar: BossHealthBar = dungeon.get_node("BossHealthBar")
	var objective: DungeonObjectiveUI = dungeon.get_node("DungeonObjectiveUI")

	_record(boss != null and bar.is_showing() and boss.combat_enabled,
		"F%d) the encounter starts: boss awake, health bar up" % n)
	_record(boss.get_phase() == DungeonBoss.BossPhase.PHASE_1
			and bar.get_phase_text() == bar.phase_1_text,
		"F%d) it opens in phase 1, UI reads '%s'" % [n, bar.get_phase_text()])
	_record(objective.get_objective() == "Sconfiggi il Boss",
		"F%d) objective reads '%s'" % [n, objective.get_objective()])
	_record(dungeon.get_rooms()[2].exit_door.is_locked(),
		"F%d) the arena is sealed" % n)

	var phases: Array[int] = [boss.get_phase()]
	var attacks_used: Dictionary = {}
	var telegraphs: Dictionary = {}
	var locked_during_active: bool = true
	var yaw_at_active: float = 0.0
	var was_active: bool = false
	var damage_dealt: float = 0.0
	var objective_held: bool = true
	var swings: int = 0
	var elapsed: float = 0.0

	# Shielded to begin with in both runs. The death run drops the shield the
	# moment phase 2 starts: standing in melee and trading without dodging now
	# kills the player before the boss is halfway down, and this test is about
	# dying IN phase 2, not about winning that race.
	player.hurtbox.set_invulnerable(true)

	while elapsed < 90.0:
		if boss.health_component.is_dead:
			break
		if die_in_phase_2 and player.health_component.is_dead:
			break

		# Track what the boss is doing, frame by frame.
		if boss.get_phase() != phases[phases.size() - 1]:
			phases.append(boss.get_phase())
		var index: int = boss.get_active_attack_index()
		var active: bool = index >= 0 and boss.get_attack_phase() == DungeonBoss.AttackPhase.ACTIVE
		if index >= 0:
			attacks_used[boss.attacks[index].attack_name] = true
		if boss.get_attack_phase() == DungeonBoss.AttackPhase.STARTUP and index >= 0:
			_track_telegraph_peak(telegraphs, boss.attacks[index].attack_name, boss)
		if active and not was_active:
			yaw_at_active = boss.visual_root.rotation.y
		elif active and absf(wrapf(boss.visual_root.rotation.y - yaw_at_active, -PI, PI)) > 0.02:
			locked_during_active = false
		was_active = active
		if objective.get_objective() != "Sconfiggi il Boss" and not boss.health_component.is_dead:
			objective_held = false

		# The player keeps swinging, unless this run is the one that dies. The
		# swing is fired and the loop goes straight on: pausing here would skip
		# whole wind-ups, and Double Strike's is only 0.22s long.
		var stop_swinging: bool = die_in_phase_2 and boss.get_phase() == DungeonBoss.BossPhase.PHASE_2
		if stop_swinging and player.hurtbox.is_invulnerable:
			player.hurtbox.set_invulnerable(false)
		if not stop_swinging and player.combat.get_state() == PlayerCombat.State.IDLE:
			_swing(player, boss)
			swings += 1
		elif stop_swinging:
			# Stand still in reach and let the boss land its hits.
			player.global_position = boss.global_position + Vector3(0, 0, 1.4)
		await physics_frame
		elapsed += 1.0 / 60.0

	damage_dealt = boss.health_component.max_health - boss.health_component.current_health

	if die_in_phase_2:
		await _fight_death(n, dungeon, boss, bar)
		return

	player.hurtbox.set_invulnerable(false)
	await _pause(0.8)

	_record(boss.health_component.is_dead and boss.get_state() == DungeonBoss.State.DEAD,
		"F%d) the player kills the boss with its own combo (%d swings, %.0f damage)" % [
			n, swings, damage_dealt])
	_record(phases.size() == 3 and phases[0] == DungeonBoss.BossPhase.PHASE_1
			and phases[1] == DungeonBoss.BossPhase.TRANSITION
			and phases[2] == DungeonBoss.BossPhase.PHASE_2,
		"F%d) the fight ran PHASE_1 -> TRANSITION -> PHASE_2 exactly once: %s" % [n, phases])
	_record(attacks_used.size() == 4,
		"F%d) all four attacks were used: %s" % [n, attacks_used.keys()])
	var shapes: Array[String] = []
	for key in telegraphs:
		shapes.append(_shape_of(telegraphs[key]))
	_record(telegraphs.size() == 4 and not shapes.has("none") and _distinct(shapes),
		"F%d) each wind-up reads differently: %s" % [n, _shape_map(telegraphs)])
	_record(locked_during_active, "F%d) facing stayed locked through every active window" % n)
	_record(objective_held, "F%d) the objective read 'Sconfiggi il Boss' until the boss fell" % n)
	_record(not bar.is_showing() and not bar.is_banner_showing(),
		"F%d) the boss UI is gone" % n)
	_record(dungeon.get_rooms()[2].is_cleared()
			and dungeon.get_state() == DungeonController.DungeonState.COMPLETED,
		"F%d) boss room cleared, dungeon COMPLETED" % n)
	_record(objective.get_objective() == "Dungeon completato",
		"F%d) objective reads '%s'" % [n, objective.get_objective()])
	_record(dungeon.exit_portal.is_enabled(), "F%d) the exit portal is live" % n)


## The boss killed the player: the run must fail and reload, and the boss must
## come back whole and asleep in phase 1.
func _fight_death(n: int, dungeon: DungeonController, boss: DungeonBoss, _bar: BossHealthBar) -> void:
	_record(boss.get_phase() == DungeonBoss.BossPhase.PHASE_2,
		"F%d) the boss reached phase 2 before it killed the player" % n)
	var doomed_id: int = current_scene.get_instance_id()
	await _pause(0.4)
	_record(dungeon.get_state() == DungeonController.DungeonState.FAILED,
		"F%d) the boss killing the player fails the run" % n)

	await _pause(2.5)
	_record(current_scene.get_instance_id() != doomed_id,
		"F%d) the dungeon reloaded out of the boss fight" % n)
	var restarted: DungeonController = current_scene as DungeonController
	var fresh: DungeonBoss = restarted.get_rooms()[2].get_enemies()[0] as DungeonBoss
	var fresh_bar: BossHealthBar = restarted.get_node("BossHealthBar")
	_record(fresh.get_phase() == DungeonBoss.BossPhase.PHASE_1
			and not fresh.phase_transition_spent()
			and fresh.health_component.current_health == fresh.health_component.max_health
			and fresh.get_state() == DungeonBoss.State.INACTIVE,
		"F%d) the restarted boss: phase 1, transition unspent, %.0f HP, INACTIVE" % [
			n, fresh.health_component.current_health])
	_record(not fresh_bar.is_showing() and not fresh_bar.is_banner_showing(),
		"F%d) its UI starts hidden again" % n)


func _exit_dungeon(n: int) -> void:
	var dungeon: DungeonController = current_scene as DungeonController
	var player: Player = current_scene.get_node("Player")
	player.global_position = EXIT_POS
	await _pause(0.4)
	var used: bool = dungeon.exit_portal.activate()
	await _pause(1.2)
	_record(used and current_scene.scene_file_path == HUB,
		"F%d) the exit portal really returns to the test world" % n)


## Records how far the body actually moved during a wind-up, read off the mesh
## rather than off the resource: a telegraph that is configured but never
## animated must not count as readable.
func _track_telegraph_peak(store: Dictionary, name: String, boss: DungeonBoss) -> void:
	var mesh: Node3D = boss.mesh_root
	var peak: Dictionary = store.get(name, {"pz": 0.0, "rx": 0.0, "ry": 0.0, "sy": 1.0})
	peak["pz"] = maxf(peak["pz"], absf(mesh.position.z))
	peak["rx"] = maxf(peak["rx"], absf(mesh.rotation.x))
	peak["ry"] = maxf(peak["ry"], absf(mesh.rotation.y))
	peak["sy"] = minf(peak["sy"], mesh.scale.y)
	store[name] = peak


## Names the shape from the peak, most specific first.
func _shape_of(peak: Dictionary) -> String:
	if peak["ry"] > 0.5:
		return "spin"
	if peak["sy"] < 0.8:
		return "compress"
	if peak["pz"] > 0.1:
		return "recoil"
	if peak["rx"] > 0.1:
		return "lean"
	return "none"


func _shape_map(store: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for key in store:
		out[key] = _shape_of(store[key])
	return out


func _distinct(values: Array) -> bool:
	var seen: Dictionary = {}
	for v in values:
		if seen.has(v):
			return false
		seen[v] = true
	return true
