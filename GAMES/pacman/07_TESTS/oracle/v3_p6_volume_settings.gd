# v3_p6_volume_settings.gd — CAUSE RACINE P6.
#
# DEFAUT MESURE (playtest Pierre) : aucun reglage de volume. Le champ `volume` existait,
# mais PAR SON — six descripteurs dans sound_bank.gd — donc reglable par personne. Ce
# qui manquait est un reglage GLOBAL (musique / effets / muet), consomme par audio.gd et
# persistant.
#
# CE QUE CETTE PREUVE MESURE : (1) le vocabulaire du volume est ferme et chaque rang a un
# effet observable ; (2) le reglage GOUVERNE reellement l'amplitude synthetisee — sinon
# ce serait un cadran debranche ; (3) il PERSISTE et se relit ; (4) la persistance ne
# contamine PAS la valeur du premier lancement, qui reste CONSTRUITE dans la logique pure.
extends RefCounted

const Reglages = preload("res://05_SYSTEMS/settings/settings.gd")
const Options = preload("res://06_RUNTIME/adapters/shell_view/options_screen.gd")
const Audio = preload("res://06_RUNTIME/adapters/audio/audio.gd")
const Bank = preload("res://06_RUNTIME/adapters/sound_bank/sound_bank.gd")
const Shell = preload("res://06_RUNTIME/adapters/app_shell/app_shell.gd")
const App = preload("res://05_SYSTEMS/app_state/app_state.gd")
const Intents = preload("res://05_SYSTEMS/input_intents/input_intents.gd")
const Purity = preload("res://06_RUNTIME/adapters/proof_harness/harness_purity_counts.gd")


func run(h) -> void:
	# --- VOCABULAIRE FERME ET ECHELLE MONOTONE. ---
	h.eq(Reglages.CANAUX.size(), 2, "v3.p6: deux canaux declares")
	h.eq(Reglages.GAINS.size(), Reglages.NIVEAU_MAX - Reglages.NIVEAU_MIN + 1,
		"v3.p6: un gain par rang de l'echelle")
	var monotone: int = 0
	for n in range(Reglages.NIVEAU_MIN, Reglages.NIVEAU_MAX):
		if Reglages.gain(n) >= Reglages.gain(n + 1):
			monotone += 1
	h.eq(monotone, 0, "v3.p6: l'echelle est strictement croissante, aucun rang indiscernable")
	h.eq(Reglages.gain(Reglages.NIVEAU_MIN), 0.0, "v3.p6: le rang le plus bas coupe le son")
	h.eq(Reglages.gain(Reglages.NIVEAU_MAX), 1.0, "v3.p6: le rang le plus haut ne l'attenue pas")
	h.eq(Reglages.gain(Reglages.NIVEAU_MAX + 1), 1.0,
		"v3.p6: un rang hors echelle ne coupe pas le son sans qu'on l'ait demande")
	h.eq(Reglages.niveau_valide(-1), false, "v3.p6: un rang negatif est refuse")
	h.eq(Reglages.canal_valide(9), false, "v3.p6: un canal inconnu est refuse")
	h.eq(Reglages.cle_canal(9), "", "v3.p6: un canal inconnu n'a aucune cle")
	h.eq(Reglages.nom_canal(Reglages.Canal.MUSIQUE), "MUSIQUE", "v3.p6: le canal musique est nomme")

	# LE PARCOURS BOUCLE : chaque activation change la valeur, aucune position bloquante.
	h.eq(Reglages.volume_suivant(Reglages.NIVEAU_MAX), Reglages.NIVEAU_MIN, "v3.p6: le reglage boucle")
	var vus: Array = []
	var n_courant: int = Reglages.NIVEAU_MIN
	for _i in range(Reglages.GAINS.size()):
		vus.append(n_courant)
		n_courant = Reglages.volume_suivant(n_courant)
	h.eq(vus.size(), Reglages.GAINS.size(), "v3.p6: le parcours atteint tous les rangs")
	h.eq(n_courant, Reglages.NIVEAU_MIN, "v3.p6: et revient a son point de depart")

	# LE COUPE-SON L'EMPORTE sur les deux rangs — une seule regle de priorite.
	var plein: Dictionary = Reglages.avec_volume(
		Reglages.avec_volume({}, Reglages.Canal.MUSIQUE, Reglages.NIVEAU_MAX),
		Reglages.Canal.EFFETS, Reglages.NIVEAU_MAX)
	h.eq(Reglages.gain_effectif(plein, Reglages.Canal.EFFETS), 1.0, "v3.p6: son plein sans coupe-son")
	var muet: Dictionary = Reglages.avec_muet(plein, true)
	h.eq(Reglages.gain_effectif(muet, Reglages.Canal.EFFETS), 0.0, "v3.p6: le coupe-son coupe les effets")
	h.eq(Reglages.gain_effectif(muet, Reglages.Canal.MUSIQUE), 0.0, "v3.p6: et la musique aussi")
	h.eq(Reglages.gain_effectif(plein, 9), 0.0, "v3.p6: un canal inconnu ne produit aucun gain")

	# LES DEUX CONDITIONS D'INSTALLATION D'UN VOLUME sont exercees SEPAREMENT : canal
	# valide mais rang hors echelle, puis canal inconnu mais rang valide. Sans ces deux
	# cas, une conjonction relachee en disjonction passerait inapercue — le rang serait
	# installe sur un canal inexistant, ou une valeur hors echelle serait retenue.
	var defauts: Dictionary = Reglages.normaliser({})
	h.eq(Reglages.avec_volume({}, Reglages.Canal.MUSIQUE, Reglages.NIVEAU_MAX + 5), defauts,
		"v3.p6: un rang hors echelle ne s'installe pas, meme sur un canal valide")
	h.eq(Reglages.avec_volume({}, 9, 2), defauts,
		"v3.p6: un canal inconnu n'installe rien, meme avec un rang valide")
	h.eq(Reglages.avec_volume({}, 9, 2).size(), defauts.size(),
		"v3.p6: un canal inconnu ne cree aucune cle de reglage")

	# --- LE REGLAGE GOUVERNE REELLEMENT LE SIGNAL (cadran branche, pas decoratif). ---
	Audio.reinitialiser()
	var desc: Dictionary = Bank.descripteur("son_collecte")
	var fort: PackedFloat32Array = Audio.echantillons(desc, Reglages.gain(Reglages.NIVEAU_MAX))
	var moitie: PackedFloat32Array = Audio.echantillons(desc, Reglages.gain(2))
	var nul: PackedFloat32Array = Audio.echantillons(desc, Reglages.gain(Reglages.NIVEAU_MIN))
	h.gt(int(Audio.amplitude_max(fort) * 1000.0), int(Audio.amplitude_max(moitie) * 1000.0),
		"v3.p6: baisser le volume baisse l'amplitude")
	h.eq(int(Audio.amplitude_max(nul) * 1000.0), 0, "v3.p6: le rang nul rend le silence")
	h.eq(fort.size(), nul.size(), "v3.p6: le volume ne change pas la duree du son")
	# LA MESURE PASSE PAR LE CHEMIN PUBLIC : `jouer` consomme les reglages, pas seulement
	# `echantillons`. Sans cela le reglage serait branche sur une fonction que personne
	# n'appelle.
	var joue_fort: Dictionary = Audio.jouer("son_collecte", 1, plein)
	var joue_muet: Dictionary = Audio.jouer("son_collecte", 2, muet)
	h.gt(int(float(joue_fort["amplitude"]) * 1000.0), 0, "v3.p6: le son joue porte du signal")
	h.eq(int(float(joue_muet["amplitude"]) * 1000.0), 0, "v3.p6: coupe-son actif, le son joue est muet")
	h.eq(int(joue_muet["echantillons"]), int(joue_fort["echantillons"]),
		"v3.p6: le coupe-son ne supprime pas le declenchement, il l'attenue")
	Audio.reinitialiser()

	# --- L'ECRAN D'OPTIONS EXPOSE LES TROIS REGLAGES, chacun avec un effet. ---
	h.eq(Options.ENTREES.size(), 5, "v3.p6: cinq reglages exposes")
	h.eq(Options.entrees_sans_effet({}), 0, "v3.p6: 0 entree sans effet")
	var r0: Dictionary = Reglages.initial()
	var apres: Dictionary = Options.activer(Options.Entree.VOLUME_MUSIQUE, r0)
	h.ok(apres[Reglages.CLE_MUSIQUE] != r0[Reglages.CLE_MUSIQUE], "v3.p6: le volume musique change")
	h.ok(Options.activer(Options.Entree.MUET, r0)["muet"] != r0["muet"], "v3.p6: le coupe-son bascule")
	h.eq(Options.canal_de_l_entree(Options.Entree.MODE), Options.AUCUN_CANAL,
		"v3.p6: une entree qui n'est pas un volume n'a aucun canal")
	# LA JAUGE est LISIBLE et varie avec le rang : un nombre nu se lirait comme un code.
	h.ok(Options.jauge(Reglages.NIVEAU_MIN) != Options.jauge(Reglages.NIVEAU_MAX),
		"v3.p6: la jauge distingue les rangs")
	h.eq(Options.jauge(Reglages.NIVEAU_MAX).length(), Reglages.GAINS.size(),
		"v3.p6: la jauge a une longueur constante")
	h.eq(Options.valeur_lisible(Options.Entree.VOLUME_EFFETS, r0),
		Options.jauge(Reglages.VOLUME_EFFETS_PAR_DEFAUT), "v3.p6: la valeur affichee suit le reglage")

	# LE CHEMIN PUBLIC : depuis l'ecran d'options, Valider modifie reellement la session.
	var sess: Dictionary = Shell.session_initiale()
	sess["app"] = App.Etat.OPTIONS
	sess["selection"] = Options.Entree.MUET
	var apres_intention: Dictionary = Shell.appliquer_intention(sess, Intents.Intention.VALIDER)
	h.ok(apres_intention["session"]["reglages"]["muet"] != sess["reglages"]["muet"],
		"v3.p6: le coupe-son est atteignable par le seul canal d'entree public")

	# --- PERSISTANCE : elle existe, elle relit, et elle ne contamine pas le defaut. ---
	# LA LOGIQUE PURE RESTE PURE : c'est ce comptage qui garantit que la valeur du premier
	# lancement est CONSTRUITE, jamais heritee d'un fichier.
	h.eq(Purity.entree_dans_logique().size(), 0, "v3.p6: la logique ignore toujours les peripheriques")
	h.eq(Purity.audio_dans_logique().size(), 0, "v3.p6: la logique ignore toujours l'audio")
	var f := FileAccess.open("res://05_SYSTEMS/settings/settings.gd", FileAccess.READ)
	var texte: String = f.get_as_text() if f != null else ""
	h.eq(texte.contains("FileAccess"), false, "v3.p6: settings ne lit aucun fichier")
	h.eq(texte.contains("user://"), false, "v3.p6: settings ne connait aucun etat persistant")

	# ETAT DE DEPART RESTAURE EN FIN DE PREUVE : cette preuve ne laisse aucune trace au
	# suivant. Un test qui laisse un fichier derriere lui rend le harnais dependant de
	# son ordre d'execution.
	var avant: Dictionary = Options.charger_brut()
	var existait: bool = Options.existe_une_sauvegarde()

	var a_ecrire: Dictionary = Reglages.avec_muet(
		Reglages.avec_volume(Reglages.initial(), Reglages.Canal.MUSIQUE, Reglages.NIVEAU_MIN), true)
	h.eq(Options.sauvegarder(a_ecrire), true, "v3.p6: les reglages s'ecrivent")
	h.eq(Options.existe_une_sauvegarde(), true, "v3.p6: la sauvegarde existe")
	var relu: Dictionary = Options.charger()
	h.eq(relu[Reglages.CLE_MUSIQUE], Reglages.NIVEAU_MIN, "v3.p6: le volume relu est celui ecrit")
	h.eq(relu["muet"], true, "v3.p6: le coupe-son relu est celui ecrit")
	h.eq(relu, Reglages.normaliser(a_ecrire), "v3.p6: aller-retour complet sans perte")

	# LE DEFAUT DU PREMIER LANCEMENT N'EST PAS CONTAMINE : la logique pure ignore le
	# fichier, meme quand il existe et contredit les defauts.
	h.eq(Reglages.initial()["muet"], Reglages.MUET_PAR_DEFAUT,
		"v3.p6: le defaut construit ignore la sauvegarde")
	h.eq(Shell.session_initiale()["reglages"]["muet"], Reglages.MUET_PAR_DEFAUT,
		"v3.p6: la session d'amorcage aussi")

	# UNE SAUVEGARDE ABSENTE OU ILLISIBLE retombe sur les defauts, sans exception.
	h.eq(Options.oublier()["efface"], true, "v3.p6: la sauvegarde s'efface")
	h.eq(Options.existe_une_sauvegarde(), false, "v3.p6: elle n'existe plus")
	h.eq(Options.charger_brut(), {}, "v3.p6: sans fichier, aucun reglage brut")
	h.eq(Options.charger(), Reglages.initial(), "v3.p6: sans fichier, les defauts declares")
	h.eq(Options.oublier()["existait"], false, "v3.p6: effacer deux fois n'invente rien")

	# RESTAURATION de l'etat de depart du poste.
	if existait:
		Options.sauvegarder(avant)
