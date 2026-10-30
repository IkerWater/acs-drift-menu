-- Ventana principal: cabecera, pestanas, barra de estado y pie.
-- Para anadir una pestana: crea ui/tabs/<nombre>.lua y anadela a TABS.
local core = import('core')
local T = import('ui/theme')
local C, bigText, smallText, accentLine, styledButton =
  T.C, T.bigText, T.smallText, T.accentLine, T.styledButton

local TABS = {
  { id = 'car',      label = 'Coche',    draw = import('ui/tabs/car') },
  { id = 'skin',     label = 'Skin',     draw = import('ui/tabs/skin') },
  { id = 'track',    label = 'Circuito', draw = import('ui/tabs/track') },
  { id = 'time',     label = 'Hora',     draw = import('ui/tabs/time') },
  { id = 'teleport', label = 'TP',       draw = import('ui/tabs/teleport') },
}

local M = {}

local function header()
  ui.dummy(vec2(0, 2))
  bigText('ACS DRIFT', 26, C.text)
  smallText('by Water', C.accentHi)
  ui.dummy(vec2(0, 6))
  accentLine()
end

local function drawTabBar()
  local w = (ui.availableSpaceX() - (#TABS - 1) * 6) / #TABS
  for i, t in ipairs(TABS) do
    if i > 1 then ui.sameLine(0, 6) end
    if styledButton(t.label, vec2(w, 30), core.state.tab == t.id) then core.state.tab = t.id end
  end
  ui.dummy(vec2(0, 6))
end

local function drawStatus()
  local state = core.state
  if state.message ~= '' and os.clock() - state.messageTime < 6 then
    ui.dummy(vec2(0, 8))
    ui.pushStyleColor(ui.StyleColor.ChildBg, C.surface)
    ui.pushStyleVar(ui.StyleVar.ChildRounding, 9)
    ui.childWindow('acs_status', vec2(-0.1, 46), false, function()
      ui.dummy(vec2(0, 2))
      ui.indent(8)
      ui.pushFont(ui.Font.Small)
      ui.textWrapped(state.message)
      ui.popFont()
    end)
    ui.popStyleVar(1)
    ui.popStyleColor(1)
  end
end

local function drawMenu()
  header()
  drawTabBar()
  for _, t in ipairs(TABS) do
    if core.state.tab == t.id then t.draw() break end
  end
  drawStatus()
  ui.dummy(vec2(0, ui.availableSpaceY() - 32))
  ui.newLine()
  ui.textAligned(' [M] para cerrar | ACS Drift by Water | ' .. genDate, vec2(0.5, 0.5), vec2(ui.availableSpaceX(), 32))
end

function M.drawWindow()
  ui.pushStyleColor(ui.StyleColor.WindowBg, C.bg)
  ui.pushStyleColor(ui.StyleColor.Border, C.accent)
  ui.pushStyleVar(ui.StyleVar.WindowRounding, 16)
  ui.pushStyleVar(ui.StyleVar.WindowPadding, vec2(16, 12))
  ui.toolWindow('acs_menu/main', vec2(200, 150), vec2(500, 720), false, true, drawMenu)
  ui.popStyleVar(2)
  ui.popStyleColor(2)
end

return M
