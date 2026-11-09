-- Punto de entrada: engancha los callbacks de CSP. Aqui no hay logica propia.
local core = import('core')
local I18N = import('i18n')
local teleport = import('features/teleport')
local mapvote = import('features/mapvote')
local car = import('features/car')
local admin = import('features/admin')
local layouts = import('features/layouts')
local ghost = import('features/ghost')
local menu = import('ui/menu')
local voteWindow = import('ui/vote_window')
local ghostHud = import('ui/ghost_hud')
local ghostConfirm = import('ui/ghost_confirm')

function script.update(dt)
  local sim = ac.getSim()
  if sim.isReplayActive or sim.isPaused or sim.isInMainMenu then return end
  -- Cierre automatico al acelerar (se activa/desactiva en la pestana Ajustes).
  if core.state.open and core.state.settings.closeOnGas then
    local car = ac.getCar(0)
    if car and car.gas > 0 then core.state.open = false end
  end
  teleport.update(dt)
  mapvote.update(dt, core.state.open and core.state.tab == 'track')
  car.update(dt, core.state.open and core.state.tab == 'car')
  admin.update(dt, core.state.open and core.state.tab == 'admin')
  layouts.update(dt, core.state.open and core.state.tab == 'layouts')
  ghost.update(dt, core.state.open and core.state.tab == 'ghost')
end

function script.drawUI(dt)
  local waitingForToggleKey = core.state.awaitingToggleKey
  if waitingForToggleKey and core.state.open then
    local keyName = core.pressedToggleKeyName()
    if keyName then
      core.state.settings.toggleKeyName = keyName
      core.state.awaitingToggleKey = false
      core.persistSettings()
      core.notify(I18N.get('settings.toggle_key_saved', keyName))
    end
  elseif waitingForToggleKey then
    core.state.awaitingToggleKey = false
  elseif ui.keyboardButtonPressed(core.toggleKeyIndex(), false) then
    core.state.open = not core.state.open
  end
  if core.state.open then menu.drawWindow() end
  voteWindow.draw()
  ghostHud.draw()
  ghostConfirm.draw()
end