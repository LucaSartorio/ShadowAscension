class_name BossPhaseController
extends RefCounted

## Which phase a boss fight is in (M12.8), and which it is due for — the one
## owner of that answer. Pure logic: no scene tree, no timers. The boss asks it
## when its health changes, runs the transition beat itself, and tells it when
## the new phase begins.
##
##     not started (-1) --start()--> phase 0 --enter(n)--> phase n  (n only ever grows)
##
## Monotonic: a phase is due when the health share has fallen to its threshold,
## and only a phase after the current one can be due, so a heal never brings an
## earlier phase back and a health that wobbles round a threshold never flips.
## One blow that crosses several thresholds is due for the deepest of them: the
## phases in between are passed over, deterministically.

var _phases: Array[BossPhaseData] = []
var _index: int = -1


func configure(phases: Array[BossPhaseData]) -> void:
	_phases = phases
	_index = -1


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


## The fight is now in phase `index` — only ever forward; anything else is
## refused, and false.
func enter(index: int) -> bool:
	if index <= _index or index >= _phases.size():
		return false
	_index = index
	return true
