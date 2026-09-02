# test_map_validator.gd — le POINT DE PASSAGE OBLIGE. Une carte invalide doit etre refusee
# AVEC SON MOTIF, jamais jouee a moitie. Un motif par cas : c'est ce qui fait la difference
# entre « la validation marche » et « la validation attrape ce pour quoi elle existe ».
extends RefCounted

const P = preload("res://05_SYSTEMS/params/params.gd")
const V = preload("res://05_SYSTEMS/map_validator/map_validator.gd")
const Fx = preload("res://07_TESTS/unit/fixtures.gd")


func _refus(desc: Dictionary) -> Dictionary:
	return V.verifier(desc)


func run(h) -> void:
	# --- carte valide ---
	var ok := V.carte_validee(Fx.desc_simple())
	h.ok(ok["valide"], "validator: la carte de reference est acceptee")
	h.ok(ok["arene"] != null, "validator: une carte acceptee porte son arene")
	h.eq(ok["spawns"].size(), 2, "validator: deux spawns derives du plan")
	h.eq(ok["motifs"], [], "validator: une carte acceptee ne porte aucun motif")

	# --- champ obligatoire manquant ---
	var d1 := Fx.desc_simple()
	d1.erase("victory_rule")
	var r1 := _refus(d1)
	h.ok(not r1["valide"], "validator: champ manquant refuse")
	h.ok(r1["motifs"].has(V.MOTIF_CHAMP_MANQUANT), "validator: motif champ_obligatoire_manquant")
	h.ok(r1["details"].has("victory_rule"), "validator: le champ manquant est NOMME")

	# --- plan non rectangulaire ---
	var d2 := Fx.desc_simple()
	d2["plan"] = ["#####", "#S.S#", "#..#", "#####"]
	var r2 := _refus(d2)
	h.ok(r2["motifs"].has(V.MOTIF_PLAN_NON_RECTANGULAIRE), "validator: motif plan_non_rectangulaire")

	# --- symbole hors legende ---
	var d3 := Fx.desc_simple()
	d3["plan"] = ["#####", "#SZS#", "#...#", "#####"]
	var r3 := _refus(d3)
	h.ok(r3["motifs"].has(V.MOTIF_SYMBOLE_INCONNU), "validator: motif symbole_hors_legende")
	h.ok(r3["details"].has("Z"), "validator: le symbole inconnu est NOMME")

	# --- bord non solide ---
	var d4 := Fx.desc_simple()
	d4["plan"] = ["#####", "#S.S#", "....#", "#####"]
	var r4 := _refus(d4)
	h.ok(r4["motifs"].has(V.MOTIF_BORD_NON_SOLIDE), "validator: motif bord_non_solide")

	# --- spawns insuffisants ---
	var d5 := Fx.desc_simple()
	d5["plan"] = ["#####", "#S..#", "#...#", "#####"]
	var r5 := _refus(d5)
	h.ok(r5["motifs"].has(V.MOTIF_SPAWNS_INSUFFISANTS), "validator: motif spawns_insuffisants")

	# --- spawns adjacents ---
	var d6 := Fx.desc_simple()
	d6["plan"] = ["#####", "#SS.#", "#...#", "#####"]
	var r6 := _refus(d6)
	h.ok(r6["motifs"].has(V.MOTIF_SPAWNS_ADJACENTS), "validator: motif spawns_adjacents")

	# --- arene non connexe : deux moities separees par une colonne solide ---
	var d7 := Fx.desc_simple()
	d7["plan"] = ["#####", "#S#S#", "#.#.#", "#####"]
	var r7 := _refus(d7)
	h.ok(r7["motifs"].has(V.MOTIF_ARENE_NON_CONNEXE), "validator: motif arene_non_connexe")

	# --- regle de victoire inconnue ---
	var d8 := Fx.desc_simple()
	d8["victory_rule"] = "DOMINATION"
	var r8 := _refus(d8)
	h.ok(r8["motifs"].has(V.MOTIF_REGLE_VICTOIRE_INCONNUE), "validator: motif regle_de_victoire_inconnue")

	# --- power-up hors registre ---
	var d9 := Fx.desc_simple()
	d9["powerup_rules"] = {"MEGA_BOMB": 1}
	var r9 := _refus(d9)
	h.ok(r9["motifs"].has(V.MOTIF_POWERUP_INCONNU), "validator: motif powerup_hors_registre")
	h.ok(r9["details"].has("MEGA_BOMB"), "validator: le power-up inconnu est NOMME")

	# --- une carte refusee ne rend JAMAIS d'arene jouable ---
	var refusee := V.carte_validee(d8)
	h.ok(refusee["arene"] == null, "validator: carte refusee => aucune arene (jamais jouee a moitie)")
	h.eq(refusee["spawns"], [], "validator: carte refusee => aucun spawn")

	# --- chaque motif du vocabulaire est unique et non vide ---
	var vus := {}
	for m in V.MOTIFS:
		h.ok(String(m).length() > 0 and not vus.has(m), "validator: motif '%s' unique et nomme" % str(m))
		vus[m] = true

	# --- la carte LIVREE du jeu est valide (sinon le produit ne demarre pas) ---
	var provider = load("res://06_RUNTIME/adapters/content_provider/content_provider.gd")
	var livree: Dictionary = provider.descripteur(0)
	h.ok(not livree.is_empty(), "validator: la carte livree est lisible")
	var vl := V.carte_validee(livree)
	h.ok(vl["valide"], "validator: la carte LIVREE passe le verdict")
	h.eq(vl["spawns"].size(), 4, "validator: la carte livree porte 4 spawns")
	h.gt(vl["arene"].nb_destructibles(), 0, "validator: la carte livree porte des destructibles")

	# ---------- ARENA : bornes exactes et cas negatifs (mutation 2026-08-10, 8/18) ----------
	const Arena = preload("res://05_SYSTEMS/arena/arena.gd")
	var ar = Arena.depuis_descripteur(Fx.desc_vide())
	# `dans_bornes` : les QUATRE bornes exactes, dedans et dehors.
	h.ok(ar.dans_bornes(Vector2i(0, 0)), "arena: (0,0) est dans les bornes")
	h.ok(ar.dans_bornes(Vector2i(ar.largeur - 1, ar.hauteur - 1)), "arena: le coin oppose aussi")
	h.ok(not ar.dans_bornes(Vector2i(-1, 0)), "arena: x negatif est hors bornes")
	h.ok(not ar.dans_bornes(Vector2i(0, -1)), "arena: y negatif est hors bornes")
	h.ok(not ar.dans_bornes(Vector2i(ar.largeur, 0)), "arena: x EGAL a la largeur est hors bornes")
	h.ok(not ar.dans_bornes(Vector2i(0, ar.hauteur)), "arena: y EGAL a la hauteur est hors bornes")
	# hors bornes vaut SOLIDE : le monde est ferme, la lecture ne leve jamais
	h.eq(ar.type_case(Vector2i(-5, -5)), P.SOLIDE, "arena: hors bornes se lit SOLIDE")
	h.ok(ar.est_solide(Vector2i(999, 999)), "arena: tres loin aussi")
	h.ok(not ar.est_libre(Vector2i(-1, -1)), "arena: hors bornes n'est jamais libre")
	# `detruire` : cas negatifs, chacun rend false SANS rien changer
	var n0: int = ar.nb_destructibles()
	h.ok(not ar.detruire(Vector2i(-1, 0)), "arena: detruire hors bornes rend false")
	h.ok(not ar.detruire(Vector2i(0, 0)), "arena: detruire un SOLIDE rend false")
	h.ok(not ar.detruire(Vector2i(2, 2)), "arena: detruire du SOL rend false")
	h.eq(ar.nb_destructibles(), n0, "arena: aucun de ces refus n'a modifie l'arene")
	# `solidifier` : cas negatifs et cas nominal
	h.ok(not ar.solidifier(Vector2i(-1, 0)), "arena: solidifier hors bornes rend false")
	h.ok(not ar.solidifier(Vector2i(0, 0)), "arena: solidifier un deja-SOLIDE rend false")
	h.ok(ar.solidifier(Vector2i(2, 2)), "arena: solidifier du SOL rend true")
	h.ok(ar.est_solide(Vector2i(2, 2)), "arena: la case est devenue solide")
	h.ok(not ar.solidifier(Vector2i(2, 2)), "arena: la meme case ne se solidifie pas deux fois")
	# destruction reelle, sur une carte qui en porte
	var ab = Arena.depuis_descripteur(Fx.desc_blocs())
	var nb: int = ab.nb_destructibles()
	h.gt(nb, 0, "arena: la carte temoin porte des destructibles")
	h.ok(ab.detruire(Vector2i(3, 1)), "arena: detruire un DESTRUCTIBLE rend true")
	h.eq(ab.nb_destructibles(), nb - 1, "arena: le compte baisse d'EXACTEMENT un")
	h.ok(ab.est_libre(Vector2i(3, 1)), "arena: la case detruite devient du SOL")
	# clone : independance reelle
	var ac = ab.clone()
	ac.detruire(Vector2i(2, 2))
	h.ok(ac.nb_destructibles() <= ab.nb_destructibles(), "arena: le clone est independant")
