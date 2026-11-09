# AcsDriftServerPlugin para AssettoServer 0.0.55-pre45

Plugin de servidor para ACS Drift (antes MapVotePlugin). Da al menú CSP de ACS Drift los coches con plazas
libres, el estado de administrador y los presets disponibles. Permite votar circuitos o que un administrador
cambie directamente el preset activo; AssettoServer se reinicia por dentro. La reconexión automática solo se
usa al cambiar de circuito. También publica los layouts de DriftZonesEditor que el servidor haya instalado.

## Instalar (sustituye a MapVotePlugin)
1. Para el servidor.
2. En Pterodactyl > Files, en la carpeta raíz del servidor, sube `AcsDriftServerPlugin.zip` y descomprímelo
   (Unarchive). Debe quedar `plugins/AcsDriftServerPlugin/AcsDriftServerPlugin.dll` y
   `plugins/AcsDriftServerPlugin/lua/mapvote.lua`.
3. Borra la carpeta antigua `plugins/MapVotePlugin`.
4. En AC Panel > Votación en el juego, apaga y vuelve a encender "Votación de circuito": quita
   `MapVotePlugin` y pone `AcsDriftServerPlugin` en `EnablePlugins` de cfg/ y de todos los presets.
   (A mano: cambia `- MapVotePlugin` por `- AcsDriftServerPlugin` en cada `extra_cfg.yml`.)
5. Arranca. La configuración sigue en `cfg/plugin_map_vote_cfg.yml` (el nombre del archivo no cambia).
6. Para publicar layouts de DriftZonesEditor, crea
   `plugins/AcsDriftServerPlugin/layouts/<id-del-circuito>/` y coloca ahí los archivos `.lua`.
   Ejemplo: `plugins/AcsDriftServerPlugin/layouts/naparrak/NAPARRAK LAYOUT 1 LWDC.lua`.
   El ID es el nombre de la carpeta del circuito en `content/tracks/`. El plugin crea la carpeta
   `layouts` al recibir la primera consulta; los archivos pueden añadirse o reemplazarse en caliente.

Nunca actives los dos plugins a la vez: registran las mismas rutas y eventos.

## En el juego
- Menú: en el chat de CSP, extras > "Track vote" (search, Propose, Yes / No).
- Chat: `/maplist [página]`, `/mapstart <n>`, `/mapyes`, `/mapno`, `/mapstatus`
- Admin (`/admin <contraseña>`): el tab Admin permite elegir un preset y programar el reinicio; también
  están `/mapset <n>`, `/mapcancel` y `/mapreload`.
- Los presets se leen de `presets/<carpeta>/server_cfg.ini` al arrancar el servidor (un preset creado después
  aparece tras el siguiente reinicio). Se muestran con el nombre que tienen en AC Panel. Al elegir uno se avisa
  a todos, se muestra la cuenta atrás y el servidor se reinicia por dentro con ese preset; no edita sus archivos.
  No hay reconexión automática: justo antes del reinicio se saca a todos con el aviso "CAMBIO DE PRESET";
  espera en Content Manager, vuelve a entrar y elige un coche de la nueva lista.
- Un reinicio desde Pterodactyl o AC Panel vuelve a la configuración de arranque, salvo que en AC Panel tengas
  "Configuración al arrancar" en "el último preset que estuvo en pista".

## API HTTP (para menús Lua)
- `GET /mapvote/tracks`: circuitos instalados (id, carpeta, layout, nombre).
- `GET /mapvote/status`: estado de la votación.
- `GET /admin/presets`: presets disponibles (`id`, `name` para mostrar, `folder`, `current`).
- `GET /cars/list`: coches del entry list con plazas libres ahora (`[{"id","name","free","total"}]`);
  el tráfico IA no cuenta como plaza libre.
- `GET /layouts/{track}`: archivos Lua publicados para el ID del circuito (`{"track","layouts":[{"name","size"}]}`).
- `GET /layouts/{track}/{fileName}`: descarga el archivo Lua de DriftZonesEditor (máximo 5 MiB).

## Eventos online (para menús Lua)
- `ACP_MapVoteAction` (cliente → servidor): `action` 1 proponer, 2 a favor, 3 en contra; `id` del circuito.
- `ACP_MapVoteReconnect` (servidor → todos): `time` segundos hasta reconectar.
- `ACP_AdminStatusRequest` (cliente → servidor, campo `request`, cualquier valor) y
  `ACP_AdminStatusResponse` (servidor → solo quien pregunta): `isAdmin` 1 si esa conexión ha hecho
  `/admin <contraseña>`. Pídelo después de `/admin`. Solo sirve para mostrar u ocultar opciones;
  los comandos de admin se comprueban siempre en el servidor.
- `ACP_AdminPresetChange` (cliente → servidor, campo `presetId`): solicita cambiar al preset indicado.
  El servidor comprueba `IsAdministrator` antes de aceptar la solicitud y emitir el aviso/reinicio.

## Notas
- Compilado contra AssettoServer v0.0.55-pre45. Si actualizas AssettoServer, hay que recompilarlo.
- Nunca modifica un preset: cambia TRACK/CONFIG_TRACK en cfg/server_cfg.ini. Si en pista había un preset
  (cargado por la votación entre presets), copia antes su server_cfg.ini y su entry_list.ini a cfg/.
  Con `ApplyToAllPresets: true` cambia el circuito también en todos los presets.
- El circuito debe estar instalado en el servidor (content/tracks) y en el juego de cada jugador.
- El menú abre cada layout como descarga del navegador. La ruta de ejemplo es
  `steamapps/common/assettocorsa/apps/lua/DriftZonesEditor/tracks`; el menú no configura
  esa carpeta ni puede seleccionarla en el diálogo del navegador. El jugador debe cargar
  los layouts desde DriftZonesEditor. Se sirven como archivos, no se ejecutan en el menú
  ACS Drift. DriftZonesEditor sí ejecuta el Lua al cargarlo, así que publica únicamente
  archivos de confianza.
- Si el circuito no tiene ubicación en data_track_params.ini, activa "No pedir ubicación" en AC Panel.
- `codigo-fuente/` es solo de referencia; el servidor usa `plugins/AcsDriftServerPlugin/`.

## Para seguir desarrollando
- **Parte siempre de `codigo-fuente/` de este zip.** Es la versión que corre en el servidor. Si trabajas sobre
  una copia anterior se pierden arreglos (ya ha pasado dos veces).
- **Hay que compilar.** El servidor solo usa `plugins/AcsDriftServerPlugin/AcsDriftServerPlugin.dll`; cambiar
  el código o renombrar el DLL viejo no hace nada. Compila contra AssettoServer **v0.0.55-pre45 exactamente**
  (net11). Si no puedes, pasa el código y se compila aquí.
- El nombre del ensamblado y de la carpeta tienen que ser `AcsDriftServerPlugin`, y en `EnablePlugins` va ese
  mismo nombre. La clase de configuración sigue siendo `MapVoteConfiguration`, para que el archivo siga siendo
  `cfg/plugin_map_vote_cfg.yml`; si se renombra, cambia el nombre del archivo y se pierden los ajustes.
- `#if MAPVOTE_TEST` solo entra en la compilación de pruebas (fuerza cambios sin jugadores conectados:
  `POST /mapvote/test/apply/{id}` y `POST /mapvote/test/preset/{id}`). No compiles la versión del servidor con
  `MAPVOTE_TEST`: esas rutas no piden contraseña.

### Cosas que no hay que quitar
- `MapVoteCommandModule.Run(...)`: envuelve cada comando y escribe en el log el error completo
  (`ACS Drift Server: fallo en ...`). Sin él, AssettoServer solo dice "An exception occurred".
- `private readonly object _lock`: no lo cambies por `Lock`.
- En `ApplyChangeAsync`: si en pista hay un preset, se copian a cfg/ **su `server_cfg.ini` y su
  `entry_list.ini`**. Cada preset puede tener sus propios coches; sin copiar el entry_list, al cambiar de
  circuito se cargarían los coches de otra configuración.
- No se declara `FREQUENT_TRACK_CHANGES` si `VotingPresetPlugin` está activado: los dos lo declararían y
  AssettoServer no arrancaría.
- `PresetEntry.Folder` (la carpeta, lo que se pasa a `Program.RestartServer`) y `PresetEntry.Name` (el nombre
  para mostrar) son distintos. No uses `Name` para reiniciar.
- Cualquier acción de admin que llegue por evento online tiene que comprobar `client.IsAdministrator` en el
  servidor, aunque el menú ya oculte el botón.
- No enviar `KickCar` con `SessionId = 255` (broadcast): puede cerrar el juego del cliente. Para expulsar
  jugadores al cambiar de preset, enviar `KickCar` con el SessionId individual y cerrar las conexiones después
  de que el aviso haya permanecido visible, con `EntryCarManager.KickAsync` (`ACTcpClient.DisconnectAsync` no es
  público en pre45).
- Envuelve en `try/catch` cualquier bucle que recorra jugadores antes de un reinicio: si una excepción lo corta,
  el reinicio no llega a hacerse.

## Cambios

### 2026-11-09: fantasma, confirmar antes de guardar y salida parada de 1 s
- El timestamp de las posiciones del fantasma usa `SessionManager.ServerTimeMilliseconds` (antes
  `Environment.TickCount64`, que no coincidía con la base del `TimeOffset` y lanzaba el coche lejísimos).
- Parar una grabación ya no la guarda: el servidor la recorta y la deja pendiente (`state` 4, `seconds` =
  duración). Se guarda con `action` 7 (o `/ghostsave`) y se descarta con `action` 8, `/ghostdiscard` o
  `/ghostcancel`. Código de error nuevo: 8 no hay grabación pendiente. `/ghost/status` añade `pending` y
  `pendingSeconds`.
- La pendiente se descarta si su autor se va, a los 5 minutos sin confirmar o al empezar otra grabación.
  Si el jugador se va a mitad de grabación, ahora se descarta (antes se guardaba).
- Recorte: se quita la parada inicial (velocidad ≤ 0,5 m/s) y se pone en su lugar exactamente 1 s de coche
  quieto en la última postura parada (`GhostService.TrimStart`).

### 2026-11-07: fantasma (pasada grabada), solo administradores
- Nuevos archivos: `GhostFile.cs` (formato de pasada), `GhostRecorder.cs`, `GhostService.cs` (grabación,
  reproducción y reserva de plaza), `GhostSlotFilter.cs` (impide que un jugador entre en esa plaza),
  `GhostCommandModule.cs` (comandos de chat) y `GhostController.cs` (`GET /ghost/list`, `GET /ghost/status`).
- Un solo fantasma a la vez: cargar otro sobrescribe el anterior. Todas las acciones son de administrador
  (se comprueba `IsAdministrator` en el servidor, también en el evento online).
- Eventos online: `ACP_GhostAction` (cliente → servidor: `action` 1 grabar, 2 parar (ver 2026-11-09), 3 cancelar,
  4 cargar `id`, 5 quitar, 6 borrar `id`) y `ACP_GhostState` (servidor → quien pregunta: `state` 0 libre,
  1 grabando, 2 guardada, 3 error; `seconds`, `code`, `id`). Códigos de error: 1 no admin, 2 sin coche,
  3 ya se graba, 4 pasada demasiado corta, 5 sin plaza libre del modelo, 6 no existe, 7 no se graba nada.
- Comandos: `/ghostrec`, `/ghoststop`, `/ghostcancel`, `/ghostlist`, `/ghostplay <id>`, `/ghostclear`,
  `/ghostdelete <id>`.
- Pasadas en `cfg/ghosts/<circuito>/<layout>/<id>.json` + `<id>.ghost` (60 bytes por muestra).
- Configuración nueva en `plugin_map_vote_cfg.yml`: `GhostsFolder`, `GhostMaxRecordSeconds`,
  `GhostLoopGapSeconds`, `GhostPlaybackHz`.
- `MapVoteConfiguration` y `AcsDriftServerPlugin.CurrentTrack` (ahora `TrackOf`, estático) son los únicos
  cambios en código existente, además del registro en `AcsDriftServerModule`.
- **Sin compilar ni probar todavía.** Pendiente de validar: la unidad de `Rotation` (`AngleWrap`), el
  timestamp que ve el cliente (se calcula como en `EntryCar.GetPositionUpdateForCar`), la cadencia real con
  `Task.Delay` (no es un temporizador de precisión) y la comprobación de que nadie aparezca encima del fantasma
  al reaparecer (todavía no se hace).

### 2026-11-02 (d): desconexión de clientes al cambiar de preset
- Al terminar la cuenta atrás, se envían a cada jugador los paquetes de aviso/expulsión usando su `SessionId`
  individual. El aviso indica la cuenta atrás total; tras mostrar la pantalla de expulsión durante dos segundos
  se cierran las conexiones y se reinicia AssettoServer con el preset seleccionado.
- Evita el `SessionId = 255` global que precedió al crash y permite volver desde Content Manager tras el aviso.
- Textos del juego (menú `lua/mapvote.lua`, mensajes del chat) y del log pasados al inglés. El menú del chat
  de CSP se llama ahora "Track vote". Los comandos no cambian.
- La desconexión tras el aviso usa paquetes con SessionId individual; queda por probar en el juego con
  clientes conectados.
- Revisado aquí:
  - **No compilaba**: `ACTcpClient.DisconnectAsync()` no es público en pre45 (error CS1061). Cambiado por
    `EntryCarManager.KickAsync(client, KickReason.Kicked, "preset change", PresetKickReasonText)`, que es lo que
    usa el `/kick` de AssettoServer y cierra la conexión. Va después de los 2 s del aviso, como querías.
  - `KickCar` se envía con `client.SendPacket`, solo a ese jugador y con su propio SessionId.
  - Añadido un `try/catch` por jugador al avisar y al desconectar. Si un jugador se iba justo en ese momento,
    la excepción cortaba el bucle, se cancelaba el reinicio y el servidor se quedaba con el preset anterior.
  - Probado el cambio forzado de `p1` a `p2` sin jugadores conectados.

### 2026-11-02 (c): cambio de preset sin reconexión automática
- Del colega: al cambiar de preset ya no se intenta la reconexión automática (el preset nuevo puede tener otros
  coches); se avisa por chat de que hay que elegir coche a mano. `NotifyAndRestartAsync` se divide y el reinicio
  pasa a `RestartAsync(name, preset, delaySeconds, token)`.
- Quitado el envío de `KickCar` a `SessionId = 255` y `CSPKickBanMessageOverride` al cambiar de preset:
  el informe de crash muestra errores al buscar ese session ID justo antes del crash nativo del cliente en
  `ACClient::onMessageTCP`. Los clientes se desconectan cuando el servidor se reinicia.
- Corregido aquí también en el cambio de circuito: cuando no hay reconexión automática (`EnableReconnect: false`
  o `EnableClientMessages: false`) se hacía el mismo `KickCar` a `SessionId = 255`. Quitado; solo queda el
  aviso por chat en ese flujo. Se permite `KickCar` con el SessionId individual, nunca con 255.
- Probado contra pre45: cambio forzado de `p1` a `p2`, carga `presets/p2/server_cfg.ini`.

### 2026-11-02 (b): cambio de preset desde el menú admin
- Del colega:
  - `ACP_AdminPresetChange` (campo `presetId`) y `GET /admin/presets`, con `PresetCatalog` y `AdminPresetController`.
  - Cambio de preset programado con aviso y cuenta atrás; `/mapcancel` también lo cancela.
  - No se puede cambiar de preset y votar circuito a la vez.
- Corregido aquí:
  - `PresetEntry` separa `Folder` y `Name`.
  - El menú muestra el nombre del preset de AC Panel (`Meta.Name` de `plugin_voting_preset_cfg.yml`) y el
    reinicio usa la carpeta. Antes, con un nombre distinto de la carpeta, el reinicio habría buscado un preset
    que no existe.
  - `/admin/presets` devuelve también `folder`.
- Probado contra pre45: arrancado con el preset `p1`, cambio forzado a `p2`; carga `presets/p2/server_cfg.ini`
  y `/admin/presets` marca `p2` como activo.

### 2026-11-02 (a): MapVotePlugin pasa a llamarse AcsDriftServerPlugin
- Del colega:
  - Cambio de nombre (namespace, clases, carpeta, mensajes del log).
  - `ACP_AdminStatusRequest` lleva el campo `request`.
- Corregido aquí: se volvieron a meter `Run(...)`, `object _lock` y la copia de `entry_list.ini`, que se
  habían perdido por partir de una copia antigua.
- AC Panel reconoce los dos nombres, usa el nuevo si está subido y nunca activa los dos a la vez.

### 2026-11-01 (b): estado de administrador
- Del colega: `ACP_AdminStatusRequest` / `ACP_AdminStatusResponse`, con la respuesta solo a quien pregunta.
- Comprobado aquí que la propiedad `ACTcpClient.IsAdministrator` existe en pre45.

### 2026-11-01 (a): lista de coches
- Del colega: `GET /cars/list` (`CarCatalog`, `CarListController`), con las plazas libres por modelo. El tráfico
  IA no cuenta como libre.
- Corregido aquí: se partió de una versión antigua y se habían perdido `Run(...)`, `object _lock` y la copia de
  `entry_list.ini`.

### 2026-10-30
- Si en pista hay un preset, el cambio de circuito copia también su `entry_list.ini` a cfg/.
- `Run(...)` en los comandos para ver el error completo en el log.
- Compilado con información de depuración embebida (`-debug:embedded`), para que el log muestre la línea del
  error.
- Nunca se modifica un preset: el circuito nuevo se escribe en cfg/ y se reinicia desde cfg/.
- No se declara `FREQUENT_TRACK_CHANGES` si `VotingPresetPlugin` está activado.

### 2026-10-29: versión inicial adaptada a pre45
- Basada en el MapVotePlugin original del colega, que necesitaba un lanzador externo.
- Ahora reinicia AssettoServer por dentro (`Program.RestartServer`), así que funciona en Pterodactyl sin lanzador.
- La configuración va en su propio archivo (`cfg/plugin_map_vote_cfg.yml`).
- Reconexión automática de los jugadores, menú "Votar circuito" (`lua/mapvote.lua`) y comandos de chat.
- La votación se cierra antes si ya no puede salir; `/mapset` para admins.
