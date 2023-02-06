# SME Labs - GCP Reference Architecture (Feb '23)

## Introduction

*Hi! Welcome to EMEA Public Cloud SME Trainings / Google Cloud reference architecture lab.*

*I tried to summarize here basic information about the most commonly used architecture. I'll walk you through it during the session and also will talk about when it does NOT work (which happens and you should know why). If you're doing this lab outside of my session, feel free to reach out with any questions.*

*Once you start the lab by hitting the green "Start Lab" button, Qwiklabs will create a temporary environment for you consisting of 2 projects (let's call them netsec and workloads) with several VPC networks and subnets (ext, int, hasync and mgmt in the netsec, tier1 and tier2 in workloads). Once it's running you'll see your temporary student password and a link to cloud console under the red "End Lab" button. You can switch between the projects using the drop-down at the top of the console.*

*Have fun!*

*Bartek Mo.*

## Step 1 - deploy the FGT HA cluster

1. Log into Cloud Shell by clicking small prompt icon at the top right of your screen (between Search and bell icon). After a minute or so a terminal will open
2. Make sure the prompt indicates your main (netsec) project. If it does not - change if using `gcloud config set project` command
3. Create a directory `lab`
4. In `lab` create a `main.tf` file and edit its contents to the code below:

```
module "fgt_ha" {
  source        = "git::github.com/40net-cloud/fortigate-gcp-ha-ap-lb-terraform"

  prefix        = "fgt"
  region        = "us-central1"
  image_family  = "fortigate-72-payg"
  subnets       = [ "ext", "int", "hasync", "mgmt" ]
  frontends     = ["app1"]
}
```

5. Initialize terraform environment by running `terraform init`
6. Deploy the environment by running `terraform apply` and confirming deployment

## Step 2 - log into your Gates

Use GCP web console to find public IP and instance ID of primary FortiGate (vm1) and log into the managmenet console to make sure everything works.

## Step 3 - peer workload VPCs

1. In cloud console go to vpc-int and open *VPC network peering* tab and click *Add peering*
2. Create 2 peerings from hub to `vpc-tier1` and to `vpc-tier2` (both in the workloads project), remember to enable "Export custom routes" option
3. Switch to the workload project
4. open details for `vpc-tier1` VPC
5. go to *Routes* tab and delete the default route to Internet (0.0.0.0/0)
6. in *VPC network peering* tab add a peering to `vpc-int` in netsec project; this time remember to enable "Import custom routes" option
7. Repeat the same for `vpc-tier2`
8. Verify the peerings are in *Active* state
9. Go to VPC routes and verify you can see 0.0.0.0/0 route with next hop set to "Network peering"

**Hint: peerings not coming up? Make sure you didn't mix the project and VPC names!**

After peerings are set in Google Cloud you need to indicate to FortiGate where to find prefixes (yes, manually). Go to your Gate and add static routes to 10.0.1.0/24 and 10.0.2.0/24 via 172.20.2.1 on port2

Congrats! You have created a complete (almost, we don't have InterConnect) reference architecture deployment in GCP! Yay :)

## Step 4 - inbound traffic

Identify the ELB in use by the FGT cluster: start from the VM and work your way up by following **In use by** links to: *fgtumig* (UnManaged Instance Group), *fgtbes-elb* (BackEnd Service for ELB - part of load balancer), to *fgtfr-app1* (forwarding rule - a.k.a. load balancer frontend).

The template created a load balancer forwarding traffic for all supported protocols on all ports to the FGT cluster. Note down the *External IP address*, you will need it.

### Health checks

Load balancers in GCP send health probes from dedicated **public** IP ranges (209.85.152.0/22, 209.85.204.0/22, 35.191.0.0/16, 130.211.0.0/22) to the load balancer frontend IP. Port and protocol are configurable in health check properties and by default set to HTTP on port 8008. Go to your Gate, open sniffer to verify it's indeed responding to probes and try to find out why it does respond.

Shhh, if you forgot the sniffer syntax, here it is:

```
di sniff pack port1 "port 8008"
```

To verify the health checks are read properly on the cloud side you can go to the BES page to check it.

Note that health checks are related to the frontend - with multiple frontends you will have multiple healthchecks, with no frontends - no checks.

### Forwarding traffic

Network load balancers in GCP never translate the addresses (you know it from Azure as "floating IP"). That means redirecting Internet traffic to cloud workload requires VIP from ELB frontend IP to the workload real address.

Note: do use port forwarding to avoid "stealing" of health check port.

Your frontend server is available at 10.0.1.2, try configuring FGT (VIP and firewall policy) to pass the traffic to it. If you succeed, you will see an nginx proxy error (504).

## Step 5 - outbound traffic

There are 3 different ways to allow traffic from VM (including FGT) to Internet:
1. using VM's "own" public IP - as you can see your FortiGates have zero public IPs assigned to port1.
2. using Cloud NAT - it's a managed outbound NAT gateway which can allow traffic from VMs to Internet without exposing them to inbound traffic (if you forget to restrict it using cloud firewall rules). We use Cloud NAT to allow traffic initiated by FGTs to Internet (eg. FortiGuard servers)
3. load balancer forwarding rules - **not documented** but working great for forwarded traffic.

The reference architecture uses both Cloud NAT and ELB allowing full control over public IP used for given connection using only FGT configuration.

If FGT SNATs forwarded traffic to its own private IP (NAT to port1 interface address) - the traffic will be handled by Cloud NAT.

If FGT SNATs forwarded traffic directly to public IP of ELB frontend - the traffic will be passed to Internet using that address. In practice it means FGTs in Google Cloud can use public IPs as their interface addresses! (extra experiment: remove entirely port1 private IP and replace it with the ELB frontend IP; keep routing as it is)

To forward outbound traffic use IP Pools (of a single IP) and assign them to desired firewall policies.

## Step 6 - east-west segmentation

Injecting an NVA into routing is possible only for traffic leaving a VPC. That means implementing multi-tier architecture requires a separate VPC for each "tier". In practice it generates a lot of VPCs and requires elevating project quotas (default limit is 5). The lab works around this problem by using 2 separate projects (each with its own quota of 5).

While a natural way for on-prem deployments is to connect each tier to a dedicated network interface (NIC), this approach does not work well in public clouds and in Google Cloud in particular. The maximum number of NICs is 8 and requires at least 8-vCPU instance. It's also not possible to add/remove/reassign NICs once FortiGate was deployed without deleting and re-deploying it again (re-assigning is now supported as preview but doesn't work very smoothly). That's why the reference architecture uses VPC Peering instead.

VPC Peering allows to connect more segments/tiers and allows doing it with zero downtime. While VPC Peering is not transitive (keep it in mind as every Google Cloud engineer will point it out when you talk about architectures), it can be made transitive using exported custom route an a routing virtual appliance like FGT. For the detailed flow see the east-west flow diagram linked in Student Resources (top left).

Mind that FortiGate configuration in this case requires a policy "from port2 to port2". Remember to use additional filters for addresses.

The lab features a frontend server (10.0.1.2) trying to connect to backend (10.0.2.2). Both are tagged with "frontend" and "backend" respectively. Add a necessary firewall policy to allow the traffic. Bonus points for using GCP connector and dynamic networks :)

## Thank you

That's all folks! I hope you liked it. Please end your lab when you're done. If you have any questions - you know where to find your instructor.
