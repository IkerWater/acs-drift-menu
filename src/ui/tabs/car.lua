-- Pestana: cambio de coche (lista de plazas libres leida del servidor).
-- Misma estructura que la de skins: textos, recargar, lista con imagen y aplicar.
local core = import('core')
local carFeat = import('features/car')
local T = import('ui/theme')
local I18N = import('i18n')
local C, smallText, sectionTitle, styledButton = T.C, T.smallText, T.sectionTitle, T.styledButton

local cars = carFeat.data

return function()
  local state = core.state

  sectionTitle(I18N.get('car.title'), C.accentHi)
  smallText(I18N.get('car.reconnect_note'))
  smallText(I18N.get('car.current', tostring(ac.getCarID(0))), C.text)
  ui.dummy(vec2(0, 4))

  -- Sin lista: aviso y boton de recarga (como "sin skins")
  if cars.status == 'error' then
    smallText(I18N.get('plugin.connection_warning'))
    ui.dummy(vec2(0, 8))
    if styledButton(I18N.get('plugin.retry'), vec2(-0.1, 34), true) then carFeat.refresh() end
    return
  elseif cars.status == 'loading' and #cars.list == 0 then
    smallText(I18N.get('car.loading'))
    return
  elseif #cars.list == 0 then
    smallText(I18N.get('car.empty'))
    ui.dummy(vec2(0, 8))
    if styledButton(I18N.get('car.reload'), vec2(-0.1, 34), true) then carFeat.refresh() end
    return
  end

  -- Si la seleccion previa ya no existe en la lista (cambio de preset, etc.), se olvida.
  local selected
  for _, c in ipairs(cars.list) do
    if c.id == state.carID then selected = c break end
  end
  if not selected then state.carID = nil end

  smallText(I18N.get('car.count', #cars.list))
  ui.dummy(vec2(0, 4))

  if styledButton(I18N.get('car.reload'), vec2(-0.1, 28), false) then
    carFeat.refresh()
  end

  ui.dummy(vec2(0, 6))

  -- Lista con scroll para que no desborde la ventana si hay muchos coches
  ui.pushStyleColor(ui.StyleColor.ChildBg, rgbm(0, 0, 0, 0.18))
  ui.pushStyleVar(ui.StyleVar.ChildRounding, 9)
  local listHeight = math.max(120, ui.availableSpaceY() - 62)
  ui.childWindow('acs_car_list', vec2(-0.1, listHeight), false, function()
    for _, c in ipairs(cars.list) do
      local buttonPos = ui.getCursor()
      local label = '          ' .. I18N.get('car.free', c.name, c.free, c.total, c.id)
      if styledButton(label, vec2(-0.1, 48), state.carID == c.id) then
        state.carID = c.id
      end
      local preview, isBadge = carFeat.preview(c.id)
      local previewMin = buttonPos + vec2(4, 1)
      local previewMax = buttonPos + vec2(72, 47)
      if isBadge then
        -- El badge es un logo: entero y con margen.
        ui.drawImage(preview, previewMin + vec2(14, 4), previewMax - vec2(14, 4),
            rgbm.colors.white, vec2(0, 0), vec2(1, 1), ui.ImageFit.Fit)
      else
        ui.drawImage(preview or 'color::30303A', previewMin, previewMax,
            rgbm.colors.white, vec2(0.18, 0.18), vec2(0.82, 0.82), ui.ImageFit.Fit)
      end
    end
  end)
  ui.popStyleVar(1)
  ui.popStyleColor(1)

  ui.dummy(vec2(0, 8))

  local canApply = selected ~= nil and selected.free > 0
  if styledButton(I18N.get('car.apply'), vec2(-0.1, 38), true, not canApply) then
    carFeat.changeCar(state.carID)
  end

  local hint
  if selected and selected.free <= 0 then
    hint = I18N.get('car.no_slots')
  elseif not selected then
    hint = I18N.get('car.choose')
  end
  if hint then
    ui.dummy(vec2(0, 6))
    ui.pushFont(ui.Font.Small)
    ui.textWrapped(hint)
    ui.popFont()
  end
end
