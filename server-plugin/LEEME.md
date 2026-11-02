# AcsDriftServerPlugin para AssettoServer 0.0.55-pre45

Plugin de servidor para ACS Drift (antes MapVotePlugin). Da al menú CSP de ACS Drift los coches con plazas
libres y el estado de administrador, y hace la votación libre de circuito: cambia el circuito y reinicia
AssettoServer por dentro; los jugadores se reconectan solos.

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
- Admin (`/admin <contraseña>`): `/mapset <n>` cambia ya, `/mapcancel`, `/mapreload`

## API HTTP (para menús Lua)
- `GET /mapvote/tracks`: circuitos instalados (id, carpeta, layout, nombre).
- `GET /mapvote/status`: estado de la votación.
- `GET /cars/list`: coches del entry list con plazas libres ahora (`[{"id","name","free","total"}]`);
  el tráfico IA no cuenta como plaza libre.

## Eventos online (para menús Lua)
- `ACP_MapVoteAction` (cliente → servidor): `action` 1 proponer, 2 a favor, 3 en contra; `id` del circuito.
- `ACP_MapVoteReconnect` (servidor → todos): `time` segundos hasta reconectar.
- `ACP_AdminStatusRequest` (cliente → servidor, campo `request`, cualquier valor) y
  `ACP_AdminStatusResponse` (servidor → solo quien pregunta): `isAdmin` 1 si esa conexión ha hecho
  `/admin <contraseña>`. Pídelo después de `/admin`. Solo sirve para mostrar u ocultar opciones;
  los comandos de admin se comprueban siempre en el servidor.

## Notas
- Compilado contra AssettoServer v0.0.55-pre45. Si actualizas AssettoServer, hay que recompilarlo.
- Nunca modifica un preset: cambia TRACK/CONFIG_TRACK en cfg/server_cfg.ini. Si en pista había un preset
  (cargado por la votación entre presets), copia antes su server_cfg.ini y su entry_list.ini a cfg/.
  Con `ApplyToAllPresets: true` cambia el circuito también en todos los presets.
- El circuito debe estar instalado en el servidor (content/tracks) y en el juego de cada jugador.
- Si el circuito no tiene ubicación en data_track_params.ini, activa "No pedir ubicación" en AC Panel.
- `codigo-fuente/` es solo de referencia; el servidor usa `plugins/AcsDriftServerPlugin/`.
