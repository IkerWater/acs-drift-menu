# MapVotePlugin para AssettoServer 0.0.55-pre45

Votación libre de circuito: cualquier jugador propone un circuito instalado y se cambia si vota
a favor más de la mitad de los conectados. Funciona dentro de Pterodactyl: el plugin cambia el circuito
y reinicia AssettoServer por dentro; los jugadores se reconectan solos.

## Instalar
1. Para el servidor.
2. En Pterodactyl > Files, en la carpeta raíz del servidor, sube `MapVotePlugin.zip` y descomprímelo
   (Unarchive). Debe quedar `plugins/MapVotePlugin/MapVotePlugin.dll` y `plugins/MapVotePlugin/lua/mapvote.lua`.
3. En AC Panel > Presets activa "Votación libre de circuito" (o añade `- MapVotePlugin` a `EnablePlugins`
   en `extra_cfg.yml` de cfg/ y de cada preset) y reinicia.
4. Al primer arranque se crea `cfg/plugin_map_vote_cfg.yml` con los ajustes (duraciones, etc.).

## En el juego
- Menú: en el chat de CSP, extras > "Votar circuito" (buscar, Proponer, A favor / En contra).
- Chat: `/maplist [página]`, `/mapstart <n>`, `/mapyes`, `/mapno`, `/mapstatus`
- Admin (`/admin <contraseña>`): `/mapset <n>` cambia ya, `/mapcancel`, `/mapreload`

## API HTTP (para menús Lua del juego)
- `GET /mapvote/tracks`: circuitos instalados (id, carpeta, layout, nombre).
- `GET /mapvote/status`: estado de la votación.
- `GET /cars/list`: coches del entry list con plazas libres ahora mismo
  (`[{"id":"carpeta","name":"Nombre","free":1,"total":3}]`); el tráfico IA no cuenta como plaza libre.

## Notas
- Compilado contra AssettoServer v0.0.55-pre45. Si actualizas AssettoServer, hay que recompilarlo.
- Nunca modifica un preset: cambia TRACK/CONFIG_TRACK en cfg/server_cfg.ini. Si en pista había un preset
  (cargado por la votación entre presets), copia antes su server_cfg.ini y su entry_list.ini a cfg/.
  Con `ApplyToAllPresets: true` cambia el circuito también en todos los presets.
- El circuito debe estar instalado en el servidor (content/tracks) y en el juego de cada jugador.
- Si el circuito no tiene ubicación en data_track_params.ini, activa "No pedir ubicación" en AC Panel.
- `codigo-fuente/` es solo de referencia; el servidor usa la carpeta `plugins/`.
