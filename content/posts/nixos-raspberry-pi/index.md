---
title: "NixOSをRaspberry Pi上に構築したときのメモ"
date: 2026-10-15T14:13:00+09:00
tags: [ "Raspberry Pi"]
categories: [ "NixOS" ]
---

NixOSをラズパイに入れたときの備忘録。

## 背景

もともとの目的は、遠隔地からWake on LANでデスクトップを起動するための、簡易的なサーバーが欲しかったこと。そういえばラズパイを持っていたので、それが使えるんじゃないかと思い、倉庫から取り出して構築を始めた。

昔はRaspberry Pi OSを使ってたけど、NixOSを知って大好きになったのでこれを機にラズパイにもNixOSを入れることにした。

## 前提

* Raspberry Pi 4 Model B / 8GB

## NixOSのイメージの入手

[nixos.org](https://nixos.org/download/#nixos-more)にはISOのイメージの案内しかないが、[Installing NixOS on a Raspberry Pi](https://nix.dev/tutorials/nixos/installing-nixos-on-a-raspberry-pi.html) を読むと、SDカード用のイメージがありそれを書き込むらしい。

ここの最新のものをDLしてくる。

https://hydra.nixos.org/job/nixos/unstable/nixos.sd_image.aarch64-linux

```sh
curl -LO https://hydra.nixos.org/build/349228952/download/1/nixos-image-sd-card-26.11pre1092090.55bfb4d7437b-aarch64-linux.img.zst
```

DLされるものはzstdという圧縮形式なので、これを解凍する。手元のmacOSには入ってないので、nix shell経由で実行する。

```sh
nix shell 'nixpkgs#zstd' -c unzstd 'nixos-image-sd-card-26.11pre1092090.55bfb4d7437b-aarch64-linux.img.zst'
```

```console
bombrary@bombrary-macbookair:~% curl -LO https://hydra.nixos.org/build/349228952/download/1/nixos-image-sd-card-26.11pre1092090.55bfb4d7437b-aarch64-linux.img.zst
  % Total    % Received % Xferd  Average Speed   Time    Time     Time  Current
                                 Dload  Upload   Total   Spent    Left  Speed
100 1440M    0 1440M    0     0  2996k      0 --:--:--  0:08:12 --:--:-- 4673k
bombrary@bombrary-macbookair:~% nix shell 'nixpkgs#zstd' -c unzstd 'nixos-image-sd-card-26.11pre1092090.55bfb4d7437b-aarch64-linux.img.zst'
nixos-image-sd-card-26.11pre1092090.55bfb4d7437b-aarch64-linux.img.zst: 3982954496 bytes
```

## NixOSイメージをmicroSDに焼く

### SDカードリーダーの用意

昔焼くときに使っていたPCにはSDスロットがあったのだが、MacBook Airにはついてない。近くの電気屋で適当なものを買ってきた。SDカード系の売り場にあった。

[USB Type-C(TM)接続 直挿しメモリーカードリーダー(UHS-I)](https://www.elecom.co.jp/products/MR3C-D20BK.html)

### デバイスファイルの特定

この後ddコマンドで書き込むので、事前に書き込み先のSDカードのデバイスファイルを特定しておく必要がある。

macOSの場合はdiskutilで確認可能。

```sh
diskutil list
```

```console
bombrary@bombrary-macbookair:~% diskutil list
/dev/disk0 (internal, physical):
   #:                       TYPE NAME                    SIZE       IDENTIFIER
   0:      GUID_partition_scheme                        *1.0 TB     disk0
   1:             Apple_APFS_ISC Container disk1         524.3 MB   disk0s1
   2:                 Apple_APFS Container disk3         994.7 GB   disk0s2
   3:        Apple_APFS_Recovery Container disk2         5.4 GB     disk0s3

/dev/disk3 (synthesized):
   #:                       TYPE NAME                    SIZE       IDENTIFIER
   0:      APFS Container Scheme -                      +994.7 GB   disk3
                                 Physical Store disk0s2
   1:                APFS Volume Macintosh HD            12.6 GB    disk3s1
   2:              APFS Snapshot com.apple.os.update-... 12.6 GB    disk3s1s1
   3:                APFS Volume Preboot                 9.0 GB     disk3s2
   4:                APFS Volume Recovery                1.3 GB     disk3s3
   5:                APFS Volume Data                    254.1 GB   disk3s5
   6:                APFS Volume VM                      2.1 GB     disk3s6
   7:                APFS Volume Nix Store               24.9 GB    disk3s7

/dev/disk4 (external, physical):
   #:                       TYPE NAME                    SIZE       IDENTIFIER
   0:     FDisk_partition_scheme                        *127.9 GB   disk4
   1:             Windows_FAT_32 boot                    268.4 MB   disk4s1
   2:                      Linux                         127.6 GB   disk4s2
```

持っているmicroSDは128GBのやつなので、 `/dev/disk4` だということがわかる。

書き込みを実行する。
```sh
sudo dd if=<imgファイル> of=<書き込み先デバイスファイル> bs=4096 conv=fsync status=progress
```

ところがそのままだとエラーになる。

```console
bombrary@bombrary-macbookair:~% sudo dd if=nixos-image-sd-card-26.11pre1092090.55bfb4d7437b-aarch64-linux.img of=/dev/disk4 bs=4096 conv=fsync status=progress
dd: /dev/disk4: Resource busy
```

これはSDカードリーダーを接続した時にmacOSが自動でマウントしたからなので、アンマウントする。macOSの場合は以下で行う。
```sh
diskutil unmountDisk <デバイスファイル>
```

```console
bombrary@bombrary-macbookair:~% ls -la /Volumes
drwx------@ - bombrary 15 Oct 12:50 boot
lrwxr-xr-x  - root     11 Oct 20:33 'Macintosh HD' -> /

bombrary@bombrary-macbookair:~% diskutil unmountDisk /dev/disk4
Unmount of all volumes on disk4 was successful

bombrary@bombrary-macbookair:~% ls -la /Volumes
lrwxr-xr-x - root 11 Oct 20:33 'Macintosh HD' -> /
bombrary@bombrary-macbookair:~%
```

これで書き込めた。

```console
bombrary@bombrary-macbookair:~% sudo dd if=nixos-image-sd-card-26.11pre1092090.55bfb4d7437b-aarch64-linux.img of=/dev/disk4 bs=4096 conv=fsync status=progress
Password:
  3976335360 bytes (3976 MB, 3792 MiB) transferred 606.003s, 6562 kB/s
972401+0 records in
972401+0 records out
3982954496 bytes transferred in 606.997727 secs (6561729 bytes/sec)
```

SDカードリーダーを取り外す（Windowsでいう「ハードウェアの安全な取り外し」みたいなやつか？）。
```sh
diskutil eject /dev/disk4
```

```console
bombrary@bombrary-macbookair:~% diskutil eject /dev/disk4
Disk /dev/disk4 ejected
```

（外した時に気づいたが、だいぶカードリーダーが熱を持っていた）

## Raspberry Pi起動

microSDをラズパイの本体に差して起動する。初回はモニターが必要なのでモニターにも繋ぐ。NixOS初回のプロンプトが出る。

```console
[nixos@nixos:~]$
```

また上部には以下のメッセージが見える。

```console
<<< Welcome to NixOS sd-card-26.11pre1092090.55bfb4d7437b (aarch64) - tty1 >>>

To log in over ssh you must set a password for either "nixos" or "root"
with `passwd` (prefix with `sudo` for "root"), or add your public key to
/home/nixos/.ssh/authorized_keys or /root/.ssh/authorized_keys.
```

これ以降はSSHでセットアップしたいので、ひとまずnixosユーザのパスワードを設定する。
```sh
passwd
```

有線LANに繋いでIPを確認。
```console
[nixos@nixos:~]$ ip a
1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN group default qlen 1000
    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
    inet 127.0.0.1/8 scope host lo
       valid_lft forever preferred_lft forever
    inet6 ::1/128 scope host noprefixroute
       valid_lft forever preferred_lft forever
2: end0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc mq state UP group default qlen 1000
    link/ether xx:xx:xx:xx:xx:xx brd ff:ff:ff:ff:ff:ff
    altname enxxxxxxxxxxxxx
    inet 192.168.11.7/24 brd 192.168.11.255 scope global dynamic noprefixroute end0
       valid_lft 172513sec preferred_lft 172513sec
    inet6 xxxx:xxxx:xxxx:xxxx:xxxx:xxxx:xxxx:xxxx/64 scope global temporary dynamic
       valid_lft 86112sec preferred_lft 14112sec
    inet6 xxxx:xxxx:xxxx:xxxx:xxxx:xxxx:xxxx:xxxx/64 scope global dynamic mngtmpaddr noprefixroute
       valid_lft 86112sec preferred_lft 14112sec
    inet6 fe80::ad92:ff0a:7430:5847/64 scope link noprefixroute
       valid_lft forever preferred_lft forever
3: wlan0: <NO-CARRIER,BROADCAST,MULTICAST,UP> mtu 1500 qdisc fq_codel state DOWN group default qlen 1000
    link/ether xx:xx:xx:xx:xx:xx brd ff:ff:ff:ff:ff:ff permaddr xx:xx:xx:xx:xx:xx
    altname wlxxxxxxxxxxxxx
```

この環境では `192.168.11.7` みたいなので、これでSSHログインが可能になる。
```sh
ssh -p22 nixos@192.168.11.7
```

これ以降はモニターを外して作業が可能。

## セットアップ

あとはNixOSでやるいつものセットアップ。

rootに入る。  
※ configuration.nixにnixosユーザを書かなければnixosユーザが消えて何もできなくなるので、この時点でrootに入っておくべき。ミスった場合はブートローダー画面で元の世代に戻ればよい
```sh
sudo -i
```

初期設定ファイルを生成
```sh
nixos-generate-config
```

`/etc/nixos/configuration.nix` に設定を書いた後、システムのビルドの実行。

```sh
nixos-rebuild switch
```

ユーザを追加した場合は、初期パスワードを設定。
```sh
passwd <ユーザ名>
```

あとはこのconfiguration.nixをリポジトリで管理するなり、home-managerでユーザ側のパッケージを管理するなりやれば良いが、そのあたりは[以前の記事]({{< ref "/posts/nixos-23.11-setup/" >}}) で紹介したので省略。

## 終わりに

NixOSをラズパイに入れるところまでやった。調べたのはOSイメージの場所とディスク書き込みのやり方くらいで、思い立ってから2時間ほどでここまで来られるくらいには簡単だった。
