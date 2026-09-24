extends Area3D

@export var damage_per_tick: float = 15.0
@export var tick_interval: float = 0.5

var _elapsed: float = 0.0


func _ready() -> void:
	monitoring = true
	monitorable = false


func _physics_process(delta: float) -> void:
	_elapsed += delta
	if _elapsed < tick_interval:
		return
	_elapsed = 0.0
	for area in get_overlapping_areas():
		var hb: Hurtbox = area as Hurtbox
		if hb != null:
			hb.receive_hit(DamageInfo.new(damage_per_tick, self))
