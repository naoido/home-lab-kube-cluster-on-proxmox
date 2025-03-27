#!/usr/bin/env bash

TARGET_BRANCH=main
ARM_TEMPLATE_VMID=9051
AMD_TEMPLATE_VMID=9052
CLOUDINIT_IMAGE_TARGET_VOLUME=vm-storage
TEMPLATE_BOOT_IMAGE_TARGET_VOLUME=vm-storage
BOOT_IMAGE_TARGET_VOLUME=vm-storage
SNIPPET_TARGET_VOLUME=nfs
SNIPPET_TARGET_PATH=/mnt/pve/nfs/snippets
REPOSITORY_RAW_SOURCE_URL="https://raw.githubusercontent.com/naoido/home-lab-kube-cluster-on-proxmox/${TARGET_BRANCH}"
VM_LIST=(
    # ---
    # vmid:       proxmox上でVMを識別するID
    # vmname:     proxmox上でVMを識別する名称およびホスト名
    # cpu:        VMに割り当てるコア数(vCPU)
    # mem:        VMに割り当てるメモリ(MB)
    # vmsrvip:    VMのService Segment側NICに割り振る固定IP
    # vmsanip:    VMのStorage Segment側NICに割り振る固定IP
    # targetip:   VMの配置先となるProxmoxホストのIP
    # targethost: VMの配置先となるProxmoxホストのホスト名
    # ---
    #vmid #vmname  #cpu #mem  #vmsrvip    #targetip   #targethost
    "1001 k8s-cp-1 2    8192  192.168.1.11 192.168.1.1 raspberrypi-proxmox-01"
    "1002 k8s-cp-2 2    8192  192.168.1.12 192.168.1.2 raspberrypi-proxmox-02"
    "1003 k8s-cp-3 2    8192  192.168.1.13 192.168.1.3 raspberrypi-proxmox-03"
    "1101 k8s-wk-1 4    8192  192.168.1.21 192.168.1.6 primergy-proxmox-01"
    "1102 k8s-wk-2 4    8192  192.168.1.22 192.168.1.6 primergy-proxmox-01"
    "1103 k8s-wk-3 4    8192  192.168.1.23 192.168.1.6 primergy-proxmox-01"
)

# For raspberrypi
wget https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-arm64.img
# For other
wget https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img

qm create $ARM_TEMPLATE_VMID --cores 2 --memory 4096 --net0 virtio,bridge=vmbr0 --name k8s-cp-template
qm create $AMD_TEMPLATE_VMID --cores 2 --memory 4096 --net0 virtio,bridge=vmbr0 --name k8s-wk-template

qm importdisk $ARM_TEMPLATE_VMID jammy-server-cloudimg-arm64.img $TEMPLATE_BOOT_IMAGE_TARGET_VOLUME
qm importdisk $AMD_TEMPLATE_VMID jammy-server-cloudimg-amd64.img $TEMPLATE_BOOT_IMAGE_TARGET_VOLUME

qm set $ARM_TEMPLATE_VMID --scsihw virtio-scsi-pci --scsi0 $TEMPLATE_BOOT_IMAGE_TARGET_VOLUME:vm-$ARM_TEMPLATE_VMID-disk-0
qm set $AMD_TEMPLATE_VMID --scsihw virtio-scsi-pci --scsi0 $TEMPLATE_BOOT_IMAGE_TARGET_VOLUME:vm-$AMD_TEMPLATE_VMID-disk-0

qm set $ARM_TEMPLATE_VMID --boot c --bootdisk scsi0
qm set $AMD_TEMPLATE_VMID --boot c --bootdisk scsi0

qm set $ARM_TEMPLATE_VMID --serial0 socket --vga serial0
qm set $AMD_TEMPLATE_VMID --serial0 socket --vga serial0

qm template $ARM_TEMPLATE_VMID
qm template $AMD_TEMPLATE_VMID

rm jammy-server-cloudimg-arm64.img
rm jammy-server-cloudimg-amd64.img

for array in "${VM_LIST[@]}"
do
    echo "${array}" | while read -r vmid vmname cpu mem vmsrvip targetip targethost
    do
        case targethost in
            raspberrypi-*)
                TEMPLATE_VMID=$ARM_TEMPLATE_VMID
                ;;
            *)
                TEMPLATE_VMID=$AMD_TEMPLATE_VMID
                ;;
        esac
        # clone from template
        # in clone phase, can't create vm-disk to local volume
        qm clone "${TEMPLATE_VMID}" "${vmid}" --name "${vmname}" --full true --target "${targethost}"
        
        # set compute resources
        ssh -n "${targetip}" qm set "${vmid}" --cores "${cpu}" --memory "${mem}"

        # move vm-disk to local
        # ssh -n "${targetip}" qm move-disk "${vmid}" scsi0 "${BOOT_IMAGE_TARGET_VOLUME}" --delete true

        # resize disk (Resize after cloning, because it takes time to clone a large disk)
        ssh -n "${targetip}" qm resize "${vmid}" scsi0 30G

        # create snippet for cloud-init(user-config)
        # START irregular indent because heredoc
# ----- #
cat > "$SNIPPET_TARGET_PATH"/"$vmname"-user.yaml << EOF
#cloud-config
hostname: ${vmname}
timezone: Asia/Tokyo
manage_etc_hosts: true
chpasswd:
  expire: False
users:
  - default
  - name: cloudinit
    sudo: ALL=(ALL) NOPASSWD:ALL
    lock_passwd: false
    # mkpasswd --method=SHA-512 --rounds=4096
    # password is zaq12wsx
    passwd: \$6\$rounds=4096\$Xlyxul70asLm\$9tKm.0po4ZE7vgqc.grptZzUU9906z/.vjwcqz/WYVtTwc5i2DWfjVpXb8HBtoVfvSY61rvrs/iwHxREKl3f20
ssh_pwauth: true
ssh_authorized_keys: []
package_upgrade: true
runcmd:
  # set ssh_authorized_keys
  - su - cloudinit -c "mkdir -p ~/.ssh && chmod 700 ~/.ssh"
  - su - cloudinit -c "curl -sS https://github.com/naoido.keys >> ~/.ssh/authorized_keys"
  - su - cloudinit -c "chmod 600 ~/.ssh/authorized_keys"
  # run install scripts
  - su - cloudinit -c "curl -s ${REPOSITORY_RAW_SOURCE_URL}/scripts/k8s-setup.sh > ~/k8s-setup.sh"
  - su - cloudinit -c "sudo bash ~/k8s-setup.sh ${vmname} ${TARGET_BRANCH}"
  # change default shell to bash
  - chsh -s $(which bash) cloudinit
EOF
# ----- #
        # END irregular indent because heredoc

        # create snippet for cloud-init(network-config)
        # START irregular indent because heredoc
# ----- #
cat > "$SNIPPET_TARGET_PATH"/"$vmname"-network.yaml << EOF
version: 1
config:
  - type: physical
    name: ens18
    subnets:
    - type: static
      address: '${vmsrvip}'
      netmask: '255.255.254.0'
      gateway: '192.168.0.1'
  - type: nameserver
    address:
    - '192.168.0.1'
    search:
    - 'local'
EOF
# ----- #
        # END irregular indent because heredoc

        # set snippet to vm
        ssh -n "${targetip}" qm set "${vmid}" --cicustom "user=${SNIPPET_TARGET_VOLUME}:snippets/${vmname}-user.yaml,network=${SNIPPET_TARGET_VOLUME}:snippets/${vmname}-network.yaml"
        case targethost in
            raspberrypi-*)
                ssh -n "${targetip}" qm set "${vmid}" --machine virt
                ssh -n "${targetip}" qm set "${vmid}" --scsi1 $CLOUDINIT_IMAGE_TARGET_VOLUME:cloudinit
                ;;
            *)
                ssh -n "${targetip}" qm set "${vmid}" --ide2 $CLOUDINIT_IMAGE_TARGET_VOLUME:cloudinit
                ;;
        esac
    done
done

for array in "${VM_LIST[@]}"
do
    echo "${array}" | while read -r vmid vmname cpu mem vmsrvip targetip targethost
    do
        ssh -n "${targetip}" qm start "${vmid}"
        
    done
done