// ============================================================================
// Module: gs512_core
// Author: JUHO ARTTURI HEMMINKI
// Year: 2026
// License: Apache 2.0
// Description: Ghost-Sync Alignment (gs512_core) for G-STORM-512.
//              Single-cycle deterministic frame alignment using 
//              Majority Vote (MV) resonance tracking.
// ============================================================================

module gs512_core #(
    parameter [511:0] KA_ANCHOR = 512'hACE_B00_000_000 // Kalman Anchor
)(
    input  logic         clk,
    input  logic         rst_n,      // Active low reset
    input  logic [511:0] m_in,       // 512-bit Measurement Input
    output logic [511:0] s_synch,    // 512-bit Synchronized output
    output logic [8:0]   delta_out   // 9-bit delta for TR-512 analysis
);

    // Internal signals
    logic [8:0] delta_reg;           // 9-bit resonance state tracking
    logic [8:0] delta_next;          // Calculated next resonance point

    // --- 1. Resonance Update Logic (Majority Vote) ---
    // Extract 9-bit LSBs from prime-shifted positions (157, 311)
    wire [8:0] v1 = m_in[8:0];                   // floor(M_in)_9
    wire [8:0] v2 = m_in[165:157];               // floor(M_in >> 157)_9
    wire [8:0] v3 = m_in[319:311];               // floor(M_in >> 311)_9

    // Hardware-level 2-out-of-3 Majority Vote (MV) for noise immunity
    assign delta_next = (v1 & v2) | (v2 & v3) | (v3 & v1);

    // --- 2. Alignment Logic (Right-Rotate & XOR) ---
    // Right cyclic shift (ROR) using current resonance delta_reg
    logic [511:0] rotated_data;
    assign rotated_data = (m_in >> delta_reg) | (m_in << (512 - delta_reg));

    // XOR with Kalman Anchor (Ka) for state recovery
    assign s_synch = rotated_data ^ KA_ANCHOR;
    assign delta_out = delta_reg;

    // --- 3. Sequential Logic (Clocked Process) ---
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            delta_reg <= 9'h000;     // Reset to Initial Vector (IV)
        end else begin
            delta_reg <= delta_next; // Update resonance for the next cycle
        end
    end

endmodule
