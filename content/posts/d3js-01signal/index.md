---
title: "D3.js 01信号の可視化"
date: 2019-12-17T13:56:36+09:00
tags: ["D3.js", "Visualization", "JavaScript", "可視化"]
categories: ["D3.js", "Visualization", "JavaScript"]
---

信号に関する授業を聴いていたらふと思い立ったのでやってみた。

## コード

### index.html

個人的テンプレを書く。

{{< highlight html >}}
<!DOCTYPE html>
<html lang="ja">
  <head>
    <meta charset="utf-8">
    <title>0-1 Signal</title>
  </head>
  <body>
    <h1>0-1 Signale</h1>
    <svg>
    </svg>
    <script src="https://d3js.org/d3.v5.min.js"></script>
    <script src="script.js"></script>
  </body>
</html>
{{< /highlight >}}

### script.js

JavaScriptで`flatMap`使うのはこれが初めてかも。

{{< highlight js >}}
const format = (data, w) => {
  const pairs = d3.pairs(data);
  const deltas = pairs.flatMap(e => {
    let sig = e.toString()
    if (sig == '0,0') {
      return [[1,0]];
    } else if (sig == '0,1') {
      return [[1,0],[0,-1]];
    } else if (sig == '1,0') {
      return [[1,0],[0,1]];
    } else if (sig == '1,1') {
      return [[1,0]];
    } else {
      throw new Error('invalid element.');
    }
  });
  const points = deltas.reduce((acc, e) => {
    const back = acc[acc.length - 1].slice();
    back[0] += w * e[0];
    back[1] += w * e[1];
    return acc.concat([back])
  }, [[0,0]]);
  return points;
};

const [svgWidth, svgHeight] = [800, 800];
const svg = d3.select('svg')
  .attr('width', svgWidth)
  .attr('height', svgHeight);

const pad = 70;
const render = (data) => {
  svg.selectAll('*').remove();
  svg.append('path')
    .datum(data)
    .attr('transform', `translate(${pad}, ${pad})`)
    .attr('stroke', 'black')
    .attr('fill', 'none')
    .attr('d', d3.line()
        .x(d => d[0])
        .y(d => d[1]));
};

render(format([0,0,1,0,1,0,1,1,1,1,0,0], 50));
{{< /highlight >}}

### 実行結果

{{< figure src="./sc01.png" >}}

## 説明

### format

01の情報を、path用の頂点データに変換する関数。

隣り合う数字によって上に上がるか下に下がるかが変わってくるため、まず隣り合う頂点をまとめたデータを`d3.pairs`で作成する。次にそれを元に進み具合を表した配列`delta`を作成する。例えば`0,1`の場合、「右に1進んで上に1上がる」という動きをするため、配列`[[1,0],[0,-1]]`を返すようにしている。作った増分データから、実際の頂点データを作成したものが`points`となる。ここで、1進んだり上がったりだと、svg上ではあまりにも小さすぎるので、引数`w`を掛けて拡大している。

### render

`format`が完成すれば話は早い。ここでは実際の描画を担う。単に`path`要素にデータを結びつけて、`d3.line`を使って折れ線を生成しているだけ。
