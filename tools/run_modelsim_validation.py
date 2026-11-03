"""Repeatable batch checks using the locally installed ModelSim-Altera 10.3c.

Only isolated testbench copies are instrumented: this old installation omits
Verilog console messages from its transcript, so verdicts use $fdisplay instead.
The original DUTs and testbenches are never rewritten. Every invocation creates
a new directory, and requires a PASS, normal $finish, clean process/transcript,
plus a deliberate failing canary before accepting the real test results.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import subprocess
import tempfile
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_BIN = Path("C:/altera/14.1/modelsim_ase/win32aloem")
DEFAULT_OUT = ROOT / "material/vendor_review_20261022/modelsim_validation"
HDL = ROOT / "proj/src/user_source/hdl_source"


def verdict(returncode: int, result: str, transcript: str = "") -> bool:
    """A successful exit or a PASS before a fatal error is insufficient."""
    lines = [line.strip() for line in result.splitlines() if line.strip()]
    return (
        returncode == 0
        and any(re.match(r"^PASS(?:\b|:)", line) for line in lines)
        and bool(lines) and lines[-1] == "FINISH"
        and not re.search(r"\b(?:FAIL|FATAL|ERROR)\b", result, re.I)
        and not re.search(r"\*\*\s*(?:Error|Fatal):", transcript, re.I)
    )


def call_end(text: str, opening: int) -> int:
    depth, in_string, escaped = 0, False, False
    for index in range(opening, len(text)):
        char = text[index]
        if in_string:
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == '"':
                in_string = False
        elif char == '"':
            in_string = True
        elif char == "(":
            depth += 1
        elif char == ")":
            depth -= 1
            if depth == 0:
                return index
    raise ValueError("Unterminated testbench system task")


def instrument(source: str) -> str:
    """Adapt only the three tasks used by the selected, reviewed testbenches."""
    if re.search(r"\$(?:error|warning|stop)\b", source):
        raise ValueError("Unsupported assertion task; add explicit result capture")
    pattern = re.compile(r"\$(display|fatal|finish)\b")
    fragments, offset = [], 0
    for match in pattern.finditer(source):
        if match.start() < offset:
            continue
        fragments.append(source[offset:match.start()])
        after = match.end()
        while after < len(source) and source[after].isspace():
            after += 1
        args = ""
        if source[after] == "(":
            end = call_end(source, after)
            args = source[after + 1:end]
            after = end + 1
        while after < len(source) and source[after].isspace():
            after += 1
        if source[after] != ";":
            raise ValueError("System task must be a complete statement")
        offset = after + 1
        if match[1] == "display":
            replacement = f"$fdisplay(codex_result_fd, {args});"
        elif match[1] == "fatal":
            severity, sep, message = args.partition(",")
            if not sep or severity.strip() not in ("0", "1", "2"):
                raise ValueError("Expected $fatal(severity, message, ...)")
            replacement = (
                'begin $fdisplay(codex_result_fd, "FAIL: assertion"); '
                f"$fdisplay(codex_result_fd, {message}); "
                f"$fflush(codex_result_fd); $fatal({args}); end "
            )
        else:
            replacement = (
                'begin $fdisplay(codex_result_fd, "FINISH"); '
                "$fclose(codex_result_fd); $finish; end "
            )
        fragments.append(replacement)
    fragments.append(source[offset:])
    adapted = "".join(fragments)
    declaration = re.search(r"\bmodule\s+\w+\s*;", adapted)
    if not declaration:
        raise ValueError("Expected a no-port testbench module")
    index = declaration.end()
    return (
        adapted[:index]
        + '\ninteger codex_result_fd = $fopen("result.txt", "w");\n'
        + adapted[index:]
    )


def run_command(command: list[str], folder: Path, name: str, timeout: int = 180) -> dict:
    process = subprocess.run(command, cwd=folder, capture_output=True, timeout=timeout)
    output = (process.stdout + process.stderr).decode("utf-8", errors="replace")
    (folder / f"{name}.log").write_text(output, encoding="utf-8")
    return {"command": command, "returncode": process.returncode, "output": output}


def simulate(binary: Path, folder: Path, name: str, source: str, dependencies: list[Path]) -> dict:
    folder.mkdir()
    (folder / f"{name}.sv").write_text(instrument(source), encoding="utf-8")
    steps = []
    for command, log_name in [
        ([str(binary / "vmap.exe"), "-c"], "vmap"),
        ([str(binary / "vlib.exe"), "work"], "vlib"),
        ([str(binary / "vlog.exe"), "-sv", "-work", "work"]
         + [str(path) for path in dependencies] + [f"{name}.sv"], "compile"),
    ]:
        step = run_command(command, folder, log_name)
        steps.append(step)
        if step["returncode"] or re.search(r"\*\*\s*(?:Error|Fatal):", step["output"]):
            return {"name": name, "pass": False, "steps": steps, "result": "", "stage": log_name}
    (folder / "run.do").write_text(
        "transcript on\nonerror {quit -force -code 1}\n"
        f"vsim -onfinish exit work.{name}\n"
        "run -all\nquit -force -code 0\n", encoding="ascii"
    )
    step = run_command([str(binary / "vsim.exe"), "-c", "-do", "run.do"], folder, "run")
    steps.append(step)
    result_path = folder / "result.txt"
    result = result_path.read_text(encoding="utf-8", errors="replace") if result_path.exists() else ""
    transcript_path = folder / "transcript"
    transcript = step["output"]
    if transcript_path.exists():
        transcript += transcript_path.read_text(encoding="utf-8", errors="replace")
    return {
        "name": name, "pass": verdict(step["returncode"], result, transcript),
        "steps": steps, "result": result, "stage": "run",
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bin", type=Path, default=DEFAULT_BIN)
    parser.add_argument("--output-root", type=Path, default=DEFAULT_OUT)
    args = parser.parse_args()
    args.output_root.mkdir(parents=True, exist_ok=True)
    folder = Path(tempfile.mkdtemp(prefix=datetime.now().strftime("run_%Y%m%d_%H%M%S_"), dir=args.output_root))
    summary = {"run_directory": str(folder), "tests": [], "canary_rejected": False, "success": False}
    try:
        summary["version"] = run_command([str(args.bin / "vsim.exe"), "-version"], folder, "version")
        if summary["version"]["returncode"]:
            raise RuntimeError("ModelSim version query failed")
        canary_source = '''`timescale 1ns/1ps
module tb_runner_canary;
initial begin
 #1; $display("PASS: this marker alone must not pass");
 #1; $fatal(1, "intentional canary failure");
 $finish;
end
endmodule
'''
        canary = simulate(args.bin, folder / "canary", "tb_runner_canary", canary_source, [])
        summary["canary"] = canary
        summary["canary_rejected"] = (
            not canary["pass"] and canary["stage"] == "run"
            and "PASS: this marker" in canary["result"]
            and "FAIL: assertion" in canary["result"]
            and "intentional canary failure" in canary["result"]
            and "FINISH" not in canary["result"]
        )
        if not summary["canary_rejected"]:
            raise RuntimeError("Canary did not execute and fail as intended")
        print("PASS runner canary: earlier PASS followed by $fatal was rejected", flush=True)
        cases = {
            "tb_pcm_mix16": [HDL / 'pcm_mix16.v'],
            "tb_video_rgb_to_axis_640x480": [HDL / 'video_rgb_to_axis_640x480.v'],
            "tb_picture_controls": [HDL / 'picture_controls.v'],
            "tb_bmp_scaling": [HDL / 'SD/bmp_read.v', HDL / 'SD/bmp_scale_stream.v', HDL / 'SD/bmp_scale_quality.v', HDL / 'SD/bmp_bilinear_stream.v'],
            "tb_spectrum_quality_display": [HDL / 'audio_spectrum_quality.v'],
        }
        for name, dependencies in cases.items():
            original = ROOT / "sim" / f"{name}.v"
            test = simulate(args.bin, folder / name, name, original.read_text(encoding="utf-8"), dependencies)
            test["source_sha256"] = {
                str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest()
                for path in [original] + dependencies
            }
            summary["tests"].append(test)
            print(f"{'PASS' if test['pass'] else 'FAIL'} {name}: {test['result'].strip()}", flush=True)
        summary["success"] = all(test["pass"] for test in summary["tests"])
        return 0 if summary["success"] else 1
    except (OSError, ValueError, RuntimeError, subprocess.TimeoutExpired) as error:
        summary["error"] = str(error)
        print(f"FAIL: {error}", flush=True)
        return 1
    finally:
        (folder / "summary.json").write_text(json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8")
        print(f"Evidence: {folder}", flush=True)


if __name__ == "__main__":
    raise SystemExit(main())
