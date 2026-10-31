-- Cambio de coche/skin por reconexion al servidor.
local CONFIG = import('config')
local core = import('core')

local M = {}

function M.changeCar(carIdx, skinIdx)
  local car = CONFIG.cars[carIdx]
  core.safe('Cambio de coche', function()
    ac.reconnectTo({
      host = CONFIG.server.host, port = CONFIG.server.port,
      httpPort = CONFIG.server.httpPort, password = CONFIG.server.password,
      car = car.id, skin = car.skins[skinIdx],
    })
  end)
end

return M
