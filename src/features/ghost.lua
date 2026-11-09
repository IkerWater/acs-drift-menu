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
