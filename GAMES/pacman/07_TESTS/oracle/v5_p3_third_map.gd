# v5_p3_third_map.gd — CAUSE RACINE P3, et TEST EN PRODUCTION DE LA METRIQUE V2.
#
# DEMANDE (Pierre, 2026-08-06) : une TROISIEME carte — nouvelle geometrie, meme systeme,
# memes fantomes, difficulte legerement superieure. Arc vise : apprendre / maitriser /
# terminer.
#
# CE QUE CETTE PREUVE MESURE :
# (1) LA CARTE EXISTE ET EST VALIDE par le verdict complet du validateur, pas par lecture ;
# (2) ELLE EST NOUVELLE : dimensions, plan, depart et total de collectibles PROPRES —
#     jamais recopies d'une carte existante ;
# (3) ELLE EST REELLEMENT SOLVABLE : le bot deterministe GAGNE dessus, tous collectibles
#     ramasses, par le meme canal d'entree public que le joueur ;
# (4) LA DIFFICULTE MONTE, mesuree sur deux grandeurs et non declaree : la cadence des
#     fantomes est STRICTEMENT croissante d'une carte a l'autre (un fantome saute moins
#     souvent, donc court plus vite), et la carte 3 porte PLUS de collectibles que la
#     carte 2 (exposition plus longue) ;
# (5) LA METRIQUE D'ARCHITECTURE V2 TIENT EN PRODUCTION : 0 fichier de 05_SYSTEMS ne
#     nomme une carte — la troisieme comprise. Ajouter une carte n'a ouvert aucun fichier
#     de logique.
extends RefCounted

const ContentV2 = preload("res://06_RUNTIME/adapters/content_provider/content_provider.gd")
const Shell = preload("res://06_RUNTIME/adapters/app_shell/app_shell.gd")
const Bot = preload("res://06_RUNTIME/adapters/solvability_bot/solvability_bot.gd")
const Purity = preload("res://06_RUNTIME/adapters/proof_harness/harness_purity_counts.gd")
const MazeClass = preload("res://05_SYSTEMS/maze/maze.gd")
const Schema = preload("res://05_SYSTEMS/map_schema/map_schema.gd")
const Validator = preload("res://05_SYSTEMS/map_validator/map_validator.gd")
const Pellets = preload("res://05_SYSTEMS/pellets/pellets.gd")
const State = preload("res://05_SYSTEMS/game_state/game_state.gd")

const INDEX_TROISIEME: int = 2
const DOSSIER_TROISIEME := "maze_grid"


# Cases praticables SANS ISSUE (au plus un voisin praticable). Mesure apprise au premier
# jet de cette carte : les culs-de-sac sont des pieges de FIN DE PARTIE — le bot y mourait
# a 195-201 collectibles sur 204, apres avoir ramasse presque toute la carte.
func _culs_de_sac(c) -> int:
	var n: int = 0
	for y in range(c.HAUTEUR):
		for x in range(c.LARGEUR):
			var p := Vector2i(x, y)
			if c.praticable(p) and c.voisins_praticables(p).size() <= 1:
				n += 1
	return n


func run(h) -> void:
	# --- (1) LA CARTE EST CATALOGUEE ET VALIDE. ---
	h.eq(ContentV2.nb_niveaux(), 3, "v5.p3: trois niveaux au catalogue")
	h.eq(ContentV2.dossier(INDEX_TROISIEME), DOSSIER_TROISIEME, "v5.p3: le troisieme niveau est declare")
	h.eq(ContentV2.index_du_dossier(DOSSIER_TROISIEME), INDEX_TROISIEME,
		"v5.p3: il se resout par son nom de dossier")
	var desc: Dictionary = ContentV2.descripteur(INDEX_TROISIEME)
	h.eq(desc.is_empty(), false, "v5.p3: son descripteur est lisible")
	h.eq(Schema.champs_manquants(desc).size(), 0, "v5.p3: meme jeu de champs obligatoires")
	h.eq(Schema.symboles_inconnus(desc["plan"]).size(), 0, "v5.p3: meme legende fermee")
	var verdict: Dictionary = Validator.verifier(desc)
	h.eq(verdict["valide"], true, "v5.p3: verdict de validite favorable")
	h.eq(verdict["motifs"].size(), 0, "v5.p3: aucun motif de refus")

	# --- (2) ELLE EST NOUVELLE, mesure par mesure. ---
	var carte = MazeClass.depuis_descripteur(desc)
	var classique = MazeClass.depuis_descripteur(ContentV2.descripteur(0))
	var alt = MazeClass.depuis_descripteur(ContentV2.descripteur(1))
	h.ok(carte.LARGEUR != classique.LARGEUR and carte.LARGEUR != alt.LARGEUR,
		"v5.p3: largeur propre, differente des deux autres")
	h.ok(carte.HAUTEUR != classique.HAUTEUR and carte.HAUTEUR != alt.HAUTEUR,
		"v5.p3: hauteur propre")
	h.ok(carte.PLAN != classique.PLAN and carte.PLAN != alt.PLAN, "v5.p3: plan propre")
	h.ok(carte.DEPART_PACMAN != classique.DEPART_PACMAN and carte.DEPART_PACMAN != alt.DEPART_PACMAN,
		"v5.p3: depart propre")
	h.ok(carte.ID != classique.ID and carte.ID != alt.ID, "v5.p3: identifiant propre")

	var grille := Pellets.poser(carte)
	var total: int = Pellets.total_pose(grille)
	var total_alt: int = Pellets.total_pose(Pellets.poser(alt))
	var total_classique: int = Pellets.total_pose(Pellets.poser(classique))
	h.eq(total, 188, "v5.p3: 188 collectibles, comptes et non recopies")
	h.ok(total != total_alt and total != total_classique, "v5.p3: total propre a la carte")
	h.eq(Pellets.tous_atteignables(carte, grille, carte.DEPART_PACMAN), true,
		"v5.p3: tous les collectibles sont atteignables depuis le depart")
	h.eq(Pellets.une_super_par_quadrant(carte, grille), true,
		"v5.p3: une super-pastille par quadrant, comme les deux autres cartes")
	h.eq(Pellets.supers_plus_proches_de_leur_coin(carte, grille), true,
		"v5.p3: chaque super-pastille est plus proche de son coin que de la maison")
	# LE LABYRINTHE EST D'UN SEUL TENANT : aucune poche praticable coupee du reste.
	var praticables: int = 0
	for y in range(carte.HAUTEUR):
		for x in range(carte.LARGEUR):
			if carte.praticable(Vector2i(x, y)):
				praticables += 1
	h.eq(Pellets.cases_atteignables(carte, carte.DEPART_PACMAN).size(), praticables,
		"v5.p3: le labyrinthe est d'un seul tenant")
	# AUCUN CUL-DE-SAC : toute case praticable a au moins DEUX issues.
	h.eq(_culs_de_sac(carte), 0, "v5.p3: 0 cul-de-sac sur la troisieme carte")
	# CONTROLE POSITIF du compteur : il DETECTE une impasse quand il y en a une, sans quoi
	# le zero ci-dessus ne prouverait rien.
	var impasse = MazeClass.depuis_descripteur({
		"id": "impasse", "nom": "impasse",
		"plan": ["#####", "#...#", "###.#", "###.#", "#####"],
	})
	h.gt(_culs_de_sac(impasse), 0, "v5.p3: le compteur detecte bien une impasse")

	# LE BOUCLAGE existe et relie REELLEMENT les deux bords.
	h.ok(carte.LIGNE_TUNNEL != Schema.LIGNE_ABSENTE, "v5.p3: la carte porte une ligne de bouclage")
	h.eq(carte.praticable(carte.boucler(Vector2i(-1, carte.LIGNE_TUNNEL))), true,
		"v5.p3: le bouclage debouche sur une case praticable")

	# --- (3) ELLE EST REELLEMENT SOLVABLE. ---
	var r: Dictionary = Bot.jouer_carte(carte, INDEX_TROISIEME + 1, Bot.BUDGET_DEFAUT,
		Shell.cadence(INDEX_TROISIEME))
	h.eq(r["succeeded"], true, "v5.p3: le bot GAGNE sur la troisieme carte")
	h.eq(r["statut"], State.Statut.GAGNE, "v5.p3: le statut final est GAGNE")
	h.eq(r["consommees"], r["total_pose"], "v5.p3: tous les collectibles sont ramasses")
	h.eq(int(r["total_pose"]), total, "v5.p3: sur le total propre a cette carte")
	h.gt(int(r["ticks"]), 0, "v5.p3: la partie a reellement dure")

	# --- (4) LA DIFFICULTE MONTE, MESUREE. ---
	var cadences: Array = ContentV2.cadences_declarees()
	h.eq(cadences.size(), 3, "v5.p3: une cadence par carte")
	h.eq(ContentV2.cadence(INDEX_TROISIEME), 28, "v5.p3: cadence declaree de la troisieme carte")
	var non_croissantes: int = 0
	for i in range(1, cadences.size()):
		if not (int(cadences[i]) > int(cadences[i - 1])):
			non_croissantes += 1
	h.eq(non_croissantes, 0, "v5.p3: la cadence est STRICTEMENT croissante d'une carte a l'autre")
	h.eq(ContentV2.valeurs_distinctes(cadences), 3, "v5.p3: trois valeurs distinctes, aucune recopiee")
	# Un fantome saute UN tick sur `cadence` : plus la valeur est haute, moins il saute,
	# donc plus il va vite. La montee est donc bien une montee de difficulte.
	h.gt(int(cadences[2]) - 1, int(cadences[1]) - 1, "v5.p3: le fantome saute moins souvent qu'au niveau 2")
	# Seconde grandeur : exposition plus longue que sur la carte 2.
	h.gt(total, total_alt, "v5.p3: plus de collectibles a ramasser que sur la carte 2")

	# --- (5) LA METRIQUE D'ARCHITECTURE V2 TIENT EN PRODUCTION. ---
	# 0 fichier de logique ne nomme une carte, la troisieme comprise : c'est CE comptage
	# qui fait qu'ajouter une carte n'ouvre aucun fichier de 05_SYSTEMS.
	var noms: Array = ["maze_classic", "maze_alt", DOSSIER_TROISIEME]
	h.eq(Purity.fichiers_portant("res://05_SYSTEMS", noms).size(), 0,
		"v5.p3: 0 fichier de logique ne nomme une carte")
	# CONTROLE POSITIF du comptage : les memes noms SONT trouves dans la donnee, sans quoi
	# le zero ci-dessus ne prouverait rien.
	h.eq(FileAccess.file_exists("res://03_WORLD/levels/" + DOSSIER_TROISIEME + "/level.json"), true,
		"v5.p3: le descripteur vit dans la donnee")
	var f := FileAccess.open("res://03_WORLD/rules/level_catalog/catalog.json", FileAccess.READ)
	h.ok(f != null, "v5.p3: le catalogue est lisible")
	h.eq(String(f.get_as_text() if f != null else "").contains(DOSSIER_TROISIEME), true,
		"v5.p3: et c'est le catalogue qui nomme la carte")
	# LE FOURNISSEUR non plus ne la cite pas : la resolution reste generique.
	var g := FileAccess.open("res://06_RUNTIME/adapters/content_provider/content_provider.gd", FileAccess.READ)
	h.ok(g != null, "v5.p3: le fournisseur est lisible")
	h.eq(Purity.code_seul(String(g.get_as_text() if g != null else "")).contains(DOSSIER_TROISIEME), false,
		"v5.p3: le fournisseur ne cite pas la troisieme carte non plus")
