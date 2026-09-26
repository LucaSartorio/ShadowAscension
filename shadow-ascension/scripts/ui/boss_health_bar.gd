class_name BossHealthBar
extends CanvasLayer

## Temporary boss health readout. Hidden until an encounter starts, gone when the
## boss dies. Deliberately not a HUD framework — M5.2 replaces it.
##
## It finds the boss through the `boss` group and listens; the boss knows nothing
## about any UI. One bar for the one pool: a phase changes the caption, never the
## bar — nothing refills or resets it.

@onready var root: Control = $Root
@onready var name_label: Label = $Root/NameLabel
@onready var bar: ProgressBar = $Root/Bar
@onready var phase_label: Label = $Root/PhaseLabel
## Flashed when the fight changes gear. Separate from phase_label so the standing
## readout and the momentary callout do not fight over one node.
@onready var banner: Label = $Root/Banner

## How long the phase callout stays up.
@export var banner_duration: float = 1.5
## The phase caption, numbered from 1 — the boss reports indices, the wording
## lives here, in the player's language. Empty hides the caption.
@export var phase_text_format: String = "FASE %d"

var _health: HealthComponent = null
var _banner_tween: Tween = null


func _ready() -> void:
	root.visible = false
	var boss: DungeonBoss = get_tree().get_first_node_in_group(DungeonBoss.GROUP) as DungeonBoss
	if boss == null:
		return
	banner.visible = false
	boss.encounter_started.connect(_on_encounter_started)
	boss.phase_transition_started.connect(_on_phase_transition_started)
	boss.phase_changed.connect(_on_phase_changed)
	boss.enemy_died.connect(_on_boss_died)


func is_showing() -> bool:
	return root.visible


func get_ratio() -> float:
	if bar.max_value <= 0.0:
		return 0.0
	return bar.value / bar.max_value


func _on_encounter_started(display_name: String, health: HealthComponent) -> void:
	_health = health
	name_label.text = display_name
	bar.max_value = health.max_health
	bar.value = health.current_health
	root.visible = true
	if not health.health_changed.is_connected(_on_health_changed):
		health.health_changed.connect(_on_health_changed)


func get_phase_text() -> String:
	return phase_label.text


func is_banner_showing() -> bool:
	return banner.visible


## The boss says which phase it is in; the wording lives here, with the UI.
func _on_phase_changed(index: int) -> void:
	phase_label.text = _phase_text(index)


## The callout announces what is coming, during the beat itself.
func _on_phase_transition_started(to_index: int) -> void:
	phase_label.text = _phase_text(to_index)
	_flash_banner()


func _phase_text(index: int) -> String:
	if phase_text_format.is_empty() or index < 0:
		return ""
	return phase_text_format % (index + 1)


func _flash_banner() -> void:
	if _banner_tween != null and _banner_tween.is_running():
		_banner_tween.kill()
	banner.visible = true
	banner.modulate.a = 1.0
	# Node-bound, so leaving the scene mid-flash cannot strand a coroutine.
	_banner_tween = create_tween()
	_banner_tween.tween_interval(banner_duration)
	_banner_tween.tween_property(banner, "modulate:a", 0.0, 0.3)
	_banner_tween.tween_callback(func() -> void: banner.visible = false)


func _on_health_changed(current: float, maximum: float) -> void:
	bar.max_value = maximum
	bar.value = current


func _on_boss_died(_combatant: RoomCombatant) -> void:
	if _banner_tween != null and _banner_tween.is_running():
		_banner_tween.kill()
	banner.visible = false
	root.visible = false
	_health = null
