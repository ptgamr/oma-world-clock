import re
import unittest
from pathlib import Path


ROOT = Path(__file__).parents[1]


class QmlSecurityTests(unittest.TestCase):
    def test_all_text_elements_force_plain_text(self):
        text_elements = 0
        plain_text_declarations = 0
        for path in ROOT.rglob("*.qml"):
            source = path.read_text(encoding="utf-8")
            text_elements += len(re.findall(r"(?m)^\s*Text\s*\{", source))
            plain_text_declarations += len(
                re.findall(r"(?m)^\s*textFormat:\s*Text\.PlainText\s*$", source)
            )
        self.assertGreater(text_elements, 0)
        self.assertEqual(plain_text_declarations, text_elements)


if __name__ == "__main__":
    unittest.main()
