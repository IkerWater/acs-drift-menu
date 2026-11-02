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
end)

local pollTimer = 0

function M.request()
  requestEvent({ request = 0 })
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
end

M.request() -- primer chequeo nada mas cargar el script

return M
