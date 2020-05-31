---
title: "VimでLaTeXを使うための環境構築(Mac)"
date: 2020-05-31T19:03:00+09:00
toc: true
tags: ["latexmk", "vimtex"]
categories: ["環境構築", "Vim", "LaTeX"]
---

備忘録。基本的にはMacのTerminalでやることを想定。Macをインストールしたての状態を仮定する。

homebrewを使って、TeXLiveとSkimをインストールする。latexmkの設定をした後、vimにdein.vimを入れて、それを用いてvimtexを入れるところまでやる。おまけでvimrcの他の設定や、colorschemeの設定もやる。

## 注意

なるべくコマンドを載せるようにするが、それを実行しても上手くいかない場合は、公式サイトなどを参照すること。この記事が古くなっていて、打つべきコマンドが変わっている可能性がある。

## homebrewのインストール

homebrewをインストールしておくと、いろいろなソフトが`brew (cack) install ...`だけでインストールできる。便利なので入れる。

[homebrewの公式サイト](https://brew.sh/index_ja)のインストールを参照。

念のため、Terminalを再起動しておく。

## TeXLive(MacTeX)のインストール

TeXLiveの説明については[Wiki](https://texwiki.texjp.org/?TeX%20Live)を参照。TeX関連のあらゆるパッケージやソフトの詰め合わせ。そのMac版がMacTeX。

MacTeXやそのインストール方法については、[Wiki](https://texwiki.texjp.org/?MacTeX)を参照。homebrewをインストールしたので、次のコマンドでインストールできる。以下は`mactex-no-gui`としているが、もしguiアプリも入れたい場合は`mactex`とする。どんなguiアプリが入るのかについてはWikiを参照。

かなり巨大なファイル群のため、インストールにかなり時間がかかった気がする。

{{< cui >}}
$ brew cask install mactex-no-gui
$ sudo tlmgr update --self --all
$ sudo tlmgr paper a4
{{< /cui >}}

念のため、Terminalを再起動しておく。

## Skimのインストール

SkimとはPDFビュワーの一種で、PDFの自動リロードを行ってくれる。こちらもhomebrewでインストールできる。

{{< cui >}}
$ brew cask install Skim
{{< /cui >}}

起動して、環境設定を開く。「同期」タブに移動して、「ファイルの変更をチェック」と「自動的にリロードする」にチェックを入れておく。

## latexmkの設定

後でインストールするVimのプラグイン(vimtex)がlatexmkを利用するので、設定しておく。

[こちら](https://qiita.com/Rumisbern/items/d9de41823aa46d5f05a8)のページは、latexmkについて分かりやすく説明してくれているので見ておくと良い。

`~/.latexmkrc`を作成し、内容を以下のようにする。これは上の参考サイトの引用。

```perl
#!/usr/bin/env perl
$latex            = 'platex -synctex=1 -halt-on-error';
$latex_silent     = 'platex -synctex=1 -halt-on-error -interaction=batchmode';
$bibtex           = 'pbibtex';
$biber            = 'biber --bblencoding=utf8 -u -U --output_safechars';
$dvipdf           = 'dvipdfmx %O -o %D %S';
$makeindex        = 'mendex %O -o %D %S';
$max_repeat       = 5;
$pdf_mode         = 3;
$pvc_view_file_via_temporary = 0;
$pdf_previewer    = "open -ga /Applications/Skim.app";
```

## Vimのインストール

恐らく標準で入っていると思われる。もし入っていなかったら以下のコマンドでインストールする。

{{< cui >}}
$ brew install vim
{{< /cui >}}

## dein.vimのインストール

Vimのプラグインを管理するためのプラグイン。

[公式のQuick Start](https://github.com/Shougo/dein.vim#quick-start)の1を参考に、以下のコマンドを実行。

すると以下のメッセージが表示される。

{{< cui >}}
$ curl https://raw.githubusercontent.com/Shougo/dein.vim/master/bin/installer.sh > installer.sh
$ sh ./installer.sh ~/.cache/dein
{{< /cui >}}

{{< cui >}}
...
Done.                                                                                        

Please add the following settings for dein to the top of your vimrc (Vim) or init.vim (NeoVim) file: 

"dein Scripts-----------------

if &compatible
  set nocompatible               " Be iMproved
endif

...(略)

" If you want to install not installed plugins on startup.
" if dein#check_install()
"   call dein#install()
" endif

"End dein Scripts-------------------------

Done.
Complete setup dein!
{{< /cui >}}

言われた通り、`"dein Scripts----`から`"End dein Scripts----`までの内容を`~/.vimrc`に記載する。

ただし、恐らく最後の3行になっているであろう以下の記述はコメントを外しておく。これを行っておくと、vimが起動する度に、登録したプラグインを自動でインストールしてくれる。登録方法については後の項でやる。

```vim
if dein#check_install()
  call dein#install()
endif
```

`source`コマンドを打つか、Vimを再起動する。

### helpが見られるようにする

Vimを起動して、以下のコマンドを実行する。

```txt
:helptags ~/.cache/dein/repos/github.com/Shougo/dein.vim/doc/
```

これで、`:h dein`でdeinのhelpが見られるようになる。

### tomlファイルの設定

プラグインの登録は`~/.config/dein.toml`、遅延ロードしたいプラグインの登録は`~/.config/dein_lazy.toml`に記載することにする。遅延ロードとは、ある特定の状況のみプラグインがロードされる仕組みのこと。例えば「挿入モードに入った時」「texのファイルを読み込んだ時」などのタイミングで、然るべきプラグインをロードすることができる。これにより、すべてのプラグインをロードしなくて済むため、vimの動作が遅くなりにくくなる。

`:h dein`でhelpを開き、`toml`という単語で検索をかける。色々調べていくと、結局以下のように設定すれば良いことが分かる。さっき書いた設定ファイルにおいて、`dein#load_state`と`dein#begin`の直後に文を追加する。

```vim
let s:toml = '~/.config/dein.toml` "追加
let s:toml_lazy = '~/.config/dein_lazy.toml` "追加

if dein#load_state('...')
  call dein#begin('...')

  call dein#load_toml(s:toml, {'lazy': 0}) "追加
  call dein#load_toml(s:toml_lazy, {'lazy': 1}) "追加

  ...(略)

  call dein#end()
  call dein#save_state()
endif
```

`source`コマンドを打つか、Vimを再起動する。

### プラグインの登録

`~/.config/dein.toml`を作っておく。とりあえず中身は空にする。`~/.config/dein_lazy.toml`の内容を以下のようにする[参考](https://qiita.com/KeitaNakamura/items/87dad47dc09ae8bf6abf)。

```toml
[[plugins]]
repo = 'lervag/vimtex'
on_ft=['tex']
hook_source='''
  let g:vimtex_view_general_viewer = 'displayline'
  let g:vimtex_view_general_options = '-r @line @pdf @tex'
'''    
```

軽く説明すると、

- 1つのプラグインの登録は`[[plugins]]`から始める
- `repo = プラグインのリポジトリ名`
- `on_ft = [ファイルの種類のリスト]`。今回は`on_ft=['tex']`なので、texのファイルの時だけ、このプラグインがロードされる。
- `hook_source`: プラグインが読み込まれる直前に実行される命令を書く。`hook`関連については、`:h dein-hook`を引くか、[こちら](https://qiita.com/delphinus/items/cd221a450fd23506e81a)が参考になる。

`g:vimtex_view_general_viewer`では、開くPDFビュワーを設定する。ここでは`displayline`を設定している。これはSkimをインストールした際に付属するスクリプト。Skimの公式Wikiを漁ってみたところ、説明は[このページ](https://sourceforge.net/p/skim-app/wiki/TeX_and_PDF_Synchronization/#setting-up-your-editor-for-forward-search)にあった。pdfを、行番号指定付きで開くためのもの。vimtexは`<localleader>lv`というコマンドで「該当行をハイライトしてpdfを開く」ことが可能なので、その機能の実現のためにdisplaylineを使っているのだと思われる。`g:vimtex_view_general_options`では、`displayline`に指定するコマンドライン引数を設定している。

### texファイルのfiletypeをlatexにする

空のtexファイルを作ったときに限って、`vimtex`が読み込まれない。これは、空の`tex`ファイルのfiletypeは`plaintex`として認識されているかららしい([参考](https://superuser.com/questions/208177/vim-and-tex-filetypes-plaintex-vs-tex))。よく調べたら、`:h vimtex-comment-internal`にも書いてあった。

`~/.vimrc`に以下の記述を追加。

```
let g:tex_flavor = "latex"
```

### localleaderの設定

詳細は`:h mapleader`や`:h maplocalleader`を参照。vimtexでは`<LocalLeader>ll`で自動コンパイルモードをオンにしたり、`<LocalLeader>lv`でpdfを開いたりする。

以下の設定をすることで、`<LocalLeader>`の部分を半角スペースに設定する。つまり、`[Space]ll`や` [Space]lv`というコマンドを認識するようになる。

```
let maplocalleader=' '
```

## vimtexを使う

適当なtexファイルを書いて、

- スペース + `ll`: 自動コンパイルモードのON/OFF切り替え。
- スペース + `lv`: PDFを表示。

ができる。これでひとまず、LaTeXができる環境が整った。


## おまけ

### colorschemeの設定

ここでは[iceberg](https://github.com/cocopon/iceberg.vim)を利用する。`dein.toml`にcolorschemeの設定をしてもうまく動かない。`:h dein-faq`に詳細が載っていたので、それに沿って設定。`.vimrc`において、`dein#load_state`の中と外に文を追加する。[別の解決方法](https://qiita.com/kawaz/items/ee725f6214f91337b42b#colorscheme-は-vimenter-に-nested-指定で遅延設定する)もあるみたい。

```vim
"dein Scripts-----------------------------

...(略)

if dein#load_state('...')

  ...(略)

  " Let dein manage dein
  " Required:
  call dein#add('...')

  " Add or remove your plugins here like this:
  call dein#add('cocopon/iceberg.vim') " 追加

  " Required:
  call dein#end()
  call dein#save_state()
endif

...(略)

"End dein Scripts-------------------------

set background=dark "追加
colorscheme iceberg "追加
```

### vimrcの設定

そもそもvimでtexを使うような人はvimをよく使っている人がほとんどだと思うので、この節は必要ないかもしれないが&hellip;

とりあえず[こちら](https://qiita.com/morikooooo/items/9fd41bcd8d1ce9170301)を参考にして、必要なものだけ設定するのがありだと思う。

それに加えて、個人的には以下の設定をやったほうが良い。[こちら](https://qiita.com/Linda_pp/items/9e0c94eb82b18071db34)からの引用。`~/.vimrc`に追記する。これは、挿入モードに入った時にカーソルの形を変える設定。いま自分が挿入モードとノーマルモードのどちらにいるのかが分かりやすくなる。

```vim
" カーソルの形についての設定
if has('vim_starting')
    " 挿入モード時に非点滅の縦棒タイプのカーソル
    let &t_SI .= "\e[6 q"
    " ノーマルモード時に非点滅のブロックタイプのカーソル
    let &t_EI .= "\e[2 q"
    " 置換モード時に非点滅の下線タイプのカーソル
    let &t_SR .= "\e[4 q"
endif
```

何かわからないことがあったら、こまめに:hコマンドで調べてみると良い。素のvimのhelpなら[日本語版もある](https://vim-jp.org/vimdoc-ja/)。


## 参考

- [homebrew](https://brew.sh/index_ja)
- [TeXLive - TeX Wiki](https://texwiki.texjp.org/?TeX%20Live)
- [Latexmkから学ぶPDF化までの処理の流れ - Qiita](https://qiita.com/Rumisbern/items/d9de41823aa46d5f05a8)
- [Shougo/dein.vim - GitHub](https://github.com/Shougo/dein.vim)
- [CLIのneovimでSkimとSyncTeXするには - Qiita](https://qiita.com/KeitaNakamura/items/87dad47dc09ae8bf6abf)
- [[dein.vim] hook の便利な使い方 - Qiita](https://qiita.com/delphinus/items/cd221a450fd23506e81a)
- [Skim/Wiki/TeX_and_PDF_Synchronization](https://sourceforge.net/p/skim-app/wiki/TeX_and_PDF_Synchronization/#setting-up-your-editor-for-forward-search)
- [lervag/vimtex - GitHub](https://github.com/lervag/vimtex)
- [vim and TeX filetypes: plaintex vs. tex - superuser](https://superuser.com/questions/208177/vim-and-tex-filetypes-plaintex-vs-tex)
- [cocopon/iceberg - GitHub](https://github.com/cocopon/iceberg.vim)
- [dein.vimによるプラグイン管理のマイベストプラクティス - Qiita](https://qiita.com/kawaz/items/ee725f6214f91337b42b)
- [help - Vim日本語ドキュメント](https://vim-jp.org/vimdoc-ja/)
