-- Pestana: reaparicion / TP y boton de retorno.
local teleport = import('features/teleport')
local T = import('ui/theme')
local C, smallText, sectionTitle, styledButton = T.C, T.smallText, T.sectionTitle, T.styledButton

return function()
  local returnButton = teleport.returnButton

  sectionTitle('Reaparicion / TP', C.accentHi)
  if styledButton('Guardar punto actual', vec2(-0.1, 34), false) then teleport.savePoint() end
  if styledButton('Volver al punto guardado', vec2(-0.1, 34), false) then teleport.teleportToPoint() end
  if styledButton('Ir a pits', vec2(-0.1, 34), false) then teleport.teleportToPits() end

  sectionTitle('Boton de retorno', C.accentHi)
  smallText('Asigna una tecla o boton para volver al punto guardado.')
  ui.dummy(vec2(0, 4))
  returnButton:control(vec2(ui.availableSpaceX(), 30))
  ui.dummy(vec2(0, 2))
  if returnButton:configured() then
    smallText('Asignado a: ' .. tostring(returnButton:boundTo()), C.accentHi)
  else
    smallText('Sin asignar: pulsa el cuadro y luego la tecla/boton.')
  end
end
