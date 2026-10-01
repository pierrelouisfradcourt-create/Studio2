extends SceneTree

## Oracle de non-régression VISUELLE : compare deux captures pixel à pixel.
##   godot --headless --path <projet> --script res://addons/studio_kit/outils/comparer.gd -- <a.png> <b.png> [tolérance=8]
## Sortie 0 = images identiques (à la tolérance près, sur 255) ; 1 = différentes (nombre et zone affichés) ;
## 2 = illisibles ou tailles différentes.

const TOLERANCE_DEFAUT := 8


func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() < 2:
		printerr("usage : comparer.gd -- <a.png> <b.png> [tolérance]")
		quit(2)
		return
	var ia := Image.load_from_file(a[0])
	var ib := Image.load_from_file(a[1])
	if ia == null or ib == null or ia.get_size() != ib.get_size():
		printerr("images illisibles ou de tailles différentes")
		quit(2)
		return
	var tol := (int(a[2]) if a.size() >= 3 else TOLERANCE_DEFAUT) / 255.0
	var r := comparer(ia, ib, tol)
	print("pixels différents : %d sur %d ; zone : %s" % [r["nombre"], ia.get_width() * ia.get_height(), str(r["zone"])])
	quit(0 if r["nombre"] == 0 else 1)


static func comparer(ia: Image, ib: Image, tol: float) -> Dictionary:
	var n := 0
	var zone := Rect2i()
	for y in ia.get_height():
		for x in ia.get_width():
			var ca := ia.get_pixel(x, y)
			var cb := ib.get_pixel(x, y)
			if maxf(maxf(absf(ca.r - cb.r), absf(ca.g - cb.g)), maxf(absf(ca.b - cb.b), absf(ca.a - cb.a))) > tol:
				zone = Rect2i(x, y, 1, 1) if n == 0 else zone.expand(Vector2i(x, y))
				n += 1
	return {"nombre": n, "zone": zone}
