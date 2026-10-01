class_name StudioInspecteur
extends Node

## Inspecteur d'exécution : regarde un jeu qui tourne et l'écrit dans un journal. OBSERVATION SEULE :
## il ne dessine rien (Node, pas CanvasItem), ne lit aucune entrée, ne modifie aucun état du jeu.
##
## ÉTEINT PAR DÉFAUT : sans demande, il se retire dès son entrée dans l'arbre (coût nul pour le joueur).
## L'allumer : variable d'environnement STUDIO_INSPECTEUR=1, ou argument « -- --inspecteur ».
## Sortie : $STUDIO_INSPECTEUR_SORTIE, sinon user://inspecteur/ ; une ligne JSON par instantané dans
## <session>.jsonl, et dernier.json (le plus récent).
##
## Configuration du jeu (optionnelle) : res://studio_inspecteur.json
##   periode_s  : secondes RÉELLES entre deux instantanés (défaut 5 ; indépendant d'Engine.time_scale)
##   etat       : {"script": "composer.gd", "propriete": "_etat", "cles": [...]} — nœud trouvé par le nom de
##                son script ; seules les clés listées sont COPIÉES (nombres, textes ; sinon leur taille)
##   groupes    : groupes dont on compte les nœuds (ex. « affordance »)
##   semantique : {"script": "res://…"} — la couche SÉMANTIQUE du jeu (un script du jeu, fonctions statiques
##                resume(etat), repondre(etat, question, id), charger_etat(chemin)) : elle reçoit l'état et en
##                fait une COPIE avant toute lecture. Ajoute « semantique » à chaque instantané et répond aux
##                QUESTIONS : écrire <sortie>/question.json {"question", "id"} -> réponse dans <sortie>/reponse.json
##   copie_etat : true -> <sortie>/etat.json (copie de l'état) à chaque instantané, pour l'interroger hors jeu
##   ancrage    : {"script": "res://…"} — la couche d'ANCRAGE monde <-> écran du jeu (StudioAncrage) :
##                questions « where_is <id> » / « ou_est » et « find_misplaced » (elle a besoin de la scène vivante)
## Installé comme autoload (StudioInspecteur) : un seul endroit, aucune ligne dans le code du jeu.

const CONFIG := "res://studio_inspecteur.json"
const SORTIE_DEFAUT := "user://inspecteur/"
const PERIODE_DEFAUT_S := 5.0
const TYPES_MONTRES := 12
const ERREURS_GARDEES := 20
const PERIODE_QUESTIONS_MS := 1000

var actif := false
var sortie := ""
var session := ""
var _config: Dictionary = {}
var _prochain_ms := 0
var _n := 0
var _capteur: _Capteur
var _semantique: Script
var _ancrage: Script
var _prochaine_question_ms := 0
var _questions := 0


## Capte les erreurs et avertissements du moteur. Appelé depuis n'importe quel fil : protégé.
class _Capteur extends Logger:
	var verrou := Mutex.new()
	var erreurs := 0
	var avertissements := 0
	var nouvelles: Array[String] = []

	func _log_error(function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		verrou.lock()
		if error_type == ERROR_TYPE_WARNING:
			avertissements += 1
		else:
			erreurs += 1
		if nouvelles.size() < 20:
			nouvelles.append("%s %s:%d %s %s" % ["AVERT." if error_type == ERROR_TYPE_WARNING else "ERREUR",
				file.get_file(), line, function, (rationale if rationale != "" else code)])
		verrou.unlock()

	func _log_message(_message: String, _error: bool) -> void:
		pass

	func relever() -> Dictionary:
		verrou.lock()
		var r := {"erreurs": erreurs, "avertissements": avertissements, "nouvelles": nouvelles.duplicate()}
		nouvelles.clear()
		verrou.unlock()
		return r


static func demande() -> bool:
	return OS.get_environment("STUDIO_INSPECTEUR") == "1" or OS.get_cmdline_user_args().has("--inspecteur")


func _ready() -> void:
	if not demande():
		# retrait en fin d'image, annulé si quelqu'un l'a allumé entre-temps (un test, un outil)
		_retirer_si_eteint.call_deferred()
		return
	activer(_lire_config(), OS.get_environment("STUDIO_INSPECTEUR_SORTIE"))


func _retirer_si_eteint() -> void:
	if not actif:
		queue_free()


## Allume l'inspecteur (appelé par _ready si demandé, ou directement par un test).
func activer(config: Dictionary, dossier: String = "") -> void:
	_config = config
	sortie = dossier if dossier != "" else SORTIE_DEFAUT
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(sortie))
	session = Time.get_datetime_string_from_system().replace(":", "-")
	process_mode = Node.PROCESS_MODE_ALWAYS
	_capteur = _Capteur.new()
	OS.add_logger(_capteur)
	var s := String((_config.get("semantique", {}) as Dictionary).get("script", ""))
	if s != "" and ResourceLoader.exists(s):
		_semantique = load(s)
	var a := String((_config.get("ancrage", {}) as Dictionary).get("script", ""))
	if a != "" and ResourceLoader.exists(a):
		_ancrage = load(a)
		StudioVisualAnchor.activer(true)   # la couche d'ancrage lit les dessins notés
	actif = true
	_prochain_ms = Time.get_ticks_msec() + 1000  # premier instantané après le démarrage du jeu


func _process(_delta: float) -> void:
	if not actif:
		return
	if Time.get_ticks_msec() >= _prochain_ms:
		_prochain_ms = Time.get_ticks_msec() + int(float(_config.get("periode_s", PERIODE_DEFAUT_S)) * 1000.0)
		ecrire(instantane())
	if (_semantique or _ancrage) and Time.get_ticks_msec() >= _prochaine_question_ms:
		_prochaine_question_ms = Time.get_ticks_msec() + PERIODE_QUESTIONS_MS
		repondre_question()


func _exit_tree() -> void:
	if actif:
		StudioVisualAnchor.activer(false)
		ecrire(instantane("fin"))
		OS.remove_logger(_capteur)
		actif = false


## Un instantané du jeu, sans rien y toucher.
func instantane(moment: String = "") -> Dictionary:
	_n += 1
	var arbre := get_tree()
	var i := {
		"n": _n, "moment": moment, "t_reel_s": snappedf(Time.get_ticks_msec() / 1000.0, 0.01),
		"image": Engine.get_process_frames(), "fps": Performance.get_monitor(Performance.TIME_FPS),
		"process_ms": snappedf(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, 0.01),
		"physique_ms": snappedf(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0, 0.01),
		"noeuds": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"noeuds_orphelins": int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),
		"objets": int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		"memoire_mo": snappedf(Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0, 0.1),
		"appels_dessin": int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		"vitesse": Engine.time_scale, "pause": arbre.paused if arbre else false,
		"scene": String(arbre.current_scene.name) if arbre and arbre.current_scene else "",
	}
	i["types"] = _types(arbre.root) if arbre else {}
	i["groupes"] = _groupes(arbre)
	i["etat"] = _etat(arbre)
	var etat_jeu := etat_du_jeu()
	if _semantique and not etat_jeu.is_empty():
		i["semantique"] = _semantique.resume(etat_jeu)
	if bool(_config.get("copie_etat", false)) and not etat_jeu.is_empty():
		_ecrire_fichier("etat.json", JSON.stringify(etat_jeu))
	if _capteur:
		i["journal"] = _capteur.relever()
	return i


func ecrire(i: Dictionary) -> void:
	var ligne := JSON.stringify(i)
	var chemin := sortie.path_join(session + ".jsonl")
	var f := FileAccess.open(chemin, FileAccess.READ_WRITE if FileAccess.file_exists(chemin) else FileAccess.WRITE)
	if f == null:
		return
	f.seek_end()
	f.store_line(ligne)
	f.close()
	var d := FileAccess.open(sortie.path_join("dernier.json"), FileAccess.WRITE)
	if d:
		d.store_string(JSON.stringify(i, "\t"))
		d.close()


## La question déposée dans <sortie>/question.json reçoit sa réponse dans <sortie>/reponse.json ;
## la question traitée est renommée question.<n>.traitee.json (rien n'est effacé).
func repondre_question() -> bool:
	var q_chemin := sortie.path_join("question.json")
	if not FileAccess.file_exists(q_chemin):
		return false
	var q: Variant = JSON.parse_string(FileAccess.get_file_as_string(q_chemin))
	_questions += 1
	DirAccess.rename_absolute(ProjectSettings.globalize_path(q_chemin),
		ProjectSettings.globalize_path(sortie.path_join("question.%d.traitee.json" % _questions)))
	var reponse: Variant = {"erreur": "question illisible : attendu {\"question\": …, \"id\": …}"}
	if q is Dictionary:
		reponse = _repondre(String(q.get("question", "")), String(q.get("id", "")))
	_ecrire_fichier("reponse.json", JSON.stringify({"n": _questions, "t_reel_s": snappedf(Time.get_ticks_msec() / 1000.0, 0.01),
		"question": q, "reponse": reponse}, "	"))
	return true


func _repondre(question: String, id: String) -> Variant:
	if question in ["where_is", "ou_est"] and _ancrage:
		return _ancrage.ou_est(get_tree().root, etat_du_jeu(), id)
	if question in ["find_misplaced", "mal_places"] and _ancrage:
		var m: Dictionary = _ancrage.mesurer(get_tree().root, etat_du_jeu())
		return {"bilan": StudioAncrage.bilan(m.get("mesures", [])), "decalage_du_cadre": m.get("decalage_du_cadre")}
	if _semantique:
		return _semantique.repondre(etat_du_jeu(), question, id)
	return {"erreur": "aucune couche pour la question « %s »" % question}


## L'état VIVANT du jeu (référence) : réservé à la couche sémantique, qui le copie avant de le lire.
func etat_du_jeu() -> Dictionary:
	var conf: Dictionary = _config.get("etat", {})
	var arbre := get_tree()
	if conf.is_empty() or arbre == null:
		return {}
	var n := trouver(arbre.root, String(conf.get("script", "")))
	var e: Variant = n.get(String(conf.get("propriete", ""))) if n else null
	return e if e is Dictionary else {}


func _ecrire_fichier(nom: String, texte: String) -> void:
	var f := FileAccess.open(sortie.path_join(nom), FileAccess.WRITE)
	if f:
		f.store_string(texte)
		f.close()


func _types(racine: Node) -> Dictionary:
	var compte := {}
	var pile: Array[Node] = [racine]
	while not pile.is_empty():
		var n: Node = pile.pop_back()
		compte[n.get_class()] = int(compte.get(n.get_class(), 0)) + 1
		pile.append_array(n.get_children())
	var cles := compte.keys()
	cles.sort_custom(func(a: String, b: String) -> bool: return compte[a] > compte[b])
	var out := {}
	for k in cles.slice(0, TYPES_MONTRES):
		out[k] = compte[k]
	return out


func _groupes(arbre: SceneTree) -> Dictionary:
	var out := {}
	for g in _config.get("groupes", []):
		out[g] = arbre.get_node_count_in_group(g) if arbre else 0
	return out


## COPIE des clés choisies de l'état du jeu (jamais une référence : l'inspecteur ne peut rien modifier).
func _etat(arbre: SceneTree) -> Dictionary:
	var conf: Dictionary = _config.get("etat", {})
	if conf.is_empty() or arbre == null:
		return {}
	var n := trouver(arbre.root, String(conf.get("script", "")))
	if n == null:
		return {"_": "nœud introuvable : %s" % conf.get("script", "")}
	var etat: Variant = n.get(String(conf.get("propriete", "")))
	if not (etat is Dictionary):
		return {"_": "propriété illisible : %s" % conf.get("propriete", "")}
	var out := {}
	for k in conf.get("cles", []):
		var v: Variant = (etat as Dictionary).get(k, null)
		out[k] = v if (v == null or v is int or v is float or v is bool or v is String) else (v.size() if (v is Array or v is Dictionary) else str(v))
	return out


static func trouver(racine: Node, nom_script: String) -> Node:
	if nom_script == "":
		return null
	var pile: Array[Node] = [racine]
	while not pile.is_empty():
		var n: Node = pile.pop_back()
		var s: Script = n.get_script()
		if s and s.resource_path.get_file() == nom_script:
			return n
		pile.append_array(n.get_children())
	return null


func _lire_config() -> Dictionary:
	var brut: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONFIG)) if FileAccess.file_exists(CONFIG) else null
	return brut if brut is Dictionary else {}
