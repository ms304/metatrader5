//+------------------------------------------------------------------+
//| SMC ICT Full Candle MT5 EA - Multi-Symbol (Corrigé)              |
//+------------------------------------------------------------------+
#property copyright "SMC AI"
#property link      "https://www.mql5.com"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>
CTrade trade;

// Symbols and timeframes
input string SymbolsString = "BTCUSD,XAUUSD,GBPJPY,EURUSD,US30"; // Liste séparée par des virgules pour faciliter l'édition
input ENUM_TIMEFRAMES TrendTF = PERIOD_H1;
input ENUM_TIMEFRAMES EntryTF = PERIOD_M15;
input ENUM_TIMEFRAMES MicroTF = PERIOD_M5;

// Risk & trade parameters
input double RiskPercent = 1.0;
input int MaxTradesPerSymbol = 1;

// Session filter
input bool UseSessionFilter = true;
input int StartHour = 8;
input int EndHour   = 17;

// Telegram
input string TelegramBotToken = "VOTRE_TOKEN_ICI";
input string TelegramChatID = "VOTRE_CHAT_ID_ICI";
input bool SendTelegramAlerts = true;

// Logging
input string LogFileName = "SMC_ICT_TradeLog.csv";
input bool EnableLogging = true;

string SymbolList[]; // Tableau dynamique pour stocker les symboles

//+------------------------------------------------------------------+
int OnInit()
{
   Print("SMC ICT Full MT5 EA Initialized");
   
   // Découpage de la string d'input en tableau
   StringSplit(SymbolsString, ',', SymbolList);
   
   // S'assurer que les symboles sont disponibles dans le Market Watch
   for(int i=0; i<ArraySize(SymbolList); i++)
   {
      string sym = SymbolList[i];
      if(!SymbolSelect(sym, true))
      {
         Print("Erreur: Impossible de sélectionner le symbole ", sym);
      }
   }
   
   InitLogFile();
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
void OnTick()
{
   datetime t = TimeCurrent();
   MqlDateTime dt;
   TimeToStruct(t, dt); // Conversion correcte pour MQL5
   int hourNow = dt.hour;

   for(int i=0; i<ArraySize(SymbolList); i++)
   {
      string sym = SymbolList[i];
      
      // Vérifier si le symbole existe et a des données
      if(SymbolInfoInteger(sym, SYMBOL_VISIBLE) == false) continue;

      // Session filter: BTC 24/7, les autres filtrés
      if(UseSessionFilter && StringFind(sym, "BTC") == -1) // Si ce n'est pas BTC
      {
         if(hourNow < StartHour || hourNow >= EndHour) continue;
      }

      // Limit max trades
      if(CountOpenTrades(sym) >= MaxTradesPerSymbol) continue;

      // Trend detection H1
      int trend = CheckMarketStructure(sym, TrendTF);
      if (trend == 0) continue; // Pas de tendance claire

      // ICT candle detection
      double obLow=0, obHigh=0, fvgLow=0, fvgHigh=0, breakerLow=0, breakerHigh=0, sweepLevel=0;
      
      // On cherche au moins une condition majeure
      bool foundOB = FindOrderBlock(sym, EntryTF, trend, obLow, obHigh);
      bool foundFVG = FindFairValueGap(sym, EntryTF, trend, fvgLow, fvgHigh);
      
      // Si ni OB ni FVG trouvé, on passe
      if(!foundOB && !foundFVG) continue; 
      
      // Optionnel : Breaker et Sweep
      FindBreakerBlock(sym, EntryTF, trend, breakerLow, breakerHigh);
      if(!FindLiquiditySweep(sym, MicroTF, trend, sweepLevel)) sweepLevel = 0;

      // Microstructure confirmation M5
      bool entrySignal = CheckMicrostructure(sym, MicroTF, obLow, obHigh, fvgLow, fvgHigh, breakerLow, breakerHigh, sweepLevel, trend);

      if(entrySignal)
      {
         // Définition du SL et TP basique pour l'exemple
         double entryPrice = (trend == 1) ? SymbolInfoDouble(sym, SYMBOL_ASK) : SymbolInfoDouble(sym, SYMBOL_BID);
         
         // Calcul SL intelligent (sous OB ou FVG)
         double sl = (trend == 1) ? (obLow != 0 ? obLow : fvgLow) : (obHigh != 0 ? obHigh : fvgHigh);
         
         // Protection si SL mal défini
         if(sl == 0 || MathAbs(entryPrice - sl) < Point() * 10) {
             sl = (trend == 1) ? entryPrice - 1000*Point() : entryPrice + 1000*Point();
         }
         
         // TP Ratio 1:2 pour l'exemple
         double riskDist = MathAbs(entryPrice - sl);
         double tp = (trend == 1) ? entryPrice + (riskDist * 2) : entryPrice - (riskDist * 2);

         double lot = CalculateLotSize(sym, RiskPercent, MathAbs(entryPrice - sl));

         // Envoi ordre
         if (SendTrade(sym, trend, sl, tp, lot)) {
             LogAndAlert(sym, trend, obLow, obHigh, fvgLow, fvgHigh, breakerLow, breakerHigh, sl, tp, lot);
         }
      }
   }
}

//+------------------------------------------------------------------+
// --- Core Functions --- //

int CountOpenTrades(string sym)
{
   int count = 0;
   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      // En MQL5, il faut récupérer le symbole par l'index
      string posSym = PositionGetSymbol(i);
      if(posSym == sym) count++;
   }
   return count;
}

int CheckMarketStructure(string sym, ENUM_TIMEFRAMES tf)
{
   // iHigh et iLow fonctionnent en MQL5 mais il vaut mieux vérifier les erreurs
   double high1 = iHigh(sym, tf, 1);
   double high2 = iHigh(sym, tf, 2);
   double low1 = iLow(sym, tf, 1);
   double low2 = iLow(sym, tf, 2);
   
   if(high1 == 0 || high2 == 0) return 0; // Données pas prêtes

   if(high1 > high2 && low1 > low2) return 1;
   if(high1 < high2 && low1 < low2) return -1;
   return 0;
}

bool FindOrderBlock(string sym, ENUM_TIMEFRAMES tf, int trend, double &obLow, double &obHigh)
{
   for(int i=2; i<10; i++)
   {
      double open = iOpen(sym, tf, i);
      double close = iClose(sym, tf, i);
      double high = iHigh(sym, tf, i);
      double low = iLow(sym, tf, i);

      if(trend == 1 && close < open) { obLow = low; obHigh = high; return true; } // Dernière bougie rouge avant hausse
      if(trend == -1 && close > open) { obLow = low; obHigh = high; return true; } // Dernière bougie verte avant baisse
   }
   return false;
}

bool FindFairValueGap(string sym, ENUM_TIMEFRAMES tf, int trend, double &fvgLow, double &fvgHigh)
{
   for(int i=2; i<10; i++)
   {
      double high_prev = iHigh(sym, tf, i+1); // Bougie 1 (passée)
      double low_prev  = iLow(sym, tf, i+1);
      
      double high_next = iHigh(sym, tf, i-1); // Bougie 3 (récente)
      double low_next  = iLow(sym, tf, i-1);

      // FVG Haussier: Gap entre High de la bougie i+1 et Low de la bougie i-1
      if(trend == 1 && low_next > high_prev) { fvgLow = high_prev; fvgHigh = low_next; return true; }
      
      // FVG Baissier: Gap entre Low de la bougie i+1 et High de la bougie i-1
      if(trend == -1 && high_next < low_prev) { fvgLow = high_next; fvgHigh = low_prev; return true; }
   }
   return false;
}

bool FindBreakerBlock(string sym, ENUM_TIMEFRAMES tf, int trend, double &breakerLow, double &breakerHigh)
{
   // Simplification pour compilation
   return false; 
}

bool FindLiquiditySweep(string sym, ENUM_TIMEFRAMES tf, int trend, double &sweepLevel)
{
   double high = iHigh(sym, tf, 1);
   double low = iLow(sym, tf, 1);
   sweepLevel = (trend == 1) ? high : low;
   return true;
}

bool CheckMicrostructure(string sym, ENUM_TIMEFRAMES tf, double obLow, double obHigh, double fvgLow, double fvgHigh, double breakerLow, double breakerHigh, double sweepLevel, int trend)
{
   double close = iClose(sym, tf, 0);
   // Logique simple: si on est dans une zone d'intérêt
   if(trend == 1)
   {
       if((obHigh > 0 && close >= obLow && close <= obHigh) || (fvgHigh > 0 && close >= fvgLow && close <= fvgHigh)) return true;
   }
   if(trend == -1)
   {
       if((obLow > 0 && close >= obLow && close <= obHigh) || (fvgLow > 0 && close >= fvgLow && close <= fvgHigh)) return true;
   }
   return false;
}

bool SendTrade(string sym, int trend, double sl, double tp, double lot)
{
   if (lot <= 0) return false;
   
   double price = (trend == 1) ? SymbolInfoDouble(sym, SYMBOL_ASK) : SymbolInfoDouble(sym, SYMBOL_BID);
   
   // Normalisation des prix
   double tickSize = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_SIZE);
   price = NormalizeDouble(price, (int)SymbolInfoInteger(sym, SYMBOL_DIGITS));
   sl    = NormalizeDouble(sl, (int)SymbolInfoInteger(sym, SYMBOL_DIGITS));
   tp    = NormalizeDouble(tp, (int)SymbolInfoInteger(sym, SYMBOL_DIGITS));

   if(trend == 1) return trade.Buy(lot, sym, price, sl, tp, "SMC Buy");
   else           return trade.Sell(lot, sym, price, sl, tp, "SMC Sell");
}

double CalculateLotSize(string sym, double riskPercent, double slDistancePrice)
{
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskMoney = balance * riskPercent / 100.0;
   
   double tickValue = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_SIZE);
   
   if(tickValue == 0 || tickSize == 0 || slDistancePrice == 0) return 0.01;

   double lossPerLot = (slDistancePrice / tickSize) * tickValue;
   if(lossPerLot == 0) return 0.01;
   
   double lot = riskMoney / lossPerLot;
   
   // Arrondir le lot selon le step du broker
   double lotStep = SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP);
   lot = MathFloor(lot / lotStep) * lotStep;
   
   double minLot = SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(sym, SYMBOL_VOLUME_MAX);
   
   if(lot < minLot) lot = minLot;
   if(lot > maxLot) lot = maxLot;
   
   return lot;
}

//+------------------------------------------------------------------+
// --- Logging + Telegram --- //

void InitLogFile()
{
   if(!EnableLogging) return;
   int handle = FileOpen(LogFileName, FILE_READ|FILE_WRITE|FILE_CSV|FILE_COMMON);
   if(handle == INVALID_HANDLE)
   {
      handle = FileOpen(LogFileName, FILE_WRITE|FILE_CSV|FILE_COMMON);
      if(handle != INVALID_HANDLE)
      {
         FileWrite(handle, "Timestamp", "Symbol", "Direction", "SL", "TP", "Lot");
         FileClose(handle);
      }
   }
   else FileClose(handle);
}

void LogTrade(string symbol, int trend, double obLow, double obHigh, double fvgLow, double fvgHigh, double breakerLow, double breakerHigh, double sl, double tp, double lot, string result="")
{
   if(!EnableLogging) return;
   int handle = FileOpen(LogFileName, FILE_READ|FILE_WRITE|FILE_CSV|FILE_COMMON);
   if(handle != INVALID_HANDLE)
   {
      FileSeek(handle, 0, SEEK_END);
      string dir = (trend == 1) ? "BUY" : "SELL";
      FileWrite(handle, TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES), symbol, dir, sl, tp, lot);
      FileClose(handle);
   }
}

void SendTelegramMessage(string message)
{
   if(!SendTelegramAlerts) return;
   
   // Configuration correcte pour MQL5 WebRequest
   string url = "https://api.telegram.org/bot" + TelegramBotToken + "/sendMessage?chat_id=" + TelegramChatID + "&text=" + message;
   
   char data[];  // Body vide pour GET
   char result[];
   string resultHeaders;
   string headers = ""; 
   int timeout = 5000; // 5 secondes
   
   // Note: WebRequest nécessite d'ajouter l'URL dans Outils > Options > Expert Advisors > Allow WebRequest
   int res = WebRequest("GET", url, headers, timeout, data, result, resultHeaders);
   
   if (res == -1) {
       Print("Erreur WebRequest Telegram: ", GetLastError());
   }
}

void AlertSignal(string symbol, int trend, double sl, double tp)
{
   string dir = (trend == 1) ? "BUY" : "SELL";
   string msg = "SMC Signal: " + symbol + " " + dir + " | SL: " + DoubleToString(sl, 2) + " TP: " + DoubleToString(tp, 2);
   Print(msg);
   SendTelegramMessage(msg);
}

void LogAndAlert(string symbol, int trend, double obLow, double obHigh, double fvgLow, double fvgHigh, double breakerLow, double breakerHigh, double sl, double tp, double lot)
{
   AlertSignal(symbol, trend, sl, tp);
   LogTrade(symbol, trend, obLow, obHigh, fvgLow, fvgHigh, breakerLow, breakerHigh, sl, tp, lot);
}
