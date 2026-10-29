-- Pestana: votacion de mapa.
local mv = import('features/mapvote')
local T = import('ui/theme')
local C, smallText, sectionTitle, styledButton, drawProgress =
  T.C, T.smallText, T.sectionTitle, T.styledButton, T.drawProgress

local mapvote = mv.data

return function()
  local st = mapvote.status

  sectionTitle('Mapa actual')
  if st and st.current then
    ui.pushFont(ui.Font.Small)
    ui.textWrapped(st.current.name)
    ui.popFont()
  elseif mapvote.statusError then
    smallText('Sin conexion con el servidor: ' .. mapvote.statusError)
  else
    smallText('Consultando...')
  end

  -- Cambio aprobado: cuenta atras
  if st and st.changing then
    sectionTitle('Cambiando de circuito')
    smallText(string.format('El servidor se reinicia en %d s. Vuelve a entrar al servidor.', st.changeInSeconds or 0), C.accentHi)
    return
  end

  -- Votacion en curso
  if st and st.active and st.proposal then
    sectionTitle('Votacion en curso')
    ui.pushFont(ui.Font.Small)
    ui.textWrapped(st.proposal.name)
    ui.popFont()
    smallText('Propone: ' .. tostring(st.proposer or '?'))
    smallText(string.format('A favor: %d de %d necesarios  |  Conectados: %d', st.yes, st.needed, st.connectedAtStart))
    smallText(string.format('Tiempo restante: %d s', st.secondsLeft))
    ui.dummy(vec2(0, 4))
    drawProgress(st.yes / math.max(1, st.needed))

    local voted = mapvote.myVoteFor == st.proposal.id
    local w = (ui.availableSpaceX() - 6) / 2
    if styledButton('A FAVOR', vec2(w, 36), voted and mapvote.myVote == true) then mv.castVote(true) end
    ui.sameLine(0, 6)
    if styledButton('EN CONTRA', vec2(w, 36), voted and mapvote.myVote == false) then mv.castVote(false) end
    return
  end

  -- Sin votacion: elegir mapa y proponer
  local cooldown = st and st.cooldownLeft or 0
  sectionTitle('Proponer cambio de mapa')
  if cooldown > 0 then
    smallText(string.format('Podras iniciar otra votacion en %d s', cooldown), C.accentHi)
  end

  if mapvote.tracksState == 'loading' then
    smallText('Cargando lista de mapas...')
  elseif mapvote.tracksState == 'error' then
    smallText('No se pudo cargar la lista de mapas.')
    ui.dummy(vec2(0, 4))
    if styledButton('REINTENTAR', vec2(-0.1, 32), true) then mv.loadTracks() end
    return
  end

  ui.setNextItemWidth(ui.availableSpaceX())
  mapvote.filter = ui.inputText('##mapfilter', mapvote.filter)
  if mapvote.filter == '' then smallText('Escribe arriba para filtrar mapas.') end
  ui.dummy(vec2(0, 4))

  local needle = string.lower(mapvote.filter or '')
  ui.pushStyleColor(ui.StyleColor.ChildBg, rgbm(0, 0, 0, 0.18))
  ui.pushStyleVar(ui.StyleVar.ChildRounding, 9)
  ui.childWindow('acs_map_list', vec2(-0.1, 230), false, function()
    local shown = 0
    for _, e in ipairs(mapvote.tracks) do
      if needle == '' or string.find(string.lower(e.name), needle, 1, true) then
        shown = shown + 1
        if shown > 150 then
          smallText('Hay mas resultados: afina el filtro.')
          break
        end
        if styledButton(e.name .. '##map_' .. e.id, vec2(-0.1, 28), mapvote.selected == e.id) then
          mapvote.selected = e.id
        end
      end
    end
    if shown == 0 then smallText('Sin resultados.') end
  end)
  ui.popStyleVar(1)
  ui.popStyleColor(1)

  ui.dummy(vec2(0, 8))
  local entry
  for _, e in ipairs(mapvote.tracks) do
    if e.id == mapvote.selected then entry = e break end
  end
  local isCurrent = entry and st and st.current
      and entry.track == st.current.track and entry.layout == st.current.layout
  local canPropose = entry ~= nil and cooldown <= 0 and not isCurrent

  if styledButton('PROPONER CAMBIO', vec2(-0.1, 38), true, not canPropose) then mv.propose(entry) end
  if isCurrent then smallText('Ya estas en ese mapa.') end
  ui.dummy(vec2(0, 4))
  if styledButton('Recargar lista', vec2(-0.1, 26), false) then mv.loadTracks() end
end
