extends RefCounted
## Le fichier d'une partie de référence (references/parties/<nom>.ref) : compact, fait pour être
## versionné (les 70 parties : moins de 2 Mo). Un dictionnaire écrit par store_var dans un fichier
## compressé (ZSTD) :
##   format      version de ce codec
##   name, spec  la partie (references/catalogue.gd) : le fichier se rejoue seul
##   frames      nombre d'images jouées ; ticks : game.tick final
##   ops         le déroulé : n > 0 = jouer n images ; 0 = point de contrôle ;
##               n < 0 = commande de menu n° (-n - 1) >> 1, acceptée si (-n - 1) & 1
##   columns     les entrées, une colonne par champ (mx, my, ax, ay, drapeaux, sx, sy), chacune
##               codée par plages répétées : [valeur, nombre d'images, valeur, nombre…]
##   commands    les commandes de menu distinctes (JSON)
##   signatures  8 octets par point de contrôle : le début du SHA-256 de l'empreinte d'état
##   final       l'empreinte COMPLÈTE du dernier point (JSON, nombres exacts) : c'est elle qui
##               permet de dire quelle valeur diffère quand la partie finit autrement
## Une signature dit « même état » ou « état différent », pas lequel : pour le voir,
## references/verifier.gd -- detail <partie>.

const Format = preload("res://outils/bots/format.gd")

const FORMAT := 1
const DIR := "res://references/parties/"
const EXT := ".ref"
const SIGNATURE_BYTES := 8
const INPUT_FIELDS := 7 # un pas d'entrées : [0, mx, my, ax, ay, drapeaux, sx, sy]

static func path_of(name: String) -> String:
	return DIR + name + EXT

# ---------------------------------------------------------------- signature

## Forme canonique d'une valeur : nombres en double (2 et 2.0 sont le même nombre), clés triées.
static func _put(buf: StreamPeerBuffer, v) -> void:
	match typeof(v):
		TYPE_NIL:
			buf.put_u8(0)
		TYPE_BOOL:
			buf.put_u8(1)
			buf.put_u8(1 if v else 0)
		TYPE_INT, TYPE_FLOAT:
			buf.put_u8(2)
			buf.put_double(float(v))
		TYPE_STRING, TYPE_STRING_NAME:
			buf.put_u8(3)
			buf.put_utf8_string(String(v))
		TYPE_ARRAY:
			buf.put_u8(4)
			buf.put_u32(v.size())
			for x in v:
				_put(buf, x)
		TYPE_DICTIONARY:
			buf.put_u8(5)
			buf.put_u32(v.size())
			var keys: Array = v.keys()
			keys.sort()
			for k in keys:
				buf.put_utf8_string(String(k))
				_put(buf, v[k])
		_:
			push_error("empreinte : type non prévu %s" % type_string(typeof(v)))

## Signature courte d'une empreinte d'état : au bit près sur chaque nombre.
static func signature(digest: Dictionary) -> PackedByteArray:
	var buf := StreamPeerBuffer.new()
	_put(buf, digest)
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(buf.data_array)
	return ctx.finish().slice(0, SIGNATURE_BYTES)

# ---------------------------------------------------------------- écrire

static func _rle_push(column: PackedInt32Array, value: int) -> void:
	var n := column.size()
	if n >= 2 and column[n - 2] == value:
		column[n - 1] += 1
	else:
		column.append(value)
		column.append(1)

## Ajoute `n` images au déroulé (fusionnées avec les images qui précèdent).
static func _ops_frame(ops: PackedInt32Array) -> void:
	var n := ops.size()
	if n >= 1 and ops[n - 1] > 0:
		ops[n - 1] += 1
	else:
		ops.append(1)

## La forme écrite d'une partie notée (references/partie.gd, record).
static func encode(rec: Dictionary) -> Dictionary:
	var columns: Array = []
	for i in INPUT_FIELDS:
		columns.append(PackedInt32Array())
	var ops := PackedInt32Array()
	var commands: Array = []
	var signatures := PackedByteArray()
	var last = null
	for step in rec.steps:
		match int(step[0]):
			0:
				_ops_frame(ops)
				for i in INPUT_FIELDS:
					_rle_push(columns[i], int(step[i + 1]))
			1:
				var text := JSON.stringify(step[1])
				if not commands.has(text):
					commands.append(text)
				ops.append(-(commands.find(text) * 2 + (1 if step[2] != 0.0 else 0)) - 1)
			2:
				ops.append(0)
				signatures.append_array(signature(step[1]))
				last = step[1]
	return {
		"format": FORMAT, "name": rec.name, "spec": rec.spec, "frames": rec.frames, "ticks": rec.ticks,
		"ops": ops, "columns": columns, "commands": commands, "signatures": signatures,
		"final": JSON.stringify(Format.exact(last)),
	}

static func write(rec: Dictionary) -> Error:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	var f := FileAccess.open_compressed(path_of(rec.name), FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
	if f == null:
		return FileAccess.get_open_error()
	f.store_var(encode(rec))
	f.close()
	return OK

# ---------------------------------------------------------------- lire

## Lit un fichier de référence. Rend null s'il manque, est illisible ou d'un autre format.
static func read(name: String):
	if not FileAccess.file_exists(path_of(name)):
		return null
	var f := FileAccess.open_compressed(path_of(name), FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	if f == null:
		return null
	var d = f.get_var()
	f.close()
	if not (d is Dictionary) or d.get("format") != FORMAT:
		return null
	return d

## Curseur sur une colonne codée par plages : rend la valeur de l'image suivante.
static func _rle_next(column: PackedInt32Array, cursor: Array) -> int:
	if cursor[1] >= column[cursor[0] + 1]:
		cursor[0] += 2
		cursor[1] = 0
	cursor[1] += 1
	return column[cursor[0]]

## Les pas d'une partie lue, à la forme de references/partie.gd ; un point de contrôle y porte sa
## signature : [2, PackedByteArray].
static func steps(d: Dictionary) -> Array:
	var out: Array = []
	var cursors: Array = []
	for i in INPUT_FIELDS:
		cursors.append([0, 0])
	var checks := 0
	for op in d.ops:
		if op == 0:
			out.append([2.0, d.signatures.slice(checks * SIGNATURE_BYTES, (checks + 1) * SIGNATURE_BYTES)])
			checks += 1
		elif op < 0:
			var code: int = -op - 1
			out.append([1.0, D6Js.decode(JSON.parse_string(d.commands[code >> 1])), float(code & 1)])
		else:
			for n in op:
				var step: Array = [0.0]
				for i in INPUT_FIELDS:
					step.append(float(_rle_next(d.columns[i], cursors[i])))
				out.append(step)
	return out

## L'empreinte complète du dernier point de contrôle.
static func final_digest(d: Dictionary) -> Dictionary:
	return D6Js.decode(JSON.parse_string(d.final))

static func names_on_disk() -> Array:
	var out: Array = []
	for f in DirAccess.get_files_at(DIR):
		if f.ends_with(EXT):
			out.append(f.trim_suffix(EXT))
	out.sort()
	return out
