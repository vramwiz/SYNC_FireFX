# SYNC_FireFX の作業規則

- 作業開始時に `note.md` を読む。仕様は `docs/SPECIFICATION.md`、使い方は `README.md` を参照する。
- 本番プロジェクトは `SYNC_FireFX.dproj` の1つ。検査用 EXE からも同じ `SYNC_FireFX.auf2` を読み込む。
- Delphi 37.0 の `rsvars.bat` を呼び、MSBuild で Win64 Debug / Release の両方をビルドする。警告・エラーと AUF2 の生成を確認し、最後に Release を配置する。
- ユニット追加時は DPR の `in` と DPROJ の `DCCReference` を更新し、必要なフォルダーを検索パスに加える。
- 日本語を含む PAS、DPR、PowerShell は UTF-8 BOM と CRLF を使う。公開処理の入出力、重要な副作用、ホスト資源の有効範囲と所有権を明記する。
- 設定、GUI、描画を分ける。SDK の構造体を変更するときは公式ヘッダーと照合する。ホストのポインターをコールバック後まで保持せず、DLL 境界から例外を漏らさない。
- 通常のビルドと検査はコマンドラインで行う。IDE と AviUtl2 の画面操作は、ユーザーが明示的に依頼したときに行う。
- 元の WeatherFX、ユーザーの AUP2、他のプラグインを変更しない。`setup` はユーザーの指定どおり WeatherFX の内容を保持する。
