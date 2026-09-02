# naive_bots.gd — ligne proof.negative_control_bot. CONTROLES NEGATIFS nommes (charter
# SOLVABILITE PROUVEE PAR INTERCEPTION REELLE) : sans eux, un taux de victoire eleve ne
# prouverait rien sur la difficulte reelle du niveau. Deux bots volontairement INSUFFISANTS :
#   - CAMP_CENTRE : la raquette reste au centre (aucune interception).
#   - SUIVI_NAIF  : suit toujours la position x ACTUELLE de la balle, sans anticipation.
# RefCounted, purs, deterministes. Pilotent le MEME canal d'entree public que le bot reel.
extends RefCounted

const P = preload("res://05_SYSTEMS/params/params.gd")
const InputRules = preload("res://05_SYSTEMS/input_rules/input_rules.gd")

# Se dirige vers une position x cible (helper commun, pas d'anticipation).
static func _vers(paddle_x: float, cible: float) -> int:
	if paddle_x < cible - 1.0:
		return InputRules.DROITE
	if paddle_x > cible + 1.0:
		return InputRules.GAUCHE
	return InputRules.AUCUNE

# CONTROLE NEGATIF 1 : campe au centre, ne suit jamais la balle.
static func action_camp_centre(state) -> int:
	return _vers(state.paddle_x, P.TERRAIN_LARGEUR / 2.0)

# CONTROLE NEGATIF 2 : suit la position x ACTUELLE de la balle, SANS prediction de trajectoire
# ni reflexion (arrive systematiquement en retard sur une balle rapide).
static func action_suivi_naif(state) -> int:
	return _vers(state.paddle_x, state.ball_pos.x)
