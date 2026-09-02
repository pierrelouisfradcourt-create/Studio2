# palette.gd — DESCRIPTEUR D'IDENTITE VISUELLE UNIQUE.
#
# reused_from = CONCEPT (games/pacman/06_RUNTIME/adapters/palette/palette.gd) : « changer
# ce SEUL module change l'apparence de tout, c'est l'UNICITE DU LIEU qui rend l'identite
# mesurable au lieu d'etre une appreciation ». Le comptage des litteraux de couleur situes
# hors de ce fichier doit valoir 0.
#
# reused_from = CONCEPT (games/snake/.../grid_view.gd::categories_couleur_partagee) :
# l'oracle de DISCERNABILITE. Snake avait deja etabli que deux categories de gameplay ne
# doivent jamais partager une couleur, et le verifiait mecaniquement. Bomberman ne l'avait
# pas consomme — c'est ce trou qui a laisse passer TROIS power-ups rendus a l'identique.
#
# CE QUE CE FICHIER AJOUTE au patron herite : une identite n'est pas qu'une couleur. Un
# power-up se distingue par COULEUR + FORME + HAUTEUR. La couleur seule echoue sur un petit
# objet vu de loin, et echoue tout court pour un joueur daltonien.
extends RefCounted

const P = preload("res://05_SYSTEMS/params/params.gd")

# --- Formes disponibles (vocabulaire ferme) ---
const FORME_CUBE: int = 0
const FORME_SPHERE: int = 1
const FORME_CYLINDRE: int = 2
const FORME_PRISME: int = 3
# Formes reservees au DECOR (jamais a un objet de jeu : un element decoratif ne doit pas
# pouvoir se confondre avec quelque chose de ramassable ou de dangereux).
const FORME_ARBRE: int = 4     # tronc + frondaison
const FORME_NAPPE: int = 5     # surface a plat (eau, dalle)

# --- Structure de l'arene, par THEME. La carte declare son theme en donnee ; ce module
# traduit. Un theme inconnu retombe sur `pierre` — jamais un plantage, jamais une carte
# invisible.
const THEMES: Dictionary = {
	"pierre": {
		"sol": Color(0.16, 0.18, 0.22),
		"sol_alt": Color(0.21, 0.23, 0.28),
		"mur": Color(0.42, 0.44, 0.50),
		"fond": Color(0.05, 0.06, 0.09),
		"ambiance": Color(0.35, 0.38, 0.45),
		"decor": Color(0.34, 0.36, 0.40),
	},
	"foret": {
		"sol": Color(0.17, 0.26, 0.16),
		"sol_alt": Color(0.22, 0.32, 0.20),
		"mur": Color(0.30, 0.42, 0.26),
		"fond": Color(0.04, 0.09, 0.06),
		"ambiance": Color(0.42, 0.50, 0.38),
		"decor": Color(0.20, 0.45, 0.22),
	},
	"eau": {
		"sol": Color(0.12, 0.22, 0.32),
		"sol_alt": Color(0.16, 0.28, 0.39),
		"mur": Color(0.26, 0.40, 0.52),
		"fond": Color(0.03, 0.07, 0.12),
		"ambiance": Color(0.36, 0.46, 0.58),
		"decor": Color(0.22, 0.52, 0.66),
	},
}
const THEME_DEFAUT := "pierre"

# LISIBILITE DE LA GRILLE. `sol` et `sol_alt` alternent en damier : c'est ce qui rend les
# CASES visibles. Sans elles, le terrain est une dalle uniforme et le joueur ne sait pas
# sur quelle case il se trouve — or dans ce genre le placement EST le jeu.
#
# reused_from = CONCEPT (games/pacman/.../maze_view.gd:87,346) : le sol se dessine CASE PAR
# CASE, jamais en un aplat. Pacman colore par TYPE de case, ce qui suffit a montrer la forme
# d'un labyrinthe ; ici deux couloirs voisins doivent aussi se distinguer, d'ou l'alternance.

# Ecart de luminance minimal exige entre deux teintes qui doivent se distinguer.
const ECART_LUMINANCE_MIN: float = 0.03


static func luminance(c: Color) -> float:
	return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b


# Teinte du sol d'une case, en damier. FONCTION PURE de la position.
static func sol_de(nom: String, c: Vector2i) -> Color:
	var th: Dictionary = theme(nom)
	return th["sol"] if (c.x + c.y) % 2 == 0 else th["sol_alt"]

# --- DECOR PAR THEME. Une carte n'a pas d'identite parce qu'elle a « du decor » : elle en a
# parce que ce decor RACONTE le meme lieu que son sol et ses murs. Chaque theme declare donc
# son propre repertoire, en donnee.
#
# `forme` reutilise le vocabulaire ci-dessus. `hauteur`/`largeur` sont des facteurs de case.
# `poids` regle la frequence relative ; `pose` dit ou l'element a le droit d'apparaitre :
#   "anneau" = pourtour exterieur (hors zone jouable, aucun effet sur les regles)
#   "nappe"  = a plat au sol sur le pourtour (mares, dalles)
# AUCUN element de decor n'est pose dans l'arene jouable : c'est ce qui garantit
# mecaniquement qu'enrichir l'image ne change pas le jeu.
#
# `mesh` — CHAMP OPTIONNEL (P9, 2026-08-12). Chemin d'un `.glb` de la bibliotheque qui porte
# la FORME de cette piece a la place de sa primitive. Le mecanisme de chargement est
# EXACTEMENT celui des destructibles (`arena_view_3d._destructible`) : meme `load()`, meme
# `instantiate()`, meme override de materiau — le `.glb` sort nu, c'est `couleur` ci-dessous
# qui porte la lecture. Une entree SANS `mesh` se rend comme avant, inchangee.
#
# `forme`/`hauteur`/`largeur` RESTENT RENSEIGNES sur une entree a `mesh`, et ce n'est pas un
# doublon mort : ils decrivent le REPLI. Si le `.glb` est absent ou non importe, la piece se
# rend en primitive au lieu de laisser un trou dans l'anneau. C'est la meme discipline que le
# repli de `_acteur` — un asset manquant doit degrader, jamais faire disparaitre.
#
# AUCUNE DIMENSION DE MESH N'EST RECOPIEE ICI. Un `.glb` porte ses propres dimensions et son
# pivot en base ; les redeclarer produirait une seconde source de verite qui derive au premier
# regeneration d'asset. La mesure vit dans l'Asset Geometry Oracle, pas dans ce fichier.

# --- MATIERES DU KIT MILITAIRE. Nommees (P10) parce qu'elles servent desormais a DEUX
# descripteurs — le repertoire de props `DECORS` et la cellule architecturale `CELLULES`.
# Un litteral recopie dans les deux aurait fait, a l'interieur meme du descripteur unique,
# la seconde source de verite que ce fichier existe pour interdire.
# AUCUNE VALEUR NOUVELLE : les six premieres sont exactement celles que `DECORS` portait en
# clair depuis le kit V3. Seules les trois dernieres sont introduites par la cellule.
const MIL_BETON := Color(0.44, 0.45, 0.47)          # barriere Jersey, dalle de toit
const MIL_SABLE := Color(0.52, 0.47, 0.34)          # sacs de sable
const MIL_KAKI := Color(0.33, 0.36, 0.27)           # caisses de munitions, panneau
const MIL_ACIER := Color(0.36, 0.37, 0.39)          # poteaux, mats
const MIL_VERT_MATERIEL := Color(0.30, 0.40, 0.34)  # bidons de carburant
const MIL_BETON_USE := Color(0.40, 0.40, 0.42)      # debris, bandeau de socle
# PLAN DE VALEURS DE LA CELLULE (P10). Etabli a l'image, pas au raisonnement — deux passes de
# rendu ont ete necessaires et les deux corrections etaient invisibles sur la specification.
#
#   sol du theme      0.16/0.18/0.22   luminance 0.176   (donne)
#   MIL_AIRE          0.21/0.22/0.23   luminance 0.218   aire de manoeuvre, a peine detachee
#   MIL_BETON_MASSE   0.34/0.35/0.36   luminance 0.348   la masse
#   MIL_BETON         0.44/0.45/0.47   luminance 0.447   bordure de l'aire, barrieres
#   MIL_BETON_COIFFE  0.50/0.51/0.53   luminance 0.508   la dalle de toit — le point le plus clair
#
# LA REGLE QUE CES VALEURS SERVENT : de loin, une cellule ne se lit pas a sa teinte (tout est
# gris) mais a son ECART INTERNE DE VALEUR. Passe 1 : masse a 0.38, indiscernable de `mur`
# (0.42/0.44/0.50) — un blockhaus gris dans un anneau de murs gris. Passe 2 : aire a 0.40,
# elle criait plus fort que ce qu'elle portait et la cellule se lisait « grande dalle vide ».
# L'aire est donc SOMBRE et sa BORDURE est claire : de la camera de jeu, c'est un liseré clair
# qui dessine l'emprise du lieu, pas un aplat qui l'ecrase.
const MIL_AIRE := Color(0.21, 0.22, 0.23)
const MIL_BETON_MASSE := Color(0.34, 0.35, 0.36)
const MIL_BETON_COIFFE := Color(0.50, 0.51, 0.53)
const MIL_OMBRE := Color(0.17, 0.18, 0.20)          # embrasure — un CREUX, pas un volume (P10)
const DECORS: Dictionary = {
	# KIT MILITAIRE V3 (P4) — l'anneau du theme `pierre` cesse d'etre trois cubes gris pour
	# devenir une LIGNE DE DEFENSE. Aucune forme nouvelle : le vocabulaire existant
	# (CUBE / CYLINDRE / PRISME) suffit, seules les proportions, les poids et les teintes
	# changent. Aucun `.glb`, aucun pipeline, aucun systeme de plus.
	#
	# ECHELLE TENUE : hauteurs 0,22 a 1,55, dans la bande deja observee sur ce theme
	# (0,32 a 1,60). Rien ne depasse l'enveloppe mesuree — le mirador a 3,00 reste EXCLU
	# tant que cadrage camera et occlusion ne sont pas mesures.
	#
	# BANDE ROUGE-ORANGE EVITEE : aucune de ces teintes n'entre dans la gamme reservee a
	# MENACE / FLAMME. Un decor militaire attire vers le kaki et le beton, jamais vers le
	# signal de danger — c'est ce qui protege P2 ici.
	"pierre": [
		# Barriere beton (Jersey) : basse, large, tres frequente -- elle FAIT la ligne.
		{"forme": FORME_CUBE, "couleur": MIL_BETON, "hauteur": 0.42, "largeur": 1.00, "poids": 5, "pose": "anneau"},
		# Empilement de sacs de sable : le MOU de la grammaire. `gen_sandbag_01` porte la forme,
		# la teinte sable desaturee ci-dessous reste celle de la primitive qu'il remplace.
		{"forme": FORME_CUBE, "couleur": MIL_SABLE, "hauteur": 0.30, "largeur": 0.72, "poids": 4, "pose": "anneau",
			"mesh": "res://04_ASSETS/meshes/gen_sandbag_01.glb"},
		# Caisses de munitions kaki : le registre "materiel", pas "fortification". La famille
		# DURE/modulaire de la grammaire — `gen_crate_mil_01` remplace le cube.
		{"forme": FORME_CUBE, "couleur": MIL_KAKI, "hauteur": 0.62, "largeur": 0.66, "poids": 3, "pose": "anneau",
			"mesh": "res://04_ASSETS/meshes/gen_crate_mil_01.glb"},
		# Poteau de grillage : vertical, fin, ponctue la ligne sans la fermer.
		{"forme": FORME_CYLINDRE, "couleur": MIL_ACIER, "hauteur": 1.55, "largeur": 0.16, "poids": 3, "pose": "anneau"},
		# Bidon de carburant : la famille CYLINDRIQUE utilitaire. `gen_fuel_drum_01` remplace le
		# cylindre ; il rappelle le destructible `gen_barrel_01` sans etre lui — teinte distincte,
		# et il vit sur l'anneau, jamais sur une case jouable.
		{"forme": FORME_CYLINDRE, "couleur": MIL_VERT_MATERIEL, "hauteur": 0.58, "largeur": 0.46, "poids": 2, "pose": "anneau",
			"mesh": "res://04_ASSETS/meshes/gen_fuel_drum_01.glb"},
		# Debris de beton : petit, anguleux, densite du "chaos joyeux" de la direction A.
		{"forme": FORME_PRISME, "couleur": MIL_BETON_USE, "hauteur": 0.22, "largeur": 0.52, "poids": 2, "pose": "anneau"},
	],
	"foret": [
		# Un arbre = tronc + frondaison : deux elements superposes, pas un cylindre vert.
		{"forme": FORME_ARBRE, "couleur": Color(0.16, 0.42, 0.18), "hauteur": 2.10, "largeur": 0.85, "poids": 4, "pose": "anneau"},
		{"forme": FORME_SPHERE, "couleur": Color(0.22, 0.52, 0.24), "hauteur": 0.70, "largeur": 0.70, "poids": 3, "pose": "anneau"},
		{"forme": FORME_CUBE, "couleur": Color(0.34, 0.32, 0.28), "hauteur": 0.36, "largeur": 0.80, "poids": 2, "pose": "anneau"},
	],
	"eau": [
		{"forme": FORME_NAPPE, "couleur": Color(0.16, 0.44, 0.62, 0.75), "hauteur": 0.04, "largeur": 2.30, "poids": 4, "pose": "nappe"},
		{"forme": FORME_CUBE, "couleur": Color(0.34, 0.36, 0.40), "hauteur": 0.40, "largeur": 0.85, "poids": 3, "pose": "anneau"},
		{"forme": FORME_CYLINDRE, "couleur": Color(0.28, 0.46, 0.34), "hauteur": 1.10, "largeur": 0.40, "poids": 2, "pose": "anneau"},
	],
}


# Teinte de TRONC derivee d une teinte de frondaison. Vit ici et pas dans la vue : la vue
# ne doit porter AUCUN litteral de couleur, meme calcule (oracle purete_visuelle).
# KIT MILITAIRE V3 — un mur n'est plus une boite unie. Trois volumes, trois teintes DERIVEES
# de `mur` : aucune couleur nouvelle n'entre dans le jeu, la garde `purete_visuelle` reste
# satisfaite par construction et le thème continue de commander sa propre gamme.
# Meme idiome que `tronc()` ci-dessous : une fonction pure, pas une constante de plus.
static func mur_socle(mur: Color) -> Color:
	return Color(mur.r * 0.72, mur.g * 0.72, mur.b * 0.74)


static func mur_chapeau(mur: Color) -> Color:
	return Color(min(1.0, mur.r * 1.18 + 0.04), min(1.0, mur.g * 1.18 + 0.04), min(1.0, mur.b * 1.16 + 0.03))


static func tronc(feuillage: Color) -> Color:
	return Color(feuillage.r * 0.45 + 0.18, feuillage.g * 0.38 + 0.12, feuillage.b * 0.30 + 0.06)


static func decor(nom: String) -> Array:
	if DECORS.has(nom):
		return DECORS[nom]
	return DECORS[THEME_DEFAUT]

# ====================================================================================
# CELLULE ARCHITECTURALE — P10, test de la regle candidate R3.
# ====================================================================================
#
# R3 (candidate, `knowledge_base/proposals/forge.consumer_is_not_found_by_shape.yaml`) :
#     « Une unite decorative doit exprimer une FONCTION SPATIALE, pas seulement une
#       identite d'objet. »
# `DECORS` ci-dessus est un REPERTOIRE D'OBJETS : il tire une piece par case d'anneau, et
# c'est exactement ce que le playtest a juge insuffisant — trois caisses et un bidon ne font
# pas une zone de stockage parce qu'ils coexistent. `CELLULES` declare l'etage manquant :
#     PROP -> GROUPE -> FONCTION -> CELLULE ARCHITECTURALE -> COMPOSITION DE L'ARENE
# Ce n'est PAS un second repertoire de props : aucune piece nouvelle n'est inventee ici. Une
# cellule est une DISPOSITION de pieces qui existent deja, et c'est la disposition seule qui
# porte l'information nouvelle.
#
# REPERE LOCAL, et il est la raison pour laquelle une cellule est REUTILISABLE :
#     u = le long de l'anneau      v = vers l'EXTERIEUR (dos a l'arene)      y = hauteur
# Aucune piece ne connait sa position dans le monde ni le cote d'anneau ou elle atterrit.
# La vue applique un seul pivot par instance ; poser la meme cellule sur les quatre cotes ne
# demande aucune declaration de plus, et il n'existe aucune variante « cote gauche ».
#
# `sx`/`sy`/`sz` = ENCOMBREMENT TOTAL de la piece, saillies comprises (regle R2, transposee de
# l'echelle de l'asset a celle de la piece). `y` est la BASE, jamais le centre : c'est la
# convention des `.glb` de la bibliotheque (pivot en base), et l'imposer aux primitives evite
# qu'une meme cle veuille dire deux choses selon la branche de rendu.
#
# `mesh` a EXACTEMENT le sens qu'il a dans `DECORS` : le `.glb` porte la forme, `couleur`
# porte la lecture, et `sx`/`sy`/`sz` decrivent le REPLI en primitive si l'asset manque.
#
# `var` (optionnel) = les VARIANTES ou la piece apparait. Une piece sans cette cle est dans
# toutes. C'est ce qui empeche la repetition de se lire comme un tampon : la cellule est une
# unite PARAMETRABLE, pas un decor fige.
#
# `libre` (optionnel) = piece POSEE PAR UN HOMME, donc autorisee a un leger desalignement
# deterministe. Le beton coule, lui, reste d'equerre. Le desordre est un choix par piece.
const ROLE_SOL := "sol"                # l'aire batie : ce qui fait un LIEU d'un groupe d'objets
const ROLE_PRINCIPAL := "principal"    # LA masse qui porte la silhouette de la cellule
const ROLE_SAILLIE := "saillie"        # bande ou plaque SUR la masse (R1)
const ROLE_FRONTIERE := "frontiere"    # ce qui separe le dedans du dehors
const ROLE_FONCTION := "fonction"      # ce qui dit A QUOI SERT la cellule
const ROLE_PROP := "prop"              # materiel — accompagne, ne raconte pas seul
const ROLE_LIAISON := "liaison"        # le detail qui coud les groupes entre eux

const CELLULES: Dictionary = {
	# DEPOT DE CARBURANT FORTIFIE. Une seule fonction declaree — `carburant` — portee par
	# TROIS bidons groupes en triangle a l'abri du parapet. Un bidon isole se lit « un objet
	# cylindrique » ; trois bidons serres derriere une ligne de defense se lisent « depot ».
	# C'est la these de R3, reduite a sa plus petite demonstration.
	#
	# HIERARCHIE VOULUE, et mesurable : le blockhaus fait ~1,9 m3 d'enveloppe, la plus grosse
	# piece d'anneau du kit V3 en fait 0,13. Rien d'autre dans la cellule ne s'en approche.
	#
	# ECHELLE TENUE : point haut 0,95 — sous le poteau de grillage du kit V3 (1,55) et sous le
	# mirador a 3,00 qui reste EXCLU tant que cadrage et occlusion ne sont pas mesures.
	"pierre": [
		{
			"nom": "depot_carburant_fortifie",
			"fonction": "carburant",
			# Cases d'anneau RESERVEES. Le repertoire de props ne tire plus dessus : sans cette
			# reservation, un bidon isole viendrait se poser au milieu du blockhaus et la
			# composition redeviendrait un tas.
			"emprise": 5,
			# ENCOMBREMENT TOTAL DECLARE (u, y, v), saillies comprises — R2 a l'echelle du
			# groupe. Confronte a l'AABB reellement construite ; un ecart signifie qu'une piece
			# deborde de la reservation, donc qu'elle mord sur l'anneau voisin. `y` compte
			# depuis le DESSOUS de l'aire batie (-0.57) jusqu'au point haut du blockhaus.
			"encombrement": Vector3(5.00, 1.65, 2.34),
			"pieces": [
				# ---- L'AIRE BATIE. C'est la piece que la premiere passe n'avait pas, et c'est
				# elle qui a change le resultat.
				#
				# MESURE QUI L'A IMPOSEE : le dessus de la grande dalle exterieure est a
				# y = -0.570, et TOUTE piece d'anneau a sa base a y = 0.000. Le decor du kit V3
				# ne repose donc sur rien — il flotte a 0,57 au-dessus du sol, soit plus d'une
				# demi-case. Un groupe d'objets qui flottent ne peut pas se lire comme un lieu,
				# quelle que soit la qualite des objets.
				# Le defaut est GENERAL (murs et destructibles flottent aussi, de 0,45 au-dessus
				# du damier) ; le corriger partout deplacerait tout le rendu du jeu et sort de
				# ce lot. La cellule le resout LOCALEMENT en descendant jusqu'au sol : elle
				# apporte sa propre aire, et ce qui etait un flottement devient un TERRE-PLEIN.
				# CORPS DU TERRE-PLEIN — la partie qui descend jusqu'au sol. Il est en beton
				# CLAIR et non dans la teinte de l'aire : c'est lui qu'on voit de profil depuis
				# la camera de jeu, et une passe l'a eu en teinte d'aire (0,21), ou ses faces a
				# l'ombre viraient au noir et donnaient une grande dalle funebre. Faces
				# verticales = ce qu'on voit de loin ; teinte de dessus = ce qu'on voit d'en
				# haut. Les separer n'est pas un detail, c'est la difference entre les deux.
				{"role": ROLE_SOL, "forme": FORME_CUBE, "couleur": MIL_BETON_MASSE,
					"u": 2.00, "y": -0.57, "v": 0.15, "sx": 4.94, "sy": 0.45, "sz": 2.28},
				# BORDURE CLAIRE en leger debord : elle dessine l'EMPRISE du lieu vue de haut.
				# C'est ce liseré, et non l'aire elle-meme, qui porte la lecture de loin.
				{"role": ROLE_SOL, "forme": FORME_CUBE, "couleur": MIL_BETON,
					"u": 2.00, "y": -0.12, "v": 0.15, "sx": 5.00, "sy": 0.11, "sz": 2.34},
				# Aire de manoeuvre, dessus a y = 0.000 EXACTEMENT : toutes les autres pieces
				# posent leur base a 0, elles reposent donc dessus sans decalage a declarer.
				# Elle depasse la bordure de 0,01 — deux dessus RIGOUREUSEMENT coplanaires se
				# battraient en profondeur et feraient scintiller le liseré.
				{"role": ROLE_SOL, "forme": FORME_CUBE, "couleur": MIL_AIRE,
					"u": 2.00, "y": -0.12, "v": 0.15, "sx": 4.84, "sy": 0.12, "sz": 2.18},

				# ---- STRUCTURE DOMINANTE : le blockhaus. Une masse, trois saillies, et les
				# trois sont des BANDES ou des PLAQUES — jamais une seconde masse (R1).
				{"role": ROLE_PRINCIPAL, "forme": FORME_CUBE, "couleur": MIL_BETON_MASSE,
					"u": 0.85, "y": 0.00, "v": 0.00, "sx": 1.46, "sy": 0.92, "sz": 1.04},
				# Dalle de toit DEBORDANTE : c'est le debord, pas la hauteur, qui fait lire
				# « ouvrage coule » plutot que « gros cube pose la ».
				{"role": ROLE_SAILLIE, "forme": FORME_CUBE, "couleur": MIL_BETON_COIFFE,
					"u": 0.85, "y": 0.92, "v": 0.00, "sx": 1.72, "sy": 0.16, "sz": 1.30},
				# EMBRASURE, cote ARENE. Un creux se lit comme un manque de matiere : c'est lui
				# qui dit « on tire d'ici », et il regarde le terrain, pas le vide.
				{"role": ROLE_SAILLIE, "forme": FORME_CUBE, "couleur": MIL_OMBRE,
					"u": 0.85, "y": 0.56, "v": -0.54, "sx": 1.02, "sy": 0.17, "sz": 0.08},
				# PORTE, cote EXTERIEUR. Corrige un defaut vu a l'image et invisible sur la
				# spec : depuis l'anneau le plus proche de la camera, on ne voit QUE la face
				# arriere du blockhaus — et une face arriere nue se lit « bloc de beton ».
				# Les deux faces longues portent desormais chacune leur ouverture.
				{"role": ROLE_SAILLIE, "forme": FORME_CUBE, "couleur": MIL_OMBRE,
					"u": 0.85, "y": 0.00, "v": 0.54, "sx": 0.44, "sy": 0.62, "sz": 0.08},

				# ---- FRONTIERE : la ligne qui part du blockhaus, descend en hauteur et
				# s'interrompt sur un passage. Le PROFIL DECROISSANT (0,95 -> 0,92 -> 0,46 ->
				# 0,42) est ce qui la fait lire comme une defense organisee et non comme une
				# rangee d'objets de meme taille.
				{"role": ROLE_FRONTIERE, "forme": FORME_CUBE, "couleur": MIL_SABLE, "libre": true,
					"mesh": "res://04_ASSETS/meshes/gen_sandbag_01.glb", "var": [0, 2],
					"u": 1.95, "y": 0.00, "v": -0.42, "sx": 0.86, "sy": 0.46, "sz": 0.404},
				{"role": ROLE_FRONTIERE, "forme": FORME_CUBE, "couleur": MIL_SABLE, "libre": true,
					"mesh": "res://04_ASSETS/meshes/gen_sandbag_01.glb", "var": [0, 2],
					"u": 1.95, "y": 0.46, "v": -0.42, "yaw": 9.0, "sx": 0.86, "sy": 0.46, "sz": 0.404},
				{"role": ROLE_FRONTIERE, "forme": FORME_CUBE, "couleur": MIL_SABLE, "libre": true,
					"mesh": "res://04_ASSETS/meshes/gen_sandbag_01.glb", "var": [0, 2],
					"u": 2.62, "y": 0.00, "v": -0.40, "yaw": -6.0, "sx": 0.86, "sy": 0.46, "sz": 0.404},
				{"role": ROLE_FRONTIERE, "forme": FORME_CUBE, "couleur": MIL_SABLE, "libre": true,
					"mesh": "res://04_ASSETS/meshes/gen_sandbag_01.glb", "var": [2],
					"u": 2.62, "y": 0.46, "v": -0.40, "yaw": 4.0, "sx": 0.86, "sy": 0.46, "sz": 0.404},
				# VARIANTE 1 : la meme frontiere, en beton. Ce n'est pas « la cellule 0 amputee » —
				# c'est la meme FONCTION servie par une autre matiere, ce que R3 demande de
				# pouvoir faire sans redessiner la cellule.
				{"role": ROLE_FRONTIERE, "forme": FORME_CUBE, "couleur": MIL_BETON, "var": [1],
					"u": 1.95, "y": 0.00, "v": -0.42, "sx": 0.96, "sy": 0.42, "sz": 0.30},
				{"role": ROLE_FRONTIERE, "forme": FORME_CUBE, "couleur": MIL_BETON, "var": [1],
					"u": 2.62, "y": 0.00, "v": -0.40, "yaw": -7.0, "sx": 0.96, "sy": 0.42, "sz": 0.30},
				{"role": ROLE_FRONTIERE, "forme": FORME_CUBE, "couleur": MIL_BETON,
					"u": 3.78, "y": 0.00, "v": -0.40, "sx": 0.96, "sy": 0.42, "sz": 0.30},
				# La derniere barriere PIVOTE vers l'exterieur : la ligne tourne au lieu de
				# s'arreter net. Une frontiere qui tourne enferme un espace ; une frontiere
				# droite ne fait que longer.
				{"role": ROLE_FRONTIERE, "forme": FORME_CUBE, "couleur": MIL_BETON,
					"u": 3.96, "y": 0.00, "v": 0.02, "yaw": 38.0, "sx": 0.96, "sy": 0.42, "sz": 0.30},

				# ---- FONCTION : le depot. Groupe en TRIANGLE et non en file — trois objets
				# alignes se lisent « inventaire », trois objets serres se lisent « stock ».
				# Pose DERRIERE la frontiere (v > 0) : ce qu'on protege est a l'abri.
				{"role": ROLE_FONCTION, "forme": FORME_CYLINDRE, "couleur": MIL_VERT_MATERIEL,
					"libre": true, "mesh": "res://04_ASSETS/meshes/gen_fuel_drum_01.glb",
					"u": 3.25, "y": 0.00, "v": 0.58, "sx": 0.70, "sy": 0.90, "sz": 0.70},
				{"role": ROLE_FONCTION, "forme": FORME_CYLINDRE, "couleur": MIL_VERT_MATERIEL,
					"libre": true, "mesh": "res://04_ASSETS/meshes/gen_fuel_drum_01.glb",
					"u": 3.92, "y": 0.00, "v": 0.66, "yaw": 15.0, "sx": 0.70, "sy": 0.90, "sz": 0.70},
				{"role": ROLE_FONCTION, "forme": FORME_CYLINDRE, "couleur": MIL_VERT_MATERIEL,
					"libre": true, "mesh": "res://04_ASSETS/meshes/gen_fuel_drum_01.glb", "var": [0, 2],
					"u": 3.52, "y": 0.00, "v": 0.82, "yaw": -12.0, "sx": 0.70, "sy": 0.90, "sz": 0.70},

				# ---- PROPS : le materiel. Deux caisses posees a la main contre le blockhaus,
				# partiellement sous le debord du toit — un objet ABRITE appartient au batiment,
				# un objet a cote ne fait que voisiner.
				{"role": ROLE_PROP, "forme": FORME_CUBE, "couleur": MIL_KAKI, "libre": true,
					"mesh": "res://04_ASSETS/meshes/gen_crate_mil_01.glb",
					"u": 1.68, "y": 0.00, "v": 0.64, "yaw": 6.0, "sx": 0.84, "sy": 0.62, "sz": 0.62},
				{"role": ROLE_PROP, "forme": FORME_CUBE, "couleur": MIL_KAKI, "libre": true,
					"mesh": "res://04_ASSETS/meshes/gen_crate_mil_01.glb",
					"u": 2.38, "y": 0.00, "v": 0.50, "yaw": -14.0, "sx": 0.84, "sy": 0.62, "sz": 0.62},

				# ---- LIAISON : le panneau d'entree, plante DANS la coupure de la frontiere.
				# C'est la seule piece verticale fine de la cellule : elle marque le passage et
				# relie visuellement le groupe « blockhaus + sacs » au groupe « barrieres +
				# depot », qui sans elle se liraient comme deux tas voisins.
				{"role": ROLE_LIAISON, "forme": FORME_CYLINDRE, "couleur": MIL_ACIER,
					"u": 3.02, "y": 0.00, "v": -0.66, "sx": 0.10, "sy": 1.05, "sz": 0.10},
				{"role": ROLE_LIAISON, "forme": FORME_CUBE, "couleur": MIL_KAKI, "var": [0, 1],
					"u": 3.02, "y": 0.72, "v": -0.72, "sx": 0.48, "sy": 0.30, "sz": 0.05},
			],
		},
	],
	# AUCUNE cellule pour ces themes, et c'est une DECLARATION, pas un oubli : un blockhaus de
	# beton dans une foret ou sur l'eau raconterait un autre lieu que son sol et ses murs. La
	# grammaire de composition est prete pour eux ; le vocabulaire ne l'est pas.
	"foret": [],
	"eau": [],
}


static func cellules(nom: String) -> Array:
	if CELLULES.has(nom):
		return CELLULES[nom]
	return CELLULES[THEME_DEFAUT]


# Pieces d'une cellule pour une variante donnee. Le FILTRE vit ici et non dans la vue : la
# vue construit des noeuds, elle ne decide pas de ce que le lieu contient.
static func cellule_pieces(modele: Dictionary, variante: int) -> Array:
	var out: Array = []
	for p in modele["pieces"]:
		if p.has("var") and not (variante in p["var"]):
			continue
		out.append(p)
	return out


# Nombre de variantes REELLEMENT distinctes declarees par une cellule. Mesure, pas constante :
# ajouter une variante a une piece doit se voir ici sans qu'on pense a mettre un chiffre a jour.
static func cellule_nb_variantes(modele: Dictionary) -> int:
	var vues: Dictionary = {}
	for p in modele["pieces"]:
		if p.has("var"):
			for v in p["var"]:
				vues[int(v)] = true
	return int(max(1, vues.size()))

# --- FERMETURE : la cellule CONDAMNEE par la mort subite. TROISIEME etat, a ne jamais
# fusionner avec les deux autres :
#     MENACE     danger ANNONCE, reversible      -> dalle au ras du sol + pulsation
#     FLAMME     mort IMMEDIATE, transitoire     -> volume bas et large
#     FERMETURE  condamnation IRREVERSIBLE       -> volume haut, forme non cubique
#
# CHAINE RESPECTEE — la semantique appartient au gameplay, la representation seule vit ici :
#     SEMANTIQUE GAMEPLAY -> cellule condamnee -> obstacle/danger -> REPRESENTATION THEMATIQUE
# `sudden_death.gd` solidifie la cellule et n'apprend rien de ce tableau. Quel que soit le
# theme, une cellule fermee est un mur solide pour les regles : changer l'habillage ne peut
# pas changer une partie.
#
# CONTRAINTES TENUES : jamais un cube recolore (les trois formes sont non cubiques) ·
# hauteur SOUS celle d'un mur permanent (H_SOLIDE = 1,0 cote vue), sans quoi une fermeture et
# un mur d'origine se liraient pareil · emprise inferieure a une case, donc aucune cellule
# voisine masquee.
const H_FERMETURE: float = 0.85
const FERMETURES: Dictionary = {
	"pierre": {"forme": FORME_SPHERE,   "couleur": Color(0.46, 0.42, 0.38)},  # eboulement
	"foret":  {"forme": FORME_CYLINDRE, "couleur": Color(0.33, 0.26, 0.16)},  # arbre tombe
	"eau":    {"forme": FORME_PRISME,   "couleur": Color(0.20, 0.48, 0.62)},  # masse d'eau
}


static func fermeture(nom: String) -> Dictionary:
	if FERMETURES.has(nom):
		return FERMETURES[nom]
	return FERMETURES[THEME_DEFAUT]

# --- Destructibles : deux variantes de la MEME chose (teintes proches a dessein). ---
const DESTRUCTIBLE: Array = [Color(0.66, 0.45, 0.24), Color(0.50, 0.33, 0.19)]

# --- Entites ---
const BOMBE := Color(0.08, 0.08, 0.10)
const FLAMME := Color(1.0, 0.55, 0.12)
# ZONE MENACEE : la case qu'une bombe armee VA frapper. Rouge sombre, translucide, au ras
# du sol — elle doit se lire sans jamais etre confondue avec la flamme qui, elle, tue deja.
const MENACE := Color(0.72, 0.14, 0.12)

# PULSATION DE MENACE (ratifiee Pierre 2026-08-11). Modulation d'OPACITE seule, par script :
# aucun shader, aucune geometrie nouvelle, aucun second mouvement concurrent. Elle ajoute un
# canal de MOUVEMENT au danger annonce — le seul canal qui reste lisible pour un daltonisme
# rouge-vert severe, ou la teinte de `MENACE` ne se distingue pas du sol.
#
# FONCTION PURE DU TICK DE PARTIE, jamais d'horloge murale : deux rejeux de la meme graine
# doivent rendre exactement la meme image, sinon la preuve en pixels cesse d'etre rejouable.
const MENACE_ALPHA_MIN: float = 0.45
const MENACE_ALPHA_MAX: float = 0.90
const MENACE_PERIODE_TICKS: int = 12


# Teinte de MENACE a un tick donne. Seule l'alpha varie — R/G/B restent la constante
# ci-dessus, pour que la pulsation ne puisse jamais deriver vers la teinte de FLAMME.
static func menace_pulsee(ticks: int) -> Color:
	var phase: float = float(ticks % MENACE_PERIODE_TICKS) / float(MENACE_PERIODE_TICKS)
	var onde: float = 0.5 - 0.5 * cos(phase * TAU)
	return Color(MENACE.r, MENACE.g, MENACE.b,
		MENACE_ALPHA_MIN + (MENACE_ALPHA_MAX - MENACE_ALPHA_MIN) * onde)
const ACTEURS: Array = [
	Color(0.95, 0.95, 0.98),
	Color(0.90, 0.25, 0.28),
	Color(0.25, 0.55, 0.92),
	Color(0.95, 0.80, 0.20),
]

# --- SILHOUETTES DES ACTEURS : le canal NON CHROMATIQUE de l'identite joueur.
#
# VOCABULAIRE SEPARE DES `FORME_*` ci-dessus, et l'ecart de numerotation (100+) est
# deliberé : une silhouette d'acteur est un PERSONNAGE 3D complet (un .glb de l'escouade),
# pas une primitive de rendu. Les confondre redeviendrait possible le jour ou quelqu'un
# comparerait les deux vocabulaires ; l'ecart rend cette confusion impossible a produire
# par accident.
#
# HISTORIQUE, garde parce qu'il explique la forme du code : la premiere version differenciait
# les joueurs par un COUVRE-CHEF pose sur un corps cubique. Rejete au playtest (« des chapeaux
# ridicules sur des cubes »). Le canal de differenciation reste le meme — la silhouette — mais
# il est desormais porte par le personnage entier.
#
# SET COHERENT, pas quatre choix independants : les quatre .glb sortent d'UN seul archetype
# `soldier` (scripts/forge/asset_producer/build_asset.py), corps et proportions ecrits une
# seule fois ; seuls le casque et un accessoire varient.
const SILHOUETTE_SCOUT: int = 100    # J1 blanc  — eclaireur/leader : casque rond + radio
const SILHOUETTE_ASSAULT: int = 101  # J2 rouge  — assaut : casque anguleux + epaulieres
const SILHOUETTE_TECH: int = 102     # J3 bleu   — technicien : barre de visee + module dorsal
const SILHOUETTE_DEMO: int = 103     # J4 jaune  — demineur : large bord + sacoche

# Tableau PARALLELE a `ACTEURS` — meme index = meme joueur.
const SILHOUETTES_ACTEURS: Array = [
	SILHOUETTE_SCOUT,
	SILHOUETTE_ASSAULT,
	SILHOUETTE_TECH,
	SILHOUETTE_DEMO,
]

# ACCENT des personnages : bottes, mains, visiere, accessoires. Vit ICI parce que le
# descripteur visuel est unique — un .glb de la bibliotheque porte la FORME, jamais la
# lecture (convention du depot, constatee le 2026-08-10 : la geometrie nue sort blanche).
const ACCENT_ACTEUR := Color(0.20, 0.21, 0.24)


# Silhouette d'un joueur. Meme convention modulo que la couleur cote vue
# (`ACTEURS[i % ACTEURS.size()]`) : aucune valeur par defaut inventee.
static func silhouette_acteur(index: int) -> int:
	return int(SILHOUETTES_ACTEURS[index % SILHOUETTES_ACTEURS.size()])

# --- INTERFACE. Les ecrans en prennent leur teinte : sans cette section, le shell
# reintroduisait des litteraux hors descripteur (detecte par purete_visuelle, pas par
# relecture — l affirmation d unicite etait fausse des sa premiere redaction).
const UI_VOILE := Color(0.03, 0.04, 0.07, 0.82)
const UI_TITRE := Color(1.0, 1.0, 1.0)
const UI_SOUS_TITRE := Color(0.85, 0.88, 0.95)
const UI_AIDE := Color(0.65, 0.70, 0.80)
const UI_HUD := Color(0.95, 0.95, 1.0)
const UI_FLASH := Color(1.0, 0.92, 0.45)

# --- POWER-UPS : identite COMPLETE, une entree par identifiant du registre de regles.
# `couleur` + `forme` + `hauteur` : trois canaux, pour qu'aucun ne porte seul la lecture.
const POWERUPS: Dictionary = {
	P.PU_BOMB_UP:  {"couleur": Color(0.20, 0.85, 0.95), "forme": FORME_SPHERE,   "hauteur": 0.52},
	P.PU_FIRE_UP:  {"couleur": Color(1.00, 0.42, 0.10), "forme": FORME_PRISME,   "hauteur": 0.60},
	P.PU_SPEED_UP: {"couleur": Color(0.55, 0.95, 0.30), "forme": FORME_CYLINDRE, "hauteur": 0.46},
}


static func theme(nom: String) -> Dictionary:
	if THEMES.has(nom):
		return THEMES[nom]
	return THEMES[THEME_DEFAUT]


static func powerup(identifiant: String) -> Dictionary:
	if POWERUPS.has(identifiant):
		return POWERUPS[identifiant]
	# Un power-up sans identite declaree ne doit pas devenir INVISIBLE : il se rend en
	# magenta, couleur qu'aucun theme n'emploie. Un defaut doit crier, pas disparaitre.
	return {"couleur": Color(1.0, 0.0, 1.0), "forme": FORME_CUBE, "hauteur": 0.5}


# ====================================================================================
# ORACLE DE DISCERNABILITE — porte de Snake, etendue.
# ====================================================================================

# Les categories de gameplay que le joueur DOIT pouvoir distinguer d'un coup d'oeil.
# Y figurent les trois power-ups : c'est precisement ce que l'ancienne version ne
# distinguait pas.
static func _identites_powerups() -> Array:
	var out: Array = []
	for id in P.POWERUP_IDS:
		var d: Dictionary = powerup(String(id))
		out.append({"nom": String(id), "couleur": d["couleur"], "forme": int(d["forme"])})
	return out


# Les quatre joueurs, avec la forme REELLE de leur couvre-chef.
# CORRIGE le 2026-08-12 : cette entree posait `FORME_CUBE` en dur, si bien qu'aucun controle
# ne pouvait voir la silhouette d'un acteur. Donner un couvre-chef distinct sans corriger ce
# point aurait produit une convention artistique NON VERIFIEE — exactement le defaut que P1
# doit empecher.
static func _identites_acteurs() -> Array:
	var out: Array = []
	for i in range(ACTEURS.size()):
		out.append({"nom": "acteur_%d" % i, "couleur": ACTEURS[i], "forme": silhouette_acteur(i)})
	return out


static func _identites_jouables() -> Array:
	var out: Array = _identites_powerups()
	out.append({"nom": "bombe", "couleur": BOMBE, "forme": FORME_CUBE})
	out.append({"nom": "flamme", "couleur": FLAMME, "forme": FORME_CUBE})
	out.append({"nom": "menace", "couleur": MENACE, "forme": FORME_CUBE})
	out.append_array(_identites_acteurs())
	return out


# Nombre de PAIRES de categories de gameplay partageant EXACTEMENT la meme couleur.
# L'oracle exige 0 (regle heritee de Snake).
static func categories_couleur_partagee() -> int:
	var ids: Array = _identites_jouables()
	var partages: int = 0
	for i in range(ids.size()):
		for j in range(i + 1, ids.size()):
			if ids[i]["couleur"] == ids[j]["couleur"]:
				partages += 1
	return partages


# Paires d'identites partageant la couleur OU la forme. Exigence PLUS DURE que celle de
# Snake (couleur seule), et c'est delibere : deux objets de tailles voisines ne se
# distinguent pas a distance par la seule teinte. Rendre 0 ici implique donc AUSSI 0 paire
# partageant simultanement couleur ET forme — la propriete faible est contenue dans la forte.
#
# GENERALISEE le 2026-08-12 : la fonction prend desormais la liste des identites a controler
# au lieu de coder `P.POWERUP_IDS` en dur. C'est la MEME fonction, appliquee a un second jeu
# d'identites — pas un oracle de plus.
#
# NE JAMAIS l'appliquer a `_identites_jouables()` : bombe, flamme et menace y partagent
# FORME_CUBE a dessein (ce ne sont pas des silhouettes, ce sont des volumes de signalisation
# differencies par la taille et la hauteur d'attache). Le controle inter-categories reste
# celui de la COULEUR, hérité de Snake.
static func identites_partagees(identites: Array) -> int:
	var partages: int = 0
	for i in range(identites.size()):
		for j in range(i + 1, identites.size()):
			var a: Dictionary = identites[i]
			var b: Dictionary = identites[j]
			if a["couleur"] == b["couleur"] or int(a["forme"]) == int(b["forme"]):
				partages += 1
	return partages


static func powerups_identite_partagee() -> int:
	return identites_partagees(_identites_powerups())


# Le controle qui manquait : la silhouette des quatre joueurs est enfin CONSOMMEE.
static func acteurs_identite_partagee() -> int:
	return identites_partagees(_identites_acteurs())


# Tout identifiant du registre de REGLES a-t-il une identite visuelle declaree ?
static func powerups_sans_identite() -> Array:
	var manquants: Array = []
	for id in P.POWERUP_IDS:
		if not POWERUPS.has(String(id)):
			manquants.append(String(id))
	return manquants
