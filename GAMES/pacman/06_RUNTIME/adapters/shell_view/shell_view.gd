# shell_view.gd — ECRANS DE LA COQUILLE PRODUITE (lignes shell.palette_only_colors,
# shell.screen_captures).
#
# Un ecran est une DONNEE : un titre, des lignes, un couple de couleurs LUES dans le
# descripteur de palette unique. Aucun ecran ne prend une couleur ailleurs — le comptage
# des litteraux de couleur situes hors du descripteur vaut exactement 0.
#
# CONTRAINTE DE PLATEFORME CONNUE ET NON CONTOURNEE : une capture Godot exige une
# FENETRE GPU REELLE (`--headless` rend une texture nulle, fait mesure au studio le
# 2026-07-22). Sans elle, le volet capture vaut NOT_MEASURED motive, jamais un vert.
extends RefCounted

const App = preload("res://05_SYSTEMS/app_state/app_state.gd")
const Menu = preload("res://05_SYSTEMS/menu_model/menu_model.gd")
const Reglages = preload("res://05_SYSTEMS/settings/settings.gd")
const Palette = preload("res://06_RUNTIME/adapters/palette/palette.gd")
const Controles = preload("res://06_RUNTIME/adapters/shell_view/controls_screen.gd")
const Options = preload("res://06_RUNTIME/adapters/shell_view/options_screen.gd")
const EndScreen = preload("res://06_RUNTIME/adapters/presentation/end_screen.gd")
const GhostGuide = preload("res://06_RUNTIME/adapters/presentation/ghost_guide.gd")

const TITRE_JEU := "PAC-MAN"
const ECRANS: Array = [
	App.Etat.TITRE, App.Etat.PARTIE, App.Etat.PAUSE,
	App.Etat.CONTROLES, App.Etat.OPTIONS, App.Etat.FIN,
]

const RAISON_HEADLESS := "fenetre GPU absente : --headless rend une texture nulle"


static func _lignes_menu(libelles: Array, selection: int) -> Array:
	var sortie: Array = []
	for i in range(libelles.size()):
		var marque: String = "> " if i == selection else "  "
		sortie.append(marque + String(libelles[i]))
	return sortie


# ECRAN produit pour un etat d'application. `contexte` porte la selection courante, les
# reglages et le dernier releve observable — il est REMIS, jamais cherche.
static func ecran(etat: int, contexte: Dictionary) -> Dictionary:
	var selection: int = int(contexte.get("selection", 0))
	var reglages: Dictionary = Reglages.normaliser(contexte.get("reglages", {}))
	var releve: Dictionary = contexte.get("releve", {})
	var lignes: Array = []
	var titre: String = ""
	if etat == App.Etat.TITRE:
		titre = TITRE_JEU
		lignes = _lignes_menu(Menu.LIBELLES_TITRE, selection)
	elif etat == App.Etat.PARTIE:
		titre = "PARTIE"
		lignes = [String(releve.get("statut_nom", "")), "SCORE " + str(releve.get("score", 0))]
	elif etat == App.Etat.PAUSE:
		titre = "PAUSE"
		lignes = _lignes_menu(Menu.LIBELLES_PAUSE, selection)
	elif etat == App.Etat.CONTROLES:
		titre = Controles.TITRE
		lignes = Controles.lignes()
		# V4, cause racine P3 : le comportement des quatre fantomes est TRANSMIS ici,
		# sur le seul ecran de consultation atteignable depuis le titre ET depuis la
		# pause. Les lignes viennent du guide, source unique derivee du ciblage —
		# `Controles.lignes()` n'est pas touche, il continue de valoir une ligne par
		# intention.
		lignes.append("")
		lignes.append(GhostGuide.TITRE)
		for l in GhostGuide.lignes():
			lignes.append(l)
	elif etat == App.Etat.OPTIONS:
		titre = Options.TITRE
		lignes = Options.lignes(reglages, selection)
	elif etat == App.Etat.FIN:
		# V3, cause racine P5 : l'ecran final porte desormais les SUITES OFFERTES, pas
		# seulement un constat. Les lignes de choix viennent de l'ecran de fin, source
		# unique — les recopier ici ferait deux listes qui pourraient diverger.
		titre = "FIN DE PARTIE"
		lignes = ["SCORE FINAL " + str(releve.get("score", 0)), String(releve.get("statut_nom", ""))]
		for l in EndScreen.lignes(selection):
			lignes.append(l)
	return {
		"etat": etat,
		"titre": titre,
		"lignes": lignes,
		"couleur_fond": Palette.FOND_ECRAN,
		"couleur_texte": Palette.TEXTE,
		"couleur_selection": Palette.SELECTION,
	}


# Signature comparable d'un ecran : titre + lignes. Deux ecrans identiques par leur
# signature seraient indistinguables a l'ecran.
static func signature(e: Dictionary) -> String:
	return String(e["titre"]) + "|" + "\n".join(e["lignes"])


static func ecrans(contexte: Dictionary) -> Array:
	var sortie: Array = []
	for etat in ECRANS:
		sortie.append(ecran(etat, contexte))
	return sortie


# Nombre de PAIRES D'ECRANS IDENTIQUES. La valeur attendue vaut exactement 0.
static func paires_identiques(contexte: Dictionary) -> int:
	var liste: Array = ecrans(contexte)
	var n: int = 0
	for i in range(liste.size()):
		for j in range(i + 1, liste.size()):
			if signature(liste[i]) == signature(liste[j]):
				n += 1
	return n


# Couleurs utilisees par un ecran — toutes lues dans la palette : le nombre de couleurs
# ABSENTES du descripteur vaut exactement 0.
static func couleurs_hors_palette(e: Dictionary) -> int:
	var connues: Array = Palette.couleurs()
	var n: int = 0
	for cle in ["couleur_fond", "couleur_texte", "couleur_selection"]:
		if not connues.has(e[cle]):
			n += 1
	return n


# CAPTURE d'un ecran : possible UNIQUEMENT en fenetre GPU reelle. En headless, le
# constat est NOT_MEASURED MOTIVE — jamais un vert, jamais un fichier vide.
static func capture(etat: int, viewport) -> Dictionary:
	if viewport == null:
		return {"mesure": false, "etat": etat, "raison": RAISON_HEADLESS}
	var texture = viewport.get_texture()
	if texture == null:
		return {"mesure": false, "etat": etat, "raison": RAISON_HEADLESS}
	var image = texture.get_image()
	if image == null or image.is_empty():
		return {"mesure": false, "etat": etat, "raison": RAISON_HEADLESS}
	return {"mesure": true, "etat": etat, "raison": "", "taille": image.get_size()}


# Captures des SIX ecrans. Rend le constat par ecran, jamais un booleen agrege.
static func captures(viewport) -> Array:
	var sortie: Array = []
	for etat in ECRANS:
		sortie.append(capture(etat, viewport))
	return sortie
