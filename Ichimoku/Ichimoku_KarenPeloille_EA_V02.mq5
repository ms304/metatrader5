//+------------------------------------------------------------------+
//|                    Ichimoku_KarenPeloille_EA.mq5                 |
//|          Expert Advisor - Méthode Ichimoku Karen Péloille        |
//|          v2.0 - Filtre Kumo % + Confirmation Multi-TF            |
//+------------------------------------------------------------------+
#property copyright   "Ichimoku EA - Méthode Karen Péloille - Didier V. Le HPI Réunionnais"
#property version     "2.00"
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

// -----------------------------------------------------------------
// CORRECTION 1 : Filtre Kumo en % du prix
// Remplace l'ancien filtre en points absolus (3 pts) qui était
// inutilisable sur des actifs à faible valeur comme ADAUSD (0.25$).
// Exemple : MinKumoPct=0.05% → sur ADAUSD 0.25$ = seuil 0.000125$
//           sur BTCUSD 78000$ = seuil 39$ (cohérent)
// -----------------------------------------------------------------
input group "=== FILTRES QUALITÉ ==="
input double InpMinKumoPct      = 0.05; // Épaisseur Kumo minimale (% du prix)
input double InpMinKumoPoints   = 5;    // Épaisseur Kumo minimale (points absolus, fallback)

// -----------------------------------------------------------------
// CORRECTION 2 : Confirmation Multi-Timeframe
// Un setup sur TF court n'est validé QUE si le TF supérieur
// est aligné dans la même direction.
// Règle Karen Péloille : le TF supérieur prime toujours.
// -----------------------------------------------------------------
input group "=== CONFIRMATION MULTI-TF ==="
input bool   InpRequireHTFConfirm = true;  // Exiger confirmation TF supérieur
// Score minimum sur le TF supérieur pour valider (sur 11)
// Ex: 5 = au moins 5 critères haussiers/baissiers sur le TF du dessus
input int    InpHTFMinScore       = 5;
// Si true : le setup est rejeté si le TF supérieur est en sens CONTRAIRE
// Si false : le setup passe si le TF supérieur est neutre (pas de signal fort opposé)
input bool   InpRejectOnConflict  = true;

input group "=== TIMEFRAMES ACTIFS ==="
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
   double senkouA;
   double senkouB;
   double senkouA_fwd;
   double senkouB_fwd;
   double chikou;
   double price_at_chikou;
   double kumo_at_chikou_A;
   double kumo_at_chikou_B;
};

struct TradeSetup
{
   string   symbol;
   ENUM_TIMEFRAMES timeframe;
   string   direction;
   double   entryPrice;
   double   stopLoss;
   double   takeProfit;
   double   lotSize;
   int      score;
   string   reasons[];
   string   warnings[];
   bool     isValid;
   // Nouveau : score et direction du TF supérieur (pour log)
   int      htfScore;
   string   htfDirection;
   string   htfName;
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
datetime      g_lastAnalysisTime = 0;
int           g_analysisInterval = 300;

ENUM_TIMEFRAMES g_timeframes[];
string          g_tfNames[];

//+------------------------------------------------------------------+
//| Initialisation                                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   g_trade.SetExpertMagicNumber(InpMagicNumber);
   g_trade.SetDeviationInPoints(20);
   g_logPath = InpLogFileName;
   BuildTimeframeList();

   string startMsg = "\n" + StringRepeat("=", 70) + "\n";
   startMsg += "  ICHIMOKU EXPERT ADVISOR v2.0 - MÉTHODE KAREN PÉLOILLE\n";
   startMsg += "  Démarrage: " + TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES) + "\n";
   startMsg += "  Compte: " + IntegerToString((int)g_accountInfo.Login()) +
               " | Solde: " + DoubleToString(g_accountInfo.Balance(), 2) + " " +
               g_accountInfo.Currency() + "\n";
   startMsg += "  Risk/trade: " + DoubleToString(InpRiskPercent, 1) + "%" +
               " | Magic: " + IntegerToString(InpMagicNumber) + "\n";
   startMsg += "  Mode: " + (InpAutoTrade ? "TRADING AUTOMATIQUE ACTIF" : "Analyse uniquement") + "\n";
   // Log des nouveaux paramètres
   startMsg += "  [v2] Filtre Kumo: " + DoubleToString(InpMinKumoPct, 3) + "% du prix\n";
   startMsg += "  [v2] Confirmation HTF: " + (InpRequireHTFConfirm ? "OUI" : "NON") +
               " | Score HTF min: " + IntegerToString(InpHTFMinScore) + "/11\n";
   startMsg += "  [v2] Rejet si conflit HTF: " + (InpRejectOnConflict ? "OUI" : "NON") + "\n";
   startMsg += StringRepeat("=", 70);
   WriteLog(startMsg);

   Print("Ichimoku KP EA v2.0 démarré. Log: ", g_logPath);
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
   datetime now = TimeCurrent();
   if(now - g_lastAnalysisTime >= g_analysisInterval)
   {
      RunFullAnalysis();
      g_lastAnalysisTime = now;
   }
}

//+------------------------------------------------------------------+
//| Analyse complète de tous les actifs du Market Watch              |
//+------------------------------------------------------------------+
void RunFullAnalysis()
{
   string header = "\n" + StringRepeat("*", 70) + "\n";
   header += "  ANALYSE ICHIMOKU COMPLÈTE v2.0\n";
   header += "  Date/Heure: " + TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES|TIME_SECONDS) + "\n";
   header += "  Solde: " + DoubleToString(g_accountInfo.Balance(), 2) + " " + g_accountInfo.Currency() +
             " | Equity: " + DoubleToString(g_accountInfo.Equity(), 2) + "\n";
   header += StringRepeat("*", 70);
   WriteLog(header);

   int symbolCount = SymbolsTotal(true);
   int setupCount  = 0;

   TradeSetup allSetups[];
   string     allSetupsSymbols[];

   WriteLog("\n[SCAN] " + IntegerToString(symbolCount) + " actif(s) dans le Market Watch");

   for(int i = 0; i < symbolCount; i++)
   {
      string sym = SymbolName(i, true);
      if(sym == "") continue;

      bool tradable = IsSymbolTradable(sym);
      string tradableStr = tradable ? "OUVERT" : "FERMÉ/NON TRADABLE";

      WriteLog("\n" + StringRepeat("-", 60));
      WriteLog("[ACTIF] " + sym + " | Marché: " + tradableStr);

      if(!tradable)
         WriteLog("  >> Actif ignoré pour le trading (marché fermé ou non tradable)");

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

   WriteSummary(allSetups, allSetupsSymbols, setupCount);

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
//| CORRECTION 1 : Filtre Kumo en pourcentage du prix               |
//| Retourne true si le Kumo est suffisamment épais pour être        |
//| exploitable sur cet actif/TF.                                    |
//| Utilise InpMinKumoPct (ex: 0.05%) × prix comme seuil dynamique. |
//+------------------------------------------------------------------+
bool IsKumoThickEnough(const string symbol, const double price,
                        const double senkouA, const double senkouB,
                        const double senkouA_fwd, const double senkouB_fwd,
                        const string tfName, string &reason)
{
   double point      = SymbolInfoDouble(symbol, SYMBOL_POINT);
   double kumoNow    = MathAbs(senkouA - senkouB);
   double kumoFut    = MathAbs(senkouA_fwd - senkouB_fwd);

   // Seuil dynamique : % du prix courant (adapté à tous les actifs)
   double minByPct   = price * InpMinKumoPct / 100.0;
   // Seuil absolu fallback (en points)
   double minByPts   = InpMinKumoPoints * point;
   // On prend le MAX des deux seuils pour être robuste
   double minThresh  = MathMax(minByPct, minByPts);

   if(kumoNow < minThresh && kumoFut < minThresh)
   {
      reason = "Kumo trop plat: actuel=" +
               DoubleToString(kumoNow / point, 1) + "pts (" +
               DoubleToString(kumoNow / price * 100, 4) + "% prix) | " +
               "seuil=" + DoubleToString(minThresh / point, 1) + "pts (" +
               DoubleToString(InpMinKumoPct, 3) + "%)";
      return false;
   }
   return true;
}

//+------------------------------------------------------------------+
//| CORRECTION 2 : Obtenir le TF supérieur dans la liste active     |
//| Retourne PERIOD_CURRENT si aucun TF supérieur n'est trouvé      |
//+------------------------------------------------------------------+
ENUM_TIMEFRAMES GetHigherTimeframe(const ENUM_TIMEFRAMES tf, string &htfName)
{
   int tfCount = ArraySize(g_timeframes);
   for(int i = 0; i < tfCount; i++)
   {
      if(g_timeframes[i] == tf && i + 1 < tfCount)
      {
         htfName = g_tfNames[i + 1];
         return g_timeframes[i + 1];
      }
   }
   htfName = "";
   return PERIOD_CURRENT; // Pas de TF supérieur disponible
}

//+------------------------------------------------------------------+
//| CORRECTION 2 : Calcul rapide du score directionnel sur un TF    |
//| Utilisé pour la confirmation HTF sans logging complet            |
//+------------------------------------------------------------------+
bool GetHTFScore(const string symbol, const ENUM_TIMEFRAMES tf,
                  int &bullScore, int &bearScore)
{
   bullScore = 0;
   bearScore = 0;

   int handle = iIchimoku(symbol, tf, InpTenkanPeriod, InpKijunPeriod, InpSenkouBPeriod);
   if(handle == INVALID_HANDLE) return false;

   int barsNeeded = InpSenkouBPeriod + InpDisplacement * 3 + 20;

   double tenkan[], kijun[], senkouA[], senkouB[], chikou[], close[];
   double high[], low[];
   ArraySetAsSeries(tenkan,  true); ArraySetAsSeries(kijun,   true);
   ArraySetAsSeries(senkouA, true); ArraySetAsSeries(senkouB, true);
   ArraySetAsSeries(chikou,  true); ArraySetAsSeries(close,   true);
   ArraySetAsSeries(high,    true); ArraySetAsSeries(low,     true);

   bool ok = (CopyBuffer(handle, 0, 0, barsNeeded, tenkan)  >= barsNeeded &&
              CopyBuffer(handle, 1, 0, barsNeeded, kijun)   >= barsNeeded &&
              CopyBuffer(handle, 2, 0, barsNeeded, senkouA) >= barsNeeded &&
              CopyBuffer(handle, 3, 0, barsNeeded, senkouB) >= barsNeeded &&
              CopyBuffer(handle, 4, 0, barsNeeded, chikou)  >= barsNeeded &&
              CopyClose(symbol, tf, 0, barsNeeded, close)   >= barsNeeded &&
              CopyHigh(symbol,  tf, 0, barsNeeded, high)    >= barsNeeded &&
              CopyLow(symbol,   tf, 0, barsNeeded, low)     >= barsNeeded);
   IndicatorRelease(handle);
   if(!ok) return false;

   double price   = close[0];
   double onePoint = SymbolInfoDouble(symbol, SYMBOL_POINT);

   // --- Filtre Kumo % aussi sur le HTF ---
   double sa = senkouA[InpDisplacement];
   double sb = senkouB[InpDisplacement];
   double sa_fwd = senkouA[0];
   double sb_fwd = senkouB[0];
   string unused;
   if(!IsKumoThickEnough(symbol, price, sa, sb, sa_fwd, sb_fwd, "", unused))
      return false;

   double kumoTop    = MathMax(sa, sb);
   double kumoBottom = MathMin(sa, sb);

   // C1 : Position prix / Kumo
   if(price > kumoTop)    bullScore += 2;
   else if(price < kumoBottom) bearScore += 2;

   // C2 : Couleur Kumo actuel
   if(sa > sb) bullScore += 1; else bearScore += 1;

   // C2b : Kumo futur
   if(sa_fwd > sb_fwd) bullScore += 1; else bearScore += 1;

   // C3 : Tenkan / Kijun
   if(tenkan[0] > kijun[0])      bullScore += 1;
   else if(tenkan[0] < kijun[0]) bearScore += 1;

   // C4 : TK Cross
   if(tenkan[1] <= kijun[1] && tenkan[0] > kijun[0]) bullScore += 3;
   else if(tenkan[1] >= kijun[1] && tenkan[0] < kijun[0]) bearScore += 3;

   // C5 : Prix > Tenkan et Kijun
   if(price > tenkan[0] && price > kijun[0])      bullScore += 1;
   else if(price < tenkan[0] && price < kijun[0]) bearScore += 1;

   // C6 : Chikou (simplifié)
   double chikouTol  = MathMax(5.0 * onePoint, price * 0.0005);
   double priceT26   = close[InpDisplacement];
   double kumoCA     = senkouA[InpDisplacement * 2];
   double kumoCB     = senkouB[InpDisplacement * 2];
   double kumoTopC   = MathMax(kumoCA, kumoCB);
   double kumoBottomC = MathMin(kumoCA, kumoCB);

   if(price > priceT26 + chikouTol && price > kumoTopC + chikouTol)
      bullScore += 3;
   else if(price < priceT26 - chikouTol && price < kumoBottomC - chikouTol)
      bearScore += 3;

   return true;
}

//+------------------------------------------------------------------+
//| Analyse Ichimoku complète sur un symbole/timeframe               |
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
   ArraySetAsSeries(tenkan,  true); ArraySetAsSeries(kijun,   true);
   ArraySetAsSeries(senkouA, true); ArraySetAsSeries(senkouB, true);
   ArraySetAsSeries(chikou,  true);

   if(CopyBuffer(handle, 0, 0, barsNeeded, tenkan)  < barsNeeded ||
      CopyBuffer(handle, 1, 0, barsNeeded, kijun)   < barsNeeded ||
      CopyBuffer(handle, 2, 0, barsNeeded, senkouA) < barsNeeded ||
      CopyBuffer(handle, 3, 0, barsNeeded, senkouB) < barsNeeded ||
      CopyBuffer(handle, 4, 0, barsNeeded, chikou)  < barsNeeded)
   {
      IndicatorRelease(handle);
      if(InpVerboseLog)
         WriteLog("  [" + tfName + "] Données insuffisantes sur " + symbol);
      return false;
   }
   IndicatorRelease(handle);

   double close[], high[], low[], open[];
   ArraySetAsSeries(close, true); ArraySetAsSeries(high,  true);
   ArraySetAsSeries(low,   true); ArraySetAsSeries(open,  true);

   if(CopyClose(symbol, tf, 0, barsNeeded, close) < barsNeeded) return false;
   if(CopyHigh(symbol,  tf, 0, barsNeeded, high)  < barsNeeded) return false;
   if(CopyLow(symbol,   tf, 0, barsNeeded, low)   < barsNeeded) return false;
   if(CopyOpen(symbol,  tf, 0, barsNeeded, open)  < barsNeeded) return false;

   IchimokuValues ich;
   ich.tenkan      = tenkan[0];
   ich.kijun       = kijun[0];
   ich.senkouA_fwd = senkouA[0];
   ich.senkouB_fwd = senkouB[0];
   ich.senkouA     = senkouA[InpDisplacement];
   ich.senkouB     = senkouB[InpDisplacement];
   ich.chikou      = close[0];
   ich.price_at_chikou  = close[InpDisplacement];
   ich.kumo_at_chikou_A = senkouA[InpDisplacement * 2];
   ich.kumo_at_chikou_B = senkouB[InpDisplacement * 2];

   double currentPrice = close[0];
   double currentHigh  = high[0];
   double currentLow   = low[0];

   double DBL_LIMIT = 1e15;
   if(ich.tenkan      <= 0 || ich.tenkan      > DBL_LIMIT ||
      ich.kijun       <= 0 || ich.kijun       > DBL_LIMIT ||
      ich.senkouA     <= 0 || ich.senkouA     > DBL_LIMIT ||
      ich.senkouB     <= 0 || ich.senkouB     > DBL_LIMIT ||
      ich.senkouA_fwd <= 0 || ich.senkouA_fwd > DBL_LIMIT ||
      ich.senkouB_fwd <= 0 || ich.senkouB_fwd > DBL_LIMIT ||
      ich.chikou      <= 0 || ich.chikou      > DBL_LIMIT ||
      ich.price_at_chikou <= 0 || currentPrice <= 0)
   {
      if(InpVerboseLog)
         WriteLog("  [" + tfName + "] Valeurs Ichimoku invalides sur " + symbol);
      setup.isValid = false;
      return false;
   }

   // ================================================================
   // CORRECTION 1 : FILTRE KUMO EN % DU PRIX
   // ================================================================
   string kumoFilterReason = "";
   if(!IsKumoThickEnough(symbol, currentPrice,
                          ich.senkouA, ich.senkouB,
                          ich.senkouA_fwd, ich.senkouB_fwd,
                          tfName, kumoFilterReason))
   {
      if(InpVerboseLog)
         WriteLog("  [" + tfName + "] Kumo filtré (" + symbol + "): " + kumoFilterReason);
      setup.isValid = false;
      return false;
   }

   // Log d'analyse
   string logEntry = "\n  [" + tfName + "] Analyse " + symbol + "\n";
   logEntry += "  Prix: " + DoubleToString(currentPrice, _Digits) +
               " | T: " + DoubleToString(ich.tenkan, _Digits) +
               " | K: " + DoubleToString(ich.kijun, _Digits) + "\n";
   logEntry += "  Kumo: [" + DoubleToString(MathMin(ich.senkouA, ich.senkouB), _Digits) +
               " - " + DoubleToString(MathMax(ich.senkouA, ich.senkouB), _Digits) + "]" +
               " | Kumo futur: [" + DoubleToString(MathMin(ich.senkouA_fwd, ich.senkouB_fwd), _Digits) +
               " - " + DoubleToString(MathMax(ich.senkouA_fwd, ich.senkouB_fwd), _Digits) + "]\n";
   logEntry += "  Chikou: " + DoubleToString(ich.chikou, _Digits) +
               " vs Prix t-26: " + DoubleToString(ich.price_at_chikou, _Digits);
   WriteLog(logEntry);

   int bullScore = 0;
   int bearScore = 0;
   string bullReasons[], bearReasons[];
   string warnings[];

   // C1 : Position prix / Kumo
   double kumoTop    = MathMax(ich.senkouA, ich.senkouB);
   double kumoBottom = MathMin(ich.senkouA, ich.senkouB);
   double kumoThickness = kumoTop - kumoBottom;
   bool priceAboveKumo = currentPrice > kumoTop;
   bool priceBelowKumo = currentPrice < kumoBottom;

   string kumoPos;
   if(priceAboveKumo)      { kumoPos = "AU-DESSUS du Kumo (HAUSSIER)"; bullScore += 2; AddToArray(bullReasons, "Prix au-dessus du Kumo"); }
   else if(priceBelowKumo) { kumoPos = "EN-DESSOUS du Kumo (BAISSIER)"; bearScore += 2; AddToArray(bearReasons, "Prix en-dessous du Kumo"); }
   else                    { kumoPos = "DANS le Kumo (neutre/danger)"; AddToArray(warnings, "Prix dans le Kumo - signal faible"); }
   WriteLog("  C1 - Position/Kumo: " + kumoPos);

   // C2 : Couleur Kumo
   bool kumoHaussier      = ich.senkouA > ich.senkouB;
   bool kumoFuturHaussier = ich.senkouA_fwd > ich.senkouB_fwd;
   if(kumoHaussier)      { bullScore += 1; AddToArray(bullReasons, "Kumo vert (SA > SB)"); }
   else                  { bearScore += 1; AddToArray(bearReasons, "Kumo rouge (SB > SA)"); }
   if(kumoFuturHaussier) { bullScore += 1; AddToArray(bullReasons, "Kumo futur vert"); }
   else                  { bearScore += 1; AddToArray(bearReasons, "Kumo futur rouge"); }
   WriteLog("  C2 - Kumo actuel: " + (kumoHaussier ? "VERT" : "ROUGE") +
            " | Kumo futur: " + (kumoFuturHaussier ? "VERT" : "ROUGE"));

   // C3 : Tenkan / Kijun
   bool tenkanAboveKijun = ich.tenkan > ich.kijun;
   if(tenkanAboveKijun)       { bullScore += 1; AddToArray(bullReasons, "Tenkan > Kijun"); }
   else if(ich.tenkan < ich.kijun) { bearScore += 1; AddToArray(bearReasons, "Tenkan < Kijun"); }
   else AddToArray(warnings, "Tenkan = Kijun (compression)");
   WriteLog("  C3 - Tenkan/Kijun: " + (tenkanAboveKijun ? "T > K (haussier)" :
            (ich.tenkan < ich.kijun ? "T < K (baissier)" : "T = K (neutre)")));

   // C4 : TK Cross
   double prevTenkan = tenkan[1];
   double prevKijun  = kijun[1];
   bool tkGoldenCross = (prevTenkan <= prevKijun) && (ich.tenkan > ich.kijun);
   bool tkDeathCross  = (prevTenkan >= prevKijun) && (ich.tenkan < ich.kijun);
   if(tkGoldenCross)
   { bullScore += 3; AddToArray(bullReasons, "TK Golden Cross"); WriteLog("  C4 - TK CROSS: *** GOLDEN CROSS ***"); }
   else if(tkDeathCross)
   { bearScore += 3; AddToArray(bearReasons, "TK Death Cross"); WriteLog("  C4 - TK CROSS: *** DEATH CROSS ***"); }
   else WriteLog("  C4 - TK CROSS: Pas de croisement");

   // C5 : Prix / Tenkan + Kijun
   bool priceAboveTenkan = currentPrice > ich.tenkan;
   bool priceAboveKijun  = currentPrice > ich.kijun;
   if(priceAboveTenkan && priceAboveKijun)
   { bullScore += 1; AddToArray(bullReasons, "Prix > Tenkan et Prix > Kijun"); }
   else if(!priceAboveTenkan && !priceAboveKijun)
   { bearScore += 1; AddToArray(bearReasons, "Prix < Tenkan et Prix < Kijun"); }
   WriteLog("  C5 - Prix/TK: " + (priceAboveTenkan ? "Prix>T" : "Prix<T") +
            " | " + (priceAboveKijun ? "Prix>K" : "Prix<K"));

   // C6 : Chikou
   double onePoint   = SymbolInfoDouble(symbol, SYMBOL_POINT);
   double chikouTol  = MathMax(5.0 * onePoint, currentPrice * 0.0005);
   bool chikouAbovePrice = ich.chikou > ich.price_at_chikou + chikouTol;
   bool chikouBelowPrice = ich.chikou < ich.price_at_chikou - chikouTol;
   double kumoTopAtChikou    = MathMax(ich.kumo_at_chikou_A, ich.kumo_at_chikou_B);
   double kumoBottomAtChikou = MathMin(ich.kumo_at_chikou_A, ich.kumo_at_chikou_B);
   bool chikouAboveKumo = ich.chikou > kumoTopAtChikou    + chikouTol;
   bool chikouBelowKumo = ich.chikou < kumoBottomAtChikou - chikouTol;
   bool chikouInKumo    = !chikouAboveKumo && !chikouBelowKumo;

   string chikouAnalysis;
   if(chikouAbovePrice && chikouAboveKumo)
   { bullScore += 3; AddToArray(bullReasons, "Chikou au-dessus des prix ET du Kumo passé (fort)"); chikouAnalysis = "HAUSSIER FORT"; }
   else if(chikouAbovePrice && chikouInKumo)
   { bullScore += 1; AddToArray(bullReasons, "Chikou au-dessus des prix (dans Kumo passé)"); AddToArray(warnings, "Chikou traverse le Kumo passé"); chikouAnalysis = "HAUSSIER MODÉRÉ"; }
   else if(chikouBelowPrice && chikouBelowKumo)
   { bearScore += 3; AddToArray(bearReasons, "Chikou en-dessous des prix ET du Kumo passé (fort)"); chikouAnalysis = "BAISSIER FORT"; }
   else if(chikouBelowPrice && chikouInKumo)
   { bearScore += 1; AddToArray(bearReasons, "Chikou en-dessous des prix (dans Kumo passé)"); AddToArray(warnings, "Chikou traverse le Kumo passé"); chikouAnalysis = "BAISSIER MODÉRÉ"; }
   else
   { AddToArray(warnings, "Chikou en zone neutre ou contradictoire"); chikouAnalysis = "NEUTRE"; }
   WriteLog("  C6 - CHIKOU: " + chikouAnalysis + " | " +
            DoubleToString(ich.chikou, _Digits) + " vs t-26=" +
            DoubleToString(ich.price_at_chikou, _Digits));

   // C7 : Distance Kijun
   double kijunDistPct = (ich.kijun > 0) ? MathAbs(currentPrice - ich.kijun) / ich.kijun * 100 : 0;
   if(kijunDistPct < 0.1) AddToArray(warnings, "Prix très proche du Kijun (" + DoubleToString(kijunDistPct, 2) + "%)");
   WriteLog("  C7 - Distance au Kijun: " + DoubleToString(kijunDistPct, 3) + "%");

   // C8 : Épaisseur Kumo (informatif)
   double kijunValue      = ich.kijun > 0 ? ich.kijun : 1;
   double kumoThickPct    = kumoThickness / kijunValue * 100;
   if(kumoThickPct > 3.0) AddToArray(warnings, "Kumo épais (" + DoubleToString(kumoThickPct, 2) + "%) - traversée difficile");
   WriteLog("  C8 - Épaisseur Kumo: " + DoubleToString(kumoThickPct, 3) + "%");

   // ================================================================
   // SYNTHÈSE DIRECTIONELLE
   // ================================================================
   string direction = "";
   int    totalScore = 0;
   bool   setupValid = false;

   string synthesis = "\n  SYNTHÈSE [" + tfName + "] " + symbol + ":\n";
   synthesis += "  Score BULL: " + IntegerToString(bullScore) +
                " | Score BEAR: " + IntegerToString(bearScore) + "\n";

   if(bullScore >= 6 && bullScore > bearScore + 2)
   {
      direction  = "BUY";
      totalScore = bullScore;
      setupValid = true;
      synthesis += "  >> SETUP HAUSSIER INITIAL (score " + IntegerToString(bullScore) + "/11)\n";
   }
   else if(bearScore >= 6 && bearScore > bullScore + 2)
   {
      direction  = "SELL";
      totalScore = bearScore;
      setupValid = true;
      synthesis += "  >> SETUP BAISSIER INITIAL (score " + IntegerToString(bearScore) + "/11)\n";
   }
   else
   {
      synthesis += "  >> PAS DE SETUP (scores insuffisants ou contradictoires)\n";
   }

   // ================================================================
   // CORRECTION 2 : CONFIRMATION MULTI-TIMEFRAME
   // ================================================================
   bool htfConfirmed = true;
   int  htfBull = 0, htfBear = 0;
   string htfName = "";
   string htfLog  = "";

   if(setupValid && InpRequireHTFConfirm)
   {
      ENUM_TIMEFRAMES htf = GetHigherTimeframe(tf, htfName);

      if(htf == PERIOD_CURRENT || htfName == "")
      {
         // Pas de TF supérieur disponible dans la liste active
         // → On accepte le setup mais on le signale
         htfLog = "  [HTF] Aucun TF supérieur actif - confirmation non disponible\n";
         synthesis += htfLog;
      }
      else
      {
         bool htfOk = GetHTFScore(symbol, htf, htfBull, htfBear);

         if(!htfOk)
         {
            // Données HTF insuffisantes → on rejette par prudence
            htfConfirmed = false;
            htfLog = "  [HTF " + htfName + "] Données insuffisantes - setup rejeté par prudence\n";
         }
         else
         {
            string htfDir = "";
            int    htfScore = 0;
            if(htfBull > htfBear + 1) { htfDir = "BUY";  htfScore = htfBull; }
            else if(htfBear > htfBull + 1) { htfDir = "SELL"; htfScore = htfBear; }
            else { htfDir = "NEUTRE"; htfScore = 0; }

            htfLog = "  [HTF " + htfName + "] Score BULL=" + IntegerToString(htfBull) +
                     " BEAR=" + IntegerToString(htfBear) +
                     " Direction=" + htfDir + "\n";

            bool aligned  = (htfDir == direction);
            bool neutral  = (htfDir == "NEUTRE");
            bool conflict = (!aligned && !neutral);

            if(conflict && InpRejectOnConflict)
            {
               // Le TF supérieur dit le CONTRAIRE → rejet total
               htfConfirmed = false;
               htfLog += "  [HTF] CONFLIT de direction (" + htfDir + " vs " + direction +
                         ") → Setup REJETÉ\n";
            }
            else if(aligned && htfScore >= InpHTFMinScore)
            {
               // Alignement parfait et score suffisant → confirmation forte
               htfLog += "  [HTF] Confirmation FORTE - TF supérieur aligné (score " +
                         IntegerToString(htfScore) + "/" + IntegerToString(InpHTFMinScore) + " requis)\n";
            }
            else if(neutral && !InpRejectOnConflict)
            {
               // HTF neutre + rejet conflit désactivé → on laisse passer
               htfLog += "  [HTF] TF supérieur neutre - setup accepté (InpRejectOnConflict=false)\n";
            }
            else if(neutral && InpRejectOnConflict)
            {
               // HTF neutre mais on est strict → rejet
               htfConfirmed = false;
               htfLog += "  [HTF] TF supérieur neutre → Setup REJETÉ (mode strict)\n";
            }
            else if(aligned && htfScore < InpHTFMinScore)
            {
               // Aligné mais score insuffisant
               htfConfirmed = false;
               htfLog += "  [HTF] Score HTF insuffisant (" + IntegerToString(htfScore) +
                         " < " + IntegerToString(InpHTFMinScore) + " requis) → Setup REJETÉ\n";
            }

            // Remplissage pour le rapport
            setup.htfScore     = htfScore;
            setup.htfDirection = htfDir;
            setup.htfName      = htfName;
         }
         synthesis += htfLog;
      }
   }

   if(setupValid && !htfConfirmed)
   {
      setupValid = false;
      synthesis += "  >> SETUP ANNULÉ après vérification HTF\n";
   }
   else if(setupValid && htfConfirmed)
   {
      synthesis += "  >> SETUP CONFIRMÉ (" + direction + ")\n";
   }

   // Raisons
   if(direction == "BUY")
   {
      synthesis += "  Raisons haussières:\n";
      for(int r = 0; r < ArraySize(bullReasons); r++)
         synthesis += "    + " + bullReasons[r] + "\n";
   }
   else if(direction == "SELL")
   {
      synthesis += "  Raisons baissières:\n";
      for(int r = 0; r < ArraySize(bearReasons); r++)
         synthesis += "    - " + bearReasons[r] + "\n";
   }
   if(ArraySize(warnings) > 0)
   {
      synthesis += "  Alertes:\n";
      for(int w = 0; w < ArraySize(warnings); w++)
         synthesis += "    ! " + warnings[w] + "\n";
   }

   // Calcul SL/TP/Lots si setup valide
   if(setupValid)
   {
      double entryPrice = SymbolInfoDouble(symbol, SYMBOL_ASK);
      if(direction == "SELL") entryPrice = SymbolInfoDouble(symbol, SYMBOL_BID);

      double sl = 0, tp = 0;
      CalculateSLTP(symbol, tf, direction, ich, currentPrice, high, low, sl, tp);
      double lotSize = CalculateLotSize(symbol, entryPrice, sl);

      synthesis += "\n  TRADE PROPOSÉ:\n";
      synthesis += "  Direction:   " + direction + "\n";
      synthesis += "  Entrée:      " + DoubleToString(entryPrice, _Digits) + "\n";
      synthesis += "  Stop Loss:   " + DoubleToString(sl, _Digits) + "\n";
      synthesis += "  Take Profit: " + DoubleToString(tp, _Digits) + "\n";
      synthesis += "  Lots:        " + DoubleToString(lotSize, 2) + "\n";
      double slPts = MathAbs(entryPrice - sl) / SymbolInfoDouble(symbol, SYMBOL_POINT);
      double tpPts = MathAbs(tp - entryPrice) / SymbolInfoDouble(symbol, SYMBOL_POINT);
      synthesis += "  SL: " + DoubleToString(slPts, 0) + " pts | TP: " +
                   DoubleToString(tpPts, 0) + " pts | R/R: 1:" +
                   DoubleToString(tpPts / MathMax(slPts, 1), 2) + "\n";

      setup.symbol     = symbol;
      setup.timeframe  = tf;
      setup.direction  = direction;
      setup.entryPrice = entryPrice;
      setup.stopLoss   = sl;
      setup.takeProfit = tp;
      setup.lotSize    = lotSize;
      setup.score      = totalScore;
      setup.isValid    = true;

      if(direction == "BUY")
      {
         ArrayResize(setup.reasons, ArraySize(bullReasons));
         for(int r = 0; r < ArraySize(bullReasons); r++) setup.reasons[r] = bullReasons[r];
      }
      else
      {
         ArrayResize(setup.reasons, ArraySize(bearReasons));
         for(int r = 0; r < ArraySize(bearReasons); r++) setup.reasons[r] = bearReasons[r];
      }
      ArrayResize(setup.warnings, ArraySize(warnings));
      for(int w = 0; w < ArraySize(warnings); w++) setup.warnings[w] = warnings[w];
   }
   else
   {
      setup.isValid = false;
   }

   WriteLog(synthesis);
   return true;
}

//+------------------------------------------------------------------+
//| Calcul Stop Loss et Take Profit selon méthode KP                |
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
      double entryPrice = entryBuy;
      double slKijun  = ich.kijun  - spread - point;
      double slKumo   = MathMin(ich.senkouA, ich.senkouB) - spread - point;

      if(currentPrice > MathMax(ich.senkouA, ich.senkouB))
         sl = slKijun;
      else
         sl = slKumo;

      if(entryPrice - sl < minDist)
      {
         double hh = high[0], ll = low[0];
         int lb = MathMin(14, ArraySize(high)-1);
         for(int k = 1; k <= lb; k++) { if(high[k] > hh) hh = high[k]; if(low[k] < ll) ll = low[k]; }
         double atr = (hh - ll) * 0.5;
         if(atr > minDist) minDist = atr;
         sl = entryPrice - minDist;
      }
      sl = MathMin(sl, entryPrice - minDist);
      double slDist = entryPrice - sl;
      if(slDist > entryPrice * 0.20) { sl = entryPrice - entryPrice * 0.20; slDist = entryPrice * 0.20; WriteLog("  [WARN] SL plafonné à 20%"); }
      tp = entryPrice + slDist * InpTPRatio;
      double fkB = MathMin(ich.senkouA_fwd, ich.senkouB_fwd);
      double fkT = MathMax(ich.senkouA_fwd, ich.senkouB_fwd);
      if(tp > fkB && tp < fkT) tp = fkT + spread;
   }
   else
   {
      double entryPrice = entryBid;
      double slKijun  = ich.kijun  + spread + point;
      double slKumo   = MathMax(ich.senkouA, ich.senkouB) + spread + point;

      if(currentPrice < MathMin(ich.senkouA, ich.senkouB))
         sl = slKijun;
      else
         sl = slKumo;

      if(sl - entryPrice < minDist)
      {
         double hh = high[0], ll = low[0];
         int lb = MathMin(14, ArraySize(high)-1);
         for(int k = 1; k <= lb; k++) { if(high[k] > hh) hh = high[k]; if(low[k] < ll) ll = low[k]; }
         double atr = (hh - ll) * 0.5;
         if(atr > minDist) minDist = atr;
         sl = entryPrice + minDist;
      }
      sl = MathMax(sl, entryPrice + minDist);
      double slDist = sl - entryPrice;
      if(slDist > entryPrice * 0.20) { sl = entryPrice + entryPrice * 0.20; slDist = entryPrice * 0.20; WriteLog("  [WARN] SL plafonné à 20%"); }
      if(tp <= 0) tp = entryPrice * 0.5;
      tp = entryPrice - slDist * InpTPRatio;
      double fkB = MathMin(ich.senkouA_fwd, ich.senkouB_fwd);
      double fkT = MathMax(ich.senkouA_fwd, ich.senkouB_fwd);
      if(tp > fkB && tp < fkT) tp = fkB - spread;
      if(tp <= 0) tp = entryPrice * 0.5;
   }

   sl = NormalizeDouble(sl, digits);
   tp = NormalizeDouble(tp, digits);
}

//+------------------------------------------------------------------+
//| Calcul de la taille de lot (risque fixe %)                      |
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
   double slPoints    = MathAbs(entryPrice - sl) / tickSize;
   double valuePerLot = slPoints * tickValue;
   if(valuePerLot <= 0) return minLot;
   double lots = MathFloor(riskAmount / valuePerLot / lotStep) * lotStep;
   lots = MathMax(minLot, MathMin(maxLot, lots));
   return NormalizeDouble(lots, 2);
}

//+------------------------------------------------------------------+
//| Résumé global des setups trouvés                                |
//+------------------------------------------------------------------+
void WriteSummary(TradeSetup &setups[], string &labels[], const int count)
{
   string summary = "\n" + StringRepeat("=", 70) + "\n";
   summary += "  RÉSUMÉ v2.0 - " + IntegerToString(count) + " SETUP(S) CONFIRMÉ(S)\n";
   summary += "  " + TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES) + "\n";
   summary += StringRepeat("=", 70) + "\n";

   if(count == 0)
   {
      summary += "  Aucun setup valide + confirmé HTF sur l'ensemble des actifs.\n";
      summary += "  Conseil: Attendre une configuration claire avec alignement multi-TF.\n";
   }
   else
   {
      double totalRisk = count * InpRiskPercent;
      summary += "  Risque total si tous les setups sont pris: " +
                 DoubleToString(totalRisk, 1) + "% du capital\n";
      summary += "  Capital à risque: " +
                 DoubleToString(g_accountInfo.Balance() * totalRisk / 100, 2) + " " +
                 g_accountInfo.Currency() + "\n\n";

      for(int i = 0; i < ArraySize(setups); i++)
      {
         TradeSetup s = setups[i];
         summary += "  [" + IntegerToString(i+1) + "] " + labels[i] + "\n";
         summary += "      " + s.direction + " | Entrée: " + DoubleToString(s.entryPrice, _Digits) + "\n";
         summary += "      SL: " + DoubleToString(s.stopLoss, _Digits) +
                    " | TP: " + DoubleToString(s.takeProfit, _Digits) + "\n";
         summary += "      Lots: " + DoubleToString(s.lotSize, 2) +
                    " | Score LTF: " + IntegerToString(s.score) + "/11";
         if(s.htfName != "")
            summary += " | Score HTF (" + s.htfName + "): " +
                       IntegerToString(s.htfScore) + "/11 (" + s.htfDirection + ")";
         summary += "\n";
         summary += "      CONSEIL: " + GetTradingAdvice(s) + "\n\n";
      }

      if(count * InpRiskPercent > 5.0)
         summary += "  ATTENTION: Risque total élevé. Sélectionner les meilleurs scores.\n";
      else
         summary += "  Risque total acceptable. Respecter la gestion du risque.\n";
   }
   summary += StringRepeat("=", 70);
   WriteLog(summary);
}

//+------------------------------------------------------------------+
//| Conseil de trading personnalisé                                  |
//+------------------------------------------------------------------+
string GetTradingAdvice(const TradeSetup &s)
{
   string advice = "";
   if(s.score >= 9)      advice = "SIGNAL TRÈS FORT (conf. HTF). ";
   else if(s.score >= 7) advice = "SIGNAL FORT - bonne configuration KP. ";
   else                  advice = "SIGNAL MODÉRÉ - configuration acceptable. ";

   if(s.direction == "BUY")
      advice += "Acheter sur retour au Kijun si possible. Surveiller tenue du support Kijun.";
   else
      advice += "Vendre sur rebond au Kijun si possible. Surveiller résistance Kijun.";

   if(ArraySize(s.warnings) > 0)
   {
      advice += " VIGILANCE: ";
      for(int w = 0; w < ArraySize(s.warnings); w++)
      {
         advice += s.warnings[w];
         if(w < ArraySize(s.warnings) - 1) advice += "; ";
      }
   }
   return advice;
}

//+------------------------------------------------------------------+
//| Exécution des trades en mode automatique                        |
//+------------------------------------------------------------------+
void ExecuteSetups(TradeSetup &setups[], string &labels[])
{
   int existing = CountOpenPositions();
   WriteLog("\n[EXECUTION] Mode auto - " + IntegerToString(ArraySize(setups)) + " setups à évaluer");
   WriteLog("[EXECUTION] Positions existantes: " + IntegerToString(existing));

   for(int i = 0; i < ArraySize(setups); i++)
   {
      if(existing >= InpMaxPositions) { WriteLog("[EXECUTION] Limite positions atteinte"); break; }
      TradeSetup s = setups[i];
      if(HasOpenPosition(s.symbol)) { WriteLog("[EXECUTION] Position déjà ouverte sur " + s.symbol); continue; }

      bool success = false;
      if(s.direction == "BUY")
         success = g_trade.Buy(s.lotSize, s.symbol, s.entryPrice, s.stopLoss, s.takeProfit,
                               "IchimokuKP|Score:" + IntegerToString(s.score) + "|HTF:" + s.htfName);
      else
         success = g_trade.Sell(s.lotSize, s.symbol, s.entryPrice, s.stopLoss, s.takeProfit,
                                "IchimokuKP|Score:" + IntegerToString(s.score) + "|HTF:" + s.htfName);

      string execLog = "[EXECUTION] " + s.direction + " " + s.symbol + " " + labels[i] + ": ";
      execLog += success ? "SUCCÈS #" + IntegerToString((int)g_trade.ResultOrder())
                         : "ÉCHEC (" + g_trade.ResultRetcodeDescription() + ")";
      WriteLog(execLog);
      if(success) existing++;
   }
}

//+------------------------------------------------------------------+
//| Utilitaires positions                                            |
//+------------------------------------------------------------------+
int CountOpenPositions()
{
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
      if(g_posInfo.SelectByIndex(i) && g_posInfo.Magic() == InpMagicNumber) count++;
   return count;
}

bool HasOpenPosition(const string symbol)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
      if(g_posInfo.SelectByIndex(i) && g_posInfo.Magic() == InpMagicNumber && g_posInfo.Symbol() == symbol)
         return true;
   return false;
}

//+------------------------------------------------------------------+
//| Construction de la liste des timeframes actifs                  |
//+------------------------------------------------------------------+
void BuildTimeframeList()
{
   ArrayResize(g_timeframes, 0);
   ArrayResize(g_tfNames, 0);

   struct TFEntry { ENUM_TIMEFRAMES tf; string name; bool active; };
   TFEntry entries[] = {
      {PERIOD_M1,  "M1",  InpTradeM1},
      {PERIOD_M5,  "M5",  InpTradeM5},
      {PERIOD_M15, "M15", InpTradeM15},
      {PERIOD_M30, "M30", InpTradeM30},
      {PERIOD_H1,  "H1",  InpTradeH1},
      {PERIOD_H4,  "H4",  InpTradeH4},
      {PERIOD_D1,  "D1",  InpTradeD1},
      {PERIOD_W1,  "W1",  InpTradeW1},
      {PERIOD_MN1, "MN",  InpTradeMN}
   };

   for(int i = 0; i < ArraySize(entries); i++)
   {
      if(entries[i].active)
      {
         int sz = ArraySize(g_timeframes);
         ArrayResize(g_timeframes, sz + 1);
         ArrayResize(g_tfNames,    sz + 1);
         g_timeframes[sz] = entries[i].tf;
         g_tfNames[sz]    = entries[i].name;
      }
   }
   WriteLog("Timeframes actifs: " + IntegerToString(ArraySize(g_timeframes)));
}

//+------------------------------------------------------------------+
//| Utilitaires                                                      |
//+------------------------------------------------------------------+
void AddToArray(string &arr[], const string value)
{
   int sz = ArraySize(arr);
   ArrayResize(arr, sz + 1);
   arr[sz] = value;
}

void WriteLog(const string message)
{
   Print(message);
   int handle = FileOpen(g_logPath, FILE_WRITE|FILE_READ|FILE_TXT|FILE_ANSI|FILE_SHARE_READ);
   if(handle == INVALID_HANDLE)
      handle = FileOpen(g_logPath, FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_SHARE_READ);
   if(handle != INVALID_HANDLE)
   {
      FileSeek(handle, 0, SEEK_END);
      FileWriteString(handle, message + "\n");
      FileClose(handle);
   }
   else Print("[LOG ERROR] Fichier: ", g_logPath, " Erreur: ", GetLastError());
}

string StringRepeat(const string s, const int count)
{
   string result = "";
   for(int i = 0; i < count; i++) result += s;
   return result;
}

//+------------------------------------------------------------------+
//| Événements clavier                                               |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   if(id == CHARTEVENT_KEYDOWN && lparam == 'A')
   {
      WriteLog("\n[MANUEL] Analyse déclenchée manuellement");
      RunFullAnalysis();
   }
}
//+------------------------------------------------------------------+
