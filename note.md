# SYNC_FireFX 作業ノート

## プロジェクト

- `D:\DelphiProg\MyApp\SYNC_FireFX`。Delphi プロジェクト名は `SYNC_FireFX`、登録名は「火演出」、ラベルは「SYNC」。
- 仕様書の原文は `docs/SPECIFICATION.md`。作業とビルドの規則は WeatherFX の `note.md` から本プロジェクトに適用できる箇所を引き継いだ。
- Delphi 37.0 / Win64。IDE で開くファイルは `SYNC_FireFX.dproj`。本番はメディア入力用の `SYNC_FireFX.auf2` 1本。初回リリースの表示バージョンと製品バージョンは v1.0.0。
- SDK の型、共通登録、プロジェクト設定とライセンスを継承した。編集APIを型付きにして、登録項目の配列を128枠へ拡張した。SDK のレコードの位置は公式ヘッダーに合わせる。

## ビルド

```powershell
cmd /c 'call "C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat" && msbuild SYNC_FireFX.dproj /t:Rebuild /p:Config=Debug /p:Platform=Win64'
cmd /c 'call "C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat" && msbuild SYNC_FireFX.dproj /t:Rebuild /p:Config=Release /p:Platform=Win64'
```

- 両構成の出力先は `C:\ProgramData\aviutl2\Plugin\SYNC_FireFX\`。継承したビルド後イベントが DLL を AUF2 へコピーし、元の DLL を削除する。Release では RSM も削除する。最終配置は Release。
- DCU は `Win64\Debug\DCU` と `Win64\Release\DCU`。デバッガーホストは両構成ともコピー元の `D:\aviutl2_v2.1.16\aviutl2.exe`。
- `FireFX_Shader.rc` で HLSL を AUF2 に格納する。シェーダーは最初のGPU描画時に一度コンパイルする。
- 追加ユニットは DPR と DPROJ に両方登録する。開いている DPR / DPROJ を外部で更新した場合は IDE で開き直す。

## 描画

- `FireFX_Settings` はパラメータ、範囲、12プリセット、`FireFX_Parameters` は折りたたみ項目とプリセット適用を担当する。選択セレクタの値は描画に使用せず、ボタンで個別の値を編集APIへ設定する。
- X、Y、Z、拡大率、透明度は AviUtl2 の基底オブジェクトで調整する。火演出はシーン中央を原点とする画像を生成し、配置はホストの標準描画に任せる。
- `FireFX_Scene` は火元を疑似3D空間へ配置し、奥行順に炎を作る。風、揺らぎ、発光、干渉面に沿う炎、煙、火の粉、赤熱を時刻から求める。物体との干渉は各炎の進行方向と底面の交点を使う近似。
- `FireFX_Field` は CPU 描画と GPU へ渡す定数の配置を管理する。GPU は `FireFX_GPU` と `Source/Shaders/FireFX.hlsl` で描画する。シェーダー API を呼べないときは CPU で描画し、負荷の高い炎や煙だけ評価解像度を下げる。
- 陽炎は GPU で取得できた背景テクスチャを局所的にずらして合成する。2Dの標準描画を対象とする。背景コピーに失敗する場面では陽炎を省略する。
- 消火は `GetObjectTrackValue` で火力トラックを参照する。過去の描画順に依存しない。火力の変化方向を取得できない場面では、点火用の火花を抑制する。
- 画像はシーン寸法で生成する。上限は一辺16384、全体33554432画素。

## 検査

```powershell
& .\Tests\run_tests.ps1
& .\Tests\run_tests.ps1 -Benchmark
```

- 本番 AUF2 の公開関数、設定、時系列の動作を検査する。D3D11 デバイス上でシェーダーを実行し、CPU との出力と背景サンプルを照合する。検査結果の PNG は `Win64\Verification` 以下に保存される。
- SDK の ABI は [公式 SDK](https://spring-fragrance.mints.ne.jp/aviutl/) の2026年11月21日版を照合に使用。AviUtl2 本体での使用確認とコールバックの単体検査は別扱い。
- 2026年11月24日、Win64 Debug / Release の Rebuild はどちらも警告0件・エラー0件。両構成の本番 AUF2 が、12プリセット、火力による点火と消火、シーク時の再現性、物体干渉、D3D11 の描画と背景屈折の検査に合格した。AviUtl2 と Delphi IDE の画面確認は未実施。
- Release の1080p火災プリセットを検査EXEで測定した結果は、D3D11実機18.1 ms/フレーム（読み戻しを含む）、CPU代替180.5 ms/フレーム。ログは `Win64\BuildLogs`、プリセット見本は `Win64\Verification\Preview.png`。
- 同日の仕様変更で火演出の「基本設定」グループを削除した。Debug / Release の Rebuild は警告0件・エラー0件。両構成で、登録項目からの削除、ホスト描画パラメータの維持、CPU / D3D11 描画を確認した。最終配置は Release。ログは `Win64\BuildLogs\BaseObject`。

## setup

- WeatherFX の配布バッチを継承した。`setup\make_release_zip.bat` で `SYNC_FireFX.zip` を生成し、`SYNC_FireFX.catalog.json` のハッシュを更新する。手順は `setup/README.md`。
- カタログは v1.0.0 から開始する。インストールのコピー先は `{pluginsDir}/SYNC_FireFX`。アンインストールは同じフォルダを1工程で削除する。
- 配布 ZIP の初回作成では xxHash 公式 v0.8.4 の Windows 版を使用した。取得した ZIP の SHA-256 は `58e3dcb7063eb3829418453702556cdb2b52e7c9082215fcd4e9135fabbd4ed9`。
- v1.0.0 は Win64 Debug / Release とも警告0件・エラー0件で描画検査に合格した。配布 ZIP の5ファイル、AUF2 の XXH3-128 `fc9da8f2f94e14b309e2b46f6e1bcae8`、再実行時のカタログ不変を検証した。検査ログは `Win64\BuildLogs\v1.0.0`。カタログの公開日欄は `2026-11-24` に設定した。

## AviUtl2カタログ登録時の共通ルール

1. **概要は35文字以内。** `Setup/*.catalog.json` の `summary` は、JSONのエスケープ表記ではなく実際の表示文字列を数える。機能の詳細や補足は概要に詰め込まず、説明・READMEに記載する。
2. **既存タグを優先する。** [公開カタログの `index.json`](https://github.com/Neosku/aviutl2-catalog-data/blob/main/index.json) で、同じ製品や近い用途に使われているタグの表記を確認し、用途を表すものだけを選ぶ。同義語を重ねたり、製品ごとに新しいタグを量産したりしない。
3. **配布専用フォルダー単位で導入・削除する。** ZIP内を製品専用フォルダーにまとめ、ダウンロード・展開後の配置はフォルダーの `copy` 1件、アンインストールはその専用フォルダーだけを指定する `delete` 1件を基本とする。共有フォルダーや、ユーザー素材・設定を含むフォルダーは一括削除しない。既存パッケージで変更する際は、配布ZIPの配置とセットアップスクリプトの検証条件も確認し、整合しない場合は既存の手順を維持する。
