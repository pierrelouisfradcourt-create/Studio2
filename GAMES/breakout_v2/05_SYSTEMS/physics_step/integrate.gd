# integrate.gd — ligne physics.continuous_integration. Integre la position de la balle sur
# un pas fixe. Ne resout AUCUNE collision. RefCounted, pur.
extends RefCounted

# Un pas : p' = p + v * dt. Meme expression que ball.pas_libre (cinematique partagee).
static func integrer(pos: Vector2, vel: Vector2, dt: float) -> Vector2:
	return pos + vel * dt

# Forme fermee sur n pas SANS collision : p_n = p0 + v * (dt * n). Utilisee par
# integration_exact.test.gd, qui recompose la meme valeur composante par composante ->
# egalite flottante stricte (un mutant sur l'associativite (v*dt)*n serait detecte).
static func integrer_n(pos: Vector2, vel: Vector2, dt: float, n: int) -> Vector2:
	return pos + vel * (dt * float(n))
