#!/usr/bin/env python3
"""
GenerateBuildInfo.py - Comprehensive build-information generator.

Reads a JSON context file produced by CMake (via GenerateBuildInfo.cmake),
augments it with runtime-gathered data (git, CPU, memory, disk, CI, Python
environment), then writes a detailed build-info report in one of four formats:
  txt  - human-readable table (default)
  json - machine-readable JSON
  yaml - YAML (PyYAML if installed; built-in serializer otherwise)
  ini  - INI / configparser format

Usage
-----
  python3 GenerateBuildInfo.py \\
      --context  <cmake-context.json> \\
      --output   <output-file>        \\
      --format   <txt|json|yaml|ini>  \\
      [--target-binary <path-to-built-binary>] \\
      [--source-dir    <project-source-dir>]

The context JSON is created by the _gbinfo_write_context_json() function inside
GenerateBuildInfo.cmake and contains all variables that CMake knows at
configure-time.  This script then enriches the report with data that is easier
to collect in Python (git, system resources, CI detection, binary hashing).
"""

from __future__ import annotations

import argparse
import configparser
import datetime
import hashlib
import json
import os
import platform
import re
import shutil
import socket
import subprocess
import sys
from pathlib import Path
from typing import Any, Dict, List, Optional

# ---------------------------------------------------------------------------
# Version of this generator (bump when the schema changes in a breaking way)
# ---------------------------------------------------------------------------
_GENERATOR_VERSION = "2.0"


# ===========================================================================
# Utility helpers
# ===========================================================================


def _run(cmd: List[str], cwd: Optional[str] = None, timeout: int = 8) -> str:
    """Execute *cmd* and return stdout as a stripped string, or '' on failure."""
    try:
        r = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=timeout,
            cwd=cwd,
            check=False,
        )
        return r.stdout.strip()
    except Exception:
        return ""


def _file_sha256(path: str) -> str:
    """Return hex SHA-256 digest of *path*, or '' if unavailable."""
    try:
        h = hashlib.sha256()
        with open(path, "rb") as fh:
            for chunk in iter(lambda: fh.read(65536), b""):
                h.update(chunk)
        return h.hexdigest()
    except Exception:
        return ""


def _file_sha512(path: str) -> str:
    """Return hex SHA-512 digest of *path*, or '' if unavailable."""
    try:
        h = hashlib.sha512()
        with open(path, "rb") as fh:
            for chunk in iter(lambda: fh.read(65536), b""):
                h.update(chunk)
        return h.hexdigest()
    except Exception:
        return ""


def _file_size(path: str) -> int:
    """Return file size in bytes, or 0 if unavailable."""
    try:
        return Path(path).stat().st_size
    except Exception:
        return 0


def _human_size(n: int) -> str:
    """Format *n* bytes as a human-readable string."""
    for unit in ("B", "KB", "MB", "GB"):
        if n < 1024:
            return f"{n:.1f} {unit}"
        n //= 1024  # type: ignore[assignment]
    return f"{n:.1f} TB"


def _env(key: str, default: str = "") -> str:
    return os.environ.get(key, default)


def _infer_build_type_from_binary_path(binary_path: str) -> str:
    """Infer CMake build type from binary path (e.g. .../Release/foo.dll or .../Debug/...).
    Used when context has empty build_type (multi-config generators like Visual Studio).
    """
    if not binary_path:
        return ""
    path_n = binary_path.replace("\\", "/")
    for cfg in ("Release", "Debug", "RelWithDebInfo", "MinSizeRel"):
        if f"/{cfg}/" in path_n:
            return cfg
    return ""


# ===========================================================================
# Data collectors
# ===========================================================================


def _submodule_git_dir(source_dir: str) -> Optional[str]:
    """If *source_dir* is a git submodule (.git is a file with gitdir: ...), return resolved git dir."""
    git_file = Path(source_dir) / ".git"
    if not git_file.is_file():
        return None
    try:
        line = git_file.read_text(encoding="utf-8", errors="replace").strip()
        if line.startswith("gitdir:"):
            raw = line[7:].strip()
            resolved = (git_file.parent / raw).resolve()
            if resolved.exists():
                return str(resolved)
    except Exception:
        pass
    return None


def collect_git_info(source_dir: Optional[str]) -> Dict[str, Any]:
    """Return a dict with git repository metadata from *source_dir*.
    When *source_dir* is a submodule (.git file), uses that repo so the commit is the submodule's.
    """
    git = shutil.which("git")
    if not git:
        return {"available": False, "reason": "git not found in PATH"}
    if not source_dir or not Path(source_dir).exists():
        return {"available": False, "reason": "source_dir not found"}

    cwd = str(source_dir)
    env = os.environ.copy()
    submodule_git_dir = _submodule_git_dir(cwd)
    if submodule_git_dir:
        env["GIT_DIR"] = submodule_git_dir

    def g(*args: str) -> str:
        try:
            r = subprocess.run(
                [git, *args],
                capture_output=True,
                text=True,
                timeout=8,
                cwd=cwd,
                env=env,
                check=False,
            )
            return r.stdout.strip()
        except Exception:
            return ""

    # Verify this is actually a git repo
    toplevel = g("rev-parse", "--show-toplevel")
    if not toplevel:
        return {"available": False, "reason": "not a git repository"}

    branch = g("rev-parse", "--abbrev-ref", "HEAD")
    commit_hash = g("rev-parse", "HEAD")
    commit_short = g("rev-parse", "--short", "HEAD")
    commit_msg = g("log", "-1", "--format=%s")
    commit_author = g("log", "-1", "--format=%an <%ae>")
    commit_date = g("log", "-1", "--format=%ci")
    tag = g("describe", "--tags", "--exact-match", "HEAD")
    nearest_tag = g("describe", "--tags", "--abbrev=0")
    dirty_out = g("status", "--porcelain")
    origin = g("remote", "get-url", "origin")
    commit_count = g("rev-list", "--count", "HEAD")
    contributors = g("shortlog", "-sn", "--no-merges", "HEAD")

    # Ahead / behind upstream (may fail if no upstream is configured)
    upstream_raw = g("rev-list", "--count", "--left-right", "@{upstream}...HEAD")
    ahead = behind = ""
    if upstream_raw and "\t" in upstream_raw:
        parts = upstream_raw.split()
        if len(parts) == 2:
            behind, ahead = parts

    return {
        "available": True,
        "is_submodule": submodule_git_dir is not None,
        "repository_root": toplevel,
        "toplevel": toplevel,
        "branch": branch or "unknown",
        "commit_hash": commit_hash or "unknown",
        "commit_short": commit_short or "unknown",
        "commit_message": commit_msg or "",
        "commit_author": commit_author or "",
        "commit_date": commit_date or "",
        "tag": tag or "",
        "nearest_tag": nearest_tag or "",
        "dirty": bool(dirty_out.strip()),
        "origin_url": origin or "",
        "commit_count": commit_count or "",
        "commits_ahead": ahead,
        "commits_behind": behind,
        "contributors": (
            [l.strip() for l in contributors.splitlines()[:10]] if contributors else []
        ),
    }


def collect_platform_info() -> Dict[str, Any]:
    """Return OS / hardware / architecture details."""
    info: Dict[str, Any] = {
        "os": platform.system(),
        "os_release": platform.release(),
        "os_version": platform.version(),
        "node": platform.node(),
        "machine": platform.machine(),
        "processor": platform.processor() or platform.machine(),
        "architecture": platform.architecture()[0],
        "endianness": sys.byteorder + "-endian",
        "python_bits": "64-bit" if sys.maxsize > 2**32 else "32-bit",
    }

    # Logical CPU count
    try:
        import multiprocessing

        info["cpu_logical_count"] = multiprocessing.cpu_count()
    except Exception:
        info["cpu_logical_count"] = "unknown"

    # Physical core count (best-effort)
    try:
        import os as _os

        count = len(
            set(
                line.split(":")[1].strip()
                for line in open("/proc/cpuinfo")
                if line.startswith("core id")
            )
        )
        info["cpu_physical_count"] = count
    except Exception:
        pass

    # Windows extras
    if platform.system() == "Windows":
        try:
            info["windows_edition"] = platform.win32_edition()  # type: ignore[attr-defined]
        except AttributeError:
            pass
        ver = platform.win32_ver()
        info["windows_ver"] = " ".join(v for v in ver[:3] if v).strip()

    # Linux extras
    if platform.system() == "Linux":
        distro_info = ""
        try:
            import distro as _distro  # type: ignore

            distro_info = f"{_distro.name()} {_distro.version()}"
        except ImportError:
            try:
                text = Path("/etc/os-release").read_text()
                for line in text.splitlines():
                    if line.startswith("PRETTY_NAME="):
                        distro_info = line.split("=", 1)[1].strip().strip('"')
                        break
            except Exception:
                distro_info = "unknown"
        info["linux_distro"] = distro_info

        # Kernel version
        kernel = _run(["uname", "-r"])
        if kernel:
            info["kernel_version"] = kernel

    # macOS extras
    if platform.system() == "Darwin":
        info["macos_ver"] = platform.mac_ver()[0]

    return info


def collect_cpu_info() -> Dict[str, Any]:
    """Return CPU brand, features, and frequency info."""
    info: Dict[str, Any] = {}

    # CPU brand string
    brand = ""
    if platform.system() == "Windows":
        out = _run(["wmic", "cpu", "get", "Name", "/VALUE"])
        m = re.search(r"Name=(.+)", out)
        brand = m.group(1).strip() if m else ""
    elif platform.system() == "Linux":
        try:
            for line in open("/proc/cpuinfo"):
                if "model name" in line:
                    brand = line.split(":", 1)[1].strip()
                    break
        except Exception:
            pass
    elif platform.system() == "Darwin":
        brand = _run(["sysctl", "-n", "machdep.cpu.brand_string"])

    if brand:
        info["brand"] = brand

    # CPU frequency (best-effort)
    if platform.system() == "Linux":
        try:
            freq_raw = Path(
                "/sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_max_freq"
            ).read_text()
            info["max_freq_mhz"] = int(freq_raw.strip()) // 1000
        except Exception:
            pass
    elif platform.system() == "Windows":
        out = _run(["wmic", "cpu", "get", "MaxClockSpeed", "/VALUE"])
        m = re.search(r"MaxClockSpeed=(\d+)", out)
        if m:
            info["max_freq_mhz"] = int(m.group(1))

    # SIMD feature detection (x86 only via cpuid - best-effort via /proc/cpuinfo on Linux)
    if platform.system() == "Linux":
        try:
            flags_line = ""
            for line in open("/proc/cpuinfo"):
                if line.startswith("flags"):
                    flags_line = line.split(":", 1)[1].strip()
                    break
            if flags_line:
                flags = set(flags_line.split())
                simd_features = []
                for feat in (
                    "sse",
                    "sse2",
                    "sse3",
                    "ssse3",
                    "sse4_1",
                    "sse4_2",
                    "avx",
                    "avx2",
                    "avx512f",
                    "fma",
                    "bmi1",
                    "bmi2",
                ):
                    if feat in flags:
                        simd_features.append(feat.replace("_", ".").upper())
                if simd_features:
                    info["simd_features"] = simd_features
        except Exception:
            pass

    return info


def collect_memory_info() -> Dict[str, Any]:
    """Return physical memory stats."""
    info: Dict[str, Any] = {}
    try:
        if platform.system() == "Linux":
            with open("/proc/meminfo") as f:
                for line in f:
                    if line.startswith("MemTotal:"):
                        info["total_mb"] = int(line.split()[1]) // 1024
                    elif line.startswith("MemAvailable:"):
                        info["available_mb"] = int(line.split()[1]) // 1024
        elif platform.system() == "Windows":
            out = _run(
                [
                    "wmic",
                    "OS",
                    "get",
                    "TotalVisibleMemorySize,FreePhysicalMemory",
                    "/VALUE",
                ]
            )
            for line in out.splitlines():
                if "TotalVisibleMemorySize=" in line:
                    info["total_mb"] = int(line.split("=")[1].strip()) // 1024
                if "FreePhysicalMemory=" in line:
                    info["available_mb"] = int(line.split("=")[1].strip()) // 1024
        elif platform.system() == "Darwin":
            total = _run(["sysctl", "-n", "hw.memsize"])
            if total:
                info["total_mb"] = int(total) // (1024 * 1024)
    except Exception:
        pass
    return info


def collect_disk_info(path: str) -> Dict[str, Any]:
    """Return disk usage for the filesystem containing *path*."""
    try:
        usage = shutil.disk_usage(path)
        return {
            "path": path,
            "total_gb": round(usage.total / (1024**3), 2),
            "used_gb": round(usage.used / (1024**3), 2),
            "free_gb": round(usage.free / (1024**3), 2),
        }
    except Exception:
        return {"path": path}


def detect_ci() -> Dict[str, Any]:
    """Detect CI/CD system from environment variables."""
    systems = [
        ("GITHUB_ACTIONS", "GitHub Actions", "GITHUB_WORKFLOW"),
        ("GITLAB_CI", "GitLab CI", "CI_PIPELINE_ID"),
        ("JENKINS_URL", "Jenkins", "BUILD_ID"),
        ("CIRCLECI", "CircleCI", "CIRCLE_BUILD_NUM"),
        ("TEAMCITY_VERSION", "TeamCity", ""),
        ("TRAVIS", "Travis CI", "TRAVIS_JOB_ID"),
        ("APPVEYOR", "AppVeyor", "APPVEYOR_BUILD_ID"),
        ("AZURE_HTTP_USER_AGENT", "Azure DevOps", "BUILD_BUILDID"),
        ("BUILDKITE", "Buildkite", "BUILDKITE_BUILD_ID"),
        ("DRONE", "Drone CI", "DRONE_BUILD_NUMBER"),
        ("BITBUCKET_BUILD_NUMBER", "Bitbucket Pipelines", "BITBUCKET_PIPELINE_UUID"),
    ]
    for env_key, name, detail_key in systems:
        if _env(env_key):
            return {
                "detected": True,
                "system": name,
                "detail": _env(detail_key) if detail_key else "",
            }
    return {"detected": False, "system": "local"}


def collect_env_tools() -> Dict[str, Any]:
    """Detect common build-chain tools available on PATH."""
    tools: Dict[str, str] = {}
    for tool in (
        "cmake",
        "ninja",
        "make",
        "git",
        "python3",
        "python",
        "clang",
        "gcc",
        "g++",
        "cl",
        "link",
        "doxygen",
        "cppcheck",
        "valgrind",
        "gdb",
        "lldb",
    ):
        found = shutil.which(tool)
        if found:
            tools[tool] = found
    return tools


def collect_binary_info(binary_path: Optional[str]) -> Dict[str, Any]:
    """Return size, hashes, and timestamp for the compiled binary."""
    if not binary_path or not Path(binary_path).exists():
        return {"available": False, "path": binary_path or "(not provided)"}

    size = _file_size(binary_path)
    info: Dict[str, Any] = {
        "available": True,
        "path": binary_path,
        "size_bytes": size,
        "size_human": _human_size(size),
        "sha256": _file_sha256(binary_path),
        "sha512": _file_sha512(binary_path),
    }

    try:
        mtime = Path(binary_path).stat().st_mtime
        info["modified_at"] = datetime.datetime.fromtimestamp(mtime).isoformat()
    except Exception:
        pass

    # PE/ELF/Mach-O format hint
    try:
        with open(binary_path, "rb") as fh:
            magic = fh.read(4)
        if magic[:2] == b"MZ":
            info["format"] = "PE (Windows)"
        elif magic == b"\x7fELF":
            info["format"] = "ELF (Linux/Unix)"
        elif magic[:4] in (
            b"\xfe\xed\xfa\xce",
            b"\xfe\xed\xfa\xcf",
            b"\xce\xfa\xed\xfe",
            b"\xcf\xfa\xed\xfe",
        ):
            info["format"] = "Mach-O (macOS)"
        else:
            info["format"] = "unknown"
    except Exception:
        pass

    return info


# ===========================================================================
# Report builder
# ===========================================================================


def build_report(
    context: Dict[str, Any],
    source_dir: Optional[str],
    binary_path: Optional[str],
) -> Dict[str, Any]:
    """Merge CMake context with runtime-gathered data into a single report."""

    now_utc = datetime.datetime.now(datetime.timezone.utc)
    eff_source = source_dir or context.get("source_dir", "") or ""
    eff_binary = binary_path or context.get("target_binary_path", "") or ""

    # Build type: from context, or inferred from binary path (multi-config generators)
    eff_build_type = (context.get("build_type") or "").strip()
    if not eff_build_type and eff_binary:
        eff_build_type = _infer_build_type_from_binary_path(eff_binary)

    # Precompute frequently used values
    ci_info = detect_ci()
    plat_info = collect_platform_info()

    return {
        # -----------------------------------------------------------------
        "meta": {
            "generated_at": now_utc.isoformat(),
            "generated_at_local": datetime.datetime.now().isoformat(),
            "generator": "GenerateBuildInfo.py",
            "generator_version": _GENERATOR_VERSION,
            "context_file": context.get("_context_file", ""),
        },
        # -----------------------------------------------------------------
        "project": {
            "name": context.get("project_name", "unknown"),
            "version": context.get("project_version", ""),
            "description": context.get("project_description", ""),
            "source_dir": context.get("source_dir", eff_source),
            "binary_dir": context.get("binary_dir", ""),
            "install_prefix": context.get("install_prefix", ""),
            "homepage": context.get("project_homepage", ""),
        },
        # -----------------------------------------------------------------
        "cmake": {
            "version": context.get("cmake_version", ""),
            "generator": context.get("cmake_generator", ""),
            "toolchain_file": context.get("cmake_toolchain_file", ""),
            "build_type": eff_build_type,
            "configuration_types": context.get("configuration_types", []),
            "source_dir": context.get("source_dir", ""),
            "binary_dir": context.get("binary_dir", ""),
            "install_prefix": context.get("install_prefix", ""),
            "position_independent": context.get("cmake_pic", ""),
            "interprocedural_opt": context.get("cmake_ipo", ""),
        },
        # -----------------------------------------------------------------
        "compiler": {
            "cxx": {
                "id": context.get("cxx_compiler_id", ""),
                "version": context.get("cxx_compiler_version", ""),
                "path": context.get("cxx_compiler_path", ""),
                "standard": context.get("cxx_standard", ""),
                "flags_global": context.get("cxx_flags_global", ""),
                "flags_release": context.get("cxx_flags_release", ""),
                "flags_debug": context.get("cxx_flags_debug", ""),
                "flags_relwdeb": context.get("cxx_flags_relwithdeb", ""),
                "flags_minsize": context.get("cxx_flags_minsize", ""),
            },
            "c": {
                "id": context.get("c_compiler_id", ""),
                "version": context.get("c_compiler_version", ""),
                "path": context.get("c_compiler_path", ""),
                "standard": context.get("c_standard", ""),
            },
            "linker": {
                "flags_exe": context.get("linker_flags_exe", ""),
                "flags_shared": context.get("linker_flags_shared", ""),
                "flags_static": context.get("linker_flags_static", ""),
            },
        },
        # -----------------------------------------------------------------
        "target": {
            "name": context.get("target_name", ""),
            "type": context.get("target_type", ""),
            "output_name": context.get("target_output_name", ""),
            "output_dir": context.get("target_output_dir", ""),
            "compile_options": context.get("target_compile_options", []),
            "link_options": context.get("target_link_options", []),
            "compile_definitions": context.get("target_compile_definitions", []),
            "include_dirs": context.get("target_include_dirs", []),
            "link_libraries": context.get("target_link_libraries", []),
            "position_independent": context.get("target_pic", ""),
            "cxx_standard": context.get("target_cxx_standard", ""),
        },
        # -----------------------------------------------------------------
        "optimization": {
            "level": context.get("opt_level", ""),
            "lto_enabled": context.get("lto_enabled", ""),
            "pgo_enabled": context.get("pgo_enabled", ""),
            "pgo_mode": context.get("pgo_mode", ""),
            "debug_symbols": context.get("debug_symbols", ""),
            "fast_math": context.get("fast_math", ""),
            "arch_baseline": context.get("arch_baseline", ""),
        },
        # -----------------------------------------------------------------
        "sanitizers": {
            "address": context.get("use_asan", "OFF"),
            "memory": context.get("use_msan", "OFF"),
            "thread": context.get("use_tsan", "OFF"),
            "undefined_behavior": context.get("use_ubsan", "OFF"),
            "leak": context.get("use_lsan", "OFF"),
        },
        # -----------------------------------------------------------------
        "platform": plat_info,
        "cpu": collect_cpu_info(),
        "memory": collect_memory_info(),
        "disk": collect_disk_info(context.get("binary_dir") or "."),
        # -----------------------------------------------------------------
        "system": {
            "hostname": socket.gethostname(),
            "fqdn": socket.getfqdn(),
            "user": (os.environ.get("USERNAME") or os.environ.get("USER") or "unknown"),
            "python_version": platform.python_version(),
            "python_executable": sys.executable,
            "python_implementation": platform.python_implementation(),
            "python_compiler": platform.python_compiler(),
        },
        # -----------------------------------------------------------------
        "ci": ci_info,
        "tools": collect_env_tools(),
        # -----------------------------------------------------------------
        "git": collect_git_info(eff_source),
        "binary": collect_binary_info(eff_binary),
    }


# ===========================================================================
# Format writers
# ===========================================================================

# ---------------------------------------------------------------------------
# JSON
# ---------------------------------------------------------------------------


def write_json(report: Dict[str, Any], outfile: str) -> None:
    Path(outfile).parent.mkdir(parents=True, exist_ok=True)
    with open(outfile, "w", encoding="utf-8") as f:
        json.dump(report, f, indent=2, ensure_ascii=False, default=str)


# ---------------------------------------------------------------------------
# YAML - PyYAML preferred; built-in fallback
# ---------------------------------------------------------------------------


def write_yaml(report: Dict[str, Any], outfile: str) -> None:
    Path(outfile).parent.mkdir(parents=True, exist_ok=True)
    header = (
        "# Build Information Report\n"
        f"# Generated: {report['meta']['generated_at']}\n"
        "# Generator: GenerateBuildInfo.py\n"
        "---\n"
    )
    try:
        import yaml  # type: ignore

        content = yaml.dump(
            report,
            allow_unicode=True,
            default_flow_style=False,
            sort_keys=False,
            width=120,
        )
    except ImportError:
        content = _yaml_fallback(report)

    with open(outfile, "w", encoding="utf-8") as f:
        f.write(header + content)


def _yaml_fallback(data: Any, level: int = 0) -> str:
    """Minimal YAML serializer that handles dict / list / scalars."""
    pad = "  " * level
    lines: List[str] = []

    if isinstance(data, dict):
        for key, value in data.items():
            safe_key = str(key)
            if isinstance(value, dict) and value:
                lines.append(f"{pad}{safe_key}:")
                lines.append(_yaml_fallback(value, level + 1))
            elif isinstance(value, list) and value:
                lines.append(f"{pad}{safe_key}:")
                lines.append(_yaml_fallback(value, level + 1))
            elif isinstance(value, bool):
                lines.append(f"{pad}{safe_key}: {'true' if value else 'false'}")
            elif value is None:
                lines.append(f"{pad}{safe_key}: null")
            elif isinstance(value, (int, float)):
                lines.append(f"{pad}{safe_key}: {value}")
            else:
                esc = str(value).replace("\\", "\\\\").replace('"', '\\"')
                lines.append(f'{pad}{safe_key}: "{esc}"')
    elif isinstance(data, list):
        for item in data:
            if isinstance(item, (dict, list)):
                first, *rest = _yaml_fallback(item, level + 1).splitlines(keepends=True)
                lines.append(f"{pad}- {first.lstrip()}")
                lines.extend(rest)
            elif isinstance(item, bool):
                lines.append(f"{pad}- {'true' if item else 'false'}")
            elif item is None:
                lines.append(f"{pad}- null")
            elif isinstance(item, (int, float)):
                lines.append(f"{pad}- {item}")
            else:
                esc = str(item).replace("\\", "\\\\").replace('"', '\\"')
                lines.append(f'{pad}- "{esc}"')
    else:
        lines.append(f"{pad}{data}")

    return "\n".join(lines) + "\n"


# ---------------------------------------------------------------------------
# INI - configparser with flattened section names
# ---------------------------------------------------------------------------


def write_ini(report: Dict[str, Any], outfile: str) -> None:
    Path(outfile).parent.mkdir(parents=True, exist_ok=True)
    cfg = configparser.ConfigParser()
    cfg.optionxform = str  # preserve key case

    def _sanitize(s: str) -> str:
        return str(s).replace("\n", " ").replace("\r", "").replace("%", "%%")

    def _flatten(section: str, data: Any) -> None:
        """Recursively flatten nested dicts into INI sections."""
        if isinstance(data, dict):
            # Truncate section name to configparser safe length
            sec = section[:60]
            if not cfg.has_section(sec):
                cfg.add_section(sec)
            for key, value in data.items():
                if isinstance(value, dict):
                    _flatten(f"{section}.{key}", value)
                elif isinstance(value, list):
                    items_sec = f"{section}.{key}"[:60]
                    if not cfg.has_section(items_sec):
                        cfg.add_section(items_sec)
                    for idx, item in enumerate(value):
                        if isinstance(item, dict):
                            _flatten(f"{section}.{key}[{idx}]", item)
                        else:
                            cfg.set(items_sec, f"item_{idx}", _sanitize(item)[:1000])
                elif isinstance(value, bool):
                    cfg.set(sec, str(key)[:60], "true" if value else "false")
                elif value is None:
                    cfg.set(sec, str(key)[:60], "")
                else:
                    cfg.set(sec, str(key)[:60], _sanitize(value)[:1000])
        elif isinstance(data, list):
            sec = section[:60]
            if not cfg.has_section(sec):
                cfg.add_section(sec)
            for idx, item in enumerate(data):
                if isinstance(item, dict):
                    _flatten(f"{section}[{idx}]", item)
                else:
                    cfg.set(sec, f"item_{idx}", _sanitize(item)[:1000])

    for top_key, top_val in report.items():
        _flatten(top_key, top_val)

    with open(outfile, "w", encoding="utf-8") as f:
        f.write(f"# Build Information Report\n")
        f.write(f"# Generated: {report['meta']['generated_at']}\n")
        f.write(f"# Generator: GenerateBuildInfo.py\n\n")
        cfg.write(f)


# ---------------------------------------------------------------------------
# TXT - human-readable
# ---------------------------------------------------------------------------


def write_txt(report: Dict[str, Any], outfile: str) -> None:
    Path(outfile).parent.mkdir(parents=True, exist_ok=True)
    lines: List[str] = []

    W = 78  # total width

    def sep(title: str = "") -> None:
        if title:
            bar_len = max(0, W - len(title) - 6)
            lines.append(f"===[ {title} ]{'=' * bar_len}")
        else:
            lines.append("=" * W)

    def row(label: str, value: Any, indent: int = 2) -> None:
        pad = " " * indent
        if isinstance(value, list):
            val = ", ".join(str(v) for v in value) if value else "(none)"
        elif value is None or str(value) in ("", "[]", "{}"):
            val = "(none)"
        else:
            val = str(value)
        lines.append(f"{pad}{label:<36}{val}")

    def subrow(value: str, indent: int = 4) -> None:
        lines.append(" " * indent + value)

    def blank() -> None:
        lines.append("")

    def list_items(items: Any, indent: int = 4) -> None:
        if not items:
            subrow("(none)", indent)
            return
        if isinstance(items, list):
            for i in items:
                subrow(str(i), indent)
        else:
            subrow(str(items), indent)

    # ---- Header ----
    sep()
    lines.append(f"{'BUILD INFORMATION REPORT':^{W}}")
    sep()
    meta = report.get("meta", {})
    lines.append(f"  Generated At (UTC) : {meta.get('generated_at', '')}")
    lines.append(f"  Generated At (Local): {meta.get('generated_at_local', '')}")
    lines.append(
        f"  Generator          : {meta.get('generator', '')} v{meta.get('generator_version', '')}"
    )
    blank()

    # ---- Project ----
    sep("PROJECT")
    proj = report.get("project", {})
    row("Name", proj.get("name"))
    row("Version", proj.get("version"))
    if proj.get("description"):
        row("Description", proj.get("description"))
    if proj.get("homepage"):
        row("Homepage", proj.get("homepage"))
    row("Source Directory", proj.get("source_dir"))
    row("Binary Directory", proj.get("binary_dir"))
    row("Install Prefix", proj.get("install_prefix"))
    blank()

    # ---- CMake ----
    sep("CMAKE")
    cm = report.get("cmake", {})
    row("CMake Version", cm.get("version"))
    row("Generator", cm.get("generator"))
    row("Build Type", cm.get("build_type"))
    row("Config Types", cm.get("configuration_types"))
    if cm.get("toolchain_file"):
        row("Toolchain File", cm.get("toolchain_file"))
    row("Position Indep. Code", cm.get("position_independent"))
    row("Interprocedural Opt", cm.get("interprocedural_opt"))
    blank()

    # ---- Compiler ----
    sep("COMPILER")
    cxx = report.get("compiler", {}).get("cxx", {})
    c = report.get("compiler", {}).get("c", {})
    lnk = report.get("compiler", {}).get("linker", {})
    row("C++ Compiler ID", cxx.get("id"))
    row("C++ Compiler Version", cxx.get("version"))
    row("C++ Compiler Path", cxx.get("path"))
    row("C++ Standard", cxx.get("standard"))
    if cxx.get("flags_global"):
        row("C++ Flags (global)", cxx.get("flags_global"))
    if cxx.get("flags_release"):
        row("C++ Flags (Release)", cxx.get("flags_release"))
    if cxx.get("flags_relwdeb"):
        row("C++ Flags (RelWDeb)", cxx.get("flags_relwdeb"))
    if cxx.get("flags_debug"):
        row("C++ Flags (Debug)", cxx.get("flags_debug"))
    if cxx.get("flags_minsize"):
        row("C++ Flags (MinSize)", cxx.get("flags_minsize"))
    blank()
    row("C Compiler ID", c.get("id"))
    row("C Compiler Version", c.get("version"))
    row("C Compiler Path", c.get("path"))
    row("C Standard", c.get("standard"))
    if lnk.get("flags_exe"):
        blank()
        row("Linker Flags (EXE)", lnk.get("flags_exe"))
    if lnk.get("flags_shared"):
        row("Linker Flags (Shared)", lnk.get("flags_shared"))
    blank()

    # ---- Target ----
    sep("TARGET")
    tgt = report.get("target", {})
    row("Target Name", tgt.get("name"))
    row("Target Type", tgt.get("type"))
    if tgt.get("output_name"):
        row("Output Name", tgt.get("output_name"))
    if tgt.get("cxx_standard"):
        row("C++ Standard", tgt.get("cxx_standard"))
    row("Position Indep.", tgt.get("position_independent"))

    for label, key in (
        ("Compile Options", "compile_options"),
        ("Link Options", "link_options"),
        ("Compile Definitions", "compile_definitions"),
        ("Include Dirs", "include_dirs"),
        ("Link Libraries", "link_libraries"),
    ):
        items = tgt.get(key, [])
        if items:
            lines.append(f"  {label}:")
            list_items(items)
    blank()

    # ---- Optimization ----
    sep("OPTIMIZATION")
    opt = report.get("optimization", {})
    row("Level", opt.get("level"))
    row("LTO", opt.get("lto_enabled"))
    row("PGO", opt.get("pgo_enabled"))
    if str(opt.get("pgo_enabled", "")).upper() == "ON":
        row("PGO Mode", opt.get("pgo_mode"))
    row("Debug Symbols", opt.get("debug_symbols"))
    if opt.get("fast_math"):
        row("Fast Math", opt.get("fast_math"))
    if opt.get("arch_baseline"):
        row("Arch Baseline", opt.get("arch_baseline"))

    san = report.get("sanitizers", {})
    active_san = [
        k for k, v in san.items() if str(v).upper() not in ("OFF", "FALSE", "0", "")
    ]
    row("Sanitizers", active_san if active_san else "(none)")
    blank()

    # ---- Platform ----
    sep("PLATFORM")
    plat = report.get("platform", {})
    row("OS", plat.get("os"))
    row("OS Release", plat.get("os_release"))
    row("OS Version", plat.get("os_version"))
    row("Machine", plat.get("machine"))
    row("Processor", plat.get("processor"))
    row("Architecture", plat.get("architecture"))
    row("Endianness", plat.get("endianness"))
    row("Logical CPUs", plat.get("cpu_logical_count"))
    if plat.get("cpu_physical_count"):
        row("Physical CPUs", plat.get("cpu_physical_count"))
    if plat.get("linux_distro"):
        row("Linux Distro", plat.get("linux_distro"))
    if plat.get("kernel_version"):
        row("Kernel Version", plat.get("kernel_version"))
    if plat.get("windows_ver"):
        row("Windows Version", plat.get("windows_ver"))
    if plat.get("macos_ver"):
        row("macOS Version", plat.get("macos_ver"))
    blank()

    # ---- CPU ----
    cpu = report.get("cpu", {})
    if cpu:
        sep("CPU")
        if cpu.get("brand"):
            row("Brand", cpu.get("brand"))
        if cpu.get("max_freq_mhz"):
            row("Max Frequency", f"{cpu.get('max_freq_mhz')} MHz")
        if cpu.get("simd_features"):
            row("SIMD Features", cpu.get("simd_features"))
        blank()

    # ---- Memory & Disk ----
    sep("RESOURCES")
    mem = report.get("memory", {})
    if mem.get("total_mb"):
        row("RAM Total", f"{mem.get('total_mb')} MB")
    if mem.get("available_mb"):
        row("RAM Available", f"{mem.get('available_mb')} MB")
    disk = report.get("disk", {})
    if disk.get("total_gb"):
        row("Disk Total", f"{disk.get('total_gb')} GB")
    if disk.get("free_gb"):
        row("Disk Free", f"{disk.get('free_gb')} GB")
    blank()

    # ---- Build Environment ----
    sep("BUILD ENVIRONMENT")
    sys_info = report.get("system", {})
    ci_info = report.get("ci", {})
    row("Hostname", sys_info.get("hostname"))
    if sys_info.get("fqdn") != sys_info.get("hostname"):
        row("FQDN", sys_info.get("fqdn"))
    row("User", sys_info.get("user"))
    row("CI System", ci_info.get("system"))
    if ci_info.get("detected") and ci_info.get("detail"):
        row("CI Build ID", ci_info.get("detail"))
    row("Python Version", sys_info.get("python_version"))
    row("Python Executable", sys_info.get("python_executable"))
    row("Python Impl.", sys_info.get("python_implementation"))

    tools = report.get("tools", {})
    if tools:
        lines.append("  Available Build Tools:")
        for tool, path in sorted(tools.items()):
            lines.append(f"    {tool:<20}{path}")
    blank()

    # ---- Git ----
    sep("GIT")
    git = report.get("git", {})
    if git.get("available"):
        row("Toplevel", git.get("toplevel"))
        row("Branch", git.get("branch"))
        row("Commit Hash", git.get("commit_hash"))
        row("Commit Short", git.get("commit_short"))
        if git.get("tag"):
            row("Tag", git.get("tag"))
        if git.get("nearest_tag") and git.get("nearest_tag") != git.get("tag"):
            row("Nearest Tag", git.get("nearest_tag"))
        row("Dirty", git.get("dirty"))
        row("Commit Count", git.get("commit_count"))
        if git.get("commits_ahead"):
            row("Ahead", git.get("commits_ahead"))
        if git.get("commits_behind"):
            row("Behind", git.get("commits_behind"))
        if git.get("commit_message"):
            row("Last Message", git.get("commit_message"))
        if git.get("commit_author"):
            row("Last Author", git.get("commit_author"))
        if git.get("commit_date"):
            row("Last Date", git.get("commit_date"))
        if git.get("origin_url"):
            row("Remote URL", git.get("origin_url"))
        if git.get("contributors"):
            lines.append("  Top Contributors:")
            for c in git["contributors"]:
                subrow(c)
    else:
        subrow(f"(not available: {git.get('reason', 'unknown')})")
    blank()

    # ---- Binary ----
    sep("BINARY")
    binary = report.get("binary", {})
    if binary.get("available"):
        row("Path", binary.get("path"))
        row("Format", binary.get("format"))
        row("Size", binary.get("size_human"))
        row("Size (bytes)", binary.get("size_bytes"))
        row("SHA-256", binary.get("sha256"))
        row("SHA-512", binary.get("sha512"))
        if binary.get("modified_at"):
            row("Built At", binary.get("modified_at"))
    else:
        subrow("(binary not available - run cmake --build first)")
    blank()

    sep()
    blank()

    with open(outfile, "w", encoding="utf-8") as f:
        f.write("\n".join(lines))


# ===========================================================================
# Entry point
# ===========================================================================


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Generate a comprehensive build-information file.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    parser.add_argument(
        "--context",
        required=True,
        help="Path to the JSON context file created by CMake.",
    )
    parser.add_argument(
        "--output",
        required=True,
        help="Destination file path.",
    )
    parser.add_argument(
        "--format",
        dest="fmt",
        default="txt",
        choices=["txt", "json", "yaml", "ini"],
        help="Output format (default: txt).",
    )
    parser.add_argument(
        "--target-binary",
        default="",
        help="Path to the compiled binary for size/hash analysis.",
    )
    parser.add_argument(
        "--source-dir",
        default="",
        help="Project source directory (used for git queries).",
    )
    args = parser.parse_args()

    # Load context
    ctx_path = Path(args.context)
    if not ctx_path.exists():
        print(
            f"[GenerateBuildInfo] ERROR: context file not found: {ctx_path}",
            file=sys.stderr,
        )
        return 1

    with open(ctx_path, encoding="utf-8") as f:
        context: Dict[str, Any] = json.load(f)
    context["_context_file"] = str(ctx_path)

    eff_source = args.source_dir or context.get("source_dir", "")
    eff_binary = args.target_binary or context.get("target_binary_path", "")

    # Build report
    print("[GenerateBuildInfo] Collecting build information...")
    report = build_report(context, eff_source or None, eff_binary or None)
    report["meta"]["format"] = args.fmt

    # Write output
    writers = {
        "txt": write_txt,
        "json": write_json,
        "yaml": write_yaml,
        "ini": write_ini,
    }
    writers[args.fmt](report, args.output)
    print(f"[GenerateBuildInfo] Written {args.fmt.upper()} report -> {args.output}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
