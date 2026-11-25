@ rodata_04.s - read-only data 0x0805113c..0x08051757: display strings (ASCII and UTF-8), region table, packed RAM image
@ Part of the FNIRSI LC1020E firmware rewrite: port of the application V1.1 (Thumb-2 assembly).
	.syntax unified
	.arch armv7e-m
	.fpu fpv4-sp-d16
	.thumb

@ This part holds three kinds of data:
@  1. NUL-terminated strings, each padded with zero bytes to a 4-byte boundary.
@     The string addresses are held in the initial RAM image (pointer tables in
@     RAM), so the code reads the strings through RAM pointers. Each string the
@     typed image of our build names carries a label with its V1.1 address.
@  2. The scatter-load region table at 0x08051510 (two entries: the entry for the
@     initial RAM image and a zero-fill entry).
@  3. The initial RAM image: in V1.1 packed (551 bytes) for the decompressor, which
@     unpacks it to 0x20000000 (0x57C bytes); in our build (make own) typed out
@     (0x57C bytes, copied word by word by copy_init, own/init.s), so that its flash
@     pointers are labels the linker sets.
@ The addresses in labels and comments are those of V1.1; in our build the part sits
@ lower (link_own.ld), the region table stays word aligned and the image follows it.

	.section .rodata.fixed.0805113c,"a",%progbits

@ ---- ASCII unit and label strings ----
	.global d_0805113c
d_0805113c:
	.ascii "H\0"			@ "H" (0x0805113c)
	.short 0x0000			@ padding
	.global d_08051140
d_08051140:
	.ascii "100K\0"			@ "100K" (0x08051140)
	.byte 0x00, 0x00, 0x00		@ padding
	.global d_08051148
d_08051148:
	.ascii "10K\0"			@ "10K" (0x08051148)
	.global d_0805114c
d_0805114c:
	.ascii "1K\0"			@ "1K" (0x0805114c)
	.byte 0x00			@ padding
	.global d_08051150
d_08051150:
	.ascii "OK\0"			@ "OK" (0x08051150)
	.byte 0x00			@ padding
	.global d_08051154
d_08051154:
	.ascii "10M\0"			@ "10M" (0x08051154)
	.global d_08051158
d_08051158:
	.ascii "1M\0"			@ "1M" (0x08051158)
	.byte 0x00			@ padding
	.global d_0805115c
d_0805115c:
	.ascii "ON\0"			@ "ON" (0x0805115c)
	.byte 0x00			@ padding
	.global d_08051160
d_08051160:
	.ascii "NO\0"			@ "NO" (0x08051160)
	.byte 0x00			@ padding
	.global d_08051164
d_08051164:
	.ascii "100R\0"			@ "100R" (0x08051164)
	.byte 0x00, 0x00, 0x00		@ padding
	.global d_0805116c
d_0805116c:
	.ascii "10R\0"			@ "10R" (0x0805116c)
	.global d_08051170
d_08051170:
	.ascii "1R\0"			@ "1R" (0x08051170)
	.byte 0x00			@ padding
	.global d_08051174
d_08051174:
	.ascii "100mR\0"		@ "100mR" (0x08051174)
	.short 0x0000			@ padding
	.global d_0805117c
d_0805117c:
	.ascii "10mR\0"			@ "10mR" (0x0805117c)
	.byte 0x00, 0x00, 0x00		@ padding
	.global d_08051184
d_08051184:
	.ascii "YES\0"			@ "YES" (0x08051184)
	.global d_08051188
d_08051188:
	.ascii "This operation will lost all data\0"	@ message text (0x08051188, 34 bytes)
	.byte 0x00, 0x00		@ padding (the text above is 33 characters plus NUL)
	.global d_080511ac
d_080511ac:
	.ascii "Language\0"		@ "Language" (0x080511ac)
	.byte 0x00, 0x00, 0x00		@ padding
	.global d_080511b8
d_080511b8:
	.ascii "Off Time\0"		@ "Off Time" (0x080511b8)
	.byte 0x00, 0x00, 0x00		@ padding
	.global d_080511c4
d_080511c4:
	.ascii "Volume\0"		@ "Volume" (0x080511c4)
	.byte 0x00			@ padding
	.global d_080511cc
d_080511cc:
	.ascii "Restore\0"		@ "Restore" (0x080511cc)
	.global d_080511d4
d_080511d4:
	.ascii "Sorting\0"		@ "Sorting" (0x080511d4)
	.global d_080511dc
d_080511dc:
	.ascii "English\0"		@ "English" (0x080511dc)
	.global d_080511e4
d_080511e4:
	.ascii "Finish\0"		@ "Finish" (0x080511e4)
	.byte 0x00			@ padding
	.global d_080511ec
d_080511ec:
	.ascii "Cali\0"			@ "Cali" (0x080511ec)
	.byte 0x00, 0x00, 0x00		@ padding
	.global d_080511f4
d_080511f4:
	.ascii "Fail\0"			@ "Fail" (0x080511f4)
	.byte 0x00, 0x00, 0x00		@ padding
	.global d_080511fc
d_080511fc:
	.ascii "Tol\0"			@ "Tol" (0x080511fc)
	.global d_08051200
d_08051200:
	.ascii "System\0"		@ "System" (0x08051200)
	.byte 0x00			@ padding
	.global d_08051208
d_08051208:
	.ascii "Norm\0"			@ "Norm" (0x08051208)
	.byte 0x00, 0x00, 0x00		@ padding
	.global d_08051210
d_08051210:
	.ascii "Open\0"			@ "Open" (0x08051210)
	.byte 0x00, 0x00, 0x00		@ padding
	.global d_08051218
d_08051218:
	.ascii "30min\0"		@ "30min" (0x08051218)
	.short 0x0000			@ padding
	.global d_08051220
d_08051220:
	.ascii "15min\0"		@ "15min" (0x08051220)
	.short 0x0000			@ padding
	.global d_08051228
d_08051228:
	.ascii "5min\0"			@ "5min" (0x08051228)
	.byte 0x00, 0x00, 0x00		@ padding
	.global d_08051230
d_08051230:
	.ascii "Calibration\0"		@ "Calibration" (0x08051230)
	.global d_0805123c
d_0805123c:
	.ascii "Warn\0"			@ "Warn" (0x0805123c)
	.byte 0x00, 0x00, 0x00		@ padding
	.global d_08051244
d_08051244:
	.ascii "Brightness\0"		@ "Brightness" (0x08051244)
	.byte 0x00			@ padding
	.global d_08051250
d_08051250:
	.ascii "Start\0"		@ "Start" (0x08051250)
	.short 0x0000			@ padding
	.global d_08051258
d_08051258:
	.ascii "Short\0"		@ "Short" (0x08051258)
	.short 0x0000			@ padding
	.global d_08051260
d_08051260:
	.ascii "Busy\0"			@ "Busy" (0x08051260)
	.byte 0x00, 0x00, 0x00		@ padding

@ ---- UTF-8 strings (Chinese display texts) ----
@ Our build: the Chinese runs 0x08051268..0x080512d7 (112 bytes), 0x080512e8..0x08051413 (300),
@ 0x0805144c..0x080514bb (112), 0x080514dc..0x080514eb (16) and 0x08051500..0x0805150f (16)
@ are freed; each size is a multiple of 4, so nothing of them is left. They are named only by
@ row 0 of the RAM text tables, which the typed image below sets equal to row 1.
.ifndef OWN
	.byte 0xe5, 0xbc, 0x80, 0x00	@ UTF-8 "kai" (open/on) (0x08051268)
	.byte 0xe6, 0xa0, 0xa1, 0xe5, 0x87, 0x86, 0x00	@ UTF-8 "jiao zhun" (calibration) (0x0805126c)
	.byte 0x00			@ padding
	.byte 0xe4, 0xb8, 0xad, 0xe6, 0x96, 0x87, 0x00	@ UTF-8 "zhong wen" (Chinese) (0x08051274)
	.byte 0x00			@ padding
	.byte 0xe6, 0x8a, 0xa5, 0xe8, 0xad, 0xa6, 0xe7, 0xb1, 0xbb, 0xe5, 0x9e, 0x8b, 0x00	@ UTF-8 "bao jing lei xing" (alarm type) (0x0805127c)
	.byte 0x00, 0x00, 0x00		@ padding
	.byte 0xe5, 0xbc, 0x80, 0xe5, 0xa7, 0x8b, 0x00	@ UTF-8 "kai shi" (start) (0x0805128c)
	.byte 0x00			@ padding
	.byte 0xe5, 0xae, 0x8c, 0xe6, 0x88, 0x90, 0x00	@ UTF-8 "wan cheng" (finish) (0x08051294)
	.byte 0x00			@ padding
	.byte 0x33, 0x30, 0xe5, 0x88, 0x86, 0xe9, 0x92, 0x9f, 0x00	@ "30" + UTF-8 "fen zhong" (minutes) (0x0805129c)
	.byte 0x00, 0x00, 0x00		@ padding
	.byte 0x31, 0x35, 0xe5, 0x88, 0x86, 0xe9, 0x92, 0x9f, 0x00	@ "15" + UTF-8 "fen zhong" (minutes) (0x080512a8)
	.byte 0x00, 0x00, 0x00		@ padding
	.byte 0x35, 0xe5, 0x88, 0x86, 0xe9, 0x92, 0x9f, 0x00	@ "5" + UTF-8 "fen zhong" (minutes) (0x080512b4)
	.byte 0xe5, 0xa4, 0xb1, 0xe8, 0xb4, 0xa5, 0x00	@ UTF-8 "shi bai" (fail) (0x080512bc)
	.byte 0x00			@ padding
	.byte 0xe5, 0x90, 0xa6, 0x00	@ UTF-8 "fou" (no) (0x080512c4)
	.byte 0xe5, 0xb1, 0x8f, 0xe5, 0xb9, 0x95, 0xe4, 0xba, 0xae, 0xe5, 0xba, 0xa6, 0x00	@ UTF-8 "ping mu liang du" (screen brightness) (0x080512c8)
	.byte 0x00, 0x00, 0x00		@ padding
.endif
	.global d_080512d8
d_080512d8:
	.byte 0x4b, 0xce, 0xa9, 0x00	@ "K" + UTF-8 omega sign (0x080512d8)
	.global d_080512dc
d_080512dc:
	.byte 0x4d, 0xce, 0xa9, 0x00	@ "M" + UTF-8 omega sign (0x080512dc)
	.global d_080512e0
d_080512e0:
	.byte 0x6d, 0xce, 0xa9, 0x00	@ "m" + UTF-8 omega sign (0x080512e0)
	.global d_080512e4
d_080512e4:
	.byte 0xce, 0xa9, 0x00		@ UTF-8 omega sign (0x080512e4)
	.byte 0x00			@ padding
.ifndef OWN
	.byte 0xe6, 0xa0, 0xa1, 0xe5, 0x87, 0x86, 0xe4, 0xb8, 0xad, 0x00	@ UTF-8 "jiao zhun zhong" (calibrating) (0x080512e8)
	.short 0x0000			@ padding
	.byte 0xe8, 0xaf, 0xad, 0xe8, 0xa8, 0x80, 0xe8, 0xae, 0xbe, 0xe7, 0xbd, 0xae, 0x00	@ UTF-8 "yu yan she zhi" (language setting) (0x080512f4)
	.byte 0x00, 0x00, 0x00		@ padding
	.byte 0xe6, 0x81, 0xa2, 0xe5, 0xa4, 0x8d, 0xe5, 0x87, 0xba, 0xe5, 0x8e, 0x82, 0xe8, 0xae, 0xbe, 0xe7	@ UTF-8 "hui fu chu chang she zhi" (restore factory setting) (0x08051304)
	.byte 0xbd, 0xae, 0x00		@ (end of the string above)
	.byte 0x00			@ padding
	.byte 0xe6, 0xa0, 0xa1, 0xe5, 0x87, 0x86, 0xe8, 0xae, 0xbe, 0xe7, 0xbd, 0xae, 0x00	@ UTF-8 "jiao zhun she zhi" (calibration setting) (0x08051318)
	.byte 0x00, 0x00, 0x00		@ padding
	.byte 0xe5, 0x88, 0x86, 0xe9, 0x80, 0x89, 0xe8, 0xae, 0xbe, 0xe7, 0xbd, 0xae, 0x00	@ UTF-8 "fen xuan she zhi" (sorting setting) (0x08051328)
	.byte 0x00, 0x00, 0x00		@ padding
	.byte 0xe7, 0xb3, 0xbb, 0xe7, 0xbb, 0x9f, 0xe8, 0xae, 0xbe, 0xe7, 0xbd, 0xae, 0x00	@ UTF-8 "xi tong she zhi" (system setting) (0x08051338)
	.byte 0x00, 0x00, 0x00		@ padding
	.byte 0xe5, 0xa3, 0xb0, 0xe9, 0x9f, 0xb3, 0xe8, 0xae, 0xbe, 0xe7, 0xbd, 0xae, 0x00	@ UTF-8 "sheng yin she zhi" (sound setting) (0x08051348)
	.byte 0x00, 0x00, 0x00		@ padding
	.byte 0xe7, 0xb3, 0xbb, 0xe7, 0xbb, 0x9f, 0xe4, 0xbf, 0xa1, 0xe6, 0x81, 0xaf, 0x00	@ UTF-8 "xi tong xin xi" (system information) (0x08051358)
	.byte 0x00, 0x00, 0x00		@ padding
	.byte 0xe6, 0x8c, 0x87, 0xe7, 0xa4, 0xba, 0xe7, 0x81, 0xaf, 0x00	@ UTF-8 "zhi shi deng" (indicator light) (0x08051368)
	.short 0x0000			@ padding
	.byte 0xe6, 0x98, 0xaf, 0x00	@ UTF-8 "shi" (yes) (0x08051374)
	.byte 0xe5, 0xbc, 0x80, 0xe8, 0xb7, 0xaf, 0x00	@ UTF-8 "kai lu" (open circuit) (0x08051378)
	.byte 0x00			@ padding
	.byte 0xe7, 0x9f, 0xad, 0xe8, 0xb7, 0xaf, 0x00	@ UTF-8 "duan lu" (short circuit) (0x08051380)
	.byte 0x00			@ padding
	.byte 0xe4, 0xb8, 0x8d, 0xe5, 0x85, 0xb3, 0x00	@ UTF-8 "bu guan" (do not switch off) (0x08051388)
	.byte 0x00			@ padding
	.byte 0xe5, 0x85, 0xb3, 0x00	@ UTF-8 "guan" (off) (0x08051390)
	.byte 0xe6, 0x8a, 0xa5, 0xe8, 0xad, 0xa6, 0xe5, 0xa3, 0xb0, 0xe9, 0x9f, 0xb3, 0x00	@ UTF-8 "bao jing sheng yin" (alarm sound) (0x08051394)
	.byte 0x00, 0x00, 0x00		@ padding
	.byte 0xe6, 0x81, 0xa2, 0xe5, 0xa4, 0x8d, 0xe5, 0x87, 0xba, 0xe5, 0x8e, 0x82, 0xe8, 0xae, 0xbe, 0xe7	@ UTF-8 long text: restore factory setting ... (0x080513a4, 49 bytes)
	.byte 0xbd, 0xae, 0xe4, 0xbc, 0x9a, 0xe9, 0x87, 0x8d, 0xe7, 0xbd, 0xae, 0xe4, 0xb9, 0x8b, 0xe5, 0x89	@ ... will reset the earlier ...
	.byte 0x8d, 0xe6, 0x89, 0x80, 0xe6, 0x9c, 0x89, 0xe7, 0x9a, 0x84, 0xe4, 0xbf, 0xae, 0xe6, 0x94, 0xb9	@ ... all modifications
	.byte 0x00			@ NUL of the long text
	.byte 0x00, 0x00, 0x00		@ padding
	.byte 0xe8, 0x87, 0xaa, 0xe5, 0x8a, 0xa8, 0xe5, 0x85, 0xb3, 0xe6, 0x9c, 0xba, 0x00	@ UTF-8 "zi dong guan ji" (auto power off) (0x080513d8)
	.byte 0x00, 0x00, 0x00		@ padding
	.byte 0xe5, 0xae, 0xb9, 0xe9, 0x99, 0x90, 0xe5, 0x80, 0xbc, 0x00	@ UTF-8 "rong xian zhi" (tolerance value) (0x080513e8)
	.short 0x0000			@ padding
	.byte 0xe6, 0xa0, 0x87, 0xe7, 0xa7, 0xb0, 0xe5, 0x80, 0xbc, 0x00	@ UTF-8 "biao cheng zhi" (nominal value) (0x080513f4)
	.short 0x0000			@ padding
	.byte 0xe4, 0xb8, 0x8d, 0xe5, 0x90, 0x88, 0xe6, 0xa0, 0xbc, 0x00	@ UTF-8 "bu he ge" (fail/reject) (0x08051400)
	.short 0x0000			@ padding
	.byte 0xe5, 0x90, 0x88, 0xe6, 0xa0, 0xbc, 0x00	@ UTF-8 "he ge" (pass) (0x0805140c)
	.byte 0x00			@ padding
.endif

@ ---- ASCII measurement labels ----
	.global d_08051414
d_08051414:
	.ascii "C\0"			@ "C" (0x08051414)
	.short 0x0000			@ padding
	.global d_08051418
d_08051418:
	.ascii "RANGE\0"		@ "RANGE" (0x08051418)
	.short 0x0000			@ padding
	.global d_08051420
d_08051420:
	.ascii "TOL\0"			@ "TOL" (0x08051420)
	.global d_08051424
d_08051424:
	.ascii "L\0"			@ "L" (0x08051424)
	.short 0x0000			@ padding
	.global d_08051428
d_08051428:
	.ascii "AUTO\0"			@ "AUTO" (0x08051428)
	.byte 0x00, 0x00, 0x00		@ padding
	.global d_08051430
d_08051430:
	.ascii "AMP\0"			@ "AMP" (0x08051430)
	.global d_08051434
d_08051434:
	.ascii "FREQ\0"			@ "FREQ" (0x08051434)
	.byte 0x00, 0x00, 0x00		@ padding
	.global d_0805143c
d_0805143c:
	.ascii "R\0"			@ "R" (0x0805143c)
	.short 0x0000			@ padding
	.global d_08051440
d_08051440:
	.ascii "BIAS\0"			@ "BIAS" (0x08051440)
	.byte 0x00, 0x00, 0x00		@ padding
	.global d_08051448
d_08051448:
	.ascii "Z\0"			@ "Z" (0x08051448)
	.short 0x0000			@ padding

@ ---- UTF-8 measurement and mode texts ----
.ifndef OWN
	.byte 0xe9, 0xa2, 0x91, 0xe7, 0x8e, 0x87, 0x00	@ UTF-8 "pin lu" (frequency) (0x0805144c)
	.byte 0x00			@ padding
	.byte 0xe9, 0x87, 0x8f, 0xe7, 0xa8, 0x8b, 0x00	@ UTF-8 "liang cheng" (range) (0x08051454)
	.byte 0x00			@ padding
	.byte 0xe5, 0x88, 0x86, 0xe9, 0x80, 0x89, 0xe6, 0xb5, 0x8b, 0xe9, 0x87, 0x8f, 0x00	@ UTF-8 "fen xuan ce liang" (sorting measurement) (0x0805145c)
	.byte 0x00, 0x00, 0x00		@ padding
	.byte 0xe9, 0x98, 0xbb, 0xe6, 0x8a, 0x97, 0xe6, 0xb5, 0x8b, 0xe9, 0x87, 0x8f, 0x00	@ UTF-8 "zu kang ce liang" (impedance measurement) (0x0805146c)
	.byte 0x00, 0x00, 0x00		@ padding
	.byte 0xe7, 0x94, 0xb5, 0xe6, 0x84, 0x9f, 0xe6, 0xb5, 0x8b, 0xe9, 0x87, 0x8f, 0x00	@ UTF-8 "dian gan ce liang" (inductance measurement) (0x0805147c)
	.byte 0x00, 0x00, 0x00		@ padding
	.byte 0xe8, 0x87, 0xaa, 0xe5, 0x8a, 0xa8, 0xe6, 0xb5, 0x8b, 0xe9, 0x87, 0x8f, 0x00	@ UTF-8 "zi dong ce liang" (auto measurement) (0x0805148c)
	.byte 0x00, 0x00, 0x00		@ padding
	.byte 0xe7, 0x94, 0xb5, 0xe5, 0xae, 0xb9, 0xe6, 0xb5, 0x8b, 0xe9, 0x87, 0x8f, 0x00	@ UTF-8 "dian rong ce liang" (capacitance measurement) (0x0805149c)
	.byte 0x00, 0x00, 0x00		@ padding
	.byte 0xe7, 0x94, 0xb5, 0xe9, 0x98, 0xbb, 0xe6, 0xb5, 0x8b, 0xe9, 0x87, 0x8f, 0x00	@ UTF-8 "dian zu ce liang" (resistance measurement) (0x080514ac)
	.byte 0x00, 0x00, 0x00		@ padding
.endif
	.global d_080514bc
d_080514bc:
	.byte 0x31, 0x30, 0x30, 0xce, 0xa9, 0x00	@ "100" + UTF-8 omega sign (0x080514bc)
	.short 0x0000			@ padding
	.global d_080514c4
d_080514c4:
	.byte 0x31, 0x30, 0x30, 0x4b, 0xce, 0xa9, 0x00	@ "100K" + UTF-8 omega sign (0x080514c4)
	.byte 0x00			@ padding
	.global d_080514cc
d_080514cc:
	.byte 0x31, 0x30, 0x4b, 0xce, 0xa9, 0x00	@ "10K" + UTF-8 omega sign (0x080514cc)
	.short 0x0000			@ padding
	.global d_080514d4
d_080514d4:
	.byte 0x31, 0x4b, 0xce, 0xa9, 0x00	@ "1K" + UTF-8 omega sign (0x080514d4)
	.byte 0x00, 0x00, 0x00		@ padding
.ifndef OWN
	.byte 0xe5, 0x81, 0x8f, 0xe7, 0xbd, 0xae, 0x00	@ UTF-8 "pian zhi" (bias) (0x080514dc)
	.byte 0x00			@ padding
	.byte 0xe7, 0x94, 0xb5, 0xe5, 0xb9, 0xb3, 0x00	@ UTF-8 "dian ping" (level) (0x080514e4)
	.byte 0x00			@ padding
.endif
	.global d_080514ec
d_080514ec:
	.ascii "Shutdown Countdown\0"	@ "Shutdown Countdown" (0x080514ec)
	.byte 0x00			@ padding
.ifndef OWN
	.byte 0xe5, 0x85, 0xb3, 0xe6, 0x9c, 0xba, 0xe5, 0x80, 0x92, 0xe8, 0xae, 0xa1, 0xe6, 0x97, 0xb6, 0x00	@ UTF-8 "guan ji dao ji shi" (shutdown countdown) (0x08051500)
.endif

@ ---- Scatter-load region table (0x08051510) ----
@ __scatterload (0x0800784C) walks it while the entry address is below d_08051530 (unsigned
@ cmp at 0x08007860): per entry r0 = +0 source, r1 = +4 destination, r2 = +8 length, blx to
@ the handler +12 with bit 0 set. Its ldm.w at 0x08007858 needs the table word aligned, and
@ the image has to follow it directly (link_own.ld ASSERTs both for our build).
@ Entry 0 (0x08051510): source = the initial RAM image d_08051530, destination 0x20000000,
@ length 0x57C, handler = the decompressor (__decompress) in V1.1, copy_init (own/init.s,
@ a word copy) in our build.
@ Entry 1 (0x08051520): source = image end (not read), destination 0x2000057C, length
@ 0x15E2C, handler = the zero-fill routine (zero_fill_words).
	.global d_08051510
d_08051510:
	.word d_08051530		@ entry 0 source: the initial RAM image
	.word 0x20000000		@ entry 0 destination
	.word 0x0000057c		@ entry 0 length (0x57C bytes after unpacking / copied)
.ifdef OWN
	.word copy_init_addr		@ entry 0 handler: word copy (own/init.s, even address)
.else
	.word __decompress_addr		@ entry 0 handler (even address)
.endif
	.word image_end			@ entry 1 source: end of the image (0x08051758 in V1.1)
	.word 0x2000057c		@ entry 1 destination
	.word 0x00015e2c		@ entry 1 length
	.word zero_fill_words_addr	@ entry 1 handler (even address)

.ifdef OWN
@ ---- Initial RAM image of our build (0x57C bytes for 0x20000000..0x2000057B) ----
@ The unpacked V1.1 image (__decompress format 0x08007954..0x080079A8; equal to the vendor
@ block 08051530.bin unpacked) typed out, with two differences: every flash pointer is a label
@ (the 129 string pointers, the 6 USB descriptor pointers, the 30 code pointers; the linker
@ sets the Thumb bit of the code pointers), and row 0 of each of the 17 per-language text
@ tables equals its row 1 (English in both rows), so
@ the language word 0x2000115C selects an English text either way.
	.balign 4
	.global d_08051530
d_08051530:
ram_image:
	@ 0x20000000..0x20000023: zero
	.space 0x24
	@ 0x20000024: language names (1 per row): "English"
	.word d_080511dc, d_080511dc
	@ 0x2000002C: settings screen title (1 per row): "SETTING"
	.word d_08051124, d_08051124
	@ 0x20000034: calibration title (1 per row): "Cali"
	.word d_080511ec, d_080511ec
	@ 0x2000003C: restore title (1 per row): "Restore"
	.word d_080511cc, d_080511cc
	@ 0x20000044: restore warning (1 per row)
	.word d_08051188, d_08051188
	@ 0x2000004C..0x20000053: zero
	.word 0x00000000, 0x00000000
	@ 0x20000054: menu labels (9 per row; words 7 and 8 zero): Sorting, Language,
	@ Brightness, Volume, Off Time, Calibration, System
	.word d_080511d4, d_080511ac, d_08051244, d_080511c4, d_080511b8, d_08051230
	.word d_08051200, 0x00000000, 0x00000000
	.word d_080511d4, d_080511ac, d_08051244, d_080511c4, d_080511b8, d_08051230
	.word d_08051200, 0x00000000, 0x00000000
	@ 0x2000009C: calibration types (12 per row): Short, 10mR, 100mR, 1R, 10R, 100R, 1K,
	@ 10K, 100K, 1M, 10M, Open
	.word d_08051258, d_0805117c, d_08051174, d_08051170, d_0805116c, d_08051164
	.word d_0805114c, d_08051148, d_08051140, d_08051158, d_08051154, d_08051210
	.word d_08051258, d_0805117c, d_08051174, d_08051170, d_0805116c, d_08051164
	.word d_0805114c, d_08051148, d_08051140, d_08051158, d_08051154, d_08051210
	@ 0x200000FC: calibration states (4 per row): Start, Busy, Finish, Fail
	.word d_08051250, d_08051260, d_080511e4, d_080511f4
	.word d_08051250, d_08051260, d_080511e4, d_080511f4
	@ 0x2000011C: sorting dialog rows (5 per row): Norm, Tol, Warn, Volume, LED
	.word d_08051208, d_080511fc, d_0805123c, d_080511c4, d_080510ec
	.word d_08051208, d_080511fc, d_0805123c, d_080511c4, d_080510ec
	@ 0x20000144: compare result (2 per row): NG, OK
	.word d_0805112c, d_08051150, d_0805112c, d_08051150
	@ 0x20000154: off / on (2 per row): OFF, ON
	.word d_08051110, d_0805115c, d_08051110, d_0805115c
	@ 0x20000164: yes / no (2 per row): YES, NO
	.word d_08051184, d_08051160, d_08051184, d_08051160
	@ 0x20000174: off time texts (4 per row): NO, 5min, 15min, 30min
	.word d_08051160, d_08051228, d_08051220, d_08051218
	.word d_08051160, d_08051228, d_08051220, d_08051218
	@ 0x20000194: model, version (2 per row)
	.word d_080510f0, d_080510d0, d_080510f0, d_080510d0
	@ 0x200001A4: unit texts: mOhm, Ohm, KOhm, MOhm, pF, nF, uF, mF, nH, uH, mH, H
	.word d_080512e0, d_080512e4, d_080512d8, d_080512dc
	.word d_0805111c, d_08051118, d_08051120, d_08051114
	.word d_08051134, d_08051138, d_08051130, d_0805113c
	@ 0x200001D4..0x20000223: zero
	.space 0x50
	@ 0x20000224: cursor labels (4 per row): FREQ, AMP, BIAS, RANGE
	.word d_08051434, d_08051430, d_08051440, d_08051418
	.word d_08051434, d_08051430, d_08051440, d_08051418
	@ 0x20000244: AUTO, 100 Ohm, 1K Ohm, 10K Ohm, 100K Ohm
	.word d_08051428, d_080514bc, d_080514d4, d_080514cc, d_080514c4
	@ 0x20000258: function names (6 per row): AUTO, R, C, L, Z, TOL
	.word d_08051428, d_0805143c, d_08051414, d_08051424, d_08051448, d_08051420
	.word d_08051428, d_0805143c, d_08051414, d_08051424, d_08051448, d_08051420
	@ 0x20000288..0x200002A7: zero
	.space 0x20
	@ 0x200002A8: shutdown countdown title (1 per row)
	.word d_080514ec, d_080514ec
	@ 0x200002B0: SysTick reload source, 144000000 (own.inc V_SYSTICK_RLD)
	.word 0x08954400
	@ 0x200002B4..0x200002D7: zero
	.space 0x24
	@ 0x200002D8: USB string descriptor in RAM (0x1A bytes; pointer at 0x20000390)
	.word 0x0051031a, 0x004c0050, 0x00520043, 0x00200035
	.word 0x00000000, 0x00000000, 0x00000000, 0x00000000
	@ 0x200002F8: 14 code pointers
	.word fn_08008d0c, return_only_0800fee0, return_only_0800fee0, return_only_0800fee0
	.word return_only_0800fee0, return_only_0800fee0, return_only_0800fee0, return_only_0800fee0
	.word fn_08008d10, return_only_0800fee0, return_only_0800fee0, return_only_0800fee0
	.word return_only_0800fee0, return_only_0800fee0
	@ 0x20000330
	.word 0x00000103, 0x00000000
	@ 0x20000338: USB descriptors {address, length}: device (d_0802aefc + 0x40 = 0x0802AF3C),
	@ configuration
	.word d_0802aefc + 0x40, 0x00000012
	.word d_0802af4e, 0x00000020
	@ 0x20000348: USB driver table, 10 code pointers (0x0800AC39 the USB-reset
	@ handler, then the callbacks)
	.word fn_0800ac38, fn_0800ab60, return_only_0800ac34, return_only_0800ac36
	.word fn_0800aa8c, fn_0800ab10, return_2_unless_both_zero, fn_0800aad8
	.word fn_0800aacc, fn_0800aae4
	@ 0x20000370
	.word 0x00000000, 0x00000040
	@ 0x20000378: USB string descriptors {address, length}
	.word d_0802af4e + 0x20, 0x00000004		@ 0x0802AF6E
	.word d_0802af4e + 0x24, 0x00000026		@ 0x0802AF72
	.word d_0802af4e + 0x4a, 0x00000026		@ 0x0802AF98
	.word 0x200002d8, 0x0000001a			@ in RAM (a RAM address, a number)
	.word d_0802af4e + 0x70, 0x0000001a		@ 0x0802AFBE
	@ 0x200003A0
	.word 0x00000000, 0x00000001
	@ 0x200003A8..0x200003DF: zero
	.space 0x38
	@ 0x200003E0
	.byte 0x00
	@ 0x200003E1: 36 bytes of the form of a SCSI INQUIRY response (the layout of the
	@ bootloader's image at 0x200001A1, bootloader/src/rodata.s)
	.byte 0x00, 0x80, 0x02, 0x02, 0x20, 0x00, 0x00, 0x00
	.ascii "FNIRSI  "
	.ascii "HRM-10          "
	.ascii "1.0 "
	@ 0x20000405
	.byte 0x03, 0x00, 0x00
	@ 0x20000408
	.word 0x00060000, 0x00000000
	.word 0x00007000, 0x00000000, 0x0000000a, 0x00000000
	.word 0x00000000, 0x00000000, 0x00000000, 0x00080000
	.word 0x02000000
	@ 0x20000434..0x20000497: zero (the three 8-byte font caches 0x20000444..0x2000045B among
	@ them, font records +0x14 in rodata_01.s)
	.space 0x64
	@ 0x20000498
	.word 0x0000002d
	@ 0x2000049C..0x200004AF: zero
	.space 0x14
	@ 0x200004B0
	.word 0x00000001
	@ 0x200004B4..0x200004C7: zero
	.space 0x14
	@ 0x200004C8
	.word 0x80000000
	@ 0x200004CC..0x200004EB: zero
	.space 0x20
	@ 0x200004EC
	.word 0xa1b2c3d4
	@ 0x200004F0..0x200004FB: zero
	.space 0x0c
	@ 0x200004FC
	.word 0x0000006f, 0x00000000
	@ 0x20000504: 6 code pointers (the UTF-8 helpers)
	.word utf8_lead_byte_length, utf8_decode_next, fn_08027e64, fn_08027f78
	.word fn_08027e9c, fn_08027ec4
	@ 0x2000051C..0x2000057B: zero
	.space 0x60
	.if . - ram_image != 0x57C
	.error "the typed RAM image must be 0x57C bytes"
	.endif
.else
@ ---- Packed initial RAM image (0x08051530..0x08051756, 551 bytes) ----
@ Input of the decompressor __decompress; it unpacks to 0x20000000 (0x57C
@ bytes). The unpacked image holds code entry words, so every unit of the
@ application stays at its original address.
	.global d_08051530
d_08051530:
	.incbin "assets/vendor/08051530.bin"

	.byte 0x00			@ final byte at 0x08051757 (padding)
.endif

	.global image_end
image_end:
