#!/usr/bin/env python3
"""通过 Flutter、Gradle 和 ADB 构建、安装、驱动 RemoteSend。仅依赖 Python 标准库。"""

import argparse
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time
import uuid
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[3]
PACKAGE = "com.remotesend.remote_send"
TABS = {"files": {"文件", "Files"}, "text": {"文本", "Text"}, "settings": {"设置", "Settings"}}
ARTIFACTS = ROOT / "build" / "run-remotesend"


class DriverError(RuntimeError):
    pass


def properties(path):
    if not path.is_file():
        return {}
    result = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        if "=" in line and not line.lstrip().startswith("#"):
            key, value = line.split("=", 1)
            result[key.strip()] = value.strip().replace("\\\\", "\\").replace("\\:", ":")
    return result


def execute(args, *, env=None, capture=False, timeout=120):
    args = [str(arg) for arg in args]
    print("+ " + subprocess.list2cmdline(args), flush=True)
    if os.name == "nt" and args[0].lower().endswith((".bat", ".cmd")):
        args = [os.environ.get("COMSPEC", "cmd.exe"), "/d", "/c", *args]
    result = subprocess.run(
        args, cwd=ROOT, env=env, timeout=timeout,
        stdout=subprocess.PIPE if capture else None,
        stderr=subprocess.STDOUT if capture else None,
    )
    output = result.stdout.decode("utf-8", errors="replace") if capture else ""
    if result.returncode:
        raise DriverError(f"命令失败（退出码 {result.returncode}）：\n{output}")
    return output


class Tools:
    def __init__(self):
        local = properties(ROOT / "android" / "local.properties")
        self.flutter_root = Path(os.environ.get("FLUTTER_ROOT") or local.get("flutter.sdk") or "D:/SDK/flutter")
        default_sdk = Path(os.environ.get("LOCALAPPDATA", "~")) / "Android" / "sdk"
        self.sdk = Path(os.environ.get("ANDROID_SDK_ROOT") or os.environ.get("ANDROID_HOME") or local.get("sdk.dir") or default_sdk).expanduser()
        self.flutter = self.flutter_root / "bin" / ("flutter.bat" if os.name == "nt" else "flutter")
        self.adb = self.sdk / "platform-tools" / ("adb.exe" if os.name == "nt" else "adb")
        self.gradle = ROOT / "android" / ("gradlew.bat" if os.name == "nt" else "gradlew")
        self.env = dict(os.environ)
        self.env["PUB_CACHE"] = os.environ.get("PUB_CACHE") or str(self.flutter_root.parent / "Pub")
        self.env["PYTHONIOENCODING"] = "utf-8"

    def require(self, *tools):
        for tool in tools:
            if not tool.is_file():
                raise DriverError(f"找不到工具：{tool}。请检查 FLUTTER_ROOT、ANDROID_SDK_ROOT 和现有 SDK 安装。")

    def flutter_command(self, *args, timeout=900):
        self.require(self.flutter)
        return execute([self.flutter, *args], env=self.env, timeout=timeout)

    def adb_command(self, serial, *args, timeout=45):
        self.require(self.adb)
        return execute([self.adb, "-s", serial, *args], env=self.env, capture=True, timeout=timeout)


def parse_devices(output):
    devices = []
    for line in output.splitlines():
        fields = line.split()
        if len(fields) >= 2 and not line.startswith(("List of", "*")):
            devices.append((fields[0], fields[1]))
    return devices


def select_device(devices, requested=None):
    if requested:
        if (requested, "device") in devices:
            return requested
        raise DriverError("指定设备未连接或未授权。请解锁手机并确认 USB 调试授权。")
    phones = [serial for serial, state in devices if state == "device" and not serial.startswith("emulator-")]
    if len(phones) != 1:
        raise DriverError("需要唯一一台已授权真机；多设备时通过 --device 或 ANDROID_SERIAL 明确选择。不会猜测或默认安装到模拟器。")
    return phones[0]


def device(tools, requested):
    tools.require(tools.adb)
    output = execute([tools.adb, "devices", "-l"], env=tools.env, capture=True)
    print(output, end="")
    return select_device(parse_devices(output), requested or os.environ.get("ANDROID_SERIAL"))


def parse_hierarchy(output):
    start, end = output.find("<?xml"), output.rfind("</hierarchy>")
    if start < 0 or end < 0:
        raise DriverError("未取得有效界面层级；请保持手机解锁且没有系统授权弹窗。")
    try:
        return ET.fromstring(output[start:end + len("</hierarchy>")])
    except ET.ParseError as error:
        raise DriverError("ADB 返回的界面 XML 不完整。") from error


def label(node):
    return (node.get("text") or node.get("content-desc") or "").split("\n", 1)[0].strip()


def tab_center(root, tab):
    candidates = []
    for node in root.iter("node"):
        if node.get("package") != PACKAGE or node.get("enabled") == "false":
            continue
        if label(node) not in TABS[tab] or node.get("clickable") != "true":
            continue
        match = re.fullmatch(r"\[(\d+),(\d+)\]\[(\d+),(\d+)\]", node.get("bounds", ""))
        if match:
            left, top, right, bottom = map(int, match.groups())
            if right > left and bottom > top:
                candidates.append(((left + right) // 2, (top + bottom) // 2))
    if not candidates:
        raise DriverError(f"未找到可点击的 {tab} 导航；请解锁手机，检查应用是否正常启动。")
    return max(candidates, key=lambda point: point[1])


def hierarchy(tools, serial):
    return parse_hierarchy(tools.adb_command(serial, "exec-out", "uiautomator", "dump", "/dev/tty", timeout=20))


def wait_for_tab(tools, serial, tab):
    deadline = time.monotonic() + 45
    last_error = None
    while time.monotonic() < deadline:
        try:
            root = hierarchy(tools, serial)
            return root, tab_center(root, tab)
        except (DriverError, subprocess.TimeoutExpired) as error:
            last_error = error
            time.sleep(1)
    raise DriverError(f"等待应用导航超时：{last_error}")


def screenshot(tools, serial):
    root = hierarchy(tools, serial)
    if not any(node.get("package") == PACKAGE for node in root.iter("node")):
        raise DriverError("RemoteSend 不在可见界面，拒绝截取其他应用或锁屏。请先解锁并启动 RemoteSend。")
    data = subprocess.check_output([str(tools.adb), "-s", serial, "exec-out", "screencap", "-p"], timeout=30)
    if not data.startswith(b"\x89PNG\r\n\x1a\n"):
        raise DriverError("截图数据不是有效 PNG。")
    ARTIFACTS.mkdir(parents=True, exist_ok=True)
    stamp = time.strftime("%Y%m%d-%H%M%S") + "-" + uuid.uuid4().hex[:8]
    path = ARTIFACTS / (stamp + ".png")
    with path.open("xb") as output:
        output.write(data)
    report = {
        "screenshot": str(path),
        "package": PACKAGE,
        "camera_button_visible": any(label(node) in {"拍照", "Take photo"} for node in root.iter("node") if node.get("package") == PACKAGE),
    }
    path.with_suffix(".json").write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return path


def build(tools, direct):
    tools.require(tools.flutter, tools.gradle, tools.adb)
    if not shutil.which("java", path=tools.env.get("PATH")) and not tools.env.get("JAVA_HOME"):
        raise DriverError("缺少 JDK；请设置 JAVA_HOME。")
    local = ROOT / "android" / "local.properties"
    if not local.exists():
        with local.open("x", encoding="utf-8") as output:
            output.write(f"flutter.sdk={tools.flutter_root.resolve().as_posix()}\nsdk.dir={tools.sdk.resolve().as_posix()}\n")
    tools.flutter_command("pub", "get")
    args = [tools.gradle, "-p", ROOT / "android"]
    if direct:
        args += ["-Dhttp.proxyHost=", "-Dhttps.proxyHost=", "-Dhttp.nonProxyHosts=*", "-Dhttps.nonProxyHosts=*"]
    args += [
        "-Ptarget-platform=android-arm64", f"-Ptarget={ROOT / 'lib' / 'main.dart'}",
        "-Pbase-application-name=android.app.Application", "-Pdart-obfuscation=false",
        "-Ptrack-widget-creation=true", "-Ptree-shake-icons=false", "assembleDebug",
    ]
    execute(args, env=tools.env, timeout=1500)
    apk = ROOT / "build" / "app" / "outputs" / "flutter-apk" / "app-debug.apk"
    if not apk.is_file():
        raise DriverError(f"构建成功但未发现预期 APK：{apk}")
    return apk


def launch_and_drive(tools, serial, tab):
    output = tools.adb_command(serial, "shell", "am", "start", "-W", "-n", PACKAGE + "/.MainActivity")
    print(output, end="")
    if "Status: ok" not in output:
        raise DriverError("应用启动未返回 Status: ok。")
    _, (x, y) = wait_for_tab(tools, serial, tab)
    tools.adb_command(serial, "shell", "input", "tap", str(x), str(y))
    time.sleep(1)
    wait_for_tab(tools, serial, tab)
    return screenshot(tools, serial)


def main():
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
        sys.stderr.reconfigure(encoding="utf-8", errors="replace")
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--device", help="ADB 序列号；默认仅自动选择唯一已授权真机")
    parser.add_argument("--direct", action="store_true", help="仅该次 Gradle 构建直连，覆盖失效代理，不改全局配置")
    parser.add_argument("--tab", choices=TABS, default="files", help="只导航，不拍照、不发送、不修改设置")
    parser.add_argument("command", choices=["doctor", "build", "run", "drive", "screenshot", "stop", "test"])
    args = parser.parse_args()
    tools = Tools()
    if args.command == "doctor":
        print(f"项目：{ROOT}\nFlutter：{tools.flutter_root}\nAndroid SDK：{tools.sdk}\nPub：{tools.env['PUB_CACHE']}")
        tools.flutter_command("--version", timeout=120)
        java = Path(tools.env["JAVA_HOME"]) / "bin" / ("java.exe" if os.name == "nt" else "java") if tools.env.get("JAVA_HOME") else "java"
        execute([java, "-version"])
        print("已选择设备：" + device(tools, args.device))
    elif args.command == "test":
        tools.flutter_command("test", "--no-pub")
    elif args.command == "build":
        print("APK：" + str(build(tools, args.direct)))
    else:
        serial = device(tools, args.device)
        if args.command == "run":
            abi = tools.adb_command(serial, "shell", "getprop", "ro.product.cpu.abilist")
            if "arm64-v8a" not in abi:
                raise DriverError("该驱动只构建已验证的 arm64 APK，目标设备不支持 arm64-v8a。")
            apk = build(tools, args.direct)
            output = tools.adb_command(serial, "install", "-r", str(apk), timeout=180)
            print(output, end="")
            if not re.search(r"^Success\s*$", output, re.MULTILINE):
                raise DriverError("覆盖安装未成功；不会尝试卸载或清除数据。")
            launch_and_drive(tools, serial, args.tab)
        elif args.command == "drive":
            launch_and_drive(tools, serial, args.tab)
        elif args.command == "screenshot":
            screenshot(tools, serial)
        elif args.command == "stop":
            tools.adb_command(serial, "shell", "am", "force-stop", PACKAGE)
            print("已停止 RemoteSend；没有卸载或清除数据。")


if __name__ == "__main__":
    try:
        main()
    except (DriverError, subprocess.SubprocessError, OSError) as error:
        print(f"运行失败：{error}", file=sys.stderr)
        sys.exit(1)
