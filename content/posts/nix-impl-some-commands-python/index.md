---
title: "Nixのいくつかの処理をPythonで実装してみる"
date: 2024-04-05T00:05:00+09:00
tags: ["Python", "derivation", "NAR"]
categories: ["Nix"]
toc: true
---

[Nixのパッケージ・derivationの探り方まとめ]({{< ref "/posts/nix-search-dependencies" >}})にて色々なコマンドを紹介したが、それらがNix内部でどう処理されているのかを知りたくなり、その過程でPython実装を書いた。

目的は、以下の2つの処理をPythonで実装することである。
* build dependenciesを（間接的なものも含め）出力する
* runtime dependenciesを（間接的なものも含め）出力する

なお、公式ではどちらも`nix-store --query --requisites`ないし`nix-store --query --tree`で出力可能である。

## derivationをパースする

この先の処理を実装するにあたって、drvから情報を取り出す必要があるので、ここでパーサーを実装する。

まずdrvのファイル形式は以下のようなものであった。見やすいように改行を挟んでいるが、実際には無い。

```console
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

drvファイルをにらむと、データ型としては以下のパターンしかなさそうだとわかる。
* 文字列：`"` でくくられている
* リスト：`[`と`]`でくくられている
* タプル：`(`と`)`でくくられている

本当はdataclassとかで包んだほうが良いが、今回は簡単のため`Derive(...)`をタプルとして解釈することにする。すると、drvの形式をパースする関数`parse_drv`は次のように実装できる。ほとんどの`parse_*`関数は、返り値を`(パースした値, 残りの文字列)`のタプルで返すように実装している。

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

## derivationの直接的・間接的なbuild dependenciesもすべて出力する

上記の関数をもとに、再帰的に依存関係を探る関数`dump_build_deps`を実装する
* `nix derivation show`コマンドでのinputDrvsは、drvファイルでは`Derive(...)`の2番目の要素に入っているので、そこから取り出す
* `nix derivation show`コマンドでのinputSrcsは、drvファイルでは`Derive(...)`の3番目の要素に入っているので、そこから取り出す
* ある依存関係がほかのderivationの依存関係になっていることがあるが、同じものが出てきた場合は省略する。省略のためのメモとして`DRV_CACHE`を用意している
* ツリー構造として読み込んだ後、`show_tree`で出力する

```python
import sys

DRV_CACHE = {}

Tree = str | dict[str, "Tree"]

def load_drv(path: str) -> tuple:
    with open(path) as f:
        return parse_drv(f.read())

def dump_build_deps(path: str) -> Tree:
      if path not in DRV_CACHE:
          DRV_CACHE[path] = load_drv(path)
          input_drvs = DRV_CACHE[path][1]
          input_srcs = DRV_CACHE[path][2]
          res = { input_drv_path: dump_build_deps(input_drv_path) for input_drv_path, _ in input_drvs }
          res |= { src: "" for src in input_srcs }
          return res
      else:
          return ": cached"

def show_tree(tree: Tree, last: bool, header=""):
    if isinstance(tree, str):
        return

    for i, (k, v) in enumerate(tree.items()):
        last = i == len(tree) - 1
        print(header, end="")
        if last:
            print("└──", end="")
        else:
            print("├──", end="")

        if isinstance(v, str):
            print(f'{k}{v}')
        else:
            print(k)

            if last:
                header_children = header + "   "
            else:
                header_children = header + "│  "
            show_tree(v, last, header_children)


if __name__ == "__main__":
    tree = dump_build_deps(sys.argv[1])
    show_tree(tree, True, "")
```

実行例。

```console
bombrary@nixos:~/deps$ nix run nixpkgs#python3 -- dump.py /nix/store/g0kqr7b99b70kb10vmqg10vkj9nfk7zm-coreutils-full-9.3.drv
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
│  ├──/nix/store/jm8hin39q3ms3gffpa2w3xk8bxmychm3-make-shell-wrapper-hook.drv: cached
│  ├──/nix/store/mvvhw7jrrr8wnjihpalw4s3y3g7jihgw-stdenv-linux.drv: cached
│  ├──/nix/store/szciaprmwb7kdj7zv1b56midf7jfkjnw-bash-5.2-p15.drv: cached
│  ├──/nix/store/1cwqp9msvi5z8517czfl88dd42yhrdwg-separate-debug-info.sh
│  ├──/nix/store/cklrwbwi889pp2fdsswdjvn12sdy5i5j-openssl-disable-kernel-detection.patch
│  ├──/nix/store/lzmcfv2m4ripknpvbsv8wcg1ik1kif4h-use-etc-ssl-certs.patch
│  ├──/nix/store/sq4h6bqjx12v9whvm65pjss25hg1538q-nix-ssl-cert-file.patch
│  └──/nix/store/v6x3cs394jgqfbi0a42pam708flxaphh-default-builder.sh
├──/nix/store/1cwqp9msvi5z8517czfl88dd42yhrdwg-separate-debug-info.sh
└──/nix/store/v6x3cs394jgqfbi0a42pam708flxaphh-default-builder.sh
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

## ファイル・ディレクトリをNAR形式に変換する

runtime dependenciesを出力するための前準備。なお、同様のことは`nix nar dump-path`コマンドでも行える。

[edolstra氏のPh.D論文](https://edolstra.github.io/pubs/phd-thesis.pdf)のp.93のFigure 5.2をもとに作成。

```python3
import io
import os
import stat

def archiveNAR(out_path: str) -> bytes:
    out = io.BytesIO()
    serialize(out, out_path)
    return out.getvalue()

def serialize(out: io.BytesIO, path: str):
    write_string(out, "nix-archive-1")
    serialize1(out, path)

def serialize1(out: io.BytesIO, path: str):
    write_string(out, "(")
    serialize2(out, path)
    write_string(out, ")")

def serialize_entry(out: io.BytesIO, name: str, path: str):
    write_strings(out, "entry", "(", "name", name, "node")
    serialize1(out, path);
    write_string(out, ")")

def serialize2(out: io.BytesIO, path: str):
    def dump_contents(path):
        with open(path, 'rb') as f:
            bs = f.read()
            write_bytes(out, bs);

    st = os.lstat(path)

    if stat.S_ISREG(st.st_mode):
        write_strings(out, "type", "regular")
        if is_executable(st.st_mode):
            write_strings(out, "executable", "")
        write_string(out, "contents")
        dump_contents(path);
    elif stat.S_ISDIR(st.st_mode):
        write_strings(out, "type", "directory")

        entries = read_directory(path)
        for relpath, _ in sorted(entries.items(), key=lambda e: e[0]):
            abspath = os.path.join(path, relpath)
            serialize_entry(out, relpath, abspath)

    elif stat.S_ISLNK(st.st_mode):
        write_strings(out, "type", "symlink", "target", os.readlink(path))

    else:
        raise ValueError("Invalid filetype")

def read_directory(dirpath: str):
    with os.scandir(dirpath) as it:
        return { e.name: os.lstat(e) for e in it }

def is_executable(mode: int) -> bool:
    return (mode & 0o111) != 0

def write_string(out: io.BytesIO, s: str):
    bs = s.encode(encoding='ascii')
    write_bytes(out, bs)

def write_strings(out: io.BytesIO, *ss: str):
    for s in ss:
        write_string(out, s)

def write_bytes(out: io.BytesIO, bs: bytes):
    out.write(len(bs).to_bytes(8, byteorder='little'))
    out.write(bs)

    m = len(bs) % 8
    if m:
        pad = b"\x00" * (8 - (len(bs) % 8))
        out.write(pad)
```

mainの部分。
```python
import sys

if __name__ == "__main__":
    sys.stdout.buffer.write(archiveNAR(sys.argv[1]))
```

`nix nar dump-path` コマンドの結果と一致していることが分かる。
```console
bombrary@nixos:~/deps$ echo "Hello, World" > hello.txt
bombrary@nixos:~/deps$ paste <(nix nar dump-path hello.txt | od -w8 -tx1z) <(nix run nixpkgs#python3 -- dump.py hello.txt | od -w8 -tx1z)
0000000 0d 00 00 00 00 00 00 00  >........<     0000000 0d 00 00 00 00 00 00 00  >........<
0000010 6e 69 78 2d 61 72 63 68  >nix-arch<     0000010 6e 69 78 2d 61 72 63 68  >nix-arch<
0000020 69 76 65 2d 31 00 00 00  >ive-1...<     0000020 69 76 65 2d 31 00 00 00  >ive-1...<
0000030 01 00 00 00 00 00 00 00  >........<     0000030 01 00 00 00 00 00 00 00  >........<
0000040 28 00 00 00 00 00 00 00  >(.......<     0000040 28 00 00 00 00 00 00 00  >(.......<
0000050 04 00 00 00 00 00 00 00  >........<     0000050 04 00 00 00 00 00 00 00  >........<
0000060 74 79 70 65 00 00 00 00  >type....<     0000060 74 79 70 65 00 00 00 00  >type....<
0000070 07 00 00 00 00 00 00 00  >........<     0000070 07 00 00 00 00 00 00 00  >........<
0000100 72 65 67 75 6c 61 72 00  >regular.<     0000100 72 65 67 75 6c 61 72 00  >regular.<
0000110 08 00 00 00 00 00 00 00  >........<     0000110 08 00 00 00 00 00 00 00  >........<
0000120 63 6f 6e 74 65 6e 74 73  >contents<     0000120 63 6f 6e 74 65 6e 74 73  >contents<
0000130 0d 00 00 00 00 00 00 00  >........<     0000130 0d 00 00 00 00 00 00 00  >........<
0000140 48 65 6c 6c 6f 2c 20 57  >Hello, W<     0000140 48 65 6c 6c 6f 2c 20 57  >Hello, W<
0000150 6f 72 6c 64 0a 00 00 00  >orld....<     0000150 6f 72 6c 64 0a 00 00 00  >orld....<
0000160 01 00 00 00 00 00 00 00  >........<     0000160 01 00 00 00 00 00 00 00  >........<
0000170 29 00 00 00 00 00 00 00  >).......<     0000170 29 00 00 00 00 00 00 00  >).......<
0000200 0000200
```

## output pathからderivationを引く

runtime dependenciesを出力するための前準備。

output pathからderivationを引く方法として、公式的には`nix-store --query --deriver`コマンドを用いる方法がある。しかし、そもそもoutput pathはderivationの諸々の情報を使いハッシュ化して作成されたものである。ハッシュの不可逆性により、逆にoutput pathから直接導出することは不可能のはずである。

ではNixではどうやってこれを行っているのかというと、別に`/nix/store/`を全探索とかしている訳ではない。実は`/nix/var/nix/db/db.sqlite`にSQLiteのDBがあり、そこにいろいろな情報を保管している。このDBはNix内部で用いるものであり、情報がほとんどないのだが、一応[Glossaly](https://nixos.org/manual/nix/stable/glossary#gloss-nix-database)や[Local Store](https://nixos.org/manual/nix/stable/store/types/local-store)の説明から、その存在だけは確認できる。

そこからどうやってSQL文を叩けばoutput pathからderivationが引けるのかというと、少なくともNix 2.21.1の状況では
* [nix-store --query --deriverの呼び出し場所](https://github.com/NixOS/nix/blob/2.21.1/src/nix-store/nix-store.cc#L381)：queryPathInfoで返ってきた値からderiverを取り出している
* [QueryPathInfoのSQL文](https://github.com/NixOS/nix/blob/2.21.1/src/libstore/local-store.cc#L384)

から分かる。要するに、`ValidPaths`というテーブルを`path`で引いて、`deriver`のカラムを取り出せばよい。SQL文的には
```sql
select deriver from ValidPaths where path = '<output path>';
```

となる。

実際にPythonコードにすると、mainも含め以下のようになる。

```python
import sqlite3
import sys

def get_deriver(conn: sqlite3.Connection, out_path: str):
    cur = conn.cursor()
    cur.execute('select deriver from ValidPaths where path = ?', (out_path, ))
    for row in cur:
        return row[0]
    raise ValueError("Deriver is not found")

if __name__ == "__main__":
    with sqlite3.connect("file:///nix/var/nix/db/db.sqlite?immutable=1", uri=True) as conn:
        print(get_deriver(conn, sys.argv[1]))
```


実行例。symlink先のパスの判定とかは特にやってないため、`which ls`を`dump.py`の引数に埋め込んでも動作しないことに注意。
```console
bombrary@nixos:~/deps$ realpath `which ls`
/nix/store/03167shkax5dxclnv6r3sd8waa6lq7ny-coreutils-full-9.3/bin/coreutils

bombrary@nixos:~/deps$ nix run nixpkgs#python3 -- dump.py /nix/store/03167shkax5dxclnv6r3sd8waa6lq7ny-coreutils-full-9.3
/nix/store/g0kqr7b99b70kb10vmqg10vkj9nfk7zm-coreutils-full-9.3.drv
```

## パッケージの直接的・間接的なruntime dependenciesをすべて知る

今まで書いたコードを総動員して、あるパッケージのruntime dependenciesを再帰的に探索するコードが書ける。

```python
OUT_CACHE = set()

def dump_runtime_deps(out_path: str) -> Tree:
    res = {}
    nar = archiveNAR(out_path)
    for drv in DRV_CACHE.values():
        # NARに埋め込まれているout_pathを取り出す
        paths = [ out_path for _, out_path, _, _ in drv[0] if out_path.encode('ascii') in nar ]
        for path in paths:
            if  path not in OUT_CACHE:
                OUT_CACHE.add(out_path)
                res[path] = dump_runtime_deps(path)
            else:
                res[path] = ": cached"
    return res

if __name__ == "__main__":
    with sqlite3.connect("file:///nix/var/nix/db/db.sqlite?immutable=1", uri=True) as conn:
        out_path = sys.argv[1]
        drv_path = get_deriver(conn, out_path)
        _ = dump_build_deps(drv_path) # DRV_CACHEを事前に生成
        del(DRV_CACHE[drv_path]) # 出力が冗長になるので自身のdrvは削除しておく
        tree = dump_runtime_deps(out_path)
        show_tree(tree, True, "")
```

実行結果は、`nix-store --query --requisites`ないし`nix-store --query --tree`のものと同じである。

```console
bombrary@nixos:~/deps$ OUT_PATH=/nix/store/03167shkax5dxclnv6r3sd8waa6lq7ny-coreutils-full-9.3
bombrary@nixos:~/deps$ nix run nixpkgs#python3 -- dump.py $OUT_PATH
├──/nix/store/j6mwswpa6zqhdm1lm2lv9iix3arn774g-glibc-2.38-27
│  ├──/nix/store/fhws3x2s9j5932r6ah660nsh41bkrq27-xgcc-12.3.0-libgcc
│  ├──/nix/store/j6mwswpa6zqhdm1lm2lv9iix3arn774g-glibc-2.38-27: cached
│  └──/nix/store/4h5isrbr87jjw69rgdnhi8psi7hhk5im-libidn2-2.3.4
│     ├──/nix/store/4h5isrbr87jjw69rgdnhi8psi7hhk5im-libidn2-2.3.4
│     │  ├──/nix/store/4h5isrbr87jjw69rgdnhi8psi7hhk5im-libidn2-2.3.4: cached
│     │  └──/nix/store/80dld61hbpvy1ay1sdwaqyy4jzhm48xx-libunistring-1.1
│     │     └──/nix/store/80dld61hbpvy1ay1sdwaqyy4jzhm48xx-libunistring-1.1
│     │        └──/nix/store/80dld61hbpvy1ay1sdwaqyy4jzhm48xx-libunistring-1.1: cached
│     └──/nix/store/80dld61hbpvy1ay1sdwaqyy4jzhm48xx-libunistring-1.1: cached
├──/nix/store/idwlqkj1z2cgjcijgnnxgyp0zgzpv7c5-attr-2.5.1
│  ├──/nix/store/j6mwswpa6zqhdm1lm2lv9iix3arn774g-glibc-2.38-27: cached
│  └──/nix/store/idwlqkj1z2cgjcijgnnxgyp0zgzpv7c5-attr-2.5.1
│     ├──/nix/store/j6mwswpa6zqhdm1lm2lv9iix3arn774g-glibc-2.38-27: cached
│     └──/nix/store/idwlqkj1z2cgjcijgnnxgyp0zgzpv7c5-attr-2.5.1: cached
├──/nix/store/wmsmw09x6l3kcl4ng3qs3ircj8h73si3-acl-2.3.1
│  ├──/nix/store/j6mwswpa6zqhdm1lm2lv9iix3arn774g-glibc-2.38-27: cached
│  ├──/nix/store/idwlqkj1z2cgjcijgnnxgyp0zgzpv7c5-attr-2.5.1: cached
│  └──/nix/store/wmsmw09x6l3kcl4ng3qs3ircj8h73si3-acl-2.3.1
│     ├──/nix/store/j6mwswpa6zqhdm1lm2lv9iix3arn774g-glibc-2.38-27: cached
│     ├──/nix/store/idwlqkj1z2cgjcijgnnxgyp0zgzpv7c5-attr-2.5.1: cached
│     └──/nix/store/wmsmw09x6l3kcl4ng3qs3ircj8h73si3-acl-2.3.1: cached
├──/nix/store/9vv53vzx4k988d51xfiq2p46fqrjshv0-gmp-with-cxx-6.3.0
│  ├──/nix/store/giyri337jb6sa1qyff6qp771qfq10yhf-gcc-12.3.0-lib
│  │  ├──/nix/store/giyri337jb6sa1qyff6qp771qfq10yhf-gcc-12.3.0-lib
│  │  │  ├──/nix/store/giyri337jb6sa1qyff6qp771qfq10yhf-gcc-12.3.0-lib: cached
│  │  │  ├──/nix/store/iyw6mm7a75i49h9szc0m08ynay1p7kka-gcc-12.3.0-libgcc
│  │  │  └──/nix/store/j6mwswpa6zqhdm1lm2lv9iix3arn774g-glibc-2.38-27: cached
│  │  ├──/nix/store/iyw6mm7a75i49h9szc0m08ynay1p7kka-gcc-12.3.0-libgcc
│  │  └──/nix/store/j6mwswpa6zqhdm1lm2lv9iix3arn774g-glibc-2.38-27: cached
│  ├──/nix/store/j6mwswpa6zqhdm1lm2lv9iix3arn774g-glibc-2.38-27: cached
│  └──/nix/store/9vv53vzx4k988d51xfiq2p46fqrjshv0-gmp-with-cxx-6.3.0: cached
└──/nix/store/l0rxwrg41k3lsdiybf8q0rf3nk430zr8-openssl-3.0.12
   ├──/nix/store/j6mwswpa6zqhdm1lm2lv9iix3arn774g-glibc-2.38-27: cached
   └──/nix/store/l0rxwrg41k3lsdiybf8q0rf3nk430zr8-openssl-3.0.12
      ├──/nix/store/j6mwswpa6zqhdm1lm2lv9iix3arn774g-glibc-2.38-27: cached
      └──/nix/store/l0rxwrg41k3lsdiybf8q0rf3nk430zr8-openssl-3.0.12: cached
```
