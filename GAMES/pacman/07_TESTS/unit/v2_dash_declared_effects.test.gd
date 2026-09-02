# v2_dash_declared_effects.test.gd — ligne dash.declared_effects, capacite F86.
# La DECLARATION est une donnee confrontee a la mesure, jamais une note : chaque grandeur
# declaree modifiee presente deux valeurs distinctes, chaque grandeur declaree inchangee
# deux valeurs egales.
extends RefCounted

const Dash = preload("res://05_SYSTEMS/dash/dash.gd")
const Mesure = preload("res://06_RUNTIME/adapters/proof_harness/harness_dash_measurement.gd")
const ContentV2 = preload("res://06_RUNTIME/adapters/content_provider/content_provider.gd")
const MazeClass = preload("res://05_SYSTEMS/maze/maze.gd")
var Maze = MazeClass.depuis_descripteur(ContentV2.descripteur(0))


func run(h) -> void:
	# LA DECLARATION, grandeur par grandeur.
	h.eq(Dash.GRANDEURS.size(), 4, "dash.declare: quatre grandeurs declarees")
	h.eq(Dash.EFFETS_DECLARES["vitesse_joueur"], Dash.MODIFIE, "dash.declare: vitesse modifiee")
	h.eq(Dash.EFFETS_DECLARES["delai_avant_dash"], Dash.MODIFIE, "dash.declare: delai modifie")
	h.eq(Dash.EFFETS_DECLARES["comportement_murs"], Dash.INCHANGE, "dash.declare: murs inchanges")
	h.eq(Dash.EFFETS_DECLARES["comportement_fantomes"], Dash.INCHANGE, "dash.declare: fantomes inchanges")
	h.eq(Dash.grandeurs_modifiees().size(), 2, "dash.declare: deux grandeurs modifiees")
	h.eq(Dash.grandeurs_inchangees().size(), 2, "dash.declare: deux grandeurs inchangees")

	# LA MESURE, confrontee a la declaration.
	var m: Dictionary = Mesure.mesurer(Maze)
	h.eq(m["grandeurs_sans_releve"], 0, "dash.declare: 0 grandeur sans releve")
	h.eq(m["ecarts_a_la_declaration"].size(), 0, "dash.declare: 0 ecart a la declaration")

	# Le detail, grandeur par grandeur : DISTINCTES la ou c'est declare, EGALES ailleurs.
	var r: Dictionary = m["releves"]
	h.ok(r["vitesse_joueur"]["avec"] != r["vitesse_joueur"]["sans"], "dash.declare: vitesse distincte")
	h.ok(r["delai_avant_dash"]["avec"] != r["delai_avant_dash"]["sans"], "dash.declare: delai distinct")
	h.eq(r["comportement_murs"]["avec"], r["comportement_murs"]["sans"], "dash.declare: murs egaux")
	h.eq(r["comportement_fantomes"]["avec"], r["comportement_fantomes"]["sans"], "dash.declare: fantomes egaux")

	# La raison des grandeurs inchangees est STRUCTURELLE : le module ne decide ni butee
	# ni contact. La mesure CONFIRME la declaration, elle ne la fonde pas.
	var f := FileAccess.open("res://05_SYSTEMS/dash/dash.gd", FileAccess.READ)
	var texte: String = f.get_as_text() if f != null else ""
	h.eq(texte.contains("praticable"), false, "dash.declare: le module ne decide aucune butee")
	h.eq(texte.contains("Contacts"), false, "dash.declare: le module ne decide aucun contact")
	# --- GATE MUTATION : le CONTENU des deux listes, pas seulement leur taille -------
	# Deux listes de meme taille ne prouvent rien : c'est le partage MODIFIE/INCHANGE
	# qui est declare, et c'est lui qu'il faut asserter.
	h.eq(Dash.grandeurs_modifiees(), ["vitesse_joueur", "delai_avant_dash"],
		"dash.declare: les grandeurs modifiees sont nommement celles-la")
	h.eq(Dash.grandeurs_inchangees(), ["comportement_murs", "comportement_fantomes"],
		"dash.declare: et les inchangees nommement celles-la")
	var croisement: int = 0
	for g in Dash.grandeurs_modifiees():
		if Dash.grandeurs_inchangees().has(g):
			croisement += 1
	h.eq(croisement, 0, "dash.declare: les deux listes sont disjointes")
	h.eq(Dash.grandeurs_modifiees().size() + Dash.grandeurs_inchangees().size(),
		Dash.GRANDEURS.size(), "dash.declare: ensemble, elles couvrent les quatre grandeurs")
	h.eq(Dash.grandeurs_modifiees().has("comportement_murs"), false,
		"dash.declare: le comportement face aux murs n'est pas declare modifie")
	h.eq(Dash.grandeurs_inchangees().has("vitesse_joueur"), false,
		"dash.declare: la vitesse n'est pas declaree inchangee")
