class_name ShadowInstance
extends RefCounted

## One extracted shadow, as opposed to the type it belongs to.
##
## An id that tells it apart from every other extraction, the ShadowData it came
## from, and the progression that belongs to this one shadow rather than to its
## type. Rank and equipment are still later milestones.

var instance_id: StringName = &""
var shadow_data: ShadowData = null
var level: int = 1
var current_xp: int = 0


func _init(id: StringName = &"", data: ShadowData = null, start_level: int = 1,
		start_xp: int = 0) -> void:
	instance_id = id
	shadow_data = data
	level = maxi(1, start_level)
	current_xp = maxi(0, start_xp)


func get_display_name() -> String:
	return shadow_data.display_name if shadow_data != null else "Unknown Shadow"


func get_data_id() -> StringName:
	return shadow_data.id if shadow_data != null else &""


## "#000007" — short enough for a list row, unique within the session.
func get_short_id() -> String:
	var text: String = String(instance_id)
	var underscore: int = text.rfind("_")
	return "#" + (text.substr(underscore + 1) if underscore >= 0 else text)


# --- progression ------------------------------------------------------------------
# The numbers come from the ShadowData; this holds where this one shadow has got
# to. Nothing here reaches into the scene tree, so an instance is just as valid
# sitting in a menu as it is summoned.

func get_xp_to_next_level() -> int:
	return shadow_data.xp_required_for_level(level) if shadow_data != null else 0


func get_xp_ratio() -> float:
	var required: int = get_xp_to_next_level()
	return 0.0 if required <= 0 else clampf(float(current_xp) / float(required), 0.0, 1.0)


func get_max_health() -> float:
	return shadow_data.health_at_level(level) if shadow_data != null else 0.0


func get_damage() -> float:
	return shadow_data.damage_at_level(level) if shadow_data != null else 0.0


## Adds XP and levels up as many times as it allows. Returns how many levels were
## gained, so the caller can report one level-up rather than a burst. The loop is
## bounded by the requirement always being positive.
func add_xp(amount: int) -> int:
	if amount <= 0 or shadow_data == null:
		return 0
	current_xp += amount
	var gained: int = 0
	while true:
		var required: int = get_xp_to_next_level()
		if required <= 0 or current_xp < required:
			break
		current_xp -= required
		level += 1
		gained += 1
	return gained
