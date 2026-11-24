# ライセンスと共通基盤の由来

火演出（SYNC_FireFX）: Copyright (c) 2026 VRAMの魔術師

本体のソースコードは参考元と同じ GNU General Public License v3.0（GPL-3.0-only）です。全文は [LICENSE](LICENSE) を参照してください。SDK 由来の定義には、次の MIT ライセンスの表示も同梱します。

## AviUtl ExEdit2 Plugin SDK

- 著作権: Copyright (c) 2025 Kenkun
- ライセンス: MIT
- 対象: `Source/Lib/AviUtl2FilterTypes.pas` の SDK 型定義、コールバックと編集 API の ABI 定義
- ライセンス全文: [ThirdParty/LICENSE.AviUtl2-SDK.txt](ThirdParty/LICENSE.AviUtl2-SDK.txt)

SDK の著作権表示と MIT ライセンス全文を維持しています。

## 継承元

- **SYNC_WeatherFX**: Delphi プロジェクト、ビルドイベント、DLL の公開関数、SDK 型定義、項目の登録、作業規則、setup の直接の継承元です。
- **SYNC_AquaFX**: WeatherFX の共通基盤と配布処理の継承元です。
- **SYNC_ParticleFX**: SYNC_AquaFX の共通基盤と配布処理の継承元です。
- **SYNC_Mine（SYNC_MINE）**: SYNC_ParticleFX のプロジェクト・SDK 定義・配布処理の継承元です。
- **SYNC_PhotoShot**: Win64 のビルド設定・ビルドイベントの継承元です。
- **SYNC_Nicomea**: SYNC_Mine のプロジェクトと共通基盤の移植元です。
- **Syncroh2 / SYNC_Lyrics**: `PluginFilterTable.pas` の元となるフィルターテーブル登録処理です。
- **Aul2AudioFilter**: 継承元が参考にした、選択リスト・設定ボタンと編集 API による標準項目への一括反映方式の由来です。

本体は Delphi RTL を使用します。AviUtl2 本体と Delphi の開発環境は同梱しません。外部の画像・写真・キャラクター素材は組み込んでいません。
