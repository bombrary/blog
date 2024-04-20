---
title: "NixOS & Home Managerのセットアップメモ"
date: 2024-02-11T18:00:00+09:00
tags: []
toc: true
categories: ["NixOS"]
---

NixOS 23.11をセットアップした時のメモ。

## 目標

* NixOS環境については以前構築したことがあるが、勉強のためもう一度一から構築する
* 今後、NixOSの環境をすぐに構築できるような設定ファイル、リポジトリを作る
  * なるべくNix Flakesを使う

NixOSの設定ファイルはNix言語で記述するが、自由度が結構高くて、どうファイル分け、ディレクトリ分けをしていくのかが悩ましい。
今回は[Wiki](https://nixos.wiki/wiki/Applications)の紹介されていた[dotfiles](https://github.com/hlissner/dotfiles/tree/master)リポジトリを参考にしようと思う。
とはいえ、まだまだNixOSの初学者のため、小さな部分を少し真似して作っていく。

## インストールディスクの起動 {#boot-from-install-disk}

[Download Nix](https://nixos.org/download)のページ下部にある「NixOS the Linux distributeion」からISOイメージをダウンロードしてくる。

ダウンロードリンクとして、Graphical ISO ImageとMinimal ISO Imageがあるが、今回は後者でやる。
* Graphical ISO Imageも一度試したが、ウィザード形式で設定をポチポチ進めるだけで設定が出来上がるので分かりやすい。おそらく初学者はこれで作成された `configuration.nix` を眺めて、少しずつ設定を理解していくのがよいのだと思う。
* Minimal ISO Imageはコンソールでインストール作業を行う。パーティションを分けたり、ファイルシステムを作ったりするのは自分でやることになる。今回は勉強のためにこれでやる。
  * 作業の大枠は[NixOS 23.11 manual](https://nixos.org/manual/nixos/stable/#sec-installation-manual)に乗っているのでそれに従う。

* 自分の環境の場合は、ESXiの入ったPCがあるので、コンテンツライブラリにそれをアップロードし、仮想マシン作成の時にそれをCDデバイスとしてセットする
* 物理HWに入れる場合、ISOイメージをUSBやCDに焼いておき、起動する

起動すると次の画面になるので、一番上を選択してEnterする。

{{< figure src="img/nixos-boot.png" >}}

## SSH接続できるようにする

しばらくすると以下の画面になる。

{{< figure src="img/nixos-startup.png" >}}


文章を読むと、
> To log in over ssh you must set a password for ether "nixos" or "root"
> with `passwd` (prefix with `sudo` for "root"), or ...

と親切にもSSHへの入り方のガイドが示されている。証跡を残すためには画像よりもテキストの方が取りやすいため、SSHで作業することにする。なお、このままコンソール上で作業する場合、`loadkeys` でキーボードのレイアウトを変えないと記号が思った通りに打てないので注意。

ガイド通り、パスワードを変える。

{{< figure src="img/nixos-passwd.png" >}}

SSHで入るためには、もちろんSSHで接続しに行く側との疎通ができないといけない。これは環境によって様々。
* 有線の場合
  * DHCP有効の場合：すでにIPアドレスが取得できている状態だと思う。`ip a` で確認可能
    * `journalctl -xe` を見るとわかるが、どうやら `dhcpcd` が動いている模様
  * DHCP無効の場合：`ip a add`なり`ifconfig`なりでIPアドレスを手動設定する
* 無線の場合：[wpa_supplicantを使った方法](https://nixos.org/manual/nixos/stable/#sec-installation-manual-networking)で接続できるっぽいので、これを試せばよいと思う

自分の環境の場合は、VM作成時にNICをつけたし、ルータのDHCPも有効なのですでにIPアドレスが取得できている状態だった。なのでそのままログインできる。

```shell-session
 ~> ssh nixos@192.168.11.7
The authenticity of host '192.168.11.7 (192.168.11.7)' can't be established.
ED25519 key fingerprint is SHA256:VaSGKAAf3wkC1x9oRLPUurQZtNbhCJswR+emvlXcWMw.
This key is not known by any other names
Are you sure you want to continue connecting (yes/no/[fingerprint])? yes
Warning: Permanently added '192.168.11.7' (ED25519) to the list of known hosts.
(nixos@192.168.11.7) Password:

[nixos@nixos:~]$ sudo -i
[root@nixos:~]#
```

## パーティション作成・ディスクフォーマット {#make-partition}

このあたりは[Arch Linux](https://wiki.archlinux.jp/index.php/%E3%82%A4%E3%83%B3%E3%82%B9%E3%83%88%E3%83%BC%E3%83%AB%E3%82%AC%E3%82%A4%E3%83%89)でも同様であるが、基本的には
* ブートパーティション：起動時に必要なデータを入れた領域
* スワップパーティション：スワップ領域（メモリが足りなくなったときとかに一時的にデータを退避しておく領域）
* ルートパーティション：システムやユーザが使うデータを入れる領域

を決める必要がある。もちろんルートパーティションを2つに分けてシステム領域、ユーザ領域と分けたり、またデュアルブートする場合のことを考えて空き領域を考えたりなどいろいろ考える余地はあると思うが、ここでは、基本の3つだけ作る。

パーティションを切るソフトウェアとして fdisk、gdisk、partedなどいろいろあるが、[NixOS 23.11 manual](https://nixos.org/manual/nixos/stable/#sec-installation-manual-partitioning)でpartedが使われていたのでこれを使うことにする。

GPTかMBRかによっても若干手順が異なるので注意。以下はGPTの例。

* 該当ディスクのデバイス名を確認する
  * HDDなら`/dev/sda`とか`/dev/sdb`みたいな名前になるはず
  * NVMeなら `/dev/nvme0n1`みたいな名前になるはず
* `parted` でパーティションを切る
  * GPTのラベルをつける
  * 先頭の512GBはEFI System Partition
  * 512GBから、末尾に8GBだけ残してroot partition
  * 残りの末尾8Gはswap partition

```sh
parted /dev/sda -- mklabel gpt
parted /dev/sda -- mkpart root ext4 512MG -8GB
parted /dev/sda -- mkpart swap linux-swap -8GB 100%
parted /dev/sda -- mkpart ESP fat32 1MB 512MB
parted /dev/sda -- set 3 esp on
```

現在のパーティションの確認
```shell-session
[root@nixos:~]# parted /dev/sda -- print list
Model: VMware Virtual disk (scsi)
Disk /dev/sda: 107GB
Sector size (logical/physical): 512B/512B
Partition Table: gpt
Disk Flags:

Number  Start   End     Size    File system  Name  Flags
 3      1049kB  512MB   511MB                ESP   boot, esp
 1      512MB   99.4GB  98.9GB               root
 2      99.4GB  107GB   7999MB               swap  swap


Warning: Unable to open /dev/sr0 read-write (Read-only file system).  /dev/sr0 has been opened read-only.
Model: NECVMWar VMware IDE CDR00 (scsi)
Disk /dev/sr0: 1003MB
Sector size (logical/physical): 2048B/2048B
Partition Table: msdos
Disk Flags:

Number  Start   End     Size    Type     File system  Flags
 2      36.2MB  48.8MB  12.6MB  primary               esp
```

パーティションの番号に対応した `sda1`、`sda2`、`sda3` が出来上がっている。
```shell-session
[root@nixos:~]# ls /dev/sda*
/dev/sda  /dev/sda1  /dev/sda2  /dev/sda3
```

続いて、ディスクのフォーマットをする。
* `/dev/sda1`をext4でフォーマット
* `/dev/sda2`をswapでフォーマット
* `/dev/sda3`をfat32でフォーマット

```sh
mkfs.ext4 -L nixos /dev/sda1
mkswap -L swap /dev/sda2
mkfs.fat -F 32 -n boot /dev/sda3
```

実行例。
```shell-session
[root@nixos:~]# mkfs.ext4 -L nixos /dev/sda1
mke2fs 1.47.0 (5-Feb-2023)
Creating filesystem with 24136448 4k blocks and 6037504 inodes
Filesystem UUID: 7e8133e8-e60b-4229-9ab8-b01dd8d7e44e
Superblock backups stored on blocks:
        32768, 98304, 163840, 229376, 294912, 819200, 884736, 1605632, 2654208,
        4096000, 7962624, 11239424, 20480000, 23887872

Allocating group tables: done
Writing inode tables: done
Creating journal (131072 blocks): done
Writing superblocks and filesystem accounting information: done


[root@nixos:~]# mkswap -L swap /dev/sda2
Setting up swapspace version 1, size = 7.4 GiB (7998533632 bytes)
LABEL=swap, UUID=d50a6577-8177-4b57-91d4-1fd3072de068

[root@nixos:~]# mkfs.fat -F 32 -n boot /dev/sda3
mkfs.fat 4.2 (2021-01-31)
mkfs.fat: Warning: lowercase labels might not work properly on some systems
```

つけたラベルとデバイスの対応関係の確認。
```console
[root@nixos:~]# ls -la /dev/disk/by-label/
total 0
drwxr-xr-x 2 root root 120 Feb 12 01:24 .
drwxr-xr-x 9 root root 180 Feb 12 01:24 ..
lrwxrwxrwx 1 root root  10 Feb 12 01:24 boot -> ../../sda3
lrwxrwxrwx 1 root root  10 Feb 12 01:24 nixos -> ../../sda1
lrwxrwxrwx 1 root root   9 Feb 12  2024 nixos-minimal-23.11-x86_64 -> ../../sr0
lrwxrwxrwx 1 root root  10 Feb 12 01:24 swap -> ../../sda2
```

デバイスのマウント。
* root partitionの領域を `/mnt/` にマウント
* boot partitionの領域を `/mnt/boot` にマウント
* swap partitionの領域をswap領域として有効化

```sh
mount /dev/sda1 /mnt
mkdir /mnt/boot
mount /dev/sda3 /mnt/boot
swapon /dev/sda2
```

今一度ディスク情報を確認。マウントした領域と切ったパーティションの領域のサイズがここで一致しているのかを確認。
```shell-session
[root@nixos:~]# df -H | grep sda
/dev/sda1        97G   29k   92G   1% /mnt
/dev/sda3       510M  4.1k  510M   1% /mnt/boot
```

## NixOS設定ファイルの作成 {#create-nix-configuration}

`configuration.nix`の初期ファイルを作成。

```shell-session
[root@nixos:~]# nixos-generate-config --root /mnt
writing /mnt/etc/nixos/hardware-configuration.nix...
writing /mnt/etc/nixos/configuration.nix...
For more hardware-specific settings, see https://github.com/NixOS/nixos-hardware.
```

コメント文をもとに適当に編集する。
* 今回はGUI環境を作らないので、xserverとかsoundの設定は無視してよいはず
* 後で一般ユーザに入って細かい設定をすればよいので、ここでは仮のものを作る
* 後でFlakes系のコマンドを使うので、 `nix.settings.experimental-features` の設定をする

```nix
{ config, lib, pkgs, ... }:

{
  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix
    ];

  # Use the systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.hostName = "nixos"; # Define your hostname.
  time.timeZone = "Asia/Tokyo";
  i18n.defaultLocale = "en_US.UTF-8";

  users.users.bombrary = {
    isNormalUser = true;
    extraGroups = [ "wheel" ]; # Enable ‘sudo’ for the user.
  };

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
    vim
    git
  ];

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  programs.mtr.enable = true;

  services.openssh.enable = true;

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # Do NOT change this value unless you have manually inspected all the changes it would make to your configuration,
  # and migrated your data accordingly.
  #
  # For more information, see `man configuration.nix` or https://nixos.org/manual/nixos/stable/options#opt-system.stateVersion .
  system.stateVersion = "23.11"; # Did you read the comment?
}
```

## NixOSのインストール {#nixos-install}

インストールを実行する。
```shell-session
[root@nixos:~]# nixos-install

Created EFI boot entry "Linux Boot Manager".
setting up /etc...
setting up /etc...
setting root password...
New password:
Retype new password:
passwd: password updated successfully
installation finished!
```

`nixos-enter` コマンドで、今ビルドしたNixOSのシステムに入る。一般ユーザのパスワードをそこで行う （[NixOS Wiki](https://nixos.wiki/wiki/Change_root)にて`nixos-enter`コマンドの存在を知ったので手順を追記）。
```console
[root@nixos:~]# nixos-enter
setting up /etc...

[root@nixos:/]# passwd bombrary
New password:
Retype new password:
passwd: password updated successfully

[root@nixos:/]# exit
logout
```

アンマウントしたうえで再起動する。このとき、CD・ISOを取り外した上で再起動する。

```sh
umount /mnt/boot
umount /mnt

reboot
```

SSHで一般ユーザでログインできることを確認する。
```shell-session
~> ssh bombrary@192.168.11.7
(bombrary@192.168.11.7) Password:
Last login: Tue Feb  6 20:30:18 2024 from 192.168.11.6

[bombrary@nixos:~]$ su root
```

## Flakesを利用したNixOS設定ファイルの作成

再利用の観点から、Nix Flakesを利用した方法に切り替える。やり方としては

* [Using nix flakes with NixOS - NixOS Wiki](https://nixos.wiki/wiki/Flakes#Using%20nix%20flakes%20with%20NixOS)
* [NixOSで最強のLinuxデスクトップを作ろう - Zenn](https://zenn.dev/asa1984/articles/nixos-is-the-best)
* [hlissner/dotfiles - GitHub](https://github.com/hlissner/dotfiles/tree/master)

が参考になる。

適当な作業ディレクトリを作ってその中で作業する。
```shell-session
[bombrary@nixos:~]$ mkdir dotfiles
[bombrary@nixos:~]$ cd dotfiles
```

先ほど作った`/etc/nixos/configuration.nix`と、自動生成されている`/etc/nixos/hardware-configuration.nix`を持ってくる。「必要最小限の構成にしたOS設定」という体で、適当に`minimal`などというディレクトリを作ってそこに設定ファイルを入れる。
```shell-session
[bombrary@nixos:~/dotfiles]$ mkdir -p hosts/minimal
[bombrary@nixos:~/dotfiles]$ cp /etc/nixos/* hosts/minimal/
```

`flake.nix`のひな形を作る。
```shell-session
[bombrary@nixos:~/dotfiles]$ nix flake init
wrote: /home/bombrary/dotfiles/flake.nix
```

適当にinputを書き足す。

```nix
{
  description = "NixOS Configuration";

  inputs = {
    nixos.url = github:NixOS/nixpkgs/nixos-23.11;
  };

  outputs = { self, nixos }: {

    packages.x86_64-linux.hello = nixpkgs.legacyPackages.x86_64-linux.hello;

    packages.x86_64-linux.default = self.packages.x86_64-linux.hello;

  };
}
```

文法チェック。
```shell-session
[bombrary@nixos:~/dotfiles]$ nix flake check
```

続いてOSの設定を書き足す。とその前に、`nixos-rebuild` コマンドのマニュアルを確認する。

```
[bombrary@nixos:~]$ man nixos-rebuild
...

--flake flake-uri[#name]
       Build  the  NixOS  system  from the specified flake. It defaults to the directory containing the
       target of the symlink /etc/nixos/flake.nix, if it exists. The flake must contain an output named
       ‘nixosConfigurations.name’. If name is omitted, it default to the current host name.
```

`nixosConfigurations.<name>`にNixOSの構成情報を書けば、`sudo nixos-rebuild switch --flake '.#name'`でそれを適用できることが書かれている。

そして、`nixosConfigurations.<name>`に指定するのは`lib.nixosSystem`という関数である。これに関しては[redditで同じ疑問を抱いている人](https://www.reddit.com/r/NixOS/comments/13oat7j/what_does_the_function_nixpkgslibnixossystem_do/)がいるが、公式docには（少なくとも[nixpkgs](https://github.com/NixOS/nixpkgs/tree/master)と[nix](https://github.com/NixOS/nix/tree/master)の`docs/`下を`nixosSystem`で全文検索した限りだと）example的な記載しかない。どんな引数を指定すればよいのか、というのは公式docでは見つからないため、現在Wikiや上記参考記事を見ながら設定するほかない（これは、まだflakeがexperimentalな概念だからだろうか…？ そもそもいつまでexperimentalなんだよ、というのには事情があるらしく、[Why are flakes still experimental?](https://discourse.nixos.org/t/why-are-flakes-still-experimental/29317)の話が参考になる）。

ともかく現状では、次のように書けば、flakeを使ってNixOSの構成ができる。
* `nixos`をinputに加える。このパッケージセットを使ってNixOSをビルドする。
* `nixos.lib.nixosSystem`の`modules`に、先ほど持ってきた`configuration.nix`を指定する
```nix
{
  description = "NixOS and Home Manager Configuration";

  inputs = {
    nixos.url = github:NixOS/nixpkgs/nixos-23.11;
  };

  outputs = { self, nixos }: {
    nixosConfigurations = {
      minimal = nixos.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          ./hosts/minimal/configuration.nix
        ];
      };
    };
  };
}
```

文法チェックして問題なさそうならビルドする。
```shell-session
[bombrary@nixos:~/dotfiles]$ nix flake check
[bombrary@nixos:~/dotfiles]$ sudo nixos-rebuild switch --flake '.#minimal'
```

### （おまけ）flakeの中身の確認方法

ちなみに、nixosSystem関数の出力がどんなものになっているのかを確認したい場合は、`nix repl`で確認可能。[getFlake](https://nixos.org/manual/nix/stable/language/builtins.html#builtins-getFlake)関数でflakeを読み込める。

```shell-session
[bombrary@nixos:~/dotfiles]$ nix repl
Welcome to Nix 2.18.1. Type :? for help.

nix-repl> flake = builtins.getFlake (toString ./.)

nix-repl> flake
{ _type = "flake"; homeConfigurations = { ... }; inputs = { ... }; lastModified = 1707309872; lastModifiedDate = "20240207124432"; narHash = "sha256-SHjA9tievH601ehouc/NGorEfScmXIYipV4fJX88TkI="; nixosConfigurations = { ... }; outPath = "/nix/store/l0ji9h0c2wr599m6rmmw2hm8hcf1lzqh-source"; outputs = { ... }; sourceInfo = { ... }; }

nix-repl> flake.nixosConfigurations
{ minimal = { ... }; }

nix-repl> flake.nixosConfigurations.minimal
{ _module = { ... }; _type = "configuration"; class = "nixos"; config = { ... }; extendModules = «lambda @ /nix/store/ws5098bfhd2kzvg3yxwb2ggvl05h7gfd-source/nixos/lib/eval-config.nix:113:21»; extraArgs = { ... }; options = { ... }; pkgs = { ... }; type = { ... }; }
```

### （おまけ）パッケージの検索

`nixos-generate-config`で生成されて設定ファイルに以下のコメントが書かれていた。
> List packages installed in system profile. To search, run:
> $ nix search wget

[NixOS Search](https://search.nixos.org/packages)でパッケージを検索できることは知っていたが、どうやら `nix search` コマンドでも検索できるらしい。

```console
[bombrary@nixos:~/dotfiles]$ nix search nixpkgs [package name]

# NeoVimを検索する例
[nix-shell:~]$ nix search nixpkgs '\.neovim'
* legacyPackages.x86_64-linux.neovim (0.9.5)
  Vim text editor fork focused on extensibility and agility
...
```

`legacyPackages` と書いてあるので古いパッケージを参照しているのでは？と思ってしまうが、[flake.nixのコメント](https://github.com/NixOS/nixpkgs/blob/master/flake.nix#L64)を読むと、どうやらそういうわけではないらしい。`packages`の代替としてこの名前が使われているようだ。

なお、引数の `nixpkgs` flake-registryに登録されたものを参照して、そこからリポジトリを引っ張って来ている模様。現在のflake-registryは以下のコマンドで確認可能。

```shell-session
[bombrary@nixos:~/dotfiles]$ nix registry list
global flake:agda github:agda/agda
global flake:arion github:hercules-ci/arion
global flake:blender-bin github:edolstra/nix-warez?dir=blender
global flake:bundlers github:NixOS/bundlers
global flake:cachix github:cachix/cachix
global flake:composable github:ComposableFi/composable
global flake:disko github:nix-community/disko
global flake:dreampkgs github:nix-community/dreampkgs
global flake:dwarffs github:edolstra/dwarffs
global flake:emacs-overlay github:nix-community/emacs-overlay
global flake:fenix github:nix-community/fenix
global flake:flake-parts github:hercules-ci/flake-parts
global flake:flake-utils github:numtide/flake-utils
global flake:gemini github:nix-community/flake-gemini
global flake:helix github:helix-editor/helix
global flake:hercules-ci-agent github:hercules-ci/hercules-ci-agent
global flake:hercules-ci-effects github:hercules-ci/hercules-ci-effects
global flake:home-manager github:nix-community/home-manager
global flake:hydra github:NixOS/hydra
global flake:mach-nix github:DavHau/mach-nix
global flake:nickel github:tweag/nickel
global flake:nimble github:nix-community/flake-nimble
global flake:nix github:NixOS/nix
global flake:nix-darwin github:LnL7/nix-darwin
global flake:nix-serve github:edolstra/nix-serve
global flake:nixops github:NixOS/nixops
global flake:nixos-hardware github:NixOS/nixos-hardware
global flake:nixos-homepage github:NixOS/nixos-homepage
global flake:nixos-search github:NixOS/nixos-search
global flake:nixpkgs github:NixOS/nixpkgs/nixpkgs-unstable
global flake:nur github:nix-community/NUR
global flake:patchelf github:NixOS/patchelf
global flake:poetry2nix github:nix-community/poetry2nix
global flake:pridefetch github:SpyHoodle/pridefetch
global flake:sops-nix github:Mic92/sops-nix
global flake:systems github:nix-systems/default
global flake:templates github:NixOS/templates
```

現在のNixOSのバージョンである23.11のパッケージを検索したいなら、`-I nixpkgs=...` でパッケージのリポジトリを書き換える。

```shell-session
[bombrary@nixos:~/dotfiles]$ nix search -I nixpkgs=flake:github:NixOS/nixpkgs/nixos-23.11 nixpkgs
```

## （追記）共通の設定をmoduleに分ける

[設定ファイルの作成](#create-nix-configuration)で`configuration.nix`を作成したが、今後 `dotfiles` で複数のホストの設定を管理することを考えると、共通の設定を別ファイルで分割・利用できると良い。そのような場合に [NixOS modules](https://nixos.wiki/wiki/NixOS_modules)の仕組みが使える。

とはいっても使い方は簡単で、単に `imports = [...]` に分割した設定ファイルへのパスを記述するだけなので、試しにやってみる。

moduleを入れておくディレクトリを作成する。愚直すぎるが今回は`common.nix`という一枚岩のファイルに、共通化した設定を記述することにする。
```console
[bombrary@nixos:~/dotfiles]$ mkdir modules
[bombrary@nixos:~/dotfiles]$ touch modules/common.nix
```

`common.nix`の中身は以下のようにする。タイムゾーンやユーザ、ロケール、最低限のパッケージの設定をここに分割した。
```nix
{ config, lib, pkgs, ... }:

{
  time.timeZone = "Asia/Tokyo";
  i18n.defaultLocale = "en_US.UTF-8";

  users.users.bombrary = {
    isNormalUser = true;
    extraGroups = [ "wheel" ]; # Enable ‘sudo’ for the user.
  };

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
    vim
    git
  ];
}
```

設定を `modules/common.nix` に切り出したので、 `hosts/minimal/configuration.nix` は以下のようにすっきりと書ける。`imports` の中に `modules/common.nix` へのパスを指定することで、設定を読み込んでいる。
```nix
{ config, lib, pkgs, ... }:

{
  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix
      ../../modules/common.nix
    ];

  networking.hostName = "nixos"; # Define your hostname.

  # Use the systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Do NOT change this value unless you have manually inspected all the changes it would make to your configuration,
  # and migrated your data accordingly.
  #
  # For more information, see `man configuration.nix` or https://nixos.org/manual/nixos/stable/options#opt-system.stateVersion .
  system.stateVersion = "23.11"; # Did you read the comment?
}
```

設定が終わったら、`git add` してindexに追加した後、`nixos-rebuild`コマンドで設定を反映させる。

```console
[bombrary@nixos:~/dotfiles]$ git add modules/common.nix
[bombrary@nixos:~/dotfiles]$ sudo nixos-rebuild switch --flake .#minimal
```

今回は `modules/common.nix` という1ファイルに設定を分割したが、汎用性を考えると、例えば
* 共通のユーザ、SSHの公開鍵などの設定は `modules/users.nix`
* FWやプロキシの設定は `modules/network.nix`
* 必要最低限のパッケージ・サービスは `modules/packages.nix`
* その他の設定は `modules/others.nix`

などで分けるとよいのかもしれない。もちろん、
* ホスト名
* 静的IPを設定している場合はその設定

などはサーバ個別の設定となるので、module分割はせず`configuration.nix`に記載すればよい。このあたりの管理の仕方はいろいろ自由が効く。


## Home Managerのセットアップ

OSの構成は最小限に抑えて、ユーザがメインで使うエディタやユーティリティコマンドはhome-managerで管理することにする。

まずはマニュアルを見てみる。マニュアルの開き方についてドキュメントの記載箇所が見つけられなかったが、[home-managerのflake.nix](https://github.com/nix-community/home-manager/blob/master/flake.nix)を読むと、outputsの`docs-manpages`がmanpageのderivationになっていることがわかる。なのでそこからマニュアルを入手する。

`nix shell [flake-registry]#[package]`で、一時的にパッケージを導入した状態で新しいシェルに入る。`nix-shell -p [package]`コマンドというのもあるが、
* `nix-shell`は、デフォルトでは環境変数`NIX_PATH`に指定された`nixpkgs`のパスから
* `nix shell`は`flake-registry`から

パッケージを持ってくる（はず）。そこまで使用感に差はないが、今回は後者を使ってみる。
```
[bombrary@nixos:~/home-manager]$ nix shell home-manager#docs-manpages

[bombrary@nixos:~/home-manager]$ man home-manager
```

オプションを見ると、`homeConfigurations.<name>`をflakeのoutputに指定すれば、home-managerの設定をflakeで扱えるようになることが書かれている。
```
--flake flake-uri[#name]
       Build Home Manager configuration from the flake, which must contain the output homeConfigurations.name. If no name is specified it will first try username@hostname and then username.
```

で、そのための関数だが、（これもマニュアルに記載箇所が見つけられなかったが）、同じくhome-managerの`flake.nix`を探ると、`home-manager.lib.homeManagerConfiguration { ... }` っぽいことが分かる。

また、home-managerの設定ファイルのひな形を作成するコマンドについても記載がある。これで`home.nix`が自動作成されるようだ。
```
init [--switch [dir]]
       Generates an initial home.nix file for the current user. If Nix flakes are  enabled,  then  this
       command also generates a flake.nix file.
```

ここまでわかったところで、実際に設定を作成していく。記事冒頭で参考にするといっていた[dotfiles](https://github.com/hlissner/dotfiles/tree/master)ではhomeConfigurationsを用いていないので、どうディレクトリを構成していくのか悩ましいが、ここでは`home/<ユーザ名>/home.nix`を作成することにする。
```console
[bombrary@nixos:~/dotfiles]$ mkdir home
[bombrary@nixos:~/dotfiles]$ nix run home-manager -- init home/bombrary
Creating home/bombrary/home.nix...
Creating home/bombrary/flake.nix...
```

`flake.nix`はすでに作成済みであり、余計なので消す。
```
[bombrary@nixos:~/dotfiles]$ rm home/bombrary/flake.nix
```

`home.nix`の中身は後で見るとして、これを `flake.nix` に紐づける。`flake.nix`を編集。
* `inputs`に以下を追加
  * nixpkgs
  * home-manager
    * inputs.nixpkgs.followsというのは、おそらく、[home-managerのflake.nix](https://github.com/nix-community/home-manager/blob/master/flake.nix)に指定されている`inputs.nixpkgs`を、このファイルの`nixpkgs`にするよ、という意味。公式docは[Flake inputs](https://nixos.org/manual/nix/stable/command-ref/new-cli/nix3-flake#flake-inputs)に乗っている。
* 上記を`outputs`の引数に指定
* `homeConfigurations.bombrary = home-manager.lib.homeManagerConfiguration { ... }`を設定
  * `modules`に先ほど作成した`home.nix`のパスを指定する

```nix
{
  description = "NixOS and Home Manager Configuration";

  inputs = {
    nixos.url = github:NixOS/nixpkgs/nixos-23.11;
    nixpkgs.url = github:NixOS/nixpkgs/nixos-unstable;
    home-manager = {
      url = github:nix-community/home-manager;
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixos, nixpkgs, home-manager }: {
    nixosConfigurations = {
      minimal = nixos.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          ./hosts/minimal/configuration.nix
        ];
      };
    };

    homeConfigurations = {
      bombrary = home-manager.lib.homeManagerConfiguration {
        pkgs = import nixpkgs {
          system = "x86_64-linux";
        };
        modules = [
          ./home/bombrary/home.nix
        ];
      };
    };
  };
}
```

チェックしてビルド。
```shell-session
[bombrary@nixos:~/dotfiles]$ nix flake check
warning: updating lock file '/home/bombrary/dotfiles/flake.lock':
• Added input 'home-manager':
    'github:nix-community/home-manager/21b078306a2ab68748abf72650db313d646cf2ca' (2024-02-11)
• Added input 'home-manager/nixpkgs':
    follows 'nixpkgs'
• Added input 'nixpkgs':
    'github:NixOS/nixpkgs/d934204a0f8d9198e1e4515dd6fec76a139c87f0' (2024-02-10)

[bombrary@nixos:~/dotfiles]$ nix run home-manager -- switch --flake .#bombrary
```

`flake.nix`に`programs.home-manager.enable=true`が設定されているので、この時点で`home-manager`コマンドが使えるようになっていることを確認する。
```shell-session
[bombrary@nixos:~/config]$ home-manager generations
2024-02-11 11:18 : id 1 -> /nix/store/05ga8qd4vkj73zy4sfva9flj6wasb4wy-home-manager-generation

[bombrary@nixos:~/config]$ home-manager packages
hm-session-vars.sh
home-configuration-reference-manpage
home-manager
man-db-2.12.0
shared-mime-info-2.4
```

以降は以下のように、`nix run`無しで動かせるようになる。
```console
[bombrary@nixos:~/config]$ home-manager switch --flake .#bombrary
```

## Home Managerの設定

* まずは`home.nix`のひな形に親切なコメントがたくさんあるので、それを読みつつ編集する。
* ほかには、以下のページを参考にする
  * [Appendix A Home Manager Configuration Examples](https://nix-community.github.io/home-manager/options.xhtml)
  * [Home Manager - NixOS Wiki](https://nixos.wiki/wiki/Home_Manager)

## パッケージを入れる

必要なパッケージを入れる。
* アプリケーションに寄っては、`programs.<application>`での指定方法と`home.packages`に指定する方法が2つあるが、後者のほうがユーザに親切なオプションがついていることがあるので、[Appendix A Home Manager Configuration Examples](https://nix-community.github.io/home-manager/options.xhtml)を漁ってみるとよいかも
* エイリアスは`programs.<shell名>.shellAliases`で設定可能
  * bashの場合は[programs.bash.shellAliases](https://nix-community.github.io/home-manager/options.xhtml#opt-programs.bash.shellAliases)
  * [home.shellAliases](https://nix-community.github.io/home-manager/options.xhtml#opt-home.shellAliases)は、なぜか反応しない
```nix
{
  ...
  home.packages = with pkgs; [
    tmux
    ripgrep
    eza
    bat
    fd
    zig
    deno
  ];

  programs.neovim = {
    enable = true;
    defaultEditor = true;
  };

  programs.git = {
    enable = true;
    userName = "（ユーザ名）";
    userEmail = "（メールアドレス）";
  };

  programs.bash = {
    enable = true;
    shellAliases = {
      ls = "eza --icons";
      cat = "bat";
    };
  };
  ...
}
```

## dotfilesの管理

Home Managerでは、.tmux.confやvimrcなどのdotfileを配置する設定が書ける。

そのdotfilesをどうやって管理するかだが、いろいろやりようはあると思う。
* 別リポジトリで管理
  * flakeのinputsにconfigのリポジトリを指定する
  * submoduleとしてconfigのリポジトリを追加する
    * flakeにinputsにパス指定
    * `home.nix`に直接パス指定
* 今のディレクトリにconfigのようなディレクトリを作成
  * flakeのinputsにconfigへのパス指定
  * `home.nix`に直接configへのパス指定

などやり方が考えられる。どれを選ぶかを考える上で、変更の容易さという観点は気に留めたほうが良い。Nixで指定されたファイルはすべて`/nix/store`に取り込まれ、read-only fileシステムになる。そのため、例えばビルド後に`~/.config/nvim/init.nvim`を直接編集することはできない。

その観点で考えると、例えば「少しずつ設定ファイルをいじりながら様子を見たい」という場合、手間が少なく一番楽なのは最後の「今のディレクトリにconfigディレクトリ作成 & home.nix にconfigへのパス指定」の方法だと思われる。なのでそれで進めていく。

`config`ディレクトリを作成し、そこに各種設定ファイルを入れていく。自分の場合は過去育ててきたファイルたちがあるのでそれを入れる。configの構成としては、「`nvim`ディレクトリにneovim関連、`tmux`ディレクトリにtmux関連の設定ファイル」のように分ける
```console
[bombrary@nixos:~/dotfiles]$ mkdir config

（ファイルを追加する）

[bombrary@nixos:~/dotfiles]$ nix run nixpkgs#tree -- -a config
config
├── nvim
│   ├── init.lua
│   └── lua
│       └── plugins
│           ├── ddu.lua
│           ├── global.lua
│           └── lsp.lua
└── tmux
    └── .tmux.conf

5 directories, 5 files
```

`home.nix`では、以下のように`home.file.<name>`の`source`と`target`でパスを指定する。
```nix
{ config, pkgs, myconfig, ... }:

{
  ...
  home.file = {
    ".tmux.conf" = {
      source = ../../config/tmux/.tmux.conf;
      target = ".tmux.conf";
    };
    "init.lua" = {
      source = ../../config/nvim/init.lua;
      target = ".config/nvim/init.lua";
    };
    "lua" = {
      source = ../../config/nvim/lua;
      target = ".config/nvim/lua";
    };
  };
  ...
}
```

これで`home-manager switch --flake .#<name>`を実行すれば、dotfilesが想定通りの位置に配置される。

## （追記）dotfiles管理後のNixOSセットアップ方法

dotfilesで管理した後に、追加でほかのサーバーにNixOSを導入したい場合の手順。

* dotfilesはGitのリモートリポジトリで管理していることを前提とする
* VMの場合はovaファイルで固めれば早いのだが、物理マシンに導入するシナリオも考えて、インストールディスクからやることを想定する。

`nixos-install` のときに `--flake` 引数が指定できるところがポイントである。

まず [パーティションの作成](#make-partition) までは進める。

Gitを一時的に導入し、それを用いてdotfilesリポジトリをcloneしてくる。
```console
[root@nixos:~]# nix shell --extra-experimental-features 'nix-command flakes' nixpkgs#git
[root@nixos:~]# git clone (リポジトリのURL)
[root@nixos:~]# cd dotfiles
```

`nixos-generate-config`で設定ファイルの生成を行う。
```console
[root@nixos:~]# nixos-generate-config --root /mnt
writing /mnt/etc/nixos/hardware-configuration.nix...
writing /mnt/etc/nixos/configuration.nix...
For more hardware-specific settings, see https://github.com/NixOS/nixos-hardware.
```

生成したファイルを `hosts/<host名>` ディレクトリに移す。
```console
[root@nixos:~/dotfiles]# mkdir hosts/minimal2
[root@nixos:~/dotfiles]# mv /mnt/etc/nixos/* hosts/minimal2/
```

`hosts/<host名>/configuration.nix` をよしなに編集する。例えば自作のmoduleを使いたければそれを指定する。
```nix
{ config, lib, pkgs, ... }:

{
  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix
      ../../modules/common.nix
    ];
  ...
}
```

`flake.nix`の`nixosConfigurations` に、今回追加したホストの設定をする。
```nix
{
  ...
  outputs = { self, nixos, nixpkgs, home-manager }: {
    nixosConfigurations = {
      ...
      minimal2 = nixos.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          ./hosts/minimal2/configuration.nix
        ];
      };
      ...
    };
}
```

`git add` でindexを追加して、 `--flake .#<flake.nixで設定したホスト名>`でNixOSのインストールを行う。
```console
[root@nixos:~/dotfiles]# git add .
[root@nixos:~/dotfiles]# nixos-install --flake .#minimal2
```

そのあと、必要に応じてdotfilesをcommit、pushする。

念のため、ユーザディレクトリにdotfilesを退避しておく。
```console
[root@nixos:~/dotfiles]# cd ../

[root@nixos:~]# mv dotfiles /mnt/home/bombrary/
```

これ以降の作業は [NixOSのインストール](#nixos-install) の、インストール後の作業と同様である。 `nixos-enter` 後にユーザのパスワード設定をしたら、アンマウントして再起動すればよい。

## 最後に

とりあえず現時点での設定はここまで。これから試行錯誤して、書き方とかディレクトリ構成とかを改善していく。
