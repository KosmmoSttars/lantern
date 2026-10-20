"""Puts the game's icon (tools/icon.ico) into a Windows executable, in place of Godot's.

Uses the Windows resource-update API (BeginUpdateResource and friends), so nothing has to be
downloaded. Run it on the runtime before the game's pack is folded in: rewriting the
resources drops whatever was appended after the executable proper.

    python tools/set_icon.py <exe> <icon.ico>
"""
import ctypes
import struct
import sys
from ctypes import wintypes

RT_ICON = 3
RT_GROUP_ICON = 14
LOAD_LIBRARY_AS_DATAFILE = 0x2

k32 = ctypes.WinDLL("kernel32", use_last_error=True)
ENUMNAMEPROC = ctypes.WINFUNCTYPE(wintypes.BOOL, wintypes.HMODULE, ctypes.c_void_p, ctypes.c_void_p, ctypes.c_void_p)
ENUMLANGPROC = ctypes.WINFUNCTYPE(wintypes.BOOL, wintypes.HMODULE, ctypes.c_void_p, ctypes.c_void_p, wintypes.WORD, ctypes.c_void_p)
k32.LoadLibraryExW.restype = wintypes.HMODULE
k32.LoadLibraryExW.argtypes = [wintypes.LPCWSTR, wintypes.HANDLE, wintypes.DWORD]
k32.EnumResourceNamesW.argtypes = [wintypes.HMODULE, ctypes.c_void_p, ENUMNAMEPROC, ctypes.c_void_p]
k32.EnumResourceLanguagesW.argtypes = [wintypes.HMODULE, ctypes.c_void_p, ctypes.c_void_p, ENUMLANGPROC, ctypes.c_void_p]
k32.FindResourceExW.restype = ctypes.c_void_p
k32.FindResourceExW.argtypes = [wintypes.HMODULE, ctypes.c_void_p, ctypes.c_void_p, wintypes.WORD]
k32.LoadResource.restype = ctypes.c_void_p
k32.LoadResource.argtypes = [wintypes.HMODULE, ctypes.c_void_p]
k32.LockResource.restype = ctypes.c_void_p
k32.LockResource.argtypes = [ctypes.c_void_p]
k32.SizeofResource.restype = wintypes.DWORD
k32.SizeofResource.argtypes = [wintypes.HMODULE, ctypes.c_void_p]
k32.FreeLibrary.argtypes = [wintypes.HMODULE]
k32.BeginUpdateResourceW.restype = wintypes.HANDLE
k32.BeginUpdateResourceW.argtypes = [wintypes.LPCWSTR, wintypes.BOOL]
k32.UpdateResourceW.argtypes = [wintypes.HANDLE, ctypes.c_void_p, ctypes.c_void_p, wintypes.WORD, ctypes.c_void_p, wintypes.DWORD]
k32.EndUpdateResourceW.argtypes = [wintypes.HANDLE, wintypes.BOOL]


def _is_int_resource(p):
    return p is not None and p >> 16 == 0


def existing_groups(exe):
    """[(name, lang, [icon ids])] of every icon group in the executable."""
    mod = k32.LoadLibraryExW(exe, None, LOAD_LIBRARY_AS_DATAFILE)
    if not mod:
        raise OSError(ctypes.get_last_error(), "cannot open " + exe)
    groups = []

    def on_lang(m, typ, name, lang, _):
        res = k32.FindResourceExW(m, RT_GROUP_ICON, name, lang)
        size = k32.SizeofResource(m, res)
        data = ctypes.string_at(k32.LockResource(k32.LoadResource(m, res)), size)
        count = struct.unpack_from("<H", data, 4)[0]
        ids = [struct.unpack_from("<H", data, 6 + 14 * i + 12)[0] for i in range(count)]
        key = name if _is_int_resource(name) else ctypes.wstring_at(name)
        groups.append((key, lang, ids))
        return True

    lang_cb = ENUMLANGPROC(on_lang)

    def on_name(m, typ, name, _):
        k32.EnumResourceLanguagesW(m, RT_GROUP_ICON, name, lang_cb, None)
        return True

    name_cb = ENUMNAMEPROC(on_name)
    k32.EnumResourceNamesW(mod, RT_GROUP_ICON, name_cb, None)
    k32.FreeLibrary(mod)
    return groups


def read_ico(path):
    """The images of an .ico: [(entry fields without the offset, image bytes)]."""
    data = open(path, "rb").read()
    _, kind, count = struct.unpack_from("<HHH", data, 0)
    assert kind == 1, "not an icon file"
    images = []
    for i in range(count):
        w, h, colors, res, planes, bits, size, offset = struct.unpack_from("<BBBBHHII", data, 6 + 16 * i)
        images.append(((w, h, colors, res, planes, bits, size), data[offset:offset + size]))
    return images


def main():
    exe, ico = sys.argv[1], sys.argv[2]
    groups = existing_groups(exe)
    if not groups:
        raise SystemExit("no icon in " + exe)
    images = read_ico(ico)
    h = k32.BeginUpdateResourceW(exe, False)
    if not h:
        raise OSError(ctypes.get_last_error(), "cannot update " + exe)
    keep = []
    for name, lang, old_ids in groups:
        # The new images take the old ids first, then fresh ones well clear of them.
        ids = list(old_ids) + [1000 + len(keep) * 50 + i for i in range(len(images))]
        entries = b""
        for i, (fields, blob) in enumerate(images):
            icon_id = ids[i]
            buf = ctypes.create_string_buffer(blob, len(blob))
            k32.UpdateResourceW(h, RT_ICON, icon_id, lang, buf, len(blob))
            keep.append(buf)
            w, hh, colors, res, planes, bits, size = fields
            entries += struct.pack("<BBBBHHIH", w, hh, colors, res, planes, bits, size, icon_id)
        group = struct.pack("<HHH", 0, 1, len(images)) + entries
        gbuf = ctypes.create_string_buffer(group, len(group))
        keep.append(gbuf)
        key = name if isinstance(name, int) else ctypes.c_wchar_p(name)
        k32.UpdateResourceW(h, RT_GROUP_ICON, key, lang, gbuf, len(group))
    if not k32.EndUpdateResourceW(h, False):
        raise OSError(ctypes.get_last_error(), "cannot write " + exe)
    print("icon set in", exe)


if __name__ == "__main__":
    main()
