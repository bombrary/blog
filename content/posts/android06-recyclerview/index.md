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
- 表示するためのデータ
- `xml`ファイル内で定義する`RecyclerView`要素
- データのアイテムごとのlayout: 恐らくこれはTableViewで言うところのTableCell。
- layout manager: 不明
- view holder: 不明
- adapter: adapterパターンでいうadapterのこと。データの扱い方をRecyclerViewやViewHolderに合わせる役目を持つ。
