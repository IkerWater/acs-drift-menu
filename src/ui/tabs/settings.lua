-- Pestana: ajustes del propio menu (acento, texto, transparencia, posicion).
-- Los cambios son inmediatos y duran la sesion (no se persisten en disco).
local core   = import('core')
local T      = import('ui/theme')
local I18N   = import('i18n')
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

  T.sectionTitle(I18N.get('settings.language'))
  local languageWidth = (ui.availableSpaceX() - 6) / 2
  if T.styledButton('English', vec2(languageWidth, 32), s.language == 'en') then
    s.language = 'en'
  end
  ui.sameLine(0, 6)
  if T.styledButton('Español', vec2(languageWidth, 32), s.language == 'es') then
    s.language = 'es'
  end

  -- ── Color de acento ──────────────────────────────────────────────────────
  T.sectionTitle(I18N.get('settings.accent'))
  T.smallText(I18N.get('settings.accent_hint'))
  ui.dummy(vec2(0, 4))
  local n  = #T.ACCENTS
  local aw = (ui.availableSpaceX() - (n - 1) * 5) / n
  for i, a in ipairs(T.ACCENTS) do
    if i > 1 then ui.sameLine(0, 5) end
    if swatchBtn('ac'..i, I18N.get(a.name), a.c, a.hi, s.accentIndex == i, aw, 32) then
      s.accentIndex = i
      T.applyAccent(i)
    end
  end

  -- ── Transparencia del fondo ──────────────────────────────────────────────
  T.sectionTitle(I18N.get('settings.transparency'))
  local alpha = styledSlider('##bgalpha', s.bgAlpha, 0.01, 1.0, I18N.get('settings.opacity'))
  if alpha ~= s.bgAlpha then
    s.bgAlpha = alpha
    T.applyBgAlpha(alpha)
  end

  -- ── Posicion en pantalla (en % de la pantalla, valido para cualquier resolucion) ──
  T.sectionTitle(I18N.get('settings.position'))
  T.smallText(I18N.get('settings.position_hint'))
  ui.dummy(vec2(0, 4))
  local newX = styledSlider('##posx', s.posX, 0, 100, 'X: %.0f%%')
  local newY = styledSlider('##posy', s.posY, 0, 100, 'Y: %.0f%%')
  if newX ~= s.posX then s.posX = newX end
  if newY ~= s.posY then s.posY = newY end

    -- ── Comportamiento ───────────────────────────────────────────────────────
  T.sectionTitle(I18N.get('settings.behavior'))
  ui.pushStyleColor(ui.StyleColor.FrameBg,        C.surface)
  ui.pushStyleColor(ui.StyleColor.FrameBgHovered, C.surfaceHi)
  ui.pushStyleColor(ui.StyleColor.CheckMark,      C.accentHi)
  ui.pushStyleColor(ui.StyleColor.Text,           C.text)
  if ui.checkbox(I18N.get('settings.close_gas'), s.closeOnGas) then
    s.closeOnGas = not s.closeOnGas
  end
  ui.popStyleColor(4)
end