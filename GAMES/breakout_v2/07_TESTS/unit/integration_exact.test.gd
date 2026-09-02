# integration_exact.test.gd — ligne physics.continuous_integration. Un pas = p + v*dt ;
# n pas fermes = p + v*(dt*n). Egalite flottante STRICTE (valeurs exactement representables).
extends RefCounted

const Integrate = preload("res://05_SYSTEMS/physics_step/integrate.gd")

func run(h) -> void:
	# Un pas, valeurs exactement representables (dt=0.5).
	var p := Vector2(10.0, 20.0)
	var v := Vector2(4.0, -6.0)
	h.eq(Integrate.integrer(p, v, 0.5), Vector2(12.0, 17.0), "integrer un pas exact (10,20)+(4,-6)*0.5")

	# integrer(p, v, dt) == p + v*dt (forme Vector2, tout dt).
	var dt := 0.016
	h.eq(Integrate.integrer(p, v, dt), p + v * dt, "integrer == p + v*dt (forme Vector2)")

	# n pas fermes == p + v*(dt*n), valeurs exactes (dt=0.25, n=4 -> dt*n=1.0).
	h.eq(Integrate.integrer_n(p, v, 0.25, 4), Vector2(14.0, 14.0), "integrer_n 4 pas exact -> p + v*1")
	h.eq(Integrate.integrer_n(p, v, 0.5, 0), p, "integrer_n 0 pas -> position inchangee")

	# integrer_n coherent avec la forme fermee p + v*(dt*n) pour un dt quelconque.
	var n := 5
	h.eq(Integrate.integrer_n(p, v, dt, n), p + v * (dt * float(n)), "integrer_n == p + v*(dt*n)")
