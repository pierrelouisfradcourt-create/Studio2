# v5_p1_mode_named_for_player.gd — CAUSE RACINE P1.
#
# DEFAUT MESURE (playtest Pierre, 2026-08-06) : le NOM AFFICHE du mode de jeu ETAIT
# l'identifiant interne de l'enum — « NORMAL » / « TEST » a l'ecran d'options. Meme classe
# de defaut que le keycode 4194325 corrige en V4 : une valeur de code montree au joueur.
#
# CE QUE CETTE PREUVE MESURE :
# (1) les DEUX vocabulaires coexistent — l'identifiant interne reste la cle du code et du
#     releve de debogage, le LIBELLE est ce que le joueur lit, et ils sont DIFFERENTS ;
# (2) chaque mode porte une EXPLICATION destinee au joueur, non vide, et le nombre de vies
#     qu'elle annonce est CELUI DE LA REGLE, lu dans le bloc de parametres et EGAL au
#     compteur d'une partie neuve (une valeur affichee qui diverge de la regle est un
#     defaut) ;
# (3) l'explication est REELLEMENT LUE : elle apparait sur l'ecran d'options produit —
#     une preuve sans lecteur n'existe pas ;
# (4) LA DIFFERENCE DECLAREE EST LA DIFFERENCE MESUREE. `EFFETS_DE_REGLE` annonce ce que
#     chaque mode change ; la mesure joue la MEME partie dans les deux modes et compare les
#     traces champ par champ. REVISION V6 (decision Pierre du 2026-08-06) : ce bloc
#     mesurait un mode INERTE — 0 divergence sur 200 ticks — et c'est cette mesure qui a
#     motive la decision. La declaration porte desormais UNE grandeur, les vies, et la
#     mesure exige exactement cette divergence-la, ni plus ni moins.
extends RefCounted

const Reglages = preload("res://05_SYSTEMS/settings/settings.gd")
# V6 : le preload du bloc de parametres a disparu avec `VIES_INITIALES`. Le nombre de vies
# se demande a settings, qui detient la correspondance mode -> valeur.
const State = preload("res://05_SYSTEMS/game_state/game_state.gd")
const Loop = preload("res://05_SYSTEMS/game_loop/game_loop.gd")
const Observable = preload("res://05_SYSTEMS/game_state/observable.gd")
const App = preload("res://05_SYSTEMS/app_state/app_state.gd")
const Options = preload("res://06_RUNTIME/adapters/shell_view/options_screen.gd")
const ShellView = preload("res://06_RUNTIME/adapters/shell_view/shell_view.gd")
const Probe = preload("res://06_RUNTIME/adapters/debug_probe/debug_probe.gd")
const Bot = preload("res://06_RUNTIME/adapters/solvability_bot/bot_driver.gd")
const ContentV2 = preload("res://06_RUNTIME/adapters/content_provider/content_provider.gd")
const MazeClass = preload("res://05_SYSTEMS/maze/maze.gd")
var Maze = MazeClass.depuis_descripteur(ContentV2.descripteur(0))


# Releve PRIVE du champ de mode : ce qui reste est exactement « les regles du jeu ».
func _sans_le_mode(releve: Dictionary) -> Dictionary:
	var copie: Dictionary = releve.duplicate(true)
	copie.erase("mode_jeu")
	return copie


func run(h) -> void:
	# --- (1) DEUX VOCABULAIRES, JAMAIS UN SEUL. ---
	h.eq(Reglages.LIBELLES.size(), Reglages.MODES_VALIDES.size(),
		"v5.p1: un libelle par mode du vocabulaire ferme")
	h.eq(Reglages.libelle(Reglages.Mode.NORMAL), "Arcade", "v5.p1: le mode normal se lit Arcade")
	h.eq(Reglages.libelle(Reglages.Mode.TEST), "Decouverte", "v5.p1: le second mode se lit Decouverte")
	h.ok(Reglages.libelle(Reglages.Mode.NORMAL) != Reglages.libelle(Reglages.Mode.TEST),
		"v5.p1: les deux libelles sont distincts")
	h.eq(Reglages.libelle(9), "", "v5.p1: un mode inconnu n'a aucun libelle")
	h.eq(Reglages.libelle(-1), "", "v5.p1: un mode negatif non plus")

	# L'IDENTIFIANT INTERNE est CONSERVE et reste DIFFERENT de ce que lit le joueur.
	h.eq(Reglages.nom(Reglages.Mode.NORMAL), "NORMAL", "v5.p1: l'identifiant interne est conserve")
	h.eq(Reglages.nom(Reglages.Mode.TEST), "TEST", "v5.p1: idem pour le second mode")
	var confusions: int = 0
	for m in Reglages.MODES_VALIDES:
		if Reglages.libelle(m) == Reglages.nom(m):
			confusions += 1
	h.eq(confusions, 0, "v5.p1: 0 mode dont le nom affiche EST l'identifiant interne")

	# --- (2) UNE EXPLICATION PAR MODE, ET SON NOMBRE EST CELUI DE LA REGLE. ---
	# TRIAGE V6 : DECISION_OBSOLETE sur le SYMBOLE. `P.VIES_INITIALES` n'existe plus — le
	# nombre de vies depend du mode (decision Pierre du 2026-08-06). Chaque appel remet
	# desormais la valeur DU MODE dont on parle : la garde est plus serree qu'avant, puisque
	# le nombre remis ne peut plus etre celui d'un autre mode.
	h.eq(Reglages.GABARITS_EXPLICATION.size(), Reglages.MODES_VALIDES.size(),
		"v5.p1: un gabarit d'explication par mode")
	var vides: int = 0
	for m in Reglages.MODES_VALIDES:
		if Reglages.explication(m, Reglages.vies_initiales(m)) == "":
			vides += 1
	h.eq(vides, 0, "v5.p1: 0 mode sans explication")
	h.eq(Reglages.explication(9, Reglages.vies_initiales(9)), "", "v5.p1: un mode inconnu n'explique rien")
	h.ok(Reglages.explication(Reglages.Mode.NORMAL, Reglages.vies_initiales(Reglages.Mode.NORMAL))
		!= Reglages.explication(Reglages.Mode.TEST, Reglages.vies_initiales(Reglages.Mode.TEST)),
		"v5.p1: les deux explications sont distinctes")

	# LE NOMBRE ANNONCE EST CELUI DE LA REGLE : le gabarit ne porte aucun nombre ecrit a la
	# main, et le texte produit porte le compteur d'une partie NEUVE DU MEME MODE.
	var neuve = State.initial(Maze, 1, 0, {"mode": Reglages.Mode.NORMAL})
	var texte_arcade: String = Reglages.explication(
		Reglages.Mode.NORMAL, Reglages.vies_initiales(Reglages.Mode.NORMAL))
	h.ok(texte_arcade.contains(str(neuve.vies)),
		"v5.p1: le texte annonce le nombre de vies de la partie neuve")
	h.eq(neuve.vies, Reglages.vies_initiales(Reglages.Mode.NORMAL),
		"v5.p1: et ce nombre est celui que la regle accorde a ce mode")
	# CONTRE-EPREUVE : le texte SUIT la valeur remise, il n'est pas fige.
	h.ok(Reglages.explication(Reglages.Mode.NORMAL,
		Reglages.vies_initiales(Reglages.Mode.NORMAL) + 1) != texte_arcade,
		"v5.p1: le texte suit la valeur remise, il n'est pas ecrit en dur")

	# --- (3) L'EXPLICATION EST REELLEMENT LUE : elle est sur l'ecran d'options. ---
	# TRIAGE V6 : DECISION_OBSOLETE sur le COMPTE. V5 posait UNE ligne de lecture ; V6 en
	# pose DEUX — l'explication du mode, puis la mention qui separe MODE et DASH. Le compte
	# s'adosse desormais au nombre DECLARE de lignes de lecture, et reste une egalite
	# stricte. L'explication reste a sa place : premiere ligne de lecture.
	var contexte: Dictionary = {"selection": 0, "reglages": Reglages.initial(), "releve": {}}
	var ecran: Dictionary = ShellView.ecran(App.Etat.OPTIONS, contexte)
	h.eq(ecran["lignes"].size(), Options.ENTREES.size() + Options.LIGNES_DE_LECTURE,
		"v5.p1: l'ecran porte ses entrees plus ses lignes de lecture")
	h.eq(String(ecran["lignes"][Options.ENTREES.size()]), texte_arcade,
		"v5.p1: la premiere ligne de lecture EST l'explication du mode courant")
	var ligne_mode: String = Options.ligne(Options.Entree.MODE, Reglages.initial(), 0)
	h.ok(ligne_mode.contains("Arcade"), "v5.p1: la ligne du reglage porte le libelle")
	h.eq(ligne_mode.contains("NORMAL"), false, "v5.p1: elle ne porte plus l'identifiant interne")
	# L'explication SUIT le mode : basculer change le texte lu.
	var bascule: Dictionary = Options.activer(Options.Entree.MODE, Reglages.initial())
	h.ok(Options.explication_du_mode(bascule) != Options.explication_du_mode(Reglages.initial()),
		"v5.p1: l'explication suit le mode courant")
	h.eq(Options.explication_du_mode(bascule),
		Reglages.explication(Reglages.Mode.TEST, Reglages.vies_initiales(Reglages.Mode.TEST)),
		"v5.p1: et c'est bien celle du mode bascule")

	# LE CANAL DE DEBOGAGE, LUI, GARDE L'IDENTIFIANT : les deux surfaces ne se confondent
	# pas — le joueur lit un nom, le lecteur exterieur lit une cle.
	var releve_sonde: Dictionary = Probe.projeter_session(
		{"app": App.Etat.OPTIONS, "partie": null, "reglages": Reglages.initial()})
	h.eq(releve_sonde["mode_jeu"], "NORMAL", "v5.p1: la sonde expose toujours l'identifiant interne")

	# --- (4) LA DIFFERENCE DECLAREE EST LA DIFFERENCE MESUREE. ---
	# TRIAGE V6 : DECISION_OBSOLETE. Ce bloc mesurait, et FIGEAIT, un mode INERTE — « 0
	# divergence sur 200 ticks », qui etait alors la verite. C'est precisement cette mesure
	# qui a fait trancher Pierre : un reglage sans consequence est un producteur sans
	# consommateur. La decision du 2026-08-06 donne au mode UN effet, les vies. La mesure
	# est donc INVERSEE, pas supprimee : meme instrument, meme fenetre, meme comparateur,
	# et la valeur attendue passe de « aucune divergence » a « une divergence, sur la seule
	# grandeur declaree ». Aucune assertion n'est perdue. Le detail de la mesure, avec son
	# controle negatif, vit dans v6_p1_mode_governs_lives.
	h.eq(Reglages.EFFETS_DE_REGLE.size(), Reglages.MODES_VALIDES.size(),
		"v5.p1: une declaration d'effets par mode")
	h.eq(Reglages.effets_de_regle(Reglages.Mode.NORMAL).size(), 1,
		"v5.p1: le mode Arcade declare exactement un effet de regle")
	h.eq(Reglages.effets_de_regle(Reglages.Mode.TEST).size(), 1,
		"v5.p1: le mode Decouverte aussi")
	h.eq(Reglages.effets_de_regle(9).size(), 0, "v5.p1: un mode inconnu ne declare rien")

	# MESURE : la MEME partie, jouee par le MEME bot, dans les deux modes. Hors le champ de
	# mode lui-meme, les traces DIFFERENT — et la seule cle qui differe est celle qui est
	# DECLAREE dans EFFETS_DE_REGLE.
	var a = State.initial(Maze, 7, 0, {"mode": Reglages.Mode.NORMAL})
	var b = State.initial(Maze, 7, 0, {"mode": Reglages.Mode.TEST})
	h.ok(a.mode != b.mode, "v5.p1: les deux parties partent bien dans des modes differents")
	var divergences: int = 0
	var ticks: int = 0
	var cles_divergentes: Array = []
	for _t in range(200):
		if a.statut != State.Statut.EN_COURS:
			break
		a = Loop.step(a, Bot.choisir_action(a))["etat"]
		b = Loop.step(b, Bot.choisir_action(b))["etat"]
		ticks += 1
		var ra: Dictionary = _sans_le_mode(Observable.projeter(a))
		var rb: Dictionary = _sans_le_mode(Observable.projeter(b))
		if ra != rb:
			divergences += 1
		for c in ra.keys():
			if ra[c] != rb[c] and not cles_divergentes.has(c):
				cles_divergentes.append(c)
	cles_divergentes.sort()
	h.eq(ticks, 200, "v5.p1: les deux parties ont tourne 200 ticks")
	h.eq(divergences, 200, "v5.p1: le mode diverge a chaque tick — il n'est plus inerte")
	h.eq(cles_divergentes, Reglages.effets_de_regle(Reglages.Mode.NORMAL),
		"v5.p1: les cles qui divergent sont EXACTEMENT celles qui sont declarees")
	# CONTRE-EPREUVE du comparateur : il DETECTE une difference quand il y en a une.
	var temoin: Dictionary = _sans_le_mode(Observable.projeter(a))
	temoin["score"] = int(temoin["score"]) + 1
	h.ok(temoin != _sans_le_mode(Observable.projeter(a)),
		"v5.p1: le comparateur detecte bien un ecart de regle")
	# LE CHAMP DE MODE, lui, reste distinct : la trace n'est pas comparee a elle-meme.
	h.ok(Observable.projeter(a)["mode_jeu"] != Observable.projeter(b)["mode_jeu"],
		"v5.p1: le mode expose reste different d'une partie a l'autre")
