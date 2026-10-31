-- Cambio de coche: la lista ya no se edita a mano (CONFIG.cars); se lee del
-- entry list real del servidor via MapVotePlugin (/cars/list), con cuantas
-- plazas de cada coche estan libres ahora mismo. El cambio sigue siendo una
-- reconexion (ac.reconnectTo): el servidor asigna la plaza libre que toque.
local CONFIG = import('config')
local core = import('core')
local net = import('net')

local M = {}

local state = {
  list = {}, status = 'idle',   -- idle | loading | ok | error
  pollTimer = 0,
}
M.data = state

function M.refresh()
  state.status = 'loading'
  net.getJson('/cars/list', function(data, err)
    if data then
      state.list, state.status = data, 'ok'
    else
      state.status = 'error'
      core.notify('Lista de coches: ' .. tostring(err))
    end
  end)
end

-- active = true cuando la pestana de coche esta visible (decide la UI, no este modulo).
function M.update(dt, active)
  if not active then return end
  if state.status == 'idle' then M.refresh() end
  state.pollTimer = state.pollTimer - dt
  if state.pollTimer <= 0 then
    state.pollTimer = 4 -- las plazas libres cambian poco: no hace falta sondear tan rapido como el mapa
    M.refresh()
  end
end

function M.changeCar(carID)
  if not carID or carID == '' then
    core.notify('No se ha podido cambiar de coche: seleccion no valida.')
    return false
  end

  local params = { carID = carID }
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
