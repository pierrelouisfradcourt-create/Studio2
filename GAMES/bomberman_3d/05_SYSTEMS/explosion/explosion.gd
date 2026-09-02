# explosion.gd — PROPAGATION EN CROIX et CHAINE. Le point technique central du jeu.
#
# Ce que ce module etablit, et qu'aucun autre ne peut etablir a sa place :
#   1. une flamme part du centre en QUATRE bras, longueur `rayon` ;
#   2. un bras S'ARRETE sur une case solide ;
#   3. un bras DETRUIT EXACTEMENT UN destructible puis s'arrete ;
#   4. une bombe atteinte par une flamme explose DANS LE MEME TICK, et arrete le bras
#      (sa propre croix prend le relais depuis sa case) ;
#   5. la chaine se resout EN FILE JUSQU'A POINT FIXE.
#
# DETERMINISME : la file est FIFO, l'ordre des bras est FIXE, et les bombes initiales
# arrivent triees par ordre de pose. Mais la garantie plus forte est structurelle — le
# resultat est une CLOTURE (ensemble de cases atteintes), donc independant de l'ordre
# d'insertion. C'est cette propriete que l'oracle verifie, pas seulement le fait qu'un
# ordre donne redonne le meme resultat.
#
# NE TUE PERSONNE et NE MODIFIE PAS l'arene : il calcule. L'application est au loop.
# Logique PURE.
extends RefCounted

const P = preload("res://05_SYSTEMS/params/params.gd")

# Ordre FIXE des bras. Jamais l'ordre d'iteration d'une structure non ordonnee.
const BRAS: Array = [
	Vector2i(0, -1),   # haut
	Vector2i(1, 0),    # droite
	Vector2i(0, 1),    # bas
	Vector2i(-1, 0),   # gauche
]


# Resout la detonation de `indices_initiaux` jusqu'au point fixe.
# Rend {"flammes": Array[Vector2i], "detruites": Array[Vector2i], "explosees": Array[int],
#       "auteur_par_case": Dictionary[Vector2i -> index d'acteur]}.
#
# `auteur_par_case` existe pour l'ATTRIBUTION des morts (cf. damage.gd) : premier
# ecrivain gagne, dans l'ordre FIFO de la file. Une case couverte par deux croix est donc
# attribuee a la bombe qui l'a atteinte la premiere dans l'ordre declare — arbitraire
# assume, mais REPRODUCTIBLE, ce qui est la seule propriete dont l'oracle a besoin.
static func resoudre(state, indices_initiaux: Array) -> Dictionary:
	var file: Array = []
	var vus_bombe: Dictionary = {}
	for i in indices_initiaux:
		if not vus_bombe.has(i):
			vus_bombe[i] = true
			file.append(i)

	var flammes: Dictionary = {}
	var detruites: Dictionary = {}
	var auteur: Dictionary = {}
	var explosees: Array = []

	var tete: int = 0
	while tete < file.size():
		var idx: int = int(file[tete])
		tete += 1
		if idx < 0 or idx >= state.bombes.size():
			continue
		explosees.append(idx)
		var b: Dictionary = state.bombes[idx]
		var centre: Vector2i = b["cellule"]
		var rayon: int = int(b["rayon"])
		var proprio: int = int(b["proprietaire"])
		flammes[centre] = true
		if not auteur.has(centre):
			auteur[centre] = proprio

		for d in BRAS:
			for r in range(1, rayon + 1):
				var c: Vector2i = centre + d * r
				if state.arene.est_solide(c):
					break
				flammes[c] = true
				if not auteur.has(c):
					auteur[c] = proprio
				if state.arene.est_destructible(c):
					# Exactement UN destructible par bras : la case brule, le bras s'arrete.
					detruites[c] = true
					break
				var autre: int = state.bombe_sur(c)
				if autre >= 0:
					if not vus_bombe.has(autre):
						vus_bombe[autre] = true
						file.append(autre)
					# Une bombe absorbe le bras : la propagation continue par SA croix.
					break

	return {
		"flammes": flammes.keys(),
		"detruites": detruites.keys(),
		"explosees": explosees,
		"auteur_par_case": auteur,
	}


# ZONE MENACEE : les cases que les bombes ACTUELLEMENT armees frapperont si rien ne change.
# Fonction PURE, ne modifie rien.
#
# Pourquoi elle vit ICI et pas dans la presentation : « quelles cases cette bombe couvre »
# est une question de REGLES, deja resolue au-dessus. La calculer une seconde fois dans la
# couche visuelle produirait deux verites concurrentes, et c'est exactement ainsi qu'un
# telegraphe finit par mentir sur le danger reel. La presentation LIT, elle ne recalcule pas.
#
# La chaine n'est PAS depliee : une bombe qui en amorcera une autre n'annonce que sa propre
# croix. C'est une limite ASSUMEE et nommee — anticiper la chaine donnerait au joueur une
# information que le jeu ne lui doit pas.
static func zone_menacee(state) -> Dictionary:
	var d: Dictionary = {}
	for b in state.bombes:
		var centre: Vector2i = b["cellule"]
		d[centre] = true
		for dir in BRAS:
			for r in range(1, int(b["rayon"]) + 1):
				var c: Vector2i = centre + dir * r
				if state.arene.est_solide(c):
					break
				d[c] = true
				if state.arene.est_destructible(c):
					break
	return d
