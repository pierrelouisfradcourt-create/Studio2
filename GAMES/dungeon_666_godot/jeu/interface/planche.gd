extends SceneTree
## Planche de comparaison : plusieurs captures empilées, chacune sous son titre, enregistrées en
## une image (AVANT / APRÈS d'un lot). Outil d'essai, jamais appelé par le jeu.
##   <godot> --position -3000,-3000 --resolution 1600x1560 --path . --script res://jeu/interface/planche.gd \
##     -- <sortie.png> "<titre 1>" <image 1.png> "<titre 2>" <image 2.png> …
## Les chemins sont relatifs au projet. SANS --headless (il faut un vrai rendu).

const ThemeJeu = preload("res://jeu/theme/theme.gd")
const Couleurs = preload("res://jeu/theme/couleurs.gd")
const ATTENTE := 6 # images avant d'enregistrer (la mise en page est posée)
const MARGE := 10

var _sortie := ""
var _vues := 0

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 3 or args.size() % 2 == 0:
		print("usage : planche.gd -- <sortie.png> \"<titre>\" <image.png> …")
		quit(2)
		return
	_sortie = args[0]
	var fond := ColorRect.new()
	fond.color = Couleurs.UI["void"]
	fond.set_anchors_preset(Control.PRESET_FULL_RECT)
	fond.theme = ThemeJeu.theme()
	root.add_child(fond)
	var marge := MarginContainer.new()
	marge.set_anchors_preset(Control.PRESET_FULL_RECT)
	for cote in ["left", "top", "right", "bottom"]:
		marge.add_theme_constant_override("margin_" + cote, MARGE)
	fond.add_child(marge)
	var colonne := VBoxContainer.new()
	marge.add_child(colonne)
	for i in range(1, args.size(), 2):
		_ajouter(colonne, args[i], args[i + 1])
	process_frame.connect(_image)

func _ajouter(colonne: VBoxContainer, titre: String, chemin: String) -> void:
	var etiquette := Label.new()
	etiquette.text = titre
	etiquette.theme_type_variation = &"TitreSection"
	colonne.add_child(etiquette)
	var image := Image.load_from_file(ProjectSettings.globalize_path("res://" + chemin))
	var vue := TextureRect.new()
	vue.texture = ImageTexture.create_from_image(image) if image != null else null
	vue.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	vue.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	vue.size_flags_vertical = Control.SIZE_EXPAND_FILL
	colonne.add_child(vue)

func _image() -> void:
	_vues += 1
	if _vues < ATTENTE:
		return
	var image := root.get_texture().get_image()
	image.save_png(_sortie)
	print("planche : ", _sortie, " (", image.get_width(), "x", image.get_height(), ")")
	quit(0)
