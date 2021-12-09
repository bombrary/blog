---
title: "neovimのプラグインがうまく動かなかったので原因を探した話"
date: 2021-10-01T09:19:20+09:00
draft: true
tags: []
categories: ["vim"]
toc: true
---


## 以下の文章のまとめ

**バージョン違いには注意する**

ddc-nvim-lspは2021/10/1時点では、neovim 0.5.0を想定して作られているプラグインである。しかし自分はneovim 0.5.1を使ってしまっていた。neovim 0.5.1からlsp handlerの引数に破壊的変更があったため、LSPの補完が効かなかった。

究明に当たってDockerを触ったり、Luaを触ったり、ドキュメントを漁ったりして色々糧にはなったので、記録しておく。

## 何が起きたのか

まず、プラグインの管理には[Shougo/dein.vim](https://github.com/Shougo/dein.vim)を使った。

neovimのbuildin LSPを使ってLSPが使える環境を構築した。設定に当たって以下のプラグインを導入した。

- [neovim/nvim-lspconfig](https://github.com/neovim/nvim-lspconfig)

入力補完は[Shougo/ddc.vim](https://github.com/Shougo/ddc.vim)を使った。それにあたって以下のプラグインを導入した。

- [vim-denops/denops.vim](https://github.com/vim-denops/denops.vim): ddc.vimがDenoの機能を使うため必要。
- [Shougo/ddc-matcher_head](https://github.com/Shougo/ddc-matcher_head)
- [Shougo/ddc-sorter_rank](https://github.com/Shougo/ddc-sorter_rank)
- [Shougo/ddc-around](https://github.com/Shougo/ddc-around)
- [Shougo/ddc-nvim-lsp](https://github.com/Shougo/ddc-nvim-lsp)

最後のddc-nvim-lspがうまく動かなかった．

Language Serverとして[pyright](https://github.com/microsoft/pyright)を導入したのだが、実際にPythonのファイルで入力補完を試したところ，ddc-aroundの補完は反応するが，ddc-nvim-lspの補完候補が現れなかった。

## Dockerを使って再現性を検証する

まず、

- 何か他のプラグインが邪魔しているのではないか
- Macという環境だから問題なのだろうか

という仮説を立てた。そのためには、何も無い素のneovimの環境を作る必要があると考えた。そこで、環境をDockerで構築しようと考えた。

### Docker環境の構築

適当なディレクトリを作って、そこに`Dockerfile`と`docker-compose.yml`を作成する。

`Dockerfile`を以下のようにする。ベースイメージは[anatolelucet/neovim](https://hub.docker.com/r/anatolelucet/neovim)にした。この時点でdeinを導入する。コマンドは[deinのQuick start](https://github.com/Shougo/dein.vim#quick-start)を参照した。deinのインストールにあたって`curl`、`git`コマンドが必要なので、ここで導入する。

```Dockerfile
FROM anatolelucet/neovim:stable-ubuntu
RUN apt-get update && apt-get install -y curl git
RUN curl https://raw.githubusercontent.com/Shougo/dein.vim/master/bin/installer.sh > installer.sh && sh ./installer.sh ~/.cache/dein
```

neovimの設定ファイルはコンテナ外で編集できるようにしておく。同ディレクトリにディレクトリ`.config/nvim/`を作成し、その上で、`docker-compose.yml`を以下のようにする。

```yaml
version: '3'
services:
  nvim:
    build: .
    volumes:
      - .config:/root/.config
    entrypoint: 'bash'
    working_dir: /root
```

`.config/nvim/`の中に`init.vim`、`dein.toml'、'dein_lazy.toml`を作成。`init.vim`は以下の通り。

```vim
"dein Scripts-----------------------------
if &compatible
  set nocompatible               " Be iMproved
endif

" Required:
set runtimepath+=/root/.cache/dein/repos/github.com/Shougo/dein.vim

" Required:
call dein#begin('/root/.cache/dein')

" Let dein manage dein
" Required:
call dein#add('/root/.cache/dein/repos/github.com/Shougo/dein.vim')

let s:toml = '~/.config/nvim/dein.toml'
let s:lazy_toml = '~/.config/nvim/dein_lazy.toml'
call dein#load_toml(s:toml, {'lazy': 0})
call dein#load_toml(s:lazy_toml, {'lazy': 1})

" Required:
call dein#end()

" Required:
filetype plugin indent on
syntax enable

" If you want to install not installed plugins on startup.
if dein#check_install()
  call dein#install()
endif

"End dein Scripts-------------------------
```

`dein.toml`、`dein_lazy.toml`については長くなるため省略するが、必要なプラグインを導入する。

この時点で`docker-compose build`をすればコンテナがビルドされ、その後`docker-compose run nvim`でコンテナを実行する。

### コンテナ内での作業

Language Serverであるpyrightを導入する。pyrightの導入に当たって`python3`、`npm`、`node`が必要。aptコマンドだと古いバージョンしか入らないようだったので、
[NodeSourceのInstallation instructions](https://github.com/nodesource/distributions#installation-instructions)に従って最新のバージョンを入れる。

{{< cui >}}
# curl -fsSL https://deb.nodesource.com/setup_16.x | bash -
# apt-get install -y nodejs
{{< /cui >}}

[pyrightのCommand-line](https://github.com/microsoft/pyright#command-line)に従ってpyrightを導入する。

{{< cui >}}
# npm install -g pyright
{{< /cui >}}

続いて[DenoのInstallation](https://deno.land/#installation)に従ってDenoを導入する。

{{< cui >}}
# curl -fsSL https://deno.land/x/install/install.sh | sh
{{< /cui >}}

`deno`のパスを設定するため、`.bashrc`に以下の内容を追記する。その後、変更を反映させるために`source .bashrc`を実行。

```sh
export DENO_INSTALL="/root/.deno"
export PATH="$DENO_INSTALL/bin:$PATH"
```

### 動いた

これで`nvim main.py`を実行する。なんとこれでLanguage Serverの補完が効いた。

## コンテナの設定ファイルをホストに移すが、うまくいかない

うまくいった`init.vim`、`dein.toml`、`dein_lazy.toml`をホスト側に移して、うまくいくか試してみる。勿論バックアップは取っておく。
ところが、ホスト側では補完が効かなかった。

同じ設定ファイルなのにもかかわらず、コンテナとホストで違いが現れている。「それでは、Mac固有の問題なのだろうか」と考えた(**実はそうでないことは後々分かることになる**)。

「Mac固有の問題だとしても、どこでうまくいっていないのかを知りたい」と考えた。うまくいかない状況を以下の2つに分割して、まず前者について調査した。

- LSPサーバーとの通信がうまくいっていないのか
- LSPサーバーとの通信後の処理がうまくいっていないのか

以降、Dockerからは離れ、ホスト側で調査をする。

## Luaを触る

自前でLSPサーバーとの通信を行ってみて、正しい結果が帰ってくるかどうかをみることにした。neovimではこれをLuaのAPIとして提供している。Luaなんてほとんど書いたことは無いが、ddc-nvim-lspのソースコードから何をやっているのかを類推して、補完を取得する処理を読み出した。

Luaのスクリプトを実行する方法は`:h lua-commands`に書かれている。ここではLuaファイルに書いたものを実行したいので、`luafile`コマンドを使う。

### Luaファイルの内容

適当なLuaファイルを作成し、内容を以下のようにする。

```lua
function dump(o)
  if type(o) == 'table' then
    local tbl = {}
    for k,v in pairs(o) do
      table.insert(tbl, '"' .. tostring(k) .. '":' .. toJson(v))
    end
    return '{' .. table.concat(tbl, ',') .. '}'
  elseif type(o) == 'number' or type(o) == 'boolean' then
    return tostring(o)
  else
    return '"' .. tostring(o) .. '"'
  end
end

local f = function(_, result)
  print(dump(result['items']))
end


local params = vim.lsp.util.make_position_params()
vim.lsp.buf_request(0, 'textDocument/completion', params, f)
```

#### buf_request

LSPにリクエストを送るには`vim.lsp.buf_request`という関数を使えば良いらしい。ドキュメントから抜粋すると、引数の説明は以下の通り。

```txt
buf_request({bufnr}, {method}, {params}, {handler})
                Sends an async request for all active clients attached to the
                buffer.

                Parameters: ~
                    {bufnr}    (number) Buffer handle, or 0 for current.
                    {method}   (string) LSP method name
                    {params}   (optional, table) Parameters to send to the
                               server
                    {handler}  (optional, function) See |lsp-handler|
```

現在のバッファに対して補完情報のリクエストを送りたいので、`{bufnr}`には0を入れる。補完のリクエストなので、[LSPの仕様](https://microsoft.github.io/language-server-protocol/specification#textDocument_completion)より`{method}`には`textDocument/completion`を入れる。`{params}`には現在のカーソル位置の情報を入れたいが、これは`vim.lsp.util.make_position_params`関数でできる。

#### lsp-handler

`handler`にはいわゆるコールバック関数を指定する。関数の引数は`:h lsp-handler`で確認できる。以下、**neovim 0.5.1のドキュメント**から一部抜粋する。

```txt
lsp-handlers are functions with special signatures that are designed to handle
responses and notifications from LSP servers.

For |lsp-request|, each |lsp-handler| has this signature:

  function(err, result, ctx, config)

        Parameters: ~
            {err}       (table|nil)
                            When the language server is unable to complete a
                            request, a table with information about the error
                            is sent. Otherwise, it is `nil`. See |lsp-response|.
            {result}    (Result | Params | nil)
                            When the language server is able to succesfully
                            complete a request, this contains the `result` key
                            of the response. See |lsp-response|.
```

#### dump

handlerでの処理は、単にLSPから受け取った結果を出力することにした。table関数はそのままでは出力できないため、`dump`関数を書いた。これはtableをJSONっぽい形式で出力する関数。

### Luaファイルの実行

適当なPythonのファイルを作り、以下のように書く。

```python
"Hello".
```

補完の処理が正常に動作しているなら、ピリオドの後に文字列系の関数(`join`など)が補完候補として出てくるはずである。
そこで、ピリオドの部分にカーソルを持っていって、`luafile ファイル名`でLuaファイルを実行する。

すると、neovimのウインドウ下に以下の文が表示された。

```txt
{"1":{"data":{"filePath":"/Users/bombrary/tmp/main.py","workspacePath":"/Users/bombrary/tmp","...init_subclass__"},"label":"__init_subclass__","sortText":"10.9999.__init_subclass__","kind":2}}
```

これはLSPサーバーから受けとった情報である。ということは、**LSPとの通信はうまくいっているようだ**。LSPとの通信で失敗しているわけではない。

## 原因の場所を見つける

「LSPサーバーから情報が受け取れているとしたら、その後の処理に問題があるかもしれない」と考え、ddc-nvim-lspのコードを読み始めた。コードが置いてある場所は設定によるが、自分の環境では`~/.cache/dein/repos/github.com/Shougo/ddc-vim-lsp/`ある。

とりあえず`vim.lsp.buf_request`に近いところから読み始めた。そこで、`{handler}`として指定した`get_candidates`関数に目をつけた。

```lua
local get_candidates = function(_, arg1, arg2)
  -- For neovim 0.6 breaking changes
  -- https://github.com/neovim/neovim/pull/15504
  local result = (vim.fn.has('nvim-0.6') == 1
                  and type(arg1) == 'table' and arg1 or arg2)
  -- ... 略
```

ソースコードのコメントによると、**neovimのバージョンによって、lsp-handlerの引数が変わるらしい**。代入文にて短絡評価を使っている。そこではneovimのバージョンが0.6でなかった時点で、2番目の引数`arg2`が`result`であると確定している。しかし、よく考えるとそれはおかしい。neovim 0.5.1のドキュメントを参照した時は、引数の順番は`function(err, result, ctx, config)`であり、1番目の引数が`result`のはず。

もしや、と思い、のソースコードを以下のように変更した。

```lua
local get_candidates = function(_, result)
  -- ... 略
```

なんと**これでLSPの補完が効くようになった**。その場しのぎの変更ではあるが、使えるのでそのままにしておく。

[lsp-handler変更についてのPull request](https://github.com/neovim/neovim/pull/15504)をみると、どうやらneovim 0.5.1のバージョンにこれが取り込まれたようである。実際、[0.5.1 Changelog](https://github.com/justinmk/neovim/commit/0159e4daaed1347db8719c27946fcfdc4e49e92d)にも記載されている。この変更のせいで、補完の処理がうまく動かなくなっていたようである。

Dockerコンテナのneovimでは動いたのは、Dockerのベースイメージとして入っていたneovimのバージョンが0.5.0だったからである。

## プラグインのリポジトリをよく見る

2021/10/1時点で[ddc-nvim-lspのRequired](https://github.com/Shougo/ddc-nvim-lsp#required)を読むと、そこに**neovim 0.5.0+ with LSP configuration**と書いてあった。なので、neovim 0.5.0じゃないと動作が保証されない。0.5.0と0.5.1のバージョン違いなんて対して無いだろうと思っていたが、そういうところまでちゃんと疑うべきだった。


## 学んだこと

- Docker及びDocker Composeの使い方が少し分かった。
- neovimでLuaをどう実行するかが分かった。
- neovimでLSPサーバーにどうリクエストすればよいのかが分かった。
- バージョン違いで大きな変化が起こることがあるということが分かった。
