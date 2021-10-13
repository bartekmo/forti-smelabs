project=emea-sme-training-2020-275813

# create hub vpc network
gcloud compute networks create ncc-hub-vpc --subnet-mode=custom
gcloud alpha network-connectivity hubs create ncc-hub


#create all the other networks
./3vpcs.sh

#enable BGP traffic to fortigates
gcloud compute firewall-rules create fw-hub-fgt-allow-bgp --network ncc-hub-vpc --action allow --target-tags fortigate --source-ranges "172.16.0.0/16" --rules "TCP:179"
#enable hasync traffic
gcloud compute firewall-rules create fw-hasync-allow --network ncc-hasync-vpc --action allow --target-tags fortigate --source-tags fortigate --rules "all"
#allow all hub traffic to fortigates
gcloud compute firewall-rules create fw-hub-allowall-to-fgt --network ncc-hub-vpc --action allow --target-tags fortigate --source-ranges "0.0.0.0/0" --rules "all"

###############################################################
# LONDON
###############################################################

spoke=ncc-london
region=europe-west2

#create subnets and fortigate instances for a spoke
gcloud deployment-manager deployments create ncc-london --config london.yaml

# create NCC spoke
gcloud alpha network-connectivity spokes create $spoke-spoke --hub=ncc-hub --region $region \
  --router-appliance="instance=https://www.googleapis.com/compute/alpha/projects/$project/zones/$region-b/instances/$spoke-fgt1,ip=172.16.1.2" \
  --router-appliance="instance=https://www.googleapis.com/compute/alpha/projects/$project/zones/$region-c/instances/$spoke-fgt2,ip=172.16.1.3"

# create cloud router with 2 NICs
gcloud compute routers create $spoke-crt --region $region --network ncc-hub-vpc --asn 65000

gcloud beta compute routers add-interface $spoke-crt --interface-name $spoke-crt-nic0 --subnetwork ncc-hub-london --region $region --ip-address 172.16.1.11
gcloud beta compute routers add-interface $spoke-crt --interface-name $spoke-crt-nic1 --subnetwork ncc-hub-london --region $region --ip-address 172.16.1.12 --redundant-interface $spoke-crt-nic0

# BGP peering fgt 1
gcloud beta compute routers add-bgp-peer $spoke-crt --peer-name peer-nic0-fgt-$spoke-a --interface $spoke-crt-nic0 --peer-ip-address 172.16.1.2 --peer-asn 65001 --instance $spoke-fgt1 --instance-zone $region-b --region $region
gcloud beta compute routers add-bgp-peer $spoke-crt --peer-name peer-nic1-fgt-$spoke-a --interface $spoke-crt-nic1 --peer-ip-address 172.16.1.2 --peer-asn 65001 --instance $spoke-fgt1 --instance-zone $region-b --region $region

# BGP peering fgt 2
gcloud beta compute routers add-bgp-peer $spoke-crt --peer-name peer-nic0-fgt-$spoke-c --interface $spoke-crt-nic0 --peer-ip-address 172.16.1.3 --peer-asn 65001 --instance $spoke-fgt2 --instance-zone $region-c --region $region
gcloud beta compute routers add-bgp-peer $spoke-crt --peer-name peer-nic1-fgt-$spoke-c --interface $spoke-crt-nic1 --peer-ip-address 172.16.1.3 --peer-asn 65001 --instance $spoke-fgt2 --instance-zone $region-c --region $region

#############################################################
# FGT configuration for london spoke
#############################################################
# get management public ip for fgt1
fgtlon=`gcloud compute instances describe ncc-london-fgt1 --zone europe-west2-b --format json | jq ".networkInterfaces[3].accessConfigs[0].natIP" -r`

#push configuration for Bartek's home office vpn
myip=`curl -s api.ipify.org`
#ssh admin@$fgtlon <<\EOF
cat <<EOF > fgtlon.config
config vpn ipsec phase1-interface
    edit "ncclon-bm-sl"
        set interface "port1"
        set peertype any
        set net-device disable
        set remote-gw $myip
        set psksecret WnBy8UzNCMNNpAJs2MXa9emya
    next
    edit "ncclon-bm-magi"
        set interface "port1"
        set ike-version 2
        set peertype any
        set net-device disable
        set remote-gw 195.81.20.75
        set psksecret WnBy8UzNCMNNpAJs2MXa9emya
    next
end

config vpn ipsec phase2-interface
    edit "ncclon-bm-sl"
        set phase1name "ncclon-bm-sl"
        set src-subnet 0.0.0.0/0
        set dst-subnet 0.0.0.0/0
    next
    edit "ncclon-bm-magi"
        set phase1name "ncclon-bm-magi"
        set src-subnet 0.0.0.0/0
        set dst-subnet 0.0.0.0/0
    next
end

config firewall policy
    edit 10
        set name "vpn-allow"
        set srcintf "ncclon-bm-sl" ncclon-bm-magi
        set dstintf "port2"
        set action accept
        set srcaddr "all"
        set dstaddr "all"
        set schedule "always"
        set service "ALL"
    next
end

config router bgp
  set as 65001
  set ibgp-multipath enable
  set additional-path enable
  config neighbors
    edit 169.254.110.2
      set remote-as 65101
      set soft-reconfiguration enable
      set additional-path both
    next
    edit 169.254.111.2
      set remote-as 65101
      set soft-reconfiguration enable
      set additional-path both
    next
  end
end
EOF

ssh admin@$fgtlon <fgtlon.config

vegas/create
mumbai/create
