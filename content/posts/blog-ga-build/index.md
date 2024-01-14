---
title: "ブログをGitHub Actionsを使ったビルドに切り替えたときの手順"
date: 2024-01-14T11:12:28+09:00
tags: ["Hugo", "GitHub"]
categories: ["blog"]
---

このブログはまだCI/CDも分からない頃に始めたのもあって、GitHub Actionsを使っていないビルドをしていた。いちいちビルドしてリポジトリにpushするのも面倒だし、[Chanomic Sketch](https://bombrary.github.io/sketch/)を昨年開設したときにGitHub Actionによるビルドを学んだので、重い腰を上げて切り替えようと思った。そのときのメモ。

色々調べていたら、[Chanomic Sketch](https://bombrary.github.io/sketch/)で上げたときとは違って、gh-pagesのようなブランチを作らなくても良い方法が作られていたので、その方法でやっていく。

基本的な手順は[Hugoの公式](https://gohugo.io/hosting-and-deployment/hosting-on-github/)に書かれているが、一応現時点でのやり方をメモっておく。

## （参考）現状のデプロイ方法と今後のデプロイ方法の比較

現状は、

1. `hugo new posts/.../index.md`で記事を作成
2. 記事を書いて`hugo server`で確認
3. 書き終わったら`index.md`の`draft: ture`を外してcommit
4. `hugo`コマンドを単体で実行してページのビルドをする → `docs/`下にHTMLが展開されるので、それをcommit
5. pushする

と手順を踏んでいたが、今回の変更によって、

1. `hugo new posts/.../index.md`で記事を作成
2. 記事を書いて`hugo server`で確認
3. 書き終わったら`index.md`の`draft: ture`を外してcommit
4. pushする

と手順が1個減る。また、`docs/`ディレクトリがなくなるためコミットログがすっきりすることも期待される。

## ブログの修正

まず、`config.toml`のpublishDirにて`docs/`下にHTMLを展開するようにしてあったが、この記述はいらないので消す。
```toml
publishDir="docs"
```

また、`docs/`ディレクトリは `git rm -rf`で消す。

## GitHub Pagesの設定

Pagesの設定に移動して、Build and deploymentの項目のSourceを、「Deploy from a branch」から「GitHub Actions」に変更。

{{< figure src="gh-pages-action.jpg" >}}

## workflowの記述

次に、`.github/workflows/<適当な名前>.yaml` を作成し、そこに以下の記述をする。

注）これは現時点での[Hugoの公式](https://gohugo.io/hosting-and-deployment/hosting-on-github/)をそのまま借りてきている。最新版は公式を参照すること。

```yaml
name: Deploy Hugo site to Pages

on:
  push:
    branches:
      - master

  workflow_dispatch:

permissions:
  contents: read
  pages: write
  id-token: write

concurrency:
  group: "pages"
  cancel-in-progress: false

defaults:
  run:
    shell: bash

jobs:
  build:
    runs-on: ubuntu-latest
    env:
      HUGO_VERSION: 0.121.0
    steps:
      - name: Install Hugo CLI
        run: |
          wget -O ${{ runner.temp }}/hugo.deb https://github.com/gohugoio/hugo/releases/download/v${HUGO_VERSION}/hugo_extended_${HUGO_VERSION}_linux-amd64.deb \
          && sudo dpkg -i ${{ runner.temp }}/hugo.deb
      - name: Install Dart Sass
        run: sudo snap install dart-sass
      - name: Checkout
        uses: actions/checkout@v4
        with:
          submodules: recursive
          fetch-depth: 0
      - name: Setup Pages
        id: pages
        uses: actions/configure-pages@v4
      - name: Install Node.js dependencies
        run: "[[ -f package-lock.json || -f npm-shrinkwrap.json ]] && npm ci || true"
      - name: Build with Hugo
        env:
          HUGO_ENVIRONMENT: production
          HUGO_ENV: production
        run: |
          hugo \
            --gc \
            --minify \
            --baseURL "${{ steps.pages.outputs.base_url }}/"
      - name: Upload artifact
        uses: actions/upload-pages-artifact@v2
        with:
          path: ./public

  deploy:
    environment:
      name: github-pages
      url: ${{ steps.deployment.outputs.page_url }}
    runs-on: ubuntu-latest
    needs: build
    steps:
      - name: Deploy to GitHub Pages
        id: deployment
        uses: actions/deploy-pages@v3
```

やっている内容としては、
- `on: push: branches: master`で、masterブランチにpushされたときにこのworkflowが実行される
  - 最近だとデフォルトがmainブランチのはずだが、このブログを作ったときはmasterがデフォルトだった。**新しく静的サイトを公開する場合はここがmainである**ことがほとんどだと思うので注意。
- jobとしてbuildとdeployと呼ばれるものを定義する。workflowではjob単位で何らかの処理が実行される。
- buildとdeployの大まかな処理は以下の通り。
  1. buildでページをビルドして、それをartifactという形でアップロードする
  2. artifactをdeployが受け取って、GitHub Pagesとしてデプロイする

## デプロイの実行

上記の `.github/workflows/*.yml`をcommitしてpushすれば、自動的にworkflowが実行される。

Actionsタブの、最新のworkflowを見てみると、以下のようにbuildとdeployのjobが実行されていることが確認できる。

{{< figure src="workflow-jobs.jpg" >}}

またbuildジョブのUpload artifactステップにおいて、hugoでビルドした結果がtarで固められてアップロードされているのが確認できる。

{{< figure src="upload-step.jpg" >}}

そして、deployジョブがそれを受け取ってデプロイを実行していることが確認できる。

{{< figure src="deploy-step.jpg" >}}

これで `https://ユーザ名.github.io/リポジトリ名` に静的ページがデプロイされる。
