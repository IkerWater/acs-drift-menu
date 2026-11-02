-- AcsDriftServerPlugin: CSP track-voting menu and automatic reconnect after track changes.
-- The server reloads this file when it restarts.

local baseUrl = 'http://' .. ac.getServerIP() .. ':' .. ac.getServerPortHTTP() .. '/mapvote/'
local ORANGE = rgbm(0.94, 0.64, 0.23, 1)
local GREEN = rgbm(0.22, 0.85, 0.54, 1)
local GREY = rgbm(0.6, 0.63, 0.67, 1)

-- ---------------------------------------------------------------- local clock (seconds)
local clock = 0

-- ---------------------------------------------------------------- reconnect
local reconnectAt = nil
local reconnectText = nil

ac.OnlineEvent({
  ac.StructItem.key('ACP_MapVoteReconnect'),
  time = ac.StructItem.uint16()
}, function (sender, message)
  if sender ~= nil then return end -- server messages only
  reconnectAt = clock + message.time
  reconnectText = 'Changing track…'
end)

-- ---------------------------------------------------------------- actions to the server
local actionEvent = ac.OnlineEvent({
  ac.StructItem.key('ACP_MapVoteAction'),
  action = ac.StructItem.uint8(),
  id = ac.StructItem.uint16()
})

local function propose(id) actionEvent({ action = 1, id = id }) end
local function voteYes() actionEvent({ action = 2, id = 0 }) end
local function voteNo() actionEvent({ action = 3, id = 0 }) end

-- ---------------------------------------------------------------- server data
local tracks, status = nil, nil
local lastTracks, lastStatus = -100, -100
local loadingTracks, loadingStatus = false, false
local filter = ''

local function refresh(force)
  local now = clock
  if not loadingTracks and (force or tracks == nil or now - lastTracks > 60) then
    loadingTracks = true
    web.get(baseUrl .. 'tracks', function (err, response)
      loadingTracks = false
      lastTracks = clock
      if not err and response and response.status == 200 then tracks = JSON.parse(response.body) end
    end)
  end
  if not loadingStatus and (force or now - lastStatus > 1.5) then
    loadingStatus = true
    web.get(baseUrl .. 'status', function (err, response)
      loadingStatus = false
      lastStatus = clock
      if not err and response and response.status == 200 then status = JSON.parse(response.body) end
    end)
  end
end

-- ---------------------------------------------------------------- window
local function drawMenu()
  refresh(false)
  local s = status

  if s and s.current then
    ui.text('Current track: ')
    ui.sameLine(0, 0)
    ui.textColored(s.current.name or '?', ORANGE)
  end

  if s and s.changing then
    ui.separator()
    ui.textColored(string.format('Changing to %s in %d s…', s.changingTo or 'another track', s.changeInSeconds or 0), GREEN)
    return false
  end

  if s and s.active and s.proposal then
    ui.separator()
    ui.textWrapped(string.format('%s proposes: %s', s.proposer or '?', s.proposal.name))
    ui.text(string.format('%d / %d votes in favor · %d against · %d s remaining',
      s.yes or 0, s.needed or 0, s.no or 0, s.secondsLeft or 0))
    if ui.button('Yes', vec2(110, 0)) then voteYes(); refresh(true) end
    ui.sameLine()
    if ui.button('No', vec2(110, 0)) then voteNo(); refresh(true) end
    ui.separator()
  elseif s and (s.cooldownLeft or 0) > 0 then
    ui.textColored(string.format('You can propose another track in %d s', s.cooldownLeft), GREY)
  end

  if not tracks then
    ui.text('Loading tracks…')
    return false
  end

  ui.setNextItemWidth(-1)
  filter = ui.inputText('Search', filter, ui.InputTextFlags.Placeholder)
  local f = filter:lower()
  local canPropose = s and not s.active and (s.cooldownLeft or 0) == 0

  ui.childWindow('##mapvote_list', vec2(0, 300), function ()
    for _, t in ipairs(tracks) do
      if f == '' or t.name:lower():find(f, 1, true) then
        ui.pushID(t.id)
        local current = s and s.current and s.current.track == t.track and (s.current.layout or '') == (t.layout or '')
        if current then
          ui.textColored(t.name .. '  (current)', ORANGE)
        else
          ui.text(t.name)
          if canPropose then
            ui.sameLine(math.max(ui.windowWidth() - 110, 200))
            if ui.button('Propose') then propose(t.id); refresh(true) end
          end
        end
        ui.popID()
      end
    end
  end)
  return false
end

local function getIcon()
  local ok, icon = pcall(function () return ui.Icons.Map end)
  if ok and icon then return icon end
  return ui.Icons.Info
end

ui.registerOnlineExtra(getIcon(), 'Track vote', function () return true end, drawMenu, nil, ui.OnlineExtraFlags.Tool)

-- ---------------------------------------------------------------- notification and reconnect
function script.drawUI()
  if reconnectAt then
    local w = ac.getUI().windowSize
    local text = reconnectText .. string.format(' %d', math.max(0, math.ceil(reconnectAt - clock)))
    ui.transparentWindow('mapvoteReconnect', vec2(w.x / 2 - 220, w.y / 2 - 40), vec2(440, 80), function ()
      ui.pushFont(ui.Font.Title)
      ui.textAligned(text, vec2(0.5, 0.5), vec2(440, 80))
      ui.popFont()
    end)
  end
end

function script.update(dt)
  clock = clock + dt
  if reconnectAt and clock >= reconnectAt then
    reconnectAt = nil
    ac.reconnectTo({ carID = ac.getCarID(0) })
  end
end
