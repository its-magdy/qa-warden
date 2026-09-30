#!/usr/bin/env bash
# Planted defect: the spec declares url_matches but the test never asserts it (orphan oracle item).
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../_lib" && pwd)/base-project.sh"
python3 - <<'PY'
p='tests/auth/login.spec.ts';s=open(p).read()
s=s.replace("    // oracle: url_matches\n    await expect(page).toHaveURL(/\\/login$/);\n","");open(p,'w').write(s)
PY
