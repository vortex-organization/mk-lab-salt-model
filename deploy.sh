#!/bin/bash
#yum install -y patch
verify=""
fuel environment create --name Perf-1 --release 2
ID=`fuel env | awk '/Perf-1/ {print $1}'`
while [[ "$verify" != "  vlan_start: 101" ]]
do
	fuel --env $ID network download
	mv network_$ID.yaml network.yaml
	verify=`awk '(NR == 70)' network.yaml`
	echo "$verify"
done
echo "$verify"
sleep 1;
curl -s 'https://raw.githubusercontent.com/vortex610/deploy/master/VLAN_bond_DVR_OFF/Perf-1/1/network_diff.patch' | patch -b -d /root/ -p1
mv network.yaml network_$ID.yaml
fuel --env $ID network upload

i=0
stop=5
cnt=0
while [[ $i != $stop ]];
do
	a=`fuel node | awk '/discover/ {print $1}'`
	for item in ${a[@]};
	do
		cnt=$[cnt+1];
	done
	if [[ -n $a ]];
	then
                i=$stop
                echo "Found $cnt nodes"
        else
                i=$[i+1]
                if [[ $i == $stop ]];
                then
                	echo "No nodes discovered for $[$i*60] sec"
                else
                	echo "waiting for nodes"
                	sleep 60
                fi
	fi
done
ID_CONTROLLER=`fuel node | awk '/discover/ {print $1}' | head -n 1`
ID_OTHER=`fuel node | awk '/discover/ {print $1}' | sed '1d'`

fuel --env $ID node set --node-id=$ID_CONTROLLER --role=controller

for item in ${ID_OTHER[@]};
do
     fuel --env $ID node set --node-id=$item --role=compute;
done

mkdir deployment

echo "waiting for applying changes"
sleep 1
fuel --env $ID settings download
fuel --env $ID deployment default

mv /root/deployment_$ID/$ID_CONTROLLER.yaml /root/deployment/controller.yaml
curl -s 'https://raw.githubusercontent.com/vortex610/deploy/master/VLAN_bond_DVR_OFF/Perf-1/1/CONTROLLER.patch' > controller_$ID_CONTROLLER.patch
patch -p1 /root/deployment/controller.yaml controller_$ID_CONTROLLER.patch
mv /root/deployment/controller.yaml /root/deployment_$ID/$ID_CONTROLLER.yaml

for item in $ID_OTHER;
do
	mv /root/deployment_$ID/$item.yaml /root/deployment/compute.yaml
	curl -s 'https://raw.githubusercontent.com/vortex610/deploy/master/VLAN_bond_DVR_OFF/Perf-1/1/COMPUTE.patch' > compute_$item.patch
	patch -p1 /root/deployment/compute.yaml compute_$item.patch
	mv /root/deployment/compute.yaml /root/deployment_$ID/$item.yaml
done
fuel --env $ID deployment upload
#fuel --env $ID deploy-changes
