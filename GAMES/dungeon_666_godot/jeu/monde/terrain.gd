extends "res://jeu/monde/calque.gd"
## Le TERRAIN BAS au sol : les RIVIÈRES des Enfers (room.low, kind 'river') et l'ombre des
## obstacles bas (dressés, eux, par barrieres.gd dans le groupe trié en profondeur).
## Une rivière est un canal CREUSÉ dans le dallage : berge sombre, ce qui coule dedans (eau noire,
## sang ou lave selon le Cercle), filets de courant, et un LISERÉ clair sur ses bords — la marque
## « ici, le déplacement de classe franchit ». Rien à voir avec un pilier : pas de hauteur, pas de
## face, une couleur vive au ras du sol. Présentation pure : le calque LIT room.low.
##
## Coût : rien ne bouge ici. Le calque n'est redessiné que lorsque la salle change (rectangles et
## primitives d'équerre, traits non lissés : quelques lots). La lueur est un calque additif enfant,
## redessiné en même temps.

const BERGE := 8.0 # u : berge sombre autour du canal
const LISERE := 3.0 # u : liseré clair du bord franchissable
const FILET := 22.0 # u entre deux filets de courant
const REMOUS := 46.0 # u : pas des remous le long d'un filet
const OMBRE_BARRIERE := Vector2(5.0, 7.0)
## Ce qui coule, par Cercle (1..10) : l'Achéron et le Styx sont d'eau noire, le Phlégéthon de sang,
## les fosses de feu de lave, le Cocyte d'eau glacée. `fond` : le fluide (un aplat : deux tronçons
## qui se recouvrent ne montrent aucune couture) ; `clair` : ses reflets et le liseré ; `lueur` :
## part de lumière qu'il jette sur ses berges.
const FLUIDES := {
	"eau": {"fond": Color("#102e3b"), "clair": Color("#7fc6d8"), "lueur": 0.05},
	"sang": {"fond": Color("#4a0a12"), "clair": Color("#ff5a5a"), "lueur": 0.08},
	"lave": {"fond": Color("#7a2606"), "clair": Color("#ffb04a"), "lueur": 0.12},
	"glace": {"fond": Color("#14324a"), "clair": Color("#bfe6ff"), "lueur": 0.06},
}
const FLUIDE_DU_CERCLE: Array[String] = ["eau", "eau", "eau", "lave", "eau", "lave", "sang", "lave", "glace", "lave"]

var _salle = null

func _process(_delta: float) -> void:
	var g = etat()
	var salle = g.room if g != null else null
	if not is_same(salle, _salle):
		_salle = salle
		redessiner()

## Le fluide du Cercle en cours.
func fluide() -> Dictionary:
	return FLUIDES[FLUIDE_DU_CERCLE[posmod(monde.cercle() - 1, FLUIDE_DU_CERCLE.size())]]

## Les rivières de la salle, rognées à l'intérieur des murs (elles passent dessous).
func _rivieres(room: Dictionary) -> Array:
	var d := dedans(room)
	var out: Array = []
	for o in room.get("low", []):
		if o.get("kind") == "river":
			var r := Rect2(o.x0, o.y0, o.x1 - o.x0, o.y1 - o.y0).intersection(d)
			if r.has_area():
				out.append(r)
	return out

func _draw() -> void:
	var g = etat()
	if g == null:
		return
	var room: Dictionary = g.room
	var d := dedans(room)
	for o in room.get("low", []):
		if o.get("kind") == "barrier":
			draw_rect(Rect2(Vector2(o.x0, o.y0) + OMBRE_BARRIERE, Vector2(o.x1 - o.x0, o.y1 - o.y0)).intersection(d), Color(0, 0, 0, 0.42))
	var rivieres := _rivieres(room)
	if rivieres.is_empty():
		return
	var f := fluide()
	# 1. la berge creusée, 2. le liseré clair, 3. le fluide : dans cet ordre, pour que deux tronçons
	# qui se touchent (les coudes d'une douve) ne se dessinent pas de bord l'un dans l'autre.
	for r in rivieres:
		draw_rect(r.grow(BERGE).intersection(d), Color(0.02, 0.01, 0.02, 0.78))
	for r in rivieres:
		draw_rect(r.grow(LISERE).intersection(d), Ambiance.eclaire(f.clair, 0.9))
	for r in rivieres:
		draw_rect(r, f.fond)
	for r in rivieres:
		_courant(r, f.clair)
		_ombre_de_berge(r, rivieres)

## Filets de courant : des traits courts le long du grand axe, à pas réguliers, décalés d'un
## filet sur l'autre (un motif fixe : deux salles au même plan ont la même eau).
func _courant(r: Rect2, clair: Color) -> void:
	var long_x := r.size.x >= r.size.y
	var longueur := r.size.x if long_x else r.size.y
	var largeur := r.size.y if long_x else r.size.x
	var rang := 0
	var t := FILET * 0.5
	while t < largeur - 4.0:
		var u := fposmod(float(rang) * 17.0, REMOUS)
		while u < longueur - 6.0:
			var brin := minf(10.0 + fposmod(u * 0.37 + float(rang) * 5.0, 14.0), longueur - u - 2.0)
			var a := Vector2(r.position.x + u, r.position.y + t) if long_x else Vector2(r.position.x + t, r.position.y + u)
			var b := a + (Vector2(brin, 0.0) if long_x else Vector2(0.0, brin))
			draw_line(a, b, Trace.voile(clair, 0.5 if rang % 2 == 0 else 0.3), 2.0)
			u += REMOUS
		t += FILET
		rang += 1

## La berge du fond jette son ombre dans le canal (on voit qu'il est creux) — sauf là où un autre
## tronçon continue la rivière.
func _ombre_de_berge(r: Rect2, rivieres: Array) -> void:
	var dessus := Vector2(r.get_center().x, r.position.y - 2.0)
	for autre in rivieres:
		if autre != r and autre.has_point(dessus):
			return
	Trace.degrade_vertical(self, Rect2(r.position, Vector2(r.size.x, minf(10.0, r.size.y * 0.3))), Color(0, 0, 0, 0.5), Color(0, 0, 0, 0.0))

## La lueur de ce qui coule (calque additif) : la lave éclaire ses berges, l'eau noire à peine.
func _dessiner_lumieres(c: CanvasItem) -> void:
	var g = etat()
	if g == null:
		return
	var f := fluide()
	for r in _rivieres(g.room):
		c.draw_rect(r.grow(BERGE + 8.0).intersection(dedans(g.room)), Trace.voile(f.clair, f.lueur))
