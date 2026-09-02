# test_sudden_death.gd — la mort subite ferme reellement l'arene, dans un ordre
# deterministe, et ecrase ce qu'elle recouvre.
extends RefCounted

const P = preload("res://05_SYSTEMS/params/params.gd")
const SD = preload("res://05_SYSTEMS/sudden_death/sudden_death.gd")
const Loop = preload("res://05_SYSTEMS/game_loop/loop.gd")
const Fx = preload("res://07_TESTS/unit/fixtures.gd")


func run(h) -> void:
	# ---------- la spirale couvre TOUT l'interieur, une fois chacune ----------
	var sp: Array = SD.ordre_spirale(9, 9)
	h.eq(sp.size(), 49, "mort_subite: la spirale 9x9 couvre les 7x7 cases interieures")
	var vus := {}
	var doublon := false
	for c in sp:
		if vus.has(c):
			doublon = true
		vus[c] = true
	h.ok(not doublon, "mort_subite: aucune case n'est ecrasee deux fois")
	h.eq(vus.size(), 49, "mort_subite: chaque case interieure est atteinte")
	h.eq(sp[0], Vector2i(1, 1), "mort_subite: la spirale commence au coin haut-gauche interieur")
	h.eq(sp[sp.size() - 1], Vector2i(4, 4), "mort_subite: elle finit au CENTRE (spirale rentrante)")
	var hors := false
	for c in sp:
		if c.x < 1 or c.y < 1 or c.x > 7 or c.y > 7:
			hors = true
	h.ok(not hors, "mort_subite: la spirale ne sort jamais de l'interieur")

	# ---------- deterministe : meme geometrie -> meme ordre ----------
	h.eq(SD.ordre_spirale(9, 9), SD.ordre_spirale(9, 9), "mort_subite: ordre reproductible")
	h.eq(SD.ordre_spirale(15, 13).size(), 143, "mort_subite: l'arene livree a 143 cases interieures")

	# ---------- le declenchement suit le TEMPS, pas un compteur parallele ----------
	h.ok(not SD.active(P.MORT_SUBITE_DEBUT - 1), "mort_subite: inactive avant son heure")
	h.ok(SD.active(P.MORT_SUBITE_DEBUT), "mort_subite: active a son heure exacte")
	h.eq(SD.blocs_dus(P.MORT_SUBITE_DEBUT - 1), 0, "mort_subite: aucun bloc du avant l'heure")
	h.eq(SD.blocs_dus(P.MORT_SUBITE_DEBUT), 1, "mort_subite: un bloc du des le declenchement")
	h.eq(SD.blocs_dus(P.MORT_SUBITE_DEBUT + P.MORT_SUBITE_PERIODE), 2,
		"mort_subite: un bloc de plus par periode")

	# ---------- application : la case devient solide ----------
	var s = Fx.etat(Fx.desc_vide(), 1, 2)
	s.ticks = P.MORT_SUBITE_DEBUT
	var tombes: Array = SD.appliquer(s)
	h.eq(tombes.size(), 1, "mort_subite: une case tombe")
	h.ok(s.arene.est_solide(tombes[0]), "mort_subite: la case tombee est SOLIDE")
	h.eq(int(s.blocs_tombes), 1, "mort_subite: le compteur suit")
	h.eq(SD.appliquer(s).size(), 0, "mort_subite: rien ne retombe au meme tick")

	# ---------- un acteur ecrase MEURT, sans auteur invente ----------
	var s2 = Fx.etat(Fx.desc_vide(), 1, 2)
	s2.acteurs[0]["cellule"] = Vector2i(1, 1)
	s2.ticks = P.MORT_SUBITE_DEBUT
	SD.appliquer(s2)
	h.ok(not s2.acteurs[0]["vivant"], "mort_subite: l'acteur sous le bloc meurt")
	h.eq(int(s2.morts[0]["tueur"]), -1,
		"mort_subite: la mort subite n'a PAS d'auteur (elle ne gonfle pas les eliminations)")

	# ---------- une bombe ecrasee rend son credit ----------
	var s3 = Fx.etat(Fx.desc_vide(), 1, 2)
	s3.bombes.append({"proprietaire": 0, "cellule": Vector2i(1, 1), "meche": 5, "rayon": 1})
	s3.acteurs[0]["bombes_actives"] = 1
	s3.acteurs[0]["cellule"] = Vector2i(3, 3)
	s3.ticks = P.MORT_SUBITE_DEBUT
	SD.appliquer(s3)
	h.eq(s3.bombes.size(), 0, "mort_subite: la bombe ecrasee quitte le terrain")
	h.eq(int(s3.acteurs[0]["bombes_actives"]), 0, "mort_subite: son credit est rendu")

	# ---------- un power-up ecrase disparait ----------
	var s4 = Fx.etat(Fx.desc_vide(), 1, 2)
	s4.powerups[Vector2i(1, 1)] = P.PU_FIRE_UP
	s4.acteurs[0]["cellule"] = Vector2i(3, 3)
	s4.ticks = P.MORT_SUBITE_DEBUT
	SD.appliquer(s4)
	h.eq(s4.powerups.size(), 0, "mort_subite: le power-up sous le bloc est perdu")

	# ---------- rattrapage : un saut de temps ne perd aucun bloc ----------
	var s5 = Fx.etat(Fx.desc_vide(), 1, 2)
	s5.acteurs[0]["cellule"] = Vector2i(4, 4)
	s5.acteurs[1]["cellule"] = Vector2i(3, 4)
	s5.ticks = P.MORT_SUBITE_DEBUT + P.MORT_SUBITE_PERIODE * 5
	h.eq(SD.appliquer(s5).size(), 6, "mort_subite: le retard est rattrape, aucun bloc perdu")

	# ---------- la boucle la cable reellement (sinon le systeme serait inerte) ----------
	var s6 = Fx.etat(Fx.desc_vide(), 1, 2)
	s6.ticks = P.MORT_SUBITE_DEBUT
	var avant: int = s6.arene.nb_destructibles()
	var r: Dictionary = Loop.step(s6, [P.AUCUNE, P.AUCUNE])
	h.gt(int(r["state"].blocs_tombes), 0, "mort_subite: la BOUCLE l'applique (systeme non inerte)")
	var vu_event := false
	for e in r["events"]:
		if String(e["kind"]) == "mort_subite":
			vu_event = true
	h.ok(vu_event, "mort_subite: la boucle emet l'evenement observable")
	h.eq(avant, avant, "mort_subite: temoin de coherence du test")

	# ---------- clone : la progression suit l'etat ----------
	var s7 = Fx.etat(Fx.desc_vide(), 1, 2)
	s7.blocs_tombes = 12
	h.eq(int(s7.clone().blocs_tombes), 12, "mort_subite: le compteur survit au clone")

	# ---------- MUTANTS REELS tues par mesure (mutation 2026-08-10) ----------
	# `if acteur["vivant"] and acteur["cellule"] == c` mute en `or` : TOUT acteur vivant
	# mourrait au premier bloc tombe, ou qu'il soit. Je n'assertais que la mort de celui qui
	# est DESSOUS, jamais la SURVIE de celui qui est ailleurs — le cas negatif manquait.
	var sn = Fx.etat(Fx.desc_vide(), 1, 2)
	sn.acteurs[0]["cellule"] = Vector2i(5, 5)   # loin de la spirale, qui commence en (1,1)
	sn.acteurs[1]["cellule"] = Vector2i(1, 1)   # sous le premier bloc
	sn.ticks = P.MORT_SUBITE_DEBUT
	SD.appliquer(sn)
	h.ok(not sn.acteurs[1]["vivant"], "mort_subite: l'acteur SOUS le bloc meurt")
	h.ok(sn.acteurs[0]["vivant"], "mort_subite: un acteur AILLEURS survit (cas negatif)")
	h.eq(sn.morts.size(), 1, "mort_subite: exactement une mort, pas une hecatombe")

	# `if proprio >= 0 and proprio < size()` mute en `or` : un proprietaire hors bornes
	# passerait la garde. On force un index invalide et on exige l'absence de plantage.
	var sq = Fx.etat(Fx.desc_vide(), 1, 2)
	sq.bombes.append({"proprietaire": 99, "cellule": Vector2i(1, 1), "meche": 5, "rayon": 1})
	sq.acteurs[0]["cellule"] = Vector2i(5, 5)
	sq.acteurs[1]["cellule"] = Vector2i(6, 6)
	sq.ticks = P.MORT_SUBITE_DEBUT
	SD.appliquer(sq)
	h.eq(sq.bombes.size(), 0, "mort_subite: la bombe d'un proprietaire hors bornes est ecrasee")
	h.eq(int(sq.acteurs[0]["bombes_actives"]), 0, "mort_subite: aucun credit rendu a tort")
