-- Pestana: cambio de coche.
local CONFIG = import('config')
local core = import('core')
local car = import('features/car')
local T = import('ui/theme')
local C, sectionTitle, styledButton = T.C, T.sectionTitle, T.styledButton

return function()
  local state = core.state

  sectionTitle('Coche', C.accentHi)
  for i, c in ipairs(CONFIG.cars) do
    if styledButton(c.name, vec2(-0.1, 32), state.carIndex == i) then
      state.carIndex, state.skinIndex = i, 1
    end
  end
  sectionTitle('Skin', C.accentHi)
  for i, s in ipairs(CONFIG.cars[state.carIndex].skins) do
    if styledButton(s, vec2(-0.1, 28), state.skinIndex == i) then state.skinIndex = i end
  end
  ui.dummy(vec2(0, 8))
  if styledButton('APLICAR  (reconecta)', vec2(-0.1, 38), true) then
    car.changeCar(state.carIndex, state.skinIndex)
  end
end
