# ui_shell.gd — MENU, HUD et ECRAN DE RESULTAT. Adaptateur pur presentation : il AFFICHE
# ce que `app_state` a decide, il ne decide rien. Aucune regle, aucune transition ici.
extends CanvasLayer

const App = preload("res://05_SYSTEMS/app_state/app_state.gd")
const P = preload("res://05_SYSTEMS/params/params.gd")
const Pal = preload("res://06_RUNTIME/adapters/palette/palette.gd")

var _fond: ColorRect
var _titre: Label
var _sous_titre: Label
var _aide: Label
# BLOC de detail : apercu du plan (selection de carte) ou legende (controles). UN seul label
# reutilise par les deux ecrans — la regle de ce shell est « un ecran de plus n'est pas une
# architecture de plus ».
var _bloc: Label
var _hud: Label
var _flash: Label
var _flash_restant: int = 0

# Ancres verticales de la ligne d'aide. Elle DESCEND quand le bloc de detail est affiche :
# sans ce deplacement, l'apercu du plan et l'aide se superposeraient a l'ecran.
const ANCRE_AIDE: float = 0.60
const ANCRE_AIDE_BASSE: float = 0.82
const ANCRE_BLOC: float = 0.53
const TAILLE_BLOC: int = 12

# Duree d'affichage d'un retour de ramassage, en ticks de jeu.
const FLASH_TICKS: int = 90

# --- HUD COMPACT PAR JOUEUR (ratifie Pierre, art-bible §11).
#
# UNE bande horizontale, une petite zone par joueur, indexee par J1..J4 — JAMAIS par la
# position dans l'arene : un reperage accroche a la position se deplacerait a chaque tick et
# cesserait d'etre un reperage. Les quatre zones restent presentes meme pour un joueur
# elimine ; une zone qui disparait decale les autres et fait perdre le repere aux vivants.
#
# LE MEME systeme sert en jeu (compact) et en pause (detaille) — `detaille` est le seul
# commutateur, il n'existe pas de seconde architecture de HUD.
#
# AUCUNE ANIMATION ici : la pulsation de MENACE est le seul mouvement autorise a l'ecran
# tant que son interaction avec le HUD n'a pas ete evaluee (P2 — deux sources de mouvement
# non coordonnees sont precisement ce que ce principe interdit).
const MARQUE_VIVANT := "o"
const MARQUE_MORT := "x"

# --- MENU RACINE (P8). Les libelles sont ORDONNES comme les entrees de `app_state` : le
# curseur est un index, et cette liste est la seule traduction index -> texte. Un controle
# mecanique verifie que les deux longueurs coincident, sinon le menu afficherait une entree
# que la machine a etats ne sait pas ouvrir.
const ENTREES_MENU: Array = ["JOUER", "CONTROLES", "OPTIONS", "QUITTER"]
# MEME patron que MARQUE_VIVANT / MARQUE_MORT : la marque est DERIVEE de l'etat, jamais un
# second champ « ligne selectionnee » qui pourrait diverger du curseur.
const MARQUE_CHOIX := ">"
const MARQUE_REPOS := " "


# Niveau de vitesse LISIBLE. Le `cooldown` DECROIT quand le joueur accelere : l'afficher tel
# quel se lirait a l'envers. Derive du cooldown, jamais stocke a part — un compteur parallele
# finirait par diverger de la regle.
# Libelle des volumes. PURE, donc prouvable sans moteur. Une jauge en blocs plutot qu'un
# nombre seul : le reglage doit se lire d'un coup d'oeil, y compris a 0 (« coupe »).
static func libelle_volumes(app: Dictionary) -> String:
	return "Musique  %s\nEffets   %s" % [
		jauge(int(app.get("vol_musique", App.VOLUME_MAX))),
		jauge(int(app.get("vol_effets", App.VOLUME_MAX)))]


static func jauge(pourcent: int) -> String:
	var pleins: int = int(pourcent) / App.VOLUME_PAS
	var total: int = App.VOLUME_MAX / App.VOLUME_PAS
	var barre: String = ""
	for i in range(total):
		barre += "#" if i < pleins else "-"
	if pourcent <= 0:
		return "[%s]  coupe" % barre
	return "[%s]  %d%%" % [barre, pourcent]


static func niveau_vitesse(cooldown: int) -> int:
	return 1 + (P.MOVE_COOLDOWN_BASE - cooldown) / P.SPEED_STEP


# Zone d'UN joueur. FONCTION PURE, donc prouvable sans moteur ni rendu.
static func zone_joueur(index: int, acteur: Dictionary, detaille: bool) -> String:
	var etiquette: String = "J%d" % (index + 1)
	if not bool(acteur["vivant"]):
		if detaille:
			return "%s  ELIMINE" % etiquette
		return "%s %s" % [etiquette, MARQUE_MORT]
	var b: int = int(acteur["bombes_max"])
	var r: int = int(acteur["rayon"])
	var v: int = niveau_vitesse(int(acteur["cooldown"]))
	if detaille:
		return "%s  vivant   bombes %d   portee %d   vitesse %d" % [etiquette, b, r, v]
	return "%s %s %d·%d·%d" % [etiquette, MARQUE_VIVANT, b, r, v]


# La bande complete. `partie` peut etre null (menu) : elle se tait alors, elle n'invente rien.
static func bande_joueurs(partie, detaille: bool) -> String:
	if partie == null:
		return ""
	var zones: Array = []
	for i in range(partie.acteurs.size()):
		zones.append(zone_joueur(i, partie.acteurs[i], detaille))
	if detaille:
		return "\n".join(zones)
	return "   ".join(zones)


# Libelle d'un ramassage. FONCTION PURE, donc testable sans moteur — c'est elle qui porte
# la promesse « le joueur comprend ce qu'il vient de prendre ».
# `effet` faux signifie « ramasse mais sans effet » (capacite deja au plafond) : le dire
# est plus honnete que d'afficher un gain qui n'a pas eu lieu.
# Nom de FORME lisible par un humain. La palette declare une forme ; ici on la NOMME, pour
# que le menu puisse dire « la sphere cyan augmente le nombre de bombes » au lieu de laisser
# le joueur deviner en mourant.
# OBJECTIF, en une phrase. Le joueur doit pouvoir dire ce qu'on attend de lui sans avoir
# lu de documentation — c'est la metrique humaine la plus elementaire, et elle manquait.
static func objectif(partie) -> String:
	if partie == null:
		return "Dernier survivant : eliminez les 3 adversaires"
	var restants: int = partie.vivants().size() - 1
	if int(partie.ticks) >= P.MORT_SUBITE_DEBUT:
		return "MORT SUBITE — l'arene se referme. Adversaires restants : %d" % restants
	var s: int = (P.MORT_SUBITE_DEBUT - int(partie.ticks)) / P.TICKS_PAR_SECONDE
	return "Objectif : dernier survivant. Adversaires : %d     Fermeture dans %ds" % [restants, s]


static func nom_forme(forme: int) -> String:
	match forme:
		Pal.FORME_SPHERE:
			return "sphere"
		Pal.FORME_PRISME:
			return "pyramide"
		Pal.FORME_CYLINDRE:
			return "cylindre"
		_:
			return "cube"


# LEGENDE des power-ups : une ligne par identifiant du registre de REGLES. Derivee, jamais
# recopiee — ajouter un power-up en donnee ajoute sa ligne de legende tout seul.
static func legende() -> Array:
	var out: Array = []
	for id in P.POWERUP_IDS:
		var d: Dictionary = Pal.powerup(String(id))
		out.append("%s : %s" % [nom_forme(int(d["forme"])), libelle_ramassage(String(id), true)])
	return out


# LEGENDE DES COMMANDES du joueur. Meme patron que `legende()` : une liste de lignes, PURE,
# donc prouvable sans moteur. Elle vit ici et pas dans une chaine noyee au milieu du menu —
# c'est ce qui permet a l'ecran CONTROLES de la porter sans la recopier.
static func legende_commandes() -> Array:
	return [
		"Fleches ou ZQSD : se deplacer",
		"ESPACE : poser une bombe",
		"P : mettre la partie en pause",
		"ECHAP : revenir a l'ecran precedent",
	]


# Les quatre lignes du MENU racine, avec la marque de choix DERIVEE du curseur. PURE.
static func lignes_menu(curseur: int) -> String:
	var out: Array = []
	for i in range(ENTREES_MENU.size()):
		var marque: String = MARQUE_CHOIX if i == curseur else MARQUE_REPOS
		out.append("%s %s" % [marque, String(ENTREES_MENU[i])])
	return "\n".join(out)


# Nom lisible d'une carte, lu dans SON descripteur. AUCUNE liste de cartes ne vit dans ce
# fichier : le catalogue appartient a `content_provider`, le shell ne fait que le rendre.
static func nom_carte(desc: Dictionary) -> String:
	return String(desc.get("nom", desc.get("id", "?")))


static func theme_carte(desc: Dictionary) -> String:
	return String(desc.get("theme", Pal.THEME_DEFAUT))


# APERCU du plan, rendu depuis le champ `plan` DEJA CHARGE par le fournisseur de contenu.
# Aucun asset, aucune miniature a produire : la carte est deja une grille de caracteres, et
# c'est la seule representation qui ne peut pas mentir sur la carte qui sera jouee.
#
# Une colonne sur deux est un espace : en grille pleine, 15 colonnes pour 13 rangees rendent
# un rectangle deux fois trop large... l'inverse — les cellules d'un texte sont deux fois plus
# hautes que larges, donc espacer les colonnes RETABLIT l'aspect carre de l'arene.
#
# Un descripteur sans plan rend une chaine VIDE : on n'invente pas une carte pour meubler.
static func apercu_plan(desc: Dictionary) -> String:
	var plan = desc.get("plan", [])
	if not (plan is Array):
		return ""
	var lignes: Array = []
	for rangee in plan:
		var cases: Array = []
		for i in range(String(rangee).length()):
			cases.append(String(rangee)[i])
		lignes.append(" ".join(cases))
	return "\n".join(lignes)


# Fiche d'une carte : SON rang, SON nom, SON theme. RIEN D'AUTRE.
# Ni difficulte, ni nombre de joueurs : ces donnees n'existent dans aucun descripteur, et les
# afficher reviendrait a les inventer. Une fiche n'expose que ce que la carte possede.
static func fiche_carte(desc: Dictionary, index: int, total: int) -> String:
	return "Carte %d/%d — %s\nTheme : %s" % [index + 1, total, nom_carte(desc), theme_carte(desc)]


static func libelle_ramassage(identifiant: String, effet: bool) -> String:
	var nom: String = ""
	match identifiant:
		P.PU_BOMB_UP:
			nom = "BOMBE +1"
		P.PU_FIRE_UP:
			nom = "PORTEE +1"
		P.PU_SPEED_UP:
			nom = "VITESSE +"
		_:
			nom = identifiant
	if not effet:
		return nom + " (deja au maximum)"
	return nom


func _label(taille: int, couleur: Color, ancre_y: float) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", taille)
	l.add_theme_color_override("font_color", couleur)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.anchor_left = 0.0
	l.anchor_right = 1.0
	l.anchor_top = ancre_y
	l.anchor_bottom = ancre_y
	l.offset_top = -float(taille)
	l.offset_bottom = float(taille) * 1.6
	add_child(l)
	return l


func _ready() -> void:
	_fond = ColorRect.new()
	_fond.color = Pal.UI_VOILE
	_fond.anchor_right = 1.0
	_fond.anchor_bottom = 1.0
	_fond.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fond)

	_titre = _label(56, Pal.UI_TITRE, 0.30)
	_sous_titre = _label(26, Pal.UI_SOUS_TITRE, 0.46)
	_aide = _label(20, Pal.UI_AIDE, ANCRE_AIDE)

	_bloc = _label(TAILLE_BLOC, Pal.UI_SOUS_TITRE, ANCRE_BLOC)
	# POLICE A CHASSE FIXE, demandee au systeme : une grille de carte affichee dans une police
	# proportionnelle n'est plus une grille, les colonnes se decalent rangee apres rangee.
	# `SystemFont` est une ressource du moteur, PAS un asset ajoute au depot ; si aucune des
	# familles demandees n'existe, Godot retombe sur la police par defaut sans planter.
	var chasse_fixe := SystemFont.new()
	chasse_fixe.font_names = PackedStringArray(
		["monospace", "Consolas", "Courier New", "DejaVu Sans Mono"])
	_bloc.add_theme_font_override("font", chasse_fixe)
	_bloc.visible = false

	_hud = Label.new()
	_hud.add_theme_font_size_override("font_size", 18)
	_hud.add_theme_color_override("font_color", Pal.UI_HUD)
	_hud.position = Vector2(16, 12)
	add_child(_hud)

	_flash = _label(30, Pal.UI_FLASH, 0.14)
	_flash.visible = false


# Consomme un evenement de ramassage. AVANT ce point, `powerup_ramasse` etait emis par la
# boucle et lu par PERSONNE : un evenement sans lecteur n'existe pas pour le joueur.
func signaler_ramassage(identifiant: String, effet: bool) -> void:
	_flash.text = libelle_ramassage(identifiant, effet)
	_flash_restant = FLASH_TICKS


# Rafraichit l'affichage depuis l'etat d'application et l'etat de partie.
# `partie` peut etre null (menu, resultat) : le HUD se tait alors, il n'invente rien.
#
# `cartes` est le CATALOGUE de descripteurs fourni par `content_provider`, transmis tel quel
# par le runtime. Le shell n'en connait ni le nombre ni le contenu : il lit le descripteur
# d'index `carte` et rend ce qu'il y trouve. Recopier ici une liste de cartes creerait un
# second catalogue qui divergerait du premier au premier ajout.
func rafraichir(app: Dictionary, partie, cartes: Array, meilleur: int = 0) -> void:
	var ecran: int = int(app["ecran"])
	var en_jeu: bool = ecran == App.EN_JEU
	_fond.visible = not en_jeu
	_titre.visible = not en_jeu
	_sous_titre.visible = not en_jeu
	_aide.visible = not en_jeu
	# Le bloc de detail est REARME a chaque frame : un ecran qui ne le remplit pas ne peut pas
	# heriter du texte de l'ecran precedent.
	_bloc.visible = false
	_aide.anchor_top = ANCRE_AIDE
	_aide.anchor_bottom = ANCRE_AIDE

	if ecran == App.MENU:
		_titre.text = "BOMBERMAN 3D"
		_sous_titre.text = lignes_menu(int(app.get("curseur_menu", App.MENU_JOUER)))
		_aide.text = "HAUT / BAS : choisir     ENTREE : valider"
	elif ecran == App.SELECTION_CARTE:
		var idx: int = int(app["carte"])
		var desc: Dictionary = cartes[idx] if idx < cartes.size() else {}
		_titre.text = "CHOISIR UNE CARTE"
		_sous_titre.text = fiche_carte(desc, idx, int(app["nb_cartes"]))
		_aide.text = "HAUT / BAS ou TAB : carte suivante     ENTREE : lancer     ECHAP : retour"
		_bloc.text = apercu_plan(desc)
		# L'apercu prend la teinte de MUR du theme de la carte : la carte se reconnait a sa
		# couleur avant meme d'etre lancee, et cette couleur vient du descripteur unique.
		_bloc.add_theme_color_override("font_color", Pal.theme(theme_carte(desc))["mur"])
		_bloc.visible = true
		_aide.anchor_top = ANCRE_AIDE_BASSE
		_aide.anchor_bottom = ANCRE_AIDE_BASSE
	elif ecran == App.CONTROLES:
		_titre.text = "CONTROLES"
		_sous_titre.text = "\n".join(legende_commandes())
		_aide.text = "ECHAP : retour au menu"
		# La legende des power-ups EXISTAIT et n'etait affichee nulle part. Cet ecran est sa
		# place : le joueur peut enfin comprendre les ramassages sans mourir pour apprendre.
		_bloc.text = "\n".join(legende())
		_bloc.add_theme_color_override("font_color", Pal.UI_SOUS_TITRE)
		_bloc.visible = true
		_aide.anchor_top = ANCRE_AIDE_BASSE
		_aide.anchor_bottom = ANCRE_AIDE_BASSE
	elif ecran == App.OPTIONS:
		# MEME shell, memes labels : l'ecran d'options n'a pas sa propre architecture.
		_titre.text = "OPTIONS SONORES"
		_sous_titre.text = libelle_volumes(app)
		_aide.text = "M : volume musique     B : volume effets\nECHAP ou ENTREE : retour au menu"
	elif ecran == App.PAUSE:
		_titre.text = "PAUSE"
		# MEME systeme qu'en jeu, en mode detaille : la pause est le seul moment ou l'ecran
		# peut porter le detail des quatre joueurs sans concurrencer la lecture du danger.
		_sous_titre.text = "%s\n\n%s" % [objectif(partie), bande_joueurs(partie, true)]
		# L'aide DIT ou mene ECHAP. « Abandonner » sans destination laissait croire a une partie
		# suspendue quelque part ; il n'y en a pas — on remonte a la selection de carte.
		_aide.text = "P ou ENTREE : reprendre     ECHAP : abandonner (choix de carte)"
	elif ecran == App.RESULTAT:
		_titre.text = App.libelle_issue(int(app["issue"]))
		_sous_titre.text = "Score %d     Meilleur %d     Parties %d" % [
			int(partie.score) if partie != null else 0, meilleur, int(app["parties_jouees"])]
		_aide.text = "ENTREE : rejouer     ECHAP : choix de carte"

	if _flash_restant > 0:
		_flash_restant -= 1
	_flash.visible = _flash_restant > 0 and en_jeu

	if partie == null:
		_hud.text = ""
		return
	var secondes: int = int(partie.ticks) / P.TICKS_PAR_SECONDE
	var alerte: String = ""
	if int(partie.ticks) >= P.MORT_SUBITE_DEBUT:
		alerte = "   ⚠ MORT SUBITE"
	elif P.MORT_SUBITE_DEBUT - int(partie.ticks) < 10 * P.TICKS_PAR_SECONDE:
		alerte = "   mort subite dans %ds" % ((P.MORT_SUBITE_DEBUT - int(partie.ticks)) / P.TICKS_PAR_SECONDE)
	# Deux lignes compactes. `Bombes`/`Portee` du seul joueur 0 et `Vivants` ont QUITTE la
	# ligne globale : la bande les porte desormais pour les QUATRE joueurs, et les laisser
	# aurait double l'information au lieu de l'etendre.
	# « P : pause » est le SEUL point d'entree de la boucle de retour au menu depuis une
	# partie. Sans ce rappel, la boucle existe mecaniquement mais reste introuvable — c'est
	# exactement ce que le playtest a rapporte comme « pas de retour au menu ».
	_hud.text = "Score %d   Meilleur %d   %02d:%02d%s   P : pause\n%s" % [
		int(partie.score), meilleur, secondes / 60, secondes % 60, alerte,
		bande_joueurs(partie, false)]
