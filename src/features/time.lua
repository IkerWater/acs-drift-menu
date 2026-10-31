-- Hora del dia.
local core = import('core')

local M = {}

function M.setTimeOfDay(hour)
  core.safe('Hora del dia', function()
    if type(hour) ~= 'number' or hour ~= hour or hour < 0 or hour > 24 then
      error('hora no valida')
    end

    local sim = ac.getSim()
    local currentSeconds = sim.timeHours * 3600 + sim.timeMinutes * 60 + sim.timeSeconds
    local targetSeconds = (hour % 24) * 3600
    local offset = (targetSeconds - currentSeconds + 43200) % 86400 - 43200
    local timestamp = ac.getTrackDateTime() + offset
    ac.setWeatherExactUTC0Timestamp(timestamp, false)
  end)
end

function M.initialize()
  if core.state.hourInitialized then return true end

  return core.safe('Hora del dia', function()
    local sim = ac.getSim()
    if sim.isInMainMenu then return end

    core.state.hour = sim.timeHours + sim.timeMinutes / 60 + sim.timeSeconds / 3600
    core.state.hourInitialized = true
  end)
end

return M
