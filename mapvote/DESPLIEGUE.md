# Votacion de mapa independiente de los presets

## Que hace
- Lista los mapas y layouts instalados en `content/tracks` del servidor.
- Cualquier jugador propone un mapa+layout (menu o `/mapstart <n>`).
- Umbral: estrictamente mas del 50 % de los conectados AL INICIAR la votacion.
- Se aprueba en cuanto los votos a favor alcanzan el umbral; si no, caduca a los 60 s.
- 120 s de espera desde que se inicia una votacion hasta poder iniciar otra.
- Al aprobar: se guarda `map_selection.json` y se reinicia el servidor con el nuevo mapa.
- Los presets de coches no se tocan: el lanzador solo reescribe TRACK y CONFIG_TRACK.

## Contenido
- `MapVotePlugin/`     plugin C# para AssettoServer
- `server/`            lanzador (ps1/sh) y configuracion de ejemplo
- `acs_drift_menu.lua` menu actualizado (v0.5)

## 1. Compilar el plugin (NO esta compilado ni probado)
1. Clona el repositorio de AssettoServer (la MISMA version que usa el servidor).
2. Copia la carpeta `MapVotePlugin` junto a las demas carpetas de plugins del repositorio
   y anadela a la solucion (`dotnet sln add MapVotePlugin/MapVotePlugin.csproj`).
3. `dotnet publish MapVotePlugin -c Release -r win-x64` (o `linux-x64`).
4. Copia la carpeta publicada a `plugins/MapVotePlugin/` del servidor.
5. Si el compilador marca errores, empieza por las lineas marcadas [VERIFICAR] en `MapVotePlugin.cs`.

## 2. Configurar el servidor
1. Anade el contenido de `server/extra_cfg_snippet.yml` a `extra_cfg.yml`.
2. DESACTIVA la votacion de circuito de tus plugins de presets (VotingPresetPlugin /
   CyclePresetPlugin) para que no compitan con esta. Los presets de coches siguen igual.
3. Arranca el servidor con `server/start_server.ps1` (Windows) o `server/start_server.sh`
   (Linux, requiere jq) en lugar de lanzar el ejecutable a mano. Sin el lanzador el plugin
   no puede aplicar el mapa elegido.
4. Haz copia de seguridad de `cfg/` y `presets/`: el lanzador modifica TRACK y CONFIG_TRACK
   en `cfg/server_cfg.ini` y en `presets/*/server_cfg.ini`.

## 3. Menu
1. Sube `acs_drift_menu.lua` a tu URL de [SCRIPT_1] (cambia el nombre/ruta para evitar la cache).
2. El menu lee `http://<ip>:<puerto HTTP>/mapvote/tracks` y `/mapvote/status`:
   el puerto HTTP del servidor debe estar abierto para los jugadores.

## Comandos de chat (sin menu)
`/maplist [pagina]`, `/mapstart <n>`, `/mapyes`, `/mapno`, `/mapstatus`
Admin: `/mapcancel`, `/mapreload`

## Ojo
- Los jugadores se desconectan al reiniciar el servidor y deben volver a entrar.
- El mapa debe estar instalado tambien en los clientes (o descargable via CM).
- Ajustes por mapa en extra_cfg.yml (coordenadas, zona horaria del clima) NO cambian solos.