//+------------------------------------------------------------------+
//| SMC ICT AMD Signal Trader - Multi-Chart Robust                   |
//+------------------------------------------------------------------+
#property copyright "SMC AMD Signal v2.30"
#property link      "https://www.mql5.com"
#property version   "2.30"
#property strict

// --- Paramètres ---
input string RangeStartTime = "01:00"; 
input string RangeEndTime   = "08:00"; 
input bool DrawOnChart = true; 
input color ColorRangeBox = clrMidnightBlue;
input color ColorSellSignal = clrRed;
input color ColorBuySignal = clrLime;

// --- Alertes ---
input bool SendPopupAlerts = true; 

struct SymbolState {
   string name;
   int lastDayChecked;
   double rangeHigh;
   double rangeLow;
   double highestSweep; 
   double lowestSweep;
   bool highSwept;
   bool lowSwept;
   bool signalSent;     
   bool targetHit;
   int signalDirection; // 1 pour Buy, -1 pour Sell
};

SymbolState MarketState[];

//+------------------------------------------------------------------+
int OnInit()
{
   Print("ICT AMD Signal Trader v2.30 Running (No Telegram)...");
   EventSetTimer(15); 
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   long currChart = ChartFirst();
   while(currChart != -1) {
      ObjectsDeleteAll(currChart, "AMD_");
      ChartRedraw(currChart);
      currChart = ChartNext(currChart);
   }
}

//+------------------------------------------------------------------+
void OnTimer()
{
   MqlDateTime dt;
   TimeCurrent(dt);
   int endMin = TimeStringToMinutes(RangeEndTime);
   int currentMin = dt.hour * 60 + dt.min;
   
   // Si on est dans le range, on ne trade pas encore
   if(currentMin <= endMin) return; 

   int total = SymbolsTotal(true); 
   
   for(int i=0; i<total; i++)
   {
      string sym = SymbolName(i, true);
      if(!SymbolInfoInteger(sym, SYMBOL_SELECT)) continue;

      int idx = GetSymbolIndex(sym);
      
      // Reset journalier
      if(MarketState[idx].lastDayChecked != dt.day_of_year) {
         MarketState[idx].lastDayChecked = dt.day_of_year;
         MarketState[idx].rangeHigh = 0;
         MarketState[idx].rangeLow = 0;
         MarketState[idx].highestSweep = 0;
         MarketState[idx].lowestSweep = 9999999;
         MarketState[idx].highSwept = false;
         MarketState[idx].lowSwept = false;
         MarketState[idx].signalSent = false;
         MarketState[idx].targetHit = false;
         MarketState[idx].signalDirection = 0;
      }
      
      // 1. Calcul du Range
      double h, l;
      if(CalculateRange(sym, RangeStartTime, RangeEndTime, h, l)) {
         MarketState[idx].rangeHigh = h;
         MarketState[idx].rangeLow = l;
         
         if(DrawOnChart) {
            DrawRangeBox(sym, RangeStartTime, RangeEndTime, h, l);
            if(!MarketState[idx].signalSent) DrawStatus(sym, "Active: Waiting for Sweep");
         }
      } else continue;
      
      if(MarketState[idx].targetHit) {
         if(DrawOnChart) DrawStatus(sym, "Target Hit (Done)");
         continue;
      }

      double bid = SymbolInfoDouble(sym, SYMBOL_BID);
      
      // 2. LOGIQUE TRADING (AMD)
      
      // --- LOGIQUE VENTE (Manipulation Haute) ---
      if(bid > MarketState[idx].rangeHigh) {
         MarketState[idx].highSwept = true;
         if(bid > MarketState[idx].highestSweep) MarketState[idx].highestSweep = bid;
         if(DrawOnChart) DrawStatus(sym, "High Swept! Watch for Sell Reversal");
      }
      else if(MarketState[idx].highSwept && !MarketState[idx].signalSent && bid < MarketState[idx].rangeHigh) {
         MarketState[idx].signalSent = true;
         MarketState[idx].signalDirection = -1;
         
         double sl = MarketState[idx].highestSweep; 
         double tp = MarketState[idx].rangeLow;     

         string msg = "🔫 SIGNAL VENTE (AMD) : " + sym + " @ " + DoubleToString(bid, _Digits);
         Print(msg);
         if(SendPopupAlerts) Alert(msg);
         
         if(DrawOnChart) DrawSignal(sym, bid, sl, tp, ColorSellSignal, 234);
      }
      
      // --- LOGIQUE ACHAT (Manipulation Basse) ---
      if(bid < MarketState[idx].rangeLow) {
         MarketState[idx].lowSwept = true;
         if(bid < MarketState[idx].lowestSweep) MarketState[idx].lowestSweep = bid;
         if(DrawOnChart) DrawStatus(sym, "Low Swept! Watch for Buy Reversal");
      }
      else if(MarketState[idx].lowSwept && !MarketState[idx].signalSent && bid > MarketState[idx].rangeLow) {
         MarketState[idx].signalSent = true;
         MarketState[idx].signalDirection = 1;
         
         double sl = MarketState[idx].lowestSweep;
         double tp = MarketState[idx].rangeHigh;

         string msg = "🚀 SIGNAL ACHAT (AMD) : " + sym + " @ " + DoubleToString(bid, _Digits);
         Print(msg);
         if(SendPopupAlerts) Alert(msg);
         
         if(DrawOnChart) DrawSignal(sym, bid, sl, tp, ColorBuySignal, 233);
      }
      
      // 3. GESTION DES TARGETS (TP)
      if(MarketState[idx].signalSent && !MarketState[idx].targetHit) {
         // Check TP Vente
         if(MarketState[idx].signalDirection == -1 && bid <= MarketState[idx].rangeLow) {
            MarketState[idx].targetHit = true;
         }
         // Check TP Achat
         if(MarketState[idx].signalDirection == 1 && bid >= MarketState[idx].rangeHigh) {
            MarketState[idx].targetHit = true;
         }
         
         if(MarketState[idx].targetHit && DrawOnChart) DrawStatus(sym, "Target Hit (Done)");
      }
      
      // Maintien du dessin du signal si actif
      if(MarketState[idx].signalSent && !MarketState[idx].targetHit && DrawOnChart) {
         string dirText = (MarketState[idx].signalDirection == 1) ? "BUY ACTIVE" : "SHORT ACTIVE";
         DrawStatus(sym, dirText);
      }
   }
}

//+------------------------------------------------------------------+
// --- Fonctions de Dessin ---
//+------------------------------------------------------------------+
void DrawRangeBox(string sym, string tStart, string tEnd, double h, double l) {
   long currChart = ChartFirst();
   while(currChart != -1) {
      if(ChartSymbol(currChart) == sym) {
         string objName = "AMD_Box";
         if(ObjectFind(currChart, objName) < 0) {
            datetime now = TimeCurrent(); 
            datetime dtDayStart = now - (now % 86400);
            datetime d1 = dtDayStart + StringToTime("1970.01.01 " + tStart);
            datetime d2 = dtDayStart + StringToTime("1970.01.01 " + tEnd);
            ObjectCreate(currChart, objName, OBJ_RECTANGLE, 0, d1, h, d2, l);
            ObjectSetInteger(currChart, objName, OBJPROP_COLOR, ColorRangeBox);
            ObjectSetInteger(currChart, objName, OBJPROP_FILL, (long)true);
            ObjectSetInteger(currChart, objName, OBJPROP_BACK, (long)true);
         }
         ChartRedraw(currChart);
      }
      currChart = ChartNext(currChart);
   }
}

void DrawSignal(string sym, double entry, double sl, double tp, color sigColor, int arrowCode) {
   long currChart = ChartFirst();
   while(currChart != -1) {
      if(ChartSymbol(currChart) == sym) {
         // SL Line
         string slName = "AMD_SL";
         ObjectDelete(currChart, slName);
         ObjectCreate(currChart, slName, OBJ_HLINE, 0, 0, sl);
         ObjectSetInteger(currChart, slName, OBJPROP_COLOR, sigColor);
         ObjectSetInteger(currChart, slName, OBJPROP_STYLE, STYLE_DASH);
         
         // TP Line
         string tpName = "AMD_TP";
         ObjectDelete(currChart, tpName);
         ObjectCreate(currChart, tpName, OBJ_HLINE, 0, 0, tp);
         ObjectSetInteger(currChart, tpName, OBJPROP_COLOR, clrLimeGreen);
         ObjectSetInteger(currChart, tpName, OBJPROP_WIDTH, 2);
         
         // Arrow
         string arrName = "AMD_Arrow";
         if(ObjectFind(currChart, arrName) < 0) {
            ObjectCreate(currChart, arrName, OBJ_ARROW, 0, TimeCurrent(), entry);
            ObjectSetInteger(currChart, arrName, OBJPROP_ARROWCODE, arrowCode); 
            ObjectSetInteger(currChart, arrName, OBJPROP_COLOR, sigColor);
            ObjectSetInteger(currChart, arrName, OBJPROP_WIDTH, 4);
         }
         ChartRedraw(currChart);
      }
      currChart = ChartNext(currChart);
   }
}

void DrawStatus(string sym, string text) {
   long currChart = ChartFirst();
   while(currChart != -1) {
      if(ChartSymbol(currChart) == sym) {
         string name = "AMD_Label";
         if(ObjectFind(currChart, name) < 0) ObjectCreate(currChart, name, OBJ_LABEL, 0, 0, 0);
         ObjectSetInteger(currChart, name, OBJPROP_XDISTANCE, 20);
         ObjectSetInteger(currChart, name, OBJPROP_YDISTANCE, 50);
         ObjectSetString(currChart, name, OBJPROP_TEXT, "AMD: " + text);
         ObjectSetInteger(currChart, name, OBJPROP_COLOR, clrWhite);
         ObjectSetInteger(currChart, name, OBJPROP_FONTSIZE, 10);
      }
      currChart = ChartNext(currChart);
   }
}

//+------------------------------------------------------------------+
// --- Helpers ---
//+------------------------------------------------------------------+
int GetSymbolIndex(string sym) {
   for(int i=0; i<ArraySize(MarketState); i++) if(MarketState[i].name == sym) return i;
   int s = ArraySize(MarketState); ArrayResize(MarketState, s+1); MarketState[s].name = sym; return s;
}

int TimeStringToMinutes(string t) {
   string parts[]; StringSplit(t, ':', parts);
   if(ArraySize(parts) < 2) return 0;
   return (int)StringToInteger(parts[0])*60 + (int)StringToInteger(parts[1]);
}

bool CalculateRange(string sym, string tStart, string tEnd, double &high, double &low) {
   datetime now = TimeCurrent();
   datetime dtDayStart = now - (now % 86400);
   datetime dtS = dtDayStart + StringToTime("1970.01.01 " + tStart);
   datetime dtE = dtDayStart + StringToTime("1970.01.01 " + tEnd);
   
   int startBar = iBarShift(sym, PERIOD_M15, dtS);
   int endBar   = iBarShift(sym, PERIOD_M15, dtE);
   
   if(startBar == -1 || endBar == -1 || startBar <= endBar) return false;
   
   double h = -1.0; double l = 99999999.0;
   for(int i=endBar; i<=startBar; i++) {
      double bh = iHigh(sym, PERIOD_M15, i); 
      double bl = iLow(sym, PERIOD_M15, i);
      if(bh > h) h = bh; 
      if(bl < l) l = bl;
   }
   high = h; low = l; return true;
}
