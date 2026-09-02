# fixed_step.gd — ligne physics.fixed_timestep. Le POINT DUR du jeu (charter.objectif) :
# la simulation avance d'un PAS DE TEMPS FIXE nomme, jamais le delta-time du moteur, jamais
# une horloge. RefCounted, pur. Capacite proposee hors registre : game.fixed_timestep.
#
# Ce module N'INTERROGE aucune horloge : il expose la CONSTANTE de pas (derivee de
# params.TICK_DT_FIXED_MS) et rien d'autre. La conversion temps-reel -> pas fixe (accumulateur)
# vit dans l'ADAPTATEUR runtime_loop, jamais ici (sens unique du graphe).
extends RefCounted

const P = preload("res://05_SYSTEMS/params/params.gd")

# Pas de temps fixe de la simulation, en secondes. UNIQUE porteur du pas : toute avance de la
# logique pure se fait avec cette valeur, jamais une autre.
static func dt() -> float:
	return P.dt_s()
