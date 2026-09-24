class_name PlayerStaminaHUD
extends CanvasLayer

## The player's stamina: a thin bar directly under the health bar, top-left.
##
## Its own node, like PlayerHealthHUD beside it: stamina is combat's resource,
## health is the body's, and each bar hears only its own owner. Driven entirely
## by PlayerCombat's `stamina_changed` — it never reads stamina per frame, and it
## holds none: what it shows is what it was last told. It decides nothing either;
## whether a dodge can be paid for is combat's question, not the bar's.

const GROUP: StringName = &"player_stamina_hud"

@onready var root: Control = $Root
@onready var bar: ProgressBar = $Root/StaminaBar

var _combat: PlayerCombat = null


func _ready() -> void:
	add_to_group(GROUP)
	# One frame: the player comes up in the same scene and its components are
	# not resolved until its own _ready() has run.
	call_deferred("_subscribe")


func _subscribe() -> void:
	var player: Player = get_tree().get_first_node_in_group(Player.GROUP) as Player
	if player == null or player.combat == null:
		root.visible = false
		return
	_combat = player.combat
	_combat.stamina_changed.connect(_on_stamina_changed)
	_on_stamina_changed(_combat.get_stamina(), _combat.get_max_stamina())


func get_ratio() -> float:
	if bar.max_value <= 0.0:
		return 0.0
	return bar.value / bar.max_value


func is_showing() -> bool:
	return root.visible


func _on_stamina_changed(current: float, maximum: float) -> void:
	bar.max_value = maxf(maximum, 1.0)
	bar.value = clampf(current, 0.0, bar.max_value)
