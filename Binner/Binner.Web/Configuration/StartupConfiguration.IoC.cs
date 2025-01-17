﻿using ApiClient.OAuth2;
using Binner.Common;
using Binner.Common.Integrations;
using Binner.Common.IO.Printing;
using Binner.Common.Services;
using Binner.Common.StorageProviders;
using Binner.Model.Common;
using Binner.Web.ServiceHost;
using Binner.Web.WebHost;
using LightInject;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.DependencyInjection;
using System.Reflection;

namespace Binner.Web.Configuration
{
    public partial class StartupConfiguration
    {
        public static void ConfigureIoC(IServiceContainer container, IServiceCollection services)
        {
            // https://docs.microsoft.com/en-us/aspnet/core/fundamentals/dependency-injection?view=aspnetcore-2.1#service-lifetimes
            // Transient = created each time requested, Scoped = once per http/scope request, Singleton = first time requested only
            // allow the container to be injected
            services.AddSingleton<IServiceContainer, ServiceContainer>();
            services.AddSingleton(container);

            services.AddTransient<IWebHostFactory, WebHostFactory>();
            container.RegisterInstance(container);

            // register printer configuration
            RegisterPrinterService(container);

            // register Api integrations
            RegisterApiIntegrations(container);

            // register services
            RegisterServices(container);

            // configure mapping
            RegisterMappingProfiles(container);

            // register storage provider
            // we are doing it this way because RegisterSingleton swallows the exception, we would like to shutdown the server if there is a configuration problem
            container.Register<IStorageProviderFactory, StorageProviderFactory>(new PerContainerLifetime());
            var providerFactory = container.GetInstance<IStorageProviderFactory>();
            var storageProviderConfig = container.GetInstance<StorageProviderConfiguration>();
            var storageProvider = providerFactory.Create(storageProviderConfig.Provider, storageProviderConfig.ProviderConfiguration);
            container.RegisterInstance(storageProvider);

            // register the font manager
            container.Register<FontManager>(new PerContainerLifetime());

            // request context
            container.Register<RequestContextAccessor>(new PerContainerLifetime());

            // the main server app
            container.Register<BinnerWebHostService>(new PerContainerLifetime());

            // register the CertificateProvider for providing access to the server certificate
            var config = container.GetInstance<WebHostServiceConfiguration>();
        }

        private static void RegisterMappingProfiles(IServiceContainer container)
        {
            var profile = new BinnerMappingProfile();
            AnyMapper.Mapper.Configure(config =>
            {
                config.AddProfile(profile);
            });
            // register automapper
            var config = new AutoMapper.MapperConfiguration(cfg => cfg.AddMaps(Assembly.GetEntryAssembly()));
            config.AssertConfigurationIsValid();
            container.RegisterInstance(config.CreateMapper());
        }

        private static void RegisterPrinterService(IServiceContainer container)
        {
            container.Register<IBarcodeGenerator, BarcodeGenerator>(new PerContainerLifetime());
            container.Register<ILabelPrinterHardware>((serviceFactory) =>
            {
                var config = serviceFactory.GetInstance<WebHostServiceConfiguration>();
                var barcodeGenerator = serviceFactory.GetInstance<IBarcodeGenerator>();
                return new DymoLabelPrinterHardware(new PrinterSettings
                {
                    PrinterName = config.PrinterConfiguration.PrinterName,
                    PartLabelName = config.PrinterConfiguration.PartLabelName,
                    PartLabelSource = config.PrinterConfiguration.PartLabelSource,
                    PartLabelTemplate = config.PrinterConfiguration.PartLabelTemplate,
                    LabelDefinitions = config.PrinterConfiguration.LabelDefinitions
                }, barcodeGenerator);
            }, new PerScopeLifetime());
        }

        private static void RegisterServices(IServiceContainer container)
        {
            container.Register<IPartService, PartService>(new PerContainerLifetime());
            container.Register<IPartTypeService, PartTypeService>(new PerContainerLifetime());
            container.Register<IProjectService, ProjectService>(new PerContainerLifetime());
            container.Register<ICredentialService, CredentialService>(new PerContainerLifetime());
            container.Register<ISettingsService, SettingsService>(new PerContainerLifetime());
        }

        private static void RegisterApiIntegrations(IServiceContainer container)
        {
            container.Register<OAuth2Service>((serviceFactory) =>
            {
                var config = serviceFactory.GetInstance<WebHostServiceConfiguration>();
                return new OAuth2Service(config.Integrations.Digikey);
            }, new PerContainerLifetime());
            container.Register<OctopartApi>((serviceFactory) =>
            {
                var config = serviceFactory.GetInstance<WebHostServiceConfiguration>();
                var httpContextAccessor = serviceFactory.GetInstance<IHttpContextAccessor>();
                return new OctopartApi(config.Integrations.Octopart.ApiKey, config.Integrations.Octopart.ApiUrl, httpContextAccessor);
            }, new PerContainerLifetime());
            container.Register<DigikeyApi>((serviceFactory) =>
            {
                var config = serviceFactory.GetInstance<WebHostServiceConfiguration>();
                var oAuth2Service = serviceFactory.GetInstance<OAuth2Service>();
                var credentialService = serviceFactory.GetInstance<ICredentialService>();
                var httpContextAccessor = serviceFactory.GetInstance<IHttpContextAccessor>();
                return new DigikeyApi(oAuth2Service, config.Integrations.Digikey.ApiUrl, credentialService, httpContextAccessor);
            }, new PerContainerLifetime());
            container.Register<MouserApi>((serviceFactory) =>
            {
                var config = serviceFactory.GetInstance<WebHostServiceConfiguration>();
                var httpContextAccessor = serviceFactory.GetInstance<IHttpContextAccessor>();
                return new MouserApi(config.Integrations.Mouser.ApiKeys.SearchApiKey, config.Integrations.Mouser.ApiKeys.OrderApiKey, config.Integrations.Mouser.ApiKeys.CartApiKey, config.Integrations.Mouser.ApiUrl, httpContextAccessor);
            }, new PerContainerLifetime());
            container.Register<AliExpressApi>((serviceFactory) =>
            {
                var config = serviceFactory.GetInstance<WebHostServiceConfiguration>();
                var httpContextAccessor = serviceFactory.GetInstance<IHttpContextAccessor>();
                return new AliExpressApi(config.Integrations.AliExpress.ApiKey, config.Integrations.AliExpress.ApiUrl, httpContextAccessor);
            }, new PerContainerLifetime());
        }
    }
}
