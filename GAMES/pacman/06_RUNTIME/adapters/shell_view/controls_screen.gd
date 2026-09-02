# controls_screen.gd — ECRAN DE CONSULTATION DES CONTROLES (lignes shell.controls_screen,
# shell.controls_lists_bindings).
#
# L'ecran LIT la table de liaisons au lieu de recopier des touches : une copie pourrait
# mentir sans qu'aucune mesure ne le voie. Il enumere, pour chaque intention de jeu, les
# liaisons qui la declenchent sur CHAQUE peripherique declare, et rend a l'ecran d'ou il
# a ete ouvert — l'ecran appelant est MEMORISE, jamais suppose.
#
# VOLET HUMAIN NON TRANCHE ICI : qu'une personne trouve seule les quatre gestes est un
# constat humain (F113), remonte en fog HumanGate. Cette ligne fournit le MATERIAU.
extends RefCounted

const Intents = preload("res://05_SYSTEMS/input_intents/input_intents.gd")
const App = preload("res://05_SYSTEMS/app_state/app_state.gd")
const Bindings = preload("res://06_RUNTIME/adapters/input_bindings/input_bindings.gd")

const TITRE := "CONTROLES"
const SEPARATEUR := " : "
const SEPARATEUR_LIAISONS := ", "
const AUCUNE_LIAISON := "-"
# Repli NOMME pour une liaison que la table n'a pas nommee. Jamais le code brut : c'etait
# EXACTEMENT le defaut P1 (str(liaison) affichait « 4194320 » a la place de « Fleche haut »).
const LIAISON_SANS_NOM := "(non nommee)"

# Libelles LISIBLES des intentions de jeu, dans l'ordre declare par la table.
const LIBELLES: Dictionary = {
	Intents.Intention.HAUT: "Aller en haut",
	Intents.Intention.GAUCHE: "Aller a gauche",
	Intents.Intention.BAS: "Aller en bas",
	Intents.Intention.DROITE: "Aller a droite",
	Intents.Intention.DASH: "Dash",
	Intents.Intention.PAUSE: "Pause",
	Intents.Intention.VALIDER: "Valider",
	Intents.Intention.RETOUR: "Retour",
}


static func libelle(intention: int) -> String:
	if not LIBELLES.has(intention):
		return Intents.nom(intention)
	return LIBELLES[intention]


# NOM HUMAIN d'une liaison, DEMANDE a la table qui declare les codes. Ce fichier ne
# recopie aucun nom de touche (il est mesure sans « KEY_ » ni « JOY_ ») : il demande.
# Une liaison que la table n'a pas nommee rend un repli NOMME, jamais son code brut.
static func nom_lisible(liaison, peripherique: String) -> String:
	var nom: String = Bindings.nom_liaison(liaison, peripherique)
	if nom == Bindings.NOM_INCONNU:
		return LIAISON_SANS_NOM
	return nom


# Liaisons d'une intention sur un peripherique, LUES dans la table — aucune chaine de
# touche n'est recopiee dans ce fichier.
static func liaisons_lisibles(intention: int, peripherique: String) -> String:
	var liste: Array = Bindings.liaisons(intention, peripherique)
	if liste.is_empty():
		return AUCUNE_LIAISON
	var morceaux: Array = []
	for l in liste:
		morceaux.append(nom_lisible(l, peripherique))
	return SEPARATEUR_LIAISONS.join(morceaux)


static func ligne(intention: int) -> String:
	var morceaux: Array = [libelle(intention)]
	for p in Bindings.PERIPHERIQUES:
		morceaux.append(p + SEPARATEUR + liaisons_lisibles(intention, p))
	return "  ".join(morceaux)


# Toutes les lignes de l'ecran, dans l'ordre declare des intentions.
static func lignes() -> Array:
	var sortie: Array = []
	for i in LIBELLES.keys():
		sortie.append(ligne(i))
	return sortie


# Nombre d'intentions AFFICHEES sans aucune liaison manette. La valeur attendue vaut
# exactement 0 — c'est le volet MACHINE de l'exigence de decouvrabilite.
static func intentions_affichees_sans_manette() -> int:
	var n: int = 0
	for i in LIBELLES.keys():
		if Bindings.liaisons(i, Bindings.MANETTE).is_empty():
			n += 1
	return n


# Les QUATRE GESTES dont la decouvrabilite est evaluee par une personne sont-ils tous
# affiches ? Volet machine : leur PRESENCE. Le constat humain n'est pas rendu ici.
static func gestes_absents_de_l_ecran() -> int:
	var texte: String = "\n".join(lignes())
	var n: int = 0
	for g in Bindings.GESTES_DECOUVRABLES:
		if texte.find(libelle(g)) < 0:
			n += 1
	return n


# LIGNES DE L'ECRAN PORTANT UN CHIFFRE (cause racine P1). Aucun libelle d'intention,
# aucun nom de peripherique et aucun nom de touche declare ne contient de chiffre : la
# SEULE facon d'en voir apparaitre un est qu'un code brut soit affiche a la place d'un
# nom. La valeur attendue vaut exactement 0 — avant la correction V3 elle valait 8.
static func lignes_portant_un_code_brut() -> int:
	var n: int = 0
	for l in lignes():
		if Bindings.nom_porte_un_code_brut(l):
			n += 1
	return n


# Retour a l'ecran APPELANT, memorise a l'ouverture.
static func retour(appelant: int) -> int:
	return App.retour(App.Etat.CONTROLES, appelant)
