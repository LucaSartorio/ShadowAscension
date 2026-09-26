class_name BossPhaseController
extends RefCounted

## How far a boss fight has escalated (M12.8; the enrage since M12.9): which
## phase it is in, whether the boss has enraged, and what is due next — the one
## owner of those answers. Pure logic: no scene tree, no timers. The boss asks it
## when its health changes, runs the beats itself, and tells it when each step
## takes hold.
##
##     not started (-1) --start()--> phase 0 --enter(n)--> phase n  (n only grows)
##                                   ... last phase --enrage()--> enraged (for good)
##
## Monotonic: a phase is due when the health share has fallen to its threshold,
## and only a phase after the current one can be due, so a heal never brings an
## earlier phase back and a health that wobbles round a threshold never flips.
## One blow that crosses several thresholds is due for the deepest of them: the
## phases in between are passed over, deterministically.
##
## The enrage comes last: it is due only when no phase is — a blow through a
## phase's threshold and the enrage's is the phase first, the enrage after — and
## it happens once, and is never undone.

var _phases: Array[BossPhaseData] = []
var _enrage: BossEnrageData = null
var _index: int = -1
var _enraged: bool = false


func configure(phases: Array[BossPhaseData], enrage_data: BossEnrageData = null) -> void:
	_phases = phases
	_enrage = enrage_data
	_index = -1
	_enraged = false


## The fight begins in the first phase.
func start() -> void:
	_index = 0 if not _phases.is_empty() else -1


func is_started() -> bool:
	return _index >= 0


## -1 before the fight starts.
func get_index() -> int:
	return _index


func get_count() -> int:
	return _phases.size()


## The phase the fight is in, or null before it starts.
func get_phase() -> BossPhaseData:
	return _phases[_index] if _index >= 0 and _index < _phases.size() else null


func get_phase_at(index: int) -> BossPhaseData:
	return _phases[index] if index >= 0 and index < _phases.size() else null


## The enrage configured, or null.
func get_enrage() -> BossEnrageData:
	return _enrage


func is_enraged() -> bool:
	return _enraged


## The phase due at `health_share` (current / max health): the deepest later
## phase whose threshold that share has reached, or -1 when none is — the
## current phase stands. Never an earlier phase, never the current one.
func due(health_share: float) -> int:
	if _index < 0:
		return -1
	var found: int = -1
	for i in range(_index + 1, _phases.size()):
		if health_share <= _phases[i].health_threshold:
			found = i
	return found


## Whether the enrage is due at `health_share`: configured, not yet happened, the
## share at its threshold, and no phase due before it.
func enrage_due(health_share: float) -> bool:
	return _enrage != null and not _enraged and _index >= 0 \
		and health_share <= _enrage.health_threshold and due(health_share) < 0


## The fight is now in phase `index` — only ever forward; anything else is
## refused, and false.
func enter(index: int) -> bool:
	if index <= _index or index >= _phases.size():
		return false
	_index = index
	return true


## The boss is now enraged, for good. False — and nothing changes — when there
## is no enrage or it has already happened.
func enrage() -> bool:
	if _enrage == null or _enraged or _index < 0:
		return false
	_enraged = true
	return true
