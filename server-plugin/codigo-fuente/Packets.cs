using AssettoServer.Network.ClientMessages;

namespace AcsDriftServerPlugin;

/// <summary>Cliente → servidor: solicita el estado de administrador de esta conexión.</summary>
[OnlineEvent(Key = "ACP_AdminStatusRequest")]
public class AdminStatusRequestPacket : OnlineEvent<AdminStatusRequestPacket>
{
    [OnlineEventField(Name = "request")]
    public byte Request;
}

/// <summary>Servidor → cliente: indica si esta conexión tiene permisos de administrador.</summary>
[OnlineEvent(Key = "ACP_AdminStatusResponse")]
public class AdminStatusResponsePacket : OnlineEvent<AdminStatusResponsePacket>
{
    [OnlineEventField(Name = "isAdmin")]
    public byte IsAdmin;
}

/// <summary>Cliente → servidor: solicita cambiar a un preset; el servidor valida que sea admin.</summary>
[OnlineEvent(Key = "ACP_AdminPresetChange")]
public class AdminPresetChangePacket : OnlineEvent<AdminPresetChangePacket>
{
    [OnlineEventField(Name = "presetId")]
    public ushort PresetId;
}

/// <summary>Cliente → servidor: acción del menú (1 = proponer, 2 = a favor, 3 = en contra).</summary>
[OnlineEvent(Key = "ACP_MapVoteAction")]
public class MapVoteActionPacket : OnlineEvent<MapVoteActionPacket>
{
    [OnlineEventField(Name = "action")]
    public byte Action;

    [OnlineEventField(Name = "id")]
    public ushort Id;
}

/// <summary>Servidor → clientes: el circuito va a cambiar; reconectar tras "time" segundos.</summary>
[OnlineEvent(Key = "ACP_MapVoteReconnect")]
public class MapVoteReconnectPacket : OnlineEvent<MapVoteReconnectPacket>
{
    [OnlineEventField(Name = "time")]
    public ushort Time;
}

/// <summary>Cliente → servidor: acción del fantasma (1 grabar, 2 parar y guardar, 3 cancelar, 4 cargar id,
/// 5 quitar, 6 borrar id). Solo administradores.</summary>
[OnlineEvent(Key = "ACP_GhostAction")]
public class GhostActionPacket : OnlineEvent<GhostActionPacket>
{
    [OnlineEventField(Name = "action")]
    public byte Action;

    [OnlineEventField(Name = "id")]
    public ushort Id;
}

/// <summary>Servidor → quien pregunta: estado del fantasma (0 libre, 1 grabando, 2 guardada, 3 error).</summary>
[OnlineEvent(Key = "ACP_GhostState")]
public class GhostStatePacket : OnlineEvent<GhostStatePacket>
{
    [OnlineEventField(Name = "state")]
    public byte State;

    [OnlineEventField(Name = "seconds")]
    public ushort Seconds;

    [OnlineEventField(Name = "code")]
    public byte Code;

    [OnlineEventField(Name = "id")]
    public ushort Id;
}
