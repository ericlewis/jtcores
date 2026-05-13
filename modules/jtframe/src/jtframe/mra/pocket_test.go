//go:build pocket

package mra

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"

	"jotego/jtframe/macros"
	"jotego/jtframe/xmlnode"
)

func Test_pocket_primary_video_keeps_apf_width_when_coremod_has_side_frame(t *testing.T) {
	macros.MakeFromMap(map[string]string{
		"JTFRAME_WIDTH":  "280",
		"JTFRAME_HEIGHT": "224",
	})

	oldState := pocket_state
	defer func() { pocket_state = oldState }()
	pocket_state = &pocketState{
		instances: []pocketInstance{
			{main: true, coremod: COREMOD_8PXL_FRAME << COREMOD_HFRAME_BIT},
		},
	}

	width, height, _, _, rotation := pocket_primary_video()

	if width != 280 || height != 224 || rotation != 0 {
		t.Fatalf("wrong Pocket APF shape: got %dx%d rotation %d", width, height, rotation)
	}
}

func Test_pocket_scaler_modes_keep_full_apf_width_for_framed_instances(t *testing.T) {
	oldState := pocket_state
	defer func() { pocket_state = oldState }()
	pocket_state = &pocketState{
		instances: []pocketInstance{
			{main: true, coremod: COREMOD_8PXL_FRAME << COREMOD_HFRAME_BIT},
		},
	}

	modes := pocket_scaler_modes(280, 224, 4, 3, 0)

	if len(modes) != 1 {
		t.Fatalf("expected one scaler mode, got %d: %#v", len(modes), modes)
	}
	if modes[0]["width"] != 280 {
		t.Fatalf("wrong scaler width: got %#v", modes[0]["width"])
	}
}

func Test_pocket_scaler_modes_use_authoritative_override_order(t *testing.T) {
	oldState := pocket_state
	defer func() { pocket_state = oldState }()
	pocket_state = &pocketState{
		shortname: "jttest",
		override: pocketCoreOverride{
			Video: pocketVideoOverride{
				ScalerModes: []pocketScalerModeOverride{
					{Width: 288, Height: 224, AspectW: 4, AspectH: 3, Rotation: 0},
					{Width: 272, Height: 224, AspectW: 4, AspectH: 3, Rotation: 270},
				},
			},
		},
		instances: []pocketInstance{
			{main: true, coremod: COREMOD_VERTICAL},
		},
	}

	modes := pocket_scaler_modes(320, 240, 5, 4, 90)

	if len(modes) != 2 {
		t.Fatalf("expected override scaler modes only, got %d: %#v", len(modes), modes)
	}
	if modes[0]["width"] != 288 || modes[0]["rotation"] != 0 || modes[0]["aspect_w"] != 4 {
		t.Fatalf("first override mode changed: %#v", modes[0])
	}
	if modes[1]["width"] != 272 || modes[1]["rotation"] != 270 {
		t.Fatalf("second override mode changed: %#v", modes[1])
	}
}

func Test_pocket_instance_data_slots_include_optional_save_slot(t *testing.T) {
	macros.MakeFromMap(map[string]string{"JTFRAME_IOCTL_RD": "1024"})

	slots := pocket_instance_data_slots(pocketInstance{setname: "circusc"})

	if len(slots) != 2 {
		t.Fatalf("expected ROM and save slots, got %#v", slots)
	}
	if slots[0]["id"] != 1 || slots[0]["filename"] != "circusc.rom" {
		t.Fatalf("wrong ROM slot: %#v", slots[0])
	}
	if slots[1]["id"] != 2 || slots[1]["filename"] != "circusc.sav" {
		t.Fatalf("wrong save slot: %#v", slots[1])
	}
}

func Test_pocket_platform_ids_do_not_inject_private_platform(t *testing.T) {
	oldState := pocket_state
	defer func() { pocket_state = oldState }()

	var cfg Mame2MRA
	cfg.Global.Platform = "jttest"
	pocket_state = &pocketState{
		shortname: "jttest",
		args:      Args{Core: "test"},
		cfg:       cfg,
	}

	ids := pocket_platform_ids()

	if len(ids) != 1 || ids[0] != "jttest" {
		t.Fatalf("expected only public platform id, got %#v", ids)
	}
}

func Test_pocket_instance_memory_writes_do_not_inject_flip_overlay(t *testing.T) {
	macros.MakeFromMap(map[string]string{"JTFRAME_OSD_FLIP": "1"})

	writes := pocket_instance_memory_writes(pocketInstance{
		coremod:      0x12,
		dipswDefault: 0xA5,
	})

	if len(writes) != 2 {
		t.Fatalf("expected only coremod and DIP writes, got %#v", writes)
	}
	for _, write := range writes {
		if write["address"] == "0x60000000" {
			t.Fatalf("unexpected Flip Screen overlay write: %#v", writes)
		}
	}
}

func Test_pocket_save_presets_mirrors_slot0_asset_path(t *testing.T) {
	macros.MakeFromMap(map[string]string{})
	oldState := pocket_state
	defer func() { pocket_state = oldState }()

	switches := xmlnode.MakeNode("switches")
	switches.AddNode("dip").
		AddAttr("name", "Lives").
		AddAttr("bits", "0,1").
		AddAttr("ids", "1,2,3,5")

	var cfg Mame2MRA
	cfg.Global.Platform = "jttest"
	tmp := t.TempDir()
	pocket_state = &pocketState{
		shortname: "jttest",
		args:      Args{pocketdir: tmp},
		cfg:       cfg,
	}
	presets := []pocketPreset{
		{
			instance: pocketInstance{
				description:  "Example Game",
				setname:      "example",
				main:         true,
				dipswDefault: 2,
				buttons:      []string{"Fire"},
				switches:     &switches,
			},
			relpath: filepath.Join("jotego.jttest", "Example Game.json"),
		},
	}

	pocket_save_instances(presets)
	pocket_save_presets(presets)

	instancePath := filepath.Join(tmp, "Assets", "jttest", "jotego.jttest", "Example Game.json")
	inputPath := filepath.Join(tmp, "Presets", "jotego.jttest", "Input", "jttest", "jotego.jttest", "Example Game.json")
	interactPath := filepath.Join(tmp, "Presets", "jotego.jttest", "Interact", "jttest", "jotego.jttest", "Example Game.json")
	for _, path := range []string{instancePath, inputPath, interactPath} {
		if _, err := os.Stat(path); err != nil {
			t.Fatalf("expected generated preset path %s: %v", path, err)
		}
	}

	var input map[string]interface{}
	if err := readJSON(inputPath, &input); err != nil {
		t.Fatal(err)
	}
	inputBody := input["input"].(map[string]interface{})
	controllers := inputBody["controllers"].([]interface{})
	mappings := controllers[0].(map[string]interface{})["mappings"].([]interface{})
	if len(mappings) != 1 {
		t.Fatalf("expected only real per-instance buttons, got %#v", mappings)
	}
	if mappings[0].(map[string]interface{})["name"] != "Fire" {
		t.Fatalf("per-instance input mapping not preserved: %#v", mappings[0])
	}

	var interact map[string]interface{}
	if err := readJSON(interactPath, &interact); err != nil {
		t.Fatal(err)
	}
	interactBody := interact["interact"].(map[string]interface{})
	variables := interactBody["variables"].([]interface{})
	if len(variables) != 1 {
		t.Fatalf("expected one DIP variable, got %#v", variables)
	}
	if variables[0].(map[string]interface{})["defaultval"] != float64(2) {
		t.Fatalf("per-instance DIP default not preserved: %#v", variables[0])
	}
}

func readJSON(path string, out interface{}) error {
	buf, err := os.ReadFile(path)
	if err != nil {
		return err
	}
	return json.Unmarshal(buf, out)
}
