-- Hora del dia.
local core = import('core')

local M = {}

function M.setTimeOfDay(hour)
  core.safe('Hora del dia', function()
    -- [VERIFICAR] pendiente: poner aqui la funcion real del SDK para la hora
    error('pendiente de implementar')
  end)
end

return M
