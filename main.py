import argparse
import yaml
import json
import logging
import sys

from test_driver import TestDriver

logging.basicConfig(format="[%(levelname)s] %(asctime)s %(message)s", level=logging.INFO)

if __name__ == "__main__":
    # 初始化argparse
    parser = argparse.ArgumentParser()
    parser.add_argument("-c", "--config", help="config file path (default: config.yml)", default="config.yml")
    args = parser.parse_args()
    config_file = args.config

    config = None
    with open(config_file, "r") as f:
        config = yaml.load(f, Loader=yaml.SafeLoader)
    if config is None:
        raise Exception(f"Error: Config {config_file} is invalid")
    provider = config.get("provider", {})
    gateway = provider.get("gateway", "http://localhost:8081")
    test_driver = TestDriver(gateway, max_retry=config.get("max_retry", 3), timeout=config.get("timeout", 60))

    with open("workload.json", "r") as f:
        workloads = json.load(f)

    with open("warmup.json", "r") as f:
        warmup = json.load(f)

    failed_num = 0
    succeed_num = 0
    if len(warmup) != 0:
        failed_num, succeed_num = test_driver.warmup(warmup, config["functions"])
    try:
        metric_text = test_driver.get_metrics()
        if metric_text is not None:
            with open("/run/warmup_metrics.output", "w") as f:
                f.write(metric_text)
        test_driver.cleanup_metric()
    except Exception as e:
        logging.error(f"cleanup metric after warmup failed: {e}")
    else:
        logging.info(f"warm up finished: failed num {failed_num}, succeed num {succeed_num} !")
        failed_num, succeed_num = test_driver.test(workloads, config["functions"])
        logging.info(f"test succeed and finish: failed num {failed_num} succeed_num {succeed_num} !")
