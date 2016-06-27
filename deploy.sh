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
        if [[ "$verify" != "  vlan_start: 101" ]];then echo "wrong file, downloading again";fi
done
echo "network OK"
sleep 1;
curl -s 'https://raw.githubusercontent.com/vortex610/deploy/master/VLAN_bond_DVR_OFF/Perf-1/1/network_diff.patch' | patch -b -d /root/ -p1
mv network.yaml network_$ID.yaml
fuel --env $ID network upload

i=0
stop=60
cnt=0
while [[ $i != $stop ]];
do
        a=`fuel node | awk '/discover/ {print $1}'`
        for item in ${a[@]};do cnt=$[cnt+1]; done
        if [[ $cnt == "3" ]];then
                i=$stop
                echo "Found $cnt nodes"
        else
                i=$[i+1]
                if [[ $i == $stop ]];then
                        echo "No nodes discovered for $[$i*10] sec"
                else
                        echo "waiting for nodes 10 sec"
                        echo "found $cnt nodes"
                        sleep 10
                fi
        fi
        cnt=0
done
echo "Enabling 10G interfaces"
ips=`fuel node | awk '/0c:c4:7a:0c:/ {print $9}'`
for nod in ${ips[@]};do
        ssh $nod 'ip link set up dev enp2s0f0; ip link set up dev enp2s0f1';
done
sleep 5
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
fuel --env $ID deployment default

mv /root/deployment_$ID/$ID_CONTROLLER.yaml /root/deployment/controller.yaml
curl -s 'https://raw.githubusercontent.com/vortex610/deploy/master/VLAN_bond_DVR_OFF/Perf-1/1/CONTROLLER2.patch' > controller_$ID_CONTROLLER.patch
patch -p1 /root/deployment/controller.yaml controller_$ID_CONTROLLER.patch
mv /root/deployment/controller.yaml /root/deployment_$ID/$ID_CONTROLLER.yaml

for item in $ID_OTHER;
do
        mv /root/deployment_$ID/$item.yaml /root/deployment/compute.yaml
        curl -s 'https://raw.githubusercontent.com/vortex610/deploy/master/VLAN_bond_DVR_OFF/Perf-1/1/COMPUTE2.patch' > compute_$item.patch
        patch -p1 /root/deployment/compute.yaml compute_$item.patch
        mv /root/deployment/compute.yaml /root/deployment_$ID/$item.yaml
done
fuel --env $ID deployment upload

fuel --env $ID settings download
mv settings_$ID.yaml settings.yaml
curl -s 'https://raw.githubusercontent.com/vortex610/deploy/master/VLAN_bond_DVR_OFF/Perf-1/1/settings.patch' | patch -b -d /root/ -p1
mv settings.yaml settings_$ID.yaml
fuel --env $ID settings upload

mkdir deploy_param_$ID
mv compute_* deploy_param_$ID/
mv deployment_$ID/ deploy_param_$ID/
mv network* deploy_param_$ID/
mv settings* deploy_param_$ID/
mv controller* deploy_param_$ID/
rm -r deployment/

#fuel --env $ID deploy-changes
