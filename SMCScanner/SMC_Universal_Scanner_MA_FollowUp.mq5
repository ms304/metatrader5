//+------------------------------------------------------------------+
//|                                       SMC_Market_Scanner.mq5     |
//|               Scanner + Tracker (Version Corrigée Anti-Spam)     |
//+------------------------------------------------------------------+
#property copyright "SMC Multi-Scanner"
#property version   "3.02"

//--- INPUTS ---
input group "--- PARAMETRES SMC ---"
input int      LookbackPeriod = 20;
input double   DisplacementFactor = 1.2;
input double   MinWickPercent = 20.0;
input bool     FilterByTrend = true;

input group "--- PARAMETRES DE SUIVI (TRACKER) ---"
input double   RiskRewardRatio = 2.0;    
input int      MaxTrackedTrades = 50;    

input group "--- REGLAGES SCANNER ---"
input bool     ScanClosedBar = true;     
input int      RefreshSeconds = 10;      

//--- STRUCTURES ---
struct SymbolState {
   string name;
   int handleATR, handleMA;
   datetime lastAlertTime; // Doit stocker l'heure de la bougie (rates[idx].time)
};

struct VirtualTrade {
   string symbol;
   string type;
   double entry, sl, tp;
   datetime candleTime;
   bool active;
};

//--- VARIABLES GLOBALES ---
SymbolState watchedSymbols[];
VirtualTrade trades[];
int totalSymbols = 0;
int winCount = 0;
int lossCount = 0;

//+------------------------------------------------------------------+
//| Initialisation                                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   totalSymbols = SymbolsTotal(true); 
   ArrayResize(watchedSymbols, totalSymbols);
   ArrayResize(trades, MaxTrackedTrades);
   
   for(int j=0; j<MaxTrackedTrades; j++) trades[j].active = false;

   for(int i = 0; i < totalSymbols; i++)
     {
      string symName = SymbolName(i, true);
      watchedSymbols[i].name = symName;
      watchedSymbols[i].lastAlertTime = 0;
      watchedSymbols[i].handleATR = iATR(symName, _Period, 14);
      watchedSymbols[i].handleMA  = iMA(symName, _Period, 200, 0, MODE_EMA, PRICE_CLOSE);
     }
     
   EventSetTimer(RefreshSeconds);
   return(INIT_SUCCEEDED);
  }

void OnDeinit(const int reason) { EventKillTimer(); Comment(""); }

//+------------------------------------------------------------------+
//| Timer Function                                                   |
//+------------------------------------------------------------------+
void OnTimer()
  {
   UpdateVirtualTrades();

   for(int i = 0; i < totalSymbols; i++)
     {
      if(_StopFlag) return;
      string sym = watchedSymbols[i].name;
      MqlRates rates[];
      ArraySetAsSeries(rates, true);
      if(CopyRates(sym, _Period, 0, LookbackPeriod + 5, rates) < LookbackPeriod + 5) continue;
      
      int idx = ScanClosedBar ? 1 : 0; 
      
      // FIX 1: Comparaison stricte avec l'heure de la bougie
      if(rates[idx].time <= watchedSymbols[i].lastAlertTime) continue;

      double lowestLow = 999999.0; double highestHigh = 0.0;
      for(int k = idx + 1; k <= idx + LookbackPeriod; k++) {
         if(rates[k].low < lowestLow) lowestLow = rates[k].low;
         if(rates[k].high > highestHigh) highestHigh = rates[k].high;
      }

      double atrVal[1], maVal[1];
      CopyBuffer(watchedSymbols[i].handleATR, 0, idx, 1, atrVal);
      CopyBuffer(watchedSymbols[i].handleMA, 0, idx, 1, maVal);
      
      double candleRange = rates[idx].high - rates[idx].low;
      if(candleRange <= 0) continue;
      double bodySize = MathAbs(rates[idx].close - rates[idx].open);
      double upperWick = rates[idx].high - MathMax(rates[idx].open, rates[idx].close);
      double lowerWick = MathMin(rates[idx].open, rates[idx].close) - rates[idx].low;

      // LOGIQUE BUY
      if(rates[idx].low < lowestLow && rates[idx].close > lowestLow) {
         if((lowerWick/candleRange)*100.0 >= MinWickPercent && bodySize > atrVal[0]*DisplacementFactor) {
            if(!FilterByTrend || rates[idx].close > maVal[0]) {
               AddVirtualTrade(sym, "BUY", rates[idx].close, lowestLow, rates[idx].time, i);
            }
         }
      }
      // LOGIQUE SELL
      else if(rates[idx].high > highestHigh && rates[idx].close < highestHigh) {
         if((upperWick/candleRange)*100.0 >= MinWickPercent && bodySize > atrVal[0]*DisplacementFactor) {
            if(!FilterByTrend || rates[idx].close < maVal[0]) {
               AddVirtualTrade(sym, "SELL", rates[idx].close, highestHigh, rates[idx].time, i);
            }
         }
      }
     }
   DisplayDashboard();
  }

//+------------------------------------------------------------------+
//| Ajouter un trade avec sécurité anti-doublon                      |
//+------------------------------------------------------------------+
void AddVirtualTrade(string symbol, string type, double price, double slLevel, datetime candleTime, int symIdx)
  {
   // FIX 2: Vérifier si un trade est déjà actif sur ce symbole
   for(int i=0; i<MaxTrackedTrades; i++) {
      if(trades[i].active && trades[i].symbol == symbol) return; 
   }

   // Marquer la bougie comme traitée
   watchedSymbols[symIdx].lastAlertTime = candleTime;

   double sl = slLevel;
   double risk = MathAbs(price - sl);
   if(risk <= 0) return;
   double tp = (type == "BUY") ? price + (risk * RiskRewardRatio) : price - (risk * RiskRewardRatio);

   for(int i=0; i<MaxTrackedTrades; i++) {
      if(!trades[i].active) {
         trades[i].symbol = symbol;
         trades[i].type = type;
         trades[i].entry = price;
         trades[i].sl = sl;
         trades[i].tp = tp;
         trades[i].candleTime = candleTime;
         trades[i].active = true;
         
         Alert("📝 SUIVI: " + symbol + " " + type + " (SL: " + DoubleToString(sl, 5) + ")");
         break;
      }
   }
  }

//+------------------------------------------------------------------+
//| Mise à jour des trades (Check TP/SL)                             |
//+------------------------------------------------------------------+
void UpdateVirtualTrades()
  {
   for(int i=0; i<MaxTrackedTrades; i++) {
      if(!trades[i].active) continue;

      double currentBid = SymbolInfoDouble(trades[i].symbol, SYMBOL_BID);
      double currentAsk = SymbolInfoDouble(trades[i].symbol, SYMBOL_ASK);
      if(currentBid <= 0) continue;

      bool closed = false;
      string result = "";

      if(trades[i].type == "BUY") {
         if(currentBid >= trades[i].tp) { winCount++; closed = true; result = "✅ WIN"; }
         else if(currentBid <= trades[i].sl) { lossCount++; closed = true; result = "❌ LOSS"; }
      }
      else {
         if(currentAsk <= trades[i].tp) { winCount++; closed = true; result = "✅ WIN"; }
         else if(currentAsk >= trades[i].sl) { lossCount++; closed = true; result = "❌ LOSS"; }
      }

      if(closed) {
         trades[i].active = false;
         Print("TRACKER: " + trades[i].symbol + " " + result);
      }
   }
  }

void DisplayDashboard()
  {
   double winRate = (winCount + lossCount > 0) ? ((double)winCount / (winCount + lossCount)) * 100.0 : 0;
   string out = "=== SMC TRACKER 3.02 ===\n";
   out += "Win: " + (string)winCount + " | Loss: " + (string)lossCount + " | WinRate: " + DoubleToString(winRate, 1) + "%\n";
   out += "----------------------------\nActive Trades:\n";
   for(int i=0; i<MaxTrackedTrades; i++) 
      if(trades[i].active) out += trades[i].symbol + " (" + trades[i].type + ") @ " + DoubleToString(trades[i].entry, 5) + "\n";
   Comment(out);
  }
