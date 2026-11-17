-- Ventana para confirmar una grabacion recien terminada: guardarla en el servidor o descartarla.
-- Se ve aunque el menu este cerrado (la grabacion se puede parar con la tecla).
local ghost = import('features/ghost')
local T = import('ui/theme')
local I18N = import('i18n')
local C, smallText, sectionTitle, styledButton = T.C, T.smallText, T.sectionTitle, T.styledButton

local M = {}

local function screenSize()
  local ok, info = pcall(ac.getUI)
  if ok and info and info.windowSize and info.windowSize.x > 0 then
    return info.windowSize.x, info.windowSize.y
  end
  return 1920, 1080
end

function M.draw()
  local pending = ghost.data.pending
  if not pending then return end

  local screenWidth, screenHeight = screenSize()
  local width, height = 360, 150
  local position = vec2(math.max(0, (screenWidth - width) / 2), math.max(0, (screenHeight - height) / 2))

  ui.pushStyleColor(ui.StyleColor.WindowBg, C.bg)
  ui.pushStyleColor(ui.StyleColor.Border, C.accent)
  ui.pushStyleVar(ui.StyleVar.WindowRounding, 12)
  ui.pushStyleVar(ui.StyleVar.WindowPadding, vec2(14, 10))
  ui.toolWindow('acs_menu/ghost_confirm', position, vec2(width, height), false, true, function()
    sectionTitle(I18N.get('ghost.confirm_title'), C.accentHi)
    smallText(I18N.get('ghost.confirm_text', ghost.formatTime(pending.seconds)), C.text)
    ui.dummy(vec2(0, 6))

    local w = (ui.availableSpaceX() - 6) / 2
    if styledButton(I18N.get('ghost.confirm_save') .. '##ghost_confirm_save', vec2(w, 36), true) then
      ghost.savePending()
    end
    ui.sameLine(0, 6)
    if styledButton(I18N.get('ghost.confirm_discard') .. '##ghost_confirm_discard', vec2(w, 36), false) then
      ghost.discardPending()
    end
  end)
  ui.popStyleVar(2)
  ui.popStyleColor(2)
end

return M
