extends CharacterBody2D
class_name SpecialEnemyBody

## Minimal CharacterBody2D with take_damage() so player projectiles can damage
## special event enemies through BaseProjectile's normal body_entered path.

signal killed()

var max_health: float = 100.0
var current_health: float = 100.0
var _dead: bool = false

func _ready() -> void:
	current_health = max_health

func take_damage(amount: float) -> void:
	if _dead:
		return
	current_health -= amount
	_flash()
	if current_health <= 0.0:
		_dead = true
		killed.emit()

func _flash() -> void:
	var spr := get_node_or_null("Sprite2D") as Sprite2D
	if not spr:
		return
	spr.modulate = Color(5.0, 5.0, 5.0, 1.0)
	var tw := spr.create_tween()
	tw.tween_property(spr, "modulate", Color.WHITE, 0.15)
