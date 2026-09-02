# debug_receipt.test.gd — ligne debug.receipt_line. Le recu est bien forme (prefixe +
# JSON parsable), il round-trip sans perte, et 0 recu mal forme sur une sequence de ticks.
# (Le volet "instance reellement lancee, entrees injectees" est exerce par la scene et
#  l'oracle de session ; ici on prouve le contrat de format, headless.)
extends RefCounted

const Probe = preload("res://06_RUNTIME/adapters/debug_probe/debug_probe.gd")
const Debug = preload("res://05_SYSTEMS/debug_state/debug_state.gd")
const State = preload("res://05_SYSTEMS/game_state/state.gd")
const Loop = preload("res://05_SYSTEMS/game_loop/loop.gd")

func run(h) -> void:
	var s = State.initial(13)
	var obs = Debug.projeter(s, 7)
	var ligne = Probe.formater(obs)

	# Prefixe present.
	h.ok(ligne.begins_with(Probe.PREFIXE + " "), "recu prefixe par SNAKE_TRIAL")
	# JSON parsable.
	var d = Probe.parser(ligne)
	h.ok(d != null, "recu JSON parsable")
	h.eq(d.size(), 7, "recu = 7 grandeurs")
	# Round-trip des scalaires et des vecteurs (serialises en [x,y]).
	h.eq(int(d["longueur"]), s.longueur, "longueur round-trip")
	h.eq(int(d["score"]), s.score, "score round-trip")
	h.eq(int(d["meilleur_score"]), 7, "meilleur_score round-trip")
	h.eq(int(d["tete"][0]), s.segments[0].x, "tete.x round-trip")
	h.eq(int(d["tete"][1]), s.segments[0].y, "tete.y round-trip")
	h.eq(int(d["nourriture"][0]), s.nourriture.x, "nourriture.x round-trip")

	# Ligne non prefixee -> null (jamais interpretee comme recu).
	h.eq(Probe.parser("bruit quelconque"), null, "ligne hors format -> null")

	# 0 recu mal forme sur une sequence reelle de ticks.
	var cur = s
	var mal_formes := 0
	for i in range(30):
		cur = Loop.step(cur, Loop.AUCUNE)["etat"]
		if cur.statut != State.Statut.EN_COURS:
			cur = State.initial(i + 100)
		var l = Probe.formater(Debug.projeter(cur, 0))
		if Probe.parser(l) == null:
			mal_formes += 1
	h.eq(mal_formes, 0, "0 recu mal forme sur 30 ticks")
