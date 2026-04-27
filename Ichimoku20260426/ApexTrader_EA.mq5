//+------------------------------------------------------------------+
//|                                                 ApexTrader_EA.mq5 |
//|                          Expert Advisor Autonome Multi-Actifs     |
//|                                                                    |
//|  STRATÉGIE :                                                       |
//|  - Scanner tous les actifs du MarketWatch                          |
//|  - Tendance EMA 50/200 sur H4                                      |
//|  - Entrée sur retracement Fibonacci 50-61.8% avec confirmation RSI |
//|  - Structure de marché (HH/HL ou LH/LL)                           |
//|  - 1 seul trade à la fois, risque 1% du capital, SL/TP auto       |
//|  - Trailing stop automatique                                       |
//|  - Filtre spread + drawdown journalier                             |
//+------------------------------------------------------------------+
#property copyright   "ApexTrader EA"
#property version     "1.00"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\SymbolInfo.mqh>

//--- Constantes internes (aucun paramètre à configurer)
#define RISK_PERCENT          1.0      // Risque fixe 1% du capital
#define MIN_RR                2.0      // Ratio Risk:Reward minimum
#define MAX_DAILY_DD          3.0      // Drawdown journalier max en %
#define MAX_SPREAD_MULT       3.0      // Multiplicateur spread moyen autorisé
#define MIN_BARS_REQUIRED     250      // Bougies minimum pour analyser
#define EMA_FAST              50       // EMA rapide pour tendance
#define EMA_SLOW              200      // EMA lente pour tendance
#define RSI_PERIOD            14       // Période RSI
#define RSI_OVERBOUGHT        65.0     // Seuil RSI surachat (ajusté pour éviter FP)
#define RSI_OVERSOLD          35.0     // Seuil RSI survente
#define FIB_MIN               0.45     // Zone Fibonacci min (45%)
#define FIB_MAX               0.65     // Zone Fibonacci max (65%)
#define LOOKBACK_SWING        20       // Bougies pour détecter swing high/low
#define TRAIL_TRIGGER_RR      1.0      // Activer trailing quand RR=1 atteint
#define MAGIC_NUMBER          20240101 // Identifiant unique EA
#define TF_TREND              PERIOD_H4
#define TF_ENTRY              PERIOD_H1

//--- Objet Trade global
CTrade Trade;
CSymbolInfo SymInfo;

//--- Variables globales
double   g_DayStartBalance   = 0;
datetime g_LastDayCheck      = 0;
datetime g_LastScanTime      = 0;
string   g_OpenTradeSymbol   = "";
bool     g_DailyLimitHit     = false;

//+------------------------------------------------------------------+
//| Expert initialization                                             |
//+------------------------------------------------------------------+
int OnInit()
{
   Trade.SetExpertMagicNumber(MAGIC_NUMBER);
   Trade.SetDeviationInPoints(20);
   Trade.SetTypeFilling(ORDER_FILLING_FOK);

   g_DayStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   g_LastDayCheck    = TimeCurrent();

   Print("=== ApexTrader EA démarré — Scan autonome de tous les actifs ===");
   Print("Risque: ", RISK_PERCENT, "% | RR min: ", MIN_RR, " | DD max: ", MAX_DAILY_DD, "%");

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization                                           |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   Print("=== ApexTrader EA arrêté ===");
}

//+------------------------------------------------------------------+
//| Expert tick function                                              |
//+------------------------------------------------------------------+
void OnTick()
{
   //--- Réinitialisation quotidienne
   CheckDailyReset();

   //--- Si limite DD atteinte → rien faire
   if(g_DailyLimitHit) return;

   //--- Gérer le trade ouvert (trailing stop)
   if(HasOpenTrade())
   {
      ManageOpenTrade();
      return;
   }

   //--- Scanner uniquement sur nouvelle bougie H1 (évite surcharge CPU)
   datetime currentBarTime = iTime(_Symbol, TF_ENTRY, 0);
   if(currentBarTime == g_LastScanTime) return;
   g_LastScanTime = currentBarTime;

   //--- Vérifier le drawdown journalier
   if(CheckDailyDrawdown()) return;

   //--- Scanner tous les actifs
   ScanAllSymbols();
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
      Print("Nouveau jour — Balance de référence: ", g_DayStartBalance);
   }
}

//+------------------------------------------------------------------+
//| Vérification drawdown journalier                                  |
//+------------------------------------------------------------------+
bool CheckDailyDrawdown()
{
   double currentBalance = AccountInfoDouble(ACCOUNT_BALANCE)
                         + AccountInfoDouble(ACCOUNT_EQUITY)
                         - AccountInfoDouble(ACCOUNT_BALANCE);
   double equity         = AccountInfoDouble(ACCOUNT_EQUITY);
   double ddPercent      = (g_DayStartBalance - equity) / g_DayStartBalance * 100.0;

   if(ddPercent >= MAX_DAILY_DD)
   {
      if(!g_DailyLimitHit)
      {
         Print("⛔ Drawdown journalier atteint (", DoubleToString(ddPercent, 2),
               "%) — Trading suspendu pour aujourd'hui");
         g_DailyLimitHit = true;
      }
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Vérifier si un trade EA est déjà ouvert                           |
//+------------------------------------------------------------------+
bool HasOpenTrade()
{
   for(int i = 0; i < PositionsTotal(); i++)
   {
      if(PositionGetInteger(POSITION_MAGIC) == MAGIC_NUMBER)
      {
         g_OpenTradeSymbol = PositionGetString(POSITION_SYMBOL);
         return true;
      }
   }
   g_OpenTradeSymbol = "";
   return false;
}

//+------------------------------------------------------------------+
//| Gestion du trade ouvert (trailing stop)                           |
//+------------------------------------------------------------------+
void ManageOpenTrade()
{
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetInteger(POSITION_MAGIC) != MAGIC_NUMBER) continue;

      string   sym      = PositionGetString(POSITION_SYMBOL);
      double   openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double   sl        = PositionGetDouble(POSITION_SL);
      double   tp        = PositionGetDouble(POSITION_TP);
      double   curPrice  = 0;
      int      posType   = (int)PositionGetInteger(POSITION_TYPE);

      SymInfo.Name(sym);
      double point  = SymInfo.Point();
      double ask    = SymInfo.Ask();
      double bid    = SymInfo.Bid();

      double slDist     = MathAbs(openPrice - sl);
      double newSL      = sl;
      bool   doModify   = false;

      if(posType == POSITION_TYPE_BUY)
      {
         curPrice = bid;
         // Activer trailing quand RR 1:1 atteint
         double trigger = openPrice + slDist * TRAIL_TRIGGER_RR;
         if(curPrice >= trigger)
         {
            double trailSL = curPrice - slDist;
            if(trailSL > sl + point)
            {
               newSL    = NormalizeDouble(trailSL, SymInfo.Digits());
               doModify = true;
            }
         }
      }
      else if(posType == POSITION_TYPE_SELL)
      {
         curPrice = ask;
         double trigger = openPrice - slDist * TRAIL_TRIGGER_RR;
         if(curPrice <= trigger)
         {
            double trailSL = curPrice + slDist;
            if(trailSL < sl - point)
            {
               newSL    = NormalizeDouble(trailSL, SymInfo.Digits());
               doModify = true;
            }
         }
      }

      if(doModify)
      {
         if(Trade.PositionModify(ticket, newSL, tp))
            Print("Trailing SL mis à jour → ", newSL, " sur ", sym);
      }
   }
}

//+------------------------------------------------------------------+
//| Scanner tous les symboles du MarketWatch                          |
//+------------------------------------------------------------------+
void ScanAllSymbols()
{
   int    bestScore    = -1;
   double bestRR       = 0;
   string bestSymbol   = "";
   int    bestDir      = 0; // 1=BUY, -1=SELL
   double bestEntry    = 0;
   double bestSL       = 0;
   double bestTP       = 0;
   double bestLot      = 0;

   int totalSymbols = SymbolsTotal(true); // true = seulement Market Watch
   Print("Scanner — ", totalSymbols, " symboles dans le MarketWatch");

   for(int s = 0; s < totalSymbols; s++)
   {
      string sym = SymbolName(s, true);
      if(sym == "") continue;

      //--- Vérifier disponibilité au trading
      if(!SymbolInfoInteger(sym, SYMBOL_TRADE_MODE)) continue;
      if(!SymbolSelect(sym, true)) continue;

      //--- Vérifier historique suffisant sur les deux TF
      if(SeriesInfoInteger(sym, TF_TREND, SERIES_BARS_COUNT) < MIN_BARS_REQUIRED) continue;
      if(SeriesInfoInteger(sym, TF_ENTRY, SERIES_BARS_COUNT) < MIN_BARS_REQUIRED) continue;

      //--- Vérifier spread
      if(!IsSpreadAcceptable(sym)) continue;

      //--- Analyser le setup
      int    dir    = 0;
      double entry  = 0, sl = 0, tp = 0, lot = 0;
      int    score  = 0;
      double rr     = 0;

      if(AnalyzeSymbol(sym, dir, entry, sl, tp, lot, score, rr))
      {
         if(score > bestScore || (score == bestScore && rr > bestRR))
         {
            bestScore  = score;
            bestRR     = rr;
            bestSymbol = sym;
            bestDir    = dir;
            bestEntry  = entry;
            bestSL     = sl;
            bestTP     = tp;
            bestLot    = lot;
         }
      }
   }

   //--- Ouvrir le meilleur trade trouvé
   if(bestSymbol != "" && bestScore >= 2)
   {
      Print("✅ Meilleur setup: ", bestSymbol,
            " | Direction: ", (bestDir == 1 ? "BUY" : "SELL"),
            " | Score: ", bestScore,
            " | RR: ", DoubleToString(bestRR, 2),
            " | Lot: ", DoubleToString(bestLot, 2));
      OpenTrade(bestSymbol, bestDir, bestEntry, bestSL, bestTP, bestLot);
   }
}

//+------------------------------------------------------------------+
//| Vérifier si le spread est acceptable                              |
//+------------------------------------------------------------------+
bool IsSpreadAcceptable(string sym)
{
   long   spreadCurrent = SymbolInfoInteger(sym, SYMBOL_SPREAD);
   double point         = SymbolInfoDouble(sym, SYMBOL_POINT);
   double ask           = SymbolInfoDouble(sym, SYMBOL_ASK);
   double bid           = SymbolInfoDouble(sym, SYMBOL_BID);

   if(ask == 0 || bid == 0) return false;

   // Spread en % du prix — adaptatif par type d'actif
   double spreadPct = (ask - bid) / ask * 100.0;

   // Tolérance selon le type d'actif (adaptatif automatique)
   double maxSpreadPct = 0.05; // 0.05% par défaut (Forex majeurs)

   // Détecter type d'actif via le prix
   if(ask > 1000) maxSpreadPct = 0.15;      // Indices / Or / BTC (prix élevé)
   else if(ask > 100) maxSpreadPct = 0.10;  // Pétrole, certains indices
   else if(ask < 10) maxSpreadPct = 0.30;   // Crypto bas prix / exotiques

   return (spreadPct <= maxSpreadPct);
}

//+------------------------------------------------------------------+
//| Analyser un symbole et retourner le setup                         |
//+------------------------------------------------------------------+
bool AnalyzeSymbol(string sym, int &dir, double &entry, double &sl,
                   double &tp, double &lot, int &score, double &rr)
{
   dir   = 0; entry = 0; sl = 0; tp = 0; lot = 0; score = 0; rr = 0;

   //--- 1. Tendance H4 avec EMA 50/200
   int trendDir = GetTrend(sym);
   if(trendDir == 0) return false;

   //--- 2. Structure de marché H1
   double swingHigh = 0, swingLow = 0;
   if(!GetSwingPoints(sym, swingHigh, swingLow)) return false;

   double swingRange = swingHigh - swingLow;
   if(swingRange <= 0) return false;

   //--- 3. Zone de retracement Fibonacci
   double fibHigh = swingLow + swingRange * (1.0 - FIB_MIN);
   double fibLow  = swingLow + swingRange * (1.0 - FIB_MAX);

   double currentAsk = SymbolInfoDouble(sym, SYMBOL_ASK);
   double currentBid = SymbolInfoDouble(sym, SYMBOL_BID);
   if(currentAsk == 0 || currentBid == 0) return false;

   bool inFibBuy  = (trendDir ==  1 && currentBid >= fibLow && currentBid <= fibHigh);
   bool inFibSell = (trendDir == -1 && currentAsk >= fibLow && currentAsk <= fibHigh);

   if(!inFibBuy && !inFibSell) return false;

   score++;

   //--- 4. RSI H1
   double rsiVal = GetRSI(sym);
   if(rsiVal <= 0) return false;

   bool rsiConfirmBuy  = (trendDir ==  1 && rsiVal <= RSI_OVERSOLD + 15.0);
   bool rsiConfirmSell = (trendDir == -1 && rsiVal >= RSI_OVERBOUGHT - 15.0);

   if(!rsiConfirmBuy && !rsiConfirmSell) return false;

   score++;

   //--- 5. Bougie de confirmation (pin bar ou englobante)
   int candleDir = GetCandleConfirmation(sym);
   if(candleDir == trendDir) score++;

   //--- 6. Calcul SL/TP basé sur la structure
   double point   = SymbolInfoDouble(sym, SYMBOL_POINT);
   int    digits  = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
   double slDist  = 0;

   if(trendDir == 1) // BUY
   {
      dir   = 1;
      entry = NormalizeDouble(currentAsk, digits);
      sl    = NormalizeDouble(swingLow - swingRange * 0.05, digits); // Sous le swing low
      slDist = entry - sl;
      tp    = NormalizeDouble(entry + slDist * MIN_RR, digits);
   }
   else // SELL
   {
      dir   = -1;
      entry = NormalizeDouble(currentBid, digits);
      sl    = NormalizeDouble(swingHigh + swingRange * 0.05, digits); // Au-dessus du swing high
      slDist = sl - entry;
      tp    = NormalizeDouble(entry - slDist * MIN_RR, digits);
   }

   if(slDist <= 0) return false;

   rr = MIN_RR;

   //--- 7. Calcul du lot size (1% du capital, adaptatif à tout actif)
   lot = CalculateLotSize(sym, slDist);
   if(lot <= 0) return false;

   return (score >= 2);
}

//+------------------------------------------------------------------+
//| Tendance H4 — retourne 1 (haussier), -1 (baissier), 0 (neutre)   |
//+------------------------------------------------------------------+
int GetTrend(string sym)
{
   double emaFast[], emaSlow[];
   ArraySetAsSeries(emaFast, true);
   ArraySetAsSeries(emaSlow, true);

   int hFast = iMA(sym, TF_TREND, EMA_FAST, 0, MODE_EMA, PRICE_CLOSE);
   int hSlow = iMA(sym, TF_TREND, EMA_SLOW, 0, MODE_EMA, PRICE_CLOSE);

   if(hFast == INVALID_HANDLE || hSlow == INVALID_HANDLE) return 0;

   if(CopyBuffer(hFast, 0, 0, 3, emaFast) < 3) { IndicatorRelease(hFast); IndicatorRelease(hSlow); return 0; }
   if(CopyBuffer(hSlow, 0, 0, 3, emaSlow) < 3) { IndicatorRelease(hFast); IndicatorRelease(hSlow); return 0; }

   IndicatorRelease(hFast);
   IndicatorRelease(hSlow);

   double close[];
   ArraySetAsSeries(close, true);
   if(CopyClose(sym, TF_TREND, 0, 3, close) < 3) return 0;

   // Tendance haussière : EMA50 > EMA200 ET prix au-dessus des deux
   if(emaFast[1] > emaSlow[1] && close[1] > emaFast[1]) return 1;
   // Tendance baissière : EMA50 < EMA200 ET prix en dessous des deux
   if(emaFast[1] < emaSlow[1] && close[1] < emaFast[1]) return -1;

   return 0;
}

//+------------------------------------------------------------------+
//| Détecter les swing high/low récents sur H1                        |
//+------------------------------------------------------------------+
bool GetSwingPoints(string sym, double &swingHigh, double &swingLow)
{
   double high[], low[];
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);

   if(CopyHigh(sym, TF_ENTRY, 1, LOOKBACK_SWING, high) < LOOKBACK_SWING) return false;
   if(CopyLow(sym,  TF_ENTRY, 1, LOOKBACK_SWING, low)  < LOOKBACK_SWING) return false;

   swingHigh = high[ArrayMaximum(high, 0, LOOKBACK_SWING)];
   swingLow  = low[ArrayMinimum(low,   0, LOOKBACK_SWING)];

   double range = swingHigh - swingLow;
   if(range <= 0) return false;

   // Vérifier que le range est significatif (au moins 20 points)
   double point = SymbolInfoDouble(sym, SYMBOL_POINT);
   if(range < point * 20) return false;

   return true;
}

//+------------------------------------------------------------------+
//| Valeur RSI sur H1                                                  |
//+------------------------------------------------------------------+
double GetRSI(string sym)
{
   double rsi[];
   ArraySetAsSeries(rsi, true);

   int hRSI = iRSI(sym, TF_ENTRY, RSI_PERIOD, PRICE_CLOSE);
   if(hRSI == INVALID_HANDLE) return -1;

   int copied = CopyBuffer(hRSI, 0, 1, 3, rsi);
   IndicatorRelease(hRSI);

   if(copied < 3) return -1;
   return rsi[1];
}

//+------------------------------------------------------------------+
//| Détection bougie de confirmation (englobante ou pin bar)           |
//+------------------------------------------------------------------+
int GetCandleConfirmation(string sym)
{
   MqlRates rates[];
   ArraySetAsSeries(rates, true);

   if(CopyRates(sym, TF_ENTRY, 1, 3, rates) < 3) return 0;

   double body1 = MathAbs(rates[1].close - rates[1].open);
   double body2 = MathAbs(rates[2].close - rates[2].open);
   double range1 = rates[1].high - rates[1].low;

   // Englobante haussière
   if(rates[2].close < rates[2].open &&   // bougie 2 baissière
      rates[1].close > rates[1].open &&   // bougie 1 haussière
      rates[1].close > rates[2].open &&
      rates[1].open  < rates[2].close)
      return 1;

   // Englobante baissière
   if(rates[2].close > rates[2].open &&
      rates[1].close < rates[1].open &&
      rates[1].close < rates[2].open &&
      rates[1].open  > rates[2].close)
      return -1;

   // Pin bar haussière (longue mèche basse)
   if(range1 > 0)
   {
      double lowerWick = MathMin(rates[1].open, rates[1].close) - rates[1].low;
      if(lowerWick > range1 * 0.6 && body1 < range1 * 0.3)
         return 1;

      // Pin bar baissière (longue mèche haute)
      double upperWick = rates[1].high - MathMax(rates[1].open, rates[1].close);
      if(upperWick > range1 * 0.6 && body1 < range1 * 0.3)
         return -1;
   }

   return 0;
}

//+------------------------------------------------------------------+
//| Calcul du lot size universel (1% risque, adaptatif à tout actif)  |
//+------------------------------------------------------------------+
double CalculateLotSize(string sym, double slDist)
{
   double balance   = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskMoney = balance * RISK_PERCENT / 100.0;

   double tickValue = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_SIZE);
   double point     = SymbolInfoDouble(sym, SYMBOL_POINT);

   if(tickSize == 0 || tickValue == 0 || slDist == 0) return 0;

   // Valeur monétaire par lot pour la distance SL
   double valuePerLot = (slDist / tickSize) * tickValue;
   if(valuePerLot == 0) return 0;

   double lot = riskMoney / valuePerLot;

   // Arrondir selon les contraintes du symbole
   double lotStep = SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP);
   double lotMin  = SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN);
   double lotMax  = SymbolInfoDouble(sym, SYMBOL_VOLUME_MAX);

   if(lotStep > 0) lot = MathFloor(lot / lotStep) * lotStep;

   lot = MathMax(lot, lotMin);
   lot = MathMin(lot, lotMax);

   // Sécurité : ne jamais risquer plus de 2% (garde-fou)
   double maxLot = (balance * 2.0 / 100.0) / valuePerLot;
   lot = MathMin(lot, maxLot);

   return NormalizeDouble(lot, 2);
}

//+------------------------------------------------------------------+
//| Ouvrir un trade                                                    |
//+------------------------------------------------------------------+
void OpenTrade(string sym, int dir, double entry, double sl, double tp, double lot)
{
   bool result = false;

   if(dir == 1)
      result = Trade.Buy(lot, sym, entry, sl, tp,
                         "ApexTrader BUY | Score=" + IntegerToString(3));
   else
      result = Trade.Sell(lot, sym, entry, sl, tp,
                          "ApexTrader SELL | Score=" + IntegerToString(3));

   if(result)
   {
      Print("🚀 Trade ouvert — ", sym,
            " | ", (dir == 1 ? "BUY" : "SELL"),
            " | Lot: ", DoubleToString(lot, 2),
            " | Entry: ", DoubleToString(entry, 5),
            " | SL: ", DoubleToString(sl, 5),
            " | TP: ", DoubleToString(tp, 5),
            " | Risque: ", DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE) * RISK_PERCENT / 100.0, 2),
            " ", AccountInfoString(ACCOUNT_CURRENCY));
   }
   else
   {
      int err = GetLastError();
      Print("❌ Échec ouverture trade sur ", sym, " — Erreur: ", err,
            " (", ErrorDescription(err), ")");
   }
}

//+------------------------------------------------------------------+
//| Description des erreurs MT5                                        |
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
