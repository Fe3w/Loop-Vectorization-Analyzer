# LoopLens lit configuration (out-of-tree, modeled on llvm-tutor).
import os
import lit.formats

config.name = "LoopLens"
config.test_format = lit.formats.ShTest(not lit_config.isWindows)
config.suffixes = [".ll", ".c"]
config.test_source_root = os.path.dirname(__file__)
config.test_exec_root = os.path.join(config.looplens_obj_root, "test")

# Out-of-tree projects must define their own substitutions.
config.substitutions.append(("%shlibdir", config.looplens_plugin_dir))
config.substitutions.append(("%shlibext", ".so"))

# Use opt/FileCheck/clang from the pinned LLVM, not whatever is first on PATH.
config.environment["PATH"] = os.pathsep.join(
    [config.llvm_tools_dir, config.environment.get("PATH", "")]
)
