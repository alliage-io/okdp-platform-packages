#!/usr/bin/env bash
#
# A chart embeds a local chart of charts/ by relative path (a Chart.yaml
# dependency `repository: file://../../../charts/x`, or a vendor.yaml entry
# `repository: file://...`), so changing that chart changes the embedding
# chart's artifact. release-please assigns
# commits to packages by directory, and charts/ is outside every package, so a
# charts-only change would release nothing and never reach the registry.
#
# This fails the build when a shared chart moves without its consumers.
#
# Usage: shared-chart-consumers.sh <changed-file>...
set -uo pipefail

changed=("$@")
status=0

# Nothing to inspect (empty diff): succeed rather than trip `set -u`.
[[ ${#changed[@]} -eq 0 ]] && exit 0

changed_under() {           # changed_under <dir>
  local dir="$1" f
  for f in "${changed[@]}"; do
    [[ "$f" == "$dir/"* ]] && return 0
  done
  return 1
}

# Which shared charts were touched?
charts=$(printf '%s\n' "${changed[@]}" | grep -oE '^charts/[^/]+' | sort -u)

for chart in ${charts}
do
  name="${chart#charts/}"
  # Charts embedding this chart by relative path (Chart.yaml or vendor.yaml)
  consumers=$(grep -rlE "repository: *[\"']?file://([^ ]*/)?charts/${name}/?[\"']?\$" packages/ --include=Chart.yaml --include=vendor.yaml 2>/dev/null | grep -v '/vendor/' | xargs -r -n1 dirname | sort -u)

  [[ -z "${consumers}" ]] && continue

  for pkg in ${consumers}
  do
    if changed_under "${pkg}"; then
      echo "ok   ${chart} changed, and so did ${pkg}"
    else
      echo "::error title=Shared chart changed without its consumer::${chart} is embedded by ${pkg}, but nothing under ${pkg} changed. release-please assigns commits by directory, so ${pkg} would not be released and the change would never be published. Bump or touch ${pkg} in this pull request."
      status=1
    fi
  done
done

exit ${status}
