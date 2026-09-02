# hud.gd — score, vies et pastilles restantes en CHIFFRES lisibles
# (ligne render.hud_numbers). Jamais uniquement en formes ni en pips. Les trois nombres
# affiches sont pris du SEUL releve observable : ils ne peuvent pas diverger de l'etat.
extends RefCounted

const ETIQUETTE_SCORE := "SCORE "
const ETIQUETTE_VIES := "VIES "
const ETIQUETTE_RESTANTES := "PASTILLES "
const SEPARATEUR := "    "


static func texte_score(score: int) -> String:
	return ETIQUETTE_SCORE + str(score)


static func texte_vies(vies: int) -> String:
	return ETIQUETTE_VIES + str(vies)


static func texte_restantes(restantes: int) -> String:
	return ETIQUETTE_RESTANTES + str(restantes)


# Ligne complete du bandeau, construite depuis le releve observable.
static func ligne(releve: Dictionary) -> String:
	return (texte_score(releve["score"]) + SEPARATEUR
		+ texte_vies(releve["vies"]) + SEPARATEUR
		+ texte_restantes(releve["restantes"]))


# --- PROGRESSION DANS LE CATALOGUE (V4, cause racine P4) --------------------------
# DEFAUT MESURE (playtest Pierre) : le bandeau affichait un numero de niveau NU. Le
# joueur ne savait ni combien de cartes existent, ni ce qu'il vise, ni ce qu'ouvre la
# sortie. Trois informations manquantes, toutes deja portees par l'etat et le catalogue.
#
# Le TOTAL est REMIS par l'appelant qui lit le catalogue (app_shell) : ce module
# n'enumere aucune carte et n'en ouvre aucun fichier — c'est ce qui laisse « ajouter une
# carte » a 0 fichier touche.
const ETIQUETTE_CARTE := "CARTE "
const SEPARATEUR_TOTAL := "/"
const ETIQUETTE_OBJECTIF := "OBJECTIF VIDER "
const SUFFIXE_OBJECTIF := " PASTILLES"
const ETIQUETTE_SORTIE := "SORTIE : "
const SORTIE_SUIVANTE := "PROCHAINE CARTE"
const SORTIE_FIN := "FIN DE PARTIE"


# « CARTE n/N » : ou j'en suis ET combien il y en a. Le second nombre est ce qui
# manquait — un numero seul ne situe rien.
static func texte_carte(niveau: int, total: int) -> String:
	return ETIQUETTE_CARTE + str(niveau) + SEPARATEUR_TOTAL + str(total)


# Ce qu'il reste a faire sur la carte courante, en chiffres.
static func texte_objectif(restantes: int) -> String:
	return ETIQUETTE_OBJECTIF + str(restantes) + SUFFIXE_OBJECTIF


# Ce que DEBLOQUE la sortie : une carte de plus, ou la fin. Le cas « derniere carte » est
# NOMME, jamais laisse a l'interpretation d'un numero qui cesse d'augmenter.
static func texte_sortie(niveau: int, total: int) -> String:
	if niveau >= total:
		return ETIQUETTE_SORTIE + SORTIE_FIN
	return ETIQUETTE_SORTIE + SORTIE_SUIVANTE


# Ligne de progression complete, construite depuis le SEUL releve observable et le total
# remis. Les trois informations manquantes y sont, dans cet ordre.
static func ligne_progression(releve: Dictionary, total: int) -> String:
	return (texte_carte(int(releve["niveau"]), total) + SEPARATEUR
		+ texte_objectif(int(releve["restantes"])) + SEPARATEUR
		+ texte_sortie(int(releve["niveau"]), total))


# Relit le TOTAL affiche apres le separateur : c'est cette fonction qui rend l'egalite
# « total a l'ecran == taille du catalogue » verifiable mecaniquement.
static func relire_total(texte: String) -> int:
	var debut: int = texte.find(ETIQUETTE_CARTE)
	if debut < 0:
		return -1
	var barre: int = texte.find(SEPARATEUR_TOTAL, debut)
	if barre < 0:
		return -1
	var reste: String = texte.substr(barre + SEPARATEUR_TOTAL.length())
	var chiffres := ""
	for i in range(reste.length()):
		var c: String = reste[i]
		if c >= "0" and c <= "9":
			chiffres += c
		else:
			break
	if chiffres.is_empty():
		return -1
	return int(chiffres)


# Relit le nombre affiche apres une etiquette : c'est CETTE fonction qui rend
# l'egalite « chiffre a l'ecran == chiffre de l'etat » verifiable mecaniquement, plutot
# que par relecture humaine.
static func relire(texte: String, etiquette: String) -> int:
	var debut: int = texte.find(etiquette)
	if debut < 0:
		return -1
	var reste: String = texte.substr(debut + etiquette.length())
	var chiffres := ""
	for i in range(reste.length()):
		var c: String = reste[i]
		if c >= "0" and c <= "9":
			chiffres += c
		else:
			break
	if chiffres.is_empty():
		return -1
	return int(chiffres)
