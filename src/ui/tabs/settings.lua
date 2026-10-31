-- Pestana: ajustes del propio menu (acento, texto, transparencia, posicion).
-- Los cambios son inmediatos y duran la sesion (no se persisten en disco).
local core   = import('core')
local T      = import('ui/theme')
local C      = T.C

local function styledSlider(id, value, min, max, fmt)
  ui.pushStyleColor(ui.StyleColor.FrameBg,          C.surface)
  ui.pushStyleColor(ui.StyleColor.SliderGrab,        C.accent)
  ui.pushStyleColor(ui.StyleColor.SliderGrabActive,  C.accentHi)
  ui.pushStyleVar(ui.StyleVar.FrameRounding, 9)
  ui.setNextItemWidth(ui.availableSpaceX())
  local v = ui.slider(id, value, min, max, fmt)
  ui.popStyleVar(1)
  ui.popStyleColor(3)
  return v
end

-- Boton-muestra: fondo = color del preset, texto siempre blanco para legibilidad.
local WHITE = rgbm(1, 1, 1, 1)
local function swatchBtn(id, label, col, colHi, selected, w, h)
  ui.pushStyleVar(ui.StyleVar.FrameRounding, 9)
  ui.pushStyleColor(ui.StyleColor.Button,        col)
  ui.pushStyleColor(ui.StyleColor.ButtonHovered, colHi)
  ui.pushStyleColor(ui.StyleColor.ButtonActive,  colHi)
  ui.pushStyleColor(ui.StyleColor.Text,          WHITE)
  local tag = (selected and '> ' or '') .. label .. '##' .. id
  local pressed = ui.button(tag, vec2(w, h))
  ui.popStyleColor(4)
  ui.popStyleVar(1)
  return pressed
end

return function()
  local s = core.state.settings

  -- ── Color de acento ──────────────────────────────────────────────────────
  T.sectionTitle('Color de acento')
  T.smallText('Botones activos, bordes y resaltados del menu.')
  ui.dummy(vec2(0, 4))
  local n  = #T.ACCENTS
  local aw = (ui.availableSpaceX() - (n - 1) * 5) / n
  for i, a in ipairs(T.ACCENTS) do
    if i > 1 then ui.sameLine(0, 5) end
    if swatchBtn('ac'..i, a.name, a.c, a.hi, s.accentIndex == i, aw, 32) then
      s.accentIndex = i
      T.applyAccent(i)
    end
  end

  -- ── Transparencia del fondo ──────────────────────────────────────────────
  T.sectionTitle('Transparencia del fondo')
  local alpha = styledSlider('##bgalpha', s.bgAlpha, 0.01, 1.0, 'Opacidad: %.2f')
  if alpha ~= s.bgAlpha then
    s.bgAlpha = alpha
    T.applyBgAlpha(alpha)
  end

  -- ── Posicion en pantalla (en % de la pantalla, valido para cualquier resolucion) ──
  T.sectionTitle('Posicion en pantalla')
  T.smallText('0% = pegado al borde izquierdo/superior, 100% = al derecho/inferior.')
  ui.dummy(vec2(0, 4))
  local newX = styledSlider('##posx', s.posX, 0, 100, 'X: %.0f%%')
  local newY = styledSlider('##posy', s.posY, 0, 100, 'Y: %.0f%%')
  if newX ~= s.posX then s.posX = newX end
  if newY ~= s.posY then s.posY = newY end

    -- ── Comportamiento ───────────────────────────────────────────────────────
  T.sectionTitle('Comportamiento')
  ui.pushStyleColor(ui.StyleColor.FrameBg,        C.surface)
  ui.pushStyleColor(ui.StyleColor.FrameBgHovered, C.surfaceHi)
  ui.pushStyleColor(ui.StyleColor.CheckMark,      C.accentHi)
  ui.pushStyleColor(ui.StyleColor.Text,           C.text)
  if ui.checkbox('Cerrar el menu al acelerar', s.closeOnGas) then
    s.closeOnGas = not s.closeOnGas
  end
  ui.popStyleColor(4)
end