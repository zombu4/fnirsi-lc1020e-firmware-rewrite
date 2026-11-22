@ ctl.inc - private constants of the control core (own/ctl.s, own/cmd.s and own/dset.s),
@ included after own/own.inc by those three files and by own/power.s (which reads words of the
@ control core, never writes them). Part of the FNIRSI LC1020E firmware rewrite (assembly).
@
@ Only .equ lines and one .if check: nothing here emits code, data or a section.
@ The RAM of the control core is the area O_CTL of own.inc (0x2EC0 bytes from OWN_CTL); the
@ offsets below are relative to OWN_CTL and end at CT_END (checked by the .if at the end).

@ ============================================================================
@ RAM of the control core (offsets from OWN_CTL; own_start clears the whole own RAM)
@ ============================================================================
@ 0x000 own_injected (own.inc CTO_INJECTED), read by save.s
        .equ    CT_FLAGS,       0x004           @ CF_* bits
        .equ    CT_RX_STATE,    0x008           @ frame parser state RX_*
        .equ    CT_RX_POS,      0x00C           @ bytes stored in CT_RXB so far
        .equ    CT_RX_END,      0x010           @ CT_RXB index after the CRC (length + 4)
        .equ    CT_ANS_LEN,     0x014           @ bytes of the pending answer payload (status
                                                @ byte included), 0 = nothing pending
        .equ    CT_REQ_SEQ,     0x018           @ seq of the request being answered
        .equ    CT_REQ_CMD,     0x01C           @ cmd of the request being answered
        .equ    CT_TX_SEQ,      0x020           @ running seq of stream and event frames
        .equ    CT_DROPPED,     0x024           @ stream / event frames dropped (no room)
        .equ    CT_ST_PERIOD,   0x028           @ STREAM period in ms, 0 = off
        .equ    CT_ST_NEXT,     0x02C           @ tick of the next STATE stream frame
        .equ    CT_MS_MODE,     0x030           @ MEASURE_STREAM: 0 off, 1 every result, 2 period
        .equ    CT_MS_PERIOD,   0x034           @ MEASURE_STREAM period in ms (mode 2)
        .equ    CT_MS_NEXT,     0x038           @ tick of the next MEASURE stream frame
        .equ    CT_MEAS_SEQ,    0x03C           @ number of new measurement results seen
        .equ    CT_MEAS_FLAG,   0x040           @ word 0x20001200 as read in the previous pass
        .equ    CT_MEAS_Z,      0x044           @ word 0x200050C4 (|Z|) of the previous pass
        .equ    CT_MEAS_TH,     0x048           @ word 0x200050CC (theta) of the previous pass
        .equ    CT_PREV_SCREEN, 0x04C           @ screen word 0x20001168 of the previous pass
        .equ    CT_PREV_SAVES,  0x050           @ own_save_count of the previous pass
        .equ    CT_PREV_CALST,  0x054           @ word 0x200050EC of the previous pass
        .equ    CT_PREV_CALSTP, 0x058           @ word 0x200050E8 of the previous pass
        .equ    CT_PREV_RAM,    0x05C           @ 4 words: 0x200011A4, 0x200011A8, byte
                                                @ 0x200011E4, 0x200011E8 of the previous pass
        .equ    CT_ACT,         0x06C           @ action after the answer: ACT_*
        .equ    CT_ACT_T0,      0x070           @ tick when the action was set
        .equ    CT_ANS_T,       0x074           @ tick when the last answer left
        .equ    CT_OFF_T,       0x078           @ tick when the meter's power-off path ran
        .equ    CT_HAND_SLOT,   0x07C           @ running slot from the hand-over word (0 F,
                                                @ 1 A, 2 B, 0xFF unknown)
        .equ    CT_HAND_WORD,   0x080           @ the hand-over word as found at the start
        .equ    CT_RESULT,      0x084           @ result of the last update (RES_*)
        .equ    CT_SAVES_SEEN,  0x088           @ own_save_count before 0x08009400 ran
@ key injection
        .equ    CT_I_STATE,     0x090           @ IS_*
        .equ    CT_I_MASK,      0x094           @ key mask being injected
        .equ    CT_I_HOLD,      0x098           @ hold time in ms (0 = short press)
        .equ    CT_I_T0,        0x09C           @ tick at the start of the injection
        .equ    CT_I_GOFF,      0x0A0           @ 1: guard stays off for this injection
        .equ    CT_I_RESULT,    0x0A4           @ 0 done, 1 ended by a physical key / slot taken
        .equ    CT_I_POSTED,    0x0A8           @ event code posted and not yet consumed, 0 none
        .equ    CT_I_FECNT,     0x0AC           @ 0xFE events of this hold consumed so far
@ job (command state machine)
        .equ    CT_J_ACTIVE,    0x0B0           @ 1 while a job runs
        .equ    CT_J_CMD,       0x0B4           @ command of the job
        .equ    CT_J_T0,        0x0B8           @ tick at the start of the job
        .equ    CT_J_LIMIT,     0x0BC           @ time limit in ms
        .equ    CT_J_PC,        0x0C0           @ index of the current step
        .equ    CT_J_COUNT,     0x0C4           @ presses left in the step, 0xFFFFFFFF: step new
        .equ    CT_J_LAST,      0x0C8           @ value before the last press of the step
        .equ    CT_J_SWAP,      0x0CC           @ 1: the two keys of the step are swapped
        .equ    CT_J_PRESSED,   0x0D0           @ 1: a press of this step went out
        .equ    CT_J_STATUS,    0x0D4           @ status of the answer
        .equ    CT_J_ANSWER,    0x0D8           @ AN_* answer kind
        .equ    CT_J_NSTEPS,    0x0DC           @ steps in the program
        .equ    CT_J_GUARD,     0x0E0           @ 1: the guard refused an action of this job
        .equ    CT_J_STEPT,     0x0E4           @ tick at the start of the current step
@ direct change (DIRECT_SET_DESIGN.md revision 2; own/dset.s)
        .equ    CT_DS_OP,       0x0E8           @ command (C_*) of the pending change, 0 none
        .equ    CT_DS_A,        0x0EC           @ its first argument (dset.s ds_check)
@ BOOT_* writer
        .equ    CT_B_STATE,     0x0F0           @ BS_*
        .equ    CT_B_SLOT,      0x0F4           @ slot base being written (SLOT_A / SLOT_B)
        .equ    CT_B_LEN,       0x0F8           @ length of the slot file
        .equ    CT_B_CRC,       0x0FC           @ CRC-32 of the slot file
        .equ    CT_B_PAGE,      0x100           @ next page to erase (0..11)
@ SETTINGS_WRITE_BLOCK transfer
        .equ    CT_W_NEXT,      0x104           @ next expected offset, 0xFFFFFFFF: none started
        .equ    CT_W_CRC,       0x108           @ CRC-32 given with the transfer
@ event queue
        .equ    CT_EQ_HEAD,     0x10C           @ index of the oldest entry
        .equ    CT_EQ_COUNT,    0x110           @ entries in the queue
@ direct change, further arguments (dset.s ds_check)
        .equ    CT_DS_B,        0x114           @ second argument
        .equ    CT_DS_C,        0x118           @ third argument
        .equ    CT_DS_D,        0x11C           @ fourth argument
@ records of the starter (rec_scan), the cell being written
        .equ    CT_TAB,         0x120           @ 3 x {sequence, state, version, cell address}
        .equ    CT_CELL,        0x150           @ 16 bytes
@ formatter buffers (MEASURE)
        .equ    CT_FMT_TXT,     0x160           @ 16 bytes text
        .equ    CT_FMT_UNIT,    0x170           @ 8 bytes unit text
        .equ    CT_FMT_IDX,     0x178           @ word: index the formatter returns
@ step program
        .equ    CT_PROG,        0x180           @ PROG_MAX steps of 16 bytes
        .equ    PROG_MAX,       56
        .equ    CT_REC,         0x500           @ 0x80 bytes: stream record
        .equ    CT_EVQ,         0x580           @ EVQ_N entries of 16 bytes
        .equ    EVQ_N,          16
        .equ    CT_RXB,         0x680           @ received frame: length (2), seq .. payload,
                                                @ CRC (2): at most 519 bytes
        .equ    CT_ANSB,        0x8A0           @ answer payload: status + up to 511 bytes
        .equ    CT_PREVBLK,     0xAA0           @ previous copy of the settings block (0xC14)
        .equ    CT_END,         0xAA0 + BLK_SIZE

        .if     CT_END > CTL_SIZE
        .error  "ctl.inc: the control core RAM does not fit O_CTL"
        .endif

@ CT_FLAGS bits
        .equ    CF_PRIMED,      0x01            @ previous values taken (first pass done)
        .equ    CF_OFF,         0x02            @ powered-off mode (USB power kept the meter on)
        .equ    CF_OFF_WAIT,    0x04            @ the meter's power-off path ran, CT_OFF_T set
        .equ    CF_ANS_LEFT,    0x08            @ an answer left since the action was set
        .equ    CF_MS_DUE,      0x10            @ a new result: MEASURE stream frame due (mode 1)

@ frame parser states
        .equ    RX_SYNC,        0
        .equ    RX_LEN0,        1
        .equ    RX_LEN1,        2
        .equ    RX_BODY,        3               @ seq .. payload, then the two CRC bytes
        .equ    RX_BUDGET,      600             @ bytes read per main-loop pass at most

@ actions after the answer (CT_ACT)
        .equ    ACT_NONE,       0
        .equ    ACT_RESET,      1               @ soft_restart, request word "RSTR"
        .equ    ACT_UPDATE,     2               @ soft_restart, request word "UPDT"
        .equ    ACT_POWER_OFF,  3               @ event 0xFE with mask 1, guard off
        .equ    ACT_WAIT_MS,    200             @ at most this long after the answer left
        .equ    ACT_LIMIT_MS,   1000            @ at most this long after the action was set
        .equ    OFF_WAIT_MS,    1000            @ power-off path ran, meter still on: off mode

@ key injection states (CT_I_STATE)
        .equ    IS_IDLE,        0
        .equ    IS_SHORT,       1               @ code 1 to post
        .equ    IS_HOLD,        2               @ hold: before the 100th tick
        .equ    IS_HOLD_FE,     3               @ hold: one 0xFE per pass
        .equ    IS_RELEASE,     4               @ 0xFF to post
        .equ    IS_WAIT,        5               @ posted: wait for 0x08009400 to consume it
        .equ    IS_POWER,       6               @ 0xFE with mask 1 to post (POWER_OFF)
        .equ    HOLD_FE_MS,     1000            @ 100 SysTick ticks of 10 ms (0x080094A0:
                                                @ 0xFE from a counter above 99)
        .equ    LONG_MS,        1100            @ hold time of a long press of a job
        .equ    KEY_CODE_SHORT, 1
        .equ    KEY_CODE_HELD,  0xFE
        .equ    KEY_CODE_REL,   0xFF

@ job programs: step = op word (op, kind, max, 0), keys (a | b << 16), arg, target
        .equ    PS_OP,          0
        .equ    PS_KIND,        1
        .equ    PS_MAX,         2
        .equ    PS_KEYS,        4
        .equ    PS_ARG,         8               @ OP_PRESS / OP_CHECK: address of the word read
        .equ    PS_TARGET,      12
        .equ    OP_END,         0               @ answer and finish
        .equ    OP_SCREEN,      1               @ go to screen target
        .equ    OP_PRESS,       2               @ press until the word at arg is target
        .equ    OP_KEY,         3               @ one press of key a (arg = hold ms or 0)
        .equ    OP_CHECK,       4               @ word at arg = target, else status key a
        .equ    OP_NODIALOG,    5               @ long key 8 until word 0x200011AC = 0
        .equ    OP_WAITCAL,     6               @ wait for the calibration's end
        .equ    OP_ERASE,       7               @ BOOT_BEGIN: one slot page per pass
        .equ    OP_DIRECT,      8               @ wait for the direct change (dset.s ds_run)
        .equ    KB_LONG,        0x01            @ kind: long press (hold LONG_MS)
        .equ    KB_GOFF,        0x80            @ kind: guard off, no refusal (the command's
                                                @ own path, USB_CONTROL_DESIGN.md 4.3 / 4.4)
@ answer kinds (CT_J_ANSWER)
        .equ    AN_STATE,       0               @ STATE record
        .equ    AN_MEASURE,     1               @ MEASURE record
        .equ    AN_COMPARE,     2               @ COMPARE record
        .equ    AN_CAL,         3               @ calibration status, type, save status
        .equ    AN_SAVE,        4               @ save status and flags, then STATE
        .equ    AN_NONE,        5               @ status only
        .equ    JOB_LIMIT_MS,   20000           @ time limit of a key job
        .equ    CAL_LIMIT_MS,   120000          @ time limit of CALIBRATE
        .equ    ERASE_LIMIT_MS, 10000           @ time limit of BOOT_BEGIN
        .equ    DS_LIMIT_MS,    2000            @ time limit of a direct change (a key held)
@ results of ds_check (dset.s); the refusals are the status codes S_* (2..6)
        .equ    DS_GO,          0               @ a change to make
        .equ    DS_SAME,        1               @ the value is already set: nothing to change

@ BOOT_* writer states (CT_B_STATE)
        .equ    BS_NONE,        0
        .equ    BS_ERASING,     1
        .equ    BS_ERASED,      2               @ every page read 0xFF; BOOT_DATA accepted
        .equ    BS_CHECKED,     3               @ BOOT_END passed; BOOT_INSTALL accepted
        .equ    SLOT_PAGES,     SLOT_SIZE / FLASH_PAGE      @ 12
        .equ    SLOT_FILE_MIN,  0x208           @ header page part + vector words
        .equ    SRAM_LO,        0x20000000      @ the starter's initial-SP limits
        .equ    SRAM_HI,        0x20024000

@ commands and texts
        .equ    CONFIRM_OK,     0x4F4B          @ "OK": confirmation of every confirming command
                                                @ except POWER_OFF (USB_CONTROL_DESIGN.md 9)
        .equ    ST_DEFER,       0xFF            @ handler result: the answer comes from the job
                                                @ (or was made pending by job_answer already)
        .equ    CAPS_ALL,       0x002FFFFF      @ capability bits 0..19 (4.8; bit 20, SETUP_LANGUAGE,
                                                @ clear: English only) and bit 21: SCREEN, LCR_SET,
                                                @ HOLD, SETTINGS_SET, COMPARE_SET set directly
                                                @ (DIRECT_SET_DESIGN.md revision 2)
        .equ    ID_CAL_TABLES,  0xFFFE          @ SETTING_CHANGED id: words changed in the
                                                @ calibration tables (value = their number)
        .equ    V_SCALE,        0x2000119C      @ sorting nominal unit / scale index 0..3
                                                @ (fn_0800e224, fn_0800e4f8)
        .equ    V_SEL,          0x200011B4      @ sorting dialog row / restore choice
        .equ    V_DIGIT,        0x200011B8      @ sorting editor digit index
        .equ    V_EDIT,         0x2000000C      @ byte: editing mode of the dialog
        .equ    V_SIGN_MODE,    0x20001198      @ ohm formatter sign mode (2 = keep the sign)
        .equ    V_SERPAR,       0x200011EC      @ 0 series, 1 parallel values in use
        .equ    V_MEAS_NEW,     0x20001200      @ new averaged result for 0x0800A068
        .equ    V_TICK,         0x20000480      @ GUI tick, +10 per SysTick (fn_080277a0)
        .equ    V_ROOT_MEAS,    0x200001D8      @ root object of the measure screens
        .equ    V_ROOT_SET,     0x20000014      @ root object of the settings screen
        .equ    V_OBJS,         0x200001D4      @ object words of the measure screens (fn_0800ca2c):
        .equ    OB_HOLD,        0x08            @   +0x08 the HOLD object 0x200001DC
        .equ    OB_SPEED,       0x0C            @   +0x0C the speed icon 0x200001E0
        .equ    OB_CIRCUIT,     0x10            @   +0x10 the circuit icon 0x200001E4
        .equ    OB_SECOND,      0x14            @   +0x14 the secondary picture 0x200001E8
        .equ    OB_FUNC_TXT,    0x1C            @   +0x1C the Func text 0x200001F0
        .equ    OB_FUNC_PIC,    0x28            @   +0x28 the Func picture 0x200001FC
        .equ    V_MEAS_RESTART, 0x200011C4      @ byte: restart request of the DMA interrupt
                                                @ (fn_080085d0; app_01.s 619 after hold off)
        .equ    V_EVENT_511C,   0x2000511C      @ stored 0 by 0x08009400 for every event (app_01.s
                                                @ 89); no reader in src/ or own/
        .equ    T_FUNC,         0x20000258      @ Func names: 6 pointers per language
        .equ    T_RANGE,        0x20000244      @ range names: one pointer per range
        .equ    T_CURSOR,       0x20000224      @ cursor labels: 4 pointers per language
        .equ    T_MENU,         0x20000054      @ menu labels: 9 pointers per language
        .equ    T_OFFTIME,      0x20000174      @ off time texts: 4 pointers per language
        .equ    T_WARNTYPE,     0x20000144      @ warn type texts: 2 pointers per language
        .equ    T_SORTROW,      0x2000011C      @ sorting dialog rows: 5 pointers per language
        .equ    TXT_MAX,        40              @ longest text copied from a table
