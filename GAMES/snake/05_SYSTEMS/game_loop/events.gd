# events.gd — ligne arch.event_socket. Vocabulaire FERME d'evenements-donnees emis
# par le tick, sous forme de LISTE de Dictionary (jamais un signal Godot ni un bus
# global : un signal est une API de moteur). RefCounted, pur. AUCUN collecteur.
extends RefCounted

const NOURRITURE_MANGEE := "nourriture_mangee"
const PALIER_FRANCHI := "palier_franchi"
const FIN_PARTIE := "fin_partie"
const VOCABULAIRE := [NOURRITURE_MANGEE, PALIER_FRANCHI, FIN_PARTIE]

static func nourriture_mangee(position: Vector2i, score: int) -> Dictionary:
	return {"type": NOURRITURE_MANGEE, "position": position, "score": score}

static func palier_franchi(palier: int, periode: float) -> Dictionary:
	return {"type": PALIER_FRANCHI, "palier": palier, "periode": periode}

static func fin_partie(statut: int) -> Dictionary:
	return {"type": FIN_PARTIE, "statut": statut}
