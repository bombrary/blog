---
title: "HugoのテーマをPaperModに変えた"
date: 2024-05-19T09:40:00+09:00
draft: true
tags: []
categories: [ "Hugo" ]
---

今のシンプルなままでも良い気がしたが、シンプルさはそのままでもう少しだけリッチなサイトに改築してみたくなったので、それっぽいテーマを探してそちらに引っ越してみた。

## before と after

### before

{{< figure src="./before.png" >}}

### after

{{< figure src="./after.png" >}}

## やったこと

### PaperMod導入

[PaperModのInstallation](https://github.com/adityatelange/hugo-PaperMod/wiki/Installation)に従う。

いくつかやり方が紹介されているが、自分はsubmoduleを使ってPaperModを持ってきた。

```sh
git submodule add --depth=1 https://github.com/adityatelange/hugo-PaperMod.git themes/PaperMod
```

### config.tomlの修正

[PaperModのWiki](https://github.com/adityatelange/hugo-PaperMod/wiki/)を参考にすればどんな設定をすればよいのかがわかる。Wikiはyamlで書かれているが、ブログ解説当初はtomlで書いていたため、tomlに読み替えて進めた。

また、Wikiからうまく見つけられない情報があった場合は、直接PaperModの `layouts` ディレクトリをgrepしてそれっぽい変数が無いか探した。

#### searchページとarchiveページ

searchページとarchiveページはそれぞれ次の項目を参考にした。
* [Archives Layout](https://github.com/adityatelange/hugo-PaperMod/wiki/Features#search-page)
* [Search Page](https://github.com/adityatelange/hugo-PaperMod/wiki/Features#archives-layout)

searchとarchiveのリンクをヘッダーに追加したいなら、次のように `config.toml` に書けばよい（参考：[Add menu to site](https://github.com/adityatelange/hugo-PaperMod/wiki/FAQs#add-menu-to-site)）。
```toml
[[menu.main]]
identifier = "tags"
name = "Tags"
url = "/tags/"
weight = 20

[[menu.main]]
identifier = "archives"
name = "Archive"
url = "/archives/"
weight = 30
```

#### ファイルの移動

ブログ用に書いていたCSSやKaTeXの設定を移す必要があった。

幸いPaperModにはcssやheader/footerを拡張するための仕組みが作られている。
* [Bundling Custom css with theme's assets](https://github.com/adityatelange/hugo-PaperMod/wiki/FAQs#bundling-custom-css-with-themes-assets)
* [Custom Head / Footer](https://github.com/adityatelange/hugo-PaperMod/wiki/FAQs#custom-head--footer)

やった内容としては以下の通り。
* CSSは、`assets/css/extends/` に配置する
* KaTeXの設定は、`layouts/partials/extend_heads.html` に記載する

#### lastmod設定

記事の最終更新日を記事タイトルに記載するようにしたい。

これに関しては layout を上書きする他ない。記事タイトルの下にある日付とかのhtmlは PaperModの `layouts/partials/post_metadata.html` にあるのため、これを自分のブログの `layouts/partials/` ディレクトリに移動する。そして以下の記述を追加する。

```html
{{- if not .Lastmod.IsZero -}}
{{- $scratch.Add "meta" (slice (printf "<span title='%s'>(updated %s)</span>" (.Lastmod) (.Lastmod | time.Format (default "January 2, 2006" site.Params.DateFormat)))) }}
{{- end }}
```

`config.toml` には以下の記述を追加する。
```toml
enableGitInfo = true
```

これで、記事タイトルの下が `2024-05-14·(updated 2024-05-14)` という表示になる。

なお、「新規記事の場合はupdateをつけない」といった処理をしたい場合は、次のページが参考になる。記事の `.Date` と `.Lastmod` が一致していれば、 `.Lastmod` の方を出さないようにしている。

[Use Lastmod with PaperMod](https://www.jacksonlucky.net/posts/use-lastmod-with-papermod/)

#### Google Analyticsの設定

このブログを開設したときはHugoについて無知だったので `layouts/google_analytics.html` を自作していたが、どうやらHugo公式でテンプレートが用意されているらしい。

[Google Analytics - Hugo](https://gohugo.io/templates/embedded/#google-analytics)

PaperModでも `layouts/partials/head.html` にそれを呼び出している記述があるため、これを用いる。
```html
{{- /* Misc */}}
{{- if hugo.IsProduction | or (eq site.Params.env "production") }}
{{- template "_internal/google_analytics.html" . }}
...
{{- end -}}
```

やり方としては、`config.toml`に以下の記述を追加するだけ。

```toml
[services.googleAnalytics]
ID = "（アナリティクスのID）"
```

## 思ったこと

今後、仮にブログを別のテーマに移行する、ということを考えたとき、テーマになるべく依存しないようにMarkdownを書いたほうが良いと感じた。具体的には、テーマに依存する設定は、Markdownのフロントマターに書き込むのではなく、 `config.toml` に書き込むようにしたい。

あとは、究極的にはHugoから別のSSGに移行するケースを想定するなら、Hugo（というかGoLang）のテンプレート構文をMarkdownに埋め込むのは避けたほうがよいのだけれど、利便性を考えると悩ましいところ。
