class_name StudioReglages
extends RefCounted

## Réglages du joueur, mémorisés à part de la partie (effacer sa partie ne remet pas le son à fond).
## Fichier : user://reglages.cfg (ConfigFile, lisible à la main).
##
## Un jeu peut AJOUTER ses propres clés via `defauts_jeu` ; une clé inconnue est refusée
## (évite qu'une faute de frappe crée un réglage fantôme).

signal change(cle: String, valeur: Variant)

const CHEMIN_DEFAUT := "user://reglages.cfg"
const SECTION := "reglages"
const BUS_MUSIQUE := "Musique"
const BUS_EFFETS := "Effets"
const VOLUME_MUET_DB := -80.0
const VOLUME_MIN_LINEAIRE := 0.0001

## Muet par défaut : décision Pierre 2026-09-12 (Kitten Factory), reprise pour tout le studio.
const DEFAUTS := {
	"musique_on": false, "musique_vol": 0.6,
	"effets_on": false, "effets_vol": 0.8,
	"plein_ecran": false, "langue": "fr",
}

var chemin: String
var _valeurs: Dictionary = {}
var _defauts: Dictionary = {}


func _init(defauts_jeu: Dictionary = {}, chemin_fichier: String = CHEMIN_DEFAUT) -> void:
	chemin = chemin_fichier
	_defauts = DEFAUTS.duplicate()
	_defauts.merge(defauts_jeu, true)
	_valeurs = _defauts.duplicate()


func lire(cle: String) -> Variant:
	return _valeurs.get(cle, null)


## Retourne false si la clé n'existe pas ou si le type ne correspond pas au défaut.
func regler(cle: String, valeur: Variant) -> bool:
	if not _defauts.has(cle):
		push_warning("Réglage inconnu : %s" % cle)
		return false
	var attendu := typeof(_defauts[cle])
	if attendu == TYPE_FLOAT and valeur is int:
		valeur = float(valeur)
	if typeof(valeur) != attendu:
		push_warning("Réglage %s : type %s attendu" % [cle, type_string(attendu)])
		return false
	if _valeurs[cle] == valeur:
		return true
	_valeurs[cle] = valeur
	change.emit(cle, valeur)
	return true


func tout() -> Dictionary:
	return _valeurs.duplicate()


func charger() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(chemin) != OK:
		return
	for cle in _defauts:
		if cfg.has_section_key(SECTION, cle):
			var v: Variant = cfg.get_value(SECTION, cle)
			if typeof(v) == typeof(_defauts[cle]) or (_defauts[cle] is float and v is int):
				_valeurs[cle] = float(v) if _defauts[cle] is float else v


func enregistrer() -> Error:
	var cfg := ConfigFile.new()
	for cle in _valeurs:
		cfg.set_value(SECTION, cle, _valeurs[cle])
	return cfg.save(chemin)


## Pousse les réglages vers le moteur : volumes des bus, plein écran. Sans effet en headless.
func appliquer() -> void:
	StudioReglages.assurer_bus()
	_appliquer_bus(BUS_MUSIQUE, bool(_valeurs["musique_on"]), float(_valeurs["musique_vol"]))
	_appliquer_bus(BUS_EFFETS, bool(_valeurs["effets_on"]), float(_valeurs["effets_vol"]))
	if DisplayServer.get_name() != "headless":
		var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if bool(_valeurs["plein_ecran"]) else DisplayServer.WINDOW_MODE_WINDOWED
		if DisplayServer.window_get_mode() != mode:
			DisplayServer.window_set_mode(mode)
	TranslationServer.set_locale(String(_valeurs["langue"]))


## Crée les bus Musique et Effets s'ils n'existent pas (un jeu n'a rien à configurer à la main).
static func assurer_bus() -> void:
	for nom in [BUS_MUSIQUE, BUS_EFFETS]:
		if AudioServer.get_bus_index(nom) == -1:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, nom)
			AudioServer.set_bus_send(i, "Master")


func _appliquer_bus(nom: String, actif: bool, volume: float) -> void:
	var i := AudioServer.get_bus_index(nom)
	if i == -1:
		return
	AudioServer.set_bus_mute(i, not actif)
	var lin := clampf(volume, VOLUME_MIN_LINEAIRE, 1.0)
	AudioServer.set_bus_volume_db(i, linear_to_db(lin) if actif else VOLUME_MUET_DB)
