"""Tests for tools/analyze-log.py and tools/check.py. Run: python3 -m unittest discover tools/tests"""
import contextlib
import importlib.util
import io
import pathlib
import unittest

TOOLS = pathlib.Path(__file__).resolve().parent.parent
FIXTURE = TOOLS / "tests" / "fixtures" / "walk.jsonl"


def load(name, filename):
    spec = importlib.util.spec_from_file_location(name, TOOLS / filename)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


analyze = load("analyze_log", "analyze-log.py")
check = load("check", "check.py")


class AnalyzeLogTests(unittest.TestCase):
    def report(self):
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            analyze.main(str(FIXTURE))
        return out.getvalue()

    # REQ-LOG-04
    def test_counts_and_heard_episodes(self):
        r = self.report()
        self.assertIn("5 readings, 3 event-frames, 1 marks", r)
        # Two step events less than a second apart with the same name are one episode.
        self.assertEqual(r.count("step:Step down. d=0.44 spoken=true"), 1)
        self.assertIn("MARKED WRONG", r)

    # REQ-LOG-04
    def test_noise_floor_and_margin(self):
        r = self.report()
        self.assertIn("noise floor of |drop| on level ground", r)
        self.assertIn("max=0.006", r)
        self.assertIn("real level changes", r)
        self.assertIn("margin between noise and signal: 28x", r)
        self.assertIn("frames with no reference slice: 1/5", r)

    def test_percentile(self):
        self.assertEqual(analyze.pct([1, 2, 3, 4], 0.5), 3)
        self.assertNotEqual(analyze.pct([], 0.5), analyze.pct([], 0.5))  # NaN


class CheckTests(unittest.TestCase):
    # REQ-SAFE-01
    def test_network_pattern_catches_networking_code(self):
        for line in ["let s = URLSession.shared", "import Network", "let w = WKWebView()",
                     "var c: NWConnection?"]:
            self.assertTrue(check.NETWORK.search(line), line)
        for line in ["let url = URL(string: x)", "Link(destination: url)", "// URLSession is not used"]:
            self.assertFalse(check.NETWORK.search(line.split("//", 1)[0]), line)

    # REQ-SAFE-01, REQ-PRIV-01
    def test_repository_passes(self):
        with contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(check.main(), 0)


if __name__ == "__main__":
    unittest.main()
