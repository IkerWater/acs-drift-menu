-- Colores y widgets reutilizables (tema oscuro moderno). Sin logica de negocio.
local M = {}

M.C = {
  bg        = rgbm(0.045, 0.045, 0.070, 0.96),
  surface   = rgbm(0.100, 0.100, 0.150, 1.00),
  surfaceHi = rgbm(0.150, 0.140, 0.220, 1.00),
  accent    = rgbm(0.120, 0.500, 0.280, 0.80),
  accentHi  = rgbm(0.250, 0.950, 0.480, 1.00),
  text      = rgbm(0.920, 0.950, 0.925, 1.00),
  dim       = rgbm(0.620, 0.680, 0.635, 1.00),
}
local C = M.C

-- RGB base del fondo (sin alpha) para poder recalcular al cambiar transparencia.
local BG_R, BG_G, BG_B = 0.045, 0.045, 0.070

-- Presets de color de acento. Mismo estilo que el verde original: tono oscuro
-- para botones/bordes (c) y version viva para hover y detalles (hi).
M.ACCENTS = {
  { name = 'color.green',  c = rgbm(0.120, 0.500, 0.280, 0.80), hi = rgbm(0.250, 0.950, 0.480, 1.00) },
  { name = 'color.purple', c = rgbm(0.360, 0.200, 0.620, 0.80), hi = rgbm(0.620, 0.400, 1.000, 1.00) },
  { name = 'color.orange', c = rgbm(0.620, 0.320, 0.100, 0.80), hi = rgbm(1.000, 0.600, 0.250, 1.00) },
  { name = 'color.blue',   c = rgbm(0.080, 0.400, 0.500, 0.80), hi = rgbm(0.250, 0.850, 0.950, 1.00) },
  { name = 'color.red',    c = rgbm(0.600, 0.100, 0.100, 0.80), hi = rgbm(1.000, 0.200, 0.200, 1.00) },
}

function M.applyAccent(index)
  local a = M.ACCENTS[index] or M.ACCENTS[1]
  C.accent, C.accentHi = a.c, a.hi
end

function M.applyBgAlpha(alpha)
  C.bg = rgbm(BG_R, BG_G, BG_B, math.max(0.01, math.min(1.0, alpha)))
end

-- Ancho en pixeles de un texto con la fuente por defecto (con aproximacion si no hay measureText).
function M.textWidth(text)
  local ok, size = pcall(ui.measureText, text)
  if ok and size and size.x then return size.x end
  return #text * 8
end

-- Texto grande: usa dwrite si el SDK lo ofrece; si no, texto normal.
function M.bigText(text, size, color)
  if ui.dwriteText then
    ui.dwriteText(text, size, color)
  else
    ui.pushFont(ui.Font.Title)
    ui.textColored(text, color)
    ui.popFont()
  end
end

function M.smallText(text, color)
  ui.textColored(text, color or C.dim)
end

-- Boton con estilo (selected = resaltado con el color de acento)
function M.styledButton(label, size, selected, disabled)
  ui.pushStyleVar(ui.StyleVar.FrameRounding, 9)
  ui.pushStyleColor(ui.StyleColor.Button,        selected and C.accent   or C.surface)
  ui.pushStyleColor(ui.StyleColor.ButtonHovered, selected and C.accentHi or C.surfaceHi)
  ui.pushStyleColor(ui.StyleColor.ButtonActive,  C.accent)
  ui.pushStyleColor(ui.StyleColor.Text,          C.text)
  local pressed = ui.button(label, size, disabled and ui.ButtonFlags.Disabled or 0)
  ui.popStyleColor(4)
  ui.popStyleVar(1)
  return pressed and not disabled
end

function M.sectionTitle(text, color)
  ui.dummy(vec2(0, 4))
  M.smallText(string.upper(text), color or C.accentHi)
  ui.dummy(vec2(0, 2))
end

function M.accentLine()
  local p = ui.getCursor()
  local w = ui.availableSpaceX()
  ui.drawRectFilled(p, p + vec2(w, 2), C.accent, 1)
  ui.dummy(vec2(0, 8))
end

function M.drawProgress(fraction)
  local p = ui.getCursor()
  local w = ui.availableSpaceX()
  ui.drawRectFilled(p, p + vec2(w, 8), C.surface, 4)
  ui.drawRectFilled(p, p + vec2(w * math.max(0, math.min(1, fraction)), 8), C.accent, 4)
  ui.dummy(vec2(0, 12))
end

return M
