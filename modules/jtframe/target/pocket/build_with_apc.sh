#!/bin/zsh
set -euo pipefail

die() {
    print -u2 -- "error: $*"
    exit 1
}

copy_tree_into_view() {
    local src="$1"
    local dst="$2"
    if cp -cR "$src" "$dst" 2>/dev/null; then
        return
    fi
    cp -R "$src" "$dst"
}

if [[ $# -lt 1 ]]; then
    print -u2 -- "usage: $0 <core> [outdir] [-- <apc args...>]"
    exit 1
fi

core="$1"
shift

outdir=".apc/${core}-pocket"
if [[ $# -gt 0 && "$1" != "--" ]]; then
    outdir="$1"
    shift
fi

if [[ $# -gt 0 ]]; then
    [[ "$1" == "--" ]] || die "unexpected argument '$1' (use -- to pass arguments to apc)"
    shift
fi

repo_root="$(cd "$(dirname "$0")/../../../.." && pwd)"

outdir_abs="$outdir"
if [[ "$outdir_abs" != /* ]]; then
    outdir_abs="$repo_root/$outdir_abs"
fi

rm -rf "$outdir_abs"
"$repo_root/modules/jtframe/target/pocket/export_apc_project.sh" "$core" "$outdir"

outdir_rel="$(python3 - <<'PY' "$repo_root" "$outdir_abs"
import os, sys
print(os.path.relpath(sys.argv[2], sys.argv[1]))
PY
)"
[[ "$outdir_rel" != ..* ]] || die "Pocket build outdir must stay inside $repo_root"

target_core_jsons=( "$outdir_abs"/dist/Cores/*/core.json(N) )
(( ${#target_core_jsons[@]} == 1 )) || die "expected exactly one packaged core.json in $outdir_abs/dist/Cores"
target_core_json="$target_core_jsons[1]"
target_core_dir="${target_core_json:h}"

tmp_base="${TMPDIR:-/tmp}"
apc_view_root="$(mktemp -d "$tmp_base/jtframe-pocket-apc-${core}.XXXXXXXX")"
apc_view_repo="$apc_view_root/workspace"
apc_view_outdir="$apc_view_repo/$outdir_rel"

cleanup_apc_view() {
    local exit_status=$?
    if [[ $exit_status -eq 0 && -z "${JTFRAME_POCKET_KEEP_APC_VIEW:-}" ]]; then
        rm -rf "$apc_view_root"
    else
        print -u2 -- "APC isolated workspace retained: $apc_view_root"
    fi
}
trap cleanup_apc_view EXIT INT TERM

mkdir -p "${apc_view_outdir:h}"
cp -R "$outdir_abs" "$apc_view_outdir"
copy_tree_into_view "$repo_root/cores" "$apc_view_repo/cores"
copy_tree_into_view "$repo_root/modules" "$apc_view_repo/modules"
git -C "$apc_view_repo" init -q

(
    cd "$apc_view_outdir"
    apc "$@" .
)

view_bitstream="$apc_view_outdir/src/fpga/output_files/bitstream.rbf_r"
[[ -f "$view_bitstream" ]] || die "apc completed but did not emit $view_bitstream"

rm -rf "$outdir_abs/src/fpga/output_files"
mkdir -p "$outdir_abs/src/fpga"
cp -R "$apc_view_outdir/src/fpga/output_files" "$outdir_abs/src/fpga/output_files"
cp -f "$outdir_abs/src/fpga/output_files/bitstream.rbf_r" "$target_core_dir/bitstream.rbf_r"
cmp -s "$outdir_abs/src/fpga/output_files/bitstream.rbf_r" "$target_core_dir/bitstream.rbf_r" || \
    die "packaged bitstream does not match build output"
