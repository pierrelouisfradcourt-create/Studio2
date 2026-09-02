# v4_p3_ghost_behaviour_transmitted.gd — CAUSE RACINE P3.
#
# DEFAUT MESURE (playtest Pierre) : le comportement des fantomes n'etait pas transmis.
# CE N'EST PAS UN BUG DE CODE : les quatre ciblages existent reellement dans
# 05_SYSTEMS/ghost_targeting/ghost_targeting.gd et sont prouves depuis V1. L'information
# etait PRODUITE et jamais DITE. La correction appartient donc a la presentation.
#
# REGLE DE VERITE APPLIQUEE : la description ne dit QUE ce que `cible_poursuite()` fait.
# Chaque phrase est confrontee ici a un APPEL REEL de la fonction — le code fait foi, pas
# le Pac-Man d'arcade. Un guide qui recopierait les valeurs pourrait deriver sans qu'aucune
# mesure ne le voie ; celui-ci les tient de la source, et la preuve le verifie.
extends RefCounted

const Guide = preload("res://06_RUNTIME/adapters/presentation/ghost_guide.gd")
const Targeting = preload("res://05_SYSTEMS/ghost_targeting/ghost_targeting.gd")
const ShellView = preload("res://06_RUNTIME/adapters/shell_view/shell_view.gd")
const Controles = preload("res://06_RUNTIME/adapters/shell_view/controls_screen.gd")
const Shell = preload("res://06_RUNTIME/adapters/app_shell/app_shell.gd")
const Palette = preload("res://06_RUNTIME/adapters/palette/palette.gd")
const App = preload("res://05_SYSTEMS/app_state/app_state.gd")
const Maze = preload("res://05_SYSTEMS/maze/maze.gd")


func run(h) -> void:
	# --- LES QUATRE COMPORTEMENTS SONT TRANSMIS, ET DEUX A DEUX DIFFERENTS. ---
	h.eq(Guide.fantomes_sans_description(), 0, "v4.p3: 0 fantome sans comportement transmis")
	h.eq(Guide.paires_identiques(), 0, "v4.p3: 0 paire de descriptions identiques")
	h.eq(Guide.lignes().size(), Targeting.NOMBRE_FANTOMES + 1,
		"v4.p3: une ligne par fantome, plus la mention de dispersion")
	h.eq(Guide.nom(-1), "", "v4.p3: un index hors bornes n'a pas de nom")
	h.eq(Guide.comportement(99), "", "v4.p3: ni de comportement")
	h.eq(Guide.ligne(99), "", "v4.p3: ni de ligne")

	# --- CHAQUE PHRASE EST CONFRONTEE AU CODE. C'est le coeur de cette preuve. ---
	var carte = Shell.carte(0)
	h.ok(carte != null, "v4.p3: une carte validee sert de reference")
	var pac := Vector2i(10, 10)
	var dir: Vector2i = Maze.DROITE
	var fantomes: Array = [Vector2i(3, 3), Vector2i(4, 4), Vector2i(5, 5), Vector2i(6, 6)]

	# ROUGE : poursuite DIRECTE — la cible EST la case de Pac-Man, a l'egalite stricte.
	h.eq(Targeting.cible_poursuite(carte, Targeting.ROUGE, pac, dir, fantomes), pac,
		"v4.p3: le rouge vise exactement la case de Pac-Man")
	h.eq(Guide.avance(Targeting.ROUGE), 0, "v4.p3: le rouge ne regarde pas devant")
	h.ok(Guide.comportement(Targeting.ROUGE).contains("directe"),
		"v4.p3: et sa phrase dit poursuite directe")

	# ROSE : AVANCE_ROSE cases devant. La phrase porte le nombre, et le nombre est le bon.
	h.eq(Targeting.cible_poursuite(carte, Targeting.ROSE, pac, dir, fantomes),
		pac + dir * Targeting.AVANCE_ROSE, "v4.p3: le rose vise AVANCE_ROSE cases devant")
	h.eq(Guide.avance(Targeting.ROSE), Targeting.AVANCE_ROSE, "v4.p3: le guide tient l'avance de la source")
	h.ok(Guide.comportement(Targeting.ROSE).contains(str(Targeting.AVANCE_ROSE)),
		"v4.p3: sa phrase porte la valeur reelle de l'avance")

	# CYAN : PIVOT a AVANCE_CYAN cases devant, double depuis le rouge.
	var pivot: Vector2i = pac + dir * Targeting.AVANCE_CYAN
	h.eq(Targeting.cible_poursuite(carte, Targeting.CYAN, pac, dir, fantomes),
		pivot * 2 - fantomes[Targeting.ROUGE], "v4.p3: le cyan double le pivot depuis le rouge")
	h.eq(Guide.avance(Targeting.CYAN), Targeting.AVANCE_CYAN, "v4.p3: le guide tient le pivot de la source")
	h.ok(Guide.comportement(Targeting.CYAN).contains(str(Targeting.AVANCE_CYAN)),
		"v4.p3: sa phrase porte la valeur reelle du pivot")
	h.ok(Guide.comportement(Targeting.CYAN).contains("rouge"),
		"v4.p3: et nomme le fantome dont il depend")

	# ORANGE : bascule au SEUIL. Les deux cotes du seuil sont eprouves, pas seulement un.
	var loin: Array = [Vector2i(3, 3), Vector2i(4, 4), Vector2i(5, 5),
		pac + Vector2i(Targeting.SEUIL_ORANGE + 1, 0)]
	var pres: Array = [Vector2i(3, 3), Vector2i(4, 4), Vector2i(5, 5),
		pac + Vector2i(Targeting.SEUIL_ORANGE, 0)]
	h.eq(Targeting.cible_poursuite(carte, Targeting.ORANGE, pac, dir, loin), pac,
		"v4.p3: au-dela du seuil, l'orange poursuit Pac-Man")
	h.eq(Targeting.cible_poursuite(carte, Targeting.ORANGE, pac, dir, pres),
		Targeting.cible_dispersion(carte, Targeting.ORANGE),
		"v4.p3: au seuil exactement, il rentre a son coin")
	h.eq(Guide.seuil(Targeting.ORANGE), Targeting.SEUIL_ORANGE, "v4.p3: le guide tient le seuil de la source")
	h.eq(Guide.seuil(Targeting.ROUGE), 0, "v4.p3: les autres n'ont pas de seuil")
	h.ok(Guide.comportement(Targeting.ORANGE).contains(str(Targeting.SEUIL_ORANGE)),
		"v4.p3: sa phrase porte la valeur reelle du seuil")
	h.ok(Guide.comportement(Targeting.ORANGE).contains("coin"),
		"v4.p3: et nomme le repli au coin")

	# LA DISPERSION est transmise elle aussi, et elle correspond au code : quatre coins
	# DEUX A DEUX DIFFERENTS, lus sur la carte.
	var coins: Array = []
	for i in range(Targeting.NOMBRE_FANTOMES):
		var c: Vector2i = Targeting.cible_dispersion(carte, i)
		if not coins.has(c):
			coins.append(c)
	h.eq(coins.size(), Targeting.NOMBRE_FANTOMES, "v4.p3: quatre coins de dispersion distincts")
	h.ok(Guide.PHRASE_DISPERSION.contains("coin"), "v4.p3: la mention de dispersion le dit")

	# LE GUIDE NOMME LES TEINTES QUE LE JOUEUR VOIT — il n'en declare aucune.
	h.eq(Guide.couleur(Targeting.ROUGE), Palette.FANTOMES[Targeting.ROUGE],
		"v4.p3: la teinte vient du descripteur de palette")
	h.eq(Palette.fantomes_distincts(), true, "v4.p3: les quatre teintes restent distinctes")

	# --- ET C'EST REELLEMENT AFFICHE : l'ecran de consultation le porte. ---
	var contexte: Dictionary = {"selection": 0, "reglages": {}, "releve": {}}
	var ecran: Dictionary = ShellView.ecran(App.Etat.CONTROLES, contexte)
	var texte: String = ShellView.signature(ecran)
	h.ok(texte.contains(Guide.TITRE), "v4.p3: l'ecran de consultation porte la section fantomes")
	var absents: int = 0
	for i in range(Targeting.NOMBRE_FANTOMES):
		if not texte.contains(Guide.ligne(i)):
			absents += 1
	h.eq(absents, 0, "v4.p3: les quatre lignes y sont reellement affichees")
	# L'ECRAN DE CONTROLES N'A RIEN PERDU : les huit intentions y sont toujours.
	h.eq(Controles.lignes().size(), Controles.LIBELLES.size(),
		"v4.p3: l'enumeration des controles est intacte")
	h.eq(Controles.lignes_portant_un_code_brut(), 0, "v4.p3: et toujours sans code brut")
	h.eq(ShellView.paires_identiques(contexte), 0, "v4.p3: aucun ecran n'en double un autre")
	h.eq(ShellView.couleurs_hors_palette(ecran), 0, "v4.p3: 0 couleur hors palette sur cet ecran")
