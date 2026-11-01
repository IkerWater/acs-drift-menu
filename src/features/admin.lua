-- Estado de administrador de ESTA conexion. No hay forma de saberlo por HTTP
-- (el servidor no sabe que jugador hay detras de una peticion web normal), asi
-- que se pide por online event (CSP), que si va atado a la conexion del cliente.
-- El estado puede cambiar en caliente (alguien escribe /admin <contraseña> en el
-- chat a mitad de partida), por eso se vuelve a pedir cada pocos segundos.
local core = import('core')

local M = {}

local state = { isAdmin = false }
M.data = state

local requestEvent = ac.OnlineEvent({
  ac.StructItem.key('ACP_AdminStatusRequest'),
  request = ac.StructItem.uint8(),
})

ac.OnlineEvent({
  ac.StructItem.key('ACP_AdminStatusResponse'),
  isAdmin = ac.StructItem.uint8(),
}, function(sender, message)
  if sender ~= nil then return end -- solo mensajes del propio servidor
  state.isAdmin = message.isAdmin == 1
end)

local pollTimer = 0

function M.request()
  requestEvent({ request = 0 })
end

function M.update(dt)
  pollTimer = pollTimer - dt
  if pollTimer <= 0 then
    pollTimer = 5
    if core.state.open then M.request() end
  end
end

M.request() -- primer chequeo nada mas cargar el script

return M
