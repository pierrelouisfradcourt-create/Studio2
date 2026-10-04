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
##   gestes    : (au lieu de `texte`) la phrase selon le DÉPLACEMENT DE LA CLASSE jouée
##               {dash, saut, roulade} (D6Player.move_kind) : « Dashe », « Saute », « Roule » ;
##               un « %s » y est remplacé par le terrain bas le plus proche (TERRAINS)
##   commande  : la commande nommée (attack, dash, « move », ou « competence » / « gadget » : le
##               premier des TROIS emplacements qui en porte une — voir `commande()`) : son libellé
##               (touche, bouton de manette) vient du HUD, son pictogramme du kit équipé, et son
##               bouton bat à l'écran, là où il est (arc tactile, rangée du bureau). Absente : la phrase seule. L'ultime nomme l'ATTAQUE : il part en la
##               gardant appuyée (combat V3).
##   quand     : la lecture (plus bas) qui doit être vraie pour que la consigne se montre
##   fait      : les événements de simulation qui prouvent que le joueur a FAIT le geste
##   lecture   : (au lieu de `fait`) la lecture de l'état qui prouve le geste, vue à n'importe quelle image
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
		"gestes": {"dash": "Dashe à travers les attaques", "saut": "Saute par-dessus les attaques", "roulade": "Roule à travers les attaques"}},
	{"id": "rouge", "commande": "dash", "quand": "telegraphe", "fait": ["dash"], "contexte": true, "urgent": true, "patience": 10.0,
		"gestes": {"dash": "Esquive le rouge : dashe", "saut": "Esquive le rouge : saute", "roulade": "Esquive le rouge : roule"}},
	{"id": "terrain", "commande": "dash", "quand": "terrain_proche", "lecture": "franchit", "urgent": true, "patience": 14.0,
		"gestes": {"dash": "Franchis %s d'un dash", "saut": "Franchis %s d'un saut", "roulade": "Franchis %s d'une roulade"}},
	{"id": "competence", "commande": "competence", "quand": "competence_prete", "fait": ["castStart", "skill"], "patience": 14.0,
		"texte": {"clavier": "Lance une compétence", "tactile": "Compétence : glisse pour viser, relâche"}},
	{"id": "gadget", "commande": "gadget", "quand": "gadget_pret", "fait": ["gadget"], "patience": 14.0,
		"texte": "Utilise une compétence à charges"},
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
## Le terrain bas, tel que la salle le nomme (room.low[].kind), dit au joueur.
const TERRAINS := {"river": "la rivière", "barrier": "l'obstacle"}
## Distance (u) du héros au bord d'un terrain bas en deçà de laquelle la consigne « terrain » a
## lieu d'être : un seuil d'AFFICHAGE (à peu près la portée du plus court déplacement), pas une règle.
const PRES := 120.0

static func trouver(id: String) -> Dictionary:
	for c in TABLE:
		if c.id == id:
			return c
	return {}

static func ids() -> Array:
	return TABLE.map(func(c: Dictionary) -> String: return c.id)

## La phrase de la consigne pour l'appareil (« clavier », « manette », « tactile ») ; avec `game`,
## une consigne à `gestes` parle du déplacement de la classe jouée (sans partie : celui du dash).
static func texte(c: Dictionary, appareil: String, game = null) -> String:
	var gestes = c.get("gestes")
	if gestes is Dictionary:
		var sorte: String = D6Player.move_kind(game) if game is Dictionary else D6Loadout.DEFAULT_MOVE
		var phrase := String(gestes.get(sorte, gestes.get(D6Loadout.DEFAULT_MOVE, "")))
		if not phrase.contains("%s"):
			return phrase
		return phrase % TERRAINS.get(terrain_proche(game) if game is Dictionary else "", TERRAINS.river)
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
		"terrain_proche": return en_jeu(game) and terrain_proche(game) != ""
		"franchit": return franchit(game)
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

## La sorte (« river », « barrier ») du terrain bas le plus proche du héros, à moins de PRES de son
## bord ; "" s'il n'y en a pas. On lit les rectangles de la salle (room.low), rien d'autre.
static func terrain_proche(game: Dictionary) -> String:
	var p: Dictionary = game.player
	var ici := Vector2(p.x, p.y)
	var sorte := ""
	var mini := PRES + float(p.r)
	for o in game.room.get("low", []):
		var d := ici.distance_to(ici.clamp(Vector2(o.x0, o.y0), Vector2(o.x1, o.y1)))
		if d < mini:
			mini = d
			sorte = String(o.get("kind", "river"))
	return sorte

## Le héros est en plein franchissement : son déplacement de classe (ou son Bond) le porte
## AU-DESSUS d'un terrain bas. La simulation ne l'y laisse jamais : il finira sur la terre ferme.
static func franchit(game: Dictionary) -> bool:
	var p: Dictionary = game.player
	return D6Player.crossing(game) and D6Physics.low_at(game.room, p.x, p.y, p.r)

static func _objet_libre(game: Dictionary) -> bool:
	var objet = game.room.get("interact")
	return objet is Dictionary and not D6Js.truthy(objet.get("used"))

static func _porte_ouverte(game: Dictionary) -> bool:
	for porte in game.room.get("doors", []):
		if D6Js.truthy(porte.get("open")):
			return true
	return false
