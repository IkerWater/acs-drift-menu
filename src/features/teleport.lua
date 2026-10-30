-- Punto de reaparicion, TP a pits y boton configurable de retorno.
local core = import('core')

local M = {}

-- Boton configurable para volver al punto guardado (se asigna en la pestana TP).
-- El id debe ser unico; CSP guarda la asignacion por id.
M.returnButton = ac.ControlButton('__ACS_DRIFT_RETURN')

function M.savePoint()
  local car = ac.getCar(0)
  if not car or not car.position or not car.look then
    return core.notify('No se pudo guardar el punto')
  end
  core.state.savedPoint = { pos = car.position:clone(), dir = car.look:clone() }
  core.notify('Punto guardado')
end

function M.teleportToPoint()
  local p = core.state.savedPoint
  if not p then return core.notify('No hay punto guardado') end
  core.safe('Teleport', function()
    physics.setCarPosition(0, p.pos, (p.dir * -1)) -- [VERIFICAR]
  end)
end

function M.teleportToPits()
  core.safe('Teleport a pits', function()
    physics.teleportCarTo(0, ac.SpawnSet.Pits) -- [VERIFICAR]
  end)
end

-- Escucha el boton de retorno aunque el menu este cerrado.
function M.update(dt)
  if M.returnButton:pressed() then
    M.teleportToPoint()
  end
end

return M
