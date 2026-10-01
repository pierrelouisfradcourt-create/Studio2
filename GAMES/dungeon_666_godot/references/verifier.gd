extends SceneTree
## VÉRIFIE les parties de référence : rejoue les entrées de chaque partie enregistrée
## (references/parties/<nom>.ref) et compare la signature de l'état à chaque point de contrôle.
##
##   <godot> --headless --path . --script res://references/verifier.gd [-- nom …] [--tranche i/n]
##   <godot> --headless --path . --script res://references/verifier.gd -- detail <nom> [première dernière]
##
## En cas d'écart : le nom de la partie et le numéro d'image du premier point de contrôle
## différent. `detail <nom>` rejoue cette partie en affichant l'empreinte COMPLÈTE de chaque image
## entre le dernier point identique et le premier différent (ou entre les images données) : lancée
## sur le code d'avant puis sur le code changé, la comparaison des deux sorties montre l'image et
## la valeur où les deux parties se séparent.
##
## CONSIGNE. Ces références ne disent pas « le jeu est juste » : elles disent « la simulation n'a
## pas changé SANS QU'ON LE VEUILLE ». Donc :
##   - ce script rougit sans qu'une règle ait été changée exprès : c'est une régression. On la
##     corrige. On ne réenregistre PAS pour la faire taire.
##   - une règle (sim/) ou un nombre (data/) a été changé exprès : la garde rougit, c'est attendu.
##     On vérifie que le changement fait ce qu'on voulait (son test dans tests/regles/), on
##     réenregistre (references/enregistrer.gd), et on le DIT dans le message du commit
##     (« références réenregistrées : <la règle changée> »).
## Sortie 0 = toutes identiques, 1 = au moins un écart (ou une partie du catalogue sans fichier),
## 2 = arguments invalides.

const Partie = preload("res://references/partie.gd")
const Catalogue = preload("res://references/catalogue.gd")
const Codec = preload("res://references/codec.gd")
const Enregistrer = preload("res://references/enregistrer.gd")

const EXIT_USAGE := 2
const DETAIL_TAIL := 3 # sans écart, `detail` montre les dernières images

func _initialize() -> void:
	var args: Dictionary = Enregistrer.parse_args(OS.get_cmdline_user_args())
	if args.has("error") or (args.detail and args.names.is_empty()):
		print(args.get("error", "detail attend un nom de partie"))
		quit(EXIT_USAGE)
		return
	if args.detail:
		quit(_detail(args.names))
		return
	quit(_verify(args))

static func _signature_at(ref: Dictionary, rank: int) -> PackedByteArray:
	return ref.signatures.slice(rank * Codec.SIGNATURE_BYTES, (rank + 1) * Codec.SIGNATURE_BYTES)

## Rejoue une partie lue ; `seen` reçoit le nombre d'images jouées à chaque point de contrôle.
## Rend le résultat de Partie.replay. Au dernier point, l'empreinte complète dit QUELLE valeur diffère.
static func check(ref: Dictionary, seen: Array = []) -> Dictionary:
	var total: int = ref.signatures.size() / Codec.SIGNATURE_BYTES
	var on_check := func(rank: int, frames: int, digest: Dictionary) -> String:
		seen.append(frames)
		var same: bool = rank < total and Codec.signature(digest) == _signature_at(ref, rank)
		if rank == total - 1:
			var diff := D6Comparer.diff(digest, Codec.final_digest(ref), 0.0, "fin")
			return diff if diff != "" or same else "la signature de l'état final a changé"
		return "" if same else "l'état n'est plus celui de la référence"
	var res: Dictionary = Partie.replay(ref.spec, Codec.steps(ref), on_check)
	if res.ok and (res.checks != total or res.frames != ref.frames):
		res.ok = false
		res.message = "%d images et %d points rejoués, %d et %d attendus" % [res.frames, res.checks, ref.frames, total]
	return res

## "" si le fichier de la spec est là et à jour, sinon pourquoi il ne peut pas être rejoué.
static func _unusable(spec: Dictionary, ref) -> String:
	if ref == null:
		return "pas de fichier de référence lisible (references/enregistrer.gd -- %s)" % spec.name
	if ref.spec != spec:
		return "la partie du catalogue n'est plus celle du fichier : à réenregistrer"
	return ""

func _verify(args: Dictionary) -> int:
	var t0 := Time.get_ticks_msec()
	var bad := 0
	var checks := 0
	var specs: Array = Enregistrer.selection(args)
	for spec in specs:
		var ref = Codec.read(spec.name)
		var why := _unusable(spec, ref)
		var res := {"ok": false, "checks": 0, "frames": 0, "message": why}
		if why == "":
			res = check(ref)
		checks += res.checks
		if res.ok:
			print("  ok   — %s : %d points de contrôle, %d images" % [spec.name, res.checks, res.frames])
		else:
			bad += 1
			print("  ROUGE — %s : %s" % [spec.name, res.message])
	if args.names.is_empty() and args.slice == 0:
		for n in Codec.names_on_disk():
			if Catalogue.find(n) == null:
				bad += 1
				print("  ROUGE — %s : fichier de référence sans partie au catalogue" % n)
	print("%d parties rejouées, %d points de contrôle, %d en écart — %.1f s" % [specs.size(), checks, bad, (Time.get_ticks_msec() - t0) / 1000.0])
	if bad > 0:
		print("  voir : references/verifier.gd -- detail <partie> ; consigne en tête de ce script")
	var green: bool = bad == 0 and (not specs.is_empty() or args.slices > 1)
	print("REFERENCES: %s" % ("PASS" if green else "FAIL"))
	return 0 if green else 1

## Rejoue une partie en affichant l'empreinte complète des images autour de l'écart.
func _detail(argv: Array) -> int:
	var ref = Codec.read(argv[0])
	if ref == null:
		print("pas de fichier de référence lisible pour %s" % argv[0])
		return EXIT_USAGE
	var seen: Array = []
	var res := check(ref, seen)
	var first: int = seen[-2] if seen.size() >= 2 else 0
	var last: int = seen[-1] if not seen.is_empty() else 0
	if res.ok:
		first = maxi(0, ref.frames - DETAIL_TAIL)
		last = ref.frames
	if argv.size() >= 3:
		first = int(argv[1])
		last = int(argv[2])
	print("%s — %s" % [argv[0], "aucun écart" if res.ok else "ÉCART : " + res.message])
	print("empreinte complète des images %d à %d :" % [first, last])
	var on_frame := func(frames: int, game: Dictionary, events: Dictionary) -> void:
		if frames >= first and frames <= last:
			print("image %d %s" % [frames, JSON.stringify(Partie.digest(game, events.duplicate()), "", false, true)])
	Partie.replay(ref.spec, Codec.steps(ref), func(_rank, _frames, _digest): return "", on_frame)
	return 0 if res.ok else 1
