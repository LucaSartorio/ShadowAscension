class_name PlayerCombat
extends Node

## The player's combat controller: what the player may do in a fight, and when.
##
## It turns an intent into a committed action and runs that action's timeline:
##
##     request_attack() -> WINDUP -> ACTIVE (hitbox open) -> RECOVERY -> IDLE
##                                                                 \-> the next attack
##     request_dodge()  -> DODGING (i-frames inside it) -> IDLE, then a cooldown
##
## It owns the combat state, the attack timeline, the input buffer, the combo
## chain, the hit window, and the dodge's timing and i-frames. Everything else is
## someone else's: the devices are read by the player (camera rig and player
## script), which only calls request_*(); the body is moved by the player, which
## asks this what the current action allows; the representation is played by the
## player on attack_started. A hit leaves through the hitbox as a DamageInfo, and
## whatever it lands on resolves it — this never touches a health bar, an enemy,
## XP or the dungeon.
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

@export var data: PlayerCombatData

@export_group("DEBUG")
## DEBUG ONLY. Off by default; the game never needs it. Prints every state change
## with the attack it belongs to — for tuning windows, not for play.
@export var debug_log_enabled: bool = false

# Handed over by the player in setup().
var _hitbox: Hitbox = null
var _hurtbox: Hurtbox = null
var _health: HealthComponent = null
var _progression: PlayerProgression = null

var _state: State = State.IDLE
## Time spent in the current state, reset on every change.
var _state_elapsed: float = 0.0
## The attack being performed, or null.
var _attack: AttackData = null
## Index in the light combo of the attack that starts next.
var _combo_index: int = 0
## How long the chain has been waiting since the last attack ended, and how long
## that attack said it would wait.
var _chain_idle: float = 0.0
var _chain_window: float = 0.0
## Seconds a buffered attack press has left; 0 when there is none. One slot, not
## a queue: pressing again only renews it.
var _buffered_attack: float = 0.0
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

## A light attack was asked for. Starts one now if the player is free; while an
## attack is running, remembers the press for `input_buffer_time`; otherwise —
## dodging, dead — ignores it. True when an attack started.
func request_attack() -> bool:
	match get_state():
		State.IDLE:
			return _start_next_attack()
		State.WINDUP, State.ACTIVE, State.RECOVERY:
			_buffered_attack = data.input_buffer_time
	return false


## A dodge was asked for. Refused while dodging, dead, on cooldown, or during an
## attack before its dodge-cancel window; an attack inside that window is
## cancelled. Whichever way it starts, the combo starts over. True when a dodge
## started.
func request_dodge() -> bool:
	var state: State = get_state()
	if state == State.DODGING or state == State.DEAD:
		return false
	if _dodge_cooldown_remaining > 0.0:
		return false
	if is_attacking():
		if not _in_dodge_cancel_window():
			return false
		_stop_attack()
	_restart_chain()
	_enter(State.DODGING)
	# Off at the start as well as the end, exactly as the dodge always did: the
	# window below switches it on only once the dodge is under way.
	_set_iframes(false, true)
	return true


## Drops whatever combat was doing and starts clean: no attack and no hit window,
## no dodge and no i-frames, nothing buffered, the combo from its first attack,
## no cooldown. What a death does.
func reset() -> void:
	_stop_attack()
	_set_iframes(false)
	_enter(State.IDLE)
	_restart_chain()
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


## The attack being performed, or null.
func get_current_attack() -> AttackData:
	return _attack


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
	if _state == State.IDLE:
		_advance_chain(delta)
	else:
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
			if _buffered_attack > 0.0 and _has_next_attack() \
					and _state_elapsed >= _attack.recovery * _attack.combo_window_start:
				_start_next_attack()
			elif _state_elapsed >= _attack.recovery:
				_finish_attack()


## While free after an attack that is not the last, the chain waits that
## attack's combo_window_end for the next one, then lapses.
func _advance_chain(delta: float) -> void:
	if _combo_index <= 0:
		return
	_chain_idle += delta
	if _chain_idle >= _chain_window:
		_restart_chain()


func _advance_dodge(delta: float) -> void:
	_state_elapsed += delta
	_set_iframes(_state_elapsed >= data.invulnerability_start
		and _state_elapsed < data.invulnerability_end)
	if _state_elapsed >= data.dodge_duration:
		_set_iframes(false, true)
		_enter(State.IDLE)
		_dodge_cooldown_remaining = data.dodge_cooldown


# --- attacks --------------------------------------------------------------------------------

func _has_next_attack() -> bool:
	return _combo_index < data.light_combo.size()


func _start_next_attack() -> bool:
	var combo: Array[AttackData] = data.light_combo
	if combo.is_empty():
		return false
	if _combo_index < 0 or _combo_index >= combo.size():
		_combo_index = 0
	var attack: AttackData = combo[_combo_index]
	if attack == null:
		return false
	_combo_index += 1
	_buffered_attack = 0.0
	_chain_idle = 0.0
	_attack = attack
	_enter(State.WINDUP)
	attack_started.emit(attack)
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


## Over, with nothing buffered in time. After the last attack the chain ends;
## otherwise it waits for the next.
func _finish_attack() -> void:
	var finished: AttackData = _attack
	_attack = null
	_enter(State.IDLE)
	if _has_next_attack():
		_chain_window = finished.combo_window_end
		_chain_idle = 0.0
	else:
		_restart_chain()


## Ends the current attack wherever it is, closing its hit window.
func _stop_attack() -> void:
	_close_hit_window()
	_attack = null


func _restart_chain() -> void:
	_combo_index = 0
	_chain_idle = 0.0
	_buffered_attack = 0.0


func _in_dodge_cancel_window() -> bool:
	if _state != State.RECOVERY or _attack == null:
		return false
	return _state_elapsed >= _attack.recovery * _attack.dodge_cancel_recovery_fraction


# --- state ----------------------------------------------------------------------------------

func _enter(state: State) -> void:
	_state = state
	_state_elapsed = 0.0
	if debug_log_enabled:
		print("[PlayerCombat] %s %s" % [State.keys()[state], _attack.id if _attack != null else &""])


## `force` writes the hurtbox even when the value has not changed.
func _set_iframes(value: bool, force: bool = false) -> void:
	if value == _iframes_active and not force:
		return
	_iframes_active = value
	if _hurtbox != null:
		_hurtbox.set_invulnerable(value)


func _on_owner_died() -> void:
	reset()
