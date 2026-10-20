"""Build scripts/loc_ru.gd from the translation tables in tools/ru/*.tsv.

python tools/build_loc.py           build the dictionary
python tools/build_loc.py --missing also list extracted strings with no translation

Each table line is: English <TAB> Russian. "\\n" in either column is a line break.
"""
import glob
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, '..', 'scripts', 'loc_ru.gd')


def gd(s: str) -> str:
    return '"' + s.replace('\\', '\\\\').replace('"', '\\"').replace('\n', '\\n') + '"'


def load() -> dict:
    words = {}
    for path in sorted(glob.glob(os.path.join(HERE, 'ru', '*.tsv'))):
        with open(path, encoding='utf-8') as f:
            for n, line in enumerate(f, 1):
                line = line.rstrip('\r\n')
                if not line.strip() or line.startswith('#'):
                    continue
                if '\t' not in line:
                    sys.exit(f'{path}:{n}: no tab')
                en, ru = line.split('\t', 1)
                en = en.replace('\\n', '\n')
                ru = ru.replace('\\n', '\n')
                if en not in words:
                    words[en] = ru
    return words


def main() -> None:
    words = load()
    with open(OUT, 'w', encoding='utf-8', newline='\n') as f:
        f.write('class_name LocRu\nextends RefCounted\n')
        f.write('## Russian for the game\'s strings. Built by tools/build_loc.py from tools/ru/*.tsv:\n')
        f.write('## edit the tables, not this file.\n\n')
        f.write('const WORDS := {\n')
        for en, ru in words.items():
            f.write(f'\t{gd(en)}: {gd(ru)},\n')
        f.write('}\n')
    sys.stderr.write(f'{len(words)} entries\n')
    if '--missing' in sys.argv:
        env = dict(os.environ, PYTHONIOENCODING='utf-8')
        out = subprocess.run([sys.executable, os.path.join(HERE, 'extract_strings.py')], capture_output=True, text=True, encoding='utf-8', env=env).stdout
        keys = set(k.strip() for k in words)
        for line in out.splitlines():
            where, lit = line.split('\t', 1)
            s = eval(lit).strip()
            if s and s not in keys:
                print(f'{where}\t{s!r}')


if __name__ == '__main__':
    main()
