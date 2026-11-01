# AcsDriftServerPlugin para AssettoServer 0.0.55-pre45

Plugin de servidor para ACS Drift. Centraliza la comunicación entre el menú CSP y AssettoServer:
gestiona los coches disponibles, los comandos de administración y la votación libre de circuito.
La votación cambia el circuito y reinicia AssettoServer por dentro; los jugadores se reconectan solos.

## Instalar
1. Para el servidor.
2. En Pterodactyl > Files, en la carpeta raíz del servidor, sube el paquete `AcsDriftServerPlugin.zip` y descomprímelo
   (Unarchive). Debe quedar `plugins/AcsDriftServerPlugin/AcsDriftServerPlugin.dll` y
   `plugins/AcsDriftServerPlugin/lua/mapvote.lua`.
3. En AC Panel > Presets activa "ACS Drift Server" (o añade `- AcsDriftServerPlugin` a `EnablePlugins`
   en `extra_cfg.yml` de cfg/ y de cada preset) y reinicia.
4. Al primer arranque se crea `cfg/plugin_map_vote_cfg.yml` con los ajustes de votación. Ese nombre
   se mantiene para conservar la configuración existente.

## En el juego
- Menú: en el chat de CSP, extras > "Votar circuito" (buscar, Proponer, A favor / En contra).
- El menú ACS Drift consulta a este plugin el estado de administrador de la conexión y los coches
  disponibles; mantén el plugin y el script CSP en versiones compatibles.
- Chat: `/maplist [página]`, `/mapstart <n>`, `/mapyes`, `/mapno`, `/mapstatus`
- Admin (`/admin <contraseña>`): `/mapset <n>` cambia ya, `/mapcancel`, `/mapreload`

## Notas
- Compilado contra AssettoServer v0.0.55-pre45. Si actualizas AssettoServer, hay que recompilarlo.
- El tab Admin del menú ACS recibe su estado del evento `ACP_AdminStatusRequest`.
- El binario anterior se conserva en `legacy/` como referencia; es obsoleto y no implementa los eventos nuevos. Integra y compila el código fuente con el proyecto de AssettoServer como `AcsDriftServerPlugin.dll` antes de desplegar; no basta con renombrar el DLL antiguo.
- Cambia TRACK/CONFIG_TRACK en el server_cfg.ini en uso (cfg/ o el preset activo). Con
  `ApplyToAllPresets: true` lo cambia también en cfg/ y todos los presets.
- El circuito debe estar instalado en el servidor (content/tracks) y en el juego de cada jugador.
- Si el circuito no tiene ubicación en data_track_params.ini, activa "No pedir ubicación" en AC Panel.
- `codigo-fuente/` contiene la implementación de referencia; el servidor ejecuta el ensamblado compilado en `plugins/AcsDriftServerPlugin/`.
