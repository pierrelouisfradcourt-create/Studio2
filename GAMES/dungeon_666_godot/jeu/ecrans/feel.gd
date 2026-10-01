extends RefCounted
## L'état des « Réglages du feel » (outil de mise au point, portage de src/ui/tuning.mjs) : la
## liste des réglages offerts, leurs valeurs de départ, et les écarts choisis par le testeur.
## C'est le SEUL endroit où une vue écrit dans `game.tuning` : c'est son rôle, comme sur le web —
## et seulement quand le testeur bouge une réglette, pour la partie EN COURS.
## Les écarts survivent à la fermeture : `app.regler_feel` les range dans les réglages (clé `feel`,
## jeu/profil.gd), et chaque partie neuve NAÎT avec eux (`surcharges` → `options.tuning` de
## `demarrer_descente`, jeu/principal.gd). Rien n'est réappliqué après coup.

## Un écart a bougé (réglette, réinitialisation) : à retenir par l'application.
signal change

const REGLAGES := [
	{"path": "player.speed", "label": "Vitesse de course", "min": 180.0, "max": 460.0, "step": 10.0},
	{"path": "player.accelTime", "label": "Temps d'accélération (s)", "min": 0.0, "max": 0.2, "step": 0.001},
	{"path": "dash.distance", "label": "Distance du dash", "min": 80.0, "max": 300.0, "step": 5.0},
	{"path": "dash.duration", "label": "Durée du dash (s)", "min": 0.08, "max": 0.3, "step": 0.01},
	{"path": "dash.iframes", "label": "Invulnérabilité du dash (s)", "min": 0.0, "max": 0.4, "step": 0.01},
	{"path": "dash.recharge", "label": "Recharge d'une charge (s)", "min": 0.2, "max": 2.5, "step": 0.05},
	{"path": "dash.charges", "label": "Charges de dash", "min": 1.0, "max": 4.0, "step": 1.0},
	{"path": "combo.0.damage", "label": "Dégâts coup 1", "min": 4.0, "max": 30.0, "step": 1.0},
	{"path": "combo.2.damage", "label": "Dégâts coup 3", "min": 8.0, "max": 60.0, "step": 1.0},
	{"path": "combo.2.hitstop", "label": "Gel d'impact coup 3 (s)", "min": 0.0, "max": 0.2, "step": 0.005},
	{"path": "combo.0.hitstop", "label": "Gel d'impact coups 1-2 (s)", "min": 0.0, "max": 0.12, "step": 0.005, "also": ["combo.1.hitstop"]},
	{"path": "autoAim.range", "label": "Portée de la visée auto", "min": 120.0, "max": 500.0, "step": 10.0},
	{"path": "super.chargeDamage", "label": "Dégâts pour remplir le Super", "min": 100.0, "max": 1500.0, "step": 20.0},
	{"path": "combat.maxAttackers", "label": "Ennemis attaquant ensemble", "min": 1.0, "max": 6.0, "step": 1.0},
	{"path": "enemies.imp.windup", "label": "Télégraphe diablotin (s)", "min": 0.2, "max": 0.9, "step": 0.02},
	{"path": "enemies.archer.windup", "label": "Télégraphe archer (s)", "min": 0.3, "max": 1.2, "step": 0.02},
	{"path": "enemies.imp.speed", "label": "Vitesse diablotin", "min": 80.0, "max": 300.0, "step": 5.0},
]

## Écarts au défaut choisis par le testeur : chemin -> valeur.
var ecarts: Dictionary = {}
var _defauts: Dictionary = {} # chemin -> valeur de départ de la partie en cours
var _tuning = null

## Blocs du tuning qui ne sont que des RENVOIS vers le kit équipé (sim/loadout.gd) : le chemin
## réel dépend de l'arme portée et du Super de la classe ({weaponType, superId}).
const RENVOIS := {"combo": "weapons.%s.combo", "super": "supers.%s"}
const CLE_DU_KIT := {"combo": "weaponType", "super": "superId"}

## À chaque partie (née avec les écarts `enregistres`) : retient la valeur de RÉFÉRENCE de chaque
## réglage — celle du tuning de référence `contenu` s'il a un écart, celle de la partie sinon.
func nouvelle_partie(game: Dictionary, contenu: Dictionary, enregistres: Dictionary) -> void:
	_tuning = game.tuning
	var kit = game.get("kit")
	ecarts.clear()
	_defauts.clear()
	for r in REGLAGES:
		var reference = _lire(contenu, _chemin_reel(r.path, kit if kit is Dictionary else {}))
		if enregistres.has(r.path) and reference != null:
			ecarts[r.path] = float(enregistres[r.path])
			_defauts[r.path] = reference
		else:
			_defauts[r.path] = _lire(_tuning, r.path)

## Les écarts {chemin: valeur} en SURCHARGES de tuning, pour `options.tuning` de D6Game.create_game.
## `kit` : {weaponType, superId} du héros qui va descendre. Un tableau (les coups d'un combo) est
## recopié en entier depuis `contenu` : la fusion des surcharges remplace les tableaux d'un bloc.
static func surcharges(enregistres: Dictionary, contenu: Dictionary, kit: Dictionary) -> Dictionary:
	var out := {}
	for r in REGLAGES:
		if not enregistres.has(r.path):
			continue
		for chemin in [r.path] + r.get("also", []):
			_poser(out, contenu, _chemin_reel(chemin, kit).split("."), float(enregistres[r.path]))
	return out

## « combo.0.damage » → « weapons.lame.combo.0.damage » : le chemin dans le tuning de référence.
static func _chemin_reel(chemin: String, kit: Dictionary) -> String:
	var tete := chemin.get_slice(".", 0)
	if not RENVOIS.has(tete):
		return chemin
	return RENVOIS[tete] % str(kit.get(CLE_DU_KIT[tete], "")) + chemin.substr(tete.length())

## Pose `v` au bout du chemin `cles` dans `out`, en suivant la forme de la référence `ref`.
static func _poser(out: Dictionary, ref, cles: PackedStringArray, v: float) -> void:
	var cible = out
	for i in cles.size() - 1:
		ref = _suivre(ref, cles[i])
		if ref == null:
			return
		if cible is Array:
			cible = cible[int(cles[i])]
			continue
		if not cible.has(cles[i]):
			cible[cles[i]] = ref.duplicate(true) if ref is Array else {}
		cible = cible[cles[i]]
	var derniere := cles[cles.size() - 1]
	if _suivre(ref, derniere) == null:
		return
	if cible is Array:
		cible[int(derniere)] = v
	else:
		cible[derniere] = v

func fin_de_partie() -> void:
	_tuning = null

func disponible() -> bool:
	return _tuning != null

func valeur(r: Dictionary) -> float:
	return float(D6Js.nz(_lire(_tuning, r.path), r.min)) if _tuning != null else float(r.min)

func defaut(r: Dictionary) -> float:
	return float(D6Js.nz(_defauts.get(r.path), r.min))

func a_change(r: Dictionary) -> bool:
	return absf(valeur(r) - defaut(r)) >= r.step / 2.0

## Le testeur a bougé une réglette : la partie en cours prend la valeur tout de suite.
func regler(r: Dictionary, v: float) -> void:
	if _tuning == null:
		return
	_appliquer(r, v)
	if a_change(r):
		ecarts[r.path] = v
	else:
		ecarts.erase(r.path)
	change.emit()

## Valeurs EXACTES de départ, sans passer par le pas de la réglette.
func reinitialiser() -> void:
	ecarts.clear()
	if _tuning == null:
		return
	for r in REGLAGES:
		_appliquer(r, defaut(r))
	change.emit()

## Les écarts au format JSON, à coller dans un rapport de playtest.
func texte_ecarts() -> String:
	return JSON.stringify(ecarts, " ")

## Texte d'une valeur, arrondie au pas de la réglette (0.083 et non 0.08299999).
static func texte_valeur(r: Dictionary, v: float) -> String:
	return D6Js.num_str(snappedf(v, r.step))

func _appliquer(r: Dictionary, v: float) -> void:
	_ecrire(_tuning, r.path, v)
	for autre in r.get("also", []):
		_ecrire(_tuning, autre, v)

## Suit un chemin « combo.0.damage » : clés de dictionnaire, index de tableau.
static func _suivre(objet, cle: String):
	if objet is Array:
		return objet[int(cle)] if cle.is_valid_int() and int(cle) < objet.size() else null
	if objet is Dictionary:
		return objet.get(cle)
	return null

static func _lire(tuning, chemin: String):
	var o = tuning
	for cle in chemin.split("."):
		o = _suivre(o, cle)
	return o

static func _ecrire(tuning, chemin: String, v: float) -> void:
	var cles := chemin.split(".")
	var o = tuning
	for i in cles.size() - 1:
		o = _suivre(o, cles[i])
	var derniere: String = cles[cles.size() - 1]
	if o is Array and derniere.is_valid_int():
		o[int(derniere)] = v
	elif o is Dictionary and o.has(derniere):
		o[derniere] = v
