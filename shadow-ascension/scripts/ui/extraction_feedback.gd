class_name ExtractionFeedback
extends CanvasLayer

## The banner the shadow system puts on screen: an extraction attempt, and the
## life of a summoned shadow. Deliberately not a notification framework: two
## lines, a colour and a timer.
##
## It never pauses the game — none of this is a menu.

const GROUP: StringName = &"extraction_feedback"

@export var processing_text: String = "ESTRAZIONE..."
@export var success_text: String = "ESTRAZIONE RIUSCITA"
@export var failure_text: String = "ESTRAZIONE FALLITA"
@export var success_color: Color = Color(0.6, 0.9, 1.0)
@export var failure_color: Color = Color(0.95, 0.45, 0.4)
@export var neutral_color: Color = Color(0.85, 0.85, 0.92)

@export_group("Summoning")
@export var summon_text: String = "OMBRA EVOCATA"
@export var recall_text: String = "OMBRA RICHIAMATA"
@export var defeat_text: String = "OMBRA SCONFITTA"
@export var level_up_format: String = "OMBRA LIVELLO %d"
@export var mode_format: String = "OMBRA: %s"
@export var follow_text: String = "FOLLOW"
@export var aggressive_text: String = "AGGRESSIVE"
@export var summon_color: Color = Color(0.72, 0.58, 1.0)
@export var level_up_color: Color = Color(1.0, 0.85, 0.45)
@export var banner_duration: float = 1.6

@onready var root: Control = $Root
@onready var title_label: Label = $Root/Title
@onready var detail_label: Label = $Root/Detail

var _tween: Tween = null


func _ready() -> void:
	add_to_group(GROUP)
	root.visible = false
	# One frame: this HUD and the player come up in the same scene, and its
	# components are not resolved until its own _ready() has run.
	call_deferred("_subscribe")


## The extraction result is pushed in by the remnant, but a summon, a recall, a
## death and a level-up all happen away from any one caller — so the banner
## listens for those rather than having four systems reach for it.
func _subscribe() -> void:
	var player: Player = get_tree().get_first_node_in_group(Player.GROUP) as Player
	if player == null:
		return
	if player.shadows != null:
		player.shadows.shadow_leveled_up.connect(_on_shadow_leveled_up)
	var summoner: PlayerShadowSummoner = player.shadow_summoner
	if summoner == null:
		return
	summoner.shadow_summoned.connect(_on_shadow_summoned)
	summoner.shadow_recalled.connect(_on_shadow_recalled)
	summoner.shadow_defeated.connect(_on_shadow_defeated)
	var commander: PlayerShadowCommander = player.shadow_commander
	if commander != null:
		# An order that found nothing is worth one line. The commander decides
		# there is nothing to act on; saying so is this layer's job.
		commander.command_rejected.connect(_on_command_rejected)


func _on_shadow_leveled_up(shadow: ShadowInstance, _levels: int) -> void:
	show_message(level_up_format % shadow.level, _describe(shadow), level_up_color)


func _on_shadow_summoned(shadow: ShadowInstance, node: BasicMeleeShadow) -> void:
	show_message(summon_text, _describe(shadow), summon_color)
	# Per node rather than through the commander: the mode belongs to the
	# entity, and a re-summon brings a different one.
	node.command_mode_changed.connect(_on_command_mode_changed)


func _on_command_mode_changed(mode: BasicMeleeShadow.CommandMode) -> void:
	show_message(mode_format % (follow_text
		if mode == BasicMeleeShadow.CommandMode.FOLLOW else aggressive_text),
		"", summon_color)


func _on_command_rejected(reason: String) -> void:
	show_message(reason, "", neutral_color)


func _on_shadow_recalled(shadow: ShadowInstance) -> void:
	show_message(recall_text, _describe(shadow), neutral_color)


func _on_shadow_defeated(shadow: ShadowInstance) -> void:
	show_message(defeat_text, _describe(shadow), failure_color)


func _describe(shadow: ShadowInstance) -> String:
	if shadow == null:
		return ""
	return "%s  %s  Lv.%d" % [
		shadow.get_short_id(), shadow.get_display_name(), shadow.level]


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
	var detail: String = "%s  %s" % [shadow.get_short_id(), shadow.get_display_name()] \
		if success and shadow != null else ""
	show_message(
		success_text if success else failure_text,
		detail,
		success_color if success else failure_color,
		duration)


## The same two lines every caller gets. `duration` defaults to the banner's own
## so a caller only passes one when it needs a different beat.
func show_message(title: String, detail: String, color: Color, duration: float = -1.0) -> void:
	_kill()
	title_label.text = title
	title_label.add_theme_color_override("font_color", color)
	detail_label.text = detail
	root.visible = true
	# Node-bound, so leaving the scene mid-banner cannot strand a coroutine.
	_tween = create_tween()
	_tween.tween_interval(duration if duration > 0.0 else banner_duration)
	_tween.tween_callback(func() -> void: root.visible = false)


func _kill() -> void:
	if _tween != null and _tween.is_running():
		_tween.kill()
