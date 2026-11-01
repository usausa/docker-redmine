# vendor/ — zip 配布プラグインの置き場

git clone できない zip 配布のプラグインをここに置きます。ビルド時に `Dockerfile` が
`plugins/` へ展開します。**空でもビルドは成功します。**

## 置くもの

| ファイル | 内容 | 入手元 |
|---|---|---|
| `redmine_checklists-4_1_1-light.zip` | RedmineUP Checklists の **Light 版（無償）** | <https://www.redmineup.com/pages/plugins/checklists> |

## 配置後の確認

zip の中身がプラグインディレクトリ名から始まる構造であること。

```bash
unzip -l vendor/redmine_checklists-4_1_1-light.zip | head -5
```

`redmine_checklists/...` のように**ディレクトリ名から始まっていれば** そのままで問題ありません。
ファイルが直下に展開される構造の場合は `Dockerfile` の `unzip` 先を調整してください。

## 注意

- zip は **`.gitignore` で Git 管理外**にしています（ライセンス物のため）
- **版とセットで別途保管**してください。どの版を入れたか分からなくなると再構築できません
- このプラグインが無いと、**チェックリストの完了数から進捗率を計算する運用ができません**
