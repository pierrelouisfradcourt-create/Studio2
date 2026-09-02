# end_conditions.gd — perte de vie, defaite, victoire
# (lignes end.life_loss, end.defeat, end.victory, end.respawn_from_state_map).
#
# V2 : le repositionnement apres une perte de vie lit les positions de depart de la
# CARTE PORTEE PAR L'ETAT, et non des constantes de la logique — quatrieme et derniere
# cause mesuree de la baseline V1.
#
# Ne depend PAS de game_state : l'arete end_conditions -> game_state est interdite par
# blueprint.deps_interdites. Ce module porte donc son PROPRE vocabulaire ferme d'issues,
# que game_state/status traduit en statut de partie.
extends RefCounted

const Maze = preload("res://05_SYSTEMS/maze/maze.gd")
const House = preload("res://05_SYSTEMS/ghost_house/ghost_house.gd")
const Chase = preload("res://05_SYSTEMS/chase_state/chase_state.gd")

# Vocabulaire ferme d'issues, exclusives et exhaustives.
enum Issue { EN_COURS, GAGNE, PERDU }

# V6 : `VIES_INITIALES` a DISPARU de ce module, et c'est une decision. Le nombre de vies
# de depart DEPEND DU MODE DE JEU depuis la decision Pierre du 2026-08-06 ; une constante
# unique serait donc FAUSSE dans l'un des deux modes, et un alias de plus serait un second
# endroit a corriger. La correspondance mode -> vies vit dans settings, source unique.
#
# Ce module garde ce qui NE depend pas du mode : on retire EXACTEMENT une vie par perte,
# et la defaite tombe a zero. Ces deux regles sont vraies dans les deux modes.


# Perte de vie (ligne end.life_loss) : EXACTEMENT une vie retiree, entites replacees aux
# positions de depart DE LA CARTE COURANTE, horloge revenue a son premier segment. Les
# collectibles deja consommes ne reviennent PAS.
static func perdre_une_vie(s) -> void:
	s.vies -= 1
	s.pac = s.carte.DEPART_PACMAN
	s.pac_dir = s.carte.DEPART_DIRECTION
	s.pac_attente = Maze.AUCUNE
	s.horloge = 0
	s.effraye_restant = 0
	s.rang_capture = 0
	House.reinitialiser(s)
	Chase.rafraichir_etats(s)


# Defaite (ligne end.defeat) : au tick EXACT ou les vies atteignent zero. Jamais a 1,
# jamais apres — egalite STRICTE, jamais un <=.
static func defaite(vies: int) -> bool:
	return vies == 0


# Victoire (ligne end.victory) : EGALITE STRICTE entre consommes et total pose. Jamais
# un >= : a total - 1 la partie est encore EN COURS.
static func victoire(consommees: int, total_pose: int) -> bool:
	return consommees == total_pose


# Issue courante, dans le vocabulaire ferme, exclusive et exhaustive. L'ordre d'examen
# est declare : la defaite prime, puis la victoire, sinon la partie continue.
static func issue(vies: int, consommees: int, total_pose: int) -> int:
	if defaite(vies):
		return Issue.PERDU
	if victoire(consommees, total_pose):
		return Issue.GAGNE
	return Issue.EN_COURS
