"""試作をデモ盤面で数秒動かし、スマホで見る用の GIF と PNG を snapshots/ に書き出す。

使い方: python tools/snapshot.py
出力:   snapshots/latest.gif, snapshots/latest.png（と日時つきの控え）
"""
import datetime
import glob
import os
import shutil
import subprocess
import sys
import tempfile

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GAME = os.path.join(ROOT, "game")
OUT = os.path.join(ROOT, "snapshots")


def find_godot() -> str:
    env = os.environ.get("GODOT")
    if env:
        return env
    hits = glob.glob(os.path.expanduser(
        "~/AppData/Local/Microsoft/WinGet/Packages/GodotEngine.GodotEngine_*/Godot_v*_console.exe"))
    found = shutil.which("godot")
    if hits:
        return sorted(hits)[-1]
    if found:
        return found
    sys.exit("Godot が見つからない。環境変数 GODOT に実行ファイルの場所を入れてください")


def main() -> None:
    os.makedirs(OUT, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        frames_dir = os.path.join(tmp, "frames")
        subprocess.run([find_godot(), "--path", GAME, "--", "--demo", f"--shots={frames_dir}"],
                       check=True, timeout=120, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        files = sorted(glob.glob(os.path.join(frames_dir, "frame_*.png")))
        if not files:
            sys.exit("フレームが撮れていない")
        frames = [Image.open(f).convert("RGB").resize((640, 360)) for f in files]
        stamp = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
        gif = os.path.join(OUT, "latest.gif")
        frames[0].save(gif, save_all=True, append_images=frames[1:], duration=100, loop=0, optimize=True)
        png = os.path.join(OUT, "latest.png")
        shutil.copy(files[-1], png)
        shutil.copy(gif, os.path.join(OUT, f"{stamp}.gif"))
    print(gif)
    print(png)


if __name__ == "__main__":
    main()
