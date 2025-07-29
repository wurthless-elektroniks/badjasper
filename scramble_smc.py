
import sys

def main(args):
    if len(args) < 3:
        print("usage: python3 scramble_smc.py unscrambled_smc_in.bin scrambled_smc_out.bin")
        return
    
    data = None
    with open(args[1], "rb") as f:
        data = f.read()
    
    # these random bytes can be anything, the SMC doesn't care
    rnd = bytes([0x04, 0x20, 0x69, 0x69])

    data = rnd + data[4:-8] + data[0:4] + b"\x00"*4

    with open(args[2], "wb") as f:
        f.write(data)

    print("dunzo")

if __name__ == '__main__':
    main(sys.argv)
