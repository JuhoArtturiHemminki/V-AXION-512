use std::sync::atomic::{AtomicU128, Ordering};
use std::arch::x86_64::*;

#[repr(align(64))]
#[derive(Copy, Clone)]
pub struct CleansedFlit(pub [u64; 8]);

pub struct State {
    pub ema_accumulator: [u128; 8],
    pub last_known_good: CleansedFlit,
    pub total_errors: AtomicU128,
    pub consecutive_errors: u64,
}

impl State {
    const RESYNC_THRESHOLD: u64 = 1_000_000;
    const EMA_ALPHA_SHIFT: u32 = 4;

    #[target_feature(enable = "avx512f,avx512dq,avx512vpopcntdq,avx512bw")]
    pub unsafe fn process_v11_ultimate(&mut self, inputs: &[CleansedFlit], ghost: &[CleansedFlit], parity: &[u8]) {
        let len = inputs.len().min(ghost.len()).min(parity.len());
        
        for i in 0..len {
            let p_ptr = inputs.get_unchecked(i).0.as_ptr() as *const __m512i;
            
            let (s_v1, s_v2): (__m512i, __m512i);
            core::arch::asm!(
                "vmovntdqa {v1}, [{ptr}]",
                "vmovdqu64 {v2}, [{ptr}]",
                ptr = in(reg) p_ptr,
                v1 = out(zmm_reg) s_v1,
                v2 = out(zmm_reg) s_v2,
                options(readonly, nostack, preserves_flags)
            );

            let bus_err = _mm512_cmpneq_epu64_mask(s_v1, s_v2);
            
            let res_a = self.calculate_tmr(s_v1);
            let res_b = self.calculate_tmr(s_v2);
            let alu_err = _mm512_cmpneq_epu64_mask(res_a, res_b);

            let g_v = _mm512_loadu_si512(ghost.get_unchecked(i).0.as_ptr() as *const _);
            let logic_err = self.check_logic_integrated(res_a, g_v, *parity.get_unchecked(i));
            
            let total_err_mask = bus_err | alu_err | logic_err;

            if total_err_mask == 0 {
                self.consecutive_errors = 0;
                self.update_state(res_a, inputs.get_unchecked(i));
            } else {
                self.consecutive_errors += 1;
                self.total_errors.fetch_add(total_err_mask.count_ones() as u128, Ordering::Relaxed);

                if self.consecutive_errors >= Self::RESYNC_THRESHOLD {
                    self.update_state(res_a, inputs.get_unchecked(i));
                    self.consecutive_errors = 0; 
                }
            }
        }
    }

    #[inline(always)]
    unsafe fn calculate_tmr(&self, s: __m512i) -> __m512i {
        let l = _mm512_ror_epi64(s, 13);
        let r = _mm512_ror_epi64(s, 31);
        _mm512_ternlog_epi64(l, r, s, 0xE8)
    }

    #[inline(always)]
    unsafe fn check_logic_integrated(&self, res: __m512i, ghost: __m512i, p_val: u8) -> u64 {
        let diff = _mm512_xor_si512(res, ghost);
        let ghost_err = _mm512_test_epi64_mask(diff, diff);
        
        let pop = _mm512_popcnt_epi64(res);
        let p_match = (_mm512_reduce_add_epi64(pop) as u8 ^ p_val) & 1;
        
        if (p_match != 0) | (ghost_err != 0) { 0xFFFF_FFFF_FFFF_FFFF } else { 0 }
    }

    #[inline(always)]
    unsafe fn update_state(&mut self, _data_v: __m512i, raw: &CleansedFlit) {
        self.last_known_good = *raw;
        for j in 0..8 {
            let val = raw.0[j] as u128;
            let current_ema = self.ema_accumulator[j];
            self.ema_accumulator[j] = current_ema - (current_ema >> Self::EMA_ALPHA_SHIFT) + (val << (64 - Self::EMA_ALPHA_SHIFT));
        }
    }
}
