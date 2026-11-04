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
