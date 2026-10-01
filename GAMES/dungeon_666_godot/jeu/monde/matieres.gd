extends RefCounted
## Les matières du Monde : textures de bruit FABRIQUÉES en mémoire au premier besoin (aucune image
## importée). Elles se répètent sans couture ; le sol (sol.gdshader) les lit pour son grain, ses
## taches et ses fissures.
##   const Matieres = preload("res://jeu/monde/matieres.gd")   puis   Matieres.bruit()

const TAILLE_BRUIT := 256
const TAILLE_CRAQUELURE := 512
const COUTURE := 0.12 # part de la texture fondue pour la répétition

static var _bruit: Texture2D = null
static var _craquelure: Texture2D = null

## Bruit doux à plusieurs octaves (grain de la pierre, grandes taches), valeurs 0..1.
static func bruit() -> Texture2D:
	if _bruit == null:
		var n := FastNoiseLite.new()
		n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		n.seed = 666
		n.frequency = 0.018
		n.fractal_type = FastNoiseLite.FRACTAL_FBM
		n.fractal_octaves = 4
		n.fractal_gain = 0.55
		_bruit = _texture(n, TAILLE_BRUIT)
	return _bruit

## Réseau de cellules : la valeur tombe à 0 sur les arêtes entre cellules, ce qui trace des
## fissures (lave, craquelures sèches, givre).
static func craquelure() -> Texture2D:
	if _craquelure == null:
		var n := FastNoiseLite.new()
		n.noise_type = FastNoiseLite.TYPE_CELLULAR
		n.seed = 13
		n.frequency = 0.016
		n.fractal_type = FastNoiseLite.FRACTAL_NONE
		n.cellular_distance_function = FastNoiseLite.DISTANCE_EUCLIDEAN
		n.cellular_return_type = FastNoiseLite.RETURN_DISTANCE2_SUB
		n.cellular_jitter = 0.78
		n.domain_warp_enabled = true
		n.domain_warp_amplitude = 10.0
		n.domain_warp_frequency = 0.03
		_craquelure = _texture(n, TAILLE_CRAQUELURE)
	return _craquelure

static func _texture(n: FastNoiseLite, taille: int) -> Texture2D:
	var image := n.get_seamless_image(taille, taille, false, false, COUTURE, true)
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)
