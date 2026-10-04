extends RefCounted
## Le profil PERMANENT du joueur sur disque (classe, équipement, coffre, déblocages, Âmes, or,
## checkpoints) et ses réglages. Aucune règle de jeu : le contenu du profil appartient à
## D6Profile (sim/profile.gd) ; ici on ne fait que lire, écrire et archiver.
##
## Écriture par StudioStockage (kit du studio) : fichier temporaire puis renommage, l'ancien
## devient .bak. Une progression n'est JAMAIS remplacée sans copie : `archiver()` d'abord.

const FICHIER := "profil.json"
const FICHIER_REGLAGES := "reglages_jeu.json"
## Variable d'environnement : dossier de données pour les ESSAIS (captures, bancs). Un essai
## automatique ne doit jamais lire ni écrire le vrai profil du joueur.
const ENV_DOSSIER := "D666_DONNEES"
const VERSION := 1
## `feel` : les écarts des « Réglages du feel » au tuning de référence, {chemin de tuning: nombre}.
## `accueil` : les consignes du premier joueur (jeu/interface/accueil.gd) : `actif` (montrées ou
## coupées) et `acquis`, les identifiants de celles que ce joueur a déjà apprises.
const REGLAGES_DEFAUT := {"sound": true, "haptics": true, "shake": 1.0, "lab": {"dashStrike": "fin", "hitstop": "global", "comboMobility": "mobile"}, "feel": {}, "accueil": {"actif": true, "acquis": []}}

static func chemin(fichier: String) -> String:
	var dossier := OS.get_environment(ENV_DOSSIER)
	if dossier == "":
		return "user://" + fichier
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dossier))
	return dossier.path_join(fichier)

## Profil lu et assaini (un profil absent ou abîmé donne un profil neuf, sans rien écrire).
static func charger(tuning: Dictionary) -> Dictionary:
	var lu: Dictionary = StudioStockage.lire(chemin(FICHIER), VERSION)
	var brut = lu.donnees if lu.ok else {}
	return D6Profile.sanitize_profile(D6Js.decode(brut), tuning)

static func enregistrer(profil: Dictionary) -> bool:
	return StudioStockage.ecrire(chemin(FICHIER), profil, VERSION) == OK

## Copie datée du profil enregistré, à faire AVANT de le remplacer par un profil neuf.
static func archiver() -> String:
	var source := chemin(FICHIER)
	if not FileAccess.file_exists(source):
		return ""
	var cible := chemin("profil.archive.%d.json" % int(Time.get_unix_time_from_system()))
	var err := DirAccess.copy_absolute(ProjectSettings.globalize_path(source), ProjectSettings.globalize_path(cible))
	return cible if err == OK else ""

static func charger_reglages() -> Dictionary:
	var out: Dictionary = REGLAGES_DEFAUT.duplicate(true)
	var lu: Dictionary = StudioStockage.lire(chemin(FICHIER_REGLAGES), VERSION)
	if lu.ok:
		for k in out:
			if lu.donnees.has(k) and typeof(lu.donnees[k]) == typeof(out[k]):
				out[k] = lu.donnees[k]
	out.lab = _labo_valide(out.lab)
	out.feel = _feel_valide(out.feel)
	out.accueil = _accueil_valide(out.accueil)
	return out

static func enregistrer_reglages(reglages: Dictionary) -> bool:
	return StudioStockage.ecrire(chemin(FICHIER_REGLAGES), reglages, VERSION) == OK

## Consignes de l'accueil validées : un oui/non et une liste d'identifiants, sans doublon.
static func _accueil_valide(accueil) -> Dictionary:
	var out := {"actif": true, "acquis": []}
	if not (accueil is Dictionary):
		return out
	out.actif = accueil.get("actif") != false
	var acquis = accueil.get("acquis")
	for id in acquis if acquis is Array else []:
		if id is String and not out.acquis.has(id):
			out.acquis.append(id)
	return out

## Écarts du feel validés : seulement des paires {chemin: nombre fini} ; un fichier abîmé ne casse rien.
static func _feel_valide(feel) -> Dictionary:
	var out := {}
	if not (feel is Dictionary):
		return out
	for chemin in feel:
		var v = feel[chemin]
		if chemin is String and (v is float or v is int) and is_finite(float(v)):
			out[chemin] = float(v)
	return out

## Choix du labo validés : une variante inconnue retombe sur celle de référence.
static func _labo_valide(lab) -> Dictionary:
	var axes: Dictionary = D6Data.tables().lab.LAB_AXES
	var out := {}
	for axe in axes:
		var choix = lab.get(axe) if lab is Dictionary else null
		out[axe] = choix if axes[axe].options.has(choix) else axes[axe].reference
	return out
