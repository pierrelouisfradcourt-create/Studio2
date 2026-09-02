# rng.gd — SOURCE UNIQUE d'alea de la partie, deterministe par graine.
#
# Aucun autre systeme n'a le droit d'appeler `randi()`/`randf()`/`randomize()` : un alea
# non seede casse le rejeu, donc la mutation et la solvabilite. Ici l'etat du generateur
# est une VALEUR passee et rendue, jamais une variable globale.
#
# LCG 32 bits (Numerical Recipes). Choisi pour etre reproductible a l'identique en
# GDScript sans dependre d'une implementation moteur.
extends RefCounted

const A: int = 1664525
const C: int = 1013904223
const M: int = 4294967296   # 2^32

# Graine suivante. Pure : meme entree -> meme sortie, aucun etat retenu.
static func suivant(graine: int) -> int:
	return (A * graine + C) % M

# Entier dans [0, borne). `borne <= 0` rend 0 : un refus silencieux serait pire qu'une
# valeur nommee, et lever casserait le tick.
static func entier(graine: int, borne: int) -> int:
	if borne <= 0:
		return 0
	return (graine / 65536) % borne

# Tirage pondere dans une table {cle: poids}. `ordre` impose la sequence d'examen —
# JAMAIS l'ordre d'iteration d'un Dictionary, qui n'est pas un contrat de langage.
# Rend "" si aucun poids strictement positif : l'absence de tirage est une valeur.
static func pondere(graine: int, poids: Dictionary, ordre: Array) -> String:
	var total: int = 0
	for cle in ordre:
		if poids.has(cle) and int(poids[cle]) > 0:
			total += int(poids[cle])
	if total <= 0:
		return ""
	var tirage: int = entier(graine, total)
	var cumul: int = 0
	for cle in ordre:
		if not poids.has(cle) or int(poids[cle]) <= 0:
			continue
		cumul += int(poids[cle])
		if tirage < cumul:
			return String(cle)
	return String(ordre[ordre.size() - 1])
