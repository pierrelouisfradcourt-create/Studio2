# brick_collision.gd — ligne physics.brick_collision. Destruction d'UNE brique au contact et
# rebond selon la face touchee. DECIDE ; ne detient pas le champ de briques. Fonction pure
# (balle, champ) -> {brique detruite ?, vitesse', position'}. RefCounted.
# Capacite proposee hors registre : game.brick_collision.
extends RefCounted

const P = preload("res://05_SYSTEMS/params/params.gd")
const BrickField = preload("res://05_SYSTEMS/game_state/brick_field.gd")

const FACE_AUCUNE := 0
const FACE_HORIZONTALE := 1   # dessus/dessous d'une brique -> inverse vy
const FACE_VERTICALE := 2     # gauche/droite d'une brique -> inverse vx

# La balle (disque) chevauche-t-elle le rectangle ?
static func _chevauche(pos: Vector2, r: float, rect: Rect2) -> bool:
	var cx: float = clampf(pos.x, rect.position.x, rect.position.x + rect.size.x)
	var cy: float = clampf(pos.y, rect.position.y, rect.position.y + rect.size.y)
	return pos.distance_to(Vector2(cx, cy)) <= r

# Face touchee, par comparaison des profondeurs de penetration AABB (heuristique
# deterministe standard) : penetration x plus faible -> face verticale ; sinon horizontale.
static func _face(pos: Vector2, r: float, rect: Rect2) -> int:
	var gauche: float = rect.position.x
	var droite: float = rect.position.x + rect.size.x
	var haut: float = rect.position.y
	var bas: float = rect.position.y + rect.size.y
	var overlap_x: float = min(pos.x + r, droite) - max(pos.x - r, gauche)
	var overlap_y: float = min(pos.y + r, bas) - max(pos.y - r, haut)
	if overlap_x < overlap_y:
		return FACE_VERTICALE
	return FACE_HORIZONTALE

# Repousse la balle hors de la brique le long de l'axe reflechi (evite un double contact).
static func _corriger(pos: Vector2, r: float, rect: Rect2, face: int) -> Vector2:
	var centre_rect := rect.position + rect.size / 2.0
	if face == FACE_VERTICALE:
		if pos.x < centre_rect.x:
			return Vector2(rect.position.x - r, pos.y)
		return Vector2(rect.position.x + rect.size.x + r, pos.y)
	if pos.y < centre_rect.y:
		return Vector2(pos.x, rect.position.y - r)
	return Vector2(pos.x, rect.position.y + rect.size.y + r)

# Inversion STRICTE de la composante correspondant a la face (negation exacte).
static func reflechir(vel: Vector2, face: int) -> Vector2:
	if face == FACE_VERTICALE:
		return Vector2(-vel.x, vel.y)
	if face == FACE_HORIZONTALE:
		return Vector2(vel.x, -vel.y)
	return vel

# Resout la premiere collision brique (ordre row-major, deterministe). Ne mute rien :
# renvoie {"hit":bool, "index":int, "face":int, "vel":Vector2, "pos":Vector2}.
static func resoudre(bricks: Array, start_y: float, pos: Vector2, vel: Vector2) -> Dictionary:
	var r := P.BALLE_RAYON
	for rangee in range(P.GRILLE_RANGEES):
		for colonne in range(P.GRILLE_COLONNES):
			var idx := BrickField.index(rangee, colonne)
			if idx >= bricks.size() or not bricks[idx]:
				continue
			var rect := BrickField.rect(rangee, colonne, start_y)
			if not _chevauche(pos, r, rect):
				continue
			var face := _face(pos, r, rect)
			return {
				"hit": true,
				"index": idx,
				"face": face,
				"vel": reflechir(vel, face),
				"pos": _corriger(pos, r, rect, face),
			}
	return {"hit": false, "index": -1, "face": FACE_AUCUNE, "vel": vel, "pos": pos}
