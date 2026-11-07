# ACS Drift by Water v1.0

**ACS Drift** es un menú para Assetto Corsa pensado para las sesiones de drift en
servidores online. Reúne en una sola ventana lo que un piloto necesita durante la
sesión —cambiar de coche, votar el circuito, probar una skin o volver a un punto
seguro— y, para quien administra el servidor, las herramientas para gestionarlo
sin salir del juego.

Funciona con Custom Shaders Patch (CSP). Con el plugin para AssettoServer obtiene
toda su potencia; sin él, el menú sigue funcionando y las pestañas que dependen del
servidor muestran un aviso de conexión.

## Lo que ofrece

- **Cambio de coche:** ves qué coches tienen plaza libre en el servidor antes de
  reconectarte.
- **Votación de circuito:** propón un circuito, vota a favor o en contra y sigue la
  votación desde una ventana discreta que aparece en la esquina mientras dura.
- **Layouts de drift:** descarga los layouts publicados por el servidor para el
  circuito que estás corriendo y cárgalos en DriftZonesEditor.
- **Skin local:** prueba cualquier skin instalada; el cambio solo lo ves tú.
- **Teletransporte:** guarda un punto, vuelve a él cuando quieras o ve a pits con una
  tecla asignada.
- **Administración:** las opciones de admin solo aparecen para los administradores
  reconocidos, y permiten cambiar de preset del servidor con aviso previo a todos los
  jugadores.
- **Interfaz a tu medida:** ventana arrastrable, tema oscuro, transparencia y color de
  acento ajustables, y español o inglés según prefieras. Tus ajustes se guardan en tu
  propio equipo.

## Instalación

1. Carga el menú como script online de CSP desde el archivo `dist/acs_drift_menu.lua`.
2. Si administras un servidor, instala el plugin `AcsDriftServerPlugin` en AssettoServer
   siguiendo la guía incluida en `server-plugin/LEEME.md`.

Para generar el archivo del menú desde el código fuente, ejecuta `build.ps1` (o
`build.bat`); `build.py` ofrece el mismo resultado si prefieres Python 3.

## Notas

- Los cambios de skin son locales: no afectan a la vista de los demás jugadores.
- Los layouts son scripts de DriftZonesEditor: descárgalos solo de servidores de
  confianza.
- Cambiar de circuito y cambiar de preset son cosas distintas. El primero pasa por la
  votación y mantiene la lista de coches; el segundo lo decide un administrador y es la
  vía para cambiar los coches disponibles.
- El menú se entrega en inglés por defecto y puede cambiarse a español desde Ajustes.
