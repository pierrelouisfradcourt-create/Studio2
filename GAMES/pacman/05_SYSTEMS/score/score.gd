# score.gd — conversion en points et POINT DE MUTATION UNIQUE du score
# (lignes score.pellet_value, score.ghost_capture_value, score.mutation_point).
# Feuille du graphe : ne depend d'aucun autre systeme.
extends RefCounted

const P = preload("res://05_SYSTEMS/params/params.gd")

const POINTS_PASTILLE: int = P.POINTS_PASTILLE
const POINTS_SUPER: int = P.POINTS_SUPER
# Rang de capture dans une meme fenetre Effraye : 200 / 400 / 800 / 1600.
const VALEURS_CAPTURE: Array = P.VALEURS_CAPTURE


# Points d'un collectible consomme. `est_super` distingue la super-pastille : le
# vocabulaire des collectibles appartient a pellets, il n'est pas redecrit ici.
static func valeur_collectible(est_super: bool) -> int:
	if est_super:
		return POINTS_SUPER
	return POINTS_PASTILLE


# Points d'une capture de fantome selon son RANG dans la fenetre courante. Au-dela du
# quatrieme, la valeur reste la derniere declaree (jamais une extrapolation implicite).
static func valeur_capture(rang: int) -> int:
	if rang < 0:
		return VALEURS_CAPTURE[0]
	if rang >= VALEURS_CAPTURE.size():
		return VALEURS_CAPTURE[VALEURS_CAPTURE.size() - 1]
	return VALEURS_CAPTURE[rang]


# POINT DE MUTATION UNIQUE : le SEUL endroit du jeu ou s.score change. C'est ce qui
# interdit une divergence entre le chiffre affiche et le chiffre de l'etat.
static func ajouter(s, points: int) -> void:
	s.score += points
