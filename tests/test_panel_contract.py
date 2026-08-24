import unittest
from pathlib import Path


ROOT = Path(__file__).parents[1]
PANEL_SOURCE = (ROOT / "Panel.qml").read_text(encoding="utf-8")


def qml_function_body(source, name):
    marker = f"function {name}("
    start = source.index(marker)
    opening_brace = source.index("{", start)
    depth = 0
    for index in range(opening_brace, len(source)):
        if source[index] == "{":
            depth += 1
        elif source[index] == "}":
            depth -= 1
            if depth == 0:
                return source[opening_brace + 1:index]
    raise AssertionError(f"Unterminated QML function: {name}")


class PanelContractTests(unittest.TestCase):
    def test_open_resets_planning_time_and_location_hover(self):
        body = qml_function_body(PANEL_SOURCE, "open")
        self.assertIn("root.resetToNow()", body)
        self.assertIn("root.resetLocationHover()", body)

    def test_location_hover_reset_requires_new_pointer_movement(self):
        reset_body = qml_function_body(PANEL_SOURCE, "resetLocationHover")
        self.assertIn("root.selectedIndex = -1", reset_body)
        self.assertIn("root.cursorActive = false", reset_body)
        self.assertIn("root.locationHoverSuppressed = true", reset_body)
        self.assertIn("Number.NaN", reset_body)

        tracking_body = qml_function_body(PANEL_SOURCE, "trackLocationPointer")
        self.assertIn("if (!hasPreviousPosition)", tracking_body)
        self.assertIn("return false", tracking_body)

    def test_pointer_selection_does_not_reveal_or_scroll_rows(self):
        selection_body = qml_function_body(PANEL_SOURCE, "selectLocation")
        self.assertIn("if (reveal !== false) root.revealSelection()", selection_body)

        for function_name in (
            "trackLocationPointer",
            "handleLocationPointer",
            "clickLocation",
            "beginDrag",
        ):
            body = qml_function_body(PANEL_SOURCE, function_name)
            self.assertIn("root.selectLocation(index, false)", body)


if __name__ == "__main__":
    unittest.main()
