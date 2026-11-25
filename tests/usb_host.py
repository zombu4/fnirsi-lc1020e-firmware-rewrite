"""usb_host.py - the N32G455 USB full-speed device peripheral and a USB host, for the emulator tests.

Used with tests/meter_model.py (Meter.set_timing() is required: the host drives the chip in emulated
time and the device raises IRQ 20 / IRQ 42 through the model's NVIC). Not a test by itself. The
firmware under test is our build (meter_model.OWN_BIN / OWN_ELF, Meter.load_own()).

Device (N32G45x user manual V3.5.0 chapter 19; facts by section):
  Registers 0x40005C00: USB_EP0..7 +0x00..+0x1C, USB_CTRL +0x40 (reset 0x0003: PD, FRST), USB_STS
  +0x44, USB_FN +0x48, USB_ADDR +0x4C, USB_BUFTAB +0x50; half-word or word access (19.5). Packet
  memory (PMA) 0x40006000..0x400063FF: 512 bytes, the CPU reads and writes 16 bits at 32-bit
  aligned addresses only (19.4.1: "can't be 8-bit nor 32-bit"): PMA byte offset k is at CPU address
  0x40006000 + 2 k (k even). Buffer table at USB_BUFTAB (8-byte aligned), 8 bytes per endpoint
  register n: ADDRn_TX, COUNTn_TX, ADDRn_RX, COUNTn_RX (19.6; local addresses, bit 0 must be 0);
  receive buffer size from BLSIZE / NUM_BLK (Table 19-8: BLSIZE 0 -> 2 x NUM_BLK bytes, 0 not
  allowed; BLSIZE 1 -> 32 x (NUM_BLK + 1), NUM_BLK >= 16 reserved).
  USB_EPn write semantics (19.5.2): CTRS_RX (15) / CTRS_TX (7) only cleared by writing 0;
  DATTOG_RX (14), STS_RX (13:12), DATTOG_TX (6), STS_TX (5:4) toggled by writing 1; SETUP (11)
  read only; EP_TYPE (10:9), EP_KIND (8), EPADDR (3:0) read / write.
  USB_STS (19.5.4): PMAO, ERROR, WKUP, SUSPD, RST, SOF, ESOF (14..8) cleared by writing 0, CTRS
  (15), DIR (4), EP_ID (3:0) read only and derived here from the endpoint registers: CTRS = any
  CTRS_RX / CTRS_TX set, EP_ID = the lowest endpoint register number with one set (no isochronous
  or double-buffered endpoint exists in this model), DIR = its CTRS_RX.
  USB_LP (IRQ 20) is asserted while USB_CTRL bits 15..8 AND the USB_STS flags 15..8 are not 0;
  USB_HP (IRQ 19) is never asserted (only isochronous / double-buffered bulk, not modelled).
  The USB wake-up (IRQ 42) comes from EXTI line 18: EXTI 0x40010400 IMASK / EMASK / RT_CFG /
  FT_CFG / SWIE / PEND (+0..+0x14, PEND cleared by writing 1); a host resume while USB_CTRL.FSUSPD
  is set sets USB_STS.WKUP, clears LP_MODE and sets PEND bit 18 when RT_CFG or FT_CFG bit 18 is set;
  IRQ 42 is asserted while PEND and IMASK bit 18 are both set.
  Transactions (19.4.4): IN on a VALID endpoint sends COUNTn_TX bytes with DATATTOG_TX as PID, then
  (host ACK) toggles DATTOG_TX, STS_TX = NAK, CTRS_TX = 1; OUT / SETUP on a VALID (SETUP: any but
  DISABLED) endpoint store the data and COUNTn_RX, then toggle DATTOG_RX, STS_RX = NAK, CTRS_RX = 1;
  SETUP first clears DATTOG_RX and sets DATTOG_TX and sets the SETUP bit (cleared by the next OUT);
  a SETUP while CTRS_RX is still 1 is dropped without handshake (19.4.4 note 3); data larger than
  the receive buffer: STALL and PMAO, no CTRS (19.4.4); an OUT with data while STATUS_OUT
  (EP_KIND of a control endpoint) is set: STALL and ERROR; an OUT whose PID differs from
  DATTOG_RX is acknowledged and dropped (USB 2.0 8.6.4: a retransmission).
  Reset (19.4.5): a USB bus reset or USB_CTRL.FRST = 1 resets every endpoint register except its
  CTRS bits and USB_ADDR (EFUC included) and sets USB_STS.RST. The device answers only while the
  USB clock is on (RCC_APB1PCLKEN bit 23), PD = 0, FRST = 0, the pull-up (bit 28 of 0x40001820) is
  on, USB_ADDR.EFUC = 1 and the token's address equals USB_ADDR.ADDR.
  Frame start (19.5.5): every emulated millisecond while the host runs the bus: SOF, FNUM + 1,
  LOCK after two; while the host suspends the bus: ESOF (LSTSOF counts) and after three SUSPD.

Strict choices where the manual does not say how the hardware behaves (each a violation, which
ends the run, unless said otherwise):
  - any access to the USB registers or the PMA while the USB clock is off (19.3 note 2 says they
    "can only be operated when the USB module clock is enabled");
  - PMA access that is not 16 bits at a 32-bit aligned address; USB register access of 8 bits or at
    a half-word offset; a reserved USB register address; a write to USB_FN;
  - a 1 written to a reserved bit of USB_EPn (31:16), USB_CTRL (31:16, 7:5), USB_STS (31:16, 7:5),
    USB_ADDR (31:8), USB_BUFTAB (31:16, 2:0) ("the reset value must be maintained");
  - USBEN set while RCC_CFG USBPRES is not 11 (PLL / 3: 48 MHz from the 144 MHz PLL) or the PLL
    is not on (RCC_CTRL bit 24) (manual: USBPRES "must be valid before enabling the USB clock");
  - USB_CTRL.FRST cleared less than 1 us (datasheet table 4-41 tSTARTUP) after PD was cleared;
  - RESUM set (remote wake-up: not modelled) or LP_MODE set without FSUSPD (19.5.3 note);
  - a write to 0x40001820 that changes any bit but bit 28 (19.4.5.1.1 note 1);
  - an EXTI SWIE write (software interrupts not modelled);
  - a transaction on an isochronous or double-buffered endpoint (not modelled: the run stops);
  - a buffer table entry or buffer outside the 512 bytes, an address with bit 0 set, COUNTn_TX
    reserved bits set, a receive size of NUM_BLK 0 with BLSIZE 0 or a reserved one, two endpoint
    registers enabled for one endpoint address;
  - the PMA content after a chip reset is not stated: it is filled with 0x5A, so data the firmware
    did not write never looks like zeros;
  - USB_EPn reads its reset value 0 after a chip reset; the pull-up word reads 0 (its reset value
    is not stated).
Not modelled: double-buffered and isochronous endpoints, USB_HP, remote wake-up, LP_MODE power
states, bus errors (CRC, bit stuffing) and the APB1 clock limit (> 8 MHz).

Host (USB 2.0 chapter 9 timings, strict): attach debounce 100 ms, bus reset 10 ms then 10 ms
recovery, SET_ADDRESS recovery 2 ms; a control transfer's data packets within 500 ms each and the
status stage within 50 ms (500 ms when it follows a data stage); NAKed tokens retried every
nak_gap (default 20 us of emulated time); a token without handshake retried, three in a row are an
error; a data PID that does not match the host's toggle, a packet longer than wMaxPacketSize, an IN
data stage longer than wLength: UsbError. GET_DESCRIPTOR(device) at address 0 asks for 64 bytes
and goes to the status stage after the first packet (as Windows does), then resets the bus again.
"""
import struct

USB_BASE, USB_END = 0x40005C00, 0x40006000
PMA_BASE, PMA_END = 0x40006000, 0x40006400
PMA_SIZE = 512
PULLUP, PULLUP_BIT = 0x40001820, 1 << 28
RCC_CTRL, RCC_CFG, RCC_APB1EN, USBEN = 0x40021000, 0x40021004, 0x4002101C, 1 << 23
EXTI, EXTI_LINE18 = 0x40010400, 1 << 18
IRQ_USB_LP, IRQ_USB_WKUP = 20, 42
T_STARTUP = 1e-6                      # datasheet table 4-41

CTRS_RX, DTOG_RX, STAT_RX, SETUP_BIT = 0x8000, 0x4000, 0x3000, 0x0800
EP_TYPE, EP_KIND, CTRS_TX, DTOG_TX, STAT_TX, EA = 0x0600, 0x0100, 0x0080, 0x0040, 0x0030, 0x000F
DISABLED, STALL, NAK, VALID = 0, 1, 2, 3
T_BULK, T_CONTROL, T_ISO, T_INTERRUPT = 0, 1, 2, 3


class UsbError(Exception):
    pass


class UsbStall(UsbError):
    pass


class UsbDevice:
    """The chip's USB peripheral (and EXTI line 18, the pull-up word, RCC_APB1PCLKEN): attach to a
    Meter that has timing. The host side drives it through host_setup / host_out / host_in."""

    def __init__(self, meter):
        if not meter.timing:
            raise RuntimeError('UsbDevice needs Meter.set_timing() (interrupts and emulated time)')
        self.ranges = [(USB_BASE, USB_END), (PMA_BASE, PMA_END), (PULLUP, PULLUP + 4),
                       (RCC_APB1EN, RCC_APB1EN + 4), (EXTI, EXTI + 0x18)]
        self.log = []
        self.bus = 'off'
        meter.attach(self)

    # ---- chip reset ----
    def reset(self, m):
        self.ep = [0] * 8
        self.ctrl = 0x0003
        self.sts = 0
        self.fnum, self.lstsof, self.lock, self.sofs = 0, 0, 0, 0
        self.addr = 0
        self.buftab = 0
        self.pma = bytearray(b'\x5a' * PMA_SIZE)
        self.pullup = 0
        self.exti = dict(imask=0, emask=0, rt=0, ft=0, pend=0)
        self.t_pd_clear = None
        self.bus = 'off'                    # the host must attach again after a chip reset
        self.sof_next = None
        self.esofs = 0
        self.log.append(('chip-reset', m.start_no))

    # ---- state ----
    def clock_on(self, m):
        return bool(m.st['regs'].get(RCC_APB1EN, 0) & USBEN)

    def module_on(self, m):
        return self.clock_on(m) and not self.ctrl & 3

    def attached(self, m):
        """The host sees the device: USB clock, PD = 0, FRST = 0 and the D+ pull-up."""
        return self.module_on(m) and bool(self.pullup & PULLUP_BIT)

    def full_sts(self):
        v = self.sts & 0x7F00
        for n in range(8):
            if self.ep[n] & (CTRS_RX | CTRS_TX):
                v |= 0x8000 | n | (0x10 if self.ep[n] & CTRS_RX else 0)
                break
        return v

    def irqs(self, m):
        out = []
        if self.ctrl & self.full_sts() & 0xFF00:
            out.append(IRQ_USB_LP)
        if self.exti['pend'] & self.exti['imask'] & EXTI_LINE18:
            out.append(IRQ_USB_WKUP)
        return out

    def _usb_reset_state(self, m, why):
        self.ep = [r & (CTRS_RX | CTRS_TX) for r in self.ep]
        self.addr = 0
        self.sts |= 0x0400                  # RST
        self.lock, self.sofs, self.esofs = 0, 0, 0
        self.log.append(('usb-reset', why, m.now()))
        m.irq_check()

    # ---- CPU side ----
    def read(self, m, a, size):
        regs = m.st['regs']
        if a == RCC_APB1EN and size == 4:
            return regs.get(RCC_APB1EN, 0)
        if a == PULLUP and size == 4:
            return self.pullup
        if PULLUP <= a < PULLUP + 4 or RCC_APB1EN <= a < RCC_APB1EN + 4:
            w = self.pullup if a < PULLUP + 4 else regs.get(RCC_APB1EN, 0)
            return w >> 8 * (a & 3)
        if EXTI <= a < EXTI + 0x18:
            if size != 4 or a & 3:
                m.violation('EXTI 0x%08X read with %d bytes' % (a, size))
                return 0
            return self.exti[('imask', 'emask', 'rt', 'ft', 'swie', 'pend')[(a - EXTI) // 4]] \
                if (a - EXTI) // 4 != 4 else 0
        if not self.clock_on(m):
            m.violation('USB 0x%08X read with the USB clock off' % a)
            return 0
        if PMA_BASE <= a < PMA_END:
            if size != 2 or a & 3:
                m.violation('PMA 0x%08X read with %d bytes (16 bits at 32-bit aligned addresses only)'
                            % (a, size))
                return 0
            k = (a - PMA_BASE) // 2
            return self.pma[k] | self.pma[k + 1] << 8
        off = a - USB_BASE
        if size == 1 or off & 3:
            m.violation('USB register 0x%08X read with %d bytes' % (a, size))
            return 0
        if off < 0x20:
            return self.ep[off // 4]
        if off == 0x40:
            return self.ctrl
        if off == 0x44:
            return self.full_sts()
        if off == 0x48:
            dp = 1 if self.bus in ('active', 'suspended', 'off') and self.pullup & PULLUP_BIT else 0
            return self.fnum | self.lstsof << 11 | self.lock << 13 | dp << 15
        if off == 0x4C:
            return self.addr
        if off == 0x50:
            return self.buftab
        m.violation('USB reserved register 0x%08X read' % a)
        return 0

    def write(self, m, a, size, value):
        regs = m.st['regs']
        value &= 0xFFFFFFFF
        if PULLUP <= a < PULLUP + 4:
            sh = 8 * (a & 3)
            mask = ((1 << 8 * size) - 1) << sh
            new = (self.pullup & ~mask) | ((value << sh) & mask)
            if (new ^ self.pullup) & ~PULLUP_BIT:
                m.violation('0x40001820 written 0x%08X: a bit other than bit 28 changed' % new)
                return
            if (new ^ self.pullup) & PULLUP_BIT:
                self.log.append(('pullup', 1 if new & PULLUP_BIT else 0, m.now()))
                if not new & PULLUP_BIT:
                    self.bus = 'off'
            self.pullup = new
            return
        if RCC_APB1EN <= a < RCC_APB1EN + 4:
            old = regs.get(RCC_APB1EN, 0)
            sh = 8 * (a & 3)
            mask = ((1 << 8 * size) - 1) << sh
            new = (old & ~mask) | ((value << sh) & mask)
            if new & USBEN and not old & USBEN:
                cfg, ctl = regs.get(RCC_CFG, 0), regs.get(RCC_CTRL, 0)
                if (cfg >> 22) & 3 != 3:
                    m.violation('USBEN set with RCC_CFG USBPRES %d (must be 3: PLL / 3 = 48 MHz)'
                                % ((cfg >> 22) & 3))
                    return
                if not ctl & (1 << 24):
                    m.violation('USBEN set with the PLL off (RCC_CTRL 0x%08X)' % ctl)
                    return
                self.log.append(('usben', 1, m.now()))
            regs[RCC_APB1EN] = new
            return
        if EXTI <= a < EXTI + 0x18:
            if size != 4 or a & 3:
                m.violation('EXTI 0x%08X written with %d bytes' % (a, size))
                return
            r = (a - EXTI) // 4
            if r == 4:
                if value:
                    m.violation('EXTI_SWIE written 0x%08X (software interrupts not modelled)' % value)
                return
            if r == 5:
                self.exti['pend'] &= ~value
                if value & EXTI_LINE18:
                    self.log.append(('exti18-cleared', m.now()))
                m.irq_check()
                return
            self.exti[('imask', 'emask', 'rt', 'ft')[r]] = value
            m.irq_check()
            return
        if not self.clock_on(m):
            m.violation('USB 0x%08X written with the USB clock off' % a)
            return
        if PMA_BASE <= a < PMA_END:
            if size != 2 or a & 3:
                m.violation('PMA 0x%08X written with %d bytes (16 bits at 32-bit aligned addresses only)'
                            % (a, size))
                return
            k = (a - PMA_BASE) // 2
            self.pma[k], self.pma[k + 1] = value & 0xFF, (value >> 8) & 0xFF
            return
        off = a - USB_BASE
        if size == 1 or off & 3:
            m.violation('USB register 0x%08X written with %d bytes' % (a, size))
            return
        if off < 0x20:
            if value & 0xFFFF0000:
                m.violation('USB_EP%d reserved bits written: 0x%08X' % (off // 4, value))
                return
            n = off // 4
            old = self.ep[n]
            new = (value & (EP_TYPE | EP_KIND | EA)) | (old & SETUP_BIT)
            new |= old & value & (CTRS_RX | CTRS_TX)
            new |= (old ^ value) & (DTOG_RX | STAT_RX | DTOG_TX | STAT_TX)
            self.ep[n] = new
            m.irq_check()
            return
        if off == 0x40:
            if value & 0xFFFF00E0:
                m.violation('USB_CTRL reserved bits written: 0x%08X' % value)
                return
            old = self.ctrl
            now = m.now()
            if value & 0x10:
                m.violation('USB_CTRL.RESUM set (remote wake-up not modelled)')
                return
            if value & 0x04 and not value & 0x08:
                m.violation('USB_CTRL.LP_MODE set without FSUSPD (19.5.3 note)')
                return
            if old & 2 and not value & 2:
                self.t_pd_clear = now
            if old & 1 and not value & 1:
                if self.t_pd_clear is None or value & 2 or now - self.t_pd_clear < T_STARTUP:
                    m.violation('USB_CTRL.FRST cleared %s after PD was cleared (tSTARTUP 1 us)'
                                % ('before or with PD' if self.t_pd_clear is None or value & 2
                                   else '%.3f us' % ((now - self.t_pd_clear) * 1e6)))
                    return
            if not old & 2 and value & 2:
                self.bus = 'off'
                self.log.append(('usb-power-down', now))
            self.ctrl = value & 0xFF1F
            if value & 1 and not old & 1:
                self._usb_reset_state(m, 'FRST')
            m.irq_check()
            return
        if off == 0x44:
            # The bootloader driver that enumerates on the meter clears flags with 0xFBFF / 0xEFFF
            # (bootloader/src fn_08002ca4: 1 in every other bit, reserved bits 7..5 included), so
            # 1s in the reserved low bits are written without effect; bits 31..16 stay a violation.
            if value & 0xFFFF0000:
                m.violation('USB_STS reserved bits written: 0x%08X' % value)
                return
            self.sts &= value & 0x7F00
            m.irq_check()
            return
        if off == 0x48:
            m.violation('USB_FN written 0x%08X (read only)' % value)
            return
        if off == 0x4C:
            if value & 0xFFFFFF00:
                m.violation('USB_ADDR reserved bits written: 0x%08X' % value)
                return
            self.addr = value
            self.log.append(('addr', value, m.now()))
            return
        if off == 0x50:
            if value & 0xFFFF0007:
                m.violation('USB_BUFTAB reserved bits written: 0x%08X' % value)
                return
            self.buftab = value
            return
        m.violation('USB reserved register 0x%08X written (0x%08X)' % (a, value))

    # ---- bus side (called by UsbHost between slices) ----
    def next_event(self, m, now):
        return self.sof_next if self.bus in ('active', 'suspended') else None

    def tick(self, m, now):
        while self.bus in ('active', 'suspended') and self.sof_next is not None and now >= self.sof_next:
            self.sof_next += 1e-3
            if not self.module_on(m):
                continue
            if self.bus == 'active':
                self.sts |= 0x0200                  # SOF
                self.fnum = (self.fnum + 1) & 0x7FF
                self.lstsof = 0
                self.sofs += 1
                if self.sofs >= 2:
                    self.lock = 1
            elif self.esofs < 3:
                self.sts |= 0x0100                  # ESOF
                self.lstsof = min(3, self.lstsof + 1)
                self.esofs += 1
                if self.esofs == 3:
                    self.sts |= 0x0800              # SUSPD
                    self.log.append(('suspend-detected', now))

    def bus_reset(self, m):
        self.bus = 'reset'
        self.sof_next = None
        if self.module_on(m):
            self._usb_reset_state(m, 'bus')

    def bus_run(self, m):
        if self.bus != 'active':
            self.sof_next = m.now() + 1e-3
        self.bus = 'active'
        self.esofs = 0

    def bus_suspend(self, m):
        self.bus = 'suspended'
        self.esofs = 0
        if self.sof_next is None:
            self.sof_next = m.now() + 1e-3

    def bus_resume(self, m):
        if self.module_on(m) and self.ctrl & 0x08:
            self.sts |= 0x1000                      # WKUP
            self.ctrl &= ~0x04                      # LP_MODE reset by the wake-up event
            if (self.exti['rt'] | self.exti['ft']) & EXTI_LINE18:
                self.exti['pend'] |= EXTI_LINE18
            self.log.append(('wakeup', m.now()))
            m.irq_check()

    def _bt(self, m, n):
        b = self.buftab & 0xFFF8
        if b + 8 * n + 8 > PMA_SIZE:
            m.violation('buffer table entry %d at 0x%X outside the PMA' % (n, b + 8 * n))
            return None
        return struct.unpack_from('<4H', self.pma, b + 8 * n)

    def _rx_size(self, m, cnt):
        bl, nb = cnt >> 15, (cnt >> 10) & 0x1F
        if bl:
            if nb >= 16:
                m.violation('COUNT_RX 0x%04X: reserved NUM_BLK with BLSIZE 1' % cnt)
                return None
            return 32 * (nb + 1)
        if nb == 0:
            m.violation('COUNT_RX 0x%04X: NUM_BLK 0 with BLSIZE 0 (not allowed)' % cnt)
            return None
        return 2 * nb

    def _ep_for(self, m, addr, epnum):
        """Endpoint register index for a token to (addr, epnum), None when the device does not answer."""
        if not self.attached(m) or self.bus != 'active':
            return None
        if not self.addr & 0x80 or self.addr & 0x7F != addr:
            return None
        hits = [n for n in range(8) if self.ep[n] & EA == epnum and self.ep[n] & (STAT_RX | STAT_TX)]
        if len(hits) > 1:
            m.violation('endpoint registers %r all enabled for endpoint %d' % (hits, epnum))
            return None
        if not hits:
            return None
        n = hits[0]
        t = (self.ep[n] & EP_TYPE) >> 9
        if t == T_ISO or (t == T_BULK and self.ep[n] & EP_KIND):
            m._stop('model: isochronous / double-buffered endpoint %d not modelled' % n)
            return None
        return n

    def _rx_store(self, m, n, data):
        bt = self._bt(m, n)
        if bt is None:
            return 'TIMEOUT'
        addr_rx, cnt_rx = bt[2], bt[3]
        size = self._rx_size(m, cnt_rx)
        if size is None:
            return 'TIMEOUT'
        if addr_rx & 1 or addr_rx + size > PMA_SIZE:
            m.violation('EP%d receive buffer 0x%X + %d outside the PMA or odd' % (n, addr_rx, size))
            return 'TIMEOUT'
        if len(data) > size:
            self.sts |= 0x4000                      # PMAO
            self.log.append(('rx-overflow', n, len(data), size))
            m.irq_check()
            return 'STALL'
        self.pma[addr_rx:addr_rx + len(data)] = data
        b = self.buftab & 0xFFF8
        struct.pack_into('<H', self.pma, b + 8 * n + 6, (cnt_rx & 0xFC00) | len(data))
        return None

    def host_setup(self, m, addr, pkt):
        n = self._ep_for(m, addr, 0)
        if n is None:
            return 'TIMEOUT'
        r = self.ep[n]
        if (r & EP_TYPE) >> 9 != T_CONTROL or not r & STAT_RX:
            return 'TIMEOUT'
        if r & CTRS_RX:
            self.log.append(('setup-dropped', n))
            return 'TIMEOUT'
        bad = self._rx_store(m, n, pkt)
        if bad:
            return bad
        r = (r & ~(DTOG_RX | STAT_RX)) | DTOG_TX | SETUP_BIT | CTRS_RX | DTOG_RX | (NAK << 12)
        self.ep[n] = r
        m.irq_check()
        return 'ACK'

    def host_out(self, m, addr, epnum, data, pid):
        n = self._ep_for(m, addr, epnum)
        if n is None:
            return 'TIMEOUT'
        r = self.ep[n]
        st = (r & STAT_RX) >> 12
        if st == DISABLED:
            return 'TIMEOUT'
        if st == STALL:
            return 'STALL'
        if st == NAK:
            return 'NAK'
        if (r & EP_TYPE) >> 9 == T_CONTROL and r & EP_KIND and data:
            self.sts |= 0x2000                      # ERROR
            m.irq_check()
            return 'STALL'
        if pid != (1 if r & DTOG_RX else 0):
            self.log.append(('out-toggle-mismatch', n, pid))
            return 'ACK-IGNORED'
        bad = self._rx_store(m, n, data)
        if bad:
            return bad
        r = (r & ~(STAT_RX | SETUP_BIT)) ^ DTOG_RX
        self.ep[n] = r | CTRS_RX | (NAK << 12)
        m.irq_check()
        return 'ACK'

    def host_in(self, m, addr, epnum):
        n = self._ep_for(m, addr, epnum)
        if n is None:
            return 'TIMEOUT', None, None
        r = self.ep[n]
        st = (r & STAT_TX) >> 4
        if st == DISABLED:
            return 'TIMEOUT', None, None
        if st == STALL:
            return 'STALL', None, None
        if st == NAK:
            return 'NAK', None, None
        bt = self._bt(m, n)
        if bt is None:
            return 'TIMEOUT', None, None
        addr_tx, cnt_tx = bt[0], bt[1]
        if cnt_tx & 0xFC00:
            m.violation('COUNT%d_TX 0x%04X: reserved bits set' % (n, cnt_tx))
            return 'TIMEOUT', None, None
        cnt = cnt_tx & 0x3FF
        if addr_tx & 1 or addr_tx + cnt > PMA_SIZE:
            m.violation('EP%d send buffer 0x%X + %d outside the PMA or odd' % (n, addr_tx, cnt))
            return 'TIMEOUT', None, None
        data = bytes(self.pma[addr_tx:addr_tx + cnt])
        pid = 1 if r & DTOG_TX else 0
        self.ep[n] = ((r & ~STAT_TX) ^ DTOG_TX) | CTRS_TX | (NAK << 4)
        m.irq_check()
        return 'ACK', data, pid


# ---- frames of the control channel (little-endian) ----
FR_SYNC = 0xA5
FR_REQUEST, FR_ANSWER, FR_STREAM, FR_EVENT = 1, 2, 3, 4


def crc16(data, crc=0xFFFF):
    """CRC-16/CCITT-FALSE: polynomial 0x1021, initial 0xFFFF, no reflection, no final XOR."""
    for b in data:
        crc ^= b << 8
        for _ in range(8):
            crc = ((crc << 1) ^ 0x1021) & 0xFFFF if crc & 0x8000 else (crc << 1) & 0xFFFF
    return crc


def make_frame(seq, typ, cmd, payload=b''):
    """sync 0xA5, length (u16: seq .. payload), seq, type, cmd, payload, CRC-16 over length .. payload."""
    body = struct.pack('<H', 3 + len(payload)) + bytes([seq & 0xFF, typ, cmd]) + bytes(payload)
    return bytes([FR_SYNC]) + body + struct.pack('<H', crc16(body))


class FrameParser:
    """Splits a byte stream into frames: resynchronises on 0xA5, checks length (3..515) and CRC;
    bytes skipped while searching are counted in .skipped, frames with a bad CRC in .bad."""

    def __init__(self):
        self.buf = bytearray()
        self.skipped = 0
        self.bad = 0

    def feed(self, data):
        self.buf += data
        out = []
        while True:
            i = self.buf.find(bytes([FR_SYNC]))
            if i < 0:
                self.skipped += len(self.buf)
                self.buf.clear()
                return out
            if i:
                self.skipped += i
                del self.buf[:i]
            if len(self.buf) < 3:
                return out
            ln = self.buf[1] | self.buf[2] << 8
            if not 3 <= ln <= 515:
                self.skipped += 1
                del self.buf[:1]
                continue
            total = 3 + ln + 2
            if len(self.buf) < total:
                return out
            body = bytes(self.buf[1:3 + ln])
            crc = self.buf[3 + ln] | self.buf[4 + ln] << 8
            if crc != crc16(body):
                self.bad += 1
                del self.buf[:1]
                continue
            out.append(dict(seq=body[2], type=body[3], cmd=body[4], payload=body[5:]))
            del self.buf[:total]


def parse_descriptors(data):
    """Split a descriptor set into (bDescriptorType, bytes); UsbError on a bad bLength."""
    out, i = [], 0
    while i < len(data):
        ln = data[i]
        if ln < 2 or i + ln > len(data):
            raise UsbError('descriptor at offset %d: bLength %d' % (i, ln))
        out.append((data[i + 1], bytes(data[i:i + ln])))
        i += ln
    return out


def parse_config(data):
    """Configuration descriptor set -> dict(config=fields, interfaces=[dict(fields, functional=[...],
    endpoints=[dict(address, attributes, max_packet, interval)])])."""
    ds = parse_descriptors(data)
    if not ds or ds[0][0] != 2 or len(ds[0][1]) != 9:
        raise UsbError('first descriptor is not a 9-byte configuration descriptor')
    c = ds[0][1]
    total, nif, value, icfg, attr, power = struct.unpack_from('<HBBBBB', c, 2)
    if total != len(data):
        raise UsbError('wTotalLength %d, set has %d bytes' % (total, len(data)))
    cfg = dict(total=total, interfaces=nif, value=value, iconfig=icfg, attributes=attr, max_power=power)
    ifs = []
    for t, d in ds[1:]:
        if t == 4:
            if len(d) != 9:
                raise UsbError('interface descriptor of %d bytes' % len(d))
            num, alt, neps, cls, sub, proto, istr = struct.unpack_from('<7B', d, 2)
            ifs.append(dict(number=num, alt=alt, num_endpoints=neps, cls=cls, subclass=sub, protocol=proto,
                            iinterface=istr, functional=[], endpoints=[]))
        elif t == 5:
            if len(d) != 7 or not ifs:
                raise UsbError('endpoint descriptor of %d bytes or before an interface' % len(d))
            ea, at, mps, iv = struct.unpack_from('<BBHB', d, 2)
            ifs[-1]['endpoints'].append(dict(address=ea, attributes=at, max_packet=mps, interval=iv))
        elif t == 0x24:
            if not ifs:
                raise UsbError('class-specific descriptor before an interface')
            ifs[-1]['functional'].append(d)
        else:
            raise UsbError('unexpected descriptor type 0x%02X in the configuration' % t)
    for f in ifs:
        if len(f['endpoints']) != f['num_endpoints']:
            raise UsbError('interface %d: bNumEndpoints %d, %d endpoint descriptors'
                           % (f['number'], f['num_endpoints'], len(f['endpoints'])))
    if len(ifs) != nif:
        raise UsbError('bNumInterfaces %d, %d interface descriptors' % (nif, len(ifs)))
    return dict(config=cfg, interfaces=ifs)


class UsbHost:
    """A full-speed USB host on the device model: enumeration, CDC class requests, bulk / interrupt
    transfers and the control-channel frames. Every wait runs the chip in emulated time
    (Meter.run_for); a chip run that ends (reset, violation, IWDG) raises UsbError."""

    def __init__(self, meter, dev, nak_gap=20e-6, address=5):
        self.m, self.dev = meter, dev
        self.nak_gap = nak_gap
        self.new_address = address
        self.addr = 0
        self.mps0 = 64                      # until the device descriptor is read
        self.mps = {}                       # endpoint address (with the direction bit) -> max packet
        self.tog = {}                       # endpoint address -> next data PID (0 / 1)
        self.parser = FrameParser()
        self.frames = []                    # frames read while waiting for an answer
        self.seq = 0
        self.info = None
        self.ep_in, self.ep_out, self.ep_int = 0x81, 0x02, 0x83
        self.comm_if = 0

    # ---- time ----
    def run(self, seconds):
        end = self.m.run_for(seconds)
        if end is not None:
            raise UsbError('chip run ended: %r (violations %r)' % (end, self.m.st['viol']))

    def run_until(self, pred, timeout, what):
        t_end = self.m.now() + timeout
        end = self.m.run_for(until=lambda m: pred() or m.now() >= t_end)
        if end is not None:
            raise UsbError('chip run ended while waiting for %s: %r (violations %r)'
                           % (what, end, self.m.st['viol']))
        if not pred():
            raise UsbError('%s: not within %.3f s' % (what, timeout))

    # ---- bus ----
    def connect(self, timeout=5.0):
        """Wait for the D+ pull-up with the module on, 100 ms debounce, then a bus reset."""
        self.run_until(lambda: self.dev.attached(self.m), timeout, 'device attach')
        self.run(0.1)
        if not self.dev.attached(self.m):
            raise UsbError('device detached during the attach debounce')
        self.bus_reset()

    def bus_reset(self):
        self.dev.bus_reset(self.m)
        self.addr = 0
        self.mps0 = 64 if not self.info else self.mps0
        self.tog.clear()
        self.run(10e-3)
        self.dev.bus_run(self.m)
        self.run(10e-3)

    def suspend(self, seconds=5e-3):
        self.dev.bus_suspend(self.m)
        self.run(seconds)

    def resume(self):
        self.dev.bus_resume(self.m)
        self.run(20e-3)                     # resume signalling
        self.dev.bus_run(self.m)

    # ---- transactions ----
    def _setup(self, pkt):
        for _ in range(3):
            r = self.dev.host_setup(self.m, self.addr, pkt)
            if self.m.st['end'] is not None:
                raise UsbError('chip run ended: %r (violations %r)' % (self.m.st['end'], self.m.st['viol']))
            if r == 'ACK':
                self.run(self.nak_gap)
                return
            if r == 'STALL':
                raise UsbStall('SETUP %s answered STALL (receive buffer overflow)' % pkt.hex())
            self.run(self.nak_gap)
        raise UsbError('SETUP %s: no handshake three times' % pkt.hex())

    def _in(self, ep, timeout):
        """One IN data packet (NAKs retried until timeout)."""
        t_end = self.m.now() + timeout
        strikes = 0
        while True:
            r, data, pid = self.dev.host_in(self.m, self.addr, ep & 0x0F)
            if self.m.st['end'] is not None:
                raise UsbError('chip run ended: %r (violations %r)' % (self.m.st['end'], self.m.st['viol']))
            if r == 'ACK':
                want = self.tog.get(ep, 0)
                if pid != want:
                    raise UsbError('IN EP 0x%02X: DATA%d, host expected DATA%d' % (ep, pid, want))
                mps = self.mps0 if ep & 0x0F == 0 else self.mps.get(ep, 64)
                if len(data) > mps:
                    raise UsbError('IN EP 0x%02X: %d bytes, wMaxPacketSize %d (babble)' % (ep, len(data), mps))
                self.tog[ep] = want ^ 1
                self.run(self.nak_gap)
                return data
            if r == 'STALL':
                raise UsbStall('IN EP 0x%02X: STALL' % ep)
            if r == 'TIMEOUT':
                strikes += 1
                if strikes >= 3:
                    raise UsbError('IN EP 0x%02X: no handshake three times' % ep)
            else:
                strikes = 0
            if self.m.now() >= t_end:
                raise UsbError('IN EP 0x%02X: NAK for %.3f s' % (ep, timeout))
            self.run(self.nak_gap)

    def _out(self, ep, data, timeout):
        t_end = self.m.now() + timeout
        strikes = 0
        while True:
            pid = self.tog.get(ep, 0)
            r = self.dev.host_out(self.m, self.addr, ep & 0x0F, bytes(data), pid)
            if self.m.st['end'] is not None:
                raise UsbError('chip run ended: %r (violations %r)' % (self.m.st['end'], self.m.st['viol']))
            if r == 'ACK':
                self.tog[ep] = pid ^ 1
                self.run(self.nak_gap)
                return
            if r == 'ACK-IGNORED':
                raise UsbError('OUT EP 0x%02X DATA%d: the device expected the other PID, packet dropped'
                               % (ep, pid))
            if r == 'STALL':
                raise UsbStall('OUT EP 0x%02X: STALL' % ep)
            if r == 'TIMEOUT':
                strikes += 1
                if strikes >= 3:
                    raise UsbError('OUT EP 0x%02X: no handshake three times' % ep)
            else:
                strikes = 0
            if self.m.now() >= t_end:
                raise UsbError('OUT EP 0x%02X: NAK for %.3f s' % (ep, timeout))
            self.run(self.nak_gap)

    # ---- control transfers ----
    def control_in(self, req_type, req, value, index, length, first_packet_only=False):
        self._setup(struct.pack('<BBHHH', req_type, req, value, index, length))
        self.tog[0x80] = 1
        buf = b''
        while True:
            pkt = self._in(0x80, 0.5)
            buf += pkt
            if len(buf) > length:
                raise UsbError('control IN 0x%02X: %d bytes for wLength %d' % (req, len(buf), length))
            if first_packet_only or len(pkt) < self.mps0 or len(buf) == length:
                break
        self.tog[0x00] = 1
        self._out(0x00, b'', 0.5)
        return buf

    def control_out(self, req_type, req, value, index, data=b''):
        self._setup(struct.pack('<BBHHH', req_type, req, value, index, len(data)))
        self.tog[0x00] = 1
        for i in range(0, len(data), self.mps0):
            self._out(0x00, data[i:i + self.mps0], 0.5)
        self.tog[0x80] = 1
        st = self._in(0x80, 0.5 if data else 0.05)
        if st:
            raise UsbError('control OUT 0x%02X: status stage IN of %d bytes' % (req, len(st)))

    def get_descriptor(self, dtype, index, length, lang=0, first_packet_only=False):
        return self.control_in(0x80, 6, dtype << 8 | index, lang, length, first_packet_only)

    def set_address(self, addr):
        self.control_out(0x00, 5, addr, 0)
        self.run(2e-3)                      # SetAddress recovery (USB 2.0 9.2.6.3)
        self.addr = addr

    def set_configuration(self, value):
        self.control_out(0x00, 9, value, 0)
        for ep in list(self.tog):
            if ep & 0x0F:
                self.tog[ep] = 0
        for ep in self.mps:
            self.tog[ep] = 0                # SET_CONFIGURATION resets the data toggles (9.4.5)

    def set_line_coding(self, baud=115200, stop=0, parity=0, bits=8):
        data = struct.pack('<IBBB', baud, stop, parity, bits)
        self.control_out(0x21, 0x20, 0, self.comm_if, data)
        return data

    def get_line_coding(self):
        return self.control_in(0xA1, 0x21, 0, self.comm_if, 7)

    def set_control_line_state(self, dtr=True, rts=True):
        self.control_out(0x21, 0x22, (1 if dtr else 0) | (2 if rts else 0), self.comm_if)

    def enumerate(self, line_coding=(115200, 0, 0, 8), dtr=True):
        """Attach, reset, the first 64-byte device descriptor request, reset, SET_ADDRESS, device /
        configuration / string descriptors, SET_CONFIGURATION 1, SET_LINE_CODING (read back with
        GET_LINE_CODING) and SET_CONTROL_LINE_STATE. Returns dict(device, config, strings, raw)."""
        self.info = None
        self.connect()
        first = self.get_descriptor(1, 0, 64, first_packet_only=True)
        if len(first) < 8 or first[1] != 1:
            raise UsbError('first device descriptor packet %s' % first.hex())
        self.bus_reset()
        self.mps0 = first[7]
        if self.mps0 not in (8, 16, 32, 64):
            raise UsbError('bMaxPacketSize0 %d' % self.mps0)
        self.set_address(self.new_address)
        dd = self.get_descriptor(1, 0, 18)
        if len(dd) != 18 or dd[0] != 18 or dd[1] != 1:
            raise UsbError('device descriptor %s' % dd.hex())
        f = struct.unpack('<BBHBBBBHHHBBBB', dd)
        device = dict(bcdUSB=f[2], cls=f[3], subclass=f[4], protocol=f[5], mps0=f[6], vid=f[7], pid=f[8],
                      bcdDevice=f[9], imanufacturer=f[10], iproduct=f[11], iserial=f[12], configs=f[13])
        head = self.get_descriptor(2, 0, 9)
        total = struct.unpack_from('<H', head, 2)[0]
        raw_cfg = self.get_descriptor(2, 0, total)
        config = parse_config(raw_cfg)
        langs = self.get_descriptor(3, 0, 255)
        if len(langs) < 4 or langs[1] != 3 or langs[0] != len(langs):
            raise UsbError('string descriptor 0 %s' % langs.hex())
        lang = struct.unpack_from('<H', langs, 2)[0]
        strings = {}
        for idx in (device['imanufacturer'], device['iproduct'], device['iserial']):
            if idx:
                s = self.get_descriptor(3, idx, 255, lang)
                if len(s) < 2 or s[1] != 3 or s[0] != len(s) or len(s) % 2:
                    raise UsbError('string descriptor %d %s' % (idx, s.hex()))
                strings[idx] = s[2:].decode('utf-16-le')
        for itf in config['interfaces']:
            for ep in itf['endpoints']:
                self.mps[ep['address']] = ep['max_packet']
                t = ep['attributes'] & 3
                if itf['cls'] == 0x02 and t == 3:
                    self.ep_int = ep['address']
                    self.comm_if = itf['number']
                elif itf['cls'] == 0x0A and t == 2:
                    if ep['address'] & 0x80:
                        self.ep_in = ep['address']
                    else:
                        self.ep_out = ep['address']
        self.set_configuration(config['config']['value'])
        lc = self.set_line_coding(*line_coding)
        back = self.get_line_coding()
        if back != lc:
            raise UsbError('GET_LINE_CODING %s after SET_LINE_CODING %s' % (back.hex(), lc.hex()))
        self.set_control_line_state(dtr=dtr, rts=dtr)
        self.info = dict(device=device, config=config, strings=strings, raw_device=dd, raw_config=raw_cfg,
                         first_packet=first, lang=lang)
        return self.info

    # ---- data ----
    def bulk_out(self, data, ep=None, timeout=0.5, zlp=False):
        """Write data to the bulk OUT endpoint in packets of wMaxPacketSize; a zero-length packet after
        a full last packet when zlp."""
        ep = self.ep_out if ep is None else ep
        mps = self.mps.get(ep, 64)
        for i in range(0, len(data), mps):
            self._out(ep, data[i:i + mps], timeout)
        if zlp and data and len(data) % mps == 0:
            self._out(ep, b'', timeout)

    def bulk_in(self, ep=None, timeout=0.05, max_bytes=None):
        """Read from a bulk IN endpoint until a short packet, max_bytes, or a NAK lasting timeout
        (then the bytes so far are returned)."""
        ep = self.ep_in if ep is None else ep
        mps = self.mps.get(ep, 64)
        buf = b''
        while max_bytes is None or len(buf) < max_bytes:
            try:
                pkt = self._in(ep, timeout)
            except UsbStall:
                raise
            except UsbError as e:
                if 'NAK for' in str(e):
                    break
                raise
            buf += pkt
            if len(pkt) < mps:
                break
        return buf

    def interrupt_in(self, ep=None, timeout=0.05):
        ep = self.ep_int if ep is None else ep
        try:
            return self._in(ep, timeout)
        except UsbStall:
            raise
        except UsbError as e:
            if 'NAK for' in str(e):
                return None
            raise

    def send(self, cmd, payload=b'', typ=FR_REQUEST, seq=None):
        """Send one frame; returns its seq."""
        if seq is None:
            seq = self.seq
            self.seq = (self.seq + 1) & 0xFF
        self.bulk_out(make_frame(seq, typ, cmd, payload))
        return seq

    def recv(self, timeout=0.5):
        """Frames that arrive within timeout (at least one poll)."""
        t_end = self.m.now() + timeout
        out = []
        while True:
            out += self.parser.feed(self.bulk_in(timeout=min(0.01, timeout)))
            if out or self.m.now() >= t_end:
                return out

    def request(self, cmd, payload=b'', timeout=1.0):
        """Send a request frame and wait for the answer with the same seq and cmd; other frames go to
        self.frames. Returns the answer frame (dict seq, type, cmd, payload)."""
        seq = self.send(cmd, payload)
        t_end = self.m.now() + timeout
        while self.m.now() < t_end:
            for f in self.recv(timeout=t_end - self.m.now()):
                if f['type'] == FR_ANSWER and f['seq'] == seq and f['cmd'] == cmd:
                    return f
                self.frames.append(f)
        raise UsbError('no answer to cmd 0x%02X seq %d within %.3f s' % (cmd, seq, timeout))
