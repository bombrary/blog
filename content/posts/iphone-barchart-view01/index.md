---
title: "iPhoneアプリ開発メモ - 棒グラフの作成(UIStackView) (1)"
date: 2019-12-24T13:07:39+09:00
tags: ["Swift", "iPhone", "UIKit", "UIStackView", "Visualization", "棒グラフ"]
categories: ["Swift", "iPhone", "Visualization"]
---

前に頑張ってCoreGraphicsを使って棒グラフを描いたが、やはりViewを棒に見立てて扱った方が良さそうだ。考えられる利点は次の3つ。

- タップ時に何かアクションを起こせる。例えば、棒グラフをタップしたら、そのデータに関する詳細ページに飛ぶ、などの処理が実装できる。
- アニメーションについてのコードを描きやすい。例えば棒グラフの高さを0から伸ばしていくアニメーションが実現できる。
- StackViewで棒を管理すれば、棒のサイズや棒同士の間隔を自動で設定してくれる

これはやるしかない。

基本的には[こちら](https://solidgeargroup.com/ios-simple-bar-chart-with-uisatckviews-using-swift-download-code-test-xcode/)を参考にしながら進めていく。

## UIStackViewをコード上で使う基本

とりあえず使い方を確認する。

### Main.storyboard

こんな感じにする。

{{< figure src="./storyboard_main01.png" width="50%" >}}

### ViewController.swift

{{< highlight swift >}}
class ViewController: UIViewController {
    let colors: [UIColor] = [.systemRed, .systemBlue, .systemPink, .systemGreen, .systemIndigo]
    let percentages: [CGFloat] = [0.1, 0.2, 0.5, 0.3, 0.9]
    @IBOutlet weak var graphStackView: UIStackView!
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.
        graphStackView.distribution = .fillEqually
        graphStackView.alignment = .bottom
        graphStackView.spacing = 20
        graphStackView.isLayoutMarginsRelativeArrangement = true
        graphStackView.layoutMargins.left = 20
        graphStackView.layoutMargins.right = 20
        
        for (color, percentage) in zip(colors, percentages) {
            addBar(bgColor: color, percentage: percentage)
        }
    }
    private func addBar(bgColor: UIColor, percentage: CGFloat ) {
        let view = UIView()
        let height = graphStackView.frame.height * percentage
        view.backgroundColor = bgColor
        view.heightAnchor.constraint(equalToConstant: height).isActive = true
        graphStackView.addArrangedSubview(view)
    }
}
{{< /highlight >}}


こんなに短いコードで次のような棒グラフが表現できる。

{{< figure src="./iphone01.png" width="30%" >}}

### 説明

次の事実を覚えておく:

- `stackView.axis`: 要素の並び方向を決める。`.vertical`か`.horizontal`を選べる。Storyboard上で追加する場合はいじらない。以下は全て`horizontal`での説明。
- `stackView.distribution`: 要素の並べ方を決める。`.fillEqually`にしておくと、全ての要素の幅が同じになるように並べられる。
- `stackView.alignment`: 要素の寄せ方向を決める。デフォルトは`.fill`なので、これをいじらないと高さがみんな一緒になってしまう。
- `stackView.addArrangedSubview(_:)`: stackViewの要素を追加するときはこれを利用する。

今回調べていて知った、`stackView`に限らない知見:

- Viewの余白を設定するには、`layoutMargins`を用いる。設定を反映するためには`isLayoutMarginsRelativeArrangement`を`true`にしておく必要がある。ちなみにこれはStoryboard上でも設定できる。
- 前回は`scale`関数を定義していたが、レイアウトが単純な場合は上のように`percentage`で定義しても良さそう。

## 目標

前回とつける機能はほぼ同じ。

- 横スクロールできる棒グラフを作る。
- 1ページに表示する棒は最大5本とする。

## ScrollViewの準備

### Main.storyboard

{{< figure src="./storyboard_main02.png" width="50%" >}}

### ViewController.swift

`ScrollView`からのOutlet接続を作る。`viewDidLoad`に以下の記述を追加する。

{{< highlight swift >}}
scrollView.frame = CGRect(
    x: 0,
    y: 0,
    width: scrollView.superview!.frame.width,
    height: scrollView.superview!.frame.height
)
{{< /highlight >}}

## Modelの準備

棒グラフ用のモデルを作成する。

{{< highlight swift >}}
struct BarChartModel {
    var percentage: CGFloat
    var value: Int
    var name: String
    var color: UIColor
}
{{< /highlight >}}

前回のユーティリティ関数を今回も使う。

{{< highlight swift >}}
extension Array {
    func chunked(into size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0 ..< Swift.min($0 + size, count)])
        }
    }
}
{{< /highlight >}}

`ViewController`内にデータとそのformatterを用意する。

{{< highlight swift >}}
var dataSource = [
    (7, "太郎"), (1, "次郎"), (2, "三郎"), (6, "四郎"), (3, "五郎"),
    (9, "六郎"), (2, "七郎"), (3, "八郎"), (1, "九郎"), (5, "十郎"),
    (1, "十一郎"), (1, "十二郎"), (6, "十三郎")
]
lazy var data: [[BarChartModel]] = format(dataSource)
lazy var maxVal: Int = dataSource.map({ $0.0 }).max() ?? -1


private func format(_ data: [(Int, String)]) -> [[BarChartModel]] {
    return data.map({ datum in
        let (val, name) = datum
        let percentage = CGFloat(val) / CGFloat(maxVal)
        let color: UIColor = val == maxVal ? .systemOrange : .systemBlue
        return BarChartModel(percentage: percentage, value: val, name: name, color: color)
    }).chunked(into: 5)
}
{{< /highlight >}}

## BarChartViewの準備

`BarChartView.swift`を作成する。`ViewController`に書かれていたStackViewの内容を、`BarChartView`としてまとめる。`axis`はデフォルトで`.horizontal`っぽいが、念のため明示しておく。

{{< highlight swift >}}
class BarChartView: UIStackView {

    init(frame: CGRect, barChartItems: [BarChartModel]) {
        super.init(frame: frame)
        axis = .horizontal
        distribution = .fillEqually
        alignment = .bottom
        spacing = 20
        isLayoutMarginsRelativeArrangement = true
        layoutMargins.left = 20
        layoutMargins.right = 20
        
        for item in barChartItems {
            addBar(bgColor: item.color, percentage: item.percentage)
        }
    }
    
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func addBar(bgColor: UIColor, percentage: CGFloat ) {
        let view = UIView()
        let height = frame.height * percentage
        view.backgroundColor = bgColor
        view.heightAnchor.constraint(equalToConstant: height).isActive = true
        addArrangedSubview(view)
    }
}
{{< /highlight >}}

## ページ追加

メソッド`configureScrollView`を追加する。

{{< highlight swift >}}
override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.
        scrollView.frame = CGRect(
            x: 0,
            y: 0,
            width: scrollView.superview!.frame.width,
            height: scrollView.superview!.frame.height
        )
        
        configureScrollView()
    }

private func configureScrollView() {
    scrollView.isPagingEnabled = true
    let contentsView = UIView(frame: CGRect(
        x: 0,
        y: 0,
        width: scrollView.frame.width * CGFloat(data.count),
        height: scrollView.frame.height
    ))
    scrollView.addSubview(contentsView)
    scrollView.contentSize = contentsView.frame.size
    for (i, barChartItems) in data.enumerated() {
        let widthPercentage = CGFloat(barChartItems.count) / CGFloat(data[0].count)
        let frame = CGRect(
            x: scrollView.frame.width * CGFloat(i),
            y: 0,
            width: scrollView.frame.width * widthPercentage,
            height: scrollView.frame.height
        )
        let view = BarChartView(frame: frame, barChartItems: barChartItems)
        contentsView.addSubview(view)
    }
}
{{< /highlight >}}

前回の相違点は次の2つ。

- ページViewの`frame`を`ViewController`側でやっている
- 棒の本数が5本未満だと棒が太くなってしまうため、`widthPercentage`で`BarChartView`の横幅を調整している:

{{< highlight swift >}}
let widthPercentage = CGFloat(barChartItems.count) / CGFloat(data[0].count)
let frame = CGRect(
    x: scrollView.frame.width * CGFloat(i),
    y: 0,
    width: scrollView.frame.width * widthPercentage,
    height: scrollView.frame.height
)
{{< /highlight >}}

この時点でアプリを起動すると、次のようになる。

{{< figure src="./mov01.gif" width="30%" >}}

## ラベル追加

`horizontal`の中に`vertical`を入れ子にすることで実現できる。

{{< figure src="./horizontal_vertical.svg" width="50%" >}}

次のような配分にする。要素が同じ高さでない場合、`distribution`は`fill`にする。

{{< figure src="./barContainer.svg" width="50%" >}}

`varLabelHeight`と`nameLabelHeight`は固定である。これと親ビューの高さから、`barHeight`が計算できる。これを念頭に置きながら`Constraint`を設定していく。

### BarChartView.swift

クラス先頭に定数を定義する。

{{< highlight swift >}}
let fontSize: CGFloat = 20
let textPad: CGFloat = 10
{{< /highlight >}}

`addBarContainer`を定義する。上の通りに実装する。

`barHeight`の計算方法に注目。おかしなことをすると`Constraint`でエラーを吐くので注意。

{{< highlight swift >}}
private func addBarContainer(of item: BarChartModel) {
    let valueTextHeight: CGFloat = fontSize + textPad
    let nameTextHeight: CGFloat = fontSize + textPad
    let barHeight: CGFloat = (frame.height - valueTextHeight - nameTextHeight) * item.percentage
    
    let barContainer = UIStackView()
    barContainer.axis = .vertical
    barContainer.alignment = .fill
    barContainer.distribution = .fill
    
    let valueLabel = makeBarLabel(text: "\(item.value)", fontSize: fontSize, height: valueTextHeight)
    barContainer.addArrangedSubview(valueLabel)
    
    let barView = UIView()
    barView.backgroundColor = item.color
    barView.heightAnchor.constraint(equalToConstant: barHeight).isActive = true
    barContainer.addArrangedSubview(barView)
    
    let nameLabel = makeBarLabel(text: item.name, fontSize: fontSize, height: nameTextHeight)
    barContainer.addArrangedSubview(nameLabel)
    
    addArrangedSubview(barContainer)
}
{{< /highlight >}}

`addBar`だったものを`addBarContainer`に変更する。

{{< highlight swift >}}
for item in barChartItems {
    addBarContainer(of: item)
}
{{< /highlight >}}

こんな感じになる。

{{< figure src="./iphone02.png" width="30%" >}}

## 軸(水平線)の描画

棒グラフの下に水平線を描きたい。

[こちら](https://qiita.com/kojimetal666/items/d3c674244e5312ce8cfe)を参考にする。ものすごく細い長方形を`layer`として用意して、それを棒の下に配置すれば良い。

`BarChartView`の`init`関数の末尾に以下の記述を追加する。

{{< highlight swift >}}
let border = CALayer()
let borderWidth: CGFloat = 1
border.backgroundColor = UIColor.darkGray.cgColor
border.frame = CGRect(
    x: 0,
    y: frame.height - (borderWidth/2 + fontSize + textPad),
    width: frame.width,
    height: borderWidth
)
layer.addSublayer(border)
{{< /highlight >}}

{{< figure src="./iphone03.png" width="50%" >}}

## 次回予告

- リファクタリング - `BarContainer`を別クラスに分ける
- タッチのイベント捕捉
- アニメーション

## 参考

- [iOS: Simple Bar Chart with UISatckViews](https://solidgeargroup.com/ios-simple-bar-chart-with-uisatckviews-using-swift-download-code-test-xcode/)
- [【Swift】枠線を任意の場所につける - Qiita](https://qiita.com/kojimetal666/items/d3c674244e5312ce8cfe)
