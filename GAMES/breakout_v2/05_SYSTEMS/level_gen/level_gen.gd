# level_gen.gd — ligne level.seeded_generation. Generation SEEDEE et DETERMINISTE de la
# disposition des briques : (seed, index_de_niveau) -> disposition. Aucun alea non seede,
# aucune horloge. RefCounted, pur. Capacite proposee hors registre : game.level_generation.
#
# COMPTE CONSTANT / POSITION SEEDEE : le compte de briques vaut EXACTEMENT rangees*colonnes
# (charter state.brick_field), toutes presentes. Ce qui varie avec la seed est la POSITION
# du bloc (offset vertical seede) : deux seeds distinctes -> deux dispositions distinctes
# (charter VARIANCE PROUVEE), a compte identique. Un seul niveau en V1 (charter.hors_scope).
extends RefCounted

const P = preload("res://05_SYSTEMS/params/params.gd")

# Offset vertical (index discret) derive de la seed et du niveau, borne a LEVEL_NB_OFFSETS.
# Deterministe : meme (seed, niveau) -> meme index. Deux seeds distinctes proches -> index
# distincts (verifie par level_seed_determinism.test.gd sur les seeds de reference).
static func _offset_index(seed: int, niveau: int) -> int:
	var n: int = P.LEVEL_NB_OFFSETS
	return (((seed % n) + n) % n + ((niveau % n) + n) % n) % n

# y du haut du bloc de briques pour (seed, niveau).
static func start_y(seed: int, niveau: int) -> float:
	return P.BRIQUE_ZONE_Y_BASE + float(_offset_index(seed, niveau)) * P.LEVEL_OFFSET_STEP

# Disposition complete : toutes les briques presentes (compte = rangees*colonnes), bloc
# decale du start_y seede. Renvoie {"bricks": Array[bool], "start_y": float}.
static func generer(seed: int, niveau: int) -> Dictionary:
	var bricks: Array = []
	var total: int = P.total_briques()
	for _i in range(total):
		bricks.append(true)
	return {"bricks": bricks, "start_y": start_y(seed, niveau)}
