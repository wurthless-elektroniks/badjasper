'''
Takes SMC from one ECC and shove it into another.
This is a dumb script which performs no ECC recalculation.

Originally intended for injecting different SMCs into RGH3 images.
'''

import sys
def main():
    if len(sys.argv) < 4:
        print(f"usage: {sys.argv[0]} smc_source.ecc build_source.ecc output.ecc")
        exit(1)

    glitch2_ecc = None
    rgh3_ecc = None

    with open(sys.argv[1], "rb") as f:
        glitch2_ecc = f.read()
    
    with open(sys.argv[2], "rb") as f:
        rgh3_ecc = f.read()
    
    merged_ecc = rgh3_ecc[0:0x1080] + glitch2_ecc[0x1080:0x4200] + rgh3_ecc[0x4200:]

    with open(sys.argv[3], "wb") as f:
        f.write(merged_ecc)

if __name__ == "__main__":
    main()
