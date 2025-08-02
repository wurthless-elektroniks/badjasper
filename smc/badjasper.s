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

LED_LIGHTSHOW_SM_TIMEOUT_TICKS equ 150 ; 150 * 20 * 2 = 6000 ms

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

on_reset_watchdog_done:
    ; stop that watchdog
    clr g_sysreset_watchdog_should_run

    ; and start executing ours
    mov r0,#g_ledlightshow_watchdog_state
    mov @r0,#1

led_lightshow_sm_reload_counter_and_exit:
    mov r0,#g_ledlightshow_watchdog_death_counter
    mov @r0,#LED_LIGHTSHOW_SM_TIMEOUT_TICKS
led_lightshow_sm_do_nothing:
    ret

;
; LED lightshow watchdog down here
;
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
    cjne a,#2,led_lightshow_sm_do_nothing

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

    ; reset on timeout
ifdef SOFT_RESET_ON_LED_WATCHDOG_TIMEOUT
    setb 022h.4
    setb g_sysreset_watchdog_should_run

    sjmp _led_lightshow_sm_go_idle
else
    ljmp hard_reset
endif

    ; IPC hook lands here
ipc_led_anim_has_arrived:
    ; this setb was overwritten by our ljmp earlier so restore it
    setb 028h.7

    ; REALLY make sure the CPU requested that we play the animation
    ; (carry should still be set coming into this function)
    jnc led_lightshow_sm_do_nothing

    ; it did - shut down lightshow statemachine
_led_lightshow_sm_go_idle:
    mov r0,#g_ledlightshow_watchdog_state
    mov @r0,#0
    ret

hard_reset_end:
    .end
