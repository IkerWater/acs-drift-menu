-- Skins locales: descubrimiento y aplicacion (solo cliente).
local M = {}

local TEXTURE_EXTENSIONS = {
  dds = true,
  jpg = true,
  jpeg = true,
  png = true,
  tga = true,
}

M.state = {
  carID = nil,
  skins = {},
  selected = 1,
  message = '',
}

local function loadLocalSkins(carID)
  local carsPath = ac.getFolder(ac.FolderID.ContentCars)
  local skinsPath = carsPath .. '/' .. carID .. '/skins'
  local skins = {}

  if not io.dirExists(skinsPath) then
    return skins
  end

  local dirs = io.scanDir(skinsPath, '*') or {}

  for _, name in ipairs(dirs) do
    local skinPath = skinsPath .. '/' .. name

    if io.dirExists(skinPath) then
      local label = name
      local preview = skinPath .. '/preview.jpg'
      local skinJson = skinPath .. '/ui_skin.json'

      if not io.fileExists(preview) then
        preview = skinPath .. '/preview.png'
        if not io.fileExists(preview) then
          preview = nil
        end
      end

      -- El nombre visible es opcional:
      -- si no existe ui_skin.json, usamos el nombre de carpeta.
      if io.fileExists(skinJson) then
        local ok, data = pcall(function()
          return JSON.parse(io.load(skinJson, ''))
        end)

        if ok and type(data) == 'table'
            and type(data.skinname) == 'string'
            and data.skinname ~= '' then
          label = data.skinname
        end
      end

      skins[#skins + 1] = { id = name, label = label, preview = preview }
    end
  end

  table.sort(skins, function(a, b)
    return a.label:lower() < b.label:lower()
  end)

  return skins
end

function M.refresh()
  local st = M.state
  local carID = ac.getCarID(0)

  st.carID = carID
  st.skins = loadLocalSkins(carID)
  st.selected = 1
  st.message = ''

  -- Seleccionar inicialmente la skin oficial del coche.
  local currentSkinID = ac.getCarSkinID(0)

  for i, skin in ipairs(st.skins) do
    if skin.id == currentSkinID then
      st.selected = i
      break
    end
  end
end

function M.apply(skin)
  if type(skin) ~= 'table' or type(skin.id) ~= 'string'
      or type(skin.label) ~= 'string' then
    M.state.message = 'No se ha podido aplicar: skin no valida.'
    return false
  end

  local carID = ac.getCarID(0)
  local skinPath = ac.getFolder(ac.FolderID.ContentCars)
      .. '/' .. carID .. '/skins/' .. skin.id

  local ok, err = pcall(function()
    if not io.dirExists(skinPath) then
      error('No se encuentra la carpeta local de la skin.')
    end

    local replacements = {}
    for _, name in ipairs(io.scanDir(skinPath, '*') or {}) do
      local extension = name:match('%.([^%.]+)$')
      local texturePath = skinPath .. '/' .. name
      if extension and TEXTURE_EXTENSIONS[extension:lower()]
          and io.fileExists(texturePath) then
        replacements[name] = texturePath
      end
    end
    if next(replacements) == nil then
      error('La carpeta no contiene texturas compatibles.')
    end

    local carRoot = ac.findNodes('carRoot:0')
    if not carRoot then
      error('No se encontro el coche local.')
    end
    if type(carRoot.applySkin) ~= 'function' then
      error('Esta version de CSP no permite cambiar skins localmente.')
    end
    if type(carRoot.resetSkin) ~= 'function' then
      error('Esta version de CSP no permite restablecer la skin local.')
    end

    carRoot:resetSkin()
    carRoot:applySkin(replacements)
  end)

  if ok then
    M.state.message = 'Skin aplicada localmente (solo visible para ti): ' .. skin.label
  else
    M.state.message = 'Error al aplicar skin: ' .. tostring(err)
  end
  return ok
end

return M
