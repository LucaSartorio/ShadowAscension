class_name ActiveShadowHUD
extends CanvasLayer

## Everything about the shadow that is out: who it is, how hurt it is, what mode
## it is fighting in, and what the player can order it to do.
##
## Hidden entirely when nothing is summoned — there is no such thing as an empty
## shadow panel. Driven by signals throughout: health comes from
## `health_changed`, not from reading the component every frame, so a shadow that
## is not being hit costs nothing to display.
##
## The command hints live here rather than in the bottom-right menu-hint column
## because they only apply while a shadow is out, and a hint that comes and goes
## in a fixed column would shuffle the ones below it.

const GROUP: StringName = &"active_shadow_hud"

@onready var root: Control = $Root
@onready var name_label: Label = $Root/Panel/Content/NameLabel
@onready var level_label: Label = $Root/Panel/Content/LevelLabel
@onready var health_bar: ProgressBar = $Root/Panel/Content/HealthBar
@onready var health_label: Label = $Root/Panel/Content/HealthLabel
@onready var mode_label: Label = $Root/Panel/Content/ModeLabel
@onready var hints_label: Label = $Root/Panel/Content/Hints

@export var level_format: String = "Lv. %d"
@export var health_format: String = "%d / %d"
@export var mode_format: String = "Modalità: %s"
@export var follow_text: String = "FOLLOW"
@export var aggressive_text: String = "AGGRESSIVE"
## `[KEY] Action`, the house format. Filled in from the real InputMap at
## startup, so a rebound key cannot leave the hint lying.
@export var hint_recall: String = "Torna da me"
@export var hint_mode: String = "Modalità"
@export var hint_attack: String = "Attacca bersaglio"

var _summoner: PlayerShadowSummoner = null
var _collection: PlayerShadowCollection = null
var _shadow: BasicMeleeShadow = null
var _instance: ShadowInstance = null
var _health: HealthComponent = null


func _ready() -> void:
	add_to_group(GROUP)
	root.visible = false
	hints_label.text = _build_hints()
	# One frame: this HUD and the player come up in the same scene, and the
	# player's components are not resolved until its own _ready() has run.
	call_deferred("_subscribe")


func _subscribe() -> void:
	var player: Player = get_tree().get_first_node_in_group(Player.GROUP) as Player
	if player == null:
		return
	_collection = player.shadows
	if _collection != null:
		_collection.collection_changed.connect(_refresh_identity)
	_summoner = player.shadow_summoner
	if _summoner == null:
		return
	_summoner.shadow_summoned.connect(_on_summoned)
	_summoner.shadow_recalled.connect(_on_gone)
	_summoner.shadow_defeated.connect(_on_gone)
	# A shadow summoned before this HUD finished subscribing — the automatic
	# re-summon after a scene change is exactly that — is picked up here.
	if _summoner.has_active_shadow():
		_on_summoned(_collection.get_shadow(_summoner.get_active_instance_id()),
			_summoner.get_active_node())


# --- queries for tests and for anything that wants to read the panel -----------------

func is_showing() -> bool:
	return root.visible


func get_name_text() -> String:
	return name_label.text


func get_level_text() -> String:
	return level_label.text


func get_health_text() -> String:
	return health_label.text


func get_mode_text() -> String:
	return mode_label.text


func get_hints_text() -> String:
	return hints_label.text


func get_health_ratio() -> float:
	if health_bar.max_value <= 0.0:
		return 0.0
	return health_bar.value / health_bar.max_value


# --- the shadow coming and going ---------------------------------------------------------

func _on_summoned(instance: ShadowInstance, node: BasicMeleeShadow) -> void:
	_disconnect_current()
	_instance = instance
	_shadow = node
	if node == null:
		return
	_health = node.health_component
	if _health != null:
		_health.health_changed.connect(_on_health_changed)
	node.command_mode_changed.connect(_on_mode_changed)
	root.visible = true
	_refresh_identity()
	_on_mode_changed(node.command_mode)
	if _health != null:
		_on_health_changed(_health.current_health, _health.max_health)


func _on_gone(_instance: ShadowInstance) -> void:
	_disconnect_current()
	root.visible = false


func _disconnect_current() -> void:
	if _health != null and is_instance_valid(_health) \
			and _health.health_changed.is_connected(_on_health_changed):
		_health.health_changed.disconnect(_on_health_changed)
	if _shadow != null and is_instance_valid(_shadow) \
			and _shadow.command_mode_changed.is_connected(_on_mode_changed):
		_shadow.command_mode_changed.disconnect(_on_mode_changed)
	_health = null
	_shadow = null
	_instance = null


# --- content --------------------------------------------------------------------------------

## Name and level. Re-read on any collection change, which is how a level earned
## mid-fight reaches the panel — the health that level bought arrives separately,
## through `health_changed`.
func _refresh_identity() -> void:
	if _instance == null or not root.visible:
		return
	name_label.text = _instance.get_display_name().to_upper()
	level_label.text = level_format % _instance.level


func _on_health_changed(current: float, maximum: float) -> void:
	health_bar.max_value = maxf(maximum, 1.0)
	health_bar.value = clampf(current, 0.0, health_bar.max_value)
	health_label.text = health_format % [roundi(current), roundi(maximum)]


func _on_mode_changed(mode: BasicMeleeShadow.CommandMode) -> void:
	mode_label.text = mode_format % (
		follow_text if mode == BasicMeleeShadow.CommandMode.FOLLOW else aggressive_text)


## Reads the real bindings, so the hints cannot drift from the InputMap.
func _build_hints() -> String:
	return "\n".join([
		"[%s] %s" % [_key_for(PlayerShadowCommander.ACTION_RECALL), hint_recall],
		"[%s] %s" % [_key_for(PlayerShadowCommander.ACTION_MODE_TOGGLE), hint_mode],
		"[%s] %s" % [_key_for(PlayerShadowCommander.ACTION_ATTACK_COMMAND), hint_attack],
	])


func _key_for(action: StringName) -> String:
	if not InputMap.has_action(action):
		return "?"
	for event in InputMap.action_get_events(action):
		var key: InputEventKey = event as InputEventKey
		if key != null:
			return OS.get_keycode_string(
				key.physical_keycode if key.physical_keycode != 0 else key.keycode)
		var button: InputEventMouseButton = event as InputEventMouseButton
		if button != null:
			match button.button_index:
				MOUSE_BUTTON_LEFT:
					return "LMB"
				MOUSE_BUTTON_RIGHT:
					return "RMB"
				MOUSE_BUTTON_MIDDLE:
					return "MMB"
				_:
					return "M%d" % button.button_index
	return "?"
