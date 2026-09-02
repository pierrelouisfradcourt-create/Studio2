# test_explosion.gd — LE volet critique du jeu.
#
# Ce qui est prouve ici, et qui ne l'est nulle part ailleurs : la croix, l'arret sur solide,
# EXACTEMENT UN destructible par bras, la CHAINE dans le meme tick, et surtout
# l'INDEPENDANCE A L'ORDRE d'insertion — la propriete qui distingue une resolution
# deterministe d'une resolution qui se trouve etre stable sur l'exemple choisi.
extends RefCounted

const P = preload("res://05_SYSTEMS/params/params.gd")
const Explosion = preload("res://05_SYSTEMS/explosion/explosion.gd")
const Fx = preload("res://07_TESTS/unit/fixtures.gd")


func _poser(s, proprio: int, c: Vector2i, rayon: int) -> void:
	s.bombes.append({"proprietaire": proprio, "cellule": c, "meche": 1, "rayon": rayon})


func run(h) -> void:
	# ---------- croix simple, rayon 2, terrain vide ----------
	var s = Fx.etat(Fx.desc_vide(), 1, 2)
	_poser(s, 0, Vector2i(4, 4), 2)
	var r: Dictionary = Explosion.resoudre(s, [0])
	var f: Array = r["flammes"]
	h.eq(f.size(), 9, "explosion: croix rayon 2 sur terrain vide = 1 centre + 4x2 bras")
	h.ok(f.has(Vector2i(4, 4)), "explosion: le centre brule")
	h.ok(f.has(Vector2i(4, 2)) and f.has(Vector2i(4, 6)), "explosion: bras vertical complet")
	h.ok(f.has(Vector2i(2, 4)) and f.has(Vector2i(6, 4)), "explosion: bras horizontal complet")
	h.ok(not f.has(Vector2i(5, 5)), "explosion: la croix n'est PAS un carre (aucune diagonale)")
	h.eq(r["detruites"].size(), 0, "explosion: rien a detruire sur terrain vide")
	h.eq(r["explosees"], [0], "explosion: une seule bombe explosee")

	# ---------- arret sur solide ----------
	var s2 = Fx.etat(Fx.desc_vide(), 1, 2)
	_poser(s2, 0, Vector2i(1, 4), 5)
	var r2: Dictionary = Explosion.resoudre(s2, [0])
	h.ok(not r2["flammes"].has(Vector2i(0, 4)), "explosion: le bras n'entre pas dans le mur")
	h.ok(r2["flammes"].has(Vector2i(2, 4)), "explosion: le bras progresse du cote libre")
	h.ok(not r2["flammes"].has(Vector2i(-1, 4)), "explosion: aucune flamme hors bornes")

	# ---------- EXACTEMENT UN destructible par bras ----------
	# Ligne y=1 de desc_blocs : "#S.+.S#" -> (3,1) est destructible.
	var s3 = Fx.etat(Fx.desc_blocs(), 1, 2)
	_poser(s3, 0, Vector2i(2, 1), 4)
	var r3: Dictionary = Explosion.resoudre(s3, [0])
	h.ok(r3["detruites"].has(Vector2i(3, 1)), "explosion: le premier destructible du bras est detruit")
	h.ok(not r3["flammes"].has(Vector2i(4, 1)), "explosion: le bras S'ARRETE sur le destructible")
	h.eq(r3["detruites"].size(), 2, "explosion: exactement un destructible par bras (droite + bas)")

	# ---------- CHAINE : deux bombes, meme tick ----------
	var s4 = Fx.etat(Fx.desc_vide(), 1, 2)
	_poser(s4, 0, Vector2i(2, 4), 2)   # index 0
	_poser(s4, 1, Vector2i(4, 4), 2)   # index 1, dans la portee de la premiere
	var r4: Dictionary = Explosion.resoudre(s4, [0])
	h.eq(r4["explosees"].size(), 2, "explosion: la bombe touchee explose DANS LE MEME TICK")
	h.ok(r4["flammes"].has(Vector2i(6, 4)), "explosion: la chaine porte au-dela de la premiere portee")
	h.ok(not r4["flammes"].has(Vector2i(3, 3)), "explosion: la chaine reste en croix")

	# ---------- une bombe ARRETE le bras qui l'atteint ----------
	var s5 = Fx.etat(Fx.desc_vide(), 1, 2)
	_poser(s5, 0, Vector2i(2, 4), 4)
	_poser(s5, 1, Vector2i(3, 4), 1)
	var r5: Dictionary = Explosion.resoudre(s5, [0])
	h.ok(r5["flammes"].has(Vector2i(4, 4)), "explosion: la bombe chainee propage SA propre croix")
	h.ok(not r5["flammes"].has(Vector2i(5, 4)),
		"explosion: le bras d'origine est absorbe par la bombe (portee 4 non depliee)")

	# ---------- CHAINE LONGUE : point fixe, pas une seule iteration ----------
	var s6 = Fx.etat(Fx.desc_vide(), 1, 2)
	for i in range(5):
		_poser(s6, 0, Vector2i(1 + i, 1), 1)
	var r6: Dictionary = Explosion.resoudre(s6, [0])
	h.eq(r6["explosees"].size(), 5, "explosion: la chaine se resout JUSQU'AU POINT FIXE (5 bombes)")

	# ---------- INDEPENDANCE A L'ORDRE D'INSERTION ----------
	# La propriete forte : le resultat est une CLOTURE. Deux ordres d'amorcage differents
	# doivent donner exactement les memes ensembles. Sans ce test, on prouverait seulement
	# qu'un ordre donne est stable, ce qui est plus faible.
	var s7 = Fx.etat(Fx.desc_vide(), 1, 2)
	_poser(s7, 0, Vector2i(3, 3), 2)
	_poser(s7, 1, Vector2i(5, 3), 2)
	_poser(s7, 0, Vector2i(3, 5), 2)
	var a: Dictionary = Explosion.resoudre(s7, [0, 1, 2])
	var b: Dictionary = Explosion.resoudre(s7, [2, 1, 0])
	var fa: Array = a["flammes"].duplicate(); fa.sort()
	var fb: Array = b["flammes"].duplicate(); fb.sort()
	h.eq(fa, fb, "explosion: memes flammes quel que soit l'ordre d'amorcage")
	var da: Array = a["detruites"].duplicate(); da.sort()
	var db: Array = b["detruites"].duplicate(); db.sort()
	h.eq(da, db, "explosion: memes destructions quel que soit l'ordre d'amorcage")
	var ea: Array = a["explosees"].duplicate(); ea.sort()
	var eb: Array = b["explosees"].duplicate(); eb.sort()
	h.eq(ea, eb, "explosion: memes bombes explosees quel que soit l'ordre d'amorcage")

	# ---------- attribution : chaque case brulee a un auteur ----------
	var auteurs: Dictionary = a["auteur_par_case"]
	h.eq(auteurs.size(), a["flammes"].size(), "explosion: chaque case brulee porte son auteur")
	h.ok(auteurs.has(Vector2i(3, 3)), "explosion: le centre est attribue")
	h.eq(int(auteurs[Vector2i(3, 3)]), 0, "explosion: le centre est attribue a SON poseur")

	# ---------- une bombe deja resolue n'est jamais comptee deux fois ----------
	var r8: Dictionary = Explosion.resoudre(s4, [0, 1, 0, 1])
	h.eq(r8["explosees"].size(), 2, "explosion: aucun doublon meme si l'amorcage repete une bombe")

	# ---------- rayon 0 : seul le centre brule ----------
	var s9 = Fx.etat(Fx.desc_vide(), 1, 2)
	_poser(s9, 0, Vector2i(4, 4), 0)
	var r9: Dictionary = Explosion.resoudre(s9, [0])
	h.eq(r9["flammes"].size(), 1, "explosion: rayon 0 ne brule que le centre")

	# ---------- index hors bornes : ignore, jamais un crash ----------
	var r10: Dictionary = Explosion.resoudre(s9, [42, -1, 0])
	h.eq(r10["explosees"].size(), 1, "explosion: un index invalide est ignore, pas fatal")

	# ---------- MUTANTS REELS, tues par mesure (mutation 2026-08-10) ----------
	# La mutation a survecu deux fois sur explosion.gd ; ces deux volets existent pour
	# fermer les trous qu'elle a nommes, pas pour couvrir une ligne.

	# (a) `if autre >= 0` muté en `> 0` : `bombe_sur` rend -1 ou un INDEX, et l'index 0 est
	# VALIDE. Le mutant cesse donc de chainer vers la PREMIERE bombe posee, en silence.
	# Pour le distinguer il faut une chaine qui remonte vers l'index 0 — les tests
	# precedents amorcaient toujours DEPUIS l'index 0, ou le cas ne se presente jamais.
	var sm = Fx.etat(Fx.desc_vide(), 1, 2)
	_poser(sm, 0, Vector2i(3, 3), 1)   # index 0 — la cible de la chaine
	_poser(sm, 1, Vector2i(5, 3), 2)   # index 1 — l'amorce, sa portee atteint (3,3)
	var rm: Dictionary = Explosion.resoudre(sm, [1])
	h.eq(rm["explosees"].size(), 2,
		"explosion: la chaine atteint la bombe d'INDEX 0 (borne inferieure valide)")
	h.ok(rm["explosees"].has(0), "explosion: l'index 0 est bien dans les bombes explosees")

	# (b) `if idx < 0 or idx >= state.bombes.size()` muté en `>` : un index EXACTEMENT egal
	# a la taille passerait la garde et lirait hors bornes. Les tests precedents n'essayaient
	# que 42, tres au-dela, que `>` rejette aussi.
	var sb = Fx.etat(Fx.desc_vide(), 1, 2)
	_poser(sb, 0, Vector2i(4, 4), 1)
	var rb: Dictionary = Explosion.resoudre(sb, [sb.bombes.size()])
	h.eq(rb["explosees"].size(), 0,
		"explosion: un index EGAL a la taille est rejete (borne superieure exacte)")
	h.eq(rb["flammes"].size(), 0, "explosion: aucun effet d'un index hors bornes exact")
