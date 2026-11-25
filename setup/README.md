# SYNC_FireFX のZIP配布

`make_release_zip.bat` を実行すると、ビルド済みの `SYNC_FireFX.auf2` を `SYNC_FireFX.zip` へ梱包し、`SYNC_FireFX.catalog.json` の末尾バージョンへ同梱した AUF2 の XXH3-128 を設定します。

## 作成前の準備

- Win64 Release 構成の本体を用意します。標準の参照先は `C:\ProgramData\aviutl2\Plugin\SYNC_FireFX` です。
- 初回リリースは **v1.0.0** です。JSON の `release_date` は実際の公開日に合わせます。
- ハッシュ計算には `xxhsum.exe` を使用します。`Win64\Dependencies\xxHash-0.8.4\xxhsum.exe` へ配置するか、PATH へ登録します。[xxHash 公式 Windows 版 v0.8.4](https://github.com/Cyan4973/xxHash/releases/tag/v0.8.4)

```bat
setup\make_release_zip.bat
```

参照先は引数で指定できます。

```bat
setup\make_release_zip.bat -ReleaseDirectory "D:\Release\SYNC_FireFX" -XxhsumPath "D:\Tools\xxhsum.exe"
```

## ZIPの内容

```text
SYNC_FireFX/
  SYNC_FireFX.auf2
  README.md
  LICENSE
  THIRD_PARTY_NOTICES.md
  ThirdParty/
    LICENSE.AviUtl2-SDK.txt
```

カタログでのインストールはダウンロードと展開の後、`SYNC_FireFX` フォルダを `{pluginsDir}/SYNC_FireFX` へコピーします。アンインストールでは ZIP からインストールしたファイルのみを個別に削除します。

バッチは ZIP をローカルに作成します。GitHub のリリースを公開する際は、タグ `v1.0.0` に ZIP とカタログ JSON を添付します。
