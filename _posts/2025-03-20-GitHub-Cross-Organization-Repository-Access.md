---
excerpt: Learn how to securely access repositories across GitHub organizations without using Personal Access Tokens by using GitHub Apps.

title: GitHub Repositories Cross-Organization Access

image: /assets/posts/2025-03-20-GitHub-Cross-Organization-Repository-Access/header.webp

date: 2025-03-20

categories:
  - Blog

tags:
  - GitHub Actions
  - Security
  - CICD
  - Terraform

related_posts:
  - _posts/2023-09-27-GitHub-Powered-Terraform-Modules-Monorepo.md
---

* toc
{:toc .large only} 

# Introduction

While architecting and configuring GitHub Enterprise from scratch, I needed to create two separate organizations based on our company's software delivery structure. Reusing workflows and actions within the same organization was straightforward, requiring only the correct repository-level permissions. However, I encountered a significant challenge when trying to reference a Terraform Modules monorepo from another organization.

After researching the Internet and consulting with GitHub support, they suggested using a Personal Access Token (PAT) as the only solution. This approach has several drawbacks - PATs can be easily leaked, they expire, and they're tied to individual user accounts rather than services. Fortunately, I discovered a better solution: using GitHub Apps to securely access repositories across organizations!


In this article I focus on accessing the repository. However, you can use the same approach to access any resource in another organization.
{:.note title="important"}

# Why GitHub Apps Are Superior to PATs

Before diving into implementation, let's understand why GitHub Apps provide a better approach:
- **Fine-grained permissions** - Limit access to only what's needed
- **No user dependency** - Works independently of individual accounts
- **Short-lived tokens** - Automatically rotated, reducing security risks
- **Transparency** - Clear tracking of all cross-organization actions
- **Scalable management** - Easier to maintain across teams and projects

How about `GITHUB_TOKEN`?
Unfortunately GitHub token which is exposed to runners and controlled by permissions are scoped to the repository where the action is running.

# Implementation Guide

## Step 1: Create a GitHub App

First, create a GitHub App in the organization that hosts the repository you want to share:

1. Navigate to your organization settings
2. Open **Developer settings** → **GitHub Apps**
3. Click **New GitHub App**
4. Configure the following essential settings:
   - Application name (descriptive and recognizable - for example `RepositoryName-Read`)
   - Homepage URL (required - you can sue use your organization website)
   - Disable Webhooks - It's needed but required additional configuration.

## Step 2: Configure App Permissions

The permissions section is important and you should follow least privilege principle. For basic repository access:

- **Repository permissions**:
  - **Contents**: Read-only (or Write if you need to commit changes)
  - **Metadata**: Read-only (required)

For more complex scenarios, you might need additional permissions based on your workflow requirements.

## Step 3: Generate Authentication Credentials

After creating the app:

1. Note the **App ID** (not Client ID) displayed on the app's settings page. 
2. Scroll down to the **Private keys** section.
3. Click **Generate a private key** and save the downloaded file securely.

## Step 4: Install the App on Your Organization

Next, install your new app on the organization:

1. Navigate to the app's settings page
2. Click **Install App** in the sidebar
3. Select the organization
4. Choose whether to install on all repositories or select specific ones
   - **Best practice**: Limit access to only necessary repositories. Personally, I often create separate application for each repository, but it really depends on your secenario. 

### Store Secrets Securely

To complete the setup:
1. Add the App ID as a repository or organization secret. In this example I named it `APP_ID`
2. Open private key in a text editor and add content as a multiline secret. In this example I named it  `APP_PRIVATE_KEY`

## Step 6: Implement in Your Workflow

Now, integrate the app authentication into your workflow using the `actions/create-github-app-token` action:

{% raw %}
```yaml
jobs:
  access-cross-org-repo:
    runs-on: ubuntu-latest
    steps:
    - name: Generate GitHub App token
      uses: actions/create-github-app-token@v1.11.6
      id: app-token
      with:
        app-id: ${{ secrets.APP_ID }}
        private-key: ${{ secrets.APP_PRIVATE_KEY }}
        owner: source-organization-name

    - name: Checkout repository from other organization
      uses: actions/checkout@v4.2.2
      with:
        repository: target-organization-name/repository-name
        token: ${{ steps.app-token.outputs.token }}
        
    - name: Show cloned repository
      run: ls -la
```
{% endraw %}

If you have problems with the official GitHub action, you can fall back on the community action, which has served me well for a long time `tibdex/github-app-token@v2.1.0`.

{% raw %}
```yaml
- name: Generate GitHub App token
  uses: tibdex/github-app-token@v2.1.0
  id: app-token
  with:
    app_id: ${{ secrets.APP_ID }}
    private_key: ${{ secrets.APP_PRIVATE_KEY }}
    installation_retrieval_mode: organization
    installation_retrieval_payload: source-organization-name
```
{% endraw %}

## Real-World Implementation Example

Here's how I implemented this solution for accessing my [Terraform Modules Monorepo](/blog/GitHub-Powered-Terraform-Modules-Monorepo/) with gitref across organizations:

{% raw %}
```yaml
name: Deploy Infrastructure

on:
  workflow_dispatch:
  push:
    branches: [main]

jobs:
  terraform-plan:
    runs-on: ubuntu-latest
    steps:
    - name: Checkout current repository
      uses: actions/checkout@v4.2.2
    
    - name: Generate app token for cross-org access
      uses: actions/create-github-app-token@v1.11.6
      id: app-token
      with:
        app-id: ${{ secrets.APP_ID }}
        private-key: ${{ secrets.APP_PRIVATE_KEY }}
        owner: source-organization-name

    - name: Authenticate to git with bot token
      run: |
        echo ${{ steps.app-token.outputs.token }} | gh auth login --with-token
        gh auth setup-git

    - name: Setup Terraform
      uses: hashicorp/setup-terraform@v3
      
    - name: Initialize Terraform
      run: |
        terraform init
```
{% endraw %}

# Conclusion

Using GitHub Apps for cross-organization repository access provides a more secure, manageable, and scalable solution than Personal Access Tokens. This approach aligns with modern security practices by reducing the risk associated with long-lived credentials and individual user accounts.

By implementing GitHub Apps for cross-organization access, you'll improve your GitHub Enterprise security posture while maintaining the flexibility needed for complex multi-organization workflows.
