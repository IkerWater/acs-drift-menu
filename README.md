# ACS Drift by Water v1.0

**Versión del menú: v1.0 (candidata a release; pendiente de pruebas en juego).** ACS Drift es un menú para Assetto Corsa con Custom Shaders Patch (CSP), acompañado
de un plugin para AssettoServer. Reúne herramientas para los pilotos y opciones
de gestión para los administradores. El menú puede utilizarse sin el plugin; si no
está disponible, las pestañas que dependen de él muestran un aviso de conexión.

## Funciones del menú

- **Cambio de coche:** consulta los coches y las plazas disponibles en el servidor
  para facilitar el cambio y la reconexión.
- **Votación de circuito:** muestra los circuitos disponibles y el estado de la
  votación; permite proponer un circuito y votar a favor o en contra. Cuando hay
  una votación activa, muestra una ventana flotante en la esquina superior derecha
  con el circuito, el progreso y los botones de voto. La pestaña Circuito se mantiene.
- **Layouts de drift:** permite consultar los archivos de DriftZonesEditor publicados
  por el servidor para el circuito actual y abrir la descarga en el navegador. La
  ubicación se elige con el diálogo del navegador; la ruta de ejemplo desde la
  biblioteca de Steam es `steamapps/common/assettocorsa/apps/lua/DriftZonesEditor/tracks`.
- **Cambio local de skin:** permite elegir una skin instalada localmente y aplicarla
  a la vista del propio jugador.
- **Teletransporte y reaparición:** guarda una ubicación, permite volver a ella o ir
  a pits, y admite asignar una tecla o botón a la acción de retorno.
- **Administración:** muestra opciones de administrador únicamente a las conexiones
  reconocidas como administradores. Permite consultar los presets del servidor y
  solicitar un cambio directo, sin votación.
- **Interfaz personalizable:** ventana desplazable arrastrando la cabecera, centrada
  por defecto, tema oscuro e idioma seleccionable entre inglés y español.
  El contenido de las pestañas largas se desplaza dentro de la pestaña; cabecera,
  pestañas, zona de estado y pie permanecen fijos. El idioma, el color de acento,
  la transparencia, la posición, la opción de cerrar al acelerar y la tecla
  configurable para abrir/cerrar (M por defecto) se guardan localmente en CSP y
  se restauran al cargar el menú. No se sincronizan entre equipos ni se guardan
  en el servidor.

## Funciones del plugin de servidor

- **Información en tiempo real:** proporciona al menú la lista de coches con plazas
  libres, los circuitos disponibles, el estado de la votación y los presets
  configurados en el servidor.
- **Layouts de DriftZonesEditor:** sirve archivos Lua de `layouts/<id del circuito>/`
  desde la carpeta del plugin. El menú abre el enlace de descarga en el navegador del
  sistema, que gestiona la escritura del archivo. Activa en el navegador la opción
  para preguntar dónde guardar cada descarga y elige como ruta de ejemplo
  `steamapps/common/assettocorsa/apps/lua/DriftZonesEditor/tracks`; después, el
  jugador los carga manualmente desde DriftZonesEditor. La ruta no se configura ni
  se aplica automáticamente desde el menú.
- **Votaciones de circuito:** gestiona propuestas y votos, informa del resultado y
  aplica los cambios aprobados. Puede coordinar la transición y la reconexión de los
  jugadores según la configuración del servidor. Cambiar de circuito no modifica la
  lista de coches del servidor.
- **Herramientas de administración:** ofrece comandos para consultar circuitos y
  votaciones, cancelar o recargar una votación y aplicar un circuito directamente.
  Las acciones administrativas se validan en el servidor.
- **Cambio de preset:** permite a un administrador elegir un preset, avisa a todos
  los jugadores y programa el reinicio del servidor con la nueva configuración.
  Como la lista de coches puede cambiar, los jugadores deben volver a entrar desde
  Content Manager y elegir un coche manualmente. El flujo envía un aviso de
  desconexión individual antes de cerrar las conexiones.
- **Comandos para jugadores:** incluye consultas de circuitos y estado, además de
  comandos para proponer circuitos y votar.

## Notas

- El cambio de skin es local: no modifica la skin de los demás jugadores.
- Los layouts son archivos Lua del servidor y DriftZonesEditor los ejecuta cuando
  el jugador los carga. Descarga layouts únicamente de servidores de confianza.
- El cambio de circuito y el cambio de preset son acciones distintas: el primero se
  integra con el sistema de votación y conserva la lista de coches; el cambio de
  preset lo inicia directamente un administrador y es la función prevista para
  cambiar los coches disponibles.
- El idioma predeterminado del menú es inglés. El selector permite cambiarlo a
  español durante la sesión.
- La carpeta elegida para las descargas depende de la configuración del navegador;
  el menú no puede asignar una carpeta inicial al diálogo de guardado.

## Preparación de release v1.0

La versión y el bundle están actualizados, pero no se debe publicar la release hasta
completar estas comprobaciones en una instalación de prueba:

- [ ] Cargar el bundle como script CSP online y comprobar idioma, persistencia de
  ajustes y reasignación de tecla.
- [ ] Probar varias resoluciones: scroll solo dentro de listas/contenido de pestaña,
  sin desplazamiento global; verificar cabecera y pie fijos.
- [ ] Revisar visualmente las listas de Coche, Skin, Circuito y Layouts, incluyendo
  la preview de skin ampliada.
- [ ] Probar descarga de un layout desde el navegador y cargarlo desde
  DriftZonesEditor.
- [ ] Probar votación de circuito, cambio de coche, skin local y teletransporte.
- [ ] En un servidor de pruebas, validar comandos de admin y cambio de preset con
  clientes conectados, incluido aviso, desconexión y reinicio.
- [ ] Confirmar que `/mapcancel` y `/mapreload` se envían correctamente desde el tab
  Admin (`ac.sendChatMessage`) y que el recuento de plazas coincide con el entry list.
- [ ] Confirmar que el DLL distribuido del plugin corresponde al código de
  `server-plugin/codigo-fuente/` y está compilado para AssettoServer v0.0.55-pre45.

Para generar `dist/acs_drift_menu.lua`, ejecutar `build.ps1` (también lo invoca
`build.bat`). `build.py` ofrece el mismo empaquetado como alternativa si se usa
Python 3. No hay pruebas automatizadas de UI en el repositorio; la checklist de
arriba requiere pruebas dentro de Assetto Corsa/CSP.
