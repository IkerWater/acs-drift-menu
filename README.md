# ACS Drift by Water - menu (codigo fuente modular)

CSP carga un script online desde UNA sola URL, asi que se trabaja en varios ficheros
y se empaquetan en uno solo antes de subirlo.

## Estructura
```
src/
  config.lua          datos editables (coches, servidor, comandos)
  core.lua            estado compartido, notify, safe, sendChatCommand
  features/           logica, sin dibujar nada
    car.lua  skin.lua  mapvote.lua  time.lua  teleport.lua
  ui/                 todo lo que se dibuja
    theme.lua         colores y widgets (boton, titulos, barra)
    menu.lua          ventana, cabecera, pestanas, barra de estado
    tabs/             una pestana por fichero
  main.lua            callbacks de CSP (script.update / script.drawUI)
build.py | build.ps1  empaquetan src/ en dist/acs_drift_menu.lua
```

## Reglas de dependencia
- `ui/*` puede importar `features/*`, `core` y `config`.
- `features/*` NO importa nada de `ui/`.
- `core` y `config` no importan nada.
- Los modulos se cargan con `import('ruta/sin/extension')` (lo define el empaquetado).

## Flujo de trabajo
1. Edita ficheros de `src/`.
2. `python build.py` (o `build.ps1`).
3. Sube `dist/acs_drift_menu.lua` a la URL de [SCRIPT_1].

## Anadir una pestana
1. Crea `src/ui/tabs/nueva.lua` (`return function() ... end`).
2. Anadela a `TABS` en `src/ui/menu.lua`.
3. Si necesita logica, crea `src/features/nueva.lua`.

## Errores
El codigo generado lleva comentarios `-- ===== modulo: ... =====`: la linea que indique
el log de CSP se localiza en el .lua generado y ahi se ve a que modulo pertenece.
