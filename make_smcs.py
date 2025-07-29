'''
Bulk SMC makescript
'''

import struct
import platform
import os
import subprocess

def find_c51asm() -> str | None:
    if platform.system() == "Darwin": # =macos
        return os.path.join("bin", "c51asm_darwin")

    if platform.system() == "Windows":
        return os.path.join("bin", "c51asm.exe")

    raise RuntimeError("your platform isn't supported yet (sorry, linux havers)")

def apply_overlay(clean_smc: bytes, smc_overlay: bytes) -> bytes | None:
    # check for 0x90 as first byte in overlay
    if smc_overlay[0] != 0x90:
        print("first byte of overlay not 0x90")
        return None

    # read overlays. they are two instructions back to back.
    # and keep reading until 0x00 is encountered.
    overlay_parse_pos = 0

    patched_smc = bytearray(clean_smc)

    while True:
        if smc_overlay[overlay_parse_pos+0] == 0:
            break

        if smc_overlay[overlay_parse_pos+0] != 0x90 or smc_overlay[overlay_parse_pos+3] != 0x90:
            print(f"overlay header is invalid at offset {overlay_parse_pos:04x}")

        # there's not much error handling here, so be careful with how you assemble things
        patch_start_address = struct.unpack(">H", smc_overlay[overlay_parse_pos+1:overlay_parse_pos+3])[0]
        patch_end_address   = struct.unpack(">H", smc_overlay[overlay_parse_pos+4:overlay_parse_pos+6])[0]
        patched_smc[patch_start_address:patch_end_address] = smc_overlay[patch_start_address:patch_end_address]

        print(f"\t- patched {patch_start_address:04x}~{patch_end_address:04x}")

        overlay_parse_pos += 6

    return patched_smc

def load_or_die(path: str) -> bytes:
    with open(path, "rb") as f:
        return f.read()

def make_patched_smc(c51asm_path:    str,
                     clean_smc_path: str,
                     asm_path:       str,
                     overlay_path:   str,
                     output_path:    str):
    
    # run c51asm to assemble the overlay
    result = subprocess.call(
        executable=c51asm_path,
        args=[
            '',
            asm_path,
            '-fB',
            '-o',
            overlay_path
        ]
    )
    if result != 0:
        raise RuntimeError("c51asm FAILED.")

    clean_smc   = load_or_die(clean_smc_path)
    smc_overlay = load_or_die(overlay_path)
    patched_smc = apply_overlay(clean_smc, smc_overlay)

    with open(output_path, "wb") as f:
        f.write(patched_smc)

SMC_TARGETS = {
    "jasper_smc+badjasper" : {
        "clean_smc_name": "jasper_smc+.bin",            
        "asm_name": "badjasper.s",              
        "overlay_name": "smc+badjasper_jasper_overlay.bin",
        "output": "smc+badjasper.bin"
    },
    "jasper_smc+badjasper_hardreset_on_normal_timeout" : {
        "clean_smc_name": "jasper_smc+.bin",
        "asm_name": "badjasper_hardreset_on_normal_timeout.s",
        "overlay_name": "smc+badjasper_hardreset_on_normal_timeout_overlay.bin",
        "output": "smc+badjasper_hardreset_on_normal_timeout.bin"
    },
    "jasper_smc+badjasper_softreset_on_led_timeout" : {
        "clean_smc_name": "jasper_smc+.bin",
        "asm_name": "badjasper_softreset_on_led_timeout.s",
        "overlay_name": "smc+badjasper_softreset_on_led_timeout_overlay.bin",
        "output": "smc+badjasper_softreset_on_led_timeout.bin"
    }
}

def main():
    # find c51asm - MUST be an absolute path
    print("checking for c51asm...")
    c51asm_path = os.path.join(os.getcwd(),find_c51asm())
    print(f"found c51asm at: {c51asm_path}")
    
    try:
        # cd into the smc directory if we're not there already
        # (this throws exception on failure)
        os.chdir('smc')
        
        for target, target_params in SMC_TARGETS.items():
            print(f"building target: {target}")

            clean_smc_path = target_params["clean_smc_name"]
            asm_path       = target_params["asm_name"]
            overlay_path   = os.path.join("build", target_params["overlay_name"])
            output_path    = os.path.join("build", target_params["output"])

            print(f"\tclean_smc_path = {clean_smc_path}")
            print(f"\tasm_path = {asm_path}")
            print(f"\toverlay_path = {overlay_path}")
            print(f"\toutput_path = {output_path}")

            make_patched_smc(c51asm_path, clean_smc_path, asm_path, overlay_path, output_path)

    finally:
        pass

if __name__ == '__main__':
    main()

