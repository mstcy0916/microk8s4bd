
# **Black Duck products for MicroK8s**
ブラック・ダック・ソフトウェア製品をMicroK8sで動作させた際の手順をスクリプト化したものです

## Black Duck (SCA) / bd-ctrl.sh
### 使用方法
#### インストール
```bash
./bd-ctrl.sh install
```
```bash
bash <(curl -sSL https://raw.githubusercontent.com/mstcy0916/microk8s4bds/refs/heads/main/bd-ctrl.sh) install
```
#### アップグレード
```bash
./bd-ctrl.sh upgrade
```
```bash
bash <(curl -sSL https://raw.githubusercontent.com/mstcy0916/microk8s4bds/refs/heads/main/bd-ctrl.sh) upgrade
```
#### アンインストール
```bash
./bd-ctrl.sh uninstall
```
```bash
bash <(curl -sSL https://raw.githubusercontent.com/mstcy0916/microk8s4bds/refs/heads/main/bd-ctrl.sh) uninstall
```
### 動作の前提条件
#### MicroK8s
* MicroK8sがインストールされている必要があります
* MicroK8でdns、hostpath-storageを有効にしている必要があります
* ネットワークはNodePortで30443ポートを使用した構成です
#### Black Duck (SCA)
* ハードウェア要件を10sphとしています（現在、10sphは非推奨）
* SSL/TLS証明書は考慮していません
* PostgreSQLは内部のインスタンスを使用します
* データのバックアップ、リストアは考慮していません
* このスクリプトではBinaryやAlertは起動しません
* 実行したフォルダ内に「bds_repo」フォルダが作成されます
