extends RefCounted
## Disposition de REPLI des commandes tactiles, quand la vue Entrees manque (bancs, essais) : la
## MÊME que celle de la vue Entrees, parce que c'est elle qui la calcule (jeu/entrees/tactile.gd,
## seule à connaître les places : attaque, arc des trois emplacements, dash à part). Rend la même
## forme que `interface_tactile()`.

const Tactile = preload("res://jeu/entrees/tactile.gd")

## `taille` : celle du viewport ; `marges` : zone sûre (gauche, haut, droite, bas), en pixels du
## viewport ; `echelle` : unités du viewport par px CSS.
static func calculer(taille: Vector2, marges: Vector4, echelle: float = 1.0) -> Dictionary:
	var doigts := Tactile.new({})
	doigts.disposer(taille, {"left": marges.x, "top": marges.y, "right": marges.z, "bottom": marges.w}, echelle)
	return doigts.interface(true)
