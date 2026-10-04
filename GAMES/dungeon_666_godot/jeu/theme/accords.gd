extends RefCounted
## Les ACCORDS des textes composés : un nombre et son nom, au singulier ou au pluriel.
##   const Accords = preload("res://jeu/theme/accords.gd")
##   Accords.compte(1.0, "Âme", "Âmes")  ->  « 1 Âme »      Accords.compte(12.0, "Âme", "Âmes")  ->  « 12 Âmes »
## Un nom tiré des données (classe, arme…) ne se fait jamais précéder de « du », « de la », « le » :
## son genre n'est pas connu. On écrit « Armes de la classe %s », « Super · %s ».

## « 0 démon », « 1 démon », « 2 démons » : le pluriel commence à deux.
static func compte(n: float, singulier: String, pluriel: String) -> String:
	return D6Js.num_str(n) + " " + nom(n, singulier, pluriel)

## Le nom seul, accordé au nombre.
static func nom(n: float, singulier: String, pluriel: String) -> String:
	return pluriel if n >= 2.0 else singulier
