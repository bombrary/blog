---
title: "Nixでderivationとその依存関係を調べる"
date: 2024-03-31T03:54:17Z
draft: true
tags: []
categories: []
---

Nixで、あるderivationに依存しているderivationを列挙する方法を知りたくなったので調べ、スクリプトを作成した。

## （前置き）パッケージのビルドとderivationについて

NixOSを使うとなるとたいていは`configuration.nix`や`home.nix`を設定するだけなので、もしかしたらderivationを知らないという人も少なからずいそうなので、初めに簡単に解説する。

derivationは、（一つの使い道としては）ビルドの仕様書である。原義としては、[公式doc](https://nixos.org/manual/nix/stable/language/derivations.html)を引用すると、
> a specification for running an executable on precisely defined input files to repeatably produce output files at uniquely determined file system paths
である。「正確に定義された入力ファイルをもとに繰り返し出力ファイルを生成し、一意に定められたシステムパスにそれを配置するための実行ファイルを動かすための仕様書」ということになる。つまり、derivationには、
* 入力
* （何らかの出力を生成する）実行ファイル
を書くことができる。

この特徴はプログラムのビルドに使える。例えば何らかのプログラムをビルドしたいという場合、ライブラリを持ってきて、それをコンパイルして、適当な所に生成物を配置する、という過程を踏むことになる。この情報をderivationに書くことができる。
Nixではあらゆるツールやアプリケーションのビルド方法をderivationで記述する。

もちろん、derivationの定義としては別にビルドに限らず使える。例えば[buildEnv](https://nixos.org/manual/nixpkgs/stable/#sec-building-environment)は、アプリケーションをビルドするのではなく、アプリケーションを集めたディレクトリ構造を生成する。

## 準備

今回パッケージの列挙に用いるパッケージを適当に作ってビルドしてみよう。

まず、flakeのひな形を作成。
```console
bombrary@nixos:~/deps$ nix flake init
wrote: /home/bombrary/deps/flake.nix
```

## あるアプリケーションがどのderivationでビルドされたかを特定する

derivation名だけ知りたいのであれば、`which`と`realpath`を組み合わせて、アプリケーションが`/nix/store`のどのディレクトリに配置されているのかを見ればよい。以下は、lsコマンドが`coreutils-full-9.3`に含まれていることを特定する例。
```console
bombrary@nixos:~$ realpath `which ls`
/nix/store/03167shkax5dxclnv6r3sd8waa6lq7ny-coreutils-full-9.3/bin/coreutils
```

derivationファイルそのものを見たい場合は、[nix derivation showコマンド](https://nixos.org/manual/nix/stable/command-ref/new-cli/nix3-derivation-show)を使う。

以下はlsコマンドが収録されているパッケージのderivationの情報を出力する例。
```console
bombrary@nixos:~$ nix derivation show `which ls`
{
  "/nix/store/g0kqr7b99b70kb10vmqg10vkj9nfk7zm-coreutils-full-9.3.drv": {
    "args": [
      "-e",
      "/nix/store/v6x3cs394jgqfbi0a42pam708flxaphh-default-builder.sh"
    ],
    "builder": "/nix/store/7dpxg7ki7g8ynkdwcqf493p2x8divb4i-bash-5.2-p15/bin/bash",
    "env": {
      ...
    },
    "inputDrvs": {
      "/nix/store/5q67fxm276bdp87jpmckvz3n81akw6a5-perl-5.38.2.drv": {
        "dynamicOutputs": {},
        "outputs": [
          "out"
        ]
      },
      "/nix/store/98sv0g544bqmks49d6vgylbkh9sccdvm-attr-2.5.1.drv": {
        "dynamicOutputs": {},
        "outputs": [
          "dev"
        ]
      },
      "/nix/store/9jcfzyyb0h86mvc31s9qmxs6lncqrwhc-acl-2.3.1.drv": {
        "dynamicOutputs": {},
        "outputs": [
          "dev"
        ]
      },
      "/nix/store/akpwym6q116hivciyq2vqj9n5jk9f5i6-xz-5.4.4.drv": {
        "dynamicOutputs": {},
        "outputs": [
          "bin"
        ]
      },
      "/nix/store/d1qldhg6iix84bqncbzml2a1nw8p95bg-gmp-with-cxx-6.3.0.drv": {
        "dynamicOutputs": {},
        "outputs": [
          "dev"
        ]
      },
      "/nix/store/ks5ivc59k57kwii93qlsfgcx2a7xma1k-autoreconf-hook.drv": {
        "dynamicOutputs": {},
        "outputs": [
          "out"
        ]
      },
      "/nix/store/mnrjvk62d35v8514kc5w31fg3py0smr8-coreutils-9.3.tar.xz.drv": {
        "dynamicOutputs": {},
        "outputs": [
          "out"
        ]
      },
      "/nix/store/mvvhw7jrrr8wnjihpalw4s3y3g7jihgw-stdenv-linux.drv": {
        "dynamicOutputs": {},
        "outputs": [
          "out"
        ]
      },
      "/nix/store/szciaprmwb7kdj7zv1b56midf7jfkjnw-bash-5.2-p15.drv": {
        "dynamicOutputs": {},
        "outputs": [
          "out"
        ]
      },
      "/nix/store/wd100hlzyh5w9zkfljkaagp87b7h7733-openssl-3.0.12.drv": {
        "dynamicOutputs": {},
        "outputs": [
          "dev"
        ]
      }
    },
    "inputSrcs": [
      "/nix/store/1cwqp9msvi5z8517czfl88dd42yhrdwg-separate-debug-info.sh",
      "/nix/store/v6x3cs394jgqfbi0a42pam708flxaphh-default-builder.sh"
    ],
    "name": "coreutils-full-9.3",
    "outputs": {
      "debug": {
        "path": "/nix/store/b073nwng2fy24zaqbdx6zbimxkad7dyk-coreutils-full-9.3-debug"
      },
      "info": {
        "path": "/nix/store/1pd076gkjwh0wdv8cnxy6p7kl141jnk2-coreutils-full-9.3-info"
      },
      "out": {
        "path": "/nix/store/03167shkax5dxclnv6r3sd8waa6lq7ny-coreutils-full-9.3"
      }
    },
    "system": "x86_64-linux"
  }
}
```

ちなみに、アプリケーションの実行ファイルそのものではなく、直接drvファイルを指定することも可能（その場合は、末尾に `^*` をつけたほうがよいっぽい）。
```sh
nix derivation show /nix/store/g0kqr7b99b70kb10vmqg10vkj9nfk7zm-coreutils-full-9.3.drv^*
```

derivationから、以下のことがわかる。
* パッケージ名とバージョン：coreutils-full-9.3にlsが収録されている
* 依存関係：coreutilsをビルドするためには、さらに次のderivationが必要である

```console
bombrary@nixos:~$ nix derivation show `which ls` | jq -r 'to_entries[].key'
/nix/store/g0kqr7b99b70kb10vmqg10vkj9nfk7zm-coreutils-full-9.3.drv

bombrary@nixos:~$ nix derivation show `which ls` | jq -r 'to_entries[].value.inputDrvs | to_entries[].key'
/nix/store/5q67fxm276bdp87jpmckvz3n81akw6a5-perl-5.38.2.drv
/nix/store/98sv0g544bqmks49d6vgylbkh9sccdvm-attr-2.5.1.drv
/nix/store/9jcfzyyb0h86mvc31s9qmxs6lncqrwhc-acl-2.3.1.drv
/nix/store/akpwym6q116hivciyq2vqj9n5jk9f5i6-xz-5.4.4.drv
/nix/store/d1qldhg6iix84bqncbzml2a1nw8p95bg-gmp-with-cxx-6.3.0.drv
/nix/store/ks5ivc59k57kwii93qlsfgcx2a7xma1k-autoreconf-hook.drv
/nix/store/mnrjvk62d35v8514kc5w31fg3py0smr8-coreutils-9.3.tar.xz.drv
/nix/store/mvvhw7jrrr8wnjihpalw4s3y3g7jihgw-stdenv-linux.drv
/nix/store/szciaprmwb7kdj7zv1b56midf7jfkjnw-bash-5.2-p15.drv
/nix/store/wd100hlzyh5w9zkfljkaagp87b7h7733-openssl-3.0.12.drv
```

なお、derivationファイルの実態は `/nix/store/g0kqr7b99b70kb10vmqg10vkj9nfk7zm-coreutils-full-9.3.drv` であり、ATermという形式で書かれている（[参考](https://nixos.org/manual/nix/stable/protocols/derivation-aterm)）。`nix derivation show` コマンドではこれをJSONに変換して出力している。生のデータを見てみたいなら直接 `cat` で見てみるとよい。以下はcoreutilsの結果（分かりやすく改行している）。
```console
bombrary@nixos:~$ nix derivation show `which ls` | jq -r 'to_entries[].key'
/nix/store/g0kqr7b99b70kb10vmqg10vkj9nfk7zm-coreutils-full-9.3.drv

bombrary@nixos:~$ nix derivation show `which ls` | jq -r 'to_entries[].key' | xargs cat
Derive(
 [("debug","/nix/store/b073nwng2fy24zaqbdx6zbimxkad7dyk-coreutils-full-9.3-debug","",""),
  ("info","/nix/store/1pd076gkjwh0wdv8cnxy6p7kl141jnk2-coreutils-full-9.3-info","",""),
  ("out","/nix/store/03167shkax5dxclnv6r3sd8waa6lq7ny-coreutils-full-9.3","","")],
 [("/nix/store/5q67fxm276bdp87jpmckvz3n81akw6a5-perl-5.38.2.drv",["out"]),
  ("/nix/store/98sv0g544bqmks49d6vgylbkh9sccdvm-attr-2.5.1.drv",["dev"]),
  ("/nix/store/9jcfzyyb0h86mvc31s9qmxs6lncqrwhc-acl-2.3.1.drv",["dev"]),
  ("/nix/store/akpwym6q116hivciyq2vqj9n5jk9f5i6-xz-5.4.4.drv",["bin"]),
  ("/nix/store/d1qldhg6iix84bqncbzml2a1nw8p95bg-gmp-with-cxx-6.3.0.drv",["dev"]),
  ("/nix/store/ks5ivc59k57kwii93qlsfgcx2a7xma1k-autoreconf-hook.drv",["out"]),
  ("/nix/store/mnrjvk62d35v8514kc5w31fg3py0smr8-coreutils-9.3.tar.xz.drv",["out"]),
  ("/nix/store/mvvhw7jrrr8wnjihpalw4s3y3g7jihgw-stdenv-linux.drv",["out"]),
  ("/nix/store/szciaprmwb7kdj7zv1b56midf7jfkjnw-bash-5.2-p15.drv",["out"]),
  ("/nix/store/wd100hlzyh5w9zkfljkaagp87b7h7733-openssl-3.0.12.drv",["dev"])],
 ["/nix/store/1cwqp9msvi5z8517czfl88dd42yhrdwg-separate-debug-info.sh",
  "/nix/store/v6x3cs394jgqfbi0a42pam708flxaphh-default-builder.sh"],
 "x86_64-linux",
 "/nix/store/7dpxg7ki7g8ynkdwcqf493p2x8divb4i-bash-5.2-p15/bin/bash",
 ["-e","/nix/store/v6x3cs394jgqfbi0a42pam708flxaphh-default-builder.sh"],
 [("FORCE_UNSAFE_CONFIGURE",""),
  ("NIX_CFLAGS_COMPILE",""),
  ("NIX_LDFLAGS",""),
  ("__structuredAttrs",""),
  ("buildInputs","/nix/store/hwb08pf2byl2a1rnmaxq56f389h6b6yn-acl-2.3.1-dev /nix/store/djciacxl96yr2wd02lcxyn8z046fzrqr-attr-2.5.1-dev /nix/store/1fszsmhmlhbi4yzl2wgi08cfw0dng7pq-gmp-with-cxx-6.3.0-dev /nix/store/2d8yhfx7f2crn8scyzdk6dg3lw7y1ifh-openssl-3.0.12-dev"),
  ("builder","/nix/store/7dpxg7ki7g8ynkdwcqf493p2x8divb4i-bash-5.2-p15/bin/bash"),
  ("cmakeFlags",""),
  ("configureFlags","--with-packager=https://nixos.org --enable-single-binary=symlinks --with-openssl gl_cv_have_proc_uptime=yes"),
  ("debug","/nix/store/b073nwng2fy24zaqbdx6zbimxkad7dyk-coreutils-full-9.3-debug"),
  ("depsBuildBuild",""),
  ("depsBuildBuildPropagated",""),
  ("depsBuildTarget",""),
  ("depsBuildTargetPropagated",""),
  ("depsHostHost",""),
  ("depsHostHostPropagated",""),
  ("depsTargetTarget",""),
  ("depsTargetTargetPropagated",""),
  ("doCheck","1"),
  ("doInstallCheck",""),
  ("enableParallelBuilding","1"),
  ("enableParallelChecking","1"),
  ("enableParallelInstalling","1"),
  ("info","/nix/store/1pd076gkjwh0wdv8cnxy6p7kl141jnk2-coreutils-full-9.3-info"),
  ("mesonFlags",""),
  ("name","coreutils-full-9.3"),
  ("nativeBuildInputs","/nix/store/nsl35d8x8jp0vy8n4xy8sx9v68gdh444-autoreconf-hook /nix/store/rza0ib08brnkwx75n7rncyjq97j76ris-perl-5.38.2 /nix/store/3q6fnwcm677l1q60vkhcf9m1gxhv83jm-xz-5.4.4-bin /nix/store/1cwqp9msvi5z8517czfl88dd42yhrdwg-separate-debug-info.sh"),
  ("out","/nix/store/03167shkax5dxclnv6r3sd8waa6lq7ny-coreutils-full-9.3"),
  ("outputs","out info debug"),
  ("patches",""),
  ("pname","coreutils-full"),
  ("postInstall",""),
  ("postPatch","# The test tends to fail on btrfs, f2fs and maybe other unusual filesystems.\nsed '2i echo Skipping dd sparse test && exit 77' -i ./tests/dd/sparse.sh\nsed '2i echo Skipping du threshold test && exit 77' -i ./tests/du/threshold.sh\nsed '2i echo Skipping cp reflink-auto test && exit 77' -i ./tests/cp/reflink-auto.sh\nsed '2i echo Skipping cp sparse test && exit 77' -i ./tests/cp/sparse.sh\nsed '2i echo Skipping rm deep-2 test && exit 77' -i ./tests/rm/deep-2.sh\nsed '2i echo Skipping du long-from-unreadable test && exit 77' -i ./tests/du/long-from-unreadable.sh\n\n# Some target platforms, especially when building inside a container have\n# issues with the inotify test.\nsed '2i echo Skipping tail inotify dir recreate test && exit 77' -i ./tests/tail-2/inotify-dir-recreate.sh\n\n# sandbox does not allow setgid\nsed '2i echo Skipping chmod setgid test && exit 77' -i ./tests/chmod/setgid.sh\nsubstituteInPlace ./tests/install/install-C.sh \\\n  --replace 'mode3=2755' 'mode3=1755'\n\n# Fails on systems with a rootfs. Looks like a bug in the test, see\n# https://lists.gnu.org/archive/html/bug-coreutils/2019-12/msg00000.html\nsed '2i print \"Skipping df skip-rootfs test\"; exit 77' -i ./tests/df/skip-rootfs.sh\n\n# these tests fail in the unprivileged nix sandbox (without nix-daemon) as we break posix assumptions\nfor f in ./tests/chgrp/{basic.sh,recurse.sh,default-no-deref.sh,no-x.sh,posix-H.sh}; do\n  sed '2i echo Skipping chgrp && exit 77' -i \"$f\"\ndone\nfor f in gnulib-tests/{test-chown.c,test-fchownat.c,test-lchown.c}; do\n  echo \"int main() { return 77; }\" > \"$f\"\ndone\n\n# intermittent failures on builders, unknown reason\nsed '2i echo Skipping du basic test && exit 77' -i ./tests/du/basic.sh\n"),
  ("preInstall",""),
  ("propagatedBuildInputs",""),
  ("propagatedNativeBuildInputs",""),
  ("separateDebugInfo","1"),
  ("src","/nix/store/8f1x5yr083sjbdkv33gxwiybywf560nz-coreutils-9.3.tar.xz"),
  ("stdenv","/nix/store/kv5wkk7xgc8paw9azshzlmxraffqcg0i-stdenv-linux"),
  ("strictDeps",""),
  ("system","x86_64-linux"),
  ("version","9.3")]
)
```

## derivationに依存するderivationの特定

先述のとおり、`nix derivation show` コマンドで出力されたJSON結果のうち、`inputDrvs`に書かれているものがそれである。

```console
bombrary@nixos:~$ nix derivation show `which ls` | jq -r 'to_entries[].value.inputDrvs | to_entries[].key'
/nix/store/5q67fxm276bdp87jpmckvz3n81akw6a5-perl-5.38.2.drv
/nix/store/98sv0g544bqmks49d6vgylbkh9sccdvm-attr-2.5.1.drv
/nix/store/9jcfzyyb0h86mvc31s9qmxs6lncqrwhc-acl-2.3.1.drv
/nix/store/akpwym6q116hivciyq2vqj9n5jk9f5i6-xz-5.4.4.drv
/nix/store/d1qldhg6iix84bqncbzml2a1nw8p95bg-gmp-with-cxx-6.3.0.drv
/nix/store/ks5ivc59k57kwii93qlsfgcx2a7xma1k-autoreconf-hook.drv
/nix/store/mnrjvk62d35v8514kc5w31fg3py0smr8-coreutils-9.3.tar.xz.drv
/nix/store/mvvhw7jrrr8wnjihpalw4s3y3g7jihgw-stdenv-linux.drv
/nix/store/szciaprmwb7kdj7zv1b56midf7jfkjnw-bash-5.2-p15.drv
/nix/store/wd100hlzyh5w9zkfljkaagp87b7h7733-openssl-3.0.12.drv
```

さらに深い階層をインタラクティブに確認したい、という場合には、[nix-tree](https://github.com/utdemir/nix-tree)を使うとよい。

## 再帰的に依存関係を調べる

nix-treeではインタラクティブに深い階層の依存関係を探れるが、一括で全部表示するためにはどうすればよいのだろうか。
これに関しては、いまいち調べ方がわからず、コマンドでの調べ方が見つからない。そのためPythonスクリプトを書いた。

### drvファイルのパース

drvファイルの中に依存関係が書かれているため、まずはdrvファイルをパースする。drvファイルをぐっとにらむと、データ型としては以下のパターンしかなさそうだとわかる。
* 文字列：`"` でくくられている
* リスト：`[`と`]`でくくられている
* タプル：`(`と`)`でくくられている

最初の`Derive(...)`もタプルとして解釈することにすると、drvの形式をパースする関数`parse_drv`は次のように実装できる。ほとんどの`parse_*`関数は、返り値を`(パースした値, 残りの文字列)`のタプルで返すように実装している。

```python
def parse_drv(s: str) -> tuple:
    s = s[len("Derive("):]
    r, _ = parse_tuple(s)
    return r

def parse_ch(s: str) -> tuple[str, str]:
    return s[0], s[1:]

def parse_prim(head: str, s: str) -> tuple[tuple|list|str, str]:
    match head:
        case "(":
            return parse_tuple(s)
        case "[":
            return parse_list(s)
        case "\"":
            return parse_str(s)
        case _:
            raise ValueError("Invalid token")

def parse_tuple(s: str) -> tuple[tuple, str]:
    res = []
    while True:
        c, s = parse_ch(s)
        match c:
            case ")":
                break
            case ",":
               pass
            case _:
                r, s = parse_prim(c, s)
                res.append(r)
    return tuple(res), s

def parse_list(s: str) -> tuple[list, str]:
    res = []
    while True:
        c, s = parse_ch(s)
        match c:
            case "]":
                break
            case ",":
                pass
            case _:
                r, s = parse_prim(c, s)
                res.append(r)
    return res, s

def parse_str(s: str) -> tuple[str, str]:
    res = ""
    while True:
        match s[0]:
            case "\"":
                c, s = parse_ch(s)
                if res and res[-1] == "\\":
                    res += c
                else:
                    break
            case _:
                c, s = parse_ch(s)
                res += c
    return res, s
```

### 依存関係の再帰的な読み取りと出力

上記の関数をもとに、再帰的に依存関係を探る関数`show_deps`を実装する
* `nix derivation show`コマンドでのinputDrvsは、drvファイルでは`Derive(...)`の2番目の要素に入っているので、そこから取り出す
* ある依存関係がほかのderivationの依存関係になっていることがあるが、同じものが出てきた場合は省略する。省略のためのメモとして`SET`を用意している
* ツリー構造として読み込んだ後、`show_tree`で出力する

```python
import sys

SET = set()

Tree = None | dict[str, "Tree"]


def load_drv(path: str) -> tuple:
    with open(path) as f:
        return parse_drv(f.read())


def dump_deps(path: str) -> Tree:
      if path not in SET:
          SET.add(path)

          drv = load_drv(path)
          input_drvs = drv[1]
          return { input_drv_path: dump_deps(input_drv_path) for input_drv_path, _ in input_drvs }
      else:
          return None


def show_tree(tree: Tree, last: bool, header=""):
    if tree is None:
        return

    for i, (k, v) in enumerate(tree.items()):
        last = i == len(tree) - 1
        print(header, end="")
        if last:
            print("└──", end="")
        else:
            print("├──", end="")

        if v is None:
            print(f'{k}: cached')
        else:
            print(k)

            if last:
                header_children = header + "   "
            else:
                header_children = header + "│  "
            show_tree(v, last, header_children)


if __name__ == "__main__":
    tree = dump_deps(sys.argv[1])
    show_tree(tree, True, "")
```

実行例。

```console
bombrary@nixos:~/deps$ nix run nixpkgs#python3 -- dump.py /nix/store/g0kqr7b99b70kb10vmqg10vkj9nfk7zm-coreutils-full-9.3.drv | head
├──/nix/store/5q67fxm276bdp87jpmckvz3n81akw6a5-perl-5.38.2.drv
│  ├──/nix/store/1vzpfyxn64qx5my47kc0hjys37404hls-gcc-12.3.0.drv
│  │  ├──/nix/store/1032as2ph6j8pwan8dijl60jmfnzfi6b-perl-5.38.2.drv
│  │  │  ├──/nix/store/2zsw6v5l9zzhslrrdqpljnb425njg1pf-perl-5.38.2.tar.gz.drv
│  │  │  ├──/nix/store/9xhbdxvc93v7hc4vplng07z3y3lmfwvq-bootstrap-stage1-stdenv-linux.drv
│  │  │  │  ├──/nix/store/271ydjn02v2r49l5nn6yw5lr3nc5ydbi-update-autotools-gnu-config-scripts-hook.drv
│  │  │  │  │  ├──/nix/store/303sqdqr3x78jlgs00pixbdwv7hqizq1-gnu-config-2023-09-19.drv
│  │  │  │  │  │  ├──/nix/store/h11pn2l5rszzgjrl84qw2ifr33rdkjcq-config.sub-28ea239.drv
│  │  │  │  │  │  ├──/nix/store/ks6kir3vky8mb8zqpfhchwasn0rv1ix6-bootstrap-tools.drv
│  │  │  │  │  │  │  ├──/nix/store/b7irlwi2wjlx5aj1dghx4c8k3ax6m56q-busybox.drv
...
   ├──/nix/store/2cv1xd90as2wkga6wg8yv53gz7lg95if-openssl-3.0.12.tar.gz.drv
   │  ├──/nix/store/6ic1qxk57sy6zqjfj3v9zpwizq90ljja-stdenv-linux.drv: cached
   │  ├──/nix/store/h1y9767im7cxdc2rqg6qyfiiq8ijgk41-mirrors-list.drv: cached
   │  ├──/nix/store/kvq4wg5d44bbpg6820hqixdhwbvm5yhb-curl-8.4.0.drv: cached
   │  └──/nix/store/szciaprmwb7kdj7zv1b56midf7jfkjnw-bash-5.2-p15.drv: cached
   ├──/nix/store/5q67fxm276bdp87jpmckvz3n81akw6a5-perl-5.38.2.drv: cached
   ├──/nix/store/a6a7nrfmpkj7lapckk8h5qmvr6f8542h-coreutils-9.3.drv: cached
   ├──/nix/store/jm8hin39q3ms3gffpa2w3xk8bxmychm3-make-shell-wrapper-hook.drv: cached
   ├──/nix/store/mvvhw7jrrr8wnjihpalw4s3y3g7jihgw-stdenv-linux.drv: cached
   └──/nix/store/szciaprmwb7kdj7zv1b56midf7jfkjnw-bash-5.2-p15.drv: cached
```

ツリー構造ではなくただ一覧で表示したい & cachedの行はいらない場合は、適当にsedやgrepで整形すればよい。
```
bombrary@nixos:~/deps$ nix run nixpkgs#python3 -- dump.py /nix/store/g0kqr7b99b70kb10vmqg10vkj9nfk7zm-coreutils-full-9.3.drv | sed 's/.*\(\/nix\/store\/.*\)/\1/' | grep -v cached
/nix/store/5q67fxm276bdp87jpmckvz3n81akw6a5-perl-5.38.2.drv
/nix/store/1vzpfyxn64qx5my47kc0hjys37404hls-gcc-12.3.0.drv
/nix/store/1032as2ph6j8pwan8dijl60jmfnzfi6b-perl-5.38.2.drv
/nix/store/2zsw6v5l9zzhslrrdqpljnb425njg1pf-perl-5.38.2.tar.gz.drv
/nix/store/9xhbdxvc93v7hc4vplng07z3y3lmfwvq-bootstrap-stage1-stdenv-linux.drv
/nix/store/271ydjn02v2r49l5nn6yw5lr3nc5ydbi-update-autotools-gnu-config-scripts-hook.drv
/nix/store/303sqdqr3x78jlgs00pixbdwv7hqizq1-gnu-config-2023-09-19.drv
/nix/store/h11pn2l5rszzgjrl84qw2ifr33rdkjcq-config.sub-28ea239.drv
/nix/store/ks6kir3vky8mb8zqpfhchwasn0rv1ix6-bootstrap-tools.drv
/nix/store/b7irlwi2wjlx5aj1dghx4c8k3ax6m56q-busybox.drv
...
```
