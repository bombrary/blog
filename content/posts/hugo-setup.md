---
title: "HugoセットアップからGitHubにデプロイするまでの備忘録"
date: 2019-11-09T19:33:37+09:00
draft: true
tags: ["Hugo", "GitHub"]
categories: ["備忘録"]
---

簡単にセットアップ方法を備忘のために書いておく

## 前提

- MacOS Mojave
- Homebrew 2.1.16
- GitHubのblogリポジトリで公開する
- この記事でディレクトリを表記する時は、blogローカルリポジトリの最上位を`/`で表現する

## インストール

ターミナルにて以下のコマンドを叩く

{{< highlight txt >}}
$ brew install hugo
{{< /highlight >}}

## ブログサイトの作成

blogサイトのローカルリポジトリがある前提で進める。blogディレクトリに移動して以下のコマンドを実行する。
forceフラグをつけると、今のディレクトリに何かファイルがあった場合でもサイトを生成してくれる。僕の環境の場合はREADME.mdしかなかったので何も上書きされなかったが、hugoが生成するファイルと名前がかぶる場合は、何かファイルが上書きされる恐れがあるので注意。

{{< highlight txt >}}
$ hugo new site ./ --force
{{< /highlight >}}

すると、何やらたくさんファイルやディレクトリを生成してくれる。

## テーマの追加

[contrast-hugo](https://github.com/niklasbuschmann/contrast-hugo)が気に入ったのでこれを使う。

`/themes`に移動して、contrast-hugoのファイルをcloneしてくる

{{< highlight txt >}}
$ git clone https://github.com/niklasbuschmann/contrast-hugo.git
{{< /highlight >}}

後でテーマをいじるので、一応テーマ名を変更しておく。`contrast-hugo`を`ch-modified`に変更する。

## シンタックスハイライトの設定

`Chroma`というハイライターが入っているらしい。そのテーマは[こちら](https://xyproto.github.io/splash/docs/)で見られる。今回はgithubというテーマを利用する。

`/config.toml`で`pygmentsStyle=github`と指定すると、スタイルをhtmlに直接埋め込んでくれる。しかしCSSを後で自分でいじりたいのでこの方法は用いない。その代わり、`pygmentsUseClasses=true`として、CSSを利用することにする。

`/themes/ch-modified/static/css`に移動して、以下のコマンドを実行する。

{{< highlight txt >}}
$ hugo gen chromastyles --style=github > syntax.css
{{< /highlight >}}

## configの設定

`/config.toml`の内容を以下の通りにする

{{< highlight toml >}}
baseURL = "https:/[自分のgithub pagesのアドレス]/blog/"
languageCode = "ja-jp"
title = "[ブログ名]"
theme = "[テーマ名]"
pygmentsUseClasses = true
publishDir="docs"

[taxonomies]
tag = "tags"
categories = "categories"
{{< /highlight >}}

- baseURL: 後でhugoコマンドで静的ページを作成するとき、cssやjsのアドレス解決のために必要。github公開後のアドレスを指定しておく。
- theme: テーマ名を指定する。ここでは`ch-modified`を指定。
- publishDir: 後でhugoコマンドで静的ページを作成したときの保存先。GitHub Pagesの表示先を`master/docs`にしたいので、このように書いている。
- tag、categories: タグとカテゴリーで分けられるようにしたいのでこれを指定する。taxonomiesについて詳しくはまだよく分かっていないので要勉強。

## index.mdの作成

`/contents/_index.md`を作成し、内容は以下のものとする。これは`/theme/ch-modified/layouts/_default/list.html`の`{{ .Content }}`に埋め込まれる。

{{< highlight md >}}
---

---

## Others

- [Tags](tags/)
- [Categories](categories/)

{{< /highlight >}}

## KaTeXの有効化

`/layouts/partials/math.html`を作成し、内容を以下のものとする。

{{< highlight html >}}
<link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/katex@0.11.1/dist/katex.min.css" integrity="sha384-zB1R0rpPzHqg7Kpt0Aljp8JPLqbXI3bhnPWROx27a9N0Ll6ZP/+DiW/UqRcLbRjq" crossorigin="anonymous">

<!-- The loading of KaTeX is deferred to speed up page rendering -->
<script defer src="https://cdn.jsdelivr.net/npm/katex@0.11.1/dist/katex.min.js" integrity="sha384-y23I5Q6l+B6vatafAwxRu/0oK/79VlbSz7Q9aiSZUvyWYIYsd+qj+o24G5ZU2zJz" crossorigin="anonymous"></script>

<!-- To automatically render math in text elements, include the auto-render extension: -->
<script defer src="https://cdn.jsdelivr.net/npm/katex@0.11.1/dist/contrib/auto-render.min.js" integrity="sha384-kWPLUVMOks5AQFrykwIup5lo0m3iMkkHrD0uJ4H5cjeGihAutqP0yW0J6dpFiVkI" crossorigin="anonymous"
                                                                                                                                                                                  onload="renderMathInElement(document.body);"></script>
<script>
  document.addEventListener("DOMContentLoaded", function() {
    renderMathInElement(document.body, {delimiters: [
      {left: "$$", right: "$$", display: true},
      {left: "$", right: "$", display: false}]
    });
  });
</script>
{{< /highlight >}}

次に、`/theme/ch-modified/layouts/_default/baseof.html`を開き、以下の内容を見つける。
{{< highlight html >}}
{{- if or .Params.math .Site.Params.math }}
<link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/katex@0.10.2/dist/katex.min.css" integrity="sha256-uT5rNa8r/qorzlARiO7fTBE7EWQiX/umLlXsq7zyQP8=" crossorigin="anonymous">
<script defer src="https://cdn.jsdelivr.net/npm/katex@0.10.2/dist/katex.min.js" integrity="sha256-TxnaXkPUeemXTVhlS5tDIVg42AvnNAotNaQjjYKK9bc=" crossorigin="anonymous"></script>
<script defer src="https://cdn.jsdelivr.net/npm/katex@0.10.2/dist/contrib/mathtex-script-type.min.js" integrity="sha256-b8diVEOgPDxUp0CuYCi7+lb5xIGcgrtIdrvE8d/oztQ=" crossorigin="anonymous"></script>
{{- end }}
{{< /highlight >}}

これを次の記述に置き換える。
{{< highlight html >}}
{{ if or .Params.math .Site.Params.math }}
{{ partial "math.html" . }}
{{ end }}
{{< /highlight >}}

ちなみにCSSの読み込みとかは`baseof.html`で行うので、新しいCSSファイルを追加したい場合はここに追記することになる。

## ブログの投稿方法

次のコマンドを実行すると、フロントマターにdateが書き込まれた状態の雛形が`contents/post/`にできる。

{{< highlight txt >}}
$ hugo new post/[ファイル名].md
{{< /highlight >}}


## GitHubへのデプロイ

以下のコマンドで静的ページを`docs`以下に作成する。

{{< highlight txt >}}
$ hugo
{{< /highlight >}}

あとはcommitしてリモートリポジトリにpushする。GitHub Pagesの設定で、`Source`を`master/docs`に設定すれば終わり。

## 参考

[HugoでKaTeX](https://blog.atusy.net/2019/05/09/katex-in-hugo/)
