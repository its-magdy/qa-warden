#!/usr/bin/env bash
# Planted defect: asserted literal differs from the oracle value (green-but-wrong).
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../_lib" && pwd)/base-project.sh"
python3 - <<'PY'
p='tests/auth/login.spec.ts';s=open(p).read()
s=s.replace("toHaveText('Invalid email or password')","toHaveText('Invalid credentials')");open(p,'w').write(s)
PY
