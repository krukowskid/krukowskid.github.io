---
excerpt: "How to setup and use azure manage identity in local developement with docker desktop and visual studio."

title: "Azure Managed Identity with Local Docker Containers in Visual Studio"

image: /assets/posts/2023-07-23-Azure-Managed-Identity-with-Local-Docker-Containers-in-Visual-Studio/header.webp

date: 2023-07-23
last_modified_at: 2024-01-19

categories:
  - Blog

tags:
  - Azure
  - Managed Identity
  - Security
  - Containers
  - Visual Studio
  - Docker

---

* toc
{:toc .large only} 

# Introduction

Microsoft has recently rolled out some exciting updates to Visual Studio and Azure identity packages, including the support for [workload identity](/blog/A-Step-by-Step-Guide-to-installing-Azure-Workload-Identities-on-AKS/).

One of the most awaited features by me was the Azure identities support in local Docker containers, which brings a unified developer experience. Starting from version 17.6, this support is finally available! However, this new capability wasn't widely announced, and I'm here to shed light on it!

Managed identity is a fantastic mechanism that allows you to assign an identity to your application and authenticate it with Azure services without using passwords or connection strings. It offers fine-grained access policies based on RBAC access, making it a powerful tool. Additionally, working with identities in Visual Studio simplifies local development. If your application uses managed identity authentication, and your Visual Studio logged-in account has the proper permissions (e.g., to Azure Storage or a database), it will connect seamlessly without the need for a connection string in application settings.

Until now, managed identity support in local Docker containers was limited, and developers had to use workarounds. This led to an inconsistent developer experience where containers were used only for deployments, but local development and debugging were based on IIS or CLR.

# How to enable managed identity for containers?

## Requirements
To get started with managed identity for containers, you'll need the following:

- Visual Studio 17.6 or later.
- `azure.identity` package version 1.9.0 or later.
- `Microsoft.VisualStudio.Azure.Containers.Tools.Targets` package version 1.18.1 or later.
- Docker Desktop with WSL (for Windows machines).
- A Dockerfile for your project.

## Steps
1. Ensure that you are using the latest version of Visual Studio. You can check for updates by clicking `Help -> Check for updates`<br>
![Visual Studio check for updates](/assets/posts/2023-07-23-Azure-Managed-Identity-with-Local-Docker-Containers-in-Visual-Studio/Visual-Studio-check-for-updates.webp)<br>
*Visual Studio check for updates*<br><br>
Make sure your version is >=17.6.
![Visual Studio update window](/assets/posts/2023-07-23-Azure-Managed-Identity-with-Local-Docker-Containers-in-Visual-Studio/Visual-Studio-update-window.webp)<br>
*Visual Studio update window*<br><br>
2. [Install the latest version of Docker Desktop](https://www.docker.com/) with WSL on your Windows machine if you haven't already.

3. Make sure you have a Dockerfile in your project.<br>
![Dockerfile in project](/assets/posts/2023-07-23-Azure-Managed-Identity-with-Local-Docker-Containers-in-Visual-Studio/Dockerfile-in-project.webp)<br>
*Dockerfile in project*<br><br>
If you don't have one yet, you can auto-generate it by right-clicking on your project and selecting `Add -> Docker support...`<br>
![Add Docker support option in VS](/assets/posts/2023-07-23-Azure-Managed-Identity-with-Local-Docker-Containers-in-Visual-Studio/Add-Docker-support-option-in-VS.webp)<br>
*Add Docker support option in VS*<br><br>
If you haven't add Docker support from VS, you will also need to add a project launch profile with proper settings like ports and startup variables. You can add lanuch profile by going to `Debug -> project Debug Properties`<br>
![Debug properties option](/assets/posts/2023-07-23-Azure-Managed-Identity-with-Local-Docker-Containers-in-Visual-Studio/Debug-properties-option.webp)<br>
*Debug properties option*<br><br>
and click on Add option in Launch Profile window
![Add Docker Launch Profile](/assets/posts/2023-07-23-Azure-Managed-Identity-with-Local-Docker-Containers-in-Visual-Studio/Add-Docker-Launch-Profile.webp)<br>
*Add Docker Launch Profile*
4. Update your project to use version >=1.9.0 of the Azure.Identity package. You can install or update the package by right-clicking on your solution in `Solution Explorer -> Manage NuGet packages for the solution`, or do the same in the context of your project.<br>
![Add NuGet package](/assets/posts/2023-07-23-Azure-Managed-Identity-with-Local-Docker-Containers-in-Visual-Studio/Add-NuGet-package.webp)<br>
*Add NuGet package*

5. Lastly, add the `Microsoft.VisualStudio.Azure.Containers.Tools.Targets` package with a version `>=1.18.1`.


From now on, your container will have access to your logged-in account. 

![Visual Studio logged-in identity](/assets/posts/2023-07-23-Azure-Managed-Identity-with-Local-Docker-Containers-in-Visual-Studio/Visual-Studio-logged-in-identity.webp)<br>
*Visual Studio logged-in identity*

If you use `DefaultAzureCredential()` in your application code, it will utilize VisualStudioIdentity when running locally and `WorkloadIdentityCredential` or `ManagedIdentityCredential` when deployed to Azure.

## Sample code

In the code snippet provided, `DefaultAzureCredential()` plays a crucial role in enabling secure and seamless retrieval of local configuration from Azure App Configuration and Azure Key Vault without the need to store any passwords or connection strings. This code is utilized both during development and in the deployed application, ensuring a consistent and secure approach throughout the entire development lifecycle. 

{% raw %}
```csharp
builder.Host.ConfigureAppConfiguration((context, config) =>
{
    var settings = config.Build();
    config.AddAzureAppConfiguration(options =>
    {
        options.Connect(new Uri(settings["AppConfiguration:Endpoint"]), new DefaultAzureCredential())
               .ConfigureKeyVault(keyVault =>
               {
                   keyVault.SetCredential(new DefaultAzureCredential());
    });
});
```
{% endraw %}

# How it works

The mechanism behind this is fairly simple. Visual Studio maps volumes to Docker, exposing the token to the container. One drawback is that running container directly from CLI or Docker Desktop still requires some workarounds to make it work with developer identity. However, Visual Studio has support for Docker-compose, allowing you to start multiple containers from VS with rich debugging capabilities and described above Azure identity support.

![Volumes mounted by VS](/assets/posts/2023-07-23-Azure-Managed-Identity-with-Local-Docker-Containers-in-Visual-Studio/Volumes-mounted-by-VS.webp)<br>
*Volumes mounted by VS*

# Conslusion 

The recent updates to Visual Studio and Azure identity packages bring improved support for workload identity and enhanced capabilities. Managed identity simplifies authentication with Azure services and offers better security. Using those features makes development easier and provides a more consistent experience between local and cloud deployment. So, make sure to update your Visual Studio and packages to leverage these powerful features!
