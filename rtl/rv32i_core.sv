`timescale 1ns/1ps
// Small in-order RV32I controller core.  The core exposes explicit
// request/response instruction and data ports; it neither knows nor assumes
// anything about the CNN accelerator or an FPGA fabric.
module rv32i_core (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        irq,

  output logic        imem_valid,
  output logic [31:0] imem_addr,
  input  logic        imem_ready,
  input  logic [31:0] imem_rdata,

  output logic        dmem_valid,
  output logic        dmem_write,
  output logic [31:0] dmem_addr,
  output logic [31:0] dmem_wdata,
  output logic [3:0]  dmem_wstrb,
  input  logic        dmem_ready,
  input  logic [31:0] dmem_rdata
);
  typedef enum logic [1:0] {F_REQ, EXEC, D_WAIT} state_t;
  state_t state;

  logic [31:0] pc, instr;
  logic [31:0] regs [0:31];
  logic [31:0] mem_addr_q, mem_wdata_q;
  logic [3:0]  mem_wstrb_q;
  logic        mem_write_q;
  logic [4:0]  mem_rd_q;
  logic [2:0]  mem_funct3_q;

  wire [6:0] opcode = instr[6:0];
  wire [2:0] funct3 = instr[14:12];
  wire [6:0] funct7 = instr[31:25];
  wire [4:0] rs1_idx = instr[19:15];
  wire [4:0] rs2_idx = instr[24:20];
  wire [4:0] rd_idx  = instr[11:7];
  wire [31:0] rs1 = (rs1_idx == 0) ? 32'd0 : regs[rs1_idx];
  wire [31:0] rs2 = (rs2_idx == 0) ? 32'd0 : regs[rs2_idx];
  wire [31:0] imm_i = {{20{instr[31]}}, instr[31:20]};
  wire [31:0] imm_s = {{20{instr[31]}}, instr[31:25], instr[11:7]};
  wire [31:0] imm_b = {{19{instr[31]}}, instr[31], instr[7], instr[30:25], instr[11:8], 1'b0};
  wire [31:0] imm_u = {instr[31:12], 12'd0};
  wire [31:0] imm_j = {{11{instr[31]}}, instr[31], instr[19:12], instr[20], instr[30:21], 1'b0};
  wire [31:0] store_addr = rs1 + imm_s;

  function automatic [31:0] load_extend(input logic [31:0] word, input logic [1:0] lane, input logic [2:0] size);
    logic [7:0] b;
    logic [15:0] h;
    begin
      b = word >> (lane * 8);
      h = lane[1] ? word[31:16] : word[15:0];
      case (size)
        3'b000: load_extend = {{24{b[7]}}, b};
        3'b001: load_extend = {{16{h[15]}}, h};
        3'b010: load_extend = word;
        3'b100: load_extend = {24'd0, b};
        3'b101: load_extend = {16'd0, h};
        default: load_extend = 32'd0;
      endcase
    end
  endfunction

  always_comb begin
    imem_valid = (state == F_REQ);
    imem_addr  = pc;
    dmem_valid = (state == D_WAIT);
    dmem_write = mem_write_q;
    dmem_addr  = mem_addr_q;
    dmem_wdata = mem_wdata_q;
    dmem_wstrb = mem_wstrb_q;
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state <= F_REQ;
      pc <= 32'd0;
      instr <= 32'h00000013; // NOP
      mem_addr_q <= '0; mem_wdata_q <= '0; mem_wstrb_q <= '0;
      mem_write_q <= 1'b0; mem_rd_q <= '0; mem_funct3_q <= '0;
      // Architectural x0 is forced to zero.  The remaining GPRs intentionally
      // have no reset network; ABI-compliant boot code initializes live state
      // and the implementation avoids a high-fanout reset tree in the core.
    end else begin
      regs[0] <= 32'd0;
      case (state)
        F_REQ: if (imem_ready) begin instr <= imem_rdata; state <= EXEC; end
        EXEC: begin
          case (opcode)
            7'b0110111: begin if (rd_idx != 0) regs[rd_idx] <= imm_u; pc <= pc + 4; state <= F_REQ; end // LUI
            7'b0010111: begin if (rd_idx != 0) regs[rd_idx] <= pc + imm_u; pc <= pc + 4; state <= F_REQ; end // AUIPC
            7'b1101111: begin if (rd_idx != 0) regs[rd_idx] <= pc + 4; pc <= pc + imm_j; state <= F_REQ; end // JAL
            7'b1100111: begin if (rd_idx != 0) regs[rd_idx] <= pc + 4; pc <= (rs1 + imm_i) & 32'hffff_fffe; state <= F_REQ; end // JALR
            7'b1100011: begin // Branch
              case (funct3)
                3'b000: pc <= (rs1 == rs2) ? pc + imm_b : pc + 4;
                3'b001: pc <= (rs1 != rs2) ? pc + imm_b : pc + 4;
                3'b100: pc <= ($signed(rs1) <  $signed(rs2)) ? pc + imm_b : pc + 4;
                3'b101: pc <= ($signed(rs1) >= $signed(rs2)) ? pc + imm_b : pc + 4;
                3'b110: pc <= (rs1 <  rs2) ? pc + imm_b : pc + 4;
                3'b111: pc <= (rs1 >= rs2) ? pc + imm_b : pc + 4;
                default: pc <= pc + 4;
              endcase
              state <= F_REQ;
            end
            7'b0000011: begin // Load
              mem_addr_q <= rs1 + imm_i; mem_wdata_q <= '0; mem_wstrb_q <= 4'd0;
              mem_write_q <= 1'b0; mem_rd_q <= rd_idx; mem_funct3_q <= funct3; state <= D_WAIT;
            end
            7'b0100011: begin // Store
              mem_addr_q <= store_addr; mem_write_q <= 1'b1; mem_rd_q <= '0; mem_funct3_q <= funct3;
              case (funct3)
                3'b000: begin mem_wstrb_q <= 4'b0001 << store_addr[1:0]; mem_wdata_q <= {4{rs2[7:0]}}; end
                3'b001: begin mem_wstrb_q <= store_addr[1] ? 4'b1100 : 4'b0011; mem_wdata_q <= {2{rs2[15:0]}}; end
                3'b010: begin mem_wstrb_q <= 4'b1111; mem_wdata_q <= rs2; end
                default: begin mem_wstrb_q <= 4'b0000; mem_wdata_q <= '0; end
              endcase
              state <= D_WAIT;
            end
            7'b0010011: begin // ALU immediate
              if (rd_idx != 0) begin
                case (funct3)
                  3'b000: regs[rd_idx] <= rs1 + imm_i;
                  3'b010: regs[rd_idx] <= ($signed(rs1) < $signed(imm_i));
                  3'b011: regs[rd_idx] <= (rs1 < imm_i);
                  3'b100: regs[rd_idx] <= rs1 ^ imm_i;
                  3'b110: regs[rd_idx] <= rs1 | imm_i;
                  3'b111: regs[rd_idx] <= rs1 & imm_i;
                  3'b001: regs[rd_idx] <= rs1 << instr[24:20];
                  3'b101: regs[rd_idx] <= funct7[5] ? $signed(rs1) >>> instr[24:20] : rs1 >> instr[24:20];
                  default: regs[rd_idx] <= 32'd0;
                endcase
              end
              pc <= pc + 4; state <= F_REQ;
            end
            7'b0110011: begin // ALU register
              if (rd_idx != 0) begin
                case (funct3)
                  3'b000: regs[rd_idx] <= funct7[5] ? rs1 - rs2 : rs1 + rs2;
                  3'b001: regs[rd_idx] <= rs1 << rs2[4:0];
                  3'b010: regs[rd_idx] <= ($signed(rs1) < $signed(rs2));
                  3'b011: regs[rd_idx] <= (rs1 < rs2);
                  3'b100: regs[rd_idx] <= rs1 ^ rs2;
                  3'b101: regs[rd_idx] <= funct7[5] ? $signed(rs1) >>> rs2[4:0] : rs1 >> rs2[4:0];
                  3'b110: regs[rd_idx] <= rs1 | rs2;
                  3'b111: regs[rd_idx] <= rs1 & rs2;
                  default: regs[rd_idx] <= 32'd0;
                endcase
              end
              pc <= pc + 4; state <= F_REQ;
            end
            default: begin pc <= pc + 4; state <= F_REQ; end // illegal instruction is a NOP until trap CSR is added
          endcase
        end
        D_WAIT: if (dmem_ready) begin
          if (!mem_write_q && mem_rd_q != 0) regs[mem_rd_q] <= load_extend(dmem_rdata, mem_addr_q[1:0], mem_funct3_q);
          pc <= pc + 4;
          state <= F_REQ;
        end
        default: state <= F_REQ;
      endcase
    end
  end
endmodule
