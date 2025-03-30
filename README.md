# 自宅環境でk8sをセットアップするためのスクリプト
```bash
/bin/bash <(curl -s https://raw.githubusercontent.com/naoido/home-lab-kube-cluster-on-proxmox/main/deploy-vm.sh) ${GITHUB_PAT}
```

## トラブルシューティング
### ディスクマッパーが残ってしまっている場合
```bash
clone failed: lvcreate 'local-lvm/vm-1101-disk-0' error:   Failed to activate new LV local-lvm/vm-1101-disk-0.
Configuration file 'nodes/primergy-proxmox-01/qemu-server/1101.conf' does not exist
```
のエラーが出た場合ディスクマッパーが残っている場合があります。
```bash
# ディスクマッパーが残っていないか確認
dmsetup ls | grep 1101
# ディスクマッパーの削除
dmsetup remove /dev/mapper/local--lvm-vm--1101--disk--0
```

## SPECIAL THANKS!
Portions © 2022 [unchama](https://github.com/unchama)  
Based on [kube-cluster-on-proxmox](https://github.com/unchama/kube-cluster-on-proxmox)