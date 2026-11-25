"""measure_model.py - the LC1020E measurement path for the emulator (tests/meter_model.py with timing).

One device (attach with Meter.attach(MeasurePath(source))) for the peripherals the application's
measurement uses, and a pluggable signal source for the analog front end. Not a test by itself.
"Manual" is the N32G45x user manual V3.5.0 (docs/ of the project folder); fn_xxxxxxxx names the
application code in firmware/src/*.s.

What the application sets up (read from the code and from the registers after the start-up):
  fn_08007bdc (measure_32.s), started by fn_08009f10:
    DMA1 ch1 (CHCFG 0x40020008) ADC1 DAT 0x4002084C -> 0x20005A38, 128 halfwords, CHCFG 0x2581
    DMA1 ch8 (0x40020094)        ADC2 DAT 0x40020C4C -> 0x20005B38, 128 halfwords, CHCFG 0x2581
    DMA2 ch5 (0x40020458)        ADC3 DAT 0x4002184C -> 0x20005C38, 128 halfwords, CHCFG 0x0581
      (0x2581 = PRIOLVL high, MSIZE 16, PSIZE 16, MINC, CHEN; not circular, no interrupt)
    ADC1 channel 3, ADC2 channel 4, ADC3 channel 1 (RSEQ3), one conversion (RSEQ1 length 0), not
    continuous, sample time code 0 = 1.5 cycles, ENDMA, EXTRTRIG with EXTRSEL 010 = TIM1_CC3
    (manual table 9-5 / 9-6); CTRL2 0x00540101.
    TIM1 (0x40012C00, fn_08007e7c): PSC 0, AR = 144000000 / (f * 128) for f < 10 kHz (f * 32 below
    100 kHz, f * 8 above), channel 3 PWM mode 2 (CCMOD2 0x70), CCDAT3 = 1, CC3 output and MOE on:
    one CC3 event, so one conversion of each ADC, per counter period (AR + 1 timer ticks).
  fn_08008024: DMA2 ch8 (0x40020494) ADC4 DAT 0x40021C4C -> 0x20005D38, 128 halfwords, circular
    (CHCFG 0x25A1); ADC4 channel 3, sample time code 6 = 71.5 cycles, continuous (CTU), EXTRSEL 111
    = SWSTRRCH started by fn_08007b3c; fn_080092cc averages the buffer: supply = mean * 6.6 / 4095.
  fn_08008814 / fn_080087d4: DAC channel 1 (DAC_CTRL 0x1007: CH1EN, B1EN, T1EN, T1SEL 000 = TIM6
    TRGO, DMA1EN) fed by DMA2 ch3 (0x40020430) from the sine table 0x20005120 (n = 180 halfwords
    below 100 kHz, else 36) to DAC_DR12CH1 0x40007408, circular, memory to peripheral, TXCIE
    (CHCFG 0x25B3); TIM6 (0x40001000) PSC 0, AR = 72000000 / f / n - 1, MMSEL update (CTRL2 0x20):
    the DAC plays the table once per period 1 / f. IRQ 58 (DMA2 channel 3, manual vector table)
    enabled by fn_0800ad68; its handler fn_080085d0 clears TXCF3 (0x200 to DMA2 INTCLR) and, when the
    byte 0x200011C4 is set, clears it, writes TXNUM 0x80 to the three ADC channels and enables them:
    each acquisition starts at the end of a DAC period.
  fn_0800a068 waits for TXCF1 / TXCF8 of DMA1 and TXCF5 of DMA2 (fn_08007e24), then fn_08007fd4 /
    fn_0800b20c (ADC1 peak-to-peak window 1500..3600, gain byte 0x200011C5) and fn_08007f38 /
    fn_0800b000 (ADC2 window 1500..3000, gain byte 0x200011C6, range byte 0x200011C8; ADC3
    peak-to-peak above 250 steps the auto range down), FFT of both buffers,
    Z = R[0x200011C8] * G[0x200011C6] / G[0x200011C5] * |ADC1| / |ADC2| (R = 100, 1000, 10000,
    100000 ohm at 0x0802AEEC, G = 1..128 at 0x0802AEE4), theta = phase(ADC1) - phase(ADC2).
  Clocks (RCC_CFG 0x08C5250A after the start-up): APB2 /2, APB1 /4 of 144 MHz, so the TIM1 clock is
  144 MHz and the TIM6 clock 72 MHz (manual 6.2 Clock control unit: "If the APB prescaler is 1
  ... Otherwise, ... twice the frequency"); RCC_CFG2 0x3C01: ADCHPRES 1 = HCLK / 2 = 72 MHz with
  ADC_CTRL3.CKMOD 0 (AHB).

Model (each rule with its source):
  DMA1 / DMA2 (manual 8.4, 8.5): INTSTS (+0x00) flags GLBF / TXCF / HTXF / ERRF per channel (read
  only: a write is a violation), INTCLR (+0x04) write 1 to clear, reads 0; per channel x CHCFG
  (+0x08 + 20 (x - 1)), TXNUM (+0x0C), PADDR (+0x10), MADDR (+0x14), CHSEL (+0x18, stored), CHMAPEN
  (+0xA8: setting MAP_EN is not modelled, violation). While CHEN = 1 a CHCFG write changes only CHEN
  (8.4.8 "when CHEN is 1, other bits ... cannot be rewritten") and TXNUM / PADDR / MADDR writes are
  ignored and logged (8.5.5..8.5.7 "can only be written if the channel is disabled"). Enabling a
  channel starts at PADDR / MADDR; every request moves one item (PSIZE read, MSIZE write, PINC /
  MINC), TXNUM counts down; HTXF when TXNUM reaches half of the programmed count (rounded down),
  TXCF at 0; then circular mode reloads the programmed count and the base addresses (8.4.5), else
  the channel stops and CHEN is cleared (8.5.5 "it will keep at zero and reset channel enable").
  GLBF with every flag. The channel's IRQ line (DMA1 ch1..7 = 11..17, ch8 = 76; DMA2 ch1..5 =
  56..60, ch6 / 7 = 68 / 69, ch8 = 77, manual vector table) is asserted while a flag with its
  enable bit (TXCIE / HTXIE / ERRIE) is set ("Interrupt is a level signal", 8.4.10).
  Requests (manual tables 8-4 / 8-5, CHMAPEN 0): DMA1 ch1 ADC1, DMA1 ch8 ADC2, DMA2 ch5 ADC3, DMA2
  ch8 ADC4 (each when its ENDMA is set), DMA2 ch3 DAC channel 1 (DMA1EN). An enabled channel with
  another request source, MEM2MEM or a TIM6 update DMA request is not modelled (violation).
  Manual silent (8.4.1 says only that a request is processed by priority): a request that arrives
  while its channel is disabled or at TXNUM 0 is held, one at a time (not accumulated, as 10.3.7
  states for the DAC), until the channel is enabled with TXNUM > 0, which then serves it at once
  with the peripheral's data as it stands (the ADC's DAT of its last conversion); the peripheral
  withdraws it when its DMA enable or the peripheral is switched off or reset. Chosen for the
  vendor code: an acquisition fn_080085d0 starts after a gap then holds the last conversion as its
  first item and ends one conversion period (7.82 us at 1 kHz) earlier. With requests lost, every
  run (our build and the vendor build, R, C and L at 1 kHz, 2026-11-20) stopped measuring at
  0.4992 s; with held requests the vendor build measures R, C and L and our build R.
  Enabling a channel at TXNUM 0 is logged ('dma-enabled-at-txnum-0'); it transfers nothing and
  sets no flag (8.5.5: TXNUM is the number of data to transfer).
  The vendor code races with these rules (both builds, not a model choice): 128 conversions take
  128 x 1126 / 144 MHz = 1.00089 ms, one DAC period 1 ms; when the main loop sets 0x200011C4 while
  an acquisition still runs (fn_0800a068 takes the transfer-complete flags of the previous one,
  which fn_08007efc leaves set), the next interrupt can come within the acquisition's last
  conversion period: fn_080085d0's TXNUM writes (0x080087CE) land while a channel is enabled and
  are ignored, the channel completes, its enable write (0x08008782) sets CHEN at TXNUM 0, and the
  measurement waits for a flag that never comes (no new result until fn_08009f10 runs again; when
  it hits the wait loop of fn_08007efc, the IWDG resets the chip: our build, L 10 mH).
  Whether a run meets it depends on instruction timing (Meter cpi), which the model does not
  claim to be the meter's.
  ADC1..ADC4 (manual 9): register file at 0x40020800 / 0x40020C00 / 0x40021800 / 0x40021C00;
  CTRL3 reset value 0x43 (9.12.18), RDY (bit 5) reads ON (no power-up time modelled), CTRL2 ENCAL
  reads 0 (calibration ends at once); a regular conversion starts on the external trigger of
  EXTRSEL when EXTRTRIG is set (TIM1_CC3 for 010, the only timer trigger modelled; any other timer
  source is a violation), on SWSTRRCH with EXTRSEL 111 (the bit is then cleared, 9.12.4), or on a
  CTRL2 write of ON = 1 to an ON ADC that changes no other bit (9.12.4); CTU repeats it. Conversion
  time (9.3 "Programmable channel sampling time", TCONV): 3 + sample time + 12.5 ADC clocks for the first conversion, sample time +
  12.5 for the next of a continuous run; the input is taken at the end of the sample time, DAT and
  the DMA request at the end of the conversion; STS ENDC / ENDCA / STR set by a conversion, cleared
  by writing 0 (written 1 keeps them). 12-bit right aligned only; scan, sequence length > 1, the
  dual modes (CTRL1 DUSEL), injected channels and ADC interrupts are not modelled (violation).
  ADC clock: CKMOD 0 = HCLK / ADCHPRES, CKMOD 1 = PLL / ADCPLLPRES (RCC_CFG2, manual 6.3.13).
  TIM1 / TIM6 (manual 11, 13): CTRL1, CTRL2, DINTEN, STS, EVTGEN, CCMOD1 / 2, CCEN, CNT, PSC, AR
  (reset 0xFFFF), CCDAT1..4, BKDT; up-counting edge-aligned only (DIR, CAMSEL, ONEPM, SMCTRL, any
  DINTEN bit: violation). The counter runs while CNTEN is set and the clock is on, at the timer
  clock / (PSC + 1); an update at the AR -> 0 wrap, CC3 when the counter reaches CCDAT3 (CC3 an
  output, CCMOD2 bits 1:0 = 00); EVTGEN.UDGN clears the counter and the prescaler, loads PSC and AR
  and gives a TRGO pulse for MMSEL 000 and 010 (11.4.3); AR is loaded at once with ARPEN 0, a PSC
  change of a running counter waits for UDGN (both other cases: violation). TRGO = update for
  MMSEL 010. Manual silent: a counter above a new AR (fn_08008814 writes AR of the running TIM6
  before its UDGN) counts up to 0xFFFF and wraps to 0 with an update. A timer clock switched while
  the counter is enabled is not modelled (the application enables every clock first,
  fn_08008504).
  DAC channel 1 (manual 10): CTRL, SOTTR, DR12CH1 / DL12CH1 / DR8CH1 set the data hold register,
  DATO1 (+0x2C) read only; a TRGO of the T1SEL timer (TIM6 only; others: violation) with CH1EN and
  T1EN moves the hold register to DATO1 after 3 APB1 clocks (10.3.4) and, with DMA1EN, requests
  the next item from the DMA (10.3.7). Noise / triangle (W1EN) and the DAC2: violation.
  RCC: APB2PRST (+0x0C) TIM1RST, APB1PRST (+0x10) TIM6RST / DACRST, AHBPRST (+0x28) ADC1..4RST
  (bits 12..15) reset the peripheral to its reset values; the registers keep their values as
  written. Clock enables: RCC_AHBPCLKEN DMA1 / DMA2 (bits 0, 1) and ADC1..4 (12..15),
  RCC_APB2PCLKEN TIM1 (11), RCC_APB1PCLKEN TIM6 (4) and DAC (29): a peripheral without its clock
  does not run (its registers still read and write).
  Time: every register access first brings the model to the emulated time of the access
  (Meter.now(), exact per instruction), so a flag reads as on the hardware; DMA writes into SRAM are
  made at that point, at every slice end, and the slice ends at every DMA event whose interrupt is
  enabled (next_event), so an interrupt is entered at its time. Memory a channel writes while the
  CPU reads it between two such points is at most one slice (slice_insns instructions) late.

Signal source (pluggable, MeasurePath(source)): source.samples(path, adc, channel, times) returns
one code (0..4095) per time, or one int for all of them. While a DMA transfer fills a buffer, path.idx
holds the item number of each time in the buffer of the channel (0 = the first item after the enable,
the held conversion included); for any other call (a DAT register read) it is None. DutSource ignores
it; a source may use it to give every acquisition the same samples whatever its start time (the
emulated time is the instruction count, so two builds start their acquisitions at other times: tests/
test_own_ocal.py IndexSource). DutSource is the device under test
model; MeasurePath.generator(times) gives the generator voltage as the analytic signal g(t)
(volts, v(t) = Re g(t)): the fundamental of the DAC output as DMA2 ch3 plays it (bin 1 of the
table taken when the channel is enabled, the zero-order hold's sinc(pi / n) and half-step delay,
the 3 APB1 clock transfer delay), at the frequency TIM6 rate / n.
"""
import cmath
import math
import struct

DMA1, DMA2 = 0x40020000, 0x40020400
ADC_BASES = (0x40020800, 0x40020C00, 0x40021800, 0x40021C00)
TIM1, TIM6 = 0x40012C00, 0x40001000
DAC = 0x40007400
RCC_CFG, RCC_APB2PRST, RCC_APB1PRST, RCC_AHBEN, RCC_APB2EN, RCC_APB1EN, RCC_AHBPRST, RCC_CFG2 = (
    0x40021004, 0x4002100C, 0x40021010, 0x40021014, 0x40021018, 0x4002101C, 0x40021028, 0x4002102C)
GPIOA, GPIOC = 0x40010800, 0x40011000
SRAM_LO, SRAM_HI = 0x20000000, 0x20024000      # meter_model SRAM (plain memory)
IRQ_DMA1 = (11, 12, 13, 14, 15, 16, 17, 76)
IRQ_DMA2 = (56, 57, 58, 59, 60, 68, 69, 77)
# DMA request lines with CHMAPEN 0 (manual tables 8-4, 8-5): (controller, channel) -> source
REQ = {(0, 1): 'adc1', (0, 8): 'adc2', (1, 5): 'adc3', (1, 8): 'adc4', (1, 3): 'dac1'}
REQ_CH = {v: k for k, v in REQ.items()}
ADC_RSTEN = (1 << 12, 1 << 13, 1 << 14, 1 << 15)
# sample time in ADC clocks by SAMPx code, ADC_SAMPT3.SAMPSEL 0 / 1 (manual 9.12.5)
SAMP_CYC = ((1.5, 7.5, 13.5, 28.5, 41.5, 55.5, 71.5, 239.5), (1.5, 2.5, 4.5, 7.5, 19.5, 61.5, 181.5, 601.5))
RANGE_OHM = (100.0, 1000.0, 10000.0, 100000.0)       # word table 0x0802AEEC
GAIN = (1, 2, 4, 8, 16, 32, 64, 128)                  # byte table 0x0802AEE4
BIAS_COUNTS_PER_V = 620.0                             # fn_08008814: bias float * 620.0 DAC counts


def _apb_div(code):
    return 1 if code < 4 else (2, 4, 8, 16)[code - 4]


def _merge(old, a, size, value):
    sh = 8 * (a & 3)
    mask = ((1 << 8 * size) - 1) << sh
    return (old & ~mask) | ((value << sh) & mask)


def _grid_window(t0, period, t_a, t_b):
    """Indices k >= 0 of the events t0 + k * period with t_a < t <= t_b, as (k_lo, k_hi) or None."""
    if period <= 0 or t_b < t0:
        return None
    k_lo = 0 if t_a < t0 else int(math.floor((t_a - t0) / period)) + 1
    while k_lo > 0 and t0 + (k_lo - 1) * period > t_a:
        k_lo -= 1
    while t0 + k_lo * period <= t_a:
        k_lo += 1
    k_hi = int(math.floor((t_b - t0) / period))
    while t0 + k_hi * period > t_b:
        k_hi -= 1
    while t0 + (k_hi + 1) * period <= t_b:
        k_hi += 1
    return (k_lo, k_hi) if k_hi >= k_lo else None


class Channel:
    def __init__(self, ctl, x):
        self.ctl, self.x = ctl, x
        self.cfg = self.txnum = self.init = self.paddr = self.maddr = self.chsel = 0
        self.done = 0               # items since enable / reload (address offset)
        self.pending = False        # a request of the peripheral not served yet (held, not counted)

    @property
    def on(self):
        return bool(self.cfg & 1)

    @property
    def circ(self):
        return bool(self.cfg & 0x20)

    def size(self, field):
        return (1, 2, 4, 0)[(self.cfg >> field) & 3]


class Timer:
    """TIM1 (advanced) or TIM6 (basic): the counter as a time grid."""

    def __init__(self, base, name):
        self.base, self.name = base, name
        self.reset()

    def reset(self):
        self.r = {0x2C: 0xFFFF}
        self.psc_shadow = 0
        self.ar_shadow = 0xFFFF
        self.running = False
        self.t_anchor = 0.0
        self.cnt_anchor = 0
        self.sts = 0
        self.t_flags = 0.0           # flags (UDITF, CC3ITF) count events after this time

    def reg(self, off):
        return self.r.get(off, 0)


class MeasurePath:
    """DMA1 / DMA2, ADC1..4, TIM1, TIM6, DAC channel 1 (module docstring) with a signal source."""

    def __init__(self, source):
        self.source = source
        self.ranges = [(DMA1, DMA1 + 0x400), (DMA2, DMA2 + 0x400)] + [(b, b + 0x400) for b in ADC_BASES] + [
            (TIM1, TIM1 + 0x400), (TIM6, TIM6 + 0x400), (DAC, DAC + 0x400),
            (RCC_APB2PRST, RCC_APB2PRST + 8), (RCC_AHBPRST, RCC_AHBPRST + 4)]
        self.log = []
        self.m = None
        self.idx = None              # item numbers of the samples a source call fills (Signal source)

    # ------------------------------------------------------------------ chip reset
    def reset(self, m):
        self.m = m
        self.dma = [[Channel(c, x) for x in range(1, 9)] for c in range(2)]
        self.flags = [0, 0]
        self.adc = [self._adc_reset() for _ in range(4)]
        self.tim = {TIM1: Timer(TIM1, 'TIM1'), TIM6: Timer(TIM6, 'TIM6')}
        self.dac = self._dac_reset()
        self.rst = {RCC_APB2PRST: 0, RCC_APB1PRST: 0, RCC_AHBPRST: 0}
        self.t_sync = m.now()
        self.gen = None              # generator epoch (generator())
        self.stats = dict(transfers=[[0] * 8, [0] * 8], held=[[0] * 8, [0] * 8])
        self._gv, self._gk, self._gc = 0, None, {}      # grid cache (_grid_cache)
        self._bin1 = {}              # _gen_epoch: bin 1 by table bytes

    @staticmethod
    def _adc_reset():
        return dict(r={0x58: 0x43}, running=False, t0=0.0, period=0.0, single=False, sample_dt=0.0,
                    dat=0, sts=0)

    @staticmethod
    def _dac_reset():
        return dict(ctrl=0, dhr=0, dato=0)

    # ------------------------------------------------------------------ clocks
    def _regs(self):
        return self.m.st['regs']

    def hclk(self):
        core = self.m.timing['core']
        a = (self._regs().get(RCC_CFG, 0) >> 4) & 0xF
        return core / (1 if a < 8 else (2, 4, 8, 16, 64, 128, 256, 512)[a - 8])

    def timer_clock(self, base):
        cfg = self._regs().get(RCC_CFG, 0)
        code = (cfg >> 11) & 7 if base == TIM1 else (cfg >> 8) & 7
        d = _apb_div(code)
        return self.hclk() / d * (1 if d == 1 else 2)

    def pclk1(self):
        return self.hclk() / _apb_div((self._regs().get(RCC_CFG, 0) >> 8) & 7)

    def adc_clock(self, i):
        cfg2 = self._regs().get(RCC_CFG2, 0)
        if self.adc[i]['r'].get(0x58, 0) & 0x10:
            p = (cfg2 >> 4) & 0x1F
            if not p & 0x10:
                return 0.0
            div = (1, 2, 4, 6, 8, 10, 12, 16, 32, 64, 128, 256)[min(p & 0xF, 11)]
            return self.m.timing['core'] / div
        h = cfg2 & 0xF
        return self.hclk() / (1, 2, 4, 6, 8, 10, 12, 16, 32)[min(h, 8)]

    def clock_on(self, what):
        r = self._regs()
        if what == 'dma1':
            return bool(r.get(RCC_AHBEN, 0) & 1)
        if what == 'dma2':
            return bool(r.get(RCC_AHBEN, 0) & 2)
        if isinstance(what, str) and what.startswith('adc'):
            return bool(r.get(RCC_AHBEN, 0) & ADC_RSTEN[int(what[3]) - 1])
        if what == TIM1:
            return bool(r.get(RCC_APB2EN, 0) & (1 << 11))
        if what == TIM6:
            return bool(r.get(RCC_APB1EN, 0) & (1 << 4))
        if what == 'dac':
            return bool(r.get(RCC_APB1EN, 0) & (1 << 29))
        raise ValueError(what)

    # ------------------------------------------------------------------ timers
    def _tick(self, t):
        return (t.psc_shadow + 1) / self.timer_clock(t.base)

    def _tim_counting(self, t):
        return t.running and self.clock_on(t.base)

    def _tim_cnt(self, t, now):
        if not self._tim_counting(t):
            return t.cnt_anchor
        n = int(math.floor((now - t.t_anchor) / self._tick(t) + 1e-9))
        if t.cnt_anchor > t.ar_shadow:              # above a new AR: up to 0xFFFF, then from 0
            if n < 0x10000 - t.cnt_anchor:
                return t.cnt_anchor + n
            return (n - (0x10000 - t.cnt_anchor)) % (t.ar_shadow + 1)
        return (t.cnt_anchor + n) % (t.ar_shadow + 1)

    def _tim_grid(self, t, kind):
        """(t_first, period) of the update or CC3 events of a counting timer, else None."""
        if not self._tim_counting(t):
            return None
        tick, top = self._tick(t), t.ar_shadow + 1
        above = t.cnt_anchor > t.ar_shadow          # counts up to 0xFFFF and wraps to 0 (an update)
        if kind == 'update':
            first = (0x10000 if above else top) - t.cnt_anchor
        else:
            if t.reg(0x1C) & 3:            # CC3 configured as input
                return None
            ccr = t.reg(0x3C)
            if ccr > t.ar_shadow:
                return None
            if above:
                first = 0x10000 - t.cnt_anchor + ccr
            else:
                first = (ccr - t.cnt_anchor) % top or top
        return t.t_anchor + first * tick, top * tick

    def _tim_reanchor(self, t, now):
        t.cnt_anchor = self._tim_cnt(t, now)
        t.t_anchor = now

    def _trgo_grid(self, t):
        mms = (t.reg(0x04) >> 4) & 7
        return self._tim_grid(t, 'update') if mms == 2 else None

    def _tim_write(self, base, a, size, value):
        m, t = self.m, self.tim[base]
        off = a - base
        w = off & ~3
        now = m.now()
        new = _merge(t.reg(w), a, size, value) & 0xFFFF
        if w == 0x14:                      # EVTGEN
            if new & 1:
                self._tim_reanchor(t, now)
                t.cnt_anchor = 0
                t.psc_shadow = t.reg(0x28)
                t.ar_shadow = t.reg(0x2C)
                t.sts |= 1
                mms = (t.reg(0x04) >> 4) & 7
                if base == TIM6 and mms in (0, 2):
                    self._dac_trigger_once(now)
            if new & ~1:
                m.violation('%s EVTGEN 0x%04X: only UDGN is modelled' % (t.name, new))
            return
        if w == 0x10:                      # STS: rc_w0
            t.sts &= new
            t.t_flags = now
            return
        if w == 0x24:                      # CNT
            t.r[w] = new
            t.cnt_anchor = new
            t.t_anchor = now
            return
        if w == 0x08 and new:
            m.violation('%s SMCTRL 0x%04X: slave mode not modelled' % (t.name, new))
            return
        if w == 0x0C and new:
            m.violation('%s DINTEN 0x%04X: timer interrupts / DMA not modelled' % (t.name, new))
            return
        if w == 0x00:
            if new & 0x7A:
                m.violation('%s CTRL1 0x%04X: only up-counting edge-aligned with updates is modelled'
                            % (t.name, new))
                return
            was = t.running
            t.r[w] = new
            if new & 1 and not was:
                t.running = True
                t.t_anchor = now
            elif was and not new & 1:
                t.cnt_anchor = self._tim_cnt(t, now)
                t.running = False
            return
        if w == 0x2C:
            t.r[w] = new
            if not t.reg(0x00) & 0x80:
                if t.running:
                    self._tim_reanchor(t, now)
                t.ar_shadow = new
            elif t.running and new != t.ar_shadow:
                m.violation('%s AR written with ARPEN while running: not modelled' % t.name)
            return
        if w == 0x28:
            t.r[w] = new
            if not t.running:
                t.psc_shadow = new        # loaded at the latest by the next UDGN; nothing counts before
            elif new != t.psc_shadow:
                m.violation('%s PSC changed while counting without UDGN: not modelled' % t.name)
            return
        t.r[w] = new

    def _tim_read(self, base, a, size):
        t = self.tim[base]
        w = (a - base) & ~3
        now = self.m.now()
        if w == 0x24:
            v = self._tim_cnt(t, now)
        elif w == 0x10:
            v = t.sts
            g = self._tim_grid(t, 'update')
            if g and _grid_window(g[0], g[1], t.t_flags, now):
                v |= 1
            if base == TIM1:
                g = self._tim_grid(t, 'cc3')
                if g and _grid_window(g[0], g[1], t.t_flags, now):
                    v |= 8
            t.sts = v
            t.t_flags = now
        else:
            v = t.reg(w)
        return v >> 8 * (a & 3)

    # ------------------------------------------------------------------ ADC
    def _adc_trigger(self, i):
        """'tim1cc3', 'sw' or None (not modelled sources raise a violation when they would run)."""
        r = self.adc[i]['r']
        c2 = r.get(0x08, 0)
        if not c2 & 0x100000:
            return None
        sel = (c2 >> 17) & 7
        if sel == 7:
            return 'sw'
        if sel == 2:
            return 'tim1cc3'
        return 'other'

    def _adc_times(self, i, first):
        """(sample delay after the start of the conversion, conversion time) in seconds."""
        r = self.adc[i]['r']
        f = self.adc_clock(i)
        if f <= 0:
            return None
        ch = r.get(0x34, 0) & 0x1F
        sampsel = (r.get(0x5C, 0) >> 3) & 1
        word = 0x10 if ch < 10 else 0x0C
        code = (r.get(word, 0) >> (3 * (ch % 10))) & 7
        ts = SAMP_CYC[sampsel][code]
        pre = 3.0 if first else 0.0
        return (pre + ts) / f, (pre + ts + 12.5) / f

    def _adc_check(self, i):
        m, r = self.m, self.adc[i]['r']
        if r.get(0x04, 0) & 0x000F0100:
            m.violation('ADC%d CTRL1 0x%08X: scan / dual mode not modelled' % (i + 1, r.get(0x04, 0)))
            return False
        if (r.get(0x2C, 0) >> 20) & 0xF:
            m.violation('ADC%d sequence length > 1 not modelled' % (i + 1))
            return False
        if r.get(0x08, 0) & 0x800:
            m.violation('ADC%d left alignment not modelled' % (i + 1))
            return False
        if r.get(0x58, 0) & 3 != 3 or r.get(0x58, 0) & 0x300:
            m.violation('ADC%d CTRL3 0x%X: only 12 bits without interrupts are modelled' % (i + 1, r.get(0x58, 0)))
            return False
        return True

    def _grid_cache(self):
        """The grids of _adc_grid, _dac_grid and _channel_grid are functions of the register state of
        this model and of the RCC words RCC_CFG, RCC_CFG2, RCC_AHBEN, RCC_APB2EN, RCC_APB1EN (and the
        constant core clock); they are computed once per state and kept. self._gv counts the changes
        of that register state: write() before and after each register write (no write handler
        computes a grid between its changes and its end), and sync() where a single conversion ends;
        the RCC words are part of the key. Values are the ones the computation gives (same code)."""
        r = self.m.st['regs']
        k = (self._gv, r.get(RCC_CFG, 0), r.get(RCC_CFG2, 0), r.get(RCC_AHBEN, 0), r.get(RCC_APB2EN, 0),
             r.get(RCC_APB1EN, 0))
        if k != self._gk:
            self._gk = k
            self._gc.clear()
        return self._gc

    def _adc_grid(self, i):
        """(t_first_ready, period, sample_delay, single) of the conversions of ADC i, or None."""
        c = self._grid_cache()
        if i in c:
            return c[i]
        g = c[i] = self._adc_grid_calc(i)
        return g

    def _adc_grid_calc(self, i):
        a = self.adc[i]
        if not (a['r'].get(0x08, 0) & 1) or not self.clock_on('adc%d' % (i + 1)):
            return None
        trig = self._adc_trigger(i)
        if trig == 'tim1cc3':
            g = self._tim_grid(self.tim[TIM1], 'cc3')
            tt = self._adc_times(i, True)
            if g is None or tt is None:
                return None
            return g[0] + tt[1], g[1], tt[1] - tt[0], False
        if a['running']:
            return a['t0'], a['period'], a['sample_dt'], a['single']
        return None

    def _adc_sw_start(self, i, now):
        a = self.adc[i]
        t1 = self._adc_times(i, True)
        tn = self._adc_times(i, False)
        if t1 is None or not self._adc_check(i):
            return
        cont = bool(a['r'].get(0x08, 0) & 2)
        a['running'] = True
        a['t0'] = now + t1[1]
        a['period'] = tn[1] if cont else 1.0
        a['single'] = not cont
        # the first conversion has the 3 extra clocks: its sample is taken earlier relative to its end;
        # the later ones are tn apart; one sample delay (tn[1] - tn[0] = 12.5 clocks) holds for all
        a['sample_dt'] = tn[1] - tn[0]

    def _adc_write(self, i, a, size, value):
        m, ad = self.m, self.adc[i]
        base = ADC_BASES[i]
        w = (a - base) & ~3
        new = _merge(ad['r'].get(w, 0), a, size, value)
        now = m.now()
        if w == 0x00:
            ad['sts'] &= new
            return
        if w == 0x4C:
            m.violation('ADC%d DAT written' % (i + 1))
            return
        if w == 0x08:
            old = ad['r'].get(0x08, 0)
            if new & 0x00208000:
                m.violation('ADC%d injected conversions not modelled (CTRL2 0x%08X)' % (i + 1, new))
                return
            ad['r'][0x08] = new & ~(1 << 2)          # ENCAL: calibration ends at once
            trig = self._adc_trigger(i)
            if new & 1 and old & 1 and new == old:
                self._adc_sw_start(i, now)           # ON written 1 again, nothing else changed (9.12.4)
            if new & 0x400000 and trig == 'sw' and new & 1:
                ad['r'][0x08] &= ~0x400000           # SWSTRRCH cleared as the conversion begins
                self._adc_sw_start(i, now)
            if trig == 'other' and new & 1:
                m.violation('ADC%d external trigger EXTRSEL %d not modelled' % (i + 1, (new >> 17) & 7))
                return
            if trig == 'tim1cc3' and new & 1:
                self._adc_check(i)
            if not new & 1:
                ad['running'] = False
            if not new & 1 or not new & 0x100:
                self._drop_request('adc%d' % (i + 1))
            return
        ad['r'][w] = new

    def _adc_read(self, i, a, size):
        ad = self.adc[i]
        w = (a - ADC_BASES[i]) & ~3
        if w == 0x00:
            v = ad['sts']
        elif w == 0x4C:
            v = self._adc_dat(i, self.m.now())
        elif w == 0x58:
            v = ad['r'].get(0x58, 0) & ~0x20
            if ad['r'].get(0x08, 0) & 1:
                v |= 0x20
        else:
            v = ad['r'].get(w, 0)
        return v >> 8 * (a & 3)

    def _adc_dat(self, i, now):
        """DAT: the result of the last conversion that ended at or before now."""
        ad = self.adc[i]
        g = self._adc_grid(i)
        if g is None or now < g[0]:
            return ad['dat']
        if g[3]:
            return ad['dat']
        k = int(math.floor((now - g[0]) / g[1]))
        while k > 0 and g[0] + k * g[1] > now:
            k -= 1
        ad['dat'] = self._adc_samples(i, [g[0] + k * g[1] - g[2]])[0]
        return ad['dat']

    def _adc_samples(self, i, times):
        ch = self.adc[i]['r'].get(0x34, 0) & 0x1F
        v = self.source.samples(self, i + 1, ch, times)
        if isinstance(v, int):
            return [max(0, min(4095, v))] * len(times)
        return [max(0, min(4095, int(x))) for x in v]

    # ------------------------------------------------------------------ DAC
    def _dac_trigger_once(self, now):
        """One TRGO of TIM6 at time now (UDGN): DATO <- hold register, then a DMA request."""
        d = self.dac
        if not self._dac_ready():
            return
        d['dato'] = d['dhr']
        self._serve(1, 3, now + 3 / self.pclk1(), 0.0, 0, 0)
        self.gen = None

    def _dac_ready(self):
        c = self.dac['ctrl']
        return bool(c & 1) and bool(c & 4) and (c >> 3) & 7 == 0 and self.clock_on('dac')

    def _dac_grid(self):
        c = self._grid_cache()
        if 'dac' in c:
            return c['dac']
        g = c['dac'] = self._dac_grid_calc()
        return g

    def _dac_grid_calc(self):
        if not self._dac_ready():
            return None
        g = self._trgo_grid(self.tim[TIM6])
        if g is None:
            return None
        return g[0] + 3 / self.pclk1(), g[1]

    def _dac_write(self, a, size, value):
        m, d = self.m, self.dac
        off = (a - DAC) & ~3
        if off == 0x00:
            new = _merge(d['ctrl'], a, size, value)
            if new & 0x0FC0 or new & 0xFFFF0000:
                m.violation('DAC_CTRL 0x%08X: waves / DAC2 not modelled' % new)
                return
            if (new >> 3) & 7 not in (0, 7) and new & 4:
                m.violation('DAC trigger T1SEL %d not modelled' % ((new >> 3) & 7))
                return
            d['ctrl'] = new
            if not new & 0x1000 or not new & 1:
                self._drop_request('dac1')
            self.gen = None
        elif off == 0x04:
            if value & 1:
                d['dato'] = d['dhr']
        elif off == 0x08:
            d['dhr'] = value & 0xFFF
        elif off == 0x0C:
            d['dhr'] = (value >> 4) & 0xFFF
        elif off == 0x10:
            d['dhr'] = (value & 0xFF) << 4
        elif off == 0x2C:
            m.violation('DAC_DATO1 written')
        else:
            m.violation('DAC register +0x%X not modelled' % off)

    def _dac_read(self, a, size):
        off = (a - DAC) & ~3
        d = self.dac
        v = {0x00: d['ctrl'], 0x08: d['dhr'], 0x0C: d['dhr'] << 4, 0x10: d['dhr'] >> 4, 0x2C: d['dato']}.get(off, 0)
        return v >> 8 * (a & 3)

    # ------------------------------------------------------------------ generator (signal at the DUT)
    def _gen_epoch(self):
        """Bin 1 of the table DMA2 ch3 plays, anchored to the DAC trigger grid; False when silent."""
        ch = self.dma[1][2]
        g = self._dac_grid()
        if g is None or not ch.on or not ch.circ or not self.dac['ctrl'] & 0x1000 or ch.init < 2:
            return False
        n = ch.init
        sz = ch.size(10)
        raw = bytes(self.m.uc.mem_read(ch.maddr, n * sz))
        fmt = {1: 'B', 2: 'H', 4: 'I'}[sz]
        tab = [x & 0xFFF for x in struct.unpack('<%d%s' % (n, fmt), raw)]
        # bin 1 of the table: a function of the table bytes alone, computed once per table (the same
        # sum in the same order, so the same value)
        key = (n, sz, raw)
        c1 = self._bin1.get(key)
        if c1 is None:
            c1 = self._bin1[key] = sum(v * cmath.exp(-2j * math.pi * k / n) for k, v in enumerate(tab)) * 2 / n
        s = math.sin(math.pi / n) / (math.pi / n)
        t0, period = g
        # position: the transfer at request k reads item p_k = (p_ref + k - k_ref) mod n into the hold
        # register; it is output from request k + 1 on: u(t) = p_ref + (t - t0 - (k_ref + 1) P) / P
        k_ref = 0 if self.t_sync < t0 else int(math.floor((self.t_sync - t0) / period)) + 1
        p_ref = (ch.init - ch.txnum) % n
        return dict(t0=t0, period=period, n=n, c=c1 * s / BIAS_COUNTS_PER_V, k_ref=k_ref, p_ref=p_ref,
                    freq=1.0 / (n * period), table=tab)

    def generator(self, times):
        """Analytic generator voltage g(t) (volts) at the times; zeros when the DAC is silent."""
        if self.gen is None:
            self.gen = self._gen_epoch()
        e = self.gen
        if not e:
            return [0j] * len(times)
        out = []
        n, P = e['n'], e['period']
        base = e['t0'] + (e['k_ref'] + 1) * P
        for t in times:
            u = e['p_ref'] + (t - base) / P
            out.append(e['c'] * cmath.exp(2j * math.pi * (u - 0.5) / n))
        return out

    def frequency(self):
        if self.gen is None:
            self.gen = self._gen_epoch()
        return self.gen['freq'] if self.gen else 0.0

    def front_end(self):
        """Gain codes and range index from the GPIO outputs (fn_0800b164, fn_0800af58, fn_080093b8)."""
        pa, pc = self.m.gpio_out(GPIOA), self.m.gpio_out(GPIOC)
        b = lambda v, k: (v >> k) & 1
        c5 = b(pc, 0) << 2 | b(pc, 1) << 1 | b(pc, 2)
        c6 = b(pa, 1) << 2 | b(pa, 2) << 1 | b(pa, 3)
        c8 = 3 - (b(pc, 3) << 1 | b(pa, 0))
        return c5, c6, c8

    # ------------------------------------------------------------------ DMA engine
    def _source_of(self, c, ch):
        src = REQ.get((c, ch.x))
        if src is None:
            return None
        if src.startswith('adc'):
            i = int(src[3]) - 1
            return src if self.adc[i]['r'].get(0x08, 0) & 0x100 else None
        return src if self.dac['ctrl'] & 0x1000 else None

    def _serve(self, c, x, t0, period, k_lo, k_hi, held=None):
        """Requests k_lo..k_hi of the grid t0 + k * period to channel x of controller c; held = the
        value of the held request served at t0 (one item; None for the DAC)."""
        ch = self.dma[c][x - 1]
        n = k_hi - k_lo + 1
        if n <= 0:
            return
        if not ch.on or ch.txnum == 0 or not self.clock_on('dma%d' % (c + 1)):
            self.stats['held'][c][x - 1] += n
            ch.pending = True
            return
        init = ch.init or 0x10000
        total = n if ch.circ else min(n, ch.txnum)
        ch.pending = total < n              # requests after the last item stay pending (held)
        self.stats['held'][c][x - 1] += n - total
        self.stats['transfers'][c][x - 1] += total
        # flags: TXNUM values after each transfer
        cnt0 = ch.txnum
        half = init >> 1
        if ch.circ:
            # transfer j (1-based) leaves count (cnt0 - j) mod init (0 -> TC, then reload)
            tc = total >= cnt0
            ht = (cnt0 > half and total >= cnt0 - half) or (total >= cnt0 + (init - half))
            end_count = (cnt0 - total) % init
            if end_count == 0:
                end_count = init
        else:
            tc = total == cnt0
            ht = cnt0 > half and cnt0 - total <= half
            end_count = cnt0 - total
        src = REQ[(c, x)]
        msz, psz = ch.size(10), ch.size(8)
        to_mem = not ch.cfg & 0x10
        minc = bool(ch.cfg & 0x80)
        # items: j = 0..total-1 at request k_lo + j, address offset done + j (wrapping at init in
        # circular mode, the reload restarting at the base addresses)
        if to_mem:
            first = max(0, total - init) if minc or ch.circ else total - 1
            js = list(range(first, total))
            if held is not None:
                vals = [held]
            elif src.startswith('adc'):
                i = int(src[3]) - 1
                sdt = self._adc_grid(i)
                sdt = sdt[2] if sdt else 0.0
                self.idx = [ch.done + j for j in js]
                try:
                    vals = self._adc_samples(i, [t0 + (k_lo + j) * period - sdt for j in js])
                finally:
                    self.idx = None
                self.adc[i]['dat'] = vals[-1]
            else:
                self.m.violation('DMA%d ch%d peripheral to memory from %s not modelled' % (c + 1, x, src))
                return
            mask = (1 << 8 * min(psz, msz)) - 1
            fmt = {1: 'B', 2: 'H', 4: 'I'}[msz]
            uc = self.m.uc
            maddr = ch.maddr
            if SRAM_LO <= maddr and maddr + init * msz <= SRAM_HI:
                # a buffer inside SRAM (plain memory): uc.mem_write calls no hook and no mmio callback,
                # so only the bytes in the end matter: the items (js consecutive, at most init of them)
                # are one run of addresses, or two where a circular buffer wraps to its base;
                # without MINC every item goes to the base and the last one stays
                ms = [v & mask for v in vals[:len(js)]]
                if ms and not minc:
                    uc.mem_write(maddr, struct.pack('<' + fmt, ms[-1]))
                elif ms:
                    s0 = ch.done + js[0]
                    if ch.circ:
                        s0 %= init
                        k = min(len(ms), init - s0)
                    else:
                        k = len(ms)
                    uc.mem_write(maddr + s0 * msz, struct.pack('<%d%s' % (k, fmt), *ms[:k]))
                    if k < len(ms):
                        uc.mem_write(maddr, struct.pack('<%d%s' % (len(ms) - k, fmt), *ms[k:]))
            else:
                run_addr, run = None, []
                for j, v in zip(js, vals):
                    off = ((ch.done + j) % init if ch.circ else ch.done + j) if minc else 0
                    addr = ch.maddr + off * msz
                    if run_addr is not None and addr == run_addr + len(run) * msz:
                        run.append(v & mask)
                        continue
                    if run:
                        uc.mem_write(run_addr, struct.pack('<%d%s' % (len(run), fmt), *run))
                    run_addr, run = addr, [v & mask]
                if run:
                    uc.mem_write(run_addr, struct.pack('<%d%s' % (len(run), fmt), *run))
        else:
            if ch.paddr != DAC + 0x08 or src != 'dac1':
                self.m.violation('DMA%d ch%d memory to 0x%08X not modelled' % (c + 1, x, ch.paddr))
                return
            def item(j):
                off = ((ch.done + j) % init if ch.circ else ch.done + j) if minc else 0
                raw = bytes(self.m.uc.mem_read(ch.maddr + off * msz, msz))
                return int.from_bytes(raw, 'little') & 0xFFF
            if total >= 2:
                self.dac['dato'] = item(total - 2)
            else:
                self.dac['dato'] = self.dac['dhr']
            self.dac['dhr'] = item(total - 1)
        ch.done = (ch.done + total) % init if ch.circ else ch.done + total
        ch.txnum = end_count
        bit = 4 * (x - 1)
        f = 0
        if ht:
            f |= 4
        if tc:
            f |= 2
        if f:
            self.flags[c] |= (f | 1) << bit
            self.m.irq_check()
        if not ch.circ and ch.txnum == 0:
            ch.cfg &= ~1                    # manual 8.5.5: keeps zero and resets the channel enable

    def _serve_held(self, c, ch):
        """A channel enabled while its peripheral's request is held: one transfer at once."""
        src = self._source_of(c, ch)
        ch.pending = False
        if src is None or ch.txnum == 0:
            return
        now = self.m.now()
        self.idx = [ch.done]                # the held conversion becomes item ch.done (0 after the enable)
        try:
            held = self._adc_dat(int(src[3]) - 1, now) if src.startswith('adc') else None
        finally:
            self.idx = None
        self._serve(c, ch.x, now, 0.0, 0, 0, held=held)

    def _drop_request(self, src):
        self.dma[REQ_CH[src][0]][REQ_CH[src][1] - 1].pending = False

    def _channel_grid(self, c, ch):
        cache = self._grid_cache()
        key = (c, ch.x)
        if key in cache:
            return cache[key]
        g = cache[key] = self._channel_grid_calc(c, ch)
        return g

    def _channel_grid_calc(self, c, ch):
        src = self._source_of(c, ch)
        if src is None:
            return None
        if src == 'dac1':
            return self._dac_grid()
        g = self._adc_grid(int(src[3]) - 1)
        return (g[0], g[1]) if g else None

    def _dma_check(self, c, ch):
        m = self.m
        if ch.cfg & 0x4000:
            m.violation('DMA%d ch%d MEM2MEM not modelled' % (c + 1, ch.x))
            return False
        if REQ.get((c, ch.x)) is None:
            m.violation('DMA%d ch%d: request source not modelled' % (c + 1, ch.x))
            return False
        return True

    def _dma_write(self, c, a, size, value):
        m = self.m
        base = DMA1 if c == 0 else DMA2
        off = (a - base) & ~3
        if size != 4:
            value = _merge(0, a, size, value)
        if off == 0x00:
            m.violation('DMA%d INTSTS written' % (c + 1))
            return
        if off == 0x04:
            self.flags[c] &= ~value
            m.irq_check()
            return
        if off == 0xA8:
            if value & 1:
                m.violation('DMA%d CHMAPEN: channel map not modelled' % (c + 1))
            return
        if not 0x08 <= off < 0xA8:
            m.violation('DMA%d register +0x%X not modelled' % (c + 1, off))
            return
        x = (off - 0x08) // 20 + 1
        r = (off - 0x08) % 20
        ch = self.dma[c][x - 1]
        if r == 0:
            if ch.on:
                if not value & 1:
                    ch.cfg &= ~1
                    self.gen = None
            else:
                if value & 1:
                    tmp = Channel(c, x)
                    tmp.cfg = value
                    if not self._dma_check(c, tmp):
                        return
                    ch.done = 0
                    if ch.txnum == 0:                 # manual silent: nothing to transfer, no flag
                        self.log.append(('dma-enabled-at-txnum-0', m.now(), c + 1, x))
                ch.cfg = value & 0x7FFF
                self.gen = None
                if ch.on and ch.pending:
                    self._serve_held(c, ch)
            m.irq_check()
            return
        if r == 0x10:
            ch.chsel = value & 0x3F
            return
        if ch.on:
            self.log.append(('dma-write-while-enabled', m.now(), c + 1, x, r, value))
            return
        if r == 0x04:
            ch.txnum = ch.init = value & 0xFFFF
        elif r == 0x08:
            ch.paddr = value
        elif r == 0x0C:
            ch.maddr = value

    def _dma_read(self, c, a, size):
        base = DMA1 if c == 0 else DMA2
        off = (a - base) & ~3
        if off == 0x00:
            v = self.flags[c]
        elif off == 0x04 or off == 0xA8:
            v = 0
        else:
            x = (off - 0x08) // 20 + 1
            r = (off - 0x08) % 20
            ch = self.dma[c][x - 1]
            v = (ch.cfg, ch.txnum, ch.paddr, ch.maddr, ch.chsel)[r // 4]
        return v >> 8 * (a & 3)

    # ------------------------------------------------------------------ time
    def sync(self, now=None):
        """Bring every conversion, trigger and DMA transfer up to the emulated time now."""
        m = self.m
        if now is None:
            now = m.now()
        t_a = self.t_sync
        if now <= t_a:
            return
        if not self.gen:
            self.gen = self._gen_epoch()           # the generator as it stands at t_a
        cache, dma = self._grid_cache(), self.dma     # no step of this loop changes the cache key
        for key in REQ:
            c, x = key
            ch = dma[c][x - 1]
            g = cache[key] if key in cache else self._channel_grid(c, ch)
            if g is None:
                continue
            w = _grid_window(g[0], g[1], t_a, now)
            if w:
                self._serve(c, x, g[0], g[1], w[0], w[1])
        cache = self._grid_cache()
        for i in range(4):
            ad = self.adc[i]
            g = cache[i] if i in cache else self._adc_grid(i)
            if g is None:
                continue
            if g[3]:                                      # single software conversion
                if t_a < g[0] <= now:
                    ad['dat'] = self._adc_samples(i, [g[0] - g[2]])[0]
                    ad['sts'] |= 0x32
                    ad['running'] = False
                    self._gv += 1
                    cache = self._grid_cache()
                continue
            if _grid_window(g[0], g[1], t_a, now):
                ad['sts'] |= 0x32
        self.t_sync = now

    def next_event(self, m, now):
        """The time of the next DMA flag whose interrupt is enabled."""
        best = None
        for c in range(2):
            for ch in self.dma[c]:
                if not ch.on or not ch.cfg & 6:
                    continue
                g = self._channel_grid(c, ch)
                if g is None:
                    continue
                t0, period = g
                k = 0 if self.t_sync < t0 else int(math.floor((self.t_sync - t0) / period)) + 1
                while t0 + k * period <= self.t_sync:
                    k += 1
                init = ch.init or 0x10000
                steps = []
                if ch.cfg & 2:
                    steps.append(ch.txnum)
                if ch.cfg & 4:
                    h = ch.txnum - (init >> 1)
                    steps.append(h if h > 0 else (h + init if ch.circ else None))
                steps = [s for s in steps if s]
                if not steps:
                    continue
                t = t0 + (k + min(steps) - 1) * period
                best = t if best is None else min(best, t)
        return best

    def tick(self, m, now):
        self.sync(now)

    def irqs(self, m):
        out = []
        for c in range(2):
            f = self.flags[c]
            for ch in self.dma[c]:
                bit = 4 * (ch.x - 1)
                if (f >> bit) & (ch.cfg & 0xE):
                    out.append((IRQ_DMA1 if c == 0 else IRQ_DMA2)[ch.x - 1])
        return out

    # ------------------------------------------------------------------ RCC resets
    def _rcc_write(self, a, size, value):
        w = a & ~3
        new = _merge(self.rst[w], a, size, value)
        rise = new & ~self.rst[w]
        self.rst[w] = new
        now = self.m.now()
        if w == RCC_APB2PRST and rise & (1 << 11):
            self.tim[TIM1].reset()
        if w == RCC_APB1PRST and rise & (1 << 4):
            self.tim[TIM6].reset()
        if w == RCC_APB1PRST and rise & (1 << 29):
            self.dac = self._dac_reset()
            self._drop_request('dac1')
        if w == RCC_AHBPRST:
            for i in range(4):
                if rise & ADC_RSTEN[i]:
                    self.adc[i] = self._adc_reset()
                    self._drop_request('adc%d' % (i + 1))
        self.gen = None
        self.t_sync = max(self.t_sync, now)

    # ------------------------------------------------------------------ register access
    def read(self, m, a, size):
        self.sync()
        if DMA1 <= a < DMA1 + 0x400:
            return self._dma_read(0, a, size)
        if DMA2 <= a < DMA2 + 0x400:
            return self._dma_read(1, a, size)
        for i, b in enumerate(ADC_BASES):
            if b <= a < b + 0x400:
                return self._adc_read(i, a, size)
        if TIM1 <= a < TIM1 + 0x400:
            return self._tim_read(TIM1, a, size)
        if TIM6 <= a < TIM6 + 0x400:
            return self._tim_read(TIM6, a, size)
        if DAC <= a < DAC + 0x400:
            return self._dac_read(a, size)
        return self.rst[a & ~3] >> 8 * (a & 3)

    def write(self, m, a, size, value):
        self.sync()
        if TIM1 <= a < TIM1 + 0x400 or any(x <= a < x + 0x400 for x in ADC_BASES):
            now = m.now()
            for i in range(4):                      # DAT keeps the last result of the old set-up
                self.adc[i]['dat'] = self._adc_dat(i, now)
        self._gv += 1                               # _grid_cache: the register state changes here
        if DMA1 <= a < DMA1 + 0x400:
            self._dma_write(0, a, size, value)
        elif DMA2 <= a < DMA2 + 0x400:
            self._dma_write(1, a, size, value)
        elif TIM1 <= a < TIM1 + 0x400:
            self._tim_write(TIM1, a, size, value)
            self.gen = None
        elif TIM6 <= a < TIM6 + 0x400:
            self._tim_write(TIM6, a, size, value)
            self.gen = None
        elif DAC <= a < DAC + 0x400:
            self._dac_write(a, size, value)
        elif RCC_APB2PRST <= a < RCC_APB2PRST + 8 or RCC_AHBPRST <= a < RCC_AHBPRST + 4:
            self._rcc_write(a, size, value)
        else:
            for i, b in enumerate(ADC_BASES):
                if b <= a < b + 0x400:
                    self._adc_write(i, a, size, value)
                    break
        self._gv += 1
        m.irq_check()


class DutSource:
    """A device under test on the front end, as the application's arithmetic assumes it
    (fn_0800a068: Z = R * G6 / G5 * |ADC1| / |ADC2|, theta = phase(ADC1) - phase(ADC2)):
      ADC1 channel 3 (buffer 0x20005A38): mid + k * G[c5] * v(t), v = the generator voltage across
        the DUT (an ideal source: the DUT gets the whole generator voltage);
      ADC2 channel 4 (buffer 0x20005B38): mid + k * G[c6] * R[c8] * i(t), i = v / Z(f): the DUT
        current through the range resistor R[c8] (100 / 1k / 10k / 100k ohm, 0x0802AEEC);
      gains G = 2^code (0x0802AEE4) from the GPIO outputs (MeasurePath.front_end);
      ADC3 channel 1 (buffer 0x20005C38): its signal is not identified (only its peak-to-peak value
        is used, fn_0800b000 steps the auto range down above 250); default the constant adc3
        (mid-scale), or a function adc3(path, times) -> codes;
      ADC4 channel 3 (battery, 0x20005D38): round(supply_v * 4095 / 6.6) (fn_080092cc's scale).
    k (codes per volt) is the same for both channels, so it cancels in Z; default 4095 / 3.3 (a
    3.3 V ADC reference: not proven for this board, the choice only sets the codes the windows of
    fn_0800b20c / fn_0800b000 see). Codes are clipped to 0..4095 and rounded (an ideal 12-bit
    ADC, no noise unless noise_lsb > 0: a fixed pseudo-random sequence, uniform +- noise_lsb).
    kind 'R' (value ohm), 'C' (farad, optional series esr ohm), 'L' (henry, optional series esr),
    or z=callable(f) -> complex ohm."""

    def __init__(self, kind='R', value=1000.0, esr=0.0, z=None, counts_per_volt=4095 / 3.3, mid=2048.0,
                 supply_v=4.0, adc3=2048, noise_lsb=0.0):
        self.kind, self.value, self.esr, self.zf = kind, float(value), float(esr), z
        self.k, self.mid, self.supply_v, self.adc3, self.noise = counts_per_volt, mid, supply_v, adc3, noise_lsb
        self._seed = 12345

    def z(self, f):
        if self.zf is not None:
            return complex(self.zf(f))
        w = 2 * math.pi * f
        if self.kind == 'R':
            return complex(self.value, 0.0)
        if self.kind == 'C':
            return complex(self.esr, -1.0 / (w * self.value)) if w > 0 else complex(1e18, 0)
        if self.kind == 'L':
            return complex(self.esr, w * self.value)
        raise ValueError(self.kind)

    def _noise(self):
        self._seed = (self._seed * 1103515245 + 12345) & 0x7FFFFFFF
        return (self._seed / 0x7FFFFFFF * 2 - 1) * self.noise

    def samples(self, path, adc, channel, times):
        if adc == 4:
            return int(round(self.supply_v * 4095 / 6.6))
        if adc == 3:
            return self.adc3 if isinstance(self.adc3, int) else self.adc3(path, times)
        g = path.generator(times)
        c5, c6, c8 = path.front_end()
        f = path.frequency()
        if adc == 1:
            scale = self.k * GAIN[c5]
            vals = [self.mid + scale * x.real for x in g]
        elif adc == 2:
            if f <= 0:
                return int(self.mid)
            zz = self.z(f)
            scale = self.k * GAIN[c6] * RANGE_OHM[c8]
            vals = [self.mid + scale * (x / zz).real for x in g]
        else:
            return int(self.mid)
        if self.noise:
            vals = [v + self._noise() for v in vals]
        return [int(round(v)) for v in vals]
