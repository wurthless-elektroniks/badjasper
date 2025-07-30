'''
Patch CDxell so it loops infinitely after it runs GetPowerUpCause.
Used for testing the LED watchdog so we don't have to make a full build and deal with the
headaches that causes.
'''

from patcher import *

def cdxell_make_spinloop_patch(cd: bytes) -> bytes:
    cd = bytearray(cd)

    # place infinite loop right after CDxell runs GetPowerUpCause
    cd, _ = assemble_nop(cd, 0x2D4)
    cd, _ = assemble_branch(cd, 0x2D8, 0x2D4)

    return cd
