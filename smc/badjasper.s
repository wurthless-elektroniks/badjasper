;
; Bad Jasper "fix" (more of a workaround).
; If the boot attempt fails, hard reset (NOT soft reset) and try again.
;
; For 8051 noobs:
; - You need to use r0 for writing/reading some memory cells
;   or you'll end up accessing special registers instead.
;   And that breaks things.
; - Stack operations are weird. Pushes increase stack pointer,
;   pops decrease stack pointer. Keep your variables away from the stack pointer.
;

; turn this on to increase SMC timeout (might be necessary in some cases)
INCREASE_RESET_WATCHDOG_TIMEOUT equ 1

; ------------------------------------------------------------------------
;
; Consts / defs
;
; ------------------------------------------------------------------------

g_powerswitch_pushed                    equ 021h.0
g_powerup_sm_should_run                 equ 021h.5
g_sysreset_watchdog_should_run          equ 021h.6

g_powerdown_sm_should_run               equ 022h.0

g_has_getpowerupcause_arrived           equ 022h.3

g_force_shutdown                        equ 023h.3

g_power_up_cause                        equ 061h

g_shared_timer_cell                     equ 03Dh

; these variables will be automatically zeroed out on reset
g_ledlightshow_watchdog_state           equ 096h
g_ledlightshow_watchdog_death_counter   equ 097h

; these variables will persist past a reboot
; see init_memclear_patch_start
g_hardreset_sm_init                     equ 098h
g_hardreset_sm_state                    equ 099h
g_power_up_cause_backup                 equ 09Ah

g_rol_ledstate                          equ 0AFh
g_rol_flags                             equ 062h
g_rol_update_pending                    equ 029h.0
g_rol_run_bootanim                      equ 028h.7

LED_LIGHTSHOW_SM_TIMEOUT_TICKS equ 125 ; 125 * 20 * 2 = 5000 ms, adjust as necessary

LEDPATTERN_RED_ORANGE_GREEN equ 0b01100011

; ------------------------------------------------------------------------
;
; Patchlist
;
; ------------------------------------------------------------------------
    .org 0x0000
    mov dptr,#mainloop_reorg_start
    mov dptr,#mainloop_reorg_end

    mov dptr,#init_memclear_patch_start
    mov dptr,#init_memclear_patch_end

    mov dptr,#ipc_setled_reroute_start
    mov dptr,#ipc_setled_reroute_end

    mov dptr,#ipc_displayerror_reroute_start
    mov dptr,#ipc_displayerror_reroute_end

    mov dptr,#reset_watchdog_success_case_start
    mov dptr,#reset_watchdog_success_case_end
ifdef HARD_RESET_ON_NORMAL_TIMEOUT
    mov dptr,#reset_watchdog_fail_case_start
    mov dptr,#reset_watchdog_fail_case_end
endif

ifdef INCREASE_RESET_WATCHDOG_TIMEOUT
    mov dptr,#reset_watchdog_reload_1_patch_start
    mov dptr,#reset_watchdog_reload_1_patch_end
    mov dptr,#reset_watchdog_reload_2_patch_start
    mov dptr,#reset_watchdog_reload_2_patch_end
endif

    mov dptr,#hard_reset_start
    mov dptr,#hard_reset_end

    .byte 0 ; zero terminates the patchlist

; ------------------------------------------------------------------------

    ; mainloop re-org
    .org 0x07C2
mainloop_reorg_start:
    ; we drop this reorg in where the debug led statemachine was
    ; (it's NOP'd out on hacked SMCs)
    lcall 0x1DE9                        ; power event monitor (checks for button presses and acts on them)
    lcall 0x119B                        ; no idea what this does
    lcall 0x1072                        ; powerup statemachine
    lcall 0x12D5                        ; reset watchdog (reboots if GetPowerUpCause isn't received in time)
    lcall 0x1127                        ; reset statemachine (performs actual hardware reset sequence)
    lcall 0x0EA9                        ; powerdown statemachine
    lcall badjasper_statemachines_exec  ; our custom code below

    ; should end at 0x07D7 - if it doesn't, we've broken the build
mainloop_reorg_end:

    ; make room for our state machine variables
    ; so they are in a safe space and don't get killed on reboot
    .org 0x7EC
init_memclear_patch_start:
    mov r2,#0x1A ; stop memory clear at 0x97, so 0x98, 0x99, 0x9A don't get overwritten on reboot
init_memclear_patch_end:


    ; reroute any power LED changes (via IPC) to custom code below
    .org 0xC77
ipc_setled_reroute_start:
    ljmp ipc_led_anim_has_arrived
ipc_setled_reroute_end:

    ; if CPU sends an error code to the SMC, then we need
    ; to cancel the LED lightshow watchdog to prevent reboots
    .org 0xCF5
ipc_displayerror_reroute_start:
    ljmp ipc_displayerror_has_arrived
ipc_displayerror_reroute_end:


ifdef INCREASE_RESET_WATCHDOG_TIMEOUT
    ; patches to set reset watchdog timeout (if necessary)
    ; 0x64 for both = 4 seconds
    ; 0x50 for both = 3.2 seconds (SMC+ default)

    .org 0x1279
reset_watchdog_reload_1_patch_start:
    mov 0x3D,#0x64
reset_watchdog_reload_1_patch_end:
    
    .org 0x1290
reset_watchdog_reload_2_patch_start:
    mov 0x3D,#0x64
reset_watchdog_reload_2_patch_end:

endif

    ; reset watchdog patch: GetPowerUpCause arrived
    ; so jump to custom code to start the LED lightshow watchdog
    ; (I had problems monitoring g_has_getpowerupcause_arrived)
    .org 0x12AD
reset_watchdog_success_case_start:
    ljmp on_reset_watchdog_done
reset_watchdog_success_case_end:



    ; reset watchdog patch: jump to hard reset function on timeout
    ; (togglable)
ifdef HARD_RESET_ON_NORMAL_TIMEOUT
    .org 0x12B7
reset_watchdog_fail_case_start:
    ljmp hard_reset
reset_watchdog_fail_case_end:

endif

    ; the bulk of our code lives in here
    .org 0x2E20
hard_reset_start:

hard_reset:
    ; if power button is held, power off immediately so the user can actually power the console down.
    ; if we don't do this, the console will likely bootloop until power is disconnected.
    lcall 0x25f0 ; power button read routine
    jc _hard_reset_power_off

    ; stash powerup cause because it will get trashed on reboot
    mov r0,#g_power_up_cause
    mov a,@r0
    mov r0,#g_power_up_cause_backup
    mov @r0,a

    ; activate statemachine below
    mov r0,#g_hardreset_sm_state   ; init first state
    mov @r0,#0x43

    ; and force a hard reset
    ; (this should NOT clear our work var space!!)
_hard_reset_power_off:
    jmp 0x0000

_hardreset_do_nothing:
    ret

badjasper_statemachines_exec:
    lcall hardreset_sm_exec
    lcall led_lightshow_sm_exec
    ret

    ; one-time init stuff
hardreset_init_vars:
    mov r0,#g_power_up_cause_backup     ; power button by default
    mov @r0,0x11
    mov r0,#g_hardreset_sm_state        ; statemachine off by default
    mov @r0,#0
    mov r0,#g_hardreset_sm_init         ; SM now initialized
    mov @r0,#69
    ret

hardreset_sm_exec:
    ; init work vars if not initialized already
    mov r0,#g_hardreset_sm_init
    mov a,@r0
    cjne a,#69,hardreset_init_vars

    ; actual state machine execution here
    mov r0,#g_hardreset_sm_state
    mov a,@r0

    cjne a,#0x43,_hardreset_sm_check_case_54

    ; first state is just to load the next state
    ; this delays the power-on by 20 or so ms, giving things time to cool down a bit
    mov r0,#g_hardreset_sm_state
    mov @r0,#0x54
    ret

_hardreset_sm_check_case_54:
    cjne a,#0x54,_hardreset_sm_check_case_63

    ; push power button and go to next state
    setb g_powerswitch_pushed
    mov r0,#g_hardreset_sm_state
    mov @r0,#0x63

    ret

_hardreset_sm_check_case_63:
    cjne a,#0x63,_hardreset_do_nothing

    ; wait for power up sequence to finish,
    ; then restore powerup cause
    jb g_powerup_sm_should_run,_hardreset_do_nothing

    mov r0,#g_power_up_cause_backup ; read stashed powerup cause
    mov a,@r0
    mov r0,#g_power_up_cause        ; write it back to restore it
    mov @r0,a
    mov r0,#g_hardreset_sm_state    ; turn off hard reset statemachine
    mov @r0,#0
    ret



;
; LED lightshow watchdog down here
;

on_reset_watchdog_done:
    ; stop that watchdog
    clr g_sysreset_watchdog_should_run

    ; set LEDs to indicate GetPowerUpCause arrival
    mov a,#LEDPATTERN_RED_ORANGE_GREEN
    lcall rol_set_leds

    ; start the IPC watchdog
    mov r0,#g_ledlightshow_watchdog_state
    mov @r0,#1

led_lightshow_sm_reload_counter_and_exit:
    mov r0,#g_ledlightshow_watchdog_death_counter
    mov @r0,#LED_LIGHTSHOW_SM_TIMEOUT_TICKS
led_lightshow_sm_do_nothing:
    ret

led_lightshow_sm_exec:
    mov r0,#g_ledlightshow_watchdog_state
    mov a,@r0
    cjne a,#1,_led_lightshow_sm_do_state_2

    ; short-circuit if powerdown statemachine starts
    ; so that we don't power up again by mistake
    jb g_powerdown_sm_should_run,_led_lightshow_sm_go_idle

    ; tick death counter down
    ; djnz can't be used here because our vars are in high memory
    mov r0,#g_ledlightshow_watchdog_death_counter
    mov a,@r0
    dec a
    mov @r0,a
    cjne a,#0,led_lightshow_sm_do_nothing

    ; timed out - reload counter and go to state 2
    mov r0,#g_ledlightshow_watchdog_state
    mov @r0,#2
    sjmp led_lightshow_sm_reload_counter_and_exit

_led_lightshow_sm_do_state_2:
    cjne a,#2,_led_lightshow_sm_do_state_3

    ; short-circuit if powerdown statemachine starts
    ; so that we don't power up again by mistake
    jb g_powerdown_sm_should_run,_led_lightshow_sm_go_idle

    ; tick death counter down
    ; djnz can't be used here because our vars are in high memory
    mov r0,#g_ledlightshow_watchdog_death_counter
    mov a,@r0
    dec a
    mov @r0,a
    cjne a,#0,led_lightshow_sm_do_nothing

    ; failure case ends up here
    ; first clear LED states
    mov a,#0
    lcall rol_set_leds

    ; then reboot
    ljmp hard_reset

_led_lightshow_sm_do_state_3:
    cjne a,#3,led_lightshow_sm_do_nothing

    ; manually run ring of light bootanim (if necessary)
    setb g_rol_run_bootanim

    mov a,g_rol_flags
    anl a,#0b11011111
    orl a,#0b00010000  ; bootanim sets bit 4
    mov g_rol_flags,a

    sjmp _led_lightshow_sm_go_idle

    ; IPC hook lands here
ipc_led_anim_has_arrived:
    ; this setb was overwritten by our ljmp earlier so restore it
    setb g_rol_run_bootanim

    ; REALLY make sure the CPU requested that we play the animation
    ; (carry should still be set coming into this function)
    jnc led_lightshow_sm_do_nothing

    ; clear our LED state
    mov a,#0
    lcall rol_set_leds

    ; note that this RoL operation also cancels the bootanim
    ; so we need to run the bootanim manually after this
    mov r0,#g_ledlightshow_watchdog_state
    mov @r0,#3
    ret

_led_lightshow_sm_go_idle:
    mov r0,#g_ledlightshow_watchdog_state
    mov @r0,#0
    ret

    ; other IPC hook lands here
ipc_displayerror_has_arrived:
    ; these instructions were trashed by our ljmp
    mov 0x5A,r2
    mov 0x5C,r3

    ; shut statemachine off
    mov r0,#g_ledlightshow_watchdog_state
    mov @r0,#0

    ; and continue with error case
    ljmp 0x0CF9


;
; Common function to set Ring of Light LEDs
; a - LED states (upper 4 bits green, lower 4 bits red)
;
rol_set_leds:
    mov r0,#g_rol_ledstate
    mov @r0,a

    ; bits 5/7 must be set for argon sm to display things
    ; bit 5 is apparently some "high priority" bit and when it is set
    ; nothing else will display on the ring
    mov a,g_rol_flags
    orl a,#0b10100000 
    mov g_rol_flags,a
    
    ; and this bit has to be set too
    setb g_rol_update_pending

    ret



hard_reset_end:
    .end
