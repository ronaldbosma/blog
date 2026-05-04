---
title: "Logic Apps Standard Extension for Azure Developer CLI (azd)"
date: 2026-05-04T17:30:00+02:00
publishdate: 2026-05-04T17:30:00+02:00
lastmod: 2026-05-04T17:30:00+02:00
tags: [ "azd", "Azure", "Azure Developer CLI", "Azure Integration Services", "Logic Apps" ]
summary: "Deploying a Logic Apps Standard project with azd currently requires configuring Node.js as the language, even when your project has nothing to do with Node. In this post, I'll introduce the azure.logicappsstandard extension I created to fix this, and walk through how to use it for both a basic Logic App and one that includes a .NET custom code project."
draft: true
---

I've been working with the [Azure Developer CLI (azd)](https://learn.microsoft.com/en-us/azure/developer/azure-developer-cli/) to deploy Logic Apps Standard projects. Azd doesn't have native support for Logic Apps Standard, so you have to work around it by configuring `language: js` and `host: function` in your `azure.yaml`. That works, but it creates an unnecessary dependency on Node.js, even when your project has nothing to do with Node. It also doesn't handle the case where your Logic App includes a .NET custom code project.

To address this, I created the `azure.logicappsstandard` azd extension. The extension introduces the `logicappsstandard` language, which handles packaging Logic Apps Standard projects correctly, including support for custom code projects.

In this post, I'll explain the problem in more detail, introduce azd extensions and walk through how to install and use the `azure.logicappsstandard` extension.

### Table of Contents

- [The Problem with Deploying Logic Apps Using azd](#the-problem-with-deploying-logic-apps-using-azd)
- [azd Extensions](#azd-extensions)
- [Installing the Extension](#installing-the-extension)
- [Packaging a Logic App Without Custom Code](#packaging-a-logic-app-without-custom-code)
- [Packaging a Logic App with Custom Code](#packaging-a-logic-app-with-custom-code)
- [Troubleshooting](#troubleshooting)
- [Conclusion](#conclusion)

### The Problem with Deploying Logic Apps Using azd

When you want to deploy a Logic Apps Standard project using azd, there's no built-in language option for it. The standard workaround is to configure the service with `language: js` and `host: function` in your `azure.yaml`:

```yaml
services:
  logicapp:
    project: ./src/logicapp
    host: function
    language: js
```

This works because Logic Apps Standard uses the Azure Functions runtime under the hood. But it introduces a dependency on Node.js that isn't needed if your project doesn't contain any JavaScript. Every developer and CI/CD agent that deploys the template needs Node.js installed for no real reason.

The situation gets more complicated when your Logic App includes a [custom code project](https://learn.microsoft.com/en-us/azure/logic-apps/create-run-custom-code-functions). Custom code projects let you add .NET functions that your workflows can call. Before packaging the Logic App, you need to build the .NET project so the compiled output gets included in the deployment zip. With the `js` language workaround, you have to add a `prepackage` hook to trigger the build manually:

```yaml
services:
  logicapp:
    project: ./src/logicapp
    dist: Workflows
    host: function
    language: js
    hooks:
      prepackage:
        shell: pwsh
        run: ../../hooks/prepackage-logicapp-build-functions-project.ps1
        interactive: true
```

This works, but it means writing and maintaining extra hook scripts. I opened [a discussion in the azd repository](https://github.com/Azure/azure-dev/discussions/6956) proposing native support for Logic Apps Standard, where azd maintainer [wbreza](https://github.com/wbreza) suggested using the azd extension framework instead. That turned out to be exactly the right tool for the job.

### azd Extensions

> **Note**: azd extensions are currently in beta. Features and APIs may change. See the [Azure Developer CLI extensions overview](https://learn.microsoft.com/en-us/azure/developer/azure-developer-cli/extensions/overview) for the latest information.

[Azure Developer CLI extensions](https://learn.microsoft.com/en-us/azure/developer/azure-developer-cli/extensions/overview) are modular components that extend the functionality of azd. They allow you to add new capabilities, automate workflows and integrate with other services directly from the CLI without modifying azd itself.

Extensions are distributed through extension sources, which are file or URL based manifests that list available extensions. Think of them as NuGet feeds or npm registries for azd. By default, azd is configured with the official extension source registry, so you can install extensions without any additional setup.

The extension framework also supports a concept called a Framework Service Provider, which is what I used for the `azure.logicappsstandard` extension. It lets an extension register itself as the handler for a custom language value in `azure.yaml`. When azd encounters `language: logicappsstandard`, it hands off the build and package phases to the extension instead of using the built-in handling.

### Installing the Extension

To install the `azure.logicappsstandard` extension, run:

```shell
azd ext install azure.logicappsstandard
```

If you already have the extension installed and want to upgrade to the latest version, run:

```shell
azd ext upgrade azure.logicappsstandard
```

The source code for the extension is available at [https://github.com/Azure/azure-dev/tree/main/cli/azd/extensions/azure.logicappsstandard](https://github.com/Azure/azure-dev/tree/main/cli/azd/extensions/azure.logicappsstandard).

### Packaging a Logic App Without Custom Code

If your Logic App doesn't include a custom code project, the setup is straightforward. Assume your template has the following project structure:

```
└── src
    └── logicapp
        ├── .vscode
        ├── artifacts
        ├── lib
        ├── workflow1
        │   └── workflow.json
        ├── workflow2
        │   └── workflow.json
        ├── workflow-designtime
        ├── .funcignore
        ├── .gitignore
        ├── host.json
        └── local.settings.json
```

Configure your service in `azure.yaml` like this:

```yaml
services:
  logicapp:
    project: ./src/logicapp
    host: function
    language: logicappsstandard
```

The extension packages everything under `./src/logicapp` into a zip file. Because `host: function` is used, the exclusions in `.funcignore` are respected and only the relevant files are included in the package. No Node.js required.

### Packaging a Logic App with Custom Code

If your Logic App includes a custom code project, the project structure typically looks like this:

```
└── src
    └── logicapp
        ├── Functions
        │   ├── MyFunctions.cs
        │   ├── Functions.csproj
        │   └── ...
        └── Workflows
            ├── workflow1
            │   └── workflow.json
            ├── workflow2
            │   └── workflow.json
            ├── host.json
            └── ...
```

Here the workflows are in a `Workflows` subfolder instead of at the root of the project. There's also a `Functions` folder containing the custom code project that needs to be built before packaging.

Configure your service in `azure.yaml` like this:

```yaml
services:
  logicapp:
    project: ./src/logicapp
    dist: Workflows
    host: function
    language: logicappsstandard
    customCodeProject: Functions/Functions.csproj
```

When azd runs the package phase, the extension first builds the custom code project specified in `customCodeProject` and then packages the Logic App artifacts from the `dist` folder. No prepackage hook needed.

The `customCodeProject` property is the path to the `.csproj` file, relative to the `project` folder. Make sure the required build toolchain is installed on the machine running the deployment. For .NET 8 projects that means the .NET 8 SDK. For .NET Framework projects you need .NET Framework or MSBuild tools.

### Troubleshooting

If you see the following error while packaging your Logic App, azd couldn't find an installed extension that provides the `logicappsstandard` language:

```
ERROR: initializing service '...', getting framework service: language 'logicappsstandard' is not supported by
built-in framework services and no extensions are currently providing it
```

Make sure you've installed the `azure.logicappsstandard` extension by running:

```shell
azd ext install azure.logicappsstandard
```

If the extension is already installed, verify that the default extension source is configured by running `azd ext source list`. If the default source is missing, add it with:

```shell
azd extension source add -n azd -t url -l "https://aka.ms/azd/extensions/registry"
```

### Conclusion

The `azure.logicappsstandard` extension removes the Node.js dependency from Logic Apps Standard deployments and adds first-class support for custom code projects, without needing prepackage hooks or custom scripts. If you're deploying Logic Apps Standard with azd, give it a try.

Since azd extensions are still in beta, there may be rough edges. If you run into issues or have suggestions, feel free to open an issue or discussion in the [azure-dev repository](https://github.com/Azure/azure-dev).
