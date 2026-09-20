class_name BossHealthBar
extends CanvasLayer

## Temporary boss health readout. Hidden until an encounter starts, gone when the
## boss dies. Deliberately not a HUD framework — M5.2 replaces it.
##
## It finds the boss through the `boss` group and listens; the boss knows nothing
## about any UI.

@onready var root: Control = $Root
@onready var name_label: Label = $Root/NameLabel
@onready var bar: ProgressBar = $Root/Bar

var _health: HealthComponent = null


func _ready() -> void:
	root.visible = false
	var boss: DungeonBoss = get_tree().get_first_node_in_group(DungeonBoss.GROUP) as DungeonBoss
	if boss == null:
		return
	boss.encounter_started.connect(_on_encounter_started)
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


func _on_health_changed(current: float, maximum: float) -> void:
	bar.max_value = maximum
	bar.value = current


func _on_boss_died(_combatant: RoomCombatant) -> void:
	root.visible = false
	_health = null
