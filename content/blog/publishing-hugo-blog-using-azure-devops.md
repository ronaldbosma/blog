---
title: "Publishing Hugo Blog Using Azure Devops"
date: 2019-03-24T00:00:00+01:00
publishdate: 2019-03-24T00:00:00+01:00
lastmod: 2019-03-24T00:00:00+01:00
image: "images/blog/publishing-hugo-blog-using-azure-devops.jpg"
tags: []
comments: true
draft: true
---

In this post I'll give a step-by-step explanation on how I publish my Hugo blog to GitHub Pages using Azure DevOps.

### Preperations

In Azure Devops you'll need a project that has the 'Pipelines' Azure DevOps service enabled. You can enable this service in your Project settings.

There are also two extension we'll need to intall from the Marketplace. These will be installed at the Organization level in Azure DevOps. So be sure you have the proper permissions.

#### Installing the Hugo extension

We're going to use the Hugo extension to generate our Hugo site. You can find it [here](https://marketplace.visualstudio.com/items?itemName=giuliovdev.hugo-extension) in the Marketplace. You'll have to sign in first before you can actually install the extension.

After signing in. Click 'Get it free'. Select your Azure DevOps organization and click 'Install'.

#### Installing the GitHub Pages Publish extension

We also need the GitHub Pages Publish extension to publish our Hugo site to GitHub pages. You can find it [here](https://marketplace.visualstudio.com/items?itemName=AccidentalFish.githubpages-publish) in the Marketplace.

Click 'Get it free' again. Select your Azure DevOps organization and click 'Install'.

### Generate Hugo site

#### Create build pipeline linked to GitHub

We'll start with a new build pipeline. (_See [create your first pipeline](https://docs.microsoft.com/en-us/azure/devops/pipelines/get-started-yaml?view=azure-devops) for a detailed explanation._)

- Open your Azure DevOps project.
- In the left menu choose Pipelines > Builds.
- Click the 'New pipeline' button.
- Select 'GitHub' as the source of your code.
- Select your blog repository containing your Hugo templates, themes, markdown posts, etc.
- Install Azure Pipelines in your GitHub account if you haven't already.
- Authorize Azure Pipelines to access your GitHub resources.
- Select the pipeline template you want to start from. In our case 'Starter pipeline' will do fine.
- An editor is opened where you can configure your pipeline using yaml.  
  Remove all content from the .yml file. We'll start from scratch in the next section.

#### Configure the actual build pipeline

First of we can [configure a trigger](https://docs.microsoft.com/en-us/azure/devops/pipelines/yaml-schema?view=azure-devops&tabs=schema#trigger). This will configure the build to trigger whenever code is pushed to master.

```yaml
trigger:
- master
```

The Hugo task we're going to use, uses PowerShell. So we'll have to use a Windows VM for as a build agent.

```yaml
pool:
  vmImage: 'vs2017-win2016'  # need a Windows host because the Hugo task uses PowerShell
```

I've included the Hugo theme I use as a submodule in my blog repository. So the first build step is to [checkout the blog repository including the theme submodule](https://docs.microsoft.com/en-us/azure/devops/pipelines/yaml-schema?view=azure-devops&tabs=schema#checkout).

```yaml
steps:
- checkout: self
  displayName: 'Checkout repository including submodules'
  submodules: true  # true so Hugo theme submodule is checked out
```

Next up is to generate the Hugo site. This will use the Hugo task we've installed earlier and output the result to the artifact staging directory.  

```yaml
- task: HugoTask@1
  displayName: 'Generate Hugo site'
  inputs:
    destination: '$(Build.ArtifactStagingDirectory)'
```

You can find an description of the possible parameters [here](https://github.com/giuliov/hugo-vsts-extension/blob/master/README.md). Have a look at the [task.json](https://github.com/giuliov/hugo-vsts-extension/blob/master/hugo-task/task.json) if you're looking for the exact input names.

The last step is to publish the generate Hugo site as an artifact of our build. This will make it possible use a release pipeline when publishing the site to GitHbub pages.

```yaml
- task: PublishPipelineArtifact@0
  displayName: 'Publish Hugo site as artifact'
  inputs:
    artifactName: 'hugo-site'
    targetPath: '$(Build.ArtifactStagingDirectory)'
```

That's it. You can click 'Save and run. Provide a comment and click 'Save and run' again. This will create an 'azure-pipelines.yml' file in your repository containing your build pipeline. It will then trigger a build.

You can find the final .yml [here](https://github.com/ronaldbosma/blog/blob/master/azure-pipelines.yml).

After your build succeeds it should have an artifact as shown in the image below.
![Build artifacts](../../images/blog/publishing-hugo-blog-using-azure-devops/hugo-site-artifacts.png)

### Release pipeline

Now that we have a successful build it's time to create a release.

- Open your Azure DevOps project.
- In the left menu choose Pipelines > Releases.
- Click the 'New pipeline' button.
- Select the 'Empty job' template.
- Give the stage a name like 'GitHub Pages'.
- Click 'Add an artifact'.
- Select 'Build' as the source type and select the build we've just created as the source. Enter a different source alias if you want, like 'blog'.  
  ![Add artifact](../../images/blog/publishing-hugo-blog-using-azure-devops/release-add-an-artifact.png)
  
- Enable the 'Continuous deployment trigger' so the release will automatically start after the build succeeds.  
![Continuous deployment trigger](../../images/blog/publishing-hugo-blog-using-azure-devops/release-continuous-deployment-trigger.png)
- Open the Tasks tab for the 'GitHub Pages' stage.
- Add the 'Publish to GitHub Pages' task and configure it:
  - 'Documentation Source' should be something like '$(System.DefaultWorkingDirectory)/blog/*'. Where blog is the artifact alias you've configured.
  - Configure the 'GitHub Personal Access Token' as [a secret](https://docs.microsoft.com/en-us/azure/devops/pipelines/process/variables?view=azure-devops&tabs=yaml%2Cbatch#secret-variables) using a variable.  
  ![Publish to GitHub Pages configuration](../../images/blog/publishing-hugo-blog-using-azure-devops/release-publish-to-github-pages.png)