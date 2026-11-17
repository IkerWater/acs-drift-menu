# ACS Drift by Water v1.1

**ACS Drift** es un menú para Assetto Corsa pensado para las sesiones de drift en
servidores online. Reúne en una sola ventana lo que un piloto necesita durante la
sesión —cambiar de coche, votar el circuito, probar una skin o volver a un punto
seguro— y, para quien administra el servidor, las herramientas para gestionarlo
sin salir del juego.

Funciona con Custom Shaders Patch (CSP). Con el plugin para AssettoServer obtiene
toda su potencia; sin él, el menú sigue funcionando y las pestañas que dependen del
servidor muestran un aviso de conexión.

## Lo que ofrece

- **Cambio de coche:** lista de los coches del servidor con su imagen y las plazas
  libres de cada uno, para elegir antes de reconectarte. Si hay muchos coches, la lista
  tiene su propio scroll, igual que la de skins.
- **Votación de circuito:** propón un circuito, vota a favor o en contra y sigue la
  votación desde una ventana discreta que aparece en la esquina mientras dura.
- **Layouts de drift:** descarga los layouts publicados por el servidor para el
  circuito que estás corriendo y cárgalos en DriftZonesEditor.
- **Skin local:** prueba cualquier skin instalada; el cambio solo lo ves tú.
- **Teletransporte:** guarda un punto, vuelve a él cuando quieras o ve a pits con una
  tecla asignada.
- **Grabar pasadas (fantasma):** graba una pasada con un botón del menú o con una
  tecla asignada, sin abrir el menú. Al parar, el menú pregunta si quieres guardarla o
  descartarla. Las pasadas guardadas se listan por circuito y layout. Puedes cargar una
  como coche fantasma en pista para correr contra ella, quitarla o borrarla. Solo hay un
  fantasma a la vez, y la función es solo para administradores.
- **Administración:** las opciones de admin solo aparecen para los administradores
  reconocidos, y permiten cambiar de preset del servidor con aviso previo a todos los
  jugadores.
- **Interfaz a tu medida:** ventana arrastrable, tema oscuro, transparencia y color de
  acento ajustables, y español o inglés según prefieras. Tus ajustes se guardan en tu
  propio equipo.

## La interfaz

- **Cabecera y pie:** arriba, el título y la versión (desde ahí se arrastra la ventana);
  abajo, los avisos del menú (durante unos segundos) y la tecla que lo abre y cierra.
- **Barra lateral:** cada pestaña tiene un icono siempre visible a la izquierda. Al pasar el
  ratón por encima, la barra se despliega sobre el contenido y muestra el nombre completo
  de cada pestaña; al quitarlo, vuelve a plegarse. Ajustes queda siempre abajo del todo.
  Las pestañas de administración (Admin y Fantasma) solo aparecen para administradores.
- **Transparencia:** la barra lateral usa la misma opacidad que el fondo del menú. El
  mínimo es un 15 %, así el fondo nunca queda del todo transparente y la barra, superpuesta,
  siempre se distingue del contenido.
- **Sin scroll general:** las listas largas (coches, skins, pasadas guardadas) ocupan el
  espacio que queda en la ventana y hacen scroll por dentro.

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
- El fantasma necesita el plugin de servidor y una plaza libre del mismo coche en el
  servidor, que queda reservada mientras está cargado. Al guardar, la parada inicial se
  recorta a 1 s. Una pasada sin confirmar se descarta si su autor se va o pasan
  5 minutos.

## Novedades en la v1.1

- Nuevo menú con barra lateral de iconos que se despliega al pasar el ratón.
- Ventana más ancha, botones e iconos más grandes y nombres de pestaña en negrita.
- Pestaña de coche rediseñada con la misma estructura que la de skins y con la imagen
  de cada coche.
- Grabación de pasadas (fantasma) para administradores, con confirmación antes de
  guardar.