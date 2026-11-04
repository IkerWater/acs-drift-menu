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

  return appsLua .. '\\DriftZonesEditor\\tracks'
end

function M.normalizeDownloadDirectory(path)
  if type(path) ~= 'string' then return nil end
  path = path:match('^%s*(.-)%s*$')
  if path == '' then return nil end
  local quote = path:sub(1, 1)
  if (quote == '"' or quote == "'") and path:sub(-1) == quote then
    path = path:sub(2, -2):match('^%s*(.-)%s*$')
  end
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

local function replaceDownloadedFile(directory, fileName, content, downloadId, callback)
  local suffix = tostring(os.time()) .. '_' .. tostring(downloadId)
  local temporary, backup
  local attempt = 0
  repeat
    attempt = attempt + 1
    temporary = directory .. '/.acs_drift_' .. suffix .. '_' .. attempt .. '.tmp'
    backup = directory .. '/.acs_drift_' .. suffix .. '_' .. attempt .. '.bak'
  until not io.fileExists(temporary) and not io.fileExists(backup)

  local destination = directory .. '/' .. fileName
  io.saveAsync(temporary, content, function(saveError)
    if saveError then
      if io.fileExists(temporary) then io.deleteFile(temporary) end
      callback(tostring(saveError) .. ' [' .. temporary .. ']')
      return
    end

    local backupCreated = false
    local ok, replaceError = pcall(function()
      local hadExistingFile = io.fileExists(destination)
      if hadExistingFile then
        if not io.move(destination, backup) then
          error('no se pudo conservar el archivo existente: ' .. destination)
        end
        backupCreated = true
      end

      if not io.move(temporary, destination) then
        error('no se pudo reemplazar el archivo: ' .. destination)
      end

      if backupCreated and not io.deleteFile(backup) then
        ac.log('[ACS Menu] No se pudo borrar el respaldo temporal: ' .. backup)
      end
    end)

    if not ok then
      if backupCreated and not io.fileExists(destination)
          and not io.move(backup, destination) then
        replaceError = tostring(replaceError)
            .. '; no se pudo restaurar el archivo original: ' .. backup
      end
      if io.fileExists(temporary) then io.deleteFile(temporary) end
      callback(tostring(replaceError))
    else
      callback(nil)
    end
  end)
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

    local destination = downloadDirectory .. '/' .. fileName
    local started, startError = pcall(function()
      replaceDownloadedFile(downloadDirectory, fileName, content, downloadId,
          function(saveError)
        if downloadId ~= state.downloadId then return end
        state.downloading = false
        if saveError then
          core.notify(I18N.get('layouts.download_error',
              tostring(saveError) .. ' [' .. destination .. ']'))
        else
          core.notify(I18N.get('layouts.downloaded', fileName))
        end
      end)
    end)
    if not started then
      state.downloading = false
      core.notify(I18N.get('layouts.download_error',
          tostring(startError) .. ' [' .. destination .. ']'))
    end
  end)
end

return M
