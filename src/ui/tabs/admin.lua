-- Pestana: Admin (solo visible si esta conexion entro con /admin <contraseña>).
-- Incluye acciones de chat y cambio directo de preset validado por el servidor.
local T = import('ui/theme')
local I18N = import('i18n')
local admin = import('features/admin')
local C, sectionTitle, styledButton, smallText = T.C, T.sectionTitle, T.styledButton, T.smallText

-- [VERIFICAR] nombre de la funcion de CSP para enviar un mensaje de chat local (se asume ac.sendChatMessage).
local function sendChat(cmd)
  local ok = pcall(ac.sendChatMessage, cmd)
  if not ok then ac.log(I18N.get('admin.send_error', cmd)) end
end

return function()
  local data = admin.data
  sectionTitle(I18N.get('tab.admin'), C.accentHi)
  smallText(I18N.get('admin.description'))
  ui.dummy(vec2(0, 8))

  if styledButton(I18N.get('admin.cancel'), vec2(-0.1, 32)) then
    sendChat('/mapcancel')
  end
  if styledButton(I18N.get('admin.reload'), vec2(-0.1, 32)) then
    sendChat('/mapreload')
  end

  sectionTitle(I18N.get('admin.presets'), C.accentHi)
  smallText(I18N.get('admin.presets_description'))
  ui.dummy(vec2(0, 4))

  if data.presetsState == 'loading' then
    smallText(I18N.get('admin.presets_loading'))
  elseif data.presetsState == 'error' then
    smallText(I18N.get('admin.presets_load_error', data.presetsError or ''))
    if styledButton(I18N.get('common.retry'), vec2(-0.1, 30), true) then admin.loadPresets() end
  elseif #data.presets == 0 then
    smallText(I18N.get('admin.presets_empty'))
  else
    ui.pushStyleColor(ui.StyleColor.ChildBg, rgbm(0, 0, 0, 0.18))
    ui.pushStyleVar(ui.StyleVar.ChildRounding, 9)
    ui.childWindow('acs_admin_presets', vec2(-0.1, 190), false, function()
      for _, preset in ipairs(data.presets) do
        local label = preset.name
        if preset.current then
          label = label .. ' (' .. I18N.get('admin.preset_current') .. ')'
        end
        if styledButton(label .. '##preset_' .. preset.id, vec2(-0.1, 30),
            data.selectedPreset == preset.id, preset.current) then
          data.selectedPreset = preset.id
        end
      end
    end)
    ui.popStyleVar(1)
    ui.popStyleColor(1)

    ui.dummy(vec2(0, 6))
    if styledButton(I18N.get('admin.preset_apply'), vec2(-0.1, 36), true,
        data.selectedPreset == nil) then
      admin.changePreset(data.selectedPreset)
    end
  end
end
