-- Estado compartido y utilidades basicas. No depende de ningun otro modulo.
local M = {}

local toggleKeyCandidates = {}
for key = ui.KeyIndex.A, ui.KeyIndex.Z do
  toggleKeyCandidates[#toggleKeyCandidates + 1] = {
    name = string.char(key),
    index = key,
  }
end
for digit = 0, 9 do
  local name = 'D' .. digit
  toggleKeyCandidates[#toggleKeyCandidates + 1] = {
    name = tostring(digit),
    index = ui.KeyIndex[name],
  }
end
for number = 1, 12 do
  local name = 'F' .. number
  toggleKeyCandidates[#toggleKeyCandidates + 1] = {
    name = name,
    index = ui.KeyIndex[name],
  }
end

local function isToggleKeyName(value)
  for _, candidate in ipairs(toggleKeyCandidates) do
    if candidate.name == value and candidate.index then return true end
  end
  return false
end

local storedSettings = ac.storage({
  language = 'en',
  accentIndex = 1,
  bgAlpha = 0.15,
  closeOnGas = false,
  posX = 0.5,
  posY = 0.5,
  toggleKeyName = 'M',
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

local toggleKeyName = storedSettings.toggleKeyName
if not isToggleKeyName(toggleKeyName) then toggleKeyName = 'M' end

M.state = {
  open = false,
  awaitingToggleKey = false,
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
    toggleKeyName = toggleKeyName,
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
  storedSettings.toggleKeyName = settings.toggleKeyName
end

M.persistSettings()

function M.toggleKeyIndex()
  for _, candidate in ipairs(toggleKeyCandidates) do
    if candidate.name == M.state.settings.toggleKeyName then return candidate.index end
  end
  return ui.KeyIndex.M
end

function M.pressedToggleKeyName()
  for _, candidate in ipairs(toggleKeyCandidates) do
    if candidate.index and ui.keyboardButtonPressed(candidate.index, false) then
      return candidate.name
    end
  end
end

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

return M
