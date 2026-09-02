# score.gd — ligne state.score. Detient le score, fonction PURE du nombre de briques
# detruites. Aucun affichage. RefCounted. Capacite play.score deja au registre (Pong).
extends RefCounted

const P = preload("res://05_SYSTEMS/params/params.gd")

# Score = briques_detruites * points_par_brique (constante nommee, valeur A_EQUILIBRER non
# recopiee ici). Le nombre de briques detruites = total initial - restantes.
static func depuis_detruites(briques_detruites: int) -> int:
	return briques_detruites * P.POINTS_PAR_BRIQUE

# Recalcule le score depuis l'etat (total initial - restantes). Fonction pure, pas d'increment
# aveugle : impossible d'augmenter le score sans qu'une brique ait reellement disparu.
static func recalculer(state) -> int:
	var detruites: int = P.total_briques() - state.briques_restantes
	return depuis_detruites(detruites)
