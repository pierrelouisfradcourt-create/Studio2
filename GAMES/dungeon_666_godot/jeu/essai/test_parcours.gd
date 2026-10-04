extends SceneTree
## TEST DE PARCOURS : le VRAI jeu assemblé (jeu/principal.tscn, toutes ses vues montées), joué de
## bout en bout sans fenêtre (sortie 0 = vert, dernière ligne « PARCOURS : OK ») :
##   <godot> --headless --path . --script res://jeu/essai/test_parcours.gd
## Il passe par les portes des vues (jeu/ARCHITECTURE.md) : les actions de `principal.gd` et les
## commandes de menu ; jamais d'écriture dans l'état de la partie. Quatre actes :
##   1. un joueur NEUF : titre, Ville (chaque onglet, un achat refusé, le labo), descente de
##      l'étage 1 jouée par le bot de outils/bots/ : bénédiction, butin, marchand, autel, chambre
##      forte, pause en combat, puis le GARDIEN de l'étage 18 réellement battu (butin, portes,
##      checkpoint) ; retour en Ville par le PORTAIL ; le Portail propose le nouveau point et le
##      Gardien à défier ; REPRISE depuis ce point ; mort, « Repartir », mort, Ville, dépenses ;
##   2. un joueur au BOUT DU CHEMIN (profil écrit sur le disque d'essai, relu par un jeu neuf) :
##      la dernière section, de son checkpoint (étage 649) au dernier Gardien (étage 666), fontaine
##      comprise ; l'écran de VICTOIRE, son bouton, ce que le profil reçoit ;
##   3. un joueur AVANCÉ (profil de jeu/ville/profil_essai.gd, relu du disque par un jeu neuf) :
##      opérations de chaque onglet, arène d'essai, entraînement contre un Gardien, puis une
##      descente profonde par classe (étages 19, 37, 55), finies par abandon ou par mort ;
##   4. des cycles titre → Ville → descente → mort → Ville : le nombre de nœuds ne monte pas.
## Le temps : le test tient l'horloge. Il arrête le `_process` de la Partie et appelle sa boucle
## lui-même, un pas de 1/60 s par appel, PAS_PAR_IMAGE appels par image du moteur : la même
## partie à chaque lancement, quelle que soit la vitesse de la machine.
## Ce qu'il ne prouve pas : le rendu, le toucher des boutons (jeu/ecrans/test_ecrans.gd,
## jeu/ville/test_ville.gd), le plaisir de jeu.

const Principal = preload("res://jeu/principal.tscn")
const Profil = preload("res://jeu/profil.gd")
const ProfilEssai = preload("res://jeu/ville/profil_essai.gd")
const Pilote = preload("res://jeu/essai/parcours_pilote.gd")
const Ville = preload("res://jeu/essai/parcours_ville.gd")
const Temoin = preload("res://jeu/essai/parcours_temoin.gd")
const Fondus = preload("res://jeu/essai/fondus.gd")

const DOSSIER := "user://essais_parcours"
const VRAI_PROFIL := "user://profil.json"
const PAS_PAR_IMAGE := 10
const GRAINE := 666.0
const ETAGES_PROFONDS := [19.0, 37.0, 55.0] # un par classe ; au-delà de 13 vivent les ennemis ajoutés
const GARDIEN := "cerbere"
const CYCLES := 4
## Durées de jeu accordées (secondes de boucle) avant de déclarer une étape manquée.
const DUREE_SECTION := 1200.0
const ARMEMENT_MAX_MS := 3000 # temps réel laissé à un écran pour répondre (son armement : 350 ms)
## La première descente cherche ces menus (la halte n'en offre qu'un : la fontaine attend l'acte 2).
const SORTES_DU_DEBUT := ["boon", "loot", "shop", "event", "treasure"]
const SORTES_DE_LA_FIN := ["rest", "treasure", "shop", "event"]
const CLASSE_DE_LA_FIN := "bourreau"
const GRAINE_DE_LA_FIN := 1.0
const DUREE_SALLE := 240.0
const DUREE_MORT := 120.0
const DUREE_ESSAI := 20.0
## Gardes anti-faux-vert : en dessous, le parcours n'a pas joué ce qu'il dit.
const MIN_SALLES := 30
const MIN_ETAGES := 40
const MIN_VERIFICATIONS := 400
## Les nœuds se comptent au nœud près ; les objets (ressources, interpolations en cours) varient
## de quelques unités d'une mesure à l'autre : au-delà, quelque chose s'accumule.
const TOLERANCE_OBJETS := 8

var app: Node
var ecrans: Node
var pilote: RefCounted
var ville: RefCounted
var temoin := Temoin.new()
var echecs := 0
var verifications := 0
var _appels := 0
var _bloque := false
var _ecrans_vus: Array = []
var _empreintes: Array = []
var _bilan := {"pauses": 0, "abandons": 0, "reprises": 0, "retours": 0, "gardiens": [], "portails": 0, "departs_du_point": 0, "victoires": 0, "cycles": 0, "classes": [], "operations": {}}
var _totaux := {"salles": 0, "gardiens": 0, "etages": 0, "morts": 0, "pas": 0, "etage_max": 0.0, "choix": {}, "commandes": {}}
var _base := {}
var _vrai_profil_avant := ""

func _initialize() -> void:
	OS.set_environment(Profil.ENV_DOSSIER, DOSSIER)
	_vrai_profil_avant = FileAccess.get_sha256(VRAI_PROFIL)
	OS.add_logger(temoin)
	_derouler.call_deferred()

func _derouler() -> void:
	var debut := Time.get_ticks_msec()
	_vider_le_dossier()
	await images(2)
	_base = _mesure()
	await _acte_du_nouveau_joueur()
	await _acte_de_la_victoire()
	await _acte_du_joueur_avance()
	await _acte_des_fuites()
	await _fermer_le_jeu("fin")
	_conclure(Time.get_ticks_msec() - debut)

# ---------------------------------------------------------------- outils

func verifier(nom: String, ok: bool, detail = "") -> void:
	verifications += 1
	if not ok:
		echecs += 1
		print("ÉCHEC  ", nom, "  ", detail)

func images(n: int) -> void:
	for i in n:
		await process_frame

func _vider_le_dossier() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DOSSIER))
	for f in DirAccess.get_files_at(DOSSIER):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(DOSSIER.path_join(f)))

func _mesure() -> Dictionary:
	return {
		"noeuds": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"orphelins": int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),
		"objets": int(Performance.get_monitor(Performance.OBJECT_COUNT)),
	}

## Le profil relu du disque d'essai est celui que l'application tient en mémoire, tel quel.
func verifier_disque(etape: String) -> void:
	var relu: Dictionary = Profil.charger(app.contenu)
	verifier(etape + " : le profil du disque d'essai est celui en mémoire", relu == app.profil, _ecart(relu, app.profil))

## Le premier endroit où deux valeurs diffèrent (« equipment.arme.uid : disque …, mémoire … »).
func _ecart(a, b, chemin: String = "") -> String:
	if a is Dictionary and b is Dictionary:
		for k in b.keys() + a.keys().filter(func(c) -> bool: return not b.has(c)):
			if not a.has(k) or not b.has(k) or typeof(a[k]) != typeof(b[k]) or a[k] != b[k]:
				return _ecart(a.get(k, "<absent>"), b.get(k, "<absent>"), "%s.%s" % [chemin, k])
	elif a is Array and b is Array and a.size() == b.size():
		for i in a.size():
			if typeof(a[i]) != typeof(b[i]) or a[i] != b[i]:
				return _ecart(a[i], b[i], "%s[%d]" % [chemin, i])
	return "%s : disque %s, mémoire %s" % [chemin.trim_prefix("."), str(a).left(160), str(b).left(160)]

func _game() -> Dictionary:
	return app.partie.game

## Lance le jeu comme au démarrage : il lit le disque d'essai. Le test prend l'horloge et la manette.
func _lancer_le_jeu() -> void:
	app = Principal.instantiate()
	root.add_child(app)
	app.partie.set_process(false)
	app.ecran_change.connect(func(e: String) -> void: _ecrans_vus.append(e))
	ecrans = app.vues.get("ecrans")
	pilote = Pilote.new(app)
	ville = Ville.new(self, app)
	verifier("lancement : les sept vues sont montées", app.vues.size() == app.VUES.size(), app.vues.keys())
	await _controler("lancement", "titre")

## Ferme le jeu : rien ne lui survit (ni nœud dans l'arbre, ni nœud orphelin).
func _fermer_le_jeu(etape: String) -> void:
	_cumuler()
	await Fondus.laisser_finir(self) # un fondu coupé net resterait en mémoire jusqu'à la sortie
	app.free()
	app = null
	await images(3)
	var m := _mesure()
	verifier("fermeture (%s) : aucun nœud ne survit au jeu" % etape, m.noeuds == _base.noeuds and m.orphelins == _base.orphelins, [_base, m])

func _cumuler() -> void:
	for k in ["salles", "gardiens", "etages", "morts", "pas"]:
		_totaux[k] += pilote.compte[k]
	_totaux.etage_max = maxf(_totaux.etage_max, pilote.compte.etage_max)
	for k in ["choix", "commandes"]:
		for id in pilote.compte[k]:
			_totaux[k][id] = _totaux[k].get(id, 0) + pilote.compte[k][id]
	for id in ville.operations:
		_bilan.operations[id] = _bilan.operations.get(id, 0) + ville.operations[id]

# ---------------------------------------------------------------- ce que montrent les vues

## L'écran posé par-dessus le jeu que l'état demande ("" : aucun).
func _panneau_attendu() -> String:
	if app.ecran == "titre":
		return "titre"
	var g = app.partie.game
	if app.ecran != "jeu" or g == null:
		return ""
	if app.partie.en_pause:
		return "pause"
	return {"choice": "choix", "dead": "mort", "victory": "victoire"}.get(g.mode, "")

## Après deux images : l'application est sur l'écran voulu, chaque vue montre ce que l'état
## demande, et rien d'autre.
func _controler(etape: String, ecran: String, mode: String = "") -> void:
	await images(2)
	var g = app.partie.game
	var mode_vu: String = g.mode if g != null else ""
	verifier("%s : écran « %s », partie « %s »" % [etape, ecran, mode], app.ecran == ecran and mode_vu == mode, [app.ecran, mode_vu])
	verifier(etape + " : la Ville est visible en Ville, et là seulement", app.vues.ville.visible == (app.ecran == "ville"))
	verifier(etape + " : le HUD est visible en jeu, et là seulement", app.vues.hud.visible == (app.ecran == "jeu" and g != null))
	verifier(etape + " : le monde est visible quand une partie existe", app.vues.monde.visible == (g != null))
	verifier("%s : panneau « %s »" % [etape, _panneau_attendu()], ecrans.ecran_montre() == _panneau_attendu(), ecrans.ecran_montre())

# ---------------------------------------------------------------- la boucle

## Un appel de la boucle de la Partie (un pas de simulation, hors ralenti) ; un menu ouvert est
## traversé. Rend la main au moteur toutes les PAS_PAR_IMAGE fois : les vues vivent.
func _avancer() -> void:
	var g = app.partie.game
	if g != null and g.mode == "choice" and not app.partie.en_pause:
		await _traverser_le_menu()
		return
	app.partie._process(D6Data.DT)
	_appels += 1
	if _appels % PAS_PAR_IMAGE == 0:
		await process_frame

## Joue jusqu'à `condition` ; faux si elle n'arrive pas en `secondes` de boucle.
func _jouer_jusqu_a(condition: Callable, secondes: float) -> bool:
	for i in int(secondes / D6Data.DT):
		if condition.call() or _bloque or app.partie.game == null:
			break
		await _avancer()
	return condition.call()

func _jouer(secondes: float) -> void:
	await _jouer_jusqu_a(func() -> bool: return false, secondes)

## Menu ouvert : l'écran de choix est montré ; la réponse du pilote passe par `app.commande` ;
## l'écran suit (il se ferme, ou le marchand reste ouvert après un achat).
func _traverser_le_menu() -> void:
	var sorte: String = _game().choice.kind
	var avant := _etat_du_heros()
	await images(2)
	verifier("menu %s : l'écran de choix est montré" % sorte, ecrans.ecran_montre() == "choix", ecrans.ecran_montre())
	var reponse: Dictionary = pilote.repondre_au_menu()
	verifier("menu %s : la simulation accepte une commande" % sorte, reponse.ok, _game().choice)
	_bloque = not reponse.ok
	_verifier_la_salle_calme(reponse.option, avant)
	await images(2)
	verifier("menu %s : après « %s », l'écran suit la partie" % [sorte, reponse.type], ecrans.ecran_montre() == _panneau_attendu(), ecrans.ecran_montre())

## Ce qu'une salle calme peut changer : les PV du héros, les niveaux de ses bénédictions.
func _etat_du_heros() -> Dictionary:
	var niveaux := 0.0
	for b in _game().run.boons:
		niveaux += b.level
	return {"hp": _game().player.hp, "niveaux": niveaux}

## Chambre forte, fontaine : l'option choisie (son identifiant) a fait ce que son panneau annonce.
func _verifier_la_salle_calme(option: String, avant: Dictionary) -> void:
	var apres := _etat_du_heros()
	var objet = _game().room.get("interact")
	match option:
		"objet":
			verifier("chambre forte : l'objet choisi attend d'être pris, les portes attendent", _game().mode == "play" and objet.kind == "loot" and not D6Js.truthy(objet.used), objet)
		"mediter":
			verifier("fontaine : méditer approfondit une bénédiction d'un niveau", apres.niveaux == avant.niveaux + 1.0, [avant, apres])
		"boire":
			verifier("fontaine : boire ne retire aucun PV", apres.hp >= avant.hp, [avant, apres])

func _en_combat() -> bool:
	var g: Dictionary = _game()
	return g.mode == "play" and not D6Js.truthy(g.room.get("cleared")) and g.enemies.any(func(e: Dictionary) -> bool: return not D6Js.truthy(e.get("dead")))

# ---------------------------------------------------------------- gestes en partie

## Pause en plein combat : le panneau s'ouvre, la partie n'avance plus ; reprise : elle repart.
## `par_les_entrees` : la demande vient de la vue Entrees (touche, bouton), sinon du bouton du HUD.
func _pause_et_reprise(etape: String, par_les_entrees: bool) -> void:
	var basculer := func(pause: bool) -> void:
		if par_les_entrees:
			app.vues.entrees.pause_demandee.emit()
		else:
			app.mettre_en_pause(pause)
	basculer.call(true)
	await _controler(etape + ", pause", "jeu", "play")
	var tick: float = _game().tick
	for i in 30:
		app.partie._process(D6Data.DT)
	verifier(etape + " : en pause, la partie n'avance pas", app.partie.en_pause and _game().tick == tick, _game().tick - tick)
	basculer.call(false)
	await _controler(etape + ", reprise", "jeu", "play")
	await _jouer(0.5)
	verifier(etape + " : à la reprise, le temps de jeu avance", not app.partie.en_pause and _game().tick > tick, _game().tick - tick)
	_bilan.pauses += 1

## Le pilote lâche les commandes : mort, écran de mort, et le profil a DÉJÀ reçu la descente
## (un joueur qui ferme le jeu sur cet écran ne perd rien).
func _mourir(etape: String) -> void:
	pilote.inerte = true
	var mort := await _jouer_jusqu_a(func() -> bool: return _game().mode == "dead", DUREE_MORT)
	verifier(etape + " : le héros laissé sans commandes meurt", mort, _game().mode)
	await _controler(etape + ", mort", "jeu", "dead")
	var meta: Dictionary = _game().meta
	if not _game().sandbox and not _game().practice:
		verifier(etape + " : à l'écran de mort, le profil a reçu les Âmes, le record et la mort", app.profil.souls == meta.souls and app.profil.bestFloor == meta.bestFloor and app.profil.stats.deaths == meta.stats.deaths, [app.profil.souls, meta.souls])
	verifier_disque(etape + ", mort")

func _noter_la_fin() -> void:
	_empreintes.append(D6Game.state_hash(_game()))

## Retour en Ville par la commande de l'écran de mort.
func _rentrer(etape: String) -> void:
	_noter_la_fin()
	var ames: float = _game().meta.souls
	verifier(etape + " : « Retour à la Ville » accepté", app.commande({"type": "returnToTown"}))
	await _controler(etape + ", retour", "ville")
	verifier(etape + " : la partie est finie, les Âmes sont au profil", app.partie.game == null and app.profil.souls == ames, app.profil.souls)
	verifier_disque(etape + ", retour")
	_bilan.retours += 1

## Abandon en cours de route (bouton de la pause) : retour en Ville, Charon a pris sa part.
func _abandonner(etape: String) -> void:
	_noter_la_fin()
	app.abandonner()
	await _controler(etape + ", abandon", "ville")
	verifier(etape + " : abandon, la partie est finie", app.partie.game == null)
	verifier_disque(etape + ", abandon")
	_bilan.abandons += 1

# ---------------------------------------------------------------- acte 1 : le joueur neuf

func _acte_du_nouveau_joueur() -> void:
	await _lancer_le_jeu()
	verifier("joueur neuf : profil neuf (0 Âme, record 1)", app.profil.souls == 0.0 and app.profil.bestFloor == 1.0, app.profil)
	app.ouvrir_ville()
	await _controler("joueur neuf", "ville")
	await ville.visite_du_nouveau_joueur()
	await _premiere_descente()
	await _reprise_depuis_le_point()
	await ville.visite_apres_la_descente()
	app.ouvrir_titre()
	await _controler("joueur neuf, retour au titre", "titre")
	await _fermer_le_jeu("joueur neuf")

## Étage 1 : un combat, une pause, puis toute la section — cinq sortes de menu, le Gardien de
## l'étage 18 battu, son butin, le portail de la Ville, et ce que le Portail propose au retour.
func _premiere_descente() -> void:
	var etape := "première descente"
	var gardien: float = D6Floors.section_bounds(app.contenu, 1.0).guardian
	app.demarrer_descente(1.0, false, false, GRAINE)
	pilote.voulues = SORTES_DU_DEBUT
	await _controler(etape, "jeu", "play")
	verifier(etape + " : étage 1, profil du joueur neuf", _game().run.floor == 1.0 and not _game().sandbox and _game().meta.stats.runs == 1.0)
	verifier(etape + " : un combat s'engage", await _jouer_jusqu_a(_en_combat, DUREE_SALLE))
	await _pause_et_reprise(etape, false)
	var battu := await _jouer_jusqu_a(func() -> bool: return pilote.compte.gardiens > 0, DUREE_SECTION)
	verifier(etape + " : le Gardien de l'étage %s est battu" % D6Js.num_str(gardien), battu and _game().run.floor == gardien, [_game().mode, _game().run.floor, _game().player.hp])
	verifier(etape + " : bénédiction, butin, marchand, autel et chambre forte traversés", pilote.sortes_manquantes().is_empty(), pilote.compte.choix)
	verifier(etape + " : le temps de jeu a avancé", _game().time > 0.0 and _game().tick == float(pilote.compte.pas), [_game().tick, pilote.compte.pas])
	print("première descente : %d salles, étage %s, menus %s, %s Âmes" % [pilote.compte.salles, D6Js.num_str(_game().run.floor), pilote.compte.choix, D6Js.num_str(_game().meta.souls)])
	if not battu:
		return
	await _gardien_battu(etape, {"checkpoints": [1.0], "rencontres": 0.0, "victoires": 0.0, "ames": 0.0})
	await _prendre_le_portail(etape)
	await ville.verifier_le_portail(etape + ", de retour", gardien + 1.0)

## Le Gardien vient de tomber (au pas de simulation même) : checkpoint et point de téléportation
## au profil ET sur le disque, Âmes, butin à prendre, deux portes ouvertes dont celle de la Ville.
## `avant` : ce que le profil avait avant la descente (checkpoints, rencontres, victoires, ames).
func _gardien_battu(etape: String, avant: Dictionary) -> void:
	var g: Dictionary = _game()
	var modele: String = D6Floors.guardian_for(app.contenu, g.info.section)
	var point: float = D6Floors.checkpoint_after_boss(app.contenu, g.run.floor)
	_empreintes.append(D6Game.state_hash(g))
	_bilan.gardiens.append(g.run.floor)
	await _controler(etape + ", Gardien battu", "jeu", "play")
	verifier(etape + " : salle du Gardien nettoyée, un seul checkpoint annoncé", g.room.kind == "boss" and D6Js.truthy(g.room.cleared) and g.info.isBoss and pilote.vus("checkpoint") == 1, [g.room.kind, pilote.vus("checkpoint")])
	var butin = g.room.get("interact")
	verifier(etape + " : le Gardien laisse un butin rare ou légendaire, à prendre", butin != null and butin.kind == "loot" and not D6Js.truthy(butin.used) and butin.item.rarity in ["rare", "legendaire"], butin)
	var portes: Array = g.room.doors.map(func(d: Dictionary) -> String: return d.reward)
	verifier(etape + " : deux portes ouvertes, la suite et la Ville", portes.size() == 2 and portes[0] != "town" and portes[1] == "town" and g.room.doors.all(func(d: Dictionary) -> bool: return D6Js.truthy(d.get("open"))), portes)
	verifier(etape + " : le checkpoint de l'étage %s est posé au profil" % D6Js.num_str(point), app.profil.checkpoints == avant.checkpoints + [point], app.profil.checkpoints)
	verifier(etape + " : le Gardien (%s) est compté au profil, il pourra être défié" % modele, D6Js.nz(app.profil.guardians.get(modele), 0.0) == avant.rencontres + 1.0 and app.profil.stats.guardianKills == avant.victoires + 1.0, [app.profil.guardians, app.profil.stats])
	_verifier_la_prime(etape, avant.ames)
	verifier_disque(etape + ", Gardien battu")

## La prime du Gardien (Âmes de sa section) est annoncée avec son checkpoint, et le profil tient
## les Âmes de la partie : celles d'avant, plus les gains, moins ce qu'un autel a pu prendre.
func _verifier_la_prime(etape: String, ames_avant: float) -> void:
	var g: Dictionary = _game()
	var ames: Dictionary = app.contenu.progression.souls
	var prime: float = ames.guardian + ames.guardianPerSection * (g.info.section - 1.0)
	var annonce: Dictionary = pilote.dernier_checkpoint
	verifier(etape + " : la prime du Gardien (%s Âmes) est annoncée avec son checkpoint" % D6Js.num_str(prime), annonce.get("souls") == prime and annonce.get("guardian") == D6Floors.guardian_for(app.contenu, g.info.section) and annonce.get("floor") == D6Floors.checkpoint_after_boss(app.contenu, g.run.floor), annonce)
	verifier(etape + " : le profil tient les Âmes de la partie, prime comprise", app.profil.souls == g.meta.souls and g.telemetry.soulsEarned > prime and g.meta.souls <= ames_avant + g.telemetry.soulsEarned, [app.profil.souls, ames_avant, g.telemetry.soulsEarned])

## Le pilote prend le butin puis le portail de la Ville : le run finit SANS mort ni taxe, la
## Ville s'ouvre, le profil garde tout.
func _prendre_le_portail(etape: String) -> void:
	var butins: int = pilote.compte.choix.get("loot", 0)
	var morts: float = app.profil.stats.deaths
	pilote.vers_la_ville = true
	var rentre := await _jouer_jusqu_a(func() -> bool: return app.partie.game == null, DUREE_SALLE)
	verifier(etape + " : le héros franchit le portail, la partie finit", rentre and pilote.vus("returnTown") == 1, [app.ecran, pilote.vus("returnTown")])
	await _controler(etape + ", portail", "ville")
	verifier(etape + " : le butin du Gardien a été pris avant de partir", pilote.compte.choix.get("loot", 0) == butins + 1, pilote.compte.choix)
	verifier(etape + " : le portail n'est pas une mort (aucune taxe de Charon)", app.profil.stats.deaths == morts and pilote.compte.morts == 0, app.profil.stats)
	verifier_disque(etape + ", portail")
	_bilan.portails += 1 if rentre else 0

## Reprise depuis le point de téléportation ouvert par le Gardien : la descente part de là, avec
## l'équipement gardé et sans bénédiction ; une salle ; mort ; « Repartir » y ramène ; mort ; Ville.
func _reprise_depuis_le_point() -> void:
	var etape := "reprise depuis le point"
	var point: float = D6Js.nz(app.profil.checkpoints.max(), 1.0)
	var porte: Dictionary = app.profil.equipment.duplicate(true)
	var salles: int = pilote.compte.salles
	app.demarrer_descente(point, false, false, GRAINE + point)
	await _controler(etape, "jeu", "play")
	verifier(etape + " : la descente part de l'étage %s, seconde du profil" % D6Js.num_str(point), point > 1.0 and _game().run.floor == point and _game().meta.stats.runs == 2.0, [point, _game().run.floor])
	verifier(etape + " : l'équipement est gardé, les bénédictions non", _game().meta.equipment == porte and _game().run.boons.is_empty(), _game().run.boons)
	var nettoyee := await _jouer_jusqu_a(func() -> bool: return pilote.compte.salles > salles, DUREE_SALLE)
	verifier(etape + " : une salle nettoyée", nettoyee, [_game().mode, _game().player.hp])
	_bilan.departs_du_point += 1 if nettoyee and _game().run.floor >= point else 0
	await _mourir(etape)
	verifier(etape + " : le record suit l'étage atteint, une mort comptée", app.profil.bestFloor == pilote.compte.etage_max and app.profil.stats.deaths == 1.0, [app.profil.bestFloor, app.profil.stats])
	await _reprendre(etape, point)
	await _mourir(etape + " (seconde vie)")
	await _rentrer(etape)

## « Repartir » depuis l'écran de mort : même partie, étage du dernier checkpoint, sans bénédiction.
func _reprendre(etape: String, point: float) -> void:
	var salles: int = pilote.compte.salles
	verifier(etape + " : « Repartir » accepté", app.commande({"type": "respawn", "floor": D6Run.last_checkpoint(_game())}))
	pilote.inerte = false
	await _controler(etape + ", reprise après la mort", "jeu", "play")
	verifier(etape + " : reparti du dernier checkpoint, sans bénédiction", _game().run.floor == point and _game().run.boons.is_empty(), _game().run.floor)
	verifier(etape + " : une salle nettoyée après la reprise", await _jouer_jusqu_a(func() -> bool: return pilote.compte.salles > salles, DUREE_SALLE), _game().mode)
	_bilan.reprises += 1

# ---------------------------------------------------------------- acte 2 : la victoire

## Un joueur au bout du chemin (profil écrit sur le disque d'essai, relu par un jeu neuf) : la
## dernière section, de son dernier checkpoint au dernier Gardien, puis l'écran de victoire.
func _acte_de_la_victoire() -> void:
	var etape := "bout du chemin"
	_vider_le_dossier()
	var ecrit: Dictionary = ProfilEssai.au_bout_du_chemin(D6Data.create_tuning(), CLASSE_DE_LA_FIN)
	ProfilEssai.ecrire(ecrit)
	await _lancer_le_jeu()
	var depart: float = D6Floors.section_bounds(app.contenu, D6Floors.floor_info(app.contenu, app.contenu.floors.total).section).first
	verifier(etape + " : le jeu a relu son profil du disque, dernier checkpoint à l'étage %s" % D6Js.num_str(depart), app.profil == D6Profile.sanitize_profile(ecrit, app.contenu) and D6Js.nz(app.profil.checkpoints.max(), 0.0) == depart, _ecart(ecrit, app.profil))
	app.ouvrir_ville()
	await _controler(etape, "ville")
	await ville.verifier_le_portail(etape, depart)
	var avant := {"checkpoints": app.profil.checkpoints.duplicate(), "rencontres": app.profil.guardians.duplicate(), "victoires": app.profil.stats.guardianKills, "ames": app.profil.souls, "morts": app.profil.stats.deaths}
	app.demarrer_descente(depart, false, false, GRAINE_DE_LA_FIN)
	pilote.voulues = SORTES_DE_LA_FIN
	await _controler(etape, "jeu", "play")
	verifier(etape + " : la descente part du dernier checkpoint", _game().run.floor == depart and _game().kit.classId == CLASSE_DE_LA_FIN, _game().run.floor)
	var gagne := await _jouer_jusqu_a(func() -> bool: return _game().mode == "victory", DUREE_SECTION)
	verifier(etape + " : le dernier Gardien est battu, sans une mort", gagne and pilote.compte.morts == 0 and pilote.compte.gardiens == 1, [_game().mode, _game().run.floor, _game().player.hp])
	verifier(etape + " : la fontaine a été traversée en chemin", pilote.compte.choix.get("rest", 0) > 0, pilote.compte.choix)
	print("bout du chemin : %d salles, étage %s, menus %s" % [pilote.compte.salles, D6Js.num_str(_game().run.floor), pilote.compte.choix])
	if gagne:
		await _victoire(etape, avant)
	app.ouvrir_titre()
	await _controler(etape + ", retour au titre", "titre")
	await _fermer_le_jeu(etape)

## L'écran de victoire : ce que le profil a reçu (aucun checkpoint : il n'y a pas d'étage après),
## ce que l'écran dit et refuse, puis son seul bouton, appuyé comme le ferait un joueur.
func _victoire(etape: String, avant: Dictionary) -> void:
	var g: Dictionary = _game()
	var total: float = app.contenu.floors.total
	var modele: String = D6Floors.guardian_for(app.contenu, g.info.section)
	_noter_la_fin()
	_bilan.gardiens.append(g.run.floor)
	await _controler(etape + ", victoire", "jeu", "victory")
	verifier(etape + " : victoire à l'étage %s, annoncée une fois" % D6Js.num_str(total), g.run.floor == total and g.info.isFinal and pilote.vus("victory") == 1, [g.run.floor, pilote.vus("victory")])
	verifier(etape + " : le dernier Gardien n'ouvre aucun checkpoint, le record est l'étage %s" % D6Js.num_str(total), app.profil.checkpoints == avant.checkpoints and app.profil.bestFloor == total, [app.profil.checkpoints.size(), app.profil.bestFloor])
	verifier(etape + " : le Gardien (%s) est compté au profil" % modele, app.profil.guardians.get(modele) == avant.rencontres.get(modele) + 1.0 and app.profil.stats.guardianKills == avant.victoires + 1.0, [app.profil.guardians, app.profil.stats])
	_verifier_la_prime(etape, avant.ames)
	verifier_disque(etape + ", victoire")
	var bouton := _bouton_de_la_victoire(etape, total)
	verifier(etape + " : on ne « repart » pas d'une victoire", not app.commande({"type": "respawn", "floor": avant.checkpoints.max()}) and g.mode == "victory")
	if bouton == null:
		return
	var limite := Time.get_ticks_msec() + ARMEMENT_MAX_MS
	while not ecrans.pret() and Time.get_ticks_msec() < limite:
		await process_frame
	bouton.pressed.emit()
	await _controler(etape + ", retour de la victoire", "ville")
	verifier(etape + " : le bouton ramène en Ville, la partie est finie, sans mort, les Âmes au profil", app.partie.game == null and app.profil.souls == g.meta.souls and app.profil.stats.deaths == avant.morts, [app.profil.souls, app.profil.stats])
	verifier_disque(etape + ", retour de la victoire")
	await ville.verifier_le_portail(etape + ", après la victoire", avant.checkpoints.max())
	_bilan.victoires += 1 if app.ecran == "ville" and app.partie.game == null else 0

## L'écran de victoire dit l'étage atteint et n'offre qu'un bouton, le retour en Ville (null s'il manque).
func _bouton_de_la_victoire(etape: String, total: float) -> Button:
	var ecran: Control = ecrans.ecran()
	var bouton: Button = ecran.get_node_or_null("%Ville") if ecran != null else null
	var accroche: Label = ecran.get_node_or_null("%Accroche") if ecran != null else null
	var seul: bool = ecran != null and ecran.find_children("*", "Button", true, false).size() == 1
	verifier(etape + " : l'écran dit l'étage atteint et offre un seul bouton, « Retour à la Ville »", accroche != null and accroche.text.contains(D6Js.num_str(total)) and bouton != null and bouton.is_visible_in_tree() and not bouton.disabled and seul, accroche.text if accroche != null else "écran absent")
	return bouton

# ---------------------------------------------------------------- acte 3 : le joueur avancé

func _acte_du_joueur_avance() -> void:
	_vider_le_dossier()
	var ecrit: Dictionary = ProfilEssai.riche(D6Data.create_tuning())
	ProfilEssai.ecrire(ecrit)
	await _lancer_le_jeu()
	verifier("joueur avancé : le jeu a relu son profil du disque", app.profil == D6Profile.sanitize_profile(ecrit, app.contenu) and app.profil.checkpoints.size() == 4, _ecart(ecrit, app.profil))
	app.ouvrir_ville()
	await _controler("joueur avancé", "ville")
	await ville.visite_du_joueur_avance()
	await _arene()
	await _entrainement()
	var classes: Array = app.contenu.classes.keys()
	for i in classes.size():
		await _descente_profonde(classes[i], ETAGES_PROFONDS[i % ETAGES_PROFONDS.size()], "mort" if i == 1 else "abandon")

## Arène d'essai : on s'y bat, on y met en pause par la vue Entrees, on l'abandonne ; le profil
## n'en garde aucune trace.
func _arene() -> void:
	var etape := "arène d'essai"
	var avant: Dictionary = app.profil.duplicate(true)
	var tues: int = pilote.vus("kill")
	app.demarrer_descente(1.0, true, false, GRAINE)
	await _controler(etape, "jeu", "play")
	verifier(etape + " : la partie est une arène", _game().sandbox and not _game().practice)
	verifier(etape + " : un combat s'engage", await _jouer_jusqu_a(_en_combat, DUREE_SALLE))
	await _pause_et_reprise(etape, true)
	await _jouer(DUREE_ESSAI)
	verifier(etape + " : des ennemis tombent", pilote.vus("kill") > tues, pilote.vus("kill") - tues)
	await _abandonner(etape)
	verifier(etape + " : le profil n'a pas bougé", app.profil == avant, _ecart(avant, app.profil))

## Entraînement contre un Gardien déjà rencontré : sans enjeu, le profil n'en garde aucune trace.
func _entrainement() -> void:
	var etape := "entraînement (%s)" % GARDIEN
	var avant: Dictionary = app.profil.duplicate(true)
	verifier(etape + " : ce Gardien a été rencontré", D6Js.nz(app.profil.guardians.get(GARDIEN), 0.0) > 0.0, app.profil.guardians)
	app.demarrer_entrainement(GARDIEN, GRAINE)
	await _controler(etape, "jeu", "play")
	var boss: Array = _game().enemies.filter(func(e: Dictionary) -> bool: return D6Js.truthy(e.get("boss")))
	verifier(etape + " : sans enjeu, dans la salle du Gardien, à la graine demandée", _game().practice and _game().room.kind == "boss" and _game().seed == GRAINE, [_game().room.kind, _game().seed])
	await _jouer(DUREE_ESSAI)
	boss = _game().enemies.filter(func(e: Dictionary) -> bool: return D6Js.truthy(e.get("boss")))
	verifier(etape + " : le Gardien est là, le combat a lieu", (not boss.is_empty() or pilote.compte.morts > 0) and pilote.vus("hit") > 0, [boss.size(), _game().mode])
	if _game().mode == "dead":
		await _controler(etape + ", mort", "jeu", "dead")
		_noter_la_fin()
		verifier(etape + " : « Retour à la Ville » accepté", app.commande({"type": "returnToTown"}))
		await _controler(etape + ", retour", "ville")
	else:
		await _abandonner(etape)
	verifier(etape + " : le profil n'a pas bougé", app.profil == avant, _ecart(avant, app.profil))

## Une classe, une descente profonde : au moins une salle nettoyée, puis la fin demandée
## (« abandon » au combat suivant, ou « mort » et retour par l'écran de mort).
func _descente_profonde(classe: String, etage: float, fin: String) -> void:
	var etape := "descente profonde (%s, étage %s)" % [classe, D6Js.num_str(etage)]
	await ville.ouvrir(etape, "classe")
	await ville.choisir_la_classe(etape, classe)
	await ville.ouvrir(etape, "portail")
	var salles: int = pilote.compte.salles
	app.demarrer_descente(etage, false, false, GRAINE + etage)
	await _controler(etape, "jeu", "play")
	verifier(etape + " : la partie porte la classe et part de l'étage", _game().kit.classId == classe and _game().run.floor == etage, _game().kit)
	var nettoyee := await _jouer_jusqu_a(func() -> bool: return pilote.compte.salles > salles, DUREE_SALLE)
	verifier(etape + " : une salle nettoyée", nettoyee, [_game().mode, _game().player.hp])
	if nettoyee:
		_bilan.classes.append(classe)
	if fin == "mort":
		await _mourir(etape)
		await _rentrer(etape)
		return
	verifier(etape + " : un nouveau combat s'engage", await _jouer_jusqu_a(func() -> bool: return _game().run.floor > etage and _en_combat(), DUREE_SALLE), _game().run.floor)
	var morts: float = app.profil.stats.deaths
	await _abandonner(etape)
	verifier(etape + " : l'abandon compte comme une mort", app.profil.stats.deaths == morts + 1.0, app.profil.stats)

# ---------------------------------------------------------------- acte 4 : les fuites

## Des cycles identiques titre → Ville → descente → mort → Ville. Le premier chauffe les réserves
## (sons, particules) ; ensuite le compte des nœuds ne doit plus monter d'un cycle à l'autre.
func _acte_des_fuites() -> void:
	var mesures: Array = []
	for i in CYCLES:
		var etape := "cycle %d" % (i + 1)
		app.ouvrir_titre()
		await _controler(etape, "titre")
		app.ouvrir_ville()
		await _controler(etape, "ville")
		app.demarrer_descente(ETAGES_PROFONDS[2], false, false, GRAINE)
		await _controler(etape, "jeu", "play")
		await _jouer(3.0)
		await _mourir(etape)
		await _rentrer(etape)
		await images(4)
		mesures.append(_mesure())
		_bilan.cycles += 1
	var apres: Dictionary = mesures[CYCLES - 1]
	var avant: Dictionary = mesures[1]
	print("fuites : ", mesures)
	verifier("fuites : le nombre de nœuds ne monte pas d'un cycle à l'autre", apres.noeuds <= avant.noeuds, mesures)
	verifier("fuites : aucun nœud orphelin ne s'accumule", apres.orphelins <= avant.orphelins, mesures)
	verifier("fuites : le nombre d'objets ne monte pas (à %d près)" % TOLERANCE_OBJETS, apres.objets <= avant.objets + TOLERANCE_OBJETS, mesures)

# ---------------------------------------------------------------- verdict

## Gardes anti-faux-vert : un parcours qui n'a pas réellement joué est ROUGE.
func _gardes() -> void:
	var t := _totaux
	verifier("garde : au moins %d salles nettoyées" % MIN_SALLES, t.salles >= MIN_SALLES, t.salles)
	var etages: Dictionary = D6Data.default_tuning().floors
	verifier("garde : au moins %d étages entrés, jusqu'au dernier" % MIN_ETAGES, t.etages >= MIN_ETAGES and t.etage_max == etages.total, [t.etages, t.etage_max])
	verifier("garde : deux Gardiens battus, celui de la section 1 et le dernier", t.gardiens == 2 and _bilan.gardiens == [etages.sectionLength, etages.total], [t.gardiens, _bilan.gardiens])
	verifier("garde : un portail pris, un départ du point ouvert, une victoire", _bilan.portails == 1 and _bilan.departs_du_point == 1 and _bilan.victoires == 1, _bilan)
	for sorte in Pilote.SORTES_VOULUES:
		verifier("garde : menu « %s » traversé" % sorte, t.choix.get(sorte, 0) > 0, t.choix)
	verifier("garde : un butin équipé ou rangé, une bénédiction choisie", t.commandes.get("equip", 0) + t.commandes.get("stash", 0) > 0 and t.commandes.get("choose", 0) > 0, t.commandes)
	verifier("garde : morts, reprise, retours, abandons, pauses", t.morts >= 3 + CYCLES and _bilan.reprises >= 1 and _bilan.retours >= 2 + CYCLES and _bilan.abandons >= 3 and _bilan.pauses >= 2, [t.morts, _bilan])
	verifier("garde : les trois classes ont nettoyé une salle", _bilan.classes.size() == 3, _bilan.classes)
	verifier("garde : %d cycles de fuite joués" % CYCLES, _bilan.cycles == CYCLES, _bilan.cycles)
	for op in ["select_class", "unlock", "equip_from_stash", "buy_upgrade", "labo"]:
		verifier("garde : opération de Ville « %s » acceptée" % op, _bilan.operations.get(op, 0) > 0, _bilan.operations)
	verifier("garde : au moins %d vérifications" % MIN_VERIFICATIONS, verifications >= MIN_VERIFICATIONS, verifications)

func _conclure(duree_ms: int) -> void:
	_gardes()
	OS.remove_logger(temoin)
	verifier("aucune erreur de script ni du moteur pendant le parcours", temoin.nombre == 0, "%d erreur(s) : %s" % [temoin.nombre, temoin.retenues])
	if temoin.sans_fenetre > 0:
		print("SIGNALÉ (non bloquant) : %d erreur(s) du moteur dues à l'absence de fenêtre, provoquées par %s" % [temoin.sans_fenetre, temoin.lieux_sans_fenetre])
	var vrai_apres := FileAccess.get_sha256(VRAI_PROFIL)
	verifier("le vrai profil du joueur n'a pas bougé", vrai_apres == _vrai_profil_avant, [_vrai_profil_avant, vrai_apres])
	var t := _totaux
	print("RÉSUMÉ joué : %d salles, %d étages (max %s), %d morts, %d pas ; menus %s ; commandes %s" % [t.salles, t.etages, D6Js.num_str(t.etage_max), t.morts, t.pas, t.choix, t.commandes])
	print("RÉSUMÉ gestes : %s ; écrans %s" % [_bilan, " ".join(PackedStringArray(_ecrans_vus))])
	print("RÉSUMÉ empreintes : %s" % [_empreintes])
	print("vrai profil (SHA-256) : %s — inchangé : %s" % [vrai_apres if vrai_apres != "" else "absent", vrai_apres == _vrai_profil_avant])
	print("test_parcours : %d vérifications, %d échec(s), %d erreur(s) de script, %.1f s" % [verifications, echecs, temoin.nombre, duree_ms / 1000.0])
	print("PARCOURS : %s" % ("OK" if echecs == 0 else "ECHEC"))
	quit(1 if echecs > 0 else 0)
