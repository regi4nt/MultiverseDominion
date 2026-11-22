class_name DiceSystem
extends RefCounted
## Two D6. TODO (later phase): Special Dice (reroll / movement / teleport / gold / portal / turn order).


static func roll(rng: RandomNumberGenerator) -> Vector2i:
	return Vector2i(rng.randi_range(1, 6), rng.randi_range(1, 6))
