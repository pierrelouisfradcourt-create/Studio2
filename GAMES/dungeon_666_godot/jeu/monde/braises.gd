extends "res://jeu/monde/calque.gd"
## Les braises en suspension : de petits points de lumière à la teinte du Cercle, qui montent
## lentement et vacillent. Discrètes (quelques dizaines, 1 à 3 u) : elles donnent de la profondeur
## sans rien cacher. Aucun état : chaque braise est une fonction du temps, ancrée dans le monde
## et repliée autour de la caméra. Calque en mélange additif (matériau posé dans monde.tscn).

const MARGE := 60.0 # u au-delà de la vue
const MONTEE := 14.0 # u/s
const COEUR := Color(1.0, 0.95, 0.85)

func _draw() -> void:
	var g = etat()
	if g == null:
		return
	var a: Dictionary = monde.ambiance()
	var t := temps()
	var etendue: Vector2 = monde.camera.vue + Vector2(MARGE, MARGE) * 2.0
	var coin: Vector2 = monde.camera.centre - etendue / 2.0
	for i in int(a.braises):
		var k := float(i)
		var hx := fposmod(k * 0.754877, 1.0)
		var hy := fposmod(k * 0.569840, 1.0)
		var vitesse := MONTEE * (0.5 + hx)
		var base := Vector2(hx * etendue.x + 26.0 * sin(t * 0.45 + k * 1.9), hy * etendue.y - t * vitesse)
		var p := coin + Vector2(fposmod(base.x - coin.x, etendue.x), fposmod(base.y - coin.y, etendue.y))
		var eclat := 0.5 + 0.5 * sin(t * (1.2 + hy * 2.0) + k * 2.7)
		var r := 1.0 + 1.6 * hy
		Trace.halo(self, p, r * 5.0, a.teinte, 0.28 * eclat)
		Trace.halo(self, p, r * 1.3, COEUR.lerp(a.teinte, 0.35), 0.4 + 0.6 * eclat)
