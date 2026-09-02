# paddle_deflection_three_points.test.gd — ligne physics.paddle_deflection. Angle de rebond
# FONCTION DU POINT D'IMPACT, asserte par EGALITE STRICTE aux 3 points d'echantillon nommes
# (centre, bord gauche, bord droit) — charter POINT DUR / politique flottante F2, AUCUN epsilon.
# La valeur attendue EST l'expression derivee de la constante nommee angle_rebond_max_rad(),
# construite en Vector2 (domaine real_t du moteur) pour une egalite bit-a-bit exacte.
extends RefCounted

const PaddleDefl = preload("res://05_SYSTEMS/paddle_rebound/paddle_deflection.gd")
const P = preload("res://05_SYSTEMS/params/params.gd")

func run(h) -> void:
	# --- offset relatif : borne strict a [-1, 1] ---
	h.eq(PaddleDefl.offset_relatif(0.0, 0.0), 0.0, "impact au centre -> offset 0")
	h.eq(PaddleDefl.offset_relatif(P.raquette_demi_largeur(), 0.0), 1.0, "impact bord droit -> offset +1")
	h.eq(PaddleDefl.offset_relatif(-P.raquette_demi_largeur(), 0.0), -1.0, "impact bord gauche -> offset -1")
	h.eq(PaddleDefl.offset_relatif(1000.0, 0.0), 1.0, "impact au-dela du bord droit -> borne a +1")
	h.eq(PaddleDefl.offset_relatif(-1000.0, 0.0), -1.0, "impact au-dela du bord gauche -> borne a -1")

	var v := Vector2(0.0, 300.0)         # balle descendante, |v| = 300 (exact)
	var speed := v.length()
	var maxr := P.angle_rebond_max_rad()

	# (1) CENTRE (offset 0) : vx' == 0.0 exact, balle tout droit vers le haut a la meme vitesse.
	var c := PaddleDefl.deflechir(v, 0.0)
	h.eq(c.x, 0.0, "centre: vx' == 0.0 (strict, aucun epsilon)")
	h.eq(c, Vector2(0.0, -speed), "centre: v' == (0, -|v|) (strict)")

	# (2) BORD DROIT (offset +1) : theta = +max -> v' == (|v|sin(max), -|v|cos(max)).
	var rd := PaddleDefl.deflechir(v, 1.0)
	h.eq(rd, Vector2(speed * sin(maxr), -speed * cos(maxr)), "bord droit: v' == (|v|sin(max), -|v|cos(max)) (strict)")

	# (3) BORD GAUCHE (offset -1) : theta = -max -> v' == (|v|sin(-max), -|v|cos(-max)).
	var lg := PaddleDefl.deflechir(v, -1.0)
	h.eq(lg, Vector2(speed * sin(-maxr), -speed * cos(-maxr)), "bord gauche: v' == (|v|sin(-max), -|v|cos(-max)) (strict)")

	# --- variance PROUVEE : 3 points d'impact -> 3 deviations horizontales DISTINCTES ---
	h.ok(c.x != rd.x and c.x != lg.x and lg.x != rd.x, "3 points d'impact -> 3 vx' distincts (angle variable)")
	# la balle repart TOUJOURS vers le haut (vy' negatif) aux 3 points.
	h.ok(c.y < 0.0 and rd.y < 0.0 and lg.y < 0.0, "aux 3 points, la balle repart vers le haut")
