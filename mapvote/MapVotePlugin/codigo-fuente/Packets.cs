using AssettoServer.Network.ClientMessages;

namespace MapVotePlugin;

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
