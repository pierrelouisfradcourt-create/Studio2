# debug_state_fields.test.gd — ligne debug.state_projection. Le dictionnaire d'observation
# contient EXACTEMENT les 7 grandeurs decisives, construites depuis l'etat DEJA tenu,
# sans structure parallele et sans champ invente.
extends RefCounted

const State = preload("res://05_SYSTEMS/game_state/state.gd")
const Debug = preload("res://05_SYSTEMS/debug_state/debug_state.gd")

func run(h) -> void:
	var s = State.initial(11)
	var d = Debug.projeter(s, 42)
	# EXACTEMENT 7 cles.
	h.eq(d.size(), 7, "exactement 7 grandeurs exposees")
	for k in ["longueur", "score", "meilleur_score", "tete", "nourriture", "periode", "statut"]:
		h.ok(d.has(k), "cle presente : " + k)
	# Valeurs = projection de l'etat deja tenu (aucune divergence).
	h.eq(d["longueur"], s.longueur, "longueur projetee = etat")
	h.eq(d["score"], s.score, "score projete = etat")
	h.eq(d["meilleur_score"], 42, "meilleur_score = valeur fournie de l'exterieur")
	h.eq(d["tete"], s.segments[0], "tete projetee = segment 0")
	h.eq(d["nourriture"], s.nourriture, "nourriture projetee = etat")
	h.eq(d["periode"], s.periode, "periode projetee = etat")
	h.eq(d["statut"], s.statut, "statut projete = etat")
