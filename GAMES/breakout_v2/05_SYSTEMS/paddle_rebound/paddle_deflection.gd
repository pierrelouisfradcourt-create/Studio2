# paddle_deflection.gd — ligne physics.paddle_deflection. Angle de rebond FONCTION DU POINT
# D'IMPACT sur la raquette. Fonction PURE (offset_relatif, vitesse_entrante) -> vitesse_sortante.
# Aucun etat, aucune horloge, aucun alea. RefCounted. Capacite proposee : game.paddle_deflection.
#
# Modele (Arkanoid-like) : l'impact remplace la DIRECTION par un angle de deviation par
# rapport a la verticale montante, proportionnel a l'offset, en CONSERVANT la vitesse. Les
# valeurs sont STRICTES aux 3 points d'echantillon (charter, politique flottante F2 :
# egalite bit-a-bit du resultat produit par l'expression derivee de la constante nommee).
extends RefCounted

const P = preload("res://05_SYSTEMS/params/params.gd")

# Offset relatif du point d'impact : -1 (bord gauche) .. 0 (centre) .. +1 (bord droit).
# Borne : un impact au-dela du bord compte comme le bord (jamais > 1 en valeur absolue).
static func offset_relatif(ball_x: float, paddle_x: float) -> float:
	return clampf((ball_x - paddle_x) / P.raquette_demi_largeur(), -1.0, 1.0)

# Vitesse sortante. theta = offset * angle_max ; la balle repart VERS LE HAUT :
#   vx' = |v| * sin(theta)   (0 au centre, +/- |v|*sin(max) aux bords)
#   vy' = -|v| * cos(theta)  (toujours negatif : vers le haut)
# La norme |v'| vaut |v| par construction (meme scalaire de vitesse).
static func deflechir(vitesse_entrante: Vector2, offset: float) -> Vector2:
	var vitesse: float = vitesse_entrante.length()
	var theta: float = offset * P.angle_rebond_max_rad()
	return Vector2(vitesse * sin(theta), -vitesse * cos(theta))
