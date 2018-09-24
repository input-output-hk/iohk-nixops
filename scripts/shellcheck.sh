#!/usr/bin/env nix-shell
#!nix-shell -i bash -p shellcheck
EXIT_STATUS=0

while IFS= read -r -d '' i
do
  shellcheck -x -e 1008 -e 2148 "$i"
  RETURN_CODE="$?"
  if [ "$RETURN_CODE" -gt "$EXIT_STATUS" ]
  then
    EXIT_STATUS="$RETURN_CODE"
  fi
done <  <(find . -name '*.sh' -print0)
exit "$EXIT_STATUS"
