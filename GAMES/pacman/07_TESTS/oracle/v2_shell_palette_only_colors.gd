# v2_shell_palette_only_colors.gd — ligne shell.palette_only_colors, capacite F110.
# Aucun ecran produit ne prend une couleur ailleurs que dans le descripteur de palette :
# le comptage des litteraux de couleur situes hors du descripteur vaut exactement 0.
extends RefCounted

const App = preload("res://05_SYSTEMS/app_state/app_state.gd")
const ShellView = preload("res://06_RUNTIME/adapters/shell_view/shell_view.gd")
const Palette = preload("res://06_RUNTIME/adapters/palette/palette.gd")
const Purity = preload("res://06_RUNTIME/adapters/proof_harness/harness_purity_counts.gd")


func run(h) -> void:
	h.eq(Purity.couleur_hors_palette().size(), 0, "shell.couleurs: 0 litteral de couleur hors du descripteur")
	h.eq(Purity.couleur_dans_palette().size(), 1, "shell.couleurs: le descripteur en porte — controle positif")

	# CHAQUE ECRAN produit ne cite que des couleurs du descripteur.
	var contexte: Dictionary = {"selection": 0, "reglages": {}, "releve": {}}
	var hors: int = 0
	for e in ShellView.ecrans(contexte):
		hors += ShellView.couleurs_hors_palette(e)
	h.eq(hors, 0, "shell.couleurs: aucun ecran ne prend une couleur hors palette")
	h.eq(ShellView.ecrans(contexte).size(), 6, "shell.couleurs: six ecrans produits")

	# LE FICHIER des ecrans ne porte lui-meme aucun litteral.
	var f := FileAccess.open("res://06_RUNTIME/adapters/shell_view/shell_view.gd", FileAccess.READ)
	var texte: String = Purity.code_seul(f.get_as_text() if f != null else "")
	h.eq(texte.contains("Color("), false, "shell.couleurs: aucun litteral dans le fichier des ecrans")
	h.eq(texte.contains("Palette."), true, "shell.couleurs: il lit le descripteur")

	# CHANGER L'IDENTITE : un seul module a ouvrir, et 0 fichier de logique.
	h.eq(Purity.couleur_dans_logique().size(), 0, "shell.couleurs: 0 fichier de logique porte une couleur")
	h.eq(Palette.couleurs().has(ShellView.ecran(App.Etat.TITRE, contexte)["couleur_fond"]), true,
		"shell.couleurs: le fond de l'ecran titre vient du descripteur")
