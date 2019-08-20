---
title: "Multi-stage YAML pipeline to create and publish NuGet packages"
date: 2019-08-20T00:00:00+01:00
publishdate: 2019-08-20T00:00:00+01:00
lastmod: 2019-08-20T00:00:00+01:00
image: "images/multi-stage-yaml-pipeline-to-create-and-publish-nuget-packages.jpg"
tags: [ "Azure Pipelines", "Azure DevOps", "NuGet", "Continuous Integration", "YAML" ]
comments: false
draft: true
---

I've recently created a NuGet package that I published on nuget.org. To make this proces a smoothed and simple as possible I've created a pipeline in Azure DevOps to create and publish my package.

Using the Multi-stage pipelines feature that's currently in preview I've created a single pipeline that:

- builds my solution
- creates a prerelease version of my package
- creates a release version of my package
- automatically publishes the prerelease package to a private Azure DevOps Artifacts feed
- publishes the release version of the package to nuget.org if I approve this


???Why this pipeline???


In this post I'll go into how the pipeline is set up.

First step is to enable the Multi-stage pipelines preview feature:

- Login to your Azure DevOps environment.
- Click on your avatar in the top right corner.
- Choose Preview features.
- Enable the Multi-stage pipelines option.

![Multi-stage pipelines preview feature](../../static/images/multi-stage-yaml-pipeline-to-create-and-publish-nuget-packages/preview-feature-multi-stage-pipelines.png)
![Multi-stage pipelines preview feature](../../../../../images/multi-stage-yaml-pipeline-to-create-and-publish-nuget-packages/preview-feature-multi-stage-pipelines.png)

Now that the preview feature is enabled we can start by creating a pipeline. So create a new pipeline and connect it to one of the sources that supports YAML, like Azure Repositories or GitHub. You can choose any pipeline template, because we're going to clear it and start from scratch. [Build, test, and deploy .NET Core apps](https://docs.microsoft.com/azure/devops/pipelines/languages/dotnet-core) is a good starting point if you haven't created a pipeline before.

### Create NuGet packages

Clear the yml file and add the following yaml. This will build any projects in your git repository using the .NET Core 2.2 SDK.

```yaml
trigger:
- master

stages:

- stage: 'Build'
  variables:
    buildConfiguration: 'Release'

  jobs:
  - job:
    pool:
      vmImage: 'ubuntu-latest'

    workspace:
      clean: all

    steps:
    - task: UseDotNet@2
      displayName: 'Use .NET Core sdk'
      inputs:
        packageType: sdk
        version: 2.2.x
        installationPath: $(Agent.ToolsDirectory)/dotnet
    
    - task: DotNetCoreCLI@2
      displayName: "NuGet Restore"
      inputs:
        command: restore
        projects: '**/*.csproj'
    
    - task: DotNetCoreCLI@2
      displayName: "Build Solution"
      inputs:
        command: build
        projects: '**/*.csproj'
        arguments: '--configuration $(buildConfiguration)'
```

There are a few things to take notice of. First the pipeline will trigger on a push to master. Next we specify the `stages` keyword. Indicating that this is a multi-stage pipeline. The first stage will be to build the solution and create the packages.

My package targets netstandard2.0 so we're installing the .NET Core SDK as the first step in the pipeline. Note that instead of using the `DotNetCoreInstaller` task we're using the `UseDotNet` task. This task allows us to specify a wildcard for the version. Ensuring that we're always using the latest available version of the .NET Core SDK.

Next we restore any NuGet packages we require and then build the solution.

To keep the example simple. I've left out steps to analyse the solution using SonarQube and running unit tests. The full pipeline of my package including these steps can be found [here](https://github.com/ronaldbosma/FluentAssertions.ArgumentMatchers.Moq/blob/master/azure-pipelines.yml).

Now that the solution has been build we can create our prerelease and release versions of the NuGet package.

To be able to create a prerelease package the first thing we need to do is configure the version prefix in the csproj of our project. See the example below.

```xml
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <VersionPrefix>1.2.0</VersionPrefix>
  </PropertyGroup>
</Project>
```

If you have a `Version` tag specified than change this to `VersionPrefix`. This will make it possible to add a prerelease suffix to the version.

You might also have the `GeneratePackageOnBuild` property set to true. Altough it can't hurt. It's not necessary. So you can remove it if you want.

Not that we've prepared our project go back to the pipeline editor and add the following YAML at the end.

```yaml
    - task: DotNetCoreCLI@2
      displayName: 'Create NuGet Package - Release Version'
      inputs:
        command: pack
        packDirectory: '$(Build.ArtifactStagingDirectory)/packages/releases'
        arguments: '--configuration $(buildConfiguration)'
        nobuild: true
    
    - task: DotNetCoreCLI@2
      displayName: 'Create NuGet Package - Prerelease Version'
      inputs:
        command: pack
        buildProperties: 'VersionSuffix="$(Build.BuildNumber)"'
        packDirectory: '$(Build.ArtifactStagingDirectory)/packages/prereleases'
        arguments: '--configuration $(buildConfiguration)'
```

The first task will create the release version of the package. The generated nupkg file will be created in the folder `packages/releases` of the artifact staging directory. The `nobuild` input is set to `true`. Meaning the command will not rebuild the solution.

The second task will create the prerelease version of the package. The output will be generated in the `packages\prereleases` folder. Allthough this task looks similar to the release version there are two differences.

First of all. Using the `buildProperties` input we're adding the build number to the version of the package. Anything specified in the version suffix will be added after the version prefix, seperated by a -. E.g. if the version prefix is `1.2.0` and the build number is `20190820.1`. Than the version of the package will be `1.2.0-20190820.1`.

The second difference is that the `nobuild` input is not specified. To add the version suffix to the package a build is necessary. Because of this, the order of these two tasks is also important. If you first create the prerelease version and than the release version (and have `nobuild` set to `true`), the release version assemblies will have a product version containing the prerelease suffix. So the product version would be `1.2.0-20190820.1` instead of `1.2.0`.

The last step in the build stage is to publish the packages as an artifact of the pipeline. Making it possible to access them in following stages. Add the following task to create a packages artifact in the pipeline.

```yaml
    - task: PublishBuildArtifacts@1
      displayName: 'Publish Artifact'
      inputs:
        artifactName: 'packages'
        PathtoPublish: '$(Build.ArtifactStagingDirectory)/packages'
```

### Publish prerelease package to Azure DevOps Artifacts feed

```yaml
- stage: 'PublishPrereleaseNuGetPackage'
  displayName: 'Publish Prerelease NuGet Package'
  dependsOn: 'Build'
  condition: succeeded()
  jobs:
  - job:
    pool:
      vmImage: 'ubuntu-latest'

    steps:
    - checkout: none

    - task: DownloadPipelineArtifact@2
      displayName: 'Download NuGet package'

    - task: NuGetCommand@2
      displayName: 'Push NuGet Package'
      inputs:
        command: 'push'
        packagesToPush: '$(Pipeline.Workspace)/packages/prereleases/*.nupkg'
        nuGetFeedType: 'internal'
        publishVstsFeed: 'Test'
```

### Publish release package to nuget.org

```yaml
- stage: 'PublishReleaseNuGetPackage'
  displayName: 'Publish Release NuGet Package'
  dependsOn: 'PublishPrereleaseNuGetPackage'
  condition: succeeded()
  jobs:
  - deployment:
    pool:
      vmImage: 'ubuntu-latest'
    environment: 'nuget-org'
    strategy:
     runOnce:
       deploy:
         steps:
         - task: NuGetCommand@2
           displayName: 'Push NuGet Package'
           inputs:
             command: 'push'
             packagesToPush: '$(Pipeline.Workspace)/packages/releases/*.nupkg'
             nuGetFeedType: 'external'
             publishFeedCredentials: 'NuGet'
```
