---
title: "Nixのstore path計算方法メモ"
date: 2024-04-20T09:00:00+09:00
tags: ["hash", "sha256", "derivation"]
toc: true
categories: ["Nix"]
---

Nixでは、パッケージの再現性を担保するために、`/nix/store/`下にハッシュ値を含んだ名前であらゆるファイルを保管する。そのハッシュ値がどのような情報から計算されるものなのかを知っておくことは、なぜNixが再現性を確保できるのかを考える上で重要である。

そこで、この記事では、Nixのstore path、つまりその中に含まれるハッシュの計算方法について解説し、実際にステップバイステップで計算してみる。

## 参考記事

* [How Nix Isntantiation Works (Web Archive)](https://web.archive.org/web/20221001050043/https://comono.id/posts/2020-03-20-how-nix-instantiation-works/)
* [Nix manual(unstable)Store Pathの仕様](https://nixos.org/manual/nix/unstable/protocols/store-path)
* [Nix PillsのChapter 18](https://nixos.org/guides/nix-pills/nix-store-paths)

なお、本記事では `nix derivation show` コマンドの結果からいろいろと情報を取り出すために [jq](https://jqlang.github.io/jq/) を用いる。

## store pathの種類

ほとんど[Store Path](https://nixos.org/manual/nix/unstable/protocols/store-path)の書き起こしみたいになってしまうが書いておく。

まずstore pathは、`/nix/store/<digest>-<name>`の形式を持っている。
* `<digest>`というのは、fingerprint（後述）をSHA256でハッシュ化し、160bitに圧縮したうえでNix32表現にしたもの。ドキュメントには「SHA256の先頭160bitをBase32表現にしたもの」と記載があるが、
  * Base32という言葉は[Release Note 2.20](https://nixos.org/manual/nix/unstable/release-notes/rl-2.20)でNix32という名前に改められた。理由としては[通常の意味のBase32表現](https://ja.wikipedia.org/wiki/%E4%B8%89%E5%8D%81%E4%BA%8C%E9%80%B2%E6%B3%95#Base32)とは処理が異なり紛らわしいためのようだ
  * 先頭160bitを単純に切り取ってNix32表現にするのではなく、実装では `complressHash` という関数で圧縮処理が行われている（[該当ソース]([nix/hash.cc](https://github.com/NixOS/nix/blob/2.21.1/src/nix/hash.cc#L118))）。
* fingerprintは、`<type>:sha256:<inner-digest>:/nix/store:<name>`の形式
  * `<type>`というのは以下のいずれか
    * `text:<input store path>:<input store path>:...`：derivation。`<input store path>`には、（存在すれば）derivationが参照する他のファイルのパスを指定する
    * `source:<input store path>:<input store path>:...`：外部から持ってきたファイルをNAR形式でアーカイブ化したもの
      * sourceがinput store pathを持つケースってどんなときなの？と感じるが、確かに[libstore/store-api.cc](https://github.com/NixOS/nix/blob/2.21.2/src/libstore/store-api.cc#L128)にそれっぽいコードが見つかる。しかし実例がまだ良くわかっていない…。
    * `output:<id>`：derivationからビルドされたもの、もしくはビルド予定のものを表す。`<id>`には通常`out`が入るが、ビルド出力結果を複数分けているようなパッケージでは`bin`や`lib`、`dev`などが指定されうる。
  * `<inner-digest>`は、`inner-fingerprint`をSHA256でハッシュ化し、Base16表現にしたもの
    * `inner-fingerprint`の計算方法は、上述の`type`によって異なるが、これは後々実際に計算してみつつ解説する

いろいろと書いてあるが、結局`/nix/store`下におかれるパスの種類は実質`fingerprint`の種類であり、すなわち3種類である。
* text：derivationを表す
* source：ビルドに必要なファイル、ソースコードを表す
* output：ビルド生成物そのもの、ないしディレクトリを表す

## （前準備）derivationの準備 {#prepare-derivation}

今回手で計算するもととなるderivationを簡単に書く。
* [Nix PillsのChapter 7](https://nixos.org/guides/nix-pills/working-derivation#id1388)の内容をもとに。汎用性とかは意識せず、`x86_64-linux`前提で書く
* ただNix Pillsをそのまま書き起こしになってしまうのもつまらないので、flakeを使って書いてみる。


まずいくつかのファイルを作成する
* `flake.nix`：flakeファイル
  * `default.nix` で分けないで、ここに直接derivationを書く
* `mubuilder.nix`：derivationをもとに成果物をビルドするためのシェルスクリプト
* `hello.c`：ビルドする適当なC言語ソースコード

```sh
nix flake init
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

`flake.nix`の中身。
* `packages.<system>.sample = { ... }`と書いているので、`nix build .#sample` でビルドが可能
* `coreutils = coreutils`と`gcc = gcc`は、`mybuilder.sh`で`PATH`を設定するために必要

`nix build`コマンドが実行されると、`(bashのstore path)/bin/bash (mybuilder.shのstore path)`が実行される。`flake.nix`に記載のある`./mybuilder.sh`は、`nix build`コマンド実行時に、自動的にsourceとして`/nix/store`上にコピーされる。
```nix
{
  description = "A very basic flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-23.11";
  };

  outputs = { self, nixpkgs }: {
    packages.x86_64-linux.sample = with nixpkgs.legacyPackages.x86_64-linux; derivation {
        name = "sample";
        builder = "${bash}/bin/bash";
        args = [ ./mybuilder.sh ];
        system = "x86_64-linux";
        src = ./hello.c;
        coreutils = coreutils;
        gcc = gcc;
    };
  };
}
```

これで`nix build`コマンドを実行すると、`results`ディレクトリが生成されていることがわかる。それは`/nix/store/<digest>-sample`へのシンボリックリンクになっている

```console
bombrary@nixos:~/drv-test$ nix build .#sample

bombrary@nixos:~/drv-test$ ls
default.nix  flake.lock  flake.nix  hello.c  mybuilder.sh  result

bombrary@nixos:~/drv-test$ realpath result
/nix/store/2l1a42rcz7jm1mspka2n8ivgdds8jlql-sample

bombrary@nixos:~/drv-test$ ./result/hello
Hello, World
```

## drvファイルを見る

`nix derivation show (ビルド生成物へのstore path)`で、`nix/store`に取り込まれたderivationの情報が確認できる。
```console
bombrary@nixos:~/drv-test$ nix derivation show ./result
{
  "/nix/store/rj4yv464wz8n055r8d3z8iag33f1mgg4-sample.drv": {
    "args": [
      "/nix/store/in7cqd3v1mg9f8jkvlm4d0h002h1697j-mybuilder.sh"
    ],
    "builder": "/nix/store/r9h133c9m8f6jnlsqzwf89zg9w0w78s8-bash-5.2-p15/bin/bash",
    "env": {
      "builder": "/nix/store/r9h133c9m8f6jnlsqzwf89zg9w0w78s8-bash-5.2-p15/bin/bash",
      "coreutils": "/nix/store/rk067yylvhyb7a360n8k1ps4lb4xsbl3-coreutils-9.3",
      "gcc": "/nix/store/ihhhd1r1a2wb4ndm24rnm83rfnjw5n0z-gcc-wrapper-12.3.0",
      "name": "sample",
      "out": "/nix/store/2l1a42rcz7jm1mspka2n8ivgdds8jlql-sample",
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
      "/nix/store/in7cqd3v1mg9f8jkvlm4d0h002h1697j-mybuilder.sh"
    ],
    "name": "sample",
    "outputs": {
      "out": {
        "path": "/nix/store/2l1a42rcz7jm1mspka2n8ivgdds8jlql-sample"
      }
    },
    "system": "x86_64-linux"
  }
}
```

上記のdrvファイルを見ると、多くのstore pathが確認できる。なお今回はnixpkgsのコミットハッシュを固定していないため、source以外のstore pathは異なる可能性がある。
* drvファイル：nixファイルに書かれたderivationをNixのシステムが扱うための中間表現。ATermと呼ばれる形式で書かれている
  * `/nix/store/rj4yv464wz8n055r8d3z8iag33f1mgg4-sample.drv`
* ビルドで必要な依存関係（build dependencies）
  * drvファイル
    * `/nix/store/hpkl2vyxiwf7rwvjh9lpij7swp7igilx-bash-5.2-p15.drv`
    * `/nix/store/svc566dmzacxdvdy6d1w4ahhcm9qc8zf-gcc-wrapper-12.3.0.drv`
    * `/nix/store/zf1sc2qhyv3dn4xmkkxb9n23v422bb15-coreutils-9.3.drv`
  * source
    * `/nix/store/cap4mlkfwzh7l2f2x5zy5lvgy8xb5ywd-hello.c`
    * `/nix/store/in7cqd3v1mg9f8jkvlm4d0h002h1697j-mybuilder.sh`
* output
  * `/nix/store/2l1a42rcz7jm1mspka2n8ivgdds8jlql-sample`


このうち、
* `sample`のdrvファイル
* `sample`で読み込んだsource
* `sample`のoutput

のdigestの計算をするのが、本記事の目的である。

## drvファイルの計算

drvのstore pathは以下のものであった。
* `/nix/store/rj4yv464wz8n055r8d3z8iag33f1mgg4-sample.drv`

drvファイルのdigestが本当に`rj4yv464wz8n055r8d3z8iag33f1mgg4`になるのか確認してみよう。

digestとは、fingerprintをNix32でハッシュ化したものである。fingerprintとは、drvファイルの場合以下の形式のものである。
```
text:(input store path):(input store path):...:(input store path):sha256:<inner-digest>:/nix/store:<name>
```

innter-digestとは、drvファイルをSHA256でハッシュ化し、Base16表現にしたものである。Base16というのはにHex（16進数）表記のこと。これは`sha256sum`コマンドで計算できる。
```console
bombrary@nixos:~/drv-test$ cat /nix/store/rj4yv464wz8n055r8d3z8iag33f1mgg4-sample.drv | sha256sum
786fd501ac320756a174e90baa74e7aa6ece4e36d126fac8e6bea5444bdd54ec  -

# （補足）nix-hashコマンドを使う場合
bombrary@nixos:~/drv-test$ nix-hash --type sha256 /nix/store/rj4yv464wz8n055r8d3z8iag33f1mgg4-sample.drv --flat
786fd501ac320756a174e90baa74e7aa6ece4e36d126fac8e6bea5444bdd54ec
```

`(input store path)`というのは、derivationに依存するファイルや別derivationを差す。これは`inputDrvs`と`inputSrcs`から取り出せる。
```console
bombrary@nixos:~/drv-test$ nix derivation show ./result | jq -r 'to_entries[].value | ((.inputDrvs | keys) + .inputSrcs) | .[]'
/nix/store/hpkl2vyxiwf7rwvjh9lpij7swp7igilx-bash-5.2-p15.drv
/nix/store/svc566dmzacxdvdy6d1w4ahhcm9qc8zf-gcc-wrapper-12.3.0.drv
/nix/store/zf1sc2qhyv3dn4xmkkxb9n23v422bb15-coreutils-9.3.drv
/nix/store/cap4mlkfwzh7l2f2x5zy5lvgy8xb5ywd-hello.c
/nix/store/in7cqd3v1mg9f8jkvlm4d0h002h1697j-mybuilder.sh
```

`jq`で辞書順へのソート & joinを使って、fingerprintに入れる文字列を作る（辞書順の根拠については後述の補足にて）。
```console
bombrary@nixos:~/drv-test$ \
  nix derivation show ./result | \
  jq -r 'to_entries[].value | ( (.inputDrvs | keys) + .inputSrcs) | sort | join(":")'

/nix/store/cap4mlkfwzh7l2f2x5zy5lvgy8xb5ywd-hello.c:/nix/store/hpkl2vyxiwf7rwvjh9lpij7swp7igilx-bash-5.2-p15.drv:/nix/store/in7cqd3v1mg9f8jkvlm4d0h002h1697j-mybuilder.sh:/nix/store/svc566dmzacxdvdy6d1w4ahhcm9qc8zf-gcc-wrapper-12.3.0.drv:/nix/store/zf1sc2qhyv3dn4xmkkxb9n23v422bb15-coreutils-9.3.drv
```

これを`text:`の直後に挿入すれば、fingerprintの完成である。
```console
bombrary@nixos:~/drv-test$ \
  nix derivation show ./result | \
  jq -r 'to_entries[].value | ( (.inputDrvs | keys) + .inputSrcs) | sort | join(":")' | \
  xargs -I{} echo 'text:{}:sha256:786fd501ac320756a174e90baa74e7aa6ece4e36d126fac8e6bea5444bdd54ec:/nix/store:sample.drv'

text:/nix/store/cap4mlkfwzh7l2f2x5zy5lvgy8xb5ywd-hello.c:/nix/store/hpkl2vyxiwf7rwvjh9lpij7swp7igilx-bash-5.2-p15.drv:/nix/store/in7cqd3v1mg9f8jkvlm4d0h002h1697j-mybuilder.sh:/nix/store/svc566dmzacxdvdy6d1w4ahhcm9qc8zf-gcc-wrapper-12.3.0.drv:/nix/store/zf1sc2qhyv3dn4xmkkxb9n23v422bb15-coreutils-9.3.drv:sha256:786fd501ac320756a174e90baa74e7aa6ece4e36d126fac8e6bea5444bdd54ec:/nix/store:sample.drv
```

これを適当なファイルに書き出して、`nix-hash`ハッシュ化することで、期待通りのdigestが計算できた。
* echoには必ず`-n`をつけて、ファイルの終わりに改行が入らないようにすること。そうしないと全然違うハッシュになってしまう
* nix-hashについて
  * `--flat`は、NAR形式に変換せずにハッシュ化するオプション
  * `--base32`でNix32表現で出力する
  * `--truncate`で、ハッシュを160ビットに圧縮して出力

```console
bombrary@nixos:~/drv-test$ echo -n "text:/nix/store/cap4mlkfwzh7l2f2x5zy5lvgy8xb5ywd-hello.c:/nix/store/hpkl2vyxiwf7rwvjh9lpij7swp7igilx-bash-5.2-p15.drv:/nix/store/in7cqd3v1mg9f8jkvlm4d0h002h1697j-mybuilder.sh:/nix/store/svc566dmzacxdvdy6d1w4ahhcm9qc8zf-gcc-wrapper-12.3.0.drv:/nix/store/zf1sc2qhyv3dn4xmkkxb9n23v422bb15-coreutils-9.3.drv:sha256:786fd501ac320756a174e90baa74e7aa6ece4e36d126fac8e6bea5444bdd54ec:/nix/store:sample.drv" > sample.drv.str

bombrary@nixos:~/drv-test$ nix-hash --type sha256 --truncate --base32 --flat sample.drv.str
rj4yv464wz8n055r8d3z8iag33f1mgg4
```

### 補足 inputのstore pathが辞書順であることの根拠

drvのハッシュが一意であるためには、当然だがfingerprintの計算も一意に定まらなければならない。そのため、`inputDrv`や`inputSrc`の順番もまた、一意で表せるような何らかのルールが必要である。そのルールとは辞書順である。

辞書順である根拠についてはドキュメントに記載がないので[NixOS/nix](https://github.com/NixOS/nix)を読む。以下は[Nix 2.21.1](https://github.com/NixOS/nix/tree/2.21.1)時点での情報である。

[libstore/derivations.cc](https://github.com/NixOS/nix/blob/2.21.1/src/libstore/derivations.cc)の`writeDerivation`関数で、`reference`に`inputSrcs`と`inputDrvs`を入れている箇所が見つかる。

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

[libstore/path.hh](https://github.com/NixOS/nix/blob/2.21.1/src/libstore/path.hh)にStorePathSetというのが用意されている。
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

C++の文字列比較は[std::char_traits::compare](https://cpprefjp.github.io/reference/string/char_traits/compare.html)となるので、辞書式順序による比較である。

## sourceの計算

今回作成したderivationでsourceは以下の2つである。
* `/nix/store/cap4mlkfwzh7l2f2x5zy5lvgy8xb5ywd-hello.c`
* `/nix/store/in7cqd3v1mg9f8jkvlm4d0h002h1697j-mybuilder.sh`

このdigestである`cap4mlkfwzh7l2f2x5zy5lvgy8xb5ywd`と`in7cqd3v1mg9f8jkvlm4d0h002h1697j`を計算したい。

いずれも依存するstore pathは存在しないはずであるから、fingerprintは以下の形式になるはずである。
```
source:sha256:<inner-digest>:/nix/store:hello.c
source:sha256:<inner-digest>:/nix/store:mybuilder.sh
```

innter-digestはsourceの場合、NAR化してそれをsha256ハッシュ化すればよい。前項で述べたが、`nix-hash`に`--flat`オプションを付けずに実行すれば、これを達成できる。
```console
bombrary@nixos:~/drv-test$ nix-hash --type sha256 hello.c
1b6fc2a02e4591a8010b53edad47273129b020a50e88abdf1d877ff832efba93

bombrary@nixos:~/drv-test$ nix-hash --type sha256 mybuilder.sh
20a1c1b966ead0ada47dfd77aebe3f3188553e91caeda9d31b70ff284ea90bf5
```

あとは`source:sha256:<inner-digest>:/nix/store:<name>`のフォーマットで書き出して、`nix-hash`コマンドでNix32表現で出力することで、sourceのdigestが計算できた。
```console
bombrary@nixos:~/drv-test$ echo -n 'source:sha256:1b6fc2a02e4591a8010b53edad47273129b020a50e88abdf1d877ff832efba93:/nix/store:hello.c' > hello.c.str

bombrary@nixos:~/drv-test$ echo -n 'source:sha256:20a1c1b966ead0ada47dfd77aebe3f3188553e91caeda9d31b70ff284ea90bf5:/nix/store:mybuilder.sh' > mybuilder.sh.str

bombrary@nixos:~/drv-test$ nix-hash --type sha256 --base32 --truncate --flat hello.c.str
cap4mlkfwzh7l2f2x5zy5lvgy8xb5ywd

bombrary@nixos:~/drv-test$ nix-hash --type sha256 --base32 --truncate --flat mybuilder.sh.str
in7cqd3v1mg9f8jkvlm4d0h002h1697j
```

## outputの計算（単純なケース） {#output-calc-simple}

上記の`hello.c`をビルドしてoutputを作成するケースの場合、outputのハッシュ計算を手作業で行うのは現実的に不可能である（理由は後述）、そのため別のシンプルなケースで計算してみよう。

まずは以下のように、`flake.nix`に`foo`、`bar`、`baz`を追加し、依存関係として `foo <- bar <- baz` が満たされるようにする。
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
      ...
      packages.x86_64-linux.foo = foo;
    };
}
```

この状態でdry-runすることで、ビルドせずにderivationだけ作る。
```console
bombrary@nixos:~/drv-test$ nix build --dry-run .#foo
these 3 derivations will be built:
  /nix/store/574hqhsqxm64xbcg1r8hgg2839abw0vm-baz.drv
  /nix/store/86np2qg3fry2zqbamcihiawcci9vcq7a-bar.drv
  /nix/store/si4z7n6kbpi3ndlmwfyp2fk6wb4wyfrf-foo.drv
```

これのoutputのパスを確認する。
```
bombrary@nixos:~/drv-test$ nix derivation show /nix/store/si4z7n6kbpi3ndlmwfyp2fk6wb4wyfrf-foo.drv^* | jq -r 'to_entries[].value.outputs.out.path'
/nix/store/jbjk9yppbjhdnja04lh9xj87adiq1mcy-foo
```

実際にdigestが `jbjk9yppbjhdnja04lh9xj87adiq1mcy` となるのかを確認してみよう。

まずfingerprintは以下の形式である。
```
output:<id>:sha256:<inner-digest>:/nix/store:<name>
```

今回のケースだと`<id>`は`out`、`<name>`は`foo`である。しかし`<inner-digest>`の計算がやや面倒である。これはdrvファイルについて、以下の状態になっているものをSHA256ハッシュ化したものである。
1. `output`のパスが含まれていない：outputのパスを計算しようとしてるのに最初から入っていたら自己再帰的になってしまい計算できないため、当たり前といえば当たり前
2. `inputDrvs`の要素の各drvファイルを以下の状態にし、SHA256ハッシュ化したもので置き換えられている
    * `output`のパスは含まれている
    * `inputDrvs`について、2と同じようにSHA256化された状態になっている。**つまり再帰的な計算が必要**。

それでは`foo.drv`を目的の状態になるように整形していく。まずファイルをコピーしてくる。
```console
bombrary@nixos:~/drv-test$ cp -f /nix/store/si4z7n6kbpi3ndlmwfyp2fk6wb4wyfrf-foo.drv foo.drv

[bombrary@nixos:~/tmp/drv-test]$ cat foo.drv
Derive([("out","/nix/store/xpp1hb67nl8f6mmxg54sidvc96xkhh43-foo","","")],[("/nix/store/azh4hppmaxva1xgckz80khsnvp22a7x0-bar.drv",["out"])],["/nix/store/lxgb38my517cf4605zm4pp39lpszvzjh-mybuilder.sh"],"x86_64-linux","/nix/store/lxgb38my517cf4605zm4pp39lpszvzjh-mybuilder.sh",[],[("bar","/nix/store/22ag5m2f89jswgcpg9rxans5msdvjbfj-bar"),("builder","/nix/store/lxgb38my517cf4605zm4pp39lpszvzjh-mybuilder.sh"),("name","foo"),("out","/nix/store/xpp1hb67nl8f6mmxg54sidvc96xkhh43-foo"),("system","x86_64-linux")])

bombrary@nixos:~/drv-test$ cat foo.drv
Derive([("out","/nix/store/jbjk9yppbjhdnja04lh9xj87adiq1mcy-foo","","")],[("/nix/store/86np2qg3fry2zqbamcihiawcci9vcq7a-bar.drv",["out"])],["/nix/store/in7cqd3v1mg9f8jkvlm4d0h002h1697j-mybuilder.sh"],"x86_64-linux","/nix/store/in7cqd3v1mg9f8jkvlm4d0h002h1697j-mybuilder.sh",[],[("bar","/nix/store/b3s0fpl7mf4h958k5dwcxhwdz37c979k-bar"),("builder","/nix/store/in7cqd3v1mg9f8jkvlm4d0h002h1697j-mybuilder.sh"),("name","foo"),("out","/nix/store/jbjk9yppbjhdnja04lh9xj87adiq1mcy-foo"),("system","x86_64-linux")])
```

まず`output`のパスを消す。

```console
bombrary@nixos:~/drv-test$ sed -i "s,/nix/store/jbjk9yppbjhdnja04lh9xj87adiq1mcy-foo,,g" foo.drv

[bombrary@nixos:~/tmp/drv-test]$ cat foo.drv
Derive([("out","","","")],[("/nix/store/86np2qg3fry2zqbamcihiawcci9vcq7a-bar.drv",["out"])],["/nix/store/in7cqd3v1mg9f8jkvlm4d0h002h1697j-mybuilder.sh"],"x86_64-linux","/nix/store/in7cqd3v1mg9f8jkvlm4d0h002h1697j-mybuilder.sh",[],[("bar","/nix/store/b3s0fpl7mf4h958k5dwcxhwdz37c979k-bar"),("builder","/nix/store/in7cqd3v1mg9f8jkvlm4d0h002h1697j-mybuilder.sh"),("name","foo"),("out",""),("system","x86_64-linux")])
```

`foo`の依存関係に`bar.drv`があるのが分かる。これをハッシュ化したいが、`bar.drv`の中にさらに`baz.drv`が依存関係にあるので、それをまずハッシュ化する。
```console
bombrary@nixos:~/drv-test$ nix derivation show /nix/store/si4z7n6kbpi3ndlmwfyp2fk6wb4wyfrf-foo.drv^* | \
  jq -r 'to_entries[].value.inputDrvs | to_entries[].key'
/nix/store/86np2qg3fry2zqbamcihiawcci9vcq7a-bar.drv

bombrary@nixos:~/drv-test$ nix derivation show /nix/store/86np2qg3fry2zqbamcihiawcci9vcq7a-bar.drv^* | \
  jq -r 'to_entries[].value.inputDrvs | to_entries[].key'
/nix/store/574hqhsqxm64xbcg1r8hgg2839abw0vm-baz.drv
```

`baz.drv`が依存するdrvは特にないので、そのままハッシュ化する。
```
bombrary@nixos:~/drv-test$ cat /nix/store/574hqhsqxm64xbcg1r8hgg2839abw0vm-baz.drv | \
  sha256sum | \
  cut -d ' ' -f 1
d7e138110ee3a03c9f28cf7d124de6db8adea690ebcb2fcd901da7cccaed645c
```

これをもとに`bar.drv`の`baz.drv`の依存関係の部分をそのハッシュに書き換え、ハッシュ化する。
```console
[bombrary@nixos:~/tmp/drv-test]$ cat /nix/store/azh4hppmaxva1xgckz80khsnvp22a7x0-bar.drv | \
  sed 's,/nix/store/f7ixslcwscmg9npjv834jcwd78m878q5-baz.drv,d7e138110ee3a03c9f28cf7d124de6db8adea690ebcb2fcd901da7cccaed645c,g' | \
  sha256sum | \
  cut -d ' ' -f 1
679584e662eaccaf5810935a21dbed2155f627d5369ba9a4ab8485b7bc8f9193
```

これをもとに`foo.drv`の`bar.drv`の依存関係の部分をそのハッシュに書き換え、fingerprintの完成である。
```console
bombrary@nixos:~/drv-test$ sed -i 's,/nix/store/86np2qg3fry2zqbamcihiawcci9vcq7a-bar.drv,c040ebdb2552e1e48c695d85079554af21637f20509d524b60150781596a9672,g' foo.drv
bombrary@nixos:~/drv-test$ cat foo.drv
Derive([("out","","","")],[("c040ebdb2552e1e48c695d85079554af21637f20509d524b60150781596a9672",["out"])],["/nix/store/in7cqd3v1mg9f8jkvlm4d0h002h1697j-mybuilder.sh"],"x86_64-linux","/nix/store/in7cqd3v1mg9f8jkvlm4d0h002h1697j-mybuilder.sh",[],[("bar","/nix/store/b3s0fpl7mf4h958k5dwcxhwdz37c979k-bar"),("builder","/nix/store/in7cqd3v1mg9f8jkvlm4d0h002h1697j-mybuilder.sh"),("name","foo"),("out",""),("system","x86_64-linux")])bombrary@nixos:~/drv-test$

bombrary@nixos:~/drv-test$ cat foo.drv | sha256sum | cut -d ' ' -f 1
0a0d34068d69a2d91943c99ab6da423372bc74e1451dc6605bd249df01b682c7
```

これを指定の形式でSHA256ハッシュ化し、Nix32表現にすれば、digestの完成で、ちゃんと`xpp1hb67nl8f6mmxg54sidvc96xkhh43`となっていることが確認できた。
```console
bombrary@nixos:~/drv-test$ cat foo.drv | sha256sum | cut -d ' ' -f 1 | xargs -I{} echo -n 'output:out:sha256:{}:/nix/store:foo' > foo.str

bombrary@nixos:~/drv-test$ nix-hash --type sha256 --base32 --truncate --flat foo.str
jbjk9yppbjhdnja04lh9xj87adiq1mcy
```

## fixed outputの計算 {#fixed-out-calc}

fixed outputとは、outputの計算に必要なものが入力に依存せず、前もって計算できるようなoutputのこと。外部からファイルをDLしてくるような場合は、`inputDrvs`や`inputSrcs`に依存せず、あくまでDLしてきたファイルのハッシュに依存してほしいため、前節での計算方法とは異なるものが用いられる。

### fixed outputの作り方

例えば、ソースコード`hello-2.1.1.tar.gz`を外部からDLするためだけのderivationである`hello-src`を追加してみよう。`fetchurl`を用いることで、ファイルをDLしてきて、それをoutputとしてくれるようなderivationを作成できる。
```nix
{
  description = "A very basic flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-23.11";
  };

  outputs = { self, nixpkgs }:
    let
      ...
    in
    {
      ...
      packages.x86_64-linux.hello-src = nixpkgs.legacyPackages.x86_64-linux.fetchurl {
        url = "http://ftp.gnu.org/pub/gnu/hello/hello-2.1.1.tar.gz";
        hash = "sha256-xRDjrQIAUX46FFNOSUs33Adw79cz/DXOL0Rd1JyWp9U="
      };
    };
}
```

これでビルドしてみる。
```console
bombrary@nixos:~/drv-test$ nix build --dry-run .#hello-src
this derivation will be built:
  /nix/store/9alvyaz7v4ljfm6kian0l3vi2vabbzz1-hello-2.1.1.tar.gz.drv
```

中身を見てみると、以下のようなderivationになっていることが分かる。
```console
bombrary@nixos:~/drv-test$ nix derivation show /nix/store/9alvyaz7v4ljfm6kian0l3vi2vabbzz1-hello-2.1.1.tar.gz.drv^*
{
  "/nix/store/9alvyaz7v4ljfm6kian0l3vi2vabbzz1-hello-2.1.1.tar.gz.drv": {
    "args": [
      ...
    ],
    "builder": "/nix/store/r9h133c9m8f6jnlsqzwf89zg9w0w78s8-bash-5.2-p15/bin/bash",
    ...
    "inputDrvs": {
      ...
    },
    "inputSrcs": [
      ...
    ],
    "name": "hello-2.1.1.tar.gz",
    "outputs": {
      "out": {
        "hash": "c510e3ad0200517e3a14534e494b37dc0770efd733fc35ce2f445dd49c96a7d5",
        "hashAlgo": "sha256",
        "path": "/nix/store/9bw6xyn3dnrlxp5vvis6qpmdyj4dq4xy-hello-2.1.1.tar.gz"
      }
    },
    "system": "x86_64-linux"
  }
}
```

いままでのderivationとは違い、`outputs`に`hash`と`hashAlg`が追加されている。これは、`hello-2.1.1.tar.gz`をDLしてきたときのハッシュとそのハッシュ方式を表している。実際、`hello.2.1.1.tar.gz`をDLしてきて`sha256sum`をかけてみると、そのハッシュはdrvに書かれていたものと一致する。
```console
bombrary@nixos:~/drv-test$ curl -OL http://ftp.gnu.org/pub/gnu/hello/hello-2.1.1.tar.gz
  % Total    % Received % Xferd  Average Speed   Time    Time     Time  Current
                                 Dload  Upload   Total   Spent    Left  Speed
100  380k  100  380k    0     0   257k      0  0:00:01  0:00:01 --:--:--  257k

bombrary@nixos:~/drv-test$ sha256sum hello-2.1.1.tar.gz
c510e3ad0200517e3a14534e494b37dc0770efd733fc35ce2f445dd49c96a7d5  hello-2.1.1.tar.gz

bombrary@nixos:~/drv-test$ nix-hash --type sha256 --base64 hello-2.1.1.tar.gz --flat
xRDjrQIAUX46FFNOSUs33Adw79cz/DXOL0Rd1JyWp9U=
```


### outputの計算（fixed outputの場合）

[outputの計算](#outputの計算)での場合、outputのハッシュを計算するためには、`inputDrvs`を適切なハッシュで置き換える必要があった。しかしfixed outputは`inputDrvs`に依存しないため、また別のハッシュの計算方法が用意されている。

ここでは、`hello-2.1.1.tar.gz` のoutputのパスが
```
bombrary@nixos:~/drv-test$ nix derivation show /nix/store/9alvyaz7v4ljfm6kian0l3vi2vabbzz1-hello-2.1.1.tar.gz.drv^* | jq -r 'to_entries[].value.outputs.out.path'
/nix/store/9bw6xyn3dnrlxp5vvis6qpmdyj4dq4xy-hello-2.1.1.tar.gz
```

になっているが、このハッシュ`9bw6xyn3dnrlxp5vvis6qpmdyj4dq4xy`を実際に計算してみよう。

今回の場合、fixed outputのinner-digestは以下の形式をSHA256でハッシュ化したものである。
```txt
fixed:out:sha256:(outputsに記載されていたhash):
```

補足：[ドキュメント](https://nixos.org/manual/nix/unstable/protocols/store-path)によると、実際の形式は `fixed:out:<rec>:<algo>:<hash>:` になるらしいが、`rec`の意味がまだ調査し切れていない。今回は無しでよいはず。

そのため、以下のように計算できる。
```console
bombrary@nixos:~/drv-test$ nix derivation show /nix/store/9alvyaz7v4ljfm6kian0l3vi2vabbzz1-hello-2.1.1.tar.gz.drv^* | \
  jq -r 'to_entries[].value.outputs.out.hash' | \
  xargs -I{} echo -n "fixed:out:sha256:{}:" | \
  sha256sum
71b997e44b3c59ab7d51f493265b099086ab9bf9d523b0db2f4a19f22ac7c4c4  -
```

fingerprintはoutputと同じで `output:out:sha256:<inner-digest>:/nix/store:<name>` の形式である。それをSHA256のNix32表現で出力すれば、求めたいハッシュの完成である。
```console
bombrary@nixos:~/drv-test$ echo -n "output:out:sha256:71b997e44b3c59ab7d51f493265b099086ab9bf9d523b0db2f4a19f22ac7c4c4:/nix/store:hello-2.1.1.tar.gz" > hello-src.str
bombrary@nixos:~/drv-test$ nix-hash --type sha256 --truncate --base32 --flat hello-src.str
9bw6xyn3dnrlxp5vvis6qpmdyj4dq4xy
```

## outputの計算（複雑なケース）の困難さの説明

[outputの計算（単純なケース）](#output-calc-simple)では、`foo.drv <- bar.drv <- baz.drv` とシンプルかつ少ない依存関係だったのでoutputのdigestを手軽に計算できた。しかし、初めのほうで作った`hello.c`をコンパイルするderivationの場合はそうはいかない。実際、その依存関係を見てみよう。

```console
bombrary@nixos:~/drv-test$ nix derivation show ./result | jq -r 'to_entries[].value.inputDrvs | to_entries[].key'
/nix/store/hpkl2vyxiwf7rwvjh9lpij7swp7igilx-bash-5.2-p15.drv
/nix/store/svc566dmzacxdvdy6d1w4ahhcm9qc8zf-gcc-wrapper-12.3.0.drv
/nix/store/zf1sc2qhyv3dn4xmkkxb9n23v422bb15-coreutils-9.3.drv
```

これらのハッシュを計算するためには、それぞれの依存関係となるdrvのハッシュも計算する必要がある。最終的には、以下のtreeをたどって再帰的に計算する必要が出てくる。
```console
bombrary@nixos:~/drv-test$ nix-store --query --tree /nix/store/rj4yv464wz8n055r8d3z8iag33f1mgg4-sample.drv | head
/nix/store/rj4yv464wz8n055r8d3z8iag33f1mgg4-sample.drv
├───/nix/store/cap4mlkfwzh7l2f2x5zy5lvgy8xb5ywd-hello.c
├───/nix/store/hpkl2vyxiwf7rwvjh9lpij7swp7igilx-bash-5.2-p15.drv
│   ├───/nix/store/ks6kir3vky8mb8zqpfhchwasn0rv1ix6-bootstrap-tools.drv
│   │   ├───/nix/store/b7irlwi2wjlx5aj1dghx4c8k3ax6m56q-busybox.drv
│   │   ├───/nix/store/bzq60ip2z5xgi7jk6jgdw8cngfiwjrcm-bootstrap-tools.tar.xz.drv
│   │   └───/nix/store/i9nx0dp1khrgikqr95ryy2jkigr4c5yv-unpack-bootstrap-tools.sh
│   ├───/nix/store/v6x3cs394jgqfbi0a42pam708flxaphh-default-builder.sh
│   ├───/nix/store/0ky7cdwf28g9v5721k3f6avjnmd2j7b5-bootstrap-stage4-gcc-wrapper-12.3.0.drv
│   │   ├───/nix/store/3dl59vc3fzy2ld67jqh12xi63z9684vf-cc-wrapper.sh
...
```

このことから、手で計算するのが絶望的であることがわかる。しかも、このoutputがfixed outputかそうでないかを見て、計算方法を変える必要がある。

するとスクリプトを書いて計算してみたくなるが、長くなるので別記事に分割する。

## まとめ

* ハッシュの計算方法を、実際にコマンドを手打ちしながら見てきた。そのことから、nix storeにあるオブジェクトには以下の4つがあることが分かった
  * derivation：build dependenciesに依存
  * source：何らかのinput store pathに依存することがある
  * output：input derivationsに依存
  * fixed output：依存関係は無し
* derivationとしてユーザがnixファイルに書く際には、インデントやスペースなどの表記揺れや依存関係の記述順に関係なく、同じハッシュが得られる
  * ATermという形式に変換され、その際に辞書順にソートされる

ほかの関連話題として、
* storeの種類：storeにもlocal-storeだとかremote-storeなどで分かれている
* fixed outputの `rec` パラメータ
* [CA Derivation](https://nixos.wiki/wiki/Ca-derivations)

などまだまだ調べていないものがあるが、調査して分かってきたらまた別記事にアウトプットしたい。
