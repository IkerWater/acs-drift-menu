-- Pestana: cambio de coche (lista de plazas libres leida del servidor).
local core = import('core')
local carFeat = import('features/car')
local T = import('ui/theme')
local C, smallText, sectionTitle, styledButton = T.C, T.smallText, T.sectionTitle, T.styledButton

local cars = carFeat.data

return function()
  local state = core.state

  sectionTitle('Coche', C.accentHi)

  if cars.status == 'loading' and #cars.list == 0 then
    smallText('Consultando coches disponibles...')
    return
  elseif cars.status == 'error' and #cars.list == 0 then
    smallText('No se pudo consultar el servidor.')
    ui.dummy(vec2(0, 4))
    if styledButton('REINTENTAR', vec2(-0.1, 32), true) then carFeat.refresh() end
    return
  elseif #cars.list == 0 then
    smallText('El servidor no tiene coches configurados en el entry list.')
    return
  end

  -- Si la seleccion previa ya no existe en la lista (cambio de preset, etc.), se olvida.
  local selected
  for _, c in ipairs(cars.list) do
    if c.id == state.carID then selected = c break end
  end
  if not selected then state.carID = nil end

  ui.pushStyleColor(ui.StyleColor.ChildBg, rgbm(0, 0, 0, 0.18))
  ui.pushStyleVar(ui.StyleVar.ChildRounding, 9)
  ui.childWindow('acs_car_list', vec2(-0.1, 220), false, function()
    for _, c in ipairs(cars.list) do
      local label = string.format('%s  (%d/%d libres)##car_%s', c.name, c.free, c.total, c.id)
      if styledButton(label, vec2(-0.1, 32), state.carID == c.id) then
        state.carID = c.id
      end
    end
  end)
  ui.popStyleVar(1)
  ui.popStyleColor(1)

  ui.dummy(vec2(0, 6))
  if styledButton('Recargar lista', vec2(-0.1, 26), false) then carFeat.refresh() end
  ui.dummy(vec2(0, 8))

  local canApply = selected ~= nil and selected.free > 0
  if styledButton('APLICAR  (reconecta)', vec2(-0.1, 38), true, not canApply) then
    carFeat.changeCar(state.carID)
  end
  if selected and selected.free <= 0 then
    smallText('Ese coche no tiene plazas libres ahora mismo.')
  elseif not selected then
    smallText('Elige un coche de la lista.')
  end
end
