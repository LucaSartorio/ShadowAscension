class_name TrainingDummy
extends CharacterBody3D

@export var gravity: float = 20.0

@onready var health_component: HealthComponent = $HealthComponent
@onready var hurtbox: Hurtbox = $Hurtbox
@onready var body_collision: CollisionShape3D = $CollisionShape3D
@onready var hurtbox_collision: CollisionShape3D = $Hurtbox/CollisionShape3D
@onready var visual_root: Node3D = $VisualRoot

var _dead: bool = false


func _ready() -> void:
	health_component.died.connect(_on_died)


func _physics_process(delta: float) -> void:
	if _dead:
		return
	if is_on_floor():
		if velocity.y < 0.0:
			velocity.y = 0.0
	else:
		velocity.y -= gravity * delta
	move_and_slide()


func _on_died() -> void:
	_dead = true
	body_collision.call_deferred("set_disabled", true)
	hurtbox.call_deferred("set_monitorable", false)
	hurtbox_collision.call_deferred("set_disabled", true)
	if visual_root != null:
		var tween: Tween = create_tween()
		tween.tween_property(visual_root, "rotation:x", deg_to_rad(90.0), 0.4)
