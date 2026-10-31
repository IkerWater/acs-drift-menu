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

    if ac.setWeatherExactUTC0Timestamp then
      local timestamp = ac.getTrackDateTime() + offset
      ac.setWeatherExactUTC0Timestamp(timestamp, false)
    elseif not sim.isOnlineRace and ac.setWeatherTimeOffset then
      ac.setWeatherTimeOffset(offset, true)
    else
      error('Actualiza CSP a 0.3.0+ para cambiar la hora online')
    end
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
