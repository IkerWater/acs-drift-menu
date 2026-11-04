-- ACS Drift by Water - script ONLINE para CSP
-- GENERADO EL (2026-11-04 14:01).
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

-- ===== modulo: config (src/config.lua) =====
__modules['config'] = function()
-- Configuracion editable del menu. Solo datos, sin logica.
return {
  version = 'v0.5',
  toggleKey = ui.KeyIndex.M,

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

local storedSettings = ac.storage({
  language = 'en',
  accentIndex = 1,
  bgAlpha = 0.15,
  closeOnGas = false,
  posX = 0.5,
  posY = 0.5,
  layoutDownloadPath = '',
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
  return math.max(0.01, math.min(1, value))
end

local language = storedSettings.language
if language ~= 'en' and language ~= 'es' then language = 'en' end

local accentIndex = storedSettings.accentIndex
if type(accentIndex) ~= 'number' or accentIndex ~= accentIndex then accentIndex = 1 end
accentIndex = math.max(1, math.min(5, math.floor(accentIndex)))

local closeOnGas = storedSettings.closeOnGas
if type(closeOnGas) ~= 'boolean' then closeOnGas = false end

local layoutDownloadPath = storedSettings.layoutDownloadPath
if type(layoutDownloadPath) ~= 'string' then layoutDownloadPath = '' end

M.state = {
  open = false,
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
    layoutDownloadPath = layoutDownloadPath,
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
  storedSettings.layoutDownloadPath = settings.layoutDownloadPath
end

M.persistSettings()

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

function M.sendChatCommand(cmd, sentMessage)
  ac.sendChatMessage(cmd)
  M.notify(sentMessage or ('Enviado: ' .. cmd))
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
  downloading = false,
  requestId = 0,
  downloadId = 0,
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
  local appsLua = ac.getFolder(ac.FolderID.ACAppsLua)
  if type(appsLua) ~= 'string' or appsLua == '' then return nil end

  return appsLua .. '/DriftZonesEditor/tracks'
end

function M.normalizeDownloadDirectory(path)
  if type(path) ~= 'string' then return nil end
  path = path:match('^%s*(.-)%s*$')
  if path == '' then return nil end

  path = path:gsub('\\', '/')
  while #path > 3 and path:sub(-1) == '/' do
    path = path:sub(1, -2)
  end
  return path
end

function M.refresh(track)
  state.requestId = state.requestId + 1
  state.downloadId = state.downloadId + 1
  state.downloading = false
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
  if not validFileName(fileName) or state.downloading then return end
  local tracksDirectory = M.normalizeDownloadDirectory(
      core.state.settings.layoutDownloadPath)
  if not tracksDirectory then
    core.notify(I18N.get('layouts.path_required'))
    return
  end

  local available = false
  for _, layout in ipairs(state.layouts) do
    if layout.name == fileName then available = true break end
  end
  if not available or not state.track then return end

  state.downloading = true
  state.downloadId = state.downloadId + 1
  local downloadId = state.downloadId
  local track = state.track
  local downloadDirectory = tracksDirectory
  local path = '/layouts/' .. encodePathSegment(track) .. '/' .. encodePathSegment(fileName)
  net.getText(path, function(content, err)
    if downloadId ~= state.downloadId then return end
    if not content then
      state.downloading = false
      core.notify(I18N.get('layouts.download_error', tostring(err)))
      return
    end

    local ok, saveError = pcall(function()
      local saved, err = io.save(downloadDirectory .. '/' .. fileName, content)
      if saved == false then
        error(tostring(err or 'no se pudo guardar el archivo'))
      end
    end)
    state.downloading = false
    if ok then
      core.notify(I18N.get('layouts.downloaded', fileName))
    else
      core.notify(I18N.get('layouts.download_error', tostring(saveError)))
    end
  end)
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
    ['menu.footer'] = '[M] to close | ACS Drift by Water',
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
    ['car.reload'] = 'Reload list',
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
    ['layouts.path_required'] = 'Set the download folder in Settings before downloading.',
    ['layouts.track_unavailable'] = 'Could not determine the current track from the server.',
    ['layouts.loading'] = 'Loading layouts for this track...',
    ['layouts.load_error'] = 'Could not load layouts: %s',
    ['layouts.load_error_short'] = 'Could not load the layout list.',
    ['layouts.empty'] = 'No layouts are available for this track.',
    ['layouts.download'] = 'DOWNLOAD LAYOUT',
    ['layouts.downloading'] = 'Downloading layout...',
    ['layouts.downloaded'] = 'Downloaded %s to DriftZonesEditor tracks.',
    ['layouts.download_error'] = 'Could not download layout: %s',
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
    ['settings.language'] = 'Language',
    ['settings.layout_path'] = 'Layout download folder',
    ['settings.layout_path_hint'] = 'Enter the full path to the folder. Copy it from File Explorer; the folder must already exist.',
    ['settings.layout_path_example'] = 'Recommended for DriftZonesEditor: %s',
    ['settings.layout_path_save'] = 'SAVE DOWNLOAD FOLDER',
    ['settings.layout_path_saved'] = 'Download folder saved. Make sure the folder already exists.',
    ['settings.layout_path_invalid'] = 'Enter a folder path before saving.',
    ['settings.accent'] = 'Accent color',
    ['settings.accent_hint'] = 'Active buttons, borders and menu highlights.',
    ['settings.transparency'] = 'Background transparency',
    ['settings.opacity'] = 'Opacity: %.2f',
    ['settings.position'] = 'On-screen position',
    ['settings.position_hint'] = '0% = left/top edge, 100% = right/bottom edge.',
    ['settings.behavior'] = 'Behavior',
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
    ['menu.footer'] = '[M] para cerrar | ACS Drift by Water',
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
    ['car.reload'] = 'Recargar lista',
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
    ['layouts.path_required'] = 'Configura la carpeta de descarga en Ajustes antes de descargar.',
    ['layouts.track_unavailable'] = 'No se pudo determinar el circuito actual desde el servidor.',
    ['layouts.loading'] = 'Cargando layouts para este circuito...',
    ['layouts.load_error'] = 'No se pudieron cargar los layouts: %s',
    ['layouts.load_error_short'] = 'No se pudo cargar la lista de layouts.',
    ['layouts.empty'] = 'No hay layouts disponibles para este circuito.',
    ['layouts.download'] = 'DESCARGAR LAYOUT',
    ['layouts.downloading'] = 'Descargando layout...',
    ['layouts.downloaded'] = 'Layout %s descargado en la carpeta de DriftZonesEditor.',
    ['layouts.download_error'] = 'No se pudo descargar el layout: %s',
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
    ['settings.language'] = 'Idioma',
    ['settings.layout_path'] = 'Carpeta para descargar layouts',
    ['settings.layout_path_hint'] = 'Escribe la ruta completa de la carpeta. Cópiala desde el Explorador; la carpeta debe existir.',
    ['settings.layout_path_example'] = 'Ruta recomendada para DriftZonesEditor: %s',
    ['settings.layout_path_save'] = 'GUARDAR CARPETA DE DESCARGA',
    ['settings.layout_path_saved'] = 'Carpeta guardada. Comprueba que la carpeta ya exista.',
    ['settings.layout_path_invalid'] = 'Escribe una ruta de carpeta antes de guardarla.',
    ['settings.accent'] = 'Color de acento',
    ['settings.accent_hint'] = 'Botones activos, bordes y resaltados del menu.',
    ['settings.transparency'] = 'Transparencia del fondo',
    ['settings.opacity'] = 'Opacidad: %.2f',
    ['settings.position'] = 'Posicion en pantalla',
    ['settings.position_hint'] = '0% = pegado al borde izquierdo/superior, 100% = al derecho/inferior.',
    ['settings.behavior'] = 'Comportamiento',
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

-- [VERIFICAR] firma de web.get y forma del callback (err, response) en tu version de CSP.
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

function M.getText(path, callback)
  local ok, err = pcall(function()
    web.get(M.serverBaseUrl() .. path, function(e, response)
      if e or not response or response.status ~= 200 then
        return callback(nil, tostring(e or (response and response.status) or 'sin respuesta'))
      end
      if type(response.body) ~= 'string' then
        return callback(nil, 'respuesta invalida')
      end
      callback(response.body)
    end)
  end)
  if not ok then callback(nil, tostring(err)) end
end

return M
end

-- ===== modulo: ui/menu (src/ui/menu.lua) =====
__modules['ui/menu'] = function()
-- Ventana principal: cabecera, pestanas, barra de estado y pie.
-- Para anadir una pestana: crea ui/tabs/<nombre>.lua y anadela a TABS.
local core = import('core')
local CONFIG = import('config')
local admin = import('features/admin')
local T = import('ui/theme')
local I18N = import('i18n')
local C, accentLine, styledButton = T.C, T.accentLine, T.styledButton
T.applyBgAlpha(core.state.settings.bgAlpha)
T.applyAccent(core.state.settings.accentIndex)

-- visible es opcional; sin ella la pestana siempre se muestra.
local TABS = {
  { id = 'car',      label = 'tab.car',      height = 440, draw = import('ui/tabs/car')      },
  { id = 'skin',     label = 'tab.skin',     height = 580, draw = import('ui/tabs/skin')     },
  { id = 'track',    label = 'tab.track',    height = 800, draw = import('ui/tabs/track')    },
  { id = 'layouts',  label = 'tab.layouts',  height = 580, draw = import('ui/tabs/layouts')  },
  { id = 'teleport', label = 'tab.teleport', height = 480, draw = import('ui/tabs/teleport') },
  { id = 'settings',  label = 'tab.settings',  height = 660, draw = import('ui/tabs/settings') },
  { id = 'admin',    label = 'tab.admin',    height = 620, draw = import('ui/tabs/admin'),
    visible = function()
      return admin.data.isAdmin or admin.data.pluginConnection == 'unavailable'
    end },
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

local MAX_WIN_H    = 900
local MIN_WIN_H    = 560
local MIN_W        = 420   -- ancho minimo aunque todo quepa en menos
local PAD_X        = 16    -- WindowPadding horizontal (a cada lado)
local BTN_PAD      = 28    -- margen interior extra de cada boton respecto a su texto
local GAP_TABS     = 6
local GAP_SWATCH   = 5

local function footerText()
  return I18N.get('menu.footer')
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
  ui.pushStyleColor(ui.StyleColor.Text, C.accentHi)
  ui.textAligned(footerText(), vec2(0.5, 0.5), vec2(ui.availableSpaceX(), 32))
  ui.popStyleColor(1)
end

function M.drawWindow()
  local s = core.state.settings
  local tabs = visibleTabs()
  local w = requiredWidth(tabs)
  local h = requiredHeight(tabs)
  local sw, sh = screenSize()
  -- % del espacio libre: 0% pega la ventana al borde, 100% al borde opuesto (nunca se sale).
  local maxX, maxY = math.max(0, sw - w), math.max(0, sh - h)
  local x = s.posX * maxX
  local y = s.posY * maxY

  local mouse = ui.mousePos()
  local overHeader = mouse.x >= x and mouse.x <= x + w
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
  ui.pushStyleVar(ui.StyleVar.WindowPadding, vec2(16, 12))
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
local core = import('core')
local carFeat = import('features/car')
local T = import('ui/theme')
local I18N = import('i18n')
local C, smallText, sectionTitle, styledButton = T.C, T.smallText, T.sectionTitle, T.styledButton

local cars = carFeat.data

return function()
  local state = core.state

  sectionTitle(I18N.get('car.title'), C.accentHi)

  if cars.status == 'error' then
    smallText(I18N.get('plugin.connection_warning'))
    ui.dummy(vec2(0, 4))
    if styledButton(I18N.get('plugin.retry'), vec2(-0.1, 32), true) then carFeat.refresh() end
    return
  elseif cars.status == 'loading' and #cars.list == 0 then
    smallText(I18N.get('car.loading'))
    return
  elseif #cars.list == 0 then
    smallText(I18N.get('car.empty'))
    return
  end

  -- Si la seleccion previa ya no existe en la lista (cambio de preset, etc.), se olvida.
  local selected
  for _, c in ipairs(cars.list) do
    if c.id == state.carID then selected = c break end
  end
  if not selected then state.carID = nil end

  ui.pushStyleColor(ui.StyleColor.ChildBg, rgbm(0, 0, 0, 0.18))
  ui.pushStyleVar(ui.StyleVar.ChildRounding, 9)
  ui.childWindow('acs_car_list', vec2(-0.1, 220), false, function()
    for _, c in ipairs(cars.list) do
      local label = I18N.get('car.free', c.name, c.free, c.total, c.id)
      if styledButton(label, vec2(-0.1, 32), state.carID == c.id) then
        state.carID = c.id
      end
    end
  end)
  ui.popStyleVar(1)
  ui.popStyleColor(1)

  ui.dummy(vec2(0, 6))
  if styledButton(I18N.get('car.reload'), vec2(-0.1, 26), false) then carFeat.refresh() end
  ui.dummy(vec2(0, 8))

  local canApply = selected ~= nil and selected.free > 0
  if styledButton(I18N.get('car.apply'), vec2(-0.1, 38), true, not canApply) then
    carFeat.changeCar(state.carID)
  end
  if selected and selected.free <= 0 then
    smallText(I18N.get('car.no_slots'))
  elseif not selected then
    smallText(I18N.get('car.choose'))
  end
end
end

-- ===== modulo: ui/tabs/layouts (src/ui/tabs/layouts.lua) =====
__modules['ui/tabs/layouts'] = function()
-- Pestana: layouts de DriftZonesEditor publicados por el servidor.
local layoutsFeature = import('features/layouts')
local mapvote = import('features/mapvote')
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
end

-- ===== modulo: ui/tabs/settings (src/ui/tabs/settings.lua) =====
__modules['ui/tabs/settings'] = function()
-- Pestana: ajustes del propio menu (acento, texto, transparencia, posicion).
-- Los ajustes personales se persisten en el cliente, incluida la ruta de layouts.
local core   = import('core')
local layoutsFeature = import('features/layouts')
local T      = import('ui/theme')
local I18N   = import('i18n')
local C      = T.C
local layoutPathDraft = core.state.settings.layoutDownloadPath
local layoutPathMessage
local layoutPathMessageIsError

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

  T.sectionTitle(I18N.get('settings.language'))
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

  -- ── Color de acento ──────────────────────────────────────────────────────
  T.sectionTitle(I18N.get('settings.accent'))
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
  T.sectionTitle(I18N.get('settings.transparency'))
  local alpha = styledSlider('##bgalpha', s.bgAlpha, 0.01, 1.0, I18N.get('settings.opacity'))
  if alpha ~= s.bgAlpha then
    s.bgAlpha = alpha
    T.applyBgAlpha(alpha)
    core.persistSettings()
  end

  -- ── Posicion en pantalla (en % de la pantalla, valido para cualquier resolucion) ──
  T.sectionTitle(I18N.get('settings.position'))
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

  T.sectionTitle(I18N.get('settings.layout_path'))
  T.smallText(I18N.get('settings.layout_path_hint'))
  local suggestedPath = layoutsFeature.suggestedDownloadDirectory()
  if suggestedPath then
    T.smallText(I18N.get('settings.layout_path_example', suggestedPath))
  end
  ui.setNextItemWidth(ui.availableSpaceX())
  local editedPath = ui.inputText('##layoutdownloadpath', layoutPathDraft)
  if editedPath ~= layoutPathDraft then
    layoutPathDraft = editedPath
    layoutPathMessage = nil
  end
  if T.styledButton(I18N.get('settings.layout_path_save'),
      vec2(-0.1, 32), false) then
    local validPath = layoutsFeature.normalizeDownloadDirectory(layoutPathDraft)
    if validPath then
      s.layoutDownloadPath = validPath
      layoutPathDraft = validPath
      core.persistSettings()
      layoutPathMessage = I18N.get('settings.layout_path_saved')
      layoutPathMessageIsError = false
    else
      layoutPathMessage = I18N.get('settings.layout_path_invalid')
      layoutPathMessageIsError = true
    end
  end
  if layoutPathMessage then
    T.smallText(layoutPathMessage, layoutPathMessageIsError and C.accentHi or C.dim)
  end

  -- ── Comportamiento ────────────────────────────────────────────────────────
  T.sectionTitle(I18N.get('settings.behavior'))
  ui.pushStyleColor(ui.StyleColor.FrameBg,        C.surface)
  ui.pushStyleColor(ui.StyleColor.FrameBgHovered, C.surfaceHi)
  ui.pushStyleColor(ui.StyleColor.CheckMark,      C.accentHi)
  ui.pushStyleColor(ui.StyleColor.Text,           C.text)
  if ui.checkbox(I18N.get('settings.close_gas'), s.closeOnGas) then
    s.closeOnGas = not s.closeOnGas
    core.persistSettings()
  end
  ui.popStyleColor(4)
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
  ui.childWindow('acs_skin_list', vec2(-0.1, 200), false, function()
    for i, s in ipairs(skinState.skins) do
      local buttonPos = ui.getCursor()
      local label = '       ' .. s.label .. '##skin_' .. s.id
      if styledButton(label, vec2(-0.1, 48), skinState.selected == i) then
        skinState.selected = i
      end
      local previewMin = buttonPos + vec2(5, 2)
      local previewMax = buttonPos + vec2(63, 46)
      ui.drawImage(s.preview or 'color::30303A', previewMin, previewMax,
          rgbm.colors.white, vec2(0.08, 0.08), vec2(0.92, 0.92), ui.ImageFit.Fit)
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
  ui.childWindow('acs_map_list', vec2(-0.1, 230), false, function()
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

function M.applyBgAlpha(alpha)
  C.bg = rgbm(BG_R, BG_G, BG_B, math.max(0.01, math.min(1.0, alpha)))
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
  ui.textColored(text, color or C.dim)
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
local CONFIG = import('config')
local core = import('core')
local teleport = import('features/teleport')
local mapvote = import('features/mapvote')
local car = import('features/car')
local admin = import('features/admin')
local layouts = import('features/layouts')
local menu = import('ui/menu')
local voteWindow = import('ui/vote_window')

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
end

function script.drawUI(dt)
  if ui.keyboardButtonPressed(CONFIG.toggleKey, false) then core.state.open = not core.state.open end
  if core.state.open then menu.drawWindow() end
  voteWindow.draw()
end
end
import('__main')
