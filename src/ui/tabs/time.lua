-- Pestana: hora del dia.
local core = import('core')
local time = import('features/time')
local T = import('ui/theme')
local C, sectionTitle, styledButton = T.C, T.sectionTitle, T.styledButton

return function()
  local state = core.state

  time.initialize()
  sectionTitle('Hora del dia (solo tu cliente)', C.accentHi)
  ui.pushStyleColor(ui.StyleColor.FrameBg, C.surface)
  ui.pushStyleColor(ui.StyleColor.SliderGrab, C.accent)
  ui.pushStyleColor(ui.StyleColor.SliderGrabActive, C.accentHi)
  ui.pushStyleVar(ui.StyleVar.FrameRounding, 9)
  ui.setNextItemWidth(ui.availableSpaceX())
  state.hour = ui.slider('##hour', state.hour, 0, 24, 'Hora: %.1f')
  ui.popStyleVar(1)
  ui.popStyleColor(3)
  ui.dummy(vec2(0, 8))
  if styledButton('Aplicar hora', vec2(-0.1, 36), true) then time.setTimeOfDay(state.hour) end
end
