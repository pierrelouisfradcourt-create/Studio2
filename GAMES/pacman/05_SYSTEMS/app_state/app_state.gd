# app_state.gd — ETAT D'APPLICATION (lignes app.state_vocabulary, app.tick_gate,
# app.pause_entry).
#
# Vocabulaire FERME, exclusif et exhaustif, DISTINCT du statut de PARTIE (EN COURS /
# GAGNE / PERDU) qu'il n'absorbe pas : fusionner les deux rendrait indecidable la
# question « une partie tourne-t-elle derriere ce menu ? ».
#
# Logique PURE, feuille du graphe : ne depend de RIEN. Aucun noeud, aucune horloge.
extends RefCounted

enum Etat { TITRE, PARTIE, PAUSE, CONTROLES, OPTIONS, FIN }

const ETATS_VALIDES: Array = [
	Etat.TITRE, Etat.PARTIE, Etat.PAUSE, Etat.CONTROLES, Etat.OPTIONS, Etat.FIN,
]

const NOMS: Array = ["TITRE", "PARTIE", "PAUSE", "CONTROLES", "OPTIONS", "FIN"]

# Etat d'amorcage : l'application demarre SUR L'ECRAN TITRE, aucune partie construite.
const ETAT_INITIAL: int = Etat.TITRE


static func valide(etat: int) -> bool:
	return ETATS_VALIDES.has(etat)


static func nom(etat: int) -> String:
	if not valide(etat):
		return ""
	return NOMS[etat]


# LE PREDICAT QUI FAIT FOI (ligne app.tick_gate) : le tick de partie est-il autorise a
# cet instant ? Unique autorite consultee par la boucle du runtime. C'est ce qui
# distingue « aucune partie n'avance » de « un menu masque une partie qui tourne ».
static func tick_autorise(etat: int) -> bool:
	return etat == Etat.PARTIE


# La pause n'est demandable que depuis une partie en cours.
static func peut_mettre_en_pause(etat: int) -> bool:
	return etat == Etat.PARTIE


# TRANSITION DE PAUSE UNIQUE (ligne app.pause_entry) : definie sur l'INTENTION, jamais
# sur le peripherique. Les trois chemins (clavier, manette, tactile) ne peuvent donc pas
# produire trois ecrans paralleles — il n'existe qu'une transition a emprunter.
static func vers_pause(etat: int) -> int:
	if peut_mettre_en_pause(etat):
		return Etat.PAUSE
	return etat


# Reprise depuis la pause : retour a la partie, sans autre effet.
static func vers_partie(_etat: int) -> int:
	return Etat.PARTIE


static func vers_titre(_etat: int) -> int:
	return Etat.TITRE


static func vers_fin(_etat: int) -> int:
	return Etat.FIN


# Ecran de consultation ouvert DEPUIS un ecran appelant memorise, jamais suppose.
static func vers_consultation(cible: int, appelant: int) -> Dictionary:
	if cible != Etat.CONTROLES and cible != Etat.OPTIONS:
		return {"etat": appelant, "appelant": appelant}
	return {"etat": cible, "appelant": appelant}


# Retour d'un ecran de consultation : on revient a l'appelant MEMORISE.
static func retour(etat: int, appelant: int) -> int:
	if etat != Etat.CONTROLES and etat != Etat.OPTIONS:
		return etat
	if not valide(appelant):
		return Etat.TITRE
	return appelant
