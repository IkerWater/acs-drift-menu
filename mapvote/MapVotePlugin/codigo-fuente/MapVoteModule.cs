using AssettoServer.Server.Plugin;
using Autofac;
using Microsoft.Extensions.Hosting;

namespace MapVotePlugin;

public class MapVoteModule : AssettoServerModule<MapVoteConfiguration>
{
    protected override void Load(ContainerBuilder builder)
    {
        // Si falta plugin_map_vote_cfg.yml en la carpeta de configuración, usar valores por defecto
        // en vez de impedir que arranque el servidor.
        builder.Register(_ => new MapVoteConfiguration()).AsSelf().SingleInstance().PreserveExistingDefaults();
        builder.RegisterType<TrackCatalog>().AsSelf().SingleInstance();
        builder.RegisterType<MapVotePlugin>().AsSelf().As<IHostedService>().SingleInstance();
    }
}
