-- Pestana: skins locales.
local skin = import('features/skin')
local T = import('ui/theme')
local I18N = import('i18n')
local C, smallText, sectionTitle, styledButton = T.C, T.smallText, T.sectionTitle, T.styledButton

return function()
  local skinState = skin.state

  sectionTitle(I18N.get('skin.title'), C.accentHi)
  smallText(I18N.get('skin.local_only'))

  local carID = ac.getCarID(0)

  -- Actualizar la lista cuando cambia el coche.
  if skinState.carID ~= carID then
    skin.refresh()
  end

  smallText(I18N.get('skin.car', tostring(carID)), C.text)
  ui.dummy(vec2(0, 4))

  -- Sin skins: aviso y boton de recarga
  if #skinState.skins == 0 then
    smallText(I18N.get('skin.not_found'))
    smallText(I18N.get('skin.check_path'))
    ui.dummy(vec2(0, 8))
    if styledButton(I18N.get('skin.reload'), vec2(-0.1, 34), true) then
      skin.refresh()
    end
    return
  end

  smallText(I18N.get('skin.count', #skinState.skins))
  ui.dummy(vec2(0, 4))

  if styledButton(I18N.get('skin.reload_list'), vec2(-0.1, 28), false) then
    skin.refresh()
  end

  ui.dummy(vec2(0, 6))

  -- Lista con scroll para que no desborde la ventana si hay muchas skins
  ui.pushStyleColor(ui.StyleColor.ChildBg, rgbm(0, 0, 0, 0.18))
  ui.pushStyleVar(ui.StyleVar.ChildRounding, 9)
  ui.childWindow('acs_skin_list', vec2(-0.1, 200), false, function()
    for i, s in ipairs(skinState.skins) do
      local buttonPos = ui.getCursor()
      local label = '       ' .. s.label .. '##skin_' .. s.id
      if styledButton(label, vec2(-0.1, 48), skinState.selected == i) then
        skinState.selected = i
      end
      local previewMin = buttonPos + vec2(5, 2)
      local previewMax = buttonPos + vec2(63, 46)
      ui.drawImage(s.preview or 'color::30303A', previewMin, previewMax,
          rgbm.colors.white, vec2(0.08, 0.08), vec2(0.92, 0.92), ui.ImageFit.Fit)
    end
  end)
  ui.popStyleVar(1)
  ui.popStyleColor(1)

  ui.dummy(vec2(0, 8))

  if styledButton(I18N.get('skin.apply'), vec2(-0.1, 38), true) then
    local selected = skinState.skins[skinState.selected]
    if selected then
      skin.apply(selected)
    end
  end

  if skinState.message ~= '' then
    ui.dummy(vec2(0, 6))
    ui.pushFont(ui.Font.Small)
    ui.textWrapped(skinState.message)
    ui.popFont()
  end
end
