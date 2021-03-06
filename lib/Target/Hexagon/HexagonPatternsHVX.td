def SDTVecLeaf:
  SDTypeProfile<1, 0, [SDTCisVec<0>]>;
def SDTVecBinOp:
  SDTypeProfile<1, 2, [SDTCisVec<0>, SDTCisVec<1>, SDTCisSameAs<1,2>]>;

def SDTHexagonVEXTRACTW: SDTypeProfile<1, 2,
  [SDTCisVT<0, i32>, SDTCisVec<1>, SDTCisVT<2, i32>]>;
def HexagonVEXTRACTW : SDNode<"HexagonISD::VEXTRACTW", SDTHexagonVEXTRACTW>;

def SDTHexagonVINSERTW0: SDTypeProfile<1, 2,
  [SDTCisVec<0>, SDTCisSameAs<0, 1>, SDTCisVT<2, i32>]>;
def HexagonVINSERTW0 : SDNode<"HexagonISD::VINSERTW0", SDTHexagonVINSERTW0>;

def HwLen2: SDNodeXForm<imm, [{
  const auto &ST = static_cast<const HexagonSubtarget&>(CurDAG->getSubtarget());
  return CurDAG->getTargetConstant(ST.getVectorLength()/2, SDLoc(N), MVT::i32);
}]>;

def Q2V: OutPatFrag<(ops node:$Qs), (V6_vandqrt $Qs, (A2_tfrsi -1))>;

def Combinev: OutPatFrag<(ops node:$Vs, node:$Vt),
  (REG_SEQUENCE HvxWR, $Vs, vsub_hi, $Vt, vsub_lo)>;

def Combineq: OutPatFrag<(ops node:$Qs, node:$Qt),
  (V6_vandvrt
    (V6_vor
      (V6_vror (V6_vpackeb (V6_vd0), (Q2V $Qs)),
               (A2_tfrsi (HwLen2 (i32 0)))),  // Half the vector length
      (V6_vpackeb (V6_vd0), (Q2V $Qt))),
    (A2_tfrsi -1))>;

def LoVec: OutPatFrag<(ops node:$Vs), (EXTRACT_SUBREG $Vs, vsub_lo)>;
def HiVec: OutPatFrag<(ops node:$Vs), (EXTRACT_SUBREG $Vs, vsub_hi)>;

def HexagonVZERO:  SDNode<"HexagonISD::VZERO",  SDTVecLeaf>;
def HexagonQCAT:   SDNode<"HexagonISD::QCAT",   SDTVecBinOp>;
def HexagonQTRUE:  SDNode<"HexagonISD::QTRUE",  SDTVecLeaf>;
def HexagonQFALSE: SDNode<"HexagonISD::QFALSE", SDTVecLeaf>;
def vzero:  PatFrag<(ops), (HexagonVZERO)>;
def qtrue:  PatFrag<(ops), (HexagonQTRUE)>;
def qfalse: PatFrag<(ops), (HexagonQFALSE)>;
def qcat:   PatFrag<(ops node:$Qs, node:$Qt),
                    (HexagonQCAT node:$Qs, node:$Qt)>;

def qnot: PatFrag<(ops node:$Qs), (xor node:$Qs, qtrue)>;

def VSxtb: OutPatFrag<(ops node:$Vs), (V6_vunpackb  $Vs)>;
def VSxth: OutPatFrag<(ops node:$Vs), (V6_vunpackh  $Vs)>;
def VZxtb: OutPatFrag<(ops node:$Vs), (V6_vunpackub $Vs)>;
def VZxth: OutPatFrag<(ops node:$Vs), (V6_vunpackuh $Vs)>;

def SplatB: SDNodeXForm<imm, [{
  uint32_t V = N->getZExtValue();
  assert(isUInt<8>(V));
  uint32_t S = V << 24 | V << 16 | V << 8 | V;
  return CurDAG->getTargetConstant(S, SDLoc(N), MVT::i32);
}]>;

def SplatH: SDNodeXForm<imm, [{
  uint32_t V = N->getZExtValue();
  assert(isUInt<16>(V));
  return CurDAG->getTargetConstant(V << 16 | V, SDLoc(N), MVT::i32);
}]>;


// HVX loads

multiclass HvxLd_pat<InstHexagon MI, PatFrag Load, ValueType VT,
                     PatFrag ImmPred> {
  def: Pat<(VT (Load I32:$Rt)),                   (MI I32:$Rt, 0)>;
  def: Pat<(VT (Load (add I32:$Rt, ImmPred:$s))), (MI I32:$Rt, imm:$s)>;
  // The HVX selection code for shuffles can generate vector constants.
  // Calling "Select" on the resulting loads from CP fails without these
  // patterns.
  def: Pat<(VT (Load (HexagonCP tconstpool:$A))), (MI (A2_tfrsi imm:$A), 0)>;
  def: Pat<(VT (Load (HexagonAtPcrel tconstpool:$A))),
           (MI (C4_addipc imm:$A), 0)>;
}

let Predicates = [UseHVX] in {
  multiclass HvxLdVs_pat<InstHexagon MI, PatFrag Load> {
    defm: HvxLd_pat<MI, Load, VecI8,  IsVecOff>;
    defm: HvxLd_pat<MI, Load, VecI16, IsVecOff>;
    defm: HvxLd_pat<MI, Load, VecI32, IsVecOff>;
  }
  defm: HvxLdVs_pat<V6_vL32b_nt_ai, alignednontemporalload>;
  defm: HvxLdVs_pat<V6_vL32b_ai,    alignedload>;
  defm: HvxLdVs_pat<V6_vL32Ub_ai,   unalignedload>;

  multiclass HvxLdWs_pat<InstHexagon MI, PatFrag Load> {
    defm: HvxLd_pat<MI, Load, VecPI8,  IsVecOff>;
    defm: HvxLd_pat<MI, Load, VecPI16, IsVecOff>;
    defm: HvxLd_pat<MI, Load, VecPI32, IsVecOff>;
  }
  defm: HvxLdWs_pat<PS_vloadrw_nt_ai, alignednontemporalload>;
  defm: HvxLdWs_pat<PS_vloadrw_ai,    alignedload>;
  defm: HvxLdWs_pat<PS_vloadrwu_ai,   unalignedload>;
}


// HVX stores

multiclass HvxSt_pat<InstHexagon MI, PatFrag Store, PatFrag ImmPred,
                     PatFrag Value> {
  def: Pat<(Store Value:$Vs, I32:$Rt),
           (MI I32:$Rt, 0, Value:$Vs)>;
  def: Pat<(Store Value:$Vs, (add I32:$Rt, ImmPred:$s)),
           (MI I32:$Rt, imm:$s, Value:$Vs)>;
}

let Predicates = [UseHVX] in {
  multiclass HvxStVs_pat<InstHexagon MI, PatFrag Store> {
    defm: HvxSt_pat<MI, Store, IsVecOff, HVI8>;
    defm: HvxSt_pat<MI, Store, IsVecOff, HVI16>;
    defm: HvxSt_pat<MI, Store, IsVecOff, HVI32>;
  }
  defm: HvxStVs_pat<V6_vS32b_nt_ai, alignednontemporalstore>;
  defm: HvxStVs_pat<V6_vS32b_ai,    alignedstore>;
  defm: HvxStVs_pat<V6_vS32Ub_ai,   unalignedstore>;

  multiclass HvxStWs_pat<InstHexagon MI, PatFrag Store> {
    defm: HvxSt_pat<MI, Store, IsVecOff, HWI8>;
    defm: HvxSt_pat<MI, Store, IsVecOff, HWI16>;
    defm: HvxSt_pat<MI, Store, IsVecOff, HWI32>;
  }
  defm: HvxStWs_pat<PS_vstorerw_nt_ai, alignednontemporalstore>;
  defm: HvxStWs_pat<PS_vstorerw_ai,    alignedstore>;
  defm: HvxStWs_pat<PS_vstorerwu_ai,   unalignedstore>;
}


let Predicates = [UseHVX] in {
  def: Pat<(VecI8   vzero), (V6_vd0)>;
  def: Pat<(VecI16  vzero), (V6_vd0)>;
  def: Pat<(VecI32  vzero), (V6_vd0)>;
  // Use V6_vsubw_dv instead.
  def: Pat<(VecPI8  vzero), (Combinev (V6_vd0), (V6_vd0))>;
  def: Pat<(VecPI16 vzero), (Combinev (V6_vd0), (V6_vd0))>;
  def: Pat<(VecPI32 vzero), (Combinev (V6_vd0), (V6_vd0))>;

  def: Pat<(VecPI8 (concat_vectors HVI8:$Vs, HVI8:$Vt)),
           (Combinev HvxVR:$Vt, HvxVR:$Vs)>;
  def: Pat<(VecPI16 (concat_vectors HVI16:$Vs, HVI16:$Vt)),
           (Combinev HvxVR:$Vt, HvxVR:$Vs)>;
  def: Pat<(VecPI32 (concat_vectors HVI32:$Vs, HVI32:$Vt)),
           (Combinev HvxVR:$Vt, HvxVR:$Vs)>;

  def: Pat<(VecQ8  (qcat HQ16:$Qs, HQ16:$Qt)), (Combineq $Qs, $Qt)>;
  def: Pat<(VecQ16 (qcat HQ32:$Qs, HQ32:$Qt)), (Combineq $Qs, $Qt)>;

  def: Pat<(HexagonVEXTRACTW HVI8:$Vu, I32:$Rs),
           (V6_extractw HvxVR:$Vu, I32:$Rs)>;
  def: Pat<(HexagonVEXTRACTW HVI16:$Vu, I32:$Rs),
           (V6_extractw HvxVR:$Vu, I32:$Rs)>;
  def: Pat<(HexagonVEXTRACTW HVI32:$Vu, I32:$Rs),
           (V6_extractw HvxVR:$Vu, I32:$Rs)>;

  def: Pat<(HexagonVINSERTW0 HVI8:$Vu,  I32:$Rt),
           (V6_vinsertwr HvxVR:$Vu, I32:$Rt)>;
  def: Pat<(HexagonVINSERTW0 HVI16:$Vu, I32:$Rt),
           (V6_vinsertwr HvxVR:$Vu, I32:$Rt)>;
  def: Pat<(HexagonVINSERTW0 HVI32:$Vu, I32:$Rt),
           (V6_vinsertwr HvxVR:$Vu, I32:$Rt)>;

  let AddedComplexity = 10 in {
    def: Pat<(VecI8 (HexagonVSPLAT u8_0ImmPred:$V)),
             (V6_lvsplatw (ToI32 (SplatB $V)))>;
    def: Pat<(VecI16 (HexagonVSPLAT u16_0ImmPred:$V)),
             (V6_lvsplatw (ToI32 (SplatH $V)))>;
    def: Pat<(VecI32 (HexagonVSPLAT anyimm:$V)),
             (V6_lvsplatw (ToI32 $V))>;
    def: Pat<(VecPI8 (HexagonVSPLAT u8_0ImmPred:$V)),
             (Combinev (V6_lvsplatw (ToI32 (SplatB $V))),
                       (V6_lvsplatw (ToI32 (SplatB $V))))>;
    def: Pat<(VecPI16 (HexagonVSPLAT u16_0ImmPred:$V)),
             (Combinev (V6_lvsplatw (ToI32 (SplatH $V))),
                       (V6_lvsplatw (ToI32 (SplatH $V))))>;
    def: Pat<(VecPI32 (HexagonVSPLAT anyimm:$V)),
             (Combinev (V6_lvsplatw (ToI32 $V)), (V6_lvsplatw (ToI32 $V)))>;
  }
  def: Pat<(VecI8 (HexagonVSPLAT I32:$Rs)),
           (V6_lvsplatw (S2_vsplatrb I32:$Rs))>;
  def: Pat<(VecI16 (HexagonVSPLAT I32:$Rs)),
           (V6_lvsplatw (A2_combine_ll I32:$Rs, I32:$Rs))>;
  def: Pat<(VecI32 (HexagonVSPLAT I32:$Rs)),
           (V6_lvsplatw I32:$Rs)>;
  def: Pat<(VecPI8 (HexagonVSPLAT I32:$Rs)),
           (Combinev (V6_lvsplatw (S2_vsplatrb I32:$Rs)),
                     (V6_lvsplatw (S2_vsplatrb I32:$Rs)))>;
  def: Pat<(VecPI16 (HexagonVSPLAT I32:$Rs)),
           (Combinev (V6_lvsplatw (A2_combine_ll I32:$Rs, I32:$Rs)),
                     (V6_lvsplatw (A2_combine_ll I32:$Rs, I32:$Rs)))>;
  def: Pat<(VecPI32 (HexagonVSPLAT I32:$Rs)),
           (Combinev (V6_lvsplatw I32:$Rs), (V6_lvsplatw I32:$Rs))>;

  def: Pat<(add HVI8:$Vs,  HVI8:$Vt),   (V6_vaddb    HvxVR:$Vs, HvxVR:$Vt)>;
  def: Pat<(add HVI16:$Vs, HVI16:$Vt),  (V6_vaddh    HvxVR:$Vs, HvxVR:$Vt)>;
  def: Pat<(add HVI32:$Vs, HVI32:$Vt),  (V6_vaddw    HvxVR:$Vs, HvxVR:$Vt)>;
  def: Pat<(add HWI8:$Vs,  HWI8:$Vt),   (V6_vaddb_dv HvxWR:$Vs, HvxWR:$Vt)>;
  def: Pat<(add HWI16:$Vs, HWI16:$Vt),  (V6_vaddh_dv HvxWR:$Vs, HvxWR:$Vt)>;
  def: Pat<(add HWI32:$Vs, HWI32:$Vt),  (V6_vaddw_dv HvxWR:$Vs, HvxWR:$Vt)>;

  def: Pat<(sub HVI8:$Vs,  HVI8:$Vt),   (V6_vsubb    HvxVR:$Vs, HvxVR:$Vt)>;
  def: Pat<(sub HVI16:$Vs, HVI16:$Vt),  (V6_vsubh    HvxVR:$Vs, HvxVR:$Vt)>;
  def: Pat<(sub HVI32:$Vs, HVI32:$Vt),  (V6_vsubw    HvxVR:$Vs, HvxVR:$Vt)>;
  def: Pat<(sub HWI8:$Vs,  HWI8:$Vt),   (V6_vsubb_dv HvxWR:$Vs, HvxWR:$Vt)>;
  def: Pat<(sub HWI16:$Vs, HWI16:$Vt),  (V6_vsubh_dv HvxWR:$Vs, HvxWR:$Vt)>;
  def: Pat<(sub HWI32:$Vs, HWI32:$Vt),  (V6_vsubw_dv HvxWR:$Vs, HvxWR:$Vt)>;

  def: Pat<(and HVI8:$Vs,  HVI8:$Vt),   (V6_vand  HvxVR:$Vs, HvxVR:$Vt)>;
  def: Pat<(or  HVI8:$Vs,  HVI8:$Vt),   (V6_vor   HvxVR:$Vs, HvxVR:$Vt)>;
  def: Pat<(xor HVI8:$Vs,  HVI8:$Vt),   (V6_vxor  HvxVR:$Vs, HvxVR:$Vt)>;

  def: Pat<(vselect HQ8:$Qu, HVI8:$Vs, HVI8:$Vt),
           (V6_vmux HvxQR:$Qu, HvxVR:$Vs, HvxVR:$Vt)>;
  def: Pat<(vselect HQ16:$Qu, HVI16:$Vs, HVI16:$Vt),
           (V6_vmux HvxQR:$Qu, HvxVR:$Vs, HvxVR:$Vt)>;
  def: Pat<(vselect HQ32:$Qu, HVI32:$Vs, HVI32:$Vt),
           (V6_vmux HvxQR:$Qu, HvxVR:$Vs, HvxVR:$Vt)>;

  def: Pat<(vselect (qnot HQ8:$Qu), HVI8:$Vs, HVI8:$Vt),
           (V6_vmux HvxQR:$Qu, HvxVR:$Vt, HvxVR:$Vs)>;
  def: Pat<(vselect (qnot HQ16:$Qu), HVI16:$Vs, HVI16:$Vt),
           (V6_vmux HvxQR:$Qu, HvxVR:$Vt, HvxVR:$Vs)>;
  def: Pat<(vselect (qnot HQ32:$Qu), HVI32:$Vs, HVI32:$Vt),
           (V6_vmux HvxQR:$Qu, HvxVR:$Vt, HvxVR:$Vs)>;

  def: Pat<(VecPI16 (sext HVI8:$Vs)),  (VSxtb $Vs)>;
  def: Pat<(VecPI32 (sext HVI16:$Vs)), (VSxth $Vs)>;
  def: Pat<(VecPI16 (zext HVI8:$Vs)),  (VZxtb $Vs)>;
  def: Pat<(VecPI32 (zext HVI16:$Vs)), (VZxth $Vs)>;

  def: Pat<(VecI16 (sext_invec HVI8:$Vs)),  (LoVec (VSxtb $Vs))>;
  def: Pat<(VecI32 (sext_invec HVI16:$Vs)), (LoVec (VSxth $Vs))>;
  def: Pat<(VecI32 (sext_invec HVI8:$Vs)),
           (LoVec (VSxth (LoVec (VSxtb $Vs))))>;
  def: Pat<(VecPI16 (sext_invec HWI8:$Vss)),  (VSxtb (LoVec $Vss))>;
  def: Pat<(VecPI32 (sext_invec HWI16:$Vss)), (VSxth (LoVec $Vss))>;
  def: Pat<(VecPI32 (sext_invec HWI8:$Vss)),
           (VSxth (LoVec (VSxtb (LoVec $Vss))))>;

  def: Pat<(VecI16 (zext_invec HVI8:$Vs)),  (LoVec (VZxtb $Vs))>;
  def: Pat<(VecI32 (zext_invec HVI16:$Vs)), (LoVec (VZxth $Vs))>;
  def: Pat<(VecI32 (zext_invec HVI8:$Vs)),
           (LoVec (VZxth (LoVec (VZxtb $Vs))))>;
  def: Pat<(VecPI16 (zext_invec HWI8:$Vss)),  (VZxtb (LoVec $Vss))>;
  def: Pat<(VecPI32 (zext_invec HWI16:$Vss)), (VZxth (LoVec $Vss))>;
  def: Pat<(VecPI32 (zext_invec HWI8:$Vss)),
           (VZxth (LoVec (VZxtb (LoVec $Vss))))>;

  // The "source" types are not legal, and there are no parameterized
  // definitions for them, but they are length-specific.
  let Predicates = [UseHVX,UseHVX64B] in {
    def: Pat<(VecI16 (sext_inreg HVI16:$Vs, v32i8)),
             (V6_vasrh (V6_vaslh HVI16:$Vs, (A2_tfrsi 8)), (A2_tfrsi 8))>;
    def: Pat<(VecI32 (sext_inreg HVI32:$Vs, v16i8)),
             (V6_vasrw (V6_vaslw HVI32:$Vs, (A2_tfrsi 24)), (A2_tfrsi 24))>;
    def: Pat<(VecI32 (sext_inreg HVI32:$Vs, v16i16)),
             (V6_vasrw (V6_vaslw HVI32:$Vs, (A2_tfrsi 16)), (A2_tfrsi 16))>;
  }
  let Predicates = [UseHVX,UseHVX128B] in {
    def: Pat<(VecI16 (sext_inreg HVI16:$Vs, v64i8)),
             (V6_vasrh (V6_vaslh HVI16:$Vs, (A2_tfrsi 8)), (A2_tfrsi 8))>;
    def: Pat<(VecI32 (sext_inreg HVI32:$Vs, v32i8)),
             (V6_vasrw (V6_vaslw HVI32:$Vs, (A2_tfrsi 24)), (A2_tfrsi 24))>;
    def: Pat<(VecI32 (sext_inreg HVI32:$Vs, v32i16)),
             (V6_vasrw (V6_vaslw HVI32:$Vs, (A2_tfrsi 16)), (A2_tfrsi 16))>;
  }

  def: Pat<(HexagonVASL HVI8:$Vs, I32:$Rt),
           (V6_vpackeb (V6_vaslh (HiVec (VZxtb HvxVR:$Vs)), I32:$Rt),
                       (V6_vaslh (LoVec (VZxtb HvxVR:$Vs)), I32:$Rt))>;
  def: Pat<(HexagonVASR HVI8:$Vs, I32:$Rt),
           (V6_vpackeb (V6_vasrh (HiVec (VSxtb HvxVR:$Vs)), I32:$Rt),
                       (V6_vasrh (LoVec (VSxtb HvxVR:$Vs)), I32:$Rt))>;
  def: Pat<(HexagonVLSR HVI8:$Vs, I32:$Rt),
           (V6_vpackeb (V6_vlsrh (HiVec (VZxtb HvxVR:$Vs)), I32:$Rt),
                       (V6_vlsrh (LoVec (VZxtb HvxVR:$Vs)), I32:$Rt))>;

  def: Pat<(HexagonVASL HVI16:$Vs, I32:$Rt), (V6_vaslh HvxVR:$Vs, I32:$Rt)>;
  def: Pat<(HexagonVASL HVI32:$Vs, I32:$Rt), (V6_vaslw HvxVR:$Vs, I32:$Rt)>;
  def: Pat<(HexagonVASR HVI16:$Vs, I32:$Rt), (V6_vasrh HvxVR:$Vs, I32:$Rt)>;
  def: Pat<(HexagonVASR HVI32:$Vs, I32:$Rt), (V6_vasrw HvxVR:$Vs, I32:$Rt)>;
  def: Pat<(HexagonVLSR HVI16:$Vs, I32:$Rt), (V6_vlsrh HvxVR:$Vs, I32:$Rt)>;
  def: Pat<(HexagonVLSR HVI32:$Vs, I32:$Rt), (V6_vlsrw HvxVR:$Vs, I32:$Rt)>;

  def: Pat<(shl HVI16:$Vs, HVI16:$Vt), (V6_vaslhv HvxVR:$Vs, HvxVR:$Vt)>;
  def: Pat<(shl HVI32:$Vs, HVI32:$Vt), (V6_vaslwv HvxVR:$Vs, HvxVR:$Vt)>;
  def: Pat<(sra HVI16:$Vs, HVI16:$Vt), (V6_vasrhv HvxVR:$Vs, HvxVR:$Vt)>;
  def: Pat<(sra HVI32:$Vs, HVI32:$Vt), (V6_vasrwv HvxVR:$Vs, HvxVR:$Vt)>;
  def: Pat<(srl HVI16:$Vs, HVI16:$Vt), (V6_vlsrhv HvxVR:$Vs, HvxVR:$Vt)>;
  def: Pat<(srl HVI32:$Vs, HVI32:$Vt), (V6_vlsrwv HvxVR:$Vs, HvxVR:$Vt)>;

  def: Pat<(vnot  HQ8:$Qs), (V6_pred_not HvxQR:$Qs)>;
  def: Pat<(vnot HQ16:$Qs), (V6_pred_not HvxQR:$Qs)>;
  def: Pat<(vnot HQ32:$Qs), (V6_pred_not HvxQR:$Qs)>;
  def: Pat<(qnot  HQ8:$Qs), (V6_pred_not HvxQR:$Qs)>;
  def: Pat<(qnot HQ16:$Qs), (V6_pred_not HvxQR:$Qs)>;
  def: Pat<(qnot HQ32:$Qs), (V6_pred_not HvxQR:$Qs)>;

  def: Pat<(VecQ8 (seteq   HVI8:$Vs,  HVI8:$Vt)),
           (V6_veqb  HvxVR:$Vs, HvxVR:$Vt)>;
  def: Pat<(VecQ8 (setgt   HVI8:$Vs,  HVI8:$Vt)),
           (V6_vgtb  HvxVR:$Vs, HvxVR:$Vt)>;
  def: Pat<(VecQ8 (setugt  HVI8:$Vs,  HVI8:$Vt)),
           (V6_vgtub HvxVR:$Vs, HvxVR:$Vt)>;
  def: Pat<(VecQ16 (seteq  HVI16:$Vs, HVI16:$Vt)),
           (V6_veqh  HvxVR:$Vs, HvxVR:$Vt)>;
  def: Pat<(VecQ16 (setgt  HVI16:$Vs, HVI16:$Vt)),
           (V6_vgth  HvxVR:$Vs, HvxVR:$Vt)>;
  def: Pat<(VecQ16 (setugt HVI16:$Vs, HVI16:$Vt)),
           (V6_vgtuh HvxVR:$Vs, HvxVR:$Vt)>;
  def: Pat<(VecQ32 (seteq  HVI32:$Vs, HVI32:$Vt)),
           (V6_veqw  HvxVR:$Vs, HvxVR:$Vt)>;
  def: Pat<(VecQ32 (setgt  HVI32:$Vs, HVI32:$Vt)),
           (V6_vgtw  HvxVR:$Vs, HvxVR:$Vt)>;
  def: Pat<(VecQ32 (setugt HVI32:$Vs, HVI32:$Vt)),
           (V6_vgtuw HvxVR:$Vs, HvxVR:$Vt)>;

  def: Pat<(VecI8 (trunc HWI16:$Vss)),
           (V6_vpackeb (HiVec $Vss), (LoVec $Vss))>;
  def: Pat<(VecI16 (trunc HWI32:$Vss)),
           (V6_vpackeh (HiVec $Vss), (LoVec $Vss))>;
}

class HvxSel_pat<InstHexagon MI, PatFrag RegPred>
  : Pat<(select I1:$Pu, RegPred:$Vs, RegPred:$Vt),
        (MI I1:$Pu, RegPred:$Vs, RegPred:$Vt)>;

let Predicates = [HasV60T,UseHVX] in {
  def: HvxSel_pat<PS_vselect, HVI8>;
  def: HvxSel_pat<PS_vselect, HVI16>;
  def: HvxSel_pat<PS_vselect, HVI32>;
  def: HvxSel_pat<PS_wselect, HWI8>;
  def: HvxSel_pat<PS_wselect, HWI16>;
  def: HvxSel_pat<PS_wselect, HWI32>;
}

