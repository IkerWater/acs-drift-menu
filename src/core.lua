-- Estado compartido y utilidades basicas. No depende de ningun otro modulo.
local M = {}

M.state = {
  open = false,
  tab = 'car',            -- id de la pestana activa (ver ui/menu.lua)
  carIndex = 1, skinIndex = 1,
  hour = 12,
  message = '', messageTime = 0,
  savedPoint = nil,
  -- Ajustes del propio menu (pestana 'settings'). Solo duran la sesion.
  settings = {
    accentIndex = 1,   -- indice en T.ACCENTS
    bgAlpha     = 0.15,
    closeOnGas  = false, -- cerrar el menu al acelerar (ver main.lua)
    posX        = 10,    -- % del espacio libre horizontal (0 = pegado a la izquierda, 100 = a la derecha)
    posY        = 15,    -- % del espacio libre vertical (0 = arriba, 100 = abajo)
  },
}

function M.notify(text)
  M.state.message, M.state.messageTime = text, os.clock()
  ac.log('[ACS Menu] ' .. text)
end

-- Ejecuta fn protegida; si falla, avisa en el menu y devuelve false.
function M.safe(label, fn)
  local ok, err = pcall(fn)
  if not ok then M.notify(label .. ': no disponible (' .. tostring(err):sub(1, 70) .. ')') end
  return ok
end

function M.sendChatCommand(cmd)
  ac.sendChatMessage(cmd)
  M.notify('Enviado: ' .. cmd)
end

return M
