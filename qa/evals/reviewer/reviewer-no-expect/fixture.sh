#!/usr/bin/env bash
# Planted defect: the test performs the steps but asserts nothing (green-but-empty).
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../_lib" && pwd)/base-project.sh"
python3 - <<'PY'
import re;p='tests/auth/login.spec.ts';s=open(p).read()
s=re.sub(r"\n    // oracle: error_shown.*?toHaveURL\([^\n]*\n","\n",s,flags=re.S);open(p,'w').write(s)
PY
