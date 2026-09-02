# input_adapter_burst.test.gd — lignes input.adapter / core.input. Entre le tick ou une
# direction legale est acceptee et le tick ou la tete se deplace dans cette direction, il
# s'ecoule EXACTEMENT 1 tick, a toutes les cadences (plancher compris). Vocabulaire ferme
# traduit correctement ; canal public unique (clavier = bot).
extends RefCounted

const IA = preload("res://06_RUNTIME/adapters/input_adapter/input_adapter.gd")
const DR = preload("res://05_SYSTEMS/input_rules/direction_rules.gd")
const State = preload("res://05_SYSTEMS/game_state/state.gd")
const Loop = preload("res://05_SYSTEMS/game_loop/loop.gd")

func run(h) -> void:
	# Traduction du vocabulaire ferme.
	h.eq(IA.traduire_keycode(KEY_UP)["dir"], DR.HAUT, "UP -> HAUT")
	h.eq(IA.traduire_keycode(KEY_DOWN)["dir"], DR.BAS, "DOWN -> BAS")
	h.eq(IA.traduire_keycode(KEY_LEFT)["dir"], DR.GAUCHE, "LEFT -> GAUCHE")
	h.eq(IA.traduire_keycode(KEY_RIGHT)["dir"], DR.DROITE, "RIGHT -> DROITE")
	h.eq(IA.traduire_keycode(KEY_W)["dir"], DR.HAUT, "W -> HAUT")
	h.eq(IA.traduire_keycode(KEY_P)["commande"], IA.CMD_PAUSE, "P -> pause")
	h.eq(IA.traduire_keycode(KEY_R)["commande"], IA.CMD_RELANCE, "R -> relance")
	h.eq(IA.traduire_keycode(KEY_ESCAPE)["commande"], IA.CMD_SORTIE, "ESC -> sortie")
	# Touche non liee -> aucun (aucune commande inerte n'existe : elle est simplement nulle).
	h.eq(IA.traduire_keycode(KEY_J)["kind"], "aucun", "touche non liee -> aucun")

	# Latence EXACTEMENT 1 tick : serpent VERTICAL (corps sous la tete) allant HAUT, on
	# presse LEFT (perpendiculaire) : la case a gauche est libre, le serpent tourne.
	var s = State.initial(8)
	s.segments = [Vector2i(10, 10), Vector2i(10, 11), Vector2i(10, 12)]
	s.longueur = 3
	s.dir_effectuee = DR.HAUT
	s.dir_en_attente = DR.HAUT
	s.nourriture = Vector2i(19, 19)  # loin, pas de consommation parasite
	var action = IA.traduire_keycode(KEY_LEFT)
	DR.demander(s, action["dir"])
	var tete_avant = s.segments[0]
	var r = Loop.step(s, Loop.AUCUNE)["etat"]
	h.eq(r.ticks, s.ticks + 1, "exactement 1 tick s'ecoule")
	h.eq(r.segments[0], tete_avant + DR.GAUCHE, "la tete s'est deplacee a GAUCHE au tick suivant")

	# Meme latence au PLANCHER de periode (fruits eleve) : toujours 1 tick.
	var s2 = State.initial(8)
	s2.segments = [Vector2i(10, 10), Vector2i(10, 11), Vector2i(10, 12)]
	s2.longueur = 3
	s2.dir_effectuee = DR.HAUT
	s2.dir_en_attente = DR.HAUT
	s2.fruits = 55  # periode = plancher
	s2.nourriture = Vector2i(19, 19)
	DR.demander(s2, IA.traduire_keycode(KEY_LEFT)["dir"])
	var tete2 = s2.segments[0]
	var r2 = Loop.step(s2, Loop.AUCUNE)["etat"]
	h.eq(r2.segments[0], tete2 + DR.GAUCHE, "au plancher : deplacement a GAUCHE apres 1 tick")

	# Canal public unique : passer l'action par step(action) donne le meme resultat que
	# par demander() prealable (clavier et bot empruntent le meme canal).
	var s3 = State.initial(8)
	s3.segments = [Vector2i(10, 10), Vector2i(10, 11), Vector2i(10, 12)]
	s3.longueur = 3
	s3.dir_effectuee = DR.HAUT
	s3.dir_en_attente = DR.HAUT
	s3.nourriture = Vector2i(19, 19)
	var via_step = Loop.step(s3, IA.traduire_keycode(KEY_LEFT)["dir"])["etat"]
	h.eq(via_step.segments[0], s3.segments[0] + DR.GAUCHE, "action passee au step : meme canal, meme effet")
