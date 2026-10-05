extends Node
## Banc de l'ÉCRAN DE L'ARBRE : le VRAI programme principal (jeu/principal.gd), ouvert sur le
## Grimoire de la Ville, avec un profil d'essai amené dans l'état voulu. Pour se capturer :
##   D666_CLASSE=bourreau D666_ARBRE=moitie D666_NOEUD=chaine <godot> --position -3000,-3000 \
##     --resolution 1280x720 --path . --script res://outils/capture.gd -- res://jeu/ville/banc_arbre.tscn <sortie.png> 60
##   D666_CLASSE  : revenant (défaut) | bourreau | chasseresse
##   D666_ARBRE   : vide (niveau 1, aucun point) | points (défaut : des points à dépenser) | choix (les
##                  deux améliorations de la première compétence offertes) | moitie (quinze points
##                  dépensés) | plein (tout ce qu'un héros peut acheter)
##   D666_NOEUD   : le nœud à choisir (identifiant de data/arbres.json) ; « emplacement:2 » : le
##                  deuxième emplacement de l'arc ; absent : celui que l'écran choisit seul
##   D666_GESTE   : choisir (premier appui sur la première amélioration offerte : la confirmation) |
##                  rendre (premier appui sur « Tout rendre » : la confirmation) | focus (le focus du
##                  clavier est posé sur le nœud choisi)
##   D666_FACTICE : nombre de nœuds par étage d'un arbre FACTICE (jeu/ville/arbre_factice.gd)
##   D666_ONGLET  : un autre onglet que le Grimoire (pour voir sa pastille et la consigne de la Ville)
## Le banc écrit dans son propre dossier d'essai, jamais dans le vrai profil.

const Principal = preload("res://jeu/principal.gd")
const Profil = preload("res://jeu/profil.gd")
const ProfilEssai = preload("res://jeu/ville/profil_essai.gd")
const Factice = preload("res://jeu/ville/arbre_factice.gd")
const DONNEES := "user://essais_ville/banc_arbre"
const NIVEAUX := {"vide": 1.0, "moitie": 16.0} # niveau de classe posé pour D666_ARBRE
const POSE := 12 # images avant de poser le geste (la mise en page est faite)

var app: Node
var partie: Node
var _images := 0

func _ready() -> void:
	OS.set_environment("D666_DONNEES", DONNEES)
	ProfilEssai.effacer()
	var tuning: Dictionary = D6Data.create_tuning()
	var profil: Dictionary = ProfilEssai.riche(tuning)
	D6Profile.select_class(profil, tuning, _env("D666_CLASSE", "revenant"))
	garnir(profil, tuning, _env("D666_ARBRE", "points"))
	ProfilEssai.ecrire(profil)
	var reglages: Dictionary = Profil.REGLAGES_DEFAUT.duplicate(true)
	reglages.sound = false
	reglages.haptics = false
	Profil.enregistrer_reglages(reglages)
	app = Principal.new()
	app.name = "Principal"
	add_child(app)
	partie = app.partie
	app.ouvrir_ville()
	app.vues.ville.ouvrir_onglet(_env("D666_ONGLET", "grimoire"))

func _env(nom: String, defaut: String = "") -> String:
	var v := OS.get_environment(nom)
	return v if v != "" else defaut

## L'arbre de la classe portée, dans l'état demandé (un banc a le droit de fabriquer son profil).
static func garnir(profil: Dictionary, tuning: Dictionary, etat: String) -> void:
	var classe: String = profil.loadout.classId
	var st: Dictionary = profil.tree[classe]
	var c: Dictionary = tuning.classes[classe]
	st.level = NIVEAUX.get(etat, ProfilEssai.NIVEAU_RICHE)
	if etat == "plein":
		st.level = tuning.tree.maxLevel
		st.guardians = tuning.boss.keys()
	if etat == "choix":
		for i in int(tuning.tree.choiceRank) - 1:
			D6Profile.tree_buy(profil, tuning, classe, c.skills[0])
	if etat != "moitie" and etat != "plein":
		return
	var achete := true
	while achete:
		achete = false
		for n in tuning.tree.classes[classe].nodes:
			achete = D6Js.truthy(D6Profile.tree_buy(profil, tuning, classe, n.id).ok) or achete
	for n in tuning.tree.classes[classe].nodes:
		if n.has("choices") and n.tier < 2.0:
			D6Profile.tree_choose(profil, tuning, classe, n.id, n.choices[0].id)
	D6Profile.select_slot(profil, tuning, 2.0, c.skills[1])

func _process(_delta: float) -> void:
	_images += 1
	if _images != POSE or _env("D666_ONGLET", "grimoire") != "grimoire":
		return
	var page: Node = app.vues.ville.page("grimoire")
	var factice := int(_env("D666_FACTICE", "0"))
	if factice > 0:
		var classe: String = app.profil.loadout.classId
		page.vue_forcee = Factice.gonfler(D6Profile.tree_view(app.profil, app.contenu, classe), factice)
		app.profil_change.emit()
	var noeud := _env("D666_NOEUD")
	if noeud.begins_with("emplacement:"):
		page.get_node("%Arc").bouton(int(noeud.trim_prefix("emplacement:")) - 1).pressed.emit()
	elif noeud != "":
		page.selectionner(noeud)
	_poser_le_geste.call_deferred(page)

func _poser_le_geste(page: Node) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	match _env("D666_GESTE"):
		"choisir":
			for b: Button in page.panneau().find_children("*", "Button", true, false):
				if String(b.get_meta("action", "")).begins_with("choix:") and not b.disabled:
					b.pressed.emit()
					break
		"rendre":
			page.get_node("%Rendre").pressed.emit()
		"focus":
			page.arbre().bouton(page.selection()).grab_focus()
