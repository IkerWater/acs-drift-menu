-- Punto de entrada: engancha los callbacks de CSP. Aqui no hay logica propia.
local CONFIG = import('config')
local core = import('core')
local teleport = import('features/teleport')
local mapvote = import('features/mapvote')
local menu = import('ui/menu')

function script.update(dt)
  local sim = ac.getSim()
  if sim.isReplayActive or sim.isPaused or sim.isInMainMenu then return end
  teleport.update(dt)
  mapvote.update(dt, core.state.open and core.state.tab == 'track')
end

-- Callback de UI para scripts online [VERIFICAR el nombre en tu version de CSP:
-- si el menu no aparece, comprueba el log; alternativas habituales: script.drawUI / script.update]
function script.drawUI(dt)
  if ui.keyboardButtonPressed(CONFIG.toggleKey, false) then core.state.open = not core.state.open end
  if not core.state.open then return end
  menu.drawWindow()
end
