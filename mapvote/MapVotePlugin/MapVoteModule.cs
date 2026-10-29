using AssettoServer.Server.Plugin;
using Autofac;

namespace MapVotePlugin;

public class MapVoteModule : AssettoServerModule<MapVoteConfiguration>
{
    protected override void Load(ContainerBuilder builder)
    {
        builder.RegisterType<TrackCatalog>().AsSelf().SingleInstance();
        builder.RegisterType<MapVotePlugin>().AsSelf().As<IAssettoServerAutostart>().SingleInstance();
    }
}
