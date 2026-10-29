-- ACS Drift by Water - script ONLINE para CSP, v0.5
-- Se carga desde el servidor via csp_extra_options.ini ([SCRIPT_1]).
-- Tecla M: abrir/cerrar el menu.
-- Lo marcado [VERIFICAR] no esta confirmado en la documentacion: si falla,
-- el error aparece en el propio menu y en el log de CSP.

------------------------------------------------------------------------
-- CONFIGURACION (edita antes de subir)
------------------------------------------------------------------------
local CONFIG = {
  toggleKey = ui.KeyIndex.M,

  -- Coches ofrecidos ('id' = carpeta del coche, 'skins' = carpetas de skin).
  -- Deben existir como entradas en el entry_list del servidor.
  cars = {
    { id = 'tunermnrcars_eskuko_missile_e36coupe', name = 'Eskuko Missile E36 Coupe', skins = { 'default', 'Titanio' } },
    { id = 'tunermnrcars_eskuko_missile_e36compact',    name = 'Eskuko Missile E36 Compact',    skins = { 'default', 'JulenArjona' } },
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

------------------------------------------------------------------------
-- ESTADO Y UTILIDADES
------------------------------------------------------------------------
local state = {
  open = false, tab = 1, carIndex = 1, skinIndex = 1, hour = 12,
  message = '', messageTime = 0, savedPoint = nil,
}

-- Boton configurable para volver al punto guardado (se asigna en la pestana TP).
-- El id debe ser unico; CSP guarda la asignacion por id.
local returnButton = ac.ControlButton('__ACS_DRIFT_RETURN')

local function notify(text)
  state.message, state.messageTime = text, os.clock()
  ac.log('[ACS Menu] ' .. text)
end

local function safe(label, fn)
  local ok, err = pcall(fn)
  if not ok then notify(label .. ': no disponible (' .. tostring(err):sub(1, 70) .. ')') end
  return ok
end

local function sendChatCommand(cmd)
  ac.sendChatMessage(cmd)
  notify('Enviado: ' .. cmd)
end

------------------------------------------------------------------------
-- FUNCIONES
------------------------------------------------------------------------

------------------------------------------------------------------------
-- Coche y skin
------------------------------------------------------------------------
local function changeCar(carIdx, skinIdx)
  local car = CONFIG.cars[carIdx]
  safe('Cambio de coche', function()
    -- [VERIFICAR] nombre y parametros exactos en tu SDK
    ac.reconnectTo({
      host = CONFIG.server.host, port = CONFIG.server.port,
      httpPort = CONFIG.server.httpPort, password = CONFIG.server.password,
      car = car.id, skin = car.skins[skinIdx],
    })
  end)
end

-- CAMBIO VISUAL DE SKIN (solo cliente local)


-- =========================================
-- SKINS LOCALES: descubrimiento y aplicación
-- =========================================

local skinState = {
  carID = nil,
  skins = {},
  selected = 1,
  message = ''
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

      skins[#skins + 1] = {
        id = name,
        label = label
      }
    end
  end

  table.sort(skins, function(a, b)
    return a.label:lower() < b.label:lower()
  end)

  return skins
end

local function refreshLocalSkins()
  local carID = ac.getCarID(0)

  skinState.carID = carID
  skinState.skins = loadLocalSkins(carID)
  skinState.selected = 1
  skinState.message = ''

  -- Seleccionar inicialmente la skin oficial del coche.
  local currentSkinID = ac.getCarSkinID(0)

  for i, skin in ipairs(skinState.skins) do
    if skin.id == currentSkinID then
      skinState.selected = i
      break
    end
  end
end

local function applyLocalSkin(skin)
  local carID = ac.getCarID(0)
  local skinPath = ac.getFolder(ac.FolderID.ContentCars)
      .. '/' .. carID .. '/skins/' .. skin.id

  local ok, err = pcall(function()
    ac.findNodes('carRoot:0'):applySkin(skinPath)
  end)

  if ok then
    skinState.message = 'Skin aplicada localmente: ' .. skin.label
  else
    skinState.message = 'Error al aplicar skin: ' .. tostring(err)
  end
end


------------------------------------------------------------------------
-- Votacion de mapa (servidor: MapVotePlugin)
-- La lista de mapas y el estado se leen por HTTP; las acciones van por chat.
------------------------------------------------------------------------
local mapvote = {
  tracks = {}, tracksState = 'idle',   -- idle | loading | ok | error
  status = nil, statusError = nil,
  filter = '', selected = nil,
  pollTimer = 0, myVote = nil, myVoteFor = nil,
}

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

local function loadTracks()
  mapvote.tracksState = 'loading'
  httpGetJson('/mapvote/tracks', function(data, err)
    if data then
      mapvote.tracks, mapvote.tracksState = data, 'ok'
    else
      mapvote.tracksState = 'error'
      notify('Lista de mapas: ' .. tostring(err))
    end
  end)
end

local function pollStatus()
  httpGetJson('/mapvote/status', function(data, err)
    mapvote.status, mapvote.statusError = data, err
    if data and not data.active then mapvote.myVote, mapvote.myVoteFor = nil, nil end
  end)
end

local function mapVoteUpdate(dt)
  if not state.open or state.tab ~= 3 then return end
  if mapvote.tracksState == 'idle' then loadTracks() end
  mapvote.pollTimer = mapvote.pollTimer - dt
  if mapvote.pollTimer <= 0 then
    mapvote.pollTimer = 1.5
    pollStatus()
  end
end

local function proposeTrack(entry)
  sendChatCommand(string.format(CONFIG.commands.mapStart, entry.id))
  mapvote.pollTimer = 0.4
end

local function castVote(yes)
  sendChatCommand(yes and CONFIG.commands.mapYes or CONFIG.commands.mapNo)
  mapvote.myVote = yes
  mapvote.myVoteFor = mapvote.status and mapvote.status.proposal and mapvote.status.proposal.id or nil
  mapvote.pollTimer = 0.4
end


local function setTimeOfDay(hour)
  safe('Hora del dia', function()
    -- [VERIFICAR] pendiente: poner aqui la funcion real del SDK para la hora
    error('pendiente de implementar')
  end)
end

local function savePoint()
  local car = ac.getCar(0)
  state.savedPoint = { pos = car.position:clone(), dir = car.look:clone() }
  notify('Punto guardado')
end

local function teleportToPoint()
  if not state.savedPoint then return notify('No hay punto guardado') end
  safe('Teleport', function()
    physics.setCarPosition(0, state.savedPoint.pos, (state.savedPoint.dir * -1)) -- [VERIFICAR]
  end)
end

local function teleportToPits()
  safe('Teleport a pits', function()
    physics.teleportCarTo(0, ac.SpawnSet.Pits) -- [VERIFICAR]
  end)
end

-- Escucha el boton de retorno aunque el menu este cerrado.
function script.update(dt)
  local sim = ac.getSim()
  if sim.isReplayActive or sim.isPaused or sim.isInMainMenu then return end
  if returnButton:pressed() then
    teleportToPoint()
  end
  mapVoteUpdate(dt)
end

------------------------------------------------------------------------
-- INTERFAZ (tema oscuro moderno)
------------------------------------------------------------------------
local C = {
  bg        = rgbm(0.045, 0.045, 0.070, 0.96),
  surface   = rgbm(0.100, 0.100, 0.150, 1),
  surfaceHi = rgbm(0.150, 0.140, 0.220, 1),
  accent    = rgbm(0.62, 0.36, 1.00, 1),
  accentHi  = rgbm(0.74, 0.50, 1.00, 1),
  text      = rgbm(0.94, 0.94, 0.98, 1),
  dim       = rgbm(0.58, 0.58, 0.70, 1),
}

-- Texto grande: usa dwrite si el SDK lo ofrece; si no, texto normal.
local function bigText(text, size, color)
  if ui.dwriteText then
    ui.dwriteText(text, size, color)
  else
    ui.pushFont(ui.Font.Title)
    ui.textColored(text, color)
    ui.popFont()
  end
end

local function smallText(text, color)
  ui.pushFont(ui.Font.Small)
  ui.textColored(text, color or C.dim)
  ui.popFont()
end

-- Boton con estilo (selected = resaltado con el color de acento)
local function styledButton(label, size, selected, disabled)
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

local function sectionTitle(text)
  ui.dummy(vec2(0, 4))
  smallText(string.upper(text), C.accent)
  ui.dummy(vec2(0, 2))
end

local function accentLine()
  local p = ui.getCursor()
  local w = ui.availableSpaceX()
  ui.drawRectFilled(p, p + vec2(w, 2), C.accent, 1)
  ui.dummy(vec2(0, 8))
end

local function header()
  ui.dummy(vec2(0, 2))
  bigText('ACS DRIFT', 26, C.text)
  smallText('by Water', C.accentHi)
  ui.dummy(vec2(0, 6))
  accentLine()
end

local function tabs()
  local names = { 'Coche', 'Skin', 'Circuito', 'Hora', 'TP' }
  local w = (ui.availableSpaceX() - (#names - 1) * 6) / #names
  for i, n in ipairs(names) do
    if i > 1 then ui.sameLine(0, 6) end
    if styledButton(n, vec2(w, 30), state.tab == i) then state.tab = i end
  end
  ui.dummy(vec2(0, 6))
end

local function tabCar()
  sectionTitle('Coche')
  for i, c in ipairs(CONFIG.cars) do
    if styledButton(c.name, vec2(-0.1, 32), state.carIndex == i) then
      state.carIndex, state.skinIndex = i, 1
    end
  end
  sectionTitle('Skin')
  for i, s in ipairs(CONFIG.cars[state.carIndex].skins) do
    if styledButton(s, vec2(-0.1, 28), state.skinIndex == i) then state.skinIndex = i end
  end
  ui.dummy(vec2(0, 8))
  if styledButton('APLICAR  (reconecta)', vec2(-0.1, 38), true) then
    changeCar(state.carIndex, state.skinIndex)
  end
end

local function tabSkin()
  sectionTitle('Cambiar skin')
 
  local carID = ac.getCarID(0)
 
  -- Actualizar la lista cuando cambia el coche.
  if skinState.carID ~= carID then
    refreshLocalSkins()
  end
 
  smallText('Coche: ' .. tostring(carID), C.text)
  ui.dummy(vec2(0, 4))
 
  -- Sin skins: aviso y boton de recarga
  if #skinState.skins == 0 then
    smallText('No se han encontrado carpetas de skins.')
    smallText('Comprueba la ruta local del coche.')
    ui.dummy(vec2(0, 8))
    if styledButton('RECARGAR SKINS', vec2(-0.1, 34), true) then
      refreshLocalSkins()
    end
    return
  end
 
  smallText('Skins locales: ' .. #skinState.skins)
  ui.dummy(vec2(0, 4))
 
  if styledButton('RECARGAR LISTA', vec2(-0.1, 28), false) then
    refreshLocalSkins()
  end
 
  ui.dummy(vec2(0, 6))
 
  -- Lista con scroll para que no desborde la ventana si hay muchas skins
  ui.pushStyleColor(ui.StyleColor.ChildBg, rgbm(0, 0, 0, 0.18))
  ui.pushStyleVar(ui.StyleVar.ChildRounding, 9)
  ui.childWindow('acs_skin_list', vec2(-0.1, 200), false, function()
    for i, skin in ipairs(skinState.skins) do
      local label = skin.label .. '##skin_' .. skin.id
      if styledButton(label, vec2(-0.1, 28), skinState.selected == i) then
        skinState.selected = i
      end
    end
  end)
  ui.popStyleVar(1)
  ui.popStyleColor(1)
 
  ui.dummy(vec2(0, 8))
 
  if styledButton('APLICAR SKIN', vec2(-0.1, 38), true) then
    local skin = skinState.skins[skinState.selected]
    if skin then
      applyLocalSkin(skin)
    end
  end
 
  if skinState.message ~= '' then
    ui.dummy(vec2(0, 6))
    ui.pushFont(ui.Font.Small)
    ui.textWrapped(skinState.message)
    ui.popFont()
  end
end

local function drawProgress(fraction)
  local p = ui.getCursor()
  local w = ui.availableSpaceX()
  ui.drawRectFilled(p, p + vec2(w, 8), C.surface, 4)
  ui.drawRectFilled(p, p + vec2(w * math.max(0, math.min(1, fraction)), 8), C.accent, 4)
  ui.dummy(vec2(0, 12))
end

local function tabTrack()
  local st = mapvote.status

  sectionTitle('Mapa actual')
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
    sectionTitle('Cambiando de circuito')
    smallText(string.format('El servidor se reinicia en %d s. Vuelve a entrar al servidor.', st.changeInSeconds or 0), C.accentHi)
    return
  end

  -- Votacion en curso
  if st and st.active and st.proposal then
    sectionTitle('Votacion en curso')
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
    if styledButton('A FAVOR', vec2(w, 36), voted and mapvote.myVote == true) then castVote(true) end
    ui.sameLine(0, 6)
    if styledButton('EN CONTRA', vec2(w, 36), voted and mapvote.myVote == false) then castVote(false) end
    return
  end

  -- Sin votacion: elegir mapa y proponer
  local cooldown = st and st.cooldownLeft or 0
  sectionTitle('Proponer cambio de mapa')
  if cooldown > 0 then
    smallText(string.format('Podras iniciar otra votacion en %d s', cooldown), C.accentHi)
  end

  if mapvote.tracksState == 'loading' then
    smallText('Cargando lista de mapas...')
  elseif mapvote.tracksState == 'error' then
    smallText('No se pudo cargar la lista de mapas.')
    ui.dummy(vec2(0, 4))
    if styledButton('REINTENTAR', vec2(-0.1, 32), true) then loadTracks() end
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

  if styledButton('PROPONER CAMBIO', vec2(-0.1, 38), true, not canPropose) then proposeTrack(entry) end
  if isCurrent then smallText('Ya estas en ese mapa.') end
  ui.dummy(vec2(0, 4))
  if styledButton('Recargar lista', vec2(-0.1, 26), false) then loadTracks() end
end

local function tabTime()
  sectionTitle('Hora del dia')
  ui.pushStyleColor(ui.StyleColor.FrameBg, C.surface)
  ui.pushStyleColor(ui.StyleColor.SliderGrab, C.accent)
  ui.pushStyleColor(ui.StyleColor.SliderGrabActive, C.accentHi)
  ui.pushStyleVar(ui.StyleVar.FrameRounding, 9)
  ui.setNextItemWidth(ui.availableSpaceX())
  state.hour = ui.slider('##hour', state.hour, 0, 24, 'Hora: %.1f')
  ui.popStyleVar(1)
  ui.popStyleColor(3)
  ui.dummy(vec2(0, 8))
  if styledButton('Aplicar hora', vec2(-0.1, 36), true) then setTimeOfDay(state.hour) end
end

local function tabTeleport()
  sectionTitle('Reaparicion / TP')
  if styledButton('Guardar punto actual', vec2(-0.1, 34), false) then savePoint() end
  if styledButton('Volver al punto guardado', vec2(-0.1, 34), true) then teleportToPoint() end
  if styledButton('Ir a pits', vec2(-0.1, 34), false) then teleportToPits() end

  sectionTitle('Boton de retorno')
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

local function drawStatus()
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
  tabs()
  if state.tab == 1 then tabCar()
  elseif state.tab == 2 then tabSkin()
  elseif state.tab == 3 then tabTrack()
  elseif state.tab == 4 then tabTime()
  else tabTeleport() end
  drawStatus()
  ui.dummy(vec2(0, 10))
  smallText('ACS Drift by Water   |   M para cerrar')
end

-- Callback de UI para scripts online [VERIFICAR el nombre en tu version de CSP:
-- si el menu no aparece, comprueba el log; alternativas habituales: script.drawUI / script.update]
function script.drawUI(dt)
  if ui.keyboardButtonPressed(CONFIG.toggleKey, false) then state.open = not state.open end
  if not state.open then return end
  ui.pushStyleColor(ui.StyleColor.WindowBg, C.bg)
  ui.pushStyleColor(ui.StyleColor.Border, C.accent)
  ui.pushStyleVar(ui.StyleVar.WindowRounding, 16)
  ui.pushStyleVar(ui.StyleVar.WindowPadding, vec2(16, 12))
  ui.toolWindow('acs_menu/main', vec2(150, 150), vec2(500, 700), false, true, drawMenu)
  ui.popStyleVar(2)
  ui.popStyleColor(2)
end