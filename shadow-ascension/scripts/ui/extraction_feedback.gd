class_name ExtractionFeedback
extends CanvasLayer

## The banner an extraction attempt puts on screen. Deliberately not a
## notification framework: two lines, a colour and a timer.
##
## It never pauses the game — an extraction is a beat, not a menu.

const GROUP: StringName = &"extraction_feedback"

@export var processing_text: String = "ESTRAZIONE..."
@export var success_text: String = "ESTRAZIONE RIUSCITA"
@export var failure_text: String = "ESTRAZIONE FALLITA"
@export var success_color: Color = Color(0.6, 0.9, 1.0)
@export var failure_color: Color = Color(0.95, 0.45, 0.4)
@export var neutral_color: Color = Color(0.85, 0.85, 0.92)

@onready var root: Control = $Root
@onready var title_label: Label = $Root/Title
@onready var detail_label: Label = $Root/Detail

var _tween: Tween = null


func _ready() -> void:
	add_to_group(GROUP)
	root.visible = false


func is_showing() -> bool:
	return root.visible


func get_title() -> String:
	return title_label.text


func get_detail() -> String:
	return detail_label.text


func show_processing() -> void:
	_kill()
	title_label.text = processing_text
	title_label.add_theme_color_override("font_color", neutral_color)
	detail_label.text = ""
	root.visible = true


func show_result(success: bool, shadow: ShadowInstance, duration: float) -> void:
	_kill()
	title_label.text = success_text if success else failure_text
	title_label.add_theme_color_override("font_color",
		success_color if success else failure_color)
	detail_label.text = "%s  %s" % [shadow.get_short_id(), shadow.get_display_name()] \
		if success and shadow != null else ""
	root.visible = true
	# Node-bound, so leaving the scene mid-banner cannot strand a coroutine.
	_tween = create_tween()
	_tween.tween_interval(duration)
	_tween.tween_callback(func() -> void: root.visible = false)


func _kill() -> void:
	if _tween != null and _tween.is_running():
		_tween.kill()
