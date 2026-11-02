-- Punto de reaparicion, TP a pits y boton configurable de retorno.
local core = import('core')
local I18N = import('i18n')

local M = {}

-- Boton configurable para volver al punto guardado (se asigna en la pestana TP).
-- El id debe ser unico; CSP guarda la asignacion por id.
M.returnButton = ac.ControlButton('__ACS_DRIFT_RETURN')

function M.savePoint()
  local car = ac.getCar(0)
  if not car or not car.position or not car.look then
    return core.notify(I18N.get('teleport.save_error'))
  end
  core.state.savedPoint = { pos = car.position:clone(), dir = car.look:clone() }
  core.notify(I18N.get('teleport.saved'))
end

function M.teleportToPoint()
  local p = core.state.savedPoint
  if not p then return core.notify(I18N.get('teleport.no_point')) end
  core.safe(I18N.get('teleport.action_error'), function()
    physics.setCarPosition(0, p.pos, (p.dir * -1))
  end, I18N.get('common.unavailable'))
end

function M.teleportToPits()
  core.safe(I18N.get('teleport.pits_error'), function()
    physics.teleportCarTo(0, ac.SpawnSet.Pits)
  end, I18N.get('common.unavailable'))
end

-- Escucha el boton de retorno aunque el menu este cerrado.
function M.update(dt)
  if M.returnButton:pressed() then
    M.teleportToPoint()
  end
end

return M
