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
