-- Ventana principal: cabecera, barra lateral de pestanas, barra de estado y pie.
-- Para anadir una pestana: crea ui/tabs/<nombre>.lua y anadela a TABS
-- (icon = nombres de ui.Icons a probar en orden; si no hay ninguno se dibuja la inicial).
local core = import('core')
local CONFIG = import('config')
local admin = import('features/admin')
local T = import('ui/theme')
local I18N = import('i18n')
local C, accentLine, styledButton = T.C, T.accentLine, T.styledButton
T.applyBgAlpha(core.state.settings.bgAlpha)
T.applyAccent(core.state.settings.accentIndex)

-- visible es opcional; sin ella la pestana siempre se muestra.
-- bottom = true la ancla abajo del todo de la barra lateral.
local TABS = {
  { id = 'car',      label = 'tab.car',      height = 500, draw = import('ui/tabs/car'),
    icon = { 'Car', 'Steering', 'SteeringWheel', 'Wrench' } },
  { id = 'skin',     label = 'tab.skin',     height = 640, draw = import('ui/tabs/skin'),
    icon = { 'Palette', 'Paintbrush', 'Brush', 'Paint' } },
  { id = 'track',    label = 'tab.track',    height = 860, draw = import('ui/tabs/track'),
    icon = { 'Map', 'Earth', 'Globe', 'Road' } },
  { id = 'layouts',  label = 'tab.layouts',  height = 640, draw = import('ui/tabs/layouts'),
    icon = { 'Layers', 'Grid', 'List', 'Folder' } },
  { id = 'teleport', label = 'tab.teleport', height = 540, draw = import('ui/tabs/teleport'),
    icon = { 'Crosshair', 'Target', 'Pin', 'Location' } },
  { id = 'admin',    label = 'tab.admin',    height = 680, draw = import('ui/tabs/admin'),
    icon = { 'Shield', 'Key', 'Lock', 'Hammer' },
    visible = function()
      return admin.data.isAdmin or admin.data.pluginConnection == 'unavailable'
    end },
  -- Solo administradores (el servidor rechaza las acciones del resto)
  { id = 'ghost',    label = 'tab.ghost',    height = 700, draw = import('ui/tabs/ghost'),
    icon = { 'Ghost', 'Person', 'User', 'Video' },
    visible = function()
      return admin.data.isAdmin
    end },
  { id = 'settings', label = 'tab.settings', height = 720, draw = import('ui/tabs/settings'),
    icon = { 'Settings', 'Gear', 'Cog' }, bottom = true },
}

local M = {}
local dragging = false

-- Solo las pestanas que tocan mostrarse ahora mismo (admin.data.isAdmin puede
-- cambiar en caliente: se recalcula cada vez, es barato con esta pocas pestanas).
local function visibleTabs()
  local out = {}
  for _, t in ipairs(TABS) do
    if not t.visible or t.visible() then out[#out + 1] = t end
  end
  return out
end

local MAX_WIN_H    = 960
local MIN_WIN_H    = 560
local MIN_W        = 420   -- ancho minimo aunque todo quepa en menos
local WIDTH_EXTRA  = 80    -- holgura extra de ancho para la columna principal
local PAD_X        = 16    -- margen derecho de la columna principal
local PAD_Y        = 12    -- margen superior/inferior de la columna principal
local WINDOW_PADDING = vec2(16, 12) -- padding de las ventanas hijas con borde (como antes)
local BTN_PAD      = 28    -- margen interior extra de cada boton respecto a su texto
local GAP_SWATCH   = 5
local SIDEBAR_W       = 46  -- ancho de la barra lateral colapsada (solo iconos)
local SIDEBAR_GAP     = 10  -- separacion entre la barra y el contenido
local SIDEBAR_BTN_H   = 36
local SIDEBAR_BTN_GAP = 6
local SIDEBAR_PAD     = 4   -- margen interior horizontal de la barra
local SIDEBAR_PAD_Y   = 14  -- margen arriba/abajo (libra las esquinas redondeadas de la ventana)
local ICON_SIZE       = 18
local STATUS_HEIGHT = 54
local FOOTER_HEIGHT = 38
local CONTENT_BOTTOM_MARGIN = 20

local function footerText()
  return I18N.get('menu.footer', core.state.settings.toggleKeyName)
end
local function requiredHeight(tabs)
  local h = MIN_WIN_H
  for _, tab in ipairs(tabs) do
    local tabHeight = type(tab.height) == 'function' and tab.height(tab) or tab.height
    h = math.max(h, tabHeight)
  end
  return math.min(MAX_WIN_H, h)
end

-- Ancho de la ventana: barra lateral colapsada + el mayor entre el minimo, la fila
-- de colores de acento y el pie (las partes que no pueden partirse) + holgura.
-- Tambien calcula el ancho de la barra desplegada (icono + etiqueta mas larga).
-- Se cachea por idioma, tecla y pestanas visibles (Admin/Ghost aparecen en caliente).
local cachedWidth, cachedWidthKey
local sidebarExpandedW = SIDEBAR_W
local function tabsKey(tabs)
  local parts = {
    core.state.settings.language,
    core.state.settings.toggleKeyName,
  }
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
  sidebarExpandedW = math.ceil(SIDEBAR_W + widestTabLabel + 18)

  local maxAccent = 0
  for _, a in ipairs(T.ACCENTS) do
    maxAccent = math.max(maxAccent, T.textWidth('> ' .. I18N.get(a.name)))
  end
  local accentW = #T.ACCENTS * (maxAccent + BTN_PAD) + (#T.ACCENTS - 1) * GAP_SWATCH

  local footerW = T.textWidth(footerText()) + 16
  local mainW = math.max(MIN_W, accentW, footerW) + WIDTH_EXTRA

  cachedWidth = math.ceil(SIDEBAR_W + SIDEBAR_GAP + mainW + PAD_X)
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
  local titleWidth, versionWidth, gap, rowHeight = 164, 42, 4, 42
  local leftSpace = math.max(0, (ui.availableSpaceX() - titleWidth) / 2)
  ui.indent(leftSpace)
  ui.dwriteTextAligned('ACS DRIFT', 35, ui.Alignment.Start, ui.Alignment.Center,
      vec2(titleWidth, rowHeight), false, C.text)
  ui.sameLine(0, gap)
  ui.dwriteTextAligned(CONFIG.version, 16, ui.Alignment.Start, ui.Alignment.End,
      vec2(versionWidth, rowHeight), false, C.accentHi)
  ui.unindent(leftSpace)
  ui.dummy(vec2(0, 6))
  accentLine()
end

-- Barra lateral: ocupa todo el alto de la ventana y al pasar el raton se despliega
-- por encima de cabecera, contenido y pie.
local sidebarHover = false

local function ensureActiveTab(tabs)
  -- Si la pestana activa dejo de estar visible (p.ej. Admin al perder el admin), cae a la primera.
  for _, t in ipairs(tabs) do
    if t.id == core.state.tab then return end
  end
  if tabs[1] then core.state.tab = tabs[1].id end
end

local function textHeight(text)
  local ok, size = pcall(ui.measureText, text)
  if ok and size and size.y then return size.y end
  return 16
end

-- Boton de la barra: fondo con styledButton y encima icono (columna fija) + etiqueta si esta desplegada.
local function sidebarButton(id, width, selected, drawIcon, label)
  local p = ui.getCursor()
  local pressed = styledButton('##sidebar_' .. id, vec2(width, SIDEBAR_BTN_H), selected)
  local iconCenter = p + vec2((SIDEBAR_W - SIDEBAR_PAD * 2) / 2, SIDEBAR_BTN_H / 2)
  drawIcon(iconCenter)
  if label then
    ui.pushFont(ui.Font.Title)
    local textPos = p + vec2(SIDEBAR_W - SIDEBAR_PAD, (SIDEBAR_BTN_H - textHeight(label)) / 2)
    ui.drawText(label, textPos, C.text)
    ui.popFont()
  end
  return pressed
end

local function tabIconDrawer(t)
  return function(center)
    if T.icon(t.icon or {}, center, ICON_SIZE, C.text) then return end
    -- Fallback: inicial de la etiqueta.
    local initial = string.upper(string.sub(I18N.get(t.label), 1, 1))
    ui.pushFont(ui.Font.Title)
    local w, h = T.textWidth(initial), textHeight(initial)
    ui.drawText(initial, center - vec2(w / 2, h / 2), C.text)
    ui.popFont()
  end
end

local function drawSidebar(tabs, width, height, expanded)
  local btnW = width - SIDEBAR_PAD * 2
  local function place(y) ui.setCursor(vec2(SIDEBAR_PAD, y)) end
  local function select(t) core.state.tab = t.id end

  local y = SIDEBAR_PAD_Y
  local bottom = {}
  for _, t in ipairs(tabs) do
    if t.bottom then
      bottom[#bottom + 1] = t
    else
      place(y)
      if sidebarButton(t.id, btnW, core.state.tab == t.id, tabIconDrawer(t),
          expanded and I18N.get(t.label) or nil) then
        select(t)
      end
      y = y + SIDEBAR_BTN_H + SIDEBAR_BTN_GAP
    end
  end

  -- Las pestanas 'bottom' (Ajustes) se apilan desde abajo del todo.
  local by = height - SIDEBAR_PAD_Y - #bottom * SIDEBAR_BTN_H - (#bottom - 1) * SIDEBAR_BTN_GAP
  for _, t in ipairs(bottom) do
    place(math.max(y, by))
    if sidebarButton(t.id, btnW, core.state.tab == t.id, tabIconDrawer(t),
        expanded and I18N.get(t.label) or nil) then
      select(t)
    end
    by = by + SIDEBAR_BTN_H + SIDEBAR_BTN_GAP
  end

  if expanded then
    -- Linea de acento en el borde derecho para separarla del contenido que tapa.
    ui.drawRectFilled(vec2(width - 2, 16), vec2(width, height - 16), C.accent, 1)
  end
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
  else
    ui.dummy(vec2(0, STATUS_HEIGHT))
  end
end

--Si el fondo sale descolocado o doble, pon OWN_BG = false para volver al comportamiento anterior.
local OWN_BG = true

local function drawBackground()
  ui.drawRectFilled(vec2(0, 0), ui.windowSize(), C.bg, 16)
end

local NO_SCROLL = bit.bor(ui.WindowFlags.NoScrollbar, ui.WindowFlags.NoScrollWithMouse)

-- Columna principal (a la derecha de la barra colapsada): cabecera, contenido, estado y pie.
local function drawMainColumn(activeTab)
  header()
  local reservedHeight = FOOTER_HEIGHT + STATUS_HEIGHT
  local contentHeight = math.max(1,
      ui.availableSpaceY() - reservedHeight - CONTENT_BOTTOM_MARGIN)
  ui.childWindow('acs_menu_tab_content', vec2(-0.1, contentHeight), false, function()
    if activeTab then activeTab.draw() end
  end)

  drawStatus()
  ui.dummy(vec2(0, 6))
  ui.pushStyleColor(ui.StyleColor.Text, C.accentHi)
  ui.textAligned(footerText(), vec2(0.5, 0.5), vec2(ui.availableSpaceX(), 32))
  ui.popStyleColor(1)
end

local function drawMenu()
  local tabs = visibleTabs()
  if OWN_BG then drawBackground() end
  ensureActiveTab(tabs)
  local activeTab
  for _, tab in ipairs(tabs) do
    if core.state.tab == tab.id then
      activeTab = tab
      break
    end
  end

  local winSize = ui.windowSize()

  -- Hover con el ancho actual (desplegada si ya lo estaba) para no parpadear en el borde.
  local currentW = sidebarHover and sidebarExpandedW or SIDEBAR_W
  local origin = ui.windowPos()
  local mouse = ui.mousePos()
  sidebarHover = mouse.x >= origin.x and mouse.x <= origin.x + currentW
      and mouse.y >= origin.y and mouse.y <= origin.y + winSize.y
  local sidebarW = sidebarHover and sidebarExpandedW or SIDEBAR_W

  -- La ventana va sin padding (para que la barra llegue al borde); las hijas con borde
  -- de las pestanas siguen usando el padding de siempre.
  ui.pushStyleVar(ui.StyleVar.WindowPadding, WINDOW_PADDING)
  ui.pushStyleColor(ui.StyleColor.ChildBg, rgbm(0, 0, 0, 0))

  -- Columna principal primero...
  local mainX = SIDEBAR_W + SIDEBAR_GAP
  ui.setCursor(vec2(mainX, PAD_Y))
  ui.childWindow('acs_menu_main', vec2(winSize.x - mainX - PAD_X, winSize.y - PAD_Y * 2),
      false, NO_SCROLL, function() drawMainColumn(activeTab) end)
  ui.popStyleColor(1)

  -- ...y la barra despues, para que al desplegarse quede por encima y reciba el raton.
  ui.setCursor(vec2(0, 0))
  ui.pushStyleColor(ui.StyleColor.ChildBg, rgbm(0.070, 0.070, 0.105, 1.0))
  ui.pushStyleVar(ui.StyleVar.ChildRounding, 16)
  ui.childWindow('acs_menu_sidebar', vec2(sidebarW, winSize.y), false, NO_SCROLL, function()
    drawSidebar(tabs, sidebarW, winSize.y, sidebarHover)
  end)
  ui.popStyleVar(2)
  ui.popStyleColor(1)
end

function M.drawWindow()
  local s = core.state.settings
  local tabs = visibleTabs()
  local w = requiredWidth(tabs)
  local sw, sh = screenSize()
  local h = math.min(requiredHeight(tabs) + 40, math.max(320, sh - 24))
  -- % del espacio libre: 0% pega la ventana al borde, 100% al borde opuesto (nunca se sale).
  local maxX, maxY = math.max(0, sw - w), math.max(0, sh - h)
  local x = s.posX * maxX
  local y = s.posY * maxY

  local mouse = ui.mousePos()
  -- La cabecera empieza a la derecha de la barra lateral (y no cuenta si la barra esta desplegada).
  local overHeader = not sidebarHover
      and mouse.x >= x + SIDEBAR_W and mouse.x <= x + w
      and mouse.y >= y + 12 and mouse.y <= y + 82
  if ui.mouseClicked(ui.MouseButton.Left) and overHeader then
    dragging = true
  end
  if dragging then
    if ui.mouseDown(ui.MouseButton.Left) then
      local delta = ui.mouseDelta()
      x = math.max(0, math.min(maxX, x + delta.x))
      y = math.max(0, math.min(maxY, y + delta.y))
      s.posX = maxX > 0 and x / maxX or 0
      s.posY = maxY > 0 and y / maxY or 0
      core.persistSettings()
    else
      dragging = false
    end
  end

  ui.pushStyleColor(ui.StyleColor.WindowBg, OWN_BG and rgbm(0, 0, 0, 0) or C.bg)
  ui.pushStyleColor(ui.StyleColor.Border, C.accent)
  ui.pushStyleVar(ui.StyleVar.WindowRounding, 16)
  ui.pushStyleVar(ui.StyleVar.WindowPadding, vec2(0, 0))
  ui.toolWindow('acs_menu/main', vec2(x, y), vec2(w, h), false, true, drawMenu)
  ui.popStyleVar(2)
  ui.popStyleColor(2)
end

return M
