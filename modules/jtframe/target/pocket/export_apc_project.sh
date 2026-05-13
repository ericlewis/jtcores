#!/bin/zsh
set -euo pipefail

die() {
    print -u2 -- "error: $*"
    exit 1
}

require_cmd() {
    command -v "$1" >/dev/null 2>&1 || die "missing required tool '$1' in PATH"
}

require_dir() {
    local path="$1"
    local hint="${2:-}"
    [[ -d "$path" ]] || die "missing required directory: $path${hint:+ ($hint)}"
}

require_file() {
    local path="$1"
    local hint="${2:-}"
    [[ -f "$path" ]] || die "missing required file: $path${hint:+ ($hint)}"
}

jq_assert() {
    local file="$1"
    local expr="$2"
    local msg="$3"
    jq -e "$expr" "$file" >/dev/null 2>&1 || die "invalid Pocket metadata in $file: $msg"
}

uses_legacy_jtframe_game_ports() {
    local file_path="$1"
    [[ -f "$file_path" ]] && grep -Eq '^[[:space:]]*`include[[:space:]]+"jtframe_game_ports\.inc"' "$file_path"
}

legacy_cps_requires_migration() {
    local core_name="$1"
    case "$core_name" in
        cps1|cps15|cps2)
            [[ "${JTFRAME_POCKET_ALLOW_LEGACY_CPS:-0}" != "1" ]]
            ;;
        *)
            return 1
            ;;
    esac
}

copy_hdl_collateral_dir() {
    local collateral_dir="$1"
    [[ -d "$collateral_dir" ]] || return 0
    for collateral in "$collateral_dir"/*(.N); do
        case "${collateral:t}" in
            "${GAMETOP}.v"|mem_ports.inc|msg.bin|msg.hex|logodata.hex|logomap.hex)
                continue
                ;;
        esac
        case "${collateral:e:l}" in
            hex|mif|bin)
                fpga_collateral="$fpga_dir/${collateral:t}"
                hdl_collateral="$hdl_collateral_dir/${collateral:t}"
                [[ "${collateral:A}" == "${fpga_collateral:A}" ]] || cp -f "$collateral" "$fpga_collateral"
                [[ "${collateral:A}" == "${hdl_collateral:A}" ]] || cp -f "$collateral" "$hdl_collateral"
                ;;
        esac
    done
}

sanitize_pocket_sdc_constraints() {
    local files_qip="$fpga_dir/files.qip"
    require_file "$files_qip"
    python3 - "$files_qip" "$fpga_dir" <<'PY'
import os
import re
import sys

files_qip, fpga_dir = sys.argv[1:]
sdc_re = re.compile(r"^(set_global_assignment\s+-name\s+SDC_FILE\s+\[file join \$::quartus\(qip_path\) )([^]]+)(\])(\s*)$")

with open(files_qip, "r", encoding="utf-8") as f:
    lines = f.readlines()

out = []
warnings = []
for line in lines:
    m = sdc_re.match(line.rstrip("\n"))
    if not m:
        out.append(line)
        continue

    source_rel = m.group(2)
    if not source_rel.startswith("../../../../cores/"):
        out.append(line)
        continue

    source_abs = os.path.normpath(os.path.join(fpga_dir, source_rel))
    try:
        with open(source_abs, "r", encoding="utf-8") as f:
            sdc_lines = f.readlines()
    except OSError:
        out.append(line)
        continue

    marker = next((i for i, sdc_line in enumerate(sdc_lines) if re.search(r"\bMiSTer specific\b", sdc_line, re.IGNORECASE)), None)
    if marker is None:
        out.append(line)
        continue

    safe_name = re.sub(r"[^A-Za-z0-9]+", "_", source_rel).strip("_")
    sanitized_rel = f"core/{safe_name}_pocket.sdc"
    sanitized_abs = os.path.join(fpga_dir, sanitized_rel)
    os.makedirs(os.path.dirname(sanitized_abs), exist_ok=True)
    with open(sanitized_abs, "w", encoding="utf-8") as f:
        f.write(f"# Auto-generated Pocket-filtered copy of {source_rel}\n")
        f.write("# MiSTer-specific constraints from the source file were removed.\n\n")
        f.writelines(sdc_lines[:marker])

    out.append(f"{m.group(1)}{sanitized_rel}{m.group(3)}{m.group(4)}\n")
    warnings.append(f"warning: filtered MiSTer-specific constraints from {source_rel} for Pocket export")

with open(files_qip, "w", encoding="utf-8") as f:
    f.writelines(out)

for warning in warnings:
    print(warning, file=sys.stderr)
PY
}

append_optional_qsf() {
    local qsf_file="$1"
    [[ -f "$qsf_file" ]] || return 0
    {
        echo
        echo "# Core-local Pocket QSF overrides from ${qsf_file#$repo_root/}"
        cat "$qsf_file"
    } >> ap_core.qsf
}

if [[ $# -lt 1 || $# -gt 2 ]]; then
    echo "usage: $0 <core> [outdir]" >&2
    exit 1
fi

core="$1"
outdir="${2:-.apc/${core}-pocket}"

repo_root="$(cd "$(dirname "$0")/../../../.." && pwd)"
outdir_abs="$(cd "$repo_root" && mkdir -p "$outdir" && cd "$outdir" && pwd)"
if [[ "$outdir_abs" != "$repo_root" && "$outdir_abs" != "$repo_root/"* ]]; then
    die "Pocket export outdir must stay inside $repo_root; the generated project uses repo-relative JTFRAME paths. Use the default .apc export or another folder under the repository."
fi
fpga_dir="$outdir_abs/src/fpga"
dist_dir="$outdir_abs/dist"
hdl_collateral_dir="$outdir_abs/hdl"
mkdir -p "$fpga_dir/core" "$hdl_collateral_dir"

require_cmd python3
require_cmd jq
require_dir "$repo_root/cores/$core" "unknown core '$core'"
require_file "$repo_root/modules/jtframe/bin/font0.hex"
require_file "$repo_root/modules/jtframe/target/pocket/pocket.qsf"

rel_repo="$(python3 - <<'PY' "$repo_root" "$fpga_dir"
import os, sys
print(os.path.relpath(sys.argv[1], sys.argv[2]))
PY
)"

export JTROOT="$rel_repo"
export JTFRAME="$rel_repo/modules/jtframe"
export CORES="$rel_repo/cores"
export MODULES="$rel_repo/modules"
export JTBIN="$dist_dir"
export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$repo_root/modules/jtframe/bin"

cd "$fpga_dir"
rm -f msg.bin msg.hex

cfg_bash="$("$repo_root/modules/jtframe/bin/jtframe" cfgstr "$core" --target pocket --nodbg --output bash)" || \
    die "failed to resolve Pocket macros for '$core' with jtframe cfgstr"
eval "$cfg_bash"
[[ -n "${GAMETOP:-}" ]] || die "jtframe cfgstr did not define GAMETOP for core '$core'"
[[ -n "${CORENAME:-}" ]] || die "jtframe cfgstr did not define CORENAME for core '$core'"

shortname="${CORENAME:l}"
core_dir="$dist_dir/Cores/jotego.${shortname}"
metadata_src_dir="$dist_dir/pocket/raw/Cores/jotego.${shortname}"
platforms_src_dir="$dist_dir/pocket/raw/Platforms"
pocket_core_dir="$repo_root/cores/$core/pocket"
mem_cfg="$repo_root/cores/$core/cfg/mem.yaml"
files_cfg="$repo_root/cores/$core/cfg/files.yaml"
legacy_gametop_src="$repo_root/cores/$core/hdl/${GAMETOP}.v"
had_pocket_dir=0
if [[ -d "$pocket_core_dir" ]]; then
    had_pocket_dir=1
fi
use_legacy_gametop=0

pocket_extra_macros=()
if [[ -f "$files_cfg" ]] && grep -Eq '^[[:space:]]*jt539:' "$files_cfg" && [[ ! -f "$repo_root/modules/jt539/cfg/files.yaml" ]]; then
    pocket_extra_macros+=( NOSOUND )
    print -u2 -- "warning: modules/jt539 is unavailable; exporting '$core' for Pocket with NOSOUND (K054539 PCM disabled)"
fi
pocket_macro_list="JTFRAME_RELEASE"
if (( ${#pocket_extra_macros[@]} )); then
    pocket_macro_list="${pocket_macro_list},${(j:,:)pocket_extra_macros}"
fi
pocket_cfgstr_args=()
for macro in "${pocket_extra_macros[@]}"; do
    pocket_cfgstr_args+=( --def "$macro" )
done

mem_rc=0
"$repo_root/modules/jtframe/bin/jtframe" mem "$core" --target pocket --nodbg || mem_rc=$?
if (( mem_rc != 0 )); then
    if [[ -f "$pocket_core_dir/${GAMETOP}.v" && -f "$pocket_core_dir/mem_ports.inc" ]]; then
        print -u2 -- "warning: jtframe mem failed for '$core'; using existing Pocket wrapper under cores/$core/pocket"
    elif [[ ! -f "$mem_cfg" ]] && uses_legacy_jtframe_game_ports "$legacy_gametop_src"; then
        use_legacy_gametop=1
        print -u2 -- "warning: jtframe mem failed for '$core'; using legacy JTFRAME game top $legacy_gametop_src"
    else
        die "jtframe mem failed for '$core' and no complete Pocket wrapper exists under cores/$core/pocket"
    fi
fi
if [[ ! -d "$pocket_core_dir" ]]; then
    if [[ ! -f "$mem_cfg" ]] && uses_legacy_jtframe_game_ports "$legacy_gametop_src"; then
        use_legacy_gametop=1
        print -u2 -- "warning: using legacy JTFRAME game top for '$core'; no generated Pocket wrapper is required"
    elif [[ ! -f "$mem_cfg" ]]; then
        die "missing Pocket wrapper for '$core': $mem_cfg does not exist, so jtframe mem cannot synthesize cores/$core/pocket automatically. Add a bespoke Pocket wrapper under cores/$core/pocket or teach the core to generate one."
    else
        die "jtframe mem did not create the Pocket synthesis folder for '$core'"
    fi
fi

if (( use_legacy_gametop )) && legacy_cps_requires_migration "$core"; then
    die "legacy CPS top export is diagnostic-only for '$core': hardware testing showed CPS1/CPS1.5/CPS2 packages do not work from the legacy internal jtcps1_sdram path. Migrate this family to a generated Pocket memory wrapper/mem.yaml boundary before release, or set JTFRAME_POCKET_ALLOW_LEGACY_CPS=1 for a local comparison run."
fi

if (( ! use_legacy_gametop )); then
    gametop_src="$pocket_core_dir/${GAMETOP}.v"
    if [[ ! -f "$gametop_src" ]]; then
        if [[ -f "$pocket_core_dir/${GAMETOP}.sv" ]]; then
            die "found $pocket_core_dir/${GAMETOP}.sv after jtframe mem, but the Pocket export flow currently expects a Verilog wrapper named ${GAMETOP}.v"
        fi
        if [[ $had_pocket_dir -eq 1 && ! -f "$mem_cfg" ]]; then
            die "incomplete bespoke Pocket wrapper for '$core': missing $gametop_src"
        fi
        die "jtframe mem did not generate the Pocket game wrapper: $gametop_src"
    fi
    if [[ ! -f "$pocket_core_dir/mem_ports.inc" ]]; then
        if [[ $had_pocket_dir -eq 1 && ! -f "$mem_cfg" ]]; then
            die "incomplete bespoke Pocket wrapper for '$core': missing $pocket_core_dir/mem_ports.inc"
        fi
        die "jtframe mem did not generate mem_ports.inc for '$core'"
    fi
fi

"$repo_root/modules/jtframe/bin/jtframe" mmr "$core"
"$repo_root/modules/jtframe/bin/jtframe" files syn "$core" --target pocket --rel --macro "$pocket_macro_list"
if (( use_legacy_gametop )) && ! grep -Fq "cores/$core/hdl/${GAMETOP}.v" "$fpga_dir/files.qip"; then
    die "legacy JTFRAME game top for '$core' is not listed in files.qip; add $legacy_gametop_src to cfg/files.yaml or provide a complete cores/$core/pocket wrapper"
fi
sanitize_pocket_sdc_constraints
"$repo_root/modules/jtframe/bin/jtframe" parse "$core" "$repo_root/modules/jtframe/target/pocket/pocket.qsf" --def "$pocket_macro_list" --output ap_core.qsf

{
    echo
    "$repo_root/modules/jtframe/bin/jtframe" cfgstr "$core" --target pocket --nodbg "${pocket_cfgstr_args[@]}" --output quartus | sort
} >> ap_core.qsf
append_optional_qsf "$repo_root/cores/$core/syn/pocket.qsf"
if [[ -n "${JTFRAME_POCKET_EXTRA_QSF:-}" ]]; then
    {
        echo
        echo "# Ad-hoc Pocket QSF overrides from JTFRAME_POCKET_EXTRA_QSF"
        print -r -- "$JTFRAME_POCKET_EXTRA_QSF"
    } >> ap_core.qsf
fi

cat > ap_core.qpf <<'EOF'
QUARTUS_VERSION = "17.1"
DATE = "${DATE}"
PROJECT_REVISION = "ap_core"
EOF

cat > core/core_constraints.sdc <<'EOF'
#
# Auto-generated core constraints for the Pocket build.
# Do not edit by hand — regenerate from export_apc_project.sh.
#

set pocket_clock_group_args [list -asynchronous]

foreach pocket_clock_filter {
    bridge_spiclk
    clk_74a
    clk_74b
} {
    set pocket_clocks [get_clocks -nowarn $pocket_clock_filter]
    if {[get_collection_size $pocket_clocks] > 0} {
        lappend pocket_clock_group_args -group $pocket_clocks
    }
}

set pocket_pll_clocks [get_clocks -nowarn {
    u_core|u_clocks|u_pll|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk
    u_core|u_clocks|u_pll|altera_pll_i|general[1].gpll~PLL_OUTPUT_COUNTER|divclk
    u_core|u_clocks|u_pll|altera_pll_i|general[2].gpll~PLL_OUTPUT_COUNTER|divclk
    u_core|u_clocks|u_pll|altera_pll_i|general[3].gpll~PLL_OUTPUT_COUNTER|divclk
    u_core|u_clocks|u_pll|altera_pll_i|general[4].gpll~PLL_OUTPUT_COUNTER|divclk
}]
if {[get_collection_size $pocket_pll_clocks] > 0} {
    lappend pocket_clock_group_args -group $pocket_pll_clocks
}

if {[llength $pocket_clock_group_args] > 3} {
    eval set_clock_groups $pocket_clock_group_args
}

unset pocket_clock_group_args
unset pocket_clock_filter
unset pocket_clocks
unset pocket_pll_clocks

derive_clock_uncertainty
EOF

if (( ! use_legacy_gametop )); then
    cp -f "$gametop_src" "$fpga_dir/${GAMETOP}.v"
    cp -f "$pocket_core_dir/mem_ports.inc" "$fpga_dir/mem_ports.inc"
fi
cp -f "$repo_root/modules/jtframe/bin/font0.hex" "$fpga_dir/font0.hex"
for collateral_dir in "$repo_root/cores/$core/hdl" "$pocket_core_dir"; do
    copy_hdl_collateral_dir "$collateral_dir"
done
while IFS= read -r qip_line; do
    if [[ "$qip_line" =~ '\[file join \$::quartus\(qip_path\) ([^]]+)\]' ]]; then
        source_rel="$match[1]"
        source_dir="$(cd "$fpga_dir" && cd "${source_rel:h}" 2>/dev/null && pwd)" || continue
        copy_hdl_collateral_dir "$source_dir"
    fi
done < "$fpga_dir/files.qip"

require_file "$fpga_dir/ap_core.qsf"
require_file "$fpga_dir/ap_core.qpf"
require_file "$fpga_dir/core/core_constraints.sdc"
require_file "$fpga_dir/files.qip"
if (( ! use_legacy_gametop )); then
    require_file "$fpga_dir/${GAMETOP}.v"
    require_file "$fpga_dir/mem_ports.inc"
fi
require_file "$fpga_dir/font0.hex"

cd "$repo_root"
export JTROOT="$repo_root"
export JTFRAME="$repo_root/modules/jtframe"
export CORES="$repo_root/cores"
export MODULES="$repo_root/modules"
export JTBIN="$dist_dir"

rm -rf "$dist_dir/pocket" "$core_dir"
"$repo_root/modules/jtframe/bin/jtframe" mra "$core" --skipROM --skipMRA --nodbg --git

require_dir "$metadata_src_dir" "jtframe mra did not emit the Pocket metadata directory for '$shortname'"
for name in core.json audio.json data.json input.json interact.json variants.json video.json info.txt; do
    require_file "$metadata_src_dir/$name"
done
[[ -s "$metadata_src_dir/info.txt" ]] || die "Pocket info.txt is empty: $metadata_src_dir/info.txt"

jq_assert "$metadata_src_dir/core.json" '.core.magic == "APF_VER_1"' "core.magic must be APF_VER_1"
jq_assert "$metadata_src_dir/core.json" ".core.metadata.shortname == \"$shortname\"" "core.metadata.shortname must match $shortname"
jq_assert "$metadata_src_dir/core.json" '.core.cores | type == "array" and length > 0' "core.cores must contain at least one bitstream entry"
jq_assert "$metadata_src_dir/core.json" '.core.cores[0].filename | type == "string" and length > 0' "core.cores[0].filename must be set"
jq_assert "$metadata_src_dir/core.json" '.core.metadata.platform_ids | type == "array" and length > 0' "core.metadata.platform_ids must contain at least one platform id"
jq_assert "$metadata_src_dir/audio.json" '.audio.magic == "APF_VER_1"' "audio.magic must be APF_VER_1"
jq_assert "$metadata_src_dir/data.json" '.data.magic == "APF_VER_1" and (.data.data_slots | type == "array")' "data.json must contain a data_slots array"
jq_assert "$metadata_src_dir/input.json" '.input.magic == "APF_VER_1" and (.input.controllers | type == "array")' "input.json must contain a controllers array"
jq_assert "$metadata_src_dir/interact.json" '.interact.magic == "APF_VER_1" and (.interact.variables | type == "array")' "interact.json must contain a variables array"
jq_assert "$metadata_src_dir/variants.json" '.variants.magic == "APF_VER_1" and (.variants.variant_list | type == "array")' "variants.json must contain a variant_list array"
jq_assert "$metadata_src_dir/video.json" '.video.magic == "APF_VER_1" and (.video.scaler_modes | type == "array") and (.video.display_modes | type == "array")' "video.json must contain scaler_modes and display_modes arrays"

mkdir -p "$core_dir"
for name in core.json audio.json data.json input.json interact.json variants.json video.json info.txt; do
    cp -f "$metadata_src_dir/$name" "$core_dir/$name"
done
if [[ -d "$platforms_src_dir" ]]; then
    rm -rf "$dist_dir/Platforms"
    cp -R "$platforms_src_dir" "$dist_dir/Platforms"
fi
while IFS= read -r platform_id; do
    [[ -n "$platform_id" ]] || continue
    require_file "$dist_dir/Platforms/${platform_id}.json" "core.json references platform_id '$platform_id'; Pocket packages need dist/Platforms/${platform_id}.json"
    jq_assert "$dist_dir/Platforms/${platform_id}.json" '.platform | type == "object"' "platform JSON must contain a platform object"
done < <(jq -r '.core.metadata.platform_ids[]' "$core_dir/core.json")
if [[ -d "$dist_dir/pocket/raw/Assets" ]]; then
    rm -rf "$dist_dir/Assets"
    cp -R "$dist_dir/pocket/raw/Assets" "$dist_dir/Assets"
fi
if [[ -d "$dist_dir/pocket/raw/Presets" ]]; then
    while IFS= read -r preset_json; do
        case "$preset_json" in
            */Input/*)
                jq_assert "$preset_json" '.input.magic == "APF_VER_1" and (.input.controllers | type == "array")' "input preset must contain an input.controllers array"
                ;;
            */Interact/*)
                jq_assert "$preset_json" '.interact.magic == "APF_VER_1" and (.interact.variables | type == "array")' "interact preset must contain an interact.variables array"
                ;;
        esac
    done < <(find "$dist_dir/pocket/raw/Presets" -type f -name '*.json' | sort)
    rm -rf "$dist_dir/Presets"
    cp -R "$dist_dir/pocket/raw/Presets" "$dist_dir/Presets"
fi

jq '.core.cores[0].filename="bitstream.rbf_r"' \
    "$core_dir/core.json" > "$core_dir/core.json.tmp" || die "failed to rewrite Pocket bitstream filename in $core_dir/core.json"
mv "$core_dir/core.json.tmp" "$core_dir/core.json"
jq_assert "$core_dir/core.json" '.core.cores[0].filename == "bitstream.rbf_r"' "packaged core.json must reference bitstream.rbf_r"

echo "APC project exported to $outdir_abs"
