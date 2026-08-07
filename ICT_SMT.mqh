//+------------------------------------------------------------------+
//|                          ICT_SMT.mqh                              |
//|          Smart Money Technique Divergence Detection               |
//|            "ICT Unified Professional EA V20"                      |
//+------------------------------------------------------------------+
#ifndef ICT_SMT_MQH
#define ICT_SMT_MQH

#include "../Core/ICT_Types.mqh"
#include "../Core/ICT_Globals.mqh"
#include "../Core/ICT_Utilities.mqh"

//+------------------------------------------------------------------+
//|              SECTION 1: INITIALIZATION                             |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Initialize SMT                                                    |
//+------------------------------------------------------------------+
string GetSMTPairSymbol();   // fwd decl: resolver is defined below

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool InitializeSMT()
  {
   g_smtDivergence.Reset();

//--- FIX C8 -------------------------------------------------------
// Resolve the correlated instrument ONCE at init and report it, so a
// missing/renamed symbol is visible in the journal instead of
// silently degrading SMT to a permanent SMT_NONE.
   if(InpSMT_Pair != SMT_PAIR_NONE)
     {
      string s = GetSMTPairSymbol();
      if(s == "")
         Print("SMT Divergence System initialized - CORRELATED SYMBOL UNRESOLVED");
      else
         Print("SMT Divergence System initialized against: ", s);
     }
   else
     {
      Print("SMT Divergence System initialized (disabled: SMT_PAIR_NONE)");
     }

   return true;
  }

//+------------------------------------------------------------------+
//|              SECTION 2: SMT DETECTION                              |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Update SMT Analysis                                               |
//+------------------------------------------------------------------+
void UpdateSMTAnalysis()
  {
   if(!g_needDetectSMT || InpSMT_Pair == SMT_PAIR_NONE)
     {
      g_smtDivergence.status = SMT_NONE;
      return;
     }

// Get correlated pair symbol
   string smtSymbol = GetSMTPairSymbol();

   if(smtSymbol == "")
     {
      g_smtDivergence.status = SMT_NONE;
      return;
     }

// Check if symbol is available
   if(!SymbolSelect(smtSymbol, true))
     {
      g_smtDivergence.status = SMT_NONE;
      return;
     }

// Detect divergence
   DetectSMTDivergence(smtSymbol);
  }

//+------------------------------------------------------------------+
//| Get SMT Pair Symbol                                               |
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| FIX C8 (a)                                                       |
//| Resolve a canonical instrument name to whatever this broker       |
//| actually calls it. Handles suffix style (EURUSD.pro, EURUSD.m,    |
//| EURUSD_raw) and prefix style (mEURUSD, FX_EURUSD).                |
//|                                                                   |
//| Matching is deliberately restricted to PREFIX or SUFFIX position. |
//| A naive StringFind() would match "ES" inside "TESLA" and "NESN".  |
//| Shortest qualifying name wins: on a feed carrying both            |
//| "EURUSD" and "EURUSD.raw", the plain spot symbol is preferred.    |
//+------------------------------------------------------------------+
string SMT_ResolveBrokerSymbol(const string base)
  {
   if(base == "")
      return "";

// Fast path: broker uses the canonical name verbatim.
   if(SymbolSelect(base, true))
      return base;

   int    total   = SymbolsTotal(false);   // FULL list, not Market Watch
   int    baseLen = StringLen(base);
   string best    = "";
   int    bestLen = INT_MAX;

   for(int i = 0; i < total; i++)
     {
      string name = SymbolName(i, false);
      int    pos  = StringFind(name, base);
      if(pos < 0)
         continue;

      bool isPrefix = (pos == 0);
      bool isSuffix = (pos == StringLen(name) - baseLen);
      if(!isPrefix && !isSuffix)
         continue;

      int len = StringLen(name);
      if(len < bestLen)
        {
         bestLen = len;
         best    = name;
        }
     }

   if(best != "" && SymbolSelect(best, true))
      return best;

   return "";
  }

//+------------------------------------------------------------------+
//| FIX C8 (a)                                                       |
//| Cached once per run: SymbolsTotal() scanning is not something to  |
//| do on every bar. Falls back through common feed aliases for the   |
//| index instruments, which almost no broker publishes as DXY/ES/NQ. |
//+------------------------------------------------------------------+
string GetSMTPairSymbol()
  {
   static bool   s_resolved = false;
   static string s_cached   = "";

   if(s_resolved)
      return s_cached;

   string base = "";
   switch(InpSMT_Pair)
     {
      case SMT_PAIR_DXY:
         base = "DXY";
         break;
      case SMT_PAIR_EURUSD:
         base = "EURUSD";
         break;
      case SMT_PAIR_GBPUSD:
         base = "GBPUSD";
         break;
      case SMT_PAIR_USDJPY:
         base = "USDJPY";
         break;
      case SMT_PAIR_XAUUSD:
         base = "XAUUSD";
         break;
      case SMT_PAIR_ES:
         base = "ES";
         break;
      case SMT_PAIR_NQ:
         base = "NQ";
         break;
      default:
         s_resolved = true;
         s_cached   = "";
         return "";
     }

   string found = SMT_ResolveBrokerSymbol(base);

   if(found == "" && InpSMT_Pair == SMT_PAIR_DXY)
     {
      string aliases[] = {"USDX", "USDIDX", "USDOLLAR", "USDINDEX", "DX"};
      for(int i = 0; i < ArraySize(aliases) && found == ""; i++)
         found = SMT_ResolveBrokerSymbol(aliases[i]);
     }

   if(found == "" && InpSMT_Pair == SMT_PAIR_ES)
     {
      string aliases[] = {"SP500", "US500", "SPX500", "USA500"};
      for(int i = 0; i < ArraySize(aliases) && found == ""; i++)
         found = SMT_ResolveBrokerSymbol(aliases[i]);
     }

   if(found == "" && InpSMT_Pair == SMT_PAIR_NQ)
     {
      string aliases[] = {"NAS100", "US100", "USTEC", "NASDAQ", "USATEC"};
      for(int i = 0; i < ArraySize(aliases) && found == ""; i++)
         found = SMT_ResolveBrokerSymbol(aliases[i]);
     }

   s_cached   = found;
   s_resolved = true;

   if(found == "")
      Print("[SMT] WARNING: no broker symbol resolves to '", base,
            "'. SMT divergence will remain SMT_NONE.");
   else
      Print("[SMT] Resolved '", base, "' -> '", found, "'");

   return s_cached;
  }

//+------------------------------------------------------------------+
//| Detect SMT Divergence                                             |
//+------------------------------------------------------------------+
void DetectSMTDivergence(string smtSymbol)
  {
   int lookback = InpSMT_SwingLookback;
   int tolerance = InpSMT_TimeTolerance;


// === ADD THIS BLOCK ===
   int mainBarsAvailable = iBars(_Symbol, PERIOD_CURRENT);
   int smtBarsAvailable = iBars(smtSymbol, PERIOD_CURRENT);

// Ensure lookback doesn't exceed available bars
   if(lookback * 3 >= mainBarsAvailable || lookback * 3 >= smtBarsAvailable)
     {
      lookback = MathMin(mainBarsAvailable, smtBarsAvailable) / 3 - 1;
      if(lookback < 5)
        {
         g_smtDivergence.status = SMT_NONE;
         return;
        }
     }
// === END OF ADDED BLOCK ===

// Find swing points on main symbol
   int mainHighBar = iHighest(_Symbol, PERIOD_CURRENT, MODE_HIGH, lookback, 0);
   int mainLowBar = iLowest(_Symbol, PERIOD_CURRENT, MODE_LOW, lookback, 0);

   double mainHigh = iHigh(_Symbol, PERIOD_CURRENT, mainHighBar);
   double mainLow = iLow(_Symbol, PERIOD_CURRENT, mainLowBar);

// Find swing points on correlated symbol
   int smtHighBar = iHighest(smtSymbol, PERIOD_CURRENT, MODE_HIGH, lookback, 0);
   int smtLowBar = iLowest(smtSymbol, PERIOD_CURRENT, MODE_LOW, lookback, 0);

   double smtHigh = iHigh(smtSymbol, PERIOD_CURRENT, smtHighBar);
   double smtLow = iLow(smtSymbol, PERIOD_CURRENT, smtLowBar);

// Check time alignment
//--- FIX C8 (c) ---------------------------------------------------
// Bar INDICES are NOT comparable across two instruments: different
// session calendars, holidays and data gaps shift them relative to
// one another, so index 7 on EURUSD and index 7 on DXY can be hours
// apart. Align on absolute bar TIME, with the tolerance still
// expressed in bars for input compatibility.
   long tolSec = (long)tolerance * (long)PeriodSeconds(PERIOD_CURRENT);

   datetime mainHighT = iTime(_Symbol,   PERIOD_CURRENT, mainHighBar);
   datetime mainLowT  = iTime(_Symbol,   PERIOD_CURRENT, mainLowBar);
   datetime smtHighT  = iTime(smtSymbol, PERIOD_CURRENT, smtHighBar);
   datetime smtLowT   = iTime(smtSymbol, PERIOD_CURRENT, smtLowBar);

   long dHigh = (long)mainHighT - (long)smtHighT;
   if(dHigh < 0)
      dHigh = -dHigh;
   long dLow  = (long)mainLowT  - (long)smtLowT;
   if(dLow  < 0)
      dLow  = -dLow;

   bool highsAligned = (dHigh <= tolSec);
   bool lowsAligned  = (dLow  <= tolSec);

// Determine correlation type
   bool isInverse = IsInverseCorrelation();

// === BULLISH SMT DIVERGENCE ===
// For inverse pairs (DXY): Main makes LL, Correlated makes HL
// For direct pairs: Main makes LL, Correlated makes LL (but different magnitude)

   bool bullishDivergence = false;
   bool bearishDivergence = false;

   if(isInverse)
     {
      // === BULLISH SMT CHECK (inverse) ===
      // Get previous main swing low
      int prevMainLowStart = mainLowBar + 1;
      int prevMainLowCount = MathMin(lookback, mainBarsAvailable - prevMainLowStart - 1);
      int prevMainLowBar = (prevMainLowCount > 0) ?
                           iLowest(_Symbol, PERIOD_CURRENT, MODE_LOW, prevMainLowCount, prevMainLowStart) : mainLowBar;

      // Get previous SMT swing high
      int prevSmtHighStart = smtHighBar + 1;
      int prevSmtHighCount = MathMin(lookback, smtBarsAvailable - prevSmtHighStart - 1);
      int prevSmtHighBar = (prevSmtHighCount > 0) ?
                           iHighest(smtSymbol, PERIOD_CURRENT, MODE_HIGH, prevSmtHighCount, prevSmtHighStart) : smtHighBar;

      double prevMainLow = iLow(_Symbol, PERIOD_CURRENT, prevMainLowBar);
      double prevSmtHigh = iHigh(smtSymbol, PERIOD_CURRENT, prevSmtHighBar);

      if(mainLow < prevMainLow && smtHigh < prevSmtHigh && lowsAligned)
        {
         bullishDivergence = true;
        }

      // === BEARISH SMT CHECK (inverse) ===
      // Get previous main swing high
      int prevMainHighStart = mainHighBar + 1;
      int prevMainHighCount = MathMin(lookback, mainBarsAvailable - prevMainHighStart - 1);
      int prevMainHighBar = (prevMainHighCount > 0) ?
                            iHighest(_Symbol, PERIOD_CURRENT, MODE_HIGH, prevMainHighCount, prevMainHighStart) : mainHighBar;

      // Get previous SMT swing low
      int prevSmtLowStart = smtLowBar + 1;
      int prevSmtLowCount = MathMin(lookback, smtBarsAvailable - prevSmtLowStart - 1);
      int prevSmtLowBar = (prevSmtLowCount > 0) ?
                          iLowest(smtSymbol, PERIOD_CURRENT, MODE_LOW, prevSmtLowCount, prevSmtLowStart) : smtLowBar;

      double prevMainHigh = iHigh(_Symbol, PERIOD_CURRENT, prevMainHighBar);
      double prevSmtLow = iLow(smtSymbol, PERIOD_CURRENT, prevSmtLowBar);

      if(mainHigh > prevMainHigh && smtLow > prevSmtLow && highsAligned)
        {
         bearishDivergence = true;
        }
     }
   else
     {
      // === BULLISH SMT CHECK (direct) ===
      int prevMainLowStart2 = mainLowBar + 1;
      int prevMainLowCount2 = MathMin(lookback, mainBarsAvailable - prevMainLowStart2 - 1);
      int prevMainLowBar2 = (prevMainLowCount2 > 0) ?
                            iLowest(_Symbol, PERIOD_CURRENT, MODE_LOW, prevMainLowCount2, prevMainLowStart2) : mainLowBar;

      int prevSmtLowStart2 = smtLowBar + 1;
      int prevSmtLowCount2 = MathMin(lookback, smtBarsAvailable - prevSmtLowStart2 - 1);
      int prevSmtLowBar2 = (prevSmtLowCount2 > 0) ?
                           iLowest(smtSymbol, PERIOD_CURRENT, MODE_LOW, prevSmtLowCount2, prevSmtLowStart2) : smtLowBar;

      double prevMainLow2 = iLow(_Symbol, PERIOD_CURRENT, prevMainLowBar2);
      double prevSmtLow2 = iLow(smtSymbol, PERIOD_CURRENT, prevSmtLowBar2);

      //--- FIX C8 (c): direct branch was missing the alignment gate ---
      if(mainLow < prevMainLow2 && smtLow > prevSmtLow2 && lowsAligned)
        {
         bullishDivergence = true;
        }

      // === BEARISH SMT CHECK (direct) ===
      int prevMainHighStart2 = mainHighBar + 1;
      int prevMainHighCount2 = MathMin(lookback, mainBarsAvailable - prevMainHighStart2 - 1);
      int prevMainHighBar2 = (prevMainHighCount2 > 0) ?
                             iHighest(_Symbol, PERIOD_CURRENT, MODE_HIGH, prevMainHighCount2, prevMainHighStart2) : mainHighBar;

      int prevSmtHighStart2 = smtHighBar + 1;
      int prevSmtHighCount2 = MathMin(lookback, smtBarsAvailable - prevSmtHighStart2 - 1);
      int prevSmtHighBar2 = (prevSmtHighCount2 > 0) ?
                            iHighest(smtSymbol, PERIOD_CURRENT, MODE_HIGH, prevSmtHighCount2, prevSmtHighStart2) : smtHighBar;

      double prevMainHigh2 = iHigh(_Symbol, PERIOD_CURRENT, prevMainHighBar2);
      double prevSmtHigh2 = iHigh(smtSymbol, PERIOD_CURRENT, prevSmtHighBar2);

      //--- FIX C8 (c): direct branch was missing the alignment gate ---
      if(mainHigh > prevMainHigh2 && smtHigh < prevSmtHigh2 && highsAligned)
        {
         bearishDivergence = true;
        }
     }

// Update SMT status
   if(bullishDivergence)
     {
      g_smtDivergence.status = SMT_BULLISH_DIV;
      g_smtDivergence.time = iTime(_Symbol, PERIOD_CURRENT, mainLowBar);
      g_smtDivergence.mainPrice = mainLow;
      g_smtDivergence.correlatedPrice = smtHigh;
      g_smtDivergence.isConfirmed = true;
      g_smtDivergence.strength = CalculateSMTStrengthByTime(mainLowT, smtHighT);

      Print("📈 BULLISH SMT Divergence detected!");
     }
   else
      if(bearishDivergence)
        {
         g_smtDivergence.status = SMT_BEARISH_DIV;
         g_smtDivergence.time = iTime(_Symbol, PERIOD_CURRENT, mainHighBar);
         g_smtDivergence.mainPrice = mainHigh;
         g_smtDivergence.correlatedPrice = smtLow;
         g_smtDivergence.isConfirmed = true;
         g_smtDivergence.strength = CalculateSMTStrengthByTime(mainHighT, smtLowT);

         Print("📉 BEARISH SMT Divergence detected!");
        }
      else
        {
         g_smtDivergence.status = SMT_NONE;
         g_smtDivergence.isConfirmed = false;
        }

   g_smtDivergence.correlatedPair = InpSMT_Pair;
  }

//+------------------------------------------------------------------+
//| Check if Inverse Correlation                                      |
//+------------------------------------------------------------------+
bool IsInverseCorrelation()
  {
// DXY is inverse to most pairs
// Gold is inverse to DXY

   switch(InpSMT_Pair)
     {
      case SMT_PAIR_DXY:
         return true;  // DXY is inverse to XAUUSD, EURUSD, etc.

      case SMT_PAIR_XAUUSD:
         return false; // Gold is direct correlation with itself

      default:
         return false; // Most forex pairs are direct
     }
  }

//+------------------------------------------------------------------+
//| Calculate SMT Strength                                            |
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| FIX C8 (c)                                                       |
//| Same 3/2/1 banding as CalculateSMTStrength(), but measured on the |
//| absolute time gap converted to chart bars, so it is valid across  |
//| two instruments with different calendars.                         |
//| CalculateSMTStrength() is kept for source compatibility.          |
//+------------------------------------------------------------------+
int CalculateSMTStrengthByTime(datetime a, datetime b)
  {
   long secs = (long)a - (long)b;
   if(secs < 0)
      secs = -secs;

   long barSec = (long)PeriodSeconds(PERIOD_CURRENT);
   if(barSec <= 0)
      barSec = 60;

   long diff = secs / barSec;

   if(diff <= 1)
      return 3;   // Strong  - simultaneous
   if(diff <= 3)
      return 2;   // Moderate
   return 1;                 // Weak
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
int CalculateSMTStrength(int mainBar, int smtBar)
  {
   int timeDiff = MathAbs(mainBar - smtBar);

   if(timeDiff <= 1)
      return 3; // Strong - simultaneous
   else
      if(timeDiff <= 3)
         return 2; // Moderate
      else
         return 1; // Weak
  }

//+------------------------------------------------------------------+
//|              SECTION 3: CHECK FUNCTIONS                            |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Has SMT Confirmation                                              |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| FIX C8 (b) - STRICT                                              |
//| "An SMT divergence EXISTS and it points our way."                 |
//| This is the ONLY correct semantic for a State Machine stage       |
//| element, which asserts the PRESENCE of a structural event.        |
//| Route SM_ELEM_SMT_DIVERGENCE here.                                |
//+------------------------------------------------------------------+
bool HasSMTDivergence(bool forBullish)
  {
   if(InpSMT_Pair == SMT_PAIR_NONE)
      return false;
   if(!g_needDetectSMT)
      return false;
   if(!g_smtDivergence.isConfirmed)
      return false;
   if(g_smtDivergence.status == SMT_NONE)
      return false;

   return forBullish ? (g_smtDivergence.status == SMT_BULLISH_DIV)
          : (g_smtDivergence.status == SMT_BEARISH_DIV);
  }

//+------------------------------------------------------------------+
//| FIX C8 (b) - SOFT                                                |
//| "Nothing CONTRADICTS us." Absence of divergence passes. Correct   |
//| for a scoring/veto FILTER, categorically wrong for a stage        |
//| element. This is the original HasSMTConfirmation() behaviour,     |
//| preserved verbatim under an honest name.                          |
//+------------------------------------------------------------------+
bool SMTNotContradicting(bool forBullish)
  {
   if(!g_needDetectSMT)
      return true;
   if(InpSMT_Pair == SMT_PAIR_NONE)
      return true;
   if(g_smtDivergence.status == SMT_NONE)
      return true;

   return forBullish ? (g_smtDivergence.status == SMT_BULLISH_DIV)
          : (g_smtDivergence.status == SMT_BEARISH_DIV);
  }

//+------------------------------------------------------------------+
//| DEPRECATED. Retained as an explicit alias to the SOFT semantic so |
//| any remaining filter call site keeps its behaviour unchanged.     |
//| Do NOT use this for SM_ELEM_SMT_DIVERGENCE.                       |
//+------------------------------------------------------------------+
bool HasSMTConfirmation(bool forBullish)
  {
   return SMTNotContradicting(forBullish);
  }

//+------------------------------------------------------------------+
//| Get SMT Score Bonus                                               |
//+------------------------------------------------------------------+
int GetSMTScoreBonus()
  {
   if(!g_needDetectSMT)
      return 0;

   if(g_smtDivergence.status == SMT_NONE || !g_smtDivergence.isConfirmed)
      return 0;

// Check if aligned with current direction
   bool aligned = false;

   if(g_currentDirection == DIR_BULLISH && g_smtDivergence.status == SMT_BULLISH_DIV)
      aligned = true;
   else
      if(g_currentDirection == DIR_BEARISH && g_smtDivergence.status == SMT_BEARISH_DIV)
         aligned = true;

   if(!aligned)
      return 0;

   return g_smtDivergence.strength * 3; // 3-9 points based on strength
  }

//+------------------------------------------------------------------+
//| Get SMT Description                                               |
//+------------------------------------------------------------------+
string GetSMTDescription()
  {
   if(g_smtDivergence.status == SMT_NONE)
      return "No SMT";

   string pair = "";
   switch(g_smtDivergence.correlatedPair)
     {
      case SMT_PAIR_DXY:
         pair = "DXY";
         break;
      case SMT_PAIR_EURUSD:
         pair = "EURUSD";
         break;
      case SMT_PAIR_GBPUSD:
         pair = "GBPUSD";
         break;
      case SMT_PAIR_XAUUSD:
         pair = "XAUUSD";
         break;
      default:
         pair = "???";
     }

   string divType = (g_smtDivergence.status == SMT_BULLISH_DIV) ? "Bullish" : "Bearish";
   string strength = "";
   switch(g_smtDivergence.strength)
     {
      case 3:
         strength = "Strong";
         break;
      case 2:
         strength = "Moderate";
         break;
      case 1:
         strength = "Weak";
         break;
     }

   return divType + " SMT vs " + pair + " (" + strength + ")";
  }

#endif // ICT_SMT_MQH
