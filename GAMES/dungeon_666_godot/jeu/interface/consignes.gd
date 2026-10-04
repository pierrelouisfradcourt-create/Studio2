extends RefCounted
## LA TABLE des consignes de l'accueil du premier joueur (jeu/interface/accueil.gd), et les
## LECTURES de l'état qui disent quand une consigne a lieu d'être. Rien n'est écrit dans la
## simulation, aucune règle de jeu ici : on lit `partie.game` et les événements publiés.
##   const Consignes = preload("res://jeu/interface/consignes.gd")
##
## Une ligne par consigne, dans l'ordre où on les apprend :
##   id        : l'identifiant retenu dans les réglages (`reglages_jeu.json`, champ `accueil.acquis`)
##   texte     : la phrase ; une seule pour tous les appareils, ou une par appareil
##               {clavier, manette, tactile} (à défaut d'une clé, celle du clavier)
##   commande  : la commande nommée (attack, dash, « move », ou « competence » / « gadget » : le
##               premier emplacement qui en porte une — voir `commande()`) : son libellé (touche,
##               bouton de manette) vient du HUD, son pictogramme du kit équipé, et son bouton bat
##               à l'écran. Absente : la phrase seule. L'ultime nomme l'ATTAQUE : il part en la
##               gardant appuyée (combat V3).
##   quand     : la lecture (plus bas) qui doit être vraie pour que la consigne se montre
##   fait      : les événements de simulation qui prouvent que le joueur a FAIT le geste
##   parcours  : (au lieu de `fait`) la distance, en unités de salle, que le héros doit avoir parcourue
##   contexte  : vrai = le geste ne compte que si `quand` était vrai à ce moment-là
##   urgent    : vrai = consigne de circonstance, elle passe devant celles qui peuvent attendre
##   patience  : secondes d'affichage cumulées au bout desquelles la consigne est tenue pour vue
##               (elle ne revient plus) ; absente : elle attend le geste
const TABLE := [
	{"id": "bouger", "commande": "move", "quand": "en_jeu", "parcours": 90.0,
		"texte": {"clavier": "Déplace-toi", "tactile": "Glisse le pouce gauche pour bouger"}},
	{"id": "attaquer", "commande": "attack", "quand": "en_jeu", "fait": ["attackStart"],
		"texte": "Frappe les démons"},
	{"id": "dash", "commande": "dash", "quand": "en_jeu", "fait": ["dash"],
		"texte": "Traverse les attaques d'un dash"},
	{"id": "rouge", "commande": "dash", "quand": "telegraphe", "fait": ["dash"], "contexte": true, "urgent": true, "patience": 10.0,
		"texte": "Esquive le rouge"},
	{"id": "competence", "commande": "competence", "quand": "competence_prete", "fait": ["castStart", "skill"], "patience": 14.0,
		"texte": {"clavier": "Lance ta compétence", "tactile": "Compétence : glisse pour viser, relâche"}},
	{"id": "gadget", "commande": "gadget", "quand": "gadget_pret", "fait": ["gadget"], "patience": 14.0,
		"texte": "Utilise ton gadget"},
	{"id": "super", "commande": "attack", "quand": "super_pret", "fait": ["super"], "urgent": true, "patience": 14.0,
		"texte": "Jauge pleine : garde le bouton d'attaque appuyé"},
	{"id": "recompense", "quand": "recompense", "fait": ["choiceOpen"], "urgent": true,
		"texte": "Marche sur la récompense pour la prendre"},
	{"id": "porte", "quand": "portes", "fait": ["floorEnter"], "contexte": true, "urgent": true,
		"texte": "Franchis une porte : elle annonce ta récompense"},
	{"id": "mort", "quand": "revenu", "urgent": true, "patience": 9.0,
		"texte": "Les bénédictions se regagnent.\nDépense tes Âmes en Ville."},
]
## Objets d'interaction que la consigne « recompense » désigne (les autres ont leur propre écran).
const RECOMPENSES := ["boon", "loot"]
## Commandes qui nomment une SORTE d'action plutôt qu'un bouton : la sorte lue par slot_view.
const SORTES := {"competence": "skill", "gadget": "gadget"}

static func trouver(id: String) -> Dictionary:
	for c in TABLE:
		if c.id == id:
			return c
	return {}

static func ids() -> Array:
	return TABLE.map(func(c: Dictionary) -> String: return c.id)

## La phrase de la consigne pour l'appareil (« clavier », « manette », « tactile »).
static func texte(c: Dictionary, appareil: String) -> String:
	var t = c.get("texte", "")
	if t is Dictionary:
		return String(t.get(appareil, t.get("clavier", "")))
	return String(t)

## La commande qu'une consigne désigne DANS CETTE PARTIE : « competence » et « gadget » deviennent
## le premier emplacement (skill1, skill2, skill3) qui en porte une ; "" si aucun n'en porte.
static func commande(c: Dictionary, game) -> String:
	var cmd := String(c.get("commande", ""))
	if not SORTES.has(cmd):
		return cmd
	var index := _emplacement(game, SORTES[cmd]) if game is Dictionary else -1
	return "skill%d" % (index + 1) if index >= 0 else ""

## Premier emplacement qui porte une action de la sorte (« skill » ou « gadget »), prête si
## `prete` ; -1 s'il n'y en a pas.
static func _emplacement(game: Dictionary, sorte: String, prete: bool = false) -> int:
	for i in D6Loadout.SLOTS:
		var vue = D6Loadout.slot_view(game, i)
		if vue != null and vue.kind == sorte and (vue.ready or not prete):
			return i
	return -1

## Les consignes n'ont cours que dans une vraie descente : ni arène d'essai, ni entraînement.
static func ouvert(game) -> bool:
	return game is Dictionary and not D6Js.truthy(game.get("sandbox")) and not D6Js.truthy(game.get("practice"))

# ---------------------------------------------------------------- lectures de l'état (`quand`)

static func quand(nom: String, game: Dictionary) -> bool:
	match nom:
		"en_jeu": return en_jeu(game)
		"telegraphe": return en_jeu(game) and telegraphe(game)
		"competence_prete": return combat(game) and _emplacement(game, "skill", true) >= 0
		"gadget_pret": return combat(game) and _emplacement(game, "gadget", true) >= 0
		"super_pret": return en_jeu(game) and game.player.superCharge >= 1.0
		"recompense": return en_jeu(game) and _objet_libre(game) and game.room.interact.kind in RECOMPENSES
		"portes": return en_jeu(game) and D6Js.truthy(game.room.get("cleared")) and not _objet_libre(game) and _porte_ouverte(game)
		"revenu": return en_jeu(game) and game.telemetry.deaths > 0.0
	return false

## Le héros est debout et la partie se joue (ni menu, ni agonie).
static func en_jeu(game: Dictionary) -> bool:
	return game.mode == "play" and game.player.state != "dead" and game.player.hp > 0.0

## Un ennemi est là, apparu et visible : il y a quelqu'un à frapper.
static func combat(game: Dictionary) -> bool:
	if not en_jeu(game):
		return false
	for e in game.enemies:
		if not D6Js.truthy(e.get("dead")) and not D6Js.truthy(e.get("hidden")) and not float(e.get("spawnT", 0.0)) > 0.0:
			return true
	return false

## Une attaque ennemie est annoncée en rouge au sol (les alertes inoffensives ne comptent pas).
static func telegraphe(game: Dictionary) -> bool:
	for e in game.enemies:
		var t = e.get("tele")
		if t is Dictionary and not D6Js.truthy(e.get("dead")) and not D6Js.truthy(t.get("harmless")):
			return true
	for h in game.hazards:
		if D6Js.truthy(h.get("hitsPlayer")) and not D6Js.truthy(h.get("done")):
			return true
	return false

static func _objet_libre(game: Dictionary) -> bool:
	var objet = game.room.get("interact")
	return objet is Dictionary and not D6Js.truthy(objet.get("used"))

static func _porte_ouverte(game: Dictionary) -> bool:
	for porte in game.room.get("doors", []):
		if D6Js.truthy(porte.get("open")):
			return true
	return false
