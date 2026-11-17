-- Pestana: fantasma (grabar una pasada, cargarla o quitarla y gestionar las guardadas).
local ghost = import('features/ghost')
local T = import('ui/theme')
local I18N = import('i18n')
local C, smallText, sectionTitle, styledButton = T.C, T.smallText, T.sectionTitle, T.styledButton

local data = ghost.data

return function()
  sectionTitle(I18N.get('tab.ghost'), C.accentHi)

  if data.statusError or data.listState == 'error' then
    smallText(I18N.get('plugin.connection_warning'))
    ui.dummy(vec2(0, 4))
    if styledButton(I18N.get('plugin.retry'), vec2(-0.1, 32), true) then ghost.retry() end
    return
  end

  -- Grabacion
  sectionTitle(I18N.get('ghost.record_title'), C.accentHi)
  if data.pending then
    -- Misma decision que la ventana de confirmacion (por si la cierra otro admin o se perdio el aviso)
    smallText(I18N.get('ghost.pending', ghost.formatTime(data.pending.seconds)), C.accentHi)
    ui.dummy(vec2(0, 4))
    local w = (ui.availableSpaceX() - 6) / 2
    if styledButton(I18N.get('ghost.confirm_save') .. '##tab_save', vec2(w, 36), true) then ghost.savePending() end
    ui.sameLine(0, 6)
    if styledButton(I18N.get('ghost.confirm_discard') .. '##tab_discard', vec2(w, 36), false) then ghost.discardPending() end
  elseif data.recording then
    smallText(I18N.get('ghost.recording', ghost.formatTime(ghost.recSeconds())), C.accentHi)
    ui.dummy(vec2(0, 4))
    local w = (ui.availableSpaceX() - 6) / 2
    if styledButton(I18N.get('ghost.stop'), vec2(w, 36), true) then ghost.stopRecording() end
    ui.sameLine(0, 6)
    if styledButton(I18N.get('ghost.cancel'), vec2(w, 36), false) then ghost.cancelRecording() end
  else
    smallText(I18N.get('ghost.record_hint'))
    ui.dummy(vec2(0, 4))
    if styledButton(I18N.get('ghost.start'), vec2(-0.1, 36), true) then ghost.startRecording() end
  end

  -- Tecla para grabar/parar con el menu cerrado
  sectionTitle(I18N.get('ghost.button_title'), C.accentHi)
  smallText(I18N.get('ghost.button_hint'))
  ui.dummy(vec2(0, 4))
  data.recButton:control(vec2(ui.availableSpaceX(), 30))
  ui.dummy(vec2(0, 2))
  if data.recButton:configured() then
    smallText(I18N.get('teleport.assigned', tostring(data.recButton:boundTo())), C.accentHi)
  else
    smallText(I18N.get('teleport.unassigned'))
  end

  -- Pasada cargada
  sectionTitle(I18N.get('ghost.active_title'), C.accentHi)
  local active = data.status and data.status.ghost
  if active then
    smallText(I18N.get('ghost.active', active.author, active.car, ghost.durationText(active.durationMs)))
    ui.dummy(vec2(0, 4))
    if styledButton(I18N.get('ghost.unload'), vec2(-0.1, 32), false) then ghost.unload() end
  else
    smallText(I18N.get('ghost.none'))
  end

  -- Pasadas guardadas en este circuito
  sectionTitle(I18N.get('ghost.saved_title'), C.accentHi)
  if data.listState == 'loading' and #data.list == 0 then
    smallText(I18N.get('common.loading'))
  elseif #data.list == 0 then
    smallText(I18N.get('ghost.empty'))
  else
    local loadedId = active and active.id or nil
    ui.pushStyleColor(ui.StyleColor.ChildBg, rgbm(0, 0, 0, 0.18))
    ui.pushStyleVar(ui.StyleVar.ChildRounding, 9)
    -- Ocupa el hueco que queda (como skins/coches), reservando sitio para los botones
    -- de cargar/borrar y recargar de debajo, asi la pestana no necesita scroll general.
    local listHeight = math.max(64, ui.availableSpaceY() - 100)
    ui.childWindow('acs_ghost_list', vec2(-0.1, listHeight), false, function()
      for _, g in ipairs(data.list) do
        local label = string.format('%s  ·  %s  ·  %s', g.author, g.car, ghost.durationText(g.durationMs))
        if g.id == loadedId then label = label .. '  (' .. I18N.get('ghost.loaded') .. ')' end
        if styledButton(label .. '##ghost_' .. g.id, vec2(-0.1, 30), data.selected == g.id) then
          data.selected = g.id
          data.confirmDelete = nil
        end
      end
    end)
    ui.popStyleVar(1)
    ui.popStyleColor(1)

    local selected
    for _, g in ipairs(data.list) do
      if g.id == data.selected then selected = g end
    end

    ui.dummy(vec2(0, 6))
    local w = (ui.availableSpaceX() - 6) / 2
    if styledButton(I18N.get('ghost.load'), vec2(w, 34), true,
        selected == nil or selected.id == loadedId) then
      ghost.load(selected.id)
    end
    ui.sameLine(0, 6)
    local confirming = selected ~= nil and data.confirmDelete == selected.id
    local deleteLabel = confirming and I18N.get('ghost.confirm_delete') or I18N.get('ghost.delete')
    if styledButton(deleteLabel .. '##ghost_delete', vec2(w, 34), confirming, selected == nil) then
      ghost.delete(selected.id)
    end
  end

  ui.dummy(vec2(0, 6))
  if styledButton(I18N.get('ghost.reload'), vec2(-0.1, 26), false) then ghost.refreshList() end
end
