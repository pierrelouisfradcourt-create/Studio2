# run_tests.gd — POINT D'ENTREE MECANIQUE au chemin EXIGE par l'oracle maitre
# (ligne core.main_loop, categorie godot.project_tests -> tests/{id} dans repo_map.yaml).
# scripts/forge/godot_oracle.mjs charge `res://tests/run_tests.gd` en headless et exige
# un code de retour 0.
#
# ENUMERE et execute DEUX dossiers :
#   res://07_TESTS/unit    (*.test.gd)   — assertions unitaires
#   res://07_TESTS/oracle  (*.gd)        — points de controle et harnais de preuve
# Un fichier de preuve qu'aucun executeur ne lance n'existe pas dans la chaine qualite :
# les deux dossiers sont donc parcourus par CE harnais, jamais laisses dormants.
#
# GARDE ANTI-FAUX-VERT `EXPECTED_ASSERTS` (patron chess_tcg / snake) : si un coeur ne
# compile pas, ses tests ne s'executent pas et le total tombe — sans cette garde, le
# harnais sortirait vert en silence. La valeur est une MESURE, pas une intention.
extends SceneTree

# Compteur d'assertions partage. Classe interne : la wiremap gelee ne declare aucun
# fichier d'aide au harnais, et un fichier hors carte ne s'improvise pas.
class Harness extends RefCounted:
	var passed: int = 0
	var failed: int = 0
	var fails: Array = []

	func ok(cond: bool, nom: String) -> void:
		if cond:
			passed += 1
		else:
			failed += 1
			fails.append(nom)

	# Egalite STRICTE (jamais un >=). Trace la valeur observee en cas d'echec.
	func eq(a, b, nom: String) -> void:
		if a == b:
			passed += 1
		else:
			failed += 1
			fails.append("%s (attendu %s, obtenu %s)" % [nom, str(b), str(a)])

	# Inegalite STRICTE, nommee pour interdire le glissement vers un >= tautologique.
	func lt(a: int, b: int, nom: String) -> void:
		if a < b:
			passed += 1
		else:
			failed += 1
			fails.append("%s (attendu %s < %s)" % [nom, str(a), str(b)])

	func gt(a: int, b: int, nom: String) -> void:
		if a > b:
			passed += 1
		else:
			failed += 1
			fails.append("%s (attendu %s > %s)" % [nom, str(a), str(b)])

# Total d'assertions attendu — MESURE REELLE de ce depot le 2026-08-05 : 150 fichiers de
# preuve, 2212 assertions. Valeur RELEVEE d'une execution, jamais anticipee : si un coeur
# cesse de compiler, ses assertions ne s'executent plus, le total tombe et le harnais
# echoue au lieu de sortir vert en silence.
#
# HISTORIQUE V1 : 966 au premier vert, puis 1012 apres le gate de mutation (150 mutants,
# 16 survivants). 46 assertions ont ete ajoutees pour tuer 14 des 16 survivants —
# frontieres de maze.dans_grille / maze.dans_labyrinthe, branches negatives des deux
# verificateurs d'invariants de carte, trois refus de game_state.est_valide, et le tick
# de bascule a l'expiration de la fenetre Effraye. Les 2 restants sont tries equivalents
# dans games/pacman/mutation_triage.json.
#
# V2 : 65 fichiers de preuve V1 CONSERVES (1012 assertions, aucune supprimee) + 85
# fichiers V2, un par ligne de lab/forge_runs/pacman/wiremap_v2.json. Le total passe a
# 2212. La garde vaut dans les DEUX sens : un total inferieur signale un coeur qui ne
# compile plus, un total superieur un fichier de preuve ajoute hors carte.
# V3 (finition produit, 2026-08-06) : 150 fichiers de preuve V1+V2 CONSERVES, aucune
# assertion supprimee, et 6 fichiers ajoutes — UN PAR CAUSE RACINE mesuree au playtest
# (P1 touches illisibles, P2 direction artistique, P3 musique, P4 enveloppe des cartes,
# P5 fin de partie bloquee, P6 reglage de volume). Deux comptes existants ont ete
# RELEVES et non contournes : la palette passe de 18 a 26 entrees nommees, les reglages
# de 2 a 5. Le total passe de 2212 a 2389. VALEUR MESUREE, jamais anticipee.
# V4 (correction playtest, 2026-08-06) : 156 fichiers de preuve V1+V2+V3 CONSERVES, aucune
# assertion supprimee, et 4 fichiers ajoutes — UN PAR CAUSE RACINE mesuree au playtest
# (P1 aucun son, P2 ecran de fin illisible, P3 comportement des fantomes non transmis,
# P4 progression inconnue). UN compte existant a ete RELEVE et non contourne : la palette
# passe de 26 a 27 entrees nommees (FOND_MODAL, le voile de l'ecran de fin). Le total
# passe de 2389 a 2515. VALEUR MESUREE d'une execution, jamais anticipee.
# V5 (cloture avant gel, 2026-08-06) : 160 fichiers de preuve V1+V2+V3+V4 CONSERVES,
# aucune assertion supprimee, et 3 fichiers ajoutes — UN PAR POINT du lot de cloture
# (P1 mode de jeu nomme pour le joueur, P2 cinq vies, P3 troisieme carte). Des comptes
# existants ont ete RELEVES et non contournes, chacun trie AVANT modification :
# COUNT_FROZEN pour les cinq assertions qui figeaient la valeur 3 des vies
# (v2_params_rules_only, state_initial_from_seed, end_life_loss, core_boot,
# render_hud_numbers), DECISION_OBSOLETE pour les deux assertions de l'ecran d'options
# qui figeaient l'affichage de l'identifiant interne et le compte de lignes. Aucune
# assertion n'a ete affaiblie. Le total passe de 2515 a 2612. VALEUR MESUREE d'une
# execution, jamais anticipee.
# V6 (lot de validation, 2026-08-06) : 163 fichiers de preuve V1..V5 CONSERVES, aucune
# assertion supprimee, et 3 fichiers ajoutes — UN PAR POINT du lot (P1 le mode gouverne les
# vies, P2 source unique et coherence, P3 clin d'oeil de victoire sans aide). Le lot change
# la NATURE d'une regle : « les vies sont une valeur » devient « les vies sont une fonction
# du mode ». Chaque assertion existante portant un nombre de vies a donc ete TRIEE AVANT
# MODIFICATION, et le triage est ecrit a cote d'elle :
#   COUNT_FROZEN      — state_initial_from_seed, core_boot, render_hud_numbers (5 -> 3, la
#                       partie neuve sans reglages part dans le mode par defaut) ;
#                       end_life_loss (descente jouee dans le mode qui donne le plus, plus
#                       une seconde descente complete dans le mode du defi : +4 assertions) ;
#   DECISION_OBSOLETE — v2_params_rules_only et v5_p2 (la valeur unique n'existe plus) ;
#                       core_error_guard et v2_end_respawn (le symbole `End.VIES_INITIALES`
#                       a disparu, la borne est celle du mode ou le maximum derive) ;
#                       v5_p1 section 4 (elle FIGEAIT un mode inerte — c'est la mesure qui a
#                       motive la decision ; la valeur attendue est inversee, pas retiree) ;
#                       v2_shell_options_screen et v5_p1 section 3 (une seconde ligne de
#                       lecture separe MODE et DASH).
# Aucune assertion n'a ete affaiblie ; aucune n'a ete supprimee. Le total passe de 2612 a
# 2740. VALEUR MESUREE d'une execution, jamais anticipee.
const EXPECTED_ASSERTS := 2740

const DOSSIERS: Array = [
	["res://07_TESTS/unit", ".test.gd"],
	["res://07_TESTS/oracle", ".gd"],
]


# ARBRE VIVANT EXIGE (V4, cause racine P1). Les preuves tournaient dans `_initialize()`,
# ou `root.is_inside_tree()` vaut FAUX : le moteur y refuse `play()` (« Playback can only
# happen when a node is inside the scene tree », mesure de ce poste le 2026-08-06). Aucun
# chemin de lecture audio reel n'y etait donc verifiable — seule la synthese l'etait, ce
# qui est exactement la panne que V4 corrige. Les preuves sont donc executees a la
# PREMIERE TRAME, ou l'arbre est vivant. Aucune assertion n'est modifiee par ce
# deplacement : il ouvre une capacite, il n'en relache aucune.
func _process(_delta: float) -> bool:
	_executer()
	return true


func _executer() -> void:
	var h := Harness.new()
	var executes: int = 0
	for entree in DOSSIERS:
		var dossier: String = entree[0]
		var suffixe: String = entree[1]
		var da := DirAccess.open(dossier)
		if da == null:
			h.failed += 1
			h.fails.append("DOSSIER: %s introuvable" % dossier)
			continue
		var fichiers: Array = []
		da.list_dir_begin()
		var nom := da.get_next()
		while nom != "":
			if not da.current_is_dir() and nom.ends_with(suffixe):
				fichiers.append(nom)
			nom = da.get_next()
		da.list_dir_end()
		fichiers.sort()  # ordre deterministe, jamais dependant du systeme de fichiers
		for f in fichiers:
			var chemin: String = dossier + "/" + f
			var script = load(chemin)
			if script == null or not (script is GDScript) or not script.can_instantiate():
				h.failed += 1
				h.fails.append("CHARGEMENT: %s introuvable/illisible/non compilable" % chemin)
				continue
			var inst = script.new()
			if not inst.has_method("run"):
				h.failed += 1
				h.fails.append("CONTRAT: %s n'expose pas run(h)" % chemin)
				continue
			inst.run(h)
			executes += 1

	var total: int = h.passed + h.failed
	if total != EXPECTED_ASSERTS:
		h.failed += 1
		h.fails.append("META: %d/%d assertions executees (coeur non charge ? test manquant ?)"
			% [total, EXPECTED_ASSERTS])

	print("\n=== RESULT: %d passed, %d failed (fichiers: %d) ===" % [h.passed, h.failed, executes])
	for x in h.fails:
		print("  FAIL: ", x)
	quit(0 if h.failed == 0 else 1)
