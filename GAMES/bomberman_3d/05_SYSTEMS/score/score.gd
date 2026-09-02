# score.gd — BAREME. Traduit un evenement de tick en points. Logique PURE.
#
# Pourquoi un score dans un jeu ou l'on gagne en survivant : sans grandeur cumulative, deux
# parties gagnees sont indiscernables, et il n'y a rien a rejouer POUR. Le score est ce qui
# transforme « j'ai gagne » en « j'ai mieux joue que la derniere fois ».
#
# Le bareme est SUPERLINEAIRE sur l'elimination : casser des blocs fait progresser, mais
# c'est eliminer qui rapporte. Un jeu ou farmer les blocs paie mieux que combattre
# recompenserait le contraire de son propre objectif.
extends RefCounted

const POINTS_BLOC: int = 10
const POINTS_POWERUP: int = 25
const POINTS_ELIMINATION: int = 250
const POINTS_VICTOIRE: int = 1000

# Points d'un evenement de boucle, du point de vue de l'acteur `index`.
# Un evenement qui ne le concerne pas vaut 0 — jamais un score attribue par erreur.
static func points_pour(evenement: Dictionary, index: int, statut_gagnant: bool) -> int:
	match String(evenement["kind"]):
		"bloc_detruit":
			return POINTS_BLOC
		"powerup_ramasse":
			# Seul un ramassage QUI A EU UN EFFET rapporte : recompenser un bonus inutile
			# apprendrait au joueur a ramasser au plafond.
			if int(evenement["acteur"]) == index and bool(evenement["effet"]):
				return POINTS_POWERUP
			return 0
		"mort":
			if int(evenement["tueur"]) == index and int(evenement["victime"]) != index:
				return POINTS_ELIMINATION
			return 0
		"fin":
			return POINTS_VICTOIRE if statut_gagnant else 0
		_:
			return 0


# Total d'un lot d'evenements.
static func total(evenements: Array, index: int, statut_gagnant: bool) -> int:
	var n: int = 0
	for e in evenements:
		n += points_pour(e, index, statut_gagnant)
	return n
