---
title: "NixOSでmatplotlibを使いグラフを表示する - uvを使う & 共有ライブラリとoverlayの話"
date: 2024-09-16T22:20:00+09:00
tags: ["Python", "matplotlib", "pyplot", "LD_LIBRARY_PATH", "overlay"]
categories: ["NixOS"]
---

## 要約

ここではNixOSとPythonとmatplotlibでグラフを出力するための方法を記載する。

グラフを表示するケースとして以下の2つのケースを考える。
* （パターン1）NixだけでPythonのパッケージ管理をする方法
* （パターン2）[astral-sh/uv](https://github.com/astral-sh/uv)でPythonのパッケージ管理をする方法

前者はあっさり終わるが、後者はすんなり動かないので工夫が必要。具体的には以下の工夫がいる。
* 共有ライブラリのパスが解決できずエラーになる： uvが外部から持ってきたライブラリにプリコンパイルされたCの共有ライブラリファイルがあるため。`LD_LIBRARY_PATH` の指定をする必要がある
* tkinterのモジュールが解決できず、グラフが出力されない：nixpkgsに入っているPythonのデフォルトにはtkinterがついてないため。overlayとoverrideを使い、tkinter入りのPythonを用意する

NixOSでほかのLinuxディストリビューションと同じようなことをしようとするとひと手間必要という良い例かも。

なお、今回紹介するのはあくまで Nix**OS** 上での例である。例えばNixOSでないほかのOSでNixパッケージマネージャだけ導入しているようなケースでは、（環境によるが）パターン2は特に工夫なく動くかもしれない。

また、今回使うuvは0.4.8である。uvは開発が早いので、数か月後にはこの記事通りに動かなくなってるかも。
```console
[bombrary@nixos:~/example]$ uv --version
uv 0.4.8
```


## （パターン1）Nixを用いたパッケージ管理例

はじめに、`flake.nix` ファイルを作る。

```console
[bombrary@nixos:~/example]$ nix flake init
wrote: /home/bombrary/example/flake.nix
```

以下のような `flake.nix` を書く。[python.withPackages](https://nixos.org/manual/nixpkgs/stable/#python.withpackages-function)を使うことで、特定のパッケージが入ったPythonを作ることができる（イメージ的には、venvと同じものを `/nix/store/` で管理する感じ）。
```nix
{
  description = "A very basic flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
  };

  outputs = { self, nixpkgs }:
  let
    pkgs = nixpkgs.legacyPackages.x86_64-linux;
    my-python = pkgs.python312.withPackages (python-pkgs: [
      python-pkgs.matplotlib
    ]);
  in
  {
    devShells.x86_64-linux.default = pkgs.mkShell {
      packages = with pkgs; [
        my-python
      ];
    };
  };
}
```

`nix develop` して、上記で定義したPython環境が使える状態にする。
```console
[bombrary@nixos:~/example]$ nix develop
```

Pythonが入っているディレクトリの周辺を探ってみると、同パッケージディレクトリの `/lib/python3.12/site-packages` ディレクトリにmatplotlibが確かにあることがわかる。
```console
[bombrary@nixos:~]$ which python
/nix/store/fm0p1f5fl4pvb06y07zpivsqx4rlyq2z-python3-3.12.5-env/bin/python

[bombrary@nixos:~]$ ls /nix/store/fm0p1f5fl4pvb06y07zpivsqx4rlyq2z-python3-3.12.5-env/lib/python3.12/site-packages/
contourpy                  defusedxml                     kiwisolver-1.4.5.dist-info  numpy-1.26.4.dist-info    PIL                      pyparsing-3.1.2.dist-info              six.py
contourpy-1.2.1.dist-info  defusedxml-0.8.0rc2.dist-info  matplotlib                  olefile                   pillow-10.4.0.dist-info  python_dateutil-2.9.0.post0.dist-info  _sysconfigdata__linux_x86_64-linux-gnu.py
cycler                     fontTools                      matplotlib-3.9.1.dist-info  olefile-0.47.dist-info    __pycache__              README.txt                             _tkinter.cpython-312-x86_64-linux-gnu.so
cycler-0.12.1.dist-info    fonttools-4.53.1.dist-info     mpl_toolkits                packaging                 pylab.py                 sitecustomize.py
dateutil                   kiwisolver                     numpy                       packaging-24.1.dist-info  pyparsing                six-1.16.0.dist-info
```

試しにグラフを出力してみよう。以下のコードを `main.py` として保存する。
```python3
import matplotlib
from matplotlib import pyplot as plt

fig, ax = plt.subplots()
ax.plot([1,2,3], [1,2,3])
plt.show()
```

以下で `main.py` を実行すると、グラフが出力される。
```console
[bombrary@nixos:~/example]$ python main.py
```

## （パターン2）uvを用いたパッケージ管理例

NixでPythonのパッケージの管理はせず、別のツールで管理したい人もいるかもしれない。ここではuvを用いる状況を想定する。

この場合、以下の課題が存在する。
* 共有ライブラリが見つからない問題：NumPyなどはCでプリコンパイルされたバイナリを持ってるので、それが外部の共有ライブラリを要求し見つからずエラーになる
* tkinterが見つからない問題：nixpkgsで提供されているデフォルトのPythonにはtkinterが付属していないので、付属済みのPythonを用意する必要がある

次の作業のために、先ほどの `nix develop` からは抜けておく。

### 共有ライブラリが見つからない問題：LD_LIBRARY_PATHの話

#### 共有ライブラリが見つからないエラー

続いて、以下のようにuvだけ導入した状態にする。
```nix
{
  description = "A very basic flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
  };

  outputs = { self, nixpkgs }:
  let
    pkgs = nixpkgs.legacyPackages.x86_64-linux;
  in
  {
    devShells.x86_64-linux.default = pkgs.mkShell {
      packages = with pkgs; [
        uv
      ];
    };
  };
}
```

`nix develop` で uv が入ったシェルに入り、プロジェクトの初期化とmatplotlibの導入を行う。
```console
[bombrary@nixos:~/example]$ nix develop

[bombrary@nixos:~/example]$ uv init
Initialized project `example`

[bombrary@nixos:~/example]$ uv add matplotlib
Using Python 3.12.5 interpreter at: /nix/store/h3i0acpmr8mrjx07519xxmidv8mpax4y-python3-3.12.5/bin/python3.12
Creating virtualenv at: .venv
Resolved 12 packages in 244ms
Prepared 11 packages in 669ms
Installed 11 packages in 21ms
 + contourpy==1.3.0
 + cycler==0.12.1
 + fonttools==4.53.1
 + kiwisolver==1.4.7
 + matplotlib==3.9.2
 + numpy==2.1.1
 + packaging==24.1
 + pillow==10.4.0
 + pyparsing==3.1.4
 + python-dateutil==2.9.0.post0
 + six==1.16.0
```

ところが、uv経由で `main.py` を実行しようとすると、次のエラーが出力される。
```console
[bombrary@nixos:~/example]$ uv run python main.py
Traceback (most recent call last):
  File "/home/bombrary/example/.venv/lib/python3.12/site-packages/numpy/_core/__init__.py", line 23, in <module>
    from . import multiarray
  File "/home/bombrary/example/.venv/lib/python3.12/site-packages/numpy/_core/multiarray.py", line 10, in <module>
    from . import overrides
  File "/home/bombrary/example/.venv/lib/python3.12/site-packages/numpy/_core/overrides.py", line 8, in <module>
    from numpy._core._multiarray_umath import (
ImportError: libstdc++.so.6: cannot open shared object file: No such file or directory

During handling of the above exception, another exception occurred:

Traceback (most recent call last):
  File "/home/bombrary/example/.venv/lib/python3.12/site-packages/numpy/__init__.py", line 114, in <module>
    from numpy.__config__ import show as show_config
  File "/home/bombrary/example/.venv/lib/python3.12/site-packages/numpy/__config__.py", line 4, in <module>
    from numpy._core._multiarray_umath import (
  File "/home/bombrary/example/.venv/lib/python3.12/site-packages/numpy/_core/__init__.py", line 49, in <module>
    raise ImportError(msg)
ImportError:

IMPORTANT: PLEASE READ THIS FOR ADVICE ON HOW TO SOLVE THIS ISSUE!

Importing the numpy C-extensions failed. This error can happen for
many reasons, often due to issues with your setup or how NumPy was
installed.

We have compiled some common reasons and troubleshooting tips at:

    https://numpy.org/devdocs/user/troubleshooting-importerror.html

Please note and check the following:

  * The Python version is: Python3.12 from "/home/bombrary/example/.venv/bin/python3"
  * The NumPy version is: "2.1.1"

and make sure that they are the versions you expect.
Please carefully study the documentation linked above for further help.

Original error was: libstdc++.so.6: cannot open shared object file: No such file or directory


The above exception was the direct cause of the following exception:

Traceback (most recent call last):
  File "/home/bombrary/example/main.py", line 1, in <module>
    import matplotlib
  File "/home/bombrary/example/.venv/lib/python3.12/site-packages/matplotlib/__init__.py", line 159, in <module>
    from . import _api, _version, cbook, _docstring, rcsetup
  File "/home/bombrary/example/.venv/lib/python3.12/site-packages/matplotlib/cbook.py", line 24, in <module>
    import numpy as np
  File "/home/bombrary/example/.venv/lib/python3.12/site-packages/numpy/__init__.py", line 119, in <module>
    raise ImportError(msg) from e
ImportError: Error importing numpy: you should not try to import numpy from
        its source directory; please exit the numpy source tree, and relaunch
        your python interpreter from there.
```

エラーの内容を見てみると、どうやらNumPyが裏で読まれ、その際に `libstdc++.so.6` が無くてエラーが出ているらしい。
NumPyは一部がCで書かれているため （[参考](https://numpy.org/doc/stable/user/whatisnumpy.html#why-is-numpy-fast)）、いくつかの構成ファイルはPythonコードではなく、Cでコンパイルされた共有ライブラリである。これらが`libstdc++.so.6`を要求しているが、そのパスが解決できずエラーになっている。普通このファイルは `/lib/` 配下にはるはずだが、NixOSはビルドの再現性の担保のために `/lib/` を捨てているのでこのような状況になっている。

```console
[bombrary@nixos:~/example]$ ldd ./.venv/lib/python3.12/site-packages/numpy/_core/_multiarray_umath.cpython-312-x86_64-linux-gnu.so
        linux-vdso.so.1 (0x00007fff3fffe000)
        libscipy_openblas64_-ff651d7f.so => /home/bombrary/example/./.venv/lib/python3.12/site-packages/numpy/_core/../../numpy.libs/libscipy_openblas64_-ff651d7f.so (0x00007f5d6da00000)
        libstdc++.so.6 => not found
        libm.so.6 => /nix/store/r8qsxm85rlxzdac7988psm7gimg4dl3q-glibc-2.39-52/lib/libm.so.6 (0x00007f5d6ef1d000)
        libgcc_s.so.1 => /nix/store/k8aiaw3mslh4120lah1ssg3r6xa46cz1-xgcc-13.2.0-libgcc/lib/libgcc_s.so.1 (0x00007f5d6eef8000)
        libc.so.6 => /nix/store/r8qsxm85rlxzdac7988psm7gimg4dl3q-glibc-2.39-52/lib/libc.so.6 (0x00007f5d6d813000)
        /nix/store/r8qsxm85rlxzdac7988psm7gimg4dl3q-glibc-2.39-52/lib64/ld-linux-x86-64.so.2 (0x00007f5d6f9b3000)
        libpthread.so.0 => /nix/store/r8qsxm85rlxzdac7988psm7gimg4dl3q-glibc-2.39-52/lib/libpthread.so.0 (0x00007f5d6f9aa000)
        libgfortran-040039e1-0352e75f.so.5.0.0 => /home/bombrary/example/./.venv/lib/python3.12/site-packages/numpy/_core/../../numpy.libs/libgfortran-040039e1-0352e75f.so.5.0.0 (0x00007f5d6d200000)
        libquadmath-96973f99-934c22de.so.0.0.0 => /home/bombrary/example/./.venv/lib/python3.12/site-packages/numpy/_core/../../numpy.libs/libquadmath-96973f99-934c22de.so.0.0.0 (0x00007f5d6ce00000)
        libz.so.1 => not found
```

ちなみに `/nix/store/...` をうまく解決できているやつがちょこちょこいるが、どうやって解決しているのかは `LD_DEBUG=files,libs` をつけて `ldd` を実行すると分かる。
```console
[bombrary@nixos:~/example]$ LD_DEBUG=files,libs ldd ./.venv/lib/python3.12/site-packages/numpy/_core/_multiarray_umath.cpython-312-x86_64-linux-gnu.so
     14590:
     14590:     file=libreadline.so.8 [0];  needed by /bin/sh [0]
     14590:     find library=libreadline.so.8 [0]; searching
     14590:      search path=/nix/store/zkmxm571ds0j8gzchb2dxs1hizmr10ad-ncurses-6.4/lib/glibc-hwcaps/x86-64-v3:/nix/store/zkmxm571ds0j8gzchb2dxs1hizmr10ad-ncurses-6.4/lib/glibc-hwcaps/x86-64-v2:/nix/store/zkmxm571ds0j8gzchb2dxs1hizmr10ad-ncurses-6.4/lib:/nix/store/x3axw06zyyw0dsabfgichjilqqs0i9vc-readline-8.2p10/lib/glibc-hwcaps/x86-64-v3:/nix/store/x3axw06zyyw0dsabfgichjilqqs0i9vc-readline-8.2p10/lib/glibc-hwcaps/x86-64-v2:/nix/store/x3axw06zyyw0dsabfgichjilqqs0i9vc-readline-8.2p10/lib              (RUNPATH from file /bin/sh)
     14590:       trying file=/nix/store/zkmxm571ds0j8gzchb2dxs1hizmr10ad-ncurses-6.4/lib/glibc-hwcaps/x86-64-v3/libreadline.so.8
...
```

ログ `(RUNPATH from file /bin/sh)` を見るに、どうやら `/bin/sh` のRUNPATHから取り出しているようだ。

#### LD_LIBRARY_PATHの設定

`libstdc++.so.6`のパスをどうにかして解決しなければいけない。 `patchelf --set-rpath` をやろうにも共有ライブラリの量が多すぎるので、ここでは`LD_LIBRARY_PATH`に設定する解決策を紹介する。 まず `libstcd++.so.6` の場所を把握する。探すと libgcc パッケージにあることがわかる。
```console
[bombrary@nixos:~/example]$ ls $(nix eval --raw 'nixpkgs#libgcc.lib')/lib/libstdc++.so.6
/nix/store/22nxhmsfcv2q2rpkmfvzwg2w5z1l231z-gcc-13.3.0-lib/lib/libstdc++.so.6
```

そこで、`flake.nix` を以下のようにして、 `nix develop` をやり直す。
* `pkgs.mkShell` の引数に指定した attribute は、環境変数として `nix develop` 後に設定される。そのため `LD_LIBRARY_PATH = ...` を設定すればこれが環境変数になる
* [lib.string.makeLibraryPath](https://nixos.org/manual/nixpkgs/stable/#function-library-lib.strings.makeLibraryPath) またはこれと同義の `lib.makeLibraryPath` で、パッケージの `/lib` へのパスをコロン `:` でつなげた文字列を生成する
```nix
{
  description = "A very basic flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
  };

  outputs = { self, nixpkgs }:
  let
    pkgs = nixpkgs.legacyPackages.x86_64-linux;
  in
  {
    devShells.x86_64-linux.default = pkgs.mkShell {
      packages = with pkgs; [
        uv
      ];
      LD_LIBRARY_PATH = pkgs.lib.makeLibraryPath (with pkgs; [
        libgcc.lib
      ]);
    };
  };
}
```

すると、 `LD_LIBRARY_PATH` にパスが設定されていることがわかる。
```console
[bombrary@nixos:~/example]$ echo $LD_LIBRARY_PATH
/nix/store/22nxhmsfcv2q2rpkmfvzwg2w5z1l231z-gcc-13.3.0-lib/lib
```

これで、共有ライブラリが解決できないというエラーはでなくなる。

### tkinterが見つからない問題：overlayの話

#### tkinterが見つからないエラー

共有ライブラリが解決できないエラーは無くなったが、代わりにWarningが出ており、matplotlibのウインドウは出現しない。

```console
[bombrary@nixos:~/example]$ uv run python main.py
/home/bombrary/example/main.py:6: UserWarning: FigureCanvasAgg is non-interactive, and thus cannot be shown
  plt.show()
```

tkinterが入っていればそれを用いてUIが作成されウインドウが出現されるはずである。試しに無理やりTkを使って出力させるよう、Pythonのコードに以下の一文を加える。
```python
import matplotlib
matplotlib.use("TkAgg")
```

すると、以下のエラーが出る。どうやらtkinterが入ってないらしい。
```console
  File "/home/bombrary/example/.venv/lib/python3.12/site-packages/matplotlib/backends/backend_tkagg.py", line 1, in <module>
    from . import _backend_tk
  File "/home/bombrary/example/.venv/lib/python3.12/site-packages/matplotlib/backends/_backend_tk.py", line 9, in <module>
    import tkinter as tk
  File "/nix/store/h3i0acpmr8mrjx07519xxmidv8mpax4y-python3-3.12.5/lib/python3.12/tkinter/__init__.py", line 38, in <module>
    import _tkinter # If this fails your Python may not be configured for Tk
    ^^^^^^^^^^^^^^^
ModuleNotFoundError: No module named '_tkinter'
```

そもそもuvから動くPythonはいったい何者なのだろうか？ これは `uv python list` コマンドで確認できる。どうやら `/nix/store/` にあるPythonを参照しているようだ。つまりnixpkgs上で管理されているPythonである。
```console
[bombrary@nixos:~/example]$ uv python list
cpython-3.12.5-linux-x86_64-gnu     /nix/store/h3i0acpmr8mrjx07519xxmidv8mpax4y-python3-3.12.5/bin/python3.12
cpython-3.12.5-linux-x86_64-gnu     /nix/store/h3i0acpmr8mrjx07519xxmidv8mpax4y-python3-3.12.5/bin/python3 -> python3.12
cpython-3.12.5-linux-x86_64-gnu     /nix/store/h3i0acpmr8mrjx07519xxmidv8mpax4y-python3-3.12.5/bin/python -> python3.12
cpython-3.12.5-linux-x86_64-gnu     <download available>
cpython-3.11.9-linux-x86_64-gnu     <download available>
...
```

uvでは、Pythonを `PATH` 環境変数から探す。そして[uvのderivation](https://github.com/NixOS/nixpkgs/blob/345c263f2f53a3710abe117f28a5cb86d0ba4059/pkgs/by-name/uv/uv/package.nix#L17)では`python3Packages.buildPythonApplication`が使われているため、`nix develop` 実行時にそのパスが `PATH` 環境変数に指定され、標準でPythonのバイナリが認識できるような状態になっている。

そして、そのPythonについて [nixpkgsのドキュメント](https://nixos.org/manual/nixpkgs/stable/#missing-tkinter-module-standard-library) に書かれているが、tkinterは標準で入っていない。そのため、tkinter入りのPythonを自分で作ってuvが参照するPythonを書き換える必要がある。

#### overlayとoverrideを用いたパッケージの追加・書き換え

そこで、tkinterがサポートされたPythonを追加し、それをuvに設定しよう。以下のようにする。nixpkgsの [overlay](https://nixos.wiki/wiki/Overlays) の仕組みを使えば、nixpkgsにパッケージを追加したり、パラメータを変更したりすることができる。具体的には以下を行う。
* nixpkgsに新しい `my-python` というパッケージを追加し、x11のサポートを有効にする
* nixpkgsにある `uv` パッケージのパラメータ `python3Packages` を、 `my-python` のパッケージに変更する
```nix
{
  description = "A very basic flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
  };

  outputs = { self, nixpkgs }:
  let
    pkgs = nixpkgs.legacyPackages.x86_64-linux.extend
      (final: prev: {
        my-python312 = prev.python312.override { self = final.my-python; x11Support = true; };
        uv = (prev.uv.override { python3Packages = final.my-python.pkgs; });
      });
  in
  {
    devShells.x86_64-linux.default = pkgs.mkShell {
      packages = with pkgs; [
        uv

      ];
      LD_LIBRARY_PATH = pkgs.lib.makeLibraryPath (with pkgs; [
        libgcc.lib
      ]);

    };
  };
}
```

これで uv は、x11がサポートされたPythonである `my-python` を認識するようになる。ハッシュ値が変わったのがわかるだろう。
```console
[bombrary@nixos:~/example]$ uv python list
cpython-3.12.5-linux-x86_64-gnu     /nix/store/lmh3qxw8gr8kr2nz3094id5kk446mdhf-python3-3.12.5/bin/python3.12
cpython-3.12.5-linux-x86_64-gnu     /nix/store/lmh3qxw8gr8kr2nz3094id5kk446mdhf-python3-3.12.5/bin/python3 -> python3.12
cpython-3.12.5-linux-x86_64-gnu     /nix/store/lmh3qxw8gr8kr2nz3094id5kk446mdhf-python3-3.12.5/bin/python -> python3.12
cpython-3.12.5-linux-x86_64-gnu     <download available>
```

既存の `.venv` を消して `main.py` を再実行すると、グラフが出力される。
```console
[bombrary@nixos:~/example]$ rm -rf .venv

[bombrary@nixos:~/example]$ uv run python main.py
Using Python 3.12.5 interpreter at: /nix/store/lmh3qxw8gr8kr2nz3094id5kk446mdhf-python3-3.12.5/bin/python3.12
Creating virtualenv at: .venv
Installed 11 packages in 26ms
```

この方法の欠点は、`nix develop` の初回はuvの再ビルドが行われてしまう点。ビルドには、少なくとも自分の環境だと5分程度かかった。

なお、別バージョンのPythonも使えるようにしたい場合は、次のようにする。
```nix
{
  description = "A very basic flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
  };

  outputs = { self, nixpkgs }:
  let
    pkgs = nixpkgs.legacyPackages.x86_64-linux.extend
      (final: prev: {
        my-python312 = prev.python312.override { self = final.my-python312; x11Support = true; };
        my-python311 = prev.python311.override { self = final.my-python311; x11Support = true; };
        uv = (prev.uv.override { python3Packages = final.my-python312.pkgs; });
      });
  in
  {
    devShells.x86_64-linux.default = pkgs.mkShell {
      packages = with pkgs; [
        uv
        my-python311
      ];
      LD_LIBRARY_PATH = pkgs.lib.makeLibraryPath (with pkgs; [
        libgcc.lib
      ]);
    };
  };
}
```

```console
[bombrary@nixos:~/example]$ uv python list
cpython-3.12.5-linux-x86_64-gnu     /nix/store/lmh3qxw8gr8kr2nz3094id5kk446mdhf-python3-3.12.5/bin/python3.12
cpython-3.12.5-linux-x86_64-gnu     /nix/store/lmh3qxw8gr8kr2nz3094id5kk446mdhf-python3-3.12.5/bin/python3 -> python3.12
cpython-3.12.5-linux-x86_64-gnu     /nix/store/lmh3qxw8gr8kr2nz3094id5kk446mdhf-python3-3.12.5/bin/python -> python3.12
cpython-3.12.5-linux-x86_64-gnu     <download available>
cpython-3.11.9-linux-x86_64-gnu     /nix/store/ycjcblkvvbrhsm2rvmj4d6ddp7a13mh1-python3-3.11.9/bin/python3.11
cpython-3.11.9-linux-x86_64-gnu     /nix/store/ycjcblkvvbrhsm2rvmj4d6ddp7a13mh1-python3-3.11.9/bin/python3 -> python3.11
cpython-3.11.9-linux-x86_64-gnu     /nix/store/ycjcblkvvbrhsm2rvmj4d6ddp7a13mh1-python3-3.11.9/bin/python -> python3.11
cpython-3.11.9-linux-x86_64-gnu     <download available>
cpython-3.10.14-linux-x86_64-gnu    <download available>
cpython-3.9.19-linux-x86_64-gnu     <download available>
cpython-3.8.19-linux-x86_64-gnu     <download available>
cpython-3.7.9-linux-x86_64-gnu      <download available>
pypy-3.10.14-linux-x86_64-gnu       <download available>
pypy-3.9.19-linux-x86_64-gnu        <download available>
pypy-3.8.16-linux-x86_64-gnu        <download available>
pypy-3.7.13-linux-x86_64-gnu        <download available>
```

なお、今回はx11をサポートするオプションだけを追加した `my-python311` と `my-python312` を自前で用意したが、代わりにほかのオプションが全部有効になっているバージョンの `python311Full` 、 `python312Full` を使ってもよい（サイズは大きいだろうが、何か開発するうえで必要なパッケージが足りないなどの余計なトラブルが少なく開発できるかも）。

## まとめ

NixOS上でmatplotlibを使いグラフを出力する方法として、Nix単体で完結する方法と、uvを使った方法の2つを紹介した。前者はあっさりできるが、後者は共有ライブラリの設定やPythonの用意が必要であった。

そもそもNixは `/nix/store/` 上であらゆるコンテンツを管理するよう作られているので、nixファイルを使わずパッケージを管理することはNixの思想から外れているのだろう。なのでそれを無理に動かそうとすると工夫が必要なのは仕方ないのかも、と思った。とはいえケースによっては使いたいときもあるだろうから、その方法を模索することは無駄ではないと思う。

しかし、（もちろんユーザの習熟度にもよるが）普段ユーザがあまり気にしないであろう共有ライブラリの話やNixのoverlayの話が出てくるのはなかなか厄介だなと感じた。自分はただPythonでグラフが描きたいだけなのに、なぜ共有ライブラリとかNixについてを学ばなくてはいけないのだ、みたいな人は少なからずいるのかも…。いや、NixOSを使う人でそんなライトなユーザはあまりいないのだろうか…？


## （おまけ：リモートからやる場合）NixOSのXForwardingの設定

NixOSのデスクトップ環境を直接操作したり、WSL上のNixOSで作業したりする場合は不要だが、リモート上にNixOSがありそこにSSHしてグラフを出力したい場合は、X11 の設定をする必要がある。

X11 の設定をするため、当然だがSSH接続元でXServerが動いている必要がある。最近のWSLなら [標準でX11のサーバーが動いているっぽい](https://learn.microsoft.com/ja-jp/windows/wsl/tutorials/gui-apps)。

`configuration.nix` に以下を追記する。 `services.openssh.settings.X11Forwarding = true` を追記している。
```nix
services.openssh = {
  enable = true;
  settings = {
    X11Forwarding = true;
  };
};
```

これでNixOSを再ビルドすると、 `/etc/ssh/sshd_config` に `X11Forwarding yes` が追加されていることがわかる。
```console
[bombrary@nixos:~]$ sudo nixos-rebuild switch

[bombrary@nixos:~]$ cat /etc/ssh/sshd_config | grep X11Forwarding
X11Forwarding yes
```

いったん再ログインして、xeyesコマンドを実行し、ウインドウが接続元で出力されれば成功。
```console
at 19:40:22 ❯ ssh -Y bombrary@192.168.11.11
(bombrary@192.168.11.11) Password:
Warning: No xauth data; using fake authentication data for X11 forwarding.
Last login: Sun Sep 15 19:10:40 2024 from 192.168.11.6

[bombrary@nixos:~]$ nix run 'nixpkgs#xorg.xeyes'
```
