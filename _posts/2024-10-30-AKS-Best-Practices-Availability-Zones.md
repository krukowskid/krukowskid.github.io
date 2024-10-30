---
excerpt: "AKS Best Practices related to availability zones"

title: "AKS Best Practices Part1: Availability Zones"

image: /assets/posts/2024-10-30-AKS-Best-Practices-Part1-Availability-Zones/header.webp

date: 2024-10-30

categories:
  - Blog

tags:
  - Azure
  - AKS
  - Kubernetes
  - Containers
---

* toc
{:toc .large only} 

# Introduction

In the cloud era, deploying a Kubernetes cluster and ensuring it's up and running is a breeze - it just requires the budget. Unfortunately, this has led to the situation where everyone wants to use Kubernetes, believing it will solve potential scaling problems that likely will never materialize. Even worse, it affects architectural decisions, often making microservices seem like the only valid option regardless of what we are building. What I frequently see are microservices that cannot be deployed separately, overly complex pipelines and release processes, and additional tooling created solely to fix problems we introduced ourselves.  Although everything may be running smoothly, basic best practices are often overlooked, leading to a lack of control and visibility into what's really happening in our systems as it struggle with even minor issues.

Like every technology, Kubernetes comes with its own learning curve and architectural decisions. While cloud-managed Kubernetes takes away most infrastructure-related problems and challenges, there is still much to be done in terms of configuration, application setup, deployment strategies, monitoring, and other aspects that remain our responsibility. Let's dive into these aspects starting with Availability Zones.

## Availability zones

You are probably familiar with the concept that most Azure regions are composed of three separate locations. Each of those may contain multiple datacenters and is further divided into physical areas connected to different power sources, housed in separate racks, rooms, etc., and divided logically to manage updates and infrastructure change and also divided logically for updates and rolling out infrastructure changes (Availability Sets and Update Domains).
Storage follows similar principles, though it isn't mapped one-to-one with virtual machines because there are five fault domains for compute and two or three fault domains for storage, depending on the region. Additionally, zone numbers are unique to each tenant, so if you place something in Zone 1 in Tenant A and Tenant B, it may end up in different datacenters. So, how should you handle this in AKS? Many people overlook these aspects, and everything may work fine by default, but if you're seeking performance or reliability gains, there's a lot to consider!

Although it is not well described in AKS documentation, standard AKS nodes use Virtual Machine Scale Sets (VMSS), so most of the same concepts apply. However, VMSS is managed by AKS, and while we can modify its parameters, it's not recommended as these changes may be reverted, leading to unpredictable behavior.

### Differences between zone configurations

You might think that selecting no zone or all three zones is the same - it isn't. If you don't specify a zone (`[]` or `null`), it's considered a "regional deployment", meaning instances are placed in any zone at random, with no guarantee of distribution, so all instances could end up in a single zone.

What about selecting just one zone, like [1]? Machines and disks will be created only in that zone, but there's no guarantee for disks other than Premium v2 to be created within the same datacenter. These are managed by platformFaultDomainCount and Managed Disk fault domains, meaning that by default (which can't be changed in AKS), all nodes in the pool will spread across as many racks as possible.

Speaking of disks, Premium v2 will be created in the same datacenter as the VM, while Premium v1 disks are placed as close as possible based on best efford, and Standard disks have no guarantee of close proximity. This means an AKS node's disk might be created in not optimal location! This isn't as crazy as it sounds, but if you're aiming for each millisecond of latency, it's an important factor.

If you select all zones `[1,2,3]`, Azure will try to distribute resources evenly, but there's no guarantee. In VMSS, you can set the `zoneBalance` to `true` parameter to ensure even distribution, but this isn't supported in AKS. While you could set it on your own in VMSS, it might lead to unpredictable behavior. If you take this route, ensure you use ZRS disks. A pod in Zone 1 won't connect to a persistent volume in Zone 2, as AKS schedules pods where their disks are located. In case of zone failure, ZRS disks may have some transient connectivity, so ensure that you can handle such interruptions. 

Alternatively, you could create three node pools, each assigned to one zone. However, single nodepool with multiple zones is sufficient for most use-cases, as in the worst-case scenario, without multiple per-zone node pools, if one zone fails, a new node in an unaffected zone should be provisioned, and pods can be recreated there.

Usually, latency between zones is below 2 ms, if it unacceptable, deploy everything in a single zone (for example, Zone `[1]`), creating services like the node pool, disks and databases in it. This type of deployment is vulnerable to single-zone failure.
If you want to make sure that all nodes within the scale set, are close to each other use 

To achieve low latency with resiliency, configure three node pools each in separate zone. If you also want to use autoscaling feature with such setup, you should setup `balance-similar-node-groups` to `true`. The downside of it is that you need to configure multiple deployments and consider data replication between pods in separate zones to avoid synchronous processes. ZRS disks can handle zone replication, but in a synchronous way which affects performance and allows to attach to only one node at a time. Additionaly ZRS disks comes with higher cost.
Anyway the complexity depends on your system architecture. For example if you do not need storage attached to your pods you can probably omit this aspect and consider other factors like pod-to-pod communication. 

## Recommendations

Do not change any settings on your own in VMSS. Plan your strategy before creating a cluster, because you can only define availability zones during creation of the cluster or node pool.

1. For generic workloads without special requirements, aiming for cost-efficiency:
- Use the regional deployment model `[]`.
- Use LRS disks.

2. For best resiliency within a single region:
- Use the zonal deployment model `[1,2,3]` with a single node pool, and optionally use Pod Topology Spread Constraints to ensure pods are scheduled across zones.
- Use a node pool per zone, replicate application deployments for each zone, and limit each deployment to a specific zone using Pod Topology Spread Constraints.
- Use LRS/ZRS disks for ephemeral storage, or Azure Files if you need persistent storage across multiple pods.

3. For best performance:
- Deploy all resources (like AKS, databases, etc.) in a single zone, or use node pool per zone, and handle data on your own.
- Use proximity placement groups.
- Avoid ZRS disks, as they rely on synchronous replication.
- Use LRS Premium V2 disks.

# Conclusion

Unfortunately, AKS doesn’t yet offer the ability to fine-tune all settings within the managed Virtual Machine Scale Sets. However, I hope this post clarifies these aspects and helps you make the right decisions when setting up your cluster!
