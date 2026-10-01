extends "res://jeu/monde/calque.gd"
## La lumière d'ambiance de la salle, à la teinte du Cercle : la flamme de chaque flambeau, la
## lueur qu'elle jette sur son mur et sa flaque de lumière au sol, qui vacillent doucement.
## Calque en mélange additif (matériau posé dans monde.tscn) : la lumière s'ajoute à la pierre.

const FLAQUE := 190.0 # u : rayon de la flaque de lumière au sol
const HAUTEUR_FLAMME := 17.0
const COEUR := Color(1.0, 0.95, 0.85)

func _draw() -> void:
	var g = etat()
	if g == null:
		return
	var teinte: Color = monde.teinte_du_cercle()
	var t := temps()
	var flambeaux: Array = monde.flambeaux()
	# Les halos d'abord, les flammes ensuite : chaque passe part en un lot.
	for i in flambeaux.size():
		var vacille := _vacille(t, float(i + 1))
		Trace.halo(self, flambeaux[i].sol, FLAQUE, teinte, 0.2 * vacille)
		Trace.halo(self, flambeaux[i].p, 58.0, teinte, 0.5 * vacille)
	for i in flambeaux.size():
		_flamme(flambeaux[i].p, teinte, t * 9.0 + float(i + 1) * 1.7, _vacille(t, float(i + 1)))

func _vacille(t: float, rang: float) -> float:
	return 0.82 + 0.1 * sin(t * 7.0 + rang * 2.1) + 0.08 * sin(t * 13.0 + rang * 5.3)

## Flamme : trois langues en triangles (un seul lot), cœur clair.
func _flamme(p: Vector2, teinte: Color, phase: float, vacille: float) -> void:
	var h := HAUTEUR_FLAMME * (0.85 + 0.3 * vacille)
	var penche := 2.5 * sin(phase)
	var pied := p + Vector2(0, -3.0)
	var chaud := Trace.voile(teinte, 0.9)
	var rien := Trace.voile(teinte, 0.0)
	var sans := PackedVector2Array()
	draw_primitive(PackedVector2Array([pied + Vector2(-6.5, 0), pied + Vector2(6.5, 0), pied + Vector2(penche, -h)]), PackedColorArray([chaud, chaud, rien]), sans)
	draw_primitive(PackedVector2Array([pied + Vector2(-5.0, 0), pied + Vector2(1.0, 0), pied + Vector2(-2.0 - penche, -h * 0.62)]), PackedColorArray([chaud, chaud, rien]), sans)
	draw_primitive(PackedVector2Array([pied + Vector2(-3.2, 0), pied + Vector2(3.2, 0), pied + Vector2(penche * 0.5, -h * 0.55)]), PackedColorArray([COEUR, COEUR, Trace.voile(COEUR, 0.2)]), sans)
