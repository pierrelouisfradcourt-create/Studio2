# rng.gd — UNIQUE generateur pseudo-aleatoire du jeu (ligne rng.seeded_stream).
# Son ETAT est un champ de l'etat de partie : il se clone, se rejoue et se compare comme
# n'importe quel autre champ. Aucune horloge, aucun randi()/randf()/randomize(), aucune
# source d'alea de plateforme n'est lue nulle part dans 05_SYSTEMS.
extends RefCounted

# Generateur congruentiel lineaire 31 bits (parametres ANSI C). Choisi pour rester dans
# les entiers positifs sans depassement : la suite est donc identique sur toute machine.
const MULTIPLICATEUR: int = 1103515245
const INCREMENT: int = 12345
const MODULO: int = 2147483648  # 2^31


# Normalise une graine en etat de generateur valide (toujours dans [0, MODULO[).
static func graine(valeur: int) -> int:
	var v: int = valeur % MODULO
	if v < 0:
		v += MODULO
	return v


# Avance la suite d'un cran. Retourne le nouvel etat — fonction PURE.
static func suivant(etat: int) -> int:
	return (etat * MULTIPLICATEUR + INCREMENT) % MODULO


# Tire un entier dans [0, borne[ et rend le nouvel etat. borne <= 0 -> valeur 0.
static func tirer(etat: int, borne: int) -> Dictionary:
	if borne <= 0:
		return {"valeur": 0, "etat": etat}
	var suite: int = suivant(etat)
	# Les bits de poids fort d'un LCG sont les mieux distribues : on decale avant modulo.
	var valeur: int = (suite >> 8) % borne
	return {"valeur": valeur, "etat": suite}


# Ecart DECLARE entre deux graines de niveaux successifs. Nombre premier : deux niveaux
# voisins ne repartent jamais sur le meme flux.
const ECART_GRAINE_NIVEAU: int = 7919


# GRAINE DE NIVEAU (ligne rng.reseed_on_switch) : valeur DECLAREE et reproductible,
# derivee de la graine de partie et du numero de niveau. Sans ce reseedage, le niveau
# suivant ne serait ni rejouable ni comparable — l'etat du generateur reste un champ de
# l'etat de partie, clone et compare comme n'importe quel autre.
static func graine_de_niveau(graine_partie: int, niveau: int) -> int:
	return graine(graine_partie + niveau * ECART_GRAINE_NIVEAU)


# Reseede l'etat de partie a la graine declaree du niveau donne.
static func reseeder(s, graine_partie: int, niveau: int) -> void:
	s.rng_etat = graine_de_niveau(graine_partie, niveau)
