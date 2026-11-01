-- Ventana principal: cabecera, pestanas, barra de estado y pie.
-- Para anadir una pestana: crea ui/tabs/<nombre>.lua y anadela a TABS.
local core = import('core')
local admin = import('features/admin')
local T = import('ui/theme')
local I18N = import('i18n')
local C, accentLine, styledButton = T.C, T.accentLine, T.styledButton
T.applyBgAlpha(core.state.settings.bgAlpha)

-- visible es opcional; sin ella la pestana siempre se muestra.
local TABS = {
  { id = 'car',      label = 'tab.car',      height = 440, draw = import('ui/tabs/car')      },
  { id = 'skin',     label = 'tab.skin',     height = 580, draw = import('ui/tabs/skin')     },
  { id = 'track',    label = 'tab.track',    height = 800, draw = import('ui/tabs/track')    },
  { id = 'teleport', label = 'tab.teleport', height = 480, draw = import('ui/tabs/teleport') },
  { id = 'settings', label = 'tab.settings', height = 580, draw = import('ui/tabs/settings') },
  { id = 'admin',    label = 'tab.admin',    height = 260, draw = import('ui/tabs/admin'),
    visible = function() return admin.data.isAdmin end },
}

local M = {}

-- Solo las pestanas que tocan mostrarse ahora mismo (admin.data.isAdmin puede
-- cambiar en caliente: se recalcula cada vez, es barato con esta pocas pestanas).
local function visibleTabs()
  local out = {}
  for _, t in ipairs(TABS) do
    if not t.visible or t.visible() then out[#out + 1] = t end
  end
  return out
end

local MAX_WIN_H    = 900
local MIN_WIN_H    = 560
local MIN_W        = 420   -- ancho minimo aunque todo quepa en menos
local PAD_X        = 16    -- WindowPadding horizontal (a cada lado)
local BTN_PAD      = 28    -- margen interior extra de cada boton respecto a su texto
local GAP_TABS     = 6
local GAP_SWATCH   = 5

local function footerText()
  return I18N.get('menu.footer', genDate)
end
local function requiredHeight(tabs)
  local h = MIN_WIN_H
  for _, tab in ipairs(tabs) do
    local tabHeight = type(tab.height) == 'function' and tab.height(tab) or tab.height
    h = math.max(h, tabHeight)
  end
  local state = core.state
  if state.message ~= '' and os.clock() - state.messageTime < 6 then h = h + 62 end
  return math.min(MAX_WIN_H, h)
end

-- Ancho que necesita el contenido: el mayor entre la barra de pestanas, el pie
-- y la fila de colores de acento (las tres son las partes que no pueden partirse).
-- Se cachea por la combinacion de pestanas visibles: la de Admin aparece/desaparece
-- en caliente y cambia cuanto ocupa la barra.
local cachedWidth, cachedWidthKey
local function tabsKey(tabs)
  local parts = { core.state.settings.language }
  for _, t in ipairs(tabs) do parts[#parts + 1] = t.id end
  return table.concat(parts, ',')
end

local function requiredWidth(tabs)
  local key = tabsKey(tabs)
  if cachedWidth and cachedWidthKey == key then return cachedWidth end

  ui.pushFont(ui.Font.Title)
  local widestTabLabel = 0
  for _, t in ipairs(tabs) do
    widestTabLabel = math.max(widestTabLabel, T.textWidth(I18N.get(t.label)))
  end
  ui.popFont()
  local tabsW = #tabs * (widestTabLabel + BTN_PAD) + (#tabs - 1) * GAP_TABS

  local maxAccent = 0
  for _, a in ipairs(T.ACCENTS) do
    maxAccent = math.max(maxAccent, T.textWidth('> ' .. I18N.get(a.name)))
  end
  local accentW = #T.ACCENTS * (maxAccent + BTN_PAD) + (#T.ACCENTS - 1) * GAP_SWATCH

  local footerW = T.textWidth(footerText()) + 16

  cachedWidth = math.ceil(math.max(MIN_W, tabsW, accentW, footerW) + PAD_X * 2)
  cachedWidthKey = key
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

local function drawTabBar(tabs)
  -- Si la pestana activa dejo de estar visible (p.ej. Admin al perder el admin), cae a la primera.
  local stillThere = false
  for _, t in ipairs(tabs) do
    if t.id == core.state.tab then stillThere = true break end
  end
  if not stillThere and tabs[1] then core.state.tab = tabs[1].id end

  ui.pushFont(ui.Font.Title)
  local tabCount = #tabs
  local buttonWidth = (ui.availableSpaceX() - (tabCount - 1) * GAP_TABS) / tabCount
  for i, t in ipairs(tabs) do
    if i > 1 then ui.sameLine(0, GAP_TABS) end
    if styledButton(I18N.get(t.label), vec2(buttonWidth, 34), core.state.tab == t.id) then
      core.state.tab = t.id
    end
  end
  ui.popFont()
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

--Si el fondo sale descolocado o doble, pon OWN_BG = false para volver al comportamiento anterior.
local OWN_BG = true

local function drawBackground()
  ui.drawRectFilled(vec2(0, 0), ui.windowSize(), C.bg, 16)
end

local function drawMenu()
  local tabs = visibleTabs()
  if OWN_BG then drawBackground() end
  header()
  drawTabBar(tabs)
  for _, tab in ipairs(tabs) do
    if core.state.tab == tab.id then
      tab.draw()
      break
    end
  end
  drawStatus()
  ui.dummy(vec2(0, math.max(0, ui.availableSpaceY() - 64)))
  ui.newLine()
  ui.textAligned(footerText(), vec2(0.5, 0.5), vec2(ui.availableSpaceX(), 32))
end

function M.drawWindow()
  local s = core.state.settings
  local tabs = visibleTabs()
  local w = requiredWidth(tabs)
  local h = requiredHeight(tabs)
  local sw, sh = screenSize()
  -- % del espacio libre: 0% pega la ventana al borde, 100% al borde opuesto (nunca se sale).
  local x = (s.posX / 100) * math.max(0, sw - w)
  local y = (s.posY / 100) * math.max(0, sh - h)
  ui.pushStyleColor(ui.StyleColor.WindowBg, OWN_BG and rgbm(0, 0, 0, 0) or C.bg)
  ui.pushStyleColor(ui.StyleColor.Border, C.accent)
  ui.pushStyleVar(ui.StyleVar.WindowRounding, 16)
  ui.pushStyleVar(ui.StyleVar.WindowPadding, vec2(16, 12))
  ui.toolWindow('acs_menu/main', vec2(x, y), vec2(w, h), false, true, drawMenu)
  ui.popStyleVar(2)
  ui.popStyleColor(2)
end

return M
