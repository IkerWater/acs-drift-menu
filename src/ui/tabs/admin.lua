-- Pestana: Admin (solo visible si esta conexion entro con /admin <contraseña>).
-- De momento son accesos directos a comandos de chat /map* ya existentes en el
-- servidor (MapVotePlugin, marcados [RequireAdmin]); se puede ampliar aqui.
local T = import('ui/theme')
local C, sectionTitle, styledButton, smallText = T.C, T.sectionTitle, T.styledButton, T.smallText

-- [VERIFICAR] nombre de la funcion de CSP para enviar un mensaje de chat local (se asume ac.sendChatMessage).
local function sendChat(cmd)
  local ok = pcall(ac.sendChatMessage, cmd)
  if not ok then ac.log('No se pudo enviar: ' .. cmd) end
end

return function()
  sectionTitle('Admin', C.accentHi)
  smallText('Acciones de administrador (requieren haber entrado con /admin).')
  ui.dummy(vec2(0, 8))

  if styledButton('Cancelar votacion / cambio en curso', vec2(-0.1, 32)) then
    sendChat('/mapcancel')
  end
  if styledButton('Recargar lista de circuitos', vec2(-0.1, 32)) then
    sendChat('/mapreload')
  end
end
