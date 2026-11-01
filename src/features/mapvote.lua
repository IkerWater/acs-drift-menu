-- Votacion de mapa (servidor: AcsDriftServerPlugin).
-- La lista de mapas y el estado se leen por HTTP; las acciones van por chat.
local CONFIG = import('config')
local core = import('core')
local net = import('net')

local M = {}

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
      core.notify('Lista de mapas: ' .. tostring(err))
    end
  end)
end

local function pollStatus()
  net.getJson('/mapvote/status', function(data, err)
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
