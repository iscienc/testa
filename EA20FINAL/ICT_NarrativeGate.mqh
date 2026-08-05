//+------------------------------------------------------------------+
//| ICT_NarrativeGate.mqh                                            |
//|     "ICT Unified Professional EA V20"                            |
//+------------------------------------------------------------------+
#ifndef ICT_NARRATIVE_GATE_MQH
#define ICT_NARRATIVE_GATE_MQH

#include "../Core/ICT_Types.mqh"
#include "../Core/ICT_Globals.mqh"
#include "../Core/ICT_Utilities.mqh"
#include "ICT_SMDetectors.mqh"   // ★ Patch F: SM_Detect_* (layer-aware) visible here

int NAR_MinCompletedStages() { return 3; }        // Trigger + Confirmation + Entry

int NAR_MaxChainAgeBars() { return MathMax(20, InpSM_GlobalTimeout); }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool NAR_DirectionAligned(ENUM_TRADE_DIRECTION dir)
  {
   if(dir == DIR_NONE)
      return false;
   if(g_currentDirection == DIR_NONE)
      return true;
   return (dir == g_currentDirection);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool NAR_EnvironmentOK(ENUM_TRADE_DIRECTION dir)
  {
   if(InpUseKillzoneFilter && !IsInKillzone())
      return false;
   return true;                                   // Pure Narrative SM
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
int NAR_CountStageDone(const SSMInstance &inst)
  {
   int n = 0;
   for(int s = 0; s < SM_MAX_STAGES; s++)
      if(inst.stageDone[s])
         n++;
   return n;
  }

//+------------------------------------------------------------------+
//| PATCH F: entry narrative validated on the ENTRY STAGE's TF layer |
//+------------------------------------------------------------------+
bool NAR_HasRequiredNarrativeAtEntry(const SSMInstance &inst)
  {
   const int entryStage = SM_MAX_STAGES - 1;
   SSMStageConfig entryCfg = g_smStageCfg[entryStage];

   // No configured entry element means this gate has no narrative
   // requirement. Preserve the existing contract in that case.
   if(entryCfg.primaryElem == SM_ELEM_NONE &&
      entryCfg.secondaryElem == SM_ELEM_NONE)
      return true;

   ENUM_SM_ELEMENT requiredElem = entryCfg.primaryElem;
   ENUM_TF_LAYER requiredTF = entryCfg.primaryTF;
   double capturedPrice = inst.stagePrimaryPrice[entryStage];

   // For an entry stage with no primary element, use the secondary slot.
   if(requiredElem == SM_ELEM_NONE)
     {
      requiredElem = entryCfg.secondaryElem;
      requiredTF = entryCfg.secondaryTF;
      capturedPrice = inst.stageSecondaryPrice[entryStage];
     }

   if(requiredElem == SM_ELEM_NONE)
      return true;

   // For OR stages, the secondary element may be the one that actually
   // satisfied the stage. Prefer whichever configured slot has a valid
   // captured price. This avoids accepting an unrelated detector.
   if(entryCfg.logic == SM_LOGIC_OR)
     {
      if(entryCfg.primaryElem != SM_ELEM_NONE &&
         inst.stagePrimaryPrice[entryStage] > 0.0)
        {
         requiredElem = entryCfg.primaryElem;
         requiredTF = entryCfg.primaryTF;
         capturedPrice = inst.stagePrimaryPrice[entryStage];
        }
      else if(entryCfg.secondaryElem != SM_ELEM_NONE &&
              inst.stageSecondaryPrice[entryStage] > 0.0)
        {
         requiredElem = entryCfg.secondaryElem;
         requiredTF = entryCfg.secondaryTF;
         capturedPrice = inst.stageSecondaryPrice[entryStage];
        }
     }

   if(capturedPrice <= 0.0)
     {
      // Structural elements such as ChoCh/BOS can legitimately satisfy
      // a stage without returning a zone price. In that case the stage
      // completion itself is the evidence, not a narrative-zone scan.
      bool structuralElement =
         (requiredElem == SM_ELEM_CHOCH_BREAK ||
          requiredElem == SM_ELEM_BOS ||
          requiredElem == SM_ELEM_EXT_SWEEP ||
          requiredElem == SM_ELEM_JUDAS_SWING ||
          requiredElem == SM_ELEM_DISPLACEMENT ||
          requiredElem == SM_ELEM_BODY_CLOSE ||
          requiredElem == SM_ELEM_SMT_DIVERGENCE ||
          requiredElem == SM_ELEM_DR_TARGET_AREA ||
          requiredElem == SM_ELEM_KILLZONE ||
          requiredElem == SM_ELEM_AMD_ACCUMULATION ||
          requiredElem == SM_ELEM_AMD_MANIPULATION ||
          requiredElem == SM_ELEM_AMD_DISTRIBUTION);

      if(structuralElement)
         return true;

      return false;
     }

   // The configured entry element already succeeded and produced a price.
   // The gate must not re-run unrelated detectors. The TF is retained here
   // for diagnostics and future per-layer validation.
   PrintFormat("[NAR][Gate] entry element=%s tf=%d capturedPrice=%.5f",
               SM_ElementShortName(requiredElem),
               (int)requiredTF,
               capturedPrice);
   return true;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool NAR_IsChainTradable(const SSMInstance &inst, string &reason)
  {
   reason = "";
   if(!inst.active)
     {
      reason = "inactive_chain";
      PrintFormat("[SMDBG][GateBlock] chain=%d reason=%s", inst.id, reason);
      return false;
     }

// ★ FIX 1: entry stage must be complete
   if(!inst.stageDone[SM_MAX_STAGES - 1])
     {
      reason = "entry_not_done";
      PrintFormat("[SMDBG][GateBlock] chain=%d reason=%s", inst.id, reason);
      return false;
     }

// ★ FIX 2: every REQUIRED, non-empty stage must be done.
//          Skipped OPTIONAL stages do NOT block the chain.
   for(int s = 0; s < SM_MAX_STAGES; s++)
     {
      if(g_smStageCfg[s].required &&
         g_smStageCfg[s].primaryElem != SM_ELEM_NONE &&
         !inst.stageDone[s])
        {
         reason = "required_stage_incomplete";
         PrintFormat("[SMDBG][GateBlock] chain=%d reason=%s", inst.id, reason);
         return false;
        }
     }

   int age = (inst.stageBarCtr[0] > 0) ? (g_smBarCounter - inst.stageBarCtr[0]) : 0;
   if(age > NAR_MaxChainAgeBars())
     {
      reason = "chain_timeout";
      PrintFormat("[SMDBG][GateBlock] chain=%d reason=%s", inst.id, reason);
      return false;
     }

   ENUM_TRADE_DIRECTION checkDir = SM_ResolveTradeDirection(inst);
   if(!inst.isCounterDirPreset && !NAR_DirectionAligned(checkDir))
     {
      reason = "direction_mismatch";
      PrintFormat("[SMDBG][GateBlock] chain=%d reason=%s", inst.id, reason);
      return false;
     }

   if(!NAR_EnvironmentOK(inst.direction))
     {
      reason = "environment_filter";
      PrintFormat("[SMDBG][GateBlock] chain=%d reason=%s", inst.id, reason);
      return false;
     }
   if(!NAR_HasRequiredNarrativeAtEntry(inst))
     {
      reason = "no_entry_element";
      PrintFormat("[SMDBG][GateBlock] chain=%d reason=%s", inst.id, reason);
      return false;
     }
   return true;
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool IsNarrativeTradable(ENUM_TRADE_DIRECTION dir, string &reason)
  {
   reason = "no_ready_chain";
   for(int i = 0; i < SM_MAX_INSTANCES; i++)
     {
      if(!g_smInstances[i].active)
         continue;
      if(!g_smInstances[i].stageDone[SM_MAX_STAGES - 1])
         continue;

      ENUM_TRADE_DIRECTION instDir = SM_ResolveTradeDirection(g_smInstances[i]);
      if(dir != DIR_NONE && instDir != dir)
         continue;

      string r = "";
      if(NAR_IsChainTradable(g_smInstances[i], r))
        {
         reason = "";
         return true;
        }
      reason = r;
     }
   return false;
  }

#endif
//+------------------------------------------------------------------+
