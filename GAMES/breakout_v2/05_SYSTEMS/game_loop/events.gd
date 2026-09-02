# events.gd — ligne loop.event_socket. Vocabulaire FERME d'evenements-donnees emis par le
# tick, sous forme de LISTE de Dictionary (jamais un signal Godot : un signal est une API de
# moteur). RefCounted, pur. AUCUN collecteur, aucune telemetrie. Capacite : game.events.
extends RefCounted

const BRIQUE_DETRUITE := "brique_detruite"
const REBOND_MUR := "rebond_mur"
const REBOND_RAQUETTE := "rebond_raquette"
const VIE_PERDUE := "vie_perdue"
const FIN_PARTIE := "fin_partie"
const VOCABULAIRE := [BRIQUE_DETRUITE, REBOND_MUR, REBOND_RAQUETTE, VIE_PERDUE, FIN_PARTIE]

static func brique_detruite(index: int) -> Dictionary:
	return {"type": BRIQUE_DETRUITE, "index": index}

static func rebond_mur(face: int) -> Dictionary:
	return {"type": REBOND_MUR, "face": face}

static func rebond_raquette(offset: float) -> Dictionary:
	return {"type": REBOND_RAQUETTE, "offset": offset}

static func vie_perdue(vies_restantes: int) -> Dictionary:
	return {"type": VIE_PERDUE, "vies": vies_restantes}

static func fin_partie(statut: int) -> Dictionary:
	return {"type": FIN_PARTIE, "statut": statut}
