#!/usr/bin/env python3
import argparse
import os
import signal
import subprocess
import sys
import time
from pathlib import Path


class SleepPolicy:
    def __init__(self, battery_timeout, ac_timeout):
        self.timeouts = {"battery": battery_timeout, "ac": ac_timeout}
        self.due = set()
        self.idle_since = None
        self.suspended = False

    def mark_idle(self, power, now):
        self.due.add(power)
        anchor = now - self.timeouts[power]
        self.idle_since = anchor if self.idle_since is None else min(self.idle_since, anchor)

    def resume(self):
        self.due.clear()
        self.idle_since = None
        self.suspended = False

    def suspend_if_due(self, power, now, suspend):
        if self.suspended or self.idle_since is None or power not in self.due:
            return False
        if now - self.idle_since < self.timeouts[power]:
            return False
        self.suspended = True
        if suspend():
            return True
        self.suspended = False
        self.idle_since = now
        return True


def read_power_source(path="/sys/class/power_supply/AC/online"):
    try:
        value = Path(path).read_text(encoding="ascii").strip()
    except (OSError, UnicodeError):
        return None
    return {"0": "battery", "1": "ac"}.get(value)


def swayidle_command(arguments, process_id):
    reset = f"kill -CONT {process_id}"
    restore = f'swaymsg "output * power on"; {reset}'
    return [
        "swayidle", "-w",
        "timeout", str(arguments.lock_timeout), "swaylock -f", "resume", reset,
        "timeout", str(arguments.screen_timeout), 'swaymsg "output * power off"', "resume", restore,
        "timeout", str(arguments.battery_sleep_timeout), f"kill -USR1 {process_id}", "resume", reset,
        "timeout", str(arguments.ac_sleep_timeout), f"kill -USR2 {process_id}", "resume", reset,
        "before-sleep", "swaylock -f", "lock", "swaylock -f",
        "unlock", 'pkill -xu "$USER" -SIGUSR1 swaylock',
    ]


def suspend_system():
    try:
        completed = subprocess.run(["systemctl", "suspend"], check=False, timeout=30)
    except (OSError, subprocess.TimeoutExpired) as error:
        print(f"swayidle-laptop: suspend failed: {error}", file=sys.stderr)
        return False
    if completed.returncode:
        print(f"swayidle-laptop: suspend failed ({completed.returncode})", file=sys.stderr)
        return False
    return True


def main():
    parser = argparse.ArgumentParser()
    for name in ("lock_timeout", "screen_timeout", "battery_sleep_timeout", "ac_sleep_timeout"):
        parser.add_argument(f"--{name.replace('_', '-')}", type=int, required=True)
    arguments = parser.parse_args()
    policy = SleepPolicy(arguments.battery_sleep_timeout, arguments.ac_sleep_timeout)
    stopping = False

    def stop(_signum, _frame):
        nonlocal stopping
        stopping = True

    for event, handler in {
        signal.SIGUSR1: lambda _signum, _frame: policy.mark_idle("battery", time.monotonic()),
        signal.SIGUSR2: lambda _signum, _frame: policy.mark_idle("ac", time.monotonic()),
        signal.SIGCONT: lambda _signum, _frame: policy.resume(),
        signal.SIGTERM: stop,
        signal.SIGINT: stop,
        signal.SIGHUP: stop,
    }.items():
        signal.signal(event, handler)

    def attempt_suspend(power, now):
        signal.pthread_sigmask(signal.SIG_BLOCK, {signal.SIGCONT})
        try:
            policy.suspend_if_due(power, now, suspend_system)
        finally:
            signal.pthread_sigmask(signal.SIG_UNBLOCK, {signal.SIGCONT})

    child = subprocess.Popen(swayidle_command(arguments, str(os.getpid())))
    warned = False
    try:
        while child.poll() is None and not stopping:
            power = read_power_source()
            if power is None:
                if not warned:
                    print("swayidle-laptop: cannot read AC power state; suspend disabled", file=sys.stderr)
                warned = True
            else:
                warned = False
                attempt_suspend(power, time.monotonic())
            time.sleep(1)
    finally:
        if child.poll() is None:
            child.terminate()
            try:
                child.wait(5)
            except subprocess.TimeoutExpired:
                child.kill()
                child.wait()
    return 0 if stopping else child.returncode


if __name__ == "__main__":
    raise SystemExit(main())
