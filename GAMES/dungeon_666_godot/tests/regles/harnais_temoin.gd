extends RefCounted
## Témoin du harnais : prouve que le harnais joue une partie et que ses affirmations comptent.

static func tests(h) -> void:
	h.test("témoin : une partie se crée et avance", func():
		var g: Dictionary = h.bac_a_sable({"seed": 3.0})
		h.egal(g.mode, "play")
		var x0: float = g.player.x
		h.avancer(g, h.ticks(0.5), {"moveX": 1.0})
		h.ok(g.player.x > x0, "le héros avance vers la droite")
		h.proche(g.tick, 30.0, 0.0))
