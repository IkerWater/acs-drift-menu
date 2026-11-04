-- Estado compartido y utilidades basicas. No depende de ningun otro modulo.
local M = {}

local storedSettings = ac.storage({
  language = 'en',
  accentIndex = 1,
  bgAlpha = 0.15,
  closeOnGas = false,
  posX = 0.5,
  posY = 0.5,
}, 'acsDriftMenu.')

local function normalizedPosition(value)
  if type(value) ~= 'number' or value ~= value
      or value == math.huge or value == -math.huge then
    return 0.5
  end
  return math.max(0, math.min(1, value))
end

local function normalizedAlpha(value)
  if type(value) ~= 'number' or value ~= value
      or value == math.huge or value == -math.huge then
    return 0.15
  end
  return math.max(0.01, math.min(1, value))
end

local language = storedSettings.language
if language ~= 'en' and language ~= 'es' then language = 'en' end

local accentIndex = storedSettings.accentIndex
if type(accentIndex) ~= 'number' or accentIndex ~= accentIndex then accentIndex = 1 end
accentIndex = math.max(1, math.min(5, math.floor(accentIndex)))

local closeOnGas = storedSettings.closeOnGas
if type(closeOnGas) ~= 'boolean' then closeOnGas = false end

M.state = {
  open = false,
  tab = 'car',            -- id de la pestana activa (ver ui/menu.lua)
  carID = nil,            -- id del coche elegido en la pestana 'car' (lista leida del servidor)
  message = '', messageTime = 0,
  savedPoint = nil,
  -- Preferencias locales persistidas en CSP.
  settings = {
    language    = language, -- en | es; CSP Lua API does not expose a documented game-language getter.
    accentIndex = accentIndex, -- indice en T.ACCENTS
    bgAlpha     = normalizedAlpha(storedSettings.bgAlpha),
    closeOnGas  = closeOnGas, -- cerrar el menu al acelerar (ver main.lua)
    posX        = normalizedPosition(storedSettings.posX),
    posY        = normalizedPosition(storedSettings.posY),
  },
}

function M.persistSettings()
  local settings = M.state.settings
  storedSettings.language = settings.language
  storedSettings.accentIndex = settings.accentIndex
  storedSettings.bgAlpha = settings.bgAlpha
  storedSettings.closeOnGas = settings.closeOnGas
  storedSettings.posX = settings.posX
  storedSettings.posY = settings.posY
end

M.persistSettings()

function M.notify(text)
  M.state.message, M.state.messageTime = text, os.clock()
  ac.log('[ACS Menu] ' .. text)
end

-- Ejecuta fn protegida; si falla, avisa en el menu y devuelve false.
function M.safe(label, fn, unavailableText)
  local ok, err = pcall(fn)
  if not ok then
    M.notify(label .. ': ' .. (unavailableText or 'no disponible')
        .. ' (' .. tostring(err):sub(1, 70) .. ')')
  end
  return ok
end

function M.sendChatCommand(cmd, sentMessage)
  ac.sendChatMessage(cmd)
  M.notify(sentMessage or ('Enviado: ' .. cmd))
end

return M
