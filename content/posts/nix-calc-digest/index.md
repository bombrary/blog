---
title: "Nixのstore path、ハッシュの計算方法メモ"
date: 2024-03-03T08:43:16+09:00
draft: true
tags: []
categories: ["Nix"]
---

Nixでは、パッケージの再現性を担保するために、`/nix/store/`下にハッシュ値を含んだ名前であらゆるファイルを保管する。そのハッシュ値がどのような情報から計算されるものなのかを知っておくことは、なぜNixが再現性を確保できるのかを考える上で重要である。

## 参考記事

* [How Nix Isntantiation Works (Web Archive)](https://web.archive.org/web/20221001050043/https://comono.id/posts/2020-03-20-how-nix-instantiation-works/)
* [Nix manual(unstable)ののProtocol - Store Path](https://nixos.org/manual/nix/unstable/protocols/store-path)
* [Nix PillsのChapter 18](https://nixos.org/guides/nix-pills/nix-store-paths)

## store pathの種類

ほとんど[Store Path](https://nixos.org/manual/nix/unstable/protocols/store-path)の書き起こしみたいになってしまうが書いておく。

まずstore pathは、`/nix/store/<digest>-<name>`の形式を持っている。
* `<digest>`というのは、fingerprint（後述）をSHA-256でハッシュ化し、その先頭160bitをNix32形式にしたものである
  * ドキュメントではいまだBase32表現と記載があるが、[Release Note 2.20](https://nixos.org/manual/nix/unstable/release-notes/rl-2.20)でNix32という名前に改められた。理由としては[通常の意味のBase32表現](https://ja.wikipedia.org/wiki/%E4%B8%89%E5%8D%81%E4%BA%8C%E9%80%B2%E6%B3%95#Base32)とは処理が異なり紛らわしいためのようだ
  * 先頭160bitをNix32表現にするというのは、Nix32表現に直した文字列の先頭20文字を切り取ることと同義である。
* fingerprintは、`<type>:sha256:<inner-digest>:/nix/store:<name>`の形式
  * `<type>`というのは以下のいずれか
    * `text:<input store path>:<input store path>:...`：derivation。`<input store path>`には、（存在すれば）derivationが参照する他のファイルのパスを指定する
    * `source:<input store path>:<input store path>:...`：外部から持ってきたファイルをNAR形式でアーカイブ化したもの
    * `output:<id>`：derivationからビルドされたもの、もしくはビルド予定のものを表す。`<id>`には通常`out`が入るが、ビルド出力結果を複数分けているようなパッケージでは`bin`や`lib`、`dev`などが指定されうる。
  * `<inner-digest>`は、`inner-fingerprint`をSHA256でハッシュ化し、Base16表現にしたもの。
    * `inner-fingerprint`の計算方法は、上述の`type`によって異なるが、これは後々実際に計算してみつつ解説する

いろいろと書いてあるが、結局`/nix/store`下におかれるパスの種類は実質`fingerprint`の種類であり、すなわち3種類である。
* text：derivationを表す
* source：ビルドに必要なファイル、ソースコードを表す
* output：ビルド生成物を置くディレクトリを表す

それでは実際にハンズオンとして、fingerprintの計算を手動でやってみる。

## （前準備）derivationの準備

今回手で計算するもととなるderivationを、超雑に書く。
* [Nix PillsのChapter 7](https://nixos.org/guides/nix-pills/working-derivation#id1388)の内容をもとに。汎用性とかは意識せず、`x86_64-linux`前提で書く
* ただNix Pillsそのままだと面白くないので、flakeを使って書いてみる。


まずいくつかのファイルを作成する
* `flake.nix`：flakeファイル
* `default.nix`：derivationを記述したファイル
* `mubuilder.nix`：derivationをもとに成果物をビルドするためのシェルスクリプト
* `hello.c`：ビルドする適当なC言語ソースコード

```sh
nix flake init
touch default.nix
touch mybuilder.sh
touch hello.c
```

`hello.c`の中身
```c
#include <stdio.h>

int main(void) {
  printf("Hello, World\n");
  return 0;
}
```

`mybuilder.sh`の中身。
* ただgccでビルドして、成果物を`$out`ディレクトリに放り込むだけ
* `$out`という環境変数は前述のoutputのことで、`nix build`時に勝手に設定されている。
* `$coreutils`と`$gcc`は、後述の`default.nix`で設定しているもの
  * `coreutils`は`mkdir`のために必要

```sh
export PATH="$coreutils/bin:$gcc/bin"
mkdir $out
gcc $src -o $out/hello
```

`default.nix`の中身。
* 引数に`bash`と`coreutils`が設定されているが、これは`flake.nix`からこのファイルを読ませるときに指定する
* `nix build`コマンドが実行されると、`(bashのstore path)/bin/bash (mybuilder.shのstore path)`が実行される
  * `./mybuilder.sh`は`nix build`コマンド実行時に、勝手に現在のパス上にあるファイルが読み込まれ、sourceとして`/nix/store`上にコピーされる
* `coreutils = coreutils`と`gcc = gcc`は、`mybuilder.sh`で`PATH`を設定するために必要
```nix
{ bash, coreutils, gcc }:
  derivation {
    name = "sample";
    builder = "${bash}/bin/bash";
    args = [ ./mybuilder.sh ];
    system = "x86_64-linux";
    src = ./hello.c;
    coreutils = coreutils;
    gcc = gcc;
  }
```

`flake.nix`の中身。
* 上述の`default.nix`を読ませる
  * `bash`と`coreutils`を`nixpkgs`から読み込ませる
* `packages.<system>.sample = { ... }`と書いているので、`nix build .#sample` でビルドが可能
```nix
{
  description = "A very basic flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-23.11";
  };

  outputs = { self, nixpkgs }: {
    packages.x86_64-linux.sample = import ./default.nix {
      bash = nixpkgs.legacyPackages.x86_64-linux.bash;
      gcc = nixpkgs.legacyPackages.x86_64-linux.gcc;
      coreutils = nixpkgs.legacyPackages.x86_64-linux.coreutils;
    };
  };
}
```

これで`nix build`コマンドを実行すると、`results`ディレクトリが生成されていることがわかる
* `/nix/store/<digest>-sample`へのシンボリックリンクになっている

```console
[bombrary@nixos:~/tmp/drv-test]$ nix build .#sample

[bombrary@nixos:~/tmp/drv-test]$ ls
default.nix  flake.lock  flake.nix  hello.c  mybuilder.sh  result

[bombrary@nixos:~/tmp/drv-test]$ realpath result
/nix/store/xmy0zsk9y7w5ccfvm694igb7dz9357n1-sample

[bombrary@nixos:~/tmp/drv-test]$ ./result/hello
Hello, World
```

## drvファイルを見る

`nix derivation show (ビルド生成物へのstore path)`で、`nix/store`に取り込まれたderivationの情報が確認できる。
```console
[bombrary@nixos:~/tmp/drv-test]$ nix derivation show `realpath result`
{
  "/nix/store/0hyv285szbkl1gxiyjblv07wj1s6gdqb-sample.drv": {
    "args": [
      "/nix/store/lxgb38my517cf4605zm4pp39lpszvzjh-mybuilder.sh"
    ],
    "builder": "/nix/store/r9h133c9m8f6jnlsqzwf89zg9w0w78s8-bash-5.2-p15/bin/bash",
    "env": {
      "builder": "/nix/store/r9h133c9m8f6jnlsqzwf89zg9w0w78s8-bash-5.2-p15/bin/bash",
      "coreutils": "/nix/store/rk067yylvhyb7a360n8k1ps4lb4xsbl3-coreutils-9.3",
      "gcc": "/nix/store/ihhhd1r1a2wb4ndm24rnm83rfnjw5n0z-gcc-wrapper-12.3.0",
      "name": "sample",
      "out": "/nix/store/xmy0zsk9y7w5ccfvm694igb7dz9357n1-sample",
      "src": "/nix/store/cap4mlkfwzh7l2f2x5zy5lvgy8xb5ywd-hello.c",
      "system": "x86_64-linux"
    },
    "inputDrvs": {
      "/nix/store/hpkl2vyxiwf7rwvjh9lpij7swp7igilx-bash-5.2-p15.drv": {
        "dynamicOutputs": {},
        "outputs": [
          "out"
        ]
      },
      "/nix/store/svc566dmzacxdvdy6d1w4ahhcm9qc8zf-gcc-wrapper-12.3.0.drv": {
        "dynamicOutputs": {},
        "outputs": [
          "out"
        ]
      },
      "/nix/store/zf1sc2qhyv3dn4xmkkxb9n23v422bb15-coreutils-9.3.drv": {
        "dynamicOutputs": {},
        "outputs": [
          "out"
        ]
      }
    },
    "inputSrcs": [
      "/nix/store/cap4mlkfwzh7l2f2x5zy5lvgy8xb5ywd-hello.c",
      "/nix/store/lxgb38my517cf4605zm4pp39lpszvzjh-mybuilder.sh"
    ],
    "name": "sample",
    "outputs": {
      "out": {
        "path": "/nix/store/xmy0zsk9y7w5ccfvm694igb7dz9357n1-sample"
      }
    },
    "system": "x86_64-linux"
  }
}
```

実際には、これは `/nix/store/6jxxivs39bmh0ad84lad2xlb0z9ajq64-sample.drv`をパースしてJSONで見やすく表示している。生のdrvファイルは次のようになっている。これは[ATerm file format](https://nixos.org/manual/nix/unstable/protocols/derivation-aterm)という形式らしい。
```console
[bombrary@nixos:~/tmp/drv-test]$ nix derivation show `readlink result` | jq -r 'keys | .[]'
/nix/store/0hyv285szbkl1gxiyjblv07wj1s6gdqb-sample.drv

[bombrary@nixos:~/tmp/drv-test]$ cat -pp /nix/store/0hyv285szbkl1gxiyjblv07wj1s6gdqb-sample.drv
Derive([("out","/nix/store/xmy0zsk9y7w5ccfvm694igb7dz9357n1-sample","","")],[("/nix/store/hpkl2vyxiwf7rwvjh9lpij7swp7igilx-bash-5.2-p15.drv",["out"]),("/nix/store/svc566dmzacxdvdy6d1w4ahhcm9qc8zf-gcc-wrapper-12.3.0.drv",["out"]),("/nix/store/zf1sc2qhyv3dn4xmkkxb9n23v422bb15-coreutils-9.3.drv",["out"])],["/nix/store/cap4mlkfwzh7l2f2x5zy5lvgy8xb5ywd-hello.c","/nix/store/lxgb38my517cf4605zm4pp39lpszvzjh-mybuilder.sh"],"x86_64-linux","/nix/store/r9h133c9m8f6jnlsqzwf89zg9w0w78s8-bash-5.2-p15/bin/bash",["/nix/store/lxgb38my517cf4605zm4pp39lpszvzjh-mybuilder.sh"],[("builder","/nix/store/r9h133c9m8f6jnlsqzwf89zg9w0w78s8-bash-5.2-p15/bin/bash"),("coreutils","/nix/store/rk067yylvhyb7a360n8k1ps4lb4xsbl3-coreutils-9.3"),("gcc","/nix/store/ihhhd1r1a2wb4ndm24rnm83rfnjw5n0z-gcc-wrapper-12.3.0"),("name","sample"),("out","/nix/store/xmy0zsk9y7w5ccfvm694igb7dz9357n1-sample"),("src","/nix/store/cap4mlkfwzh7l2f2x5zy5lvgy8xb5ywd-hello.c"),("system","x86_64-linux")])
```

さて、上記のdrvファイルを見ると、多くのstore pathが確認できる。
* drvファイル
  * `/nix/store/0hyv285szbkl1gxiyjblv07wj1s6gdqb-sample.drv`
* source
  * `/nix/store/cap4mlkfwzh7l2f2x5zy5lvgy8xb5ywd-hello.c`
  * `/nix/store/lxgb38my517cf4605zm4pp39lpszvzjh-mybuilder.sh`
* output
  * `/nix/store/xmy0zsk9y7w5ccfvm694igb7dz9357n1-sample`
* その他依存するパッケージのdrvファイル
  * `/nix/store/hpkl2vyxiwf7rwvjh9lpij7swp7igilx-bash-5.2-p15.drv`
  * `/nix/store/svc566dmzacxdvdy6d1w4ahhcm9qc8zf-gcc-wrapper-12.3.0.drv`
  * `/nix/store/zf1sc2qhyv3dn4xmkkxb9n23v422bb15-coreutils-9.3.drv`

前者3種類について、そのdigestの計算をするのが、本記事の目的である。

## drvファイルの計算

drvのstore pathは以下のものであった。
* `/nix/store/0hyv285szbkl1gxiyjblv07wj1s6gdqb-sample.drv`

drvファイルのdigestが本当に`0hyv285szbkl1gxiyjblv07wj1s6gdqb`になるのか確認してみよう。

digestとは、fingerprintをNix32でハッシュ化したものである。fingerprintとは、drvファイルの場合以下の形式のものである。
```
text:(input store path):(input store path):...:(input store path):sha256:<inner-digest>:/nix/store:<name>
```

innter-digestとは、drvファイルをSHA256でハッシュ化し、Base16表現にしたものである。Base16というのは要するにHex（16進数）表記のこと。これは`sha256sum`コマンドで計算できる。早速drvファイルのハッシュを出してみよう。
```console
[bombrary@nixos:~/tmp/drv-test]$ cat /nix/store/0hyv285szbkl1gxiyjblv07wj1s6gdqb-sample.drv | sha256sum
2d2850f3d91d46693b6f6c06c910f1de8fac2f34746379c51062fa7f6367361e  -

# （補足）nix-hashコマンドを使う場合
[bombrary@nixos:~/tmp/drv-test]$ nix-hash --type sha256 /nix/store/0hyv285szbkl1gxiyjblv07wj1s6gdqb-sample.drv --flat
2d2850f3d91d46693b6f6c06c910f1de8fac2f34746379c51062fa7f6367361e
```

`(input store path)`というのは、derivationに依存するファイルや別derivationを差す。これは`inputDrvs`と`inputSrcs`から取り出せる。
```console
[bombrary@nixos:~/tmp/drv-test]$ nix derivation show ./result | jq -r 'to_entries[].value | ((.inputDrvs | keys) + .inputSrcs) | .[]'
/nix/store/hpkl2vyxiwf7rwvjh9lpij7swp7igilx-bash-5.2-p15.drv
/nix/store/svc566dmzacxdvdy6d1w4ahhcm9qc8zf-gcc-wrapper-12.3.0.drv
/nix/store/zf1sc2qhyv3dn4xmkkxb9n23v422bb15-coreutils-9.3.drv
/nix/store/cap4mlkfwzh7l2f2x5zy5lvgy8xb5ywd-hello.c
/nix/store/lxgb38my517cf4605zm4pp39lpszvzjh-mybuilder.sh
```

で、これらをどんな順番でfingerprintで取得すればよいのか。上記の順番でfingerprintに指定しても正しいhashが計算できない。試行錯誤した感じだと、`nix-store -q --references`で出力される順番で設定すると正しい結果が出せるようだ。
```console
[bombrary@nixos:~/tmp/drv-test]$ nix-store -q --references /nix/store/0hyv285szbkl1gxiyjblv07wj1s6gdqb-sample.drv
/nix/store/cap4mlkfwzh7l2f2x5zy5lvgy8xb5ywd-hello.c
/nix/store/hpkl2vyxiwf7rwvjh9lpij7swp7igilx-bash-5.2-p15.drv
/nix/store/lxgb38my517cf4605zm4pp39lpszvzjh-mybuilder.sh
/nix/store/zf1sc2qhyv3dn4xmkkxb9n23v422bb15-coreutils-9.3.drv
/nix/store/svc566dmzacxdvdy6d1w4ahhcm9qc8zf-gcc-wrapper-12.3.0.drv
```

上記の結果からなんとなく辞書順な感じがする。それを信じて、`jq`でソートとjoinを使って、fingerprintに入れる文字列を作る。
```console
[bombrary@nixos:~/tmp/drv-test]$ nix derivation show ./result | jq -r 'to_entries[].value | ( (.inputDrvs | keys) + .inputSrcs) | sort | join(":")'
/nix/store/cap4mlkfwzh7l2f2x5zy5lvgy8xb5ywd-hello.c:/nix/store/hpkl2vyxiwf7rwvjh9lpij7swp7igilx-bash-5.2-p15.drv:/nix/store/lxgb38my517cf4605zm4pp39lpszvzjh-mybuilder.sh:/nix/store/svc566dmzacxdvdy6d1w4ahhcm9qc8zf-gcc-wrapper-12.3.0.drv:/nix/store/zf1sc2qhyv3dn4xmkkxb9n23v422bb15-coreutils-9.3.drv
```

これを`text:`の直後に挿入して、fingerprintの完成。
```console
[bombrary@nixos:~/tmp/drv-test]$ echo '/nix/store/cap4mlkfwzh7l2f2x5zy5lvgy8xb5ywd-hello.c:/nix/store/hpkl2vyxiwf7rwvjh9lpij7swp7igilx-bash-5.2-p15.drv:/nix/store/lxgb38my517cf4605zm4pp39lpszvzjh-mybuilder.sh:/nix/store/svc566dmzacxdvdy6d1w4ahhcm9qc8zf-gcc-wrapper-12.3.0.drv:/nix/store/zf1sc2qhyv3dn4xmkkxb9n23v422bb15-coreutils-9.3.drv' | xargs -I{} echo 'text:{}:sha256:2d2850f3d91d46693b6f6c06c910f1de8fac2f34746379c51062fa7f6367361e:/nix/store:sample.drv'

text:/nix/store/cap4mlkfwzh7l2f2x5zy5lvgy8xb5ywd-hello.c:/nix/store/hpkl2vyxiwf7rwvjh9lpij7swp7igilx-bash-5.2-p15.drv:/nix/store/lxgb38my517cf4605zm4pp39lpszvzjh-mybuilder.sh:/nix/store/svc566dmzacxdvdy6d1w4ahhcm9qc8zf-gcc-wrapper-12.3.0.drv:/nix/store/zf1sc2qhyv3dn4xmkkxb9n23v422bb15-coreutils-9.3.drv:sha256:2d2850f3d91d46693b6f6c06c910f1de8fac2f34746379c51062fa7f6367361e:/nix/store:sample.drv
```

これを適当なファイルに書き出して、`nix-hash`ハッシュ化することで、期待通りのdigestが計算できた。
* `--flat`は、NAR形式に変換せずにハッシュ化するオプション
* `--base32`でNix32形式で出力する
* `--truncate`で、ハッシュの先頭160ビットを出力

```console
[bombrary@nixos:~/tmp/drv-test]$ echo -n "text:/nix/store/cap4mlkfwzh7l2f2x5zy5lvgy8xb5ywd-hello.c:/nix/store/hpkl2vyxiwf7rwvjh9lpij7swp7igilx-bash-5.2-p15.drv:/nix/store/lxgb38my517cf4605zm4pp39lpszvzjh-mybuilder.sh:/nix/store/svc566dmzacxdvdy6d1w4ahhcm9qc8zf-gcc-wrapper-12.3.0.drv:/nix/store/zf1sc2qhyv3dn4xmkkxb9n23v422bb15-coreutils-9.3.drv:sha256:2d2850f3d91d46693b6f6c06c910f1de8fac2f34746379c51062fa7f6367361e:/nix/store:sample.drv" > sample.drv.str

[bombrary@nixos:~/tmp/drv-test]$ nix-hash --type sha256 --truncate --base32 --flat sample.drv.str
0hyv285szbkl1gxiyjblv07wj1s6gdqb
```

### 補足 inputのstore pathが辞書順であることの根拠をソースコードから探す

ドキュメントに記載がないので[NixOS/nix](https://github.com/NixOS/nix)を読む。

`libstore/derivations.cc`の`writeDerivation`関数で、`reference`に`inputSrcs`と`inputDrvs`を入れている箇所が見つかる。

```cpp
StorePath writeDerivation(Store & store,
    const Derivation & drv, RepairFlag repair, bool readOnly)
{
    auto references = drv.inputSrcs;
    for (auto & i : drv.inputDrvs.map)
        references.insert(i.first);
    // 略
}
```

`libstore/path.hh`にStorePathSetというのが用意されている。
```cpp
typedef std::set<StorePath> StorePathSet;
```

`std::set`は2分木で実装されているため、setの要素は比較可能である必要がある。そして`StorePath`は以下のように比較演算子が定義されており、結局のところ文字列`baseName`の文字列比較になっている。
```cpp
class StorePath
{
    std::string baseName;

    // 略

    bool operator < (const StorePath & other) const
    {
        return baseName < other.baseName;
    }

    bool operator == (const StorePath & other) const
    {
        return baseName == other.baseName;
    }

    bool operator != (const StorePath & other) const
    {
        return baseName != other.baseName;
    }

    // 略
}
```

C++の文字列比較は[std::char_traits::compare](https://cpprefjp.github.io/reference/string/char_traits/compare.html)となるので、辞書式順序による比較である

### nix-hashのflatオプションって何？

`--flat`オプションをつけるとつけないとで異なる結果になる。
```console
[bombrary@nixos:~/tmp/drv-test]$ nix-hash --type sha256 sample.drv.str
d12ff17b0cb43be5c8272bf9b8ceecbd3591ae9ed946d7e13bc7f5a5ef9d3a25

[bombrary@nixos:~/tmp/drv-test]$ nix-hash --type sha256 --flat sample.drv.str
0844c1053ac75a2e3423c4b640e7faba20b13d0403f3a671aa3bda63a3d77509
```

`--flat`をつけないと、NAR（Nix Archive）形式に変換してからそれをハッシュ化することになる。NAR形式というのは[Nix Pills](https://nixos.org/guides/nix-pills/automatic-runtime-dependencies.html#id1400)にも解説があるが、要するにtar形式の非決定的な特徴を取り除いたバージョンである。

NAR形式は、`nix-store --dump`コマンドまたは`nix nar dump-path`コマンドを使うことで実際に見ることができる。試しに実行して見てみよう。なお、NAR形式はバイナリなので、`strings`コマンドを噛ませて閲覧する（`strings`コマンドは`binutils`に含まれている）。
```console
[bombrary@nixos:~/tmp/drv-test]$ nix nar dump-path sample.drv.str | nix shell nixpkgs#binutils --command strings
nix-archive-1
type
regular
contents
text:/nix/store/cap4mlkfwzh7l2f2x5zy5lvgy8xb5ywd-hello.c:/nix/store/hpkl2vyxiwf7rwvjh9lpij7swp7igilx-bash-5.2-p15.drv:/nix/store/lxgb38my517cf4605zm4pp39lpszvzjh-mybuilder.sh:/nix/store/svc566dmzacxdvdy6d1w4ahhcm9qc8zf-gcc-wrapper-12.3.0.drv:/nix/store/zf1sc2qhyv3dn4xmkkxb9n23v422bb15-coreutils-9.3.drv:sha256:2d2850f3d91d46693b6f6c06c910f1de8fac2f34746379c51062fa7f6367361e:/nix/store:sample.drv
```

`--flat`無しの`nix-hash`の結果と、NAR形式にしてsha256sumをかけた結果は一致する。
```console
[bombrary@nixos:~/tmp/drv-test]$ nix nar dump-path sample.drv.str | sha256sum | cut -d ' ' -f 1
d12ff17b0cb43be5c8272bf9b8ceecbd3591ae9ed946d7e13bc7f5a5ef9d3a25

[bombrary@nixos:~/tmp/drv-test]$ nix-hash --type sha256 --flat sample.drv.str
0844c1053ac75a2e3423c4b640e7faba20b13d0403f3a671aa3bda63a3d77509
```

`--flat`有りの`nix-hash`の結果と、NARにしない素のファイルにsha256sumをかけた結果は一致する。
```console
[bombrary@nixos:~/tmp/drv-test]$ nix nar dump-path sample.drv.str | sha256sum | cut -d ' ' -f 1
d12ff17b0cb43be5c8272bf9b8ceecbd3591ae9ed946d7e13bc7f5a5ef9d3a25

[bombrary@nixos:~/tmp/drv-test]$ cat sample.drv.str | sha256sum | cut -d ' ' -f 1
0844c1053ac75a2e3423c4b640e7faba20b13d0403f3a671aa3bda63a3d77509
```

### Nix32表現の計算

[v2.20.5時点でのhash.cc](https://github.com/NixOS/nix/blob/master/src/libutil/hash.cc#L83-L107)を見てみよう。

以下の並びのビット列があるとする（見やすさのため8bitごとに縦棒で区切ってある）。
```
... | b15 b14 b13 b12 b11 b10 b9 b8 | b7 b6 b5 b4 b3 b2 b1 b0
```

Nix32表現では、以下のような順で5bitずつ取り出していく。
```
5bit：b4 b3 b2 b1 b0
5bit：b9 b8 | b7 b6 b5
5bit：b14 b13 b12 b11 b10
5bit：b19 b18 b17 b16 | b15
...
```

その5bitに文字を対応させる。具体的には、5bit値`idx`に対して、以下の文字列の`chars[idx]`を対応させる。
```
chars = "0123456789abcdfghijklmnpqrsvwxyz"
```

上記の処理を、上160bit目から上0bit目まで行って、文字列を順に連結したら完成である。これをpythonコードで実現すると次のようになる。
```python
import sys

chars = "0123456789abcdfghijklmnpqrsvwxyz"
hashSize = 32 # 5 * 32 = 160bit

def printHash32(hash: bytes):
    s = ""
    for n in range(hashSize - 1, -1, -1):
        # 5bit区切りで見たい
        # 先頭から数えて5 * n bit目の位置を見る
        b = n * 5

        # ところがバイトは8bit単位であるため、2バイト分にまたがって見たい5bitが存在する場合がある
        #   stuv wxyz STUV WXYZ
        i = b // 8
        j = b % 8

        # jビット右シフトすることで
        # 先頭(8-j)ビットだけ残す
        #   stuv wxyz >> 6 = 0000 00st
        a = (hash[i] >> j) & 0xff

        # (8-j)ビット左シフトすることで
        # 後方jビットだけ残す
        #   STUV WXYZ << 2 = UVWX YZ00
        b = (0 if i >= hashSize - 1 else hash[i + 1] << (8 - j)) & 0xff

        # aとbをマージする
        #    UVWX YZst
        c = a | b

        # これの先頭5bitだけとりだす
        #     000X YZst
        idx = c & 0x1f
        print(f'hash[{i:02d}] >> {j} = {a:08b}')
        print(f'hash[{i + 1:02d}] << {8-j} = {b:08b}')
        print('---------------------------------')
        print(f'                {c:08b} -> {idx:05b} -> {chars[idx]}')
        print()
        s = s + chars[idx]

    print_bytes(tmp)

    return s

print(printHash32(sys.stdin.buffer.read()))
```


## sourceの計算

今回作成したderivationでsourceは以下の2つである。
* `/nix/store/cap4mlkfwzh7l2f2x5zy5lvgy8xb5ywd-hello.c`
* `/nix/store/lxgb38my517cf4605zm4pp39lpszvzjh-mybuilder.sh`

このdigestである`cap4mlkfwzh7l2f2x5zy5lvgy8xb5ywd`と`lxgb38my517cf4605zm4pp39lpszvzjh`を計算したい。

いずれも依存するstore pathは存在しないはずであるから、fingerprintは以下の形式になるはずである。
```
source:sha256:<inner-digest>:/nix/store:hello.c
source:sha256:<inner-digest>:/nix/store:mybuilder.sh
```

innter-digestはsourceの場合、NAR化してそれをsha256ハッシュ化すればよい。前項で述べたが、`nix-hash`に`--flat`オプションを付けずに実行すれば、これを達成できる。
```console
[bombrary@nixos:~/tmp/drv-test]$ nix-hash --type sha256 hello.c
1b6fc2a02e4591a8010b53edad47273129b020a50e88abdf1d877ff832efba93

[bombrary@nixos:~/tmp/drv-test]$ nix-hash --type sha256 mybuilder.sh
c0e9a62e443a22572043c7f18e0e0db9946f0f33415f57a9290c3b7a35357726
```

あとは`source:sha256:<inner-digest>:/nix/store:<name>`のフォーマットで書き出して、`nix-hash`コマンドでNix32表現で出力することで、sourceのdigestが計算できた。
```console
[bombrary@nixos:~/tmp/drv-test]$ echo -n 'source:sha256:1b6fc2a02e4591a8010b53edad47273129b020a50e88abdf1d877ff832efba93:/nix/store:hello.c' > hello.c.str

[bombrary@nixos:~/tmp/drv-test]$ echo -n 'source:sha256:c0e9a62e443a22572043c7f18e0e0db9946f0f33415f57a9290c3b7a35357726:/nix/store:mybuilder.sh' > mybuilder.sh.str

[bombrary@nixos:~/tmp/drv-test]$ nix-hash --type sha256 --base32 --truncate --flat hello.c.str
cap4mlkfwzh7l2f2x5zy5lvgy8xb5ywd

[bombrary@nixos:~/tmp/drv-test]$ nix-hash --type sha256 --base32 --truncate --flat mybuilder.sh.str
lxgb38my517cf4605zm4pp39lpszvzjh
```

## outputの計算

### シンプルなケース

上記の`hello.c`をコンパイルするケースは想像以上に計算が大変なので、まずは別のシンプルなケースで計算してみよう。

まずは以下のように、`flake.nix`に`foo-input`と`foo`を追加する。`foo`というderivationの依存関係として`foo-input`がある、という想定。
```nix
{
  description = "A very basic flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-23.11";
  };

  outputs = { self, nixpkgs }:
  let
    foo = derivation {
      system = "x86_64-linux";
      name = "foo";
      builder = ./mybuilder.sh;
      bar = bar;
    };
    bar = derivation {
      system = "x86_64-linux";
      name = "bar";
      builder = ./mybuilder.sh;
      baz = baz;
    };
    baz = derivation {
      system = "x86_64-linux";
      name = "baz";
      builder = ./mybuilder.sh;
    };
  in
  {
    packages.x86_64-linux.sample = import ./default.nix {
      bash = nixpkgs.legacyPackages.x86_64-linux.bash;
      gcc = nixpkgs.legacyPackages.x86_64-linux.gcc;
      coreutils = nixpkgs.legacyPackages.x86_64-linux.coreutils;
    };
    packages.x86_64-linux.foo = foo;
  };
}
```

この状態でdry-runすることで、ビルドせずにderivationだけ作る。
```console
[bombrary@nixos:~/tmp/drv-test]$ nix build --dry-run .#foo
these 3 derivations will be built:
  /nix/store/f7ixslcwscmg9npjv834jcwd78m878q5-baz.drv
  /nix/store/azh4hppmaxva1xgckz80khsnvp22a7x0-bar.drv
  /nix/store/6xvabp58vn5sfkshin9xj97bbaw2xblh-foo.drv
```

これのoutputのパスを確認する。
```
[bombrary@nixos:~/tmp/drv-test]$ nix derivation show /nix/store/6xvabp58vn5sfkshin9xj97bbaw2xblh-foo.drv^* | jq 'to_entries[].value.outputs'
{
  "out": {
    "path": "/nix/store/xpp1hb67nl8f6mmxg54sidvc96xkhh43-foo"
  }
}
```

実際にdigestが `xpp1hb67nl8f6mmxg54sidvc96xkhh43` となるのかを確認してみよう。

まずfingerprintは以下の形式である。
```
output:<id>:sha256:<inner-digest>:/nix/store:<name>
```

今回のケースだと`<id>`は`out`、`<name>`は`foo`である。ここまでは単純で良いが、`<inner-digest>`の計算がやや面倒である。これはdrvファイルについて、以下の状態になっているものをSHA256ハッシュ化したものである。
* `output`のパスが含まれていない：outputのパスを計算しようとしてるのに最初から入っていたら自己再帰的になってしまい計算できないため、当たり前といえば当たり前
* `inputDrvs`の要素の各drvファイルを以下の状態にし、SHA256ハッシュ化したもので置き換えられている
  * `output`のパスは含まれている
  * `inputDrvs`について、上記と同じようにSHA256化された状態になっている：つまり再帰的な計算が必要

それでは`foo.drv`を目的の状態になるように整形していく。まずファイルをコピーしてくる。
```console
[bombrary@nixos:~/tmp/drv-test]$ cp -f /nix/store/6xvabp58vn5sfkshin9xj97bbaw2xblh-foo.drv foo.drv

[bombrary@nixos:~/tmp/drv-test]$ cat foo.drv
Derive([("out","/nix/store/xpp1hb67nl8f6mmxg54sidvc96xkhh43-foo","","")],[("/nix/store/azh4hppmaxva1xgckz80khsnvp22a7x0-bar.drv",["out"])],["/nix/store/lxgb38my517cf4605zm4pp39lpszvzjh-mybuilder.sh"],"x86_64-linux","/nix/store/lxgb38my517cf4605zm4pp39lpszvzjh-mybuilder.sh",[],[("bar","/nix/store/22ag5m2f89jswgcpg9rxans5msdvjbfj-bar"),("builder","/nix/store/lxgb38my517cf4605zm4pp39lpszvzjh-mybuilder.sh"),("name","foo"),("out","/nix/store/xpp1hb67nl8f6mmxg54sidvc96xkhh43-foo"),("system","x86_64-linux")])
```

まず`output`のパスを消す。

```console
[bombrary@nixos:~/tmp/drv-test]$ sed -i "s,/nix/store/xpp1hb67nl8f6mmxg54sidvc96xkhh43-foo,,g" foo.drv

[bombrary@nixos:~/tmp/drv-test]$ cat foo.drv
Derive([("out","","","")],[("/nix/store/azh4hppmaxva1xgckz80khsnvp22a7x0-bar.drv",["out"])],["/nix/store/lxgb38my517cf4605zm4pp39lpszvzjh-mybuilder.sh"],"x86_64-linux","/nix/store/lxgb38my517cf4605zm4pp39lpszvzjh-mybuilder.sh",[],[("bar","/nix/store/22ag5m2f89jswgcpg9rxans5msdvjbfj-bar"),("builder","/nix/store/lxgb38my517cf4605zm4pp39lpszvzjh-mybuilder.sh"),("name","foo"),("out",""),("system","x86_64-linux")])
```

`foo`の依存関係に`bar.drv`があるのが分かる。これをハッシュ化したいが、`bar.drv`の中にさらに`baz.drv`が依存関係にあるので、それをまずハッシュ化する。
```console
[bombrary@nixos:~/tmp/drv-test]$ nix derivation show /nix/store/azh4hppmaxva1xgckz80khsnvp22a7x0-bar.drv^* | jq -r 'to_entries[].value.inputDrvs | to_entries[].key'
/nix/store/f7ixslcwscmg9npjv834jcwd78m878q5-baz.drv
```

`baz.drv`が依存するdrvは特にないので、そのままハッシュ化する。
```
[bombrary@nixos:~/tmp/drv-test]$ cat /nix/store/f7ixslcwscmg9npjv834jcwd78m878q5-baz.drv | sha256sum | cut -d ' ' -f 1
d7e138110ee3a03c9f28cf7d124de6db8adea690ebcb2fcd901da7cccaed645c
```

これをもとに`bar.drv`の`baz.drv`の依存関係の部分をそのハッシュに書き換え、ハッシュ化する。
```console
[bombrary@nixos:~/tmp/drv-test]$ cat /nix/store/azh4hppmaxva1xgckz80khsnvp22a7x0-bar.drv | sed 's,/nix/store/f7ixslcwscmg9npjv834jcwd78m878q5-baz.drv,d7e138110ee3a03c9f28cf7d124de6db8adea690ebcb2fcd901da7cccaed645c,g' | sha256sum | cut -d ' ' -f 1
679584e662eaccaf5810935a21dbed2155f627d5369ba9a4ab8485b7bc8f9193
```

これをもとに`foo.drv`の`bar.drv`の依存関係の部分をそのハッシュに書き換え、fingerprintの完成である。
```console
[bombrary@nixos:~/tmp/drv-test]$ sed -i 's,/nix/store/azh4hppmaxva1xgckz80khsnvp22a7x0-bar.drv,679584e662eaccaf5810935a21dbed2155f627d5369ba9a4ab8485b7bc8f9193,g' foo.drv

[bombrary@nixos:~/tmp/drv-test]$ cat foo.drv
Derive([("out","","","")],[("679584e662eaccaf5810935a21dbed2155f627d5369ba9a4ab8485b7bc8f9193",["out"])],["/nix/store/lxgb38my517cf4605zm4pp39lpszvzjh-mybuilder.sh"],"x86_64-linux","/nix/store/lxgb38my517cf4605zm4pp39lpszvzjh-mybuilder.sh",[],[("bar","/nix/store/22ag5m2f89jswgcpg9rxans5msdvjbfj-bar"),("builder","/nix/store/lxgb38my517cf4605zm4pp39lpszvzjh-mybuilder.sh"),("name","foo"),("out",""),("system","x86_64-linux")])

[bombrary@nixos:~/tmp/drv-test]$ cat foo.drv | sha256sum | cut -d ' ' -f 1
5269760e7ff34e22f60238b25a8a0c535d4dd03af483f97acff61dc515a01d8e
```

これを指定の形式でSHA256ハッシュ化し、Nix32表現にすれば、digestの完成で、ちゃんと`xpp1hb67nl8f6mmxg54sidvc96xkhh43`となっていることが確認できた。
```console
[bombrary@nixos:~/tmp/drv-test]$ echo -n 'output:out:sha256:5269760e7ff34e22f60238b25a8a0c535d4dd03af483f97acff61dc515a01d8e:/nix/store:foo' > foo.str

[bombrary@nixos:~/tmp/drv-test]$ nix-hash --type sha256 --base32 --truncate --flat foo.str
xpp1hb67nl8f6mmxg54sidvc96xkhh43
```

### 実際のケース

outputは以下のファイルであった。
* `/nix/store/ahrkz8b85n3qcxdsnhr0m6jhg4kw96c3-sample`

このdigestが`ahrkz8b85n3qcxdsnhr0m6jhg4kw96c3`になるのか確認してみよう。

fingerprintの形式は、`output:<id>:sha256:<inner-digest>:/nix/store:<name>`になる。`<id>`はデフォルトでは`out`、`<name>`は`sample`のはずだから、`output:out:sha256:<inner-digest>:/nix/store:sample`の形式になるはずである。
あとはinner-digestを計算すればよい。これはdrvファイル
* `/nix/store/rg9vdgc8wf0l1aa2x417fdfl4xv8n60f-sample.drv`

で、outputのパスが空の状態だったものをsha256ハッシュ化することで得られる。

```console
[bombrary@nixos:~/tmp/drv-test]$ sed 's,/nix/store/ahrkz8b85n3qcxdsnhr0m6jhg4kw96c3-sample,,g' /nix/store/rg9vdgc8wf0l1aa2x417fdfl4xv8n60f-sample.drv | sha256sum
5ac78f90e024fc294832d4c92fcbba1382528573715ee5b17077fc195ca80257  -
```

あとはこれからfingerprintを作成し、sha256ハッシュ化してNix32表現にすれば完成。
```console
[bombrary@nixos:~/tmp/drv-test]$ echo -n "output:out:sha256:5ac78f90e024fc294832d4c92fcbba1382528573715ee5b17077fc195ca80257:/nix/store:sample" > sample-out.str

[bombrary@nixos:~/tmp/drv-test]$ nix-hash --type sha256 --base32 --flat --truncate sample-out.str
msiwqizkl7lisy4scjgf6n9zwp9ih0n9
```

### 補足

outputのhashの計算方法については以下が参考になる。
* `libstore/derivation.cc`の`DrvHash hashDerivationModulo()`
* `libstore/derivation.cc`の`DrvHash pathDerivationModulo()`
* `libstore/derivation.cc`の`unparse()`関数
