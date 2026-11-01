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
