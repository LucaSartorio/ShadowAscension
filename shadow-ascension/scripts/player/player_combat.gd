class_name PlayerCombat
extends Node

## The player's combat controller: what the player may do in a fight, and when.
##
## It turns an intent into a committed action and runs that action's timeline:
##
##     request_light_attack() -> WINDUP -> ACTIVE (hitbox open) -> RECOVERY -> IDLE
##     request_heavy_attack()                                         \-> the next attack of
##                                                                        the chain, if one was
##                                                                        accepted in the window
##     request_dodge()        -> DODGING: STARTUP -> INVULNERABLE -> RECOVERY -> IDLE,
##                               then a cooldown before the next dodge
##
## It owns the combat state, the attack timeline, the attack chains, the input
## buffer, the hit window, and the dodge's timing and i-frames. Everything
## else is someone else's: the devices are read by the player (camera rig and
## player script), which only calls request_*(); the body is moved by the player,
## which asks this what the current action allows; the representation is played
## by the player on attack_started. A hit leaves through the hitbox as a
## DamageInfo, and whatever it lands on resolves it — this never touches a
## health bar, an enemy, XP or the dungeon.
##
## Attack chains. Every intent names a chain of attacks: the light combo
## (Light 1 -> 2 -> 3, M11.2) and the heavy attack, a chain of one (M11.3). A
## free player starts the chain's first attack. A chain runs on only while each
## attack accepts the next one: a press FOR THE SAME CHAIN inside an attack's
## combo window — or just before it, held by the input buffer — queues the next
## attack, which starts the moment the current one is over. Anything else ends the
## chain with the attack. A press for another chain is ignored while an attack
## runs: chains do not branch into each other yet. Nothing of a chain survives
## the player going free, so after any attack the next press starts a chain from
## its first attack.
##
## The dodge (M11.4). A directed burst of movement with a window of
## invulnerability inside it: vulnerable for its first moment (STARTUP),
## invulnerable in the middle (INVULNERABLE), vulnerable again for its tail
## (RECOVERY), then free, with a short cooldown before another. The i-frames are
## the hurtbox refusing hits for one reason of its own — this never tells an
## attacker anything, and the attacker never asks. Where the dodge goes and how
## fast is the player's: this only says when.
##
## One timing source: this node's _physics_process, on delta. It runs after the
## player's own (a child processes after its parent), pauses with the tree, and
## is freed with the player, so nothing of it outlives a scene.

## An attack began — first of a chain or the next one. The presentation listens
## (facing, animation); nothing that decides a hit does.
signal attack_started(attack: AttackData)

## What the player is doing in combat. WINDUP, ACTIVE and RECOVERY are the three
## phases of an attack. DEAD is never stored: it is read from the health
## component, so combat cannot be dead while the body lives, or the other way.
enum State { IDLE, WINDUP, ACTIVE, RECOVERY, DODGING, DEAD }
## Where a dodge is, NONE when there is none. The i-frames are INVULNERABLE,
## exactly: the phase is what switches them.
enum DodgePhase { NONE, STARTUP, INVULNERABLE, RECOVERY }

## No attack: no chain has started, or it is over.
const NO_ATTACK: int = -1
## The chain while free: none.
const NO_CHAIN: Array[AttackData] = []
## The reason the dodge gives the hurtbox for refusing hits, so ending the
## i-frames ends only the dodge's invulnerability, never another system's.
const IFRAMES_REASON: StringName = &"dodge_iframes"

@export var data: PlayerCombatData

@export_group("DEBUG")
## DEBUG ONLY. Off by default; the game never needs it. Prints every state and
## dodge-phase change with the attack, its place in the chain, what is waiting to
## follow it and whether the i-frames are on — for tuning windows, not for play.
@export var debug_log_enabled: bool = false

# Handed over by the player in setup().
var _hitbox: Hitbox = null
var _hurtbox: Hurtbox = null
var _health: HealthComponent = null
var _progression: PlayerProgression = null

var _state: State = State.IDLE
## Time spent in the current state, reset on every change.
var _state_elapsed: float = 0.0
## The chain being performed — one of the data's chains, by reference — the
## attack, and its index in that chain; NO_CHAIN, null and NO_ATTACK while free.
var _chain: Array[AttackData] = NO_CHAIN
var _attack: AttackData = null
var _combo_index: int = NO_ATTACK
## The attack accepted to follow this one, or null. Set at most once per attack,
## so one window buys one follow-up however often the button is pressed.
var _next_attack: AttackData = null
## Seconds a press made before the combo window opened has left; 0 when there is
## none. One slot, not a queue: pressing again only renews it.
var _buffered_attack: float = 0.0
var _dodge_phase: DodgePhase = DodgePhase.NONE
var _dodge_cooldown_remaining: float = 0.0
var _iframes_active: bool = false


func _ready() -> void:
	if data == null:
		push_warning("%s has no PlayerCombatData; using the class defaults, with no attacks." % name)
		data = PlayerCombatData.new()


## Called once by the player with the parts of itself this drives or reads.
func setup(hitbox: Hitbox, hurtbox: Hurtbox, health: HealthComponent,
		progression: PlayerProgression) -> void:
	_hitbox = hitbox
	_hurtbox = hurtbox
	_health = health
	_progression = progression
	if _health != null:
		_health.died.connect(_on_owner_died)


# --- intents ------------------------------------------------------------------------------

## A light attack was asked for: the light combo. True when an attack started.
func request_light_attack() -> bool:
	return _request(data.light_combo)


## A heavy attack was asked for: a chain of one. True when an attack started.
func request_heavy_attack() -> bool:
	return _request(data.heavy_combo)


## What any attack press does, whichever chain it asks for:
##
## - Free: the chain's first attack starts now.
## - For the running chain, inside the current attack's combo window: the next
##   attack is queued.
## - For the running chain, earlier in an attack that has a next one: the press
##   is held for `input_buffer_time`, and queues the next attack if the window
##   opens in time.
## - Anything else — another chain, after the window, during a chain's last
##   attack, a follow-up already queued, dodging, dead — does nothing. Two
##   presses in one frame therefore resolve in arrival order: the first starts
##   its chain, the second is judged against it.
func _request(chain: Array[AttackData]) -> bool:
	var state: State = get_state()
	if state == State.IDLE:
		return _start_attack(chain, 0)
	if not is_attacking() or state == State.DEAD:
		return false
	if not is_same(chain, _chain) or _next_attack != null or not _has_next_attack():
		return false
	if _in_combo_window():
		_queue_next_attack()
	elif not _combo_window_passed():
		_buffered_attack = data.input_buffer_time
	return false


## A dodge was asked for. Starts one if can_dodge() allows it; an attack inside
## its dodge-cancel window is cancelled, and the chain with it. Anything else —
## dodging already, on cooldown, dead, an attack not yet cancellable — refuses
## it, and nothing is held: a dodge is never buffered. True when a dodge started.
func request_dodge() -> bool:
	if not can_dodge():
		return false
	if is_attacking():
		_stop_attack()
	_end_chain()
	_enter(State.DODGING)
	_enter_dodge_phase(DodgePhase.STARTUP)
	return true


## Drops whatever combat was doing and starts clean: no attack and no hit window,
## no chain, nothing queued or buffered, no dodge and no i-frames, no cooldown.
## What a death does.
func reset() -> void:
	_stop_attack()
	_end_chain()
	_dodge_phase = DodgePhase.NONE
	_set_iframes(false)
	_enter(State.IDLE)
	_dodge_cooldown_remaining = 0.0


# --- queries --------------------------------------------------------------------------------

func get_state() -> State:
	if _health != null and _health.is_dead:
		return State.DEAD
	return _state


func is_attacking() -> bool:
	return _state == State.WINDUP or _state == State.ACTIVE or _state == State.RECOVERY


func is_dodging() -> bool:
	return _state == State.DODGING


## Whether a dodge may start now: not dodging already, not dead, off cooldown,
## and not committed to an attack short of its dodge-cancel window. The one gate
## every dodge passes — where a stamina check will join it.
func can_dodge() -> bool:
	var state: State = get_state()
	if state == State.DODGING or state == State.DEAD:
		return false
	if _dodge_cooldown_remaining > 0.0:
		return false
	return not is_attacking() or _in_dodge_cancel_window()


func get_dodge_phase() -> DodgePhase:
	return _dodge_phase


## The attack being performed, or null.
func get_current_attack() -> AttackData:
	return _attack


## Where the current attack sits in its chain (0 for the first), or NO_ATTACK
## while free.
func get_combo_index() -> int:
	return _combo_index


## Whether the running chain is `chain` — `data.light_combo` or `data.heavy_combo`.
func is_running_chain(chain: Array[AttackData]) -> bool:
	return is_same(chain, _chain)


## The attack accepted to follow the current one, or null.
func get_queued_attack() -> AttackData:
	return _next_attack


func has_buffered_attack() -> bool:
	return _buffered_attack > 0.0


## Whether the player may turn toward where it is walking. Only when free: an
## attack commits to the direction it was aimed in, and a dodge to its own.
func allows_turning() -> bool:
	return _state == State.IDLE


## Scales the player's movement speed for whatever is running now.
func get_movement_multiplier() -> float:
	if _attack != null:
		return _attack.movement_multiplier
	return 1.0


## The one place a player attack's damage is worked out: the character's base,
## scaled by the attack, then by the weapon and STR. It runs once per swing, when
## the hit window opens, so every target that swing reaches takes the same
## number, and neither the attack nor the base is ever written.
func calculate_damage(attack: AttackData) -> float:
	var base: float = data.base_damage * attack.damage_multiplier
	if _progression == null:
		return base
	return _progression.get_effective_damage(base)


# --- the timeline ---------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if _state == State.DODGING:
		_advance_dodge(delta)
		return
	if _dodge_cooldown_remaining > 0.0:
		_dodge_cooldown_remaining = maxf(0.0, _dodge_cooldown_remaining - delta)
	if is_attacking():
		_advance_attack(delta)
	if _buffered_attack > 0.0:
		_buffered_attack = maxf(0.0, _buffered_attack - delta)


func _advance_attack(delta: float) -> void:
	_state_elapsed += delta
	match _state:
		State.WINDUP:
			if _state_elapsed >= _attack.windup:
				_open_hit_window()
		State.ACTIVE:
			if _state_elapsed >= _attack.active:
				_close_hit_window()
				_enter(State.RECOVERY)
		State.RECOVERY:
			if _buffered_attack > 0.0 and _next_attack == null and _in_combo_window():
				_queue_next_attack()
			if _state_elapsed >= _attack.recovery:
				_end_attack()


func _advance_dodge(delta: float) -> void:
	_state_elapsed += delta
	if _state_elapsed >= data.dodge_duration:
		_enter_dodge_phase(DodgePhase.NONE)
		_enter(State.IDLE)
		_dodge_cooldown_remaining = data.dodge_cooldown
	elif _state_elapsed >= data.invulnerability_end:
		_enter_dodge_phase(DodgePhase.RECOVERY)
	elif _state_elapsed >= data.invulnerability_start:
		_enter_dodge_phase(DodgePhase.INVULNERABLE)


func _enter_dodge_phase(phase: DodgePhase) -> void:
	if phase == _dodge_phase:
		return
	_dodge_phase = phase
	_set_iframes(phase == DodgePhase.INVULNERABLE)
	_log("dodge %s" % DodgePhase.keys()[phase])


# --- chains -----------------------------------------------------------------------------------

func _has_next_attack() -> bool:
	return _combo_index + 1 < _chain.size()


## The window in which the current attack accepts the next one: a stretch of its
## recovery, given as fractions of it by the attack itself.
func _in_combo_window() -> bool:
	if _state != State.RECOVERY or not _has_next_attack():
		return false
	return _state_elapsed >= _attack.recovery * _attack.combo_window_start \
		and _state_elapsed <= _attack.recovery * _attack.combo_window_end


func _combo_window_passed() -> bool:
	return _state == State.RECOVERY and _state_elapsed > _attack.recovery * _attack.combo_window_end


func _queue_next_attack() -> void:
	_next_attack = _chain[_combo_index + 1]
	_buffered_attack = 0.0
	_log("queued %s" % _next_attack.id)


## Starts the attack at `index` in `chain` — a fresh instance: its own timeline,
## its own hit window, nobody hit yet.
func _start_attack(chain: Array[AttackData], index: int) -> bool:
	if index < 0 or index >= chain.size() or chain[index] == null:
		return false
	_chain = chain
	_attack = chain[index]
	_combo_index = index
	_next_attack = null
	_buffered_attack = 0.0
	_enter(State.WINDUP)
	attack_started.emit(_attack)
	return true


## The hit window: the hitbox takes this swing's damage and its name, and opens.
## activate() also forgets whom the previous swing hit, so each swing can reach
## every target once — and any number of targets.
func _open_hit_window() -> void:
	_enter(State.ACTIVE)
	if _hitbox == null:
		return
	_hitbox.damage = calculate_damage(_attack)
	_hitbox.attack_id = _attack.id
	_hitbox.set_debug_color(_attack.debug_color)
	_hitbox.activate()


func _close_hit_window() -> void:
	if _hitbox != null and _hitbox.is_active():
		_hitbox.deactivate()


## The attack is over: the queued one follows at once, or the chain ends here.
func _end_attack() -> void:
	if _next_attack != null:
		_start_attack(_chain, _combo_index + 1)
		return
	_attack = null
	_end_chain()
	_enter(State.IDLE)


## Ends the current attack wherever it is, closing its hit window.
func _stop_attack() -> void:
	_close_hit_window()
	_attack = null


## Nothing of the chain is kept: the next attack will be the first.
func _end_chain() -> void:
	_chain = NO_CHAIN
	_combo_index = NO_ATTACK
	_next_attack = null
	_buffered_attack = 0.0


func _in_dodge_cancel_window() -> bool:
	if _state != State.RECOVERY or _attack == null:
		return false
	return _state_elapsed >= _attack.recovery * _attack.dodge_cancel_recovery_fraction


# --- state ----------------------------------------------------------------------------------

func _enter(state: State) -> void:
	_state = state
	_state_elapsed = 0.0
	_log(State.keys()[state])


func _log(what: String) -> void:
	if not debug_log_enabled:
		return
	print("[PlayerCombat] %s  attack=%s (%d/%d)  queued=%s  buffered=%.2fs  dodge=%s  iframes=%s" % [
		what, _attack.id if _attack != null else &"-", _combo_index + 1, _chain.size(),
		_next_attack.id if _next_attack != null else &"-", _buffered_attack,
		DodgePhase.keys()[_dodge_phase], _iframes_active])


func _set_iframes(value: bool) -> void:
	if value == _iframes_active:
		return
	_iframes_active = value
	if _hurtbox != null:
		_hurtbox.set_invulnerable(value, IFRAMES_REASON)


func _on_owner_died() -> void:
	reset()
