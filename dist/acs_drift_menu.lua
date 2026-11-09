-- ACS Drift by Water - script ONLINE para CSP
-- GENERADO EL (2026-11-09 16:24).
-- Se carga desde el servidor via csp_extra_options.ini ([SCRIPT_1]). Tecla configurable: abrir/cerrar.

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

-- ===== modulo: config (src/config.lua) =====
__modules['config'] = function()
-- Configuracion editable del menu. Solo datos, sin logica.
return {
  version = 'v1.0',
  -- La lista de coches de la pestana "Coche" ya NO se edita aqui: se lee en vivo
  -- del entry list del servidor (features/car.lua -> GET /cars/list, servido por
  -- AcsDriftServerPlugin/CarListController). Para anadir o quitar coches, cambia el
  -- entry_list del preset/servidor; el menu lo recoge solo.

  -- Datos opcionales del servidor para reconectar. Dejando host y password vacios reconecta con los datos que tenia.
  server = { host = '', port = 9600, httpPort = 8081, password = '' },

  -- Comandos de chat del plugin AcsDriftServerPlugin (votacion de mapa independiente de los presets).
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

local toggleKeyCandidates = {}
for key = ui.KeyIndex.A, ui.KeyIndex.Z do
  toggleKeyCandidates[#toggleKeyCandidates + 1] = {
    name = string.char(key),
    index = key,
  }
end
for digit = 0, 9 do
  local name = 'D' .. digit
  toggleKeyCandidates[#toggleKeyCandidates + 1] = {
    name = tostring(digit),
    index = ui.KeyIndex[name],
  }
end
for number = 1, 12 do
  local name = 'F' .. number
  toggleKeyCandidates[#toggleKeyCandidates + 1] = {
    name = name,
    index = ui.KeyIndex[name],
  }
end

local function isToggleKeyName(value)
  for _, candidate in ipairs(toggleKeyCandidates) do
    if candidate.name == value and candidate.index then return true end
  end
  return false
end

local storedSettings = ac.storage({
  language = 'en',
  accentIndex = 1,
  bgAlpha = 0.15,
  closeOnGas = false,
  posX = 0.5,
  posY = 0.5,
  toggleKeyName = 'M',
}, 'acsDriftMenu.')

local function normalizedPosition(value)
  if type(value) ~= 'number' or value ~= value
      or value == math.huge or value == -math.huge then
    return 0.5
  end
  return math.max(0, math.min(1, value))
end

local function normalizedAlpha(value)
  if type(value) ~= 'number' or value ~= value
      or value == math.huge or value == -math.huge then
    return 0.15
  end
  return math.max(0.15, math.min(1, value)) -- minimo 15%: el fondo nunca es invisible
end

local language = storedSettings.language
if language ~= 'en' and language ~= 'es' then language = 'en' end

local accentIndex = storedSettings.accentIndex
if type(accentIndex) ~= 'number' or accentIndex ~= accentIndex then accentIndex = 1 end
accentIndex = math.max(1, math.min(5, math.floor(accentIndex)))

local closeOnGas = storedSettings.closeOnGas
if type(closeOnGas) ~= 'boolean' then closeOnGas = false end

local toggleKeyName = storedSettings.toggleKeyName
if not isToggleKeyName(toggleKeyName) then toggleKeyName = 'M' end

M.state = {
  open = false,
  awaitingToggleKey = false,
  tab = 'car',            -- id de la pestana activa (ver ui/menu.lua)
  carID = nil,            -- id del coche elegido en la pestana 'car' (lista leida del servidor)
  message = '', messageTime = 0,
  savedPoint = nil,
  -- Preferencias locales persistidas en CSP.
  settings = {
    language    = language, -- en | es; CSP Lua API does not expose a documented game-language getter.
    accentIndex = accentIndex, -- indice en T.ACCENTS
    bgAlpha     = normalizedAlpha(storedSettings.bgAlpha),
    closeOnGas  = closeOnGas, -- cerrar el menu al acelerar (ver main.lua)
    posX        = normalizedPosition(storedSettings.posX),
    posY        = normalizedPosition(storedSettings.posY),
    toggleKeyName = toggleKeyName,
  },
}

function M.persistSettings()
  local settings = M.state.settings
  storedSettings.language = settings.language
  storedSettings.accentIndex = settings.accentIndex
  storedSettings.bgAlpha = settings.bgAlpha
  storedSettings.closeOnGas = settings.closeOnGas
  storedSettings.posX = settings.posX
  storedSettings.posY = settings.posY
  storedSettings.toggleKeyName = settings.toggleKeyName
end

M.persistSettings()

function M.toggleKeyIndex()
  for _, candidate in ipairs(toggleKeyCandidates) do
    if candidate.name == M.state.settings.toggleKeyName then return candidate.index end
  end
  return ui.KeyIndex.M
end

function M.pressedToggleKeyName()
  for _, candidate in ipairs(toggleKeyCandidates) do
    if candidate.index and ui.keyboardButtonPressed(candidate.index, false) then
      return candidate.name
    end
  end
end

function M.notify(text)
  M.state.message, M.state.messageTime = text, os.clock()
  ac.log('[ACS Menu] ' .. text)
end

-- Ejecuta fn protegida; si falla, avisa en el menu y devuelve false.
function M.safe(label, fn, unavailableText)
  local ok, err = pcall(fn)
  if not ok then
    M.notify(label .. ': ' .. (unavailableText or 'no disponible')
        .. ' (' .. tostring(err):sub(1, 70) .. ')')
  end
  return ok
end

return M
end

-- ===== modulo: features/admin (src/features/admin.lua) =====
__modules['features/admin'] = function()
-- Estado de administrador de ESTA conexion. No hay forma de saberlo por HTTP
-- (el servidor no sabe que jugador hay detras de una peticion web normal), asi
-- que se pide por online event (CSP), que si va atado a la conexion del cliente.
-- El estado puede cambiar en caliente (alguien escribe /admin <contraseña> en el
-- chat a mitad de partida), por eso se vuelve a pedir cada pocos segundos.
local core = import('core')
local net = import('net')
local I18N = import('i18n')

local M = {}

local state = {
  isAdmin = false,
  pluginConnection = 'checking',
  statusRequestPending = false,
  statusRequestAt = 0,
  presets = {},
  presetsState = 'idle',
  presetsError = nil,
  selectedPreset = nil,
}
M.data = state

local presetChangeEvent = ac.OnlineEvent({
  ac.StructItem.key('ACP_AdminPresetChange'),
  presetId = ac.StructItem.uint16(),
})

local requestEvent = ac.OnlineEvent({
  ac.StructItem.key('ACP_AdminStatusRequest'),
  request = ac.StructItem.uint8(),
})

ac.OnlineEvent({
  ac.StructItem.key('ACP_AdminStatusResponse'),
  isAdmin = ac.StructItem.uint8(),
}, function(sender, message)
  if sender ~= nil then return end -- solo mensajes del propio servidor
  state.isAdmin = message.isAdmin == 1
  state.pluginConnection = 'available'
  state.statusRequestPending = false
end)

local pollTimer = 0

function M.request()
  state.statusRequestAt = os.clock()
  state.statusRequestPending = true
  local ok, err = pcall(function()
    requestEvent({ request = 0 })
  end)
  if not ok then
    state.pluginConnection = 'unavailable'
    state.statusRequestPending = false
    ac.log('[ACS Menu] Admin status request failed: ' .. tostring(err))
  end
end

function M.loadPresets()
  state.presetsState = 'loading'
  net.getJson('/admin/presets', function(data, err)
    if data and type(data.presets) == 'table' then
      state.presets, state.presetsState, state.presetsError = data.presets, 'ok', nil
    else
      state.presetsState, state.presetsError = 'error', tostring(err or 'respuesta invalida')
      core.notify(I18N.get('admin.presets_error', state.presetsError))
    end
  end)
end

function M.changePreset(id)
  local ok, err = pcall(function()
    presetChangeEvent({ presetId = id })
  end)
  if not ok then
    core.notify(I18N.get('admin.preset_send_error', tostring(err)))
    return
  end
  state.selectedPreset = nil
  core.notify(I18N.get('admin.preset_sent'))
end

function M.retry()
  M.request()
  if state.isAdmin then M.loadPresets() end
end

function M.update(dt, active)
  if not core.state.open then
    pollTimer = 0
    return
  end

  if active and state.presetsState == 'idle' then M.loadPresets() end

  pollTimer = pollTimer - dt
  if pollTimer <= 0 then
    pollTimer = 5
    M.request()
  end

  if state.statusRequestPending and os.clock() - state.statusRequestAt >= 3 then
    state.pluginConnection = 'unavailable'
    state.statusRequestPending = false
  end
end

M.request() -- primer chequeo nada mas cargar el script

return M
end

-- ===== modulo: features/car (src/features/car.lua) =====
__modules['features/car'] = function()
-- Cambio de coche: la lista ya no se edita a mano (CONFIG.cars); se lee del
-- entry list real del servidor via AcsDriftServerPlugin (/cars/list), con cuantas
-- plazas de cada coche estan libres ahora mismo. El cambio sigue siendo una
-- reconexion (ac.reconnectTo): el servidor asigna la plaza libre que toque.
local CONFIG = import('config')
local core = import('core')
local net = import('net')
local I18N = import('i18n')

local M = {}

local state = {
  list = {}, status = 'idle',   -- idle | loading | ok | error
  pollTimer = 0,
}
M.data = state

function M.refresh()
  state.status = 'loading'
  net.getJson('/cars/list', function(data, err)
    if data then
      state.list, state.status = data, 'ok'
    else
      state.status = 'error'
      core.notify(I18N.get('car.list_error', tostring(err)))
    end
  end)
end

-- active = true cuando la pestana de coche esta visible (decide la UI, no este modulo).
function M.update(dt, active)
  if not active then return end
  if state.status == 'idle' then M.refresh() end
  state.pollTimer = state.pollTimer - dt
  if state.pollTimer <= 0 then
    state.pollTimer = 4 -- las plazas libres cambian poco: no hace falta sondear tan rapido como el mapa
    M.refresh()
  end
end

-- Imagen para la lista: preview de la primera skin local del coche o, si no hay,
-- su badge (logo). Devuelve nil si el coche no esta instalado. Se cachea por coche.
-- El segundo valor indica si es un badge (se dibuja entero, sin recortar).
local previewCache = {}
function M.preview(carID)
  local cached = previewCache[carID]
  if cached == nil then
    cached = false
    pcall(function()
      local carPath = ac.getFolder(ac.FolderID.ContentCars) .. '/' .. carID
      local skinsPath = carPath .. '/skins'
      if io.dirExists(skinsPath) then
        local dirs = io.scanDir(skinsPath, '*') or {}
        table.sort(dirs)
        for _, name in ipairs(dirs) do
          for _, file in ipairs({ 'preview.jpg', 'preview.png' }) do
            local p = skinsPath .. '/' .. name .. '/' .. file
            if io.fileExists(p) then
              cached = { path = p, badge = false }
              return
            end
          end
        end
      end
      local badge = carPath .. '/ui/badge.png'
      if io.fileExists(badge) then cached = { path = badge, badge = true } end
    end)
    previewCache[carID] = cached
  end
  if not cached then return nil, false end
  return cached.path, cached.badge
end

function M.changeCar(carID)
  if not carID or carID == '' then
    core.notify(I18N.get('car.invalid'))
    return false
  end

  local params = { carID = carID }
  if CONFIG.server.host ~= '' then
    params.serverIP = CONFIG.server.host
    params.serverPort = CONFIG.server.port
    params.serverHttpPort = CONFIG.server.httpPort
    params.serverPassword = CONFIG.server.password
  end

  return core.safe(I18N.get('car.change_error'), function()
    ac.reconnectTo(params)
  end, I18N.get('common.unavailable'))
end

return M
end

-- ===== modulo: features/ghost (src/features/ghost.lua) =====
__modules['features/ghost'] = function()
-- Fantasma: grabar una pasada y reproducirla contra el resto (servidor: GhostService).
-- Solo administradores. Las acciones van por evento online (van atadas a la conexion) y la
-- lista y el estado se leen por HTTP. El estado de grabacion lo marca el ultimo ACP_GhostState
-- y se revisa contra /ghost/status, porque el servidor no avisa si el jugador se va a mitad.
local core = import('core')
local net = import('net')
local admin = import('features/admin')
local I18N = import('i18n')

local M = {}

local actionEvent = ac.OnlineEvent({
  ac.StructItem.key('ACP_GhostAction'),
  action = ac.StructItem.uint8(),
  id = ac.StructItem.uint16(),
})

-- Respuestas del servidor (solo a quien pidio la accion)
ac.OnlineEvent({
  ac.StructItem.key('ACP_GhostState'),
  state = ac.StructItem.uint8(),
  seconds = ac.StructItem.uint16(),
  code = ac.StructItem.uint8(),
  id = ac.StructItem.uint16(),
}, function(sender, message)
  if sender ~= nil then return end -- solo mensajes del propio servidor
  M.onServerState(message)
end)

-- Estado que lee la UI
local ghost = {
  list = {}, listState = 'idle',  -- idle | loading | ok | error
  listError = nil,
  status = nil, statusError = nil,
  recording = false, recStartedAt = 0,
  pending = nil, -- { seconds, at } grabacion terminada esperando a guardarse o descartarse
  pendingClosedAt = -10,
  pollTimer = 0, statusTimer = 0,
  selected = nil, confirmDelete = nil,
  recButton = ac.ControlButton('__ACS_DRIFT_GHOST_REC'),
}
M.data = ghost

function M.formatTime(seconds)
  -- LuaJIT (Lua 5.1): sin operador //
  seconds = math.max(0, math.floor(seconds or 0))
  return string.format('%d:%02d', math.floor(seconds / 60), seconds % 60)
end

function M.recSeconds()
  if not ghost.recording then return 0 end
  return os.clock() - ghost.recStartedAt
end

local function durationText(ms)
  return M.formatTime((ms or 0) / 1000)
end
M.durationText = durationText

-- ------------------------------------------------------------------ lectura (HTTP)
function M.refreshList()
  ghost.listState = 'loading'
  net.getJson('/ghost/list', function(data, err)
    if data then
      ghost.list, ghost.listState, ghost.listError = data, 'ok', nil
    else
      ghost.listState, ghost.listError = 'error', tostring(err)
      core.notify(I18N.get('ghost.list_error', ghost.listError))
    end
  end)
end

function M.refreshStatus()
  net.getJson('/ghost/status', function(data, err)
    if not data then
      ghost.statusError = tostring(err)
      return
    end
    ghost.status, ghost.statusError = data, nil

    if data.recording and not ghost.recording then
      -- Grabacion ya en marcha (p.ej. se reabrio el menu): seguir el contador del servidor.
      ghost.recording = true
      ghost.recStartedAt = os.clock() - (data.recordingSeconds or 0)
    elseif ghost.recording and not data.recording and os.clock() - ghost.recStartedAt > 3 then
      -- El servidor ya no graba (se fue el jugador o llego al maximo). Margen de 3 s por las peticiones en vuelo.
      ghost.recording = false
    end

    -- Grabacion pendiente de confirmar: la que diga el servidor (puede haberla resuelto otro admin o caducado).
    -- Margen de 3 s como arriba, para que una respuesta antigua no cierre la ventana recien abierta.
    if data.pending then
      if not ghost.pending and os.clock() - ghost.pendingClosedAt > 3 then ghost.pending = { seconds = data.pendingSeconds or 0, at = os.clock() } end
    elseif ghost.pending and os.clock() - ghost.pending.at > 3 then
      ghost.pending = nil
    end
  end)
end

function M.retry()
  M.refreshList()
  M.refreshStatus()
end

-- ------------------------------------------------------------------ acciones (evento online)
local function send(action, id)
  local ok, err = pcall(function()
    actionEvent({ action = action, id = id or 0 })
  end)
  if not ok then
    core.notify(I18N.get('ghost.action_error', tostring(err)))
    ac.log('[ACS Menu] Ghost action failed: ' .. tostring(err))
    return false
  end
  ghost.statusTimer = 0.5 -- confirmar el estado enseguida
  return true
end

function M.startRecording() return send(1) end
function M.stopRecording() return send(2) end
function M.cancelRecording() return send(3) end
function M.load(id) return send(4, id) end
function M.unload() return send(5) end
function M.savePending() return send(7) end
function M.discardPending() return send(8) end

function M.delete(id)
  if ghost.confirmDelete ~= id then
    ghost.confirmDelete = id -- primer clic: pedir confirmacion
    return false
  end
  ghost.confirmDelete = nil
  return send(6, id)
end

local function closePending()
  if ghost.pending then ghost.pendingClosedAt = os.clock() end
  ghost.pending = nil
end

-- Respuesta del servidor (ACP_GhostState)
function M.onServerState(message)
  if message.state == 1 then
    ghost.recording = true
    ghost.recStartedAt = os.clock()
    closePending()
  elseif message.state == 2 then
    ghost.recording = false
    closePending()
    core.notify(I18N.get('ghost.saved', durationText(message.seconds * 1000)))
    ghost.listState = 'idle' -- que se recargue la lista con la pasada nueva
  elseif message.state == 0 then
    ghost.recording = false
    closePending()
    ghost.listState = 'idle' -- puede haberse borrado o cargado una pasada
    ghost.statusTimer = 0
  elseif message.state == 3 then
    ghost.recording = false
    core.notify(I18N.get('ghost.err.' .. tostring(message.code)))
  elseif message.state == 4 then
    -- Grabacion terminada: se abre la ventana de confirmacion (ui/ghost_confirm)
    ghost.recording = false
    ghost.pending = { seconds = message.seconds, at = os.clock() }
  end
end

-- ------------------------------------------------------------------ bucle
-- tabActive: la pestana Fantasma esta abierta (decide que se consulta).
function M.update(dt, tabActive)
  -- Con una grabacion pendiente la tecla no hace nada: hay que guardarla o descartarla antes.
  if ghost.recButton:pressed() and admin.data.isAdmin and not ghost.pending then
    if ghost.recording then M.stopRecording() else M.startRecording() end
  end

  if tabActive and ghost.listState == 'idle' then M.refreshList() end

  ghost.statusTimer = ghost.statusTimer - dt
  if ghost.statusTimer <= 0 then
    ghost.statusTimer = 2
    if tabActive or ghost.recording or ghost.pending then M.refreshStatus() end
  end
end

return M
end

-- ===== modulo: features/layouts (src/features/layouts.lua) =====
__modules['features/layouts'] = function()
-- Descarga de layouts de DriftZonesEditor publicados por el servidor.
local core = import('core')
local mapvote = import('features/mapvote')
local net = import('net')
local I18N = import('i18n')

local M = {}
local state = {
  track = nil,
  layouts = {},
  status = 'idle', -- idle | loading | ok | error
  selected = nil,
  requestId = 0,
}
M.data = state

local function encodePathSegment(value)
  return (value:gsub('([^A-Za-z0-9_.~%-])', function(char)
    return string.format('%%%02X', string.byte(char))
  end))
end

local function validFileName(fileName)
  return type(fileName) == 'string'
      and fileName ~= ''
      and fileName ~= '.'
      and fileName ~= '..'
      and not fileName:find('[/\\:]')
      and fileName:lower():match('%.lua$') ~= nil
end

function M.suggestedDownloadDirectory()
  return 'steamapps\\common\\assettocorsa\\apps\\lua\\DriftZonesEditor\\tracks'
end

function M.refresh(track)
  state.requestId = state.requestId + 1
  local requestId = state.requestId
  state.track = track
  state.layouts = {}
  state.selected = nil
  state.status = track and 'loading' or 'idle'
  if not track then return end

  net.getJson('/layouts/' .. encodePathSegment(track), function(data, err)
    if requestId ~= state.requestId then return end
    if data and type(data.layouts) == 'table' then
      state.layouts, state.status = data.layouts, 'ok'
    else
      state.status = 'error'
      core.notify(I18N.get('layouts.load_error', tostring(err or 'respuesta invalida')))
    end
  end)
end

function M.update(_, active)
  if not active then return end

  local status = mapvote.data.status
  local track = status and status.current and status.current.track or nil
  if track ~= state.track then M.refresh(track) end
end

function M.download(fileName)
  if not validFileName(fileName) then return end

  local available = false
  for _, layout in ipairs(state.layouts) do
    if layout.name == fileName then available = true break end
  end
  if not available or not state.track then return end

  local openURL = type(os) == 'table' and os.openURL or nil
  if type(openURL) ~= 'function' then
    core.notify(I18N.get('layouts.open_unsupported'))
    return
  end

  local track = state.track
  local path = '/layouts/' .. encodePathSegment(track) .. '/' .. encodePathSegment(fileName)
  local url = net.serverBaseUrl() .. path
  local opened, result = pcall(openURL, url)
  if not opened then
    core.notify(I18N.get('layouts.open_error', tostring(result)))
    return
  elseif result == false then
    core.notify(I18N.get('layouts.open_error', I18N.get('layouts.open_rejected')))
    return
  end

  core.notify(I18N.get('layouts.browser_opened',
      fileName, M.suggestedDownloadDirectory()))
end

return M
end

-- ===== modulo: features/mapvote (src/features/mapvote.lua) =====
__modules['features/mapvote'] = function()
-- Votacion de mapa (servidor: AcsDriftServerPlugin).
-- La lista y el estado se leen por HTTP; las acciones se envian por evento online.
local core = import('core')
local net = import('net')
local I18N = import('i18n')

local M = {}

local actionEvent = ac.OnlineEvent({
  ac.StructItem.key('ACP_MapVoteAction'),
  action = ac.StructItem.uint8(),
  id = ac.StructItem.uint16(),
})

-- Estado que lee la UI
local mapvote = {
  tracks = {}, tracksState = 'idle',   -- idle | loading | ok | error
  status = nil, statusError = nil,
  filter = '', selected = nil,
  pollTimer = 0, myVote = nil, myVoteFor = nil,
}
M.data = mapvote

function M.loadTracks()
  mapvote.tracksState = 'loading'
  net.getJson('/mapvote/tracks', function(data, err)
    if data then
      mapvote.tracks, mapvote.tracksState = data, 'ok'
    else
      mapvote.tracksState = 'error'
      core.notify(I18N.get('track.list_error', tostring(err)))
    end
  end)
end

local function pollStatus()
  net.getJson('/mapvote/status', function(data, err)
    mapvote.status, mapvote.statusError = data, err
    if data and not data.active then mapvote.myVote, mapvote.myVoteFor = nil, nil end
  end)
end

function M.retry()
  M.loadTracks()
  pollStatus()
end

local function sendAction(action, id)
  local ok, err = pcall(function()
    actionEvent({ action = action, id = id or 0 })
  end)
  if not ok then
    core.notify(I18N.get('track.action_error', tostring(err)))
    ac.log('[ACS Menu] Track vote action failed: ' .. tostring(err))
    return false
  end
  mapvote.pollTimer = 0.4
  return true
end

function M.update(dt, active)
  if active and mapvote.tracksState == 'idle' then M.loadTracks() end
  mapvote.pollTimer = mapvote.pollTimer - dt
  if mapvote.pollTimer <= 0 then
    mapvote.pollTimer = 1.5
    pollStatus()
  end
end

function M.propose(entry)
  sendAction(1, entry.id)
end

function M.castVote(yes)
  if not sendAction(yes and 2 or 3) then return end
  mapvote.myVote = yes
  mapvote.myVoteFor = mapvote.status and mapvote.status.proposal and mapvote.status.proposal.id or nil
end

return M
end

-- ===== modulo: features/skin (src/features/skin.lua) =====
__modules['features/skin'] = function()
-- Skins locales: descubrimiento y aplicacion (solo cliente).
local I18N = import('i18n')
local M = {}

local TEXTURE_EXTENSIONS = {
  dds = true,
  jpg = true,
  jpeg = true,
  png = true,
  tga = true,
}

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
      local preview = skinPath .. '/preview.jpg'
      local skinJson = skinPath .. '/ui_skin.json'

      if not io.fileExists(preview) then
        preview = skinPath .. '/preview.png'
        if not io.fileExists(preview) then
          preview = nil
        end
      end

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

      skins[#skins + 1] = { id = name, label = label, preview = preview }
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
  if type(skin) ~= 'table' or type(skin.id) ~= 'string'
      or type(skin.label) ~= 'string' then
    M.state.message = I18N.get('skin.invalid')
    return false
  end

  local carID = ac.getCarID(0)
  local skinPath = ac.getFolder(ac.FolderID.ContentCars)
      .. '/' .. carID .. '/skins/' .. skin.id

  local ok, err = pcall(function()
    if not io.dirExists(skinPath) then
      error(I18N.get('skin.folder_missing'))
    end

    local replacements = {}
    for _, name in ipairs(io.scanDir(skinPath, '*') or {}) do
      local extension = name:match('%.([^%.]+)$')
      local texturePath = skinPath .. '/' .. name
      if extension and TEXTURE_EXTENSIONS[extension:lower()]
          and io.fileExists(texturePath) then
        replacements[name] = texturePath
      end
    end
    if next(replacements) == nil then
      error(I18N.get('skin.textures_missing'))
    end

    local carRoot = ac.findNodes('carRoot:0')
    if not carRoot then
      error(I18N.get('skin.car_missing'))
    end
    if type(carRoot.applySkin) ~= 'function' then
      error(I18N.get('skin.unsupported'))
    end
    if type(carRoot.resetSkin) ~= 'function' then
      error(I18N.get('skin.reset_unsupported'))
    end

    carRoot:resetSkin()
    carRoot:applySkin(replacements)
  end)

  if ok then
    M.state.message = I18N.get('skin.local_applied', skin.label)
  else
    M.state.message = I18N.get('skin.apply_error', tostring(err))
  end
  return ok
end

return M
end

-- ===== modulo: features/teleport (src/features/teleport.lua) =====
__modules['features/teleport'] = function()
-- Punto de reaparicion, TP a pits y boton configurable de retorno.
local core = import('core')
local I18N = import('i18n')

local M = {}

-- Boton configurable para volver al punto guardado (se asigna en la pestana TP).
-- El id debe ser unico; CSP guarda la asignacion por id.
M.returnButton = ac.ControlButton('__ACS_DRIFT_RETURN')

function M.savePoint()
  local car = ac.getCar(0)
  if not car or not car.position or not car.look then
    return core.notify(I18N.get('teleport.save_error'))
  end
  core.state.savedPoint = { pos = car.position:clone(), dir = car.look:clone() }
  core.notify(I18N.get('teleport.saved'))
end

function M.teleportToPoint()
  local p = core.state.savedPoint
  if not p then return core.notify(I18N.get('teleport.no_point')) end
  core.safe(I18N.get('teleport.action_error'), function()
    physics.setCarPosition(0, p.pos, (p.dir * -1))
  end, I18N.get('common.unavailable'))
end

function M.teleportToPits()
  core.safe(I18N.get('teleport.pits_error'), function()
    physics.teleportCarTo(0, ac.SpawnSet.Pits)
  end, I18N.get('common.unavailable'))
end

-- Escucha el boton de retorno aunque el menu este cerrado.
function M.update(dt)
  if M.returnButton:pressed() then
    M.teleportToPoint()
  end
end

return M
end

-- ===== modulo: i18n (src/i18n.lua) =====
__modules['i18n'] = function()
local core = import('core')

local M = {}

local strings = {
  en = {
    ['color.green'] = 'Green',
    ['color.purple'] = 'Purple',
    ['color.orange'] = 'Orange',
    ['color.blue'] = 'Blue',
    ['color.red'] = 'Red',
    ['tab.car'] = 'Car',
    ['tab.skin'] = 'Skin',
    ['tab.track'] = 'Track',
    ['tab.layouts'] = 'Layouts',
    ['tab.teleport'] = 'TP',
    ['tab.settings'] = 'Settings',
    ['tab.admin'] = 'Admin',
    ['menu.footer'] = '[%s] to open/close | ACS Drift by Water',
    ['car.title'] = 'Car',
    ['car.loading'] = 'Loading available cars...',
    ['car.server_error'] = 'Could not reach the server.',
    ['common.retry'] = 'RETRY',
    ['plugin.connection_warning'] = 'Cannot connect to the ACS Drift server plugin. It may not be installed or enabled on this server.',
    ['plugin.retry'] = 'RETRY CONNECTION',
    ['common.unavailable'] = 'unavailable',
    ['common.sent'] = 'Sent: %s',
    ['car.empty'] = 'The server has no cars configured in its entry list.',
    ['car.free'] = '%s  (%d/%d free)##car_%s',
    ['car.reload'] = 'RELOAD LIST',
    ['car.reconnect_note'] = 'Changing car reconnects you to the server.',
    ['car.current'] = 'Current car: %s',
    ['car.count'] = 'Available cars: %d',
    ['car.apply'] = 'APPLY  (reconnects)',
    ['car.no_slots'] = 'That car has no free slots right now.',
    ['car.choose'] = 'Choose a car from the list.',
    ['car.list_error'] = 'Car list: %s',
    ['car.invalid'] = 'Could not change car: invalid selection.',
    ['car.change_error'] = 'Car change',
    ['skin.title'] = 'Change skin',
    ['skin.local_only'] = 'This change is only visible to you; it does not affect the server.',
    ['skin.car'] = 'Car: %s',
    ['skin.not_found'] = 'No skin folders found.',
    ['skin.check_path'] = 'Check the local car folder.',
    ['skin.reload'] = 'RELOAD SKINS',
    ['skin.count'] = 'Local skins: %d',
    ['skin.reload_list'] = 'RELOAD LIST',
    ['skin.apply'] = 'APPLY SKIN',
    ['skin.invalid'] = 'Could not apply skin: invalid skin.',
    ['skin.local_applied'] = 'Skin applied locally (only visible to you): %s',
    ['skin.apply_error'] = 'Error applying skin: %s',
    ['skin.folder_missing'] = 'Local skin folder not found.',
    ['skin.textures_missing'] = 'The folder contains no supported textures.',
    ['skin.car_missing'] = 'Local car not found.',
    ['skin.unsupported'] = 'This CSP version does not support local skin changes.',
    ['skin.reset_unsupported'] = 'This CSP version does not support resetting the local skin.',
    ['track.current'] = 'Current track',
    ['track.connection_error'] = 'No connection to server: %s',
    ['common.loading'] = 'Loading...',
    ['track.changing'] = 'Track change in progress',
    ['track.restart'] = 'The server restarts in %d s. Rejoin the server.',
    ['track.vote_active'] = 'Vote in progress',
    ['track.vote_counts'] = 'Yes: %d  |  No: %d  |  %d needed',
    ['track.proposer'] = 'Proposed by: %s',
    ['track.votes'] = 'Yes: %d of %d required  |  Connected: %d',
    ['track.time_left'] = 'Time remaining: %d s',
    ['track.action_error'] = 'Could not send track vote action: %s',
    ['track.yes'] = 'YES',
    ['track.no'] = 'NO',
    ['track.propose_title'] = 'Propose track change',
    ['track.cooldown'] = 'You can start another vote in %d s',
    ['track.loading_list'] = 'Loading track list...',
    ['track.load_error'] = 'Could not load the track list.',
    ['track.filter_hint'] = 'Type above to filter tracks.',
    ['track.more_results'] = 'More results: refine your filter.',
    ['track.no_results'] = 'No results.',
    ['track.propose'] = 'PROPOSE CHANGE',
    ['track.already_current'] = 'You are already on this track.',
    ['track.reload'] = 'Reload list',
    ['track.list_error'] = 'Track list: %s',
    ['layouts.title'] = 'Drift layouts: %s',
    ['layouts.browser_hint'] = 'These Lua layouts are for DriftZonesEditor. The browser controls where downloads are saved; enable “Ask where to save each file” to choose a folder.',
    ['layouts.browser_path'] = 'Example destination folder: %s',
    ['layouts.track_unavailable'] = 'Could not determine the current track from the server.',
    ['layouts.loading'] = 'Loading layouts for this track...',
    ['layouts.load_error'] = 'Could not load layouts: %s',
    ['layouts.load_error_short'] = 'Could not load the layout list.',
    ['layouts.empty'] = 'No layouts are available for this track.',
    ['layouts.download'] = 'OPEN LAYOUT DOWNLOAD',
    ['layouts.browser_opened'] = 'Requested %s in your browser. Example destination folder: %s',
    ['layouts.open_unsupported'] = 'This CSP script context cannot open an external browser.',
    ['layouts.open_rejected'] = 'CSP rejected the request to open the browser.',
    ['layouts.open_error'] = 'Could not open the layout download: %s',
    ['layouts.reload'] = 'Reload list',
    ['teleport.title'] = 'Respawn / TP',
    ['teleport.save'] = 'Save current point',
    ['teleport.return'] = 'Return to saved point',
    ['teleport.pits'] = 'Go to pits',
    ['teleport.button_title'] = 'Return button',
    ['teleport.assign_hint'] = 'Assign a key or button to return to the saved point.',
    ['teleport.assigned'] = 'Assigned to: %s',
    ['teleport.unassigned'] = 'Not assigned: click the box, then press a key/button.',
    ['teleport.save_error'] = 'Could not save the point',
    ['teleport.saved'] = 'Point saved',
    ['teleport.no_point'] = 'No saved point',
    ['teleport.action_error'] = 'Teleport',
    ['teleport.pits_error'] = 'Teleport to pits',
    ['admin.description'] = 'Admin actions (requires signing in with /admin).',
    ['admin.cancel'] = 'Cancel current vote / track change',
    ['admin.reload'] = 'Reload track list',
    ['admin.send_error'] = 'Could not send: %s',
    ['admin.presets'] = 'Server presets',
    ['admin.presets_description'] = 'Choose a preset to switch the server car lineup and restart.',
    ['admin.presets_loading'] = 'Loading server presets...',
    ['admin.presets_load_error'] = 'Could not load presets: %s',
    ['admin.presets_error'] = 'Preset list: %s',
    ['admin.presets_empty'] = 'No server presets were found.',
    ['admin.preset_current'] = 'current',
    ['admin.preset_apply'] = 'CHANGE PRESET & RESTART',
    ['admin.preset_sent'] = 'Preset change requested. The server will announce the restart.',
    ['admin.preset_send_error'] = 'Could not request preset change: %s',
    ['settings.general'] = 'General',
    ['settings.appearance'] = 'Appearance',
    ['tab.ghost'] = 'Ghost',
    ['ghost.record_title'] = 'Record a lap',
    ['ghost.record_hint'] = 'Drive one clean lap. The key below also starts and stops it with the menu closed.',
    ['ghost.start'] = 'START RECORDING',
    ['ghost.stop'] = 'STOP',
    ['ghost.confirm_title'] = 'Save this lap?',
    ['ghost.confirm_text'] = 'Recorded lap: %s (standing start trimmed to 1 s). Save it to the server or discard it.',
    ['ghost.confirm_save'] = 'SAVE',
    ['ghost.confirm_discard'] = 'DISCARD',
    ['ghost.pending'] = 'Recorded lap waiting for confirmation: %s',
    ['ghost.cancel'] = 'CANCEL',
    ['ghost.recording'] = 'Recording: %s',
    ['ghost.button_title'] = 'Record / stop key',
    ['ghost.button_hint'] = 'Assign a key or button to start and stop a recording without opening the menu.',
    ['ghost.active_title'] = 'Loaded ghost',
    ['ghost.active'] = '%s · %s · %s',
    ['ghost.none'] = 'No ghost loaded. Load a saved lap to race against it.',
    ['ghost.unload'] = 'REMOVE GHOST',
    ['ghost.saved_title'] = 'Saved laps (this track)',
    ['ghost.empty'] = 'No saved laps for this track and layout yet.',
    ['ghost.loaded'] = 'loaded',
    ['ghost.load'] = 'LOAD',
    ['ghost.delete'] = 'DELETE',
    ['ghost.confirm_delete'] = 'CONFIRM DELETE',
    ['ghost.reload'] = 'Reload list',
    ['ghost.list_error'] = 'Saved laps: %s',
    ['ghost.action_error'] = 'Could not send ghost action: %s',
    ['ghost.saved'] = 'Lap saved (%s). Load it to race against it.',
    ['ghost.hud_rec'] = 'REC %s',
    ['ghost.err.1'] = 'Ghosts are for administrators only.',
    ['ghost.err.2'] = 'Connect with a car before recording.',
    ['ghost.err.3'] = 'A lap is already being recorded.',
    ['ghost.err.4'] = 'That lap is too short to save.',
    ['ghost.err.5'] = 'No free slot for that car on the server. Free one first.',
    ['ghost.err.6'] = 'That lap no longer exists on this track.',
    ['ghost.err.7'] = 'Nothing is being recorded.',
    ['ghost.err.8'] = 'There is no recorded lap waiting to be saved.',
    ['settings.language'] = 'Language',
    ['settings.accent'] = 'Accent color',
    ['settings.accent_hint'] = 'Active buttons, borders and menu highlights.',
    ['settings.transparency'] = 'Background transparency',
    ['settings.opacity'] = 'Opacity: %.2f',
    ['settings.position'] = 'On-screen position',
    ['settings.position_hint'] = '0% = left/top edge, 100% = right/bottom edge.',
    ['settings.toggle_key'] = 'Menu toggle key',
    ['settings.toggle_key_change'] = 'CHANGE KEY  [%s]',
    ['settings.toggle_key_prompt'] = 'Press a letter, number or F1–F12 to assign it.',
    ['settings.toggle_key_cancel'] = 'CANCEL',
    ['settings.toggle_key_saved'] = 'Menu toggle key set to %s.',
    ['settings.close_gas'] = 'Close menu while accelerating',
  },
  es = {
    ['color.green'] = 'Verde',
    ['color.purple'] = 'Morado',
    ['color.orange'] = 'Naranja',
    ['color.blue'] = 'Azul',
    ['color.red'] = 'Rojo',
    ['tab.car'] = 'Coche',
    ['tab.skin'] = 'Skin',
    ['tab.track'] = 'Circuito',
    ['tab.layouts'] = 'Layouts',
    ['tab.teleport'] = 'TP',
    ['tab.settings'] = 'Ajustes',
    ['tab.admin'] = 'Admin',
    ['menu.footer'] = '[%s] para abrir/cerrar | ACS Drift by Water',
    ['car.title'] = 'Coche',
    ['car.loading'] = 'Consultando coches disponibles...',
    ['car.server_error'] = 'No se pudo consultar el servidor.',
    ['common.retry'] = 'REINTENTAR',
    ['plugin.connection_warning'] = 'No se puede conectar con el plugin de ACS Drift del servidor. Puede que no esté instalado o habilitado.',
    ['plugin.retry'] = 'REINTENTAR CONEXIÓN',
    ['common.unavailable'] = 'no disponible',
    ['common.sent'] = 'Enviado: %s',
    ['car.empty'] = 'El servidor no tiene coches configurados en el entry list.',
    ['car.free'] = '%s  (%d/%d libres)##car_%s',
    ['car.reload'] = 'RECARGAR LISTA',
    ['car.reconnect_note'] = 'Cambiar de coche te reconecta al servidor.',
    ['car.current'] = 'Coche actual: %s',
    ['car.count'] = 'Coches disponibles: %d',
    ['car.apply'] = 'APLICAR  (reconecta)',
    ['car.no_slots'] = 'Ese coche no tiene plazas libres ahora mismo.',
    ['car.choose'] = 'Elige un coche de la lista.',
    ['car.list_error'] = 'Lista de coches: %s',
    ['car.invalid'] = 'No se ha podido cambiar de coche: seleccion no valida.',
    ['car.change_error'] = 'Cambio de coche',
    ['skin.title'] = 'Cambiar skin',
    ['skin.local_only'] = 'El cambio solo es visible para ti; no modifica el servidor.',
    ['skin.car'] = 'Coche: %s',
    ['skin.not_found'] = 'No se han encontrado carpetas de skins.',
    ['skin.check_path'] = 'Comprueba la ruta local del coche.',
    ['skin.reload'] = 'RECARGAR SKINS',
    ['skin.count'] = 'Skins locales: %d',
    ['skin.reload_list'] = 'RECARGAR LISTA',
    ['skin.apply'] = 'APLICAR SKIN',
    ['skin.invalid'] = 'No se ha podido aplicar: skin no valida.',
    ['skin.local_applied'] = 'Skin aplicada localmente (solo visible para ti): %s',
    ['skin.apply_error'] = 'Error al aplicar skin: %s',
    ['skin.folder_missing'] = 'No se encuentra la carpeta local de la skin.',
    ['skin.textures_missing'] = 'La carpeta no contiene texturas compatibles.',
    ['skin.car_missing'] = 'No se encontro el coche local.',
    ['skin.unsupported'] = 'Esta version de CSP no permite cambiar skins localmente.',
    ['skin.reset_unsupported'] = 'Esta version de CSP no permite restablecer la skin local.',
    ['track.current'] = 'Mapa actual',
    ['track.connection_error'] = 'Sin conexion con el servidor: %s',
    ['common.loading'] = 'Consultando...',
    ['track.changing'] = 'Cambiando de circuito',
    ['track.restart'] = 'El servidor se reinicia en %d s. Vuelve a entrar al servidor.',
    ['track.vote_active'] = 'Votacion en curso',
    ['track.vote_counts'] = 'A favor: %d  |  En contra: %d  |  Necesarios: %d',
    ['track.proposer'] = 'Propone: %s',
    ['track.votes'] = 'A favor: %d de %d necesarios  |  Conectados: %d',
    ['track.time_left'] = 'Tiempo restante: %d s',
    ['track.action_error'] = 'No se pudo enviar la accion de votacion: %s',
    ['track.yes'] = 'A FAVOR',
    ['track.no'] = 'EN CONTRA',
    ['track.propose_title'] = 'Proponer cambio de mapa',
    ['track.cooldown'] = 'Podras iniciar otra votacion en %d s',
    ['track.loading_list'] = 'Cargando lista de mapas...',
    ['track.load_error'] = 'No se pudo cargar la lista de mapas.',
    ['track.filter_hint'] = 'Escribe arriba para filtrar mapas.',
    ['track.more_results'] = 'Hay mas resultados: afina el filtro.',
    ['track.no_results'] = 'Sin resultados.',
    ['track.propose'] = 'PROPONER CAMBIO',
    ['track.already_current'] = 'Ya estas en ese mapa.',
    ['track.reload'] = 'Recargar lista',
    ['track.list_error'] = 'Lista de mapas: %s',
    ['layouts.title'] = 'Layouts de drift: %s',
    ['layouts.browser_hint'] = 'Estos layouts Lua son para DriftZonesEditor. El navegador controla dónde se guardan; activa «Preguntar dónde guardar cada archivo» para elegir carpeta.',
    ['layouts.browser_path'] = 'Ruta de destino de ejemplo: %s',
    ['layouts.track_unavailable'] = 'No se pudo determinar el circuito actual desde el servidor.',
    ['layouts.loading'] = 'Cargando layouts para este circuito...',
    ['layouts.load_error'] = 'No se pudieron cargar los layouts: %s',
    ['layouts.load_error_short'] = 'No se pudo cargar la lista de layouts.',
    ['layouts.empty'] = 'No hay layouts disponibles para este circuito.',
    ['layouts.download'] = 'ABRIR DESCARGA DEL LAYOUT',
    ['layouts.browser_opened'] = 'Se solicitó abrir %s en el navegador. Ruta de destino de ejemplo: %s',
    ['layouts.open_unsupported'] = 'Este contexto de script de CSP no puede abrir un navegador externo.',
    ['layouts.open_rejected'] = 'CSP rechazó la solicitud para abrir el navegador.',
    ['layouts.open_error'] = 'No se pudo abrir la descarga del layout: %s',
    ['layouts.reload'] = 'Recargar lista',
    ['teleport.title'] = 'Reaparicion / TP',
    ['teleport.save'] = 'Guardar punto actual',
    ['teleport.return'] = 'Volver al punto guardado',
    ['teleport.pits'] = 'Ir a pits',
    ['teleport.button_title'] = 'Boton de retorno',
    ['teleport.assign_hint'] = 'Asigna una tecla o boton para volver al punto guardado.',
    ['teleport.assigned'] = 'Asignado a: %s',
    ['teleport.unassigned'] = 'Sin asignar: pulsa el cuadro y luego la tecla/boton.',
    ['teleport.save_error'] = 'No se pudo guardar el punto',
    ['teleport.saved'] = 'Punto guardado',
    ['teleport.no_point'] = 'No hay punto guardado',
    ['teleport.action_error'] = 'Teleport',
    ['teleport.pits_error'] = 'Teleport a pits',
    ['admin.description'] = 'Acciones de administrador (requieren haber entrado con /admin).',
    ['admin.cancel'] = 'Cancelar votacion / cambio en curso',
    ['admin.reload'] = 'Recargar lista de circuitos',
    ['admin.send_error'] = 'No se pudo enviar: %s',
    ['admin.presets'] = 'Presets del servidor',
    ['admin.presets_description'] = 'Elige un preset para cambiar los coches del servidor y reiniciarlo.',
    ['admin.presets_loading'] = 'Cargando presets del servidor...',
    ['admin.presets_load_error'] = 'No se pudieron cargar los presets: %s',
    ['admin.presets_error'] = 'Lista de presets: %s',
    ['admin.presets_empty'] = 'No se encontraron presets en el servidor.',
    ['admin.preset_current'] = 'actual',
    ['admin.preset_apply'] = 'CAMBIAR PRESET Y REINICIAR',
    ['admin.preset_sent'] = 'Solicitud enviada. El servidor avisara del reinicio.',
    ['admin.preset_send_error'] = 'No se pudo solicitar el cambio de preset: %s',
    ['settings.general'] = 'General',
    ['settings.appearance'] = 'Apariencia',
    ['tab.ghost'] = 'Fantasma',
    ['ghost.record_title'] = 'Grabar una vuelta',
    ['ghost.record_hint'] = 'Haz una vuelta limpia. La tecla de abajo también la inicia y la para con el menú cerrado.',
    ['ghost.start'] = 'GRABAR',
    ['ghost.stop'] = 'PARAR',
    ['ghost.confirm_title'] = '¿Guardar esta vuelta?',
    ['ghost.confirm_text'] = 'Vuelta grabada: %s (salida parada recortada a 1 s). Guárdala en el servidor o descártala.',
    ['ghost.confirm_save'] = 'GUARDAR',
    ['ghost.confirm_discard'] = 'DESCARTAR',
    ['ghost.pending'] = 'Vuelta grabada pendiente de confirmar: %s',
    ['ghost.cancel'] = 'CANCELAR',
    ['ghost.recording'] = 'Grabando: %s',
    ['ghost.button_title'] = 'Tecla de grabar / parar',
    ['ghost.button_hint'] = 'Asigna una tecla o botón para iniciar y parar una grabación sin abrir el menú.',
    ['ghost.active_title'] = 'Fantasma cargado',
    ['ghost.active'] = '%s · %s · %s',
    ['ghost.none'] = 'No hay fantasma cargado. Carga una vuelta guardada para correr contra ella.',
    ['ghost.unload'] = 'QUITAR FANTASMA',
    ['ghost.saved_title'] = 'Vueltas guardadas (este circuito)',
    ['ghost.empty'] = 'Todavía no hay vueltas guardadas en este circuito y layout.',
    ['ghost.loaded'] = 'cargado',
    ['ghost.load'] = 'CARGAR',
    ['ghost.delete'] = 'BORRAR',
    ['ghost.confirm_delete'] = 'CONFIRMAR BORRADO',
    ['ghost.reload'] = 'Recargar lista',
    ['ghost.list_error'] = 'Vueltas guardadas: %s',
    ['ghost.action_error'] = 'No se pudo enviar la acción del fantasma: %s',
    ['ghost.saved'] = 'Vuelta guardada (%s). Cárgala para correr contra ella.',
    ['ghost.hud_rec'] = 'REC %s',
    ['ghost.err.1'] = 'Los fantasmas son solo para administradores.',
    ['ghost.err.2'] = 'Conéctate con un coche antes de grabar.',
    ['ghost.err.3'] = 'Ya se está grabando una vuelta.',
    ['ghost.err.4'] = 'Esa vuelta es demasiado corta para guardarla.',
    ['ghost.err.5'] = 'No hay plaza libre de ese coche en el servidor. Libera una primero.',
    ['ghost.err.6'] = 'Esa vuelta ya no existe en este circuito.',
    ['ghost.err.7'] = 'No se está grabando nada.',
    ['ghost.err.8'] = 'No hay ninguna vuelta grabada pendiente de guardar.',
    ['settings.language'] = 'Idioma',
    ['settings.accent'] = 'Color de acento',
    ['settings.accent_hint'] = 'Botones activos, bordes y resaltados del menu.',
    ['settings.transparency'] = 'Transparencia del fondo',
    ['settings.opacity'] = 'Opacidad: %.2f',
    ['settings.position'] = 'Posicion en pantalla',
    ['settings.position_hint'] = '0% = pegado al borde izquierdo/superior, 100% = al derecho/inferior.',
    ['settings.toggle_key'] = 'Tecla para abrir/cerrar el menú',
    ['settings.toggle_key_change'] = 'CAMBIAR TECLA  [%s]',
    ['settings.toggle_key_prompt'] = 'Pulsa una letra, número o F1–F12 para asignarla.',
    ['settings.toggle_key_cancel'] = 'CANCELAR',
    ['settings.toggle_key_saved'] = 'Tecla del menú asignada: %s.',
    ['settings.close_gas'] = 'Cerrar el menu al acelerar',
  },
}

function M.get(key, ...)
  local language = core.state.settings.language
  local text = (strings[language] or strings.en)[key] or strings.en[key] or key
  if select('#', ...) > 0 then return string.format(text, ...) end
  return text
end

return M
end

-- ===== modulo: net (src/net.lua) =====
__modules['net'] = function()
-- Peticiones HTTP al API del servidor (AcsDriftServerPlugin: /mapvote/*, /cars/*).
-- Modulo compartido: cualquier feature consulta al servidor sin reimplementar
-- la URL base ni el parseo de JSON.
local CONFIG = import('config')

local M = {}

function M.serverBaseUrl()
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

function M.getJson(path, callback)
  local ok, err = pcall(function()
    web.get(M.serverBaseUrl() .. path, function(e, response)
      if e or not response or response.status ~= 200 then
        return callback(nil, tostring(e or (response and response.status) or 'sin respuesta'))
      end
      local parsedOk, data = pcall(JSON.parse, response.body)
      if parsedOk and type(data) == 'table' then callback(data) else callback(nil, 'JSON invalido') end
    end)
  end)
  if not ok then callback(nil, tostring(err)) end
end

return M
end

-- ===== modulo: ui/ghost_confirm (src/ui/ghost_confirm.lua) =====
__modules['ui/ghost_confirm'] = function()
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
end

-- ===== modulo: ui/ghost_hud (src/ui/ghost_hud.lua) =====
__modules['ui/ghost_hud'] = function()
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
end

-- ===== modulo: ui/menu (src/ui/menu.lua) =====
__modules['ui/menu'] = function()
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
  { id = 'car',      label = 'tab.car',      height = 640, draw = import('ui/tabs/car'),
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
local SIDEBAR_W       = 58  -- ancho de la barra lateral colapsada (solo iconos)
local SIDEBAR_GAP     = 10  -- separacion entre la barra y el contenido
local SIDEBAR_BTN_H   = 46
local SIDEBAR_BTN_GAP = 6
-- Color de la barra; su opacidad es la del fondo del menu (Ajustes). Como se pinta
-- encima del fondo de la ventana, la barra siempre queda algo mas opaca que el resto.
local SIDEBAR_R, SIDEBAR_G, SIDEBAR_B = 0.055, 0.055, 0.085
local LABEL_FONT      = 'Segoe UI;Weight=Bold'
local LABEL_SIZE      = 17
local SIDEBAR_PAD     = 4   -- margen interior horizontal de la barra
local SIDEBAR_PAD_Y   = 14  -- margen arriba/abajo (libra las esquinas redondeadas de la ventana)
local ICON_SIZE       = 24
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

-- Etiquetas de la barra en negrita con DirectWrite; si este CSP no lo soporta,
-- cae a la fuente Title normal.
local HAS_DWRITE = ui.pushDWriteFont and ui.popDWriteFont and ui.dwriteDrawText
    and ui.measureDWriteText and true or false

local labelSizeCache = {}
local function measureLabel(text)
  if HAS_DWRITE then
    ui.pushDWriteFont(LABEL_FONT)
    local ok, size = pcall(ui.measureDWriteText, text, LABEL_SIZE)
    ui.popDWriteFont()
    if ok and size and size.x then return size end
  end
  ui.pushFont(ui.Font.Title)
  local ok, size = pcall(ui.measureText, text)
  ui.popFont()
  if ok and size and size.x then return size end
  return vec2(#text * 9, 16)
end

local function labelSize(text)
  local size = labelSizeCache[text]
  if not size then
    size = measureLabel(text)
    labelSizeCache[text] = size
  end
  return size
end

local function drawLabel(text, pos, color)
  if HAS_DWRITE then
    ui.pushDWriteFont(LABEL_FONT)
    local ok = pcall(ui.dwriteDrawText, text, LABEL_SIZE, pos, color)
    ui.popDWriteFont()
    if ok then return end
  end
  ui.pushFont(ui.Font.Title)
  ui.drawText(text, pos, color)
  ui.popFont()
end
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

  local widestTabLabel = 0
  for _, t in ipairs(tabs) do
    widestTabLabel = math.max(widestTabLabel, labelSize(I18N.get(t.label)).x)
  end
  sidebarExpandedW = math.ceil(SIDEBAR_W + widestTabLabel + 22)

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

-- Boton de la barra: fondo con styledButton y encima icono (columna fija) + etiqueta si esta desplegada.
local function sidebarButton(id, width, selected, drawIcon, label)
  local p = ui.getCursor()
  local pressed = styledButton('##sidebar_' .. id, vec2(width, SIDEBAR_BTN_H), selected)
  local iconCenter = p + vec2((SIDEBAR_W - SIDEBAR_PAD * 2) / 2, SIDEBAR_BTN_H / 2)
  drawIcon(iconCenter)
  if label then
    local textPos = p + vec2(SIDEBAR_W - SIDEBAR_PAD, (SIDEBAR_BTN_H - labelSize(label).y) / 2)
    drawLabel(label, textPos, C.text)
  end
  return pressed
end

local function tabIconDrawer(t)
  return function(center)
    if T.icon(t.icon or {}, center, ICON_SIZE, C.text) then return end
    -- Fallback: inicial de la etiqueta.
    local initial = string.upper(string.sub(I18N.get(t.label), 1, 1))
    drawLabel(initial, center - labelSize(initial) / 2, C.text)
  end
end

local function drawSidebar(tabs, width, height, expanded)
  local btnW = width - SIDEBAR_PAD * 2
  local function place(y) ui.setCursor(vec2(SIDEBAR_PAD, y)) end
  local function select(t) core.state.tab = t.id end

  ui.drawRectFilled(vec2(0, 0), vec2(width, height),
      rgbm(SIDEBAR_R, SIDEBAR_G, SIDEBAR_B, T.bgAlpha), 16)

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
  -- ChildBg transparente: el fondo lo pinta drawSidebar (si no, la opacidad se sumaria dos veces).
  ui.pushStyleColor(ui.StyleColor.ChildBg, rgbm(0, 0, 0, 0))
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
end

-- ===== modulo: ui/tabs/admin (src/ui/tabs/admin.lua) =====
__modules['ui/tabs/admin'] = function()
-- Pestana: Admin (solo visible si esta conexion entro con /admin <contraseña>).
-- Incluye acciones de chat y cambio directo de preset validado por el servidor.
local T = import('ui/theme')
local I18N = import('i18n')
local admin = import('features/admin')
local C, sectionTitle, styledButton, smallText = T.C, T.sectionTitle, T.styledButton, T.smallText

-- [VERIFICAR] nombre de la funcion de CSP para enviar un mensaje de chat local (se asume ac.sendChatMessage).
local function sendChat(cmd)
  local ok = pcall(ac.sendChatMessage, cmd)
  if not ok then ac.log(I18N.get('admin.send_error', cmd)) end
end

return function()
  local data = admin.data
  sectionTitle(I18N.get('tab.admin'), C.accentHi)
  if data.pluginConnection == 'unavailable' or data.presetsState == 'error' then
    smallText(I18N.get('plugin.connection_warning'))
    ui.dummy(vec2(0, 4))
    if styledButton(I18N.get('plugin.retry'), vec2(-0.1, 32), true) then admin.retry() end
    return
  end

  smallText(I18N.get('admin.description'))
  ui.dummy(vec2(0, 8))

  if styledButton(I18N.get('admin.cancel'), vec2(-0.1, 32)) then
    sendChat('/mapcancel')
  end
  if styledButton(I18N.get('admin.reload'), vec2(-0.1, 32)) then
    sendChat('/mapreload')
  end

  sectionTitle(I18N.get('admin.presets'), C.accentHi)
  smallText(I18N.get('admin.presets_description'))
  ui.dummy(vec2(0, 4))

  if data.presetsState == 'loading' then
    smallText(I18N.get('admin.presets_loading'))
  elseif data.presetsState == 'error' then
    smallText(I18N.get('admin.presets_load_error', data.presetsError or ''))
    if styledButton(I18N.get('common.retry'), vec2(-0.1, 30), true) then admin.loadPresets() end
  elseif #data.presets == 0 then
    smallText(I18N.get('admin.presets_empty'))
  else
    ui.pushStyleColor(ui.StyleColor.ChildBg, rgbm(0, 0, 0, 0.18))
    ui.pushStyleVar(ui.StyleVar.ChildRounding, 9)
    ui.childWindow('acs_admin_presets', vec2(-0.1, 190), false, function()
      for _, preset in ipairs(data.presets) do
        local label = preset.name
        if preset.current then
          label = label .. ' (' .. I18N.get('admin.preset_current') .. ')'
        end
        if styledButton(label .. '##preset_' .. preset.id, vec2(-0.1, 30),
            data.selectedPreset == preset.id, preset.current) then
          data.selectedPreset = preset.id
        end
      end
    end)
    ui.popStyleVar(1)
    ui.popStyleColor(1)

    ui.dummy(vec2(0, 6))
    if styledButton(I18N.get('admin.preset_apply'), vec2(-0.1, 36), true,
        data.selectedPreset == nil) then
      admin.changePreset(data.selectedPreset)
    end
  end
end
end

-- ===== modulo: ui/tabs/car (src/ui/tabs/car.lua) =====
__modules['ui/tabs/car'] = function()
-- Pestana: cambio de coche (lista de plazas libres leida del servidor).
-- Misma estructura que la de skins: textos, recargar, lista con imagen y aplicar.
local core = import('core')
local carFeat = import('features/car')
local T = import('ui/theme')
local I18N = import('i18n')
local C, smallText, sectionTitle, styledButton = T.C, T.smallText, T.sectionTitle, T.styledButton

local cars = carFeat.data

return function()
  local state = core.state

  sectionTitle(I18N.get('car.title'), C.accentHi)
  smallText(I18N.get('car.reconnect_note'))
  smallText(I18N.get('car.current', tostring(ac.getCarID(0))), C.text)
  ui.dummy(vec2(0, 4))

  -- Sin lista: aviso y boton de recarga (como "sin skins")
  if cars.status == 'error' then
    smallText(I18N.get('plugin.connection_warning'))
    ui.dummy(vec2(0, 8))
    if styledButton(I18N.get('plugin.retry'), vec2(-0.1, 34), true) then carFeat.refresh() end
    return
  elseif cars.status == 'loading' and #cars.list == 0 then
    smallText(I18N.get('car.loading'))
    return
  elseif #cars.list == 0 then
    smallText(I18N.get('car.empty'))
    ui.dummy(vec2(0, 8))
    if styledButton(I18N.get('car.reload'), vec2(-0.1, 34), true) then carFeat.refresh() end
    return
  end

  -- Si la seleccion previa ya no existe en la lista (cambio de preset, etc.), se olvida.
  local selected
  for _, c in ipairs(cars.list) do
    if c.id == state.carID then selected = c break end
  end
  if not selected then state.carID = nil end

  smallText(I18N.get('car.count', #cars.list))
  ui.dummy(vec2(0, 4))

  if styledButton(I18N.get('car.reload'), vec2(-0.1, 28), false) then
    carFeat.refresh()
  end

  ui.dummy(vec2(0, 6))

  -- Lista con scroll para que no desborde la ventana si hay muchos coches
  ui.pushStyleColor(ui.StyleColor.ChildBg, rgbm(0, 0, 0, 0.18))
  ui.pushStyleVar(ui.StyleVar.ChildRounding, 9)
  local listHeight = math.max(120, ui.availableSpaceY() - 62)
  ui.childWindow('acs_car_list', vec2(-0.1, listHeight), false, function()
    for _, c in ipairs(cars.list) do
      local buttonPos = ui.getCursor()
      local label = '          ' .. I18N.get('car.free', c.name, c.free, c.total, c.id)
      if styledButton(label, vec2(-0.1, 48), state.carID == c.id) then
        state.carID = c.id
      end
      local preview, isBadge = carFeat.preview(c.id)
      local previewMin = buttonPos + vec2(4, 1)
      local previewMax = buttonPos + vec2(72, 47)
      if isBadge then
        -- El badge es un logo: entero y con margen.
        ui.drawImage(preview, previewMin + vec2(14, 4), previewMax - vec2(14, 4),
            rgbm.colors.white, vec2(0, 0), vec2(1, 1), ui.ImageFit.Fit)
      else
        ui.drawImage(preview or 'color::30303A', previewMin, previewMax,
            rgbm.colors.white, vec2(0.18, 0.18), vec2(0.82, 0.82), ui.ImageFit.Fit)
      end
    end
  end)
  ui.popStyleVar(1)
  ui.popStyleColor(1)

  ui.dummy(vec2(0, 8))

  local canApply = selected ~= nil and selected.free > 0
  if styledButton(I18N.get('car.apply'), vec2(-0.1, 38), true, not canApply) then
    carFeat.changeCar(state.carID)
  end

  local hint
  if selected and selected.free <= 0 then
    hint = I18N.get('car.no_slots')
  elseif not selected then
    hint = I18N.get('car.choose')
  end
  if hint then
    ui.dummy(vec2(0, 6))
    ui.pushFont(ui.Font.Small)
    ui.textWrapped(hint)
    ui.popFont()
  end
end
end

-- ===== modulo: ui/tabs/ghost (src/ui/tabs/ghost.lua) =====
__modules['ui/tabs/ghost'] = function()
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
    ui.childWindow('acs_ghost_list', vec2(-0.1, 170), false, function()
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
end

-- ===== modulo: ui/tabs/layouts (src/ui/tabs/layouts.lua) =====
__modules['ui/tabs/layouts'] = function()
-- Pestana: layouts de DriftZonesEditor publicados por el servidor.
local layoutsFeature = import('features/layouts')
local mapvote = import('features/mapvote')
local core = import('core')
local T = import('ui/theme')
local I18N = import('i18n')
local C, smallText, sectionTitle, styledButton = T.C, T.smallText, T.sectionTitle, T.styledButton
local state = layoutsFeature.data

return function()
  local current = mapvote.data.status and mapvote.data.status.current
  if current then
    sectionTitle(I18N.get('layouts.title', current.name or current.track), C.accentHi)
  else
    sectionTitle(I18N.get('tab.layouts'), C.accentHi)
    smallText(I18N.get('layouts.track_unavailable'))
    return
  end

  smallText(I18N.get('layouts.browser_hint'))
  local downloadDirectory = layoutsFeature.suggestedDownloadDirectory()
  smallText(I18N.get('layouts.browser_path', downloadDirectory), C.accentHi)

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
  local listHeight = math.max(120, ui.availableSpaceY() - 140)
  ui.childWindow('acs_layout_list', vec2(-0.1, listHeight), false, function()
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
      vec2(-0.1, 38), true, not state.selected) then
    layoutsFeature.download(state.selected)
  end

  ui.dummy(vec2(0, 6))
  if styledButton(I18N.get('layouts.reload'), vec2(-0.1, 26), false) then
    layoutsFeature.refresh(current.track)
  end
end
end

-- ===== modulo: ui/tabs/settings (src/ui/tabs/settings.lua) =====
__modules['ui/tabs/settings'] = function()
-- Pestana: ajustes del propio menu (acento, texto, transparencia, posicion).
local core   = import('core')
local T      = import('ui/theme')
local I18N   = import('i18n')
local C      = T.C

local function styledSlider(id, value, min, max, fmt)
  ui.pushStyleColor(ui.StyleColor.FrameBg,          C.surface)
  ui.pushStyleColor(ui.StyleColor.SliderGrab,        C.accent)
  ui.pushStyleColor(ui.StyleColor.SliderGrabActive,  C.accentHi)
  ui.pushStyleVar(ui.StyleVar.FrameRounding, 9)
  ui.setNextItemWidth(ui.availableSpaceX())
  local v = ui.slider(id, value, min, max, fmt)
  ui.popStyleVar(1)
  ui.popStyleColor(3)
  return v
end

-- Boton-muestra: fondo = color del preset, texto siempre blanco para legibilidad.
local WHITE = rgbm(1, 1, 1, 1)
local function swatchBtn(id, label, col, colHi, selected, w, h)
  ui.pushStyleVar(ui.StyleVar.FrameRounding, 9)
  ui.pushStyleColor(ui.StyleColor.Button,        col)
  ui.pushStyleColor(ui.StyleColor.ButtonHovered, colHi)
  ui.pushStyleColor(ui.StyleColor.ButtonActive,  colHi)
  ui.pushStyleColor(ui.StyleColor.Text,          WHITE)
  local tag = (selected and '> ' or '') .. label .. '##' .. id
  local pressed = ui.button(tag, vec2(w, h))
  ui.popStyleColor(4)
  ui.popStyleVar(1)
  return pressed
end

return function()
  local s = core.state.settings

  T.sectionTitle(I18N.get('settings.general'))
  T.smallText(I18N.get('settings.language'), C.accentHi)
  local languageWidth = (ui.availableSpaceX() - 6) / 2
  if T.styledButton('English', vec2(languageWidth, 32), s.language == 'en') then
    s.language = 'en'
    core.persistSettings()
  end
  ui.sameLine(0, 6)
  if T.styledButton('Español', vec2(languageWidth, 32), s.language == 'es') then
    s.language = 'es'
    core.persistSettings()
  end

  ui.dummy(vec2(0, 6))
  T.smallText(I18N.get('settings.toggle_key'), C.accentHi)
  if T.styledButton(I18N.get('settings.toggle_key_change',
      s.toggleKeyName), vec2(-0.1, 32), core.state.awaitingToggleKey) then
    core.state.awaitingToggleKey = true
  end
  if core.state.awaitingToggleKey then
    T.smallText(I18N.get('settings.toggle_key_prompt'))
    if T.styledButton(I18N.get('settings.toggle_key_cancel'),
        vec2(-0.1, 28), false) then
      core.state.awaitingToggleKey = false
    end
  end

  ui.dummy(vec2(0, 4))
  ui.pushStyleColor(ui.StyleColor.FrameBg,        C.surface)
  ui.pushStyleColor(ui.StyleColor.FrameBgHovered, C.surfaceHi)
  ui.pushStyleColor(ui.StyleColor.CheckMark,      C.accentHi)
  ui.pushStyleColor(ui.StyleColor.Text,           C.text)
  if ui.checkbox(I18N.get('settings.close_gas'), s.closeOnGas) then
    s.closeOnGas = not s.closeOnGas
    core.persistSettings()
  end
  ui.popStyleColor(4)

  T.sectionTitle(I18N.get('settings.appearance'))
  -- ── Color de acento ──────────────────────────────────────────────────────
  T.smallText(I18N.get('settings.accent'), C.accentHi)
  T.smallText(I18N.get('settings.accent_hint'))
  ui.dummy(vec2(0, 4))
  local n  = #T.ACCENTS
  local aw = (ui.availableSpaceX() - (n - 1) * 5) / n
  for i, a in ipairs(T.ACCENTS) do
    if i > 1 then ui.sameLine(0, 5) end
    if swatchBtn('ac'..i, I18N.get(a.name), a.c, a.hi, s.accentIndex == i, aw, 32) then
      s.accentIndex = i
      T.applyAccent(i)
      core.persistSettings()
    end
  end

  -- ── Transparencia del fondo ──────────────────────────────────────────────
  T.smallText(I18N.get('settings.transparency'), C.accentHi)
  local alpha = styledSlider('##bgalpha', s.bgAlpha, T.MIN_BG_ALPHA, 1.0, I18N.get('settings.opacity'))
  if alpha ~= s.bgAlpha then
    s.bgAlpha = alpha
    T.applyBgAlpha(alpha)
    core.persistSettings()
  end

  -- ── Posicion en pantalla (en % de la pantalla, valido para cualquier resolucion) ──
  T.smallText(I18N.get('settings.position'), C.accentHi)
  T.smallText(I18N.get('settings.position_hint'))
  ui.dummy(vec2(0, 4))
  local newX = styledSlider('##posx', s.posX * 100, 0, 100, 'X: %.0f%%')
  local newY = styledSlider('##posy', s.posY * 100, 0, 100, 'Y: %.0f%%')
  local positionChanged = false
  if newX ~= s.posX * 100 then
    s.posX = newX / 100
    positionChanged = true
  end
  if newY ~= s.posY * 100 then
    s.posY = newY / 100
    positionChanged = true
  end
  if positionChanged then core.persistSettings() end

end
end

-- ===== modulo: ui/tabs/skin (src/ui/tabs/skin.lua) =====
__modules['ui/tabs/skin'] = function()
-- Pestana: skins locales.
local skin = import('features/skin')
local T = import('ui/theme')
local I18N = import('i18n')
local C, smallText, sectionTitle, styledButton = T.C, T.smallText, T.sectionTitle, T.styledButton

return function()
  local skinState = skin.state

  sectionTitle(I18N.get('skin.title'), C.accentHi)
  smallText(I18N.get('skin.local_only'))

  local carID = ac.getCarID(0)

  -- Actualizar la lista cuando cambia el coche.
  if skinState.carID ~= carID then
    skin.refresh()
  end

  smallText(I18N.get('skin.car', tostring(carID)), C.text)
  ui.dummy(vec2(0, 4))

  -- Sin skins: aviso y boton de recarga
  if #skinState.skins == 0 then
    smallText(I18N.get('skin.not_found'))
    smallText(I18N.get('skin.check_path'))
    ui.dummy(vec2(0, 8))
    if styledButton(I18N.get('skin.reload'), vec2(-0.1, 34), true) then
      skin.refresh()
    end
    return
  end

  smallText(I18N.get('skin.count', #skinState.skins))
  ui.dummy(vec2(0, 4))

  if styledButton(I18N.get('skin.reload_list'), vec2(-0.1, 28), false) then
    skin.refresh()
  end

  ui.dummy(vec2(0, 6))

  -- Lista con scroll para que no desborde la ventana si hay muchas skins
  ui.pushStyleColor(ui.StyleColor.ChildBg, rgbm(0, 0, 0, 0.18))
  ui.pushStyleVar(ui.StyleVar.ChildRounding, 9)
  local listHeight = math.max(120, ui.availableSpaceY() - 62)
  ui.childWindow('acs_skin_list', vec2(-0.1, listHeight), false, function()
    for i, s in ipairs(skinState.skins) do
      local buttonPos = ui.getCursor()
      local label = '          ' .. s.label .. '##skin_' .. s.id
      if styledButton(label, vec2(-0.1, 48), skinState.selected == i) then
        skinState.selected = i
      end
      local previewMin = buttonPos + vec2(4, 1)
      local previewMax = buttonPos + vec2(72, 47)
      ui.drawImage(s.preview or 'color::30303A', previewMin, previewMax,
          rgbm.colors.white, vec2(0.18, 0.18), vec2(0.82, 0.82), ui.ImageFit.Fit)
    end
  end)
  ui.popStyleVar(1)
  ui.popStyleColor(1)

  ui.dummy(vec2(0, 8))

  if styledButton(I18N.get('skin.apply'), vec2(-0.1, 38), true) then
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
local I18N = import('i18n')
local C, smallText, sectionTitle, styledButton = T.C, T.smallText, T.sectionTitle, T.styledButton

return function()
  local returnButton = teleport.returnButton

  sectionTitle(I18N.get('teleport.title'), C.accentHi)
  if styledButton(I18N.get('teleport.save'), vec2(-0.1, 34), false) then teleport.savePoint() end
  if styledButton(I18N.get('teleport.return'), vec2(-0.1, 34), false) then teleport.teleportToPoint() end
  if styledButton(I18N.get('teleport.pits'), vec2(-0.1, 34), false) then teleport.teleportToPits() end

  sectionTitle(I18N.get('teleport.button_title'), C.accentHi)
  smallText(I18N.get('teleport.assign_hint'))
  ui.dummy(vec2(0, 4))
  returnButton:control(vec2(ui.availableSpaceX(), 30))
  ui.dummy(vec2(0, 2))
  if returnButton:configured() then
    smallText(I18N.get('teleport.assigned', tostring(returnButton:boundTo())), C.accentHi)
  else
    smallText(I18N.get('teleport.unassigned'))
  end
end
end

-- ===== modulo: ui/tabs/track (src/ui/tabs/track.lua) =====
__modules['ui/tabs/track'] = function()
-- Pestana: votacion de mapa.
local mv = import('features/mapvote')
local T = import('ui/theme')
local I18N = import('i18n')
local C, smallText, sectionTitle, styledButton, drawProgress =
  T.C, T.smallText, T.sectionTitle, T.styledButton, T.drawProgress

local mapvote = mv.data

return function()
  if mapvote.tracksState == 'error' or mapvote.statusError then
    sectionTitle(I18N.get('tab.track'), C.accentHi)
    smallText(I18N.get('plugin.connection_warning'))
    ui.dummy(vec2(0, 4))
    if styledButton(I18N.get('plugin.retry'), vec2(-0.1, 32), true) then mv.retry() end
    return
  end

  local st = mapvote.status

  sectionTitle(I18N.get('track.current'), C.accentHi)
  if st and st.current then
    ui.pushFont(ui.Font.Small)
    ui.textWrapped(st.current.name)
    ui.popFont()
  else
    smallText(I18N.get('common.loading'))
  end

  -- Cambio aprobado: cuenta atras
  if st and st.changing then
    sectionTitle(I18N.get('track.changing'), C.accentHi)
    smallText(I18N.get('track.restart', st.changeInSeconds or 0), C.accentHi)
    return
  end

  -- Votacion en curso
  if st and st.active and st.proposal then
    sectionTitle(I18N.get('track.vote_active'), C.accentHi)
    ui.pushFont(ui.Font.Small)
    ui.textWrapped(st.proposal.name)
    ui.popFont()
    smallText(I18N.get('track.proposer', tostring(st.proposer or '?')))
    smallText(I18N.get('track.votes', st.yes, st.needed, st.connectedAtStart))
    smallText(I18N.get('track.time_left', st.secondsLeft))
    ui.dummy(vec2(0, 4))
    drawProgress(st.yes / math.max(1, st.needed))

    local voted = mapvote.myVoteFor == st.proposal.id
    local w = (ui.availableSpaceX() - 6) / 2
    if styledButton(I18N.get('track.yes'), vec2(w, 36), voted and mapvote.myVote == true) then mv.castVote(true) end
    ui.sameLine(0, 6)
    if styledButton(I18N.get('track.no'), vec2(w, 36), voted and mapvote.myVote == false) then mv.castVote(false) end
    return
  end

  -- Sin votacion: elegir mapa y proponer
  local cooldown = st and st.cooldownLeft or 0
  sectionTitle(I18N.get('track.propose_title'), C.accentHi)
  if cooldown > 0 then
    smallText(I18N.get('track.cooldown', cooldown), C.accentHi)
  end

  if mapvote.tracksState == 'loading' then
    smallText(I18N.get('track.loading_list'))
  end

  ui.setNextItemWidth(ui.availableSpaceX())
  mapvote.filter = ui.inputText('##mapfilter', mapvote.filter)
  if mapvote.filter == '' then smallText(I18N.get('track.filter_hint')) end
  ui.dummy(vec2(0, 4))

  local needle = string.lower(mapvote.filter or '')
  ui.pushStyleColor(ui.StyleColor.ChildBg, rgbm(0, 0, 0, 0.18))
  ui.pushStyleVar(ui.StyleVar.ChildRounding, 9)
  local listHeight = math.max(120, ui.availableSpaceY() - 160)
  ui.childWindow('acs_map_list', vec2(-0.1, listHeight), false, function()
    local shown = 0
    for _, e in ipairs(mapvote.tracks) do
      if needle == '' or string.find(string.lower(e.name), needle, 1, true) then
        shown = shown + 1
        if shown > 150 then
          smallText(I18N.get('track.more_results'))
          break
        end
        if styledButton(e.name .. '##map_' .. e.id, vec2(-0.1, 28), mapvote.selected == e.id) then
          mapvote.selected = e.id
        end
      end
    end
    if shown == 0 then smallText(I18N.get('track.no_results')) end
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

  if styledButton(I18N.get('track.propose'), vec2(-0.1, 38), true, not canPropose) then mv.propose(entry) end
  if isCurrent then smallText(I18N.get('track.already_current')) end
  ui.dummy(vec2(0, 4))
  if styledButton(I18N.get('track.reload'), vec2(-0.1, 26), false) then mv.loadTracks() end
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

-- RGB base del fondo (sin alpha) para poder recalcular al cambiar transparencia.
local BG_R, BG_G, BG_B = 0.045, 0.045, 0.070

-- Presets de color de acento. Mismo estilo que el verde original: tono oscuro
-- para botones/bordes (c) y version viva para hover y detalles (hi).
M.ACCENTS = {
  { name = 'color.green',  c = rgbm(0.120, 0.500, 0.280, 0.80), hi = rgbm(0.250, 0.950, 0.480, 1.00) },
  { name = 'color.purple', c = rgbm(0.360, 0.200, 0.620, 0.80), hi = rgbm(0.620, 0.400, 1.000, 1.00) },
  { name = 'color.orange', c = rgbm(0.620, 0.320, 0.100, 0.80), hi = rgbm(1.000, 0.600, 0.250, 1.00) },
  { name = 'color.blue',   c = rgbm(0.080, 0.400, 0.500, 0.80), hi = rgbm(0.250, 0.850, 0.950, 1.00) },
  { name = 'color.red',    c = rgbm(0.600, 0.100, 0.100, 0.80), hi = rgbm(1.000, 0.200, 0.200, 1.00) },
}

function M.applyAccent(index)
  local a = M.ACCENTS[index] or M.ACCENTS[1]
  C.accent, C.accentHi = a.c, a.hi
end

-- Opacidad minima del fondo (tambien es el minimo del slider de Ajustes).
M.MIN_BG_ALPHA = 0.15
M.bgAlpha = 1

function M.applyBgAlpha(alpha)
  M.bgAlpha = math.max(M.MIN_BG_ALPHA, math.min(1.0, alpha))
  C.bg = rgbm(BG_R, BG_G, BG_B, M.bgAlpha)
end

-- Ancho en pixeles de un texto con la fuente por defecto (con aproximacion si no hay measureText).
function M.textWidth(text)
  local ok, size = pcall(ui.measureText, text)
  if ok and size and size.x then return size.x end
  return #text * 8
end

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
  ui.pushStyleColor(ui.StyleColor.Text, color or C.dim)
  ui.textWrapped(text)
  ui.popStyleColor(1)
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

-- Dibuja el primer icono de CSP que exista de la lista de nombres (ui.Icons.<nombre>)
-- centrado en 'center'. Devuelve false si ninguno existe en este CSP (para usar un fallback).
local iconCache = {}
function M.icon(candidates, center, size, color)
  local key = table.concat(candidates, ',')
  local id = iconCache[key]
  if id == nil then
    id = false
    if ui.Icons and ui.drawIcon then
      for _, name in ipairs(candidates) do
        local ok, v = pcall(function() return ui.Icons[name] end)
        if ok and v ~= nil then id = v break end
      end
    end
    iconCache[key] = id
  end
  if not id then return false end
  local half = vec2(size / 2, size / 2)
  local ok = pcall(ui.drawIcon, id, center - half, center + half, color)
  if not ok then iconCache[key] = false end
  return ok
end

function M.sectionTitle(text, color)
  ui.dummy(vec2(0, 4))
  M.smallText(string.upper(text), color or C.accentHi)
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

-- ===== modulo: ui/vote_window (src/ui/vote_window.lua) =====
__modules['ui/vote_window'] = function()
local mv = import('features/mapvote')
local T = import('ui/theme')
local I18N = import('i18n')
local C, smallText, sectionTitle, styledButton, drawProgress =
  T.C, T.smallText, T.sectionTitle, T.styledButton, T.drawProgress

local M = {}

local function screenSize()
  local ok, info = pcall(ac.getUI)
  if ok and info and info.windowSize and info.windowSize.x > 0 then
    return info.windowSize.x, info.windowSize.y
  end
  return 1920, 1080
end

function M.draw()
  local status = mv.data.status
  if not status or not status.active or not status.proposal then return end

  local screenWidth = screenSize()
  local width, height, margin = 370, 190, 32
  local position = vec2(math.max(margin, screenWidth - width - margin), margin)

  ui.pushStyleColor(ui.StyleColor.WindowBg, C.bg)
  ui.pushStyleColor(ui.StyleColor.Border, C.accent)
  ui.pushStyleVar(ui.StyleVar.WindowRounding, 12)
  ui.pushStyleVar(ui.StyleVar.WindowPadding, vec2(14, 10))
  ui.toolWindow('acs_menu/track_vote', position, vec2(width, height), false, true, function()
    sectionTitle(I18N.get('track.vote_active'), C.accentHi)
    ui.pushFont(ui.Font.Small)
    ui.textWrapped(status.proposal.name)
    ui.popFont()
    smallText(I18N.get('track.proposer', tostring(status.proposer or '?')))
    smallText(I18N.get('track.vote_counts', status.yes, status.no, status.needed))
    smallText(I18N.get('track.time_left', status.secondsLeft))
    drawProgress(status.yes / math.max(1, status.needed))

    local voted = mv.data.myVoteFor == status.proposal.id
    local buttonWidth = (ui.availableSpaceX() - 6) / 2
    if styledButton(I18N.get('track.yes'), vec2(buttonWidth, 32),
        voted and mv.data.myVote == true) then
      mv.castVote(true)
    end
    ui.sameLine(0, 6)
    if styledButton(I18N.get('track.no'), vec2(buttonWidth, 32),
        voted and mv.data.myVote == false) then
      mv.castVote(false)
    end
  end)
  ui.popStyleVar(2)
  ui.popStyleColor(2)
end

return M
end

-- ===== punto de entrada (src/main.lua) =====
__modules['__main'] = function()
-- Punto de entrada: engancha los callbacks de CSP. Aqui no hay logica propia.
local core = import('core')
local I18N = import('i18n')
local teleport = import('features/teleport')
local mapvote = import('features/mapvote')
local car = import('features/car')
local admin = import('features/admin')
local layouts = import('features/layouts')
local ghost = import('features/ghost')
local menu = import('ui/menu')
local voteWindow = import('ui/vote_window')
local ghostHud = import('ui/ghost_hud')
local ghostConfirm = import('ui/ghost_confirm')

function script.update(dt)
  local sim = ac.getSim()
  if sim.isReplayActive or sim.isPaused or sim.isInMainMenu then return end
  -- Cierre automatico al acelerar (se activa/desactiva en la pestana Ajustes).
  if core.state.open and core.state.settings.closeOnGas then
    local car = ac.getCar(0)
    if car and car.gas > 0 then core.state.open = false end
  end
  teleport.update(dt)
  mapvote.update(dt, core.state.open and core.state.tab == 'track')
  car.update(dt, core.state.open and core.state.tab == 'car')
  admin.update(dt, core.state.open and core.state.tab == 'admin')
  layouts.update(dt, core.state.open and core.state.tab == 'layouts')
  ghost.update(dt, core.state.open and core.state.tab == 'ghost')
end

function script.drawUI(dt)
  local waitingForToggleKey = core.state.awaitingToggleKey
  if waitingForToggleKey and core.state.open then
    local keyName = core.pressedToggleKeyName()
    if keyName then
      core.state.settings.toggleKeyName = keyName
      core.state.awaitingToggleKey = false
      core.persistSettings()
      core.notify(I18N.get('settings.toggle_key_saved', keyName))
    end
  elseif waitingForToggleKey then
    core.state.awaitingToggleKey = false
  elseif ui.keyboardButtonPressed(core.toggleKeyIndex(), false) then
    core.state.open = not core.state.open
  end
  if core.state.open then menu.drawWindow() end
  voteWindow.draw()
  ghostHud.draw()
  ghostConfirm.draw()
end
end
import('__main')
