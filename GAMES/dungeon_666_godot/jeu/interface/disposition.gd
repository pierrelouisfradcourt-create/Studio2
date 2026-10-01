extends RefCounted
## Disposition de REPLI des commandes tactiles, quand la vue Entrees manque : la même que
## `layout()` de GAMES/dungeon_666/src/input/input.mjs (constantes BUTTONS, marges, éventail du
## portrait). Rend la même forme que `interface_tactile()` de la vue Entrees.

const BOUTONS := [
	{"id": "attack", "r": 48.0, "angle": 0.0, "dist": 0.0},
	{"id": "dash", "r": 40.0, "angle": 186.0, "dist": 112.0},
	{"id": "skill", "r": 33.0, "angle": 228.0, "dist": 112.0},
	{"id": "super", "r": 35.0, "angle": 268.0, "dist": 116.0},
	{"id": "gadget", "r": 27.0, "angle": 318.0, "dist": 98.0},
]
const MARGE_ATTAQUE := Vector2(118.0, 112.0)
## Portrait (toléré) : deux rangées au-dessus de l'attaque. id -> [angle, distance].
const EVENTAIL_PORTRAIT := {"dash": [248.0, 108.0], "skill": [294.0, 118.0], "super": [255.0, 197.0], "gadget": [288.0, 194.0]}
const MARGE_PORTRAIT := Vector2(95.0, 115.0)

## `taille` : celle du viewport ; `marges` : zone sûre (gauche, haut, droite, bas), en pixels du viewport.
static func calculer(taille: Vector2, marges: Vector4) -> Dictionary:
	var portrait := taille.y > taille.x
	var marge := MARGE_PORTRAIT if portrait else MARGE_ATTAQUE
	var attaque := Vector2(taille.x - marge.x - marges.z, taille.y - marge.y - marges.w)
	var boutons: Array = []
	for b in BOUTONS:
		var angle: float = b.angle
		var dist: float = b.dist
		if portrait and EVENTAIL_PORTRAIT.has(b.id):
			angle = EVENTAIL_PORTRAIT[b.id][0]
			dist = EVENTAIL_PORTRAIT[b.id][1]
		var p := attaque + Vector2.from_angle(deg_to_rad(angle)) * dist
		boutons.append({"id": b.id, "x": p.x, "y": p.y, "r": b.r, "pressed": false, "dragging": false, "dx": 0.0, "dy": 0.0})
	return {
		"visible": true,
		"stick": {"active": false, "baseX": 0.0, "baseY": 0.0, "knobX": 0.0, "knobY": 0.0},
		"buttons": boutons,
	}
