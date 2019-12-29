---
title: "iPhoneアプリ開発メモ - 棒グラフの作成(Chartsの利用)"
date: 2019-12-29T22:37:26+09:00
tags: ["Swift", "iPhone", "UIKit", "Charts", "Visualization"]
categories: ["Swift", "iPhone", "UIKit", "Visualization"]
---

今度は外部ライブラリ[Charts](https://github.com/danielgindi/Charts)を利用して、棒グラフを作成してみる。

## 目標

1. 値が最大のデータは色をオレンジにする
2. アニメーションがある
3. 棒グラフの上に値を表示する
4. ページ切り替えができる棒グラフを作る
5. タップしたらイベントを発生させる

1&#x301C;3、5は機能としてある。4だけ頑張って作る。思い通りのレイアウトにするためにはプロパティとかドキュメントとかを漁る必要があるが、どこにどのプロパティがあるのかは大体予想できる。

1. `ChartDataSet.colors`で各棒の色を変更できる。
2. `BarChartView.animate(yAxisDuration:)`を利用。
3. `BarChartView.drawValueAboveBarEnabled = true`とする。表示形式を変更するためには`ChartDataSet.valueFormatter`にフォーマット用のオブジェクトを指定する。
4. ScrollViewの中ににBarChartViewを複数配置。
5. `ChartViewDelegate`を利用。

その他デフォルトの設定だと表示する情報量が多すぎるので、いくつかのプロパティをいじる。

## Chartsのインストール

まず、CocoaPodsがインストールされていることが前提。

プロジェクトフォルダで以下のコマンドを実行。

```
$ pod init
```

`podfile`が作成されるので、それを編集する。`use_frameworks!`の下に以下の記述を追加。

{{< highlight podfile >}}
pod 'Charts'
{{< /highlight >}}

プロジェクトフォルダで以下のコマンドを実行。

```
$ pod install
```

以降、プロジェクトは`プロジェクト名.xcodeproj`ではなく`プロジェクト名.xcworkspace`から開く。

## 基本

{{< highlight swift >}}
import UIKit
import Charts

struct BarChartModel {
    let value: Int
    let name: String
}

class ViewController: UIViewController {
    
    let barItems = [
        (7, "太郎"), (1, "次郎"), (2, "三郎"), (6, "四郎"), (3, "五郎"),
        (9, "六郎"), (2, "七郎"), (3, "八郎"), (1, "九郎"), (5, "十郎"),
        (1, "十一郎"), (1, "十二郎"), (6, "十三郎")
    ]

    override func viewDidLoad() {
        super.viewDidLoad()
        
        let barChartView = createBarChartView()
        self.view.addSubview(barChartView)
        barChartView.translatesAutoresizingMaskIntoConstraints = false
        barChartView.topAnchor.constraint(equalTo: self.view.topAnchor, constant: 80).isActive = true
        barChartView.bottomAnchor.constraint(equalTo: self.view.bottomAnchor, constant: -80).isActive = true
        barChartView.leadingAnchor.constraint(equalTo: self.view.leadingAnchor).isActive = true
        barChartView.trailingAnchor.constraint(equalTo: self.view.trailingAnchor).isActive = true
    }
    
    private func createBarChartView() -> BarChartView {
        let barChartView = BarChartView()
        barChartView.data = createBarChartData(of: barItems.map({BarChartModel(value: $0.0, name: $0.1)}))
        return barChartView
    }
    
    private func createBarChartData(of items: [BarChartModel]) -> BarChartData {
        let entries: [BarChartDataEntry] = items.enumerated().map {
            let (i, item) = $0
            return BarChartDataEntry(x: Double(i), y: Double(item.value))
        }
        let barChartDataSet = BarChartDataSet(entries: entries, label: "Label")
        let barChartData = BarChartData(dataSet: barChartDataSet)
        return barChartData
    }
}
{{< /highlight >}}

これだけの記述で以下の棒グラフが描ける。

{{< figure src="./iphone01.png" width="30%" >}}

### 説明

棒グラフに限っては、以下の手順で作る。

- `BarChartEntry`にデータを詰める
- `BarChartEntry`の配列から`BarChartDataSet`を作成
- `BarChartDataSet`から`BarChartData`を作成
- `BarChartView`に`BarChartData`を詰める


## 色をつける

`ViewController`に最大値のプロパティを持たせる。

{{< highlight swift >}}
lazy var maxVal: Int = barItems.map({ $0.0 }).max()!
{{< /highlight >}}

`barChartDataSet`に色の配列をセットする。

{{< highlight swift >}}
barChartDataSet.colors = items.map { $0.value == maxVal ? .systemOrange : .systemBlue }
{{< /highlight >}}

{{< figure src="./iphone02.png" width="30%" >}}

## アニメーション

`createBarChartView`関数に以下の記述を追加。

{{< highlight swift >}}
barChartView.animate(yAxisDuration: 1)
{{< /highlight >}}

{{< figure src="./mov01.gif" width="30%" >}}

## 棒グラフの下に名前を表示する

これは、棒グラフのx軸を設定することで実現できる。

`createBarChartView`関数に以下の記述を追加。

{{< highlight swift >}}
barChartView.xAxis.labelCount = items.count
barChartView.xAxis.labelPosition = .bottom
barChartView.xAxis.valueFormatter = IndexAxisValueFormatter(values: items.map({$0.name}))
{{< /highlight >}}

- `labelCount`を設定しておかないと、ラベルの表示が奇数番目のみにになるので注意。
- `labelPosition`を設定しておかないと、ラベルの位置が上になるので注意。
- `valueFormatter`には、軸の表示方法を管理するオブジェクトを定義する。

`IndexAxisValueFormatter`の代わりに、`IAxisValueFormatter`に準拠したオブジェクトを指定すると、x軸の書式をカスタマイズできる。

例えば、以下のように`XAxisFormatter`を定義すると、これは`IndexAxisValueFormatter`と同じような振る舞いをする。

{{< highlight swift >}}
class XAxisFormatter: IAxisValueFormatter {
    let items: [BarChartModel]
    init(of items: [BarChartModel]) {
        self.items = items
    }
    func stringForValue(_ value: Double, axis: AxisBase?) -> String {
        let index = Int(value)
        return self.items[index].name
    }
}
{{< /highlight >}}

{{< figure src="./iphone03.png" width="60%" >}}

## 棒グラフの上にある数字の書式設定

`createBarChartData`関数に以下の記述を追加。

{{< highlight swift >}}
barChartView.valueFont = .systemFont(ofSize: 20)
barChartDataSet.valueFormatter = ValueFormatter(of: items)
{{< /highlight >}}

`ValueFormatter`を定義する。これは`IValueFormatter`に準拠したクラス。この`stringForValue`で、x軸の値`value`に対するラベルの値を返すように設定する。

{{< highlight swift >}}
class ValueFormatter: IValueFormatter {
    let items: [BarChartModel]
    init(of items: [BarChartModel]) {
        self.items = items
    }
    func stringForValue(_ value: Double, entry: ChartDataEntry, dataSetIndex: Int, viewPortHandler: ViewPortHandler?) -> String {
        return "\(Int(value))"
    }
}
{{< /highlight >}}

{{< figure src="./iphone04.png" width="35%" >}}

## 細かい設定

グリッドとかy軸とかはいらないので、それを消す設定をする。

`createBarChartView`関数に以下の記述を追加。

{{< highlight swift >}}
// グリッドやy軸を非表示
barChartView.xAxis.drawGridLinesEnabled = false
barChartView.leftAxis.enabled = false
barChartView.rightAxis.enabled = false

// 凡例を非表示にする
barChartView.legend.enabled = false

// ズームできないようにする
barChartView.pinchZoomEnabled = false
barChartView.doubleTapToZoomEnabled = false
{{< /highlight >}}

{{< figure src="./iphone05.png" width="30%" >}}

## ページ分け

1ページ内に13本のグラフが並んでいるのは見づらい。なのでScrollViewを使ってページ分けする。

### Main.storyboard

前回通りにやる。

{{< figure src="./main_storyboard.png" width="50%" >}}

### ViewController.swift

`viewDidLoad`では主に`scrollView`の設定をする。

{{< highlight swift >}}
override func viewDidLoad() {
    super.viewDidLoad()
    
    scrollView.frame = CGRect(
        x: 0,
        y: 0,
        width: scrollView.superview!.frame.width,
        height: scrollView.superview!.frame.height
    )
    let contentsView = createContentsView(
        of: barItems.map({ BarChartModel(value: $0.0, name: $0.1 ) }),
        barsCountPerPage: 5
    )
    scrollView.addSubview(contentsView)
    scrollView.contentSize = contentsView.frame.size
    scrollView.isPagingEnabled = true
}
{{< /highlight >}}

`createContentsView`を定義する。こちらもやってること自体は前回とあまり変わっていない。

{{< highlight swift >}}
private func createContentsView(of items: [BarChartModel], barsCountPerPage: Int) -> UIView {
    let itemsPerPage = stride(from: 0, to: items.count, by: barsCountPerPage).map {
        Array(items[$0 ..< min($0 + barsCountPerPage, items.count)])
    }
    let contentsView = UIView(frame: CGRect(
        x: 0,
        y: 0,
        width: scrollView.frame.width * CGFloat(itemsPerPage.count),
        height: scrollView.frame.height
    ))
    for (i, items) in itemsPerPage.enumerated() {
        let barChartView = createBarChartView(of: items)
        let percent = CGFloat(items.count) / CGFloat(itemsPerPage[0].count)
        barChartView.frame = CGRect(
            x: scrollView.frame.width * CGFloat(i),
            y: 0,
            width: scrollView.frame.width * percent,
            height: scrollView.frame.height
        )
        contentsView.addSubview(barChartView)
    }
    return contentsView
}
{{< /highlight >}}

`createBarChartView`に以下の記述を追加。これで全ページで同じ縮尺になる。

{{< highlight swift >}}
barChartView.leftAxis.axisMaximum = Double(maxVal) + 1
{{< /highlight >}}

{{< figure src="./mov02.gif" width="30%" >}}

## タップイベント

`createBarChartView`に以下の記述を追加。

{{< highlight swift >}}
barChartView.delegate = self
{{< /highlight >}}

`ViewController`の`extension`を追加する。`chartValueSelected`メソッドでタップ時の処理を指定する。例えば次のようにすると、棒グラフの名前と値を取得できる。

{{< highlight swift >}}
extension ViewController: ChartViewDelegate {
    func chartValueSelected(_ chartView: ChartViewBase, entry: ChartDataEntry, highlight: Highlight) {
        let axisFormatter = chartView.xAxis.valueFormatter!
        let label = axisFormatter.stringForValue(entry.x, axis: nil)
        print(label, entry.y)
    }
}
{{< /highlight >}}

ちなみに、先ほど`ValueFormatter`に`items`を持たせていたため、次のようにしてitemの値を取得することも可能(あまり綺麗な方法ではないが)。

{{< highlight swift >}}
extension ViewController: ChartViewDelegate {
    func chartValueSelected(_ chartView: ChartViewBase, entry: ChartDataEntry, highlight: Highlight) {
        let valueFormatter = chartView.data?.dataSets[0].valueFormatter as! ValueFormatter
        let items = valueFormatter.items
        let index = Int(entry.x)
        print(items[index])
    }
}
{{< /highlight >}}

## 参考

- [danielgindi/Charts - GitHub](https://github.com/danielgindi/Charts)
- [Charts：タップした際の処理 - Qiita](https://qiita.com/sunskysoft/items/e6a0dff02187135f4e1a)
- [ios-chartsのグラフ表示にて、小数点を消す方法 - Qiita](https://qiita.com/unicoonn1/items/9296a109ec6cc052d53d)
- [ios charts label for every bar](https://stackoverflow.com/questions/41919209/ios-charts-label-for-every-bar)

