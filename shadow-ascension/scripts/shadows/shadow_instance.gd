class_name ShadowInstance
extends RefCounted

## One extracted shadow, as opposed to the type it belongs to.
##
## Deliberately thin: an id that tells it apart from every other extraction, and
## the ShadowData it came from. Level, XP, rank and equipment are M8.2 and later
## — the point of having an instance at all in M8.1 is that those will have
## somewhere to live without reworking the collection into a per-shadow model.

var instance_id: StringName = &""
var shadow_data: ShadowData = null


func _init(id: StringName = &"", data: ShadowData = null) -> void:
	instance_id = id
	shadow_data = data


func get_display_name() -> String:
	return shadow_data.display_name if shadow_data != null else "Unknown Shadow"


func get_data_id() -> StringName:
	return shadow_data.id if shadow_data != null else &""


## "#000007" — short enough for a list row, unique within the session.
func get_short_id() -> String:
	var text: String = String(instance_id)
	var underscore: int = text.rfind("_")
	return "#" + (text.substr(underscore + 1) if underscore >= 0 else text)
