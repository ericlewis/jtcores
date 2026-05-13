//go:build pocket

package mra

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"jotego/jtframe/common"
	"jotego/jtframe/macros"

	"gopkg.in/yaml.v2"

	. "jotego/jtframe/xmlnode"
)

type pocketState struct {
	cfg         Mame2MRA
	args        Args
	shortname   string
	coreDir     string
	description string
	buttons     []string
	instances   []pocketInstance
	override    pocketCoreOverride
}

type pocketInstance struct {
	description  string
	setname      string
	main         bool
	coremod      int
	dipswDefault uint32
	buttons      []string
	switches     *XMLNode
}

type pocketPreset struct {
	instance pocketInstance
	relpath  string
}

type pocketOverrides struct {
	Cores map[string]pocketCoreOverride `yaml:"cores"`
}

type pocketCoreOverride struct {
	Reason string              `yaml:"reason"`
	Video  pocketVideoOverride `yaml:"video"`
}

type pocketVideoOverride struct {
	AspectW     int                        `yaml:"aspect_w"`
	AspectH     int                        `yaml:"aspect_h"`
	ScalerModes []pocketScalerModeOverride `yaml:"scaler_modes"`
}

type pocketScalerModeOverride struct {
	Width    int `yaml:"width"`
	Height   int `yaml:"height"`
	AspectW  int `yaml:"aspect_w"`
	AspectH  int `yaml:"aspect_h"`
	Rotation int `yaml:"rotation"`
	Mirror   int `yaml:"mirror"`
}

var pocket_state *pocketState

const (
	pocketROMBase  = 0x10000000
	pocketCartBase = 0x10000000
	pocketSaveBase = 0x20000000
)

func pocket_clear() {
	pocket_state = nil
}

func pocket_init(cfg Mame2MRA, args Args) {
	shortname := strings.ToLower(macros.Get("CORENAME"))
	if shortname == "" {
		shortname = strings.ToLower(args.Core)
	}
	coreDir := filepath.Join(args.pocketdir, "Cores", "jotego."+shortname)
	pocket_state = &pocketState{
		cfg:       cfg,
		args:      args,
		shortname: shortname,
		coreDir:   coreDir,
		override:  pocket_load_core_override(args.Core, shortname),
	}
}

func pocket_add(machine *MachineXML, cfg Mame2MRA, args Args, def_dipsw string, coremod int, mra *XMLNode) {
	if pocket_state == nil {
		pocket_init(cfg, args)
	}
	if pocket_state.description == "" {
		pocket_state.description = mra_name(machine, cfg)
	}
	if len(pocket_state.buttons) == 0 {
		pocket_state.buttons = resolve_button_names(machine, cfg, args)
	}
	pocket_state.instances = append(pocket_state.instances, pocketInstance{
		description:  pocket_asset_name(mra),
		setname:      get_setname_from_mra(mra),
		main:         is_main(machine, cfg),
		coremod:      coremod,
		dipswDefault: pocket_dipsw_default(mra),
		buttons:      resolve_button_names(machine, cfg, args),
		switches:     mra.FindNode("switches"),
	})
}

func pocket_save() {
	if pocket_state == nil {
		return
	}
	common.Must(os.MkdirAll(pocket_state.coreDir, 0o775))

	version := "0.0.0-dev"
	if commit, err := common.GetCommit(); err == nil {
		version = "0.0.0-" + commit
	}
	dateRelease := time.Now().Format("2006-01-02")
	if pocket_state.description == "" {
		pocket_state.description = pocket_state.shortname
	}
	presets := pocket_presets()
	videoWidth, videoHeight, aspectW, aspectH, rotation := pocket_primary_video()

	platformIDs := pocket_platform_ids()

	coreJSON := map[string]interface{}{
		"core": map[string]interface{}{
			"magic": "APF_VER_1",
			"metadata": map[string]interface{}{
				"platform_ids": platformIDs,
				"shortname":    pocket_state.shortname,
				"description":  pocket_state.description,
				"author":       "jotego",
				"url":          pocket_url(pocket_state.cfg),
				"version":      version,
				"date_release": dateRelease,
			},
			"framework": map[string]interface{}{
				"target_product":   "Analogue Pocket",
				"version_required": "1.1",
				"sleep_supported":  false,
				"dock": map[string]interface{}{
					"supported":     true,
					"analog_output": false,
				},
				"hardware": map[string]interface{}{
					"link_port":         false,
					"cartridge_adapter": 0,
				},
			},
			"cores": []map[string]interface{}{
				{
					"name":     pocket_state.shortname,
					"id":       0,
					"filename": pocket_state.shortname + ".rbf_r",
				},
			},
		},
	}

	audioJSON := map[string]interface{}{
		"audio": map[string]interface{}{
			"magic": "APF_VER_1",
		},
	}

	dataJSON := map[string]interface{}{
		"data": map[string]interface{}{
			"magic":      "APF_VER_1",
			"data_slots": pocket_data_slots(pocket_state.cfg),
		},
	}

	inputJSON := map[string]interface{}{
		"input": map[string]interface{}{
			"magic": "APF_VER_1",
			"controllers": []map[string]interface{}{
				{
					"type":     "default",
					"mappings": pocket_input_mappings(pocket_state.buttons),
				},
			},
		},
	}

	interactJSON := map[string]interface{}{
		"interact": map[string]interface{}{
			"magic":     "APF_VER_1",
			"variables": pocket_interact_variables(pocket_state.instances),
			"messages":  nil,
		},
	}

	variantsJSON := map[string]interface{}{
		"variants": map[string]interface{}{
			"magic":        "APF_VER_1",
			"variant_list": []interface{}{},
		},
	}

	videoJSON := map[string]interface{}{
		"video": map[string]interface{}{
			"magic":         "APF_VER_1",
			"scaler_modes":  pocket_scaler_modes(videoWidth, videoHeight, aspectW, aspectH, rotation),
			"display_modes": pocket_display_modes(pocket_state.cfg.Pocket.Display_modes),
		},
	}

	common.Must(write_json(filepath.Join(pocket_state.coreDir, "core.json"), coreJSON))
	common.Must(write_json(filepath.Join(pocket_state.coreDir, "audio.json"), audioJSON))
	common.Must(write_json(filepath.Join(pocket_state.coreDir, "data.json"), dataJSON))
	common.Must(write_json(filepath.Join(pocket_state.coreDir, "input.json"), inputJSON))
	common.Must(write_json(filepath.Join(pocket_state.coreDir, "interact.json"), interactJSON))
	common.Must(write_json(filepath.Join(pocket_state.coreDir, "variants.json"), variantsJSON))
	common.Must(write_json(filepath.Join(pocket_state.coreDir, "video.json"), videoJSON))
	common.Must(os.WriteFile(filepath.Join(pocket_state.coreDir, "info.txt"), []byte(pocket_info_text()), 0o664))
	pocket_save_platforms(platformIDs)
	pocket_save_instances(presets)
	pocket_save_presets(presets)
}

func pocket_pico(data []byte) {
	// Placeholder. Pocket packaging may later emit Chip32 helpers or auxiliary
	// files from this hook, but the public scaffold intentionally keeps this
	// path inert until the real target command/data-slot flow exists.
}

func pocket_url(cfg Mame2MRA) string {
	if cfg.Global.Webpage != "" {
		return cfg.Global.Webpage
	}
	return "https://github.com/jotego/jtcores"
}

func pocket_platform_ids() []string {
	if pocket_state == nil {
		return nil
	}
	platformID := pocket_platform_id(pocket_state.cfg, pocket_state.args)
	if platformID == "" {
		return nil
	}
	return []string{platformID}
}

func pocket_primary_video() (width, height, aspectW, aspectH, rotation int) {
	width = macro_int("JTFRAME_WIDTH", 320)
	height = macro_int("JTFRAME_HEIGHT", 240)
	aspectW = macro_int("JTFRAME_ARX", 4)
	aspectH = macro_int("JTFRAME_ARY", 3)
	aspectW, aspectH = pocket_video_aspect_override(aspectW, aspectH)

	inst, ok := pocket_primary_instance()
	if !ok {
		if macros.IsSet("JTFRAME_VERTICAL") {
			rotation = 90
		}
		return
	}

	rotation = pocket_coremod_rotation(inst.coremod)
	return
}

func pocket_primary_instance() (pocketInstance, bool) {
	if pocket_state == nil {
		return pocketInstance{}, false
	}
	for _, inst := range pocket_state.instances {
		if inst.main {
			return inst, true
		}
	}
	if len(pocket_state.instances) == 0 {
		return pocketInstance{}, false
	}
	return pocket_state.instances[0], true
}

func pocket_coremod_width(width, coremod int) int {
	frame := (uint(coremod) & COREMOD_HFRAME_MASK) >> COREMOD_HFRAME_BIT
	switch frame {
	case COREMOD_8PXL_FRAME:
		width -= 16
	case COREMOD_16PXL_FRAME:
		width -= 32
	}
	if width < 1 {
		return 1
	}
	return width
}

func pocket_coremod_rotation(coremod int) int {
	if coremod&COREMOD_VERTICAL == 0 {
		return 0
	}
	if coremod&COREMOD_XORFLIP != 0 {
		return 270
	}
	return 90
}

func pocket_video_aspect_override(aspectW, aspectH int) (int, int) {
	if pocket_state == nil {
		return aspectW, aspectH
	}
	override := pocket_state.override.Video
	if override.AspectW > 0 && override.AspectH > 0 {
		return override.AspectW, override.AspectH
	}
	return aspectW, aspectH
}

func pocket_load_core_override(core, shortname string) pocketCoreOverride {
	overrides, err := pocket_load_overrides()
	common.Must(err)
	if len(overrides.Cores) == 0 {
		return pocketCoreOverride{}
	}
	for _, key := range []string{
		strings.ToLower(core),
		strings.TrimPrefix(strings.ToLower(shortname), "jt"),
		strings.ToLower(shortname),
	} {
		if key == "" {
			continue
		}
		if override, ok := overrides.Cores[key]; ok {
			return override
		}
	}
	return pocketCoreOverride{}
}

func pocket_load_overrides() (pocketOverrides, error) {
	var overrides pocketOverrides
	path := pocket_overrides_path()
	if path == "" {
		return overrides, nil
	}
	buf, err := os.ReadFile(path)
	if os.IsNotExist(err) {
		return overrides, nil
	}
	if err != nil {
		return overrides, fmt.Errorf("cannot read Pocket target overrides %s: %w", path, err)
	}
	if err := yaml.Unmarshal(buf, &overrides); err != nil {
		return overrides, fmt.Errorf("cannot parse Pocket target overrides %s: %w", path, err)
	}
	return overrides, nil
}

func pocket_overrides_path() string {
	jtframe := os.Getenv("JTFRAME")
	if jtframe == "" {
		return ""
	}
	return filepath.Join(jtframe, "target", "pocket", "overrides.yaml")
}

func pocket_platform_id(cfg Mame2MRA, args Args) string {
	if cfg.Global.Platform != "" {
		return cfg.Global.Platform
	}
	if args.Core != "" {
		return "jt" + args.Core
	}
	return pocket_state.shortname
}

func pocket_save_platforms(platformIDs []string) {
	if pocket_state == nil {
		return
	}
	platformDir := filepath.Join(pocket_state.args.pocketdir, "Platforms")
	common.Must(os.MkdirAll(platformDir, 0o775))
	for _, id := range platformIDs {
		if id == "" {
			continue
		}
		platformJSON := map[string]interface{}{
			"platform": map[string]interface{}{
				"category":     "Arcade",
				"name":         id,
				"year":         time.Now().Year(),
				"manufacturer": "JT FPGA",
			},
		}
		common.Must(write_json(filepath.Join(platformDir, id+".json"), platformJSON))
	}
}

func pocket_asset_name(mra *XMLNode) string {
	if mra == nil {
		return ""
	}
	name := mra.GetNode("name")
	if name == nil {
		return ""
	}
	out := strings.ReplaceAll(name.GetText(), ":", "")
	out = strings.ReplaceAll(out, "/", "-")
	return fix_filename(out)
}

func pocket_dipsw_default(mra *XMLNode) uint32 {
	value := uint32(0xFFFFFFFF)
	if mra == nil {
		return value
	}
	switches := mra.FindNode("switches")
	if switches == nil {
		return value
	}
	for idx, part := range strings.Split(switches.GetAttr("default"), ",") {
		part = strings.TrimSpace(part)
		if part == "" || idx >= 4 {
			continue
		}
		byteValue, err := strconv.ParseUint(part, 16, 8)
		if err != nil {
			continue
		}
		shift := uint(idx * 8)
		value = (value & ^(uint32(0xFF) << shift)) | (uint32(byteValue) << shift)
	}
	return value
}

func pocket_presets() []pocketPreset {
	if pocket_state == nil || pocket_state.cfg.ROM.Firmware != "" {
		return nil
	}
	presets := make([]pocketPreset, 0, len(pocket_state.instances))
	for _, inst := range pocket_state.instances {
		if inst.description == "" || inst.setname == "" {
			continue
		}
		relDir := filepath.Join("jotego." + pocket_state.shortname)
		if !inst.main {
			relDir = filepath.Join(relDir, "_alternatives")
		}
		presets = append(presets, pocketPreset{
			instance: inst,
			relpath:  filepath.Join(relDir, inst.description+".json"),
		})
	}
	return presets
}

func pocket_save_instances(presets []pocketPreset) {
	if pocket_state == nil || len(presets) == 0 {
		return
	}
	platformID := pocket_platform_id(pocket_state.cfg, pocket_state.args)
	assetRoot := filepath.Join(pocket_state.args.pocketdir, "Assets", platformID)
	commonDir := filepath.Join(assetRoot, "common")
	common.Must(os.MkdirAll(commonDir, 0o775))

	for _, preset := range presets {
		inst := preset.instance
		outPath := filepath.Join(assetRoot, preset.relpath)
		common.Must(os.MkdirAll(filepath.Dir(outPath), 0o775))
		instanceJSON := map[string]interface{}{
			"instance": map[string]interface{}{
				"magic": "APF_VER_1",
				"variant_select": map[string]interface{}{
					"id":     0,
					"select": false,
				},
				"data_path":     "",
				"data_slots":    pocket_instance_data_slots(inst),
				"memory_writes": pocket_instance_memory_writes(inst),
			},
		}
		common.Must(write_json(outPath, instanceJSON))
		pocket_copy_rom_if_present(inst.setname, commonDir)
	}
}

func pocket_save_presets(presets []pocketPreset) {
	if pocket_state == nil || len(presets) == 0 {
		return
	}
	platformID := pocket_platform_id(pocket_state.cfg, pocket_state.args)
	root := filepath.Join(pocket_state.args.pocketdir, "Presets", "jotego."+pocket_state.shortname)
	for _, preset := range presets {
		inputJSON := map[string]interface{}{
			"input": map[string]interface{}{
				"magic": "APF_VER_1",
				"controllers": []map[string]interface{}{
					{
						"type":     "default",
						"mappings": pocket_input_mappings(preset.instance.buttons),
					},
				},
			},
		}
		interactJSON := map[string]interface{}{
			"interact": map[string]interface{}{
				"magic":     "APF_VER_1",
				"variables": pocket_interact_variables_for_instance(preset.instance),
				"messages":  nil,
			},
		}
		for _, spec := range []struct {
			kind string
			data map[string]interface{}
		}{
			{"Input", inputJSON},
			{"Interact", interactJSON},
		} {
			path := filepath.Join(root, spec.kind, platformID, preset.relpath)
			common.Must(os.MkdirAll(filepath.Dir(path), 0o775))
			common.Must(write_json(path, spec.data))
		}
	}
}

func pocket_instance_data_slots(inst pocketInstance) []map[string]interface{} {
	slots := []map[string]interface{}{
		{
			"id":       1,
			"filename": inst.setname + ".rom",
		},
	}
	if macros.IsSet("JTFRAME_IOCTL_RD") {
		slots = append(slots, map[string]interface{}{
			"id":       2,
			"filename": inst.setname + ".sav",
		})
	}
	return slots
}

func pocket_instance_memory_writes(inst pocketInstance) []map[string]interface{} {
	return []map[string]interface{}{
		map[string]interface{}{
			"address": "0xF9000000",
			"data":    fmt.Sprintf("0x%X", inst.coremod),
		},
		map[string]interface{}{
			"address": "0xF9000004",
			"data":    fmt.Sprintf("0x%08X", inst.dipswDefault),
		},
	}
}

func pocket_copy_rom_if_present(setname, commonDir string) {
	if setname == "" {
		return
	}
	src := filepath.Join(os.Getenv("JTROOT"), "rom", setname+".rom")
	data, err := os.ReadFile(src)
	if err != nil {
		return
	}
	common.Must(os.WriteFile(filepath.Join(commonDir, setname+".rom"), data, 0o664))
}

func pocket_interact_variables(instances []pocketInstance) []interface{} {
	if len(instances) == 0 || instances[0].switches == nil {
		return []interface{}{}
	}
	return pocket_interact_variables_for_instance(instances[0])
}

func pocket_interact_variables_for_instance(inst pocketInstance) []interface{} {
	if inst.switches == nil {
		return []interface{}{}
	}
	variables := make([]interface{}, 0, 16)
	nextID := 1
	for _, child := range inst.switches.GetChildren() {
		if child.GetName() != "dip" {
			continue
		}
		lsb, msb, ok := pocket_parse_bits(child.GetAttr("bits"))
		if !ok || msb < lsb || msb >= 32 {
			continue
		}
		optionNames := pocket_option_names(child.GetAttr("ids"))
		if len(optionNames) == 0 {
			continue
		}
		width := uint(msb - lsb + 1)
		fieldMask := ((uint64(1) << width) - 1) << uint(lsb)
		defaultIndex := int((uint64(inst.dipswDefault) & fieldMask) >> uint(lsb))
		if defaultIndex >= len(optionNames) {
			defaultIndex = len(optionNames) - 1
		}
		options := make([]map[string]interface{}, 0, len(optionNames))
		for idx, name := range optionNames {
			options = append(options, map[string]interface{}{
				"name":  name,
				"value": fmt.Sprintf("0x%08X", uint32(idx)<<uint(lsb)),
			})
		}
		variables = append(variables, map[string]interface{}{
			"name":       child.GetAttr("name"),
			"id":         nextID,
			"type":       "list",
			"enabled":    true,
			"persist":    true,
			"address":    "0xF9000004",
			"defaultval": defaultIndex,
			"mask":       fmt.Sprintf("0x%08X", uint32(^fieldMask)),
			"options":    options,
		})
		nextID++
	}
	return variables
}

func pocket_parse_bits(bits string) (lsb, msb int, ok bool) {
	parts := strings.Split(bits, ",")
	if len(parts) == 0 || len(parts) > 2 {
		return 0, 0, false
	}
	first, err := strconv.Atoi(strings.TrimSpace(parts[0]))
	if err != nil {
		return 0, 0, false
	}
	second := first
	if len(parts) == 2 {
		second, err = strconv.Atoi(strings.TrimSpace(parts[1]))
		if err != nil {
			return 0, 0, false
		}
	}
	if first <= second {
		return first, second, true
	}
	return second, first, true
}

func pocket_option_names(ids string) []string {
	if ids == "" {
		return nil
	}
	raw := strings.Split(ids, ",")
	out := make([]string, 0, len(raw))
	for idx, name := range raw {
		name = strings.TrimSpace(name)
		if name == "" {
			name = strconv.Itoa(idx)
		}
		out = append(out, name)
	}
	return out
}

func pocket_info_text() string {
	return fmt.Sprintf(
		"* Auto-generated Pocket target for %s\n* APF host/target command space implemented at 0xF8000000\n* Data slot windows: ROM 0x10000000, Cart 0x10000000, Save 0x20000000\n* The physical APF shell wiring still needs to be completed for hardware use\n",
		pocket_state.shortname,
	)
}

func pocket_data_slots(cfg Mame2MRA) []map[string]interface{} {
	slots := make([]map[string]interface{}, 0, 5)

	makeExts := func(src []string, fallback ...string) []string {
		out := make([]string, 0, len(src)+len(fallback))
		for _, each := range src {
			each = strings.TrimSpace(strings.TrimPrefix(each, "."))
			if each != "" {
				out = append(out, each)
			}
		}
		if len(out) == 0 {
			out = append(out, fallback...)
		}
		return out
	}

	firmwareExt := "bin"
	if cfg.ROM.Firmware != "" {
		if ext := strings.TrimPrefix(filepath.Ext(cfg.ROM.Firmware), "."); ext != "" {
			firmwareExt = ext
		}
		slots = append(slots, map[string]interface{}{
			"name":        "firmware",
			"id":          1,
			"required":    true,
			"parameters":  "0x108",
			"filename":    cfg.ROM.Firmware,
			"extensions":  []string{firmwareExt},
			"address":     fmt.Sprintf("0x%08X", pocketROMBase),
			"nonvolatile": false,
		})
	}

	if cfg.ROM.Firmware == "" {
		slots = append(slots, map[string]interface{}{
			"name":        "Arcade Game",
			"id":          0,
			"required":    true,
			"parameters":  "0x113",
			"extensions":  []string{"json"},
			"address":     "",
			"nonvolatile": false,
		})
	}

	assetID := 1
	assetBase := pocketROMBase
	assetName := "ROM"
	assetParams := "0x108"
	if cfg.ROM.Firmware != "" {
		assetID = 4
		assetBase = pocketCartBase
		assetName = "Cartridge"
		assetParams = "0x09"
	}

	slots = append(slots, map[string]interface{}{
		"name":        assetName,
		"id":          assetID,
		"required":    true,
		"parameters":  assetParams,
		"extensions":  makeExts(cfg.ROM.Carts, "rom", "bin"),
		"address":     fmt.Sprintf("0x%08X", assetBase),
		"nonvolatile": false,
	})

	if macros.IsSet("JTFRAME_IOCTL_RD") {
		saveSize := macro_int("JTFRAME_IOCTL_RD", 0)
		saveSlot := map[string]interface{}{
			"name":        "NVRAM",
			"id":          2,
			"required":    false,
			"parameters":  "0x100",
			"nonvolatile": true,
			"extensions":  []string{"sav"},
			"address":     fmt.Sprintf("0x%08X", pocketSaveBase),
		}
		if saveSize > 0 {
			saveSlot["size_maximum"] = saveSize
		}
		slots = append(slots, saveSlot)
	}

	return slots
}

func pocket_display_modes(modes []int) []map[string]interface{} {
	if len(modes) == 0 {
		modes = []int{0x10, 0x20, 0x30, 0x40, 0xE0, 0xE1}
	}
	out := make([]map[string]interface{}, 0, len(modes))
	for _, mode := range modes {
		out = append(out, map[string]interface{}{
			"id": fmt.Sprintf("0x%X", mode),
		})
	}
	return out
}

func pocket_scaler_modes(width, height, aspectW, aspectH, rotation int) []map[string]interface{} {
	if modes := pocket_override_scaler_modes(); len(modes) != 0 {
		return modes
	}

	mode := func(w, h, rot int) map[string]interface{} {
		return map[string]interface{}{
			"width":    w,
			"height":   h,
			"aspect_w": aspectW,
			"aspect_h": aspectH,
			"rotation": rot,
			"mirror":   0,
		}
	}

	modes := make([]map[string]interface{}, 0, 8)
	seen := make(map[string]bool)
	addMode := func(w, h, rot int) {
		if len(modes) >= 8 {
			return
		}
		key := fmt.Sprintf("%dx%d@%d", w, h, rot)
		if seen[key] {
			return
		}
		seen[key] = true
		modes = append(modes, mode(w, h, rot))
	}

	addMode(width, height, rotation)
	if pocket_state != nil && len(pocket_state.instances) != 0 {
		baseWidth := macro_int("JTFRAME_WIDTH", width)
		for _, inst := range pocket_state.instances {
			addMode(
				baseWidth,
				height,
				pocket_coremod_rotation(inst.coremod),
			)
		}
	}
	if rotation == 90 {
		addMode(width, height, 270)
	} else if rotation == 270 {
		addMode(width, height, 90)
	}
	if rotation == 0 && width == 256 && height == 240 {
		addMode(width, height, 270)
		addMode(width, height, 90)
		addMode(240, height, 0)
		addMode(224, height, 0)
	}
	return modes
}

func pocket_override_scaler_modes() []map[string]interface{} {
	if pocket_state == nil || len(pocket_state.override.Video.ScalerModes) == 0 {
		return nil
	}
	out := make([]map[string]interface{}, 0, len(pocket_state.override.Video.ScalerModes))
	for idx, mode := range pocket_state.override.Video.ScalerModes {
		if mode.Width <= 0 || mode.Height <= 0 {
			common.Must(fmt.Errorf("invalid Pocket scaler override for %s mode %d: width and height must be positive", pocket_state.shortname, idx))
		}
		if mode.AspectW <= 0 || mode.AspectH <= 0 {
			common.Must(fmt.Errorf("invalid Pocket scaler override for %s mode %d: aspect_w and aspect_h must be positive", pocket_state.shortname, idx))
		}
		if mode.Rotation != 0 && mode.Rotation != 90 && mode.Rotation != 180 && mode.Rotation != 270 {
			common.Must(fmt.Errorf("invalid Pocket scaler override for %s mode %d: rotation must be 0, 90, 180, or 270", pocket_state.shortname, idx))
		}
		if mode.Mirror != 0 && mode.Mirror != 1 {
			common.Must(fmt.Errorf("invalid Pocket scaler override for %s mode %d: mirror must be 0 or 1", pocket_state.shortname, idx))
		}
		out = append(out, map[string]interface{}{
			"width":    mode.Width,
			"height":   mode.Height,
			"aspect_w": mode.AspectW,
			"aspect_h": mode.AspectH,
			"rotation": mode.Rotation,
			"mirror":   mode.Mirror,
		})
	}
	return out
}

func pocket_input_mappings(buttons []string) []map[string]interface{} {
	keys := []string{
		"pad_btn_a",
		"pad_btn_b",
		"pad_btn_x",
		"pad_btn_y",
		"pad_trig_l",
		"pad_trig_r",
		"pad_btn_start",
		"pad_btn_select",
	}
	mappings := make([]map[string]interface{}, 0, len(keys))
	for _, each := range buttons {
		if len(mappings) >= len(keys) {
			break
		}
		name := strings.TrimSpace(each)
		if name == "" || name == "-" {
			continue
		}
		idx := len(mappings)
		mappings = append(mappings, map[string]interface{}{
			"id":   idx,
			"name": name,
			"key":  keys[idx],
		})
	}
	return mappings
}

func resolve_button_names(machine *MachineXML, cfg Mame2MRA, args Args) []string {
	buttonDef := "button 1,button 2"
	buttonSet := false
	for _, b := range cfg.Buttons.Names {
		match := b.Match(machine)
		if (match == 1 && !buttonSet) || match == 2 {
			buttonDef = b.Names
			buttonSet = true
		}
		if match == 3 {
			buttonDef = b.Names
			break
		}
	}
	if args.Buttons != "" {
		buttonDef = args.Buttons
	}
	if buttonDef == "" {
		buttonDef = "Shot,Jump"
	}
	parts := strings.Split(buttonDef, ",")
	out := make([]string, 0, len(parts))
	for _, each := range parts {
		name := strings.TrimSpace(each)
		if name == "" || name == "-" {
			continue
		}
		out = append(out, name)
	}
	return out
}

func macro_int(name string, def int) int {
	raw := macros.Get(name)
	if raw == "" {
		return def
	}
	v, err := strconv.ParseInt(raw, 0, 64)
	if err != nil {
		return def
	}
	return int(v)
}

func write_json(fname string, data interface{}) error {
	bb, err := json.MarshalIndent(data, "", "  ")
	if err != nil {
		return err
	}
	bb = append(bb, '\n')
	return os.WriteFile(fname, bb, 0o664)
}
