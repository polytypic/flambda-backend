(**************************************************************************)
(*                                                                        *)
(*                                 OCaml                                  *)
(*                                                                        *)
(*          Fabrice Le Fessant, projet Gallium, INRIA Rocquencourt        *)
(*                                                                        *)
(*   Copyright 2014 Institut National de Recherche en Informatique et     *)
(*     en Automatique.                                                    *)
(*                                                                        *)
(*   All rights reserved.  This file is distributed under the terms of    *)
(*   the GNU Lesser General Public License version 2.1, with the          *)
(*   special exception on linking described in the file LICENSE.          *)
(*                                                                        *)
(**************************************************************************)

(** Structured representation of Intel assembly language (32 and 64 bit). *)

type condition =
  | L | GE     (* signed comparisons: less/greater *)
  | LE | G
  | B | AE     (* unsigned comparisons: below/above *)
  | BE | A
  | E | NE     (* equal *)
  | O | NO     (* overflow *)
  | S | NS     (* sign *)
  | P | NP     (* parity *)

type float_condition =
  | EQf
  | LTf
  | LEf
  | UNORDf
  | NEQf
  | NLTf
  | NLEf
  | ORDf

type rounding =
  | RoundUp
  | RoundDown
  | RoundNearest
  | RoundTruncate
  | RoundCurrent

type constant =
  | Const of int64
  | ConstThis
  | ConstLabel of string
  | ConstLabelOffset of string * int
  | ConstAdd of constant * constant
  | ConstSub of constant * constant

(* data_type is used mainly on memory addressing to specify
   the size of the addressed memory chunk.  It is directly
   used by the MASM emitter and indirectly by the GAS emitter
   to infer the instruction suffix. *)

type data_type =
  | NONE
  | REAL4 | REAL8 (* floating point values *)
  | BYTE | WORD | DWORD | QWORD (* integer values *)
  | VEC128 (* vector values (float & integer) *)
  | NEAR | PROC

type reg64 =
  | RAX | RBX | RCX | RDX | RSP | RBP | RSI | RDI
  | R8 | R9 | R10 | R11 | R12 | R13 | R14 | R15

type reg8h =
  | AH | BH | CH | DH

type regf = XMM of int

type arch = X64 | X86

type addr =
  {
    arch: arch;
    typ: data_type;
    idx: reg64;
    scale: int;
    base: reg64 option;
    sym: string option;
    displ: int;
  }
  (** Addressing modes:
      displ + sym + base + idx * scale
      (if scale = 0, idx is ignored and base must be None)
  *)

type prefetch_temporal_locality_hint = Nta | T1 | T2 | T0

type arg =
  | Imm of int64
  (** Operand is an immediate constant integer *)

  | Sym of  string
  (** Address of a symbol (absolute address except for call/jmp target
      where it is interpreted as a relative displacement *)

  | Reg8L of reg64
  | Reg8H of reg8h
  | Reg16 of reg64
  | Reg32 of reg64
  | Reg64 of reg64
  | Regf of regf

  | Mem of addr
  | Mem64_RIP of data_type * string * int

type sse_instruction =
  | MINSS of arg * arg
  | MAXSS of arg * arg
  | CMPPS of float_condition * arg * arg
  | SHUFPS of arg * arg * arg
  | ADDPS of arg * arg
  | SUBPS of arg * arg
  | MULPS of arg * arg
  | DIVPS of arg * arg
  | MAXPS of arg * arg
  | MINPS of arg * arg
  | RCPPS of arg * arg
  | SQRTPS of arg * arg
  | RSQRTPS of arg * arg
  | MOVHLPS of arg * arg
  | MOVLHPS of arg * arg
  | UNPCKHPS of arg * arg
  | UNPCKLPS of arg * arg
  | MOVMSKPS of arg * arg

type sse2_instruction =
  | PADDB of arg * arg
  | PADDW of arg * arg
  | PADDD of arg * arg
  | PADDQ of arg * arg
  | ADDPD of arg * arg
  | PADDSB of arg * arg
  | PADDSW of arg * arg
  | PADDUSB of arg * arg
  | PADDUSW of arg * arg
  | PSUBB of arg * arg
  | PSUBW of arg * arg
  | PSUBD of arg * arg
  | PSUBQ of arg * arg
  | SUBPD of arg * arg
  | PSUBSB of arg * arg
  | PSUBSW of arg * arg
  | PSUBUSB of arg * arg
  | PSUBUSW of arg * arg
  | PMAXUB of arg * arg
  | PMAXSW of arg * arg
  | MAXPD of arg * arg
  | PMINUB of arg * arg
  | PMINSW of arg * arg
  | MINPD of arg * arg
  | MULPD of arg * arg
  | DIVPD of arg * arg
  | SQRTPD of arg * arg
  | PAND of arg * arg
  | PANDNOT of arg * arg
  | POR of arg * arg
  | PXOR of arg * arg
  | PMOVMSKB of arg * arg
  | MOVMSKPD of arg * arg
  | PSLLDQ of arg * arg
  | PSRLDQ of arg * arg
  | PCMPEQB of arg * arg
  | PCMPEQW of arg * arg
  | PCMPEQD of arg * arg
  | PCMPGTB of arg * arg
  | PCMPGTW of arg * arg
  | PCMPGTD of arg * arg
  | CMPPD of float_condition * arg * arg
  | CVTDQ2PD of arg * arg
  | CVTDQ2PS of arg * arg
  | CVTPD2DQ of arg * arg
  | CVTPD2PS of arg * arg
  | CVTPS2DQ of arg * arg
  | CVTPS2PD of arg * arg
  | PSLLW of arg * arg
  | PSLLD of arg * arg
  | PSLLQ of arg * arg
  | PSRLW of arg * arg
  | PSRLD of arg * arg
  | PSRLQ of arg * arg
  | PSRAW of arg * arg
  | PSRAD of arg * arg
  | PSLLWI of arg * arg
  | PSLLDI of arg * arg
  | PSLLQI of arg * arg
  | PSRLWI of arg * arg
  | PSRLDI of arg * arg
  | PSRLQI of arg * arg
  | PSRAWI of arg * arg
  | PSRADI of arg * arg
  | SHUFPD of arg * arg * arg
  | PSHUFHW of arg * arg * arg
  | PSHUFLW of arg * arg * arg
  | PUNPCKHBW of arg * arg
  | PUNPCKHWD of arg * arg
  | PUNPCKHQDQ of arg * arg
  | PUNPCKLBW of arg * arg
  | PUNPCKLWD of arg * arg
  | PUNPCKLQDQ of arg * arg
  | PAVGB of arg * arg
  | PAVGW of arg * arg
  | PSADBW of arg * arg
  | PACKSSWB of arg * arg
  | PACKSSDW of arg * arg
  | PACKUSWB of arg * arg
  | PACKUSDW of arg * arg
  | PMULHW of arg * arg
  | PMULHUW of arg * arg
  | PMULLW of arg * arg
  | PMADDWD of arg * arg

type sse3_instruction =
  | ADDSUBPS of arg * arg
  | ADDSUBPD of arg * arg
  | HADDPS of arg * arg
  | HADDPD of arg * arg
  | HSUBPS of arg * arg
  | HSUBPD of arg * arg
  | MOVDDUP of arg * arg
  | MOVSHDUP of arg * arg
  | MOVSLDUP of arg * arg

type ssse3_instruction =
  | PABSB of arg * arg
  | PABSW of arg * arg
  | PABSD of arg * arg
  | PHADDW of arg * arg
  | PHADDD of arg * arg
  | PHADDSW of arg * arg
  | PHSUBW of arg * arg
  | PHSUBD of arg * arg
  | PHSUBSW of arg * arg
  | PSIGNB of arg * arg
  | PSIGNW of arg * arg
  | PSIGND of arg * arg
  | PSHUFB of arg * arg
  | PALIGNR of arg * arg * arg
  | PMADDUBSW of arg * arg

type sse41_instruction =
  | PBLENDW of arg * arg * arg
  | BLENDPS of arg * arg * arg
  | BLENDPD of arg * arg * arg
  | PBLENDVB of arg * arg
  | BLENDVPS of arg * arg
  | BLENDVPD of arg * arg
  | PCMPEQQ of arg * arg
  | PMOVSXBW of arg * arg
  | PMOVSXBD of arg * arg
  | PMOVSXBQ of arg * arg
  | PMOVSXWD of arg * arg
  | PMOVSXWQ of arg * arg
  | PMOVSXDQ of arg * arg
  | PMOVZXBW of arg * arg
  | PMOVZXBD of arg * arg
  | PMOVZXBQ of arg * arg
  | PMOVZXWD of arg * arg
  | PMOVZXWQ of arg * arg
  | PMOVZXDQ of arg * arg
  | DPPS of arg * arg * arg
  | DPPD of arg * arg * arg
  | PEXTRB of arg * arg * arg
  | PEXTRW of arg * arg * arg
  | PEXTRD of arg * arg * arg
  | PEXTRQ of arg * arg * arg
  | PINSRB of arg * arg * arg
  | PINSRW of arg * arg * arg
  | PINSRD of arg * arg * arg
  | PINSRQ of arg * arg * arg
  | PMAXSB of arg * arg
  | PMAXSD of arg * arg
  | PMAXUW of arg * arg
  | PMAXUD of arg * arg
  | PMINSB of arg * arg
  | PMINSD of arg * arg
  | PMINUW of arg * arg
  | PMINUD of arg * arg
  | ROUNDPD of rounding * arg * arg
  | ROUNDPS of rounding * arg * arg
  | ROUNDSS of rounding * arg * arg
  | MPSADBW of arg * arg * arg
  | PHMINPOSUW of arg * arg
  | PMULLD of arg * arg

type sse42_instruction =
  | PCMPGTQ of arg * arg
  | PCMPESTRI of arg * arg * arg
  | PCMPESTRM of arg * arg * arg
  | PCMPISTRI of arg * arg * arg
  | PCMPISTRM of arg * arg * arg
  | CRC32 of arg * arg

type instruction =
  | ADD of arg * arg
  | ADDSD of arg * arg
  | AND of arg * arg
  | ANDPD of arg * arg
  | BSF of arg * arg
  | BSR of arg * arg
  | BSWAP of arg
  | CALL of arg
  | CDQ
  | CLDEMOTE of arg
  | CMOV of condition * arg * arg
  | CMP of arg * arg
  | CMPSD of float_condition * arg * arg
  | COMISD of arg * arg
  | CQO
  | CVTSD2SI of arg * arg
  | CVTSS2SI of arg * arg
  | CVTSD2SS of arg * arg
  | CVTSI2SS of arg * arg
  | CVTSS2SD of arg * arg
  | CVTSI2SD of arg * arg
  | CVTTSD2SI of arg * arg
  | CVTTSS2SI of arg * arg
  | DEC of arg
  | DIVSD of arg * arg
  | HLT
  | IDIV of arg
  | IMUL of arg * arg option
  | MUL of arg
  | INC of arg
  | J of condition * arg
  | JMP of arg
  | LEA of arg * arg
  | LOCK_CMPXCHG of arg * arg
  | LOCK_XADD of arg * arg
  | LOCK_ADD of arg * arg
  | LOCK_SUB of arg * arg
  | LOCK_AND of arg * arg
  | LOCK_OR of arg * arg
  | LOCK_XOR of arg * arg
  | LEAVE
  | MAXSD of arg * arg
  | MINSD of arg * arg
  | MOV of arg * arg
  | MOVAPD of arg * arg
  | MOVUPD of arg * arg
  | MOVD of arg * arg
  | MOVQ of arg * arg
  | MOVLPD of arg * arg
  | MOVSD of arg * arg
  | MOVSS of arg * arg
  | MOVSX of arg * arg
  | MOVSXD of arg * arg
  | MOVZX of arg * arg
  | MULSD of arg * arg
  | NEG of arg
  | NOP
  | OR of arg * arg
  | PAUSE
  | POP of arg
  | POPCNT of arg * arg
  | PREFETCH of bool * prefetch_temporal_locality_hint * arg
  | PUSH of arg
  | RDTSC
  | RDPMC
  | LFENCE
  | SFENCE
  | MFENCE
  | RET
  | ROUNDSD of rounding * arg * arg
  | SAL of arg * arg
  | SAR of arg * arg
  | SET of condition * arg
  | SHR of arg * arg
  | SQRTSD of arg * arg
  | SUB of arg * arg
  | SUBSD of arg * arg
  | TEST of arg * arg
  | UCOMISD of arg * arg
  | XCHG of arg * arg
  | XOR of arg * arg
  | XORPD of arg * arg
  | ADDSS of arg * arg
  | SUBSS of arg * arg
  | MULSS of arg * arg
  | DIVSS of arg * arg
  | COMISS of arg * arg
  | UCOMISS of arg * arg
  | SQRTSS of arg * arg
  | XORPS of arg * arg
  | ANDPS of arg * arg
  | CMPSS of float_condition * arg * arg
  | SSE of sse_instruction
  | SSE2 of sse2_instruction
  | SSE3 of sse3_instruction
  | SSSE3 of ssse3_instruction
  | SSE41 of sse41_instruction
  | SSE42 of sse42_instruction
  | PCLMULQDQ of arg * arg * arg
  | PEXT of arg * arg * arg
  | PDEP of arg * arg * arg
  | TZCNT of arg * arg
  | LZCNT of arg * arg

(* ELF specific *)
type reloc_type =
  | R_X86_64_PLT32

type reloc =
  { offset : constant;
    name : reloc_type;
    expr : constant;
  }

(* CR gyorsh: use inline record for Section and File constructors. *)
type asm_line =
  | Ins of instruction

  | Align of bool * int
  | Byte of constant
  | Bytes of string
  | Comment of string
  | Global of string
  | Protected of string
  | Hidden of string
  | Weak of string
  | Long of constant
  | NewLabel of string * data_type
  | NewLine
  | Quad of constant
  | Section of string list * string option * string list * bool
  | Sleb128 of constant
  | Space of int
  | Uleb128 of constant
  | Word of constant

  (* masm only (the gas emitter will fail on them) *)
  | External of string * data_type
  | Mode386
  | Model of string

  (* gas only (the masm emitter will fail on them) *)
  | Cfi_adjust_cfa_offset of int
  | Cfi_endproc
  | Cfi_startproc
  | Cfi_remember_state
  | Cfi_restore_state
  | Cfi_def_cfa_register of string
  | Cfi_def_cfa_offset of int
  | File of int * string (* (file_num, file_name) *)
  | Indirect_symbol of string
  | Loc of { file_num:int; line:int; col:int; discriminator: int option }
  | Private_extern of string
  | Set of string * constant
  | Size of string * constant
  | Type of string * string
  | Reloc of reloc

  (* MacOS only *)
  | Direct_assignment of string * constant

type asm_program = asm_line list
