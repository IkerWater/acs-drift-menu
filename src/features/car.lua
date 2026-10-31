-- Cambio de coche/skin por reconexion al servidor.
local CONFIG = import('config')
local core = import('core')

local M = {}

function M.changeCar(carIdx)
  local car = CONFIG.cars[carIdx]
  if not car then
    core.notify('No se ha podido cambiar de coche: seleccion no valida.')
    return false
  end

  local params = { carID = car.id }
  if CONFIG.server.host ~= '' then
    params.serverIP = CONFIG.server.host
    params.serverPort = CONFIG.server.port
    params.serverHttpPort = CONFIG.server.httpPort
    params.serverPassword = CONFIG.server.password
  end

  return core.safe('Cambio de coche', function()
    ac.reconnectTo(params)
  end)
end

return M
