---
title: "NixOSをlima上でセットアップ & dotfilesで管理"
date: 2026-06-17T08:17:46+09:00
tags: [ "lima" ]
categories: [ "NixOS" ]
---

## はじめに

MacOSでもlinux、特にNixOSを手軽に扱いたい。ディレクトリもシームレスに連携できる、いわゆるWSLっぽいことがしたい。

調べてみたら [lima](https://lima-vm.io/) というのがそれをやるのに適していそうなので、セットアップしてみたメモ

## nixos-lima-config-sampleの利用

limaでのVMの起動にはテンプレートイメージが必要。設定ファイルとして [nixos-lima/nixos-lima-config-sample](https://github.com/nixos-lima/nixos-lima-config-sample/tree/master) を参考にする。

nixos-lima-config-sample はあくまで設定のサンプルであり、以下が同封されている
* nixos.yaml：テンプレートイメージやマウント、メモリなどの設定を記載したlimaのファイル
* setup-nixos.sh：NixOSのセットアップをするためのヘルパースクリプト。単にリポジトリに同封されているnixos-lima-config.nixを読み込んでビルドするだけ
* setup-home-manager.sh：Home Managerのセットアップをするためのヘルパースクリプト。単にリポジトリに同封されているhome.nixを読み込んでビルドするだけ

nixos.yamlをみてみると、情報が少し古い。またNixOSやHome Managerの設定ファイルに関しては、自分が育てているdotfilesのディレクトリに組み込みたいので、以下の方針で進める。

* nixos.ymlを編集し、新規の [nixos-lima/nixos-lima](https://github.com/nixos-lima/nixos-lima/releases) のイメージを参照するようにする
* setup-nixos.sh や setup-home-manager.sh は使わない。ベースとなるnixos-lima-config.nixやhome.nixは自分のdotfilesに移動し、それらへのリンクをflake.nixに記載する

## セットアップ作業

* nixos.ymlをつかってVMを作成 & 起動
* NixOSのセットアップ
* Home Managerのセットアップ

### VMの作成・起動

[nixos-lima/nixos-lima-config-sample](https://github.com/nixos-lima/nixos-lima-config-sample/tree/master) をclone。

```sh
git clone https://github.com/nixos-lima/nixos-lima-config-sample.git
cd nixos-lima-config-sample
```

設定ファイルを自分のdotfiles用リポジトリに移動。
```sh
mkdir -p ~/dotfiles/lima
cp nixos.yaml ~/dotfiles/lima/
```

編集する。
* [nixos-lima/nixos-lima](https://github.com/nixos-lima/nixos-lima/releases) の最新リリースを指定。
* 書き込み権限を許可したいディレクトリを指定
```diff
--- a/nixos.yaml
+++ b/nixos.yaml
@@ -1,7 +1,7 @@
 images:
-  - location: "https://github.com/nixos-lima/nixos-lima/releases/download/v0.0.5/nixos-lima-v0.0.5-aarch64.qcow2"
+  - location: "https://github.com/nixos-lima/nixos-lima/releases/download/v0.2/nixos-lima-v0.2-aarch64.qcow2"
     arch: "aarch64"
-    digest: "sha512:e1daeb0dcec65c624253603ab5ec06f0831b0940cd95a88903f9bfd0ee4009b2c45806b868674c7e8cb12941e50799e85d710fc0e9ad659059108cebbc4d19c1"
+    digest: "sha512:dc297799d93f0fe6cb8fac779b97bb5e2712f0dd640eed53cc57d9c95844751a32d20ce794751fb56c128b35fe8a8a956cd08856b8818e9e6c377380d6f0cc4f"
   - location: "https://github.com/nixos-lima/nixos-lima/releases/download/v0.0.5/nixos-lima-v0.0.5-x86_64.qcow2"
     arch: "x86_64"
     digest: "sha512:51fbe74c569736f1141f1c6efeaa21a0901dff0bec5bc1e863c04c7765e150c3bebd82b7f50905fb7a0a9a9b050852c250ffbdcacd17b0dc15aeb86d47587436"
@@ -16,6 +16,11 @@ mounts:
   writable: true
   9p:
     cache: "mmap"
+- location: "~/dotfiles"
+  writable: true
+  9p:
+    # Try choosing "mmap" or "none" if you see a stability issue with the default "fscache".
+    cache: "mmap"

 memory: 8GiB
```

VMを起動。 `user.name` には好きなユーザ名（今回は自分の名前）を入れる。
```sh
limactl start --yes --set '.user.name = "bombrary"' ~/dotfiles/lima/nixos.yaml
```

指定したイメージのVMがDLされて起動する。
```console
bombrary@bombrary-macbookair:~/repos/nixos-lima-config-sample% limactl start --yes --set '.user.name = "bombrary"' nixos.yaml
INFO[0000] Terminal is not available, proceeding without opening an editor
INFO[0000] Starting the instance "nixos" with internal VM driver "vz"
INFO[0000] Attempting to download the image              arch=aarch64 digest="sha512:dc297799d93f0fe6cb8fac779b97bb5e2712f0dd640eed53cc57d9c95844751a32d20ce794751fb56c128b35fe8a8a956cd08856b8818e9e6c377380d6f0cc4f" location="https://github.com/nixos-lima/nixos-lima/releases/download/v0.2/nixos-lima-v0.2-aarch64.qcow2"
Downloading the image (nixos-lima-v0.2-aarch64.qcow2)
784.67 MiB / 784.67 MiB [----------------------------------] 100.00% 22.22 MiB/s
INFO[0036] Downloaded the image from "https://github.com/nixos-lima/nixos-lima/releases/download/v0.2/nixos-lima-v0.2-aarch64.qcow2"
INFO[0040] [hostagent] hostagent socket created at /Users/bombrary/.lima/nixos/ha.sock
INFO[0040] [hostagent] Starting VZ (hint: to watch the boot progress, see "/Users/bombrary/.lima/nixos/serial*.log")
INFO[0040] [hostagent] [VZ] - vm state change: running
INFO[0050] [hostagent] Started vsock forwarder: 127.0.0.1:56034 -> vsock:22 on VM
INFO[0050] [hostagent] Detected SSH server is listening on the vsock port; changed 127.0.0.1:56034 to proxy for the vsock port
INFO[0052] SSH Local Port: 56034
INFO[0051] [hostagent] Waiting for the essential requirement 1 of 3: "ssh"
INFO[0051] [hostagent] The essential requirement 1 of 3 is satisfied
INFO[0051] [hostagent] Waiting for the essential requirement 2 of 3: "user session is ready for ssh"
INFO[0051] [hostagent] The essential requirement 2 of 3 is satisfied
INFO[0051] [hostagent] Waiting for the essential requirement 3 of 3: "Explicitly start ssh ControlMaster"
INFO[0051] [hostagent] The essential requirement 3 of 3 is satisfied
INFO[0052] [hostagent] Waiting for the guest agent to be running
INFO[0052] [hostagent] Guest agent is running
INFO[0052] [hostagent] Waiting for the final requirement 1 of 1: "boot scripts must have finished"
INFO[0052] [hostagent] Not forwarding TCP 0.0.0.0:22
INFO[0052] [hostagent] Time sync: guest agent is alive, starting time synchronization
INFO[0052] [hostagent] Not forwarding TCP [::]:22
INFO[0052] [hostagent] Not forwarding UDP 0.0.0.0:68
INFO[0052] [hostagent] The final requirement 1 of 1 is satisfied
INFO[0052] READY. Run `limactl shell nixos` to open the shell.
bombrary@bombrary-macbookair:~/repos/nixos-lima-config-sample%
```

### NixOSのセットアップ

OSの設定ファイルを格納するディレクトリを作っておく。
```sh
mkdir -p ~/dotfiles/hosts/lima/
cp nixos-lima-config.nix ~/dotfiles/hosts/lima/
```

自分の場合は `~/dotfiles/flake.nix` で各ホストの構成を管理している。ここに新たに `lima` を追加する。
```nix
{
  description = "NixOS and Home Manager Configuration";

  inputs = {
    # ...
    nixos-lima = {
      url = "github:nixos-lima/nixos-lima/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixos, nixpkgs, home-manager, nixos-wsl, nixos-lima, ... }@inputs:
  {
    nixosConfigurations = {
      # ...
      lima = nixpkgs.lib.nixosSystem {
        system = "aarch64-linux";
        modules = [
          nixos-lima.nixosModules.lima
          ./hosts/lima/nixos-lima-config.nix
        ];
      };
    }; 

    homeConfigurations = {
      # ...
    };
  };
}
```

次にNixOSの設定ファイルを好きに編集する
* hostnameとstateVersionを変える
```diff
--- a/nixos-lima-config.nix
+++ b/nixos-lima-config.nix
@@ -7,7 +7,7 @@
       (modulesPath + "/profiles/qemu-guest.nix")
     ];

-    networking.hostName = "nixsample";
+    networking.hostName = "nix";

     # TODO: Consider setting some/all of the mandatory settings in `nixos-lima.nixosModules.lima`

@@ -52,5 +62,5 @@

     # The usual warnings about changing `stateVersion` apply. Make sure to find and read them
     # before changing this value.
-    system.stateVersion = "25.11";
+    system.stateVersion = "26.11";
 }
```

これを使ってNixOSをセットアップする。 `setup-nixos.sh` をみた限り、 `nixos-rebuild boot` を使ってセットアップしているみたいなのでそれに倣う。
```sh
limactl shell nixos -- sudo nixos-rebuild boot --flake '/Users/bombrary/dotfiles#lima'
limactl restart nixos
```

### Home Managerのセットアップ

home-managerの設定ファイルを格納するディレクトリを作っておく。
```sh
mkdir -p ~/dotfiles/home/lima/
cp home.nix ~/dotfiles/home/lima/
```

`home.nix` を好きな様に編集する。
```diff
@@ -1,6 +1,9 @@
 { config, pkgs, ... }:

 {
+  home.username = "bombrary";
+  home.homeDirectory = "/home/bombrary.guest";
+
   home.packages = [
     pkgs.hello
   ];
@@ -8,12 +11,12 @@
   programs.git = {
     enable = true;
     package = pkgs.gitMinimal;  # Minimal Git without Perl or Python
-    aliases = {
-      ci = "commit";
-      co = "checkout";
-      st = "status";
-    };
-    extraConfig = {
+    settings = {
+      alias = {
+        ci = "commit";
+        co = "checkout";
+        st = "status";
+      };
       safe = {
         directory = [ "/etc/nixos" ];
       };
@@ -22,5 +25,6 @@

   # Let Home Manager install and manage itself.
   programs.home-manager.enable = true;
-}

+  home.stateVersion = "26.11";
+}
```

flake.nixのhomeConfigurationsに追記。
```nix
{
  description = "NixOS and Home Manager Configuration";

  inputs = {
    # ...
  };

  outputs = { self, nixos, nixpkgs, home-manager, nixos-wsl, nixos-lima, ... }@inputs:
  {
    nixosConfigurations = {
      # ...
    }; 

    homeConfigurations = {
      # ...
      "bombrary@lima" = home-manager.lib.homeManagerConfiguration {
        pkgs = import nixpkgs { system = "aarch64-linux"; };
        modules = [ ./home/lima/home.nix ];
      };
    };
}
```

以下コマンドで切り替え。
```sh
# 初回
limactl shell nixos -- nix run home-manager/master -- switch --flake '/Users/bombrary/dotfiles#bombrary@lima'

# 2回目以降
limactl shell nixos -- home-manager switch --flake '/Users/bombrary/dotfiles#bombrary@lima'
```


## シェルへの入り方

以下でNixOSのシェルに入れる。
```sh
limactl shell nixos
```

## （おまけ）VMを消したい場合

セットアップを全部やり直したい場合。
```sh
# VMをpower offしたうえで削除
limactl delete -f nixos

# VMのイメージのキャッシュを削除
limactl prune
```

## おわりに

lima自体のセットアップはかなり簡単にできた。これはlimaの設定ファイルを [nixos-lima/nixos-lima-config-sample](https://github.com/nixos-lima/nixos-lima-config-sample/tree/master) が用意してくれたおかげ。

あとは普通にNixOSやHome Managerのセットアップなのでいつも通りだった。

`limactl shell nixos` だけでシェルに入れるのは楽なので、手軽にNixOSに入っていろいろ検証できそう。結構手軽に作ったり消したりできるのも良い感じ。
