# test_loop_and_rules.gd — le tick complet, le determinisme, les power-ups data-driven,
# la mort attribuee, la victoire, et la purete de l'entree.
extends RefCounted

const P = preload("res://05_SYSTEMS/params/params.gd")
const Loop = preload("res://05_SYSTEMS/game_loop/loop.gd")
const Bombs = preload("res://05_SYSTEMS/bombs/bombs.gd")
const PowerUps = preload("res://05_SYSTEMS/powerups/powerups.gd")
const Victory = preload("res://05_SYSTEMS/victory/victory.gd")
const Score = preload("res://05_SYSTEMS/score/score.gd")
const Damage = preload("res://05_SYSTEMS/damage/damage.gd")
const Movement = preload("res://05_SYSTEMS/movement_rules/movement.gd")
const Rng = preload("res://05_SYSTEMS/rng/rng.gd")
const Fx = preload("res://07_TESTS/unit/fixtures.gd")


func _avancer(s, n: int, intentions: Array):
	for i in range(n):
		s = Loop.step(s, intentions)["state"]
	return s


func run(h) -> void:
	# ---------- purete : step ne mute JAMAIS son entree ----------
	var s = Fx.etat(Fx.desc_vide(), 7, 2)
	var avant: Vector2i = s.acteurs[0]["cellule"]
	var avant_ticks: int = s.ticks
	var r: Dictionary = Loop.step(s, [P.DROITE, P.AUCUNE])
	h.eq(s.acteurs[0]["cellule"], avant, "loop: l'etat d'ENTREE n'est pas mute (position)")
	h.eq(s.ticks, avant_ticks, "loop: l'etat d'ENTREE n'est pas mute (ticks)")
	h.eq(r["state"].acteurs[0]["cellule"], Vector2i(2, 1), "loop: l'etat de SORTIE porte le pas")
	h.eq(int(r["state"].ticks), avant_ticks + 1, "loop: le tick avance d'exactement 1")

	# ---------- determinisme : meme etat + memes intentions + meme graine ----------
	var a = Fx.etat(Fx.desc_blocs(), 42, 2)
	var b = Fx.etat(Fx.desc_blocs(), 42, 2)
	var intentions: Array = [P.POSER, P.GAUCHE]
	for i in range(60):
		a = Loop.step(a, intentions)["state"]
		b = Loop.step(b, intentions)["state"]
	h.eq(a.acteurs[0]["cellule"], b.acteurs[0]["cellule"], "loop: determinisme (position acteur 0)")
	h.eq(a.acteurs[1]["cellule"], b.acteurs[1]["cellule"], "loop: determinisme (position acteur 1)")
	h.eq(a.arene.nb_destructibles(), b.arene.nb_destructibles(), "loop: determinisme (arene)")
	h.eq(a.powerups.size(), b.powerups.size(), "loop: determinisme (power-ups reveles)")
	h.eq(a.graine, b.graine, "loop: determinisme (graine)")
	h.eq(a.statut, b.statut, "loop: determinisme (statut)")

	# ---------- une graine differente change le monde (variance, sinon la graine ment) ----------
	# Sur cette carte, densite 100 % : chaque bloc detruit revele. La variance porte donc sur
	# l'IDENTIFIANT tire, pas sur la presence — on la mesure la ou elle existe.
	var poids := {P.PU_BOMB_UP: 1, P.PU_FIRE_UP: 1, P.PU_SPEED_UP: 1}
	var tires := {}
	for g in range(40):
		var res: Dictionary = PowerUps.reveler(100, poids, g * 7919)
		tires[String(res["identifiant"])] = true
	h.gt(tires.size(), 1, "rng: le tirage pondere produit PLUSIEURS identifiants distincts")

	# ---------- rng : purete et bornes ----------
	h.eq(Rng.suivant(12345), Rng.suivant(12345), "rng: meme graine -> meme suite")
	h.ok(Rng.entier(999, 5) >= 0 and Rng.entier(999, 5) < 5, "rng: entier borne dans [0,5)")
	h.eq(Rng.entier(999, 0), 0, "rng: borne nulle rend 0, jamais une division par zero")
	h.eq(Rng.pondere(1, {}, P.POWERUP_IDS), "", "rng: table vide -> aucun tirage")
	h.eq(Rng.pondere(1, {P.PU_FIRE_UP: 0}, P.POWERUP_IDS), "", "rng: poids nuls -> aucun tirage")
	h.eq(Rng.pondere(1, {P.PU_FIRE_UP: 5}, P.POWERUP_IDS), P.PU_FIRE_UP,
		"rng: un seul poids positif -> ce tirage, toujours")

	# ---------- power-ups : DATA-DRIVEN et bornes ----------
	var acteur := {"bombes_max": P.BOMBES_BASE, "rayon": P.RAYON_BASE, "cooldown": P.MOVE_COOLDOWN_BASE}
	h.ok(PowerUps.appliquer(acteur, P.PU_FIRE_UP), "powerups: FIRE_UP a un effet")
	h.eq(int(acteur["rayon"]), P.RAYON_BASE + 1, "powerups: FIRE_UP augmente le rayon d'exactement 1")
	h.ok(PowerUps.appliquer(acteur, P.PU_BOMB_UP), "powerups: BOMB_UP a un effet")
	h.eq(int(acteur["bombes_max"]), P.BOMBES_BASE + 1, "powerups: BOMB_UP augmente le plafond de 1")
	h.ok(PowerUps.appliquer(acteur, P.PU_SPEED_UP), "powerups: SPEED_UP a un effet")
	h.eq(int(acteur["cooldown"]), P.MOVE_COOLDOWN_BASE - P.SPEED_STEP,
		"powerups: SPEED_UP REDUIT le cooldown (aller plus vite = attendre moins)")

	# plafonds : un power-up au plafond ne ment pas sur son effet
	for i in range(50):
		PowerUps.appliquer(acteur, P.PU_FIRE_UP)
	h.eq(int(acteur["rayon"]), P.RAYON_MAX, "powerups: le rayon est BORNE a son plafond")
	h.ok(not PowerUps.appliquer(acteur, P.PU_FIRE_UP),
		"powerups: au plafond, l'application rend false (elle ne pretend pas avoir agi)")
	for i in range(50):
		PowerUps.appliquer(acteur, P.PU_SPEED_UP)
	h.eq(int(acteur["cooldown"]), P.MOVE_COOLDOWN_MIN, "powerups: le cooldown a un PLANCHER")

	h.ok(not PowerUps.appliquer(acteur, "INCONNU"),
		"powerups: un identifiant hors registre n'a aucun effet")
	h.eq(P.POWERUP_DEFS.size(), P.POWERUP_IDS.size(),
		"powerups: la table et l'ordre declare portent le MEME nombre d'entrees")
	for id in P.POWERUP_IDS:
		h.ok(P.POWERUP_DEFS.has(id), "powerups: '%s' est defini dans la table" % str(id))

	# ramassage
	var s3 = Fx.etat(Fx.desc_vide(), 1, 2)
	s3.powerups[s3.acteurs[0]["cellule"]] = P.PU_FIRE_UP
	var faits: Array = PowerUps.ramasser(s3)
	h.eq(faits.size(), 1, "powerups: l'acteur sur la case ramasse")
	h.eq(int(s3.acteurs[0]["rayon"]), P.RAYON_BASE + 1, "powerups: le ramassage applique l'effet")
	h.eq(s3.powerups.size(), 0, "powerups: le power-up ramasse quitte le sol")
	h.eq(PowerUps.ramasser(s3).size(), 0, "powerups: rien a ramasser deux fois")

	# ---------- mort ATTRIBUEE ----------
	var s4 = Fx.etat(Fx.desc_vide(), 1, 2)
	var c0: Vector2i = s4.acteurs[0]["cellule"]
	s4.flammes[c0] = P.DUREE_FLAMME
	s4.flammes_auteur[c0] = 1
	var morts: Array = Damage.appliquer(s4)
	h.eq(morts.size(), 1, "damage: un acteur sur une case letale meurt")
	h.eq(int(morts[0]["victime"]), 0, "damage: la victime est nommee")
	h.eq(int(morts[0]["tueur"]), 1, "damage: le TUEUR est attribue (elimination active mesurable)")
	h.ok(not s4.acteurs[0]["vivant"], "damage: la victime n'est plus vivante")
	h.eq(Damage.appliquer(s4).size(), 0, "damage: on ne meurt pas deux fois")

	var s5 = Fx.etat(Fx.desc_vide(), 1, 2)
	s5.flammes[s5.acteurs[0]["cellule"]] = P.DUREE_FLAMME
	var m2: Array = Damage.appliquer(s5)
	h.eq(int(m2[0]["tueur"]), -1, "damage: sans auteur connu, le tueur vaut -1 (jamais invente)")

	# la letalite s'use
	var s6 = Fx.etat(Fx.desc_vide(), 1, 2)
	s6.flammes[Vector2i(4, 4)] = 2
	Damage.decompter_flammes(s6)
	h.eq(int(s6.flammes[Vector2i(4, 4)]), 1, "damage: la letalite descend d'un tick")
	Damage.decompter_flammes(s6)
	h.eq(s6.flammes.size(), 0, "damage: une case eteinte QUITTE la table (elle ne grossit pas)")

	# ---------- victoire ----------
	var s7 = Fx.etat(Fx.desc_vide(), 1, 2)
	h.eq(Victory.evaluer(s7), P.EN_COURS, "victory: deux vivants -> en cours")
	s7.acteurs[1]["vivant"] = false
	h.eq(Victory.evaluer(s7), P.GAGNE, "victory: dernier vivant = le joueur -> gagne")
	s7.acteurs[0]["vivant"] = false
	h.eq(Victory.evaluer(s7), P.NUL, "victory: zero vivant -> NUL, jamais une victoire sans vainqueur")

	var s8 = Fx.etat(Fx.desc_vide(), 1, 2)
	s8.acteurs[0]["vivant"] = false
	h.eq(Victory.evaluer(s8), P.PERDU, "victory: le joueur mort, un bot survit -> perdu")

	var s9 = Fx.etat(Fx.desc_vide(), 1, 2)
	s9.ticks = P.DUREE_MAX_TICKS
	h.eq(Victory.evaluer(s9), P.NUL, "victory: la duree maximale rend NUL (jamais de partie infinie)")

	var s10 = Fx.etat(Fx.desc_vide(), 1, 2)
	s10.regle_victoire = P.VICTOIRE_CLEAR_ALL_BOTS
	h.eq(Victory.evaluer(s10), P.EN_COURS, "victory: CLEAR_ALL_BOTS en cours tant qu'un bot vit")
	s10.acteurs[1]["vivant"] = false
	h.eq(Victory.evaluer(s10), P.GAGNE, "victory: CLEAR_ALL_BOTS gagne quand tous les bots sont morts")

	# ---------- partie terminee : le tick est neutre ----------
	var s11 = Fx.etat(Fx.desc_vide(), 1, 2)
	s11.statut = P.GAGNE
	var apres: Dictionary = Loop.step(s11, [P.DROITE, P.DROITE])
	h.eq(apres["state"].ticks, s11.ticks, "loop: une partie terminee n'avance plus")
	h.eq(apres["events"], [], "loop: une partie terminee n'emet plus d'evenement")

	# ---------- bout en bout : poser une bombe detruit un bloc ----------
	var s12 = Fx.etat(Fx.desc_blocs(), 3, 2)
	# Rayon 2 : depuis le spawn (1,1), le bras droit atteint (2,1) puis le destructible
	# (3,1). Au rayon de base il n'y a AUCUN bloc a portee depuis un coin — le scenario
	# aurait mesure « rien ne se detruit » en croyant mesurer la destruction.
	s12.acteurs[0]["rayon"] = 2
	var blocs_avant: int = s12.arene.nb_destructibles()
	s12 = Loop.step(s12, [P.POSER, P.AUCUNE])["state"]
	h.eq(s12.bombes.size(), 1, "bout-en-bout: la bombe est posee par la boucle")
	s12 = _avancer(s12, P.MECHE_TICKS + 2, [P.AUCUNE, P.AUCUNE])
	h.eq(s12.bombes.size(), 0, "bout-en-bout: la bombe a explose et quitte le terrain")
	h.gt(blocs_avant, s12.arene.nb_destructibles(), "bout-en-bout: un bloc a REELLEMENT ete detruit")
	h.ok(not s12.acteurs[0]["vivant"],
		"bout-en-bout: rester sur sa propre bombe tue — la menace commence par soi")

	# ---------- entrees hors domaine : l'etat reste valide ----------
	var s13 = Fx.etat(Fx.desc_vide(), 1, 2)
	var t1: Dictionary = Loop.step(s13, [])
	h.eq(int(t1["state"].ticks), 1, "error_guard: une liste d'intentions VIDE avance sans casser")
	var t2: Dictionary = Loop.step(s13, [999, -42, 7, 3])
	h.eq(int(t2["state"].ticks), 1, "error_guard: intentions hors domaine et surnumeraires absorbees")
	h.eq(t2["state"].acteurs.size(), 2, "error_guard: le nombre d'acteurs est inchange")
	h.eq(t2["state"].statut, P.EN_COURS, "error_guard: l'etat reste valide apres entree invalide")

	# ---------- MUTANTS REELS tues par mesure (mutation 2026-08-10) ----------
	# (a) `if String(rev["identifiant"]) != ""` mute en `==` : un power-up ne serait pose
	# que quand le tirage ne rend RIEN. Il faut donc asserter qu'un power-up reellement
	# revele porte un identifiant du registre — je ne verifiais que des comptes.
	var sm1 = Fx.etat(Fx.desc_blocs(), 3, 2)   # densite 100 % sur cette carte
	sm1.acteurs[0]["rayon"] = 2
	sm1 = Loop.step(sm1, [P.POSER, P.AUCUNE])["state"]
	for i in range(P.MECHE_TICKS + 4):
		sm1 = Loop.step(sm1, [P.AUCUNE, P.AUCUNE])["state"]
	h.gt(sm1.powerups.size(), 0, "loop: une destruction a densite 100 % REVELE un power-up")
	for c in sm1.powerups.keys():
		h.ok(P.POWERUP_IDS.has(String(sm1.powerups[c])),
			"loop: le power-up pose porte un identifiant NON VIDE du registre")

	# (b) `if s.statut != P.EN_COURS` (emission de `fin`) mute en `==` : l'evenement de fin
	# serait emis pendant la partie et jamais a la fin.
	var sm2 = Fx.etat(Fx.desc_vide(), 1, 2)
	var r2b: Dictionary = Loop.step(sm2, [P.AUCUNE, P.AUCUNE])
	var fin_en_cours := false
	for e in r2b["events"]:
		if String(e["kind"]) == "fin":
			fin_en_cours = true
	h.ok(not fin_en_cours, "loop: aucun evenement `fin` tant que la partie est EN COURS")
	var sm3 = Fx.etat(Fx.desc_vide(), 1, 2)
	sm3.acteurs[1]["vivant"] = false          # dernier vivant = joueur -> GAGNE ce tick
	var r3b: Dictionary = Loop.step(sm3, [P.AUCUNE, P.AUCUNE])
	var fin_a_la_fin := false
	for e in r3b["events"]:
		if String(e["kind"]) == "fin":
			fin_a_la_fin = true
	h.ok(fin_a_la_fin, "loop: l'evenement `fin` est emis AU tick terminal")

	# (c) `Score.total(events, INDEX_JOUEUR, s.statut == P.GAGNE)` mute en `!=` : la prime de
	# victoire serait versee sur une DEFAITE et refusee sur une victoire.
	h.gt(int(r3b["state"].score), Score.POINTS_VICTOIRE - 1,
		"loop: la prime de victoire est versee sur une VICTOIRE, de bout en bout")
	var sm4 = Fx.etat(Fx.desc_vide(), 1, 2)
	sm4.acteurs[0]["vivant"] = false          # joueur mort -> PERDU
	var r4b: Dictionary = Loop.step(sm4, [P.AUCUNE, P.AUCUNE])
	h.eq(int(r4b["state"].score), 0, "loop: aucune prime sur une DEFAITE")

	# ---------- MUTANTS REELS lot 2 (mutation 2026-08-10) ----------
	# `densite <= 0` mute en `< 0` : une densite EXACTEMENT nulle tirerait quand meme.
	var rz: Dictionary = PowerUps.reveler(0, {P.PU_FIRE_UP: 1}, 12345)
	h.eq(String(rz["identifiant"]), "", "powerups: densite ZERO ne revele jamais rien")

	# `Rng.entier(g,100) >= densite` mute en `>` : la valeur EGALE au seuil doit REFUSER.
	# On cherche une graine ou le tirage vaut exactement la densite — sinon la borne n'est
	# jamais exercee.
	var densite := 37
	var trouve := false
	for g in range(4000):
		if Rng.entier(Rng.suivant(g), 100) == densite:
			h.eq(String(PowerUps.reveler(densite, {P.PU_FIRE_UP: 1}, g)["identifiant"]), "",
				"powerups: un tirage EGAL au seuil refuse (borne exacte)")
			trouve = true
			break
	h.ok(trouve, "powerups: une graine exerçant la borne exacte a ete trouvee")

	# `appliquer` : champ absent de l'acteur -> aucun effet (cas negatif non couvert).
	var incomplet := {"rayon": 1}
	h.ok(not PowerUps.appliquer(incomplet, P.PU_BOMB_UP),
		"powerups: un acteur SANS le champ vise n'est pas modifie")
	h.eq(incomplet.size(), 1, "powerups: aucun champ cree a la volee")

	# victory `acteurs.size() <= 1` mute en `< 1` : une partie a UN SEUL acteur n'a pas de
	# vainqueur par elimination — elle reste en cours.
	var solo = Fx.etat(Fx.desc_vide(), 1, 1)
	h.eq(solo.acteurs.size(), 1, "victory: la partie temoin n'a qu'un acteur")
	h.eq(Victory.evaluer(solo), P.EN_COURS,
		"victory: avec UN SEUL acteur, aucune victoire par dernier survivant")

	# `densite <= 0` mute en `< 0` : a densite ZERO les deux chemins rendent un identifiant
	# vide, mais PAS la meme graine — l'original court-circuite, le mutant consomme un tirage
	# de plus. La difference n'est observable que sur la GRAINE, et c'est elle qui porte le
	# determinisme du rejeu. Asserter l'identifiant seul laissait le mutant vivre.
	var rz0: Dictionary = PowerUps.reveler(0, {P.PU_FIRE_UP: 1}, 999)
	h.eq(int(rz0["graine"]), Rng.suivant(999),
		"powerups: densite ZERO court-circuite le tirage (graine avancee d'UN seul pas)")
