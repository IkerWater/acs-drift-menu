-- Configuracion editable del menu. Solo datos, sin logica.
return {
  toggleKey = ui.KeyIndex.M,

  -- Coches ofrecidos ('id' = carpeta del coche, 'skins' = carpetas de skin).
  -- Deben existir como entradas en el entry_list del servidor.
  cars = {
    { id = 'tunermnrcars_eskuko_missile_e36coupe',   name = 'Eskuko Missile E36 Coupe',   skins = { 'default', 'Titanio' } },
    { id = 'tunermnrcars_eskuko_missile_e36compact', name = 'Eskuko Missile E36 Compact', skins = { 'default', 'JulenArjona' } },
  },

  -- Datos del servidor para reconectar (cambio de coche/skin).
  server = { host = '', port = 9600, httpPort = 8081, password = '' },

  -- Comandos de chat del plugin MapVotePlugin (votacion de mapa independiente de los presets).
  commands = {
    mapStart = '/mapstart %d',
    mapYes   = '/mapyes',
    mapNo    = '/mapno',
  },
}
