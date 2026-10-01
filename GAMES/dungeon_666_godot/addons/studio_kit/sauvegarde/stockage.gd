class_name StudioStockage
extends RefCounted

## Sauvegarde sur disque, commune à tous les jeux du studio.
##
## Hérite de Kitten Factory (sauvegarde.gd V4) ce qui marchait : enveloppe JSON versionnée,
## entiers remis en forme. Ajoute ce qui manquait :
##   - MIGRATIONS : une partie d'une version antérieure est montée pas à pas, jamais rejetée ;
##   - ÉCRITURE ATOMIQUE : on écrit un .tmp puis on renomme — un crash en pleine écriture
##     ne détruit jamais la partie précédente ;
##   - COPIE DE SECOURS : l'ancien fichier devient .bak ; si le principal est illisible, on lit le .bak.
##
## Aucune logique de jeu : le jeu donne un Dictionary, reçoit un Dictionary.

const SUFFIXE_TMP := ".tmp"
const SUFFIXE_SECOURS := ".bak"

enum Source { AUCUNE, PRINCIPAL, SECOURS }


## Écrit `donnees` sous la version `version`. Retourne OK ou le code d'erreur Godot.
static func ecrire(chemin: String, donnees: Dictionary, version: int) -> Error:
	var enveloppe := {"version": version, "ecrit_le": int(Time.get_unix_time_from_system()), "donnees": donnees}
	var tmp := chemin + SUFFIXE_TMP
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(enveloppe, "\t"))
	f.close()
	var abs_principal := ProjectSettings.globalize_path(chemin)
	var abs_secours := abs_principal + SUFFIXE_SECOURS
	if FileAccess.file_exists(chemin):
		if FileAccess.file_exists(chemin + SUFFIXE_SECOURS):
			DirAccess.remove_absolute(abs_secours)
		var err_bak := DirAccess.rename_absolute(abs_principal, abs_secours)
		if err_bak != OK:
			return err_bak
	return DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp), abs_principal)


## Lit une sauvegarde et la monte jusqu'à `version_courante`.
## `migrations` : {version_n (int) -> Callable(Dictionary) -> Dictionary} qui produit la version n+1.
## Retourne {ok, donnees, version_lue, source (Source), erreur (String)}.
static func lire(chemin: String, version_courante: int, migrations: Dictionary = {}) -> Dictionary:
	var principal := _lire_enveloppe(chemin)
	var source := Source.PRINCIPAL
	if not principal["ok"]:
		var secours := _lire_enveloppe(chemin + SUFFIXE_SECOURS)
		if not secours["ok"]:
			return _echec(String(principal["erreur"]))
		principal = secours
		source = Source.SECOURS
	var resultat := migrer(principal["donnees"], int(principal["version"]), version_courante, migrations)
	resultat["source"] = source
	return resultat


## Monte `donnees` de `depuis` à `vers`. Une version du futur est refusée (jeu plus ancien que la partie).
static func migrer(donnees: Dictionary, depuis: int, vers: int, migrations: Dictionary) -> Dictionary:
	if depuis > vers:
		return _echec("partie de version %d plus récente que le jeu (%d)" % [depuis, vers])
	var courant := donnees
	for v in range(depuis, vers):
		if not migrations.has(v):
			return _echec("aucune migration depuis la version %d" % v)
		var suivant: Variant = (migrations[v] as Callable).call(courant.duplicate(true))
		if not (suivant is Dictionary):
			return _echec("la migration %d -> %d n'a pas rendu de Dictionary" % [v, v + 1])
		courant = suivant
	return {"ok": true, "donnees": courant, "version_lue": depuis, "source": Source.AUCUNE, "erreur": ""}


static func existe(chemin: String) -> bool:
	return FileAccess.file_exists(chemin) or FileAccess.file_exists(chemin + SUFFIXE_SECOURS)


## Efface la partie ET sa copie de secours (nouvelle partie).
static func effacer(chemin: String) -> void:
	for c in [chemin, chemin + SUFFIXE_SECOURS, chemin + SUFFIXE_TMP]:
		if FileAccess.file_exists(c):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(c))


## JSON ne distingue pas 3 de 3.0 : remet en entiers les `cles` présentes dans `d` (non récursif).
static func entiers(d: Dictionary, cles: Array) -> void:
	for cle in cles:
		if d.has(cle) and (d[cle] is float or d[cle] is int):
			d[cle] = int(d[cle])


static func _lire_enveloppe(chemin: String) -> Dictionary:
	if not FileAccess.file_exists(chemin):
		return {"ok": false, "erreur": "absent"}
	var texte := FileAccess.get_file_as_string(chemin)
	var brut: Variant = JSON.parse_string(texte)
	if not (brut is Dictionary):
		return {"ok": false, "erreur": "illisible"}
	var d: Dictionary = brut
	if not d.has("version") or not (d.get("donnees", null) is Dictionary):
		return {"ok": false, "erreur": "enveloppe incomplète"}
	return {"ok": true, "version": int(d["version"]), "donnees": d["donnees"]}


static func _echec(raison: String) -> Dictionary:
	return {"ok": false, "donnees": {}, "version_lue": -1, "source": Source.AUCUNE, "erreur": raison}
