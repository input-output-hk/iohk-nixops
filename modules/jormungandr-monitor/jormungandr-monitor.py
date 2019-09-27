#!/usr/bin/env python

from prometheus_client import Gauge
from prometheus_client import Summary
from prometheus_client import start_http_server
from numbers import Number
import netifaces as ni
import json
import random
import time
from dateutil.parser import parse
import sys, warnings, os, traceback, subprocess

EXPORTER_PORT = int(os.getenv('PORT', '8000'), 10)
SLEEP_TIME = 10
JORMUNGANDR_API = os.getenv('JORMUNGANDR_API', 'http://127.0.0.1:3101/api')
ADDRESSES = os.getenv('MONITOR_ADDRESSES', '').split()
NODE_METRICS = [
    "blockRecvCnt",
    "lastBlockDate",
    "lastBlockFees",
    "lastBlockHash",
    "lastBlockHeight",
    "lastBlockSum",
    "lastBlockTime",
    "lastBlockTx",
    "txRecvCnt",
    "uptime",
]

# Create a metric to track time spent and requests made.
JORMUNGANDR_METRICS_REQUEST_TIME = Summary('jormungandr_metrics_process_time', 'Time spent processing jormungandr metrics')
JORMUNGANDR_ADDRESSES_REQUEST_TIME = Summary('jormungandr_addresses_process_time', 'Time spent processing jormungandr addresses')

jormungandr_node = { metric: Gauge(f'jormungandr_{metric}', 'Jormungandr {metric}') for metric in NODE_METRICS }

jormungandr_funds = {}
jormungandr_counts = {}
for address in ADDRESSES:
    jormungandr_funds[address] = Gauge(f'jormungandr_address_{address}_funds', f'Jormungandr Address {address} funds in Lovelace')
    jormungandr_counts[address] = Gauge(f'jormungandr_address_{address}_counts', f'Jormungandr Address {address} counter')


# Decorate function with metric.
@JORMUNGANDR_METRICS_REQUEST_TIME.time()
def process_jormungandr_metrics():
    metrics = jcli_rest(['node', 'stats', 'get'])
    metrics['lastBlockTime'] = parse(metrics['lastBlockTime']).timestamp()
    for metric, gauge in jormungandr_node.items():
        gauge.set(sanitize(metrics[metric]))

@JORMUNGANDR_ADDRESSES_REQUEST_TIME.time()
def process_jormungandr_addresses():
    for address in ADDRESSES:
        data = jcli_rest(['account', 'get', address])
        jormungandr_funds[address].set(sanitize(data['value']))
        jormungandr_counts[address].set(sanitize(data['counter']))

def sanitize(metric):
    if isinstance(metric, str):
        try:
            metric = float(metric)
        except ValueError:
            try:
                metric = int(metric, 16)
            except ValueError:
                metric = False
    elif not isinstance(metric, (float, int)):
        metric = False
    return metric

def jcli_rest(args):
    flags = ['--host', JORMUNGANDR_API, '--output-format', 'json']
    params = ['@jcli@', 'rest', 'v0'] + args + flags
    result = subprocess.run(params, stdout = subprocess.PIPE)
    return json.loads(result.stdout)

if __name__ == '__main__':
    # Start up the server to expose the metrics.
    start_http_server(EXPORTER_PORT)
    # Main Loop: Process all API's and sleep for a certain amount of time
    while True:
        try:
            process_jormungandr_metrics()
            process_jormungandr_addresses()
        except:
            traceback.print_exc(file=sys.stdout)
            print("failed to process jormungandr metrics")
            for gauge in jormungandr_funds.values(): gauge.set(False)
            for gauge in jormungandr_counts.values(): gauge.set(False)
            for gauge in jormungandr_node.values(): gauge.set(False)
        time.sleep(SLEEP_TIME)
