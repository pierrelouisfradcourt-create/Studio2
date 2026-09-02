# input_intents.gd — VOCABULAIRE FERME des intentions (ligne intents.vocabulary).
#
# SEULE entree de la logique de jeu. Aucun code de touche, aucun bouton de manette,
# aucun contact tactile n'existe ici : c'est cette absence, COMPTABLE STATIQUEMENT sur
# 05_SYSTEMS, qui rend l'invariant falsifiable au lieu d'etre redactionnel. Le controle
# positif — les memes references TROUVEES dans 06_RUNTIME — est porte par input_bindings
# et input_adapter.
#
# Feuille du graphe : ne depend de RIEN (pas meme de maze). Une intention de direction
# est designee par son RANG dans l'ordre fixe declare par maze.DIRECTIONS ; la
# traduction rang -> vecteur appartient a l'appelant qui connait la carte, jamais a ce
# module, sans quoi deux declarations de directions pourraient diverger.
extends RefCounted

# Vocabulaire FERME, exclusif et exhaustif.
enum Intention {
	AUCUNE,
	HAUT,
	GAUCHE,
	BAS,
	DROITE,
	DASH,
	PAUSE,
	VALIDER,
	RETOUR,
	SELECTION_PRECEDENTE,
	SELECTION_SUIVANTE,
}

# Les quatre intentions de direction, DANS L'ORDRE FIXE haut, gauche, bas, droite —
# le meme que celui de maze.DIRECTIONS, dont le rang est l'unique point de contact.
const DIRECTIONS: Array = [
	Intention.HAUT, Intention.GAUCHE, Intention.BAS, Intention.DROITE,
]

# Les intentions qui n'agissent PAS sur le deplacement.
const COMMANDES: Array = [
	Intention.DASH, Intention.PAUSE, Intention.VALIDER, Intention.RETOUR,
	Intention.SELECTION_PRECEDENTE, Intention.SELECTION_SUIVANTE,
]

const TOUTES: Array = [
	Intention.AUCUNE,
	Intention.HAUT, Intention.GAUCHE, Intention.BAS, Intention.DROITE,
	Intention.DASH, Intention.PAUSE, Intention.VALIDER, Intention.RETOUR,
	Intention.SELECTION_PRECEDENTE, Intention.SELECTION_SUIVANTE,
]

const RANG_ABSENT: int = -1

# Noms declares, dans l'ordre de TOUTES : un releve lisible par un lecteur exterieur.
const NOMS: Array = [
	"AUCUNE", "HAUT", "GAUCHE", "BAS", "DROITE", "DASH", "PAUSE",
	"VALIDER", "RETOUR", "SELECTION_PRECEDENTE", "SELECTION_SUIVANTE",
]


static func valide(intention: int) -> bool:
	return TOUTES.has(intention)


static func est_direction(intention: int) -> bool:
	return DIRECTIONS.has(intention)


static func est_commande(intention: int) -> bool:
	return COMMANDES.has(intention)


# RANG de l'intention de direction dans l'ordre fixe (0..3), RANG_ABSENT sinon.
static func rang_direction(intention: int) -> int:
	return DIRECTIONS.find(intention)


# Intention de direction portee par un rang de l'ordre fixe ; AUCUNE hors bornes.
static func direction_du_rang(rang: int) -> int:
	if rang < 0 or rang >= DIRECTIONS.size():
		return Intention.AUCUNE
	return DIRECTIONS[rang]


static func nom(intention: int) -> String:
	var i: int = TOUTES.find(intention)
	if i == RANG_ABSENT:
		return NOMS[0]
	return NOMS[i]
