-- Configuracion editable del menu. Solo datos, sin logica.
return {
  toggleKey = ui.KeyIndex.M,

  -- La lista de coches de la pestana "Coche" ya NO se edita aqui: se lee en vivo
  -- del entry list del servidor (features/car.lua -> GET /cars/list, servido por
  -- AcsDriftServerPlugin/CarListController). Para anadir o quitar coches, cambia el
  -- entry_list del preset/servidor; el menu lo recoge solo.

  -- Datos opcionales del servidor para reconectar. Dejando host y password vacios reconecta con los datos que tenia.
  server = { host = '', port = 9600, httpPort = 8081, password = '' },

  -- Comandos de chat del plugin AcsDriftServerPlugin (votacion de mapa independiente de los presets).
  commands = {
    mapStart = '/mapstart %d',
    mapYes   = '/mapyes',
    mapNo    = '/mapno',
  },
}
