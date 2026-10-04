extends "res://jeu/monde/calque.gd"
## Les OBSTACLES BAS (room.low, kind 'barrier') : des palissades de pieux, debout dans la salle
## comme les piliers — un nœud par obstacle, posé au PIED de sa face avant et trié du fond vers
## l'avant (y_sort) avec les ennemis, le héros et les piliers (entites.gd, groupe Debout).
## Ils se lisent AUTREMENT qu'un pilier : deux fois moins hauts, hérissés de pieux, coiffés du
## liseré clair de ce qui se franchit (le même que le bord des rivières, terrain.gd). On tire et
## l'on voit par-dessus ; le déplacement de classe les saute. Leur ombre reste au sol (terrain.gd).
##
## Coût : rien ne bouge. Les nœuds sont refaits quand la salle change, chacun dessiné UNE fois.

const Terrain = preload("res://jeu/monde/terrain.gd")

const HAUTEUR := 8.0 # u : hauteur apparente (un pilier en fait 18)
const PIEU := 20.0 # u entre deux pieux
const PIEU_HAUT := 11.0 # u : pointe d'un pieu au-dessus de la traverse
const BOIS := Color("#6a4a34")

var _salle = null

func _process(_delta: float) -> void:
	var g = etat()
	var salle = g.room if g != null else null
	if is_same(salle, _salle):
		return
	_salle = salle
	for n in get_children():
		n.queue_free()
	if salle == null:
		return
	var a: Dictionary = monde.ambiance()
	var clair: Color = Terrain.FLUIDES[Terrain.FLUIDE_DU_CERCLE[posmod(monde.cercle() - 1, Terrain.FLUIDE_DU_CERCLE.size())]].clair
	for o in salle.get("low", []):
		if o.get("kind") != "barrier":
			continue
		var n := Node2D.new()
		n.position = Vector2(o.x0, o.y1)
		n.draw.connect(_peindre.bind(n, Vector2(o.x1 - o.x0, o.y1 - o.y0), a, clair))
		add_child(n)

## Dessin d'une palissade dans SON repère (origine au pied gauche de la face avant) : traverse
## basse (dessus et face), pieux le long du grand axe, liseré clair, cerne.
func _peindre(n: Node2D, taille: Vector2, a: Dictionary, clair: Color) -> void:
	var bois: Color = BOIS.lerp(a.mur, 0.35)
	var dessus := Rect2(Vector2(0.0, -taille.y - HAUTEUR), taille)
	var face := Rect2(0.0, -HAUTEUR, taille.x, HAUTEUR)
	Trace.degrade_vertical(n, dessus, Ambiance.eclaire(bois, 1.25), Ambiance.eclaire(bois, 0.95))
	Trace.degrade_vertical(n, face, Ambiance.eclaire(bois, 0.6), Ambiance.eclaire(bois, 0.36))
	var en_long := taille.x >= taille.y
	var longueur := taille.x if en_long else taille.y
	var u := PIEU * 0.5
	while u < longueur - 4.0:
		_pieu(n, dessus, u, en_long, bois)
		u += PIEU
	# Le liseré clair de ce qui se franchit, sur l'arête du dessus.
	Trace.cadre(n, dessus.grow(-1.5), Trace.voile(clair, 0.8), 2.0)
	Trace.cadre(n, Rect2(dessus.position, taille + Vector2(0.0, HAUTEUR)), Trace.CERNE, 2.0)

## Un pieu taillé en pointe, planté dans la traverse (triangle clair, flanc sombre).
func _pieu(n: Node2D, dessus: Rect2, u: float, en_long: bool, bois: Color) -> void:
	var c := Vector2(dessus.position.x + u, dessus.get_center().y) if en_long else Vector2(dessus.get_center().x, dessus.position.y + u)
	var demi := 5.0
	var pointe := c + Vector2(0.0, -PIEU_HAUT)
	n.draw_primitive(PackedVector2Array([c + Vector2(-demi, 3.0), pointe, c + Vector2(0.0, 3.0)]), PackedColorArray([Ambiance.eclaire(bois, 1.5), Ambiance.eclaire(bois, 1.9), Ambiance.eclaire(bois, 1.5)]), PackedVector2Array())
	n.draw_primitive(PackedVector2Array([c + Vector2(0.0, 3.0), pointe, c + Vector2(demi, 3.0)]), PackedColorArray([Ambiance.eclaire(bois, 0.7), Ambiance.eclaire(bois, 1.0), Ambiance.eclaire(bois, 0.7)]), PackedVector2Array())
	n.draw_line(c + Vector2(-demi, 3.0), pointe, Trace.CERNE, 1.0)
	n.draw_line(pointe, c + Vector2(demi, 3.0), Trace.CERNE, 1.0)
