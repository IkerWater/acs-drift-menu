-- Pestana: layouts de DriftZonesEditor publicados por el servidor.
local layoutsFeature = import('features/layouts')
local mapvote = import('features/mapvote')
local core = import('core')
local T = import('ui/theme')
local I18N = import('i18n')
local C, smallText, sectionTitle, styledButton = T.C, T.smallText, T.sectionTitle, T.styledButton
local state = layoutsFeature.data

return function()
  local hasDownloadPath = layoutsFeature.normalizeDownloadDirectory(
      core.state.settings.layoutDownloadPath) ~= nil
  local current = mapvote.data.status and mapvote.data.status.current
  if current then
    sectionTitle(I18N.get('layouts.title', current.name or current.track), C.accentHi)
  else
    sectionTitle(I18N.get('tab.layouts'), C.accentHi)
    if not hasDownloadPath then
      smallText(I18N.get('layouts.path_required'), C.accentHi)
    end
    smallText(I18N.get('layouts.track_unavailable'))
    return
  end

  if not hasDownloadPath then
    smallText(I18N.get('layouts.path_required'), C.accentHi)
  end

  if state.status == 'loading' then
    smallText(I18N.get('layouts.loading'))
    return
  elseif state.status == 'error' then
    smallText(I18N.get('layouts.load_error_short'))
  elseif state.status == 'ok' and #state.layouts == 0 then
    smallText(I18N.get('layouts.empty'))
  end

  ui.pushStyleColor(ui.StyleColor.ChildBg, rgbm(0, 0, 0, 0.18))
  ui.pushStyleVar(ui.StyleVar.ChildRounding, 9)
  ui.childWindow('acs_layout_list', vec2(-0.1, 260), false, function()
    for _, layout in ipairs(state.layouts) do
      if styledButton(layout.name .. '##layout_' .. layout.name,
          vec2(-0.1, 32), state.selected == layout.name) then
        state.selected = layout.name
      end
    end
  end)
  ui.popStyleVar(1)
  ui.popStyleColor(1)

  ui.dummy(vec2(0, 8))
  if styledButton(I18N.get('layouts.download'),
      vec2(-0.1, 38), true, not state.selected or state.downloading) then
    layoutsFeature.download(state.selected)
  end
  if state.downloading then smallText(I18N.get('layouts.downloading')) end

  ui.dummy(vec2(0, 6))
  if styledButton(I18N.get('layouts.reload'), vec2(-0.1, 26), false) then
    layoutsFeature.refresh(current.track)
  end
end
