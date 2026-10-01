import tempfile
from pathlib import Path
import unittest

import driver


class DriverTests(unittest.TestCase):
    def test_selects_only_authorized_physical_device(self):
        output = (
            "List of devices attached\n"
            "emulator-5554 device product:test\n"
            "phone-a device product:phone\n"
            "phone-b unauthorized\n"
        )
        self.assertEqual(driver.select_device(driver.parse_devices(output)), "phone-a")

    def test_requires_explicit_choice_for_multiple_phones(self):
        devices = [("one", "device"), ("two", "device")]
        with self.assertRaises(driver.DriverError):
            driver.select_device(devices)
        self.assertEqual(driver.select_device(devices, "two"), "two")

    def test_never_falls_back_to_emulator_or_unauthorized_device(self):
        with self.assertRaises(driver.DriverError):
            driver.select_device([("emulator-5554", "device")])
        with self.assertRaises(driver.DriverError):
            driver.select_device([("phone", "unauthorized")], "phone")

    def test_parses_xml_surrounded_by_adb_output(self):
        root = driver.parse_hierarchy(
            'status\n<?xml version="1.0"?><hierarchy><node /></hierarchy>\nUI hierarchy dumped'
        )
        self.assertEqual(root.tag, "hierarchy")
        with self.assertRaises(driver.DriverError):
            driver.parse_hierarchy("ERROR: could not get idle state")

    def test_uses_localized_navigation_bounds_not_fixed_coordinates(self):
        root = driver.parse_hierarchy(
            '<?xml version="1.0"?><hierarchy>'
            f'<node package="{driver.PACKAGE}" content-desc="文件&#10;第 2 个标签" '
            'clickable="true" enabled="true" bounds="[100,800][300,900]" />'
            f'<node package="{driver.PACKAGE}" text="文件" '
            'clickable="true" enabled="true" bounds="[0,0][200,100]" />'
            '</hierarchy>'
        )
        self.assertEqual(driver.tab_center(root, "files"), (200, 850))
        with self.assertRaises(driver.DriverError):
            driver.tab_center(root, "settings")

    def test_ignores_other_apps_disabled_controls_and_invalid_bounds(self):
        root = driver.parse_hierarchy(
            '<?xml version="1.0"?><hierarchy>'
            '<node package="other.app" text="Files" clickable="true" bounds="[1,2][3,4]" />'
            f'<node package="{driver.PACKAGE}" text="Files" clickable="true" enabled="false" bounds="[1,2][3,4]" />'
            f'<node package="{driver.PACKAGE}" text="Files" clickable="true" bounds="bad" />'
            '</hierarchy>'
        )
        with self.assertRaises(driver.DriverError):
            driver.tab_center(root, "files")

    def test_reads_java_properties_windows_paths(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "local.properties"
            path.write_text("# ignored=x\nflutter.sdk=D:\\\\SDK\\\\flutter\n", encoding="utf-8")
            self.assertEqual(driver.properties(path), {"flutter.sdk": "D:\\SDK\\flutter"})


if __name__ == "__main__":
    unittest.main()
