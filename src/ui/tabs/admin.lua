-- Pestana: Admin (solo visible si esta conexion entro con /admin <contraseña>).
-- De momento son accesos directos a comandos de chat /map* ya existentes en el
-- servidor (AcsDriftServerPlugin, marcados [RequireAdmin]); se puede ampliar aqui.
local T = import('ui/theme')
local I18N = import('i18n')
local C, sectionTitle, styledButton, smallText = T.C, T.sectionTitle, T.styledButton, T.smallText

-- [VERIFICAR] nombre de la funcion de CSP para enviar un mensaje de chat local (se asume ac.sendChatMessage).
local function sendChat(cmd)
  local ok = pcall(ac.sendChatMessage, cmd)
  if not ok then ac.log(I18N.get('admin.send_error', cmd)) end
end

return function()
  sectionTitle(I18N.get('tab.admin'), C.accentHi)
  smallText(I18N.get('admin.description'))
  ui.dummy(vec2(0, 8))

  if styledButton(I18N.get('admin.cancel'), vec2(-0.1, 32)) then
    sendChat('/mapcancel')
  end
  if styledButton(I18N.get('admin.reload'), vec2(-0.1, 32)) then
    sendChat('/mapreload')
  end
end
