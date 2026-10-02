#!/usr/bin/env bash
# Fail if the kubectl / kind versions mirrored across the Makefile, .mise.toml,
# images/Dockerfile and vm/cloud-init.yaml disagree.
#
# Usage: check-toolchain-alignment.sh [ROOT]
#   ROOT defaults to the repo this script lives in. It is a positional argument,
#   not an environment variable, so a stray export cannot silently point the
#   gate at another tree. tests/toolchain-alignment.bats passes a temp tree.
#
# Every pin is read from the COMMITTED TEXT of its file (the Makefile included),
# so `make KUBECTL_VERSION=x` on the command line does not change the verdict.
# Out of scope by design: a value make would resolve differently from that text
# (an `include`d file, a `define` block, a target-specific assignment). The pin
# is the top-level, unindented `KUBECTL_VERSION :=` line; a tab-indented line is
# a recipe command, not an assignment, and is not counted.
#
# Failure modes this script must keep loud (each has a case in
# tests/toolchain-alignment.bats):
#   - a pin line missing or duplicated  -> "expected exactly 1 pin line in <file>, found N"
#   - a pin line present but reshaped   -> "unparseable pin in <file>"
#   - versions disagree                 -> "<tool> version drift" with <file>=<value> pairs
#
# Shape rules (do not "tidy" these away):
#   - die() writes to STDERR: pin()'s stdout is its return value, so an error on
#     stdout would be captured by the caller's $( ) and never shown.
#   - pin() is only ever called as a plain top-level `v=$(pin ...)`. In
#     `local v=$(...)` or in argument position the subshell's exit status is
#     discarded, every value comes back empty, and "" == "" reports alignment.
set -euo pipefail

die() {
	echo "ERROR: $*" >&2
	exit 1
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# ${1-...} not ${1:-...}: an explicitly EMPTY argument must fail, not silently
# fall back to checking this repo.
ROOT="${1-$SCRIPT_DIR/..}"
[ -n "$ROOT" ] || die "root argument is empty"
[ -d "$ROOT" ] || die "root directory not found: $ROOT"
cd "$ROOT"

# pin <label> <file> <line-ERE> <bare|quoted>
#   bare:   KEY=value / KEY := value   -> first whitespace-free token after the first '='
#   quoted: "key" = "value"            -> the first double-quoted string after the first '='
# Prints the version with any leading 'v' stripped.
pin() {
	local label="$1" file="$2" line_re="$3" kind="$4"
	local lines n extract val
	[ -f "$file" ] || die "$label: $file not found (root: $PWD)"
	lines="$(grep -E -- "$line_re" "$file" || true)"
	if [ -z "$lines" ]; then
		n=0
	else
		n="$(printf '%s\n' "$lines" | wc -l)"
	fi
	if [ "$n" -ne 1 ]; then
		die "$label: expected exactly 1 pin line in $file, found $n"
	fi
	case "$kind" in
		bare) extract='s/^[^=]*=[[:space:]]*([^[:space:]#]+).*$/\1/' ;;
		quoted) extract='s/^[^=]*=[[:space:]]*"([^"]*)".*$/\1/' ;;
		*) die "$label: unknown pin kind '$kind'" ;;
	esac
	val="$(printf '%s\n' "$lines" | sed -E "$extract")"
	val="${val#v}"
	# sed passes a non-matching line through whole, so "non-empty" proves nothing;
	# require the value to actually look like a version.
	if ! [[ $val =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
		die "$label: unparseable pin in $file: '$lines'"
	fi
	printf '%s' "$val"
}

mk_kubectl=$(pin "kubectl" Makefile \
	'^ *(export[[:space:]]+|override[[:space:]]+)?KUBECTL_VERSION[[:space:]]*[:?+!]*=' bare)
mise_kubectl=$(pin "kubectl" .mise.toml '^"aqua:kubernetes/kubectl"[[:space:]]*=' quoted)
docker_kubectl=$(pin "kubectl" images/Dockerfile '^ARG[[:space:]]+KUBECTL_VERSION=' bare)
ci_kubectl=$(pin "kubectl" vm/cloud-init.yaml '^[[:space:]]*KUBECTL_VERSION=' bare)
mise_kind=$(pin "kind" .mise.toml '^"aqua:kubernetes-sigs/kind"[[:space:]]*=' quoted)
ci_kind=$(pin "kind" vm/cloud-init.yaml '^[[:space:]]*KIND_VERSION=' bare)

if [ "$mise_kubectl" != "$mk_kubectl" ] || [ "$docker_kubectl" != "$mk_kubectl" ] || [ "$ci_kubectl" != "$mk_kubectl" ]; then
	die "kubectl version drift — Makefile=$mk_kubectl .mise.toml=$mise_kubectl images/Dockerfile=$docker_kubectl vm/cloud-init.yaml=$ci_kubectl"
fi
if [ "$mise_kind" != "$ci_kind" ]; then
	die "kind version drift — .mise.toml=$mise_kind vm/cloud-init.yaml=$ci_kind"
fi

echo "Toolchain alignment OK (kubectl=$mk_kubectl, kind=$mise_kind)."
if [ $# -gt 0 ]; then
	echo "(root: $PWD)"
fi
