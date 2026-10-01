extends Node
## Le son de Dungeon 666 : bruitages 100 % procéduraux (aucun fichier) pilotés par les événements
## de simulation, et vibrations. Portage de GAMES/dungeon_666/src/audio/sfx.mjs.
##
## Chaque recette (recettes.gd) est RENDUE une fois en mémoire, dans un fil d'exécution à part
## dès le démarrage, puis rejouée par un réservoir de VOIX_MAX lecteurs. Un son demandé avant
## d'être rendu est simplement passé : jamais d'attente, jamais de gel.
##
## Une image = des événements GROUPÉS par son : 6 coups dans la même image donnent 1 ou 2 sons
## plus forts, pas 6. Chaque son a un plafond de voix simultanées, et le mixage un plafond global
## dont une part est réservée aux sons vitaux (coup reçu, esquive, Super, Gardien…).
##
## Chaîne : lecteurs -> bus « Effets » (compresseur, limiteur, volume) -> sortie.
## Aucune règle de jeu ici ; `randf` ne sert qu'à varier la hauteur des sons.

## Tous les sons sont rendus et prêts à jouer.
signal sons_prets
## Une vibration vient d'être demandée au téléphone (durée en ms).
signal vibration(ms: int)

const Recettes = preload("res://jeu/son/recettes.gd")
const Routage = preload("res://jeu/son/routage.gd")

const BUS := StudioReglages.BUS_EFFETS
const VOLUME := 0.6 # volume maître des effets
# Compresseur du bus : évite la saturation quand tout frappe ensemble (réglages du web ; le gain
# compense à peu près le rattrapage automatique du compresseur de WebAudio).
const COMPRESSEUR := {"threshold": -18.0, "ratio": 6.0, "attack_us": 3000.0, "release_ms": 150.0, "gain": 6.0}
const PLAFOND_DB := -0.5 # limiteur final : la sortie ne dépasse jamais
const VARIATION_HAUTEUR := 0.05 # ±5 % de hauteur à chaque son
const HAUTEUR_MIN := 0.25
const HAUTEUR_MAX := 4.0
const VOLUME_MIN := 0.0001
const VOIX_MAX := 24 # plafond global (dur) : c'est aussi le nombre de lecteurs
const PRIORITE_VITALE := 9 # sons vitaux (coup reçu, esquive, Super, Gardien…)
const RESERVE_VITALE := 6 # voix réservées aux sons vitaux : le reste plafonne à 24 - 6
const RENFORT_PAR_DOUBLEMENT := 0.22 # gain ajouté chaque fois qu'un groupe double
const RENFORT_MAX := 1.6
const MARGE_FIN := 0.05 # s : latence de sortie, la voix reste comptée un peu après sa fin
const VIBRATION_ECART_MS := 40.0 # une vibration plus faible n'interrompt pas la précédente
const BUDGET_SANS_FIL_MS := 3 # sans fil d'exécution : temps de rendu toléré par image
const SON_ECRAN := {"voix": 3, "priorite": 5, "gain": 0.5} # sons demandés par les écrans
const CLE_ECRAN := "ecran"

## Faux : rien n'est rendu au démarrage (bancs d'essai : `rendre_tout()`).
@export var rendu_auto := true
## Vrai : rendu étalé sur les images plutôt que dans un fil (forcé sur un export sans threads).
@export var sans_fil := false

var app: Node
var partie: Node
## joues : sons lancés ; fusionnes : événements absorbés par leur groupe ; abandonnes : sons
## refusés faute de voix ; pas_prets : demandés avant d'être rendus ; manquantes : recette
## inconnue (défaut de routage) ; inconnus : types d'événements ni routés ni silencieux.
var stats := {"joues": 0, "fusionnes": 0, "abandonnes": 0, "pas_prets": 0, "manquantes": 0, "inconnus": {}, "vibrations": 0}
## Durée du rendu de toutes les recettes (ms), connue quand `sons_prets` est émis.
var temps_rendu_ms := 0.0

var _muet := false
var _vibrations := true
var _flux: Dictionary = {} # recette -> { flux, niveau, duree, crete_brute, octets }
var _lecteurs: Array[AudioStreamPlayer] = []
var _fins := PackedFloat64Array() # instant où chaque lecteur redevient libre
var _voix: Dictionary = {} # clé de son -> instants de fin des voix en cours
var _dernier_coup := -1.0
var _vibration_jusqua := 0.0
var _vibration_ms := 0
var _avance := 0.0 # s ajoutées à l'horloge (bancs d'essai)
var _fil: Thread
var _arret := false
var _depart_rendu := 0
var _a_rendre: Array = []
var _travail: Dictionary = {}
var _bruit := PackedFloat32Array()

@onready var _reservoir: Node = $Lecteurs

func _ready() -> void:
	_preparer_bus()
	for i in VOIX_MAX:
		var lecteur := AudioStreamPlayer.new()
		lecteur.bus = BUS
		_reservoir.add_child(lecteur)
		_lecteurs.append(lecteur)
	_fins.resize(VOIX_MAX)
	_fins.fill(0.0)
	set_process(false)
	if rendu_auto:
		_lancer_rendu()

func _exit_tree() -> void:
	_arreter_fil()
	_couper()

## Point d'entrée de la vue (jeu/ARCHITECTURE.md).
func brancher(application: Node, la_partie: Node) -> void:
	app = application
	partie = la_partie
	if partie != null:
		partie.evenements.connect(_sur_evenements)
		if partie.has_signal("partie_demarree"):
			partie.partie_demarree.connect(_sur_partie_demarree)
	if app != null and app.has_signal("reglages_change"):
		app.reglages_change.connect(_sur_reglages)
	_sur_reglages()

# ---------------------------------------------------------------- pour les écrans

## Joue une recette par son nom (clic de menu : `jouer("clic")`). Faux si rien n'a joué.
func jouer(nom: String, volume: float = 1.0, hauteur: float = 1.0) -> bool:
	if _muet:
		return false
	var t := _maintenant()
	_purger(t)
	if not _a_de_la_place(CLE_ECRAN, SON_ECRAN, t):
		stats.abandonnes += 1
		return false
	var fin := _lancer(nom, SON_ECRAN.gain * volume, hauteur, SON_ECRAN.priorite, t)
	if fin <= t:
		return false
	_noter_voix(CLE_ECRAN, fin)
	stats.joues += 1
	return true

func est_pret() -> bool:
	return _flux.size() >= Recettes.noms().size()

## Voix en cours (une voix = un son lancé, quel que soit son nombre de couches superposées).
func nombre_de_voix() -> int:
	_purger(_maintenant())
	var n := 0
	for cle in _voix:
		n += _voix[cle].size()
	return n

func voix_de(cle: String) -> int:
	_purger(_maintenant())
	return _voix.get(cle, []).size()

## Lecteurs réellement en train de jouer (vérité du moteur, pas notre comptabilité).
func lecteurs_actifs() -> int:
	var n := 0
	for lecteur in _lecteurs:
		if lecteur.playing:
			n += 1
	return n

func memoire_octets() -> int:
	var total := 0
	for nom in _flux:
		total += _flux[nom].octets
	return total

## Les sons rendus (lecture seule) : recette -> { flux, niveau, duree, crete_brute, octets }.
func sons_rendus() -> Dictionary:
	return _flux

## Banc d'essai : fait passer le temps sans attendre (les voix s'éteignent).
func avancer_horloge(secondes: float) -> void:
	_avance += secondes

# ---------------------------------------------------------------- bus et réglages

func _preparer_bus() -> void:
	StudioReglages.assurer_bus()
	var i := AudioServer.get_bus_index(BUS)
	if i == -1 or AudioServer.get_bus_effect_count(i) > 0:
		return
	var compresseur := AudioEffectCompressor.new()
	for reglage in COMPRESSEUR:
		compresseur.set(reglage, COMPRESSEUR[reglage])
	AudioServer.add_bus_effect(i, compresseur)
	var limiteur := AudioEffectHardLimiter.new()
	limiteur.ceiling_db = PLAFOND_DB
	AudioServer.add_bus_effect(i, limiteur)
	AudioServer.set_bus_volume_db(i, linear_to_db(VOLUME))

func _sur_reglages() -> void:
	var reglages: Dictionary = app.reglages if app != null and app.get("reglages") is Dictionary else {}
	_vibrations = D6Js.truthy(reglages.get("haptics", true))
	_muet = not D6Js.truthy(reglages.get("sound", true))
	if _muet:
		_couper()

func _couper() -> void:
	for lecteur in _lecteurs:
		lecteur.stop()
	_fins.fill(0.0)
	_voix.clear()

func _sur_partie_demarree() -> void:
	_dernier_coup = -1.0

# ---------------------------------------------------------------- rendu des recettes

func _lancer_rendu() -> void:
	Recettes.table() # construite ici, sur le fil principal : le fil de rendu ne fait que la lire
	_depart_rendu = Time.get_ticks_usec()
	_a_rendre = Recettes.noms().filter(func(nom): return not _flux.has(nom))
	if OS.has_feature("threads") and not sans_fil:
		_arret = false
		_fil = Thread.new()
		_fil.start(_rendre_en_fil.bind(_a_rendre.duplicate()))
	else:
		_bruit = Recettes.bruit()
		set_process(true)

## Fil de rendu : une recette après l'autre, remise au fil principal dès qu'elle est prête.
func _rendre_en_fil(noms: Array) -> void:
	var bruit := Recettes.bruit()
	for nom in noms:
		if _arret:
			return
		call_deferred("_recevoir", nom, Recettes.rendre(nom, bruit))

func _recevoir(nom: String, rendu: Dictionary) -> void:
	_flux[nom] = rendu
	_a_rendre.erase(nom)
	if _a_rendre.is_empty() and temps_rendu_ms == 0.0:
		temps_rendu_ms = (Time.get_ticks_usec() - _depart_rendu) / 1000.0
		sons_prets.emit()

func _arreter_fil() -> void:
	if _fil != null and _fil.is_started():
		_arret = true
		_fil.wait_to_finish()
	_fil = null

## Sans fil d'exécution (export web sans threads) : une couche à la fois, quelques
## millisecondes par image. Une couche très longue peut dépasser ce budget.
func _process(_delta: float) -> void:
	var limite := Time.get_ticks_msec() + BUDGET_SANS_FIL_MS
	while true:
		if _travail.is_empty():
			if _a_rendre.is_empty():
				set_process(false)
				return
			_travail = Recettes.commencer(_a_rendre[0], _bruit)
		if Recettes.avancer(_travail):
			var nom: String = _travail.nom
			var rendu := Recettes.conclure(_travail)
			_travail = {}
			_recevoir(nom, rendu)
		if Time.get_ticks_msec() >= limite:
			return

## Rend d'un trait tout ce qui ne l'est pas encore (bancs d'essai, planche de sons).
## Rend la durée du rendu en millisecondes.
func rendre_tout() -> float:
	_arreter_fil()
	set_process(false)
	_travail = {}
	var depart := Time.get_ticks_usec()
	var bruit := Recettes.bruit()
	for nom in Recettes.noms():
		if not _flux.has(nom):
			_flux[nom] = Recettes.rendre(nom, bruit)
	_a_rendre.clear()
	temps_rendu_ms = (Time.get_ticks_usec() - depart) / 1000.0
	sons_prets.emit()
	return temps_rendu_ms

# ---------------------------------------------------------------- événements d'une image

func _sur_evenements(liste: Array) -> void:
	if liste.is_empty():
		return
	var entrees := _annoter(liste)
	_vibrer_pour(entrees)
	if _muet:
		return
	var t := _maintenant()
	_purger(t)
	var groupes := _grouper(entrees)
	for cle in _par_priorite(groupes):
		_jouer_groupe(cle, groupes[cle], t)

## Entrées { ev, cle, lourd } ; suit l'index du dernier coup pour reconnaître le 3e coup.
func _annoter(liste: Array) -> Array:
	var out: Array = []
	for ev in liste:
		if not (ev is Dictionary) or not (ev.get("type") is String):
			continue
		var type: String = ev.type
		if type == "swing":
			_dernier_coup = -1.0 if D6Js.truthy(ev.get("strike")) else Routage.nombre(ev.get("index"), -1.0)
		if not Routage.connu(type):
			stats.inconnus[type] = stats.inconnus.get(type, 0) + 1
			continue
		out.append({"ev": ev, "cle": Routage.cle(ev), "lourd": type == "hit" and Routage.coup_lourd(ev, _dernier_coup)})
	return out

func _grouper(entrees: Array) -> Dictionary:
	var groupes := {}
	for e in entrees:
		if e.cle == "" or not Routage.SONS.has(e.cle):
			continue
		if not groupes.has(e.cle):
			groupes[e.cle] = []
		groupes[e.cle].append(e)
	return groupes

## Clés par priorité décroissante ; à égalité, l'ordre d'arrivée (tri stable).
func _par_priorite(groupes: Dictionary) -> Array:
	var cles: Array = groupes.keys()
	var rang := {}
	for i in cles.size():
		rang[cles[i]] = i
	cles.sort_custom(func(a, b):
		var pa: int = Routage.SONS[a].priorite
		var pb: int = Routage.SONS[b].priorite
		return pa > pb or (pa == pb and rang[a] < rang[b]))
	return cles

# ---------------------------------------------------------------- voix et polyphonie

func _jouer_groupe(cle: String, liste: Array, t: float) -> void:
	var def: Dictionary = Routage.SONS[cle]
	var elus := _representants(cle, liste, def.par_image)
	var renfort := minf(RENFORT_MAX, 1.0 + RENFORT_PAR_DOUBLEMENT * log(float(liste.size()) / elus.size()) / log(2.0))
	stats.fusionnes += liste.size() - elus.size()
	for e in elus:
		if not _a_de_la_place(cle, def, t):
			stats.abandonnes += 1
			continue
		_jouer_entree(cle, def, e, renfort, t)

## Les `par_image` entrées les plus fortes du groupe (ordre d'arrivée sans critère de poids).
func _representants(cle: String, liste: Array, par_image: int) -> Array:
	if liste.size() <= par_image:
		return liste
	if not Routage.SONS_PESES.has(cle):
		return liste.slice(0, par_image)
	var peses: Array = []
	for i in liste.size():
		peses.append([Routage.poids(cle, liste[i].ev), i])
	peses.sort_custom(func(a, b): return a[0] > b[0] or (a[0] == b[0] and a[1] < b[1]))
	var out: Array = []
	for i in par_image:
		out.append(liste[peses[i][1]])
	return out

## Une voix = une entrée jouée ; elle peut superposer plusieurs recettes (corps + éclat de
## critique, mort + mort d'élite…), chacune sur son lecteur.
func _jouer_entree(cle: String, def: Dictionary, e: Dictionary, renfort: float, t: float) -> void:
	var volume: float = def.gain * renfort * Routage.attenuation(e.ev, partie.get("game") if partie != null else null)
	var hauteur := 1.0 + (randf() * 2.0 - 1.0) * VARIATION_HAUTEUR
	var fin := t
	for p in Routage.parties(cle, e.ev, e.lourd, hauteur):
		fin = maxf(fin, _lancer(p[0], volume * p[2], p[1], def.priorite, t))
	if fin > t:
		_noter_voix(cle, fin)
		stats.joues += 1

## Lance une recette sur un lecteur libre. Rend l'instant où il se libère, 0 si rien n'a joué.
func _lancer(nom: String, volume: float, hauteur: float, priorite: int, t: float) -> float:
	if not _flux.has(nom):
		stats["pas_prets" if Recettes.table().has(nom) else "manquantes"] += 1
		return 0.0
	var i := _lecteur_libre(priorite, t)
	if i == -1:
		return 0.0
	var son: Dictionary = _flux[nom]
	var h := clampf(hauteur, HAUTEUR_MIN, HAUTEUR_MAX)
	var lecteur := _lecteurs[i]
	lecteur.stream = son.flux
	lecteur.pitch_scale = h
	lecteur.volume_db = linear_to_db(maxf(VOLUME_MIN, volume * son.niveau))
	lecteur.play()
	_fins[i] = t + son.duree / h + MARGE_FIN
	return _fins[i]

func _plafond(priorite: int) -> int:
	return VOIX_MAX if priorite >= PRIORITE_VITALE else VOIX_MAX - RESERVE_VITALE

## Premier lecteur libre, ou -1 si le plafond (selon la priorité) est atteint.
func _lecteur_libre(priorite: int, t: float) -> int:
	var libre := -1
	var occupes := 0
	for i in _lecteurs.size(): # vide tant que la scène n'est pas prête : rien ne joue
		if _fins[i] > t:
			occupes += 1
		elif libre == -1:
			libre = i
	return libre if occupes < _plafond(priorite) else -1

func _a_de_la_place(cle: String, def: Dictionary, t: float) -> bool:
	if _voix.get(cle, []).size() >= def.voix:
		return false
	return _lecteur_libre(def.priorite, t) != -1

func _noter_voix(cle: String, fin: float) -> void:
	if not _voix.has(cle):
		_voix[cle] = []
	_voix[cle].append(fin)

## Retire les voix éteintes.
func _purger(t: float) -> void:
	for cle in _voix:
		_voix[cle] = _voix[cle].filter(func(fin): return fin > t)

func _maintenant() -> float:
	return Time.get_ticks_usec() / 1000000.0 + _avance

# ---------------------------------------------------------------- vibrations

## Une seule vibration par image : la plus longue demandée.
func _vibrer_pour(entrees: Array) -> void:
	if not _vibrations:
		return
	var ms := 0
	for e in entrees:
		ms = maxi(ms, Routage.vibration(e.ev, e.lourd))
	if ms <= 0:
		return
	var t := _maintenant() * 1000.0
	if t < _vibration_jusqua and ms <= _vibration_ms:
		return
	Input.vibrate_handheld(ms)
	_vibration_jusqua = t + ms + VIBRATION_ECART_MS
	_vibration_ms = ms
	stats.vibrations += 1
	vibration.emit(ms)
