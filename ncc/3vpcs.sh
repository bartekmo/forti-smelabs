PREFIX=ncc

gcloud compute networks create $PREFIX-pub-vpc --subnet-mode=custom 2> /dev/null
gcloud compute networks create $PREFIX-hasync-vpc --subnet-mode=custom 2> /dev/null
gcloud compute networks create $PREFIX-mgmt-vpc --subnet-mode=custom 2< /dev/null
