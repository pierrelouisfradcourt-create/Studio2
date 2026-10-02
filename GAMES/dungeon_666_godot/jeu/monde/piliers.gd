extends "res://jeu/monde/calque.gd"
## Les PILIERS, debout dans la salle : un nœud par pilier, posé au PIED de sa face avant et trié
## du fond vers l'avant (y_sort) AVEC les ennemis et le héros (voir entites.gd, groupe Debout).
## Ce qui se tient au nord d'un pilier passe derrière lui, ce qui est au sud le recouvre.
## Chaque pilier a un dessus clair remonté de HAUTEUR, une face avant plus sombre, une arête
## claire entre les deux ; son ombre portée reste au sol (murs.gd).
##
## Coût : rien ne bouge ici. Les nœuds sont refaits quand la salle change, chacun est dessiné UNE
## fois (primitives et traits d'équerre non lissés) ; ensuite le moteur rejoue ses commandes.

const Murs = preload("res://jeu/monde/murs.gd")

const HAUTEUR := 18.0 # u : hauteur apparente d'un pilier
const BISEAU := 3.0
const CADRE_GRAVE := 9.0 # u : retrait du cadre gravé sur le dessus
const CADRE_PART := 0.22 # … jamais plus que cette part du petit côté

var _salle = null

func _process(_delta: float) -> void:
	var g = etat()
	var salle = g.room if g != null else null
	if is_same(salle, _salle):
		return
	_salle = salle
	for n in get_children():
		n.queue_free()
	if salle != null:
		_dresser(salle.obstacles, monde.ambiance())

## Un nœud par pilier. Son y est celui du pied de la face avant : c'est son rang de profondeur.
func _dresser(obstacles: Array, a: Dictionary) -> void:
	for o in obstacles:
		var n := Node2D.new()
		n.position = Vector2(o.x0, o.y1)
		n.draw.connect(_peindre.bind(n, Vector2(o.x1 - o.x0, o.y1 - o.y0), a))
		add_child(n)

## Dessin d'un pilier dans SON repère (origine au pied gauche de la face avant) : face avant
## sombre au pied, dessus clair remonté d'autant, arête claire entre les deux, biseau (lumière en
## haut à gauche), cadre gravé, cerne.
func _peindre(n: Node2D, taille: Vector2, a: Dictionary) -> void:
	var dessus := Rect2(Vector2(0.0, -taille.y - HAUTEUR), taille)
	var face := Rect2(0.0, -HAUTEUR, taille.x, HAUTEUR)
	Trace.degrade_vertical(n, dessus, Ambiance.eclaire(a.mur, 1.42), Ambiance.eclaire(a.mur, 1.14))
	Trace.degrade_vertical(n, face, Ambiance.eclaire(a.mur, 0.62), Ambiance.eclaire(a.mur, 0.34))
	var cadre := dessus.grow(-minf(CADRE_GRAVE, minf(taille.x, taille.y) * CADRE_PART))
	Trace.cadre(n, cadre, Color(0, 0, 0, 0.22), 2.0)
	Trace.cadre(n, Rect2(cadre.position + Vector2(1.5, 1.5), cadre.size), Color(1.0, 0.9, 0.82, 0.07), 1.0)
	var haut := dessus.position
	var demi := BISEAU / 2.0
	n.draw_line(haut + Vector2(0.0, demi), haut + Vector2(taille.x, demi), Color(1.0, 0.9, 0.82, 0.16), BISEAU)
	n.draw_line(haut + Vector2(demi, 0.0), haut + Vector2(demi, taille.y), Color(1.0, 0.9, 0.82, 0.09), BISEAU)
	n.draw_line(haut + Vector2(taille.x - demi, 0.0), haut + Vector2(taille.x - demi, taille.y), Color(0, 0, 0, 0.16), BISEAU)
	var x: float = Murs.BRIQUE * 0.5
	while x < taille.x - 8.0:
		n.draw_line(Vector2(x, face.position.y), Vector2(x, face.end.y), Trace.voile(a.joint, 0.5), 1.5)
		x += Murs.BRIQUE * 0.5
	n.draw_line(face.position, face.position + Vector2(taille.x, 0.0), Ambiance.eclaire(a.mur, 2.1).lerp(a.teinte, 0.15), 2.0)
	Trace.cadre(n, Rect2(dessus.position, taille + Vector2(0.0, HAUTEUR)), Trace.CERNE, 2.5)
