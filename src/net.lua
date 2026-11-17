-- Peticiones HTTP al API del servidor (AcsDriftServerPlugin: /mapvote/*, /cars/*).
-- Modulo compartido: cualquier feature consulta al servidor sin reimplementar
-- la URL base ni el parseo de JSON.
local CONFIG = import('config')

local M = {}

-- Llama a la primera funcion de CSP que exista y devuelva un valor util.
local function fromCsp(names, valid)
  for _, name in ipairs(names) do
    local fn = ac[name]
    if fn then
      local ok, v = pcall(fn)
      if ok and valid(v) then return v end
    end
  end
  return nil
end

-- URL del API del servidor al que esta conectado el jugador. Se obtiene siempre de
-- CSP (IP y puerto HTTP de la sesion actual), asi cada servidor clonado sirve sus
-- propios datos aunque compartan maquina/IP. CONFIG.server solo es el ultimo recurso.
-- Ojo: la funcion de CSP es ac.getServerPortHTTP (la misma que usa lua/mapvote.lua
-- del plugin). Antes se llamaba a ac.getServerHTTPPort, que no existe, y el menu
-- acababa siempre en el puerto 8081 del config, es decir, en el primer servidor.
function M.serverBaseUrl()
  local host = fromCsp({ 'getServerIP' }, function(v) return type(v) == 'string' and v ~= '' end)
    or CONFIG.server.host
  local port = fromCsp({ 'getServerPortHTTP', 'getServerHTTPPort' },
    function(v) return tonumber(v) and tonumber(v) > 0 end) or CONFIG.server.httpPort
  return string.format('http://%s:%d', host, tonumber(port))
end

function M.getJson(path, callback)
  local ok, err = pcall(function()
    web.get(M.serverBaseUrl() .. path, function(e, response)
      if e or not response or response.status ~= 200 then
        return callback(nil, tostring(e or (response and response.status) or 'sin respuesta'))
      end
      local parsedOk, data = pcall(JSON.parse, response.body)
      if parsedOk and type(data) == 'table' then callback(data) else callback(nil, 'JSON invalido') end
    end)
  end)
  if not ok then callback(nil, tostring(err)) end
end

return M
