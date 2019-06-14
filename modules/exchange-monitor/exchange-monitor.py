from prometheus_client import Gauge
from prometheus_client import Summary
from prometheus_client import start_http_server
import requests
import json
import random
import time
import urllib.request
import sys

#Create a metric to track time spent and requests made.
EXPORTER_PORT = 8000
SLEEP_TIME = 300 # 5 minutes
BINANCE_REQUEST_TIME = Summary('binance_process_time', 'Time spent processing binance assets')
BITTREX_REQUEST_TIME = Summary('bittrex_process_time', 'Time spent processing bittrex assets')
BITHUMB_REQUEST_TIME = Summary('bithumb_process_time', 'Time spent processing bithumb assets')
binance_deposits = Gauge('binance_deposits', 'Binance Deposits enabled')
binance_withdraws = Gauge('binance_withdraws', 'Binance Withdraws enabled')
bittrex_active = Gauge('bittrex_active', 'Bittrex Wallet enabled')
bittrex_withdraw_queue_depth = Gauge('bittrex_withdraw_queue_depth', 'Bittrex Withdraw Queue Depth')
bithumb_active = Gauge('bithumb_active', 'Bithumb Wallet enabled')

# Decorate function with metric.
@BINANCE_REQUEST_TIME.time()
def process_binance_assets():
    url = "https://www.binance.com/assetWithdraw/getAllAsset.html"
    json_obj = urllib.request.urlopen(url)
    crypto_assets = json.loads(json_obj.read().decode('utf-8'))
    print("processing binance assets")
    for crypto_asset in crypto_assets:
        if crypto_asset['assetCode']== 'ADA':
            binance_deposits.set(crypto_asset['enableCharge'])
            binance_withdraws.set(crypto_asset['enableWithdraw'])
    sys.stdout.flush()

# Decorate function with metric.
@BITTREX_REQUEST_TIME.time()
def process_bittrex_assets():
    url = "https://bittrex.com/api/v2.0/pub/currencies/GetWalletHealth"
    json_obj = urllib.request.urlopen(url)
    crypto_assets = json.loads(json_obj.read().decode('utf-8'))["result"]
    print("processing bittrex assets")
    for crypto_asset in crypto_assets:
        if crypto_asset['Health']['Currency'] == "ADA":
            bittrex_active.set(crypto_asset['Health']['IsActive'])
            bittrex_withdraw_queue_depth.set(crypto_asset['Health']['WithdrawQueueDepth'])
    sys.stdout.flush()

        # Decorate function with metric.
@BITHUMB_REQUEST_TIME.time()
def process_bithumb_assets():
    url = "https://api.bithumb.com/public/ticker/ADA"
    json_obj = urllib.request.urlopen(url)
    crypto_assets = json.loads(json_obj.read().decode('utf-8'))
    print("processing bithumb assets")
    for crypto_asset in crypto_assets:
        if crypto_asset['status']== '0000':
        bithumb_active.set(crypto_asset['Health']['IsActive'])
    sys.stdout.flush()

if __name__ == '__main__':
    # Start up the server to expose the metrics.
    start_http_server(EXPORTER_PORT)
    # Main Loop: Process all API's and sleep for a certain amount of time
    while True:
        try:
            process_binance_assets()
        except:
            print("failed to process binance assets")
            binance_deposits.set(False)
            binance_withdraw.set(False)
        try:
            process_bittrex_assets()
        except:
            print("failed to process bittrex assets")
            bittrex_active.set(False)
            bittrex_withdraw_queue_depth.set(False)
        try:
            process_bithumb_assets()
         except:
            print("failed to process bittrex assets")
            bithumb_active.set(False)
        time.sleep(SLEEP_TIME)
