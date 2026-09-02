# tick_pure.test.gd — ligne core.main_loop. Le tick est une fonction (etat, action) ->
# nouvel etat : deux appels sur des etats egaux -> etats STRICTEMENT egaux ; l'entree
# n'est jamais mutee ; une partie terminee est un etat fige a evenements vides.
extends RefCounted

const State = preload("res://05_SYSTEMS/game_state/state.gd")
const Loop = preload("res://05_SYSTEMS/game_loop/loop.gd")
const DR = preload("res://05_SYSTEMS/input_rules/direction_rules.gd")
const Collision = preload("res://05_SYSTEMS/collision/collision.gd")

func run(h) -> void:
	# Fonction pure : deux etats egaux -> deux resultats profondement egaux.
	var a = State.initial(42)
	var b = State.initial(42)
	var ra = Loop.step(a, Loop.AUCUNE)
	var rb = Loop.step(b, Loop.AUCUNE)
	h.ok(ra["etat"].egal_profond(rb["etat"]), "meme etat + meme action -> meme etat suivant")

	# L'entree n'est JAMAIS mutee par le tick.
	var avant = State.initial(42)
	var copie = avant.clone()
	Loop.step(avant, DR.HAUT)
	h.ok(avant.egal_profond(copie), "step ne mute pas l'etat d'entree")

	# Avance de base : la tete gagne une case, ticks +1, longueur inchangee (pas de food).
	var s = State.initial(7)
	# Ecarte la nourriture pour eviter de manger par hasard sur ce tick.
	var tete_next = s.segments[0] + s.dir_effectuee
	if s.nourriture == tete_next:
		s.nourriture = Vector2i(0, 0) if tete_next != Vector2i(0, 0) else Vector2i(1, 1)
	var longueur_avant = s.longueur
	var r = Loop.step(s, Loop.AUCUNE)
	h.eq(r["etat"].segments[0], tete_next, "la tete avance d'exactement une case")
	h.eq(r["etat"].ticks, 1, "ticks = 1 apres un tick")
	h.eq(r["etat"].longueur, longueur_avant, "longueur inchangee sans nourriture")

	# Etat terminal fige : evenements vides, ticks inchanges (0 rattrapage).
	var t = State.initial(7)
	t.statut = State.Statut.TERMINE_PERDU
	var ticks_avant = t.ticks
	var rt = Loop.step(t, DR.HAUT)
	h.eq(rt["evenements"].size(), 0, "partie terminee -> liste d'evenements vide")
	h.eq(rt["etat"].ticks, ticks_avant, "partie terminee -> ticks inchanges (etat fige)")
	h.eq(rt["etat"].statut, State.Statut.TERMINE_PERDU, "statut terminal conserve")

	# Mort par mur : tete poussee hors grille -> TERMINE_PERDU au tick exact.
	var w = State.initial(7)
	w.segments = [Vector2i(0, 5), Vector2i(1, 5), Vector2i(2, 5)]
	w.longueur = 3
	w.dir_effectuee = DR.GAUCHE
	w.dir_en_attente = DR.GAUCHE
	w.nourriture = Vector2i(10, 10)
	var rw = Loop.step(w, Loop.AUCUNE)
	h.eq(rw["etat"].statut, State.Statut.TERMINE_PERDU, "sortie a gauche -> perdu")
	h.eq(rw["etat"].ticks, 1, "un tick est compte meme sur la mort par mur")

	# Auto-collision REELLE (case de corps non-queue) : mort + le tick est compte.
	var sc = State.initial(7)
	sc.segments = [Vector2i(5, 5), Vector2i(5, 4), Vector2i(4, 4), Vector2i(4, 5), Vector2i(4, 6), Vector2i(5, 6), Vector2i(6, 6), Vector2i(6, 5)]
	sc.longueur = 8
	sc.dir_effectuee = DR.GAUCHE
	sc.dir_en_attente = DR.GAUCHE
	sc.nourriture = Vector2i(19, 19)
	var rsc = Loop.step(sc, Loop.AUCUNE)
	h.eq(rsc["etat"].statut, State.Statut.TERMINE_PERDU, "entrer dans son corps (non-queue) -> perdu")
	h.eq(rsc["etat"].ticks, 1, "un tick est compte sur la mort par auto-collision")

	# Case de queue LIBEREE au meme tick ne tue pas : serpent en U, la tete entre sur
	# l'ancienne case de queue qui se vide ce tick.
	var q = State.initial(7)
	# Corps : tete (2,2), (2,3), (3,3), (3,2). La tete va vers le HAUT -> (2,1)? non.
	# Construisons un cas ou la tete vise la case de la QUEUE.
	# tete=(1,1) allant DROITE ? on veut new_head == ancienne queue.
	# Corps: [ (1,1)=tete, (1,2), (2,2), (2,1)=queue ]. Direction HAUT -> new_head (1,0) libre.
	# Pour viser la queue (2,1) il faut aller ... la tete (1,1) n'est pas adjacente a (2,1)? si: (1,1)->(2,1) est DROITE.
	q.segments = [Vector2i(1, 1), Vector2i(1, 2), Vector2i(2, 2), Vector2i(2, 1)]
	q.longueur = 4
	q.dir_effectuee = DR.DROITE
	q.dir_en_attente = DR.DROITE
	q.nourriture = Vector2i(10, 10)
	var rq = Loop.step(q, Loop.AUCUNE)
	h.eq(rq["etat"].statut, State.Statut.EN_COURS, "entrer sur la queue liberee ne tue pas")
	h.eq(rq["etat"].segments[0], Vector2i(2, 1), "la tete a bien pris l'ancienne case de queue")
