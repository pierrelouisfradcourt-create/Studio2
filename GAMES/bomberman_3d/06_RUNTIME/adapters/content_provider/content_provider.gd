# content_provider.gd — LE SEUL endroit qui lit un fichier de carte.
#
# Adaptateur (06_RUNTIME) et non systeme (05_SYSTEMS) : il fait de l'I/O, donc il ne peut
# pas etre pur. Les systemes recoivent un descripteur DEJA EN MEMOIRE et n'ouvrent jamais
# rien — c'est ce qui les garde testables sans disque.
#
# Ne valide pas : il fournit. Le verdict appartient a map_validator, point de passage
# oblige entre ce module et le runtime.
extends RefCounted

# Catalogue ORDONNE. La graine de l'oracle de solvabilite selectionne la carte par
# (graine - 1) modulo cette taille : prouver la solvabilite cinquante fois sur la premiere
# carte ne dirait rien des deux autres.
const CATALOGUE: Array = [
	"res://03_WORLD/levels/arena_classic/level.json",
	"res://03_WORLD/levels/arena_chambres/level.json",
	"res://03_WORLD/levels/arena_couloirs/level.json",
]


# Descripteur brut d'une carte du catalogue. Rend un Dictionary VIDE si le fichier est
# absent ou illisible — jamais une exception, jamais un descripteur invente a moitie.
# Un descripteur vide echouera au verdict avec le motif `champ_obligatoire_manquant`,
# ce qui est la bonne facon de le signaler : par le point de passage, pas par un crash.
static func descripteur(index: int) -> Dictionary:
	if index < 0 or index >= CATALOGUE.size():
		return {}
	var f := FileAccess.open(CATALOGUE[index], FileAccess.READ)
	if f == null:
		return {}
	var brut := f.get_as_text()
	f.close()
	var parse = JSON.parse_string(brut)
	if not (parse is Dictionary):
		return {}
	return parse


static func nb_cartes() -> int:
	return CATALOGUE.size()
