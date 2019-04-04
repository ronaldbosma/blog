---
title: "Publishing Hugo Blog Using Azure Devops"
date: 2019-03-24T00:00:00+01:00
publishdate: 2019-03-24T00:00:00+01:00
lastmod: 2019-03-24T00:00:00+01:00
image: "images/publishing-hugo-blog-using-azure-devops/publishing-hugo-blog-using-azure-devops.jpg"
tags: [ "Azure DevOps", "Continuous Integration" ]
comments: true
draft: true
---

In this post I'll give a step-by-step explanation on how I publish my Hugo blog to GitHub Pages using Azure DevOps.

### Step 1: Prerequisites

You'll need a Azure DevOps project that has the 'Pipelines' Azure DevOps service enabled. You can enable this service in your Project settings.

There are also two extension we'll need to intall from the Marketplace. These will be installed at the Organization level in Azure DevOps. So be sure you have the proper permissions!

#### Install the Hugo extension

We're going to use the Hugo extension to generate our Hugo site. You can find it [here](https://marketplace.visualstudio.com/items?itemName=giuliovdev.hugo-extension) in the Marketplace. You'll have to sign in first before you can actually install the extension.

After signing in. Click 'Get it free'. Select your Azure DevOps organization and click 'Install'.

#### Generate GitHub Personal Access Token

We're going to need a GitHub Personal Access Token to publish the Hugo site to our GitHub Pages repository. So login to GitHub and follow these steps.

- Click in top right and choose 'Settings'.  
  ![GitHub settings](../../static/images/publishing-hugo-blog-using-azure-devops/access-token-settings.png)
  ![GitHub settings](../../../../../images/publishing-hugo-blog-using-azure-devops/access-token-settings.png)
- Choose 'Developer settings' in the left menu.
- Choose 'Personal access tokens' in the left menu.
- Click the 'Generate new token' button.
- Enter a description and select public_repo.  
 ![Generate token](../../static/images/publishing-hugo-blog-using-azure-devops/access-token-generate.png)
 ![Generate token](../../../../../images/publishing-hugo-blog-using-azure-devops/access-token-generate.png)
- Click 'Generate token' at the bottom of the page.
- Copy the token for later use.

### Step 2: Remove submodule

If you've included your GitHub pages repository as a submodule to your blog repo like me. You can remove the submodule, because you don't need it anymore.
Follow these steps:

- Delete the 'public' submodule section from the .gitmodules file.
- Stage the .gitmodules changes: `git add .gitmodules`
- Delete the 'public' submodule section from the .git/config file.
- Run `git rm --cached public` (no trailing slash).
- Remove the folder ".git/modules/public"
- Commit `git commit -m "Removed public submodule"`
- Delete the now untracked public folder from your cloned repo.

### Step 3: Build Hugo site

Now that we're finished with the preperations it's time to generate our Hugo site.

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

First of we can [configure a trigger](https://docs.microsoft.com/en-us/azure/devops/pipelines/yaml-schema?view=azure-devops&tabs=schema#trigger). The following will configure the build to trigger whenever code is pushed to master.

```yaml
trigger:
- master
```

The Hugo task we're going to use, uses PowerShell. So we'll have to use a Windows VM as a build agent.

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

Next up is to generate the Hugo site. This will use the Hugo task we've installed earlier. The output will be generated to the artifact staging directory.  

```yaml
- task: HugoTask@1
  displayName: 'Generate Hugo site'
  inputs:
    destination: '$(Build.ArtifactStagingDirectory)'
```

You can find a description of the possible parameters [here](https://github.com/giuliov/hugo-vsts-extension/blob/master/README.md). Have a look at the [task.json](https://github.com/giuliov/hugo-vsts-extension/blob/master/hugo-task/task.json) if you're looking for the exact input names.

The last step is to publish the generate Hugo site as an artifact of our build. This will make it possible to use a release pipeline when publishing the site to GitHbub pages.

```yaml
- task: PublishPipelineArtifact@0
  displayName: 'Publish Hugo site as artifact'
  inputs:
    artifactName: 'hugo-site'
    targetPath: '$(Build.ArtifactStagingDirectory)'
```

That's it. You can click 'Save and run'. Provide a comment and click 'Save and run' again. This will create an 'azure-pipelines.yml' file in your repository containing your build pipeline. You can find the final azure-pipelines.yml [here](https://github.com/ronaldbosma/blog/blob/master/azure-pipelines.yml).

Because of the trigger on master it will start a new build immediately. After your build succeeds it should have an artifact as shown in the image below.
![Build artifacts](../../static/images/publishing-hugo-blog-using-azure-devops/hugo-site-artifacts.png)
![Build artifacts](../../../../../images/publishing-hugo-blog-using-azure-devops/hugo-site-artifacts.png)

### Step 4: Publish Hugo site

Now that we have a successful build it's time to create a release. This will take the generated Hugo site and publish it to GitHub Pages.

- Open your Azure DevOps project.
- In the left menu choose Pipelines > Releases.
- Click the 'New pipeline' button.
- Select the 'Empty job' template.
- Give the stage a name. E.g. 'GitHub Pages'.
- Click 'Add an artifact'.
- Select 'Build' as the source type. As the source, select the build we've just created. Enter a different source alias if you want, like 'blog'.  
  ![Add artifact](../../static/images/publishing-hugo-blog-using-azure-devops/release-add-an-artifact.png)
  ![Add artifact](../../../../../images/publishing-hugo-blog-using-azure-devops/release-add-an-artifact.png)
  
- Enable the 'Continuous deployment trigger' so the release will automatically start after the build succeeds.  
![Continuous deployment trigger](../../static/images/publishing-hugo-blog-using-azure-devops/release-continuous-deployment-trigger.png)
![Continuous deployment trigger](../../../../../images/publishing-hugo-blog-using-azure-devops/release-continuous-deployment-trigger.png)
- Open the Tasks tab for the 'GitHub Pages' stage.
- Add the 'Publish to GitHub Pages' task and configure it:
  - 'Documentation Source' should be something like '$(System.DefaultWorkingDirectory)/blog/*'. Where blog is the artifact alias you've configured.
  - Configure the 'GitHub Personal Access Token' as [a secret](https://docs.microsoft.com/en-us/azure/devops/pipelines/process/variables?view=azure-devops&tabs=yaml%2Cbatch#secret-variables) using a variable.  
  ![Publish to GitHub Pages configuration](../../static/images/publishing-hugo-blog-using-azure-devops/release-publish-to-github-pages.png)
  ![Publish to GitHub Pages configuration](../../../../../images/publishing-hugo-blog-using-azure-devops/release-publish-to-github-pages.png)

  You can now trigger a new build. After the build succeeds the release will start and publish any change in your site to GitHub Pages.


```powershell
$docPath = "$(System.DefaultWorkingDirectory)/blog/*"
$githubusername = "ronaldbosma"
$githubemail = "release@ronaldbosma.github.io"
$githubaccesstoken = "$(github-personal-access-token)"
$repositoryname = "ronaldbosma.github.io"
$branch="master"
$commitMessage = "Automated Release $(Release.ReleaseId)"

$repoWorkingDirectory = "$(System.DefaultWorkingDirectory)/temp-repo"
    
Write-Host "Cloning existing GitHub Pages branch"

git clone https://$githubaccesstoken@github.com/$githubusername/$repositoryname.git --branch=$branch $repoWorkingDirectory --quiet

if ($lastexitcode -gt 0)
{
	Write-Host "##vso[task.logissue type=error;]Unable to clone repository - check username, access token and repository name. Error code $lastexitcode"
	[Environment]::Exit(1)
}

Write-Host "Copying new documentation into branch"
Copy-Item $docPath $repoWorkingDirectory -recurse -Force

Write-Host "Committing the GitHub Pages Branch"
cd $repoWorkingDirectory
git config core.autocrlf false
git config user.email $githubemail
git config user.name $githubusername
git add *
git commit -m $commitMessage

if ($lastexitcode -gt 0)
{
	Write-Host "##vso[task.logissue type=error;]Error committing - see earlier log, error code $lastexitcode"
	[Environment]::Exit(1)
}

git push

if ($lastexitcode -gt 0)
{
	Write-Host "##vso[task.logissue type=error;]Error pushing to gh-pages branch, probably an incorrect Personal Access Token, error code $lastexitcode"
	[Environment]::Exit(1)
}```