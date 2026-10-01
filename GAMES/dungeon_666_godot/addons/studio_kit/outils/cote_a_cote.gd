extends SceneTree

## Deux images côte à côte (avant | après), séparées d'un filet, éventuellement rognées sur une zone.
##   godot --headless --path <projet> --script res://addons/studio_kit/outils/cote_a_cote.gd -- <avant.png> <après.png> <sortie.png> [x y l h]
## Sert aux rapports de modification : on juge une retouche à l'écran, avant et après, au même instant.

const FILET_PX := 10


func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() < 3:
		printerr("usage : cote_a_cote.gd -- <avant.png> <après.png> <sortie.png> [x y l h]")
		quit(2)
		return
	var ia := Image.load_from_file(a[0])
	var ib := Image.load_from_file(a[1])
	if ia == null or ib == null:
		printerr("images illisibles")
		quit(2)
		return
	if a.size() >= 7:
		var r := Rect2i(int(a[3]), int(a[4]), int(a[5]), int(a[6]))
		ia = ia.get_region(r)
		ib = ib.get_region(r)
	ia.convert(Image.FORMAT_RGBA8)
	ib.convert(Image.FORMAT_RGBA8)
	var out := Image.create(ia.get_width() + ib.get_width() + FILET_PX, maxi(ia.get_height(), ib.get_height()), false, Image.FORMAT_RGBA8)
	out.fill(Color(1, 0, 1))
	out.blit_rect(ia, Rect2i(Vector2i.ZERO, ia.get_size()), Vector2i.ZERO)
	out.blit_rect(ib, Rect2i(Vector2i.ZERO, ib.get_size()), Vector2i(ia.get_width() + FILET_PX, 0))
	quit(0 if out.save_png(a[2]) == OK else 1)
