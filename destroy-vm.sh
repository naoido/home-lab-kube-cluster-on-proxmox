VM_LIST=(
    #vmid #vmname  #cpu #mem  #vmsrvip    #targetip   #targethost
    "1001 k8s-cp-1 4    8192  192.168.1.11 192.168.1.1 raspberrypi-proxmox-01"
    "1002 k8s-cp-2 4    8192  192.168.1.12 192.168.1.2 raspberrypi-proxmox-02"
    "1003 k8s-cp-3 4    8192  192.168.1.13 192.168.1.3 raspberrypi-proxmox-03"
    "1101 k8s-wk-1 4    8192  192.168.1.21 192.168.1.6 primergy-proxmox-01"
    "1102 k8s-wk-2 4    8192  192.168.1.22 192.168.1.6 primergy-proxmox-01"
    "1103 k8s-wk-3 4    8192  192.168.1.23 192.168.1.6 primergy-proxmox-01"
    "1104 k8s-wk-4 4    8192  192.168.1.24 192.168.1.7 core-proxmox-01"
    "1105 k8s-wk-5 4    8192  192.168.1.25 192.168.1.7 core-proxmox-01"
)

for array in "${VM_LIST[@]}"
do
    echo "${array}" | while read -r vmid vmname cpu mem vmsrvip targetip targethost
    do
		ssh "${targetip}" qm stop "${vmid}"
    done
done

for array in "${VM_LIST[@]}"
do
    echo "${array}" | while read -r vmid vmname cpu mem vmsrvip targetip targethost
    do
		ssh "${targetip}" qm destroy "${vmid}" --destroy-unreferenced-disks true --purge true
    done
done

qm destroy 9051
qm destroy 9052