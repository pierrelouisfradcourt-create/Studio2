# input.gd — ligne core.input_rules (R6 Piece active seule).
# genre.tetris.player_controls_active_piece_only : le joueur n'agit QUE sur la piece active
# (translation horizontale, rotation, soft-drop, hard-drop). JAMAIS sur la pile. Ce systeme
# traduit une intention en une piece transformee ; il ne touche jamais la grille (donc la pile
# est structurellement inchangee sous tout input). Lit des intentions, jamais le clavier
# physique (frontiere INV-3). RefCounted (logique pure).
extends RefCounted

const Collision = preload("res://05_SYSTEMS/collision/collision.gd")
const Rotation = preload("res://05_SYSTEMS/rotation_rules/rotation.gd")

# Vocabulaire FERME des intentions (l'input_adapter clavier les produit, il ne les invente pas).
const NONE: int = 0
const LEFT: int = 1
const RIGHT: int = 2
const SOFT_DROP: int = 3
const ROTATE_CW: int = 4
const HARD_DROP: int = 5

# Applique une intention a la SEULE piece active. Retour :
#   {piece:Dictionary, moved:bool, landed:bool}
# `landed` n'est vrai que pour un hard-drop (la piece a touche le fond et doit se verrouiller).
# La grille n'est jamais passee en ecriture : la pile est inchangee par construction.
static func move_active_piece(grid: Array, piece: Dictionary, intent: int) -> Dictionary:
	if intent == LEFT:
		return _try_shift(grid, piece, Vector2i(-1, 0))
	if intent == RIGHT:
		return _try_shift(grid, piece, Vector2i(1, 0))
	if intent == SOFT_DROP:
		return _try_shift(grid, piece, Vector2i(0, 1))
	if intent == ROTATE_CW:
		var r := Rotation.rotate_piece(grid, piece, 1)
		return {"piece": r["piece"], "moved": r["rotated"], "landed": false}
	if intent == HARD_DROP:
		return _hard_drop(grid, piece)
	return {"piece": piece, "moved": false, "landed": false}

# Translation d'un pas si legale, sinon piece inchangee.
static func _try_shift(grid: Array, piece: Dictionary, delta: Vector2i) -> Dictionary:
	var cand := Collision.make_piece(piece["type"], piece["rot"], piece["pos"] + delta)
	if Collision.piece_fits(grid, cand):
		return {"piece": cand, "moved": true, "landed": false}
	return {"piece": piece, "moved": false, "landed": false}

# Descente jusqu'au contact : la piece s'arrete sur la premiere position ou elle ne peut plus
# descendre, et signale landed (verrouillage imminent).
static func _hard_drop(grid: Array, piece: Dictionary) -> Dictionary:
	var cur := piece
	while true:
		var down := Collision.make_piece(cur["type"], cur["rot"], cur["pos"] + Vector2i(0, 1))
		if Collision.piece_fits(grid, down):
			cur = down
		else:
			break
	return {"piece": cur, "moved": true, "landed": true}
