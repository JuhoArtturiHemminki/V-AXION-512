#[repr(align(64))]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct SupremeFlit(pub [u64; 8]);

pub struct GStormSupreme {
    kalman_anchor: SupremeFlit,
    phi: f64,
    entropy_limit: f64,
    last_known_good: SupremeFlit,
}

impl GStormSupreme {
    pub fn boot(anchor: SupremeFlit) -> Self {
        Self {
            kalman_anchor: anchor,
            phi: 1.618033988749895,
            entropy_limit: 5.08320369,
            last_known_good: anchor,
        }
    }

    pub fn process_cycle(
        &mut self, 
        m_in: SupremeFlit, 
        ghost_ref: SupremeFlit, 
        parity_ref: u8
    ) -> (SupremeFlit, f64) {
        
        let s1 = self.prime_rotate(&m_in, 157);
        let s2 = self.prime_rotate(&m_in, 311);
        let s3 = m_in;

        let mut voted = [0u64; 8];
        for i in 0..8 {
            voted[i] = (s1.0[i] & s2.0[i]) | (s2.0[i] & s3.0[i]) | (s1.0[i] & s3.0[i]);
        }
        let s_sr = SupremeFlit(voted);

        let current_ghost = self.generate_ghost(&s_sr);
        let current_parity = self.compute_parity(&s_sr);

        let mut delta_acc: u64 = 0;
        for i in 0..8 { delta_acc |= current_ghost.0[i] ^ ghost_ref.0[i]; }
        delta_acc |= (current_parity ^ parity_ref) as u64;

        let mask = if delta_acc != 0 { !0u64 } else { 0u64 };

        let mut output = [0u64; 8];
        for i in 0..8 {
            output[i] = s_sr.0[i] ^ (mask & (s_sr.0[i] ^ self.kalman_anchor.0[i]));
        }

        let diff = (m_in.0[0] as f64 - self.last_known_good.0[0] as f64).abs();
        let drift = diff * self.phi;
        self.last_known_good = m_in;

        (SupremeFlit(output), drift)
    }

    fn prime_rotate(&self, f: &SupremeFlit, s: u32) -> SupremeFlit {
        let mut r = [0u64; 8];
        for i in 0..8 { r[i] = f.0[i].rotate_right(s % 64); }
        SupremeFlit(r)
    }

    fn generate_ghost(&self, f: &SupremeFlit) -> SupremeFlit {
        let g1 = self.prime_rotate(f, 157);
        let g2 = self.prime_rotate(f, 311);
        let mut r = [0u64; 8];
        for i in 0..8 { r[i] = g1.0[i] ^ g2.0[i]; }
        SupremeFlit(r)
    }

    fn compute_parity(&self, f: &SupremeFlit) -> u8 {
        let mut p = 0u8;
        for w in f.0.iter() { p ^= (w.count_ones() % 2) as u8; }
        p
    }
}
