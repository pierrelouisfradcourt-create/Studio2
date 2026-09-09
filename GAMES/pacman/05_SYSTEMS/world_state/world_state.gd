# world_state.gd — PARTITION DE PORTEE de l'etat (ligne world.scope_declaration).
#
# `level_progression` declare DEUX ensembles : CONSERVES (ce qui traverse une bascule) et
# REINITIALISES (ce qui repart). Cette declaration est complete TANT QU'UNE ZONE QUITTEE
# NE SE SOUVIENT DE RIEN. Des qu'un monde porte plusieurs zones et qu'on y REVIENT, il
# manque un troisieme cas : ce que la zone se RAPPELLE.
#
# Ce module declare donc la partition en TROIS portees, et rien d'autre. Il N'ACTIVE
# AUCUN monde multi-zone et ne change aucune regle existante : il fixe la FORME de
# l'etat pour que l'activation future soit une EXTENSION et non une reconstruction.
#
# Raison d'etre, dite franchement : tout module pur consomme la forme de l'etat. Changer
# cette forme une fois que vingt modules la lisent est une reconstruction du coeur.
# La declarer aujourd'hui, avec une seule zone, coute une constante.
#
# Logique PURE. RefCounted, aucune I/O, aucune enumeration de contenu.
extends RefCounted

const Progression = preload("res://05_SYSTEMS/level_progression/level_progression.gd")

# --- Les trois portees, nommees et disjointes ---

# GLOBALE : survit a tout — changement de zone comme bascule de niveau. Strictement les
# grandeurs que `level_progression.CONSERVES` fait deja traverser une bascule.
const PORTEE_GLOBALE: Array = ["score", "vies"]

# ZONE : ce qu'une zone QUITTEE se rappelle, et retrouve si l'on y revient. Aujourd'hui
# les collectibles : une piece deja videe reste videe. C'est le cas que la partition a
# deux ensembles ne savait pas exprimer.
const PORTEE_ZONE: Array = ["pastilles", "consommees"]

# SESSION : remis a l'etat de depart a CHAQUE entree dans une zone. `total_pose` en fait
# partie parce qu'il se RECALCULE depuis la carte a l'entree : le memoriser serait
# memoriser une valeur derivee.
const PORTEE_SESSION: Array = [
	"total_pose", "pac", "fantomes", "horloge", "effraye_restant",
	"rang_capture", "rng_etat", "ticks",
]

# Vocabulaire FERME des portees. Un champ hors de ces trois n'a pas de portee declaree.
const NOM_GLOBALE := "globale"
const NOM_ZONE := "zone"
const NOM_SESSION := "session"
const NOM_ABSENT := ""
const PORTEES: Array = [NOM_GLOBALE, NOM_ZONE, NOM_SESSION]

# Identifiant de zone ABSENT : une partie mono-zone n'en declare aucun. L'absence est
# une VALEUR, pas un cas particulier a tester ailleurs.
const AUCUNE_ZONE := ""


# Portee DECLAREE d'un champ, ou NOM_ABSENT. Le refus est une valeur de retour :
# un champ inconnu ne leve pas, il rend la chaine vide.
static func portee_de(champ: String) -> String:
	if PORTEE_GLOBALE.has(champ):
		return NOM_GLOBALE
	if PORTEE_ZONE.has(champ):
		return NOM_ZONE
	if PORTEE_SESSION.has(champ):
		return NOM_SESSION
	return NOM_ABSENT


# Tous les champs portant une portee declaree, dans l'ordre des trois ensembles.
static func champs_declares() -> Array:
	var sortie: Array = []
	sortie.append_array(PORTEE_GLOBALE)
	sortie.append_array(PORTEE_ZONE)
	sortie.append_array(PORTEE_SESSION)
	return sortie


# Les trois portees sont-elles DEUX A DEUX DISJOINTES ? Un champ a une portee, pas deux.
static func portees_disjointes() -> bool:
	var vus: Array = []
	for champ in champs_declares():
		if vus.has(champ):
			return false
		vus.append(champ)
	return true


# La partition COUVRE-T-ELLE exactement ce que level_progression declarait ? C'est la
# propriete qui empeche la troisieme portee d'etre un ajout a cote de la plaque : elle
# doit REDECOUPER l'existant, pas s'y superposer.
static func partition_couvre_progression() -> bool:
	var declare: Array = champs_declares()
	var attendu: Array = []
	attendu.append_array(Progression.CONSERVES)
	attendu.append_array(Progression.REINITIALISES)
	for champ in attendu:
		if not declare.has(champ):
			return false
	for champ in declare:
		if not attendu.has(champ):
			return false
	return true


# Champs de `level_progression` qui n'ont recu AUCUNE portee. Rend la LISTE, pour que
# l'echec NOMME les champs oublies au lieu de rendre un booleen nu.
static func champs_sans_portee() -> Array:
	var sortie: Array = []
	var attendu: Array = []
	attendu.append_array(Progression.CONSERVES)
	attendu.append_array(Progression.REINITIALISES)
	for champ in attendu:
		if portee_de(champ) == NOM_ABSENT:
			sortie.append(champ)
	return sortie


# CE QUE LA ZONE COURANTE SE RAPPELLE, lu sur l'etat. Ne mute rien.
static func capturer(s) -> Dictionary:
	return {
		"pastilles": s.pastilles.duplicate(),
		"consommees": s.consommees,
	}


# Memoire des zones ENRICHIE de la zone donnee. Fonction PURE : rend un NOUVEAU
# dictionnaire, l'entree n'est jamais mutee. Une zone absente ne memorise rien.
static func memoriser(memoire_zones: Dictionary, zone: String, s) -> Dictionary:
	if zone == AUCUNE_ZONE:
		return memoire_zones.duplicate(true)
	var sortie: Dictionary = memoire_zones.duplicate(true)
	sortie[zone] = capturer(s)
	return sortie


# Ce qu'une zone se rappelle, ou un dictionnaire VIDE si elle n'a jamais ete quittee.
# Le refus est une valeur de retour.
static func rappeler(memoire_zones: Dictionary, zone: String) -> Dictionary:
	if zone == AUCUNE_ZONE or not memoire_zones.has(zone):
		return {}
	return memoire_zones[zone].duplicate(true)


# Etat RESTAURE depuis une memoire de zone. Rend un CLONE : l'entree n'est jamais mutee.
# Une memoire vide rend un clone strictement identique — l'entree dans une zone jamais
# visitee n'est pas un cas special, c'est le cas general avec une memoire vide.
static func restaurer(s, memoire: Dictionary) -> Object:
	var c = s.clone()
	if memoire.is_empty():
		return c
	if memoire.has("pastilles"):
		c.pastilles = memoire["pastilles"].duplicate()
	if memoire.has("consommees"):
		c.consommees = int(memoire["consommees"])
	return c
