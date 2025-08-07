# badjasper: SMC-based workaround for Jasper-related headaches

RGH1.3 is still a work in progress and it's gotten incredibly complex. So, to avoid losing interest and inadvertently
hoarding code, I'm breaking the thing down into smaller chunks. First up is a workaround for troublesome Jaspers.

## NOTA BENE: IT'S A BETA. MAMMA MIA!

I don't have all the consoles in the world and I want to move on to other projects so this has been
released as something I have tested only on a couple of consoles. They might solve your problems,
they might not. Use it at your own risk!

## Explanation

There are two known issues that some Jasper and Tonkaset boards encounter in RGH scenarios. The cause isn't
known, but the symptoms are obvious. Jaspers can be cranky and when they wake up on the wrong side of the bed,
two things can happen:

1. If you glitch the CPU, it will always crash at POST 0xDB, and will keep crashing until you reset the system
   and try again. This one is easy to identify when you're using RGH1.2's timing file 21: you'll keep seeing the
   LED on your glitcher stay on after a glitch cycle, and it will continue to do so for the remainder of that
   power cycle. If you keep varying your timing files and try all combinations of wire routing and capacitor
   bodging and your system still won't cooperate, it probably has this issue.

2. Even if the glitch succeeds, the boot can proceed as normal, even running the GetPowerUpCause handshake, but
   then the CPU will crash before the Ring of Light boot animation starts, which almost always signals that the
   boot is complete. I've encountered this issue on Falcon before, but since I'm coding something for Jasper,
   I might as well code the fix here and port it to Falcon later.

So our fix is simple: we hard reset the system when this happens. Everything powers down for about 20 ms and then
powers back up, then we try the boot again. This is 100% necessary for issue 1, but issue 2 could probably make do with
a simple soft reset.

More specific details:
- There are some spare bytes in memory that are normally zeroed out on reset, but end up going unused. We
  hack the code to spare those bytes from the BSS bulldozer so they persist through a reboot.
- On the first pass through the mainloop, our custom statemachine code executes and initializes those variables.

Reboot statemachine operation for the 0xDB issue:
- When the boot fails on a normal SMC timeout, it jumps to our hard reset routine, which stores the power-up cause
  and arms the state machine for the next pass. Then, it jumps to 0x0000, which reboots. (We need to store the power-up
  cause, otherwise it breaks XeLL.)
- Everything powers down and the SMC makes it back to our reboot statemachine, whose state has persisted through the
  reboot. So, it powers the system on by pretending that the power button was pressed.
- Once the power-up sequence completes, the reboot statemachine restores the power-up cause, and goes idle until it's
  time to run the next hard reset.

LED watchdog statemachine operation for crashes late in the boot process:
- We wait for GetPowerUpCause to arrive before executing this statemachine. Once it has, we start a death counter,
  which gives the CPU five seconds to send the Ring of Light boot animation, which it usually does if the boot succeeds.
  If it doesn't in time, we reboot.
- In a first for hacked SMCs, the Ring of Light actually indicates boot progress. When we receive GetPowerUpCause,
  we set the LEDs so it displays a Red/Orange/Green pattern.
- We hook the IPC function responsible for handling the power LED state. Once the CPU enables the animation, we
  assume the boot has succeeded and disable our watchdog.
- If the CPU raises a RRoD error, we cancel the watchdog, allowing the unfortunate user to get their error code instead
  of having the system constantly reboot on them.

## Building

`python3 make_smcs.py` to make patched SMC. Mac users, please make sure `bin/c51asm_darwin` has execute permissions.

`make_smcs.py` produces these binaries:

- `badjasper.bin`: Hard resets on LED timeout only, will soft reset on a normal SMC timeout.
- `badjasper_hardreset_on_normal_timeout.bin`: Hard resets on both a normal SMC timeout and on LED timeout.

**Important note for developers!** The SMC binary is built in unscrambled form, a quirk that is inherited from
15432's original RGH3 builder. When the SMC loads data, it discards the first four bytes and instead uses four
bytes at 0x2FF8 as the real first four. If you feed the unscrambled binary into J-Runner or other tools as-is,
you will be greeted with a dead console.

To convert the SMC to a scrambled SMC, you can either extract it from the ECCs, or, more easily, run:

`python3 scramble_smc.py unscrambled_smc_in.bin scrambled_smc_out.bin`

And finally, to build XeLL ECCs:

`python3 build_glitch3_xell.py`

**FAR MORE IMPORTANT NOTE:** Big Block Jaspers are not supported yet. There's a bug in the ECC calculation code
that I'm too lazy to fix.

## Boot times

They will suck.

The most uncooperative Jaspers will take a long ass time to boot with RGH1.2. Even with speedup hacks, I've found
they can take more than 30 seconds in some cases. In a best case scenario you can expect maybe 10-20 seconds or
instaboots. The turbo reset code, if and when it's done, will help speed things up, but it will only be for RGH1.3
because it's faster and more dependable there than on RGH1.2.

**If your console is boot looping and you have hard reset enabled, hold the power button and it will power down.**

## Known improvements

- We don't really need to power cycle the system for issue 2; a soft reset would suffice. But the hard reset 
  code is far easier to use than triggering a normal soft reset.

- The MS kernel will usually hang if a HDMI cable or A/V adapter isn't plugged in, which will trigger the LED
  watchdog. However it's safe to assume most people will have their systems plugged into a display device in normal
  operation, and as a bonus, it allows us to simulate the failure condition in testing.

## People who did more than I did

- 15432's RGH3 sourcecode and builder were extremely inspirational for all this stupid work I've been doing and I've
  modified it to suit my ends
- Octal450 is a hardass but he at least provided SMC+ and valuable advice and feedback for this project

Onward to turbo reset!

## License

Public domain
