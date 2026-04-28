//+------------------------------------------------------------------+
//|                                              ApexTrader_EA_002.mq5 |
//|                     Expert Advisor Autonome Multi-Actifs v2.0     |
//|                                                                    |
//|  STRATÉGIE :                                                       |
//|  - Phase 1 : Scanner TOUS les actifs du MarketWatch               |
//|  - Phase 2 : Sélectionner le MEILLEUR setup parmi tous            |
//|  - 1 seul trade à la fois, risque 1% du capital                   |
//|  - Log détaillé dans fichier dédié (open/write/close à chaque log)|
//|  - Synthèse en tableau après chaque scan complet                  |
//+------------------------------------------------------------------+
#property copyright   "ApexTrader EA v2.0"
#property version     "2.00"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\SymbolInfo.mqh>

//--- Constantes internes (aucun paramètre à configurer)
#define RISK_PERCENT       1.0
#define MIN_RR             2.0
#define MAX_DAILY_DD       3.0
#define MIN_BARS_REQUIRED  250
#define EMA_FAST           50
#define EMA_SLOW           200
#define RSI_PERIOD         14
#define RSI_OVERBOUGHT     65.0
#define RSI_OVERSOLD       35.0
#define FIB_MIN            0.45
#define FIB_MAX            0.65
#define LOOKBACK_SWING     20
#define TRAIL_TRIGGER_RR   1.0
#define MAGIC_NUMBER       20240101
#define TF_TREND           PERIOD_H4
#define TF_ENTRY           PERIOD_H1
#define MAX_SETUPS         100

//--- Structure représentant un setup candidat
struct SSetup
{
   string   symbol;
   int      direction;      // 1=BUY, -1=SELL
   double   entry;
   double   sl;
   double   tp;
   double   lot;
   int      score;          // 0 à 3
   double   rr;
   double   rsiVal;
   double   spreadPct;
   string   trendStr;
   string   candleStr;
   string   rejectReason;
};

//--- Objets globaux
CTrade      Trade;
CSymbolInfo SymInfo;

//--- Variables globales
double      g_DayStartBalance = 0;
datetime    g_LastDayCheck    = 0;
datetime    g_LastScanTime    = 0;
bool        g_DailyLimitHit   = false;
string      g_LogFile         = "";
int         g_ScanCount       = 0;

//+------------------------------------------------------------------+
//|  LOGGING — ouvre le fichier, écrit, ferme immédiatement           |
//+------------------------------------------------------------------+
void Log(string msg)
{
   int h = FileOpen(g_LogFile,
                    FILE_WRITE | FILE_READ | FILE_TXT | FILE_ANSI | FILE_SHARE_READ);
   if(h == INVALID_HANDLE) return;
   FileSeek(h, 0, SEEK_END);
   FileWriteString(h, TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS)
                      + " | " + msg + "\n");
   FileClose(h);
}

//--- Log brut sans horodatage (tableaux, séparateurs)
void LogRaw(string msg)
{
   int h = FileOpen(g_LogFile,
                    FILE_WRITE | FILE_READ | FILE_TXT | FILE_ANSI | FILE_SHARE_READ);
   if(h == INVALID_HANDLE) return;
   FileSeek(h, 0, SEEK_END);
   FileWriteString(h, msg + "\n");
   FileClose(h);
}

//--- Séparateur visuel avec titre optionnel
void LogSep(string title = "")
{
   string sep = "================================================================================";
   if(title == "")
      LogRaw(sep);
   else
   {
      string line = "===[ " + title + " ]";
      int pad = 80 - StringLen(line);
      for(int i = 0; i < pad; i++) line += "=";
      LogRaw(line);
   }
}

//+------------------------------------------------------------------+
//| Initialisation                                                    |
//+------------------------------------------------------------------+
int OnInit()
{
   Trade.SetExpertMagicNumber(MAGIC_NUMBER);
   Trade.SetDeviationInPoints(20);
   Trade.SetTypeFilling(ORDER_FILLING_FOK);

   g_DayStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   g_LastDayCheck    = TimeCurrent();

   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   g_LogFile = StringFormat("ApexTrader_%04d%02d%02d.log", dt.year, dt.mon, dt.day);

   LogSep("APEX TRADER EA v2.0 — DEMARRAGE");
   Log("Compte        : " + AccountInfoString(ACCOUNT_NAME));
   Log("Broker        : " + AccountInfoString(ACCOUNT_COMPANY));
   Log("Serveur       : " + AccountInfoString(ACCOUNT_SERVER));
   Log("Balance       : " + DoubleToString(g_DayStartBalance, 2)
                          + " " + AccountInfoString(ACCOUNT_CURRENCY));
   Log("Risque/trade  : " + DoubleToString(RISK_PERCENT, 1) + "%");
   Log("RR minimum    : " + DoubleToString(MIN_RR, 1));
   Log("DD max/jour   : " + DoubleToString(MAX_DAILY_DD, 1) + "%");
   Log("TF Tendance   : H4  |  TF Entree : H1");
   Log("EMA           : " + IntegerToString(EMA_FAST) + " / " + IntegerToString(EMA_SLOW));
   Log("Zone Fibo     : " + DoubleToString(FIB_MIN * 100, 0) + "% - "
                          + DoubleToString(FIB_MAX * 100, 0) + "%");
   Log("Fichier log   : " + g_LogFile);
   LogSep();

   Print("=== ApexTrader EA v2.0 demarré — Log: ", g_LogFile, " ===");
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Déinitialisation                                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   LogSep("ARRET DE L'EA");
   Log("Raison        : " + IntegerToString(reason));
   Log("Balance fin   : " + DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2)
                          + " " + AccountInfoString(ACCOUNT_CURRENCY));
   Log("Equity fin    : " + DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY), 2)
                          + " " + AccountInfoString(ACCOUNT_CURRENCY));
   Log("Scans totaux  : " + IntegerToString(g_ScanCount));
   LogSep();
}

//+------------------------------------------------------------------+
//| OnTick                                                            |
//+------------------------------------------------------------------+
void OnTick()
{
   CheckDailyReset();
   if(g_DailyLimitHit) return;

   if(HasOpenTrade())
   {
      ManageOpenTrade();
      return;
   }

   // Déclencher le scan uniquement sur nouvelle bougie H1
   datetime barTime = iTime(_Symbol, TF_ENTRY, 0);
   if(barTime == g_LastScanTime) return;
   g_LastScanTime = barTime;

   if(CheckDailyDrawdown()) return;

   RunScan();
}

//+------------------------------------------------------------------+
//| Réinitialisation journalière                                      |
//+------------------------------------------------------------------+
void CheckDailyReset()
{
   MqlDateTime now, last;
   TimeToStruct(TimeCurrent(), now);
   TimeToStruct(g_LastDayCheck, last);

   if(now.day != last.day)
   {
      g_DayStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
      g_DailyLimitHit   = false;
      g_LastDayCheck    = TimeCurrent();

      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);
      g_LogFile = StringFormat("ApexTrader_%04d%02d%02d.log", dt.year, dt.mon, dt.day);

      LogSep("NOUVEAU JOUR");
      Log("Balance ref   : " + DoubleToString(g_DayStartBalance, 2)
                             + " " + AccountInfoString(ACCOUNT_CURRENCY));
      LogSep();
   }
}

//+------------------------------------------------------------------+
//| Vérification drawdown journalier                                  |
//+------------------------------------------------------------------+
bool CheckDailyDrawdown()
{
   double equity    = AccountInfoDouble(ACCOUNT_EQUITY);
   double ddPct     = (g_DayStartBalance > 0)
                    ? (g_DayStartBalance - equity) / g_DayStartBalance * 100.0
                    : 0;

   if(ddPct >= MAX_DAILY_DD)
   {
      if(!g_DailyLimitHit)
      {
         Log("ALERTE DD | " + DoubleToString(ddPct, 2)
             + "% atteint — Trading suspendu jusqu'a demain");
         g_DailyLimitHit = true;
      }
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Vérifier si un trade EA est ouvert                                |
//+------------------------------------------------------------------+
bool HasOpenTrade()
{
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0 && PositionGetInteger(POSITION_MAGIC) == MAGIC_NUMBER)
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Gestion trailing stop                                             |
//+------------------------------------------------------------------+
void ManageOpenTrade()
{
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetInteger(POSITION_MAGIC) != MAGIC_NUMBER) continue;

      string sym       = PositionGetString(POSITION_SYMBOL);
      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl        = PositionGetDouble(POSITION_SL);
      double tp        = PositionGetDouble(POSITION_TP);
      int    posType   = (int)PositionGetInteger(POSITION_TYPE);

      SymInfo.Name(sym);
      double point  = SymInfo.Point();
      double slDist = MathAbs(openPrice - sl);
      double newSL  = sl;
      bool   doMod  = false;

      if(posType == POSITION_TYPE_BUY)
      {
         double bid     = SymInfo.Bid();
         double trigger = openPrice + slDist * TRAIL_TRIGGER_RR;
         if(bid >= trigger)
         {
            double trailSL = bid - slDist;
            if(trailSL > sl + point)
            {
               newSL = NormalizeDouble(trailSL, SymInfo.Digits());
               doMod = true;
            }
         }
      }
      else if(posType == POSITION_TYPE_SELL)
      {
         double ask     = SymInfo.Ask();
         double trigger = openPrice - slDist * TRAIL_TRIGGER_RR;
         if(ask <= trigger)
         {
            double trailSL = ask + slDist;
            if(trailSL < sl - point)
            {
               newSL = NormalizeDouble(trailSL, SymInfo.Digits());
               doMod = true;
            }
         }
      }

      if(doMod && Trade.PositionModify(ticket, newSL, tp))
         Log("TRAILING | " + sym + " | Nouveau SL : "
             + DoubleToString(newSL, SymInfo.Digits())
             + " | PnL flottant : "
             + DoubleToString(PositionGetDouble(POSITION_PROFIT), 2)
             + " " + AccountInfoString(ACCOUNT_CURRENCY));
   }
}

//+------------------------------------------------------------------+
//| Analyser un symbole — retourne true si setup valide, remplit s   |
//+------------------------------------------------------------------+
bool AnalyzeSymbol(string sym, SSetup &s)
{
   // Initialisation de la structure
   s.symbol       = sym;
   s.direction    = 0;
   s.entry        = 0;
   s.sl           = 0;
   s.tp           = 0;
   s.lot          = 0;
   s.score        = 0;
   s.rr           = 0;
   s.rsiVal       = 0;
   s.spreadPct    = 0;
   s.trendStr     = "-";
   s.candleStr    = "-";
   s.rejectReason = "";

   //--- Vérifications préliminaires
   if(!SymbolInfoInteger(sym, SYMBOL_TRADE_MODE))
   { s.rejectReason = "Trading desactive"; return false; }

   if(!SymbolSelect(sym, true))
   { s.rejectReason = "SymbolSelect echoue"; return false; }

   if(SeriesInfoInteger(sym, TF_TREND, SERIES_BARS_COUNT) < MIN_BARS_REQUIRED)
   { s.rejectReason = "Historique H4 insuffisant"; return false; }

   if(SeriesInfoInteger(sym, TF_ENTRY, SERIES_BARS_COUNT) < MIN_BARS_REQUIRED)
   { s.rejectReason = "Historique H1 insuffisant"; return false; }

   //--- Spread
   double ask = SymbolInfoDouble(sym, SYMBOL_ASK);
   double bid = SymbolInfoDouble(sym, SYMBOL_BID);
   if(ask <= 0 || bid <= 0)
   { s.rejectReason = "Prix invalides"; return false; }

   s.spreadPct   = (ask - bid) / ask * 100.0;
   double maxSpr = GetMaxSpread(ask);
   if(s.spreadPct > maxSpr)
   {
      s.rejectReason = StringFormat("Spread %.4f%% > max %.4f%%", s.spreadPct, maxSpr);
      return false;
   }

   //--- Tendance H4
   int trendDir = GetTrend(sym);
   s.trendStr   = (trendDir ==  1 ? "HAUSSIERE"
                : (trendDir == -1 ? "BAISSIERE" : "NEUTRE"));
   if(trendDir == 0)
   { s.rejectReason = "Tendance H4 neutre/absente"; return false; }

   //--- Swing points
   double swingHigh = 0, swingLow = 0;
   if(!GetSwingPoints(sym, swingHigh, swingLow))
   { s.rejectReason = "Swing points invalides"; return false; }

   //--- Zone Fibonacci
   double swingRange = swingHigh - swingLow;
   double fibHigh    = swingLow + swingRange * (1.0 - FIB_MIN);
   double fibLow     = swingLow + swingRange * (1.0 - FIB_MAX);
   bool   inFibBuy   = (trendDir ==  1 && bid >= fibLow && bid <= fibHigh);
   bool   inFibSell  = (trendDir == -1 && ask >= fibLow && ask <= fibHigh);

   if(!inFibBuy && !inFibSell)
   {
      double fibPos = (swingRange > 0)
                    ? ((trendDir == 1)
                       ? (1.0 - (bid - swingLow) / swingRange) * 100.0
                       : (ask - swingLow) / swingRange * 100.0)
                    : 0;
      s.rejectReason = StringFormat("Hors zone Fibo (pos=%.1f%% zone %.0f-%.0f%%)",
                                    fibPos, FIB_MIN * 100, FIB_MAX * 100);
      return false;
   }
   s.score++;  // Point 1 : Fibo OK

   //--- RSI
   double rsiVal = GetRSI(sym);
   s.rsiVal      = rsiVal;
   if(rsiVal < 0)
   { s.rejectReason = "RSI non calculable"; return false; }

   bool rsiOk = (trendDir ==  1 && rsiVal <= RSI_OVERSOLD  + 15.0)
             || (trendDir == -1 && rsiVal >= RSI_OVERBOUGHT - 15.0);
   if(!rsiOk)
   {
      s.rejectReason = StringFormat("RSI non confirme (%.1f)", rsiVal);
      return false;
   }
   s.score++;  // Point 2 : RSI OK

   //--- Bougie de confirmation (bonus)
   int candleDir = GetCandleConfirmation(sym);
   if(candleDir == trendDir)
   {
      s.score++;
      s.candleStr = (candleDir == 1 ? "PinBar/Englobante BULL"
                                    : "PinBar/Englobante BEAR");
   }
   else
      s.candleStr = "Aucune";

   //--- SL / TP / Lot
   int    digits = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
   double slDist = 0;

   if(trendDir == 1)
   {
      s.direction = 1;
      s.entry     = NormalizeDouble(ask, digits);
      s.sl        = NormalizeDouble(swingLow - swingRange * 0.05, digits);
      slDist      = s.entry - s.sl;
      s.tp        = NormalizeDouble(s.entry + slDist * MIN_RR, digits);
   }
   else
   {
      s.direction = -1;
      s.entry     = NormalizeDouble(bid, digits);
      s.sl        = NormalizeDouble(swingHigh + swingRange * 0.05, digits);
      slDist      = s.sl - s.entry;
      s.tp        = NormalizeDouble(s.entry - slDist * MIN_RR, digits);
   }

   if(slDist <= 0)
   { s.rejectReason = "Distance SL nulle ou negative"; return false; }

   s.rr  = MIN_RR;
   s.lot = CalculateLotSize(sym, slDist);
   if(s.lot <= 0)
   { s.rejectReason = "Calcul lot invalide"; return false; }

   //--- Score minimum 2/3
   if(s.score < 2)
   {
      s.rejectReason = StringFormat("Score insuffisant (%d/3)", s.score);
      return false;
   }

   return true; // Setup valide
}

//+------------------------------------------------------------------+
//|  SCAN EN 2 PHASES                                                 |
//+------------------------------------------------------------------+
void RunScan()
{
   g_ScanCount++;
   int totalSymbols = SymbolsTotal(true);

   LogSep("SCAN #" + IntegerToString(g_ScanCount) + "  "
          + TimeToString(TimeCurrent(), TIME_DATE | TIME_MINUTES));
   Log("MarketWatch   : " + IntegerToString(totalSymbols) + " symboles");
   Log("Balance       : " + DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2)
       + "  |  Equity : " + DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY), 2)
       + "  " + AccountInfoString(ACCOUNT_CURRENCY));
   LogRaw("");

   //--- Tableaux de résultats
   SSetup validSetups[];
   SSetup rejectedSetups[];
   int    validCount    = 0;
   int    rejectedCount = 0;
   ArrayResize(validSetups,    MAX_SETUPS);
   ArrayResize(rejectedSetups, MAX_SETUPS * 3);

   //=================================================================
   //  PHASE 1 — Analyser chaque symbole via AnalyzeSymbol()
   //=================================================================
   Log("PHASE 1 : Analyse individuelle de chaque symbole...");

   for(int s = 0; s < totalSymbols; s++)
   {
      string sym = SymbolName(s, true);
      if(sym == "") continue;

      SSetup setup;
      if(AnalyzeSymbol(sym, setup))
      {
         if(validCount < MAX_SETUPS)
            validSetups[validCount++] = setup;
      }
      else
      {
         if(rejectedCount < MAX_SETUPS * 3)
            rejectedSetups[rejectedCount++] = setup;
      }
   }

   //=================================================================
   //  PHASE 2 — Sélectionner le meilleur setup
   //=================================================================
   LogRaw("");
   Log(StringFormat("PHASE 2 : Selection du meilleur setup parmi %d candidats valides",
                    validCount));

   int bestIdx = -1;
   for(int i = 0; i < validCount; i++)
   {
      if(bestIdx == -1)                                               { bestIdx = i; continue; }
      if(validSetups[i].score >  validSetups[bestIdx].score)         { bestIdx = i; continue; }
      if(validSetups[i].score == validSetups[bestIdx].score &&
         validSetups[i].rr    >  validSetups[bestIdx].rr)            { bestIdx = i; }
   }

   //=================================================================
   //  TABLEAU 1 — Tous les setups VALIDES
   //=================================================================
   LogRaw("");
   LogSep("TABLEAU SETUPS VALIDES (" + IntegerToString(validCount) + " / "
          + IntegerToString(totalSymbols) + " symboles)");

   if(validCount > 0)
   {
      // En-tête
      LogRaw(StringFormat("| %-10s | %-4s | %-9s | %5s | %5s | %6s | %5s | %-21s | %-21s | %s",
             "SYMBOLE","DIR","TENDANCE","SCORE","RSI","SPR%","LOT","ENTRY/SL/TP","BOUGIE","STATUT"));
      LogRaw("| ---------- | ---- | --------- | ----- | ----- | ------ | ----- "
             "| --------------------- | --------------------- | --------------- |");

      for(int i = 0; i < validCount; i++)
      {
         SSetup  v    = validSetups[i];
         int     digs = (int)SymbolInfoInteger(v.symbol, SYMBOL_DIGITS);
         string  esl  = StringFormat("%.*f / %.*f / %.*f",
                                     digs, v.entry, digs, v.sl, digs, v.tp);
         string  stat = (i == bestIdx) ? ">>> MEILLEUR <<<" : "Candidat";

         LogRaw(StringFormat("| %-10s | %-4s | %-9s | %5d | %5.1f | %6.4f | %5.2f | %-21s | %-21s | %s",
                v.symbol,
                (v.direction == 1 ? "BUY" : "SELL"),
                v.trendStr,
                v.score,
                v.rsiVal,
                v.spreadPct,
                v.lot,
                esl,
                v.candleStr,
                stat));
      }
   }
   else
      LogRaw("  (aucun setup valide)");

   //=================================================================
   //  TABLEAU 2 — Résumé des rejets par raison
   //=================================================================
   LogRaw("");
   LogSep("TABLEAU REJETS (" + IntegerToString(rejectedCount) + " symboles exclus)");

   if(rejectedCount > 0)
   {
      LogRaw(StringFormat("| %-10s | %-9s | %5s | %s",
             "SYMBOLE", "TENDANCE", "RSI", "RAISON DU REJET"));
      LogRaw("| ---------- | --------- | ----- | ---------------------------------------- |");

      for(int i = 0; i < rejectedCount; i++)
      {
         SSetup r = rejectedSetups[i];
         LogRaw(StringFormat("| %-10s | %-9s | %5s | %s",
                r.symbol,
                r.trendStr,
                (r.rsiVal > 0 ? DoubleToString(r.rsiVal, 1) : "-"),
                r.rejectReason));
      }
   }

   //=================================================================
   //  DÉCISION FINALE
   //=================================================================
   LogRaw("");
   LogSep("DECISION FINALE — SCAN #" + IntegerToString(g_ScanCount));

   if(bestIdx >= 0)
   {
      SSetup best = validSetups[bestIdx];
      int    digs = (int)SymbolInfoInteger(best.symbol, SYMBOL_DIGITS);

      Log("TRADE CHOISI  : " + best.symbol
          + "  " + (best.direction == 1 ? "BUY" : "SELL")
          + "  | Score : " + IntegerToString(best.score) + "/3"
          + "  | RSI : " + DoubleToString(best.rsiVal, 1)
          + "  | Spread : " + DoubleToString(best.spreadPct, 4) + "%");
      Log("Prix          : Entry=" + DoubleToString(best.entry, digs)
          + "  SL=" + DoubleToString(best.sl, digs)
          + "  TP=" + DoubleToString(best.tp, digs));
      Log("Gestion risque: Lot=" + DoubleToString(best.lot, 2)
          + "  Risque=" + DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE)
                          * RISK_PERCENT / 100.0, 2)
          + " " + AccountInfoString(ACCOUNT_CURRENCY)
          + " (" + DoubleToString(RISK_PERCENT, 1) + "% capital)");
      Log("Tendance H4   : " + best.trendStr
          + "  | Bougie : " + best.candleStr);

      OpenTrade(best);
   }
   else
   {
      Log("DECISION : Aucun setup qualifié (score >= 2) — "
          "prochain scan à la bougie suivante");
   }

   LogSep("FIN SCAN #" + IntegerToString(g_ScanCount));
   LogRaw("");
}

//+------------------------------------------------------------------+
//| Spread max adaptatif selon le prix de l'actif                     |
//+------------------------------------------------------------------+
double GetMaxSpread(double price)
{
   if(price > 1000) return 0.15;
   if(price > 100)  return 0.10;
   if(price < 10)   return 0.30;
   return 0.05;
}

//+------------------------------------------------------------------+
//| Tendance H4 — EMA 50 / EMA 200                                    |
//+------------------------------------------------------------------+
int GetTrend(string sym)
{
   double emaFast[], emaSlow[], close[];
   ArraySetAsSeries(emaFast, true);
   ArraySetAsSeries(emaSlow, true);
   ArraySetAsSeries(close,   true);

   int hFast = iMA(sym, TF_TREND, EMA_FAST, 0, MODE_EMA, PRICE_CLOSE);
   int hSlow = iMA(sym, TF_TREND, EMA_SLOW, 0, MODE_EMA, PRICE_CLOSE);
   if(hFast == INVALID_HANDLE || hSlow == INVALID_HANDLE) return 0;

   bool ok = (CopyBuffer(hFast, 0, 0, 3, emaFast) >= 3)
          && (CopyBuffer(hSlow, 0, 0, 3, emaSlow) >= 3)
          && (CopyClose(sym, TF_TREND, 0, 3, close) >= 3);

   IndicatorRelease(hFast);
   IndicatorRelease(hSlow);
   if(!ok) return 0;

   if(emaFast[1] > emaSlow[1] && close[1] > emaFast[1]) return  1;
   if(emaFast[1] < emaSlow[1] && close[1] < emaFast[1]) return -1;
   return 0;
}

//+------------------------------------------------------------------+
//| Swing High / Low sur les 20 dernières bougies H1                  |
//+------------------------------------------------------------------+
bool GetSwingPoints(string sym, double &swingHigh, double &swingLow)
{
   double high[], low[];
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low,  true);

   if(CopyHigh(sym, TF_ENTRY, 1, LOOKBACK_SWING, high) < LOOKBACK_SWING) return false;
   if(CopyLow(sym,  TF_ENTRY, 1, LOOKBACK_SWING, low)  < LOOKBACK_SWING) return false;

   swingHigh = high[ArrayMaximum(high, 0, LOOKBACK_SWING)];
   swingLow  = low [ArrayMinimum(low,  0, LOOKBACK_SWING)];

   double range = swingHigh - swingLow;
   double point = SymbolInfoDouble(sym, SYMBOL_POINT);
   return (range > 0 && range >= point * 20);
}

//+------------------------------------------------------------------+
//| RSI 14 sur H1                                                     |
//+------------------------------------------------------------------+
double GetRSI(string sym)
{
   double rsi[];
   ArraySetAsSeries(rsi, true);
   int hRSI = iRSI(sym, TF_ENTRY, RSI_PERIOD, PRICE_CLOSE);
   if(hRSI == INVALID_HANDLE) return -1;
   int copied = CopyBuffer(hRSI, 0, 1, 3, rsi);
   IndicatorRelease(hRSI);
   return (copied >= 3) ? rsi[1] : -1;
}

//+------------------------------------------------------------------+
//| Bougie de confirmation — englobante ou pin bar                    |
//+------------------------------------------------------------------+
int GetCandleConfirmation(string sym)
{
   MqlRates r[];
   ArraySetAsSeries(r, true);
   if(CopyRates(sym, TF_ENTRY, 1, 3, r) < 3) return 0;

   double body1  = MathAbs(r[1].close - r[1].open);
   double range1 = r[1].high - r[1].low;

   // Englobante haussière
   if(r[2].close < r[2].open && r[1].close > r[1].open &&
      r[1].close > r[2].open && r[1].open  < r[2].close) return  1;
   // Englobante baissière
   if(r[2].close > r[2].open && r[1].close < r[1].open &&
      r[1].close < r[2].open && r[1].open  > r[2].close) return -1;

   if(range1 > 0)
   {
      double lw = MathMin(r[1].open, r[1].close) - r[1].low;
      double uw = r[1].high - MathMax(r[1].open, r[1].close);
      if(lw > range1 * 0.6 && body1 < range1 * 0.3) return  1;
      if(uw > range1 * 0.6 && body1 < range1 * 0.3) return -1;
   }
   return 0;
}

//+------------------------------------------------------------------+
//| Calcul lot size universel (1% risque, adaptatif tout actif)       |
//+------------------------------------------------------------------+
double CalculateLotSize(string sym, double slDist)
{
   double balance   = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskMoney = balance * RISK_PERCENT / 100.0;
   double tickVal   = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_VALUE);
   double tickSz    = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_SIZE);

   if(tickSz == 0 || tickVal == 0 || slDist == 0) return 0;

   double valPerLot = (slDist / tickSz) * tickVal;
   if(valPerLot == 0) return 0;

   double lot     = riskMoney / valPerLot;
   double lotStep = SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP);
   double lotMin  = SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN);
   double lotMax  = SymbolInfoDouble(sym, SYMBOL_VOLUME_MAX);
   double maxLot  = (balance * 2.0 / 100.0) / valPerLot; // garde-fou 2%

   if(lotStep > 0) lot = MathFloor(lot / lotStep) * lotStep;
   lot = MathMax(lot, lotMin);
   lot = MathMin(lot, MathMin(lotMax, maxLot));

   return NormalizeDouble(lot, 2);
}

//+------------------------------------------------------------------+
//| Ouverture du trade retenu                                         |
//+------------------------------------------------------------------+
void OpenTrade(SSetup &s)
{
   string comment = StringFormat("ApexTrader|%s|Score%d|Scan%d",
                                 (s.direction == 1 ? "BUY" : "SELL"),
                                 s.score, g_ScanCount);
   bool result = false;

   if(s.direction == 1)
      result = Trade.Buy(s.lot,  s.symbol, s.entry, s.sl, s.tp, comment);
   else
      result = Trade.Sell(s.lot, s.symbol, s.entry, s.sl, s.tp, comment);

   if(result)
   {
      int digs = (int)SymbolInfoInteger(s.symbol, SYMBOL_DIGITS);
      Log("TRADE OUVERT  : " + s.symbol
          + " " + (s.direction == 1 ? "BUY" : "SELL")
          + " | Lot:" + DoubleToString(s.lot, 2)
          + " | Entry:" + DoubleToString(s.entry, digs)
          + " | SL:"    + DoubleToString(s.sl,    digs)
          + " | TP:"    + DoubleToString(s.tp,    digs)
          + " | Ticket:#" + IntegerToString((int)Trade.ResultOrder()));
   }
   else
   {
      int err = GetLastError();
      Log("ERREUR TRADE  : " + s.symbol
          + " | Code:" + IntegerToString(err)
          + " | " + ErrorDescription(err));
   }
}

//+------------------------------------------------------------------+
//| Description des erreurs MT5                                       |
//+------------------------------------------------------------------+
string ErrorDescription(int code)
{
   switch(code)
   {
      case 10004: return "REQUOTE";
      case 10006: return "REQUEST_REJECTED";
      case 10007: return "REQUEST_CANCELED";
      case 10010: return "NO_MONEY";
      case 10014: return "INVALID_VOLUME";
      case 10015: return "INVALID_PRICE";
      case 10016: return "INVALID_STOPS";
      case 10018: return "MARKET_CLOSED";
      case 10019: return "NO_MONEY";
      default:    return "CODE_" + IntegerToString(code);
   }
}
//+------------------------------------------------------------------+
