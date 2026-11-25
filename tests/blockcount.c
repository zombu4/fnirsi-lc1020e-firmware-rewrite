/* blockcount.c - the instruction counter of tests/meter_model.py (timing) as a native unicorn hook.
 *
 * meter_model.Meter counts instructions with a UC_HOOK_BLOCK hook: at the start of every executed
 * block it ends the slice when a stop was requested (Meter.irq_check), else it books the block
 * (address, size, count before it, the offsets of its Thumb instructions) and adds the number of its
 * instructions to the count; Meter._icount_at(pc) corrects the count to the PC inside the booked
 * block. This file is that hook and that correction in C, so no Python runs per block; the rules
 * are the ones of the Python hook it replaces, line for line:
 *   - the instruction offsets of a block are decoded once per (address, size) and kept for the
 *     life of the hook (thumb_offsets: a halfword whose top five bits are 0b11101, 0b11110 or
 *     0b11111 starts a 32-bit instruction; the walk stops when fewer than 2 bytes are left);
 *   - a pending stop request is taken at the start of the next block: request cleared, booked
 *     block dropped, uc_emu_stop, the block not counted;
 *   - icount_at(pc): inside the booked block, base + the number of offsets below pc - address
 *     (bisect_left), else the count; bc_icount_pc reads the PC itself (uc_reg_read, as
 *     Uc.reg_read(UC_ARM_REG_PC) does) to save the Python register read.
 * The state is live only while unicorn runs a slice (Meter._run): before each emu_start the model
 * loads the count into it and clears the request, after it the model takes the count back, so
 * between slices Meter.tm holds every value as before (and a test's snapshot of Meter.tm restores
 * it).
 * meter_model.py builds this file with the C compiler (cc) into a cache directory on first use
 * and loads it with ctypes (meter_model.py, "native block hook"). It links against nothing: the
 * two unicorn functions it calls (uc_mem_read, uc_emu_stop) are handed over as pointers taken
 * from the library the Python binding loaded, so the hook works on the same unicorn instance.
 */
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

typedef void uc_engine;
typedef int (*mem_read_fn)(uc_engine *uc, uint64_t address, void *bytes, uint64_t size);
typedef int (*emu_stop_fn)(uc_engine *uc);
typedef int (*reg_read_fn)(uc_engine *uc, int regid, void *value);

#define UC_ARM_REG_PC 11        /* unicorn arm.h, UC_ARM_REG_PC = UC_ARM_REG_R15 */

#define NBUCKET 4096u

typedef struct entry {
    uint64_t addr;
    uint32_t size;
    uint32_t n;                 /* number of instructions */
    uint32_t *offs;             /* n offsets, ascending */
    struct entry *next;
} entry;

/* Shared with Python (ctypes.Structure BcState in meter_model.py): keep the field order. */
typedef struct {
    int64_t icount;             /* tm['icount'] */
    int32_t stop_req;           /* tm['stop_req'] */
    int32_t blk_valid;          /* tm['blk'] is not None */
    uint64_t blk_addr;
    uint64_t blk_size;
    int64_t blk_base;
    entry *blk;                 /* the booked block's cache entry */
    uint64_t blocks;            /* blocks booked (statistics only) */
    mem_read_fn mem_read;       /* unicorn's uc_mem_read */
    emu_stop_fn emu_stop;       /* unicorn's uc_emu_stop */
    reg_read_fn reg_read;       /* unicorn's uc_reg_read */
    entry *table[NBUCKET];
} bc_state;

static uint32_t bucket(uint64_t addr, uint32_t size)
{
    uint64_t h = (addr >> 1) * 0x9E3779B97F4A7C15ull ^ size;
    return (uint32_t)(h >> 20) & (NBUCKET - 1u);
}

static entry *decode(bc_state *s, uc_engine *uc, uint64_t addr, uint32_t size)
{
    entry *e = calloc(1, sizeof(entry));
    uint8_t *code = malloc(size ? size : 1);
    uint32_t i = 0, n = 0;
    if (!e || !code)
        abort();
    if (s->mem_read(uc, addr, code, size) != 0)
        abort();            /* the Python hook raised here (UcError); not seen in a translated block */
    e->offs = malloc(sizeof(uint32_t) * (size / 2u + 1u));
    if (!e->offs)
        abort();
    while (i + 1u < size) {
        uint32_t hw = (uint32_t)code[i] | (uint32_t)code[i + 1u] << 8;
        uint32_t top = hw >> 11;
        e->offs[n++] = i;
        i += (top == 0x1Du || top == 0x1Eu || top == 0x1Fu) ? 4u : 2u;
    }
    free(code);
    e->addr = addr;
    e->size = size;
    e->n = n;
    return e;
}

void bc_block(uc_engine *uc, uint64_t addr, uint32_t size, void *user)
{
    bc_state *s = (bc_state *)user;
    entry *e;
    uint32_t b;
    if (s->stop_req) {
        s->stop_req = 0;
        s->blk_valid = 0;
        s->blk = NULL;
        s->emu_stop(uc);
        return;
    }
    b = bucket(addr, size);
    for (e = s->table[b]; e; e = e->next)
        if (e->addr == addr && e->size == size)
            break;
    if (!e) {
        e = decode(s, uc, addr, size);
        e->next = s->table[b];
        s->table[b] = e;
    }
    s->blk_valid = 1;
    s->blk_addr = addr;
    s->blk_size = size;
    s->blk_base = s->icount;
    s->blk = e;
    s->icount += e->n;
    s->blocks++;
}

int64_t bc_icount_at(bc_state *s, uint64_t pc)
{
    if (s->blk_valid && s->blk_addr <= pc && pc < s->blk_addr + s->blk_size) {
        uint64_t x = pc - s->blk_addr;
        uint32_t lo = 0, hi = s->blk->n;
        while (lo < hi) {                   /* bisect_left */
            uint32_t mid = (lo + hi) / 2u;
            if (s->blk->offs[mid] < x)
                lo = mid + 1u;
            else
                hi = mid;
        }
        return s->blk_base + (int64_t)lo;
    }
    return s->icount;
}

/* icount_at(PC): the PC read as Meter reads it (uc_reg_read of UC_ARM_REG_PC, 32 bits). */
int64_t bc_icount_pc(bc_state *s, uc_engine *uc)
{
    uint32_t pc = 0;
    if (s->reg_read(uc, UC_ARM_REG_PC, &pc) != 0)
        abort();
    return bc_icount_at(s, pc);
}

bc_state *bc_new(mem_read_fn mem_read, emu_stop_fn emu_stop, reg_read_fn reg_read)
{
    bc_state *s = calloc(1, sizeof(bc_state));
    if (!s)
        abort();
    s->mem_read = mem_read;
    s->emu_stop = emu_stop;
    s->reg_read = reg_read;
    return s;
}

void bc_free(bc_state *s)
{
    uint32_t b;
    if (!s)
        return;
    for (b = 0; b < NBUCKET; b++) {
        entry *e = s->table[b];
        while (e) {
            entry *nx = e->next;
            free(e->offs);
            free(e);
            e = nx;
        }
    }
    free(s);
}
