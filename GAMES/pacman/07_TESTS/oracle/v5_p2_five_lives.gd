# v5_p2_five_lives.gd — CAUSE RACINE P2 du lot V5, REVISEE PAR LE LOT V6.
#
# DECISION V5 (Pierre, playtest du 2026-08-06) : 3 vies -> 5, valeur UNIQUE.
# DECISION V6 (Pierre, meme jour, apres la mesure differentielle du mode) : le nombre de
# vies devient LA GRANDEUR QUE LE MODE GOUVERNE — 3 dans le mode du defi, 5 dans le mode
# de la marge d'erreur. La valeur unique de V5 a donc cesse d'exister.
#
# TRIAGE DE CE FICHIER, AVANT MODIFICATION : DECISION_OBSOLETE sur les assertions qui
# figeaient « une seule valeur, 5, partout » — ce que la nouvelle regle contredit
# explicitement. Elles sont REMPLACEES par les memes gardes rendues fonction du mode,
# jamais supprimees ni assouplies : le compte d'assertions ne baisse pas, et chaque
# egalite reste stricte.
#
# CE QUE CETTE PREUVE MESURE, INCHANGE DANS SON INTENTION :
# (1) la regle est declaree A UN SEUL ENDROIT et tout le reste en decoule ;
# (2) elle vaut pour TOUTES les cartes du catalogue — c'est une regle, pas une propriete
#     de carte ;
# (3) la descente est d'exactement UN cran par perte et la defaite tombe a zero ;
# (4) le nombre AFFICHE — HUD et texte du mode — est CE nombre, jamais un nombre recopie.
extends RefCounted

const P = preload("res://05_SYSTEMS/params/params.gd")
const End = preload("res://05_SYSTEMS/end_conditions/end_conditions.gd")
const State = preload("res://05_SYSTEMS/game_state/game_state.gd")
const Observable = preload("res://05_SYSTEMS/game_state/observable.gd")
const Reglages = preload("res://05_SYSTEMS/settings/settings.gd")
const Hud = preload("res://06_RUNTIME/adapters/presentation/hud.gd")
const Options = preload("res://06_RUNTIME/adapters/shell_view/options_screen.gd")
const Shell = preload("res://06_RUNTIME/adapters/app_shell/app_shell.gd")
const ContentV2 = preload("res://06_RUNTIME/adapters/content_provider/content_provider.gd")

# Mode dont ce fichier suit la valeur historique de cinq vies. Le nommer plutot que
# l'ecrire evite de relire « 5 » comme une constante universelle : c'est la valeur D'UN
# mode, pas celle du jeu.
const MODE_MARGE: int = Reglages.Mode.TEST


func run(h) -> void:
	# --- (1) UNE SEULE DECLARATION, ET TOUT EN DECOULE. ---
	# TRIAGE : DECISION_OBSOLETE (la valeur unique n'existe plus). Remplacee par les DEUX
	# valeurs nommees et la table UNIQUE qui les lie aux modes.
	h.eq(P.VIES_MODE_MARGE, 5, "v5.p2: cinq vies declarees pour le mode de la marge")
	h.eq(Reglages.vies_initiales(MODE_MARGE), P.VIES_MODE_MARGE,
		"v5.p2: la table de correspondance en decoule, elle ne le recopie pas")

	# --- (2) C'EST UNE REGLE, PAS UNE PROPRIETE DE CARTE : la valeur vaut sur CHAQUE carte
	# du catalogue, celle qui vient d'etre ajoutee comprise.
	var ecarts: int = 0
	for i in range(ContentV2.nb_niveaux()):
		var jeu_i = State.initial(Shell.carte(i), i + 1, Shell.cadence(i), {"mode": MODE_MARGE})
		if jeu_i.vies != P.VIES_MODE_MARGE:
			ecarts += 1
	h.gt(ContentV2.nb_niveaux(), 2, "v5.p2: la mesure porte sur plus de deux cartes")
	h.eq(ecarts, 0, "v5.p2: 0 carte ou la partie neuve ne part pas avec les vies declarees")

	# --- (3) UN CRAN PAR PERTE, ET LA DEFAITE TOMBE A ZERO. ---
	var jeu = State.initial(Shell.carte(0), 1, Shell.cadence(0), {"mode": MODE_MARGE})
	h.eq(jeu.vies, 5, "v5.p2: la partie neuve porte cinq vies dans ce mode")
	var mauvais_crans: int = 0
	var defaites_prematurees: int = 0
	for _pas in range(P.VIES_MODE_MARGE):
		var avant: int = jeu.vies
		if End.defaite(jeu.vies):
			defaites_prematurees += 1
		End.perdre_une_vie(jeu)
		if jeu.vies != avant - 1:
			mauvais_crans += 1
	h.eq(mauvais_crans, 0, "v5.p2: 0 perte qui ne retire pas exactement une vie")
	h.eq(defaites_prematurees, 0, "v5.p2: aucune defaite declaree avant zero")
	h.eq(jeu.vies, 0, "v5.p2: cinq pertes menent a zero")
	h.eq(End.defaite(jeu.vies), true, "v5.p2: et la defaite est declaree a zero")
	h.eq(End.defaite(1), false, "v5.p2: elle ne l'est pas a une vie")

	# LE DOMAINE SUIT LA REGLE : la borne haute de validite est la plus grande valeur qu'un
	# mode puisse accorder. TRIAGE : DECISION_OBSOLETE — V5 bornait par la valeur unique,
	# qui n'existe plus ; la borne est desormais derivee de la table, et le refus est
	# exerce au meme endroit, d'une unite au-dessus.
	var neuf = State.initial(Shell.carte(0), 1, Shell.cadence(0), {"mode": MODE_MARGE})
	h.eq(neuf.est_valide(), true, "v5.p2: une partie neuve a cinq vies est valide")
	neuf.vies = Reglages.vies_maximales() + 1
	h.eq(neuf.est_valide(), false, "v5.p2: une vie de plus que la regle est refusee")
	neuf.vies = Reglages.vies_maximales()
	h.eq(neuf.est_valide(), true, "v5.p2: la valeur declaree elle-meme reste valide")

	# --- (4) LE NOMBRE AFFICHE EST CE NOMBRE. ---
	var releve: Dictionary = Observable.projeter(
		State.initial(Shell.carte(0), 1, Shell.cadence(0), {"mode": MODE_MARGE}))
	h.eq(int(releve["vies"]), P.VIES_MODE_MARGE, "v5.p2: le releve observable porte la valeur declaree")
	h.eq(Hud.relire(Hud.ligne(releve), Hud.ETIQUETTE_VIES), P.VIES_MODE_MARGE,
		"v5.p2: le HUD affiche la valeur declaree, relue en chiffres")
	# LIEN P1/P2 : le texte du mode de jeu annonce le VRAI nombre de vies DE CE MODE.
	var texte: String = Options.explication_du_mode({"mode": MODE_MARGE})
	h.ok(texte.contains(str(P.VIES_MODE_MARGE)),
		"v5.p2: le texte du mode annonce le nombre de vies de la regle")
	# TRIAGE : DECISION_OBSOLETE. V5 exigeait que plus AUCUN texte n'annonce « 3 vies »,
	# parce que 3 etait l'ancienne valeur abandonnee. En V6, 3 est la valeur COURANTE d'un
	# autre mode : l'interdit se deplace donc sur la confusion entre les deux modes — le
	# texte de la marge ne doit pas annoncer le nombre du defi.
	h.eq(texte.contains(str(P.VIES_MODE_DEFI) + " vies"), false,
		"v5.p2: il n'annonce pas le nombre de vies de l'autre mode")
