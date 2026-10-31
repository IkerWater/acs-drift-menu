-- Ventana principal: cabecera, pestanas, barra de estado y pie.
-- Para anadir una pestana: crea ui/tabs/<nombre>.lua y anadela a TABS.
local core = import('core')
local T = import('ui/theme')
local C, accentLine, styledButton = T.C, T.accentLine, T.styledButton

local TABS = {
  { id = 'car',      label = 'Coche',    draw = import('ui/tabs/car')      },
  { id = 'skin',     label = 'Skin',     draw = import('ui/tabs/skin')     },
  { id = 'track',    label = 'Circuito', draw = import('ui/tabs/track')    },
  { id = 'time',     label = 'Hora',     draw = import('ui/tabs/time')     },
  { id = 'teleport', label = 'TP',       draw = import('ui/tabs/teleport') },
  { id = 'settings', label = 'Ajustes',  draw = import('ui/tabs/settings') },
}

local M = {}

local WIN_H        = 750   -- alto fijo de la ventana
local MIN_W        = 420   -- ancho minimo aunque todo quepa en menos
local PAD_X        = 16    -- WindowPadding horizontal (a cada lado)
local BTN_PAD      = 28    -- margen interior extra de cada boton respecto a su texto
local GAP_TABS     = 6
local GAP_SWATCH   = 5

local footerText = ' [M] para cerrar | ACS Drift by Water | ' .. genDate
local cachedWidth

-- Ancho que necesita el contenido: el mayor entre la barra de pestanas, el pie
-- y la fila de colores de acento (las tres son las partes que no pueden partirse).
local function requiredWidth()
  if cachedWidth then return cachedWidth end

  local tabsW = (#TABS - 1) * GAP_TABS
  for _, t in ipairs(TABS) do tabsW = tabsW + T.textWidth(t.label) + BTN_PAD end

  local maxAccent = 0
  for _, a in ipairs(T.ACCENTS) do
    maxAccent = math.max(maxAccent, T.textWidth('> ' .. a.name))
  end
  local accentW = #T.ACCENTS * (maxAccent + BTN_PAD) + (#T.ACCENTS - 1) * GAP_SWATCH

  local footerW = T.textWidth(footerText) + 16

  cachedWidth = math.ceil(math.max(MIN_W, tabsW, accentW, footerW) + PAD_X * 2)
  return cachedWidth
end

-- Tamano de la pantalla en pixeles (con valor por defecto si el SDK no lo da).
local function screenSize()
  local ok, info = pcall(ac.getUI)
  if ok and info and info.windowSize and info.windowSize.x > 0 then
    return info.windowSize.x, info.windowSize.y
  end
  return 1920, 1080
end

local function header()
  ui.dummy(vec2(0, 2))
  ui.dwriteTextAligned('ACS DRIFT', 35, ui.Alignment.Center, ui.Alignment.Center,
      vec2(ui.availableSpaceX(), 35), false, C.text)
  ui.dwriteTextAligned('by Water', 20, ui.Alignment.End, ui.Alignment.Center,
      vec2(ui.availableSpaceX(), 25), false, C.accentHi)
  ui.dummy(vec2(0, 6))
  accentLine()
end

local function drawTabBar()
  local w = (ui.availableSpaceX() - (#TABS - 1) * GAP_TABS) / #TABS
  for i, t in ipairs(TABS) do
    if i > 1 then ui.sameLine(0, GAP_TABS) end
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
  ui.dummy(vec2(0, ui.availableSpaceY() - 64))
  ui.newLine()
  ui.textAligned(footerText, vec2(0.5, 0.5), vec2(ui.availableSpaceX(), 32))
end

function M.drawWindow()
  local s = core.state.settings
  local w = requiredWidth()
  local sw, sh = screenSize()
  -- % del espacio libre: 0% pega la ventana al borde, 100% al borde opuesto (nunca se sale).
  local x = (s.posX / 100) * math.max(0, sw - w)
  local y = (s.posY / 100) * math.max(0, sh - WIN_H)
  ui.pushStyleColor(ui.StyleColor.WindowBg, C.bg)
  ui.pushStyleColor(ui.StyleColor.Border, C.accent)
  ui.pushStyleVar(ui.StyleVar.WindowRounding, 16)
  ui.pushStyleVar(ui.StyleVar.WindowPadding, vec2(16, 12))
  ui.toolWindow('acs_menu/main', vec2(x, y), vec2(w, WIN_H), false, true, drawMenu)
  ui.popStyleVar(2)
  ui.popStyleColor(2)
end

return M
