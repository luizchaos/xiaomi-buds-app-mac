#!/bin/zsh
# Verifies that every language defines exactly the same keys as English (the base language).
set -euo pipefail
cd "$(dirname "$0")/../Resources/Localization"

keys() { plutil -convert json -o - "$1" | /usr/bin/python3 -c 'import json,sys; print("\n".join(sorted(json.load(sys.stdin))))'; }

failed=0
for base in en.lproj/*.strings; do
  name=${base:t}
  for dir in *.lproj; do
    [[ $dir == en.lproj ]] && continue
    file="$dir/$name"
    if [[ ! -f $file ]]; then echo "missing: $file"; failed=1; continue; fi
    plutil -lint -s "$file" || { failed=1; continue; }
    diff_out=$(diff <(keys "$base") <(keys "$file") || true)
    if [[ -n $diff_out ]]; then
      echo "key mismatch in $file (< only in en, > only in ${dir%.lproj}):"
      echo "$diff_out" | grep -E '^[<>]'
      failed=1
    fi
  done
done
# Every key referenced in Swift code must exist in the base language.
code_keys=$(grep -rhoE '"(connection|message|error|battery|noise|settings|action)\.[A-Za-z.]+"' ../../Sources | tr -d '"' | sort -u)
missing=$(comm -23 <(echo "$code_keys") <(keys en.lproj/Localizable.strings))
if [[ -n $missing ]]; then
  echo "keys used in code but missing from en.lproj/Localizable.strings:"
  echo "$missing"
  failed=1
fi

(( failed == 0 )) && echo "Localizations OK: $(ls -d *.lproj | sed 's/.lproj//' | tr '\n' ' ')"
exit $failed
