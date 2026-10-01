extends Label
## Un grand titre d'apparat avec du RELIEF (logo, « VOUS ÊTES MORT », « LE TRÔNE EST VIDE ») : le
## liseré et l'ombre viennent du thème (variations Logo, TitreMort) ; ce script ajoute la lumière
## — un dégradé vertical dans le corps des lettres (jeu/theme/relief.gdshader), recalé quand la
## taille du titre change. Aucune image, aucune couleur de texte écrite ici.

const Relief = preload("res://jeu/theme/relief.gdshader")
const DEBUT := 0.3 # part de la hauteur où le dégradé commence
const FIN := 0.88

## Ce que devient la couleur du texte au pied des lettres (multipliée) : chaud par défaut.
@export var teinte_bas := Color(1.0, 0.74, 0.52)

func _ready() -> void:
	var matiere := ShaderMaterial.new()
	matiere.shader = Relief
	matiere.set_shader_parameter("teinte_bas", teinte_bas)
	material = matiere
	resized.connect(_caler)
	_caler()

func _caler() -> void:
	(material as ShaderMaterial).set_shader_parameter("haut", size.y * DEBUT)
	(material as ShaderMaterial).set_shader_parameter("bas", size.y * FIN)
