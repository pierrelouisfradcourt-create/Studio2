# options_screen.gd — ECRAN D'OPTIONS (ligne shell.options_screen).
#
# Expose les reglages MODIFIABLES — mode de jeu, activation du dash — et repercute leur
# changement dans l'etat expose. Rend a l'ecran d'ou il a ete ouvert, memorise.
extends RefCounted

const App = preload("res://05_SYSTEMS/app_state/app_state.gd")
const Reglages = preload("res://05_SYSTEMS/settings/settings.gd")
# V6 : l'arete vers le bloc de parametres a DISPARU. Cet ecran lisait `P.VIES_INITIALES`
# pour l'annoncer au joueur ; il demande desormais la valeur DU MODE COURANT a settings,
# unique detenteur de la correspondance. Un adaptateur qui recompose une regle a partir de
# constantes brutes est un second endroit ou la regle peut diverger.

const TITRE := "OPTIONS"

# Entrees MODIFIABLES, dans l'ordre declare.
# V3 (cause racine P6) : le volume existait UNIQUEMENT par son, dans les six descripteurs
# de synthese — donc reglable par personne. Trois entrees GLOBALES sont ajoutees, deux
# canaux et un coupe-son, toutes activables par la meme commande que les autres.
enum Entree { MODE, DASH, VOLUME_MUSIQUE, VOLUME_EFFETS, MUET }
const ENTREES: Array = [
	Entree.MODE, Entree.DASH, Entree.VOLUME_MUSIQUE, Entree.VOLUME_EFFETS, Entree.MUET,
]
const LIBELLES: Array = [
	"Mode de jeu", "Dash", "Volume musique", "Volume effets", "Muet",
]
const ACTIF := "actif"
const INACTIF := "inactif"
const OUI := "oui"
const NON := "non"

# Jauge LISIBLE d'un rang de volume : autant de pleins que le rang, autant de vides que
# ce qui reste. Un rang affiche comme un nombre nu se lirait comme un code ; la jauge se
# lit sans explication et reste comparable d'un rang a l'autre.
const JAUGE_PLEIN := "="
const JAUGE_VIDE := "."

# Canal expose par une entree de volume ; une entree qui n'est pas un volume n'a AUCUN
# canal — valeur NOMMEE hors du vocabulaire ferme, jamais un canal par defaut.
const AUCUN_CANAL: int = -1


static func canal_de_l_entree(entree: int) -> int:
	if entree == Entree.VOLUME_MUSIQUE:
		return Reglages.Canal.MUSIQUE
	if entree == Entree.VOLUME_EFFETS:
		return Reglages.Canal.EFFETS
	return AUCUN_CANAL


static func jauge(niveau: int) -> String:
	var sortie := ""
	for i in range(Reglages.NIVEAU_MIN, Reglages.NIVEAU_MAX + 1):
		sortie += JAUGE_PLEIN if i < niveau else JAUGE_VIDE
	return sortie


static func valeur_lisible(entree: int, reglages: Dictionary) -> String:
	var r: Dictionary = Reglages.normaliser(reglages)
	if entree == Entree.MODE:
		# V5, cause racine P1 : le joueur lit le LIBELLE, jamais l'identifiant interne de
		# l'enum. `Reglages.nom()` reste la cle du code et du releve de debogage.
		return Reglages.libelle(r["mode"])
	if entree == Entree.DASH:
		return ACTIF if r["dash_actif"] else INACTIF
	if entree == Entree.MUET:
		return OUI if Reglages.muet(r) else NON
	var canal: int = canal_de_l_entree(entree)
	if canal != AUCUN_CANAL:
		return jauge(Reglages.volume(r, canal))
	return ""


static func ligne(entree: int, reglages: Dictionary, selection: int) -> String:
	var marque: String = "> " if entree == selection else "  "
	return marque + LIBELLES[entree] + " : " + valeur_lisible(entree, reglages)


# EXPLICATION du mode COURANT, destinee au joueur.
#
# V6 : le nombre de vies annonce est celui QUE CE MODE ACCORDE — `Reglages.vies_initiales`
# est la SOURCE UNIQUE, la meme que celle qui construit l'etat neuf. Aucun nombre n'est
# ecrit ici : un nombre recopie pourrait diverger de la regle, et depuis que la regle
# depend du mode, un nombre unique serait faux dans l'un des deux modes.
static func explication_du_mode(reglages: Dictionary) -> String:
	var r: Dictionary = Reglages.normaliser(reglages)
	var mode: int = int(r["mode"])
	return Reglages.explication(mode, Reglages.vies_initiales(mode))


# V5, cause racine P1 : une ligne de plus que d'entrees — l'EXPLICATION du mode courant.
# Un nom seul (« Arcade ») ne dit pas ce que le mode fait ; sans lecteur, l'explication
# n'existerait pas. Elle n'est jamais selectionnable : elle se lit, elle ne s'active pas.
#
# V6 : une SECONDE ligne de lecture, la mention qui separe MODE et DASH. Les deux
# reglages aident le joueur, mais pas de la meme facon — l'un donne des vies, l'autre une
# capacite de deplacement — et le mode ne gouverne pas le dash. Sans cette phrase, les
# deux entrees voisines se lisent comme deux facons de dire « mode facile ».
static func lignes(reglages: Dictionary, selection: int) -> Array:
	var sortie: Array = []
	for e in ENTREES:
		sortie.append(ligne(e, reglages, selection))
	sortie.append(explication_du_mode(reglages))
	sortie.append(Reglages.MENTION_MODE_ET_DASH)
	return sortie


# Nombre de lignes de LECTURE (non selectionnables) posees apres les entrees. Declare, et
# non deduit par soustraction : c'est ce que les ecrans et leurs preuves comparent.
const LIGNES_DE_LECTURE: int = 2


# ACTIVATION d'une entree : bascule la valeur et rend les NOUVEAUX reglages. Chaque
# entree a donc un effet observable — le nombre d'entrees sans effet vaut 0.
static func activer(entree: int, reglages: Dictionary) -> Dictionary:
	var r: Dictionary = Reglages.normaliser(reglages)
	if entree == Entree.MODE:
		return Reglages.avec_mode(r, Reglages.mode_suivant(r["mode"]))
	if entree == Entree.DASH:
		return Reglages.avec_dash(r, not r["dash_actif"])
	if entree == Entree.MUET:
		return Reglages.avec_muet(r, not Reglages.muet(r))
	var canal: int = canal_de_l_entree(entree)
	if canal != AUCUN_CANAL:
		return Reglages.avec_volume(r, canal, Reglages.volume_suivant(Reglages.volume(r, canal)))
	return r


# Nombre d'entrees dont l'activation NE CHANGE RIEN aux reglages. Attendu : 0.
static func entrees_sans_effet(reglages: Dictionary) -> int:
	var n: int = 0
	for e in ENTREES:
		var apres: Dictionary = activer(e, reglages)
		if apres == Reglages.normaliser(reglages):
			n += 1
	return n


static func retour(appelant: int) -> int:
	return App.retour(App.Etat.OPTIONS, appelant)


# --- PERSISTANCE DES REGLAGES (V3, cause racine P6) --------------------------------
# Le disque est une API de PLATEFORME : la persistance vit donc dans l'adaptateur qui
# possede deja l'ecran de reglages, JAMAIS dans 05_SYSTEMS — settings.gd est mesure sans
# « FileAccess », sans « ConfigFile » et sans « user:// », et cette mesure est ce qui
# garantit que la valeur du PREMIER LANCEMENT reste CONSTRUITE.
#
# La lecture rend un dictionnaire BRUT que Reglages.normaliser filtre : un fichier
# absent, tronque, ou porteur d'une valeur hors vocabulaire retombe donc sur les defauts
# declares, sans exception et sans reglage fantome.
const CHEMIN_REGLAGES := "user://reglages.json"


static func sauvegarder(reglages: Dictionary) -> bool:
	var f := FileAccess.open(CHEMIN_REGLAGES, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(Reglages.normaliser(reglages)))
	f.close()
	return true


# Reglages LUS sur le disque, sous forme BRUTE. Un fichier absent ou illisible rend un
# dictionnaire VIDE — c'est-a-dire exactement « aucun reglage persistant », le cas du
# premier lancement.
static func charger_brut() -> Dictionary:
	if not FileAccess.file_exists(CHEMIN_REGLAGES):
		return {}
	var f := FileAccess.open(CHEMIN_REGLAGES, FileAccess.READ)
	if f == null:
		return {}
	var texte: String = f.get_as_text()
	f.close()
	var lu = JSON.parse_string(texte)
	if typeof(lu) != TYPE_DICTIONARY:
		return {}
	return lu


# Reglages persistes, NORMALISES : la seule forme utilisable par l'application.
static func charger() -> Dictionary:
	return Reglages.normaliser(charger_brut())


static func existe_une_sauvegarde() -> bool:
	return FileAccess.file_exists(CHEMIN_REGLAGES)


# Efface la sauvegarde. Rend le constat, jamais un booleen nu : « il n'y avait rien a
# effacer » et « l'effacement a echoue » ne sont pas le meme fait.
static func oublier() -> Dictionary:
	if not existe_une_sauvegarde():
		return {"existait": false, "efface": false}
	var erreur: int = DirAccess.remove_absolute(ProjectSettings.globalize_path(CHEMIN_REGLAGES))
	return {"existait": true, "efface": erreur == OK}
