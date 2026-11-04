import importlib.util
import os
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path


MODULE_PATH = Path(__file__).parents[1] / "bin" / "swayidle_laptop.py"
SPEC = importlib.util.spec_from_file_location("swayidle_laptop", MODULE_PATH)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class SleepPolicyTests(unittest.TestCase):
    def test_power_change_after_battery_timeout(self):
        policy = MODULE.SleepPolicy(300, 1800)
        attempts = []
        policy.mark_idle("battery", 300)
        self.assertFalse(policy.suspend_if_due("ac", 301, lambda: attempts.append("ac")))
        self.assertTrue(policy.suspend_if_due("battery", 301, lambda: attempts.append("battery")))
        self.assertEqual(attempts, ["battery"])

    def test_resume_cancels_pending_sleep_and_post_wake_loop(self):
        policy = MODULE.SleepPolicy(300, 1800)
        attempts = []
        policy.mark_idle("battery", 300)
        policy.resume()
        self.assertFalse(policy.suspend_if_due("battery", 301, lambda: attempts.append("suspend")))
        policy.mark_idle("battery", 302)
        self.assertTrue(policy.suspend_if_due("battery", 303, lambda: attempts.append("suspend")))
        self.assertEqual(attempts, ["suspend"])

    def test_resume_during_suspend_prevents_second_suspend(self):
        policy = MODULE.SleepPolicy(300, 1800)
        policy.mark_idle("battery", 300)

        def suspend_with_concurrent_resume():
            policy.resume()
            return True

        self.assertTrue(policy.suspend_if_due("battery", 301, suspend_with_concurrent_resume))
        self.assertFalse(policy.suspend_if_due("battery", 302, lambda: 0))

    def test_suspend_success_blocks_until_resume_event(self):
        policy = MODULE.SleepPolicy(300, 1800)
        policy.mark_idle("battery", 300)
        self.assertTrue(policy.suspend_if_due("battery", 301, lambda: True))
        self.assertFalse(policy.suspend_if_due("battery", 302, lambda: True))

    def test_suspend_failure_reports_and_retries_after_new_window(self):
        policy = MODULE.SleepPolicy(300, 1800)
        attempts = []
        policy.mark_idle("battery", 300)
        self.assertTrue(policy.suspend_if_due("battery", 301, lambda: False))
        self.assertFalse(policy.suspend_if_due("battery", 302, lambda: True))

        def retry_suspend():
            attempts.append("retry")
            return True

        self.assertTrue(policy.suspend_if_due("battery", 601, retry_suspend))
        self.assertEqual(attempts, ["retry"])

    def test_new_power_event_reanchors_idle_earlier(self):
        policy = MODULE.SleepPolicy(300, 1800)
        policy.mark_idle("battery", 400)
        policy.mark_idle("ac", 1800)
        self.assertTrue(policy.suspend_if_due("ac", 1800, lambda: True))

    def test_power_read_failure_disables_suspend(self):
        with tempfile.TemporaryDirectory() as directory:
            missing = Path(directory) / "AC" / "online"
            self.assertIsNone(MODULE.read_power_source(missing))


class HelperProcessTests(unittest.TestCase):
    def test_single_swayidle_child_receives_events_and_terminates_cleanly(self):
        with tempfile.TemporaryDirectory() as directory:
            runtime = Path(directory)
            fake = runtime / "swayidle"
            fake.write_text(
                "#!/usr/bin/env bash\n"
                "printf '%s\\n' \"$@\" > \"$FAKE_SWAYIDLE_ARGS\"\n"
                "printf '%s\\n' \"$$\" >> \"$FAKE_SWAYIDLE_PIDS\"\n"
                "exec sleep 3600\n"
            )
            fake.chmod(0o755)
            arguments = runtime / "arguments"
            pids = runtime / "pids"
            environment = dict(
                os.environ,
                PATH=f"{runtime}:{os.environ['PATH']}",
                FAKE_SWAYIDLE_ARGS=str(arguments),
                FAKE_SWAYIDLE_PIDS=str(pids),
            )
            command = [
                sys.executable, str(MODULE_PATH),
                "--lock-timeout", "300", "--screen-timeout", "600",
                "--battery-sleep-timeout", "300", "--ac-sleep-timeout", "1800",
            ]
            helper = subprocess.Popen(command, env=environment)
            try:
                for _ in range(100):
                    if pids.exists():
                        break
                    time.sleep(0.1)
                child_arguments = arguments.read_text().splitlines()
                self.assertEqual(child_arguments[0], "-w")
                self.assertIn("600", child_arguments)
                self.assertIn("1800", child_arguments)
                self.assertIn(f"kill -USR1 {helper.pid}", child_arguments)
                self.assertIn(f"kill -USR2 {helper.pid}", child_arguments)
                self.assertIn(f"kill -CONT {helper.pid}", child_arguments)
                self.assertIn("before-sleep", child_arguments)
                self.assertIn("swaylock -f", child_arguments)
                self.assertEqual(len(pids.read_text().splitlines()), 1)
            finally:
                helper.terminate()
                self.assertEqual(helper.wait(10), 0)
                fake_pid = int(pids.read_text())
                with self.assertRaises(ProcessLookupError):
                    os.kill(fake_pid, 0)


if __name__ == "__main__":
    unittest.main()
