extends "res://jeu/monde/calque.gd"
## Le sol de la salle : UN rectangle, peint par sol.gdshader (dalles, joints, usure, craquelures,
## fissures de lave qui pulsent, ombre au pied des murs, lanterne du héros). La pierre et
## l'appareil changent avec le Cercle (ambiance.gd). Le sol reste sombre : c'est le fond sur
## lequel le danger doit se lire. Murs et piliers sont dessinés par murs.gd.

const Matieres = preload("res://jeu/monde/matieres.gd")
const Ombrage = preload("res://jeu/monde/sol.gdshader")
const NOMBRE_D_OR := 0.618034

var _salle = null
var _matiere: ShaderMaterial

func _ready() -> void:
	_matiere = ShaderMaterial.new()
	_matiere.shader = Ombrage
	_matiere.set_shader_parameter("bruit", Matieres.bruit())
	_matiere.set_shader_parameter("craquelure", Matieres.craquelure())
	material = _matiere

func _process(_delta: float) -> void:
	var g = etat()
	if g == null:
		return
	if not is_same(g.room, _salle):
		_salle = g.room
		_regler(g)
		queue_redraw()
	_matiere.set_shader_parameter("temps", temps())
	_matiere.set_shader_parameter("heros", partie.position_dessin(g.player, true))

## Pose la matière du Cercle et la graine de la salle (deux salles n'ont pas les mêmes fissures).
func _regler(g: Dictionary) -> void:
	var a: Dictionary = monde.ambiance()
	var etage := float(g.run.floor)
	var graine := Vector2(fposmod(etage * NOMBRE_D_OR, 1.0), fposmod(etage * 0.414214 + float(g.get("seed", 1.0)) * 0.137, 1.0))
	for cle in ["dalle", "decale", "tourne", "lave", "seches", "souffle"]:
		_matiere.set_shader_parameter(cle, a[cle])
	_matiere.set_shader_parameter("pierre_a", _vec(a.pierre))
	_matiere.set_shader_parameter("pierre_b", _vec(a.pierre_b))
	_matiere.set_shader_parameter("joint", _vec(a.joint))
	_matiere.set_shader_parameter("teinte", _vec(a.teinte))
	_matiere.set_shader_parameter("salle", Vector2(g.room.w, g.room.h))
	_matiere.set_shader_parameter("marge", g.room.pad)
	_matiere.set_shader_parameter("graine", graine)

func _vec(c: Color) -> Vector3:
	return Vector3(c.r, c.g, c.b)

func _draw() -> void:
	var g = etat()
	if g != null:
		draw_rect(dedans(g.room), Color.WHITE)
