-- Pestana: reaparicion / TP y boton de retorno.
local teleport = import('features/teleport')
local T = import('ui/theme')
local I18N = import('i18n')
local C, smallText, sectionTitle, styledButton = T.C, T.smallText, T.sectionTitle, T.styledButton

return function()
  local returnButton = teleport.returnButton

  sectionTitle(I18N.get('teleport.title'), C.accentHi)
  if styledButton(I18N.get('teleport.save'), vec2(-0.1, 34), false) then teleport.savePoint() end
  if styledButton(I18N.get('teleport.return'), vec2(-0.1, 34), false) then teleport.teleportToPoint() end
  if styledButton(I18N.get('teleport.pits'), vec2(-0.1, 34), false) then teleport.teleportToPits() end

  sectionTitle(I18N.get('teleport.button_title'), C.accentHi)
  smallText(I18N.get('teleport.assign_hint'))
  ui.dummy(vec2(0, 4))
  returnButton:control(vec2(ui.availableSpaceX(), 30))
  ui.dummy(vec2(0, 2))
  if returnButton:configured() then
    smallText(I18N.get('teleport.assigned', tostring(returnButton:boundTo())), C.accentHi)
  else
    smallText(I18N.get('teleport.unassigned'))
  end
end
