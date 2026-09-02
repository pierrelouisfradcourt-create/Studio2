# capture.gd — ligne proof.visual_gpu_window. Aide a la CAPTURE d'ecran pour la preuve
# VISUELLE. Contrainte de poste (charter, mesure 2026-07-22) : --headless rend une texture
# NULLE ; une capture non monochrome exige une fenetre GPU reelle (--rendering-driver vulkan,
# fenetre hors ecran). Ce module ne fait AUCUN rendu lui-meme : il fournit la routine de
# sauvegarde et le critere de non-monochromie que le pilote/oracle applique a une Image deja
# rendue par le viewport. RefCounted.
extends RefCounted

# Une Image est-elle NON monochrome (au moins 2 couleurs distinctes) ? Preuve minimale qu'un
# rendu reel a eu lieu (une texture nulle/headless est uniforme).
static func est_non_monochrome(img: Image) -> bool:
	if img == null or img.get_width() == 0 or img.get_height() == 0:
		return false
	var premiere := img.get_pixel(0, 0)
	var pas_x: int = maxi(1, img.get_width() / 32)
	var pas_y: int = maxi(1, img.get_height() / 32)
	var y := 0
	while y < img.get_height():
		var x := 0
		while x < img.get_width():
			if img.get_pixel(x, y) != premiere:
				return true
			x += pas_x
		y += pas_y
	return false

# Sauvegarde une Image en PNG au chemin donne. Renvoie OK/erreur de save_png.
static func sauver_png(img: Image, chemin: String) -> int:
	if img == null:
		return FAILED
	return img.save_png(chemin)
