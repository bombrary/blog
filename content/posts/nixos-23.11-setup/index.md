---
title: "NixOS & Home Managerのセットアップメモ"
date: 2024-02-11T18:00:00+09:00
tags: []
categories: ["NixOS"]
---

NixOS 23.11をセットアップした時のメモ。

## インストールディスクの起動

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

## パーティション作成・ディスクフォーマット

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

```shell-session
[root@nixos:~]# parted /dev/sda -- mklabel gpt
[root@nixos:~]# parted /dev/sda -- mkpart root ext4 512MG -8GB
[root@nixos:~]# parted /dev/sda -- mkpart swap linux-swap -8GB 100%
[root@nixos:~]# parted /dev/sda -- mkpart ESP fat32 1MB 512MB
[root@nixos:~]# parted /dev/sda -- set 3 esp on
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
* `/dev/sda2`をswapでフォーマットし
* `/dev/sda3`をfat32でフォーマット

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

デバイスのマウント。
* root partitionの領域を `/mnt/` にマウント
* boot partitionの領域を `/mnt/boot` にマウント
* swap partitionの領域をswap領域として有効化

```shell-session
[root@nixos:~]# mount /dev/sda1 /mnt

[root@nixos:~]# mkdir /mnt/boot
[root@nixos:~]# mount /dev/sda3 /mnt/boot

[root@nixos:~]# swapon /dev/sda2
```

今一度ディスク情報を確認。マウントした領域と切ったパーティションの領域のサイズがここで一致しているのかを確認。
```shell-session
[root@nixos:~]# df -H | grep sda
/dev/sda1        97G   29k   92G   1% /mnt
/dev/sda3       510M  4.1k  510M   1% /mnt/boot
```

## NixOS設定ファイルの作成

`configuration.nix`の初期ファイルを作成。

```shell-session
[root@nixos:~]# nixos-generate-config --root /mnt
writing /mnt/etc/nixos/hardware-configuration.nix...
writing /mnt/etc/nixos/configuration.nix...
For more hardware-specific settings, see https://github.com/NixOS/nixos-hardware.
```

コメント文をもとに適当に編集する。後で一般ユーザに入って細かい設定をするので、ここでは仮のものを作る。
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

最後にパスワード設定を促されたと思うが、これはrootのパスワードである。一般ユーザのパスワードを忘れず行う。
```shell-session
[root@nixos:~]# passwd bombrary
New password:
Retype new password:
passwd: password updated successfully
```

アンマウントしたうえで再起動する。

```shell-session
[root@nixos:~]# umount /mnt/boot

[root@nixos:~]# umount /mnt

[root@nixos:~]# reboot

Broadcast message from root@nixos on pts/1 (Tue 2024-02-06 11:25:37 UTC):

The system will reboot now!
```

このとき、CD・ISOを取り外した上で再起動する。

SSHで一般ユーザでログインできることを確認する。
```shell-session
~> ssh bombrary@192.168.11.7
(bombrary@192.168.11.7) Password:
Last login: Tue Feb  6 20:30:18 2024 from 192.168.11.6

[bombrary@nixos:~]$ su root
```

## Flakesを利用したNixOS設定ファイルの作成

再利用の観点から、Nix Flakesを利用した方法に切り替える。やり方としては

* [Using nix flakes with NixOS](https://nixos.wiki/wiki/Flakes#Using%20nix%20flakes%20with%20NixOS)
* [NixOSで最強のLinuxデスクトップを作ろう](https://zenn.dev/asa1984/articles/nixos-is-the-best)

が参考になる。

適当な作業ディレクトリを作ってその中で作業する。
```shell-session
[bombrary@nixos:~]$ mkdir config
[bombrary@nixos:~]$ cd config
```

先ほど作った`/etc/nixos/configuration.nix`と、自動生成されている`/etc/nixos/hardware-configuration.nix`を持ってくる。「必要最小限の構成にしたOS設定」という体で、適当に`minimal`などというディレクトリを作ってそこに設定ファイルを入れる。
```shell-session
[bombrary@nixos:~/config]$ mkdir -p os-configs/minimal/
[bombrary@nixos:~/config]$ cp /etc/nixos/* os-configs/minimal/
```

`flake.nix`のひな形を作る。
```shell-session
[bombrary@nixos:~/config]$ nix flake init
wrote: /home/bombrary/config/flake.nix
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
[bombrary@nixos:~/config]$ nix flake check
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
  description = "NixOS Configuration";

  inputs = {
    nixos.url = github:NixOS/nixpkgs/nixos-23.11;
  };

  outputs = { self, nixpkgs }: {
    nixosConfigurations = {
      minimal = nixos.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [ ./os-configs/minimal/configuration.nix ];
      };
    };
  };
}
```

文法チェックして問題なさそうならビルドする。
```shell-session
[bombrary@nixos:~/config]$ nix flake check
[bombrary@nixos:~/config]$ sudo nixos-rebuild switch --flake '.#minimal'
```

## （おまけ）flakeの中身の確認方法

ちなみに、nixosSystem関数の出力がどんなものになっているのかを確認したい場合は、`nix repl`で確認可能。[getFlake](https://nixos.org/manual/nix/stable/language/builtins.html#builtins-getFlake)関数でflakeを読み込める。

```shell-session
[bombrary@nixos:~/config]$ nix repl
Welcome to Nix 2.18.1. Type :? for help.

nix-repl> flake = builtins.getFlake (toString ./.)

nix-repl> flake
{ _type = "flake"; homeConfigurations = { ... }; inputs = { ... }; lastModified = 1707309872; lastModifiedDate = "20240207124432"; narHash = "sha256-SHjA9tievH601ehouc/NGorEfScmXIYipV4fJX88TkI="; nixosConfigurations = { ... }; outPath = "/nix/store/l0ji9h0c2wr599m6rmmw2hm8hcf1lzqh-source"; outputs = { ... }; sourceInfo = { ... }; }

nix-repl> flake.nixosConfigurations
{ minimal = { ... }; }

nix-repl> flake.nixosConfigurations.minimal
{ _module = { ... }; _type = "configuration"; class = "nixos"; config = { ... }; extendModules = «lambda @ /nix/store/ws5098bfhd2kzvg3yxwb2ggvl05h7gfd-source/nixos/lib/eval-config.nix:113:21»; extraArgs = { ... }; options = { ... }; pkgs = { ... }; type = { ... }; }
```

## （おまけ）パッケージの検索

`nixos-generate-config`で生成されて設定ファイルに以下のコメントが書かれていた。
> List packages installed in system profile. To search, run:
> $ nix search wget

[NixOS Search](https://search.nixos.org/packages)でパッケージを検索できることは知っていたが、どうやら `nix search` コマンドでも検索できるらしい。

```console
[bombrary@nixos:~/config]$ nix search nixpkgs [package name]

# NeoVimを検索する例
[nix-shell:~]$ nix search nixpkgs '\.neovim'
* legacyPackages.x86_64-linux.neovim (0.9.5)
  Vim text editor fork focused on extensibility and agility
...
```

`legacyPackages` と書いてあるので古いパッケージを参照しているのでは？と思ってしまうが、[flake.nixのコメント](https://github.com/NixOS/nixpkgs/blob/master/flake.nix#L64)を読むと、どうやらそういうわけではないらしい。`packages`の代替としてこの名前が使われているようだ。

なお、引数の `nixpkgs` flake-registryに登録されたものを参照して、そこからリポジトリを引っ張って来ている模様。現在のflake-registryは以下のコマンドで確認可能。

```shell-session
[bombrary@nixos:~/config]$ nix registry list
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
[bombrary@nixos:~/config]$ nix search -I nixpkgs=flake:github:NixOS/nixpkgs/nixos-23.11 nixpkgs
```

## Home Managerのセットアップ

OSの構成は最小限に抑えて、ユーザがメインで使うエディタやユーティリティコマンドはhome-managerで管理することにする。

まずはマニュアルを見てみる。マニュアルの開き方についてドキュメントの記載箇所が見つけられなかったが、、[home-managerのflake.nix](https://github.com/nix-community/home-manager/blob/master/flake.nix)を読むと、outputsの`docs-manpages`がmanpageのderivationになっていることがわかる。なのでそこからマニュアルを入手する。

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

ここまでわかったところで、実際に設定を作成していく。まず適当にディレクトリを切って、`home.nix`を作成する。ここでは、`home-configs/<ユーザ名>/`に作成することにする。
```console
[bombrary@nixos:~/config]$ mkdir -p home-configs

[bombrary@nixos:~/config]$ nix run home-manager -- init home-configs/bombrary
Creating home-configs/bombrary/home.nix...
Creating home-configs/bombrary/flake.nix...
```

`flake.nix`はすでに作成済みであり、余計なので消す。
```
[bombrary@nixos:~/config]$ rm home-configs/bombrary/flake.nix
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
  description = "NixOS and home-mamager Configuration";

  inputs = {
    nixos.url = github:NixOS/nixpkgs/nixos-23.11;
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixos, home-manager, nixpkgs, ... }: {
    nixosConfigurations = {
      minimal = nixos.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [ ./os-configs/minimal/configuration.nix ];
      };
    };

    homeConfigurations = {
      bombrary = home-manager.lib.homeManagerConfiguration {
        pkgs = import nixpkgs {
          system = "x86_64-linux";
        };
        modules = [
          ./home-configs/bombrary/home.nix
        ];
      };
    };
  };
}
```

チェックしてビルド。
```shell-session
[bombrary@nixos:~/config]$ nix flake check
[bombrary@nixos:~/config]$ nix run home-manager -- switch --flake .#bombrary
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

gitが無いみたいなエラーが出た場合は、以下のようにgitを一時的に追加したうえでhome-managerを動かす。
```console
[bombrary@nixos:~/config]$ nix shell nixpkgs#git
[bombrary@nixos:~/config]$ home-manager switch --flake .#bombrary
```

## Home Managerの設定

* まずは`home.nix`のひな形に親切なコメントがたくさんあるので、それを読みつつ編集する。
* [Appendix A Home Manager Configuration Examples](https://nix-community.github.io/home-manager/options.xhtml)を参考にする
* [Home Manager - NixOS Wiki](https://nixos.wiki/wiki/Home_Manager)

を参考にする。

## パッケージを入れる

必要なパッケージを入れる。
```nix
{
  ...
  home.packages = with pkgs; [
    tmux
    neovim
    git
    eza
    ripgrep
    delta
    bat
    fd
  ];
  ...
}
```

## dotfilesの管理

Home Managerでは、.tmux.confやvimrcなどのdotfileを配置する設定が書ける。

そのdotfilesをどうやって管理するかだが、いろいろやりようはあると思う。
* 別リポジトリで管理
  * flakeのinputsにdotfilesのリポジトリを指定する
  * submoduleとしてdotfilesのリポジトリを追加する。
* 今のディレクトリにdotfilesのようなディレクトリを作成
  * flakeのinputsにdotfilesへのパスを指定する
  * `home.nix`に直接dotfilesへのパスを指定する

などやり方が考えられる。どれを選ぶかを考える上で、変更の容易さという観点は気に留めたほうが良い。その観点でいうと、「別リポジトリ管理 & flakeのinputに指定」という方法に関しては、設定ファイルをいじるのが簡単ではなくなってしまう。なぜなら、flakeのinputで取り込んだファイルはread-only file system扱いになるからである（NixOS自体、環境の高い再現性を目指したシステムなので、これは仕方ない）。なので、例えばビルド後に `.config/nvim/init.nvim` を直接編集することはできない。

（面倒でなければ、設定ファイルの動作確認をする環境を作ってしまうのもありか。しかし、CUIツールの環境であればDockerで作れるが、例えばi3のconfigみたいな、GUIに依存するソフトウェアの設定ファイルをいじる環境を作るとなると、別VMを立ててそこで検証することになりかなり大掛かりになってしまいそう）

逆に上記の基準以外は好みな気がするが、ここでは「今のディレクトリにdotfilesディレクトリ作成 & flake.nix にdotfilesへのパス指定」の方法をとってみたいと思う。
`dotfiles`ディレクトリを作成し、そこに各種設定ファイルを入れていく。自分の場合は過去育ててきたファイルたちがあるのでそれを入れる。
```console
[bombrary@nixos:~/config]$ mkdir dotfiles
```

まず`flake.nix`を編集する。
* `inputs`に新たに`dotfiles`を指定する
  * `url`には`dotfiles`へのパスを指定
  * `flake`ではなくただの設定ファイルの集まりのため、`flake=false`を指定
* `outputs`の引数に`dotfiles`を追加
* `homeConfigurations.<name>.extraSpecialArgs`に`dotfiles`を追加
```nix
{
  description = "NixOS Configuration";

  inputs = {
    nixos.url = github:NixOS/nixpkgs/nixos-23.11;
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    dotfiles = {
      url = "path:./dotfiles";
      flake = false;
    };
  };

  outputs = { self, nixos, home-manager, nixpkgs, dotfiles, ... }: {
    nixosConfigurations = {
      minimal = nixos.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [ ./os-configs/minimal/configuration.nix ];
      };
    };

    homeConfigurations = {
      bombrary = home-manager.lib.homeManagerConfiguration {
        pkgs = import nixpkgs {
          system = "x86_64-linux";
        };
        extraSpecialArgs = {
          inherit dotfiles;
        };
        modules = [
          ./home-configs/bombrary/home.nix
        ];
      };
    };
  };
}
```

`home.nix`では、
* 引数に`dotfiles`を追加する
* `home.file.<置く先のパス>.source = <実ファイルのパス>`で設定ファイルを置く
```nix
{ config, pkgs, dotfiles, ... }:

{
  ...
  home.file = {
    ".tmux.conf".source = "${dotfiles}/.tmux.conf";
    ".config/nvim/init.lua".source = "${dotfiles}/.config/nvim/init.lua";
    ".config/nvim/lua".source = "${dotfiles}/.config/nvim/lua";
  };
  ...
}
```

これで`home-manager switch --flake .#<name>`を実行すれば、dotfilesが想定通りの位置に配置される。

とりあえず現時点での設定はここまで。これから試行錯誤して、書き方とかディレクトリ構成とかを改善していく。
