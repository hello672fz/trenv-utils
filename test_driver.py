import gevent
from gevent import monkey

monkey.patch_all()

import requests
from requests.adapters import HTTPAdapter
from time import time
import random
from typing import Dict, List
import logging
import os


class TestDriver:
    def __init__(self, gateway: str, *, timeout: int = 60, max_retry: int = 3):
        self.gateway = gateway
        self.max_retry = max_retry
        self.timeout = timeout
        s = requests.Session()
        adapter = HTTPAdapter(pool_maxsize=500)
        s.mount("http://", adapter)
        s.mount("https://", adapter)
        self.http = s

    def invoke(self, lambda_name: str, request_body):
        # Perform a single request to one lambda
        retry_count = 0
        response = None
        error = None
        e2e_latency = 0
        while response is None or response.status_code != 200:
            start = time()
            try:
                response = self.http.post(
                    f"{self.gateway}/invoke/{lambda_name}",
                    json=request_body,
                    timeout=self.timeout,
                )
                if response.status_code != 200:
                    raise RuntimeError(f"[{response.status_code} {response.reason}] {response.text}")
            except Exception as e:
                logging.warning(f"invoke {lambda_name} try {retry_count}th failed: {e}")
                error = e
                if retry_count == self.max_retry:
                    break
                gevent.sleep(0.5 * (2**retry_count))
                retry_count += 1
            else:
                e2e_latency = time() - start
                error = None
        if error is not None or response is None:
            logging.error(f"invoke {lambda_name} FINALLY failed: {error}")
            raise RuntimeError(f"Max retry limit exceeded: {error}")
        if response.text is None or response.text == "":
            raise RuntimeError(f"Empty response from {lambda_name}")
        try:
            data = response.json()
            latency = data.get("latency")
        except Exception as e:
            logging.error(f"Failed to parse JSON from response: {response.text}")
            latency = None
            data = None
        # if latency is None:
        #     raise RuntimeError(f"Invalid response from {lambda_name}")
        res = {"e2e_latency": e2e_latency, "latency": latency, "data": data, "retry_count": retry_count}
        logging.info("%s %s", lambda_name, {"e2e_latency": e2e_latency, "latency": latency, "retry_count": retry_count})
        # response = self.http.get(
        #     f"{self.gateway}/danger/kill",
        #     timeout=self.timeout,
        # )
        # if response.status_code != 200:
        #     raise RuntimeError(f"kill instance error: [{response.status_code} {response.reason}] {response.text}")
        # os.system("sleep 1 && echo 1 > /proc/sys/vm/drop_caches")
        return res

    def warmup(self, warmup: Dict[str, List[int]], functions: dict):
        """
        Return: (failed_nr, succeed_nr)
        """
        logging.info("START warmup...")
        jobs = {}
        total_timeout = 0
        for func, invokes in warmup.items():
            if total_timeout == 0:
                total_timeout = len(invokes)
            else:
                assert total_timeout == len(invokes)
            func_jobs = []
            conf = functions[func]
            request_body = conf.get("request_body")
            for t, invoke_num in enumerate(invokes):
                for _ in range(invoke_num):
                    g = gevent.spawn_later(t + random.random(), self.invoke, func, request_body)
                    func_jobs.append(g)
            jobs[func] = func_jobs
        # result = gevent.joinall(sum(jobs.values(), []), timeout=int(total_timeout * 1.2))
        result = gevent.joinall(sum(jobs.values(), []), timeout=int(3))
        failed_nr, succeed_nr = 0, 0
        for g in result:
            if g.successful():
                succeed_nr += 1
            else:
                failed_nr += 1
        return failed_nr, succeed_nr

    def cleanup_metric(self):
        response = requests.delete(
            f"{self.gateway}/system/metrics",
            timeout=self.timeout,
        )
        if response.status_code != 200:
            logging.error(f"cleanup_metric failed: [{response.status_code} {response.reason}] {response.text}")
            raise RuntimeError(f"[{response.status_code} {response.reason}] {response.text}")

    def test(self, workloads: Dict[str, List[int]], functions: dict):
        """Test functions
        Return: (failed_nr, succeed_nr)
        """
        logging.info("START test...")
        jobs = {}
        total_timeout = 0
        for func, arrival_invokes in workloads.items():
            if total_timeout == 0:
                total_timeout = len(arrival_invokes)
            else:
                assert total_timeout == len(arrival_invokes)
            func_jobs = []
            conf = functions[func]
            request_body = conf.get("request_body")
            for t, invoke_num in enumerate(arrival_invokes):
                for _ in range(invoke_num):
                    g = gevent.spawn_later(t + random.random(), self.invoke, func, request_body)
                    func_jobs.append(g)
            jobs[func] = func_jobs
        # result = gevent.joinall(sum(jobs.values(), []), timeout=int(total_timeout * 1.2))
        result = gevent.joinall(sum(jobs.values(), []), timeout=int(3))
        failed_nr, succeed_nr = 0, 0
        for g in result:
            if g.successful():
                succeed_nr += 1
            else:
                failed_nr += 1
        return failed_nr, succeed_nr

    # return string
    def get_metrics(self):
        try:
            response = self.http.get(
                f"{self.gateway}/system/metrics",
                timeout=self.timeout,
            )
            if response.status_code != 200:
                raise RuntimeError(f"[{response.status_code} {response.reason}] {response.text}")
        except Exception as e:
            logging.error(f"request for /system/metrics failed: {e}")
            return None
        else:
            return response.text
