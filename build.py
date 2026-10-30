#!/usr/bin/env python3
"""Junta todos los modulos de src/ en un unico dist/acs_drift_menu.lua.

CSP carga los scripts online desde UNA sola URL, asi que el codigo se desarrolla
en varios ficheros y se "empaqueta" antes de subirlo.
Uso:  python build.py
"""
import datetime
import pathlib

ROOT = pathlib.Path(__file__).parent
SRC = ROOT / 'src'
OUT = ROOT / 'dist' / 'acs_drift_menu.lua'
ENTRY = 'main'

def module_name(path: pathlib.Path) -> str:
    return path.relative_to(SRC).with_suffix('').as_posix()

def main():
    files = sorted(SRC.rglob('*.lua'), key=lambda p: module_name(p))
    parts = [
        '-- ACS Drift by Water - script ONLINE para CSP',
        f'-- GENERADO EL ({datetime.datetime.now():%Y-%m-%d %H:%M}).',
        '-- Se carga desde el servidor via csp_extra_options.ini ([SCRIPT_1]). Tecla M: abrir/cerrar.',
        '',
        'local __modules, __cache = {}, {}',
        'local function import(name)',
        '  local cached = __cache[name]',
        '  if cached == nil then',
        '    local loader = __modules[name]',
        "    if not loader then error('modulo no encontrado: ' .. tostring(name)) end",
        '    cached = loader()',
        '    __cache[name] = cached == nil and true or cached',
        '  end',
        '  return cached',
        'end',
        '',
        'local genDate = ' + datetime.datetime.now().strftime('%Y-%m-%d %H:%M'),
        '',
    ]
    for f in files:
        name = module_name(f)
        if name == ENTRY:
            continue
        body = f.read_text(encoding='utf-8').replace('\r\n', '\n').rstrip('\n')
        parts += [
            f'-- ===== modulo: {name} (src/{name}.lua) =====',
            f"__modules['{name}'] = function()",
            body,
            'end',
            '',
        ]
    entry = (SRC / f'{ENTRY}.lua').read_text(encoding='utf-8').replace('\r\n', '\n').rstrip('\n')
    parts += [f'-- ===== punto de entrada (src/{ENTRY}.lua) =====', "__modules['__main'] = function()", entry, 'end', "import('__main')", '']

    OUT.parent.mkdir(exist_ok=True)
    OUT.write_text('\n'.join(parts), encoding='utf-8', newline='\n')
    print(f'OK: {OUT} ({OUT.stat().st_size} bytes, {len(files)} modulos)')

if __name__ == '__main__':
    main()
