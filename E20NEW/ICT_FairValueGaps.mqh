//+------------------------------------------------------------------+
//|                      ICT_FairValueGaps.mqh                        |
//|       Fair Value Gaps, Volume Imbalance, Liquidity Voids          |
//|           "ICT Unified Professional EA V20"                       |
//+------------------------------------------------------------------+
#ifndef ICT_FAIRVALUEGAPS_MQH
#define ICT_FAIRVALUEGAPS_MQH

#include "../Core/ICT_Types.mqh"
#include "../Core/ICT_Globals.mqh"
#include "../Core/ICT_Utilities.mqh"
#include "../UI/ICT_Drawing.mqh"

//+------------------------------------------------------------------+
//|              SECTION 1: INITIALIZATION                            |
//+------------------------------------------------------------------+
bool InitializeNarrative_FVG()
  {
   ArrayResize(g_fvgList, g_maxFVGs);
   ArrayResize(g_viList, g_maxVIs);
   ArrayResize(g_voidList, g_maxVoids);

   g_fvgCount = 0;
   g_viCount = 0;
   g_voidCount = 0;

   Print("FVG System initialized");
   return true;
  }

//+------------------------------------------------------------------+
//|              SECTION 2: FAIR VALUE GAP DETECTION                  |
//+------------------------------------------------------------------+
void DetectAllFVGs()
  {
   if(!g_needDetectFVG)
      return;

   double atr = GetATR();
   if(atr <= 0)
      return;

   bool needBaseFVG = SM_IsElementLoaded(SM_ELEM_FVG) ||
                      SM_IsElementLoaded(SM_ELEM_IFVG) ||
                      SM_IsElementLoaded(SM_ELEM_FVG_CE);

   bool needVI = SM_IsElementLoaded(SM_ELEM_VOLUME_IMBALANCE);
   bool needVoid = SM_IsElementLoaded(SM_ELEM_LIQUIDITY_VOID);

// Base FVG creation/update only if any FVG-family element is required.
   if(needBaseFVG)
     {
      // FIX C3: evaluate only the newly closed middle candle.
      // The old full-lookback scan re-created deleted/filled zones.
      int newBar = 2;
      DetectBullishFVG(newBar, atr);
      DetectBearishFVG(newBar, atr);

      UpdateFVGStatuses();
      CleanupFVGs();
     }

// VI is independent but still part of FVG family runtime.
   if(needVI)
     {
      DetectVolumeImbalances();
      UpdateVIStatuses();
     }

// Liquidity void optional branch.
   if(needVoid)
     {
      DetectLiquidityVoids();
      UpdateVoidStatuses();
     }
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void DetectBullishFVG(int barIndex, double atr)
  {
   double high1 = iHigh(_Symbol, PERIOD_CURRENT, barIndex + 1);
   double low3  = iLow(_Symbol, PERIOD_CURRENT, barIndex - 1);

   double open2  = iOpen(_Symbol, PERIOD_CURRENT, barIndex);
   double close2 = iClose(_Symbol, PERIOD_CURRENT, barIndex);

   if(InpFVG_RequireMiddleCandleDir && close2 <= open2)
      return;

   if(low3 <= high1)
      return;

   double gapSize = low3 - high1;
   if(gapSize < atr * InpFVG_MinSizeATR)
      return;

   double fvgTop = low3;
   double fvgBottom = high1;
   double ce = (fvgTop + fvgBottom) * 0.5;
   datetime sourceTime = iTime(_Symbol, PERIOD_CURRENT, barIndex);
   if(IsFVGIdentityConsumed(sourceTime, FVG_BULLISH))
      return;

   for(int i = 0; i < g_fvgCount; i++)
     {
      if(g_fvgList[i].type == FVG_BULLISH &&
         MathAbs(g_fvgList[i].top - fvgTop) < atr * 0.1)
         return;
     }

   if(g_fvgCount >= g_maxFVGs)
      RemoveOldestFVG();

   int idx = g_fvgCount;
   g_fvgList[idx].Reset();
   g_fvgList[idx].type = FVG_BULLISH;
   g_fvgList[idx].status = FVG_OPEN;
   g_fvgList[idx].top = fvgTop;
   g_fvgList[idx].bottom = fvgBottom;
   g_fvgList[idx].ce = ce;
   g_fvgList[idx].time = sourceTime;
   g_fvgList[idx].barIndex = barIndex;

   if(g_lastSMEvent.valid)
     {
      int evBar = iBarShift(_Symbol, PERIOD_CURRENT, g_lastSMEvent.time, false);
      if(evBar >= 0 && MathAbs(evBar - barIndex) <= 3)
        {
         g_fvgList[idx].causalTag = g_lastSMEvent.tag;   // no direction lock
         g_fvgList[idx].bornDirection = DIR_BULLISH;
         g_fvgList[idx].birthBar  = barIndex;
        }
     }





   g_fvgList[idx].fillPercent = 0;
   g_fvgList[idx].objName = GenerateNarrativeObjectName("FVG");
   g_fvgList[idx].labelName = g_fvgList[idx].objName + "_lbl";

   g_fvgCount++;
   RedrawFVG(idx);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void DetectBearishFVG(int barIndex, double atr)
  {
   double low1  = iLow(_Symbol, PERIOD_CURRENT, barIndex + 1);
   double high3 = iHigh(_Symbol, PERIOD_CURRENT, barIndex - 1);

   double open2  = iOpen(_Symbol, PERIOD_CURRENT, barIndex);
   double close2 = iClose(_Symbol, PERIOD_CURRENT, barIndex);

   if(InpFVG_RequireMiddleCandleDir && close2 >= open2)
      return;

   if(high3 >= low1)
      return;

   double gapSize = low1 - high3;
   if(gapSize < atr * InpFVG_MinSizeATR)
      return;

   double fvgTop = low1;
   double fvgBottom = high3;
   double ce = (fvgTop + fvgBottom) * 0.5;
   datetime sourceTime = iTime(_Symbol, PERIOD_CURRENT, barIndex);
   if(IsFVGIdentityConsumed(sourceTime, FVG_BEARISH))
      return;

   for(int i = 0; i < g_fvgCount; i++)
     {
      if(g_fvgList[i].type == FVG_BEARISH &&
         MathAbs(g_fvgList[i].bottom - fvgBottom) < atr * 0.1)
         return;
     }

   if(g_fvgCount >= g_maxFVGs)
      RemoveOldestFVG();

   int idx = g_fvgCount;
   g_fvgList[idx].Reset();
   g_fvgList[idx].type = FVG_BEARISH;
   g_fvgList[idx].status = FVG_OPEN;
   g_fvgList[idx].top = fvgTop;
   g_fvgList[idx].bottom = fvgBottom;
   g_fvgList[idx].ce = ce;
   g_fvgList[idx].time = sourceTime;
   g_fvgList[idx].barIndex = barIndex;

   if(g_lastSMEvent.valid)
     {
      int evBar = iBarShift(_Symbol, PERIOD_CURRENT, g_lastSMEvent.time, false);
      if(evBar >= 0 && MathAbs(evBar - barIndex) <= 3)
        {
         g_fvgList[idx].causalTag = g_lastSMEvent.tag;   // no direction lock
         g_fvgList[idx].bornDirection = DIR_BEARISH;
         g_fvgList[idx].birthBar  = barIndex;
        }
     }

   g_fvgList[idx].fillPercent = 0;
   g_fvgList[idx].objName = GenerateNarrativeObjectName("FVG");
   g_fvgList[idx].labelName = g_fvgList[idx].objName + "_lbl";

   g_fvgCount++;
   RedrawFVG(idx);
  }

//+------------------------------------------------------------------+
//|              SECTION 3: FVG STATUS UPDATES                        |
//+------------------------------------------------------------------+
void UpdateFVGStatuses()
  {
   if(g_fvgCount <= 0)
      return;

   double barHigh = iHigh(_Symbol, PERIOD_CURRENT, 1);
   double barLow  = iLow(_Symbol, PERIOD_CURRENT, 1);
   datetime barTime = iTime(_Symbol, PERIOD_CURRENT, 1);

   for(int i = 0; i < g_fvgCount; i++)
     {

      if(g_fvgList[i].status == FVG_FULLY_FILLED)
         continue;

      double top = MathMax(g_fvgList[i].top, g_fvgList[i].bottom);
      double bottom = MathMin(g_fvgList[i].top, g_fvgList[i].bottom);
      double height = top - bottom;

      if(height <= 0.0)
         continue;

      bool touched = (barHigh >= bottom && barLow <= top);
      if(!touched)
         continue;

      double fillPrice;

      if(g_fvgList[i].type == FVG_BULLISH)
         fillPrice = MathMax(barLow, bottom);
      else
         fillPrice = MathMin(barHigh, top);

      if(g_fvgList[i].type == FVG_BULLISH)
         g_fvgList[i].fillPercent = MathMin(100.0,
                                            MathMax(0.0, (top - fillPrice) / height * 100.0));
      else
         g_fvgList[i].fillPercent = MathMin(100.0,
                                            MathMax(0.0, (fillPrice - bottom) / height * 100.0));

      bool ceTouched =
         (barLow <= g_fvgList[i].ce && barHigh >= g_fvgList[i].ce);

      if(ceTouched && g_fvgList[i].ceReachedTime == 0)
        {
         g_fvgList[i].ceReachedTime = barTime;
         g_fvgList[i].status = FVG_PARTIALLY_FILLED;
        }

      bool fullyFilled =
         (g_fvgList[i].type == FVG_BULLISH && barLow <= bottom) ||
         (g_fvgList[i].type == FVG_BEARISH && barHigh >= top);

      if(fullyFilled)
        {
         g_fvgList[i].status = FVG_FULLY_FILLED;
         g_fvgList[i].filledTime = barTime;
         g_fvgList[i].fillPercent = 100.0;

         // A bearish FVG violated above becomes bullish IFVG.
         // A bullish FVG violated below becomes bearish IFVG.
         bool violatedForIFVG =
            (g_fvgList[i].type == FVG_BEARISH && barHigh >= top) ||
            (g_fvgList[i].type == FVG_BULLISH && barLow <= bottom);
         if(violatedForIFVG && InpFVG_DetectInverse)
            ConvertFVGToIFVG(i, barTime);

         RememberConsumedFVG(g_fvgList[i].time, g_fvgList[i].type);
        }

      RedrawFVG(i);
     }
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void UpdateVoidStatuses()
  {
   if(g_voidCount <= 0)
      return;

   double barHigh = iHigh(_Symbol, PERIOD_CURRENT, 1);
   double barLow  = iLow(_Symbol, PERIOD_CURRENT, 1);

   for(int i = 0; i < g_voidCount; i++)
     {

      if(g_voidList[i].isFilled)
         continue;

      double top = MathMax(g_voidList[i].top, g_voidList[i].bottom);
      double bottom = MathMin(g_voidList[i].top, g_voidList[i].bottom);

      bool touched = (barHigh >= bottom && barLow <= top);
      bool fullyFilled = (barLow <= bottom && barHigh >= top);

      // Treat a closed-bar touch as mitigation for entry purposes. A
      // void that has been traded back into is no longer a fresh void.
      if(touched || fullyFilled)
        {
         g_voidList[i].isFilled = true;

         if(ObjectFind(0, g_voidList[i].objName) >= 0)
            ObjectSetInteger(
               0,
               g_voidList[i].objName,
               OBJPROP_COLOR,
               clrDimGray
            );
        }
     }
  }

//+------------------------------------------------------------------+
//|              SECTION 4: VOLUME IMBALANCE                          |
//+------------------------------------------------------------------+
void DetectVolumeImbalances()
  {
   if(!ShouldDrawNarrativeElement(NZ_VOLUME_IMBALANCE) &&
      !SM_IsElementLoaded(SM_ELEM_VOLUME_IMBALANCE))
      return;

   double atr = GetATR();
   if(atr <= 0.0)
      return;

// Detect only the newly closed adjacent pair: bars 2 and 1.
// The body-gap must exist while full ranges still overlap.
   int older = 2;
   int newer = 1;

   double olderOpen  = iOpen(_Symbol, PERIOD_CURRENT, older);
   double olderClose = iClose(_Symbol, PERIOD_CURRENT, older);
   double olderHigh  = iHigh(_Symbol, PERIOD_CURRENT, older);
   double olderLow   = iLow(_Symbol, PERIOD_CURRENT, older);
   double newerOpen  = iOpen(_Symbol, PERIOD_CURRENT, newer);
   double newerClose = iClose(_Symbol, PERIOD_CURRENT, newer);
   double newerHigh  = iHigh(_Symbol, PERIOD_CURRENT, newer);
   double newerLow   = iLow(_Symbol, PERIOD_CURRENT, newer);

   double olderBodyTop = MathMax(olderOpen, olderClose);
   double olderBodyBot = MathMin(olderOpen, olderClose);
   double newerBodyTop = MathMax(newerOpen, newerClose);
   double newerBodyBot = MathMin(newerOpen, newerClose);

// Bullish VI: the newer candle opens above the older body and its
// lower wick overlaps the older upper range.
   if(newerBodyBot > olderBodyTop && newerLow <= olderHigh)
     {
      double top = newerBodyBot;
      double bottom = olderBodyTop;
      if(top - bottom >= atr * 0.10)
         AddVolumeImbalance(VI_BULLISH, top, bottom,
                            iTime(_Symbol, PERIOD_CURRENT, newer), newer);
     }

// Bearish VI: the newer candle opens below the older body and its
// upper wick overlaps the older lower range.
   if(newerBodyTop < olderBodyBot && newerHigh >= olderLow)
     {
      double top = olderBodyBot;
      double bottom = newerBodyTop;
      if(top - bottom >= atr * 0.10)
         AddVolumeImbalance(VI_BEARISH, top, bottom,
                            iTime(_Symbol, PERIOD_CURRENT, newer), newer);
     }
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void UpdateVIStatuses()
  {
   double currentPrice = iClose(_Symbol, PERIOD_CURRENT, 1);

   for(int i = g_viCount - 1; i >= 0; i--)
     {
      if(g_viList[i].isFilled)
         continue;

      if(g_viList[i].type == VI_BULLISH)
        {
         if(currentPrice <= g_viList[i].bottom)
           {
            g_viList[i].isFilled = true;
            if(ObjectFind(0, g_viList[i].objName) >= 0)
               ObjectSetInteger(0, g_viList[i].objName, OBJPROP_COLOR, clrDimGray);
           }
        }
      else
        {
         if(currentPrice >= g_viList[i].top)
           {
            g_viList[i].isFilled = true;
            if(ObjectFind(0, g_viList[i].objName) >= 0)
               ObjectSetInteger(0, g_viList[i].objName, OBJPROP_COLOR, clrDimGray);
           }
        }
     }
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void AddVolumeImbalance(ENUM_VI_TYPE type, double top, double bottom, datetime time, int barIndex)
  {
   for(int i = 0; i < g_viCount; i++)
     {
      if(g_viList[i].type == type && MathAbs(g_viList[i].top - top) < _Point * 20)
         return;
     }
   if(g_viCount >= g_maxVIs)
     {
      // Evict the oldest record instead of freezing VI detection forever.
      int oldest = 0;
      for(int j = 1; j < g_viCount; j++)
         if(g_viList[j].time < g_viList[oldest].time)
            oldest = j;
      DeleteObject(g_viList[oldest].objName);
      for(int j = oldest; j < g_viCount - 1; j++)
         g_viList[j] = g_viList[j + 1];
      g_viCount--;
     }

   int idx = g_viCount;
   g_viList[idx].Reset();
   g_viList[idx].type = type;
   g_viList[idx].top = top;
   g_viList[idx].bottom = bottom;
   g_viList[idx].time = time;
   g_viList[idx].barIndex = barIndex;
   g_viList[idx].isFilled = false;
   g_viList[idx].objName = GenerateNarrativeObjectName("VI");

   if(g_lastSMEvent.valid)
     {
      int evBar = iBarShift(_Symbol, PERIOD_CURRENT, g_lastSMEvent.time, false);
      if(evBar >= 0 && MathAbs(evBar - barIndex) <= 3)
        {
         g_viList[idx].causalTag = g_lastSMEvent.tag;
         g_viList[idx].bornDirection = (type == VI_BULLISH) ? DIR_BULLISH : DIR_BEARISH;
         g_viList[idx].birthBar = barIndex;
        }
     }

   g_viCount++;

   if(ShouldDrawNarrativeElement(NZ_VOLUME_IMBALANCE))
     {
      datetime endTime = iTime(_Symbol, PERIOD_CURRENT, 0);
      bool isBull = (type == VI_BULLISH);
      color viColor = isBull ? ColorLighten(InpBullFVG_Color, 30) : ColorLighten(InpBearFVG_Color, 30);

      DrawRectangle(g_viList[idx].objName, time, top, endTime, bottom, viColor, true);

      string lbl = BuildElementLabel(LAYER_CTF, isBull, "VI");
      string lblName = g_viList[idx].objName + "_lbl";
      double mid = (top + bottom) * 0.5;
      DrawText(lblName, time, mid, lbl, clrWhite, 7, ANCHOR_LEFT);
     }
  }

//+------------------------------------------------------------------+
//|              SECTION 5: LIQUIDITY VOID                            |
//+------------------------------------------------------------------+
void DetectLiquidityVoids()
  {
   if(!ShouldDrawNarrativeElement(NZ_LIQUIDITY_VOID) &&
      !SM_IsElementLoaded(SM_ELEM_LIQUIDITY_VOID))
     {
      return;
     }

   double atr = GetATR();
   if(atr <= 0)
      return;

// FIX H5: inspect the full configured window, but only closed bars.
   int maxScan = MathMin(InpFVG_Lookback, iBars(_Symbol, PERIOD_CURRENT) - 3);
   for(int i = maxScan; i >= 2; i--)
     {
      double high = iHigh(_Symbol, PERIOD_CURRENT, i);
      double low = iLow(_Symbol, PERIOD_CURRENT, i);
      double range = high - low;

      if(range < atr * InpVoid_MinSizeATR)
         continue;

      double open = iOpen(_Symbol, PERIOD_CURRENT, i);
      double close = iClose(_Symbol, PERIOD_CURRENT, i);

      double prevHigh = iHigh(_Symbol, PERIOD_CURRENT, i + 1);
      double prevLow = iLow(_Symbol, PERIOD_CURRENT, i + 1);
      double nextHigh = iHigh(_Symbol, PERIOD_CURRENT, i - 1);
      double nextLow = iLow(_Symbol, PERIOD_CURRENT, i - 1);

      if(close > open)
        {
         double voidTop = high;
         double voidBottom = MathMax(prevHigh, nextHigh);

         if(voidTop > voidBottom + atr * 0.2)
            AddLiquidityVoid(VOID_BULLISH, voidTop, voidBottom, iTime(_Symbol, PERIOD_CURRENT, i), i);
        }
      else
        {
         double voidTop = MathMin(prevLow, nextLow);
         double voidBottom = low;

         if(voidTop > voidBottom + atr * 0.2)
            AddLiquidityVoid(VOID_BEARISH, voidTop, voidBottom, iTime(_Symbol, PERIOD_CURRENT, i), i);
        }
     }
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void AddLiquidityVoid(ENUM_VOID_TYPE type, double top, double bottom, datetime time, int barIndex)
  {
   for(int i = 0; i < g_voidCount; i++)
     {
      if(g_voidList[i].type == type && MathAbs(g_voidList[i].top - top) < _Point * 30)
         return;
     }

if(g_voidCount >= g_maxVoids)
     {
      int oldest = 0;
      for(int j = 1; j < g_voidCount; j++)
         if(g_voidList[j].startTime < g_voidList[oldest].startTime)
            oldest = j;

      DeleteObject(g_voidList[oldest].objName);
      for(int j = oldest; j < g_voidCount - 1; j++)
         g_voidList[j] = g_voidList[j + 1];
      g_voidCount--;
     }

   int idx = g_voidCount;
   g_voidList[idx].Reset();
   g_voidList[idx].type = type;
   g_voidList[idx].top = top;
   g_voidList[idx].bottom = bottom;
   g_voidList[idx].startTime = time;
   g_voidList[idx].startBar = barIndex;
   g_voidList[idx].isFilled = false;
   g_voidList[idx].objName = GenerateNarrativeObjectName("Void");

   if(g_lastSMEvent.valid)
     {
      int evBar = iBarShift(_Symbol, PERIOD_CURRENT, g_lastSMEvent.time, false);
      if(evBar >= 0 && MathAbs(evBar - barIndex) <= 3)
        {
         g_voidList[idx].causalTag = g_lastSMEvent.tag;
         g_voidList[idx].bornDirection = (type == VOID_BULLISH) ? DIR_BULLISH : DIR_BEARISH;
         g_voidList[idx].birthBar = barIndex;
        }
     }

   g_voidCount++;

   if(ShouldDrawNarrativeElement(NZ_LIQUIDITY_VOID))
     {
      datetime endTime = iTime(_Symbol, PERIOD_CURRENT, 0);
      bool isBull = (type == VOID_BULLISH);
      string label = BuildElementLabel(LAYER_CTF, isBull, "Void");
      color voidColor = isBull ? ColorLighten(InpBullFVG_Color, 50) : ColorLighten(InpBearFVG_Color, 50);

      DrawRectangle(g_voidList[idx].objName, time, top, endTime, bottom, voidColor, true);

      string lblName = g_voidList[idx].objName + "_lbl";
      DrawText(lblName, time, (top + bottom) * 0.5, label, clrWhite, 7, ANCHOR_LEFT);
     }
  }

//+------------------------------------------------------------------+
//|              SECTION 6: CLEANUP                                   |
//+------------------------------------------------------------------+
void RemoveOldestFVG()
  {
   if(g_fvgCount == 0)
      return;

   int oldestIdx = 0;
   datetime oldestTime = g_fvgList[0].time;

   for(int i = 1; i < g_fvgCount; i++)
     {
      if(g_fvgList[i].time < oldestTime)
        {
         oldestTime = g_fvgList[i].time;
         oldestIdx = i;
        }
     }

   DeleteObject(g_fvgList[oldestIdx].objName);
   DeleteObject(g_fvgList[oldestIdx].labelName);

   for(int j = oldestIdx; j < g_fvgCount - 1; j++)
      g_fvgList[j] = g_fvgList[j + 1];

   g_fvgCount--;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void ConvertFVGToIFVG(int fvgIndex, datetime violatedTime)
  {
   if(fvgIndex < 0 || fvgIndex >= g_fvgCount)
      return;

   SFairValueGap src = g_fvgList[fvgIndex];
   ENUM_TRADE_DIRECTION flipped =
      (src.type == FVG_BEARISH) ? DIR_BULLISH : DIR_BEARISH;

   for(int i = 0; i < g_ifvgCount; i++)
      if(g_ifvgList[i].sourceTime == src.time &&
         g_ifvgList[i].direction == flipped)
         return;

   if(g_ifvgCount >= ICT_MAX_IFVGS)
     {
      for(int j = 1; j < g_ifvgCount; j++)
         g_ifvgList[j-1] = g_ifvgList[j];
      g_ifvgCount--;
     }

   int idx = g_ifvgCount++;
   g_ifvgList[idx].Reset();
   g_ifvgList[idx].sourceType = src.type;
   g_ifvgList[idx].direction = flipped;
   g_ifvgList[idx].top = MathMax(src.top, src.bottom);
   g_ifvgList[idx].bottom = MathMin(src.top, src.bottom);
   g_ifvgList[idx].ce = src.ce;
   g_ifvgList[idx].sourceTime = src.time;
   g_ifvgList[idx].violatedTime = violatedTime;
   g_ifvgList[idx].sourceBarIndex = src.barIndex;
   g_ifvgList[idx].causalTag = src.causalTag;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void CleanupFVGs()
  {
   datetime cutoffTime = iTime(_Symbol, PERIOD_CURRENT, 0) - 86400 * 2;

   for(int i = g_fvgCount - 1; i >= 0; i--)
     {
      if(g_fvgList[i].time < cutoffTime || g_fvgList[i].status == FVG_FULLY_FILLED)
        {
         DeleteObject(g_fvgList[i].objName);
         DeleteObject(g_fvgList[i].labelName);

         for(int j = i; j < g_fvgCount - 1; j++)
            g_fvgList[j] = g_fvgList[j + 1];

         g_fvgCount--;
        }
     }
  }

//+------------------------------------------------------------------+
//|              SECTION 7: DRAWING                                   |
//+------------------------------------------------------------------+
void RedrawFVG(int index)
  {
   if(index >= g_fvgCount)
      return;

   if(!ShouldDrawNarrativeElement(NZ_FVG))
      return;

   bool isBull = (g_fvgList[index].type == FVG_BULLISH);
   string label = BuildElementLabel(LAYER_CTF, isBull, "FVG");

   datetime endTime = iTime(_Symbol, PERIOD_CURRENT, 0);

   DrawFVG(g_fvgList[index].objName,
           g_fvgList[index].time,
           g_fvgList[index].top,
           g_fvgList[index].bottom,
           endTime,
           g_fvgList[index].type,
           g_fvgList[index].status,
           g_fvgList[index].ce,
           label);

// Optional CE overlay line only if CE element is loaded and chart rendering is enabled.
   if(g_fvgList[index].status == FVG_OPEN &&
      SM_IsElementLoaded(SM_ELEM_FVG_CE) &&
      ShouldDrawNarrativeElement(NZ_FVG_CE))
     {
      string ceName = g_fvgList[index].objName + "_ce";
      color ceColor = isBull ? ColorLighten(InpBullFVG_Color, 50) : ColorLighten(InpBearFVG_Color, 50);

      DrawTrendLine(ceName,
                    g_fvgList[index].time, g_fvgList[index].ce,
                    endTime, g_fvgList[index].ce,
                    ceColor, 1, STYLE_DOT, false);
     }
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void ExtendFVGRectangles()
  {
   if(!ShouldDrawNarrativeElement(NZ_FVG))
      return;

   datetime currentTime = iTime(_Symbol, PERIOD_CURRENT, 0);

   for(int i = 0; i < g_fvgCount; i++)
     {
      if(g_fvgList[i].status != FVG_FULLY_FILLED)
        {
         if(ObjectFind(0, g_fvgList[i].objName) >= 0)
            ObjectSetInteger(0, g_fvgList[i].objName, OBJPROP_TIME, 1, currentTime);
        }
     }
  }

//+------------------------------------------------------------------+
//|              SECTION 8: CHECK FUNCTIONS                           |
//+------------------------------------------------------------------+
bool IsPriceInFVG(bool lookForBullish, int &outIndex)
  {
   double price = iClose(_Symbol, PERIOD_CURRENT, 0);

   for(int i = 0; i < g_fvgCount; i++)
     {
      if(g_fvgList[i].status == FVG_FULLY_FILLED)
         continue;

      bool isBullishFVG = (g_fvgList[i].type == FVG_BULLISH);
      if(lookForBullish == isBullishFVG)
        {
         if(price >= g_fvgList[i].bottom && price <= g_fvgList[i].top)
           {
            outIndex = i;
            return true;
           }
        }
     }

   return false;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool IsPriceAtFVGCE(bool lookForBullish, int causalTag, int &outIndex)
  {
   outIndex = -1;
   double price = iClose(_Symbol, PERIOD_CURRENT, 0);
   double atr = GetATR();
   double tol = (atr > 0) ? atr * 0.03 : _Point * 10;

   for(int i = 0; i < g_fvgCount; i++)
     {
      if(g_fvgList[i].status == FVG_FULLY_FILLED)
         continue;

      bool bullFVG = (g_fvgList[i].type == FVG_BULLISH);
      if(bullFVG != lookForBullish)
         continue;

      if(causalTag >= 0 && g_fvgList[i].causalTag != causalTag)
         continue;

      if(MathAbs(price - g_fvgList[i].ce) <= tol)
        {
         outIndex = i;
         return true;
        }
     }

   return false;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool IsPriceAtVolumeImbalance(bool lookForBullish, int causalTag, int &outIndex)
  {
   outIndex = -1;
   double price = iClose(_Symbol, PERIOD_CURRENT, 0);

   for(int i = 0; i < g_viCount; i++)
     {
      if(g_viList[i].isFilled)
         continue;

      bool bullVI = (g_viList[i].type == VI_BULLISH);
      if(bullVI != lookForBullish)
         continue;

      if(causalTag >= 0 && g_viList[i].causalTag != causalTag)
         continue;

      double top = MathMax(g_viList[i].top, g_viList[i].bottom);
      double bottom = MathMin(g_viList[i].top, g_viList[i].bottom);
      if(price >= bottom && price <= top)
        {
         outIndex = i;
         return true;
        }
     }

   return false;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool IsPriceAtLiquidityVoid(bool lookForBullish, int causalTag, int &outIndex)
  {
   outIndex = -1;
   double price = iClose(_Symbol, PERIOD_CURRENT, 0);

   for(int i = 0; i < g_voidCount; i++)
     {
      if(g_voidList[i].isFilled)
         continue;

      bool bullVoid = (g_voidList[i].type == VOID_BULLISH);
      if(bullVoid != lookForBullish)
         continue;

      if(causalTag >= 0 && g_voidList[i].causalTag != causalTag)
         continue;

      double top = MathMax(g_voidList[i].top, g_voidList[i].bottom);
      double bottom = MathMin(g_voidList[i].top, g_voidList[i].bottom);
      if(price >= bottom && price <= top)
        {
         outIndex = i;
         return true;
        }
     }

   return false;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool IsPriceInIFVG(bool lookForBullish, int causalTag, int &outIndex)
  {
   outIndex = -1;
   if(!InpFVG_DetectInverse)
      return false;

   double price = iClose(_Symbol, PERIOD_CURRENT, 0);
   for(int i = 0; i < g_ifvgCount; i++)
     {
      SInvertedFVG v = g_ifvgList[i];
      if(v.invalidated || v.retested)
         continue;
      if((v.direction == DIR_BULLISH) != lookForBullish)
         continue;
      if(causalTag >= 0 && v.causalTag != causalTag)
         continue;

      if(price >= v.bottom && price <= v.top)
        {
         g_ifvgList[i].retested = true;
         outIndex = i;
         return true;
        }
     }
   return false;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
int GetOpenFVGCount(bool isBullish)
  {
   int count = 0;
   for(int i = 0; i < g_fvgCount; i++)
     {
      if(g_fvgList[i].status == FVG_OPEN)
        {
         bool isBullishFVG = (g_fvgList[i].type == FVG_BULLISH);
         if(isBullish == isBullishFVG)
            count++;
        }
     }
   return count;
  }

#endif // ICT_FAIRVALUEGAPS_MQH
//+------------------------------------------------------------------+
