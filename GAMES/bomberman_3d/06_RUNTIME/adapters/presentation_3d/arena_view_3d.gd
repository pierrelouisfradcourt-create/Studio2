# arena_view_3d.gd — PROJECTION de l'etat en 3D. N'implemente AUCUNE regle : il lit un
# etat et construit des noeuds. Le moteur de regles ignore jusqu'a l'existence de ce fichier.
#
# Patron verifie : games/chess_tcg/ui/game3d.gd (Node3D, TILE := 1.0, primitives +
# StandardMaterial3D + Camera3D + DirectionalLight3D, moteur `core/` intact).
#
# AUCUN LITTERAL DE COULEUR ICI — toute teinte vient de `palette.gd` (regle heritee de
# Pacman : l'unicite du lieu rend l'identite mesurable). Le seul « nombre » visuel qui
# reste ici est geometrique (tailles, hauteurs), pas chromatique.
#
# CONTRAINTE D'ARCHITECTURE POSEE EN L0, honoree : `projeter()` expose la correspondance
# cellule -> point d'ecran comme FONCTION PURE INTERROGEABLE. Sans elle, l'oracle pixel
# devrait deviner ou regarder pour verifier qu'une case a change.
extends Node3D

const P = preload("res://05_SYSTEMS/params/params.gd")
const Pal = preload("res://06_RUNTIME/adapters/palette/palette.gd")
const Explosion = preload("res://05_SYSTEMS/explosion/explosion.gd")

const TILE := 1.0
const H_SOLIDE := 1.0
const H_ACTEUR := 0.7

# Meshes de bibliotheque, MESURES avant usage (2026-08-10) :
#   gen_crate_wood_01  0,80 x 0,80 x 0,80  -> tient dans une case de 1,0, base a y=0. OK.
#   gen_barrel_01      0,60 x 0,90 x 0,60  -> OK, variante visuelle.
#   gen_pillar_stone_01 0,50 x 3,00 x 0,50 -> ECARTE comme MUR (trois fois trop haut), mais
#   REEMPLOYE comme DECOR vertical hors de la zone jouable : c'est la seule place ou sa
#   hauteur est un atout et non un defaut.
const MESHES_DESTRUCTIBLE: Array = [
	"res://04_ASSETS/meshes/gen_crate_wood_01.glb",
	"res://04_ASSETS/meshes/gen_barrel_01.glb",
]
const MESH_DECOR_VERTICAL := "res://04_ASSETS/meshes/gen_pillar_stone_01.glb"

# PERSONNAGES : un .glb par joueur, INDEXE comme `Pal.ACTEURS` et `Pal.SILHOUETTES_ACTEURS`.
# Les quatre sortent d'un seul archetype `soldier` : meme corps, memes proportions, meme
# echelle, meme pivot ; casque et accessoire seuls varient.
#
# LA SOURCE DE VERITE EST L'ORACLE, PAS CE COMMENTAIRE. Pour obtenir les mesures courantes :
#   PYTHONPATH=scripts .venv312/Scripts/python.exe -c "..."  -> forge.asset_geometry
# Les chiffres ne sont plus recopies ici : ils l'ont ete une fois, et ils ont menti. Releve
# du 2026-08-12 (historique DATE, ne pas mettre a jour) : scout 532 / assault 360 / tech 532
# / demo 580 sommets. Re-mesure du 2026-08-12 apres regeneration des assets : scout 844 /
# assault 648 / tech 820 / demo 868, hauteurs 0,782 a 0,836, 4/4 OK, pivot en base. Les deux
# releves portent la meme date et le meme intitule « mesures de l'oracle » : c'est
# exactement pourquoi un duplicata de mesure dans un commentaire ne peut pas servir de
# reference. Relancer l'oracle, ne pas lire ce paragraphe comme un etat courant.
#
# INVARIANT, lui, verifiable et stable : tous tiennent dans une case (TILE = 1,0) et restent
# sous la hauteur d'un mur (H_SOLIDE).
const MESHES_ACTEURS: Array = [
	"res://04_ASSETS/meshes/gen_soldier_scout_01.glb",
	"res://04_ASSETS/meshes/gen_soldier_assault_01.glb",
	"res://04_ASSETS/meshes/gen_soldier_tech_01.glb",
	"res://04_ASSETS/meshes/gen_soldier_demo_01.glb",
]
# Facteur d'ecrasement d'un acteur MORT. L'acteur n'est jamais supprime : l'ecran de
# resultat doit continuer a raconter le combat.
const ECRASEMENT_MORT := 0.14

var camera: Camera3D
var _racine_dyn: Node3D
var _largeur: int = 0
var _hauteur: int = 0
var _theme: Dictionary = {}
var _nom_theme: String = ""
var _scenes: Array = []
# Scenes des 4 personnages, chargees une fois. `null` = asset absent -> repli visible.
var _scenes_acteurs: Array = []
# Scenes de DECOR, indexees par chemin. Une entree de `Pal.DECORS` peut declarer un champ
# optionnel `mesh` ; `null` memorise = asset absent -> repli en primitive (cf. `_mesh_decor`).
var _scenes_decor: Dictionary = {}
# Cellules SOLIDES a la construction (voir `batir`). Tout ce qui devient solide ENSUITE est
# une fermeture de mort subite.
var _solides_initiaux: Dictionary = {}


# MEMOIRE DE RESSOURCES. `rafraichir` reconstruit la couche mutable a CHAQUE image ; sans
# ce cache, chaque case produisait un Mesh et un Material NEUFS a chaque image.
#
# COUT MESURE (2026-08-12, arene 15x13, fenetre GPU, V-Sync desactive). FRAME REELLE, une
# seule reconstruction par image — comme le fait `runtime_loop._process` :
#     0 bloc tombe      sans cache 4,76 ms (210 fps)   avec cache 1,67 ms (600 fps)
#     71 blocs          sans cache 6,06 ms (165 fps)   avec cache 2,05 ms (487 fps)
#     143 blocs (max)   sans cache 6,99 ms (143 fps)   avec cache 2,15 ms (465 fps)  -69 %
# Cause : un `SphereMesh` de Godot fait 64 segments x 32 anneaux par defaut (~2 100
# sommets), regenere pour CHAQUE cellule condamnee, a CHAQUE image.
#
# HONNETETE SUR LA PORTEE — une premiere mesure annoncait 14 605 us et « x5,2 » : elle
# appelait `rafraichir` DIX FOIS dans la meme image, ce qui empile dix reconstructions et
# dix vagues de `queue_free` avant que le moteur ne recupere quoi que ce soit. Elle
# SUREVALUAIT le cout. La mesure ci-dessus, une reconstruction par image, fait foi. Le gain
# est reel (-69 %), mais meme SANS cache la frame tenait dans le budget 60 fps sur ce poste :
# ce cache n'explique donc PAS a lui seul le ralenti ressenti au playtest.
#
# Un Mesh et un Material sont des RESSOURCES : les partager entre instances est le mode
# normal de Godot. Aucune geometrie ne change, aucune couleur ne change.
var _cache_mat: Dictionary = {}
var _cache_mesh: Dictionary = {}
var _cache_boite: Dictionary = {}


func _mat(col: Color, transparent: bool = false) -> StandardMaterial3D:
	var cle: String = "%s|%d" % [col.to_html(true), int(transparent)]
	if _cache_mat.has(cle):
		return _cache_mat[cle]
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 0.75
	if transparent:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_cache_mat[cle] = m
	return m


func _boite(pos: Vector3, taille: Vector3, col: Color, parent: Node3D,
		transparent: bool = false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cle: String = "%.4f_%.4f_%.4f" % [taille.x, taille.y, taille.z]
	if not _cache_boite.has(cle):
		var bm := BoxMesh.new()
		bm.size = taille
		_cache_boite[cle] = bm
	mi.mesh = _cache_boite[cle]
	mi.material_override = _mat(col, transparent)
	mi.position = pos
	parent.add_child(mi)
	return mi


# Une forme de la palette -> un mesh primitif. C'est ce qui donne aux power-ups une
# silhouette propre, et pas seulement une teinte.
func _mesh_de_forme(forme: int, hauteur: float) -> Mesh:
	var cle: String = "%d_%.4f" % [forme, hauteur]
	if _cache_mesh.has(cle):
		return _cache_mesh[cle]
	var maille: Mesh = _fabriquer_forme(forme, hauteur)
	_cache_mesh[cle] = maille
	return maille


func _fabriquer_forme(forme: int, hauteur: float) -> Mesh:
	match forme:
		Pal.FORME_SPHERE:
			var s := SphereMesh.new()
			s.radius = hauteur * 0.5
			s.height = hauteur
			return s
		Pal.FORME_CYLINDRE:
			var c := CylinderMesh.new()
			c.top_radius = hauteur * 0.42
			c.bottom_radius = hauteur * 0.42
			c.height = hauteur
			return c
		Pal.FORME_PRISME:
			var p := PrismMesh.new()
			p.size = Vector3(hauteur * 0.9, hauteur, hauteur * 0.9)
			return p
		_:
			var b := BoxMesh.new()
			b.size = Vector3(hauteur, hauteur, hauteur)
			return b


# UN ACTEUR : personnage 3D de l'escouade, pose sur sa case.
#
# Le .glb porte la FORME, la palette porte la LECTURE — convention du depot, constatee le
# 2026-08-10 : la geometrie de bibliotheque est nue, sans materiau elle sort blanche. Ici
# l'override est PAR SURFACE et non global : surface 0 = corps (couleur du joueur),
# surface 1 = accent sombre (bottes, mains, visiere, accessoire). Le producteur garantit cet
# ordre en fusionnant sur le TORSE, qui porte le materiau principal (cf. `_join`).
#
# Un `material_override` global aurait aplati le personnage en une seule teinte et refait
# exactement le defaut que la silhouette doit corriger.
func _acteur(index: int, base: Vector3, vivant: bool) -> void:
	var col: Color = Pal.ACTEURS[index % Pal.ACTEURS.size()]
	if _scenes_acteurs.is_empty():
		for chemin in MESHES_ACTEURS:
			_scenes_acteurs.append(load(chemin) if ResourceLoader.exists(chemin) else null)
	var scn = _scenes_acteurs[index % _scenes_acteurs.size()]
	if scn == null:
		# REPLI EXPLICITE : un asset manquant ne doit pas faire disparaitre un joueur de
		# l'arene. Une boite tient le role, visiblement pauvre — un defaut doit se voir.
		var hr: float = H_ACTEUR if vivant else H_ACTEUR * ECRASEMENT_MORT
		_boite(base + Vector3(0, hr * 0.5, 0), Vector3(0.58, hr, 0.58), col, _racine_dyn)
		return
	var inst = scn.instantiate()
	inst.position = base
	# MORT = APLATI, jamais supprime. Meme personnage, meme teinte : seule la hauteur change,
	# ce qui fait de « aplati = mort » une regle de forme et non une disparition.
	if not vivant:
		inst.scale = Vector3(1.0, ECRASEMENT_MORT, 1.0)
	_racine_dyn.add_child(inst)
	for mi in inst.find_children("*", "MeshInstance3D", true, false):
		var n: int = mi.mesh.get_surface_count() if mi.mesh != null else 0
		if n > 0:
			mi.set_surface_override_material(0, _mat(col))
		if n > 1:
			mi.set_surface_override_material(1, _mat(Pal.ACCENT_ACTEUR))


# FERMETURE : cellule condamnee par la mort subite. Le THEME choisit la representation ;
# la semantique, elle, reste celle du gameplay — un mur solide, identique pour les regles.
# Volume plus BAS qu'un mur permanent et forme NON CUBIQUE : la condamnation doit se lire
# comme un evenement, pas comme un mur de plus qui aurait toujours ete la.
func _fermeture(c: Vector2i) -> void:
	var d: Dictionary = Pal.fermeture(_nom_theme)
	var mi := MeshInstance3D.new()
	mi.mesh = _mesh_de_forme(int(d["forme"]), Pal.H_FERMETURE)
	mi.material_override = _mat(d["couleur"])
	mi.position = monde(c) + Vector3(0, Pal.H_FERMETURE * 0.5, 0)
	_racine_dyn.add_child(mi)


func monde(c: Vector2i) -> Vector3:
	return Vector3(float(c.x) * TILE, 0.0, float(c.y) * TILE)


# PROJECTION PURE cellule -> point d'ecran (pixels du viewport). Rend Vector2(-1,-1) si la
# case est derriere la camera. C'est le contrat que l'oracle pixel consomme.
func projeter(c: Vector2i) -> Vector2:
	if camera == null:
		return Vector2(-1, -1)
	var p := monde(c) + Vector3(0, 0.5, 0)
	if camera.is_position_behind(p):
		return Vector2(-1, -1)
	return camera.unproject_position(p)


func _destructible(c: Vector2i) -> void:
	if _scenes.is_empty():
		for chemin in MESHES_DESTRUCTIBLE:
			if ResourceLoader.exists(chemin):
				_scenes.append(load(chemin))
	if not _scenes.is_empty():
		var idx: int = int(abs(c.x * 7 + c.y * 13)) % _scenes.size()
		var inst = _scenes[idx].instantiate()
		inst.position = monde(c)
		_racine_dyn.add_child(inst)
		# Les .glb de la bibliotheque sont de la GEOMETRIE NUE : sans materiau ils sortent
		# blancs et deviennent illisibles (constate en capture, 2026-08-10). Le mesh apporte
		# la forme, la palette apporte la lecture.
		for mi in inst.find_children("*", "MeshInstance3D", true, false):
			mi.material_override = _mat(Pal.DESTRUCTIBLE[idx % Pal.DESTRUCTIBLE.size()])
		return
	_boite(monde(c) + Vector3(0, 0.45, 0), Vector3(TILE * 0.94, 0.9, TILE * 0.94),
		Pal.DESTRUCTIBLE[0], _racine_dyn)


# MESH DE DECOR : la piece est portee par un `.glb` de la bibliotheque au lieu de sa
# primitive. MEME MECANISME QUE `_destructible` ci-dessus, deliberement — meme garde
# `ResourceLoader.exists`, meme `load()`, meme `instantiate()`, meme override de materiau.
# Ce n'est pas un second chargeur d'assets : c'est le chargeur existant, applique a une
# entree de `DECORS` qui declare le champ optionnel `mesh`.
#
# Rend `false` si l'asset est absent ou non importe — et c'est le point : `load()` peut
# rendre `null` en silence quand le `.glb.import` manque, et un decor qui disparait sans
# bruit est exactement le mode de panne qu'on refuse. L'appelant retombe alors sur la
# primitive declaree par la meme entree.
#
# CHEMIN FROID : appele depuis `_decor`, donc depuis `batir`, une seule fois par partie.
# Rien de ceci n'entre dans `rafraichir` — c'est ce qui rend l'anneau gratuit par image.
#
# Les scenes sont MEMORISEES par chemin : `_decor` pose une cinquantaine de pieces pour
# trois assets distincts. Meme idiome que `_scenes` (destructibles) et `_scenes_acteurs`.
func _mesh_decor(chemin: String, col: Color, pos: Vector3, parent: Node3D) -> bool:
	if not _scenes_decor.has(chemin):
		_scenes_decor[chemin] = load(chemin) if ResourceLoader.exists(chemin) else null
	var scn = _scenes_decor[chemin]
	if scn == null:
		return false
	var inst = scn.instantiate()
	# Pivot en base cote asset : la piece se pose au sol sans decalage calcule ici. Les
	# primitives, elles, sont CENTREES et doivent etre remontees de `haut * 0.5` — d'ou la
	# difference avec les branches ci-dessous.
	inst.position = pos
	parent.add_child(inst)
	# Geometrie NUE : sans materiau elle sort blanche (constate en capture, 2026-08-10). Le
	# mesh apporte la forme, la palette apporte la lecture — la teinte est celle que l'entree
	# de `DECORS` declarait deja pour sa primitive, aucune couleur nouvelle n'entre ici.
	for mi in inst.find_children("*", "MeshInstance3D", true, false):
		mi.material_override = _mat(col)
	return true


# ====================================================================================
# CELLULE ARCHITECTURALE — l'etage de composition (P10, test de R3).
# ====================================================================================
#
# CE QUE CE BLOC N'EST PAS : un second systeme de decor. Il n'ajoute ni chargeur d'assets, ni
# cache, ni chemin de rendu. Il pose des pieces DEJA descriptibles par `palette.gd`, avec les
# memes `_boite` / `_mesh_decor` que l'anneau, et sur le MEME chemin FROID (`batir`).
#
# CE QU'IL AJOUTE, et c'est tout : un REPERE LOCAL. Une cellule est ecrite une fois en
# coordonnees (u le long de l'anneau, v vers l'exterieur) ; un unique pivot la pose sur
# n'importe lequel des quatre cotes. Sans ce pivot il faudrait quatre declarations miroir, et
# « reutilisable » redeviendrait une intention.

# Desalignement DETERMINISTE d'une piece « posee a la main ». Rend [-0.5, 0.5).
# FONCTION PURE de (ancre, index) — jamais d'aleatoire, jamais d'horloge : deux rendus de la
# meme carte doivent donner exactement la meme image, sinon la comparaison pixel de l'oracle
# cesse d'etre rejouable. C'est la meme discipline que la densite de `_decor`.
func _grain(ancre: Vector2i, index: int, sel: int) -> float:
	var n: int = int(abs(ancre.x * 73856093 + ancre.y * 19349663 + index * 83492791 + sel * 2971215073))
	return float(n % 1024) / 1024.0 - 0.5


# UNE piece de cellule. `y` est la BASE (convention des `.glb` a pivot en base) ; les
# primitives, elles, sont centrees et sont donc remontees de `sy * 0.5` ici — au meme endroit
# et une seule fois, plutot qu'a chaque declaration.
func _piece_cellule(d: Dictionary, ancre: Vector2i, index: int, parent: Node3D) -> void:
	var col: Color = d["couleur"]
	var sx: float = float(d["sx"])
	var sy: float = float(d["sy"])
	var sz: float = float(d["sz"])
	var yaw: float = float(d["yaw"]) if d.has("yaw") else 0.0
	var du: float = 0.0
	var dv: float = 0.0
	# Le beton coule reste d'equerre ; ce qu'un homme a porte ne l'est jamais tout a fait.
	# Le desordre est declare PAR PIECE : applique a tout, il ferait un tas ; applique a rien,
	# trois instances de la cellule se liraient comme un tampon.
	if d.has("libre"):
		yaw += _grain(ancre, index, 1) * 11.0
		du = _grain(ancre, index, 2) * 0.09
		dv = _grain(ancre, index, 3) * 0.09

	var sous := Node3D.new()
	sous.position = Vector3(float(d["u"]) + du, float(d["y"]), float(d["v"]) + dv)
	sous.rotation.y = deg_to_rad(yaw)
	parent.add_child(sous)
	# Le ROLE est porte par le graphe de scene, pas seulement par le descripteur. C'est ce qui
	# permet de mesurer la hierarchie du dehors — « la masse principale domine-t-elle ? » se
	# repond en comparant des volumes ETIQUETES, jamais en devinant lequel est lequel.
	# Nomme APRES `add_child` : avant, Godot desambigue en `@role@2`, un nom que plus aucun
	# motif ne retrouve (defaut mesure, pas suppose — la premiere passe n'a vu qu'une cellule
	# sur trois et a compte les deux autres comme des props d'anneau).
	sous.name = String(d["role"])

	# MEME champ optionnel `mesh`, MEME chargeur que l'anneau et que les destructibles. Si
	# l'asset manque, on retombe sur la primitive decrite par la meme entree : un decor qui
	# disparait en silence est le mode de panne qu'on refuse.
	if d.has("mesh") and _mesh_decor(String(d["mesh"]), col, Vector3.ZERO, sous):
		return
	match int(d["forme"]):
		Pal.FORME_CYLINDRE:
			var mc := MeshInstance3D.new()
			var cle: String = "cyl_%.4f_%.4f" % [sx, sy]
			if not _cache_mesh.has(cle):
				var cy := CylinderMesh.new()
				cy.top_radius = sx * 0.5
				cy.bottom_radius = sx * 0.5
				cy.height = sy
				_cache_mesh[cle] = cy
			mc.mesh = _cache_mesh[cle]
			mc.material_override = _mat(col)
			mc.position = Vector3(0, sy * 0.5, 0)
			sous.add_child(mc)
		Pal.FORME_PRISME:
			var mp := MeshInstance3D.new()
			var clp: String = "pri_%.4f_%.4f_%.4f" % [sx, sy, sz]
			if not _cache_mesh.has(clp):
				var pm := PrismMesh.new()
				pm.size = Vector3(sx, sy, sz)
				_cache_mesh[clp] = pm
			mp.mesh = _cache_mesh[clp]
			mp.material_override = _mat(col)
			mp.position = Vector3(0, sy * 0.5, 0)
			sous.add_child(mp)
		_:
			_boite(Vector3(0, sy * 0.5, 0), Vector3(sx, sy, sz), col, sous)


# Pose UNE instance de cellule et rend les cases d'anneau qu'elle consomme.
#
# `sortant` est la normale qui pointe HORS de l'arene. Elle suffit a tout orienter :
#   pivot.rotation.y = atan2(sortant.x, sortant.z)  ->  le +Z local pointe vers `sortant`,
#   et le +X local suit l'anneau. Une seule ligne de trigonometrie pour les quatre cotes,
#   au lieu d'une table de cas ou une erreur de signe serait invisible a la relecture.
func _poser_cellule(modele: Dictionary, ancre: Vector2i, sortant: Vector2i, variante: int,
		parent: Node3D) -> Dictionary:
	var pivot := Node3D.new()
	# NOMME, et pas seulement pose : sans nom, une instance de cellule est indiscernable d'une
	# instance de `.glb` d'anneau (les deux sont des Node3D enfants directs de la vue). Le nom
	# est ce qui rend la cellule MESURABLE de l'exterieur — emprise reelle, hierarchie des
	# volumes, distance aux props voisins.
	pivot.position = monde(ancre)
	pivot.rotation.y = atan2(float(sortant.x), float(sortant.y))
	parent.add_child(pivot)
	pivot.name = "cellule"
	var pieces: Array = Pal.cellule_pieces(modele, variante)
	for i in range(pieces.size()):
		_piece_cellule(pieces[i], ancre, i, pivot)

	# RESERVATION. La tangente en coordonnees de CASE se deduit de la meme normale :
	# T = (sortant.y, -sortant.x). Elle doit rester coherente avec la rotation ci-dessus,
	# sinon la cellule serait rendue d'un cote et reservee de l'autre.
	var occupees: Dictionary = {}
	var t := Vector2i(sortant.y, -sortant.x)
	for k in range(int(modele["emprise"])):
		occupees[ancre + t * k] = true
	return occupees


# Choisit les emplacements et pose les cellules. DETERMINISTE et derive des seules dimensions
# de l'arene : aucune carte ne porte de coordonnee de decor, donc aucune carte ne peut voir
# son jeu change par ce bloc.
func _cellules(parent: Node3D) -> Dictionary:
	var occupees: Dictionary = {}
	var kit: Array = Pal.cellules(_nom_theme)
	if kit.is_empty():
		return occupees
	var modele: Dictionary = kit[0]
	var e: int = int(modele["emprise"])
	var demi: int = (e - 1) / 2
	var cx: int = int(_largeur / 2)
	var cz: int = int(_hauteur / 2)
	# Trois instances, trois cotes, trois VARIANTES. Trois et pas une : une cellule unique ne
	# dirait rien de sa repetabilite, or c'est precisement ce que P10 doit mesurer. Le
	# quatrieme cote reste au repertoire de props V3 — la cohabitation se juge cote a cote.
	#
	# AFFECTATION DES VARIANTES, corrigee A L'IMAGE : l'anneau du BAS est vu de dos par la
	# camera de jeu (son cote « exterieur » est celui qui regarde le joueur), il recoit donc la
	# variante la plus fournie sur sa face exterieure. L'anneau du HAUT, vu de face, peut se
	# permettre la variante sobre. Une repartition posee au hasard aurait mis la cellule la
	# plus pauvre a l'endroit le plus visible — invisible sur la specification, evident au rendu.
	var sites: Array = [
		{"ancre": Vector2i(cx + demi, -3), "sortant": Vector2i(0, -1),
			"long": _largeur + 5, "variante": 0},
		{"ancre": Vector2i(cx - demi, _hauteur + 2), "sortant": Vector2i(0, 1),
			"long": _largeur + 5, "variante": 2},
		{"ancre": Vector2i(-3, cz - demi), "sortant": Vector2i(-1, 0),
			"long": _hauteur + 5, "variante": 1},
	]
	for s in sites:
		# Une arene trop petite ne recoit pas de cellule : mieux vaut un anneau de props qu'une
		# cellule tronquee ou deux cellules qui se chevauchent dans un angle.
		if int(s["long"]) < e + 2:
			continue
		var pris: Dictionary = _poser_cellule(modele, s["ancre"], s["sortant"],
			int(s["variante"]), parent)
		for c in pris.keys():
			occupees[c] = true
	return occupees


# Pose un element de decor decrit par le repertoire du theme.
func _element_decor(d: Dictionary, pos: Vector3, parent: Node3D) -> void:
	var col: Color = d["couleur"]
	var haut: float = float(d["hauteur"])
	var larg: float = float(d["largeur"])
	# CHAMP OPTIONNEL `mesh`. Une entree qui n'en porte pas descend directement dans le `match`
	# ci-dessous et se rend EXACTEMENT comme avant — c'est la condition de non-regression des
	# pieces restees en primitives.
	if d.has("mesh") and _mesh_decor(String(d["mesh"]), col, pos, parent):
		return
	match int(d["forme"]):
		Pal.FORME_ARBRE:
			# Deux volumes : un tronc etroit, une frondaison large. C'est la SUPERPOSITION
			# qui fait lire « arbre » ; un seul cylindre vert ne le fait pas.
			_boite(pos + Vector3(0, haut * 0.28, 0), Vector3(larg * 0.22, haut * 0.56, larg * 0.22),
				Pal.tronc(col), parent)
			var mi := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = larg * 0.5
			sm.height = haut * 0.62
			mi.mesh = sm
			mi.material_override = _mat(col)
			mi.position = pos + Vector3(0, haut * 0.70, 0)
			parent.add_child(mi)
		Pal.FORME_NAPPE:
			_boite(pos + Vector3(0, haut * 0.5, 0), Vector3(larg, haut, larg), col, parent, col.a < 1.0)
		Pal.FORME_SPHERE:
			var ms := MeshInstance3D.new()
			var s2 := SphereMesh.new()
			s2.radius = larg * 0.5
			s2.height = haut
			ms.mesh = s2
			ms.material_override = _mat(col)
			ms.position = pos + Vector3(0, haut * 0.5, 0)
			parent.add_child(ms)
		Pal.FORME_CYLINDRE:
			var mc := MeshInstance3D.new()
			var cy := CylinderMesh.new()
			cy.top_radius = larg * 0.5
			cy.bottom_radius = larg * 0.5
			cy.height = haut
			mc.mesh = cy
			mc.material_override = _mat(col)
			mc.position = pos + Vector3(0, haut * 0.5, 0)
			parent.add_child(mc)
		_:
			_boite(pos + Vector3(0, haut * 0.5, 0), Vector3(larg, haut, larg), col, parent)


# DECOR : purement visuel, pose HORS de la zone jouable. Les regles ne le lisent jamais et
# ne PEUVENT pas le lire — il n'entre dans aucun etat. C'est la condition pour qu'enrichir
# l'image ne change pas le jeu, et elle est verifiee (test_lisibilite).
#
# La composition est DETERMINISTE (fonction de la case) : deux rendus du meme theme sont
# identiques, sinon la comparaison pixel deviendrait impossible.
func _decor(parent: Node3D, occupees: Dictionary = {}) -> void:
	var kit: Array = Pal.decor(_nom_theme)
	if kit.is_empty():
		return
	var poids_total: int = 0
	for d in kit:
		poids_total += int(d["poids"])
	var cases: Array = []
	for i in range(-2, _largeur + 3):
		cases.append(Vector2i(i, -3))
		cases.append(Vector2i(i, _hauteur + 2))
	for j in range(-2, _hauteur + 3):
		cases.append(Vector2i(-3, j))
		cases.append(Vector2i(_largeur + 2, j))
	for k in range(cases.size()):
		var c: Vector2i = cases[k]
		# CASES RESERVEES par une cellule architecturale. Sans ce filtre, le tirage de props
		# viendrait poser un bidon au milieu du blockhaus : la composition serait detruite par
		# le mecanisme meme qu'elle est censee depasser.
		if occupees.has(c):
			continue
		# Densite : deux cases sur trois portent un element. Un anneau plein ferait un mur.
		if (c.x * 5 + c.y * 3) % 3 == 0:
			continue
		var tirage: int = int(abs(c.x * 31 + c.y * 17)) % poids_total
		var cumul: int = 0
		for d in kit:
			cumul += int(d["poids"])
			if tirage < cumul:
				_element_decor(d, monde(c), parent)
				break


func batir(state, theme_nom: String = "") -> void:
	_largeur = state.arene.largeur
	_hauteur = state.arene.hauteur
	_nom_theme = theme_nom
	_theme = Pal.theme(theme_nom)

	# EMPREINTE DES MURS D'ORIGINE, prise a la construction. Elle sert a distinguer un mur
	# PERMANENT d'une cellule CONDAMNEE en cours de partie : les deux sont `P.SOLIDE` pour les
	# regles, et c'est tres bien — la semantique de jeu ne doit surtout pas se dedoubler.
	# La distinction est purement VISUELLE et se DERIVE de l'etat existant ; aucun etat
	# parallele n'est cree, donc rien ici ne peut deriver du jeu.
	_solides_initiaux.clear()
	for y0 in range(_hauteur):
		for x0 in range(_largeur):
			var c0 := Vector2i(x0, y0)
			if state.arene.type_case(c0) == P.SOLIDE:
				_solides_initiaux[c0] = true

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-62, -38, 0)
	sun.light_energy = 1.15
	add_child(sun)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = _theme["fond"]
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = _theme["ambiance"]
	e.ambient_light_energy = 0.9
	env.environment = e
	add_child(env)

	# DALLE EXTERIEURE : elle ne porte plus le terrain, seulement l'anneau de decor. Sans
	# elle les elements decoratifs flottent dans le vide.
	var marge := 4.5
	_boite(Vector3(float(_largeur - 1) * TILE * 0.5, -0.62, float(_hauteur - 1) * TILE * 0.5),
		Vector3(float(_largeur) * TILE + marge * 2.0, 0.1, float(_hauteur) * TILE + marge * 2.0),
		_theme["sol"], self)

	# TERRAIN : UN CARREAU PAR CASE, en damier. C'est ce qui rend la grille lisible ; une
	# dalle uniforme laissait le joueur sans repere de position (constate en capture).
	for y in range(_hauteur):
		for x in range(_largeur):
			var c := Vector2i(x, y)
			_boite(monde(c) + Vector3(0, -0.5, 0), Vector3(TILE, 0.1, TILE),
				Pal.sol_de(_nom_theme, c), self)

	# ORDRE VOULU : les CELLULES d'abord, le repertoire de props ensuite. La composition
	# reserve ses cases, puis les props remplissent ce qui reste. L'inverse ferait dependre le
	# lieu de ce que le tirage a bien voulu laisser libre.
	_decor(self, _cellules(self))
	_murs_permanents()

	camera = Camera3D.new()
	var cx := float(_largeur - 1) * TILE * 0.5
	var cz := float(_hauteur - 1) * TILE * 0.5
	camera.position = Vector3(cx, float(max(_largeur, _hauteur)) * 0.92, cz + float(_hauteur) * 0.62)
	camera.look_at_from_position(camera.position, Vector3(cx, 0.0, cz), Vector3.UP)
	add_child(camera)

	_racine_dyn = Node3D.new()
	add_child(_racine_dyn)
	rafraichir(state)


# Reconstruit la couche mutable. L'arene change a chaque explosion : rien de ce qui bouge
# ne peut etre bati une fois pour toutes.
# MURS PERMANENTS — CHEMIN FROID. Bati une fois, jamais reconstruit.
#
# DEFAUT CORRIGE (mesure du 2026-08-12) : ces murs vivaient dans `rafraichir`, donc ils
# etaient detruits et recrees a CHAQUE IMAGE, alors qu'un mur d'origine ne change JAMAIS
# apres `batir` — `_solides_initiaux` est fige a la construction. Le sol et le decor de
# l'anneau, eux, etaient deja du bon cote de la ligne. Les murs y sont ramenes.
#
# Ce que ce deplacement NE change pas, et c'est le point : memes formes, memes dimensions,
# memes materiaux, meme volume englobant (TILE x H_SOLIDE x TILE), meme ordre de dessin.
# Aucune regle, aucune collision, aucun cadrage. Le rendu doit etre pixel pour pixel
# identique — c'est ce que verifient les volets pixel de l'oracle produit.
func _murs_permanents() -> void:
	var mur: Color = _theme["mur"]
	for c in _solides_initiaux.keys():
		var base: Vector3 = monde(c)
		_boite(base + Vector3(0, H_SOLIDE * 0.11, 0),
			Vector3(TILE, H_SOLIDE * 0.22, TILE), Pal.mur_socle(mur), self)
		_boite(base + Vector3(0, H_SOLIDE * 0.55, 0),
			Vector3(TILE * 0.86, H_SOLIDE * 0.66, TILE * 0.86), mur, self)
		_boite(base + Vector3(0, H_SOLIDE * 0.94, 0),
			Vector3(TILE, H_SOLIDE * 0.12, TILE), Pal.mur_chapeau(mur), self)


func rafraichir(state) -> void:
	if _racine_dyn == null:
		return
	for c in _racine_dyn.get_children():
		_racine_dyn.remove_child(c)
		c.queue_free()

	for y in range(state.arene.hauteur):
		for x in range(state.arene.largeur):
			var c := Vector2i(x, y)
			var t: int = state.arene.type_case(c)
			if t == P.SOLIDE:
				# MUR PERMANENT : rien a faire ici. Il est bati UNE FOIS par `_murs_permanents`
				# sur le chemin FROID (cf. `batir`). Seule la FERMETURE de mort subite, qui
				# apparait en cours de partie, appartient a la couche mutable.
				if not _solides_initiaux.has(c):
					_fermeture(c)
			elif t == P.DESTRUCTIBLE:
				_destructible(c)

	# TELEGRAPHE DE DANGER, dessine AVANT la flamme : une case menacee par une bombe armee
	# est marquee au ras du sol. Sans lui, le joueur ne voit le danger qu'au moment ou il
	# tue — ce qui, dans ce genre, revient a ne pas le voir.
	# La zone est LUE depuis les regles (Explosion.zone_menacee), jamais recalculee ici.
	# La PULSATION d'opacite est fonction du TICK DE PARTIE : elle ajoute un canal de
	# MOUVEMENT au danger annonce, sans shader et sans seconde geometrie. Calculee une fois
	# par rafraichissement — toutes les cases menacees pulsent donc ENSEMBLE, ce qui se lit
	# comme un seul signal et non comme un scintillement.
	var teinte_menace: Color = Pal.menace_pulsee(int(state.ticks))
	for c in Explosion.zone_menacee(state).keys():
		if not state.flammes.has(c):
			_boite(monde(c) + Vector3(0, 0.03, 0),
				Vector3(TILE * 0.88, 0.06, TILE * 0.88), teinte_menace, _racine_dyn, true)

	# POWER-UPS : couleur + forme + hauteur, trois canaux de lecture.
	for c in state.powerups.keys():
		var d: Dictionary = Pal.powerup(String(state.powerups[c]))
		var mi := MeshInstance3D.new()
		var haut: float = float(d["hauteur"])
		mi.mesh = _mesh_de_forme(int(d["forme"]), haut)
		mi.material_override = _mat(d["couleur"])
		mi.position = monde(c) + Vector3(0, haut * 0.5 + 0.05, 0)
		_racine_dyn.add_child(mi)

	for b in state.bombes:
		_boite(monde(b["cellule"]) + Vector3(0, 0.32, 0), Vector3(0.62, 0.62, 0.62),
			Pal.BOMBE, _racine_dyn)

	for c in state.flammes.keys():
		_boite(monde(c) + Vector3(0, 0.30, 0), Vector3(TILE * 0.9, 0.55, TILE * 0.9),
			Pal.FLAMME, _racine_dyn)

	for i in range(state.acteurs.size()):
		var a: Dictionary = state.acteurs[i]
		_acteur(i, monde(a["cellule"]), bool(a["vivant"]))
