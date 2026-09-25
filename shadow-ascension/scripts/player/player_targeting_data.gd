class_name PlayerTargetingData
extends Resource

## The player's target lock configuration: how far it reaches, how it picks,
## how fast the player turns to face what it holds. Shared and never written in
## play — what is locked right now lives on PlayerTargeting.

## A target further than this, flat on the ground, is not acquired — by a lock
## or a switch.
@export_range(0.0, 100.0, 0.5, "or_greater") var acquisition_range: float = 15.0
## A held target further than this is let go. Longer than acquisition_range, so
## one standing near the edge does not flicker in and out of the lock.
@export_range(0.0, 100.0, 0.5, "or_greater") var lose_range: float = 18.0
## How much one metre of distance weighs against one degree of angle off the
## camera's view when a lock picks its target: lower score wins. At 3, a target
## straight ahead at 10 m beats one 40 degrees off at 1 m.
@export_range(0.0, 90.0, 0.1, "or_greater") var distance_weight: float = 3.0
## How fast the player turns to face a locked target, in radians per second.
@export_range(0.0, 50.0, 0.5, "or_greater") var rotation_speed: float = 12.0
## The bodies a lock can find: enemy bodies (layer 3). Only RoomCombatants among
## them count — the type decides, not the layer alone.
@export_flags_3d_physics var target_body_mask: int = 4
## What blocks the view to a target when it is acquired: the world (layer 1).
@export_flags_3d_physics var line_of_sight_mask: int = 1
## Where the view is taken from, above the player's feet.
@export_range(0.0, 5.0, 0.05) var eye_height: float = 1.2
## The most bodies one search looks at.
@export_range(1, 256, 1) var max_candidates: int = 32
