-- ACS Drift by Water - script ONLINE para CSP
-- GENERADO EL (2026-10-30 16:48).
-- Se carga desde el servidor via csp_extra_options.ini ([SCRIPT_1]). Tecla M: abrir/cerrar.

local __modules, __cache = {}, {}
local function import(name)
  local cached = __cache[name]
  if cached == nil then
    local loader = __modules[name]
    if not loader then error('modulo no encontrado: ' .. tostring(name)) end
    cached = loader()
    __cache[name] = cached == nil and true or cached
  end
  return cached
end

local genDate = '2026-10-30 16:48'

-- ===== modulo: config (src/config.lua) =====
__modules['config'] = function()
-- Configuracion editable del menu. Solo datos, sin logica.
return {
  toggleKey = ui.KeyIndex.M,

  -- Coches ofrecidos ('id' = carpeta del coche, 'skins' = carpetas de skin).
  -- Deben existir como entradas en el entry_list del servidor.
  cars = {
    { id = 'tunermnrcars_eskuko_missile_e36coupe',   name = 'Eskuko Missile E36 Coupe',   skins = { 'default', 'Titanio' } },
    { id = 'tunermnrcars_eskuko_missile_e36compact', name = 'Eskuko Missile E36 Compact', skins = { 'default', 'JulenArjona' } },
  },

  -- Datos del servidor para reconectar (cambio de coche/skin).
  server = { host = '', port = 9600, httpPort = 8081, password = '' },

  -- Comandos de chat del plugin MapVotePlugin (votacion de mapa independiente de los presets).
  commands = {
    mapStart = '/mapstart %d',
    mapYes   = '/mapyes',
    mapNo    = '/mapno',
  },
}
end

-- ===== modulo: core (src/core.lua) =====
__modules['core'] = function()
-- Estado compartido y utilidades basicas. No depende de ningun otro modulo.
local M = {}

M.state = {
  open = false,
  tab = 'car',            -- id de la pestana activa (ver ui/menu.lua)
  carIndex = 1, skinIndex = 1,
  hour = 12,
  message = '', messageTime = 0,
  savedPoint = nil,
}

function M.notify(text)
  M.state.message, M.state.messageTime = text, os.clock()
  ac.log('[ACS Menu] ' .. text)
end

-- Ejecuta fn protegida; si falla, avisa en el menu y devuelve false.
function M.safe(label, fn)
  local ok, err = pcall(fn)
  if not ok then M.notify(label .. ': no disponible (' .. tostring(err):sub(1, 70) .. ')') end
  return ok
end

function M.sendChatCommand(cmd)
  ac.sendChatMessage(cmd)
  M.notify('Enviado: ' .. cmd)
end

return M
end

-- ===== modulo: features/car (src/features/car.lua) =====
__modules['features/car'] = function()
-- Cambio de coche/skin por reconexion al servidor.
local CONFIG = import('config')
local core = import('core')

local M = {}

function M.changeCar(carIdx, skinIdx)
  local car = CONFIG.cars[carIdx]
  core.safe('Cambio de coche', function()
    -- [VERIFICAR] nombre y parametros exactos en tu SDK
    ac.reconnectTo({
      host = CONFIG.server.host, port = CONFIG.server.port,
      httpPort = CONFIG.server.httpPort, password = CONFIG.server.password,
      car = car.id, skin = car.skins[skinIdx],
    })
  end)
end

return M
end

-- ===== modulo: features/mapvote (src/features/mapvote.lua) =====
__modules['features/mapvote'] = function()
-- Votacion de mapa (servidor: MapVotePlugin).
-- La lista de mapas y el estado se leen por HTTP; las acciones van por chat.
local CONFIG = import('config')
local core = import('core')

local M = {}

-- Estado que lee la UI
local mapvote = {
  tracks = {}, tracksState = 'idle',   -- idle | loading | ok | error
  status = nil, statusError = nil,
  filter = '', selected = nil,
  pollTimer = 0, myVote = nil, myVoteFor = nil,
}
M.data = mapvote

local function serverBaseUrl()
  local host, port = CONFIG.server.host, CONFIG.server.httpPort
  if ac.getServerIP then
    local ok, v = pcall(ac.getServerIP)
    if ok and v and v ~= '' then host = v end
  end
  if ac.getServerHTTPPort then
    local ok, v = pcall(ac.getServerHTTPPort)
    if ok and v and v > 0 then port = v end
  end
  return string.format('http://%s:%d', host, port)
end

-- [VERIFICAR] firma de web.get y forma del callback (err, response) en tu version de CSP.
local function httpGetJson(path, callback)
  local ok, err = pcall(function()
    web.get(serverBaseUrl() .. path, function(e, response)
      if e or not response or response.status ~= 200 then
        return callback(nil, tostring(e or (response and response.status) or 'sin respuesta'))
      end
      local parsedOk, data = pcall(JSON.parse, response.body)
      if parsedOk and type(data) == 'table' then callback(data) else callback(nil, 'JSON invalido') end
    end)
  end)
  if not ok then callback(nil, tostring(err)) end
end

function M.loadTracks()
  mapvote.tracksState = 'loading'
  httpGetJson('/mapvote/tracks', function(data, err)
    if data then
      mapvote.tracks, mapvote.tracksState = data, 'ok'
    else
      mapvote.tracksState = 'error'
      core.notify('Lista de mapas: ' .. tostring(err))
    end
  end)
end

local function pollStatus()
  httpGetJson('/mapvote/status', function(data, err)
    mapvote.status, mapvote.statusError = data, err
    if data and not data.active then mapvote.myVote, mapvote.myVoteFor = nil, nil end
  end)
end

-- active = true cuando la pestana de circuito esta visible (decide la UI, no este modulo).
function M.update(dt, active)
  if not active then return end
  if mapvote.tracksState == 'idle' then M.loadTracks() end
  mapvote.pollTimer = mapvote.pollTimer - dt
  if mapvote.pollTimer <= 0 then
    mapvote.pollTimer = 1.5
    pollStatus()
  end
end

function M.propose(entry)
  core.sendChatCommand(string.format(CONFIG.commands.mapStart, entry.id))
  mapvote.pollTimer = 0.4
end

function M.castVote(yes)
  core.sendChatCommand(yes and CONFIG.commands.mapYes or CONFIG.commands.mapNo)
  mapvote.myVote = yes
  mapvote.myVoteFor = mapvote.status and mapvote.status.proposal and mapvote.status.proposal.id or nil
  mapvote.pollTimer = 0.4
end

return M
end

-- ===== modulo: features/skin (src/features/skin.lua) =====
__modules['features/skin'] = function()
-- Skins locales: descubrimiento y aplicacion (solo cliente).
local M = {}

M.state = {
  carID = nil,
  skins = {},
  selected = 1,
  message = '',
}

local function loadLocalSkins(carID)
  local carsPath = ac.getFolder(ac.FolderID.ContentCars)
  local skinsPath = carsPath .. '/' .. carID .. '/skins'
  local skins = {}

  if not io.dirExists(skinsPath) then
    return skins
  end

  local dirs = io.scanDir(skinsPath, '*') or {}

  for _, name in ipairs(dirs) do
    local skinPath = skinsPath .. '/' .. name

    if io.dirExists(skinPath) then
      local label = name
      local skinJson = skinPath .. '/ui_skin.json'

      -- El nombre visible es opcional:
      -- si no existe ui_skin.json, usamos el nombre de carpeta.
      if io.fileExists(skinJson) then
        local ok, data = pcall(function()
          return JSON.parse(io.load(skinJson, ''))
        end)

        if ok and type(data) == 'table'
            and type(data.skinname) == 'string'
            and data.skinname ~= '' then
          label = data.skinname
        end
      end

      skins[#skins + 1] = { id = name, label = label }
    end
  end

  table.sort(skins, function(a, b)
    return a.label:lower() < b.label:lower()
  end)

  return skins
end

function M.refresh()
  local st = M.state
  local carID = ac.getCarID(0)

  st.carID = carID
  st.skins = loadLocalSkins(carID)
  st.selected = 1
  st.message = ''

  -- Seleccionar inicialmente la skin oficial del coche.
  local currentSkinID = ac.getCarSkinID(0)

  for i, skin in ipairs(st.skins) do
    if skin.id == currentSkinID then
      st.selected = i
      break
    end
  end
end

function M.apply(skin)
  local carID = ac.getCarID(0)
  local skinPath = ac.getFolder(ac.FolderID.ContentCars)
      .. '/' .. carID .. '/skins/' .. skin.id

  local ok, err = pcall(function()
    ac.findNodes('carRoot:0'):applySkin(skinPath)
  end)

  if ok then
    M.state.message = 'Skin aplicada localmente: ' .. skin.label
  else
    M.state.message = 'Error al aplicar skin: ' .. tostring(err)
  end
end

return M
end

-- ===== modulo: features/teleport (src/features/teleport.lua) =====
__modules['features/teleport'] = function()
-- Punto de reaparicion, TP a pits y boton configurable de retorno.
local core = import('core')

local M = {}

-- Boton configurable para volver al punto guardado (se asigna en la pestana TP).
-- El id debe ser unico; CSP guarda la asignacion por id.
M.returnButton = ac.ControlButton('__ACS_DRIFT_RETURN')

function M.savePoint()
  local car = ac.getCar(0)
  core.state.savedPoint = { pos = car.position:clone(), dir = car.look:clone() }
  core.notify('Punto guardado')
end

function M.teleportToPoint()
  local p = core.state.savedPoint
  if not p then return core.notify('No hay punto guardado') end
  core.safe('Teleport', function()
    physics.setCarPosition(0, p.pos, (p.dir * -1)) -- [VERIFICAR]
  end)
end

function M.teleportToPits()
  core.safe('Teleport a pits', function()
    physics.teleportCarTo(0, ac.SpawnSet.Pits) -- [VERIFICAR]
  end)
end

-- Escucha el boton de retorno aunque el menu este cerrado.
function M.update(dt)
  if M.returnButton:pressed() then
    M.teleportToPoint()
  end
end

return M
end

-- ===== modulo: features/time (src/features/time.lua) =====
__modules['features/time'] = function()
-- Hora del dia.
local core = import('core')

local M = {}

function M.setTimeOfDay(hour)
  core.safe('Hora del dia', function()
    -- [VERIFICAR] pendiente: poner aqui la funcion real del SDK para la hora
    error('pendiente de implementar')
  end)
end

return M
end

-- ===== modulo: ui/menu (src/ui/menu.lua) =====
__modules['ui/menu'] = function()
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
  ui.toolWindow('acs_menu/main', vec2(250, 150), vec2(500, 750), false, true, drawMenu)
  ui.popStyleVar(2)
  ui.popStyleColor(2)
end

return M
end

-- ===== modulo: ui/tabs/car (src/ui/tabs/car.lua) =====
__modules['ui/tabs/car'] = function()
-- Pestana: cambio de coche.
local CONFIG = import('config')
local core = import('core')
local car = import('features/car')
local T = import('ui/theme')
local C, sectionTitle, styledButton = T.C, T.sectionTitle, T.styledButton

return function()
  local state = core.state

  sectionTitle('Coche', C.accentHi)
  for i, c in ipairs(CONFIG.cars) do
    if styledButton(c.name, vec2(-0.1, 32), state.carIndex == i) then
      state.carIndex, state.skinIndex = i, 1
    end
  end
  sectionTitle('Skin', C.accentHi)
  for i, s in ipairs(CONFIG.cars[state.carIndex].skins) do
    if styledButton(s, vec2(-0.1, 28), state.skinIndex == i) then state.skinIndex = i end
  end
  ui.dummy(vec2(0, 8))
  if styledButton('APLICAR  (reconecta)', vec2(-0.1, 38), true) then
    car.changeCar(state.carIndex, state.skinIndex)
  end
end
end

-- ===== modulo: ui/tabs/skin (src/ui/tabs/skin.lua) =====
__modules['ui/tabs/skin'] = function()
-- Pestana: skins locales.
local skin = import('features/skin')
local T = import('ui/theme')
local C, smallText, sectionTitle, styledButton = T.C, T.smallText, T.sectionTitle, T.styledButton

return function()
  local skinState = skin.state
  sectionTitle('Cambiar skin', C.accentHi)

  local carID = ac.getCarID(0)

  -- Actualizar la lista cuando cambia el coche.
  if skinState.carID ~= carID then
    skin.refresh()
  end

  smallText('Coche: ' .. tostring(carID), C.text)
  ui.dummy(vec2(0, 4))

  -- Sin skins: aviso y boton de recarga
  if #skinState.skins == 0 then
    smallText('No se han encontrado carpetas de skins.')
    smallText('Comprueba la ruta local del coche.')
    ui.dummy(vec2(0, 8))
    if styledButton('RECARGAR SKINS', vec2(-0.1, 34), true) then
      skin.refresh()
    end
    return
  end

  smallText('Skins locales: ' .. #skinState.skins)
  ui.dummy(vec2(0, 4))

  if styledButton('RECARGAR LISTA', vec2(-0.1, 28), false) then
    skin.refresh()
  end

  ui.dummy(vec2(0, 6))

  -- Lista con scroll para que no desborde la ventana si hay muchas skins
  ui.pushStyleColor(ui.StyleColor.ChildBg, rgbm(0, 0, 0, 0.18))
  ui.pushStyleVar(ui.StyleVar.ChildRounding, 9)
  ui.childWindow('acs_skin_list', vec2(-0.1, 200), false, function()
    for i, s in ipairs(skinState.skins) do
      local label = s.label .. '##skin_' .. s.id
      if styledButton(label, vec2(-0.1, 28), skinState.selected == i) then
        skinState.selected = i
      end
    end
  end)
  ui.popStyleVar(1)
  ui.popStyleColor(1)

  ui.dummy(vec2(0, 8))

  if styledButton('APLICAR SKIN', vec2(-0.1, 38), true) then
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
end

-- ===== modulo: ui/tabs/teleport (src/ui/tabs/teleport.lua) =====
__modules['ui/tabs/teleport'] = function()
-- Pestana: reaparicion / TP y boton de retorno.
local teleport = import('features/teleport')
local T = import('ui/theme')
local C, smallText, sectionTitle, styledButton = T.C, T.smallText, T.sectionTitle, T.styledButton

return function()
  local returnButton = teleport.returnButton

  sectionTitle('Reaparicion / TP', C.accentHi)
  if styledButton('Guardar punto actual', vec2(-0.1, 34), false) then teleport.savePoint() end
  if styledButton('Volver al punto guardado', vec2(-0.1, 34), false) then teleport.teleportToPoint() end
  if styledButton('Ir a pits', vec2(-0.1, 34), false) then teleport.teleportToPits() end

  sectionTitle('Boton de retorno', C.accentHi)
  smallText('Asigna una tecla o boton para volver al punto guardado.')
  ui.dummy(vec2(0, 4))
  returnButton:control(vec2(ui.availableSpaceX(), 30))
  ui.dummy(vec2(0, 2))
  if returnButton:configured() then
    smallText('Asignado a: ' .. tostring(returnButton:boundTo()), C.accentHi)
  else
    smallText('Sin asignar: pulsa el cuadro y luego la tecla/boton.')
  end
end
end

-- ===== modulo: ui/tabs/time (src/ui/tabs/time.lua) =====
__modules['ui/tabs/time'] = function()
-- Pestana: hora del dia.
local core = import('core')
local time = import('features/time')
local T = import('ui/theme')
local C, sectionTitle, styledButton = T.C, T.sectionTitle, T.styledButton

return function()
  local state = core.state

  sectionTitle('Hora del dia', C.accentHi)
  ui.pushStyleColor(ui.StyleColor.FrameBg, C.surface)
  ui.pushStyleColor(ui.StyleColor.SliderGrab, C.accent)
  ui.pushStyleColor(ui.StyleColor.SliderGrabActive, C.accentHi)
  ui.pushStyleVar(ui.StyleVar.FrameRounding, 9)
  ui.setNextItemWidth(ui.availableSpaceX())
  state.hour = ui.slider('##hour', state.hour, 0, 24, 'Hora: %.1f')
  ui.popStyleVar(1)
  ui.popStyleColor(3)
  ui.dummy(vec2(0, 8))
  if styledButton('Aplicar hora', vec2(-0.1, 36), true) then time.setTimeOfDay(state.hour) end
end
end

-- ===== modulo: ui/tabs/track (src/ui/tabs/track.lua) =====
__modules['ui/tabs/track'] = function()
-- Pestana: votacion de mapa.
local mv = import('features/mapvote')
local T = import('ui/theme')
local C, smallText, sectionTitle, styledButton, drawProgress =
  T.C, T.smallText, T.sectionTitle, T.styledButton, T.drawProgress

local mapvote = mv.data

return function()
  local st = mapvote.status

  sectionTitle('Mapa actual', C.accentHi)
  if st and st.current then
    ui.pushFont(ui.Font.Small)
    ui.textWrapped(st.current.name)
    ui.popFont()
  elseif mapvote.statusError then
    smallText('Sin conexion con el servidor: ' .. mapvote.statusError)
  else
    smallText('Consultando...')
  end

  -- Cambio aprobado: cuenta atras
  if st and st.changing then
    sectionTitle('Cambiando de circuito', C.accentHi)
    smallText(string.format('El servidor se reinicia en %d s. Vuelve a entrar al servidor.', st.changeInSeconds or 0), C.accentHi)
    return
  end

  -- Votacion en curso
  if st and st.active and st.proposal then
    sectionTitle('Votacion en curso', C.accentHi)
    ui.pushFont(ui.Font.Small)
    ui.textWrapped(st.proposal.name)
    ui.popFont()
    smallText('Propone: ' .. tostring(st.proposer or '?'))
    smallText(string.format('A favor: %d de %d necesarios  |  Conectados: %d', st.yes, st.needed, st.connectedAtStart))
    smallText(string.format('Tiempo restante: %d s', st.secondsLeft))
    ui.dummy(vec2(0, 4))
    drawProgress(st.yes / math.max(1, st.needed))

    local voted = mapvote.myVoteFor == st.proposal.id
    local w = (ui.availableSpaceX() - 6) / 2
    if styledButton('A FAVOR', vec2(w, 36), voted and mapvote.myVote == true) then mv.castVote(true) end
    ui.sameLine(0, 6)
    if styledButton('EN CONTRA', vec2(w, 36), voted and mapvote.myVote == false) then mv.castVote(false) end
    return
  end

  -- Sin votacion: elegir mapa y proponer
  local cooldown = st and st.cooldownLeft or 0
  sectionTitle('Proponer cambio de mapa', C.accentHi)
  if cooldown > 0 then
    smallText(string.format('Podras iniciar otra votacion en %d s', cooldown), C.accentHi)
  end

  if mapvote.tracksState == 'loading' then
    smallText('Cargando lista de mapas...')
  elseif mapvote.tracksState == 'error' then
    smallText('No se pudo cargar la lista de mapas.')
    ui.dummy(vec2(0, 4))
    if styledButton('REINTENTAR', vec2(-0.1, 32), true) then mv.loadTracks() end
    return
  end

  ui.setNextItemWidth(ui.availableSpaceX())
  mapvote.filter = ui.inputText('##mapfilter', mapvote.filter)
  if mapvote.filter == '' then smallText('Escribe arriba para filtrar mapas.') end
  ui.dummy(vec2(0, 4))

  local needle = string.lower(mapvote.filter or '')
  ui.pushStyleColor(ui.StyleColor.ChildBg, rgbm(0, 0, 0, 0.18))
  ui.pushStyleVar(ui.StyleVar.ChildRounding, 9)
  ui.childWindow('acs_map_list', vec2(-0.1, 230), false, function()
    local shown = 0
    for _, e in ipairs(mapvote.tracks) do
      if needle == '' or string.find(string.lower(e.name), needle, 1, true) then
        shown = shown + 1
        if shown > 150 then
          smallText('Hay mas resultados: afina el filtro.')
          break
        end
        if styledButton(e.name .. '##map_' .. e.id, vec2(-0.1, 28), mapvote.selected == e.id) then
          mapvote.selected = e.id
        end
      end
    end
    if shown == 0 then smallText('Sin resultados.') end
  end)
  ui.popStyleVar(1)
  ui.popStyleColor(1)

  ui.dummy(vec2(0, 8))
  local entry
  for _, e in ipairs(mapvote.tracks) do
    if e.id == mapvote.selected then entry = e break end
  end
  local isCurrent = entry and st and st.current
      and entry.track == st.current.track and entry.layout == st.current.layout
  local canPropose = entry ~= nil and cooldown <= 0 and not isCurrent

  if styledButton('PROPONER CAMBIO', vec2(-0.1, 38), true, not canPropose) then mv.propose(entry) end
  if isCurrent then smallText('Ya estas en ese mapa.') end
  ui.dummy(vec2(0, 4))
  if styledButton('Recargar lista', vec2(-0.1, 26), false) then mv.loadTracks() end
end
end

-- ===== modulo: ui/theme (src/ui/theme.lua) =====
__modules['ui/theme'] = function()
-- Colores y widgets reutilizables (tema oscuro moderno). Sin logica de negocio.
local M = {}

M.C = {
  bg        = rgbm(0.045, 0.045, 0.070, 0.96),
  surface   = rgbm(0.100, 0.100, 0.150, 1.00),
  surfaceHi = rgbm(0.150, 0.140, 0.220, 1.00),
  accent    = rgbm(0.120, 0.500, 0.280, 0.80),
  accentHi  = rgbm(0.250, 0.950, 0.480, 1.00),
  text      = rgbm(0.920, 0.950, 0.925, 1.00),
  dim       = rgbm(0.620, 0.680, 0.635, 1.00),
}
local C = M.C

-- Texto grande: usa dwrite si el SDK lo ofrece; si no, texto normal.
function M.bigText(text, size, color)
  if ui.dwriteText then
    ui.dwriteText(text, size, color)
  else
    ui.pushFont(ui.Font.Title)
    ui.textColored(text, color)
    ui.popFont()
  end
end

function M.smallText(text, color)
  ui.pushFont(ui.Font.Small)
  ui.textColored(text, color or C.dim)
  ui.popFont()
end

-- Boton con estilo (selected = resaltado con el color de acento)
function M.styledButton(label, size, selected, disabled)
  ui.pushStyleVar(ui.StyleVar.FrameRounding, 9)
  ui.pushStyleColor(ui.StyleColor.Button,        selected and C.accent   or C.surface)
  ui.pushStyleColor(ui.StyleColor.ButtonHovered, selected and C.accentHi or C.surfaceHi)
  ui.pushStyleColor(ui.StyleColor.ButtonActive,  C.accent)
  ui.pushStyleColor(ui.StyleColor.Text,          C.text)
  local pressed = ui.button(label, size, disabled and ui.ButtonFlags.Disabled or 0)
  ui.popStyleColor(4)
  ui.popStyleVar(1)
  return pressed and not disabled
end

function M.sectionTitle(text, color)
  ui.dummy(vec2(0, 4))
  M.smallText(string.upper(text), color or C.accent)
  ui.dummy(vec2(0, 2))
end

function M.accentLine()
  local p = ui.getCursor()
  local w = ui.availableSpaceX()
  ui.drawRectFilled(p, p + vec2(w, 2), C.accent, 1)
  ui.dummy(vec2(0, 8))
end

function M.drawProgress(fraction)
  local p = ui.getCursor()
  local w = ui.availableSpaceX()
  ui.drawRectFilled(p, p + vec2(w, 8), C.surface, 4)
  ui.drawRectFilled(p, p + vec2(w * math.max(0, math.min(1, fraction)), 8), C.accent, 4)
  ui.dummy(vec2(0, 12))
end

return M
end

-- ===== punto de entrada (src/main.lua) =====
__modules['__main'] = function()
-- Punto de entrada: engancha los callbacks de CSP. Aqui no hay logica propia.
local CONFIG = import('config')
local core = import('core')
local teleport = import('features/teleport')
local mapvote = import('features/mapvote')
local menu = import('ui/menu')

function script.update(dt)
  local sim = ac.getSim()
  if sim.isReplayActive or sim.isPaused or sim.isInMainMenu then return end
  if core.state.open and ac.getCar(0).gas > 0 then core.state.open = false end
  teleport.update(dt)
  mapvote.update(dt, core.state.open and core.state.tab == 'track')
end

function script.drawUI(dt)
  if ui.keyboardButtonPressed(CONFIG.toggleKey, false) then core.state.open = not core.state.open end
  if not core.state.open then return end
  menu.drawWindow()
end
end
import('__main')
