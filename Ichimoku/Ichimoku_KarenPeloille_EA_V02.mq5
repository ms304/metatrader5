//+------------------------------------------------------------------+
//|                    Ichimoku_KarenPeloille_EA.mq5                 |
//|          Expert Advisor - Méthode Ichimoku Karen Péloille        |
//|          Analyse multi-actifs, multi-unités de temps             |
//+------------------------------------------------------------------+
#property copyright   "Ichimoku EA - Méthode Karen Péloille - Didier V. Le HPI Réunionnais"
#property version     "1.10"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\SymbolInfo.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\AccountInfo.mqh>

//+------------------------------------------------------------------+
//| Paramètres d'entrée                                              |
//+------------------------------------------------------------------+
input group "=== PARAMÈTRES ICHIMOKU ==="
input int    InpTenkanPeriod    = 9;    // Période Tenkan-Sen
input int    InpKijunPeriod     = 26;   // Période Kijun-Sen
input int    InpSenkouBPeriod   = 52;   // Période Senkou Span B
input int    InpDisplacement    = 26;   // Décalage Chikou/Kumo

input group "=== GESTION DU RISQUE ==="
input double InpRiskPercent     = 1.0;  // Risque par trade (%)
input double InpSLMultiplier    = 1.5;  // Multiplicateur SL (x Kijun distance)
input double InpTPRatio         = 2.0;  // Ratio TP/SL

input group "=== GESTION DES POSITIONS ==="
input bool   InpUseBreakEven    = true; // Activer la mise à BreakEven (au ratio 1:1)
input bool   InpUseTrailing     = true; // Activer le Trailing Stop sur Kijun-Sen

input group "=== FILTRES ==="
input bool   InpTradeM1         = false; // Analyser M1
input bool   InpTradeM5         = false; // Analyser M5
input bool   InpTradeM15        = true;  // Analyser M15
input bool   InpTradeM30        = true;  // Analyser M30
input bool   InpTradeH1         = true;  // Analyser H1
input bool   InpTradeH4         = true;  // Analyser H4
input bool   InpTradeD1         = true;  // Analyser D1
input bool   InpTradeW1         = true;  // Analyser W1
input bool   InpTradeMN         = false; // Analyser MN

input group "=== LOG ==="
input string InpLogFileName     = "IchimokuKP_Log.txt"; // Nom du fichier de log
input bool   InpVerboseLog      = true;  // Log détaillé

input group "=== EXÉCUTION ==="
input bool   InpAutoTrade       = false; // Exécuter les trades automatiquement
input int    InpMagicNumber     = 202406; // Numéro magique
input int    InpMaxPositions    = 5;     // Positions max simultanées

//+------------------------------------------------------------------+
//| Structures de données                                            |
//+------------------------------------------------------------------+
struct IchimokuValues
{
   double tenkan;
   double kijun;
   double senkouA;       // Span A actuelle
   double senkouB;       // Span B actuelle
   double senkouA_fwd;   // Span A future (kumo futur)
   double senkouB_fwd;   // Span B future (kumo futur)
   double chikou;        // Lagging Span
   double price_at_chikou; // Prix à la position du chikou (26 bougies en arrière)
   double kumo_at_chikou_A; // Span A à la position du chikou
   double kumo_at_chikou_B; // Span B à la position du chikou
};

struct TradeSetup
{
   string   symbol;
   ENUM_TIMEFRAMES timeframe;
   string   tfName;         // Nom du timeframe (ex: "H4")
   string   direction;      // "BUY" ou "SELL"
   double   entryPrice;
   double   stopLoss;
   double   takeProfit;
   double   lotSize;
   int      score;          // Score de qualité du setup (0-10)
   string   reasons[];      // Raisons du setup
   string   warnings[];     // Alertes/faiblesses
   bool     isValid;
};

struct SymbolAnalysis
{
   string   symbol;
   bool     isOpen;
   bool     hasSetup;
   TradeSetup bestSetup;
};

//+------------------------------------------------------------------+
//| Variables globales                                               |
//+------------------------------------------------------------------+
CTrade        g_trade;
CSymbolInfo   g_symbolInfo;
CPositionInfo g_posInfo;
CAccountInfo  g_accountInfo;

string        g_logPath;
datetime      g_lastBarTime = 0;
datetime      g_lastManageTime = 0;

ENUM_TIMEFRAMES g_timeframes[];
string          g_tfNames[];

//+------------------------------------------------------------------+
//| Initialisation                                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   g_trade.SetExpertMagicNumber(InpMagicNumber);
   g_trade.SetDeviationInPoints(20);
   
   // Chemin du fichier log
   g_logPath = InpLogFileName;
   
   // Construction du tableau des timeframes actifs
   BuildTimeframeList();
   
   // Log de démarrage
   string startMsg = "\n" + StringRepeat("=", 70) + "\n";
   startMsg += "  ICHIMOKU EXPERT ADVISOR - MÉTHODE KAREN PÉLOILLE\n";
   startMsg += "  Démarrage: " + TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES) + "\n";
   startMsg += "  Compte: " + IntegerToString((int)g_accountInfo.Login()) + 
               " | Solde: " + DoubleToString(g_accountInfo.Balance(), 2) + " " + 
               g_accountInfo.Currency() + "\n";
   startMsg += "  Risk/trade: " + DoubleToString(InpRiskPercent, 1) + "%" + 
               " | Magic: " + IntegerToString(InpMagicNumber) + "\n";
   startMsg += "  Mode: " + (InpAutoTrade ? "TRADING AUTOMATIQUE ACTIF" : "Analyse uniquement") + "\n";
   startMsg += StringRepeat("=", 70);
   WriteLog(startMsg);
   
   Print("Ichimoku KP EA démarré. Log: ", g_logPath);
   
   // Première analyse immédiate
   RunFullAnalysis();
   
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Deinitialisation                                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   string msg = "\n" + StringRepeat("-", 70) + "\n";
   msg += "EA arrêté. Raison: " + IntegerToString(reason) + 
          " | " + TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES);
   msg += "\n" + StringRepeat("-", 70);
   WriteLog(msg);
}

//+------------------------------------------------------------------+
//| Tick principal                                                   |
//+------------------------------------------------------------------+
void OnTick()
{
   // --- 1. DÉTECTION DE NOUVELLE BOUGIE POUR L'ANALYSE ---
   // On se base sur le plus petit timeframe sélectionné pour déclencher le scan global
   if(ArraySize(g_timeframes) > 0)
   {
      ENUM_TIMEFRAMES minTF = g_timeframes[0];
      datetime currentBarTime = (datetime)SeriesInfoInteger(_Symbol, minTF, SERIES_LASTBAR_DATE);
      
      if(currentBarTime != g_lastBarTime)
      {
         RunFullAnalysis();
         g_lastBarTime = currentBarTime;
      }
   }
   
   // --- 2. GESTION DES POSITIONS (Trailing Kijun / BreakEven) ---
   // On l'exécute uniquement à chaque clôture M1 pour ne pas surcharger le CPU avec les appels iIchimoku
   datetime currentM1Time = (datetime)SeriesInfoInteger(_Symbol, PERIOD_M1, SERIES_LASTBAR_DATE);
   if(currentM1Time != g_lastManageTime && InpAutoTrade)
   {
      ManagePositions();
      g_lastManageTime = currentM1Time;
   }
}

//+------------------------------------------------------------------+
//| Analyse complète de tous les actifs du Market Watch             |
//+------------------------------------------------------------------+
void RunFullAnalysis()
{
   string header = "\n" + StringRepeat("*", 70) + "\n";
   header += "  ANALYSE ICHIMOKU COMPLÈTE (Sur clôture bougie)\n";
   header += "  Date/Heure: " + TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES|TIME_SECONDS) + "\n";
   header += "  Solde: " + DoubleToString(g_accountInfo.Balance(), 2) + " " + g_accountInfo.Currency() +
             " | Equity: " + DoubleToString(g_accountInfo.Equity(), 2) + "\n";
   header += StringRepeat("*", 70);
   WriteLog(header);
   
   int symbolCount = SymbolsTotal(true); // true = seulement Market Watch
   int setupCount  = 0;
   double totalRisk = 0;
   
   TradeSetup allSetups[];
   string     allSetupsSymbols[];
   
   WriteLog("\n[SCAN] " + IntegerToString(symbolCount) + " actif(s) dans le Market Watch");
   
   for(int i = 0; i < symbolCount; i++)
   {
      string sym = SymbolName(i, true);
      if(sym == "") continue;
      
      // Vérification tradabilité
      bool tradable = IsSymbolTradable(sym);
      string tradableStr = tradable ? "OUVERT" : "FERMÉ/NON TRADABLE";
      
      WriteLog("\n" + StringRepeat("-", 60));
      WriteLog("[ACTIF] " + sym + " | Marché: " + tradableStr);
      
      if(!tradable)
      {
         WriteLog("  >> Actif ignoré pour le trading (marché fermé ou non tradable)");
         // On analyse quand même pour information
      }
      
      // Analyse Ichimoku sur tous les timeframes
      bool symbolHasSetup = false;
      for(int t = 0; t < ArraySize(g_timeframes); t++)
      {
         TradeSetup setup;
         if(AnalyzeIchimoku(sym, g_timeframes[t], g_tfNames[t], setup))
         {
            if(setup.isValid && tradable)
            {
               int sz = ArraySize(allSetups);
               ArrayResize(allSetups, sz + 1);
               ArrayResize(allSetupsSymbols, sz + 1);
               allSetups[sz] = setup;
               allSetupsSymbols[sz] = sym + " " + g_tfNames[t];
               setupCount++;
               symbolHasSetup = true;
            }
         }
      }
      
      if(!symbolHasSetup)
         WriteLog("  >> Aucun setup valide identifié sur " + sym);
   }
   
   // Résumé des setups trouvés
   WriteSummary(allSetups, allSetupsSymbols, setupCount);
   
   // Exécution si mode auto
   if(InpAutoTrade && setupCount > 0)
      ExecuteSetups(allSetups, allSetupsSymbols);
}

//+------------------------------------------------------------------+
//| Vérification si l'actif est tradable                            |
//+------------------------------------------------------------------+
bool IsSymbolTradable(const string symbol)
{
   if(!SymbolSelect(symbol, true)) return false;
   
   int tradeMode = (int)SymbolInfoInteger(symbol, SYMBOL_TRADE_MODE);
   if(tradeMode == SYMBOL_TRADE_MODE_DISABLED) return false;
   
   double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
   if(bid <= 0 || ask <= 0) return false;
   
   double spread = ask - bid;
   if(bid > 0 && spread / bid > 0.05) 
   {
      WriteLog("  [WARN] Spread anormal sur " + symbol + ": " + 
               DoubleToString(spread / bid * 100, 2) + "%");
      return false;
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Analyse Ichimoku complète sur un symbole/timeframe              |
//+------------------------------------------------------------------+
bool AnalyzeIchimoku(const string symbol, const ENUM_TIMEFRAMES tf, 
                      const string tfName, TradeSetup &setup)
{
   int handle = iIchimoku(symbol, tf, InpTenkanPeriod, InpKijunPeriod, InpSenkouBPeriod);
   if(handle == INVALID_HANDLE)
   {
      WriteLog("  [ERR] Impossible de créer indicateur Ichimoku sur " + symbol + " " + tfName);
      return false;
   }
   
   int barsNeeded = InpSenkouBPeriod + InpDisplacement * 3 + 20;
   
   double tenkan[], kijun[], senkouA[], senkouB[], chikou[];
   ArraySetAsSeries(tenkan,  true);
   ArraySetAsSeries(kijun,   true);
   ArraySetAsSeries(senkouA, true);
   ArraySetAsSeries(senkouB, true);
   ArraySetAsSeries(chikou,  true);
   
   if(CopyBuffer(handle, 0, 0, barsNeeded, tenkan)  < barsNeeded ||
      CopyBuffer(handle, 1, 0, barsNeeded, kijun)   < barsNeeded ||
      CopyBuffer(handle, 2, 0, barsNeeded, senkouA) < barsNeeded ||
      CopyBuffer(handle, 3, 0, barsNeeded, senkouB) < barsNeeded ||
      CopyBuffer(handle, 4, 0, barsNeeded, chikou)  < barsNeeded)
   {
      IndicatorRelease(handle);
      if(InpVerboseLog) WriteLog("  [" + tfName + "] Données insuffisantes sur " + symbol);
      return false;
   }
   
   IndicatorRelease(handle);
   
   double close[], high[], low[], open[];
   ArraySetAsSeries(close, true);
   ArraySetAsSeries(high,  true);
   ArraySetAsSeries(low,   true);
   ArraySetAsSeries(open,  true);
   
   if(CopyClose(symbol, tf, 0, barsNeeded, close) < barsNeeded) return false;
   if(CopyHigh(symbol,  tf, 0, barsNeeded, high)  < barsNeeded) return false;
   if(CopyLow(symbol,   tf, 0, barsNeeded, low)   < barsNeeded) return false;
   if(CopyOpen(symbol,  tf, 0, barsNeeded, open)  < barsNeeded) return false;
   
   IchimokuValues ich;
   ich.tenkan = tenkan[0];
   ich.kijun  = kijun[0];
   
   ich.senkouA_fwd = senkouA[0];
   ich.senkouB_fwd = senkouB[0];
   ich.senkouA     = senkouA[InpDisplacement];
   ich.senkouB     = senkouB[InpDisplacement];
   
   ich.chikou = close[0];
   ich.price_at_chikou  = close[InpDisplacement];
   ich.kumo_at_chikou_A = senkouA[InpDisplacement * 2];
   ich.kumo_at_chikou_B = senkouB[InpDisplacement * 2];
   
   double currentPrice = close[0];
   double currentHigh  = high[0];
   double currentLow   = low[0];

   double DBL_LIMIT = 1e15;
   if(ich.tenkan <= 0 || ich.tenkan > DBL_LIMIT || ich.kijun <= 0 || ich.kijun > DBL_LIMIT ||
      ich.senkouA <= 0 || ich.senkouA > DBL_LIMIT || ich.senkouB <= 0 || ich.senkouB > DBL_LIMIT ||
      ich.chikou <= 0 || ich.chikou > DBL_LIMIT || ich.price_at_chikou <= 0 || currentPrice <= 0)
   {
      if(InpVerboseLog) WriteLog("  [" + tfName + "] Valeurs Ichimoku invalides sur " + symbol);
      setup.isValid = false;
      return false;
   }

   // --- MODIFICATION: Filtre Kumo 0.1% du prix ---
   double minKumoThickness = currentPrice * 0.001; // 0.1% du prix
   double kumoNow  = MathAbs(ich.senkouA    - ich.senkouB);
   double kumoFut  = MathAbs(ich.senkouA_fwd - ich.senkouB_fwd);
   if(kumoNow < minKumoThickness && kumoFut < minKumoThickness)
   {
      if(InpVerboseLog) WriteLog("  [" + tfName + "] Kumo trop plat (< 0.1% du prix) sur " + symbol + " - TF ignoré");
      setup.isValid = false;
      return false;
   }

   string logEntry = "\n  [" + tfName + "] Analyse " + symbol + "\n";
   logEntry += "  Prix: " + DoubleToString(currentPrice, _Digits) + 
               " | T: " + DoubleToString(ich.tenkan, _Digits) + 
               " | K: " + DoubleToString(ich.kijun, _Digits) + "\n";
   logEntry += "  Kumo:[" + DoubleToString(MathMin(ich.senkouA, ich.senkouB), _Digits) + 
               " - " + DoubleToString(MathMax(ich.senkouA, ich.senkouB), _Digits) + "]" +
               " | Kumo futur:[" + DoubleToString(MathMin(ich.senkouA_fwd, ich.senkouB_fwd), _Digits) + 
               " - " + DoubleToString(MathMax(ich.senkouA_fwd, ich.senkouB_fwd), _Digits) + "]\n";
   logEntry += "  Chikou: " + DoubleToString(ich.chikou, _Digits) + 
               " vs Prix t-26: " + DoubleToString(ich.price_at_chikou, _Digits);
   
   WriteLog(logEntry);
   
   int bullScore = 0;
   int bearScore = 0;
   string bullReasons[], bearReasons[];
   string warnings[];
   
   double kumoTop    = MathMax(ich.senkouA, ich.senkouB);
   double kumoBottom = MathMin(ich.senkouA, ich.senkouB);
   double kumoThickness = kumoTop - kumoBottom;
   
   bool priceAboveKumo = currentPrice > kumoTop;
   bool priceBelowKumo = currentPrice < kumoBottom;
   
   if(priceAboveKumo)      { bullScore += 2; AddToArray(bullReasons, "Prix au-dessus du Kumo"); }
   else if(priceBelowKumo) { bearScore += 2; AddToArray(bearReasons, "Prix en-dessous du Kumo"); }
   else                    { AddToArray(warnings, "Prix dans le Kumo - signal faible"); }
   
   bool kumoHaussier = ich.senkouA > ich.senkouB;
   bool kumoFuturHaussier = ich.senkouA_fwd > ich.senkouB_fwd;
   
   if(kumoHaussier) { bullScore += 1; AddToArray(bullReasons, "Kumo vert (SA > SB)"); }
   else             { bearScore += 1; AddToArray(bearReasons, "Kumo rouge (SB > SA)"); }
   
   if(kumoFuturHaussier) { bullScore += 1; AddToArray(bullReasons, "Kumo futur vert"); }
   else                  { bearScore += 1; AddToArray(bearReasons, "Kumo futur rouge"); }
   
   bool tenkanAboveKijun = ich.tenkan > ich.kijun;
   if(tenkanAboveKijun) { bullScore += 1; AddToArray(bullReasons, "Tenkan > Kijun"); }
   else if(ich.tenkan < ich.kijun) { bearScore += 1; AddToArray(bearReasons, "Tenkan < Kijun"); }
   else AddToArray(warnings, "Tenkan = Kijun (compression)");
   
   double prevTenkan = tenkan[1];
   double prevKijun  = kijun[1];
   bool tkGoldenCross = (prevTenkan <= prevKijun) && (ich.tenkan > ich.kijun);
   bool tkDeathCross  = (prevTenkan >= prevKijun) && (ich.tenkan < ich.kijun);
   
   if(tkGoldenCross) { bullScore += 3; AddToArray(bullReasons, "TK Golden Cross"); }
   else if(tkDeathCross) { bearScore += 3; AddToArray(bearReasons, "TK Death Cross"); }
   
   bool priceAboveTenkan = currentPrice > ich.tenkan;
   bool priceAboveKijun  = currentPrice > ich.kijun;
   
   if(priceAboveTenkan && priceAboveKijun) { bullScore += 1; AddToArray(bullReasons, "Prix > Tenkan et Prix > Kijun"); }
   else if(!priceAboveTenkan && !priceAboveKijun) { bearScore += 1; AddToArray(bearReasons, "Prix < Tenkan et Prix < Kijun"); }
   
   double onePoint = SymbolInfoDouble(symbol, SYMBOL_POINT);
   double chikouTol = MathMax(5.0 * onePoint, currentPrice * 0.0005);
   bool chikouAbovePrice  = ich.chikou > ich.price_at_chikou + chikouTol;
   bool chikouBelowPrice  = ich.chikou < ich.price_at_chikou - chikouTol;
   
   double kumoTopAtChikou    = MathMax(ich.kumo_at_chikou_A, ich.kumo_at_chikou_B);
   double kumoBottomAtChikou = MathMin(ich.kumo_at_chikou_A, ich.kumo_at_chikou_B);
   bool chikouAboveKumo = ich.chikou > kumoTopAtChikou    + chikouTol;
   bool chikouBelowKumo = ich.chikou < kumoBottomAtChikou - chikouTol;
   bool chikouInKumo    = !chikouAboveKumo && !chikouBelowKumo;
   
   if(chikouAbovePrice && chikouAboveKumo) { bullScore += 3; AddToArray(bullReasons, "Chikou au-dessus des prix ET au-dessus du Kumo passé"); }
   else if(chikouAbovePrice && chikouInKumo) { bullScore += 1; AddToArray(warnings, "Chikou traverse le Kumo passé (hausse modérée)"); }
   else if(chikouBelowPrice && chikouBelowKumo) { bearScore += 3; AddToArray(bearReasons, "Chikou en-dessous des prix ET en-dessous du Kumo passé"); }
   else if(chikouBelowPrice && chikouInKumo) { bearScore += 1; AddToArray(warnings, "Chikou traverse le Kumo passé (baisse modérée)"); }
   else { AddToArray(warnings, "Chikou en zone neutre ou contradictoire"); }
   
   double kijunDist = MathAbs(currentPrice - ich.kijun);
   double kijunDistPct = (ich.kijun > 0) ? kijunDist / ich.kijun * 100 : 0;
   if(kijunDistPct < 0.1) AddToArray(warnings, "Prix très proche du Kijun");
   
   double kijunValue = ich.kijun > 0 ? ich.kijun : 1;
   double kumoThicknessPct = (kijunValue > 0) ? kumoThickness / kijunValue * 100 : 0;
   if(kumoThicknessPct > 3.0) AddToArray(warnings, "Kumo épais (" + DoubleToString(kumoThicknessPct, 2) + "%)");
   
   string synthesis = "\n  SYNTHÈSE[" + tfName + "] " + symbol + ":\n";
   synthesis += "  Score BULL: " + IntegerToString(bullScore) + " | Score BEAR: " + IntegerToString(bearScore) + "\n";
   
   string direction = "";
   int    totalScore = 0;
   bool   setupValid = false;
   
   if(bullScore >= 6 && bullScore > bearScore + 2)
   {
      direction  = "BUY";
      totalScore = bullScore;
      setupValid = true;
      synthesis += "  >> SETUP HAUSSIER (score " + IntegerToString(bullScore) + "/11)\n";
   }
   else if(bearScore >= 6 && bearScore > bullScore + 2)
   {
      direction  = "SELL";
      totalScore = bearScore;
      setupValid = true;
      synthesis += "  >> SETUP BAISSIER (score " + IntegerToString(bearScore) + "/11)\n";
   }
   else synthesis += "  >> PAS DE SETUP (scores insuffisants)\n";
   
   if(setupValid)
   {
      double entryPrice = SymbolInfoDouble(symbol, SYMBOL_ASK);
      if(direction == "SELL") entryPrice = SymbolInfoDouble(symbol, SYMBOL_BID);
      
      double sl = 0, tp = 0;
      CalculateSLTP(symbol, tf, direction, ich, currentPrice, high, low, sl, tp);
      
      double lotSize = CalculateLotSize(symbol, entryPrice, sl);
      
      setup.symbol     = symbol;
      setup.timeframe  = tf;
      setup.tfName     = tfName;
      setup.direction  = direction;
      setup.entryPrice = entryPrice;
      setup.stopLoss   = sl;
      setup.takeProfit = tp;
      setup.lotSize    = lotSize;
      setup.score      = totalScore;
      setup.isValid    = true;
      
      synthesis += "  Entrée: " + DoubleToString(entryPrice, _Digits) + " | SL: " + DoubleToString(sl, _Digits) + " | TP: " + DoubleToString(tp, _Digits) + "\n";
   }
   else setup.isValid = false;
   
   WriteLog(synthesis);
   return true;
}

//+------------------------------------------------------------------+
//| Calcul Stop Loss et Take Profit                                  |
//+------------------------------------------------------------------+
void CalculateSLTP(const string symbol, const ENUM_TIMEFRAMES tf, 
                    const string direction, const IchimokuValues &ich,
                    const double currentPrice, const double &high[], const double &low[],
                    double &sl, double &tp)
{
   double point  = SymbolInfoDouble(symbol, SYMBOL_POINT);
   double spread = SymbolInfoDouble(symbol, SYMBOL_ASK) - SymbolInfoDouble(symbol, SYMBOL_BID);
   int    digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   
   double entryBuy  = SymbolInfoDouble(symbol, SYMBOL_ASK);
   double entryBid  = SymbolInfoDouble(symbol, SYMBOL_BID);
   long   stopsLvl  = SymbolInfoInteger(symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double minDist   = MathMax((double)stopsLvl * point + spread, entryBuy * 0.001);
   
   if(direction == "BUY")
   {
      double slKijun  = ich.kijun  - spread - point;
      double slKumo   = MathMin(ich.senkouA, ich.senkouB) - spread - point;
      
      if(currentPrice > MathMax(ich.senkouA, ich.senkouB))
      {
         sl = slKijun;
         if(entryBuy - sl < minDist) sl = slKumo;
      }
      else sl = slKumo;
      
      if(entryBuy - sl < minDist)
      {
         double highestHigh = high[0], lowestLow = low[0];
         for(int k = 1; k <= MathMin(14, ArraySize(high)-1); k++)
         {
            if(high[k] > highestHigh) highestHigh = high[k];
            if(low[k]  < lowestLow)  lowestLow  = low[k];
         }
         double atrProxy = (highestHigh - lowestLow) * 0.5;
         if(atrProxy > minDist) minDist = atrProxy;
         sl = entryBuy - minDist;
      }
      
      sl = MathMin(sl, entryBuy - minDist);
      double slDistance = entryBuy - sl;
      if(slDistance > entryBuy * 0.20) { sl = entryBuy - entryBuy * 0.20; slDistance = entryBuy * 0.20; }
      
      tp = entryBuy + slDistance * InpTPRatio;
   }
   else // SELL
   {
      double slKijun  = ich.kijun  + spread + point;
      double slKumo   = MathMax(ich.senkouA, ich.senkouB) + spread + point;
      
      if(currentPrice < MathMin(ich.senkouA, ich.senkouB)) sl = slKijun;
      else sl = slKumo;
      
      if(sl - entryBid < minDist)
      {
         double highestHigh = high[0], lowestLow = low[0];
         for(int k = 1; k <= MathMin(14, ArraySize(high)-1); k++)
         {
            if(high[k] > highestHigh) highestHigh = high[k];
            if(low[k]  < lowestLow)  lowestLow  = low[k];
         }
         double atrProxy = (highestHigh - lowestLow) * 0.5;
         if(atrProxy > minDist) minDist = atrProxy;
         sl = entryBid + minDist;
      }
      
      sl = MathMax(sl, entryBid + minDist);
      double slDistance = sl - entryBid;
      if(slDistance > entryBid * 0.20) { sl = entryBid + entryBid * 0.20; slDistance = entryBid * 0.20; }
      
      tp = entryBid - slDistance * InpTPRatio;
      if(tp <= 0) tp = entryBid * 0.5;
   }
   
   sl = NormalizeDouble(sl, digits);
   tp = NormalizeDouble(tp, digits);
}

//+------------------------------------------------------------------+
//| Calcul de la taille de lot                                       |
//+------------------------------------------------------------------+
double CalculateLotSize(const string symbol, const double entryPrice, const double sl)
{
   double balance    = g_accountInfo.Balance();
   double riskAmount = balance * InpRiskPercent / 100.0;
   double tickValue  = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize   = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
   double lotStep    = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
   double minLot     = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   double maxLot     = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
   
   if(tickSize <= 0 || tickValue <= 0) return minLot;
   
   double slPoints     = MathAbs(entryPrice - sl) / tickSize;
   double valuePerLot  = slPoints * tickValue;
   
   if(valuePerLot <= 0) return minLot;
   
   double lots = riskAmount / valuePerLot;
   lots = MathFloor(lots / lotStep) * lotStep;
   return NormalizeDouble(MathMax(minLot, MathMin(maxLot, lots)), 2);
}

//+------------------------------------------------------------------+
//| Exécution des trades (Formatage du commentaire pour le TF)       |
//+------------------------------------------------------------------+
void ExecuteSetups(TradeSetup &setups[], string &labels[])
{
   int existingPositions = CountOpenPositions();
   
   for(int i = 0; i < ArraySize(setups); i++)
   {
      if(existingPositions >= InpMaxPositions) break;
      
      TradeSetup s = setups[i];
      if(HasOpenPosition(s.symbol)) continue;
      
      // Ajout du TF dans le commentaire pour le système de Trailing
      string comment = "IchiKP|" + s.tfName + "|Sc:" + IntegerToString(s.score);
      
      bool success = false;
      if(s.direction == "BUY")
         success = g_trade.Buy(s.lotSize, s.symbol, s.entryPrice, s.stopLoss, s.takeProfit, comment);
      else
         success = g_trade.Sell(s.lotSize, s.symbol, s.entryPrice, s.stopLoss, s.takeProfit, comment);
      
      if(success) existingPositions++;
   }
}

//+------------------------------------------------------------------+
//| Maintien des Positions (BreakEven & Trailing Stop Kijun)         |
//+------------------------------------------------------------------+
void ManagePositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!g_posInfo.SelectByIndex(i)) continue;
      if(g_posInfo.Magic() != InpMagicNumber) continue;
      
      string symbol = g_posInfo.Symbol();
      long type = g_posInfo.PositionType();
      double openPrice = g_posInfo.PriceOpen();
      double currentSL = g_posInfo.StopLoss();
      double currentTP = g_posInfo.TakeProfit();
      double currentPrice = g_posInfo.PriceCurrent();
      ulong ticket = g_posInfo.Ticket();
      
      double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
      double spread = SymbolInfoDouble(symbol, SYMBOL_ASK) - SymbolInfoDouble(symbol, SYMBOL_BID);
      int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
      
      bool modified = false;
      double newSL = currentSL;
      
      // 1. GESTION DU BREAKEVEN (Ratio 1:1)
      if(InpUseBreakEven && InpTPRatio > 0 && currentTP > 0)
      {
         double riskDist = MathAbs(currentTP - openPrice) / InpTPRatio;
         if(riskDist > point)
         {
            if(type == POSITION_TYPE_BUY && currentPrice >= openPrice + riskDist)
            {
               if(newSL < openPrice) { newSL = openPrice; modified = true; }
            }
            else if(type == POSITION_TYPE_SELL && currentPrice <= openPrice - riskDist)
            {
               if(newSL > openPrice || newSL == 0) { newSL = openPrice; modified = true; }
            }
         }
      }
      
      // 2. GESTION DU TRAILING STOP SUR KIJUN-SEN
      if(InpUseTrailing)
      {
         // Récupération du TF d'origine via le commentaire
         ENUM_TIMEFRAMES posTF = GetTFFromComment(g_posInfo.Comment());
         
         double kijun[];
         int handle = iIchimoku(symbol, posTF, InpTenkanPeriod, InpKijunPeriod, InpSenkouBPeriod);
         if(handle != INVALID_HANDLE)
         {
            ArraySetAsSeries(kijun, true);
            if(CopyBuffer(handle, 1, 0, 1, kijun) > 0)
            {
               double currentKijun = kijun[0];
               double tsBuffer = spread + (2 * point); // Marge de sécurité
               
               if(type == POSITION_TYPE_BUY)
               {
                  double trailSL = currentKijun - tsBuffer;
                  // On ne relève le SL que s'il est plus haut que le précédent ET sous le prix actuel
                  if(trailSL > newSL && trailSL < currentPrice) 
                  { 
                     newSL = trailSL; 
                     modified = true; 
                  }
               }
               else if(type == POSITION_TYPE_SELL)
               {
                  double trailSL = currentKijun + tsBuffer;
                  // On abaisse le SL que s'il est plus bas que le précédent ET au-dessus du prix
                  if((trailSL < newSL || newSL == 0) && trailSL > currentPrice) 
                  { 
                     newSL = trailSL; 
                     modified = true; 
                  }
               }
            }
            IndicatorRelease(handle);
         }
      }
      
      // Exécution de la modification si nécessaire
      if(modified)
      {
         newSL = NormalizeDouble(newSL, digits);
         if(MathAbs(newSL - currentSL) > point)
         {
            if(g_trade.PositionModify(ticket, newSL, currentTP))
               WriteLog("[GESTION] " + symbol + " SL modifié à " + DoubleToString(newSL, digits));
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Extraction du Timeframe d'origine depuis le commentaire          |
//+------------------------------------------------------------------+
ENUM_TIMEFRAMES GetTFFromComment(string comment)
{
   for(int i = 0; i < ArraySize(g_tfNames); i++)
   {
      if(StringFind(comment, "|" + g_tfNames[i] + "|") >= 0)
         return g_timeframes[i];
   }
   return PERIOD_H4; // Sécurité par défaut
}

//+------------------------------------------------------------------+
//| Utilitaires Divers (Comptage, Tableaux, Logs...)                 |
//+------------------------------------------------------------------+
int CountOpenPositions()
{
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(g_posInfo.SelectByIndex(i))
         if(g_posInfo.Magic() == InpMagicNumber) count++;
   }
   return count;
}

bool HasOpenPosition(const string symbol)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(g_posInfo.SelectByIndex(i))
         if(g_posInfo.Magic() == InpMagicNumber && g_posInfo.Symbol() == symbol)
            return true;
   }
   return false;
}

void BuildTimeframeList()
{
   ArrayResize(g_timeframes, 0); ArrayResize(g_tfNames, 0);
   struct TFEntry { ENUM_TIMEFRAMES tf; string name; bool active; };
   TFEntry entries[] = {
      {PERIOD_M1,  "M1",  InpTradeM1}, {PERIOD_M5,  "M5",  InpTradeM5},
      {PERIOD_M15, "M15", InpTradeM15}, {PERIOD_M30, "M30", InpTradeM30},
      {PERIOD_H1,  "H1",  InpTradeH1}, {PERIOD_H4,  "H4",  InpTradeH4},
      {PERIOD_D1,  "D1",  InpTradeD1}, {PERIOD_W1,  "W1",  InpTradeW1},
      {PERIOD_MN1, "MN",  InpTradeMN}
   };
   for(int i = 0; i < ArraySize(entries); i++)
   {
      if(entries[i].active)
      {
         int sz = ArraySize(g_timeframes);
         ArrayResize(g_timeframes, sz + 1); ArrayResize(g_tfNames, sz + 1);
         g_timeframes[sz] = entries[i].tf; g_tfNames[sz] = entries[i].name;
      }
   }
}

void AddToArray(string &arr[], const string value) { int sz = ArraySize(arr); ArrayResize(arr, sz + 1); arr[sz] = value; }

void WriteLog(const string message)
{
   Print(message);
   int handle = FileOpen(g_logPath, FILE_WRITE|FILE_READ|FILE_TXT|FILE_ANSI|FILE_SHARE_READ);
   if(handle == INVALID_HANDLE) handle = FileOpen(g_logPath, FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_SHARE_READ);
   if(handle != INVALID_HANDLE)
   {
      FileSeek(handle, 0, SEEK_END);
      FileWriteString(handle, message + "\n");
      FileClose(handle);
   }
}

string StringRepeat(const string s, const int count) { string res = ""; for(int i=0; i<count; i++) res+=s; return res; }

void WriteSummary(TradeSetup &setups[], string &labels[], const int count)
{
   string summary = "\n" + StringRepeat("=", 70) + "\n";
   summary += "  RÉSUMÉ - " + IntegerToString(count) + " SETUP(S) IDENTIFIÉ(S)\n";
   summary += StringRepeat("=", 70) + "\n";
   if(count == 0) summary += "  Aucun setup valide détecté.\n";
   else
   {
      for(int i = 0; i < ArraySize(setups); i++)
      {
         TradeSetup s = setups[i];
         summary += "  [" + IntegerToString(i+1) + "] " + labels[i] + " -> " + s.direction + 
                    " | Score: " + IntegerToString(s.score) + "/11\n";
      }
   }
   WriteLog(summary);
}
