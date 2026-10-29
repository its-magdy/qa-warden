#!/usr/bin/env bash
# manifest.sh — the plugin's ONE reader of its line-oriented data files, and the two matchers
# that read them back. Sourced, never run: it defines functions and sets nothing else (no
# options, no variables), so a caller's `fail`/`warn` counters and its lack of `set -e` are safe.
#
# Brain-side only. Its callers all ship in the plugin: skills/doctor/scripts/doctor.sh,
# skills/coverage/scripts/coverage.sh, bin/qa-scaffold, bin/qa-selfcheck and bin/qa-scaffoldtest.
# The stamped templates/scripts/init.sh is body (it runs in a project with no plugin behind it)
# and keeps its own copy of the comment strip, on purpose.
#
# Why it exists. The strip pipeline below was copied thirteen times, and the copies had drifted:
# doctor Check 9 trimmed leading blanks and dropped `./` from manifests/resync-set.txt while
# qa-scaffold --resync did not, though invariant M-8 (that file's header) needs detection and
# repair to read the SAME set. And the vocabulary symbols were matched as unescaped regexes, so
# the `.` in `cli-fill-env.sh` matched any character. One reader closes both.
#
# bash 3.2: no `case … in *.x)` inside `$( … )` (write `(*.x)`), no associative arrays.

# manifest_rows <file> — every data row of a manifest: `#` to end of line dropped, then leading
# and trailing blanks, then blank lines. A missing or unreadable file prints nothing; callers
# test the result for empty and name the file themselves.
manifest_rows() {
  sed -e 's/#.*$//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' "$1" 2>/dev/null | grep -v '^$'
}

# manifest_prose_rows <file> — rows of a manifest whose fields carry prose
# (manifests/claude-md-vocab.txt: `symbol|why`). Only FULL-LINE comments are dropped: a `#`
# inside the why-field is text, and the usual strip would cut the sentence there.
manifest_prose_rows() {
  grep -v '^[[:space:]]*#' "$1" 2>/dev/null | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' | grep -v '^$'
}

# manifest_normalised_rows <file> — manifest_rows with repeated `/` squeezed and each row's
# leading `./` segments and inner `/./` segments dropped, so `  ./scripts//./x.sh` reads as
# scripts/x.sh. Internal: the two readers below are the interface.
manifest_normalised_rows() {
  manifest_rows "$1" | sed -e 's#//*#/#g' -e 's#^\(\./\)*##' -e ':a' -e 's#/\./#/#' -e 'ta'
}

# manifest_paths <file> — the path column of a path manifest, one per line. For
# manifests/resync-set.txt this is THE parse M-8 depends on: doctor Check 9 (detection) and
# qa-scaffold --resync (repair) both call it, so they cannot read a row differently. A row's
# second column (resync-set.txt's protection tier) is not part of the path and is dropped here;
# manifest_tiers returns it.
manifest_paths() {
  manifest_normalised_rows "$1" | awk '{ print $1 }'
}

# manifest_tiers <file> — "path<TAB>rest" per row of resync-set.txt, where rest is everything
# after the path (blanks trimmed): `deny` or `prompt` on a well-formed row, empty when the tier
# is missing, more than one word when the row carries extra fields. Read only by
# bin/qa-selfcheck Check 9f arm 4, which judges rest; every other reader wants manifest_paths.
manifest_tiers() {
  manifest_normalised_rows "$1" | awk '{
    path = $1
    rest = $0
    sub(/^[^ \t]+[ \t]*/, "", rest)
    print path "\t" rest
  }'
}

# ere_quote <string> — <string> with every ERE metacharacter backslash-escaped, so it matches
# itself and nothing else inside a `grep -E` pattern. A character loop, not sed: BSD sed does not
# reliably match a backslash inside a bracket expression.
ere_quote() {
  local s=$1 out="" c
  while [ -n "$s" ]; do
    c=${s%"${s#?}"}
    s=${s#?}
    case "$c" in
      ('.'|'['|']'|'\'|'*'|'^'|'$'|'+'|'?'|'('|')'|'{'|'}'|'|') out="$out\\$c" ;;
      (*) out="$out$c" ;;
    esac
  done
  printf '%s' "$out"
}

# symbol_present <symbol> <file> — succeeds when <file> names <symbol> literally, not glued to a
# preceding letter or underscore, so `lock:` does not match `unlock:`. The symbol is quoted
# first: `cli-fill-env.sh` must not match `cli-fill-envXsh`. Doctor's CLAUDE.md vocabulary
# containment, qa-selfcheck Check 9b arm 4 and Check 9i arm 1 all ask this question.
symbol_present() {
  grep -qE -e "(^|[^a-zA-Z_])$(ere_quote "$1")" "$2" 2>/dev/null
}

# arg_shape_rows <file> — "key<TAB>shape" per row of an oracle arg-shape table
# (| `key` | `shape` | …). Shape is the FIRST backticked expression in column 2. The key charclass
# includes digits (`a11y_violations_below`), and the `fault:`/`clock:` rows keep their trailing
# colon precisely so this pattern skips them. Doctor Check 2 takes the key column; qa-selfcheck
# Checks 9bb and 9be compare the shapes.
# The tab is a literal one, not `\t`: an older BSD sed writes `\t` in a replacement as a `t`.
arg_shape_rows() {
  local tab
  tab=$(printf '\t')
  sed -nE 's/^\| `([a-z0-9_]+)` \| `([^`]*)`.*/\1'"$tab"'\2/p' "$1" 2>/dev/null
}

# rederives_manifest_walk <file> — succeeds when <file> re-derives the UNMANIFESTED walk that
# scripts/spec-links.sh `unmanifested` owns: an existence test on a route-manifest path built
# from a variable, on a non-comment line. spec-links.sh itself is the owner and never counts.
# Doctor 9k arm 3 asks this of a project's scripts/*.sh, qa-selfcheck 9k of the plugin's own
# files; doctor's 9k header has the history of the anchor. `-e` is mandatory: the pattern begins
# with `-f`, which grep would otherwise take as its own `-f FILE` option.
rederives_manifest_walk() {
  case "$1" in
    (*/spec-links.sh|spec-links.sh) return 1 ;;
  esac
  sed '/^[[:space:]]*#/d' "$1" 2>/dev/null | grep -qE -e '-f[[:space:]]*"artifacts/route-manifests/\$\{'
}
