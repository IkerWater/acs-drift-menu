# AcsDriftServerPlugin para AssettoServer 0.0.55-pre45

Plugin de servidor para ACS Drift (antes MapVotePlugin). Da al menú CSP de ACS Drift los coches con plazas
libres, el estado de administrador y los presets disponibles. Permite votar circuitos o que un administrador
cambie directamente el preset activo; AssettoServer se reinicia por dentro. La reconexión automática solo se
usa al cambiar de circuito.

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

Nunca actives los dos plugins a la vez: registran las mismas rutas y eventos.

## En el juego
- Menú: en el chat de CSP, extras > "Votar circuito" (buscar, Proponer, A favor / En contra).
- Chat: `/maplist [página]`, `/mapstart <n>`, `/mapyes`, `/mapno`, `/mapstatus`
- Admin (`/admin <contraseña>`): el tab Admin permite elegir un preset y programar el reinicio; también
  están `/mapset <n>`, `/mapcancel` y `/mapreload`.
- Los presets se leen de `presets/<carpeta>/server_cfg.ini` al arrancar el servidor (un preset creado después
  aparece tras el siguiente reinicio). Se muestran con el nombre que tienen en AC Panel. Al elegir uno se avisa
  a todos, se muestra la cuenta atrás y el servidor se reinicia por dentro con ese preset; no edita sus archivos.
  No hay reconexión automática: espera en Content Manager y elige manualmente un coche de la nueva lista.
- Un reinicio desde Pterodactyl o AC Panel vuelve a la configuración de arranque, salvo que en AC Panel tengas
  "Configuración al arrancar" en "el último preset que estuvo en pista".

## API HTTP (para menús Lua)
- `GET /mapvote/tracks`: circuitos instalados (id, carpeta, layout, nombre).
- `GET /mapvote/status`: estado de la votación.
- `GET /admin/presets`: presets disponibles (`id`, `name` para mostrar, `folder`, `current`).
- `GET /cars/list`: coches del entry list con plazas libres ahora (`[{"id","name","free","total"}]`);
  el tráfico IA no cuenta como plaza libre.

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

## Cambios

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
