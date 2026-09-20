#!/usr/bin/env bash
# Planted defect: a hard sleep before the assertions.
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../_lib" && pwd)/base-project.sh"
python3 - <<'PY'
p='tests/auth/login.spec.ts';s=open(p).read()
s=s.replace("    // oracle: error_shown","    await page.waitForTimeout(2000);\n    // oracle: error_shown");open(p,'w').write(s)
PY
