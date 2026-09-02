# test_movement_bombs.gd — deplacement legal/refuse, cooldown, et regles de pose.
# La regle qui compte : une bombe ne bloque pas son poseur tant qu'il n'a pas quitte sa
# case. Sans elle, poser reviendrait a se murer, et le jeu n'aurait aucune sortie.
extends RefCounted

const P = preload("res://05_SYSTEMS/params/params.gd")
const Movement = preload("res://05_SYSTEMS/movement_rules/movement.gd")
const Bombs = preload("res://05_SYSTEMS/bombs/bombs.gd")
const Fx = preload("res://07_TESTS/unit/fixtures.gd")


func run(h) -> void:
	# ---------- deplacement ----------
	var s = Fx.etat(Fx.desc_vide(), 1, 2)
	var depart: Vector2i = s.acteurs[0]["cellule"]
	h.eq(depart, Vector2i(1, 1), "movement: l'acteur 0 demarre sur son spawn")

	h.ok(Movement.appliquer(s, 0, P.DROITE), "movement: un pas vers une case libre est accepte")
	h.eq(s.acteurs[0]["cellule"], Vector2i(2, 1), "movement: la case a change")
	h.eq(int(s.acteurs[0]["cd_restant"]), P.MOVE_COOLDOWN_BASE, "movement: le cooldown est arme")

	h.ok(not Movement.appliquer(s, 0, P.DROITE), "movement: refuse pendant le cooldown")
	h.eq(s.acteurs[0]["cellule"], Vector2i(2, 1), "movement: la case n'a pas bouge sous cooldown")
	for i in range(P.MOVE_COOLDOWN_BASE):
		Movement.decompter(s)
	h.ok(Movement.appliquer(s, 0, P.DROITE), "movement: accepte une fois le cooldown ecoule")

	# mur
	var s2 = Fx.etat(Fx.desc_vide(), 1, 2)
	h.ok(not Movement.appliquer(s2, 0, P.HAUT), "movement: un mur refuse le pas")
	h.eq(s2.acteurs[0]["cellule"], Vector2i(1, 1), "movement: la case est inchangee face au mur")
	h.eq(int(s2.acteurs[0]["direction"]), P.HAUT,
		"movement: l'orientation suit l'intention MEME refusee (le refus reste lisible)")
	h.eq(int(s2.acteurs[0]["cd_restant"]), 0, "movement: un pas refuse n'arme pas le cooldown")

	# intention hors domaine
	h.ok(not Movement.appliquer(s2, 0, P.AUCUNE), "movement: AUCUNE ne deplace pas")
	h.ok(not Movement.appliquer(s2, 0, 99), "movement: une intention hors domaine est refusee")
	h.ok(not Movement.appliquer(s2, 0, -3), "movement: une intention negative est refusee")

	# acteur mort
	var s3 = Fx.etat(Fx.desc_vide(), 1, 2)
	s3.acteurs[0]["vivant"] = false
	h.ok(not Movement.appliquer(s3, 0, P.DROITE), "movement: un mort ne bouge pas")

	# ---------- pose ----------
	var s4 = Fx.etat(Fx.desc_vide(), 1, 2)
	h.ok(Bombs.poser(s4, 0), "bombs: la premiere pose est acceptee")
	h.eq(s4.bombes.size(), 1, "bombs: une bombe est sur le terrain")
	h.eq(int(s4.acteurs[0]["bombes_actives"]), 1, "bombs: le compteur du poseur a monte")
	h.eq(int(s4.bombes[0]["meche"]), P.MECHE_TICKS, "bombs: la meche part de sa valeur declaree")
	h.eq(int(s4.bombes[0]["rayon"]), P.RAYON_BASE, "bombs: la bombe herite du rayon de son poseur")

	h.ok(not Bombs.poser(s4, 0), "bombs: pose refusee au plafond de bombes")
	h.eq(s4.bombes.size(), 1, "bombs: aucune bombe fantome apres un refus")

	# la bombe ne bloque pas son poseur tant qu'il est dessus
	h.ok(Movement.traversable(s4, 0, Vector2i(1, 1)),
		"bombs: le poseur n'est pas mure par sa propre bombe")
	h.ok(not Movement.traversable(s4, 1, Vector2i(1, 1)),
		"bombs: la bombe bloque les AUTRES acteurs")
	h.ok(Movement.appliquer(s4, 0, P.DROITE), "bombs: le poseur peut s'echapper")
	h.ok(not Movement.traversable(s4, 0, Vector2i(1, 1)),
		"bombs: une fois sorti, le poseur ne peut plus revenir sur sa bombe")

	# deux bombes sur la meme case, jamais
	var s5 = Fx.etat(Fx.desc_vide(), 1, 2)
	s5.acteurs[0]["bombes_max"] = 3
	h.ok(Bombs.poser(s5, 0), "bombs: pose 1 acceptee (plafond 3)")
	h.ok(not Bombs.poser(s5, 0), "bombs: deux bombes sur la MEME case sont refusees")

	# un acteur bloque un autre acteur
	var s6 = Fx.etat(Fx.desc_vide(), 1, 2)
	s6.acteurs[1]["cellule"] = Vector2i(2, 1)
	h.ok(not Movement.traversable(s6, 0, Vector2i(2, 1)), "movement: un acteur vivant bloque")
	s6.acteurs[1]["vivant"] = false
	h.ok(Movement.traversable(s6, 0, Vector2i(2, 1)), "movement: un acteur mort ne bloque plus")

	# ---------- meche et credit ----------
	var s7 = Fx.etat(Fx.desc_vide(), 1, 2)
	Bombs.poser(s7, 0)
	var echues: Array = Bombs.tick_meches(s7)
	h.eq(echues.size(), 0, "bombs: la meche ne s'acheve pas au premier tick")
	h.eq(int(s7.bombes[0]["meche"]), P.MECHE_TICKS - 1, "bombs: la meche descend d'un tick")
	for i in range(P.MECHE_TICKS):
		echues = Bombs.tick_meches(s7)
		if not echues.is_empty():
			break
	h.eq(echues, [0], "bombs: la meche arrive a echeance et NOMME la bombe")

	Bombs.retirer(s7, echues)
	h.eq(s7.bombes.size(), 0, "bombs: la bombe explosee quitte le terrain")
	h.eq(int(s7.acteurs[0]["bombes_actives"]), 0, "bombs: le credit est rendu au poseur")

	# retrait multiple : les indices ne doivent pas se decaler
	var s8 = Fx.etat(Fx.desc_vide(), 1, 2)
	s8.acteurs[0]["bombes_max"] = 3
	s8.bombes.append({"proprietaire": 0, "cellule": Vector2i(1, 1), "meche": 1, "rayon": 1})
	s8.bombes.append({"proprietaire": 0, "cellule": Vector2i(2, 1), "meche": 1, "rayon": 1})
	s8.bombes.append({"proprietaire": 0, "cellule": Vector2i(3, 1), "meche": 1, "rayon": 1})
	s8.acteurs[0]["bombes_actives"] = 3
	Bombs.retirer(s8, [0, 2])
	h.eq(s8.bombes.size(), 1, "bombs: retrait multiple sans decalage d'indices")
	h.eq(s8.bombes[0]["cellule"], Vector2i(2, 1), "bombs: c'est la BONNE bombe qui reste")
	h.eq(int(s8.acteurs[0]["bombes_actives"]), 1, "bombs: le credit rendu correspond au retrait")

	# ---------- MUTANTS REELS tues par mesure (mutation 2026-08-10) ----------
	# (1) `poser` sur un acteur MORT rendait false, jamais asserte.
	var sd1 = Fx.etat(Fx.desc_vide(), 1, 2)
	sd1.acteurs[0]["vivant"] = false
	h.ok(not Bombs.poser(sd1, 0), "bombs: un acteur MORT ne pose pas")
	h.eq(sd1.bombes.size(), 0, "bombs: aucune bombe posee par un mort")

	# (2) `bombes_actives >= bombes_max` mute en `>` : au plafond EXACT le mutant autorise
	# une bombe de plus. Le test precedent ne l'attrapait pas parce que la SECONDE garde
	# (une bombe est deja sur la case) masquait la premiere — il faut donc BOUGER apres avoir
	# pose. Un mutant peut survivre derriere une garde redondante : c'est le cas d'ecole.
	var sd2 = Fx.etat(Fx.desc_vide(), 1, 2)
	h.ok(Bombs.poser(sd2, 0), "bombs: premiere pose acceptee")
	for i in range(P.MOVE_COOLDOWN_BASE):
		Movement.decompter(sd2)
	h.ok(Movement.appliquer(sd2, 0, P.DROITE), "bombs: le poseur s'ecarte de sa bombe")
	h.ok(not Bombs.poser(sd2, 0),
		"bombs: au plafond EXACT, refus meme sur une case libre (garde non masquee)")
	h.eq(sd2.bombes.size(), 1, "bombs: le plafond tient reellement")

	# (3) `meche <= 0` mute en `< 0` : une meche arrivant EXACTEMENT a zero n'exploserait pas.
	var sd3 = Fx.etat(Fx.desc_vide(), 1, 2)
	sd3.bombes.append({"proprietaire": 0, "cellule": Vector2i(3, 3), "meche": 1, "rayon": 1})
	h.eq(Bombs.tick_meches(sd3), [0], "bombs: la meche echoit a EXACTEMENT zero, pas en dessous")
	h.eq(int(sd3.bombes[0]["meche"]), 0, "bombs: la meche vaut bien zero a l'echeance")

	# (4) `proprio >= 0 and proprio < size()` mute en `or` : proprietaire hors bornes.
	var sd4 = Fx.etat(Fx.desc_vide(), 1, 2)
	sd4.bombes.append({"proprietaire": 42, "cellule": Vector2i(3, 3), "meche": 1, "rayon": 1})
	Bombs.retirer(sd4, [0])
	h.eq(sd4.bombes.size(), 0, "bombs: une bombe de proprietaire hors bornes est retiree")
	h.eq(int(sd4.acteurs[0]["bombes_actives"]), 0, "bombs: aucun credit rendu a tort")
