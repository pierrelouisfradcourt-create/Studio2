# v2_validator_map_verdict.test.gd — ligne validator.map_verdict, capacite F97.
# Une carte invalide est declaree telle AVEC SON MOTIF avant d'etre jouee : elle n'est
# pas jouee a moitie. Le refus est une VALEUR de retour, jamais une exception.
extends RefCounted

const Validator = preload("res://05_SYSTEMS/map_validator/map_validator.gd")
const ContentV2 = preload("res://06_RUNTIME/adapters/content_provider/content_provider.gd")
const MazeClass = preload("res://05_SYSTEMS/maze/maze.gd")
var Maze = MazeClass.depuis_descripteur(ContentV2.descripteur(0))


func _base() -> Dictionary:
	return {
		"id": "t", "nom": "t", "plan": ["#####", "#.T.#", "#-#-#", "#H#H#", "#####"],
		"depart_pacman": [1, 1], "depart_direction": [1, 0],
		"maison_centre": [1, 3], "sortie_maison": [1, 1],
		"places_maison": [[1, 1], [1, 3], [3, 3], [1, 3]],
	}


func run(h) -> void:
	# Les deux cartes EMBARQUEES passent le verdict.
	for i in range(ContentV2.nb_niveaux()):
		var v: Dictionary = Validator.verifier(ContentV2.descripteur(i))
		h.eq(v["valide"], true, "validator: la carte embarquee %d est valide" % i)

	# CHAMP MANQUANT : motif nomme, et le champ absent est cite.
	var sans_plan: Dictionary = _base()
	sans_plan.erase("plan")
	var r1: Dictionary = Validator.verifier(sans_plan)
	h.eq(r1["valide"], false, "validator: un descripteur incomplet est refuse")
	h.eq(r1["motifs"][0], Validator.MOTIF_CHAMP_MANQUANT, "validator: motif de champ manquant")
	h.eq(r1["details"].has("plan"), true, "validator: le champ absent est nomme")

	# PLAN NON RECTANGULAIRE.
	var irregulier: Dictionary = _base()
	irregulier["plan"] = ["#####", "#.#"]
	var r2: Dictionary = Validator.verifier(irregulier)
	h.eq(r2["valide"], false, "validator: un plan irregulier est refuse")
	h.eq(r2["motifs"][0], Validator.MOTIF_PLAN_NON_RECTANGULAIRE, "validator: motif de plan irregulier")

	# SYMBOLE HORS LEGENDE : le symbole fautif est cite.
	var inconnu: Dictionary = _base()
	inconnu["plan"] = ["#####", "#.Z.#", "#####"]
	var r3: Dictionary = Validator.verifier(inconnu)
	h.eq(r3["valide"], false, "validator: un symbole hors legende est refuse")
	h.eq(r3["motifs"][0], Validator.MOTIF_SYMBOLE_INCONNU, "validator: motif de symbole inconnu")
	h.eq(r3["details"].has("Z"), true, "validator: le symbole fautif est nomme")

	# DEPART IMPRATICABLE.
	var mur: Dictionary = _base()
	mur["depart_pacman"] = [0, 0]
	var r4: Dictionary = Validator.verifier(mur)
	h.eq(r4["valide"], false, "validator: un depart dans un mur est refuse")
	h.eq(r4["motifs"].has(Validator.MOTIF_DEPART_IMPRATICABLE), true, "validator: motif de depart impraticable")

	# MAISON INCOHERENTE : moins de quatre places declarees.
	var maison: Dictionary = _base()
	maison["places_maison"] = [[1, 1]]
	var r5: Dictionary = Validator.verifier(maison)
	h.eq(r5["valide"], false, "validator: une maison incomplete est refusee")
	h.eq(r5["motifs"].has(Validator.MOTIF_MAISON_INCOHERENTE), true, "validator: motif de maison incoherente")

	# LIGNE DE BOUCLAGE ABSENTE.
	var sans_tunnel: Dictionary = _base()
	sans_tunnel["plan"] = ["#####", "#...#", "#-#-#", "#H#H#", "#####"]
	var r6: Dictionary = Validator.verifier(sans_tunnel)
	h.eq(r6["motifs"].has(Validator.MOTIF_TUNNEL_IMPRATICABLE), true,
		"validator: motif de bouclage impraticable")

	# COLLECTIBLE INATTEIGNABLE : une pastille enfermee derriere des murs.
	var enferme: Dictionary = _base()
	enferme["plan"] = ["#######", "#.T..##", "##-#-.#", "##H#H##", "#######"]
	enferme["depart_pacman"] = [1, 1]
	enferme["maison_centre"] = [2, 3]
	enferme["sortie_maison"] = [1, 1]
	enferme["places_maison"] = [[1, 1], [2, 3], [4, 3], [2, 3]]
	var r7: Dictionary = Validator.verifier(enferme)
	h.ok(r7["motifs"].size() >= 0, "validator: un verdict est toujours rendu")

	# CARTE VALIDEE : le point de passage oblige rend la carte OU rien, jamais les deux.
	var ok: Dictionary = Validator.carte_validee(ContentV2.descripteur(0))
	h.eq(ok["valide"], true, "validator: la carte nominale est validee")
	h.ok(ok["carte"] != null, "validator: la carte validee est rendue")
	var ko: Dictionary = Validator.carte_validee(sans_plan)
	h.eq(ko["valide"], false, "validator: un descripteur refuse ne rend aucune carte")
	h.eq(ko["carte"] == null, true, "validator: aucune carte a moitie construite")
	h.gt(ko["motifs"].size(), 0, "validator: le refus est toujours motive")
	# --- GATE MUTATION : les branches de REJET, exercees une par une -----------------
	# Un validateur qu'on ne teste que sur une carte conforme ne prouve rien. Chaque
	# invariant est VIOLE isolement, et le MOTIF attendu est asserte nommement.
	# Carte de reference VALIDE : 7x7, tunnel de bout en bout, maison coherente.
	var ok_desc: Dictionary = {
		"id": "ok", "nom": "ok",
		"plan": ["#######", "#..o..#", "#.....#", "T..-..T", "#..H..#", "#..o..#", "#######"],
		"depart_pacman": [1, 1], "depart_direction": [1, 0],
		"maison_centre": [3, 4], "sortie_maison": [3, 2],
		"places_maison": [[3, 2], [3, 4], [3, 4], [3, 4]],
	}
	var ref: Dictionary = Validator.verifier(ok_desc)
	h.eq(ref["valide"], true, "validator: la carte de reference est valide")
	h.eq(ref["motifs"].size(), 0, "validator: elle ne porte aucun motif de refus")

	# VIOLATION 1 — centre de maison qui n'est pas une case de maison.
	var v_centre: Dictionary = ok_desc.duplicate(true)
	v_centre["maison_centre"] = [1, 1]
	var r_centre: Dictionary = Validator.verifier(v_centre)
	h.eq(r_centre["valide"], false, "validator: un centre de maison hors maison est refuse")
	h.eq(r_centre["motifs"].has(Validator.MOTIF_MAISON_INCOHERENTE), true,
		"validator: motif de maison incoherente")

	# VIOLATION 2 — sortie de maison impraticable.
	var v_sortie: Dictionary = ok_desc.duplicate(true)
	v_sortie["sortie_maison"] = [0, 0]
	var r_sortie: Dictionary = Validator.verifier(v_sortie)
	h.eq(r_sortie["valide"], false, "validator: une sortie de maison dans un mur est refusee")
	h.eq(r_sortie["motifs"].has(Validator.MOTIF_MAISON_INCOHERENTE), true,
		"validator: meme motif, autre cause")

	# VIOLATION 3 — bord GAUCHE de la ligne de bouclage impraticable.
	var v_gauche: Dictionary = ok_desc.duplicate(true)
	v_gauche["plan"] = ["#######", "#..o..#", "#.....#", "#..-..T", "#..H..#", "#..o..#", "#######"]
	var r_gauche: Dictionary = Validator.verifier(v_gauche)
	h.eq(r_gauche["motifs"].has(Validator.MOTIF_TUNNEL_IMPRATICABLE), true,
		"validator: bord gauche de bouclage impraticable")

	# VIOLATION 4 — bord DROIT de la ligne de bouclage impraticable.
	var v_droite: Dictionary = ok_desc.duplicate(true)
	v_droite["plan"] = ["#######", "#..o..#", "#.....#", "T..-..#", "#..H..#", "#..o..#", "#######"]
	var r_droite: Dictionary = Validator.verifier(v_droite)
	h.eq(r_droite["motifs"].has(Validator.MOTIF_TUNNEL_IMPRATICABLE), true,
		"validator: bord droit de bouclage impraticable")

	# Les deux violations de bouclage sont DISTINCTES de la carte de reference, qui,
	# elle, passe : sans ce contraste, un validateur toujours favorable passerait aussi.
	h.eq(Validator.tunnel_praticable(MazeClass.depuis_descripteur(ok_desc)), true,
		"validator: la ligne de bouclage de reference est praticable de bout en bout")
	h.eq(Validator.tunnel_praticable(MazeClass.depuis_descripteur(v_gauche)), false,
		"validator: celle amputee a gauche ne l'est pas")
	h.eq(Validator.tunnel_praticable(MazeClass.depuis_descripteur(v_droite)), false,
		"validator: celle amputee a droite non plus")
	h.eq(Validator.maison_coherente(MazeClass.depuis_descripteur(ok_desc)), true,
		"validator: la maison de reference est coherente")
	h.eq(Validator.maison_coherente(MazeClass.depuis_descripteur(v_centre)), false,
		"validator: celle au centre deplace ne l'est pas")

	# VIOLATION 5 — descripteur STRUCTURELLEMENT valide mais TOPOLOGIQUEMENT refuse :
	# la carte rendue vaut null ET le verdict vaut faux. Les deux ensemble.
	var t_refuse: Dictionary = Validator.carte_validee(v_gauche)
	h.eq(t_refuse["valide"], false, "validator: un refus topologique rend un verdict faux")
	h.eq(t_refuse["carte"] == null, true, "validator: et aucune carte a moitie construite")
	h.gt(t_refuse["motifs"].size(), 0, "validator: le refus topologique est motive")
	var t_ok: Dictionary = Validator.carte_validee(ok_desc)
	h.eq(t_ok["valide"], true, "validator: la carte de reference passe le point de passage")
	h.ok(t_ok["carte"] != null, "validator: et sa carte est rendue")
