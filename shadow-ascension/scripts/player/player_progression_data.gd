class_name PlayerProgressionData
extends RefCounted

## PERSISTENT PLAYER STATE: where the character's progression has got to, and
## nothing else — level, XP, unspent points and the allocated stat block.
##
## There is one of these per session. PlayerRuntimeState holds it, and every
## PlayerProgression that comes up in a scene holds a reference to this same
## object rather than a copy of its numbers. There is therefore nothing to
## restore when a player scene is built and nothing to write back when it is
## freed: destroying the player destroys a view onto this, never this.
##
## Plain data. The XP curve, the level-up loop and every derived stat belong to
## PlayerProgression, which is the only thing that writes here.

var current_level: int = 1
## Progress into the current level. The remainder after a level-up stays here.
var current_xp: int = 0
var available_stat_points: int = 0

## ALLOCATED stats only. Equipment adds on top when an effective value is asked
## for and is never written here, so taking a piece off cannot leave one inflated.
var strength: int = 10
var agility: int = 10
var vitality: int = 10
var intelligence: int = 10


## A new character, from the starting block `stats` defines. This is the only
## place starting values are ever applied: a player coming up in a scene attaches
## to the session's existing data instead of building its own.
static func from_stats(stats: ProgressionStats) -> PlayerProgressionData:
	var data: PlayerProgressionData = PlayerProgressionData.new()
	if stats == null:
		return data
	data.current_level = stats.starting_level
	data.strength = stats.strength
	data.agility = stats.agility
	data.vitality = stats.vitality
	data.intelligence = stats.intelligence
	return data
