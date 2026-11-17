-- Indicador "REC mm:ss" mientras se graba una pasada (se ve aunque el menu este cerrado).
local ghost = import('features/ghost')
local T = import('ui/theme')
local I18N = import('i18n')
local C = T.C

local M = {}

local function screenSize()
  local ok, info = pcall(ac.getUI)
  if ok and info and info.windowSize and info.windowSize.x > 0 then
    return info.windowSize.x, info.windowSize.y
  end
  return 1920, 1080
end

function M.draw()
  if not ghost.data.recording then return end

  local screenWidth = screenSize()
  local width, height = 180, 44
  -- centrado arriba, donde no estorba al cuentakilometros
  local position = vec2(math.max(0, (screenWidth - width) / 2), 16)

  ui.pushStyleColor(ui.StyleColor.WindowBg, C.bg)
  ui.pushStyleColor(ui.StyleColor.Border, rgbm(1, 0.25, 0.25, 0.9))
  ui.pushStyleVar(ui.StyleVar.WindowRounding, 12)
  ui.pushStyleVar(ui.StyleVar.WindowPadding, vec2(12, 8))
  ui.toolWindow('acs_menu/ghost_rec', position, vec2(width, height), false, true, function()
    ui.pushStyleColor(ui.StyleColor.Text, rgbm(1, 0.35, 0.35, 1))
    ui.pushFont(ui.Font.Title)
    ui.text(I18N.get('ghost.hud_rec', ghost.formatTime(ghost.recSeconds())))
    ui.popFont()
    ui.popStyleColor(1)
  end)
  ui.popStyleVar(2)
  ui.popStyleColor(2)
end

return M
