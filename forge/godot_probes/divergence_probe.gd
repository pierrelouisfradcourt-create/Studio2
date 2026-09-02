# divergence_probe.gd — SONDE GENERIQUE de l'oracle de divergence produit (P6,
# invariant INV-4 : tout parametre declare doit produire un effet runtime mesurable).
#
# ORIGINE MESUREE : sur le run Pac-Man (lot V5), le mode de jeu etait un PRODUCTEUR SANS
# CONSOMMATEUR — regle offerte au joueur, sans effet. `godot_oracle` etait VERT a 2612
# assertions. Seule une mesure DIFFERENTIELLE ecrite a la main une fois (deux parties du
# meme bot, une par valeur du parametre, 200 tics, meme graine) l'a trouve : 0 divergence
# d'etat. C'est ce test-la que cette sonde GENERALISE : n'importe quel jeu, n'importe quel
# parametre, sans reecrire l'instrument a chaque fois.
#
# CETTE SONDE NE CONNAIT RIEN DU JEU. Elle ne fait QUE piloter un ADAPTATEUR fourni en
# argument (`--adapter=<chemin res:// ou chemin disque absolu>`), qui expose le contrat
# FERME suivant (fonctions STATIC, aucun etat partage) :
#   static func etat_initial(graine: int, valeur) -> Variant
#   static func en_cours(etat) -> bool
#   static func avancer(etat) -> Variant          # un seul tic, action choisie EN INTERNE
#   static func projeter(etat) -> Dictionary      # releve observable PUR de cet etat
# L'adaptateur vit cote jeu (ou dans un dossier de preuve externe, cf. commentaire plus
# bas) : cette sonde reste chargeable via un chemin ABSOLU du disque (verifie 2026-08-07 :
# `load()` resout un chemin disque meme sous un `--path` different) OU via `res://` si
# l'adaptateur vit dans le projet cible.
#
# DEUX CAMPAGNES, MEME INSTRUMENT (jamais deux mesures differentes) :
#   CONTROLE : etat_initial(graine, valeur_a) vs etat_initial(graine, valeur_a) — MEME
#              valeur des deux cotes. Doit trouver 0 divergence, sinon la mesure est
#              bruitee et ne prouve rien (aucune conclusion n'est fiable sur un instrument
#              qui ment sur le controle).
#   REEL      : etat_initial(graine, valeur_a) vs etat_initial(graine, valeur_b) — valeurs
#              DIFFERENTES. Doit trouver AU MOINS UNE divergence, sinon le parametre est
#              un producteur sans consommateur — exactement le defaut V5.
#
# Usage :
#   <godot> --headless --path <game_dir> --script <chemin absolu de ce fichier> --
#     --adapter=<chemin> --param=<id> --seed=<n> --ticks=<n>
#     --value_a=<valeur> --value_b=<valeur> [--ignore=cle1,cle2,...]
#
# Sortie (protocole FORGE_ORACLE standard du studio, meme forme que les oracles `.gd`
# existants — cf. GAMES/snake/07_TESTS/oracle/core_boot.gd) :
#   "FORGE_ORACLE divergence_<param> {json}" puis quit(0 si ok sinon 1).
# `ok` est VRAI seulement si (a) le controle trouve 0 divergence ET (b) le reel en trouve
# au moins une. Sortie JAMAIS ambigue : l'echec nomme le parametre ET les cles comparees.
extends SceneTree


func _lire_arg_str(nom: String, defaut: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with(nom + "="):
			return a.substr((nom + "=").length())
	return defaut


func _lire_arg_int(nom: String, defaut: int) -> int:
	var s := _lire_arg_str(nom, "")
	if s != "" and s.is_valid_int():
		return int(s)
	return defaut


# Une valeur de parametre peut etre un entier (enum, la forme la plus frequente cote jeu)
# ou une chaine (parametre textuel) : l'adaptateur recoit le type qu'on lui remet, cette
# sonde ne suppose rien de plus.
func _valeur_typee(brut: String):
	if brut.is_valid_int():
		return int(brut)
	return brut


# INSTRUMENT DE MESURE, applique tel quel aux deux campagnes (controle et reel) : deux
# etats avances en PARALLELE, meme nombre de tics, jusqu'a la fin de l'un des deux ou le
# budget epuise. Rend le nombre de tics reellement joues, le nombre de tics divergents et
# la LISTE TRIEE des cles qui ont diverge (jamais un compte nu — un « ca diverge » qui ne
# dit pas SUR QUOI ne prouve rien).
func _campagne(Adapter, graine: int, tics: int, valeur_a, valeur_b, ignore: Array) -> Dictionary:
	var a = Adapter.etat_initial(graine, valeur_a)
	var b = Adapter.etat_initial(graine, valeur_b)
	var joues: int = 0
	var divergents: int = 0
	var cles: Array = []
	for _t in range(tics):
		if not Adapter.en_cours(a) or not Adapter.en_cours(b):
			break
		a = Adapter.avancer(a)
		b = Adapter.avancer(b)
		joues += 1
		var pa: Dictionary = Adapter.projeter(a)
		var pb: Dictionary = Adapter.projeter(b)
		var d: Array = []
		var toutes_cles: Array = pa.keys()
		for c in pb.keys():
			if not toutes_cles.has(c):
				toutes_cles.append(c)
		for c in toutes_cles:
			if ignore.has(c):
				continue
			if pa.get(c) != pb.get(c):
				d.append(c)
		d.sort()
		if not d.is_empty():
			divergents += 1
		for c in d:
			if not cles.has(c):
				cles.append(c)
	cles.sort()
	return {"ticks": joues, "ticks_divergents": divergents, "cles": cles}


func _emettre(param_id: String, payload: Dictionary, ok: bool) -> void:
	payload["ok"] = ok
	print("FORGE_ORACLE divergence_%s %s" % [param_id, JSON.stringify(payload)])
	quit(0 if ok else 1)


func _initialize() -> void:
	var t0: int = Time.get_ticks_msec()
	var param_id: String = _lire_arg_str("--param", "")
	var adapter_path: String = _lire_arg_str("--adapter", "")
	var graine: int = _lire_arg_int("--seed", 7)
	var tics: int = _lire_arg_int("--ticks", 200)
	var value_a_brut: String = _lire_arg_str("--value_a", "")
	var value_b_brut: String = _lire_arg_str("--value_b", "")
	var ignore_brut: String = _lire_arg_str("--ignore", "")
	var ignore: Array = [] if ignore_brut == "" else ignore_brut.split(",")

	if param_id == "":
		_emettre("inconnu", {"fails": ["--param manquant"], "cout_ms": Time.get_ticks_msec() - t0}, false)
		return
	if adapter_path == "":
		_emettre(param_id, {"fails": ["--adapter manquant"], "cout_ms": Time.get_ticks_msec() - t0}, false)
		return
	if value_a_brut == "" or value_b_brut == "":
		_emettre(param_id, {"fails": ["--value_a et --value_b sont requis"], "cout_ms": Time.get_ticks_msec() - t0}, false)
		return

	var Adapter = load(adapter_path)
	if Adapter == null:
		_emettre(param_id, {"fails": ["adaptateur introuvable/illisible: %s" % adapter_path], "cout_ms": Time.get_ticks_msec() - t0}, false)
		return
	for methode in ["etat_initial", "en_cours", "avancer", "projeter"]:
		if not Adapter.has_method(methode):
			_emettre(param_id, {"fails": ["adaptateur ne porte pas la methode requise: %s" % methode], "cout_ms": Time.get_ticks_msec() - t0}, false)
			return

	var value_a = _valeur_typee(value_a_brut)
	var value_b = _valeur_typee(value_b_brut)

	# CONTROLE NEGATIF : le MEME instrument, deux campagnes de la MEME valeur.
	var controle: Dictionary = _campagne(Adapter, graine, tics, value_a, value_a, ignore)
	# MESURE REELLE : les deux valeurs declarees.
	var reel: Dictionary = _campagne(Adapter, graine, tics, value_a, value_b, ignore)

	var fails: Array = []
	if int(controle["ticks_divergents"]) != 0:
		fails.append(
			"CONTROLE BRUITE: %d/%d tics divergent entre deux campagnes de LA MEME valeur (%s) — cles=%s. La mesure n'est pas fiable tant que ce controle n'est pas a zero."
			% [controle["ticks_divergents"], controle["ticks"], str(value_a), str(controle["cles"])])
	if int(reel["ticks_divergents"]) == 0:
		fails.append(
			"PARAMETRE INERTE: '%s' — 0 divergence sur %d tics entre valeur_a=%s et valeur_b=%s (cles comparees: %s). Producteur sans consommateur."
			% [param_id, reel["ticks"], str(value_a), str(value_b), str(Adapter.projeter(Adapter.etat_initial(graine, value_a)).keys())])

	var cout_ms: int = Time.get_ticks_msec() - t0
	_emettre(param_id, {
		"fails": fails,
		"param": param_id,
		"value_a": value_a,
		"value_b": value_b,
		"seed": graine,
		"ticks_budget": tics,
		"controle": controle,
		"reel": reel,
		"cout_ms": cout_ms,
	}, fails.is_empty())
