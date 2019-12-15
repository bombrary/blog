---
title: "Androidアプリ開発勉強(6) - RecyclerView"
title: "Android Recyclerview"
date: 2019-12-07T22:41:47+09:00
draft: true
tags: []
categories: []
---

## RecyclerViewとは

SwiftのUIKitでいうところの「dequeueReusableCellを利用してTableView」っぽい。つまり画面外に消えたセルを再利用することでメモリを節約する。

[ここ](https://codelabs.developers.google.com/codelabs/kotlin-android-training-recyclerview-fundamentals/index.html?index=..%2F..android-kotlin-fundamentals#2)を参考に簡単にbまとめてみる。

RecyclerViewを使うために必要なもの
1. 表示するためのデータ
2. `xml`ファイル内で定義する`RecyclerView`要素
3. データのアイテムごとのlayout
4. layout manager: 上リンクだと「View内のUI部品の構成を管理する」みたいな感じの説明だが、要するにRecyclerView全体の管理を行ってくれるもの、という認識で良さそう？
5. view holder: 1つのアイテムごとのViewを持つもの、みたいな認識で良さそう？
6. adapter: adapterパターンでいうadapterのこと。データの扱い方をRecyclerViewやViewHolderに合わせる役目を持つ。

SwiftのTableViewとのアナロジーで考えてみると、2はTableViewCellっぽい。

## Adapter

Itemの個数とか、Itemに対応したViewを返す関数をここに定義しておく。

SwiftのTableViewとのアナロジーで考えてみると、TableViewCellDataSourceと似た立ち位置っぽい。

- `getItemsCount`: データの個数を返す関数。
- `onBindViewHolder`: ViewHolderにデータが結ばれる際に呼ばれる関数。ViewHolderに結びついたViewにデータの値を設定する。
- `onCreateViewHolder`: ViewHolderが作成される際に呼ばれる関数。`inflate`関数でViewを作成し、それを元にViewHolderを作成する。

