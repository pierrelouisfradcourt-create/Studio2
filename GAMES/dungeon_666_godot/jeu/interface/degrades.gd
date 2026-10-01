extends RefCounted
## Les deux dégradés du HUD, fabriqués en mémoire à partir de la palette (aucune image importée) :
## la bande sombre derrière le haut de l'écran (le texte reste lisible sur tout fond) et la
## vignette rouge de danger.

const Couleurs = preload("res://jeu/theme/couleurs.gd")

static func bande() -> Texture2D:
	var encre: Color = Couleurs.UI["void"]
	var g := Gradient.new()
	g.colors = PackedColorArray([Color(encre, 0.6), Color(encre, 0.0)])
	g.offsets = PackedFloat32Array([0.0, 1.0])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.width = 4
	t.height = 64
	t.fill_from = Vector2(0.0, 0.0)
	t.fill_to = Vector2(0.0, 1.0)
	return t

static func vignette() -> Texture2D:
	var rouge: Color = Color(Couleurs.PAL.danger).darkened(0.2)
	var g := Gradient.new()
	g.colors = PackedColorArray([Color(rouge, 0.0), Color(rouge, 1.0)])
	g.offsets = PackedFloat32Array([0.72, 1.0])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.width = 128
	t.height = 128
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.12, 0.5)
	return t
