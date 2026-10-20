extends SceneTree
## Folds the game's pack into the executable, so the game is one file (Lantern.exe) with
## nothing beside it. The same layout Godot's own export uses for "embed PCK": the runtime,
## then the pack (its file offsets made relative to where it starts), padding to a multiple
## of eight, the pack's size and the pack magic at the very end. The runtime looks there for
## a pack in its own file before anything else.
##
##   godot --headless -s tools/embed_pck.gd -- <runtime.exe> <game.pck> <out.exe>

const MAGIC := 0x43504447
## Pack flag: file offsets are relative to the start of the pack.
const REL_FILEBASE := 2
const CHUNK := 4 * 1024 * 1024


func _init() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() < 3:
		printerr("usage: -- <runtime.exe> <game.pck> <out.exe>")
		quit(1)
		return
	var out := FileAccess.open(a[2], FileAccess.WRITE)
	if out == null:
		printerr("cannot write ", a[2])
		quit(1)
		return
	_copy(a[0], out)
	# The pack starts on a 64-byte boundary.
	while out.get_position() % 64 != 0:
		out.store_8(0)
	var start := out.get_position()
	var pck := FileAccess.open(a[1], FileAccess.READ)
	if pck == null or pck.get_32() != MAGIC:
		printerr("not a pack: ", a[1])
		quit(1)
		return
	pck.seek(0)
	var head := pck.get_buffer(mini(64, pck.get_length()))
	# Header: magic, format, major, minor, patch, then the flags.
	var flags := head.decode_u32(20)
	head.encode_u32(20, flags | REL_FILEBASE)
	out.store_buffer(head)
	while pck.get_position() < pck.get_length():
		out.store_buffer(pck.get_buffer(mini(CHUNK, pck.get_length() - pck.get_position())))
	# End on a multiple of eight, counting the twelve bytes still to come.
	while (out.get_position() - start + 12) % 8 != 0:
		out.store_8(0)
	out.store_64(out.get_position() - start)
	out.store_32(MAGIC)
	out.close()
	print("embedded ", a[1], " into ", a[2])
	quit(0)


func _copy(path: String, out: FileAccess) -> void:
	var f := FileAccess.open(path, FileAccess.READ)
	while f.get_position() < f.get_length():
		out.store_buffer(f.get_buffer(mini(CHUNK, f.get_length() - f.get_position())))
