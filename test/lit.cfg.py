# LoopLens lit configuration (out-of-tree, modeled on llvm-tutor).
import os
import lit.formats

config.name = "LoopLens"
config.test_format = lit.formats.ShTest(not lit_config.isWindows)
config.suffixes = [".ll", ".c", ".test"]
config.test_source_root = os.path.dirname(__file__)
config.test_exec_root = os.path.join(config.looplens_obj_root, "test")

# Out-of-tree projects must define their own substitutions.
config.substitutions.append(("%shlibdir", config.looplens_plugin_dir))
config.substitutions.append(("%shlibext", ".so"))

# Use opt/FileCheck/clang from the pinned LLVM, not whatever is first on PATH.
config.environment["PATH"] = os.pathsep.join(
    [config.llvm_tools_dir, config.environment.get("PATH", "")]
)

# %python: the interpreter running lit (used to validate JSON output).
import sys
config.substitutions.append(("%python", sys.executable))

# %looplens_clang: clang-20 with the plugin at the VectorizerStart extension
# point. -Xclang -load registers the plugin's -mllvm options before clang
# parses them (-fpass-plugin alone loads it too late).
_so = os.path.join(config.looplens_plugin_dir, "LoopLens.so")
config.substitutions.append(
    ("%looplens_clang",
     "clang -fpass-plugin=%s -Xclang -load -Xclang %s -mllvm -looplens-text=false" % (_so, _so)))

# Inputs/ hold data for the script tests, not tests.
config.excludes = ["Inputs", "overlap.c"]

# %aarch64_sysroot: the AArch64 cross headers unpacked by
# scripts/fetch_aarch64_sysroot.sh; tests that need them say REQUIRES: aarch64-sysroot.
_sr = os.path.join(os.path.dirname(__file__), "..", "bench", "sysroot-aarch64", "root", "usr", "aarch64-linux-gnu")
config.substitutions.append(("%aarch64_sysroot", "--sysroot=" + os.path.abspath(_sr)))
if os.path.isdir(os.path.join(_sr, "include")):
    config.available_features.add("aarch64-sysroot")

# gcc: GCC is installed (S28 comparison); tests that run it say REQUIRES: gcc.
import shutil
if shutil.which("gcc-13") or shutil.which("gcc"):
    config.available_features.add("gcc")
