#!/usr/bin/env bash
# Run inside the corresponding devShell, using temporary source/build files.
set -euo pipefail

suite=${1:?usage: toolchains.sh python|go|bash|rust|node|cpp|systems|ai}
task_tmp=$(mktemp -d)
trap 'rm -rf -- "$task_tmp"' EXIT

case "$suite" in
python)
  python -c 'import ssl, sqlite3, venv; assert sqlite3.connect(":memory:").execute("select 6 * 7").fetchone()[0] == 42; print("Python stdlib OK")'
  uv --version
  ruff --version
  pyright --version
  ;;
go)
  cat >"$task_tmp/main.go" <<'GO'
package main
import "fmt"
func main() { fmt.Println(6 * 7) }
GO
  export GOCACHE="$task_tmp/go-cache" GOTOOLCHAIN=local GOENV=off GOMAXPROCS=2
  test "$(go run -p 2 "$task_tmp/main.go")" = 42
  go version
  gopls version
  ;;
bash)
  cat >"$task_tmp/test.sh" <<'BASH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$((6 * 7))"
BASH
  bash -n "$task_tmp/test.sh"
  shellcheck "$task_tmp/test.sh"
  test "$(bash "$task_tmp/test.sh")" = 42
  shfmt --version
  ;;
rust)
  printf 'fn main() { println!("{}", 6 * 7); }\n' >"$task_tmp/main.rs"
  rustc "$task_tmp/main.rs" -o "$task_tmp/rust-check"
  test "$("$task_tmp/rust-check")" = 42
  cargo --version
  rust-analyzer --version
  ;;
node)
  node -e 'require("node:assert/strict").equal(6 * 7, 42); console.log("Node runtime OK")'
  node --version
  pnpm --version
  tsc --version
  ;;
cpp | systems)
  printf '#include <stdio.h>\nint main(void) { printf("%%d\\n", 6 * 7); return 0; }\n' >"$task_tmp/main.c"
  if [[ "$suite" == systems ]]; then
    clang "$task_tmp/main.c" -o "$task_tmp/c-check"
    llvm-nm "$task_tmp/c-check" | rg ' main$'
    lldb --version
    valgrind --version
  else
    cc "$task_tmp/main.c" -o "$task_tmp/c-check"
    printf '#include <iostream>\nint main() { std::cout << 6 * 7 << std::endl; }\n' >"$task_tmp/main.cpp"
    c++ "$task_tmp/main.cpp" -o "$task_tmp/cpp-check"
    test "$("$task_tmp/cpp-check")" = 42
    clangd --version
  fi
  test "$("$task_tmp/c-check")" = 42
  gdb --batch -ex "file $task_tmp/c-check" -ex 'info files' >/dev/null
  cmake --version
  ninja --version
  ;;
ai)
  python - <<'PY'
import numpy as np
import scipy.linalg
import pandas as pd
import sklearn
import matplotlib
import jupyterlab
import torch

assert scipy.linalg.det(np.eye(2)) == 1
assert pd.Series([6, 7]).prod() == 42
assert torch.version.cuda is None, "Expected CPU PyTorch"
assert torch.version.hip is None, "ROCm is outside this stage"
x = torch.tensor([6.0], requires_grad=True)
(x * 7).sum().backward()
assert x.grad.item() == 7
print(f"AI imports and CPU autograd OK: torch {torch.__version__}")
PY
  ;;
*)
  printf 'Unknown suite: %s\n' "$suite" >&2
  exit 2
  ;;
esac
printf '%s smoke test passed\n' "$suite"
