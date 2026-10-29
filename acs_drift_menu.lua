-- ACS Menu (Drift) - script ONLINE para CSP, v0.2
-- Se carga desde el servidor via csp_extra_options.ini ([SCRIPT_1]).
-- Tecla M: abrir/cerrar el menu.
-- Lo marcado [VERIFICAR] no esta confirmado en la documentacion: si falla,
-- el error aparece en el propio menu y en el log de CSP.

------------------------------------------------------------------------
-- CONFIGURACION (edita antes de subir)
------------------------------------------------------------------------
local CONFIG = {
  toggleKey = ui.KeyIndex.M,

  -- Coches ofrecidos ('id' = carpeta del coche, 'skins' = carpetas de skin).
  -- Deben existir como entradas en el entry_list del servidor.
  cars = {
    { id = 'tunermnrcars_eskuko_missile_e36coupe', name = 'Eskuko Missile E36 Coupe', skins = { 'default', 'Titanio' } },
    { id = 'tunermnrcars_eskuko_missile_e36compact',    name = 'Eskuko Missile E36 Compact',    skins = { 'default', 'JulenArjona' } },
  },

  -- Datos del servidor para reconectar (cambio de coche/skin).
  server = { host = '', port = 9600, httpPort = 8081, password = '123456789' },

  -- Comandos de chat de AssettoServer (VotingPresetPlugin). Ajusta a tu version.
  commands = {
    voteList  = '/presetlist',
    voteStart = '/presetstartvote',
    vote      = '/vote %d',
  },
  tracks = { 'sion_fk1_2026', 'sion_miranda', 'sr_shadowvalley' },
  
}

------------------------------------------------------------------------
-- ESTADO Y UTILIDADES
------------------------------------------------------------------------
local state = {
  open = false, tab = 1, carIndex = 1, skinIndex = 1, hour = 12,
  message = '', messageTime = 0, savedPoint = nil,
}

local function notify(text)
  state.message, state.messageTime = text, os.clock()
  ac.log('[ACS Menu] ' .. text)
end

local function safe(label, fn)
  local ok, err = pcall(fn)
  if not ok then notify(label .. ': no disponible (' .. tostring(err):sub(1, 70) .. ')') end
  return ok
end

local function sendChatCommand(cmd)
  ac.sendChatMessage(cmd)
  notify('Enviado: ' .. cmd)
end

------------------------------------------------------------------------
-- FUNCIONES
------------------------------------------------------------------------

------------------------------------------------------------------------
-- Coche y skin
------------------------------------------------------------------------
local function changeCar(carIdx, skinIdx)
  local car = CONFIG.cars[carIdx]
  safe('Cambio de coche', function()
    -- [VERIFICAR] nombre y parametros exactos en tu SDK
    ac.reconnectTo({
      host = CONFIG.server.host, port = CONFIG.server.port,
      httpPort = CONFIG.server.httpPort, password = CONFIG.server.password,
      car = car.id, skin = car.skins[skinIdx],
    })
  end)
end

-- CAMBIO VISUAL DE SKIN (solo cliente local)

local skinList = {}
local selectedSkin = 1
local currentCarID = nil
local skinMessage = ''

local function refreshSkinList()
  currentCarID = ac.getCarID(0)
  local currentSkinID = ac.getCarSkinID(0)

  -- El script remoto no puede enumerar carpetas libremente.
  -- De momento, esta lista debe venir de una fuente externa.
  skinList = CONFIG.localSkins and CONFIG.localSkins[currentCarID] or {}

  selectedSkin = 1
  for i, skin in ipairs(skinList) do
    if skin == currentSkinID then
      selectedSkin = i
      break
    end
  end
end

local function voteTrack(n) sendChatCommand(string.format(CONFIG.commands.vote, n)) end

local function setTimeOfDay(hour)
  safe('Hora del dia', function()
    -- [VERIFICAR] pendiente: poner aqui la funcion real del SDK para la hora
    error('pendiente de implementar')
  end)
end

local function savePoint()
  local car = ac.getCar(0)
  state.savedPoint = { pos = car.position:clone(), dir = car.look:clone() }
  notify('Punto guardado')
end

local function teleportToPoint()
  if not state.savedPoint then return notify('No hay punto guardado') end
  safe('Teleport', function()
    physics.setCarPosition(0, state.savedPoint.pos, state.savedPoint.dir) -- [VERIFICAR]
  end)
end

local function teleportToPits()
  safe('Teleport a pits', function()
    physics.teleportCarTo(0, ac.SpawnSet.Pits) -- [VERIFICAR]
  end)
end

------------------------------------------------------------------------
-- INTERFAZ
------------------------------------------------------------------------
local ACCENT = rgbm(0.75, 0.25, 1.0, 1)

local function header(text)
  ui.pushFont(ui.Font.Title)
  ui.textColored(text, ACCENT)
  ui.popFont()
  ui.separator()
end

local function tabs()
  local names = { 'Coche', 'Skins', 'Circuito', 'Hora', 'TP' }
  for i, n in ipairs(names) do
    if i > 1 then ui.sameLine() end
    ui.pushStyleColor(ui.StyleColor.Button, state.tab == i and ACCENT or rgbm(0.15, 0.15, 0.2, 1))
    if ui.button(n, vec2(80, 28)) then state.tab = i end
    ui.popStyleColor()
  end
end

local function tabCar()
  header('CAMBIAR COCHE')
  for i, c in ipairs(CONFIG.cars) do
    if ui.selectable(c.name, state.carIndex == i) then state.carIndex, state.skinIndex = i, 1 end
  end
  ui.text('Skin:')
  for i, s in ipairs(CONFIG.cars[state.carIndex].skins) do
    if ui.selectable(s, state.skinIndex == i) then state.skinIndex = i end
  end
  if ui.button('APLICAR (reconecta)', vec2(-0.1, 36)) then changeCar(state.carIndex, state.skinIndex) end
end

local function tabSkin()
  header('CAMBIAR SKIN')

  local carID = ac.getCarID(0)
  local currentSkinID = ac.getCarSkinID(0)

  ui.text('Coche: ' .. tostring(carID))
  ui.text('Skin actual: ' .. tostring(currentSkinID))
  ui.separator()

  if currentCarID ~= carID then
    refreshSkinList()
  end

  if #skinList == 0 then
    ui.text('No hay skins en el catálogo.')
    ui.text('Hace falta cargar la lista desde otra fuente.')
    return
  end

  for i, skin in ipairs(skinList) do
    if ui.selectable(skin, selectedSkin == i) then
      selectedSkin = i
    end
  end

  if ui.button('APLICAR SKIN', vec2(-0.1, 36)) then
    local skin = skinList[selectedSkin]
    local skinPath = ac.getFolder(ac.FolderID.ContentCars)
      .. '/' .. carID .. '/skins/' .. skin

    local carNodes = ac.findNodes('carRoot:0')
    carNodes:applySkin(skinPath)
    skinMessage = 'Skin visual aplicada: ' .. skin
  end

  if skinMessage ~= '' then
    ui.text(skinMessage)
  end
end

local function tabTrack()
  header('VOTAR CIRCUITO')
  for i, name in ipairs(CONFIG.tracks) do
    if ui.button(string.format('%d. %s', i, name), vec2(-0.1, 30)) then voteTrack(i) end
  end
  ui.separator()
  if ui.button('Ver lista', vec2(140, 28)) then sendChatCommand(CONFIG.commands.voteList) end
  ui.sameLine()
  if ui.button('Iniciar votacion', vec2(-0.1, 28)) then sendChatCommand(CONFIG.commands.voteStart) end
end

local function tabTime()
  header('HORA DEL DIA')
  state.hour = ui.slider('##hour', state.hour, 0, 24, 'Hora: %.1f')
  if ui.button('Aplicar hora', vec2(-0.1, 32)) then setTimeOfDay(state.hour) end
end

local function tabTeleport()
  header('REAPARICION / TP')
  if ui.button('Guardar punto actual', vec2(-0.1, 32)) then savePoint() end
  if ui.button('Volver al punto guardado', vec2(-0.1, 32)) then teleportToPoint() end
  if ui.button('Ir a pits', vec2(-0.1, 32)) then teleportToPits() end
end

local function drawMenu()
  tabs()
  ui.separator()
  if state.tab == 1 then tabCar()
  elseif state.tab == 2 then tabTrack()
  elseif state.tab == 3 then tabTime()
  elseif state.tab == 4 then tabSkin()
  else tabTeleport() end
  if state.message ~= '' and os.clock() - state.messageTime < 6 then
    ui.separator()
    ui.textWrapped(state.message)
  end
end

-- Callback de UI para scripts online [VERIFICAR el nombre en tu version de CSP:
-- si el menu no aparece, comprueba el log; alternativas habituales: script.drawUI / script.update]
function script.drawUI(dt)
  if ui.keyboardButtonPressed(CONFIG.toggleKey, false) then state.open = not state.open end
  if not state.open then return end
  ui.toolWindow('acs_menu/main', vec2(60, 120), vec2(360, 520), false, true, drawMenu)
end
