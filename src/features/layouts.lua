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
  editorInstalled = nil,
  requestId = 0,
  downloadId = 0,
}
M.data = state
local wasActive = false

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

local function getTracksDirectory()
  local root = ac.getFolder(ac.FolderID.Root)
  if type(root) ~= 'string' or root == '' then return nil end

  local editorDirectory = root .. '/apps/lua/DriftZonesEditor'
  local tracksDirectory = editorDirectory .. '/tracks'
  if not io.fileExists(editorDirectory .. '/DriftZonesEditor.lua')
      or not io.dirExists(tracksDirectory) then
    return nil
  end
  return tracksDirectory
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
  if not active then
    wasActive = false
    return
  end
  if not wasActive then
    state.editorInstalled = getTracksDirectory() ~= nil
    wasActive = true
  end

  local status = mapvote.data.status
  local track = status and status.current and status.current.track or nil
  if track ~= state.track then M.refresh(track) end
end

function M.download(fileName)
  if not validFileName(fileName) or state.downloading then return end
  local tracksDirectory = getTracksDirectory()
  state.editorInstalled = tracksDirectory ~= nil
  if not tracksDirectory then
    core.notify(I18N.get('layouts.editor_required'))
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
  local path = '/layouts/' .. encodePathSegment(track) .. '/' .. encodePathSegment(fileName)
  net.getText(path, function(content, err)
    if downloadId ~= state.downloadId then return end
    if not content then
      state.downloading = false
      core.notify(I18N.get('layouts.download_error', tostring(err)))
      return
    end

    local ok, saveError = pcall(function()
      local directory = getTracksDirectory()
      if not directory then
        state.editorInstalled = false
        error(I18N.get('layouts.editor_required'))
      end
      io.save(directory .. '/' .. fileName, content)
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
