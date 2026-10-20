"""List the player-facing English strings in the scripts, for translation.

python tools/extract_strings.py > strings.txt

A heuristic: every string literal with a capital letter or a space in it, minus paths, node and
meta names, format-only strings and code. Placeholders (%s, %d, %.1f, %5d...) are kept as they
are: Loc matches a formatted string back to its template.
"""
import os
import re
import sys

ROOT = os.path.join(os.path.dirname(__file__), '..', 'scripts')
SKIP_FILES = {'selftest.gd', 'loc.gd', 'loc_ru.gd', 'sfx.gd', 'music.gd'}
LIT = re.compile(r'"((?:[^"\\]|\\.)*)"')
CODE_CTX = re.compile(r'(get_meta|set_meta|has_meta|get_node|has_node|find_children|\.name\s*=|load\(|preload\(|\bmatch\b|Sfx\.|play_at|play\(|attach\(|ambient\(|ROOMS|_mats\[|_builder\(|_enter\(|is_action|InputMap|"\w+":)')


def keep(s: str, line: str) -> bool:
    if len(s) < 2 or not re.search(r'[A-Za-z]{2}', s):
        return False
    if s.startswith(('res://', 'user://', 'res:', 'user:')) or '/' in s and ' ' not in s:
        return False
    if re.fullmatch(r'[a-z0-9_.]+', s):
        return False
    if re.fullmatch(r'[%0-9.dsfx +\-]+', s):
        return False
    if re.fullmatch(r'[A-Z][a-z]+[A-Z]\w*', s):
        return False
    if not (re.search(r'[A-Z]', s) or ' ' in s):
        return False
    if 'shader_type' in s or 'uniform ' in s or 'vec3' in s:
        return False
    return True


def main() -> None:
    seen = {}
    for dirpath, _, files in os.walk(ROOT):
        for f in sorted(files):
            if not f.endswith('.gd') or f in SKIP_FILES:
                continue
            path = os.path.join(dirpath, f)
            with open(path, encoding='utf-8') as fh:
                for n, line in enumerate(fh, 1):
                    stripped = line.strip()
                    if stripped.startswith('#'):
                        continue
                    for m in LIT.finditer(line):
                        s = m.group(1).encode().decode('unicode_escape') if '\\' in m.group(1) else m.group(1)
                        if not keep(s, line):
                            continue
                        # Dictionary keys and meta names used as identifiers.
                        after = line[m.end():m.end() + 2]
                        if after.startswith(':') and re.fullmatch(r'[\w ]+', s) and s.lower() == s:
                            continue
                        seen.setdefault(s, f'{os.path.relpath(path, ROOT)}:{n}')
    out = sys.stdout
    for s, where in seen.items():
        out.write(f'{where}\t{s!r}\n')
    sys.stderr.write(f'{len(seen)} strings\n')


if __name__ == '__main__':
    main()
