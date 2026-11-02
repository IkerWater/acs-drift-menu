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
